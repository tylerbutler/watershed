/*!
 * Copyright (c) Microsoft Corporation and contributors. All rights reserved.
 * Licensed under the MIT License.
 */

import { strict as assert } from "node:assert";
import { mkdirSync, writeFileSync } from "node:fs";
import { isAbsolute, join } from "node:path";

import type { IIdCompressor, StableId } from "@fluidframework/id-compressor";
import { assertIsStableId } from "@fluidframework/id-compressor/internal";
import { createAlwaysFinalizedIdCompressor } from "@fluidframework/id-compressor/internal/test-utils";

import { FluidClientVersion, FormatValidatorNoOp, type ICodecOptions } from "../codec/index.js";
import {
	DetachedFieldIndex,
	TreeNavigationResult,
	TreeStoredSchemaRepository,
	applyDelta,
	combineVisitors,
	makeDetachedFieldIndex,
	makeDetachedNodeId,
	moveToDetachedField,
	rootFieldKey,
	type Anchor,
	type ChangesetLocalId,
	type DeltaDetachedNodeId,
	type DeltaFieldMap,
	type DeltaRoot,
	type DetachedField,
	type FieldKey,
	type MapTree,
	type RevisionTag,
	type TreeChunk,
	type UpPath,
} from "../core/index.js";
import {
	chunkField,
	combineChunks,
	cursorForMapTreeField,
	defaultChunkPolicy,
	mapTreeFromCursor,
	schemaCodecBuilder,
} from "../feature-libraries/index.js";
import { ObjectForest } from "../feature-libraries/object-forest/objectForest.js";
import {
	extractPersistedSchema,
	type ImplicitFieldSchema,
	SchemaFactory,
} from "../simple-tree/index.js";
import { brand } from "../util/index.js";
import { buildTestForest, forestWithContent } from "./utils.js";

const formatVersion = 1;
const packageName = "@fluidframework/tree";
const packageVersion = "3.1.0";
const expectedCommit = "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960";
const stringLeaf = "com.fluidframework.leaf.string";
const numberLeaf = "com.fluidframework.leaf.number";
const booleanLeaf = "com.fluidframework.leaf.boolean";
const nullLeaf = "com.fluidframework.leaf.null";
const rootType = "org.watershed.shared-tree.m1.Root";
const pointType = "org.watershed.shared-tree.m1.Point";
const keyProbeType = "org.watershed.shared-tree.m1.KeyProbe";

type Atom = { revision: string | null; localId: number };
type TaggedValue =
	| { kind: "string"; value: string }
	| { kind: "number"; value: number }
	| { kind: "boolean"; value: boolean }
	| { kind: "null" }
	| { kind: "object"; type: string; fields: [string, TaggedValue][] };
type FieldMap = [string, { marks: Mark[] }][];
type Mark = {
	count: number;
	attach: Atom | null;
	detach: Atom | null;
	fields: FieldMap;
};
type Build = { id: Atom; trees: TaggedValue[] };
type DeltaInput = {
	latestRevision: string | null;
	fields: FieldMap;
	build: Build[];
	refreshers: Build[];
	global: { id: Atom; fields: FieldMap }[];
	rename: { oldId: Atom; newId: Atom; count: number }[];
	destroy: { id: Atom; count: number }[];
};
type Action =
	| { id: string; op: "retain"; name: string; path: string[] }
	| { id: string; op: "retainDetached"; name: string; atom: Atom }
	| { id: string; op: "apply"; delta: DeltaInput }
	| { id: string; op: "observe" }
	| { id: string; op: "copy" };
type Scenario = {
	id: string;
	schema: string;
	root: TaggedValue | null;
	actions: Action[];
};
type Checkpoint = {
	id: string;
	accepted: boolean;
	state: ForestState | null;
};
type ForestState = {
	root: TaggedValue | null;
	references: {
		name: string;
		status: "attached" | "detached" | "destroyed" | "invalidated-by-copy";
		value: TaggedValue | null;
	}[];
	detached: {
		id: Atom;
		forestRootId: number;
		latestRelevantRevision: string | null;
		value: TaggedValue;
	}[];
	nextDetachedRootId: number;
};
type RawAction = {
	id: string;
	forest: object;
	detachedIndex: object[];
	delta?: object;
	error?: string;
	postFailureState?: {
		forest: object;
		detachedIndex: object[];
	};
};

function taggedString(value: string): TaggedValue {
	return { kind: "string", value };
}

function taggedNumber(value: number): TaggedValue {
	return { kind: "number", value };
}

function taggedBoolean(value: boolean): TaggedValue {
	return { kind: "boolean", value };
}

function taggedNull(): TaggedValue {
	return { kind: "null" };
}

function taggedObject(type: string, fields: [string, TaggedValue][]): TaggedValue {
	return { kind: "object", type, fields };
}

function point(x: number, y: number): TaggedValue {
	return taggedObject(pointType, [["x", taggedNumber(x)], ["y", taggedNumber(y)]]);
}

function root(pointValue = point(1, 2), note?: string): TaggedValue {
	const fields: [string, TaggedValue][] = [
		["title", taggedString("root")],
		["enabled", taggedBoolean(true)],
		["rating", taggedNumber(3.5)],
		["marker", taggedNull()],
		["point", pointValue],
	];
	if (note !== undefined) fields.push(["note", taggedString(note)]);
	return taggedObject(rootType, fields);
}

function keyProbe(empty: string, water: string): TaggedValue {
	return taggedObject(keyProbeType, [["", taggedString(empty)], ["水", taggedString(water)]]);
}

function atom(revision: string | null, localId: number): Atom {
	return { revision, localId };
}

function mark(
	count: number,
	attach: Atom | null = null,
	detach: Atom | null = null,
	fields: FieldMap = [],
): Mark {
	return { count, attach, detach, fields };
}

function field(name: string, marks: Mark[]): FieldMap {
	return [[name, { marks }]];
}

function nested(name: string, marks: Mark[]): FieldMap {
	return field("rootFieldKey", [mark(1, null, null, field(name, marks))]);
}

function delta(
	latestRevision: string | null,
	parts: Partial<Omit<DeltaInput, "latestRevision">>,
): DeltaInput {
	return {
		latestRevision,
		fields: [],
		build: [],
		refreshers: [],
		global: [],
		rename: [],
		destroy: [],
		...parts,
	};
}

function schemaString(schema: ImplicitFieldSchema): string {
	return JSON.stringify(extractPersistedSchema(
		schema,
		FluidClientVersion.v2_117,
		() => false,
	));
}

function mapTree(value: TaggedValue): MapTree {
	switch (value.kind) {
		case "string":
			return { type: brand(stringLeaf), value: value.value, fields: new Map() };
		case "number":
			return { type: brand(numberLeaf), value: value.value, fields: new Map() };
		case "boolean":
			return { type: brand(booleanLeaf), value: value.value, fields: new Map() };
		case "null":
			return { type: brand(nullLeaf), value: null, fields: new Map() };
		case "object":
			return {
				type: brand(value.type),
				fields: new Map(value.fields.map(([key, child]) => [brand(key), [mapTree(child)]])),
			};
	}
}

function compareText(left: string, right: string): number {
	return Buffer.compare(Buffer.from(left), Buffer.from(right));
}

function taggedTree(tree: MapTree): TaggedValue {
	const type = String(tree.type);
	switch (type) {
		case stringLeaf: {
			const value = tree.value;
			assert(typeof value === "string");
			return taggedString(value);
		}
		case numberLeaf: {
			const value = tree.value;
			assert(typeof value === "number");
			return taggedNumber(value);
		}
		case booleanLeaf: {
			const value = tree.value;
			assert(typeof value === "boolean");
			return taggedBoolean(value);
		}
		case nullLeaf:
			assert.equal(tree.value, null);
			return taggedNull();
		default: {
			const fields: [string, TaggedValue][] = [];
			for (const [key, children] of tree.fields) {
				assert.equal(children.length, 1, "The fixed object schema uses singleton fields");
				fields.push([String(key), taggedTree(children[0])]);
			}
			fields.sort(([left], [right]) => compareText(left, right));
			return taggedObject(type, fields);
		}
	}
}

function stableRevision(compressor: IIdCompressor): StableId {
	return compressor.decompress(compressor.generateCompressedId());
}

function revisionTag(value: string | null, compressor: IIdCompressor): RevisionTag | undefined {
	return value === null ? undefined : compressor.recompress(assertIsStableId(value));
}

function detachedId(value: Atom, compressor: IIdCompressor): DeltaDetachedNodeId {
	return makeDetachedNodeId(
		revisionTag(value.revision, compressor),
		brand<ChangesetLocalId>(value.localId),
	);
}

function stableAtom(value: DeltaDetachedNodeId, compressor: IIdCompressor): Atom {
	assert(value.major !== "root");
	return {
		revision: value.major === undefined ? null : compressor.decompress(value.major),
		localId: value.minor,
	};
}

function treeChunk(trees: TaggedValue[], compressor: IIdCompressor): TreeChunk {
	const cursor = cursorForMapTreeField(trees.map(mapTree));
	return combineChunks(chunkField(cursor, { policy: defaultChunkPolicy, idCompressor: compressor }));
}

function translateFields(input: FieldMap, compressor: IIdCompressor): DeltaFieldMap {
	return new Map(input.map(([key, changes]) => [
		brand<FieldKey>(key),
		{
			marks: changes.marks.map((item) => ({
				count: item.count,
				...(item.attach === null ? {} : { attach: detachedId(item.attach, compressor) }),
				...(item.detach === null ? {} : { detach: detachedId(item.detach, compressor) }),
				...(item.fields.length === 0 ? {} : { fields: translateFields(item.fields, compressor) }),
			})),
		},
	]));
}

function translateDelta(input: DeltaInput, compressor: IIdCompressor): {
	delta: DeltaRoot;
	latestRevision: RevisionTag | undefined;
	raw: object;
} {
	const fields = translateFields(input.fields, compressor);
	const build = input.build.map((item) => ({
		id: detachedId(item.id, compressor),
		trees: treeChunk(item.trees, compressor),
	}));
	const refreshers = input.refreshers.map((item) => ({
		id: detachedId(item.id, compressor),
		trees: treeChunk(item.trees, compressor),
	}));
	const global = input.global.map((item) => ({
		id: detachedId(item.id, compressor),
		fields: translateFields(item.fields, compressor),
	}));
	const rename = input.rename.map((item) => ({
		oldId: detachedId(item.oldId, compressor),
		newId: detachedId(item.newId, compressor),
		count: item.count,
	}));
	const destroy = input.destroy.map((item) => ({
		id: detachedId(item.id, compressor),
		count: item.count,
	}));
	const latestRevision = revisionTag(input.latestRevision, compressor);
	const translated: DeltaRoot = {
		...(fields.size === 0 ? {} : { fields }),
		...(build.length === 0 ? {} : { build }),
		...(refreshers.length === 0 ? {} : { refreshers }),
		...(global.length === 0 ? {} : { global }),
		...(rename.length === 0 ? {} : { rename }),
		...(destroy.length === 0 ? {} : { destroy }),
	};
	const rawAtom = (value: DeltaDetachedNodeId) => ({
		major: value.major ?? null,
		minor: value.minor,
	});
	const rawFields = (value: DeltaFieldMap): object[] => [...value].map(([key, changes]) => [
		key,
		{
			marks: changes.marks.map((item) => ({
				count: item.count,
				attach: item.attach === undefined ? null : rawAtom(item.attach),
				detach: item.detach === undefined ? null : rawAtom(item.detach),
				fields: item.fields === undefined ? [] : rawFields(item.fields),
			})),
		},
	]);
	return {
		delta: translated,
		latestRevision,
		raw: {
			latestRevision: latestRevision ?? null,
			fields: rawFields(fields),
			build: build.map((item, index) => ({ id: rawAtom(item.id), trees: input.build[index].trees })),
			refreshers: refreshers.map((item, index) => ({
				id: rawAtom(item.id),
				trees: input.refreshers[index].trees,
			})),
			global: global.map((item) => ({ id: rawAtom(item.id), fields: rawFields(item.fields) })),
			rename: rename.map((item) => ({
				oldId: rawAtom(item.oldId),
				newId: rawAtom(item.newId),
				count: item.count,
			})),
			destroy: destroy.map((item) => ({ id: rawAtom(item.id), count: item.count })),
		},
	};
}

function topField(path: UpPath): FieldKey {
	let current = path;
	while (current.parent !== undefined) current = current.parent;
	return current.parentField;
}

function rawForest(forest: ObjectForest): object {
	return {
		fields: [...forest.roots.fields]
			.map(([key, trees]) => [String(key), trees.map(taggedTree)] as const)
			.sort(([left], [right]) => compareText(left, right)),
	};
}

function rawDetachedIndex(index: DetachedFieldIndex): object[] {
	return [...index.entries()].map((entry) => ({
		id: {
			major: entry.id.major ?? null,
			minor: entry.id.minor,
		},
		root: entry.root,
		latestRelevantRevision: entry.latestRelevantRevision ?? null,
	}));
}

function readRoot(forest: ObjectForest): TaggedValue | null {
	const cursor = forest.allocateCursor("watershed forest root observation");
	try {
		moveToDetachedField(forest, cursor);
		if (!cursor.firstNode()) return null;
		const value = taggedTree(mapTreeFromCursor(cursor));
		assert.equal(cursor.nextNode(), false, "The fixed schema root has at most one node");
		return value;
	} finally {
		cursor.free();
	}
}

function readDetached(
	forest: ObjectForest,
	index: DetachedFieldIndex,
	id: DeltaDetachedNodeId,
): TaggedValue {
	const root = index.getEntry(id);
	const cursor = forest.allocateCursor("watershed detached observation");
	try {
		moveToDetachedField(forest, cursor, brand<DetachedField>(index.toFieldKey(root)));
		assert(cursor.firstNode(), "The detached field must contain one node");
		const value = taggedTree(mapTreeFromCursor(cursor));
		assert.equal(cursor.nextNode(), false, "The detached field must contain one node");
		return value;
	} finally {
		cursor.free();
	}
}

function errorText(error: unknown): string {
	return error instanceof Error ? `${error.name}: ${error.message}` : String(error);
}

function runScenario(
	scenario: Scenario,
	compressor: IIdCompressor,
	decoder: ReturnType<typeof schemaCodecBuilder.buildDecoder>,
): { observation: { id: string; checkpoints: Checkpoint[] }; raw: { id: string; actions: RawAction[] } } {
	const stored = decoder.decode(JSON.parse(scenario.schema));
	const schema = new TreeStoredSchemaRepository(stored);
	const initial = scenario.root === null ? [] : [mapTree(scenario.root)];
	const initialForest = forestWithContent({ schema: stored, initialTree: cursorForMapTreeField(initial) });
	assert(initialForest instanceof ObjectForest);
	let forest = initialForest;
	let index = makeDetachedFieldIndex(`watershed-${scenario.id}`);
	let generation = 0;
	const references = new Map<string, { anchor: Anchor; generation: number }>();
	const checkpoints: Checkpoint[] = [];
	const rawActions: RawAction[] = [];

	function observe(): ForestState {
		const referenceState = [...references]
			.sort(([left], [right]) => compareText(left, right))
			.map(([name, retained]) => {
				if (retained.generation !== generation) {
					return { name, status: "invalidated-by-copy" as const, value: null };
				}
				const cursor = forest.allocateCursor(`watershed retained ${name}`);
				try {
					const result = forest.tryMoveCursorToNode(retained.anchor, cursor);
					if (result === TreeNavigationResult.NotFound) {
						return { name, status: "destroyed" as const, value: null };
					}
					assert.equal(result, TreeNavigationResult.Ok);
					const path = cursor.getPath();
					assert(path !== undefined);
					return {
						name,
						status: topField(path) === rootFieldKey ? "attached" as const : "detached" as const,
						value: taggedTree(mapTreeFromCursor(cursor)),
					};
				} finally {
					cursor.free();
				}
			});
		const detached = [...index.entries()].map((entry) => ({
			id: stableAtom(entry.id, compressor),
			forestRootId: entry.root,
			latestRelevantRevision: (() => {
				assert(entry.latestRelevantRevision !== "root");
				return entry.latestRelevantRevision === undefined
					? null
					: compressor.decompress(entry.latestRelevantRevision);
			})(),
			value: readDetached(forest, index, entry.id),
		}));
		detached.sort((left, right) => {
			const revisionOrder = compareText(left.id.revision ?? "", right.id.revision ?? "");
			return revisionOrder === 0 ? left.id.localId - right.id.localId : revisionOrder;
		});
		return {
			root: readRoot(forest),
			references: referenceState,
			detached,
			nextDetachedRootId: index.getSummaryData().maxId + 1,
		};
	}

	function rawState() {
		return {
			forest: rawForest(forest),
			detachedIndex: rawDetachedIndex(index),
		};
	}

	for (const action of scenario.actions) {
		let accepted = true;
		let rawDelta: object | undefined;
		let error: string | undefined;
		if (action.op === "retain") {
			let path: UpPath = { parent: undefined, parentField: rootFieldKey, parentIndex: 0 };
			for (const key of action.path) {
				path = { parent: path, parentField: brand(key), parentIndex: 0 };
			}
			const cursor = forest.allocateCursor(`watershed retain ${action.name}`);
			try {
				forest.moveCursorToPath(path, cursor);
				references.set(action.name, { anchor: cursor.buildAnchor(), generation });
			} finally {
				cursor.free();
			}
		} else if (action.op === "retainDetached") {
			const id = detachedId(action.atom, compressor);
			const root = index.getEntry(id);
			const cursor = forest.allocateCursor(`watershed retain detached ${action.name}`);
			try {
				moveToDetachedField(forest, cursor, brand<DetachedField>(index.toFieldKey(root)));
				assert(cursor.firstNode());
				references.set(action.name, { anchor: cursor.buildAnchor(), generation });
			} finally {
				cursor.free();
			}
		} else if (action.op === "apply") {
			const translated = translateDelta(action.delta, compressor);
			rawDelta = translated.raw;
			try {
				applyDelta(
					translated.delta,
					translated.latestRevision,
					{
						acquireVisitor: () => combineVisitors([
							forest.acquireVisitor(),
							forest.anchors.acquireVisitor(),
						]),
					},
					index,
				);
			} catch (caught) {
				accepted = false;
				error = errorText(caught);
			}
		} else if (action.op === "copy") {
			const copied = buildTestForest({
				additionalAsserts: true,
				schema,
				roots: forest.roots,
			});
			assert(copied instanceof ObjectForest);
			forest = copied;
			index = index.clone();
			generation += 1;
		}

		const raw = rawState();
		rawActions.push({
			id: action.id,
			...raw,
			...(rawDelta === undefined ? {} : { delta: rawDelta }),
			...(accepted ? {} : { error, postFailureState: raw }),
		});
		checkpoints.push({
			id: action.id,
			accepted,
			state: accepted ? observe() : null,
		});
		if (!accepted) break;
	}

	return {
		observation: { id: scenario.id, checkpoints },
		raw: { id: scenario.id, actions: rawActions },
	};
}

function checkpoint(
	observations: { id: string; checkpoints: Checkpoint[] }[],
	scenario: string,
	action: string,
): Checkpoint {
	const result = observations
		.find((item) => item.id === scenario)
		?.checkpoints.find((item) => item.id === action);
	assert(result !== undefined, `Missing checkpoint ${scenario}.${action}`);
	return result;
}

function acceptedState(
	observations: { id: string; checkpoints: Checkpoint[] }[],
	scenario: string,
	action: string,
): ForestState {
	const result = checkpoint(observations, scenario, action);
	assert.equal(result.accepted, true);
	assert(result.state !== null);
	return result.state;
}

function objectRoot(state: ForestState): Extract<TaggedValue, { kind: "object" }> {
	assert(state.root?.kind === "object");
	return state.root;
}

if (process.env.WATERSHED_ORACLE_CORPUS === "1") {
	describe("Watershed forest oracle", () => {
		it("records persistent forest and delta behavior", () => {
			const output = process.env.WATERSHED_ORACLE_OUTPUT;
			assert(output !== undefined && isAbsolute(output), "An absolute output directory is required");
			assert.equal(process.env.WATERSHED_ORACLE_COMMIT, expectedCommit);

			const compressor = createAlwaysFinalizedIdCompressor();
			const revisions = {
				first: stableRevision(compressor),
				second: stableRevision(compressor),
				third: stableRevision(compressor),
			};
			const schemaFactory = new SchemaFactory("org.watershed.shared-tree.m1");
			class Point extends schemaFactory.object("Point", {
				x: schemaFactory.number,
				y: schemaFactory.number,
			}) {}
			class Root extends schemaFactory.object("Root", {
				title: schemaFactory.string,
				enabled: schemaFactory.boolean,
				rating: schemaFactory.number,
				marker: schemaFactory.null,
				note: schemaFactory.optional(schemaFactory.string),
				point: Point,
			}) {}
			class KeyProbe extends schemaFactory.object("KeyProbe", {
				"": schemaFactory.string,
				水: schemaFactory.string,
			}) {}
			const primitiveSchema = new SchemaFactory("org.watershed.shared-tree.primitives");
			const schemas = {
				root: schemaString(Root),
				keyProbe: schemaString(KeyProbe),
				primitives: schemaString(primitiveSchema.optional([
					primitiveSchema.string,
					primitiveSchema.number,
					primitiveSchema.boolean,
					primitiveSchema.null,
				])),
			};
			const a = (localId: number) => atom(revisions.first, localId);
			const b = (localId: number) => atom(revisions.second, localId);
			const c = (localId: number) => atom(revisions.third, localId);
			const anonymous = (localId: number) => atom(null, localId);
			const scenarios: Scenario[] = [
				{
					id: "primitives-and-optional-root",
					schema: schemas.primitives,
					root: null,
					actions: [
						{ id: "absent", op: "observe" },
						{ id: "string", op: "apply", delta: delta(revisions.first, {
							build: [{ id: a(0), trees: [taggedString("first")] }],
							fields: field("rootFieldKey", [mark(1, a(0))]),
						}) },
						{ id: "number", op: "apply", delta: delta(revisions.first, {
							build: [{ id: a(1), trees: [taggedNumber(2.5)] }],
							fields: field("rootFieldKey", [mark(1, a(1), anonymous(0))]),
							destroy: [{ id: anonymous(0), count: 1 }],
						}) },
						{ id: "boolean", op: "apply", delta: delta(revisions.second, {
							build: [{ id: b(0), trees: [taggedBoolean(false)] }],
							fields: field("rootFieldKey", [mark(1, b(0), anonymous(1))]),
							destroy: [{ id: anonymous(1), count: 1 }],
						}) },
						{ id: "null", op: "apply", delta: delta(revisions.third, {
							build: [{ id: c(0), trees: [taggedNull()] }],
							fields: field("rootFieldKey", [mark(1, c(0), anonymous(2))]),
							destroy: [{ id: anonymous(2), count: 1 }],
						}) },
					],
				},
				{
					id: "optional-field-set-clear",
					schema: schemas.root,
					root: root(),
					actions: [
						{ id: "retain-root", op: "retain", name: "root", path: [] },
						{ id: "set-note", op: "apply", delta: delta(revisions.first, {
							build: [{ id: a(10), trees: [taggedString("note")] }],
							fields: nested("note", [mark(1, a(10))]),
						}) },
						{ id: "retain-note", op: "retain", name: "note", path: ["note"] },
						{ id: "clear-note", op: "apply", delta: delta(revisions.second, {
							fields: nested("note", [mark(1, null, b(10))]),
						}) },
						{ id: "observe-cleared", op: "observe" },
						{ id: "readd-note", op: "apply", delta: delta(revisions.third, {
							fields: nested("note", [mark(1, b(10))]),
						}) },
					],
				},
				{
					id: "unicode-field-keys",
					schema: schemas.keyProbe,
					root: keyProbe("", "海"),
					actions: [
						{ id: "replace-fields", op: "apply", delta: delta(revisions.first, {
							build: [
								{ id: a(20), trees: [taggedString("empty-key")] },
								{ id: a(21), trees: [taggedString("水🌊")] },
							],
							fields: field("rootFieldKey", [mark(1, null, null, [
								["水", { marks: [mark(1, a(21), anonymous(21))] }],
								["", { marks: [mark(1, a(20), anonymous(20))] }],
							])]),
							destroy: [
								{ id: anonymous(20), count: 1 },
								{ id: anonymous(21), count: 1 },
							],
						}) },
						{ id: "observe-order", op: "observe" },
					],
				},
				{
					id: "replacement-retained-child",
					schema: schemas.root,
					root: root(),
					actions: [
						{ id: "retain-original", op: "retain", name: "original", path: ["point"] },
						{ id: "replace-point", op: "apply", delta: delta(revisions.first, {
							build: [{ id: a(30), trees: [point(10, 20)] }],
							fields: nested("point", [mark(1, a(30), a(31))]),
						}) },
						{ id: "edit-detached-x", op: "apply", delta: delta(revisions.second, {
							build: [{ id: b(30), trees: [taggedNumber(42)] }],
							global: [{ id: a(31), fields: field("x", [mark(1, b(30), b(31))]) }],
							destroy: [{ id: b(31), count: 1 }],
						}) },
					],
				},
				{
					id: "nested-replacement-old-child",
					schema: schemas.root,
					root: root(),
					actions: [
						{ id: "retain-original", op: "retain", name: "original", path: ["point"] },
						{ id: "replace-and-edit-old", op: "apply", delta: delta(revisions.first, {
							build: [
								{ id: a(40), trees: [point(10, 20)] },
								{ id: a(41), trees: [taggedNumber(7)] },
							],
							fields: nested("point", [
								mark(1, a(40), a(42), field("x", [mark(1, a(41), anonymous(40))])),
							]),
							destroy: [{ id: anonymous(40), count: 1 }],
						}) },
					],
				},
				{
					id: "reattach-keeps-identity",
					schema: schemas.root,
					root: root(),
					actions: [
						{ id: "retain-original", op: "retain", name: "original", path: ["point"] },
						{ id: "detach-original", op: "apply", delta: delta(revisions.first, {
							build: [{ id: a(50), trees: [point(10, 20)] }],
							fields: nested("point", [mark(1, a(50), a(51))]),
						}) },
						{ id: "reattach-original", op: "apply", delta: delta(revisions.second, {
							fields: nested("point", [mark(1, a(51), b(50))]),
						}) },
					],
				},
				{
					id: "detached-range-build",
					schema: schemas.root,
					root: root(),
					actions: [
						{ id: "build-range", op: "apply", delta: delta(revisions.first, {
							build: [{
								id: a(60),
								trees: [taggedNumber(1), taggedString("two"), taggedBoolean(true)],
							}],
						}) },
						{ id: "attach-middle", op: "apply", delta: delta(revisions.second, {
							fields: nested("note", [mark(1, a(61))]),
						}) },
					],
				},
				{
					id: "rename-chain-and-self",
					schema: schemas.root,
					root: root(),
					actions: [
						{ id: "build-chain", op: "apply", delta: delta(revisions.first, {
							build: [
								{ id: a(70), trees: [taggedString("first")] },
								{ id: a(71), trees: [point(4, 5)] },
							],
						}) },
						{ id: "rename-chain", op: "apply", delta: delta(revisions.second, {
							build: [{ id: b(70), trees: [taggedNumber(9)] }],
							global: [{ id: a(71), fields: field("x", [mark(1, b(70), b(71))]) }],
							rename: [
								{ oldId: a(71), newId: a(72), count: 1 },
								{ oldId: a(70), newId: a(71), count: 1 },
								{ oldId: a(72), newId: a(72), count: 1 },
							],
							destroy: [{ id: b(71), count: 1 }],
						}) },
					],
				},
				{
					id: "rename-cycle-refused",
					schema: schemas.root,
					root: root(),
					actions: [
						{ id: "build-cycle", op: "apply", delta: delta(revisions.first, {
							build: [
								{ id: a(80), trees: [taggedString("a")] },
								{ id: a(81), trees: [taggedString("b")] },
							],
						}) },
						{ id: "refuse-cycle", op: "apply", delta: delta(revisions.second, {
							rename: [
								{ oldId: a(80), newId: a(81), count: 1 },
								{ oldId: a(81), newId: a(80), count: 1 },
							],
						}) },
					],
				},
				{
					id: "duplicate-build-refused",
					schema: schemas.root,
					root: root(),
					actions: [
						{ id: "build-once", op: "apply", delta: delta(revisions.first, {
							build: [{ id: a(90), trees: [taggedString("first")] }],
						}) },
						{ id: "refuse-duplicate", op: "apply", delta: delta(revisions.second, {
							build: [{ id: a(90), trees: [taggedString("second")] }],
						}) },
					],
				},
				{
					id: "refreshers",
					schema: schemas.root,
					root: root(),
					actions: [
						{ id: "build-existing", op: "apply", delta: delta(revisions.first, {
							build: [{ id: a(100), trees: [taggedString("existing")] }],
						}) },
						{ id: "use-refreshers", op: "apply", delta: delta(revisions.second, {
							build: [{ id: b(100), trees: [taggedNumber(77)] }],
							refreshers: [
								{ id: a(100), trees: [taggedString("replacement-must-not-win")] },
								{ id: a(101), trees: [point(5, 6)] },
								{ id: a(102), trees: [taggedString("from-refresher")] },
								{ id: a(103), trees: [taggedBoolean(true)] },
								{ id: a(104), trees: [taggedString("unused")] },
							],
							global: [{
								id: a(101),
								fields: field("x", [mark(1, b(100), b(101))]),
							}],
							fields: nested("note", [mark(1, a(102))]),
							rename: [{ oldId: a(103), newId: a(105), count: 1 }],
							destroy: [{ id: b(101), count: 1 }],
						}) },
					],
				},
				{
					id: "destroy-and-revision-metadata",
					schema: schemas.root,
					root: root(),
					actions: [
						{ id: "retain-original", op: "retain", name: "original", path: ["point"] },
						{ id: "detach", op: "apply", delta: delta(revisions.first, {
							build: [{ id: a(110), trees: [point(10, 20)] }],
							fields: nested("point", [mark(1, a(110), a(111))]),
						}) },
						{ id: "update-revision", op: "apply", delta: delta(revisions.second, {
							build: [{ id: b(110), trees: [taggedNumber(8)] }],
							global: [{ id: a(111), fields: field("x", [mark(1, b(110), b(111))]) }],
							destroy: [{ id: b(111), count: 1 }],
						}) },
						{ id: "destroy", op: "apply", delta: delta(revisions.third, {
							destroy: [{ id: a(111), count: 1 }],
						}) },
					],
				},
				{
					id: "copy-retains-detached",
					schema: schemas.root,
					root: root(),
					actions: [
						{ id: "retain-original", op: "retain", name: "before-copy", path: ["point"] },
						{ id: "detach", op: "apply", delta: delta(revisions.first, {
							build: [{ id: a(120), trees: [point(10, 20)] }],
							fields: nested("point", [mark(1, a(120), a(121))]),
						}) },
						{ id: "edit-detached", op: "apply", delta: delta(revisions.second, {
							build: [{ id: b(120), trees: [taggedNumber(33)] }],
							global: [{ id: a(121), fields: field("x", [mark(1, b(120), b(121))]) }],
							destroy: [{ id: b(121), count: 1 }],
						}) },
						{ id: "copy", op: "copy" },
						{
							id: "retain-copied",
							op: "retainDetached",
							name: "copied-detached",
							atom: a(121),
						},
						{ id: "reattach-copied", op: "apply", delta: delta(revisions.third, {
							fields: nested("point", [mark(1, a(121), c(120))]),
						}) },
					],
				},
				{
					id: "missing-attach-source-refused",
					schema: schemas.root,
					root: root(),
					actions: [
						{ id: "refuse-missing-attach", op: "apply", delta: delta(revisions.first, {
							fields: nested("note", [mark(1, a(130))]),
						}) },
					],
				},
				{
					id: "missing-global-source-refused",
					schema: schemas.root,
					root: root(),
					actions: [
						{ id: "refuse-missing-global", op: "apply", delta: delta(revisions.first, {
							global: [{ id: a(140), fields: field("x", [mark(1)]) }],
						}) },
					],
				},
				{
					id: "missing-rename-source-refused",
					schema: schemas.root,
					root: root(),
					actions: [
						{ id: "refuse-missing-rename", op: "apply", delta: delta(revisions.first, {
							rename: [{ oldId: a(150), newId: a(151), count: 1 }],
						}) },
					],
				},
			];

			const decoder = schemaCodecBuilder.buildDecoder({
				jsonValidator: FormatValidatorNoOp,
			} satisfies ICodecOptions);
			const runs = scenarios.map((scenario) => runScenario(scenario, compressor, decoder));
			const observations = runs.map(({ observation }) => observation);
			const raw = runs.map((run) => run.raw);

			assert.equal(acceptedState(observations, "primitives-and-optional-root", "absent").root, null);
			assert.deepEqual(
				["string", "number", "boolean", "null"].map((id) =>
					acceptedState(observations, "primitives-and-optional-root", id).root?.kind),
				["string", "number", "boolean", "null"],
			);
			const optionalCleared = acceptedState(observations, "optional-field-set-clear", "observe-cleared");
			assert(!objectRoot(optionalCleared).fields.some(([key]) => key === "note"));
			const optionalReadded = acceptedState(observations, "optional-field-set-clear", "readd-note");
			assert(objectRoot(optionalReadded).fields.some(([key, value]) =>
				key === "note" && value.kind === "string" && value.value === "note"));
			assert.deepEqual(
				acceptedState(observations, "unicode-field-keys", "observe-order").root,
				keyProbe("empty-key", "水🌊"),
			);
			const retained = acceptedState(
				observations,
				"replacement-retained-child",
				"edit-detached-x",
			);
			assert.deepEqual(objectRoot(retained).fields.find(([key]) => key === "point")?.[1], point(10, 20));
			assert.deepEqual(retained.references[0], {
				name: "original",
				status: "detached",
				value: point(42, 2),
			});
			const nestedOld = acceptedState(
				observations,
				"nested-replacement-old-child",
				"replace-and-edit-old",
			);
			assert.deepEqual(nestedOld.references[0].value, point(7, 2));
			assert.deepEqual(objectRoot(nestedOld).fields.find(([key]) => key === "point")?.[1], point(10, 20));
			assert.equal(
				acceptedState(observations, "reattach-keeps-identity", "reattach-original")
					.references[0].status,
				"attached",
			);
			assert.deepEqual(
				acceptedState(observations, "detached-range-build", "attach-middle")
					.detached.map(({ id }) => id.localId),
				[60, 62],
			);
			const renamed = acceptedState(observations, "rename-chain-and-self", "rename-chain");
			assert.deepEqual(renamed.detached.map(({ id }) => id.localId), [71, 72]);
			assert.deepEqual(renamed.detached.find(({ id }) => id.localId === 72)?.value, point(9, 5));
			for (const [scenario, action] of [
				["rename-cycle-refused", "refuse-cycle"],
				["duplicate-build-refused", "refuse-duplicate"],
				["missing-attach-source-refused", "refuse-missing-attach"],
				["missing-global-source-refused", "refuse-missing-global"],
				["missing-rename-source-refused", "refuse-missing-rename"],
			]) {
				const refused = checkpoint(observations, scenario, action);
				assert.equal(refused.accepted, false);
				assert.equal(refused.state, null);
			}
			const refreshed = acceptedState(observations, "refreshers", "use-refreshers");
			assert(refreshed.detached.some(({ id, value }) =>
				id.localId === 100 && value.kind === "string" && value.value === "existing"));
			assert(refreshed.detached.some(({ id, value }) =>
				id.localId === 101 && value.kind === "object"
				&& value.fields.some(([key, child]) =>
					key === "x" && child.kind === "number" && child.value === 77)));
			assert(refreshed.detached.some(({ id }) => id.localId === 105));
			assert(!refreshed.detached.some(({ id }) => id.localId === 104));
			const revised = acceptedState(
				observations,
				"destroy-and-revision-metadata",
				"update-revision",
			);
			assert.equal(revised.detached[0].latestRelevantRevision, revisions.second);
			const destroyed = acceptedState(observations, "destroy-and-revision-metadata", "destroy");
			assert.equal(destroyed.references[0].status, "destroyed");
			assert.equal(destroyed.detached.length, 0);
			assert.equal(destroyed.nextDetachedRootId, revised.nextDetachedRootId);
			const copied = acceptedState(observations, "copy-retains-detached", "copy");
			assert.equal(copied.references[0].status, "invalidated-by-copy");
			assert.deepEqual(copied.detached[0].value, point(33, 2));
			const reattached = acceptedState(observations, "copy-retains-detached", "reattach-copied");
			assert.equal(
				reattached.references.find(({ name }) => name === "copied-detached")?.status,
				"attached",
			);

			const oracleCase = {
				formatVersion,
				reference: {
					package: packageName,
					version: packageVersion,
					commit: expectedCommit,
				},
				id: "forest-delta",
				domain: "forest",
				input: { scenarios },
				expected: { observations },
				raw: { scenarios: raw },
			};
			mkdirSync(output, { recursive: true });
			writeFileSync(
				join(output, "forest-cases.json"),
				`${JSON.stringify([oracleCase], null, 2)}\n`,
			);
		});
	});
}
