import { strict as assert } from "node:assert";
import { mkdirSync, writeFileSync } from "node:fs";
import { isAbsolute, join } from "node:path";

import { asAlpha } from "../api.js";
import { FluidClientVersion } from "../codec/index.js";
import { type RevertibleAlpha } from "../core/index.js";
import { TreeStatus } from "../feature-libraries/index.js";
import {
	extractPersistedSchema,
	SchemaFactory,
	TreeViewConfiguration,
	type ImplicitFieldSchema,
	type TreeViewAlpha,
} from "../simple-tree/index.js";
import { Tree } from "../shared-tree/index.js";
import { configuredSharedTreeInternal } from "../treeFactory.js";
import { TestTreeProviderLite } from "./utils.js";

const reference = {
	package: "@fluidframework/tree",
	version: "3.1.0",
	commit: "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960",
};

const sf = new SchemaFactory("com.example.typed");
class Point extends sf.object("Point", { id: sf.identifier, label: sf.string }) {}
class Items extends sf.array("Items", [sf.string, Point]) {}
class ByKey extends sf.map("ByKey", [sf.string, Point]) {}
class Root extends sf.object("Root", {
	featured: Point,
	left: Items,
	right: Items,
	byKey: ByKey,
}) {}
class Outline extends sf.objectRecursive("Outline", {
	label: sf.string,
	children: [() => Children],
}) {}
class Children extends sf.arrayRecursive("Children", [() => Outline]) {}
class OptionalNode extends sf.objectRecursive("OptionalNode", {
	child: sf.optionalRecursive([sf.null, () => OptionalNode]),
}) {}
class MutualA extends sf.objectRecursive("MutualA", {
	next: sf.optionalRecursive([() => MutualB]),
}) {}
class MutualB extends sf.objectRecursive("MutualB", {
	next: sf.optionalRecursive([() => MutualA]),
}) {}

type View = TreeViewAlpha<typeof Root>;

function createViews() {
	const factory = configuredSharedTreeInternal({
		minVersionForCollab: FluidClientVersion.v2_117,
	}).getFactory();
	const provider = new TestTreeProviderLite(2, factory);
	const config = new TreeViewConfiguration({ schema: Root, enableSchemaValidation: true });
	const main = asAlpha(provider.trees[0].viewWith(config));
	main.initialize(new Root({
		featured: new Point({ id: "featured", label: "featured" }),
		left: new Items([
			new Point({ id: "duplicate", label: "A" }),
			new Point({ id: "duplicate", label: "B" }),
		]),
		right: new Items([]),
		byKey: new ByKey([]),
	}));
	provider.synchronizeMessages();
	const peer = asAlpha(provider.trees[1].viewWith(config));
	return { provider, main, peer };
}

function pointAt(items: Items, index: number): Point {
	const point = items[index];
	assert(point instanceof Point);
	return point;
}

function status(point: Point): string {
	return TreeStatus[Tree.status(point)];
}

function visible(view: View) {
	const item = (value: string | Point) =>
		typeof value === "string" ? { kind: "string", value } :
			{ kind: "Point", id: value.id, label: value.label };
	return {
		featured: item(view.root.featured),
		left: [...view.root.left].map(item),
		right: [...view.root.right].map(item),
		byKey: [...view.root.byKey].map(([key, value]) => [key, item(value)]),
	};
}

function attempted(action: () => void) {
	try {
		action();
		return { accepted: true };
	} catch (error) {
		return { accepted: false, category: error instanceof Error ? error.constructor.name : typeof error };
	}
}

type Action =
	| { op: "insert-before" }
	| { op: "reorder" }
	| { op: "cross-parent" }
	| { op: "remove" }
	| { op: "undo" }
	| { op: "replace"; equalIdentifier: boolean }
	| { op: "replace-root" }
	| { op: "transaction"; abort: boolean }
	| { op: "competing-edit"; reconnect: boolean }
	| { op: "fork-rebase-merge"; dispose: boolean }
	| { op: "invalidate-schema" };

const scenarios: { id: string; operations: Action[] }[] = [
	{ id: "insert-before", operations: [{ op: "insert-before" }] },
	{ id: "reorder", operations: [{ op: "reorder" }] },
	{ id: "cross-parent", operations: [{ op: "cross-parent" }] },
	{ id: "remove-undo", operations: [{ op: "remove" }, { op: "undo" }] },
	{ id: "equal-content-replacement", operations: [{ op: "replace", equalIdentifier: false }] },
	{ id: "equal-identifier-replacement", operations: [{ op: "replace", equalIdentifier: true }] },
	{ id: "root-replacement", operations: [{ op: "replace-root" }] },
	{ id: "transaction-commit", operations: [{ op: "transaction", abort: false }] },
	{ id: "transaction-abort", operations: [{ op: "transaction", abort: true }] },
	{ id: "reconciliation", operations: [{ op: "competing-edit", reconnect: false }] },
	{ id: "reconnect", operations: [{ op: "competing-edit", reconnect: true }] },
	{ id: "fork-rebase-merge-retained", operations: [{ op: "fork-rebase-merge", dispose: false }] },
	{ id: "fork-rebase-merge-disposed", operations: [{ op: "fork-rebase-merge", dispose: true }] },
	{ id: "schema-invalidation", operations: [{ op: "invalidate-schema" }] },
];

function runScenario(input: { operations: Action[] }) {
	const { provider, main, peer } = createViews();
	const saved = pointAt(main.root.left, 1);
	const other = pointAt(main.root.left, 0);
	const duplicateIdentifiers = saved.id === other.id;
	const states: object[] = [];
	let removal: RevertibleAlpha | undefined;
	const off = main.events.on("changed", (_metadata, getRevertible) => {
		if (getRevertible !== undefined) removal = getRevertible();
	});
	for (const action of input.operations) {
		switch (action.op) {
			case "insert-before":
				main.root.left.insertAtStart(new Point({ id: "inserted", label: "new" }));
				states.push({ same: main.root.left[2] === saved });
				break;
			case "reorder":
				main.root.left.moveToStart(1);
				states.push({ same: main.root.left[0] === saved });
				break;
			case "cross-parent":
				main.root.right.moveToStart(1, main.root.left);
				states.push({ same: main.root.right[0] === saved });
				break;
			case "remove":
				main.root.left.removeAt(1);
				states.push({ status: status(saved), read: saved.label,
					edit: attempted(() => { saved.label = "removed-edit"; }),
					projection: "typed-api-refuses-removed-read-and-edit" });
				break;
			case "undo":
				assert(removal !== undefined);
				removal.revert();
				states.push({ status: status(saved), same: main.root.left[1] === saved });
				break;
			case "replace":
				main.root.left.removeAt(1);
				main.root.left.insertAtEnd(new Point({
					id: action.equalIdentifier ? saved.id : "replacement",
					label: action.equalIdentifier ? "replacement" : saved.label,
				}));
				states.push({ same: main.root.left[1] === saved,
					sameIdentifier: pointAt(main.root.left, 1).id === saved.id,
					status: status(saved) });
				break;
			case "replace-root":
				main.root = new Root({
					featured: new Point({ id: "featured", label: "featured" }),
					left: new Items([new Point({ id: "duplicate", label: "A" }), new Point({ id: "duplicate", label: "B" })]),
					right: new Items([]), byKey: new ByKey([]),
				});
				states.push({ same: main.root.left[1] === saved, status: status(saved) });
				break;
			case "transaction": {
				let preview: Point | undefined;
				Tree.runTransaction(main, () => {
					main.root.left.insertAtStart(new Point({ label: "preview" }));
					preview = pointAt(main.root.left, 0);
					states.push({ phase: "preview", originalSame: main.root.left[2] === saved,
						generated: preview.id });
					if (action.abort) return Tree.runTransaction.rollback;
				});
				assert(preview !== undefined);
				states.push({ phase: "after", originalSame: main.root.left[action.abort ? 1 : 2] === saved,
					previewSame: !action.abort && main.root.left[0] === preview,
					previewStatus: status(preview) });
				break;
			}
			case "competing-edit":
				if (action.reconnect) provider.trees[0].containerRuntime.connected = false;
				saved.label = "local";
				peer.root.left.insertAtStart(new Point({ label: "remote" }));
				if (action.reconnect) provider.trees[0].containerRuntime.connected = true;
				provider.synchronizeMessages();
				states.push({ same: main.root.left[2] === saved, label: saved.label,
					peerLabel: pointAt(peer.root.left, 2).label, remoteId: pointAt(main.root.left, 0).id });
				break;
			case "fork-rebase-merge": {
				const branch = main.fork() as View;
				const branchSaved = pointAt(branch.root.left, 1);
				branchSaved.label = "branch";
				main.root.left.insertAtStart(new Point({ label: "main" }));
				branch.rebaseOnto(main);
				states.push({ phase: "rebase", same: branch.root.left[2] === branchSaved,
					foreignObject: branchSaved !== saved });
				main.merge(branch, action.dispose);
				states.push({ phase: "merge", same: main.root.left[2] === saved,
					label: saved.label, branchRead: attempted(() => { void branch.root; }),
					branchStatus: status(branchSaved) });
				break;
			}
			case "invalidate-schema": {
				const checkout = Reflect.get(peer, "checkout");
				assert(checkout !== undefined);
				const wide = new SchemaFactory("com.example.typed");
				const wideRoot = wide.object("Root", {
					featured: Point, left: Items, right: Items, byKey: ByKey,
					extra: wide.optional(wide.string),
				});
				peer.dispose();
				const upgraded = checkout.viewWith(new TreeViewConfiguration({ schema: wideRoot }));
				upgraded.upgradeSchema();
				provider.synchronizeMessages();
				states.push({ canView: main.compatibility.canView,
					read: attempted(() => { void main.root; }), savedStatus: status(saved) });
				break;
			}
		}
	}
	off();
	const canView = main.compatibility.canView;
	const observations = {
		states,
		savedStatus: status(saved),
		otherStatus: status(other),
		duplicateIdentifiers,
		visible: canView ? visible(main) : null,
	};
	main.dispose();
	return observations;
}

type ConstructionAction = "initialize" | "commit" | "abort" | "reconciliation";

function runConstruction(action: ConstructionAction) {
	const factory = configuredSharedTreeInternal({
		minVersionForCollab: FluidClientVersion.v2_117,
	}).getFactory();
	const provider = new TestTreeProviderLite(2, factory);
	const compressor = provider.getCompressor(provider.trees[0]);
	const allocations: { compressed: number; value: string }[] = [];
	const generate = compressor.generateCompressedId.bind(compressor);
	Reflect.set(compressor, "generateCompressedId", () => {
		const id = generate();
		allocations.push({ compressed: id, value: compressor.decompress(id) });
		return id;
	});
	const config = new TreeViewConfiguration({ schema: Root });
	const main = asAlpha(provider.trees[0].viewWith(config));
	main.initialize({
		featured: { label: "featured" },
		left: ["text", { label: "nested-array" }],
		right: [],
		byKey: new Map([["nested", { label: "nested-map" }]]),
	});
	provider.synchronizeMessages();
	const peer = asAlpha(provider.trees[1].viewWith(config));
	const initial = visible(main);
	const initialAllocationCount = allocations.length;
	const initialIds = [
		main.root.featured.id,
		pointAt(main.root.left, 1).id,
		(main.root.byKey.get("nested") as Point).id,
	];
	let generated: Point | undefined;
	let generatedId: string | undefined;
	if (action === "commit" || action === "abort") {
		Tree.runTransaction(main, () => {
			main.root.right.insertAtEnd({ label: action });
			generated = pointAt(main.root.right, 0);
			generatedId = generated.id;
			return action === "abort" ? Tree.runTransaction.rollback : undefined;
		});
	} else if (action === "reconciliation") {
		peer.root.left.insertAtStart("peer");
		main.root.left.insertAtStart({ label: "local" });
		generated = pointAt(main.root.left, 0);
		generatedId = generated.id;
	}
	provider.synchronizeMessages();
	const ids = [...initialIds, ...(generatedId === undefined ? [] : [generatedId])];
	const observations = {
		initial,
		initialAllocationCount,
		allocations: allocations.map((event) => ({
			...event,
			kind: ids.includes(event.value) ? "identifier" : "revision",
		})),
		generatedId,
		generatedStatus: generated === undefined ? undefined : status(generated),
		survives: generated === undefined ? undefined :
			[...main.root.left, ...main.root.right].some((item) => item === generated),
		visible: visible(main),
		peerVisible: visible(peer),
	};
	main.dispose();
	peer.dispose();
	return observations;
}

function authoring() {
	const union = [sf.string, Point] as const;
	const reverse = [Point, sf.string] as const;
	const UnionObject = sf.object("UnionObject", { value: union });
	const declarations: [string, ImplicitFieldSchema][] = [
		["union-root", union], ["union-root-reversed", reverse],
		["union-object", UnionObject], ["union-array", Items], ["union-map", ByKey],
		["recursive-outline", Outline], ["mutual-recursion", MutualA],
		["optional-recursive-null", OptionalNode], ["identifier-point", Point],
	];
	const schemas = declarations.map(([id, schema]) => ({
		id, schema: extractPersistedSchema(schema, FluidClientVersion.v2_117, () => false),
	}));
	assert.deepEqual(schemas[0].schema, schemas[1].schema);
	const { main } = createViews();
	main.root.left.insertAtEnd("text", new Point({ label: "generated" }));
	main.root.byKey.set("text", "text");
	main.root.byKey.set("point", new Point({ id: "custom", label: "assigned" }));
	const observations = {
		variantKinds: [...main.root.left].map(value => typeof value === "string" ? "string" : "Point"),
		mapVariantKinds: [...main.root.byKey].map(([key, value]) => ({
			key, kind: typeof value === "string" ? "string" : "Point",
		})),
		generated: pointAt(main.root.left, 3).id,
		assigned: (main.root.byKey.get("point") as Point).id,
		distinctDuplicateNodes: main.root.left[0] !== main.root.left[1],
		equalCustomIdentifiers: pointAt(main.root.left, 0).id === pointAt(main.root.left, 1).id,
	};
	main.dispose();
	const factory = configuredSharedTreeInternal({
		minVersionForCollab: FluidClientVersion.v2_117,
	}).getFactory();
	const rootValues = (["text", { id: "custom", label: "object" }] as const).map(input => {
		const provider = new TestTreeProviderLite(1, factory);
		const view = provider.trees[0].viewWith(new TreeViewConfiguration({ schema: union }));
		view.initialize(input);
		const result = typeof view.root === "string" ? { kind: "string", value: view.root } :
			{ kind: "Point", id: view.root.id, label: view.root.label };
		view.dispose();
		return result;
	});
	const objectValues = [
		new UnionObject({ value: "text" }).value,
		new UnionObject({ value: { id: "custom", label: "object" } }).value,
	].map(value => typeof value === "string" ? { kind: "string", value } :
		{ kind: "Point", id: value.id, label: value.label });
	const outline = new Outline({ label: "parent", children: new Children([
		new Outline({ label: "child", children: new Children([]) }),
	]) });
	const optionalAbsent = new OptionalNode({});
	const optionalNull = new OptionalNode({ child: null });
	const optionalPresent = new OptionalNode({ child: new OptionalNode({}) });
	const mutual = new MutualA({ next: new MutualB({ next: new MutualA({}) }) });
	return { schemas, scenarios: [{
		id: "union-collections-identifiers",
		input: { operations: [
			{ op: "array-insert", values: [{ kind: "string", value: "text" }, { kind: "Point", label: "generated", id: "generate" }] },
			{ op: "map-set", key: "text", value: { kind: "string", value: "text" } },
			{ op: "map-set", key: "point", value: { kind: "Point", label: "assigned", id: "custom" } },
		] },
		observations,
	}, {
		id: "union-root-object",
		input: { values: ["text", { kind: "Point", id: "custom", label: "object" }] },
		observations: { rootValues, objectValues },
	}, {
		id: "finite-recursion",
		input: {
			outline: { label: "parent", children: [{ label: "child", children: [] }] },
			optional: [{}, { child: null }, { child: {} }],
			mutual: { next: { next: {} } },
		},
		observations: {
			outline: { label: outline.label, children: [...outline.children].map(child => ({
				label: child.label, children: [...child.children],
			})) },
			optionalAbsent: optionalAbsent.child === undefined,
			optionalNull: optionalNull.child === null,
			optionalPresent: optionalPresent.child instanceof OptionalNode,
			mutualPresent: mutual.next?.next instanceof MutualA,
			mutualAbsent: mutual.next?.next?.next === undefined,
		},
	}, ...(["initialize", "commit", "abort", "reconciliation"] as const).map(action => ({
		id: `generated-identifiers-${action}`,
		input: {
			action, initial: {
				featured: { label: "featured" }, left: ["text", { label: "nested-array" }],
				right: [], byKey: [["nested", { label: "nested-map" }]],
			},
		},
		observations: runConstruction(action),
	}))] };
}

describe("Watershed typed API oracle", () => {
	it("captures authoring and actual saved-reference lifetimes", () => {
		const output = process.env.WATERSHED_ORACLE_OUTPUT;
		assert(output !== undefined && isAbsolute(output));
		assert.equal(process.env.WATERSHED_ORACLE_COMMIT, reference.commit);
		mkdirSync(output, { recursive: true });
		writeFileSync(join(output, "typed-api-authoring.json"),
			`${JSON.stringify({ formatVersion: 1, reference, ...authoring() }, undefined, 2)}\n`);
		writeFileSync(join(output, "typed-api-live.json"),
			`${JSON.stringify({
				formatVersion: 1, reference,
				scenarios: scenarios.map(input => ({
					id: input.id, input: { operations: input.operations },
					observations: runScenario(input),
				})),
			}, undefined, 2)}\n`);
	});
});
