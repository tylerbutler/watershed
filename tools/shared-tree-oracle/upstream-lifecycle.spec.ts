/*!
 * Copyright (c) Microsoft Corporation and contributors. All rights reserved.
 * Licensed under the MIT License.
 */

import { strict as assert } from "node:assert";
import { mkdir, writeFile } from "node:fs/promises";
import { isAbsolute, join } from "node:path";
import { performance } from "node:perf_hooks";

import type { IFluidHandle, IFluidLoadable } from "@fluidframework/core-interfaces";
import type { IFluidHandleInternal } from "@fluidframework/core-interfaces/internal";
import type { ISequencedDocumentMessage } from "@fluidframework/driver-definitions/internal";
import { createIdCompressor } from "@fluidframework/id-compressor/internal";
import { startEphemeralService } from "@fluidframework/local-driver/internal";
import { MapFactory, type ISharedMap } from "@fluidframework/map/internal";
import {
	createSharedObjectKindAlpha,
	defineDataStore,
	FluidSerializer,
	sharedObjectRegistryFromIterable,
} from "@fluidframework/shared-object-base/internal";
import {
	MockContainerRuntimeFactory,
	MockFluidDataStoreRuntime,
	MockStorage,
} from "@fluidframework/test-runtime-utils/internal";

import { asAlpha } from "../api.js";
import { FluidClientVersion } from "../codec/index.js";
import { RevertibleStatus, type RevertibleAlpha } from "../core/index.js";
import {
	SchemaFactory,
	TreeViewConfiguration,
	type ITree,
	type TreeViewAlpha,
} from "../simple-tree/index.js";
import { Tree } from "../shared-tree/index.js";
import { configuredSharedTreeInternal } from "../treeFactory.js";

const formatVersion = 1;
const commit = "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960";
const lifecyclePath = "packages/dds/tree/src/test/watershedLifecycle.spec.ts";
const outputValue = process.env.WATERSHED_ORACLE_OUTPUT;
const digest = process.env.WATERSHED_LIFECYCLE_DIGEST;

assert(outputValue !== undefined && isAbsolute(outputValue), "An absolute output directory is required");
const outputDirectory: string = outputValue;
assert.equal(process.env.WATERSHED_ORACLE_COMMIT, commit);
assert.equal(process.env.WATERSHED_ORACLE_DETERMINISTIC, "1");
assert.match(digest ?? "", /^[0-9a-f]{64}$/);
Object.defineProperty(performance, "now", { value: () => 0, configurable: true });

const sf = new SchemaFactory("org.watershed.shared-tree.handles");
class Links extends sf.map("Links", sf.handle) {}
class Sequence extends sf.array("Sequence", sf.handle) {}
class Root extends sf.object("Root", {
	label: sf.string,
	link: sf.optional(sf.handle),
	links: Links,
	sequence: Sequence,
}) {}

type RootView = TreeViewAlpha<typeof Root>;
const PinnedTree = configuredSharedTreeInternal({
	minVersionForCollab: FluidClientVersion.v2_117,
});
type EvidenceSection = "messages" | "serialization" | "summaries";
interface RawRecord {
	id: string;
	scenarioId: string;
	kind: string;
	value: unknown;
	checkpoint?: string;
}
interface Observation {
	id: string;
	value: unknown;
	evidence: { section: EvidenceSection; id: string }[];
}

function copy<T>(value: T): T {
	return JSON.parse(JSON.stringify(value));
}

function errorOf(action: () => unknown): string {
	try {
		action();
		return "";
	} catch (error) {
		return String(error);
	}
}

function treeFactory() {
	return PinnedTree.getFactory();
}

function visible(root: Root) {
	return {
		label: root.label,
		link: root.link === undefined ? undefined : pathOf(root.link),
		links: [...root.links].map(([key, handle]) => [key, pathOf(handle)]),
		sequence: [...root.sequence].map(pathOf),
	};
}

function internalHandle(handle: IFluidHandle): IFluidHandleInternal {
	return handle as IFluidHandleInternal;
}

function pathOf(handle: IFluidHandle): string {
	return internalHandle(handle).absolutePath;
}

function isAttached(value: unknown): boolean {
	return (value as { isAttached(): boolean }).isAttached();
}

function gcData(value: unknown): unknown {
	return (value as { getGCData(): unknown }).getGCData();
}

function gcNodes(value: unknown): unknown {
	return (gcData(value) as { gcNodes: unknown }).gcNodes;
}

async function summarize(value: unknown): Promise<{ summary: unknown }> {
	return (value as { summarize(fullTree: boolean): Promise<{ summary: unknown }> }).summarize(true);
}

function summaryBlobText(value: unknown): string[] {
	const blobs: string[] = [];
	function visit(item: unknown): void {
		if (item === null || typeof item !== "object") return;
		const record = item as Record<string, unknown>;
		if (record.type === 2 && typeof record.content === "string") blobs.push(record.content);
		for (const child of Object.values(record)) visit(child);
	}
	visit(value);
	return blobs;
}

function messageOrder(messages: unknown[]): string[] {
	const order: string[] = [];
	for (const message of messages) {
		const raw = (message as { contents?: unknown }).contents;
		const contents = typeof raw === "string" ? JSON.parse(raw) as unknown : raw;
		const entries = (contents as { type?: string; contents?: unknown })?.type === "groupedBatch"
			? (contents as { contents: { contents: unknown }[] }).contents.map((entry) => entry.contents)
			: [contents];
		for (const entry of entries) {
			const item = entry as {
				type?: string;
				contents?: {
					id?: string;
					address?: string;
					contents?: {
						type?: string;
						content?: { id?: string; address?: string };
					};
				};
			};
			if (item.type === "idAllocation") {
				order.push("id-allocation");
			} else if (item.type === "attach") {
				order.push(`datastore-attach:${item.contents?.id}`);
			} else if (item.type === "component" && item.contents?.contents?.type === "attach") {
				order.push(`channel-attach:${item.contents.address}/${item.contents.contents.content?.id}`);
			} else if (item.type === "component") {
				order.push(`component:${item.contents?.address}/${item.contents?.contents?.content?.address}`);
			} else {
				order.push(String(item.type));
			}
		}
	}
	return order;
}

function sourceIdentity() {
	return {
		path: lifecyclePath,
		version: "3.1.0",
		commit,
		digest,
	};
}

async function writeCase(
	id: string,
	scenarios: { id: string; operation: string }[],
	observations: Observation[],
	raw: {
		messages: RawRecord[];
		serialization: RawRecord[];
		summaries: RawRecord[];
	},
): Promise<void> {
	assert.deepEqual(
		observations.map((item) => item.id),
		scenarios.map((item) => item.id),
		`${id}: scenario observations`,
	);
	const value = {
		formatVersion,
		reference: { package: "@fluidframework/tree", version: "3.1.0", commit },
		id,
		domain: "lifecycle",
		input: { scenarios },
		expected: { observations },
		raw: { ...raw, source: sourceIdentity() },
	};
	await mkdir(outputDirectory, { recursive: true });
	await writeFile(join(outputDirectory, `${id}.json`), `${JSON.stringify(value, null, 2)}\n`);
}

function record(
	section: EvidenceSection,
	raw: { messages: RawRecord[]; serialization: RawRecord[]; summaries: RawRecord[] },
	scenarioId: string,
	kind: string,
	value: unknown,
	checkpoint?: string,
): { section: EvidenceSection; id: string } {
	const id = `${scenarioId}:${section}:${raw[section].length}`;
	raw[section].push({ id, scenarioId, kind, value: copy(value), checkpoint });
	return { section, id };
}

function mockTree(id: string) {
	const runtime = new MockFluidDataStoreRuntime({
		idCompressor: createIdCompressor(),
		registry: [SharedMapAlpha.getFactory(), treeFactory()],
	});
	const runtimeFactory = new MockContainerRuntimeFactory();
	runtimeFactory.createContainerRuntime(runtime);
	const tree = treeFactory().create(runtime, id);
	tree.connect({
		deltaConnection: runtime.createDeltaConnection(),
		objectStorage: new MockStorage(),
	});
	(tree as unknown as { bindToContext(): void }).bindToContext();
	const view = asAlpha(tree.viewWith(
		new TreeViewConfiguration({ schema: Root, enableSchemaValidation: true }),
	));
	view.initialize(new Root({
		label: id,
		links: new Links(),
		sequence: new Sequence(),
	}));
	runtimeFactory.processAllMessages();
	return { runtime, runtimeFactory, tree, view };
}

function activeTransactionAttachment() {
	const runtime = new MockFluidDataStoreRuntime({ idCompressor: createIdCompressor() });
	const tree = treeFactory().create(runtime, "active-target");
	const runtimeFactory = new MockContainerRuntimeFactory();
	runtimeFactory.createContainerRuntime(runtime);
	const view = asAlpha(tree.viewWith(
		new TreeViewConfiguration({ schema: Root, enableSchemaValidation: true }),
	));
	view.initialize(new Root({
		label: "active",
		links: new Links(),
		sequence: new Sequence(),
	}));
	const error = errorOf(() => Tree.runTransaction(view, () => {
		tree.connect({
			deltaConnection: runtime.createDeltaConnection(),
			objectStorage: new MockStorage(),
		});
	}));
	return { error, attached: isAttached(tree) };
}

interface GraphData extends IFluidLoadable {
	root: ISharedMap;
	createMap(): Promise<ISharedMap>;
	createTree(): Promise<ITree>;
}

const SharedMapAlpha = createSharedObjectKindAlpha(MapFactory);

const GraphStore = defineDataStore<GraphData, ISharedMap>({
	type: "org.watershed.shared-tree.m7.graph",
	registry: sharedObjectRegistryFromIterable([SharedMapAlpha, PinnedTree]),
	instantiateFirstTime: async (creator) => creator.createSharedObject(SharedMapAlpha),
	view: async (root, context) => ({
		get IFluidLoadable() {
			return root.IFluidLoadable;
		},
		handle: root.handle,
		root,
		createMap: async () => context.createSharedObject(SharedMapAlpha),
		createTree: async () => context.createSharedObject(PinnedTree),
	}),
});

async function attachedGraph() {
	const service = startEphemeralService(false);
	const client = service.newClient({ oldestSupportedClient: "2.117.0" });
	const container = await client.createAttachedContainer(GraphStore);
	const messages: unknown[] = [];
	const inner = container as unknown as {
		container: { deltaManager: { on(event: "op", listener: (message: ISequencedDocumentMessage) => void): void } };
	};
	inner.container.deltaManager.on("op", (message) => messages.push(copy(message)));
	return { service, client, container, messages };
}

function newRoot(tree: Awaited<ReturnType<GraphData["createTree"]>>) {
	const view = asAlpha(tree.viewWith(
		new TreeViewConfiguration({ schema: Root, enableSchemaValidation: true }),
	));
	view.initialize(new Root({
		label: "root",
		links: new Links(),
		sequence: new Sequence(),
	}));
	return view;
}

describe("Watershed handle and attachment lifecycle", () => {
	it("captures handle leaves and serializer behavior", async () => {
		const raw = { messages: [] as RawRecord[], serialization: [] as RawRecord[], summaries: [] as RawRecord[] };
		const scenarios = [
			{ id: "required-root", operation: "store a handle as the required root" },
			{ id: "optional-root", operation: "set and clear an optional root handle" },
			{ id: "object-field", operation: "set a handle object field" },
			{ id: "map-entry", operation: "set a handle map entry" },
			{ id: "array-element", operation: "insert a handle array element" },
			{ id: "same-target-handles", operation: "decode a second handle for the same target" },
			{ id: "relative-path", operation: "decode a legacy relative handle path" },
			{ id: "escaped-path", operation: "round-trip a percent-escaped handle path" },
			{ id: "uncompressed-v2", operation: "capture the uncompressed attach summary" },
			{ id: "schema-aware-v2", operation: "capture the schema-aware attach summary" },
			{ id: "malformed-marker", operation: "decode a malformed handle marker" },
			{ id: "unsupported-marker", operation: "decode an unsupported handle marker" },
		];
		const observations: Observation[] = [];
		const { runtime, runtimeFactory, tree, view } = mockTree("handle-leaves");
		const map = SharedMapAlpha.create(runtime, "leaf-target");
		map.set("value", "target");
		const serializer = new FluidSerializer(runtime.channelsRoutingContext);

		const requiredTree = treeFactory().create(runtime, "required-root");
		const requiredView = requiredTree.viewWith(new TreeViewConfiguration({ schema: sf.handle }));
		requiredView.initialize(map.handle);
		observations.push({
			id: "required-root",
			value: { path: pathOf(requiredView.root) },
			evidence: [record("serialization", raw, "required-root", "handle", serializer.encode(requiredView.root, internalHandle(tree.handle)))],
		});

		const optionalTree = treeFactory().create(runtime, "optional-root");
		const optionalView = optionalTree.viewWith(
			new TreeViewConfiguration({ schema: sf.optional(sf.handle) }),
		);
		optionalView.initialize(map.handle);
		const beforeClear = optionalView.root === undefined ? undefined : pathOf(optionalView.root);
		optionalView.root = undefined;
		observations.push({
			id: "optional-root",
			value: { beforeClear, afterClear: optionalView.root },
			evidence: [record("serialization", raw, "optional-root", "checkpoint", { beforeClear, afterClear: null })],
		});

		view.root.link = map.handle;
		observations.push({
			id: "object-field",
			value: visible(view.root),
			evidence: [record("serialization", raw, "object-field", "handle", serializer.encode(map.handle, internalHandle(tree.handle)))],
		});
		view.root.links.set("target", map.handle);
		observations.push({
			id: "map-entry",
			value: visible(view.root),
			evidence: [record("serialization", raw, "map-entry", "handle", serializer.encode(map.handle, internalHandle(tree.handle)))],
		});
		view.root.sequence.insertAtEnd(map.handle);
		observations.push({
			id: "array-element",
			value: visible(view.root),
			evidence: [record("serialization", raw, "array-element", "handle", serializer.encode(map.handle, internalHandle(tree.handle)))],
		});

		const encoded = serializer.stringify(map.handle, internalHandle(tree.handle));
		const decoded = serializer.parse(encoded) as IFluidHandle;
		observations.push({
			id: "same-target-handles",
			value: {
				sameInstance: decoded === map.handle,
				firstPath: pathOf(map.handle),
				secondPath: pathOf(decoded),
			},
			evidence: [record("serialization", raw, "same-target-handles", "roundtrip", { encoded })],
		});
		const relative = serializer.parse('{"type":"__fluid_handle__","url":"leaf-target"}') as IFluidHandle;
		observations.push({
			id: "relative-path",
			value: { resolvedPath: pathOf(relative) },
			evidence: [record("serialization", raw, "relative-path", "legacy-relative", { url: "leaf-target" })],
		});
		const escapedUrl = `${runtime.absolutePath}/space%20and%23hash`;
		const escaped = serializer.parse(JSON.stringify({ type: "__fluid_handle__", url: escapedUrl })) as IFluidHandle;
		observations.push({
			id: "escaped-path",
			value: { serializedPath: escapedUrl, resolvedPath: pathOf(escaped) },
			evidence: [record("serialization", raw, "escaped-path", "escaped", { url: escapedUrl })],
		});

		runtimeFactory.processAllMessages();
		const summary = await summarize(tree);
		const blobs = summaryBlobText(summary.summary);
		const uncompressed = blobs.find((blob) =>
			blob.includes('"builds"') && blob.includes('"trees":{"version":2'));
		assert(uncompressed !== undefined, "The summary must contain nonincremental FieldBatch V2");
		observations.push({
			id: "uncompressed-v2",
			value: {
				version: 2,
				hasHandleMarker: uncompressed.includes("__fluid_handle__"),
			},
			evidence: [record("summaries", raw, "uncompressed-v2", "field-batch-v2", uncompressed)],
		});
		const schemaAware = blobs.find((blob) => blob.includes('"fields":{"version":2'));
		assert(schemaAware !== undefined, "The summary must contain schema-aware FieldBatch V2");
		observations.push({
			id: "schema-aware-v2",
			value: {
				version: 2,
				hasHandleMarker: schemaAware.includes("__fluid_handle__"),
			},
			evidence: [record("summaries", raw, "schema-aware-v2", "schema-aware-field-batch-v2", schemaAware)],
		});
		for (const [id, marker] of [
			["malformed-marker", { type: "__fluid_handle__" }],
			["unsupported-marker", { type: "__fluid_handle_v3__", url: "/unsupported" }],
		] as const) {
			const outcome = {
				error: errorOf(() => {
					(view.root as unknown as { link: unknown }).link = marker;
				}),
			};
			assert.notEqual(outcome.error, "", `${id}: unsupported handle marker must be refused`);
			observations.push({
				id,
				value: outcome,
				evidence: [record("serialization", raw, id, "marker-outcome", { marker, outcome })],
			});
		}
		record("messages", raw, "object-field", "checkpoint", [], "mock-runtime-drained");
		await writeCase("handle-leaves", scenarios, observations, raw);
	});

	it("captures live channel attachment", async () => {
		const raw = { messages: [] as RawRecord[], serialization: [] as RawRecord[], summaries: [] as RawRecord[] };
		const scenarios = [
			{ id: "detached-map", operation: "attach a locally edited map through a tree handle" },
			{ id: "detached-tree", operation: "attach a locally edited tree through a tree handle" },
			{ id: "serialize-remove", operation: "serialize and remove a handle before the checkpoint" },
			{ id: "nested-dependency", operation: "attach a map with a nested map dependency" },
			{ id: "self-reference", operation: "attach a self-referencing map" },
			{ id: "two-channel-cycle", operation: "attach a two-map cycle" },
			{ id: "completed-transaction", operation: "attach after a completed target transaction" },
			{ id: "active-transaction", operation: "attempt target tree attachment during its transaction" },
		];
		const observations: Observation[] = [];
		const { service, container, messages } = await attachedGraph();
		try {
			const tree = await container.data.createTree();
			const view = newRoot(tree);
			container.data.root.set("tree", tree.handle);
			await service.synchronize();
			messages.length = 0;

			const map = await container.data.createMap();
			map.set("local", "map-edit");
			view.root.link = map.handle;
			await service.synchronize();
			observations.push({
				id: "detached-map",
				value: { path: pathOf(map.handle), local: map.get("local") },
				evidence: [record("messages", raw, "detached-map", "attach", messages.splice(0))],
			});

			const targetTree = await container.data.createTree();
			const targetView = newRoot(targetTree);
			targetView.root.label = "detached-tree-edit";
			view.root.links.set("tree", targetTree.handle);
			await service.synchronize();
			observations.push({
				id: "detached-tree",
				value: { path: pathOf(targetTree.handle), label: targetView.root.label },
				evidence: [record("messages", raw, "detached-tree", "attach", messages.splice(0))],
			});

			const removed = await container.data.createMap();
			const removedOwner = await container.data.createMap();
			removedOwner.set("removed", removed.handle);
			const ownerSummary = removedOwner.getAttachSummary().summary;
			const bindingEvidence = record(
				"summaries", raw, "serialize-remove", "owner-before-removal", ownerSummary,
			);
			removedOwner.delete("removed");
			view.root.links.set("removed-owner", removedOwner.handle);
			await service.synchronize();
			observations.push({
				id: "serialize-remove",
				value: {
					ownerPath: pathOf(removedOwner.handle),
					targetPath: pathOf(removed.handle),
					attached: isAttached(removed),
					visibleValue: removedOwner.has("removed"),
				},
				evidence: [
					bindingEvidence,
					record("messages", raw, "serialize-remove", "attach-then-remove", messages.splice(0)),
				],
			});

			const outer = await container.data.createMap();
			const inner = await container.data.createMap();
			inner.set("value", "nested");
			outer.set("inner", inner.handle);
			view.root.links.set("nested", outer.handle);
			await service.synchronize();
			observations.push({
				id: "nested-dependency",
				value: { outer: pathOf(outer.handle), inner: pathOf(inner.handle) },
				evidence: [record("messages", raw, "nested-dependency", "attach", messages.splice(0))],
			});

			const self = await container.data.createMap();
			self.set("self", self.handle);
			view.root.links.set("self", self.handle);
			await service.synchronize();
			observations.push({
				id: "self-reference",
				value: { path: pathOf(self.handle), resolved: pathOf(self.get("self") as IFluidHandle) },
				evidence: [record("messages", raw, "self-reference", "attach", messages.splice(0))],
			});

			const left = await container.data.createMap();
			const right = await container.data.createMap();
			left.set("right", right.handle);
			right.set("left", left.handle);
			view.root.links.set("cycle", left.handle);
			await service.synchronize();
			observations.push({
				id: "two-channel-cycle",
				value: { left: pathOf(left.handle), right: pathOf(right.handle) },
				evidence: [record("messages", raw, "two-channel-cycle", "attach", messages.splice(0))],
			});

			const completed = await container.data.createTree();
			const completedView = newRoot(completed);
			Tree.runTransaction(completedView, () => {
				completedView.root.label = "committed";
			});
			view.root.links.set("completed", completed.handle);
			await service.synchronize();
			observations.push({
				id: "completed-transaction",
				value: {
					path: pathOf(completed.handle),
					label: completedView.root.label,
					attached: isAttached(completed),
				},
				evidence: [record("messages", raw, "completed-transaction", "attach", messages.splice(0))],
			});

			const active = activeTransactionAttachment();
			observations.push({
				id: "active-transaction",
				value: active,
				evidence: [record("messages", raw, "active-transaction", "checkpoint", messages.splice(0), "after-refusal")],
			});
			record("serialization", raw, "two-channel-cycle", "map-summary", summaryBlobText((await summarize(left)).summary));
			record("summaries", raw, "detached-tree", "tree-summary", (await summarize(targetTree)).summary);
			await writeCase("live-channel-attachment", scenarios, observations, raw);
		} finally {
			await service.close();
		}
	});

	it("captures cross-datastore attachment", async () => {
		const raw = { messages: [] as RawRecord[], serialization: [] as RawRecord[], summaries: [] as RawRecord[] };
		const scenarios = [
			{ id: "map-cross-datastore", operation: "reference a map in a secondary datastore" },
			{ id: "map-cycle", operation: "create mutual map references across datastores" },
			{ id: "tree-cross-datastore", operation: "reference a tree in a secondary datastore" },
			{ id: "tree-cycle", operation: "create mutual tree references across datastores" },
		];
		const observations: Observation[] = [];
		const { service, container, messages } = await attachedGraph();
		try {
			const primaryTree = await container.data.createTree();
			const primaryView = newRoot(primaryTree);
			container.data.root.set("primaryTree", primaryTree.handle);
			await service.synchronize();
			messages.length = 0;

			const secondary = await container.createDataStore(GraphStore);
			container.data.root.set("secondary", secondary.root.handle);
			await service.synchronize();
			const crossMessages = messages.splice(0);
			observations.push({
				id: "map-cross-datastore",
				value: {
					primary: pathOf(container.data.root.handle),
					secondary: pathOf(secondary.root.handle),
					entryPoint: "root",
					attachOrder: messageOrder(crossMessages),
				},
				evidence: [record("messages", raw, "map-cross-datastore", "attach", crossMessages)],
			});

			const leftStore = await container.createDataStore(GraphStore);
			const rightStore = await container.createDataStore(GraphStore);
			leftStore.root.set("right", rightStore.root.handle);
			rightStore.root.set("left", leftStore.root.handle);
			container.data.root.set("cycle", leftStore.root.handle);
			await service.synchronize();
			const mapCycleMessages = messages.splice(0);
			observations.push({
				id: "map-cycle",
				value: {
					left: pathOf(leftStore.root.handle),
					right: pathOf(rightStore.root.handle),
					attachOrder: messageOrder(mapCycleMessages),
				},
				evidence: [record("messages", raw, "map-cycle", "attach", mapCycleMessages)],
			});

			const secondaryTree = await secondary.createTree();
			const secondaryView = newRoot(secondaryTree);
			secondaryView.root.label = "secondary";
			secondary.root.set("tree", secondaryTree.handle);
			primaryView.root.link = secondaryTree.handle;
			await service.synchronize();
			observations.push({
				id: "tree-cross-datastore",
				value: { path: pathOf(secondaryTree.handle), label: secondaryView.root.label },
				evidence: [record("messages", raw, "tree-cross-datastore", "attach", messages.splice(0))],
			});

			const leftTreeStore = await container.createDataStore(GraphStore);
			const rightTreeStore = await container.createDataStore(GraphStore);
			const leftTree = await leftTreeStore.createTree();
			const rightTree = await rightTreeStore.createTree();
			const leftTreeView = newRoot(leftTree);
			const rightTreeView = newRoot(rightTree);
			leftTreeView.root.link = rightTree.handle;
			rightTreeView.root.link = leftTree.handle;
			primaryView.root.link = leftTree.handle;
			await service.synchronize();
			const treeCycleMessages = messages.splice(0);
			const treeCycleSummary = record("summaries", raw, "tree-cycle", "cycle-trees", {
				left: { path: pathOf(leftTree.handle), summary: (await summarize(leftTree)).summary },
				right: { path: pathOf(rightTree.handle), summary: (await summarize(rightTree)).summary },
			});
			observations.push({
				id: "tree-cycle",
				value: {
					left: pathOf(leftTree.handle),
					right: pathOf(rightTree.handle),
					attachOrder: messageOrder(treeCycleMessages),
				},
				evidence: [
					record("messages", raw, "tree-cycle", "attach", treeCycleMessages),
					treeCycleSummary,
				],
			});
			record("serialization", raw, "map-cross-datastore", "paths", {
				primary: pathOf(container.data.root.handle),
				secondary: pathOf(secondary.root.handle),
			});
			await writeCase("cross-datastore-attachment", scenarios, observations, raw);
		} finally {
			await service.close();
		}
	});

	it("captures transaction, branch, and undo side effects", async () => {
		const raw = { messages: [] as RawRecord[], serialization: [] as RawRecord[], summaries: [] as RawRecord[] };
		const scenarios = [
			{ id: "successful-transaction", operation: "commit a handle insertion" },
			{ id: "aborted-transaction", operation: "roll back a handle insertion" },
			{ id: "nested-transaction", operation: "commit nested handle edits" },
			{ id: "active-target", operation: "attach a target tree during its transaction" },
			{ id: "branch-before-merge", operation: "set a branch-only handle" },
			{ id: "branch-after-merge", operation: "merge a branch handle" },
			{ id: "branch-dropped", operation: "drop unmerged branch changes" },
			{ id: "branch-disposal", operation: "dispose a branch with a handle" },
			{ id: "handle-undo-peer-edit", operation: "undo a handle while preserving target edits" },
		];
		const observations: Observation[] = [];
		const { service, client, container, messages } = await attachedGraph();
		try {
			const tree = await container.data.createTree();
			const view = newRoot(tree);
			container.data.root.set("tree", tree.handle);
			await service.synchronize();
			messages.length = 0;

			const success = await container.data.createMap();
			Tree.runTransaction(view, () => {
				view.root.link = success.handle;
			});
			await service.synchronize();
			observations.push({
				id: "successful-transaction",
				value: {
					path: view.root.link === undefined ? undefined : pathOf(view.root.link),
					attached: isAttached(success),
				},
				evidence: [record("messages", raw, "successful-transaction", "attach", messages.splice(0))],
			});

			const aborted = await container.data.createMap();
			const abortedResult = Tree.runTransaction(view, () => {
				view.root.link = aborted.handle;
				return Tree.runTransaction.rollback;
			});
			observations.push({
				id: "aborted-transaction",
				value: {
					result: abortedResult === Tree.runTransaction.rollback ? "rollback" : "commit",
					attached: isAttached(aborted),
					referringPath: view.root.link === undefined ? undefined : pathOf(view.root.link),
				},
				evidence: [record("messages", raw, "aborted-transaction", "checkpoint", messages.splice(0), "after-rollback")],
			});

			const nested = await container.data.createMap();
			Tree.runTransaction(view, () => {
				view.root.links.set("outer", nested.handle);
				Tree.runTransaction(view, () => {
					view.root.sequence.insertAtEnd(nested.handle);
				});
			});
			await service.synchronize();
			const nestedVisible = visible(view.root);
			observations.push({
				id: "nested-transaction",
				value: nestedVisible,
				evidence: [
					record("messages", raw, "nested-transaction", "attach", messages.splice(0)),
					record("serialization", raw, "nested-transaction", "visible", nestedVisible),
				],
			});

			const active = activeTransactionAttachment();
			observations.push({
				id: "active-target",
				value: active,
				evidence: [record("messages", raw, "active-target", "checkpoint", messages.splice(0), "after-refusal")],
			});

			const branchTarget = await container.data.createMap();
			const branch = view.fork() as RootView;
			branch.root.link = branchTarget.handle;
			observations.push({
				id: "branch-before-merge",
				value: {
					branchPath: branch.root.link === undefined ? undefined : pathOf(branch.root.link),
					mainPath: view.root.link === undefined ? undefined : pathOf(view.root.link),
					attached: isAttached(branchTarget),
				},
				evidence: [record("messages", raw, "branch-before-merge", "checkpoint", messages.splice(0), "before-merge")],
			});
			view.merge(branch);
			await service.synchronize();
			observations.push({
				id: "branch-after-merge",
				value: { mainPath: view.root.link === undefined ? undefined : pathOf(view.root.link), attached: isAttached(branchTarget) },
				evidence: [record("messages", raw, "branch-after-merge", "attach", messages.splice(0))],
			});

			const droppedTarget = await container.data.createMap();
			const dropped = view.fork() as RootView;
			dropped.root.link = droppedTarget.handle;
			dropped.dispose();
			observations.push({
				id: "branch-dropped",
				value: { mainPath: view.root.link === undefined ? undefined : pathOf(view.root.link), attached: isAttached(droppedTarget) },
				evidence: [record("messages", raw, "branch-dropped", "checkpoint", messages.splice(0), "after-drop")],
			});

			const disposedTarget = await container.data.createMap();
			const disposed = view.fork() as RootView;
			disposed.root.link = disposedTarget.handle;
			disposed.dispose();
			observations.push({
				id: "branch-disposal",
				value: { attached: isAttached(disposedTarget) },
				evidence: [record("messages", raw, "branch-disposal", "checkpoint", messages.splice(0), "after-disposal")],
			});

			const undoTarget = await container.data.createMap();
			let revertible: { revert(): unknown; dispose(): void } | undefined;
			const off = view.events.on("changed", (metadata, getRevertible) => {
				if (metadata.isLocal && getRevertible !== undefined) revertible = getRevertible();
			});
			view.root.link = undoTarget.handle;
			await service.synchronize();
			const peer = await client.loadContainer(container.id, GraphStore);
			const peerTree = await (peer.data.root.get("tree") as IFluidHandle).get() as typeof tree;
			const peerView = asAlpha(peerTree.viewWith(
				new TreeViewConfiguration({ schema: Root, enableSchemaValidation: true }),
			));
			assert(peerView.root.link !== undefined);
			const peerTarget = await peerView.root.link.get() as ISharedMap;
			peerTarget.set("peer", "survives");
			await service.synchronize();
			assert(revertible !== undefined, "Handle insertion must produce a revertible");
			revertible.revert();
			await service.synchronize();
			off();
			revertible.dispose();
			const undoSummary = record(
				"summaries", raw, "handle-undo-peer-edit", "tree-summary", (await summarize(tree)).summary,
			);
			observations.push({
				id: "handle-undo-peer-edit",
				value: {
					referringPath: view.root.link === undefined ? undefined : pathOf(view.root.link),
					targetPath: pathOf(undoTarget.handle),
					targetValue: undoTarget.get("peer"),
				},
				evidence: [
					record("messages", raw, "handle-undo-peer-edit", "undo", messages.splice(0)),
					undoSummary,
				],
			});
			peer.close();
			await writeCase("handle-transaction-branch", scenarios, observations, raw);
		} finally {
			await service.close();
		}
	});

	it("captures summary and retained GC behavior", async () => {
		const raw = { messages: [] as RawRecord[], serialization: [] as RawRecord[], summaries: [] as RawRecord[] };
		const scenarios = [
			{ id: "before-removal", operation: "summarize a visible handle" },
			{ id: "after-removal", operation: "summarize after removing the handle" },
			{ id: "after-undo", operation: "undo handle removal" },
			{ id: "retained-repair", operation: "retain removed content through a branch" },
			{ id: "branch-disposal", operation: "dispose the retaining branch" },
			{ id: "revertible-disposal", operation: "dispose the removal revertible" },
			{ id: "unreferenced-datastore", operation: "remove a secondary datastore reference" },
			{ id: "fresh-load", operation: "load the document from its attach snapshot and sequenced operations, then continue editing" },
		];
		const observations: Observation[] = [];
		const { service, client, container, messages } = await attachedGraph();
		try {
			const tree = await container.data.createTree();
			const view = newRoot(tree);
			container.data.root.set("tree", tree.handle);
			const target = await container.data.createMap();
			target.set("value", "before");
			view.root.link = target.handle;
			await service.synchronize();
			messages.length = 0;

			const beforeSummary = await summarize(tree);
			observations.push({
				id: "before-removal",
				value: {
					routes: gcNodes(tree),
					path: view.root.link === undefined ? undefined : pathOf(view.root.link),
				},
				evidence: [record("summaries", raw, "before-removal", "tree-summary", beforeSummary.summary)],
			});

			const retainedHandles: RevertibleAlpha[] = [];
			const off = view.events.on("changed", (metadata, getRevertible) => {
				if (metadata.isLocal && getRevertible !== undefined) {
					retainedHandles.push(getRevertible());
				}
			});
			view.root.link = undefined;
			await service.synchronize();
			const afterSummary = await summarize(tree);
			observations.push({
				id: "after-removal",
				value: { routes: gcNodes(tree), attached: isAttached(target) },
				evidence: [record("summaries", raw, "after-removal", "tree-summary", afterSummary.summary)],
			});

			const removal = retainedHandles[0];
			assert(removal !== undefined, "Handle removal must produce a revertible");
			removal.revert();
			await service.synchronize();
			observations.push({
				id: "after-undo",
				value: {
					path: view.root.link === undefined ? undefined : pathOf(view.root.link),
					targetValue: target.get("value"),
				},
				evidence: [record("messages", raw, "after-undo", "undo", messages.splice(0))],
			});

			const retaining = view.fork() as RootView;
			view.root.link = undefined;
			await service.synchronize();
			observations.push({
				id: "retained-repair",
				value: {
					routes: gcNodes(tree),
					mainHasReference: view.root.link !== undefined,
					branchPath: retaining.root.link === undefined ? undefined : pathOf(retaining.root.link),
				},
				evidence: [record("summaries", raw, "retained-repair", "gc", gcData(tree))],
			});
			retaining.dispose();
			observations.push({
				id: "branch-disposal",
				value: { routes: gcNodes(tree) },
				evidence: [record("summaries", raw, "branch-disposal", "gc", gcData(tree))],
			});
			off();
			for (const handle of retainedHandles) {
				if (handle.status === RevertibleStatus.Valid) handle.dispose();
			}
			observations.push({
				id: "revertible-disposal",
				value: { routes: gcNodes(tree) },
				evidence: [record("summaries", raw, "revertible-disposal", "gc", gcData(tree))],
			});

			const secondary = await container.createDataStore(GraphStore);
			container.data.root.set("secondary", secondary.root.handle);
			await service.synchronize();
			container.data.root.delete("secondary");
			await service.synchronize();
			observations.push({
				id: "unreferenced-datastore",
				value: {
					path: pathOf(secondary.root.handle),
					attached: isAttached(secondary.root),
					rootGc: gcNodes(container.data.root),
				},
				evidence: [record("messages", raw, "unreferenced-datastore", "remove", messages.splice(0))],
			});

			view.root.link = target.handle;
			await service.synchronize();
			const loaded = await client.loadContainer(container.id, GraphStore);
			try {
				const loadedTreeHandle = loaded.data.root.get("tree") as IFluidHandle;
				const loadedTree = await loadedTreeHandle.get() as typeof tree;
				const loadedView = asAlpha(loadedTree.viewWith(
					new TreeViewConfiguration({ schema: Root, enableSchemaValidation: true }),
				));
				const loadedTarget = await loadedView.root.link?.get() as ISharedMap;
				loadedTarget.set("continued", true);
				await service.synchronize();
				observations.push({
					id: "fresh-load",
					value: {
						path: loadedView.root.link === undefined ? undefined : pathOf(loadedView.root.link),
						continued: target.get("continued"),
					},
					evidence: [record("summaries", raw, "fresh-load", "loaded-tree", (await summarize(loadedTree)).summary)],
				});
			} finally {
				loaded.close();
			}
			record("serialization", raw, "fresh-load", "summary-blobs", summaryBlobText((await summarize(tree)).summary));
			await writeCase("handle-retention", scenarios, observations, raw);
		} finally {
			await service.close();
		}
	});
});
