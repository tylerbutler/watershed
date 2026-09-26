/*!
 * Copyright (c) Microsoft Corporation and contributors. All rights reserved.
 * Licensed under the MIT License.
 */

import { strict as assert } from "node:assert";
import { mkdirSync, writeFileSync } from "node:fs";
import { isAbsolute, join } from "node:path";

import type { IIdCompressor, SessionId, SessionSpaceCompressedId } from "@fluidframework/id-compressor";
import {
	createIdCompressor,
	deserializeIdCompressor,
	serializeIdCompressor,
	type SerializedIdCompressorWithOngoingSession,
} from "@fluidframework/id-compressor/internal";
import { FluidClientVersion } from "../codec/index.js";
import {
	applyDelta,
	combineVisitors,
	makeDetachedFieldIndex,
	makeDetachedNodeId,
	RevisionTagCodec,
	revisionMetadataSourceFromInfo,
	rootFieldKey,
	tagChange,
	type ChangeAtomId,
	type ChangesetLocalId,
	type DeltaDetachedNodeId,
	type DeltaRoot,
	type ExclusiveMapTree,
	type FieldKey,
	type MapTree,
	type RevisionTag,
	type TreeNodeSchemaIdentifier,
} from "../core/index.js";
import {
	chunkField,
	combineChunks,
	cursorForMapTreeField,
	defaultChunkPolicy,
	DefaultRevisionReplacer,
	mapTreeWithField,
	type FieldChangeDecodingContext,
	type FieldChangeEncodingContext,
} from "../feature-libraries/index.js";
import { ObjectForest } from "../feature-libraries/object-forest/objectForest.js";
import { SchemaFactory, TreeViewConfiguration } from "../simple-tree/index.js";
import { configuredSharedTreeInternal } from "../treeFactory.js";
import { relevantRemovedRoots } from "../feature-libraries/sequence-field/relevantRemovedRoots.js";
import { replaceRevisions } from "../feature-libraries/sequence-field/replaceRevisions.js";
import { sequenceFieldChangeCodecFactory } from "../feature-libraries/sequence-field/sequenceFieldCodecs.js";
import { sequenceFieldEditor } from "../feature-libraries/sequence-field/sequenceFieldEditor.js";
import type { Changeset } from "../feature-libraries/sequence-field/types.js";
import { brand } from "../util/index.js";
import { TestChange } from "./testChange.js";
import { TestNodeId } from "./testNodeId.js";
import {
	prune,
	testCompose,
	testInvert,
	testRebase,
	toDelta,
} from "./feature-libraries/sequence-field/utils.js";
import { buildTestForest, TestTreeProviderLite } from "./utils.js";
import { captureCrossFieldCoordination as captureSourceCrossFieldCoordination } from "./watershedArraySupport.js";

const formatVersion = 1;
const reference = {
	package: "@fluidframework/tree",
	version: "3.1.0",
	commit: "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960",
};
const scenarioIds = {
	"array-forest-delta": [
		"counted-build", "counted-detach", "counted-attach", "counted-rename",
		"counted-destroy", "repair", "indexed-children", "retained-identity",
		"invalid-overlap", "invalid-cycle",
	],
	"sequence-field-editor": [
		"insert", "remove", "empty-insert", "empty-remove", "move-before", "move-after",
		"move-interior", "empty-move", "paired-endpoints", "indexed-children",
	],
	"sequence-compose-invert": [
		"mark-families", "split-ranges", "cancellation", "move-chains", "child-changes",
		"rollback", "undo", "revision-replacement", "pruning", "removed-roots",
	],
	"sequence-rebase": [
		"insert-insert", "insert-remove", "remove-remove", "move-edit", "move-delete",
		"competing-moves", "partial-overlap-moves", "empty-cells", "detached-children",
		"endpoint-invalidation",
	],
} as const;

type Scenario = {
	readonly id: string;
	readonly input: Record<string, unknown>;
	readonly output: unknown;
};

type PlainAtomId = {
	readonly revision: number;
	readonly localId: number;
};

type PlainTestNode = {
	readonly revision?: number;
	readonly localId: number;
	readonly testChange: {
		readonly inputContext?: number[];
		readonly intentions: number[];
		readonly outputContext?: number[];
	};
};

type PlainTree = {
	readonly type: string;
	readonly value?: string | number | boolean | null;
	readonly fields: readonly (readonly [string, readonly PlainTree[]])[];
};

type PlainDetachedId = {
	readonly major: number | null;
	readonly minor: number;
};

type PlainDelta = {
	readonly fields?: readonly (readonly [string, {
		readonly marks: readonly {
			readonly count: number;
			readonly attach?: PlainDetachedId;
			readonly detach?: PlainDetachedId;
			readonly fields?: PlainDelta["fields"];
		}[];
	}])[];
	readonly build?: readonly { readonly id: PlainDetachedId; readonly trees: readonly PlainTree[] }[];
	readonly refreshers?: readonly {
		readonly id: PlainDetachedId;
		readonly trees: readonly PlainTree[];
	}[];
	readonly destroy?: readonly { readonly id: PlainDetachedId; readonly count: number }[];
	readonly global?: readonly {
		readonly id: PlainDetachedId;
		readonly fields: NonNullable<PlainDelta["fields"]>;
	}[];
	readonly rename?: readonly {
		readonly oldId: PlainDetachedId;
		readonly newId: PlainDetachedId;
		readonly count: number;
	}[];
};

const changeId = (value: number): ChangesetLocalId => brand(value);

const moveOutMark = (
	count: number,
	id: ChangeAtomId,
	overrides: Record<string, unknown> = {},
) => ({
	type: "MoveOut" as const,
	count,
	id: id.localId,
	revision: id.revision,
	...overrides,
});

const moveInMark = (
	count: number,
	id: ChangeAtomId,
	overrides: Record<string, unknown> = {},
) => ({
	type: "MoveIn" as const,
	count,
	id: id.localId,
	revision: id.revision,
	cellId: { revision: id.revision, localId: changeId(id.localId + count) },
	...overrides,
});

const removeMark = (count: number, id: ChangeAtomId) => ({
	type: "Remove" as const,
	count,
	id: id.localId,
	revision: id.revision,
});

const Mark = {
	skip: (count: number) => ({ count }),
	tomb: (revision: RevisionTag, localId: ChangesetLocalId) => ({
		count: 1,
		cellId: { revision, localId },
	}),
	insert: (count: number, id: ChangeAtomId) => ({
		type: "Insert" as const,
		count,
		id: id.localId,
		cellId: id,
		revision: id.revision,
	}),
	revive: (count: number, id: ChangeAtomId) => ({
		type: "Insert" as const,
		count,
		id: id.localId,
		cellId: id,
	}),
	remove: removeMark,
	moveOut: moveOutMark,
	moveIn: moveInMark,
	move: (count: number, id: ChangeAtomId) =>
		[moveOutMark(count, id), moveInMark(count, id)] as const,
	rename: (count: number, input: ChangeAtomId, output: ChangeAtomId) => ({
		type: "Rename" as const,
		count,
		cellId: input,
		idOverride: output,
	}),
	modify: (changes: ReturnType<typeof TestNodeId.create>) => ({ count: 1, changes }),
	attachAndDetach: (
		attach: ReturnType<typeof moveInMark>,
		detach: ReturnType<typeof removeMark>,
	) => ({
		type: "AttachAndDetach" as const,
		count: attach.count,
		cellId: attach.cellId,
		attach: {
			type: attach.type,
			id: attach.id,
			revision: attach.revision,
		},
		detach: {
			type: detach.type,
			id: detach.id,
			revision: detach.revision,
		},
	}),
};

const Change = {
	insert: (
		index: number,
		count: number,
		revision: RevisionTag,
		id: ChangeAtomId,
	) => sequenceFieldEditor.insert(index, count, id, revision),
	remove: (
		index: number,
		count: number,
		revision: RevisionTag,
		id: ChangesetLocalId,
	) => sequenceFieldEditor.remove(index, count, id, revision),
	revive: (
		index: number,
		count: number,
		id: ChangeAtomId,
		revision: RevisionTag,
	) => sequenceFieldEditor.revive(index, count, id, revision),
	move: (
		source: number,
		count: number,
		destination: number,
		revision: RevisionTag,
		id: ChangesetLocalId,
	) => sequenceFieldEditor.move(
		source,
		count,
		destination,
		id,
		{ revision, localId: changeId(id + count) },
		revision,
	),
	modify: (index: number, child: ReturnType<typeof TestNodeId.create>) =>
		sequenceFieldEditor.buildChildChanges([[index, child]]),
	modifyDetached: (
		index: number,
		child: ReturnType<typeof TestNodeId.create>,
		cellId: ChangeAtomId,
	) => {
		const change = sequenceFieldEditor.buildChildChanges([[index, child]]);
		change[change.length - 1].cellId = cellId;
		return change;
	},
};

function copy<T>(value: T): T {
	return JSON.parse(JSON.stringify(value));
}

function object(value: unknown, message: string): asserts value is Record<string, unknown> {
	assert(value !== null && typeof value === "object" && !Array.isArray(value), message);
}

function integer(value: unknown, message: string): asserts value is number {
	assert(Number.isSafeInteger(value), message);
}

type ReplayIdContext = {
	readonly idCompressor: IIdCompressor;
	readonly revisionTagCodec: RevisionTagCodec;
};

function replayIdContext(input: Record<string, unknown>): ReplayIdContext {
	object(input.compressor, "The replay input must contain compressor state.");
	assert(typeof input.compressor.serialized === "string",
		"The replay compressor must contain serialized state.");
	assert(typeof input.compressor.session === "string",
		"The replay compressor must contain its session.");
	const idCompressor = deserializeIdCompressor(
		input.compressor.serialized as SerializedIdCompressorWithOngoingSession,
	);
	assert.equal(idCompressor.localSessionId, input.compressor.session,
		"The replay compressor session must match its serialized state.");
	return {
		idCompressor,
		revisionTagCodec: new RevisionTagCodec(idCompressor),
	};
}

function decodeRevision(
	value: unknown,
	message: string,
	context: ReplayIdContext,
): RevisionTag {
	integer(value, message);
	context.idCompressor.decompress(value as SessionSpaceCompressedId);
	return value as RevisionTag;
}

function decodeLocalId(value: unknown, message: string): ChangesetLocalId {
	integer(value, message);
	return brand(value);
}

function decodeAtomId(value: unknown, message: string, context: ReplayIdContext): ChangeAtomId {
	object(value, message);
	return {
		revision: decodeRevision(value.revision, `${message} revision`, context),
		localId: decodeLocalId(value.localId, `${message} local ID`),
	};
}

function decodeTestNode(
	value: unknown,
	message: string,
	context: ReplayIdContext,
): ReturnType<typeof TestNodeId.create> {
	object(value, message);
	object(value.testChange, `${message} test change`);
	assert(Array.isArray(value.testChange.intentions)
		&& value.testChange.intentions.every(Number.isSafeInteger), `${message} intentions`);
	const inputContext = value.testChange.inputContext;
	const outputContext = value.testChange.outputContext;
	assert(inputContext === undefined || Array.isArray(inputContext)
		&& inputContext.every(Number.isSafeInteger), `${message} input context`);
	assert(outputContext === undefined || Array.isArray(outputContext)
		&& outputContext.every(Number.isSafeInteger), `${message} output context`);
	const testChange = inputContext === undefined || outputContext === undefined
		? TestChange.emptyChange
		: {
				inputContext: [...inputContext],
				intentions: [...value.testChange.intentions],
				outputContext: [...outputContext],
			};
	return TestNodeId.create(
		{
			...(value.revision === undefined
				? {}
				: { revision: decodeRevision(value.revision, `${message} revision`, context) }),
			localId: decodeLocalId(value.localId, `${message} local ID`),
		},
		testChange,
	);
}

function decodeChangeset(
	value: unknown,
	message: string,
	context: ReplayIdContext,
): Changeset {
	assert(Array.isArray(value), message);
	return value.map((mark, index) => {
		object(mark, `${message} mark ${index}`);
		integer(mark.count, `${message} mark ${index} count`);
		return {
			...copy(mark),
			...(mark.id === undefined
				? {}
				: { id: decodeLocalId(mark.id, `${message} mark ${index} ID`) }),
			...(mark.revision === undefined
				? {}
				: {
						revision: decodeRevision(
							mark.revision,
							`${message} mark ${index} revision`,
							context,
						),
					}),
			...(mark.cellId === undefined
				? {}
				: {
						cellId: decodeAtomId(
							mark.cellId,
							`${message} mark ${index} cell ID`,
							context,
						),
					}),
			...(mark.idOverride === undefined
				? {}
				: { idOverride: decodeAtomId(mark.idOverride,
					`${message} mark ${index} ID override`, context) }),
			...(mark.changes === undefined
				? {}
				: {
						changes: decodeTestNode(
							mark.changes,
							`${message} mark ${index} child`,
							context,
						),
					}),
		};
	}) as Changeset;
}

function plainTestNode(node: ReturnType<typeof TestNodeId.create>): PlainTestNode {
	return copy(node) as PlainTestNode;
}

function replayedScenario(
	id: string,
	input: Record<string, unknown>,
	replay: (input: Record<string, unknown>) => unknown,
): Scenario {
	const serializedInput = copy(input);
	return { id, input: serializedInput, output: replay(copy(serializedInput)) };
}

function outcome(run: () => unknown): { accepted: true; value: unknown } | {
	accepted: false;
	error: string;
} {
	try {
		return { accepted: true, value: copy(run()) };
	} catch (error) {
		return {
			accepted: false,
			error: error instanceof Error ? `${error.name}: ${error.message}` : String(error),
		};
	}
}

function oracleCase(id: keyof typeof scenarioIds, domain: string, scenarios: Scenario[]) {
	assert.deepEqual(
		scenarios.map((scenario) => scenario.id),
		scenarioIds[id],
		`${id} must contain every required scenario.`,
	);
	return {
		formatVersion,
		reference,
		id,
		domain,
		input: {
			scenarios: scenarios.map((scenario) => ({ id: scenario.id, ...copy(scenario.input) })),
		},
		expected: {
			observations: scenarios.map((scenario) => ({
				id: scenario.id,
				executed: true,
				...outcome(() => scenario.output),
				result: copy(scenario.output),
			})),
		},
		raw: {
			scenarios: scenarios.map((scenario) => ({
				id: scenario.id,
				input: {
					id: scenario.id,
					...copy(scenario.input),
				},
				output: copy(scenario.output),
			})),
		},
	};
}

function revisions(compressor: IIdCompressor): RevisionTag[] {
	return Array.from(
		{ length: 24 },
		() => compressor.generateCompressedId() as RevisionTag,
	);
}

function codecOutput(change: Changeset, revision: RevisionTag, ids: ReplayIdContext) {
	const baseContext = {
		originatorId: ids.idCompressor.localSessionId as SessionId,
		isSummary: false,
		revision,
		idCompressor: ids.idCompressor,
	};
	const context: FieldChangeEncodingContext & FieldChangeDecodingContext = {
		baseContext,
		encodeNode: (node) => TestNodeId.encode(node, baseContext),
		decodeNode: (node) => TestNodeId.decode(node, baseContext),
	};
	const codec = sequenceFieldChangeCodecFactory(ids.revisionTagCodec).resolve(3);
	const encoded = codec.encode(change, context);
	return { encoded, decoded: codec.decode(encoded, context) };
}

function serializeRuntimeValue(value: unknown): unknown {
	if (value instanceof Map) {
		return [...value].map(([key, item]) => [String(key), serializeRuntimeValue(item)]);
	}
	if (Array.isArray(value)) return value.map(serializeRuntimeValue);
	if (value !== null && typeof value === "object") {
		return Object.fromEntries(
			Object.entries(value).map(([key, item]) => [key, serializeRuntimeValue(item)]),
		);
	}
	return value;
}

function replayContext(
	operation: string,
	initialState: unknown,
	operands: Record<string, unknown>,
	revisions: readonly RevisionTag[],
	compressor: IIdCompressor,
) {
	return {
		operation,
		initialState,
		operands,
		revisions: copy(revisions),
		algorithm: {
			localIds: "supplied-by-operands",
			composeAllocator: "unused-by-pinned-source",
			rebaseAllocator: "unused-by-pinned-source",
		},
		compressor: {
			mode: "test",
			session: String(compressor.localSessionId),
			serialized: serializeIdCompressor(compressor, true),
		},
		sequencing: {
			sequenceNumber: 0,
			referenceSequenceNumber: 0,
			minimumSequenceNumber: 0,
		},
		schedule: [{ step: operation }],
	};
}

function verifyAlgorithm(input: Record<string, unknown>): void {
	object(input.operands, "The replay input must contain operands.");
	object(input.algorithm, "The replay input must state its source algorithm contract.");
	assert.equal(input.algorithm.localIds, "supplied-by-operands",
		"The replay must use the local IDs supplied by its operands.");
	assert.equal(input.algorithm.composeAllocator, "unused-by-pinned-source",
		"The pinned sequence compose function does not use its allocator.");
	assert.equal(input.algorithm.rebaseAllocator, "unused-by-pinned-source",
		"The pinned sequence rebase function does not use its allocator.");
	assert(!Object.hasOwn(input.algorithm, "algebraAllocator"),
		"The replay must not claim that an unused allocator affects source output.");
}

export function replaySequenceEditorInput(input: Record<string, unknown>): unknown {
	verifyAlgorithm(input);
	const context = replayIdContext(input);
	object(input.operands, "The sequence editor input must contain operands.");
	const operands = input.operands;
	let change: Changeset | { readonly out: Changeset; readonly in: Changeset };
	switch (input.operation) {
		case "insert":
			change = sequenceFieldEditor.insert(
				(integer(operands.index, "The insert index must be an integer."), operands.index),
				(integer(operands.count, "The insert count must be an integer."), operands.count),
				decodeAtomId(operands.firstId, "The insert first ID must be valid.", context),
				decodeRevision(operands.revision, "The insert revision must be valid.", context),
			);
			break;
		case "remove":
			change = sequenceFieldEditor.remove(
				(integer(operands.sourceIndex, "The remove index must be an integer."),
					operands.sourceIndex),
				(integer(operands.count, "The remove count must be an integer."), operands.count),
				decodeLocalId(operands.detachId, "The remove ID must be valid."),
				decodeRevision(operands.revision, "The remove revision must be valid.", context),
			);
			break;
		case "move":
			change = sequenceFieldEditor.move(
				(integer(operands.sourceIndex, "The move source must be an integer."),
					operands.sourceIndex),
				(integer(operands.count, "The move count must be an integer."), operands.count),
				(integer(operands.destinationIndex, "The move destination must be an integer."),
					operands.destinationIndex),
				decodeLocalId(operands.detachId, "The move ID must be valid."),
				decodeAtomId(operands.attachId, "The move attach ID must be valid.", context),
				decodeRevision(operands.revision, "The move revision must be valid.", context),
			);
			break;
		case "move-endpoints":
			change = {
				out: sequenceFieldEditor.moveOut(
					(integer(operands.sourceIndex, "The move-out source must be an integer."),
						operands.sourceIndex),
					(integer(operands.count, "The move-out count must be an integer."),
						operands.count),
					decodeLocalId(operands.moveId, "The move-out ID must be valid."),
					decodeRevision(operands.revision, "The move-out revision must be valid.", context),
				),
				in: sequenceFieldEditor.moveIn(
					(integer(operands.destinationIndex, "The move-in destination must be an integer."),
						operands.destinationIndex),
					(integer(operands.count, "The move-in count must be an integer."),
						operands.count),
					decodeLocalId(operands.moveId, "The move-in ID must be valid."),
					decodeAtomId(operands.attachId, "The move-in attach ID must be valid.", context),
					decodeRevision(operands.revision, "The move-in revision must be valid.", context),
				),
			};
			break;
		case "child-changes": {
			assert(Array.isArray(operands.children), "The child changes must be an array.");
			change = sequenceFieldEditor.buildChildChanges(operands.children.map((item, index) => {
				object(item, `The child change ${index} must be an object.`);
				integer(item.index, `The child change ${index} index must be an integer.`);
				return [
					item.index,
					decodeTestNode(item.node, `The child change ${index} node`, context),
				];
			}));
			break;
		}
		default:
			assert.fail("The sequence editor operation is not supported.");
	}
	return {
		change,
		delta: "out" in change
			? {
					out: serializeRuntimeValue(toDelta(change.out)),
					in: serializeRuntimeValue(toDelta(change.in)),
				}
			: serializeRuntimeValue(toDelta(change)),
	};
}

function editorCase(revs: RevisionTag[], compressor: IIdCompressor) {
	const childA = TestNodeId.create({ localId: brand(20) }, TestChange.mint([], 1));
	const childB = TestNodeId.create({ localId: brand(21) }, TestChange.mint([], 2));
	const inputs: readonly [string, Record<string, unknown>][] = [
		["insert", replayContext("insert", { field: ["A", "B"] }, {
			index: 1, count: 2, firstId: { revision: revs[0], localId: 0 }, revision: revs[0],
		}, [revs[0]], compressor)],
		["remove", {
			...replayContext("remove", { field: ["A", "B", "C", "D"] }, {
				sourceIndex: 1, count: 2, detachId: 2, revision: revs[1],
			}, [revs[1]], compressor),
			source: { path: [], start: 1, end: 3 },
		}],
		["empty-insert", replayContext("insert", { field: ["A", "B"] }, {
			index: 1, count: 0, firstId: { revision: revs[2], localId: 3 }, revision: revs[2],
		}, [revs[2]], compressor)],
		["empty-remove", {
			...replayContext("remove", { field: ["A", "B"] }, {
				sourceIndex: 1, count: 0, detachId: 4, revision: revs[3],
			}, [revs[3]], compressor),
			source: { path: [], start: 1, end: 1 },
		}],
		...([
			["move-before", 2, 2, 0, 5, 7, revs[4]],
			["move-after", 0, 2, 4, 8, 10, revs[5]],
			["move-interior", 0, 3, 1, 11, 14, revs[6]],
			["empty-move", 1, 0, 1, 15, 15, revs[7]],
		] as const).map(([id, sourceIndex, count, destinationIndex, detachId, attachId, revision]) => [
			id,
			{
				...replayContext("move", { field: ["A", "B", "C", "D", "E"] }, {
					sourceIndex,
					count,
					destinationIndex,
					detachId,
					attachId: { revision, localId: attachId },
					revision,
				}, [revision], compressor),
				source: { path: [], start: sourceIndex, end: sourceIndex + count },
				destination: { path: [], gap: destinationIndex },
			},
		] as [string, Record<string, unknown>]),
		["paired-endpoints", {
			...replayContext("move-endpoints", {
				left: ["A", "B"], right: ["C"],
			}, {
				sourceIndex: 0,
				count: 2,
				destinationIndex: 1,
				moveId: 16,
				attachId: { revision: revs[8], localId: 18 },
				revision: revs[8],
			}, [revs[8]], compressor),
			source: { path: ["left"], start: 0, end: 2 },
			destination: { path: ["right"], gap: 1 },
		}],
		["indexed-children", replayContext("child-changes", {
			field: ["A", "B", "C", "D", "E"],
		}, {
			children: [
				{ index: 1, node: plainTestNode(childA) },
				{ index: 4, node: plainTestNode(childB) },
			],
		}, [], compressor)],
	];
	return oracleCase("sequence-field-editor", "field", inputs.map(([id, input]) =>
		replayedScenario(id, input, replaySequenceEditorInput)));
}

function decodeTaggedChange(value: unknown, message: string, context: ReplayIdContext) {
	object(value, message);
	return tagChange(
		decodeChangeset(value.change, `${message} change`, context),
		decodeRevision(value.revision, `${message} revision`, context),
	);
}

export function replaySequenceAlgebraInput(input: Record<string, unknown>): unknown {
	verifyAlgorithm(input);
	const context = replayIdContext(input);
	object(input.operands, "The sequence algebra input must contain operands.");
	const operands = input.operands;
	switch (input.operation) {
		case "codec": {
			const change = decodeChangeset(operands.change, "The codec change must be valid.", context);
			return {
				changes: change,
				codec: codecOutput(
					change,
					decodeRevision(operands.revision, "The codec revision must be valid.", context),
					context,
				),
			};
		}
		case "compose": {
			assert(Array.isArray(operands.changes), "The compose changes must be an array.");
			const tagged = operands.changes.map((change, index) =>
				decodeTaggedChange(change, `The compose operand ${index}`, context));
			if (operands.childComposer === "test-node") {
				const callbacks: unknown[] = [];
				const composed = testCompose(tagged, undefined, (left, right) => {
					callbacks.push({
						left: left === undefined ? null : copy(left),
						right: right === undefined ? null : copy(right),
					});
					return TestNodeId.composeChild(left, right);
				});
				return {
					operands: tagged.map(({ change }) => change),
					callbacks,
					composed,
				};
			}
			return testCompose(tagged);
		}
		case "compose-invert": {
			const tagged = decodeTaggedChange(
				operands.change,
				"The split change must be valid.",
				context,
			);
			const inverseRevision = decodeRevision(
				operands.inverseRevision,
				"The split inverse revision must be valid.",
				context,
			);
			assert(typeof operands.isRollback === "boolean", "The split reversal flag is required.");
			const inverted = testInvert(tagged, inverseRevision, operands.isRollback);
			return {
				operands: [tagged.change, inverted],
				composed: testCompose([tagged, tagChange(inverted, inverseRevision)]),
				inverted,
			};
		}
		case "invert": {
			assert(typeof operands.isRollback === "boolean", "The reversal flag is required.");
			return testInvert(
				decodeTaggedChange(operands.change, "The inverse change must be valid.", context),
				decodeRevision(
					operands.inverseRevision,
					"The inverse revision must be valid.",
					context,
				),
				operands.isRollback,
			);
		}
		case "replace-revisions": {
			const change = decodeChangeset(
				operands.change,
				"The replacement change must be valid.",
				context,
			);
			assert(Array.isArray(operands.obsolete), "The obsolete revisions must be an array.");
			const obsolete = operands.obsolete.map((revision, index) =>
				decodeRevision(
					revision,
					`The obsolete revision ${index} must be valid.`,
					context,
				));
			const replacement = decodeRevision(
				operands.replacement,
				"The replacement revision must be valid.",
				context,
			);
			return {
				input: change,
				obsolete,
				replacement,
				result: replaceRevisions(
					change,
					new DefaultRevisionReplacer(replacement, new Set(obsolete)),
				),
			};
		}
		case "prune":
			assert(operands.childPruner === "drop", "The prune callback must be explicit.");
			return prune(
				decodeChangeset(operands.change, "The prune change must be valid.", context),
				() => undefined,
			);
		case "removed-roots":
			assert(Array.isArray(operands.childRemovedRoots),
				"The child removed roots must be an array.");
			return [...relevantRemovedRoots(
				decodeChangeset(
					operands.change,
					"The removed-root change must be valid.",
					context,
				),
				() => copy(operands.childRemovedRoots) as never[],
			)];
		default:
			assert.fail("The sequence algebra operation is not supported.");
	}
}

function composeCase(revs: RevisionTag[], compressor: IIdCompressor) {
	const insert = Change.insert(0, 2, revs[0], { localId: brand(0), revision: revs[0] });
	const remove = Change.remove(0, 2, revs[1], brand(2));
	const move = Change.move(0, 2, 3, revs[2], brand(4));
	const child = TestNodeId.create({ localId: brand(30) }, TestChange.mint([], 3));
	const childSecond = TestNodeId.create({ localId: brand(31) }, TestChange.mint([3], 4));
	const childChange = Change.modify(2, child);
	const childChangeSecond = Change.modify(2, childSecond);
	const revisionReplacementInput = Change.insert(
		0,
		2,
		revs[0],
		{ localId: brand(0), revision: revs[0] },
	);
	const splitInput = sequenceFieldEditor.move(0, 3, 1, brand(20),
		{ revision: revs[10], localId: brand(23) }, revs[10]);
	const families = [
		Mark.skip(1),
		Mark.insert(1, { revision: revs[0], localId: changeId(0) }),
		Mark.remove(1, { revision: revs[1], localId: changeId(2) }),
		...Mark.move(1, { revision: revs[2], localId: changeId(4) }),
		Mark.attachAndDetach(
			Mark.moveIn(1, { revision: revs[2], localId: changeId(4) }),
			Mark.remove(1, { revision: revs[3], localId: changeId(6) }),
		),
		Mark.rename(1, { revision: revs[4], localId: changeId(7) },
			{ revision: revs[5], localId: changeId(8) }),
	];
	const tagged = (change: Changeset, revision: RevisionTag) => ({ change, revision });
	const inputs: Record<string, Record<string, unknown>> = {
		"mark-families": replayContext("codec", { field: [] }, {
			change: families, revision: revs[9],
		}, [revs[9]], compressor),
		"split-ranges": replayContext("compose-invert", { field: ["A", "B", "C"] }, {
			change: tagged(splitInput, revs[10]),
			inverseRevision: revs[11],
			isRollback: false,
		}, [revs[10], revs[11]], compressor),
		cancellation: replayContext("compose", { field: [] }, {
			changes: [tagged(insert, revs[0]), tagged(remove, revs[1])],
			childComposer: "test-node",
		}, [revs[0], revs[1]], compressor),
		"move-chains": replayContext("compose", { field: ["A", "B", "C", "D"] }, {
			changes: [
				tagged(move, revs[2]),
				tagged(Change.move(1, 1, 0, revs[3], brand(8)), revs[3]),
			],
			childComposer: "test-node",
		}, [revs[2], revs[3]], compressor),
		"child-changes": replayContext("compose", { field: ["A", "B", "C"] }, {
			changes: [tagged(childChange, revs[4]), tagged(childChangeSecond, revs[5])],
			childComposer: "test-node",
		}, [revs[4], revs[5]], compressor),
		rollback: replayContext("invert", { field: ["A", "B"] }, {
			change: tagged(remove, revs[1]),
			inverseRevision: revs[4],
			isRollback: true,
		}, [revs[1], revs[4]], compressor),
		undo: replayContext("invert", { field: ["A", "B"] }, {
			change: tagged(remove, revs[1]),
			inverseRevision: revs[5],
			isRollback: false,
		}, [revs[1], revs[5]], compressor),
		"revision-replacement": replayContext("replace-revisions", { field: [] }, {
			change: revisionReplacementInput,
			obsolete: [revs[0]],
			replacement: revs[6],
		}, [revs[0], revs[6]], compressor),
		pruning: replayContext("prune", { field: ["A"] }, {
			change: [Mark.skip(1), Mark.modify(child), Mark.tomb(revs[7], brand(12))],
			childPruner: "drop",
		}, [revs[7]], compressor),
		"removed-roots": replayContext("removed-roots", { field: [] }, {
			change: [Mark.insert(1, { revision: revs[8], localId: changeId(13) })],
			childRemovedRoots: [],
		}, [revs[8]], compressor),
	};
	return oracleCase("sequence-compose-invert", "field",
		scenarioIds["sequence-compose-invert"].map((id) =>
			replayedScenario(id, inputs[id], replaySequenceAlgebraInput)));
}

export function replaySequenceRebaseInput(input: Record<string, unknown>): unknown {
	verifyAlgorithm(input);
	const context = replayIdContext(input);
	object(input.operands, "The sequence rebase input must contain operands.");
	const operands = input.operands;
	assert(operands.childRebaser === "test-node", "The child rebaser must be explicit.");
	const callbacks: unknown[] = [];
	const value = testRebase(
		decodeTaggedChange(operands.change, "The rebase change must be valid.", context),
		decodeTaggedChange(operands.base, "The rebase base must be valid.", context),
		{
			childRebaser: (change, base) => {
				callbacks.push({
					change: change === undefined ? null : copy(change),
					base: base === undefined ? null : copy(base),
				});
				return TestNodeId.rebaseChild(change, base);
			},
		},
	);
	return { value, callbacks };
}

function rebaseCase(revs: RevisionTag[], compressor: IIdCompressor) {
	const insertA = Change.insert(0, 1, revs[0], { localId: brand(0), revision: revs[0] });
	const insertB = Change.insert(0, 1, revs[1], { localId: brand(1), revision: revs[1] });
	const removeA = Change.remove(0, 2, revs[2], brand(2));
	const removeB = Change.remove(1, 2, revs[3], brand(4));
	const moveA = Change.move(0, 2, 4, revs[4], brand(6));
	const moveB = Change.move(1, 2, 0, revs[5], brand(10));
	const child = TestNodeId.create({ localId: brand(40) }, TestChange.mint([], 4));
	const edit = Change.modify(1, child);
	const detachedEdit = Change.modifyDetached(0, child, {
		revision: revs[2],
		localId: brand(2),
	});
	const pairs: Record<string, [Changeset, RevisionTag, Changeset, RevisionTag]> = {
		"insert-insert": [insertA, revs[0], insertB, revs[1]],
		"insert-remove": [insertA, revs[0], removeA, revs[2]],
		"remove-remove": [removeA, revs[2], removeB, revs[3]],
		"move-edit": [edit, revs[6], moveA, revs[4]],
		"move-delete": [moveA, revs[4], removeB, revs[3]],
		"competing-moves": [moveA, revs[4], moveB, revs[5]],
		"partial-overlap-moves": [
			Change.move(0, 3, 5, revs[7], brand(14)),
			revs[7],
			Change.move(2, 3, 0, revs[8], brand(20)),
			revs[8],
		],
		"empty-cells": [
			[Mark.tomb(revs[2], brand(2))],
			revs[9],
			[Mark.revive(1, { revision: revs[2], localId: changeId(2) })],
			revs[10],
		],
		"detached-children": [detachedEdit, revs[11], removeA, revs[2]],
		"endpoint-invalidation": [
			Change.move(0, 2, 4, revs[12], brand(30)),
			revs[12],
			Change.move(2, 2, 0, revs[13], brand(34)),
			revs[13],
		],
	};
	return oracleCase("sequence-rebase", "field",
		scenarioIds["sequence-rebase"].map((id) => {
			const [change, changeRevision, base, baseRevision] = pairs[id];
			return replayedScenario(id, replayContext("rebase", { field: [] }, {
				change: { change, revision: changeRevision },
				base: { change: base, revision: baseRevision },
				childRebaser: "test-node",
			}, [changeRevision, baseRevision], compressor), replaySequenceRebaseInput);
		}));
}

export function captureCrossFieldCoordination(
	revision: RevisionTag,
	compressor: IIdCompressor,
) {
	return captureSourceCrossFieldCoordination(revision, compressor);
}

const stringType = "com.fluidframework.leaf.string";
const objectType = "org.watershed.shared-tree.m3.ForestNode";

function plainString(value: string): PlainTree {
	return { type: stringType, value, fields: [] };
}

function plainObject(label: string, children: readonly PlainTree[] = []): PlainTree {
	return {
		type: objectType,
		fields: [
			["label", [plainString(label)]],
			...(children.length === 0 ? [] : [["child", children] as [string, readonly PlainTree[]]]),
		],
	};
}

function decodeTree(tree: PlainTree): ExclusiveMapTree {
	assert(typeof tree.type === "string" && Array.isArray(tree.fields),
		"The serialized tree must contain a type and field entries.");
	return {
		type: brand<TreeNodeSchemaIdentifier>(tree.type),
		...(tree.value === undefined ? {} : { value: tree.value }),
		fields: new Map(tree.fields.map(([key, children]) => [
			brand<FieldKey>(key),
			children.map(decodeTree),
		])),
	};
}

function decodeDetachedId(id: PlainDetachedId, context: ReplayIdContext): DeltaDetachedNodeId {
	integer(id.minor, "The detached minor ID must be an integer.");
	return makeDetachedNodeId(
		id.major === null
			? undefined
			: decodeRevision(id.major, "The detached revision must be valid.", context),
		decodeLocalId(id.minor, "The detached local ID must be valid."),
	);
}

function decodeDelta(delta: PlainDelta, context: ReplayIdContext): DeltaRoot {
	const fields = delta.fields === undefined
		? undefined
		: new Map(delta.fields.map(([key, field]) => [
				brand<FieldKey>(key),
				{
					marks: field.marks.map((mark) => ({
						count: mark.count,
						...(mark.attach === undefined
							? {}
							: { attach: decodeDetachedId(mark.attach, context) }),
						...(mark.detach === undefined
							? {}
							: { detach: decodeDetachedId(mark.detach, context) }),
						...(mark.fields === undefined ? {} : {
							fields: decodeDelta({ fields: mark.fields }, context).fields,
						}),
					})),
				},
			]));
	const trees = (value: readonly PlainTree[]) => combineChunks(chunkField(
		cursorForMapTreeField(value.map(decodeTree)),
		{ policy: defaultChunkPolicy, idCompressor: context.idCompressor },
	));
	return {
		...(fields === undefined ? {} : { fields }),
		...(delta.build === undefined ? {} : {
			build: delta.build.map((entry) => ({
				id: decodeDetachedId(entry.id, context),
				trees: trees(entry.trees),
			})),
		}),
		...(delta.refreshers === undefined ? {} : {
			refreshers: delta.refreshers.map((entry) => ({
				id: decodeDetachedId(entry.id, context),
				trees: trees(entry.trees),
			})),
		}),
		...(delta.destroy === undefined ? {} : {
			destroy: delta.destroy.map((entry) => ({
				id: decodeDetachedId(entry.id, context),
				count: entry.count,
			})),
		}),
		...(delta.global === undefined ? {} : {
			global: delta.global.map((entry) => ({
				id: decodeDetachedId(entry.id, context),
				fields: decodeDelta({ fields: entry.fields }, context).fields ?? new Map(),
			})),
		}),
		...(delta.rename === undefined ? {} : {
			rename: delta.rename.map((entry) => ({
				oldId: decodeDetachedId(entry.oldId, context),
				newId: decodeDetachedId(entry.newId, context),
				count: entry.count,
			})),
		}),
	};
}

function treeValue(tree: MapTree): unknown {
	if (tree.type === brand<TreeNodeSchemaIdentifier>(stringType)) {
		assert(typeof tree.value === "string", "The array forest probe expects string values.");
		return tree.value;
	}
	return {
		type: String(tree.type),
		fields: [...tree.fields].map(([key, children]) => [
			String(key),
			children.map(treeValue),
		]),
	};
}

export function replayForestInput(input: Record<string, unknown>): unknown {
	const context = replayIdContext(input);
	object(input.operands, "The forest input must contain operands.");
	const operands = input.operands;
	if (input.operation === "public-move-cycle") {
		assert(Array.isArray(input.initialState), "The cycle initial state must be an array.");
		object(operands.move, "The cycle move arguments must be present.");
		const move = operands.move;
		assert(Array.isArray(move.sourcePath) && move.sourcePath.every(Number.isSafeInteger),
			"The cycle source path must contain integer indexes.");
		assert(Array.isArray(move.destinationPath) && move.destinationPath.every(Number.isSafeInteger),
			"The cycle destination path must contain integer indexes.");
		integer(move.sourceStart, "The cycle source start must be an integer.");
		integer(move.sourceEnd, "The cycle source end must be an integer.");
		integer(move.destinationGap, "The cycle destination gap must be an integer.");
		const sourcePath = move.sourcePath as number[];
		const destinationPath = move.destinationPath as number[];
		const sourceStart = move.sourceStart as number;
		const sourceEnd = move.sourceEnd as number;
		const destinationGap = move.destinationGap as number;
		const cycleSchema = new SchemaFactory("org.watershed.shared-tree.m3.cycle");
		class CycleItems extends cycleSchema.arrayRecursive("Items", [
			cycleSchema.string,
			() => CycleItems,
		]) {}
		const fromPlain = (value: unknown): string | CycleItems => {
			if (typeof value === "string") return value;
			assert(Array.isArray(value), "The cycle content must contain strings or arrays.");
			return new CycleItems(value.map(fromPlain));
		};
		const provider = new TestTreeProviderLite(1, configuredSharedTreeInternal({
			minVersionForCollab: FluidClientVersion.v2_117,
		}).getFactory());
		const view = provider.trees[0].viewWith(new TreeViewConfiguration({ schema: CycleItems }));
		view.initialize(new CycleItems(input.initialState.map(fromPlain)));
		const locate = (path: readonly number[]): CycleItems => {
			let current = view.root;
			for (const index of path) {
				const next = current[index];
				assert(next instanceof CycleItems, "The cycle path must identify an array.");
				current = next;
			}
			return current;
		};
		const visible = (value: CycleItems): unknown[] =>
			[...value].map((item) => item instanceof CycleItems ? visible(item) : item);
		const before = visible(view.root);
		const result = outcome(() => {
			locate(destinationPath).moveRangeToIndex(
				destinationGap,
				sourceStart,
				sourceEnd,
				locate(sourcePath),
			);
			return visible(view.root);
		});
		return { before, result, after: visible(view.root) };
	}
	assert(input.operation === "apply-deltas", "The forest operation is not supported.");
	object(input.initialState, "The forest initial state must be present.");
	assert(Array.isArray(input.initialState.field), "The forest root field must be an array.");
	assert(Array.isArray(operands.deltas), "The forest delta sequence must be an array.");
	const initial = input.initialState.field.map((tree, index) => {
		object(tree, `The initial tree ${index} must be an object.`);
		return decodeTree(tree as PlainTree);
	});
	const roots = mapTreeWithField(initial);
	const forest = buildTestForest({ additionalAsserts: true, roots });
	assert(forest instanceof ObjectForest, "The array probe requires ObjectForest.");
	const index = makeDetachedFieldIndex("watershed-array-forest");
	const retainIndex = operands.retainIndex;
	assert(retainIndex === null || Number.isSafeInteger(retainIndex),
		"The retained index must be null or an integer.");
	const retained = retainIndex as number | null;
	const anchor = retained === null ? undefined : (() => {
		const cursor = forest.allocateCursor("watershed array identity");
		try {
			forest.moveCursorToPath({
				parent: undefined,
				parentField: rootFieldKey,
				parentIndex: retained,
			}, cursor);
			return cursor.buildAnchor();
		} finally {
			cursor.free();
		}
	})();
	const values = (key: FieldKey): unknown[] =>
		(forest.roots.fields.get(key) ?? []).map(treeValue);
	const detached = () => [...index.entries()].map((entry) => ({
		id: { major: entry.id.major ?? null, minor: entry.id.minor },
		values: values(brand(index.toFieldKey(entry.root))),
	}));
	const pathData = (path: ReturnType<typeof forest.anchors.locate>): unknown =>
		path === undefined
			? null
			: {
					field: String(path.parentField),
					index: path.parentIndex,
					parent: pathData(path.parent),
				};
	const checkpoints: unknown[] = [];
	for (const [deltaIndex, encoded] of operands.deltas.entries()) {
		object(encoded, `The forest delta ${deltaIndex} must be an object.`);
		const plain = encoded as PlainDelta;
		const before = { root: values(rootFieldKey), detached: detached() };
		const result = outcome(() => {
			applyDelta(
				decodeDelta(plain, context),
				undefined,
				{ acquireVisitor: () => combineVisitors([
					forest.acquireVisitor(),
					forest.anchors.acquireVisitor(),
				]) },
				index,
			);
			return {};
		});
		const after = result.accepted
			? {
					root: values(rootFieldKey),
					detached: detached(),
					identity: anchor === undefined ? null : pathData(forest.anchors.locate(anchor)),
				}
			: { invalidated: true };
		checkpoints.push({ before, delta: copy(plain), result, after });
		if (!result.accepted) break;
	}
	return checkpoints;
}

function forestCase(revs: RevisionTag[], compressor: IIdCompressor) {
	const id = (revision: RevisionTag, minor: number): PlainDetachedId => ({
		major: revision as number,
		minor,
	});
	const root = (marks: NonNullable<PlainDelta["fields"]>[number][1]["marks"]) =>
		[["rootFieldKey", { marks }]] as const;
	const build = id(revs[0], 0);
	const detached = id(revs[1], 3);
	const renamed = id(revs[2], 6);
	const applied = (
		initial: readonly PlainTree[],
		deltas: readonly PlainDelta[],
		retainIndex: number | null = null,
	) => replayContext("apply-deltas", { field: initial }, {
		deltas,
		retainIndex,
	}, revs.slice(0, 6), compressor);
	const inputs: Record<string, Record<string, unknown>> = {
		"counted-build": applied([], [{
			build: [{ id: build, trees: [plainString("A"), plainString("B"), plainString("C")] }],
			fields: root([{ count: 3, attach: build }]),
		}]),
		"counted-detach": applied(
			["A", "B", "C", "D"].map(plainString),
			[{ fields: root([{ count: 1 }, { count: 3, detach: detached }]) }],
			2,
		),
		"counted-attach": applied([plainString("D")], [
			{ build: [{ id: detached, trees: ["A", "B", "C"].map(plainString) }] },
			{ fields: root([{ count: 3, attach: detached }]) },
		], 0),
		"counted-rename": applied([], [
			{ build: [{ id: detached, trees: ["A", "B", "C"].map(plainString) }] },
			{ rename: [{ oldId: detached, newId: renamed, count: 3 }] },
		]),
		"counted-destroy": applied([], [
			{ build: [{ id: detached, trees: ["A", "B", "C"].map(plainString) }] },
			{ destroy: [{ id: detached, count: 3 }] },
		]),
		repair: applied([], [{
			refreshers: [{ id: detached, trees: ["A", "B", "C"].map(plainString) }],
			fields: root([{ count: 3, attach: detached }]),
		}]),
		"indexed-children": applied([
			plainObject("A"),
			plainObject("B"),
			plainObject("C", [plainString("old")]),
		], [{
			build: [{ id: id(revs[3], 10), trees: [plainString("new")] }],
			fields: root([{ count: 2 }, {
				count: 1,
				fields: [["child", { marks: [{
					count: 1,
					attach: id(revs[3], 10),
					detach: id(revs[3], 9),
				}] }]],
			}]),
		}]),
		"retained-identity": applied(["A", "B", "C"].map(plainString), [{
			fields: root([
				{ count: 2, detach: id(revs[4], 12) },
				{ count: 1 },
				{ count: 2, attach: id(revs[4], 12) },
			]),
		}], 0),
		"invalid-overlap": applied([], [
			{ build: [{ id: detached, trees: ["A", "B", "C"].map(plainString) }] },
			{ fields: root([
				{ count: 3, attach: detached },
				{ count: 2, attach: id(revs[1], 4) },
			]) },
		]),
		"invalid-cycle": replayContext("public-move-cycle", [
			["child"],
			"sibling",
		], {
			move: {
				sourcePath: [],
				sourceStart: 0,
				sourceEnd: 1,
				destinationPath: [0],
				destinationGap: 1,
			},
		}, [], compressor),
	};
	return oracleCase("array-forest-delta", "forest",
		scenarioIds["array-forest-delta"].map((scenarioId) =>
			replayedScenario(scenarioId, inputs[scenarioId], replayForestInput)));
}

if (process.env.WATERSHED_ORACLE_CORPUS === "1") {
	describe("Watershed sequence oracle", () => {
		it("records editor, forest, composition, inversion, and rebase evidence", () => {
			const output = process.env.WATERSHED_ORACLE_OUTPUT;
			assert(output !== undefined && isAbsolute(output), "WATERSHED_ORACLE_OUTPUT must be absolute.");
			assert.equal(
				process.env.WATERSHED_ORACLE_COMMIT,
				reference.commit,
				"WATERSHED_ORACLE_COMMIT must match the pinned Fluid commit.",
			);
			const compressor = createIdCompressor(
				"ba6ca8d4-71ea-4abb-a919-5c0e2c252e75" as SessionId,
			);
			const revs = revisions(compressor);
			const cases = [
				forestCase(revs, compressor),
				editorCase(revs, compressor),
				composeCase(revs, compressor),
				rebaseCase(revs, compressor),
			];
			const indexedDelta = cases[1].raw.scenarios.find(
				(scenario) => scenario.id === "indexed-children",
			)?.output;
			assert(
				JSON.stringify(indexedDelta).includes("testIntentions"),
				"The indexed child delta must retain its nested TestChange fields.",
			);
			const editorInput = copy(cases[1].input.scenarios.find(
				(scenario) => scenario.id === "move-before",
			)) as Record<string, unknown> | undefined;
			assert(editorInput !== undefined, "The move-before replay input must exist.");
			object(editorInput.operands, "The move-before replay operands must exist.");
			const editorBaseline = replaySequenceEditorInput(editorInput);
			editorInput.operands.destinationIndex = 1;
			assert.notDeepEqual(
				replaySequenceEditorInput(editorInput),
				editorBaseline,
				"Changing the serialized move gap must change the replay output.",
			);
			assert.deepEqual(
				cases.map(({ id }) => id),
				[
					"array-forest-delta",
					"sequence-field-editor",
					"sequence-compose-invert",
					"sequence-rebase",
				],
				"The sequence probe must emit all four owned cases.",
			);
			mkdirSync(output, { recursive: true });
			writeFileSync(join(output, "sequence-cases.json"), `${JSON.stringify(cases, null, 2)}\n`);
		});
	});
}
