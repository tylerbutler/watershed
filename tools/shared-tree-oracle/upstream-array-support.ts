/*!
 * Copyright (c) Microsoft Corporation and contributors. All rights reserved.
 * Licensed under the MIT License.
 */

import { strict as assert } from "node:assert";

import type {
	IIdCompressor,
	SessionSpaceCompressedId,
} from "@fluidframework/id-compressor";
import {
	deserializeIdCompressor,
	serializeIdCompressor,
	type SerializedIdCompressorWithOngoingSession,
} from "@fluidframework/id-compressor/internal";
import { FluidClientVersion, type CodecWriteOptions } from "../codec/index.js";
import {
	revisionMetadataSourceFromInfo,
	RevisionTagCodec,
	tagChange,
	type ChangeAtomId,
	type ChangesetLocalId,
	type DeltaFieldMap,
	type DeltaRoot,
	type FieldKey,
	type JsonableTree,
	type RevisionTag,
} from "../core/index.js";
import { FormatValidatorBasic } from "../external-utilities/index.js";
import {
	CrossFieldTarget,
	chunkField,
	combineChunks,
	cursorForJsonableTreeField,
	defaultChunkPolicy,
	fieldBatchCodecBuilder,
	fieldKindConfigurations,
	fieldKinds,
	FlexFieldKind,
	genericFieldKind,
	intoDelta,
	jsonableTreeFromFieldCursor,
	makeModularChangeCodecFamily,
	ModularChangeFamily,
	newChangeAtomIdBTree,
	SequenceField,
	TreeCompressionStrategy,
	type CrossFieldManager,
	type FieldChangeHandler,
	type FieldChangeMap,
	type ModularChangeset,
} from "../feature-libraries/index.js";
import type {
	FieldId,
	NodeChangeset,
} from "../feature-libraries/modular-schema/modularChangeTypes.js";
import {
	makeChangesetInversions,
	makeModularChangeset,
} from "../feature-libraries/modular-schema/modularChangeUtils.js";
import { newCrossFieldKeyTable } from "../feature-libraries/modular-schema/modularChangeTypes.js";
import type { GenericChangeset } from "../feature-libraries/modular-schema/genericFieldKindTypes.js";
import { sequenceFieldEditor } from "../feature-libraries/sequence-field/sequenceFieldEditor.js";
import type { Changeset } from "../feature-libraries/sequence-field/types.js";
import { brand } from "../util/index.js";

type PlainAtom = {
	readonly revision: number | null;
	readonly localId: number;
};

type PlainFieldId = {
	readonly node: PlainAtom | null;
	readonly field: string;
};

type PlainFieldChange = {
	readonly kind: "Generic" | "Sequence" | "Value" | "Optional";
	readonly change: unknown;
};

type PlainNodeChange = {
	readonly fields: readonly (readonly [string, PlainFieldChange])[];
};

type PlainModularChange = {
	readonly maxLocalId: number;
	readonly revisions: readonly {
		readonly revision: number;
		readonly rollbackOf: number | null;
	}[];
	readonly fields: readonly (readonly [string, PlainFieldChange])[];
	readonly nodes: readonly (readonly [PlainAtom, PlainNodeChange])[];
	readonly parents: readonly (readonly [PlainAtom, PlainFieldId])[];
	readonly aliases: readonly (readonly [PlainAtom, PlainAtom])[];
	readonly crossFieldKeys: readonly {
		readonly target: "source" | "destination";
		readonly revision: number | null;
		readonly localId: number;
		readonly count: number;
		readonly field: PlainFieldId;
	}[];
	readonly builds?: readonly (readonly [PlainAtom, readonly JsonableTree[]])[];
	readonly refreshers?: readonly (readonly [PlainAtom, readonly JsonableTree[]])[];
	readonly destroys?: readonly (readonly [PlainAtom, number])[];
};

type TaggedPlainModularChange = {
	readonly revision: number;
	readonly change: PlainModularChange;
};

type ReplayInput = {
	readonly operation: "compose" | "invert" | "rebase";
	readonly initialState: unknown;
	readonly operands: {
		readonly changes: readonly TaggedPlainModularChange[];
		readonly inverseRevision?: number;
		readonly isRollback?: boolean;
		readonly revisionMetadata?: readonly {
			readonly revision: number;
			readonly rollbackOf: number | null;
		}[];
	};
	readonly revisions: readonly {
		readonly encoded: number;
		readonly stable: string;
	}[];
	readonly allocator: { readonly maxLocalId: number };
	readonly compressor: { readonly sessionId: string; readonly serialized: string };
	readonly sequencing: {
		readonly minimumSequenceNumber: number;
		readonly sequenceNumber: number;
	};
	readonly schedule: readonly string[];
};

type FieldIdentity = {
	readonly node: PlainAtom | null;
	readonly field: string;
};

type Instrumentation = {
	readonly conversionCalls: {
		direction: "generic-left" | "generic-right";
		field: FieldIdentity;
		children: readonly (readonly [number, PlainAtom])[];
	}[];
	readonly handlerCalls: {
		sequence: number;
		operation: "compose" | "invert" | "rebase";
		field: FieldIdentity;
		invocation: number;
	}[];
	readonly managerCalls: Record<string, unknown>[];
	readonly identities: WeakMap<object, FieldIdentity>;
	readonly genericDirections: Map<
		string,
		{
			readonly direction: "generic-left" | "generic-right";
			readonly field: FieldIdentity;
		}
	>;
	nextSequence: number;
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
	object(input.compressor, "The modular replay must contain compressor state.");
	assert(typeof input.compressor.sessionId === "string",
		"The modular compressor session must be a string.");
	assert(typeof input.compressor.serialized === "string",
		"The modular compressor state must be serialized.");
	const idCompressor = deserializeIdCompressor(
		input.compressor.serialized as SerializedIdCompressorWithOngoingSession,
	);
	assert.equal(
		idCompressor.localSessionId,
		input.compressor.sessionId,
		"The modular compressor session must match its serialized state.",
	);
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
	const encoded = value as SessionSpaceCompressedId;
	context.idCompressor.decompress(encoded);
	return encoded as RevisionTag;
}

function decodeOptionalRevision(
	value: unknown,
	message: string,
	context: ReplayIdContext,
): RevisionTag | undefined {
	return value === null ? undefined : decodeRevision(value, message, context);
}

function decodeLocalId(value: unknown, message: string): ChangesetLocalId {
	integer(value, message);
	assert(value >= 0, message);
	return brand(value);
}

function decodeAtom(value: unknown, message: string, context: ReplayIdContext): ChangeAtomId {
	object(value, message);
	return {
		revision: decodeOptionalRevision(value.revision, message, context),
		localId: decodeLocalId(value.localId, message),
	};
}

function plainAtom(value: ChangeAtomId): PlainAtom {
	return {
		revision: value.revision === undefined ? null : Number(value.revision),
		localId: Number(value.localId),
	};
}

function atomSignature(value: PlainAtom): string {
	return `${value.revision ?? "local"}:${value.localId}`;
}

function genericSignature(entries: readonly (readonly [number, PlainAtom])[]): string {
	return entries.map(([index, id]) => `${index}@${atomSignature(id)}`).join(",");
}

function decodeFieldId(
	value: unknown,
	message: string,
	context: ReplayIdContext,
): {
	nodeId: ChangeAtomId | undefined;
	field: FieldKey;
} {
	object(value, message);
	assert(typeof value.field === "string", message);
	return {
		nodeId: value.node === null ? undefined : decodeAtom(value.node, message, context),
		field: brand(value.field),
	};
}

function plainFieldId(value: { nodeId?: ChangeAtomId; field: FieldKey }): FieldIdentity {
	return {
		node: value.nodeId === undefined ? null : plainAtom(value.nodeId),
		field: String(value.field),
	};
}

function decodeSequence(value: unknown, message: string): Changeset {
	assert(Array.isArray(value), message);
	for (const mark of value) {
		object(mark, message);
		integer(mark.count, message);
	}
	return copy(value) as Changeset;
}

function decodeFieldChanges(
	value: unknown,
	instrumentation: Instrumentation,
	owner: FieldIdentity["node"],
	operand: number,
	otherFields: readonly (readonly [string, PlainFieldChange])[] | undefined,
	context: ReplayIdContext,
): FieldChangeMap {
	assert(Array.isArray(value), "The modular fields must be ordered entries.");
	const fields: FieldChangeMap = new Map();
	for (const entry of value) {
		assert(
			Array.isArray(entry) && entry.length === 2 && typeof entry[0] === "string",
			"The modular field entry must contain a key and change.",
		);
		object(entry[1], "The modular field change must be an object.");
		const field = brand<FieldKey>(entry[0]);
		const identity: FieldIdentity = { node: owner, field: entry[0] };
		if (entry[1].kind === "Generic") {
			object(entry[1].change, "The Generic change must be an object.");
			assert(
				Array.isArray(entry[1].change.children),
				"The Generic change must contain ordered child entries.",
			);
			const children: [number, ChangeAtomId][] = entry[1].change.children.map((child) => {
				assert(
					Array.isArray(child) && child.length === 2,
					"The Generic child entry must contain an index and node ID.",
				);
				integer(child[0], "The Generic child index must be an integer.");
				return [
					child[0],
					decodeAtom(child[1], "The Generic child ID must be valid.", context),
				];
			});
			const change = genericFieldKind.changeHandler.editor.buildChildChanges(children);
			instrumentation.identities.set(change, identity);
			const other = otherFields?.find(([key]) => key === entry[0])?.[1];
			if (other?.kind === "Sequence") {
				instrumentation.genericDirections.set(
					genericSignature(children.map(([index, id]) => [index, plainAtom(id)])),
					{
						direction: operand === 0 ? "generic-left" : "generic-right",
						field: identity,
					},
				);
			}
			fields.set(field, {
				fieldKind: genericFieldKind.identifier,
				change: brand(change),
			});
		} else if (entry[1].kind === "Value" || entry[1].kind === "Optional") {
			object(entry[1].change, "The register change must be an object.");
			assert(Array.isArray(entry[1].change.moves)
				&& Array.isArray(entry[1].change.childChanges),
				"The register change must contain moves and child changes.");
			fields.set(field, {
				fieldKind: brand(entry[1].kind),
				change: brand(copy(entry[1].change)),
			});
		} else {
			assert.equal(entry[1].kind, "Sequence", "Unsupported modular field kind.");
			const change = decodeSequence(entry[1].change, "The Sequence change must be valid.");
			instrumentation.identities.set(change, identity);
			fields.set(field, {
				fieldKind: SequenceField.sequence.identifier,
				change: brand(change),
			});
		}
	}
	return fields;
}

function decodeModularChange(
	value: PlainModularChange,
	instrumentation: Instrumentation,
	operand: number,
	other: PlainModularChange | undefined,
	context: ReplayIdContext,
): ModularChangeset {
	integer(value.maxLocalId, "The modular allocator watermark must be an integer.");
	const fieldChanges = decodeFieldChanges(
		value.fields,
		instrumentation,
		null,
		operand,
		other?.fields,
		context,
	);
	const nodeChanges = newChangeAtomIdBTree<NodeChangeset>();
	for (const [idValue, nodeValue] of value.nodes) {
		const id = decodeAtom(idValue, "The modular node ID must be valid.", context);
		nodeChanges.set([id.revision, id.localId], {
			fieldChanges: decodeFieldChanges(
				nodeValue.fields,
				instrumentation,
				plainAtom(id),
				operand,
				undefined,
				context,
			),
		});
	}
	const nodeToParent = newChangeAtomIdBTree<FieldId>();
	for (const [idValue, parentValue] of value.parents) {
		const id = decodeAtom(idValue, "The modular parent node ID must be valid.", context);
		nodeToParent.set(
			[id.revision, id.localId],
			decodeFieldId(parentValue, "The modular parent field must be valid.", context),
		);
	}
	const nodeAliases = newChangeAtomIdBTree<ChangeAtomId>();
	for (const [sourceValue, targetValue] of value.aliases) {
		const source = decodeAtom(
			sourceValue,
			"The modular alias source must be valid.",
			context,
		);
		const target = decodeAtom(
			targetValue,
			"The modular alias target must be valid.",
			context,
		);
		nodeAliases.set([source.revision, source.localId], target);
	}
	const crossFieldKeys = newCrossFieldKeyTable();
	for (const entry of value.crossFieldKeys) {
		const target =
			entry.target === "source" ? CrossFieldTarget.Source : CrossFieldTarget.Destination;
		crossFieldKeys.set(
			{
				target,
				revision: decodeOptionalRevision(
					entry.revision,
					"The cross-field revision must be valid.",
					context,
				),
				localId: decodeLocalId(entry.localId, "The cross-field local ID must be valid."),
			},
			entry.count,
			decodeFieldId(entry.field, "The cross-field owner must be valid.", context),
		);
	}
	const chunks = (
		entries: readonly (readonly [PlainAtom, readonly JsonableTree[]])[],
		message: string,
	) => {
		const table = newChangeAtomIdBTree<ReturnType<typeof combineChunks>>();
		for (const [idValue, trees] of entries) {
			const id = decodeAtom(idValue, message, context);
			table.set(
				[id.revision, id.localId],
				combineChunks(chunkField(cursorForJsonableTreeField([...trees]), {
					policy: defaultChunkPolicy,
					idCompressor: context.idCompressor,
				})),
			);
		}
		return table;
	};
	const destroys = newChangeAtomIdBTree<number>();
	for (const [idValue, count] of value.destroys ?? []) {
		const id = decodeAtom(idValue, "The modular destroy ID must be valid.", context);
		integer(count, "The modular destroy count must be an integer.");
		destroys.set([id.revision, id.localId], count);
	}
	return makeModularChangeset({
		maxId: value.maxLocalId,
		revisions: value.revisions.map((info) => ({
			revision: decodeRevision(info.revision, "The modular revision must be valid.", context),
			...(info.rollbackOf === null
				? {}
				: {
						rollbackOf: decodeRevision(
							info.rollbackOf,
							"The rollback revision must be valid.",
							context,
						),
					}),
		})),
		fieldChanges,
		nodeChanges,
		nodeToParent,
		nodeAliases,
		crossFieldKeys,
		builds: chunks(value.builds ?? [], "The modular build ID must be valid."),
		refreshers: chunks(value.refreshers ?? [], "The modular refresher ID must be valid."),
		destroys,
	});
}

function encodeSequence(value: Changeset): unknown {
	return copy(value);
}

function encodeFieldChanges(value: FieldChangeMap): (readonly [string, PlainFieldChange])[] {
	return [...value].map(([key, field]) => {
		if (field.fieldKind === genericFieldKind.identifier) {
			const change = field.change as unknown as GenericChangeset;
			return [
				String(key),
				{
					kind: "Generic",
					change: {
						children: [...change.entries()].map(([index, id]) => [index, plainAtom(id)]),
					},
				},
			] as const;
		}
		if (field.fieldKind === "Value" || field.fieldKind === "Optional") {
			return [
				String(key),
				{
					kind: field.fieldKind === "Value" ? "Value" : "Optional",
					change: copy(field.change),
				},
			] as const;
		}
		assert.equal(
			field.fieldKind,
			SequenceField.sequence.identifier,
			`Unsupported modular field kind: ${String(field.fieldKind)}`,
		);
		return [
			String(key),
			{
				kind: "Sequence",
				change: encodeSequence(field.change as unknown as Changeset),
			},
		] as const;
	});
}

export function encodeModularGraph(change: ModularChangeset): PlainModularChange {
	return {
		maxLocalId: Number(change.maxId ?? -1),
		revisions: (change.revisions ?? []).map((info) => ({
			revision: Number(info.revision),
			rollbackOf: info.rollbackOf === undefined ? null : Number(info.rollbackOf),
		})),
		fields: encodeFieldChanges(change.fieldChanges),
		nodes: [...change.nodeChanges.entries()].map(([[revision, localId], node]) => [
			plainAtom({ revision, localId }),
			{ fields: encodeFieldChanges(node.fieldChanges ?? new Map()) },
		]),
		parents: [...change.nodeToParent.entries()].map(([[revision, localId], parent]) => [
			plainAtom({ revision, localId }),
			plainFieldId(parent),
		]),
		aliases: [...change.nodeAliases.entries()].map(([[revision, localId], target]) => [
			plainAtom({ revision, localId }),
			plainAtom(target),
		]),
		crossFieldKeys: change.crossFieldKeys.entries().map((entry) => ({
			target: entry.start.target === CrossFieldTarget.Source ? "source" : "destination",
			revision: entry.start.revision === undefined ? null : Number(entry.start.revision),
			localId: Number(entry.start.localId),
			count: entry.length,
			field: plainFieldId(entry.value),
		})),
		builds: [...(change.builds?.entries() ?? [])].map(([[revision, localId], chunk]) => [
			plainAtom({ revision, localId }),
			jsonableTreeFromFieldCursor(chunk.cursor()),
		]),
		refreshers: [...(change.refreshers?.entries() ?? [])].map(([[revision, localId], chunk]) => [
			plainAtom({ revision, localId }),
			jsonableTreeFromFieldCursor(chunk.cursor()),
		]),
		destroys: [...(change.destroys?.entries() ?? [])].map(([[revision, localId], count]) => [
			plainAtom({ revision, localId }),
			count,
		]),
	};
}

function deltaFields(value: DeltaFieldMap | undefined): unknown[] {
	return [...(value ?? [])].map(([key, field]) => [
		String(key),
		{
			marks: field.marks.map((mark) => ({
				count: mark.count,
				attach:
					mark.attach === undefined
						? null
						: plainAtom({
								revision: mark.attach.major === "root" ? undefined : mark.attach.major,
								localId: brand(mark.attach.minor),
							}),
				detach:
					mark.detach === undefined
						? null
						: plainAtom({
								revision: mark.detach.major === "root" ? undefined : mark.detach.major,
								localId: brand(mark.detach.minor),
							}),
				fields: deltaFields(mark.fields),
			})),
		},
	]);
}

function delta(value: DeltaRoot): object {
	return {
		fields: deltaFields(value.fields),
		build: (value.build ?? []).map((entry) => ({
			id: plainAtom({
				revision: entry.id.major === "root" ? undefined : entry.id.major,
				localId: brand(entry.id.minor),
			}),
			count: entry.trees.topLevelLength,
		})),
		refreshers: (value.refreshers ?? []).map((entry) => ({
			id: plainAtom({
				revision: entry.id.major === "root" ? undefined : entry.id.major,
				localId: brand(entry.id.minor),
			}),
			count: entry.trees.topLevelLength,
		})),
		global: (value.global ?? []).map((entry) => ({
			id: plainAtom({
				revision: entry.id.major === "root" ? undefined : entry.id.major,
				localId: brand(entry.id.minor),
			}),
			fields: deltaFields(entry.fields),
		})),
		rename: (value.rename ?? []).map((entry) => ({
			oldId: plainAtom({
				revision: entry.oldId.major === "root" ? undefined : entry.oldId.major,
				localId: brand(entry.oldId.minor),
			}),
			newId: plainAtom({
				revision: entry.newId.major === "root" ? undefined : entry.newId.major,
				localId: brand(entry.newId.minor),
			}),
			count: entry.count,
		})),
		destroy: (value.destroy ?? []).map((entry) => ({
			id: plainAtom({
				revision: entry.id.major === "root" ? undefined : entry.id.major,
				localId: brand(entry.id.minor),
			}),
			count: entry.count,
		})),
	};
}

function managerAdapter(
	manager: CrossFieldManager,
	field: FieldIdentity,
	instrumentation: Instrumentation,
): CrossFieldManager {
	return {
		get(target, revision, id, count, addDependency) {
			const result = manager.get(target, revision, id, count, addDependency);
			instrumentation.managerCalls.push({
				sequence: instrumentation.nextSequence++,
				method: "get",
				field,
				target: target === CrossFieldTarget.Source ? "source" : "destination",
				revision: revision === undefined ? null : Number(revision),
				localId: Number(id),
				count,
				addDependency,
				found: result.value !== undefined,
				returnedLength: result.length,
			});
			return result;
		},
		set(target, revision, id, count, value, invalidateDependents) {
			instrumentation.managerCalls.push({
				sequence: instrumentation.nextSequence++,
				method: "set",
				field,
				target: target === CrossFieldTarget.Source ? "source" : "destination",
				revision: revision === undefined ? null : Number(revision),
				localId: Number(id),
				count,
				invalidateDependents,
			});
			manager.set(target, revision, id, count, value, invalidateDependents);
		},
		onMoveIn(id) {
			instrumentation.managerCalls.push({
				sequence: instrumentation.nextSequence++,
				method: "onMoveIn",
				field,
				id: plainAtom(id),
			});
			manager.onMoveIn(id);
		},
		moveKey(target, revision, id, count) {
			instrumentation.managerCalls.push({
				sequence: instrumentation.nextSequence++,
				method: "moveKey",
				field,
				target: target === CrossFieldTarget.Source ? "source" : "destination",
				revision: revision === undefined ? null : Number(revision),
				localId: Number(id),
				count,
			});
			manager.moveKey(target, revision, id, count);
		},
	};
}

function instrumentedSequenceHandler(
	instrumentation: Instrumentation,
): FieldChangeHandler<Changeset> {
	const original = SequenceField.sequence.changeHandler;
	const fieldFor = (first: Changeset, second?: Changeset): FieldIdentity =>
		instrumentation.identities.get(first) ??
		(second === undefined ? undefined : instrumentation.identities.get(second)) ?? {
			node: null,
			field: "<converted>",
		};
	const record = (operation: "compose" | "invert" | "rebase", field: FieldIdentity): void => {
		instrumentation.handlerCalls.push({
			sequence: instrumentation.nextSequence++,
			operation,
			field,
			invocation:
				instrumentation.handlerCalls.filter(
					(call) =>
						call.operation === operation &&
						call.field.field === field.field &&
						atomSignature(call.field.node ?? { revision: null, localId: -1 }) ===
							atomSignature(field.node ?? { revision: null, localId: -1 }),
				).length + 1,
		});
	};
	return {
		...original,
		editor: {
			...original.editor,
			buildChildChanges(changes) {
				const entries = [...changes];
				const plain = entries.map(([index, id]) => [index, plainAtom(id)] as const);
				const context = instrumentation.genericDirections.get(genericSignature(plain));
				assert(
					context !== undefined,
					"Every observed Generic conversion must match a serialized operand.",
				);
				instrumentation.conversionCalls.push({ ...context, children: plain });
				const converted = original.editor.buildChildChanges(entries);
				instrumentation.identities.set(converted, context.field);
				return converted;
			},
		},
		rebaser: {
			...original.rebaser,
			compose(change1, change2, composeChild, genId, manager, metadata) {
				const field = fieldFor(change1, change2);
				record("compose", field);
				return original.rebaser.compose(
					change1,
					change2,
					composeChild,
					genId,
					managerAdapter(manager, field, instrumentation),
					metadata,
				);
			},
			invert(change, isRollback, genId, revision, manager, metadata) {
				const field = fieldFor(change);
				record("invert", field);
				return original.rebaser.invert(
					change,
					isRollback,
					genId,
					revision,
					managerAdapter(manager, field, instrumentation),
					metadata,
				);
			},
			rebase(change, over, rebaseChild, genId, manager, metadata) {
				const field = fieldFor(change, over);
				record("rebase", field);
				return original.rebaser.rebase(
					change,
					over,
					rebaseChild,
					genId,
					managerAdapter(manager, field, instrumentation),
					metadata,
				);
			},
		},
	};
}

function makeInstrumentedArrayModularFamily(
	instrumentation: Instrumentation,
	context: ReplayIdContext,
): {
	readonly family: ModularChangeFamily;
	readonly codecOptions: CodecWriteOptions;
} {
	const codecOptions: CodecWriteOptions = {
		jsonValidator: FormatValidatorBasic,
		minVersionForCollab: FluidClientVersion.v2_117,
	};
	const revisionTagCodec = context.revisionTagCodec;
	const fieldBatchCodec = fieldBatchCodecBuilder.build(codecOptions);
	const codecs = makeModularChangeCodecFamily(
		fieldKindConfigurations,
		revisionTagCodec,
		fieldBatchCodec,
		codecOptions,
		TreeCompressionStrategy.Compressed,
	);
	const observedKinds = new Map(fieldKinds);
	const sequence = SequenceField.sequence;
	observedKinds.set(
		sequence.identifier,
		new FlexFieldKind(sequence.identifier, sequence.multiplicity, {
			...sequence.options,
			changeHandler: instrumentedSequenceHandler(instrumentation),
		}),
	);
	return {
		family: new ModularChangeFamily(observedKinds, codecs, codecOptions),
		codecOptions,
	};
}

function replayArrayModular(
	input: Record<string, unknown>,
	rawCoordination: boolean,
): unknown {
	object(input, "The modular replay input must be an object.");
	assert(
		input.operation === "compose" ||
			input.operation === "invert" ||
			input.operation === "rebase",
		"The modular operation must be compose, invert, or rebase.",
	);
	object(input.operands, "The modular operands must be an object.");
	assert(
		Array.isArray(input.operands.changes) && input.operands.changes.length > 0,
		"The modular operands must contain tagged changes.",
	);
	assert(
		Array.isArray(input.revisions) && input.revisions.length > 0,
		"The modular replay must contain revision mappings.",
	);
	object(input.allocator, "The modular replay must contain allocator state.");
	integer(input.allocator.maxLocalId, "The modular allocator watermark must be an integer.");
	const context = replayIdContext(input);
	const revisionMappings = new Map(
		input.revisions.map((mapping) => {
			object(mapping, "The modular revision mapping must be an object.");
			integer(mapping.encoded, "The encoded modular revision must be an integer.");
			assert(
				typeof mapping.stable === "string" && mapping.stable.length > 0,
				"The stable modular revision must be a string.",
			);
			assert.equal(
				context.idCompressor.decompress(mapping.encoded as SessionSpaceCompressedId),
				mapping.stable,
				"The modular revision mapping must match the compressor.",
			);
			return [mapping.encoded, mapping.stable] as const;
		}),
	);
	const taggedInputs = input.operands.changes as unknown as TaggedPlainModularChange[];
	assert.equal(
		input.allocator.maxLocalId,
		Math.max(...taggedInputs.map(({ change }) => change.maxLocalId)),
		"The modular allocator watermark must match the tagged operands.",
	);
	for (const tagged of taggedInputs) {
		assert(
			revisionMappings.has(tagged.revision),
			"Every tagged modular revision must have an explicit mapping.",
		);
	}
	const instrumentation: Instrumentation = {
		conversionCalls: [],
		handlerCalls: [],
		managerCalls: [],
		identities: new WeakMap(),
		genericDirections: new Map(),
		nextSequence: 0,
	};
	const decoded = taggedInputs.map((tagged, index) =>
		tagChange(
			decodeModularChange(
				tagged.change,
				instrumentation,
				index,
				taggedInputs[1 - index]?.change,
				context,
			),
			decodeRevision(tagged.revision, "The tagged modular revision must be valid.", context),
		),
	);
	const { family } = makeInstrumentedArrayModularFamily(instrumentation, context);
	let result: ModularChangeset;
	let resultRevision: RevisionTag | undefined;
	if (input.operation === "compose") {
		result = family.compose(decoded);
	} else if (input.operation === "invert") {
		assert(decoded.length === 1, "Invert requires one tagged modular change.");
		assert(
			typeof input.operands.isRollback === "boolean",
			"Invert requires the rollback flag.",
		);
		resultRevision = decodeRevision(
			input.operands.inverseRevision,
			"Invert requires an inverse revision.",
			context,
		);
		result = family.invert(decoded[0], input.operands.isRollback, resultRevision);
	} else {
		assert(decoded.length === 2, "Rebase requires a change and a base.");
		assert(
			Array.isArray(input.operands.revisionMetadata),
			"Rebase requires revision metadata.",
		);
		resultRevision = decoded[0].revision;
		result = family.rebase(
			decoded[0],
			decoded[1],
			revisionMetadataSourceFromInfo(
				input.operands.revisionMetadata.map((info) => ({
					revision: decodeRevision(
						info.revision,
						"The rebase revision must be valid.",
						context,
					),
					...(info.rollbackOf === null
						? {}
						: {
								rollbackOf: decodeRevision(
									info.rollbackOf,
									"The rebase rollback revision must be valid.",
									context,
								),
							}),
				})),
			),
		);
	}
	const coordination = {
		handlerCalls: instrumentation.handlerCalls,
		managerCalls: instrumentation.managerCalls,
	};
	const retry = instrumentation.handlerCalls.some((call) => call.invocation > 1);
	const causalCalls = [
		...instrumentation.handlerCalls.map((call) => ({
			sequence: call.sequence,
			value: {
				kind: "handler",
				operation: call.operation,
				field: call.field,
				invocation: call.invocation,
			},
		})),
		...instrumentation.managerCalls
			.filter((call) => call.method !== "get")
			.map(({ sequence, ...call }) => ({
				sequence: sequence as number,
				value: { kind: "manager", call },
			})),
	]
		.sort((left, right) => left.sequence - right.sequence)
		.map((entry) => entry.value);
	const reads = instrumentation.managerCalls.filter((call) => call.method === "get");
	const readEvidence = {
		absent: reads.some((call) => call.found === false),
		found: reads.some((call) => call.found === true),
		partial: reads.some(
			(call) =>
				typeof call.returnedLength === "number" &&
				typeof call.count === "number" &&
				call.returnedLength < call.count,
		),
		dependency: reads.some((call) => call.addDependency === true),
		invalidation:
			retry &&
			instrumentation.managerCalls.some(
				(call) => call.method === "set" && call.invalidateDependents === true,
			),
		retry,
	};
	return {
		graph: encodeModularGraph(result),
		delta: delta(intoDelta(tagChange(result, resultRevision))),
		conversion: {
			directions: instrumentation.conversionCalls.map((call) => call.direction),
			calls: instrumentation.conversionCalls,
		},
		coordination: rawCoordination
			? coordination
			: {
					handlerCalls: coordination.handlerCalls.map(
						({ sequence: _, ...call }) => call,
					),
					managerCalls: coordination.managerCalls
						.filter((call) => call.method !== "get")
						.map(({ sequence: _, ...call }) => call),
					causalCalls,
					readEvidence,
				},
	};
}

export function replayArrayModularInput(input: Record<string, unknown>): unknown {
	return replayArrayModular(input, false);
}

export function replayArrayModularInputRaw(input: Record<string, unknown>): unknown {
	return replayArrayModular(input, true);
}

function crossFieldChange(
	revision: RevisionTag,
	destinationFirst: boolean,
	compressor: IIdCompressor,
): PlainModularChange {
	const context = {
		idCompressor: compressor,
		revisionTagCodec: new RevisionTagCodec(compressor),
	};
	const moveId = brand<ChangesetLocalId>(40);
	const destinationCellId = { revision, localId: brand<ChangesetLocalId>(42) };
	const entries: (readonly [string, PlainFieldChange])[] = [
		[
			"left",
			{
				kind: "Sequence",
				change: sequenceFieldEditor.moveOut(0, 2, moveId, revision),
			},
		],
		[
			"right",
			{
				kind: "Sequence",
				change: sequenceFieldEditor.moveIn(0, 2, moveId, destinationCellId, revision),
			},
		],
	];
	if (destinationFirst) entries.reverse();
	const instrumentation: Instrumentation = {
		conversionCalls: [],
		handlerCalls: [],
		managerCalls: [],
		identities: new WeakMap(),
		genericDirections: new Map(),
		nextSequence: 0,
	};
	const fields = decodeFieldChanges(entries, instrumentation, null, 0, undefined, context);
	const inversions = makeChangesetInversions(
		fields,
		newChangeAtomIdBTree(),
		fieldKinds,
		newChangeAtomIdBTree(),
	);
	return encodeModularGraph(
		makeModularChangeset({
			maxId: 42,
			revisions: [{ revision }],
			fieldChanges: fields,
			...inversions,
		}),
	);
}

export function crossFieldCoordinationInput(
	revision: RevisionTag,
	compressor: IIdCompressor,
): ReplayInput {
	const context = {
		idCompressor: compressor,
		revisionTagCodec: new RevisionTagCodec(compressor),
	};
	const competing = (field: string, id: number): readonly [string, PlainFieldChange] => [
		field,
		{
			kind: "Sequence",
			change: sequenceFieldEditor.move(
				1,
				2,
				0,
				brand(id),
				{ revision, localId: brand(id + 2) },
				revision,
			),
		},
	];
	const fields = [competing("right", 44), competing("left", 48)];
	const instrumentation: Instrumentation = {
		conversionCalls: [],
		handlerCalls: [],
		managerCalls: [],
		identities: new WeakMap(),
		genericDirections: new Map(),
		nextSequence: 0,
	};
	const decodedFields = decodeFieldChanges(fields, instrumentation, null, 1, undefined, context);
	const inversions = makeChangesetInversions(
		decodedFields,
		newChangeAtomIdBTree(),
		fieldKinds,
		newChangeAtomIdBTree(),
	);
	const second = encodeModularGraph(
		makeModularChangeset({
			maxId: 50,
			revisions: [{ revision }],
			fieldChanges: decodedFields,
			...inversions,
		}),
	);
	return copy({
		operation: "compose",
		initialState: { left: [], right: [] },
		operands: {
			changes: [
				{ revision: Number(revision), change: crossFieldChange(revision, true, compressor) },
				{ revision: Number(revision), change: second },
			],
		},
		revisions: [
			{
				encoded: Number(revision),
				stable: compressor.decompress(revision as SessionSpaceCompressedId),
			},
		],
		allocator: { maxLocalId: 50 },
		compressor: {
			sessionId: compressor.localSessionId,
			serialized: serializeIdCompressor(compressor, true),
		},
		sequencing: { minimumSequenceNumber: 0, sequenceNumber: 0 },
		schedule: ["destination", "source", "source-update", "source-reprocess"],
	} satisfies ReplayInput);
}

export function captureCrossFieldCoordination(
	revision: RevisionTag,
	compressor: IIdCompressor,
): unknown {
	return replayArrayModularInput(
		crossFieldCoordinationInput(revision, compressor) as unknown as Record<string, unknown>,
	);
}
