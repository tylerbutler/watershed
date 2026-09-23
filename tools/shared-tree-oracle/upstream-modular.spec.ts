/*!
 * Copyright (c) Microsoft Corporation and contributors. All rights reserved.
 * Licensed under the MIT License.
 */

import { strict as assert } from "node:assert";
import { readFileSync, writeFileSync } from "node:fs";
import { isAbsolute, join } from "node:path";
import type { SessionSpaceCompressedId } from "@fluidframework/id-compressor";
import { createIdCompressor, toIdCompressorWithCore } from "@fluidframework/id-compressor/internal";

import {
	revisionMetadataSourceFromInfo,
	rootFieldKey,
	tagChange,
	type ChangeAtomId,
	type DeltaDetachedNodeId,
	type DeltaFieldMap,
	type DeltaRoot,
	type FieldUpPath,
	type RevisionTag,
	type TaggedChange,
	type TreeChunk,
	type UpPath,
} from "../core/index.js";
import {
	DefaultEditBuilder,
	DefaultRevisionReplacer,
	intoDelta,
	mapTreeFromCursor,
	newChangeAtomIdBTree,
	relevantRemovedRoots,
	schemaCodecBuilder,
	updateRefreshers,
	type FieldChangeMap,
	type ModularChangeset,
} from "../feature-libraries/index.js";
import { FormatValidatorNoOp } from "../codec/index.js";
import type { NodeChangeset } from "../feature-libraries/modular-schema/modularChangeTypes.js";
import { pruneChangeset } from "../feature-libraries/modular-schema/prune.js";
import { makeModularChangeset, validateChangeset } from "../feature-libraries/modular-schema/modularChangeUtils.js";
import { fieldKinds } from "../feature-libraries/default-schema/defaultFieldKinds.js";
import type { GenericChangeset } from "../feature-libraries/modular-schema/genericFieldKindTypes.js";
import type { OptionalChangeset, RegisterId } from "../feature-libraries/optional-field/optionalFieldChangeTypes.js";
import { SchemaFactory } from "../simple-tree/index.js";
import { brand, unbrand } from "../util/index.js";
import { assertIsSessionId, mintRevisionTag, testIdCompressor } from "./utils.js";
import { makeModularFamily, withRootAndNestedChanges } from "./watershedAlgebra.spec.js";
import {
	root,
	runScenario,
	schemaString,
	taggedTree,
	treeChunk,
	type Atom,
	type DeltaInput,
	type Scenario,
	type TaggedValue,
} from "./watershedForest.spec.js";

const referenceCommit = "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960";
let revisionCompressor = testIdCompressor;
type ObservationCompressor = typeof testIdCompressor;

function revision(value: RevisionTag | undefined): string | null {
	if (value === undefined) return null;
	assert(typeof value === "number", "The modular profile requires compressed revision IDs");
	return revisionCompressor.decompress(value);
}

function withRevisionCompressor<T>(compressor: ObservationCompressor, run: () => T): T {
	const previous = revisionCompressor;
	revisionCompressor = compressor;
	try {
		return run();
	} finally {
		revisionCompressor = previous;
	}
}

function revisionTag(value: unknown): SessionSpaceCompressedId {
	assert(typeof value === "number" && Number.isSafeInteger(value));
	const tag = value as SessionSpaceCompressedId;
	testIdCompressor.decompress(tag);
	return tag;
}

function atom(value: ChangeAtomId): Atom {
	return { revision: revision(value.revision), localId: value.localId };
}

export function atomWithCompressor(value: ChangeAtomId, compressor: ObservationCompressor): Atom {
	return withRevisionCompressor(compressor, () => atom(value));
}

export function detachedWithCompressor(
	value: DeltaDetachedNodeId,
	compressor: ObservationCompressor,
): Atom {
	return withRevisionCompressor(compressor, () => detached(value));
}

function detached(value: DeltaDetachedNodeId): Atom {
	assert(value.major !== "root", "The modular profile excludes root revision sentinels");
	return { revision: revision(value.major), localId: value.minor };
}

function register(value: RegisterId): "active" | Atom {
	return value === "self" ? "active" : atom(value);
}

function content(chunk: TreeChunk): TaggedValue[] {
	const cursor = chunk.cursor();
	const trees: TaggedValue[] = [];
	for (let present = cursor.firstNode(); present; present = cursor.nextNode()) {
		trees.push(taggedTree(mapTreeFromCursor(cursor)));
	}
	return trees;
}

function fields(value: FieldChangeMap): object[] {
	return [...value].map(([key, field]) => {
		if (field.fieldKind === "ModularEditBuilder.Generic") {
			const changes = unbrand(field.change) as GenericChangeset;
			for (const [index] of changes.entries()) assert.equal(index, 0, "Only singleton Generic fields are supported");
			return [key, {
				kind: "Generic",
				children: [...changes.entries()].map(([index, child]) => [index, atom(child)]),
			}];
		}
		assert(field.fieldKind === "Value" || field.fieldKind === "Optional",
			`Unsupported modular field kind: ${field.fieldKind}`);
		const change = unbrand(field.change) as OptionalChangeset;
		return [key, {
			kind: field.fieldKind,
			moves: (change.moves ?? []).map(([source, target]) => [atom(source), atom(target)]),
			children: (change.childChanges ?? []).map(([source, child]) => [register(source), atom(child)]),
			replacement: change.valueReplace === undefined ? null : {
				wasEmpty: change.valueReplace.isEmpty,
				source: change.valueReplace.src === undefined ? null : register(change.valueReplace.src),
				detach: atom(change.valueReplace.dst),
			},
		}];
	});
}

function node(value: NodeChangeset): object {
	assert.equal(value.nodeExistsConstraint, undefined, "Node constraints are outside the profile");
	assert.equal(value.nodeExistsConstraintOnRevert, undefined, "Revert constraints are outside the profile");
	return { fields: fields(value.fieldChanges ?? new Map()) };
}

function structure(change: ModularChangeset): object {
	assert.equal(change.constraintViolationCount ?? 0, 0);
	assert.equal(change.noChangeConstraint, undefined, "Document constraints are outside the profile");
	assert.equal(change.noChangeConstraintOnRevert, undefined, "Revert constraints are outside the profile");
	assert.equal(change.crossFieldKeys.entries().length, 0, "Cross-field keys are outside the profile");
	const chunks = (entries: ModularChangeset["builds"]) => [...(entries?.entries() ?? [])]
		.map(([[revision, localId], chunk]) => ({ id: atom({ revision, localId }), trees: content(chunk) }));
	return {
		maxLocalId: change.maxId ?? -1,
		revisions: (change.revisions ?? []).map((info) => ({
			revision: revision(info.revision),
			rollbackOf: revision(info.rollbackOf),
		})),
		fields: fields(change.fieldChanges),
		nodes: [...change.nodeChanges.entries()].map(([[revision, localId], value]) =>
			[atom({ revision, localId }), node(value)]),
		parents: [...change.nodeToParent.entries()].map(([[revision, localId], value]) =>
			[atom({ revision, localId }), {
				parent: value.nodeId === undefined ? null : atom(value.nodeId),
				field: value.field,
			}]),
		aliases: [...change.nodeAliases.entries()].map(([[revision, localId], value]) =>
			[atom({ revision, localId }), atom(value)]),
		builds: chunks(change.builds),
		destroys: [...(change.destroys?.entries() ?? [])].map(([[revision, localId], count]) =>
			({ id: atom({ revision, localId }), count })),
		refreshers: chunks(change.refreshers),
	};
}

export function structureWithCompressor(
	change: ModularChangeset,
	compressor: ObservationCompressor,
): object {
	return withRevisionCompressor(compressor, () => structure(change));
}

function deltaFields(value: DeltaFieldMap | undefined): DeltaInput["fields"] {
	return [...(value ?? [])].map(([key, field]) => [key, {
		marks: field.marks.map((mark) => ({
			count: mark.count,
			attach: mark.attach === undefined ? null : detached(mark.attach),
			detach: mark.detach === undefined ? null : detached(mark.detach),
			fields: deltaFields(mark.fields),
		})),
	}]);
}

function deltaData(value: DeltaRoot, latest: RevisionTag | undefined): DeltaInput {
	return {
		latestRevision: revision(latest),
		fields: deltaFields(value.fields),
		build: (value.build ?? []).map((build) => ({ id: detached(build.id), trees: content(build.trees) })),
		refreshers: (value.refreshers ?? []).map((build) => ({
			id: detached(build.id), trees: content(build.trees),
		})),
		global: (value.global ?? []).map((change) => ({ id: detached(change.id), fields: deltaFields(change.fields) })),
		rename: (value.rename ?? []).map((rename) => ({
			oldId: detached(rename.oldId), newId: detached(rename.newId), count: rename.count,
		})),
		destroy: (value.destroy ?? []).map((destroy) => ({ id: detached(destroy.id), count: destroy.count })),
	};
}

export function deltaDataWithCompressor(
	value: DeltaRoot,
	latest: RevisionTag | undefined,
	compressor: ObservationCompressor,
): DeltaInput {
	return withRevisionCompressor(compressor, () => deltaData(value, latest));
}

function fieldPath(path: string[]): FieldUpPath {
	let parent: UpPath | undefined;
	let field = rootFieldKey;
	for (const key of path) {
		parent = { parent, parentField: field, parentIndex: 0 };
		field = brand(key);
	}
	return { parent, field };
}

function expand(
	first: ModularChangeset,
	second: ModularChangeset,
	revisionA: RevisionTag,
	revisionB: RevisionTag,
	revisionC: RevisionTag,
) {
	revisionCompressor = testIdCompressor;
	const { family, codecOptions } = makeModularFamily();
	const sf = new SchemaFactory("org.watershed.shared-tree.m1");
	class Point extends sf.object("Point", { x: sf.number, y: sf.number }) {}
	class Root extends sf.object("Root", {
		title: sf.string, enabled: sf.boolean, rating: sf.number, marker: sf.null,
		note: sf.optional(sf.string), point: Point,
	}) {}
	const schema = schemaString(Root);
	const changes = new Map<string, TaggedChange<ModularChangeset>>([
		["first", tagChange(first, revisionA)], ["second", tagChange(second, revisionB)],
	]);
	const inputs: object[] = [];
	const observations: object[] = [];
	const revisionD = mintRevisionTag();
	const revisions = [revisionA, revisionB, revisionC, revisionD];

	function get(name: string): TaggedChange<ModularChangeset> {
		const change = changes.get(name);
		assert(change !== undefined, `Unknown modular change: ${name}`);
		return change;
	}

	function record(id: string, change: TaggedChange<ModularChangeset>, extra: object = {}) {
		assert(!changes.has(id), `Repeated modular result: ${id}`);
		changes.set(id, change);
		observations.push({
			operation: "modular", id, accepted: true,
			change: structure(change.change),
			delta: deltaData(intoDelta(change), change.revision),
			...extra,
		});
	}

	function edit(
		id: string, editRevision: RevisionTag, path: string[], value: TaggedValue | null,
		optional = false, wasEmpty = false,
		initial: { schema: string; root: TaggedValue | null } = { schema, root: root() },
	) {
		inputs.push({ op: "edit", id, revision: revision(editRevision), ...initial, path, value });
		let authored: TaggedChange<ModularChangeset> | undefined;
		const editor = new DefaultEditBuilder(family, () => editRevision, (change) => {
			assert.equal(authored, undefined, "An edit must emit exactly one change");
			authored = change;
		}, codecOptions);
		const chunk = value === null ? undefined : treeChunk([value], revisionCompressor);
		if (optional) editor.optionalField(fieldPath(path)).set(chunk, wasEmpty);
		else {
			assert(chunk !== undefined, "A required field needs a value");
			editor.valueField(fieldPath(path)).set(chunk);
		}
		assert(authored !== undefined, "The editor must emit a change");
		record(id, authored);
	}

	function compose(id: string, names: string[]) {
		inputs.push({ op: "compose", id, changes: names });
		record(id, tagChange(family.compose(names.map(get)), undefined));
	}

	function invert(id: string, name: string, isRollback: boolean) {
		inputs.push({ op: "invert", id, change: name, isRollback,
			inverseRevision: revision(revisionC) });
		record(id, tagChange(family.invert(get(name), isRollback, revisionC), revisionC));
	}

	function rebase(id: string, name: string, over: string) {
		inputs.push({ op: "rebase", id, change: name, over,
			revisionMetadata: revisions.map((tag) => ({ revision: revision(tag), rollbackOf: null })) });
		const original = get(name);
		record(id, tagChange(family.rebase(
			original, get(over), revisionMetadataSourceFromInfo(revisions.map((revision) => ({ revision }))),
		), original.revision));
	}

	function replace(id: string, name: string, obsolete: RevisionTag[], danglingAlias = false) {
		inputs.push({ op: "replace-revisions", id, change: name,
			obsolete: obsolete.map(revision), updated: revision(revisionC) });
		const replaced = tagChange(family.changeRevision(
			get(name).change, new DefaultRevisionReplacer(revisionC, new Set(obsolete)),
		), revisionC);
		if (danglingAlias) {
			assert.throws(() => intoDelta(replaced), (error: unknown) =>
				error instanceof Error && error.message === "0x9ca");
			observations.push({ operation: "modular", id, accepted: false });
		} else record(id, replaced);
	}

	edit("child-x", revisionA, ["point", "x"], { kind: "number", value: 42 });
	edit("child-y", revisionB, ["point", "y"], { kind: "number", value: 9 });
	edit("parent", revisionB, ["point"], {
		kind: "object", type: Point.identifier,
		fields: [["x", { kind: "number", value: 10 }], ["y", { kind: "number", value: 20 }]],
	});
	edit("title", revisionC, ["title"], { kind: "string", value: "changed" });
	edit("optional-set", revisionD, ["note"], { kind: "string", value: "present" }, true, true);
	edit("optional-clear-empty", revisionB, ["note"], null, true, true);
	compose("nested-composed", ["child-x", "child-y"]);
	compose("three-composed", ["child-x", "child-y", "title"]);
	compose("four-composed", ["child-x", "child-y", "title", "optional-set"]);
	compose("synthetic-composed", ["first", "second"]);
	invert("child-rollback", "child-x", true);
	invert("child-undo", "child-x", false);
	invert("multi-rollback", "nested-composed", true);
	invert("multi-undo", "nested-composed", false);
	rebase("x-over-y", "child-x", "child-y");
	rebase("x-over-parent", "child-x", "parent");
	rebase("parent-over-x", "parent", "child-x");
	compose("parent-then-detached", ["parent", "x-over-parent"]);
	replace("collision-replaced", "nested-composed", [revisionA, revisionB]);
	replace("alias-replaced", "first", [revisionA, revisionB], true);
	inputs.push({ op: "prune", id: "pruned", change: "first" });
	record("pruned", tagChange(pruneChangeset(first, fieldKinds), revisionA));
	const roots = [...relevantRemovedRoots(first)];
	const repair = roots.map((id, index) => ({
		id: detached(id), trees: [{ kind: "string" as const, value: `repair-${index}` }],
	}));
	inputs.push({ op: "refreshers", id: "refreshed", change: "first",
		roots: roots.map(detached), repair });
	record("refreshed", tagChange(updateRefreshers(first, (id) => {
		const position = roots.findIndex((root) => root.major === id.major && root.minor === id.minor);
		assert(position >= 0);
		return treeChunk(repair[position].trees, testIdCompressor);
	}, roots), revisionA), { removedRoots: roots.map(detached) });
	compose("build-destroy-cancelled", ["child-x", "child-rollback"]);
	const optionalRoot = { schema: schemaString(sf.optional(sf.string)), root: null };
	const presentRoot = { schema: optionalRoot.schema, root: { kind: "string" as const, value: "before" } };
	const nullRoot = { schema: schemaString(sf.optional(sf.null)), root: null };
	edit("optional-root-set", revisionA, [], { kind: "string", value: "after" }, true, true, optionalRoot);
	edit("optional-root-clear", revisionB, [], null, true, false, presentRoot);
	edit("optional-root-null", revisionA, [], { kind: "null" }, true, true, nullRoot);
	const withNote = root();
	assert(withNote.kind === "object");
	withNote.fields.push(["note", { kind: "string", value: "present" }]);
	const presentNote = { schema, root: withNote };
	edit("optional-clear-present", revisionA, ["note"], null, true, false, presentNote);
	const replaced = root();
	assert(replaced.kind === "object");
	const afterParent = {
		schema,
		root: { ...replaced, fields: replaced.fields.map(([key, value]): [string, TaggedValue] =>
			[key, key === "point" ? {
				kind: "object", type: Point.identifier,
				fields: [["x", { kind: "number", value: 10 }], ["y", { kind: "number", value: 20 }]],
			} : value]) },
	};
	edit("parent-again", revisionC, ["point"], {
		kind: "object", type: Point.identifier,
		fields: [["x", { kind: "number", value: 100 }], ["y", { kind: "number", value: 200 }]],
	}, false, false, afterParent);
	rebase("delayed-after-two-parents", "x-over-parent", "parent-again");
	compose("nested-reversed", ["child-y", "child-x"]);
	class RootNamedChild extends sf.object("RootNamedChild", { rootFieldKey: sf.number }) {}
	const namedRoot: { schema: string; root: TaggedValue } = {
		schema: schemaString(RootNamedChild),
		root: { kind: "object", type: RootNamedChild.identifier,
			fields: [["rootFieldKey", { kind: "number", value: 1 }]] },
	};
	edit("root-named-child", revisionA, ["rootFieldKey"], { kind: "number", value: 2 }, false, false, namedRoot);

	const normalCompressor = toIdCompressorWithCore(createIdCompressor(
		assertIsSessionId("90000000-0000-4000-8000-000000000000"),
	));
	const originalProducer = toIdCompressorWithCore(createIdCompressor(
		assertIsSessionId("00000000-0000-4000-b000-000000000000"),
	));
	for (let index = 0; index <= Math.max(...revisions.map(Number)); index++) {
		originalProducer.generateCompressedId();
	}
	normalCompressor.finalizeCreationRange(originalProducer.takeNextCreationRange());
	for (const tag of revisions) {
		assert.equal(normalCompressor.decompress(revisionTag(tag)), testIdCompressor.decompress(revisionTag(tag)));
	}
	revisionCompressor = normalCompressor;
	function foreignRevision(session: string): RevisionTag {
		const producer = toIdCompressorWithCore(createIdCompressor(assertIsSessionId(session)));
		const local = producer.generateCompressedId();
		normalCompressor.finalizeCreationRange(producer.takeNextCreationRange());
		return normalCompressor.recompress(producer.decompress(local));
	}
	const nonlexicalRight = foreignRevision("b0000000-0000-4000-8000-000000000000");
	const nonlexicalLeft = foreignRevision("a0000000-0000-4000-8000-000000000000");
	revisions.push(nonlexicalRight, nonlexicalLeft);
	class Sides extends sf.object("Sides", { left: Point, right: Point }) {}
	const sides = {
		schema: schemaString(Sides),
		root: { kind: "object" as const, type: Sides.identifier,
			fields: ["left", "right"].map((key): [string, TaggedValue] => [key, {
				kind: "object", type: Point.identifier,
				fields: [["x", { kind: "number", value: 1 }], ["y", { kind: "number", value: 2 }]],
			}]) },
	};
	edit("nonlexical-left", nonlexicalLeft, ["left", "x"], { kind: "number", value: 7 }, false, false, sides);
	edit("nonlexical-right", nonlexicalRight, ["right", "x"], { kind: "number", value: 8 }, false, false, sides);
	compose("nonlexical-composed", ["nonlexical-left", "nonlexical-right"]);
	invert("nonlexical-undo", "nonlexical-composed", false);

	class NestedDetached extends sf.object("NestedDetached", { middle: sf.optional(Point) }) {}
	const detachedInitial = {
		schema: schemaString(NestedDetached),
		root: { kind: "object" as const, type: NestedDetached.identifier, fields: [] },
	};
	const detachedId = (localId: number): ChangeAtomId => ({ revision: revisionA, localId: brand(localId) });
	const registerField = (key: string, kind: "Value" | "Optional", change: OptionalChangeset): FieldChangeMap =>
		new Map([[brand(key), { fieldKind: brand(kind), change: brand(change) }]]);
	const nestedDetached = makeModularChangeset({
		maxId: 31,
		revisions: [{ revision: revisionA }],
		fieldChanges: registerField(rootFieldKey, "Value", { moves: [], childChanges: [[detachedId(10), detachedId(1)]] }),
		builds: newChangeAtomIdBTree([
			[[revisionA, brand(30)], treeChunk([{ kind: "number", value: 2 }], revisionCompressor)],
		]),
		refreshers: newChangeAtomIdBTree([
			[[revisionA, brand(10)], treeChunk([{
				kind: "object", type: NestedDetached.identifier, fields: [["middle", {
					kind: "object", type: Point.identifier,
					fields: [["x", { kind: "number", value: 5 }], ["y", { kind: "number", value: 6 }]],
				}]],
			}], revisionCompressor)],
			[[revisionA, brand(20)], treeChunk([{
				kind: "object", type: Point.identifier,
				fields: [["x", { kind: "number", value: 1 }], ["y", { kind: "number", value: 2 }]],
			}], revisionCompressor)],
		]),
	});
	nestedDetached.nodeChanges.set([revisionA, brand(1)], {
		fieldChanges: registerField("middle", "Optional", {
			moves: [],
			childChanges: [[detachedId(20), detachedId(2)]],
			valueReplace: { isEmpty: false, dst: detachedId(21) },
		}),
	});
	nestedDetached.nodeChanges.set([revisionA, brand(2)], {
		fieldChanges: registerField("x", "Value", {
			moves: [], childChanges: [],
			valueReplace: { isEmpty: false, src: detachedId(30), dst: detachedId(31) },
		}),
	});
	nestedDetached.nodeToParent.set([revisionA, brand(1)], { nodeId: undefined, field: rootFieldKey });
	nestedDetached.nodeToParent.set([revisionA, brand(2)], { nodeId: detachedId(1), field: brand("middle") });
	validateChangeset(nestedDetached, fieldKinds);
	changes.set("nested-detached", tagChange(nestedDetached, revisionA));
	inputs.push({ op: "prune", id: "nested-global-order", change: "nested-detached" });
	record("nested-global-order", tagChange(pruneChangeset(nestedDetached, fieldKinds), revisionA));

	const scenarioInputs: object[] = [];
	const scenarioObservations: object[] = [];
	const decoder = schemaCodecBuilder.buildDecoder({ jsonValidator: FormatValidatorNoOp });
	function scenario(
		id: string, names: string[],
		initial: { schema: string; root: TaggedValue | null } = { schema, root: root() },
		retainPath: string[] | null = ["point"],
	) {
		const retain: Scenario["actions"] = retainPath === null ? [] : [
			{ id: retainPath.length === 0 ? "retain-root" : "retain-point",
				op: "retain", name: retainPath.length === 0 ? "old-root" : "old-point", path: retainPath },
		];
		const actions: Scenario["actions"] = [
			...retain,
			...names.map((name) => {
				const change = get(name);
				return { id: name, op: "apply" as const,
					delta: deltaData(intoDelta(change), change.revision) };
			}),
		];
		const definition: Scenario = { id, ...initial, actions };
		const result = runScenario(definition, revisionCompressor, decoder);
		assert(result.observation.checkpoints.every((checkpoint) => checkpoint.accepted),
			`${id}: all supported modular deltas must apply`);
		scenarioInputs.push({ id, ...initial, actions: [
			...retain, ...names.map((change) => ({ id: change, op: "apply", change })),
		] });
		scenarioObservations.push({ operation: "modular-forest", ...result.observation });
	}
	scenario("nested-independent", ["child-y", "x-over-y"]);
	scenario("nested-composed", ["nested-composed"]);
	scenario("parent-then-child", ["parent", "x-over-parent"]);
	scenario("child-then-parent", ["child-x", "parent-over-x"]);
	scenario("composed-detached-child", ["parent-then-detached"]);
	scenario("rollback-restores", ["child-x", "child-rollback"]);
	scenario("undo-restores-value", ["child-x", "child-undo"]);
	scenario("three-fields", ["three-composed"]);
	scenario("four-fields", ["four-composed"]);
	scenario("optional-root-set", ["optional-root-set"], optionalRoot, null);
	scenario("optional-root-clear", ["optional-root-clear"], presentRoot, []);
	scenario("optional-root-null", ["optional-root-null"], nullRoot, null);
	scenario("optional-clear-present", ["optional-clear-present"], presentNote);
	scenario("replace-twice-then-delayed", ["parent", "parent-again", "delayed-after-two-parents"]);
	scenario("nested-reversed", ["nested-reversed"]);
	scenario("root-named-child", ["root-named-child"], namedRoot, []);
	scenario("nonlexical-undo", ["nonlexical-composed", "nonlexical-undo"], sides, []);
	scenario("nested-global-order", ["nested-global-order"], detachedInitial, []);

	return {
		input: {
			changes: { first: structure(first), second: structure(second), "nested-detached": structure(nestedDetached) },
			tags: { first: revision(revisionA), second: revision(revisionB), "nested-detached": revision(revisionA) },
			revisions: revisions.map((tag) => ({ encoded: tag, stable: revision(tag) })),
			operations: inputs,
			scenarios: scenarioInputs,
		},
		observations: [...observations, ...scenarioObservations],
	};
}

export function expandModularEvidence(output: string): void {
	assert(isAbsolute(output));
	assert.equal(process.env.WATERSHED_ORACLE_COMMIT, referenceCommit);
	const filename = join(output, "algebra-cases.json");
	const cases = JSON.parse(readFileSync(filename, "utf8"));
	const fixture = cases.find((value: { id: string }) => value.id === "modular-nested-algebra");
	assert(fixture !== undefined);
	const a = revisionTag(fixture.input.revisions.first);
	const b = revisionTag(fixture.input.revisions.second);
	const c = revisionTag(fixture.input.revisions.replacement);
	const ids = fixture.raw.ids;
	const first = withRootAndNestedChanges(
		a, brand("root"), brand("nested-required"), brand("pruned-optional"),
		ids.rootNode, ids.rootAlias, ids.prunedNode, ids.fill, ids.detach,
		ids.buildId, ids.staleRefresherId,
	);
	const { family } = makeModularFamily();
	const second = family.codecs.resolve(5).decode(fixture.input.changes.second, {
		originatorId: testIdCompressor.localSessionId, idCompressor: testIdCompressor,
		revision: undefined, isSummary: false,
	});
	const expanded = expand(first, second, a, b, c);
	fixture.input.expanded = expanded.input;
	fixture.expected.observations.push(...expanded.observations);
	writeFileSync(filename, `${JSON.stringify(cases, undefined, 2)}\n`, "utf8");
}
