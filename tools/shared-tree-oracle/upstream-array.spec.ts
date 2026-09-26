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
	toIdCompressorWithCore,
} from "@fluidframework/id-compressor/internal";
import type { SessionSpaceCompressedId } from "@fluidframework/id-compressor";
import {
	MockDeltaConnection,
	MockFluidDataStoreRuntime,
	MockSharedObjectServices,
} from "@fluidframework/test-runtime-utils/internal";

import { FluidClientVersion, FormatValidatorNoOp } from "../codec/index.js";
import {
	tagChange,
	type RevisionTag,
	type TaggedChange,
} from "../core/index.js";
import {
	extractPersistedSchema,
	SchemaFactory,
	TreeViewConfiguration,
	type ImplicitFieldSchema,
} from "../simple-tree/index.js";
import {
	intoDelta,
	schemaCodecBuilder,
	type ModularChangeset,
} from "../feature-libraries/index.js";
import { Tree } from "../shared-tree/index.js";
import { configuredSharedTreeInternal } from "../treeFactory.js";
import {
	crossFieldCoordinationInput,
	replayArrayModularInput,
} from "./watershedArraySupport.js";
import { MockContainerRuntimeWithOpBunching } from "./mocksForOpBunching.js";
import { mintRevisionTag, testIdCompressor, TestTreeProviderLite } from "./utils.js";

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

function executed(run: () => unknown): { accepted: true; value: unknown } | {
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

async function executedAsync(run: () => Promise<unknown>): Promise<
	{ accepted: true; value: unknown } | { accepted: false; error: string }
> {
	try {
		return { accepted: true, value: copy(await run()) };
	} catch (error) {
		return {
			accepted: false,
			error: error instanceof Error ? `${error.name}: ${error.message}` : String(error),
		};
	}
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

function modularStructure(change: ModularChangeset) {
	const delta = intoDelta(tagChange(change, undefined));
	return {
		maxId: change.maxId ?? null,
		revisions: (change.revisions ?? []).map((item) => ({
			revision: item.revision,
			rollbackOf: item.rollbackOf ?? null,
		})),
		fieldKinds: fieldKinds(change),
		fields: [...change.fieldChanges].map(([key, field]) => ({
			key: String(key),
			kind: String(field.fieldKind),
		})),
		nodes: [...change.nodeChanges.entries()].length,
		parents: [...change.nodeToParent.entries()].length,
		aliases: [...change.nodeAliases.entries()].length,
		crossFieldKeys: change.crossFieldKeys.entries().map((entry) => ({
			key: copy(entry.start),
			count: entry.length,
			field: copy(entry.value),
		})),
		delta: {
			fields: [...(delta.fields ?? [])].map(([key, field]) => ({
				key: String(key),
				marks: field.marks.map((mark) => ({
					count: mark.count,
					attach: mark.attach === undefined ? null : copy(mark.attach),
					detach: mark.detach === undefined ? null : copy(mark.detach),
					nestedFields: mark.fields?.size ?? 0,
				})),
			})),
			builds: delta.build?.length ?? 0,
			refreshers: delta.refreshers?.length ?? 0,
			renames: delta.rename?.length ?? 0,
			destroys: delta.destroy?.length ?? 0,
		},
	};
}

function visible(value: unknown): unknown {
	if (value instanceof Point) return { point: { label: value.label, x: value.x } };
	if (value instanceof Items || value instanceof Points) {
		return Array.from({ length: value.length }, (_, index) => visible(value[index]));
	}
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
		input: {
			...extraInput,
			scenarios: scenarios.map((scenario) => ({
				id: scenario.id,
				...copy(scenario.input),
				operation: scenario.input.operation,
				initialState: scenario.input.initialState ?? null,
				operands: id === "array-modular-algebra"
					? copy(scenario.input.operands)
					: copy(scenario.input),
				revisions: scenario.input.revisions ?? [],
				allocator: scenario.input.allocator ?? { nextLocalId: 0 },
				compressor: scenario.input.compressor ?? { mode: "ongoing", session: null },
				sequencing: scenario.input.sequencing ?? {
					sequenceNumber: 0,
					referenceSequenceNumber: 0,
					minimumSequenceNumber: 0,
				},
				schedule: scenario.input.schedule ?? [{ step: scenario.input.operation }],
			})),
		},
		expected: {
			observations: scenarios.map((scenario) => ({
				id: scenario.id,
				executed: true,
				...scenario.observation,
				result: copy(scenario.output),
			})),
		},
		raw: {
			...extraRaw,
			scenarios: scenarios.map((scenario) => ({
				id: scenario.id,
				input: {
					id: scenario.id,
					...copy(scenario.input),
					operation: scenario.input.operation,
					initialState: copy(scenario.input.initialState ?? null),
					operands: id === "array-modular-algebra"
					? copy(scenario.input.operands)
					: copy(scenario.input),
					revisions: copy(scenario.input.revisions ?? []),
					allocator: copy(scenario.input.allocator ?? { nextLocalId: 0 }),
					compressor: copy(scenario.input.compressor ?? { mode: "ongoing", session: null }),
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
	const operationCommits = (Reflect.get(provider.trees[0].kernel, "editManager") as {
		getLocalCommits(branch: string): {
			revision: RevisionTag;
			change: {
				changes: readonly {
					type: "data" | "schema";
					innerChange: unknown;
				}[];
			};
		}[];
	}).getLocalCommits("main").map((commit) => {
		const data = commit.change.changes.filter(({ type }) => type === "data");
		assert.equal(data.length, 1, "Each array edit must contain one modular data change.");
		return {
			revision: commit.revision,
			change: data[0].innerChange as ModularChangeset,
		};
	});
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

	async function captureIdentityEdit(id: string, edit: (items: Items) => void) {
		const editProvider = new TestTreeProviderLite(2, factory);
		const editView = editProvider.trees[0].viewWith(
			new TreeViewConfiguration({ schema: Items }),
		);
		editView.initialize(new Items([
			new Point({ label: "equal", x: 1 }),
			new Point({ label: "equal", x: 1 }),
			new Point({ label: "equal", x: 1 }),
		]));
		editProvider.synchronizeMessages();
		const editProcessed: unknown[] = [];
		for (const [index, tree] of editProvider.trees.entries()) {
			const editRuntime = tree.containerRuntime;
			assert(editRuntime instanceof MockContainerRuntimeWithOpBunching,
				"Expected the bunching test runtime.");
			const process = editRuntime.process.bind(editRuntime);
			editRuntime.process = (item) => {
				if (index === 0) editProcessed.push(copy(item));
				process(item);
			};
		}
		const identities = Array.from({ length: editView.root.length }, (_, index) =>
			editView.root[index]);
		const before = visible(editView.root);
		let commits = 0;
		let changed = 0;
		let nodeEvents = 0;
		const offCommit = editView.events.on("commitApplied", () => { commits += 1; });
		const checkout = Reflect.get(editView, "checkout") as {
			events: { on(name: "changed", listener: () => void): () => void };
		};
		const offChanged = checkout.events.on("changed", () => { changed += 1; });
		const offNode = Tree.on(editView.root, "nodeChanged", () => { nodeEvents += 1; });
		edit(editView.root);
		const pendingState = managerState(editProvider.trees[0]);
		editProvider.synchronizeMessages();
		const after = visible(editView.root);
		const identityOrder = Array.from({ length: editView.root.length }, (_, index) =>
			identities.indexOf(editView.root[index]));
		offCommit();
		offChanged();
		offNode();
		return {
			id,
			before,
			after,
			identityOrder,
			visibleEqual: JSON.stringify(before) === JSON.stringify(after),
			commits,
			changed,
			nodeEvents,
			pending: pendingState.pending.length,
			revisions: pendingState.pending,
			messages: messagesIn(editProcessed),
		};
	}
	const identityEdits = [
		await captureIdentityEdit("equal-value-swap", (items) =>
			items.moveRangeToIndex(3, 1, 2)),
		await captureIdentityEdit("public-interior-move", (items) =>
			items.moveRangeToIndex(1, 0, 3)),
	];

	const batchProvider = new TestTreeProviderLite(2, factory);
	const batchView = batchProvider.trees[0].viewWith(configuration);
	batchView.initialize(initialRoot());
	batchProvider.synchronizeMessages();
	const batchProcessed: unknown[] = [];
	const batchRuntime = batchProvider.trees[0].containerRuntime;
	assert(batchRuntime instanceof MockContainerRuntimeWithOpBunching,
		"Expected the bunching test runtime.");
	const batchProcess = batchRuntime.process.bind(batchRuntime);
	batchRuntime.process = (item) => {
		batchProcessed.push(copy(item));
		batchProcess(item);
	};
	Tree.runTransaction(batchView, () => {
		batchView.root.left.insertAtEnd("batch-a");
		batchView.root.right.insertAtEnd("batch-b");
	});
	const batchPending = managerState(batchProvider.trees[0]);
	batchProvider.synchronizeMessages();
	const batchMessages = messagesIn(batchProcessed);
	assert.equal(batchMessages.length, 1, "A transaction must submit one SharedTree message.");

	const emptyProvider = new TestTreeProviderLite(1, factory);
	const emptyView = emptyProvider.trees[0].viewWith(configuration);
	emptyView.initialize(new Root({
		left: new Items([]),
		right: new Items([]),
		byKey: new ArrayMap([["empty", new Items([])]]),
		narrow: new Points([]),
	}));
	emptyProvider.synchronizeMessages();
	const emptySummary = (await emptyProvider.trees[0].summarize(true)).summary;

	const retainedProvider = new TestTreeProviderLite(2, factory);
	const retainedView = retainedProvider.trees[0].viewWith(configuration);
	retainedView.initialize(initialRoot());
	retainedProvider.synchronizeMessages();
	retainedProvider.trees[1].containerRuntime.connected = false;
	retainedView.root.left.removeRange(0, 2);
	retainedProvider.synchronizeMessages();
	const retainedSummary = (await retainedProvider.trees[0].summarize(true)).summary;

	const tailProvider = new TestTreeProviderLite(2, factory);
	const tailView = tailProvider.trees[0].viewWith(configuration);
	tailView.initialize(initialRoot());
	tailProvider.synchronizeMessages();
	const tailSummary = (await tailProvider.trees[0].summarize(true)).summary;
	const tailProcessed: unknown[] = [];
	const tailPeerRuntime = tailProvider.trees[1].containerRuntime;
	assert(tailPeerRuntime instanceof MockContainerRuntimeWithOpBunching,
		"Expected the bunching test runtime.");
	const tailProcessMessages = tailPeerRuntime.processMessages.bind(tailPeerRuntime);
	const tailProcess = tailPeerRuntime.process.bind(tailPeerRuntime);
	tailPeerRuntime.process = (message) => {
		tailProcessed.push(copy(message));
		tailProcess(message);
	};
	tailPeerRuntime.processMessages = (batch) => {
		tailProcessed.push(copy(batch));
		tailProcessMessages(batch);
	};
	tailView.root.right.insertAtEnd("tail");
	tailProvider.synchronizeMessages();
	assert(tailProcessed.length > 0, "The summary-tail probe must capture a remote delivery.");
	const tailMessages = messagesIn(tailProcessed);
	assert.equal(tailMessages.length, 1, "The summary-tail probe must capture one tree message.");
	const tailEnvelope = tailProcessed.find((item) =>
		item !== null && typeof item === "object"
		&& Reflect.get(Reflect.get(item, "contents") as object, "version") === 7
	) as Record<string, unknown> | undefined;
	assert(tailEnvelope !== undefined, "The summary-tail probe must retain the tree envelope.");
	const tailCompressor = serializeIdCompressor(
		tailProvider.getCompressor(tailProvider.trees[0]),
		false,
	);
	const tailRuntime = new MockFluidDataStoreRuntime({
		idCompressor: deserializeIdCompressor(tailCompressor, createSessionId()),
	});
	const continuationSubmitted: unknown[] = [];
	const tailServices = MockSharedObjectServices.createFromSummary(tailSummary);
	tailServices.deltaConnection = new MockDeltaConnection((message) => {
		continuationSubmitted.push(copy(message));
		return 3;
	}, () => {});
	const tailTree = await factory.load(
		tailRuntime,
		"watershed-array-tail",
		tailServices,
		factory.attributes,
	);
	const tailReader = tailTree.viewWith(configuration);
	const tailKernel = Reflect.get(tailTree, "kernel") as unknown as {
		processMessagesCore(batch: unknown, local: boolean): void;
	};
	function deliver(
		kernel: { processMessagesCore(batch: unknown, local: boolean): void },
		contents: unknown,
		envelope: {
			clientId: string;
			clientSequenceNumber: number;
			referenceSequenceNumber: number;
			sequenceNumber: number;
			minimumSequenceNumber: number;
		},
	) {
		kernel.processMessagesCore({
			envelope: {
				contents,
				...envelope,
				timestamp: 0,
				type: "op",
			},
			messagesContent: [{
				contents,
				localOpMetadata: undefined,
				clientSequenceNumber: envelope.clientSequenceNumber,
			}],
		}, false);
	}
	const tailSequence = {
		clientId: String(tailEnvelope.clientId),
		clientSequenceNumber: Number(tailEnvelope.clientSequenceNumber),
		referenceSequenceNumber: Number(tailEnvelope.referenceSequenceNumber),
		sequenceNumber: Number(tailEnvelope.sequenceNumber),
		minimumSequenceNumber: Number(tailEnvelope.minimumSequenceNumber),
	};
	deliver(tailKernel, tailMessages[0], tailSequence);
	const readerAfterTail = visible(tailReader.root);
	tailReader.root.left.insertAtEnd("reader-continuation");
	const readerAfterContinuation = visible(tailReader.root);
	const continuationMessages = messagesIn(continuationSubmitted);
	assert.equal(continuationMessages.length, 1,
		"The fresh reader must submit one continuation message.");
	assert(tailRuntime.idCompressor !== undefined,
		"The fresh reader runtime must retain its ID compressor.");
	const continuationSession = tailRuntime.idCompressor.localSessionId;
	const continuationCompressorCore = toIdCompressorWithCore(tailRuntime.idCompressor);
	continuationCompressorCore.finalizeCreationRange(
		continuationCompressorCore.takeNextCreationRange(),
	);
	const continuationCompressor = serializeIdCompressor(tailRuntime.idCompressor, false);
	const verifierRuntime = new MockFluidDataStoreRuntime({
		idCompressor: deserializeIdCompressor(continuationCompressor, createSessionId()),
	});
	const verifierTree = await factory.load(
		verifierRuntime,
		"watershed-array-tail-verifier",
		MockSharedObjectServices.createFromSummary(tailSummary),
		factory.attributes,
	);
	const verifierView = verifierTree.viewWith(configuration);
	const verifierKernel = Reflect.get(verifierTree, "kernel") as unknown as {
		processMessagesCore(batch: unknown, local: boolean): void;
	};
	deliver(verifierKernel, tailMessages[0], tailSequence);
	deliver(verifierKernel, continuationMessages[0], {
		clientId: continuationSession,
		clientSequenceNumber: 1,
		referenceSequenceNumber: tailSequence.sequenceNumber,
		sequenceNumber: tailSequence.sequenceNumber + 1,
		minimumSequenceNumber: tailSequence.minimumSequenceNumber,
	});
	assert.deepEqual(visible(verifierView.root), readerAfterContinuation,
		"An independently loaded reader must apply the tail and continuation.");

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
		operationCommits,
		identityEdits,
		batching: {
			pending: batchPending,
			messages: batchMessages,
			writer: visible(batchView.root),
			peer: visible(batchProvider.trees[1].viewWith(configuration).root),
		},
		emptySummary,
		retainedSummary,
		summaryTail: {
			snapshot: tailSummary,
			tail: tailProcessed,
			writer: visible(tailView.root),
			readerAfterTail,
			readerMessages: tailMessages,
			continuationMessages,
			readerAfterContinuation,
			verifier: visible(verifierView.root),
		},
	};
}

async function makeCases() {
	const publicEvidence = await capturePublicEvidence();
	async function initializeItems(content: Items) {
		const provider = new TestTreeProviderLite(1, treeFactory());
		const view = provider.trees[0].viewWith(new TreeViewConfiguration({ schema: Items }));
		view.initialize(content);
		provider.synchronizeMessages();
		return {
			visible: visible(view.root),
			compatibility: copy(view.compatibility),
		};
	}
	async function initializeMap(content: ArrayMap) {
		const provider = new TestTreeProviderLite(1, treeFactory());
		const view = provider.trees[0].viewWith(new TreeViewConfiguration({ schema: ArrayMap }));
		view.initialize(content);
		provider.synchronizeMessages();
		return {
			visible: visible(view.root),
			compatibility: copy(view.compatibility),
		};
	}
	const rootArrayEvidence = await initializeItems(new Items(["root", new Items(["nested"])]));
	const emptyArrayEvidence = await initializeItems(new Items([]));
	const leavesEvidence = await initializeItems(new Items(["string", 1, true, null]));
	const mapRootEvidence = await initializeMap(new ArrayMap([
		["0", new Items(["zero"])],
		["", new Items([])],
	]));
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
			observation: { accepted: true }, output: {
				schema: parsedSchemas.rootArray,
				content: rootArrayEvidence.visible,
			} },
		{ id: "object-arrays", input: { operation: "schema", schema: "objectArrays" },
			observation: { accepted: true }, output: {
				schema: parsedSchemas.objectArrays,
				content: visible(publicEvidence.view.root),
			} },
		{ id: "map-arrays", input: { operation: "schema", schema: "mapArrays" },
			observation: { accepted: true }, output: {
				schema: parsedSchemas.mapArrays,
				content: mapRootEvidence.visible,
			} },
		{ id: "nested-arrays", input: { operation: "read", path: ["left", "3", "0"] },
			observation: { value: "nested" }, output: visible(publicEvidence.view.root.left[3]) },
		{ id: "recursive-arrays", input: { operation: "read", path: ["byKey", "0", "1", "0"] },
			observation: { value: "deep" }, output: visible(publicEvidence.view.root.byKey.get("0")) },
		{ id: "incompatible-arrays", input: { operation: "move", source: { path: ["left"], start: 0, end: 1 },
			destination: { path: ["narrow"], gap: 0 } },
			observation: { accepted: false }, output: publicEvidence.incompatible },
		{ id: "empty-content", input: { operation: "initialize", schema: "rootArray", values: [] },
			observation: { value: emptyArrayEvidence.visible }, output: emptyArrayEvidence.visible },
		{ id: "allowed-leaves", input: { operation: "initialize", schema: "rootArray",
			values: ["string", 1, true, null] },
			observation: { accepted: true }, output: leavesEvidence.visible },
		{ id: "compatibility", input: { operation: "canView", stored: "objectArrays", view: "objectArrays" },
			observation: { accepted: true }, output: rootArrayEvidence.compatibility },
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
	const kernel = Reflect.get(publicEvidence.provider.trees[0], "kernel") as unknown as {
		messageCodec: { decode(value: unknown, context: unknown): unknown };
	};
	const decodeMessage = (value: unknown) => kernel.messageCodec.decode(value, {
		idCompressor: publicEvidence.provider.getCompressor(publicEvidence.provider.trees[0]),
	});
	const decodedMessage = decodeMessage(message) as Record<string, unknown>;
	const decodedCommit = Reflect.get(decodedMessage, "commit") as {
		revision?: unknown;
		change?: {
			changes?: readonly { type?: unknown }[];
		};
	};
	const decodedChange = decodedCommit.change as {
		changes?: readonly { type?: unknown; innerChange?: unknown }[];
	};
	const decodedFieldKinds = [
		...new Set((decodedChange.changes ?? [])
			.filter(({ type }) => type === "data")
			.flatMap(({ innerChange }) =>
				modularStructure(innerChange as ModularChangeset).fields.map(({ kind }) => kind))),
	].sort();
	const modularRevisions = Array.from({ length: 11 }, () => mintRevisionTag());
	const revisionMap = modularRevisions.map((revision) => ({
		encoded: Number(revision),
		stable: testIdCompressor.decompress(revision as SessionSpaceCompressedId),
	}));
	const atom = (revision: RevisionTag, localId: number) => ({
		revision: Number(revision),
		localId,
	});
	const parent = (field: string, node: ReturnType<typeof atom> | null = null) => ({
		node,
		field,
	});
	const emptyChange = (
		revision: RevisionTag,
		fields: unknown[],
		options: {
			nodes?: unknown[];
			parents?: unknown[];
			aliases?: unknown[];
			crossFieldKeys?: unknown[];
			maxLocalId?: number;
		} = {},
	) => ({
		maxLocalId: options.maxLocalId ?? 0,
		revisions: [{ revision: Number(revision), rollbackOf: null }],
		fields,
		nodes: options.nodes ?? [],
		parents: options.parents ?? [],
		aliases: options.aliases ?? [],
		crossFieldKeys: options.crossFieldKeys ?? [],
	});
	const generic = (children: unknown[]) => ({ kind: "Generic", change: { children } });
	const sequence = (change: unknown[]) => ({ kind: "Sequence", change });
	const replayContext = (
		operation: "compose" | "invert" | "rebase",
		changes: unknown[],
		options: Record<string, unknown> = {},
	) => {
		const taggedChanges = changes as { change: { maxLocalId: number } }[];
		return {
			operation,
			initialState: visible(initialRoot()),
			operands: { changes, ...options },
			revisions: revisionMap,
			allocator: {
				maxLocalId: Math.max(...taggedChanges.map(({ change }) => change.maxLocalId)),
			},
			compressor: { sessionId: testIdCompressor.localSessionId },
			sequencing: { minimumSequenceNumber: 0, sequenceNumber: 0 },
			schedule:
				operation === "compose" ? ["left", "right", "invalidated-fields"] : [operation],
		};
	};
	const tagged = (revision: RevisionTag, change: unknown) => ({
		revision: Number(revision),
		change,
	});
	const [r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10] = modularRevisions;
	const genericLeft = emptyChange(r0, [["left", generic([[1, atom(r0, 10)]])]], {
		maxLocalId: 11,
		nodes: [
			[
				atom(r0, 10),
				{ fields: [["nested", sequence([{ count: 1, changes: atom(r0, 11) }])]] },
			],
			[atom(r0, 11), { fields: [] }],
		],
		parents: [
			[atom(r0, 10), parent("left")],
			[atom(r0, 11), parent("nested", atom(r0, 10))],
		],
	});
	const sequenceLeft = emptyChange(
		r1,
		[
			[
				"left",
				sequence([
					{
						type: "Insert",
						count: 1,
						id: 0,
						cellId: atom(r1, 0),
						revision: Number(r1),
					},
				]),
			],
		],
		{ maxLocalId: 0 },
	);
	const nestedMap = emptyChange(r2, [["byKey", generic([[0, atom(r2, 20)]])]], {
		maxLocalId: 22,
		nodes: [
			[atom(r2, 20), { fields: [["0", generic([[0, atom(r2, 21)]])]] }],
			[atom(r2, 21), { fields: [["", sequence([{ count: 1, changes: atom(r2, 22) }])]] }],
			[atom(r2, 22), { fields: [] }],
		],
		parents: [
			[atom(r2, 20), parent("byKey")],
			[atom(r2, 21), parent("0", atom(r2, 20))],
			[atom(r2, 22), parent("", atom(r2, 21))],
		],
	});
	const commonLeft = emptyChange(r3, [["left", generic([[0, atom(r3, 30)]])]], {
		maxLocalId: 31,
		nodes: [
			[
				atom(r3, 30),
				{ fields: [["nested", sequence([{ count: 1, changes: atom(r3, 31) }])]] },
			],
			[atom(r3, 31), { fields: [] }],
		],
		parents: [
			[atom(r3, 30), parent("left")],
			[atom(r3, 31), parent("nested", atom(r3, 30))],
		],
	});
	const commonRight = emptyChange(r4, [["left", generic([[0, atom(r4, 40)]])]], {
		maxLocalId: 41,
		nodes: [
			[
				atom(r4, 40),
				{ fields: [["nested", sequence([{ count: 1, changes: atom(r4, 41) }])]] },
			],
			[atom(r4, 41), { fields: [] }],
		],
		parents: [
			[atom(r4, 40), parent("left")],
			[atom(r4, 41), parent("nested", atom(r4, 40))],
		],
	});
	const aliasLeft = emptyChange(r8, [["left", generic([[0, atom(r8, 60)]])]], {
		maxLocalId: 60,
		nodes: [[atom(r8, 60), { fields: [] }]],
		parents: [[atom(r8, 60), parent("left")]],
	});
	const aliasRight = emptyChange(r9, [["left", generic([[0, atom(r9, 61)]])]], {
		maxLocalId: 61,
		nodes: [[atom(r9, 61), { fields: [] }]],
		parents: [[atom(r9, 61), parent("left")]],
	});
	const modularInputs: Record<string, Record<string, unknown>> = {
		"generic-to-sequence": replayContext("compose", [
			tagged(r0, genericLeft),
			tagged(r1, sequenceLeft),
		]),
		"sequence-to-generic": replayContext("compose", [
			tagged(r1, sequenceLeft),
			tagged(r0, genericLeft),
		]),
		"nested-ancestors": replayContext("invert", [tagged(r2, nestedMap)], {
			isRollback: false,
			inverseRevision: Number(r5),
		}),
		"common-ancestors": replayContext(
			"rebase",
			[tagged(r3, commonLeft), tagged(r4, commonRight)],
			{
				revisionMetadata: [r3, r4].map((revision) => ({
					revision: Number(revision),
					rollbackOf: null,
				})),
			},
		),
		"cross-field-endpoints": crossFieldCoordinationInput(r6) as unknown as Record<
			string,
			unknown
		>,
		"node-table": replayContext("invert", [tagged(r2, nestedMap)], {
			isRollback: true,
			inverseRevision: Number(r7),
		}),
		"parent-table": replayContext("invert", [tagged(r2, nestedMap)], {
			isRollback: false,
			inverseRevision: Number(r10),
		}),
		"alias-table": replayContext("compose", [tagged(r8, aliasLeft), tagged(r9, aliasRight)]),
	};
	const modularScenarios: Scenario[] = scenarioIds["array-modular-algebra"].map((id) => {
		const input = copy(modularInputs[id]);
		const output = replayArrayModularInput(input);
		assert(
			output !== null && typeof output === "object",
			`${id}: modular replay must return an object.`,
		);
		const outputRecord = output as Record<string, unknown>;
		if (id === "generic-to-sequence" || id === "sequence-to-generic") {
			const expectedDirection =
				id === "generic-to-sequence" ? "generic-left" : "generic-right";
			const conversion = Reflect.get(outputRecord, "conversion");
			assert(
				conversion !== null && typeof conversion === "object",
				`${id}: modular replay must report conversion calls.`,
			);
			assert.deepEqual(
				Reflect.get(conversion, "directions"),
				[expectedDirection],
				`${id}: the source handler must convert the Generic operand.`,
			);
			const mutated = copy(input);
			const operands = Reflect.get(mutated, "operands") as {
				changes: {
					change: { fields: [string, { change: { children?: [number, unknown][] } }][] };
				}[];
			};
			const genericOperand = operands.changes.find(({ change }) =>
				change.fields.some(([, field]) => field.change.children !== undefined),
			);
			assert(genericOperand !== undefined, `${id}: a Generic operand is required.`);
			const genericField = genericOperand.change.fields.find(
				([, field]) => field.change.children !== undefined,
			);
			assert(
				genericField?.[1].change.children !== undefined,
				`${id}: the Generic child entries are required.`,
			);
			genericField[1].change.children[0][0] += 1;
			const mutation = executed(() => replayArrayModularInput(mutated));
			assert(
				mutation.accepted === false ||
					JSON.stringify(mutation.value) !== JSON.stringify(output),
				`${id}: changing the child index must change or reject replay.`,
			);
		}
		if (id === "cross-field-endpoints") {
			const coordination = Reflect.get(outputRecord, "coordination") as {
				handlerCalls: { sequence: number; field: { field: string } }[];
				managerCalls: {
					sequence: number;
					method: string;
					field: { field: string };
					addDependency?: boolean;
					invalidateDependents?: boolean;
					count?: number;
					returnedLength?: number;
				}[];
			};
			assert.deepEqual(
				coordination.handlerCalls.slice(0, 3).map(({ field }) => field.field),
				["right", "left", "right"],
				"The source manager must reprocess the destination after discovering the source.",
			);
			const firstRight = coordination.handlerCalls[0].sequence;
			const secondRight = coordination.handlerCalls[2].sequence;
			assert(
				coordination.managerCalls.some(
					(call) =>
						call.method === "get" &&
						call.field.field === "right" &&
						call.addDependency === true,
				),
				"The destination field must register a source-manager dependency.",
			);
			assert(
				coordination.managerCalls.some(
					(call) =>
						call.method === "set" &&
						call.invalidateDependents === true &&
						call.sequence > firstRight &&
						call.sequence < secondRight,
				),
				"A later source-manager update must invalidate a registered dependency.",
			);
			assert(
				coordination.managerCalls.some(
					(call) =>
						call.count !== undefined &&
						call.returnedLength !== undefined &&
						call.count > call.returnedLength,
				),
				"The source manager must expose an overlapping partial-range query.",
			);
		}
		return {
			id,
			input,
			observation: { fieldKinds: modularKinds, executed: true, result: output },
			output,
		};
	});

	const summary = publicEvidence.settledSummary;
	const codecOutputs: Record<string, unknown> = {
		"sequence-v3": {
			encoded: modular,
			fieldKinds: modularKinds,
		},
		"message-v7": {
			encoded: message,
			decoded: {
				type: Reflect.get(decodedMessage, "type"),
				branchId: Reflect.get(decodedMessage, "branchId"),
				revision: decodedCommit.revision,
				sessionId: Reflect.get(decodedMessage, "sessionId"),
				changeTypes: decodedChange.changes?.map(({ type }) => type) ?? [],
				fieldKinds: decodedFieldKinds,
			},
		},
		builds: {
			messages: publicEvidence.operationMessages,
			buildCount: JSON.stringify(publicEvidence.operationMessages).match(/"builds?"/g)?.length ?? 0,
		},
		"empty-arrays": {
			summary: publicEvidence.emptySummary,
			forest: summaryBlob(publicEvidence.emptySummary, "indexes", "Forest", "contents"),
			schema: summaryBlob(publicEvidence.emptySummary, "indexes", "Schema", "SchemaString"),
		},
		"retained-history": {
			history: summaryBlob(publicEvidence.retainedSummary, "indexes", "EditManager", "String"),
		},
		"detached-index": {
			detached: summaryBlob(
				publicEvidence.retainedSummary,
				"indexes",
				"DetachedFieldIndex",
				"DetachedFieldIndexBlob",
			),
		},
		"full-summary": {
			summary,
			schema: summaryBlob(summary, "indexes", "Schema", "SchemaString"),
			forest: summaryBlob(summary, "indexes", "Forest", "contents"),
			detached: summaryBlob(summary, "indexes", "DetachedFieldIndex", "DetachedFieldIndexBlob"),
			history: summaryBlob(summary, "indexes", "EditManager", "String"),
		},
	};
	const codecScenarios: Scenario[] = scenarioIds["array-codecs"].map((id) => ({
		id,
		input: {
			operation: id,
			initialState: visible(initialRoot()),
			profile: { message: 7, modularChange: 5, sequence: 3 },
			operands: codecOutputs[id],
			revisions: publicEvidence.operationCommits.map(({ revision }) => revision),
		},
		observation: { codecExecuted: true },
		output: codecOutputs[id],
	}));

	const historyOutputs: Record<string, unknown> = {
		"pending-chains": publicEvidence.pending,
		batching: {
			...publicEvidence.batching,
			identityPreserved: publicEvidence.identityPreserved,
		},
		acknowledgements: publicEvidence.settled,
		reconnect: publicEvidence.reconnectMessages,
		"window-advance": { before: publicEvidence.pending, after: publicEvidence.settled },
		"summary-tail": publicEvidence.summaryTail,
		"public-noops": {
			noops: publicEvidence.noops,
			identityEdits: publicEvidence.identityEdits,
		},
	};
	const historyScenarios: Scenario[] = scenarioIds["array-history"].map((id) => ({
		id,
		input: {
			operation: id,
			initialState: visible(initialRoot()),
			operands: historyOutputs[id],
			revisions: publicEvidence.operationCommits.map(({ revision }) => revision),
			schedule: [{ step: id, deliveries: historyOutputs[id] }],
		},
		observation: { historyExecuted: true },
		output: historyOutputs[id],
	}));

	const corruptMarkMessage = copy(message);
	let changedMark = false;
	function corruptFirstMove(value: unknown): void {
		if (changedMark) return;
		if (Array.isArray(value)) {
			value.forEach(corruptFirstMove);
		} else if (value !== null && typeof value === "object") {
			const object = value as Record<string, unknown>;
			if (object.moveOut !== undefined || object.moveIn !== undefined) {
				object.unknownMove = object.moveOut ?? object.moveIn;
				delete object.moveOut;
				delete object.moveIn;
				changedMark = true;
				return;
			}
			Object.values(object).forEach(corruptFirstMove);
		}
	}
	corruptFirstMove(corruptMarkMessage);
	assert(changedMark, "The corrupt-mark probe needs an actual move mark.");
	const corruptRevisionMessage = copy(message);
	Reflect.set(corruptRevisionMessage, "revision", "not-a-revision");
	const invalidRange = executed(() => publicEvidence.view.root.left.removeRange(2, 1));
	const ownershipProvider = new TestTreeProviderLite(1, treeFactory());
	const ownershipView = ownershipProvider.trees[0].viewWith(
		new TreeViewConfiguration({ schema: Root }),
	);
	ownershipView.initialize(initialRoot());
	const foreignPoint = ownershipView.root.narrow[0];
	assert(foreignPoint instanceof Point, "The ownership probe needs a foreign point.");
	const ownership = executed(() => publicEvidence.view.root.narrow.insertAt(0, foreignPoint));
	const corruptSummary = { ...copy(summary), tree: {} };
	const invalidFactory = treeFactory();
	const summaryFailure = await executedAsync(async () => invalidFactory.load(
		new MockFluidDataStoreRuntime({
			idCompressor: deserializeIdCompressor(
				serializeIdCompressor(publicEvidence.provider.getCompressor(publicEvidence.provider.trees[0]), false),
				createSessionId(),
			),
		}),
		"watershed-corrupt-summary",
		MockSharedObjectServices.createFromSummary(corruptSummary),
		invalidFactory.attributes,
	));
	const schemaFailure = executed(() => schemaCodecBuilder
		.buildDecoder({ jsonValidator: FormatValidatorNoOp })
		.decode({ version: 99 } as never));
	const invalidOutputs: Record<string, unknown> = {
		"corrupt-schema": { input: { version: 99 }, outcome: schemaFailure },
		"corrupt-mark": { input: corruptMarkMessage, outcome: executed(() => decodeMessage(corruptMarkMessage)) },
		"corrupt-range": { input: { start: 2, end: 1 }, outcome: invalidRange },
		"corrupt-revision": {
			input: corruptRevisionMessage,
			outcome: executed(() => decodeMessage(corruptRevisionMessage)),
		},
		"corrupt-ownership": { input: { foreign: true }, outcome: ownership },
		"corrupt-summary": { input: corruptSummary, outcome: summaryFailure },
		"native-remove-beyond-length": {
			upstream: { input: { start: 1, end: 99 }, value: publicEvidence.clampedRemoval },
			nativeContract: "error",
		},
	};
	const invalidScenarios: Scenario[] = scenarioIds["array-invalid"].map((id) => ({
		id,
		input: { operation: id, initialState: visible(initialRoot()), operands: invalidOutputs[id] },
		observation: {
			rejected: id === "native-remove-beyond-length"
				? false
				: Reflect.get(invalidOutputs[id] as object, "outcome")?.accepted === false,
		},
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
