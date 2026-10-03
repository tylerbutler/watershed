/*!
 * Copyright (c) Microsoft Corporation and contributors. All rights reserved.
 * Licensed under the MIT License.
 */

import { strict as assert } from "node:assert";
import { mkdirSync, writeFileSync } from "node:fs";
import { isAbsolute, join } from "node:path";

import {
	createSessionId,
	deserializeIdCompressor,
	serializeIdCompressor,
} from "@fluidframework/id-compressor/internal";
import {
	MockFluidDataStoreRuntime,
	MockSharedObjectServices,
} from "@fluidframework/test-runtime-utils/internal";

import { asAlpha } from "../api.js";
import { FluidClientVersion } from "../codec/index.js";
import {
	CommitKind,
	CommitOutcome,
	RevertibleStatus,
	type ChangeMetadata,
	type RevertibleAlpha,
} from "../core/index.js";
import {
	SchemaFactory,
	TreeViewConfiguration,
	type TreeView,
} from "../simple-tree/index.js";
import { Tree } from "../shared-tree/index.js";
import { configuredSharedTreeInternal } from "../treeFactory.js";
import { TestTreeProviderLite } from "./utils.js";

const formatVersion = 1;
const reference = {
	package: "@fluidframework/tree",
	version: "3.1.0",
	commit: "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960",
};

const sf = new SchemaFactory("org.watershed.shared-tree.undo-redo");
class Point extends sf.object("Point", {
	id: sf.identifier,
	label: sf.string,
	x: sf.number,
}) {}
class Items extends sf.array("Items", [sf.string, Point]) {}
class NamedMap extends sf.map("NamedMap", [sf.string, Point, Items]) {}
class Root extends sf.object("Root", {
	title: sf.string,
	note: sf.optional(sf.string),
	count: sf.number,
	featured: Point,
	left: Items,
	right: Items,
	byKey: NamedMap,
}) {}

type UndoView = TreeView<typeof Root>;

function treeFactory() {
	return configuredSharedTreeInternal({
		minVersionForCollab: FluidClientVersion.v2_117,
	}).getFactory();
}

function initialRoot() {
	return new Root({
		title: "base",
		note: "seed",
		count: 0,
		featured: new Point({ label: "featured", x: 0 }),
		left: new Items([
			new Point({ label: "left-a", x: 1 }),
			new Point({ label: "left-b", x: 2 }),
		]),
		right: new Items([new Point({ label: "right-a", x: 3 })]),
		byKey: new NamedMap([["seed", "value"]]),
	});
}

function copy<T>(value: T): T {
	return JSON.parse(JSON.stringify(value));
}

function errorOf(action: () => void): string {
	try {
		action();
		return "";
	} catch (error) {
		return String(error);
	}
}

function enumName(values: object, value: number): string {
	const name = Reflect.get(values, value);
	assert.equal(typeof name, "string");
	return name;
}

function visible(root: Root) {
	const value = (item: string | Point | Items): unknown =>
		item instanceof Point
			? { id: item.id, label: item.label, x: item.x }
			: item instanceof Items
				? [...item].map(value)
				: item;
	return {
		title: root.title,
		note: root.note ?? null,
		count: root.count,
		featured: value(root.featured),
		left: [...root.left].map(value),
		right: [...root.right].map(value),
		byKey: [...root.byKey]
			.sort(([left], [right]) => left.localeCompare(right))
			.map(([key, item]) => [key, value(item)]),
	};
}

function caseFile(id: string, domain: string, input: object, observations: object[], raw: object) {
	assert(observations.length > 0);
	return { formatVersion, reference, id, domain, input, expected: { observations }, raw };
}

function createViews(count = 1) {
	const provider = new TestTreeProviderLite(count, treeFactory());
	const first = asAlpha(provider.trees[0].viewWith(
		new TreeViewConfiguration({ schema: Root, enableSchemaValidation: true }),
	));
	first.initialize(initialRoot());
	provider.synchronizeMessages();
	const views = [first];
	for (let index = 1; index < count; index++) {
		views.push(asAlpha(provider.trees[index].viewWith(
			new TreeViewConfiguration({ schema: Root, enableSchemaValidation: true }),
		)));
	}
	return { provider, views };
}

function eventRecord(metadata: ChangeMetadata, factory: unknown) {
	const local = metadata.isLocal;
	return {
		kind: enumName(CommitKind, metadata.kind),
		local,
		factory: factory !== undefined,
		change: local ? copy(metadata.getChange()) : null,
	};
}

async function captureLifetime() {
	const provider = new TestTreeProviderLite(2, treeFactory());
	const view = asAlpha(provider.trees[0].viewWith(
		new TreeViewConfiguration({ schema: Root, enableSchemaValidation: true }),
	));
	const events: object[] = [];
	const remoteEvents: object[] = [];
	const handles: RevertibleAlpha[] = [];
	let acquireNext = true;
	let lateFactory: (() => RevertibleAlpha) | undefined;
	let duplicateError = "";

	const offFirst = view.events.on("changed", (metadata, getRevertible) => {
		events.push(eventRecord(metadata, getRevertible));
		if (metadata.isLocal && getRevertible !== undefined && acquireNext) {
			const handle = getRevertible();
			handles.push(handle);
			lateFactory = getRevertible;
			acquireNext = false;
		}
	});
	const offSecond = view.events.on("changed", (metadata, getRevertible) => {
		if (metadata.isLocal && getRevertible !== undefined && handles.length > 0
			&& duplicateError === "") {
			duplicateError = errorOf(() => getRevertible());
		}
	});

	view.initialize(initialRoot());
	provider.synchronizeMessages();
	const peer = asAlpha(provider.trees[1].viewWith(
		new TreeViewConfiguration({ schema: Root, enableSchemaValidation: true }),
	));
	const offRemote = peer.events.on("changed", (metadata, getRevertible) => {
		remoteEvents.push(eventRecord(metadata, getRevertible));
	});

	acquireNext = true;
	view.root.title = "local";
	const first = handles.at(-1);
	assert(first !== undefined);
	const lateError = errorOf(() => lateFactory?.());
	const beforeDefaultRevert = enumName(RevertibleStatus, first.status);
	first.revert();
	const afterDefaultRevert = enumName(RevertibleStatus, first.status);
	provider.synchronizeMessages();

	acquireNext = true;
	view.root.note = "repeat";
	const repeated = handles.at(-1);
	assert(repeated !== undefined && repeated !== first);
	const beforeRepeatedRevert = enumName(RevertibleStatus, repeated.status);
	repeated.revert(false);
	const afterFirstRepeatedRevert = enumName(RevertibleStatus, repeated.status);
	repeated.revert(false);
	const afterSecondRepeatedRevert = enumName(RevertibleStatus, repeated.status);
	provider.synchronizeMessages();
	repeated.dispose();
	const afterDispose = enumName(RevertibleStatus, repeated.status);
	const secondDisposeError = errorOf(() => repeated.dispose());
	const disposedRevertError = errorOf(() => repeated.revert(false));

	assert.notEqual(duplicateError, "");
	assert.notEqual(lateError, "");
	assert.equal(beforeDefaultRevert, "Valid");
	assert.equal(afterDefaultRevert, "Disposed");
	assert.equal(beforeRepeatedRevert, "Valid");
	assert.equal(afterFirstRepeatedRevert, "Valid");
	assert.equal(afterSecondRepeatedRevert, "Valid");
	assert.equal(afterDispose, "Disposed");
	assert.notEqual(secondDisposeError, "");
	assert.notEqual(disposedRevertError, "");
	assert(events.some((event) => Reflect.get(event, "factory") === false));
	assert(remoteEvents.every((event) =>
		Reflect.get(event, "local") === false && Reflect.get(event, "factory") === false));

	offFirst();
	offSecond();
	offRemote();
	return caseFile(
		"revertible-lifetime",
		"history",
		{
			scenarios: [
				"schema-no-factory",
				"remote-no-factory",
				"single-acquisition",
				"late-acquisition",
				"default-disposal",
				"retained-repeated-revert",
				"disposed-errors",
			],
		},
		[{
			id: "lifetime",
			events,
			remoteEvents,
			duplicateError,
			lateError,
			status: {
				beforeDefaultRevert,
				afterDefaultRevert,
				beforeRepeatedRevert,
				afterFirstRepeatedRevert,
				afterSecondRepeatedRevert,
				afterDispose,
			},
			secondDisposeError,
			disposedRevertError,
			snapshot: visible(view.root),
		}],
		{ events, remoteEvents },
	);
}

async function captureKinds() {
	const { provider, views: [view] } = createViews();
	const events: object[] = [];
	const handles: RevertibleAlpha[] = [];
	const settled: object[] = [];
	const beforeSequence: number[] = [];
	const off = view.events.on("changed", (metadata, getRevertible) => {
		if (!metadata.isLocal) return;
		const index = events.length;
		events.push(eventRecord(metadata, getRevertible));
		beforeSequence.push(settled.length);
		metadata.events.on("settled", (outcome) => {
			settled.push({
				index,
				kind: enumName(CommitKind, metadata.kind),
				outcome: enumName(CommitOutcome, outcome),
			});
		});
		assert(getRevertible !== undefined);
		handles.push(getRevertible());
	});

	view.root.title = "changed";
	assert.equal(settled.length, 0);
	provider.synchronizeMessages();
	handles[0].revert();
	assert.equal(settled.length, 1);
	provider.synchronizeMessages();
	handles[1].revert();
	assert.equal(settled.length, 2);
	provider.synchronizeMessages();

	const kinds = events.map((event) => Reflect.get(event, "kind"));
	assert.deepEqual(kinds, ["Default", "Undo", "Redo"]);
	assert.deepEqual(settled.map((event) => Reflect.get(event, "outcome")), [
		"FullyApplied",
		"FullyApplied",
		"FullyApplied",
	]);
	assert.deepEqual(beforeSequence, [0, 1, 2]);
	off();
	return caseFile(
		"undo-redo-kinds",
		"tree",
		{ sequence: ["Default", "Undo", "Redo"], operation: "object-set" },
		[{
			id: "kind-sequence",
			events,
			settled,
			beforeSequence,
			snapshot: visible(view.root),
		}],
		{ encodedChanges: events.map((event) => Reflect.get(event, "change")) },
	);
}

async function captureFieldScenario(
	id: string,
	edit: (view: UndoView, peer: UndoView) => void,
	afterEdit?: (view: UndoView, peer: UndoView) => void,
) {
	const { provider, views: [view, peer] } = createViews(2);
	const events: object[] = [];
	let target: RevertibleAlpha | undefined;
	const off = view.events.on("changed", (metadata, getRevertible) => {
		events.push(eventRecord(metadata, getRevertible));
		if (metadata.isLocal && metadata.kind === CommitKind.Default
			&& getRevertible !== undefined && target === undefined) {
			target = getRevertible();
		}
	});
	const before = visible(view.root);
	edit(view, peer);
	const edited = visible(view.root);
	provider.synchronizeMessages();
	afterEdit?.(view, peer);
	provider.synchronizeMessages();
	const beforeUndo = visible(view.root);
	assert(target !== undefined, `${id}: missing revertible`);
	target.revert(false);
	const optimisticUndo = visible(view.root);
	provider.synchronizeMessages();
	const settledUndo = visible(view.root);
	const status = enumName(RevertibleStatus, target.status);
	target.dispose();
	off();
	return {
		id,
		before,
		edited,
		beforeUndo,
		optimisticUndo,
		settledUndo,
		status,
		events,
	};
}

async function captureOverlapScenario(
	id: string,
	sequenceOrder: "remote-first" | "local-first",
) {
	const { provider, views: [view, peer] } = createViews(2);
	const events: object[] = [];
	let target: RevertibleAlpha | undefined;
	const off = view.events.on("changed", (metadata, getRevertible) => {
		events.push(eventRecord(metadata, getRevertible));
		if (metadata.isLocal && metadata.kind === CommitKind.Default
			&& getRevertible !== undefined && target === undefined) {
			target = getRevertible();
		}
	});
	const before = visible(view.root);
	const sequenceNumberBeforeAuthoring = provider.sequenceNumber;
	if (sequenceOrder === "remote-first") {
		peer.root.title = "remote";
		view.root.title = "local";
	} else {
		view.root.title = "local";
		peer.root.title = "remote";
	}
	const authoredBeforeSequence = provider.sequenceNumber === sequenceNumberBeforeAuthoring;
	const edited = visible(view.root);
	provider.synchronizeMessages();
	const beforeUndo = visible(view.root);
	assert(target !== undefined);
	target.revert(false);
	const optimisticUndo = visible(view.root);
	provider.synchronizeMessages();
	const settledUndo = visible(view.root);
	const status = enumName(RevertibleStatus, target.status);
	target.dispose();
	off();
	return {
		id,
		sequenceOrder,
		authoredBeforeSequence,
		before,
		edited,
		beforeUndo,
		optimisticUndo,
		settledUndo,
		status,
		events,
	};
}

async function captureFields() {
	const scenarios = [
		await captureFieldScenario("object-set", (view) => {
			view.root.title = "object-set";
		}),
		await captureFieldScenario("object-replacement", (view) => {
			view.root.featured = new Point({ label: "replacement", x: 9 });
		}),
		await captureFieldScenario("map-set", (view) => {
			view.root.byKey.set("new", new Point({ label: "map", x: 4 }));
		}),
		await captureFieldScenario("map-delete", (view) => {
			view.root.byKey.delete("seed");
		}),
		await captureFieldScenario("array-insert", (view) => {
			view.root.left.insertAtEnd(new Point({ label: "inserted", x: 5 }));
		}),
		await captureFieldScenario("array-remove", (view) => {
			view.root.left.removeAt(0);
		}),
		await captureFieldScenario("same-array-move", (view) => {
			view.root.left.moveRangeToIndex(2, 0, 1);
		}),
		await captureFieldScenario("cross-array-move", (view) => {
			view.root.right.moveRangeToEnd(0, 1, view.root.left);
		}),
		await captureFieldScenario("outer-transaction", (view) => {
			Tree.runTransaction(view, () => {
				view.root.title = "transaction";
				view.root.count = 2;
				view.root.left.insertAtEnd("transaction-item");
			});
		}),
		await captureFieldScenario(
			"later-unrelated-local-remote",
			(view) => {
				view.root.title = "target";
			},
			(view, peer) => {
				view.root.count = 7;
				peer.root.byKey.set("remote", "preserved");
			},
		),
		await captureOverlapScenario("overlap-remote-first", "remote-first"),
		await captureOverlapScenario("overlap-local-first", "local-first"),
	];
	for (const scenario of scenarios) {
		assert(scenario.events.some((event) => Reflect.get(event, "kind") === "Undo"));
		assert.equal(scenario.status, "Valid");
	}
	return caseFile(
		"undo-redo-fields",
		"field",
		{
			scenarios: scenarios.map(({ id }) => ({ id, operation: id })),
			fieldKinds: ["Value", "Optional", "Sequence", "Identifier"],
		},
		scenarios,
		{
			scenarios: scenarios.map(({ id, events }) => ({
				id,
				encodedChanges: events
					.filter((event) => Reflect.get(event, "local"))
					.map((event) => Reflect.get(event, "change")),
			})),
		},
	);
}

async function captureConstraintScenario(id: string, removeTarget: boolean) {
	const { provider, views: [view, peer] } = createViews(2);
	let target: RevertibleAlpha | undefined;
	const events: object[] = [];
	const outcomes: string[] = [];
	const off = view.events.on("changed", (metadata, getRevertible) => {
		events.push(eventRecord(metadata, getRevertible));
		if (metadata.isLocal) {
			metadata.events.on("settled", (outcome) => {
				outcomes.push(enumName(CommitOutcome, outcome));
			});
			if (metadata.kind === CommitKind.Default && getRevertible !== undefined
				&& target === undefined) {
				target = getRevertible();
			}
		}
	});
	const edited = view.root.left[0];
	assert(edited instanceof Point);
	edited.x = 10;
	provider.synchronizeMessages();
	if (removeTarget) {
		peer.root.left.removeAt(0);
	} else {
		peer.root.right.insertAtEnd("unrelated");
	}
	provider.synchronizeMessages();
	const beforeUndo = visible(view.root);
	assert(target !== undefined);
	target.revert(false);
	const optimisticUndo = visible(view.root);
	provider.synchronizeMessages();
	const settledUndo = visible(view.root);
	const status = enumName(RevertibleStatus, target.status);
	target.dispose();
	off();
	return {
		id,
		removeTarget,
		beforeUndo,
		optimisticUndo,
		settledUndo,
		status,
		events,
		outcomes,
	};
}

async function captureSettlementOutcomes() {
	const fullyApplied = await captureConstraintScenario("constraint-satisfied", false);
	const violated = await captureConstraintScenario("constraint-violated", true);

	const provider = new TestTreeProviderLite(2);
	const sfOutcome = new SchemaFactory("org.watershed.shared-tree.undo-redo.outcomes");
	const StringArray = sfOutcome.array("Array", sfOutcome.string);
	const viewA = asAlpha(provider.trees[0].viewWith(
		new TreeViewConfiguration({ schema: StringArray, enableSchemaValidation: true }),
	));
	viewA.initialize([]);
	provider.synchronizeMessages();
	const viewB = asAlpha(provider.trees[1].viewWith(
		new TreeViewConfiguration({ schema: StringArray, enableSchemaValidation: true }),
	));
	const newContentOnly: string[] = [];
	viewB.events.on("changed", (metadata) => {
		if (metadata.isLocal) {
			metadata.events.on("settled", (outcome) =>
				newContentOnly.push(enumName(CommitOutcome, outcome)));
		}
	});
	viewA.runTransaction(
		() => viewA.root.insertAt(0, "A"),
		{ preconditions: [{ type: "noChange" }] },
	);
	viewB.runTransaction(
		() => viewB.root.insertAt(0, "B"),
		{ preconditions: [{ type: "noChange" }] },
	);
	provider.synchronizeMessages();
	assert.deepEqual(newContentOnly, ["NewContentOnly"]);

	const schemaProvider = new TestTreeProviderLite(3);
	const StringsAndBooleans = sfOutcome.array(
		"Array",
		[sfOutcome.string, sfOutcome.boolean],
	);
	const StringsAndNumbers = sfOutcome.array(
		"Array",
		[sfOutcome.string, sfOutcome.number],
	);
	const base = schemaProvider.trees[0].viewWith(
		new TreeViewConfiguration({ schema: StringArray, enableSchemaValidation: true }),
	);
	base.initialize([]);
	schemaProvider.synchronizeMessages();
	const schemaB = asAlpha(schemaProvider.trees[1].viewWith(
		new TreeViewConfiguration({ schema: StringsAndBooleans, enableSchemaValidation: true }),
	));
	const schemaC = asAlpha(schemaProvider.trees[2].viewWith(
		new TreeViewConfiguration({ schema: StringsAndNumbers, enableSchemaValidation: true }),
	));
	const fullyDropped: string[] = [];
	schemaC.events.on("changed", (metadata) => {
		if (metadata.isLocal) {
			metadata.events.on("settled", (outcome) =>
				fullyDropped.push(enumName(CommitOutcome, outcome)));
		}
	});
	schemaB.upgradeSchema();
	schemaC.upgradeSchema();
	schemaProvider.synchronizeMessages();
	assert.deepEqual(fullyDropped, ["FullyDropped"]);

	return caseFile(
		"undo-redo-constraints",
		"modular",
		{
			scenarios: [
				{ id: "constraint-satisfied", requiredNode: "present" },
				{ id: "constraint-violated", requiredNode: "removed" },
				{ id: "settlement-new-content-only", precondition: "noChange" },
				{ id: "settlement-fully-dropped", conflict: "schema" },
			],
		},
		[
			fullyApplied,
			violated,
			{ id: "settlement-new-content-only", outcomes: newContentOnly },
			{ id: "settlement-fully-dropped", outcomes: fullyDropped },
		],
		{
			satisfiedChanges: fullyApplied.events
				.filter((event) => Reflect.get(event, "local"))
				.map((event) => Reflect.get(event, "change")),
			violatedChanges: violated.events
				.filter((event) => Reflect.get(event, "local"))
				.map((event) => Reflect.get(event, "change")),
		},
	);
}

async function loadSnapshot(
	summary: Parameters<typeof MockSharedObjectServices.createFromSummary>[0],
	compressor: ReturnType<typeof serializeIdCompressor>,
	id: string,
) {
	const factory = treeFactory();
	const runtime = new MockFluidDataStoreRuntime({
		idCompressor: deserializeIdCompressor(compressor, createSessionId()),
	});
	const tree = await factory.load(
		runtime,
		id,
		MockSharedObjectServices.createFromSummary(summary),
		factory.attributes,
	);
	const view = asAlpha(tree.viewWith(
		new TreeViewConfiguration({ schema: Root, enableSchemaValidation: true }),
	));
	const events: object[] = [];
	view.events.on("changed", (metadata, getRevertible) => {
		events.push(eventRecord(metadata, getRevertible));
	});
	return { snapshot: visible(view.root), events };
}

async function captureReconnect() {
	const { provider, views: [view] } = createViews();
	const handles: RevertibleAlpha[] = [];
	const events: object[] = [];
	const off = view.events.on("changed", (metadata, getRevertible) => {
		events.push(eventRecord(metadata, getRevertible));
		if (metadata.isLocal && getRevertible !== undefined) {
			handles.push(getRevertible());
		}
	});
	view.root.title = "connected-change";
	provider.synchronizeMessages();
	const original = handles[0];
	assert(original !== undefined);
	provider.trees[0].containerRuntime.connected = false;
	const disconnectedStatus = enumName(RevertibleStatus, original.status);
	provider.trees[0].containerRuntime.connected = true;
	provider.synchronizeMessages();
	const reconnectedStatus = enumName(RevertibleStatus, original.status);
	original.revert();
	provider.synchronizeMessages();
	const undoSnapshot = visible(view.root);
	const undoSummary = (await provider.trees[0].summarize(true)).summary;
	const undoCompressor = serializeIdCompressor(provider.getCompressor(provider.trees[0]), false);
	const undoLoaded = await loadSnapshot(undoSummary, undoCompressor, "undo-loaded");

	const undoHandle = handles.find((handle) => handle !== original);
	assert(undoHandle !== undefined);
	undoHandle.revert();
	provider.synchronizeMessages();
	const redoSnapshot = visible(view.root);
	const redoSummary = (await provider.trees[0].summarize(true)).summary;
	const redoCompressor = serializeIdCompressor(provider.getCompressor(provider.trees[0]), false);
	const redoLoaded = await loadSnapshot(redoSummary, redoCompressor, "redo-loaded");

	assert.equal(disconnectedStatus, "Valid");
	assert.equal(reconnectedStatus, "Valid");
	assert.deepEqual(undoLoaded.snapshot, undoSnapshot);
	assert.deepEqual(redoLoaded.snapshot, redoSnapshot);
	assert.deepEqual(undoLoaded.events, []);
	assert.deepEqual(redoLoaded.events, []);
	off();
	return caseFile(
		"undo-redo-reconnect",
		"summary",
		{
			scenarios: [
				{ id: "same-view-reconnect", handle: "retained" },
				{ id: "load-after-undo", oldHandle: "absent" },
				{ id: "load-after-redo", oldHandle: "absent" },
			],
		},
		[{
			id: "reconnect-and-reload",
			disconnectedStatus,
			reconnectedStatus,
			undoSnapshot,
			redoSnapshot,
			undoLoaded,
			redoLoaded,
			events,
		}],
		{
			undoSummary,
			redoSummary,
			encodedChanges: events
				.filter((event) => Reflect.get(event, "local"))
				.map((event) => Reflect.get(event, "change")),
		},
	);
}

describe("Watershed undo and redo oracle", () => {
	it("captures the pinned undo and redo contract", async () => {
		const output = process.env.WATERSHED_ORACLE_OUTPUT;
		assert(output !== undefined && isAbsolute(output), "WATERSHED_ORACLE_OUTPUT must be absolute");
		assert.equal(process.env.WATERSHED_ORACLE_COMMIT, reference.commit);
		mkdirSync(output, { recursive: true });
		const cases = [
			await captureLifetime(),
			await captureKinds(),
			await captureFields(),
			await captureSettlementOutcomes(),
			await captureReconnect(),
		];
		writeFileSync(
			join(output, "undo-redo-cases.json"),
			`${JSON.stringify(cases, undefined, 2)}\n`,
			"utf8",
		);
	});
});
