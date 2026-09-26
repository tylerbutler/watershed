/*!
 * Copyright (c) Microsoft Corporation and contributors. All rights reserved.
 * Licensed under the MIT License.
 */

import { strict as assert } from "node:assert";
import { mkdirSync, writeFileSync } from "node:fs";
import { isAbsolute, join } from "node:path";

import type { SessionId } from "@fluidframework/id-compressor";
import { FluidClientVersion } from "../codec/index.js";
import {
	applyDelta,
	combineVisitors,
	makeDetachedFieldIndex,
	makeDetachedNodeId,
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
	CrossFieldTarget,
	mapTreeWithField,
	type CrossFieldManager,
	type FieldChangeDecodingContext,
	type FieldChangeEncodingContext,
} from "../feature-libraries/index.js";
import { ObjectForest } from "../feature-libraries/object-forest/objectForest.js";
import { SchemaFactory, TreeViewConfiguration } from "../simple-tree/index.js";
import { configuredSharedTreeInternal } from "../treeFactory.js";
import { relevantRemovedRoots } from "../feature-libraries/sequence-field/relevantRemovedRoots.js";
import { compose as composeSequence } from "../feature-libraries/sequence-field/compose.js";
import { replaceRevisions } from "../feature-libraries/sequence-field/replaceRevisions.js";
import { sequenceFieldChangeCodecFactory } from "../feature-libraries/sequence-field/sequenceFieldCodecs.js";
import { sequenceFieldEditor } from "../feature-libraries/sequence-field/sequenceFieldEditor.js";
import type { Changeset } from "../feature-libraries/sequence-field/types.js";
import { brand, idAllocatorFromMaxId } from "../util/index.js";
import { TestChange } from "./testChange.js";
import { TestNodeId } from "./testNodeId.js";
import {
	prune,
	testCompose,
	testInvert,
	testRebase,
	toDelta,
} from "./feature-libraries/sequence-field/utils.js";
import {
	mintRevisionTag,
	testIdCompressor,
	testRevisionTagCodec,
} from "./utils.js";
import { buildTestForest, TestTreeProviderLite } from "./utils.js";

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
			scenarios: scenarios.map((scenario) => ({
				id: scenario.id,
				...copy(scenario.input),
				operation: scenario.input.operation,
				initialState: scenario.input.initialState ?? { field: [] },
				operands: copy(scenario.input),
				revisions: copy(scenario.input.revisions ?? []),
				allocator: copy(scenario.input.allocator ?? { nextLocalId: 0 }),
				compressor: copy(scenario.input.compressor ?? {
					mode: "test",
					session: String(testIdCompressor.localSessionId),
				}),
				sequencing: copy(scenario.input.sequencing ?? {
					sequenceNumber: 0,
					referenceSequenceNumber: 0,
					minimumSequenceNumber: 0,
				}),
				schedule: copy(scenario.input.schedule ?? [{ step: scenario.input.operation }]),
			})),
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
					operation: scenario.input.operation,
					initialState: copy(scenario.input.initialState ?? { field: [] }),
					operands: copy(scenario.input),
					revisions: copy(scenario.input.revisions ?? []),
					allocator: copy(scenario.input.allocator ?? { nextLocalId: 0 }),
					compressor: copy(scenario.input.compressor ?? {
						mode: "test",
						session: String(testIdCompressor.localSessionId),
					}),
					sequencing: copy(scenario.input.sequencing ?? {
						sequenceNumber: 0,
						referenceSequenceNumber: 0,
						minimumSequenceNumber: 0,
					}),
					schedule: copy(scenario.input.schedule ?? [{ step: scenario.input.operation }]),
				},
				output: copy(scenario.output),
			})),
		},
	};
}

function revisions(): RevisionTag[] {
	return Array.from({ length: 24 }, () => mintRevisionTag());
}

function codecOutput(change: Changeset, revision: RevisionTag) {
	const baseContext = {
		originatorId: testIdCompressor.localSessionId as SessionId,
		isSummary: false,
		revision,
		idCompressor: testIdCompressor,
	};
	const context: FieldChangeEncodingContext & FieldChangeDecodingContext = {
		baseContext,
		encodeNode: (node) => TestNodeId.encode(node, baseContext),
		decodeNode: (node) => TestNodeId.decode(node, baseContext),
	};
	const codec = sequenceFieldChangeCodecFactory(testRevisionTagCodec).resolve(3);
	const encoded = codec.encode(change, context);
	return { encoded, decoded: codec.decode(encoded, context) };
}

function editorCase(revs: RevisionTag[]) {
	const childA = TestNodeId.create({ localId: brand(20) }, TestChange.mint([], 1));
	const childB = TestNodeId.create({ localId: brand(21) }, TestChange.mint([], 2));
	const inputs = [
		["insert", { operation: "insert", index: 1, count: 2, firstId: 0 },
			sequenceFieldEditor.insert(1, 2, { localId: brand(0), revision: revs[0] }, revs[0])],
		["remove", { operation: "remove", source: { path: [], start: 1, end: 3 }, detachId: 2 },
			sequenceFieldEditor.remove(1, 2, brand(2), revs[1])],
		["empty-insert", { operation: "insert", index: 1, count: 0, firstId: 3 },
			sequenceFieldEditor.insert(1, 0, { localId: brand(3), revision: revs[2] }, revs[2])],
		["empty-remove", { operation: "remove", source: { path: [], start: 1, end: 1 }, detachId: 4 },
			sequenceFieldEditor.remove(1, 0, brand(4), revs[3])],
		["move-before", { operation: "move", source: { path: [], start: 2, end: 4 },
			destination: { path: [], gap: 0 } },
			sequenceFieldEditor.move(2, 2, 0, brand(5),
				{ localId: brand(7), revision: revs[4] }, revs[4])],
		["move-after", { operation: "move", source: { path: [], start: 0, end: 2 },
			destination: { path: [], gap: 4 } },
			sequenceFieldEditor.move(0, 2, 4, brand(8),
				{ localId: brand(10), revision: revs[5] }, revs[5])],
		["move-interior", { operation: "move", source: { path: [], start: 0, end: 3 },
			destination: { path: [], gap: 1 } },
			sequenceFieldEditor.move(0, 3, 1, brand(11),
				{ localId: brand(14), revision: revs[6] }, revs[6])],
		["empty-move", { operation: "move", source: { path: [], start: 1, end: 1 },
			destination: { path: [], gap: 1 } },
			sequenceFieldEditor.move(1, 0, 1, brand(15),
				{ localId: brand(15), revision: revs[7] }, revs[7])],
		["paired-endpoints", { operation: "move-endpoints", source: { path: ["left"], start: 0, end: 2 },
			destination: { path: ["right"], gap: 1 } },
			{
				out: sequenceFieldEditor.moveOut(0, 2, brand(16), revs[8]),
				in: sequenceFieldEditor.moveIn(1, 2, brand(16),
					{ localId: brand(18), revision: revs[8] }, revs[8]),
			}],
		["indexed-children", { operation: "child-changes", indices: [1, 4] },
			sequenceFieldEditor.buildChildChanges([[1, childA], [4, childB]])],
	] as const;
	return oracleCase("sequence-field-editor", "field", inputs.map(([id, input, output]) => ({
		id,
		input,
		output: {
			change: output,
			delta: "out" in output
				? { out: toDelta(output.out), in: toDelta(output.in) }
				: toDelta(output),
		},
	})));
}

function composeCase(revs: RevisionTag[]) {
	const insert = Change.insert(0, 2, revs[0], { localId: brand(0), revision: revs[0] });
	const remove = Change.remove(0, 2, revs[1], brand(2));
	const move = Change.move(0, 2, 3, revs[2], brand(4));
	const child = TestNodeId.create({ localId: brand(30) }, TestChange.mint([], 3));
	const childSecond = TestNodeId.create({ localId: brand(31) }, TestChange.mint([3], 4));
	const childChange = Change.modify(2, child);
	const childChangeSecond = Change.modify(2, childSecond);
	const childCallbacks: unknown[] = [];
	const composedChildren = testCompose(
		[tagChange(childChange, revs[4]), tagChange(childChangeSecond, revs[5])],
		undefined,
		(left, right) => {
			childCallbacks.push({
				left: left === undefined ? null : copy(left),
				right: right === undefined ? null : copy(right),
			});
			return TestNodeId.composeChild(left, right);
		},
	);
	const composed = testCompose([tagChange(insert, revs[0]), tagChange(remove, revs[1])]);
	const moveChain = testCompose([
		tagChange(move, revs[2]),
		tagChange(Change.move(1, 1, 0, revs[3], brand(8)), revs[3]),
	]);
	const rollback = testInvert(tagChange(remove, revs[1]), revs[4], true);
	const undo = testInvert(tagChange(remove, revs[1]), revs[5], false);
	const revisionReplacementInput = Change.insert(
		0,
		2,
		revs[0],
		{ localId: brand(0), revision: revs[0] },
	);
	const revised = replaceRevisions(
		revisionReplacementInput,
		new DefaultRevisionReplacer(revs[6], new Set([revs[0]])),
	);
	assert.notDeepEqual(revised, revisionReplacementInput, "Revision replacement must change references.");
	const splitInput = sequenceFieldEditor.move(0, 3, 1, brand(20),
		{ revision: revs[10], localId: brand(23) }, revs[10]);
	const splitInverse = testInvert(tagChange(splitInput, revs[10]), revs[11], false);
	const splitComposed = testCompose([
		tagChange(splitInput, revs[10]),
		tagChange(splitInverse, revs[11]),
	]);
	const pruned = prune([
		Mark.skip(1),
		Mark.modify(child),
		Mark.tomb(revs[7], brand(12)),
	], () => undefined);
	const removed = [...relevantRemovedRoots(
		[Mark.insert(1, { revision: revs[8], localId: changeId(13) })],
		() => [],
	)];
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
	const values: Record<string, unknown> = {
		"mark-families": { changes: families, codec: codecOutput(families, revs[9]) },
		"split-ranges": {
			operands: [splitInput, splitInverse],
			composed: splitComposed,
			inverted: splitInverse,
		},
		cancellation: composed,
		"move-chains": moveChain,
		"child-changes": {
			operands: [childChange, childChangeSecond],
			callbacks: childCallbacks,
			composed: composedChildren,
		},
		rollback,
		undo,
		"revision-replacement": {
			input: revisionReplacementInput,
			obsolete: [revs[0]],
			replacement: revs[6],
			result: revised,
		},
		pruning: pruned,
		"removed-roots": removed,
	};
	return oracleCase("sequence-compose-invert", "field",
		scenarioIds["sequence-compose-invert"].map((id) => ({
			id,
			input: { operation: id, revisions: revs.slice(0, 11) },
			output: values[id],
		})));
}

function rebaseCase(revs: RevisionTag[]) {
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
			const result = outcome(() => testRebase(
				tagChange(change, changeRevision),
				tagChange(base, baseRevision),
			));
			return {
				id,
				input: {
					operation: "rebase",
					change,
					changeRevision,
					base,
					baseRevision,
				},
				output: result,
			};
		}));
}

export function captureCrossFieldCoordination(revision: RevisionTag) {
		const reads: unknown[] = [];
		const writes: unknown[] = [];
		const moveIns: unknown[] = [];
		const movedKeys: unknown[] = [];
		const dependencies = new Set<string>();
		const stored = new Map<string, { value: unknown; length: number }>();
		let invalidated = false;
		const key = (
			target: CrossFieldTarget,
			itemRevision: RevisionTag | undefined,
			id: ChangesetLocalId,
		) => `${target}:${String(itemRevision)}:${id}`;
		const manager: CrossFieldManager = {
			get(target, itemRevision, id, count, addDependency) {
				const selected = key(target, itemRevision, id);
				if (addDependency) dependencies.add(selected);
				const result = stored.get(selected) ?? { value: undefined, length: count };
				reads.push({
					target,
					revision: itemRevision ?? null,
					id,
					count,
					addDependency,
					found: result.value !== undefined,
				});
				return result;
			},
			set(target, itemRevision, id, count, value, invalidateDependents) {
				const selected = key(target, itemRevision, id);
				stored.set(selected, { value, length: count });
				const didInvalidate = invalidateDependents && dependencies.has(selected);
				invalidated ||= didInvalidate;
				writes.push({
					target,
					revision: itemRevision ?? null,
					id,
					count,
					invalidateDependents,
					didInvalidate,
				});
			},
			onMoveIn(id) {
				moveIns.push(copy(id));
			},
			moveKey(target, itemRevision, id, count) {
				movedKeys.push({ target, revision: itemRevision ?? null, id, count });
			},
		};
		const moveId = brand<ChangesetLocalId>(40);
		const destinationCellId = { revision, localId: brand<ChangesetLocalId>(42) };
		const source = sequenceFieldEditor.moveOut(0, 2, moveId, revision);
		const destination = sequenceFieldEditor.moveIn(0, 2, moveId, destinationCellId, revision);
		const competing = sequenceFieldEditor.move(
			1,
			2,
			0,
			brand<ChangesetLocalId>(44),
			{ revision, localId: brand<ChangesetLocalId>(46) },
			revision,
		);
		const metadata = revisionMetadataSourceFromInfo([{ revision }]);
		const run = (base: Changeset, change: Changeset) => composeSequence(
			base,
			change,
			TestNodeId.composeChild,
			idAllocatorFromMaxId(),
			manager,
			metadata,
		);
		const firstDestination = run(destination, competing);
		const sourceResult = run(source, competing);
		const reprocessedDestination = invalidated ? run(destination, competing) : null;
		return {
			input: {
				source,
				destination,
				competing,
				revision,
				order: ["destination", "source", "destination-if-invalidated"],
			},
			reads,
			writes,
			dependencies: [...dependencies],
			invalidated,
			reprocessed: reprocessedDestination !== null,
			moveIns,
			movedKeys,
			results: { firstDestination, source: sourceResult, reprocessedDestination },
		};
}

function forestCase(revs: RevisionTag[]) {
	const changes: Record<string, Changeset> = {
		"counted-build": Change.insert(0, 3, revs[0], { localId: brand(0), revision: revs[0] }),
		"counted-detach": Change.remove(1, 3, revs[1], brand(3)),
		"counted-attach": Change.revive(0, 3, { revision: revs[1], localId: brand(3) }, revs[2]),
		"counted-rename": [
			Mark.rename(3, { revision: revs[1], localId: changeId(3) },
				{ revision: revs[2], localId: changeId(6) }),
		],
		"counted-destroy": Change.remove(0, 3, revs[3], brand(9)),
		repair: Change.revive(0, 2, { revision: revs[3], localId: brand(9) }, revs[4]),
		"indexed-children": sequenceFieldEditor.buildChildChanges([
			[2, TestNodeId.create({ localId: brand(50) }, TestChange.mint([], 5))],
		]),
		"retained-identity": Change.move(0, 2, 3, revs[5], brand(12)),
		"invalid-overlap": Change.move(0, 3, 1, revs[6], brand(16)),
		"invalid-cycle": [
			Mark.moveOut(2, { revision: revs[7], localId: changeId(20) }, {
				finalEndpoint: { revision: revs[7], localId: changeId(22) },
			}),
			Mark.moveIn(2, { revision: revs[7], localId: changeId(20) }, {
				finalEndpoint: { revision: revs[7], localId: changeId(20) },
			}),
		],
	};
	const stringType = brand<TreeNodeSchemaIdentifier>("com.fluidframework.leaf.string");
	const node = (value: string): ExclusiveMapTree => ({
		type: stringType,
		value,
		fields: new Map(),
	});
	const objectType = brand<TreeNodeSchemaIdentifier>("org.watershed.shared-tree.m3.ForestNode");
	const objectNode = (label: string, children: ExclusiveMapTree[] = []): ExclusiveMapTree => ({
		type: objectType,
		fields: new Map([
			[brand<FieldKey>("label"), [node(label)]],
			...(children.length === 0
				? []
				: [[brand<FieldKey>("child"), children] as [FieldKey, ExclusiveMapTree[]]]),
		]),
	});
	const chunk = (values: string[]) => combineChunks(chunkField(
		cursorForMapTreeField(values.map(node)),
		{ policy: defaultChunkPolicy, idCompressor: testIdCompressor },
	));
	const detachedId = (revision: RevisionTag, localId: number): DeltaDetachedNodeId =>
		makeDetachedNodeId(revision, brand<ChangesetLocalId>(localId));
	const treeValue = (tree: MapTree): unknown => {
		if (tree.type === stringType) {
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
	};
	const values = (forest: ObjectForest, key: FieldKey): unknown[] =>
		(forest.roots.fields.get(key) ?? []).map(treeValue);
	const runDelta = (
		initial: (string | ExclusiveMapTree)[],
		deltas: DeltaRoot[],
		retainIndex?: number,
	) => {
		const roots = mapTreeWithField(initial.map((value) =>
			typeof value === "string" ? node(value) : value));
		const forest = buildTestForest({ additionalAsserts: true, roots });
		assert(forest instanceof ObjectForest, "The array probe requires ObjectForest.");
		const index = makeDetachedFieldIndex("watershed-array-forest");
		const anchor = retainIndex === undefined ? undefined : (() => {
			const cursor = forest.allocateCursor("watershed array identity");
			try {
				forest.moveCursorToPath({
					parent: undefined,
					parentField: rootFieldKey,
					parentIndex: retainIndex,
				}, cursor);
				return cursor.buildAnchor();
			} finally {
				cursor.free();
			}
		})();
		const checkpoints: unknown[] = [];
		const pathData = (path: ReturnType<typeof forest.anchors.locate>): unknown =>
			path === undefined
				? null
				: {
						field: String(path.parentField),
						index: path.parentIndex,
						parent: pathData(path.parent),
					};
		for (const delta of deltas) {
			const before = {
				root: values(forest, rootFieldKey),
				detached: [...index.entries()].map((entry) => ({
					id: { major: entry.id.major ?? null, minor: entry.id.minor },
					values: values(forest, brand(index.toFieldKey(entry.root))),
				})),
			};
			let result: { accepted: true } | { accepted: false; error: string };
			try {
				applyDelta(
					delta,
					undefined,
					{ acquireVisitor: () => combineVisitors([
						forest.acquireVisitor(),
						forest.anchors.acquireVisitor(),
					]) },
					index,
				);
				result = { accepted: true };
			} catch (error) {
				result = {
					accepted: false,
					error: error instanceof Error ? `${error.name}: ${error.message}` : String(error),
				};
			}
			const after = result.accepted
				? {
						root: values(forest, rootFieldKey),
						detached: [...index.entries()].map((entry) => ({
							id: { major: entry.id.major ?? null, minor: entry.id.minor },
							values: values(forest, brand(index.toFieldKey(entry.root))),
						})),
						identity: anchor === undefined ? null : pathData(forest.anchors.locate(anchor)),
					}
				: { invalidated: true };
			checkpoints.push({ before, delta: copy(delta), result, after });
			if (!result.accepted) break;
		}
		return checkpoints;
	};
	const buildId = detachedId(revs[0], 0);
	const detachId = detachedId(revs[1], 3);
	const renamedId = detachedId(revs[2], 6);
	const cycleSchema = new SchemaFactory("org.watershed.shared-tree.m3.cycle");
	class CycleItems extends cycleSchema.arrayRecursive("Items", [
		cycleSchema.string,
		() => CycleItems,
	]) {}
	const cycleProvider = new TestTreeProviderLite(1, configuredSharedTreeInternal({
		minVersionForCollab: FluidClientVersion.v2_117,
	}).getFactory());
	const cycleView = cycleProvider.trees[0].viewWith(
		new TreeViewConfiguration({ schema: CycleItems }),
	);
	cycleView.initialize(new CycleItems([new CycleItems(["child"]), "sibling"]));
	const nestedCycleTarget = cycleView.root[0];
	assert(nestedCycleTarget instanceof CycleItems, "The cycle target must be a nested array.");
	const cycleBefore = visibleArray(cycleView.root);
	const cycleResult = outcome(() => {
		nestedCycleTarget.moveRangeToEnd(0, 1, cycleView.root);
		return visibleArray(cycleView.root);
	});
	const cycleAfter = visibleArray(cycleView.root);
	function visibleArray(value: CycleItems): unknown[] {
		return [...value].map((item) => item instanceof CycleItems ? visibleArray(item) : item);
	}
	const forestOutputs: Record<string, unknown> = {
		"counted-build": runDelta([], [{
			build: [{ id: buildId, trees: chunk(["A", "B", "C"]) }],
			fields: new Map([[rootFieldKey, { marks: [{ count: 3, attach: buildId }] }]]),
		}]),
		"counted-detach": runDelta(["A", "B", "C", "D"], [{
			fields: new Map([[rootFieldKey, {
				marks: [{ count: 1 }, { count: 3, detach: detachId }],
			}]]),
		}], 2),
		"counted-attach": runDelta(["D"], [
			{ build: [{ id: detachId, trees: chunk(["A", "B", "C"]) }] },
			{ fields: new Map([[rootFieldKey, { marks: [{ count: 3, attach: detachId }] }]]) },
		], 0),
		"counted-rename": runDelta([], [
			{ build: [{ id: detachId, trees: chunk(["A", "B", "C"]) }] },
			{ rename: [{ oldId: detachId, newId: renamedId, count: 3 }] },
		]),
		"counted-destroy": runDelta([], [
			{ build: [{ id: detachId, trees: chunk(["A", "B", "C"]) }] },
			{ destroy: [{ id: detachId, count: 3 }] },
		]),
		repair: runDelta([], [{
			refreshers: [{ id: detachId, trees: chunk(["A", "B", "C"]) }],
			fields: new Map([[rootFieldKey, { marks: [{ count: 3, attach: detachId }] }]]),
		}]),
		"indexed-children": runDelta([
			objectNode("A"), objectNode("B"), objectNode("C", [node("old")]),
		], [{
			fields: new Map([[rootFieldKey, {
				marks: [{ count: 2 }, {
					count: 1,
					fields: new Map([[brand("child"), {
						marks: [{
							count: 1,
							attach: detachedId(revs[3], 10),
							detach: detachedId(revs[3], 9),
						}],
					}]]),
				}],
			}]]),
			build: [{ id: detachedId(revs[3], 10), trees: chunk(["new"]) }],
		}]),
		"retained-identity": runDelta(["A", "B", "C"], [{
			fields: new Map([[rootFieldKey, {
				marks: [
					{ count: 2, detach: detachedId(revs[4], 12) },
					{ count: 1 },
					{ count: 2, attach: detachedId(revs[4], 12) },
				],
			}]]),
		}], 0),
		"invalid-overlap": runDelta([], [
			{ build: [{ id: detachId, trees: chunk(["A", "B", "C"]) }] },
			{ fields: new Map([[rootFieldKey, {
				marks: [
					{ count: 3, attach: detachId },
					{ count: 2, attach: detachedId(revs[1], 4) },
				],
			}]]) },
		]),
		"invalid-cycle": {
			before: cycleBefore,
			result: cycleResult,
			after: cycleAfter,
		},
	};
	return oracleCase("array-forest-delta", "forest",
		scenarioIds["array-forest-delta"].map((id) => ({
			id,
			input: {
				operation: id,
				initialState: id === "counted-build" || id === "counted-rename"
					|| id === "counted-destroy" || id === "repair" || id === "invalid-overlap"
					? { field: [] }
					: { field: ["A", "B", "C", "D"] },
				change: changes[id],
				revisions: revs.slice(0, 6),
			},
			output: {
				change: changes[id],
				delta: outcome(() => toDelta(changes[id])),
				removedRoots: outcome(() => [...relevantRemovedRoots(changes[id], () => [])]),
				forest: forestOutputs[id],
			},
		})));
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
			const revs = revisions();
			const cases = [
				forestCase(revs),
				editorCase(revs),
				composeCase(revs),
				rebaseCase(revs),
			];
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
