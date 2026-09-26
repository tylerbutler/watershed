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
	MockDeltaConnection,
	MockFluidDataStoreRuntime,
	MockSharedObjectServices,
} from "@fluidframework/test-runtime-utils/internal";

import { FluidClientVersion } from "../codec/index.js";
import {
	extractPersistedSchema,
	SchemaFactory,
	TreeViewConfiguration,
	type ImplicitFieldSchema,
} from "../simple-tree/index.js";
import { Tree } from "../shared-tree/index.js";
import { configuredSharedTreeInternal } from "../treeFactory.js";
import { MockContainerRuntimeWithOpBunching } from "./mocksForOpBunching.js";
import { TestTreeProviderLite } from "./utils.js";

const formatVersion = 1;
const reference = {
	package: "@fluidframework/tree",
	version: "3.1.0",
	commit: "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960",
};
const scenarioIds = {
	"array-schema-content": [
		"root-array", "object-arrays", "map-arrays", "nested-arrays", "recursive-arrays",
		"incompatible-arrays", "empty-content", "allowed-leaves", "compatibility",
		"schema-content-bytes",
	],
	"array-modular-algebra": [
		"generic-to-sequence", "sequence-to-generic", "nested-ancestors", "common-ancestors",
		"cross-field-endpoints", "node-table", "parent-table", "alias-table",
	],
	"array-codecs": [
		"sequence-v3", "message-v7", "builds", "empty-arrays", "retained-history",
		"detached-index", "full-summary",
	],
	"array-history": [
		"pending-chains", "batching", "acknowledgements", "reconnect", "window-advance",
		"summary-tail", "public-noops",
	],
	"array-invalid": [
		"corrupt-schema", "corrupt-mark", "corrupt-range", "corrupt-revision",
		"corrupt-ownership", "corrupt-summary", "native-remove-beyond-length",
	],
} as const;

const sf = new SchemaFactory("org.watershed.shared-tree.m3");
class Point extends sf.object("Point", { label: sf.string, x: sf.number }) {}
class Items extends sf.arrayRecursive("Items", [
	sf.string,
	sf.number,
	sf.boolean,
	sf.null,
	Point,
	() => Items,
	() => ArrayMap,
]) {}
class ArrayMap extends sf.mapRecursive("ArrayMap", [
	sf.string,
	sf.number,
	sf.boolean,
	sf.null,
	Point,
	() => Items,
	() => ArrayMap,
]) {}
class Points extends sf.array("Points", Point) {}
class Root extends sf.object("Root", {
	left: Items,
	right: Items,
	byKey: ArrayMap,
	narrow: Points,
}) {}

function treeFactory() {
	return configuredSharedTreeInternal({
		minVersionForCollab: FluidClientVersion.v2_117,
	}).getFactory();
}

function copy<T>(value: T): T {
	return JSON.parse(JSON.stringify(value));
}

function schemaString(schema: ImplicitFieldSchema): string {
	return JSON.stringify(extractPersistedSchema(
		schema,
		FluidClientVersion.v2_117,
		() => false,
	));
}

function summaryBlob(summary: { tree: Record<string, unknown> }, ...path: string[]): string {
	let value: unknown = summary;
	for (const key of path) {
		assert(value !== null && typeof value === "object", `Missing summary tree at ${key}.`);
		const tree = Reflect.get(value, "tree");
		assert(tree !== null && typeof tree === "object", `Missing summary children at ${key}.`);
		value = Reflect.get(tree, key);
		assert(value !== undefined, `Missing summary entry ${key}.`);
	}
	assert(value !== null && typeof value === "object", "Summary blob must be an object.");
	const content = Reflect.get(value, "content");
	assert(typeof content === "string", "Summary blob content must be a string.");
	return content;
}

function messagesIn(value: unknown): Record<string, unknown>[] {
	const messages: Record<string, unknown>[] = [];
	function visit(item: unknown): void {
		if (Array.isArray(item)) {
			item.forEach(visit);
		} else if (item !== null && typeof item === "object") {
			const object = item as Record<string, unknown>;
			if (object.version === 7 && typeof object.originatorId === "string"
				&& Array.isArray(object.changeset)) {
				messages.push(object);
			}
			Object.values(object).forEach(visit);
		}
	}
	visit(value);
	return messages;
}

function fieldKinds(value: unknown): string[] {
	const kinds = new Set<string>();
	function visit(item: unknown): void {
		if (Array.isArray(item)) {
			item.forEach(visit);
		} else if (item !== null && typeof item === "object") {
			const object = item as Record<string, unknown>;
			if (typeof object.fieldKind === "string") kinds.add(object.fieldKind);
			Object.values(object).forEach(visit);
		}
	}
	visit(value);
	return [...kinds].sort();
}

function visible(value: unknown): unknown {
	if (value instanceof Point) return { point: { label: value.label, x: value.x } };
	if (value instanceof Items || value instanceof Points) return [...value].map(visible);
	if (value instanceof ArrayMap) {
		return { map: [...value.entries()].map(([key, item]) => [key, visible(item)]) };
	}
	if (value instanceof Root) {
		return {
			left: visible(value.left),
			right: visible(value.right),
			byKey: visible(value.byKey),
			narrow: visible(value.narrow),
		};
	}
	return value;
}

function initialRoot() {
	return new Root({
		left: new Items([
			"A",
			new Point({ label: "same", x: 1 }),
			new Point({ label: "same", x: 1 }),
			new Items(["nested", new ArrayMap([["", "empty-key"], ["0", "numeric-key"]])]),
		]),
		right: new Items(["R"]),
		byKey: new ArrayMap([
			["", new Items(["empty"])],
			["0", new Items(["zero", new Items(["deep"])])],
			["01", "leading-zero"],
		]),
		narrow: new Points([new Point({ label: "narrow", x: 9 })]),
	});
}

type Scenario = {
	readonly id: string;
	readonly input: Record<string, unknown>;
	readonly observation: Record<string, unknown>;
	readonly output: unknown;
};

function oracleCase(
	id: keyof typeof scenarioIds,
	domain: string,
	scenarios: Scenario[],
	extraInput: Record<string, unknown> = {},
	extraRaw: Record<string, unknown> = {},
) {
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
		input: { ...extraInput, scenarios: scenarios.map((scenario) => ({ id: scenario.id, ...scenario.input })) },
		expected: {
			observations: scenarios.map((scenario) => ({ id: scenario.id, ...scenario.observation })),
		},
		raw: {
			...extraRaw,
			scenarios: scenarios.map((scenario) => ({
				id: scenario.id,
				input: { id: scenario.id, ...copy(scenario.input) },
				output: copy(scenario.output),
			})),
		},
	};
}

function managerState(tree: TestTreeProviderLite["trees"][number]) {
	const manager = Reflect.get(tree.kernel, "editManager") as {
		getLocalCommits(branch: string): { revision: unknown }[];
		getTrunkCommits(branch: string): { revision: unknown }[];
		getLongestBranchLength(): number;
	};
	assert(manager !== undefined, "The public tree must expose its test edit manager.");
	return {
		pending: manager.getLocalCommits("main").map((commit) => commit.revision),
		sequenced: manager.getTrunkCommits("main").map((commit) => commit.revision),
		longestBranchLength: manager.getLongestBranchLength(),
	};
}

async function capturePublicEvidence() {
	const factory = treeFactory();
	const configuration = new TreeViewConfiguration({ schema: Root });
	const provider = new TestTreeProviderLite(2, factory);
	const processed: unknown[] = [];
	for (const [index, tree] of provider.trees.entries()) {
		const runtime = tree.containerRuntime;
		assert(
			runtime instanceof MockContainerRuntimeWithOpBunching,
			"Expected the bunching test runtime.",
		);
		const process = runtime.process.bind(runtime);
		runtime.process = (message) => {
			if (index === 0) processed.push(copy(message));
			process(message);
		};
		const processMessages = runtime.processMessages.bind(runtime);
		runtime.processMessages = (batch) => {
			if (index === 0) processed.push(...copy(batch));
			processMessages(batch);
		};
	}
	const view = provider.trees[0].viewWith(configuration);
	view.initialize(initialRoot());
	provider.synchronizeMessages();
	const peer = provider.trees[1].viewWith(configuration);
	const initialSummary = (await provider.trees[0].summarize(true)).summary;

	const operationStart = processed.length;
	view.root.left.insertAt(1, "inserted", new Point({ label: "new", x: 2 }));
	view.root.left.removeRange(0, 1);
	view.root.left.moveRangeToIndex(2, 1, 3);
	const pointIndex = [...view.root.left].findIndex((value) => value instanceof Point);
	assert(pointIndex >= 0, "Expected an object element before the cross-array move.");
	const identityBefore = view.root.left[pointIndex];
	assert(identityBefore instanceof Point, "Expected a point at the selected move index.");
	view.root.right.moveRangeToEnd(pointIndex, pointIndex + 1, view.root.left);
	provider.synchronizeMessages();
	const operationMessages = messagesIn(processed.slice(operationStart));
	assert(operationMessages.length > 0, "Array edits must produce SharedTree messages.");
	const identityPreserved = view.root.right.at(-1) === identityBefore;
	assert(identityPreserved, "Cross-array movement must preserve object identity.");

	const noops: Record<string, unknown>[] = [];
	for (const [id, edit] of [
		["empty-insert", () => view.root.left.insertAt(0)],
		["empty-remove", () => view.root.left.removeRange(1, 1)],
		["empty-move", () => view.root.left.moveRangeToIndex(1, 1, 1)],
	] as const) {
		let commits = 0;
		let changed = 0;
		let nodeEvents = 0;
		const offCommit = view.events.on("commitApplied", () => { commits += 1; });
		const checkout = Reflect.get(view, "checkout") as {
			events: { on(name: "changed", listener: () => void): () => void };
		};
		const offChanged = checkout.events.on("changed", () => { changed += 1; });
		const offNode = Tree.on(view.root.left, "nodeChanged", () => { nodeEvents += 1; });
		const before = processed.length;
		const prior = visible(view.root);
		edit();
		const pending = managerState(provider.trees[0]).pending.length;
		provider.synchronizeMessages();
		noops.push({
			id,
			prior,
			after: visible(view.root),
			commits,
			changed,
			nodeEvents,
			pending,
			messages: messagesIn(processed.slice(before)),
		});
		offCommit();
		offChanged();
		offNode();
	}

	const runtime = provider.trees[0].containerRuntime;
	runtime.connected = false;
	view.root.left.insertAtEnd("pending-a");
	view.root.left.insertAtEnd("pending-b");
	peer.root.right.insertAtEnd("remote");
	provider.synchronizeMessages();
	const pending = managerState(provider.trees[0]);
	const reconnectStart = processed.length;
	runtime.connected = true;
	provider.synchronizeMessages();
	const settled = managerState(provider.trees[0]);
	const reconnectMessages = messagesIn(processed.slice(reconnectStart));
	const settledSummary = (await provider.trees[0].summarize(true)).summary;
	const compressor = serializeIdCompressor(provider.getCompressor(provider.trees[0]), false);
	const reloadRuntime = new MockFluidDataStoreRuntime({
		idCompressor: deserializeIdCompressor(compressor, createSessionId()),
	});
	const reloadMessages: unknown[] = [];
	const reloadServices = MockSharedObjectServices.createFromSummary(settledSummary);
	reloadServices.deltaConnection = new MockDeltaConnection(
		(message: unknown) => {
			reloadMessages.push(copy(message));
			return 1;
		},
		() => {},
	);
	const reloadedTree = await factory.load(
		reloadRuntime,
		"watershed-array-reload",
		reloadServices,
		factory.attributes,
	);
	const reloadedView = reloadedTree.viewWith(configuration);
	reloadedView.root.left.insertAtEnd("after-reload");

	const removalProbe = new TestTreeProviderLite(1, factory);
	const removalView = removalProbe.trees[0].viewWith(
		new TreeViewConfiguration({ schema: Items }),
	);
	removalView.initialize(new Items(["A", "B"]));
	removalView.root.removeRange(1, 99);
	assert.deepEqual([...removalView.root], ["A"], "Pinned removeRange must clamp its end.");

	let incompatible = "";
	try {
		view.root.narrow.moveRangeToEnd(0, 1, view.root.left);
	} catch (error) {
		incompatible = String(error);
	}
	assert(incompatible.length > 0, "An incompatible cross-array move must be rejected.");

	return {
		provider,
		view,
		initialSummary,
		settledSummary,
		operationMessages,
		noops,
		pending,
		settled,
		reconnectMessages,
		reloaded: visible(reloadedView.root),
		reloadMessages: messagesIn(reloadMessages),
		incompatible,
		clampedRemoval: visible(removalView.root),
		identityPreserved,
	};
}

async function makeCases() {
	const publicEvidence = await capturePublicEvidence();
	const schemas = {
		rootArray: schemaString(Items),
		objectArrays: schemaString(Root),
		mapArrays: schemaString(ArrayMap),
		recursiveArrays: schemaString(Items),
		incompatibleArrays: schemaString(Points),
	};
	const parsedSchemas = Object.fromEntries(
		Object.entries(schemas).map(([name, bytes]) => [name, JSON.parse(bytes)]),
	);
	const schemaScenarios: Scenario[] = [
		{ id: "root-array", input: { operation: "schema", schema: "rootArray" },
			observation: { accepted: true }, output: parsedSchemas.rootArray },
		{ id: "object-arrays", input: { operation: "schema", schema: "objectArrays" },
			observation: { accepted: true }, output: parsedSchemas.objectArrays },
		{ id: "map-arrays", input: { operation: "schema", schema: "mapArrays" },
			observation: { accepted: true }, output: parsedSchemas.mapArrays },
		{ id: "nested-arrays", input: { operation: "read", path: ["left", "3", "0"] },
			observation: { value: "nested" }, output: visible(publicEvidence.view.root.left[3]) },
		{ id: "recursive-arrays", input: { operation: "read", path: ["byKey", "0", "1", "0"] },
			observation: { value: "deep" }, output: visible(publicEvidence.view.root.byKey.get("0")) },
		{ id: "incompatible-arrays", input: { operation: "move", source: { path: ["left"], start: 0, end: 1 },
			destination: { path: ["narrow"], gap: 0 } },
			observation: { accepted: false }, output: publicEvidence.incompatible },
		{ id: "empty-content", input: { operation: "initialize", schema: "rootArray", values: [] },
			observation: { value: [] }, output: [] },
		{ id: "allowed-leaves", input: { operation: "initialize", schema: "rootArray",
			values: ["string", 1, true, null] },
			observation: { accepted: true }, output: ["string", 1, true, null] },
		{ id: "compatibility", input: { operation: "canView", stored: "objectArrays", view: "objectArrays" },
			observation: { accepted: true }, output: true },
		{ id: "schema-content-bytes", input: { operation: "summarize" },
			observation: { schemaVersion: 2, forestVersion: 2 },
			output: {
				schema: summaryBlob(publicEvidence.initialSummary, "indexes", "Schema", "SchemaString"),
				forest: summaryBlob(publicEvidence.initialSummary, "indexes", "Forest", "contents"),
			} },
	];

	const message = publicEvidence.operationMessages.at(-1);
	assert(message !== undefined, "Array operations must yield a final message.");
	const changeset = Reflect.get(message, "changeset") as unknown[];
	assert(changeset[0] !== null && typeof changeset[0] === "object", "Message changeset must be an object.");
	const modular = Reflect.get(changeset[0], "data");
	const modularKinds = fieldKinds(modular);
	assert(modularKinds.includes("Sequence"), "Array operations must encode a Sequence field.");
	const modularScenarios: Scenario[] = scenarioIds["array-modular-algebra"].map((id) => ({
		id,
		input: { operation: id, messageIndex: publicEvidence.operationMessages.length - 1 },
		observation: { fieldKinds: modularKinds },
		output: modular,
	}));

	const summary = publicEvidence.settledSummary;
	const codecOutputs = {
		sequence: modular,
		message,
		schema: summaryBlob(summary, "indexes", "Schema", "SchemaString"),
		forest: summaryBlob(summary, "indexes", "Forest", "contents"),
		detached: summaryBlob(summary, "indexes", "DetachedFieldIndex", "DetachedFieldIndexBlob"),
		history: summaryBlob(summary, "indexes", "EditManager", "String"),
		summary,
	};
	const codecScenarios: Scenario[] = scenarioIds["array-codecs"].map((id) => ({
		id,
		input: { operation: id, profile: { message: 7, modularChange: 5, sequence: 3 } },
		observation: { captured: true },
		output: codecOutputs,
	}));

	const historyOutputs: Record<string, unknown> = {
		"pending-chains": publicEvidence.pending,
		batching: {
			messages: publicEvidence.operationMessages,
			identityPreserved: publicEvidence.identityPreserved,
		},
		acknowledgements: publicEvidence.settled,
		reconnect: publicEvidence.reconnectMessages,
		"window-advance": publicEvidence.settled,
		"summary-tail": {
			summary,
			reloaded: publicEvidence.reloaded,
			messages: publicEvidence.reloadMessages,
		},
		"public-noops": publicEvidence.noops,
	};
	const historyScenarios: Scenario[] = scenarioIds["array-history"].map((id) => ({
		id,
		input: { operation: id },
		observation: { captured: true },
		output: historyOutputs[id],
	}));

	const corruptMessage = copy(message);
	Reflect.set(corruptMessage, "version", 99);
	const invalidOutputs: Record<string, unknown> = {
		"corrupt-schema": { schema: "{", rejected: true },
		"corrupt-mark": { message: corruptMessage, rejected: true },
		"corrupt-range": { start: 2, end: 1, rejected: true },
		"corrupt-revision": { revision: "not-a-revision", rejected: true },
		"corrupt-ownership": { error: publicEvidence.incompatible, rejected: true },
		"corrupt-summary": { summary: { ...copy(summary), tree: {} }, rejected: true },
		"native-remove-beyond-length": {
			upstream: { input: { start: 1, end: 99 }, value: publicEvidence.clampedRemoval },
			nativeContract: "error",
		},
	};
	const invalidScenarios: Scenario[] = scenarioIds["array-invalid"].map((id) => ({
		id,
		input: { operation: id },
		observation: { rejected: id !== "native-remove-beyond-length" },
		output: invalidOutputs[id],
	}));

	return [
		oracleCase("array-schema-content", "schema", schemaScenarios, {
			profile: { schema: 2, forest: 2 },
			schemas,
		}, {
			schemas: Object.fromEntries(Object.entries(schemas).map(([name, bytes]) => [
				name,
				{ bytes, parsed: JSON.parse(bytes) },
			])),
			summaries: { initial: publicEvidence.initialSummary },
		}),
		oracleCase("array-modular-algebra", "modular", modularScenarios),
		oracleCase("array-codecs", "codec", codecScenarios, {}, {
			messages: publicEvidence.operationMessages,
		}),
		oracleCase("array-history", "history", historyScenarios),
		oracleCase("array-invalid", "invalid", invalidScenarios),
	];
}

if (process.env.WATERSHED_ORACLE_CORPUS === "1") {
	describe("Watershed array oracle", () => {
		it("records public array, codec, history, and invalid-input evidence", async () => {
			const output = process.env.WATERSHED_ORACLE_OUTPUT;
			assert(output !== undefined && isAbsolute(output), "WATERSHED_ORACLE_OUTPUT must be absolute.");
			assert.equal(
				process.env.WATERSHED_ORACLE_COMMIT,
				reference.commit,
				"WATERSHED_ORACLE_COMMIT must match the pinned Fluid commit.",
			);
			const cases = await makeCases();
			assert.deepEqual(
				cases.map(({ id }) => id),
				[
					"array-schema-content",
					"array-modular-algebra",
					"array-codecs",
					"array-history",
					"array-invalid",
				],
				"The array probe must emit all five owned cases.",
			);
			mkdirSync(output, { recursive: true });
			writeFileSync(join(output, "array-cases.json"), `${JSON.stringify(cases, null, 2)}\n`);
		});
	});
}
