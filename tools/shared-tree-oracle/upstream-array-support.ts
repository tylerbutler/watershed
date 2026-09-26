/*!
 * Copyright (c) Microsoft Corporation and contributors. All rights reserved.
 * Licensed under the MIT License.
 */

import { strict as assert } from "node:assert";

import type { SessionSpaceCompressedId } from "@fluidframework/id-compressor";
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
	type RevisionTag,
} from "../core/index.js";
import { FormatValidatorBasic } from "../external-utilities/index.js";
import {
	CrossFieldTarget,
	fieldBatchCodecBuilder,
	fieldKindConfigurations,
	fieldKinds,
	FlexFieldKind,
	genericFieldKind,
	intoDelta,
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
import { testIdCompressor } from "./utils.js";

type PlainAtom = {
	readonly revision: number | null;
	readonly localId: number;
};

type PlainFieldId = {
	readonly node: PlainAtom | null;
	readonly field: string;
};

type PlainFieldChange = {
	readonly kind: "Generic" | "Sequence";
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
	readonly compressor: { readonly sessionId: string };
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

function decodeRevision(value: unknown, message: string): RevisionTag {
	integer(value, message);
	const encoded = value as SessionSpaceCompressedId;
	testIdCompressor.decompress(encoded);
	return encoded as RevisionTag;
}

function decodeOptionalRevision(value: unknown, message: string): RevisionTag | undefined {
	return value === null ? undefined : decodeRevision(value, message);
}

function decodeLocalId(value: unknown, message: string): ChangesetLocalId {
	integer(value, message);
	assert(value >= 0, message);
	return brand(value);
}

function decodeAtom(value: unknown, message: string): ChangeAtomId {
	object(value, message);
	return {
		revision: decodeOptionalRevision(value.revision, message),
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
): {
	nodeId: ChangeAtomId | undefined;
	field: FieldKey;
} {
	object(value, message);
	assert(typeof value.field === "string", message);
	return {
		nodeId: value.node === null ? undefined : decodeAtom(value.node, message),
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
				return [child[0], decodeAtom(child[1], "The Generic child ID must be valid.")];
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
): ModularChangeset {
	integer(value.maxLocalId, "The modular allocator watermark must be an integer.");
	const fieldChanges = decodeFieldChanges(
		value.fields,
		instrumentation,
		null,
		operand,
		other?.fields,
	);
	const nodeChanges = newChangeAtomIdBTree<NodeChangeset>();
	for (const [idValue, nodeValue] of value.nodes) {
		const id = decodeAtom(idValue, "The modular node ID must be valid.");
		nodeChanges.set([id.revision, id.localId], {
			fieldChanges: decodeFieldChanges(
				nodeValue.fields,
				instrumentation,
				plainAtom(id),
				operand,
				undefined,
			),
		});
	}
	const nodeToParent = newChangeAtomIdBTree<FieldId>();
	for (const [idValue, parentValue] of value.parents) {
		const id = decodeAtom(idValue, "The modular parent node ID must be valid.");
		nodeToParent.set(
			[id.revision, id.localId],
			decodeFieldId(parentValue, "The modular parent field must be valid."),
		);
	}
	const nodeAliases = newChangeAtomIdBTree<ChangeAtomId>();
	for (const [sourceValue, targetValue] of value.aliases) {
		const source = decodeAtom(sourceValue, "The modular alias source must be valid.");
		const target = decodeAtom(targetValue, "The modular alias target must be valid.");
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
				),
				localId: decodeLocalId(entry.localId, "The cross-field local ID must be valid."),
			},
			entry.count,
			decodeFieldId(entry.field, "The cross-field owner must be valid."),
		);
	}
	return makeModularChangeset({
		maxId: value.maxLocalId,
		revisions: value.revisions.map((info) => ({
			revision: decodeRevision(info.revision, "The modular revision must be valid."),
			...(info.rollbackOf === null
				? {}
				: {
						rollbackOf: decodeRevision(
							info.rollbackOf,
							"The rollback revision must be valid.",
						),
					}),
		})),
		fieldChanges,
		nodeChanges,
		nodeToParent,
		nodeAliases,
		crossFieldKeys,
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

function makeInstrumentedArrayModularFamily(instrumentation: Instrumentation): {
	readonly family: ModularChangeFamily;
	readonly codecOptions: CodecWriteOptions;
} {
	const codecOptions: CodecWriteOptions = {
		jsonValidator: FormatValidatorBasic,
		minVersionForCollab: FluidClientVersion.v2_117,
	};
	const revisionTagCodec = new RevisionTagCodec(testIdCompressor);
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

export function replayArrayModularInput(input: Record<string, unknown>): unknown {
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
	const revisionMappings = new Map(
		input.revisions.map((mapping) => {
			object(mapping, "The modular revision mapping must be an object.");
			integer(mapping.encoded, "The encoded modular revision must be an integer.");
			assert(
				typeof mapping.stable === "string" && mapping.stable.length > 0,
				"The stable modular revision must be a string.",
			);
			assert.equal(
				testIdCompressor.decompress(mapping.encoded as SessionSpaceCompressedId),
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
			),
			decodeRevision(tagged.revision, "The tagged modular revision must be valid."),
		),
	);
	const { family } = makeInstrumentedArrayModularFamily(instrumentation);
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
					revision: decodeRevision(info.revision, "The rebase revision must be valid."),
					...(info.rollbackOf === null
						? {}
						: {
								rollbackOf: decodeRevision(
									info.rollbackOf,
									"The rebase rollback revision must be valid.",
								),
							}),
				})),
			),
		);
	}
	return {
		graph: encodeModularGraph(result),
		delta: delta(intoDelta(tagChange(result, resultRevision))),
		conversion: {
			directions: instrumentation.conversionCalls.map((call) => call.direction),
			calls: instrumentation.conversionCalls,
		},
		coordination: {
			handlerCalls: instrumentation.handlerCalls,
			managerCalls: instrumentation.managerCalls,
		},
	};
}

function crossFieldChange(
	revision: RevisionTag,
	destinationFirst: boolean,
): PlainModularChange {
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
	const fields = decodeFieldChanges(entries, instrumentation, null, 0, undefined);
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

export function crossFieldCoordinationInput(revision: RevisionTag): ReplayInput {
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
	const decodedFields = decodeFieldChanges(fields, instrumentation, null, 1, undefined);
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
				{ revision: Number(revision), change: crossFieldChange(revision, true) },
				{ revision: Number(revision), change: second },
			],
		},
		revisions: [
			{
				encoded: Number(revision),
				stable: testIdCompressor.decompress(revision as SessionSpaceCompressedId),
			},
		],
		allocator: { maxLocalId: 50 },
		compressor: { sessionId: testIdCompressor.localSessionId },
		sequencing: { minimumSequenceNumber: 0, sequenceNumber: 0 },
		schedule: ["destination", "source", "source-update", "source-reprocess"],
	} satisfies ReplayInput);
}

export function captureCrossFieldCoordination(revision: RevisionTag): unknown {
	return replayArrayModularInput(
		crossFieldCoordinationInput(revision) as unknown as Record<string, unknown>,
	);
}
