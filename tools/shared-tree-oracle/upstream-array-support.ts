/*!
 * Copyright (c) Microsoft Corporation and contributors. All rights reserved.
 * Licensed under the MIT License.
 */

import { strict as assert } from "node:assert";

import type { IIdCompressor, SessionSpaceCompressedId } from "@fluidframework/id-compressor";
import {
	deserializeIdCompressor,
	serializeIdCompressor,
	type SerializedIdCompressorWithOngoingSession,
} from "@fluidframework/id-compressor/internal";
import { FluidClientVersion, type CodecWriteOptions } from "../codec/index.js";
import {
	revisionMetadataSourceFromInfo,
	RevisionTagCodec,
	rootFieldKey,
	tagChange,
	makeAnonChange,
	type ChangeAtomId,
	type ChangeEncodingContext,
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
	DefaultEditBuilder,
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
	ModularChangeFormatVersion,
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
import { brand, type JsonCompatibleReadOnly } from "../util/index.js";
import { moveWithin, testChangeReceiver } from "./utils.js";

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
	readonly genericOrigins: WeakMap<
		object,
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
	assert(
		typeof input.compressor.sessionId === "string",
		"The modular compressor session must be a string.",
	);
	assert(
		typeof input.compressor.serialized === "string",
		"The modular compressor state must be serialized.",
	);
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
	_otherFields: readonly (readonly [string, PlainFieldChange])[] | undefined,
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
			const entries = change.entries.bind(change);
			change.entries = () => {
				const iterable = entries();
				instrumentation.genericOrigins.set(iterable, {
					direction: operand === 0 ? "generic-left" : "generic-right",
					field: identity,
				});
				return iterable;
			};
			fields.set(field, {
				fieldKind: genericFieldKind.identifier,
				change: brand(change),
			});
		} else if (entry[1].kind === "Value" || entry[1].kind === "Optional") {
			object(entry[1].change, "The register change must be an object.");
			assert(
				Array.isArray(entry[1].change.moves) && Array.isArray(entry[1].change.childChanges),
				"The register change must contain moves and child changes.",
			);
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
		const source = decodeAtom(sourceValue, "The modular alias source must be valid.", context);
		const target = decodeAtom(targetValue, "The modular alias target must be valid.", context);
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
				combineChunks(
					chunkField(cursorForJsonableTreeField([...trees]), {
						policy: defaultChunkPolicy,
						idCompressor: context.idCompressor,
					}),
				),
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
		refreshers: [...(change.refreshers?.entries() ?? [])].map(
			([[revision, localId], chunk]) => [
				plainAtom({ revision, localId }),
				jsonableTreeFromFieldCursor(chunk.cursor()),
			],
		),
		destroys: [...(change.destroys?.entries() ?? [])].map(([[revision, localId], count]) => [
			plainAtom({ revision, localId }),
			count,
		]),
	};
}

export function encodeModularV5(
	value: PlainModularChange,
	idCompressor: IIdCompressor,
): { readonly encoded: unknown; readonly graph: PlainModularChange } {
	const context = {
		idCompressor,
		revisionTagCodec: new RevisionTagCodec(idCompressor),
	};
	const instrumentation: Instrumentation = {
		conversionCalls: [],
		handlerCalls: [],
		managerCalls: [],
		identities: new WeakMap(),
		genericOrigins: new WeakMap(),
		nextSequence: 0,
	};
	const decoded = decodeModularChange(value, instrumentation, 0, undefined, context);
	const { family } = makeArrayModularFamily(context);
	const encodingContext: ChangeEncodingContext = {
		originatorId: idCompressor.localSessionId,
		idCompressor,
		revision: undefined,
		isSummary: false,
	};
	const codec = family.codecs.resolve(ModularChangeFormatVersion.v5);
	const encoded = codec.encode(decoded, encodingContext);
	return {
		encoded,
		graph: encodeModularGraph(codec.decode(encoded, encodingContext)),
	};
}

export function decodeModularV5(
	value: unknown,
	idCompressor: IIdCompressor,
	revision?: number,
): PlainModularChange {
	const context = {
		idCompressor,
		revisionTagCodec: new RevisionTagCodec(idCompressor),
	};
	const { family } = makeArrayModularFamily(context);
	const decodedRevision: RevisionTag | undefined =
		revision === undefined ? undefined : (revision as SessionSpaceCompressedId);
	const codecContext: ChangeEncodingContext = {
		originatorId: idCompressor.localSessionId,
		idCompressor,
		revision: decodedRevision,
		isSummary: false,
	};
	return encodeModularGraph(
		family.codecs
			.resolve(ModularChangeFormatVersion.v5)
			.decode(value as JsonCompatibleReadOnly, codecContext),
	);
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
				const context = instrumentation.genericOrigins.get(changes);
				const entries = [...changes];
				const plain = entries.map(([index, id]) => [index, plainAtom(id)] as const);
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

function makeArrayModularFamily(context: ReplayIdContext): {
	readonly family: ModularChangeFamily;
	readonly codecOptions: CodecWriteOptions;
} {
	const codecOptions: CodecWriteOptions = {
		jsonValidator: FormatValidatorBasic,
		minVersionForCollab: FluidClientVersion.v2_117,
	};
	const codecs = makeModularChangeCodecFamily(
		fieldKindConfigurations,
		context.revisionTagCodec,
		fieldBatchCodecBuilder.build(codecOptions),
		codecOptions,
		TreeCompressionStrategy.Compressed,
	);
	return {
		family: new ModularChangeFamily(fieldKinds, codecs, codecOptions),
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
		genericOrigins: new WeakMap(),
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
					handlerCalls: coordination.handlerCalls.map(({ sequence: _, ...call }) => call),
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
		genericOrigins: new WeakMap(),
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
		genericOrigins: new WeakMap(),
		nextSequence: 0,
	};
	const decodedFields = decodeFieldChanges(
		fields,
		instrumentation,
		null,
		1,
		undefined,
		context,
	);
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

export function multiPassComposeInput(
	revisions: readonly [RevisionTag, RevisionTag, RevisionTag, RevisionTag, RevisionTag],
	compressor: IIdCompressor,
): ReplayInput {
	const context = {
		idCompressor: compressor,
		revisionTagCodec: new RevisionTagCodec(compressor),
	};
	const { family, codecOptions } = makeArrayModularFamily(context);
	const pendingRevisions = [...revisions.slice(0, 4)];
	const [changeReceiver, getChanges] = testChangeReceiver(family);
	const editor = new DefaultEditBuilder(
		family,
		() => pendingRevisions.shift() ?? revisions[3],
		changeReceiver,
		codecOptions,
	);
	const fieldA = brand<FieldKey>("FieldA");
	const fieldB = brand<FieldKey>("FieldB");
	const fieldC = brand<FieldKey>("FieldC");
	const nodeA = { parent: undefined, parentField: fieldA, parentIndex: 0 };
	const fieldAPath = { parent: undefined, field: fieldA };
	moveWithin(editor, fieldAPath, 0, 1, 1);
	editor.move(fieldAPath, 1, 1, { parent: nodeA, field: fieldB }, 0);
	const nodeB = { parent: nodeA, parentField: fieldB, parentIndex: 0 };
	editor.move(fieldAPath, 1, 1, { parent: nodeB, field: fieldC }, 0);
	const nodeC = { parent: nodeB, parentField: fieldC, parentIndex: 0 };
	editor.sequenceField({ parent: nodeC, field: fieldC }).remove(0, 1);
	const [moveA, moveB, moveC, removeD] = getChanges();
	assert(moveA !== undefined && moveB !== undefined && moveC !== undefined);
	assert(removeD !== undefined, "The multi-pass source edit must produce four changes.");
	const moves = family.compose([
		makeAnonChange(moveA),
		makeAnonChange(moveB),
		makeAnonChange(moveC),
	]);
	const compareRevision = revisions[4];
	return {
		operation: "compose",
		initialState: ["A", "B", "C"],
		operands: {
			changes: [
				{ revision: Number(compareRevision), change: encodeModularGraph(moves) },
				{ revision: Number(compareRevision), change: encodeModularGraph(removeD) },
			],
		},
		revisions: revisions.map((revision) => ({
			encoded: Number(revision),
			stable: compressor.decompress(revision as SessionSpaceCompressedId),
		})),
		allocator: {
			maxLocalId: Math.max(moves.maxId ?? -1, removeD.maxId ?? -1),
		},
		compressor: {
			sessionId: compressor.localSessionId,
			serialized: serializeIdCompressor(compressor, true),
		},
		sequencing: { minimumSequenceNumber: 0, sequenceNumber: 0 },
		schedule: ["move-a", "move-b", "move-c", "remove-d", "compose"],
	};
}

export function multiRevisionInversionInput(
	revisions: readonly [RevisionTag, RevisionTag, RevisionTag],
	compressor: IIdCompressor,
	contextRevisions: readonly RevisionTag[] = revisions,
	splitFirstMove = false,
): ReplayInput {
	const [firstRevision, secondRevision, inverseRevision] = revisions;
	const atom = (revision: RevisionTag, localId: number): PlainAtom => ({
		revision: Number(revision),
		localId,
	});
	const parent = (field: string): PlainFieldId => ({ node: null, field });
	const sequence = (change: unknown[]): PlainFieldChange => ({ kind: "Sequence", change });
	const change: PlainModularChange = {
		maxLocalId: 30,
		revisions: [firstRevision, secondRevision].map((revision) => ({
			revision: Number(revision),
			rollbackOf: null,
		})),
		fields: [
			[
				"left0",
				sequence([
					{
						type: "MoveIn",
						id: 10,
						count: splitFirstMove ? 2 : 1,
						cellId: atom(firstRevision, 12),
						revision: Number(firstRevision),
					},
				]),
			],
			[
				"right0",
				sequence([
					{
						type: "MoveOut",
						id: 10,
						count: 1,
						revision: Number(firstRevision),
						changes: atom(firstRevision, 30),
					},
					...(splitFirstMove
						? [
								{
									type: "MoveOut",
									id: 11,
									count: 1,
									revision: Number(firstRevision),
								},
							]
						: []),
				]),
			],
			[
				"left1",
				sequence([
					{
						type: "MoveIn",
						id: 10,
						count: 1,
						cellId: atom(secondRevision, 12),
						revision: Number(secondRevision),
					},
				]),
			],
			[
				"right1",
				sequence([
					{
						type: "MoveOut",
						id: 10,
						count: 1,
						revision: Number(secondRevision),
						changes: atom(secondRevision, 30),
					},
				]),
			],
		],
		nodes: [
			[atom(firstRevision, 30), { fields: [] }],
			[atom(secondRevision, 30), { fields: [] }],
		],
		parents: [
			[atom(firstRevision, 30), parent("right0")],
			[atom(secondRevision, 30), parent("right1")],
		],
		aliases: [],
		crossFieldKeys: [
			{
				target: "source",
				revision: Number(secondRevision),
				localId: 10,
				count: 1,
				field: parent("right1"),
			},
			{
				target: "source",
				revision: Number(firstRevision),
				localId: 10,
				count: splitFirstMove ? 2 : 1,
				field: parent("right0"),
			},
			{
				target: "destination",
				revision: Number(secondRevision),
				localId: 10,
				count: 1,
				field: parent("left1"),
			},
			{
				target: "destination",
				revision: Number(firstRevision),
				localId: 10,
				count: splitFirstMove ? 2 : 1,
				field: parent("left0"),
			},
		],
		builds: [],
		refreshers: [],
		destroys: [],
	};
	return {
		operation: "invert",
		initialState: {},
		operands: {
			changes: [{ revision: Number(firstRevision), change }],
			isRollback: false,
			inverseRevision: Number(inverseRevision),
		},
		revisions: contextRevisions.map((revision) => ({
			encoded: Number(revision),
			stable: compressor.decompress(revision as SessionSpaceCompressedId),
		})),
		allocator: { maxLocalId: 30 },
		compressor: {
			sessionId: compressor.localSessionId,
			serialized: serializeIdCompressor(compressor, true),
		},
		sequencing: { minimumSequenceNumber: 0, sequenceNumber: 0 },
		schedule: ["invert"],
	};
}

export function forestCheckpointInput(
	revisions: readonly RevisionTag[],
	compressor: IIdCompressor,
): Record<string, unknown> {
	assert(revisions.length >= 15, "Forest checkpoints need fifteen revisions.");
	const context = {
		idCompressor: compressor,
		revisionTagCodec: new RevisionTagCodec(compressor),
	};
	const { family, codecOptions } = makeArrayModularFamily(context);
	const child = brand<FieldKey>("child");
	const root = { parent: undefined, field: rootFieldKey };
	const author = (revision: RevisionTag, edit: (editor: DefaultEditBuilder) => void) => {
		const [receiver, changes] = testChangeReceiver(family);
		const editor = new DefaultEditBuilder(family, () => revision, receiver, codecOptions);
		edit(editor);
		const [change] = changes();
		assert(change !== undefined, "The forest edit must produce one modular change.");
		return change;
	};
	const move = author(revisions[0], (editor) => moveWithin(editor, root, 0, 1, 2));
	const editAfterMove = author(revisions[1], (editor) => {
		editor
			.sequenceField({
				parent: { parent: undefined, parentField: rootFieldKey, parentIndex: 1 },
				field: child,
			})
			.remove(0, 1);
	});
	const editBeforeMove = author(revisions[2], (editor) => {
		editor
			.sequenceField({
				parent: { parent: undefined, parentField: rootFieldKey, parentIndex: 0 },
				field: child,
			})
			.remove(0, 1);
	});
	const composed = family.compose([
		tagChange(move, revisions[0]),
		tagChange(editAfterMove, revisions[1]),
	]);
	const encodedRevisions = revisions.map((revision) => ({
		encoded: Number(revision),
		stable: compressor.decompress(revision as SessionSpaceCompressedId),
	}));
	const replay = (
		operation: ReplayInput["operation"],
		changes: readonly TaggedPlainModularChange[],
		options: Partial<ReplayInput["operands"]> = {},
	): ReplayInput => ({
		operation,
		initialState: {},
		operands: { changes, ...options },
		revisions: encodedRevisions,
		allocator: {
			maxLocalId: Math.max(-1, ...changes.map(({ change }) => change.maxLocalId)),
		},
		compressor: {
			sessionId: compressor.localSessionId,
			serialized: serializeIdCompressor(compressor, true),
		},
		sequencing: { minimumSequenceNumber: 0, sequenceNumber: 0 },
		schedule: [operation],
	});
	const taggedPlain = (revision: RevisionTag, change: ModularChangeset) => ({
		revision: Number(revision),
		change: encodeModularGraph(change),
	});
	const moveStep = {
		id: "move",
		...replay("compose", [taggedPlain(revisions[0], move)]),
	};
	const editStep = {
		id: "edit-after-move",
		...replay("compose", [taggedPlain(revisions[1], editAfterMove)]),
	};
	const composedStep = {
		id: "compose-move-edit",
		...replay("compose", [
			taggedPlain(revisions[0], move),
			taggedPlain(revisions[1], editAfterMove),
		]),
	};
	const rebasedStep = {
		id: "rebase-edit-over-move",
		...replay(
			"rebase",
			[taggedPlain(revisions[2], editBeforeMove), taggedPlain(revisions[0], move)],
			{
				revisionMetadata: [revisions[0], revisions[2]].map((revision) => ({
					revision: Number(revision),
					rollbackOf: null,
				})),
			},
		),
	};
	const inverseStep = {
		id: "invert-composed",
		...replay("invert", [taggedPlain(revisions[3], composed)], {
			isRollback: false,
			inverseRevision: Number(revisions[4]),
		}),
	};
	const raceChild = author(revisions[5], (editor) => {
		editor
			.sequenceField({
				parent: { parent: undefined, parentField: rootFieldKey, parentIndex: 0 },
				field: child,
			})
			.remove(0, 1);
	});
	const removeAncestor = author(revisions[6], (editor) => {
		editor.sequenceField(root).remove(0, 1);
	});
	const moveReplacement = author(revisions[7], (editor) => moveWithin(editor, root, 1, 1, 0));
	const removeReplacedAncestor = author(revisions[8], (editor) => {
		editor.sequenceField(root).remove(1, 1);
	});
	const replaceAncestor = family.compose([
		tagChange(moveReplacement, revisions[7]),
		tagChange(removeReplacedAncestor, revisions[8]),
	]);
	const raceStep = (
		id: string,
		operation: ReplayInput["operation"],
		changes: readonly TaggedPlainModularChange[],
	) => ({
		id,
		...replay(
			operation,
			changes,
			operation === "rebase"
				? {
						revisionMetadata: revisions.slice(5, 9).map((revision) => ({
							revision: Number(revision),
							rollbackOf: null,
						})),
					}
				: {},
		),
	});
	const raceChildTagged = taggedPlain(revisions[5], raceChild);
	const removeAncestorTagged = taggedPlain(revisions[6], removeAncestor);
	const replaceAncestorTagged = taggedPlain(revisions[8], replaceAncestor);
	const inversionRetry = multiRevisionInversionInput(
		[revisions[0], revisions[1], revisions[5]],
		compressor,
		revisions.slice(0, 11),
	);
	const inversionForward = inversionRetry.operands.changes[0];
	const inversionForwardStep = {
		id: "multi-revision-forward",
		...replay("compose", [inversionForward]),
	};
	const inversionRetryStep = {
		id: "multi-revision-inverse",
		...inversionRetry,
	};
	const inversionInitialState = {
		field: [
			{
				type: "org.watershed.shared-tree.m3.ForestNode",
				fields: [
					["right0", [{ type: "com.fluidframework.leaf.string", value: "A", fields: [] }]],
					["right1", [{ type: "com.fluidframework.leaf.string", value: "B", fields: [] }]],
				],
			},
		],
	};
	const inversionCandidates = [
		[0, "left0", 0],
		[0, "right0", 0],
		[0, "left1", 0],
		[0, "right1", 0],
	];
	const atom = (revision: RevisionTag, localId: number): PlainAtom => ({
		revision: Number(revision),
		localId,
	});
	const parent = (field: string): PlainFieldId => ({ node: null, field });
	const sequence = (change: unknown[]): PlainFieldChange => ({ kind: "Sequence", change });
	const plainChange = (
		revision: RevisionTag,
		fields: PlainModularChange["fields"],
		nodes: PlainModularChange["nodes"] = [],
		parents: PlainModularChange["parents"] = [],
		maxLocalId = 0,
	): PlainModularChange => ({
		maxLocalId,
		revisions: [{ revision: Number(revision), rollbackOf: null }],
		fields,
		nodes,
		parents,
		aliases: [],
		crossFieldKeys: [],
		builds: [],
		refreshers: [],
		destroys: [],
	});
	const wrapper = "wrapper";
	const detachedWrapper = atom(revisions[12], 0);
	const renamedWrapper = atom(revisions[13], 20);
	const seedDetached = plainChange(revisions[12], [
		[
			wrapper,
			sequence([
				{
					count: 1,
				},
				{
					type: "Remove",
					id: 0,
					count: 1,
					revision: Number(revisions[12]),
				},
			]),
		],
	]);
	const occupiedChild = atom(revisions[13], 30);
	const emptyChild = atom(revisions[13], 31);
	const globalRename = plainChange(
		revisions[13],
		[
			[
				wrapper,
				sequence([
					{ count: 1, changes: occupiedChild },
					{
						type: "Remove",
						id: renamedWrapper.localId,
						count: 1,
						cellId: detachedWrapper,
						revision: renamedWrapper.revision,
						changes: emptyChild,
					},
				]),
			],
		],
		[
			[
				occupiedChild,
				{
					fields: [
						[
							"child",
							sequence([
								{
									type: "Remove",
									id: 21,
									count: 1,
									revision: Number(revisions[13]),
								},
							]),
						],
					],
				},
			],
			[
				emptyChild,
				{
					fields: [
						[
							"child",
							sequence([
								{
									type: "Remove",
									id: 22,
									count: 1,
									revision: Number(revisions[13]),
								},
							]),
						],
					],
				},
			],
		],
		[
			[occupiedChild, parent(wrapper)],
			[emptyChild, parent(wrapper)],
		],
		31,
	);
	const followChild = atom(revisions[14], 32);
	const renamedFollowUp = plainChange(
		revisions[14],
		[
			[
				wrapper,
				sequence([
					{ count: 1 },
					{
						count: 1,
						cellId: renamedWrapper,
						changes: followChild,
					},
				]),
			],
		],
		[
			[
				followChild,
				{
					fields: [
						[
							"label",
							sequence([
								{
									type: "Remove",
									id: 23,
									count: 1,
									revision: Number(revisions[14]),
								},
							]),
						],
					],
				},
			],
		],
		[[followChild, parent(wrapper)]],
		32,
	);
	const plainStep = (id: string, revision: RevisionTag, change: PlainModularChange) => ({
		id,
		...replay("compose", [
			{
				revision: Number(revision),
				change,
			},
		]),
	});
	const globalRenameInitialState = {
		field: [
			{
				type: "org.watershed.shared-tree.m3.ForestNode",
				fields: [
					[
						wrapper,
						[
							{
								type: "org.watershed.shared-tree.m3.ForestNode",
								fields: [
									[
										"label",
										[
											{
												type: "com.fluidframework.leaf.string",
												value: "occupied",
												fields: [],
											},
										],
									],
									[
										"child",
										[
											{
												type: "com.fluidframework.leaf.string",
												value: "live-child",
												fields: [],
											},
										],
									],
								],
							},
							{
								type: "org.watershed.shared-tree.m3.ForestNode",
								fields: [
									[
										"label",
										[
											{
												type: "com.fluidframework.leaf.string",
												value: "detached",
												fields: [],
											},
										],
									],
									[
										"child",
										[
											{
												type: "com.fluidframework.leaf.string",
												value: "detached-child",
												fields: [],
											},
										],
									],
								],
							},
						],
					],
				],
			},
		],
	};
	return {
		operation: "apply-modular",
		initialState: {
			field: [
				{
					type: "org.watershed.shared-tree.m3.ForestNode",
					fields: [
						["label", [{ type: "com.fluidframework.leaf.string", value: "A", fields: [] }]],
						["child", [{ type: "com.fluidframework.leaf.string", value: "old", fields: [] }]],
					],
				},
				{ type: "com.fluidframework.leaf.string", value: "B", fields: [] },
			],
		},
		operands: {
			runs: [
				{ id: "sequential", retainIndex: 0, steps: [moveStep, editStep] },
				{ id: "composed", retainIndex: 0, steps: [composedStep] },
				{ id: "rebased", retainIndex: 0, steps: [moveStep, rebasedStep] },
				{ id: "inverse", retainIndex: 0, steps: [composedStep, inverseStep] },
				{
					id: "remove-then-child",
					retainIndex: 0,
					steps: [
						raceStep("remove-ancestor", "compose", [removeAncestorTagged]),
						raceStep("child-over-remove", "rebase", [raceChildTagged, removeAncestorTagged]),
					],
				},
				{
					id: "child-then-remove",
					retainIndex: 0,
					steps: [
						raceStep("child", "compose", [raceChildTagged]),
						raceStep("remove-over-child", "rebase", [removeAncestorTagged, raceChildTagged]),
					],
				},
				{
					id: "replace-then-child",
					retainIndex: 0,
					steps: [
						raceStep("replace-ancestor", "compose", [replaceAncestorTagged]),
						raceStep("child-over-replacement", "rebase", [
							raceChildTagged,
							replaceAncestorTagged,
						]),
					],
				},
				{
					id: "child-then-replace",
					retainIndex: 0,
					steps: [
						raceStep("child", "compose", [raceChildTagged]),
						raceStep("replacement-over-child", "rebase", [
							replaceAncestorTagged,
							raceChildTagged,
						]),
					],
				},
				{
					id: "inversion-retry-first",
					initialState: inversionInitialState,
					retainIndex: null,
					retainPath: [0, "right0", 0],
					identityCandidates: inversionCandidates,
					wrapFieldsAtIndex: 0,
					steps: [inversionForwardStep, inversionRetryStep],
				},
				{
					id: "inversion-retry-second",
					initialState: inversionInitialState,
					retainIndex: null,
					retainPath: [0, "right1", 0],
					identityCandidates: inversionCandidates,
					wrapFieldsAtIndex: 0,
					steps: [inversionForwardStep, inversionRetryStep],
				},
				{
					id: "global-rename-continuation",
					initialState: globalRenameInitialState,
					retainIndex: null,
					retainPath: [0, wrapper, 1],
					identityCandidates: [
						[0, wrapper, 0],
						[0, wrapper, 1],
					],
					wrapFieldsAtIndex: 0,
					steps: [
						plainStep("detach-empty-wrapper", revisions[12], seedDetached),
						plainStep("global-edit-and-rename", revisions[13], globalRename),
						plainStep("edit-renamed-detached", revisions[14], renamedFollowUp),
					],
				},
			],
		},
		revisions: revisions.map(Number),
		algorithm: {
			localIds: "supplied-by-operands",
			composeAllocator: "unused-by-pinned-source",
			rebaseAllocator: "unused-by-pinned-source",
		},
		compressor: {
			mode: "test",
			session: compressor.localSessionId,
			serialized: serializeIdCompressor(compressor, true),
		},
		sequencing: { minimumSequenceNumber: 0, sequenceNumber: 0 },
		schedule: ["sequential", "composed", "rebased", "inverse"],
	};
}

export function captureCrossFieldCoordination(
	revision: RevisionTag,
	compressor: IIdCompressor,
): unknown {
	return replayArrayModularInput(
		crossFieldCoordinationInput(revision, compressor) as unknown as Record<string, unknown>,
	);
}
