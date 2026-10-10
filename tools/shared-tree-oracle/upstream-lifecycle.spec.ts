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
interface DeferredCase {
	scenarios: { id: string; operation: string }[];
	observations: Observation[];
	raw: {
		messages: RawRecord[];
		serialization: RawRecord[];
		summaries: RawRecord[];
	};
}
let deferredLiveAttachment: DeferredCase | undefined;
let deferredTransactionBranch: DeferredCase | undefined;

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
			if (item?.type === "idAllocation") {
				order.push("id-allocation");
			} else if (item?.type === "attach") {
				order.push(`datastore-attach:${item.contents?.id}`);
			} else if (item?.type === "component" && item.contents?.contents?.type === "attach") {
				order.push(`channel-attach:${item.contents.address}/${item.contents.contents.content?.id}`);
			} else if (item?.type === "component") {
				order.push(`component:${item.contents?.address}/${item.contents?.contents?.content?.address}`);
			} else {
				order.push(String(item?.type));
			}
		}
	}
	return order;
}

function mapSetObservation(messages: unknown[], key: string) {
	for (const message of messages) {
		const sequenced = message as {
			type?: string;
			clientId?: string;
			sequenceNumber?: number;
			referenceSequenceNumber?: number;
			contents?: unknown;
		};
		if (sequenced.type !== "op") continue;
		const contents = typeof sequenced.contents === "string"
			? JSON.parse(sequenced.contents) as unknown
			: sequenced.contents;
		const entries = (contents as { type?: string; contents?: unknown })?.type === "groupedBatch"
			? (contents as { contents: { contents: unknown }[] }).contents.map((entry) => entry.contents)
			: [contents];
		for (const entry of entries) {
			const envelope = entry as {
				type?: string;
				contents?: {
					address?: string;
					contents?: {
						type?: string;
						content?: {
							address?: string;
							contents?: { key?: string; type?: string; value?: { value?: unknown } };
						};
					};
				};
			};
			const operation = envelope.contents?.contents?.content;
			if (envelope.type === "component"
				&& envelope.contents?.contents?.type === "op"
				&& operation?.contents?.type === "set"
				&& operation.contents.key === key) {
				return {
					route: `/${envelope.contents.address}/${operation.address}`,
					key,
					value: operation.contents.value?.value,
					clientId: sequenced.clientId,
					sequenceNumber: sequenced.sequenceNumber,
					referenceSequenceNumber: sequenced.referenceSequenceNumber,
				};
			}
		}
	}
	return undefined;
}

function parseJson(value: Uint8Array): unknown {
	const text = Buffer.from(value).toString("utf8");
	try {
		return JSON.parse(text);
	} catch {
		return text;
	}
}

function snapshotMetadata(tree: any, blobs: Record<string, string>) {
	const parsed: { path: string; value: unknown }[] = [];
	function visit(node: any, prefix = ""): void {
		for (const [name, id] of Object.entries(node.blobs as Record<string, string>)) {
			parsed.push({
				path: `${prefix}/${name}`,
				value: parseJson(Uint8Array.from(Buffer.from(blobs[id], "base64"))),
			});
		}
		for (const [name, child] of Object.entries(node.trees as Record<string, unknown>)) {
			visit(child, `${prefix}/${name}`);
		}
	}
	visit(tree);
	return {
		document: parsed.filter((item) => item.path.endsWith("/.metadata")),
		gcNodes: parsed.filter((item) =>
			item.value !== null
			&& typeof item.value === "object"
			&& "gcNodes" in item.value),
		components: parsed.filter((item) => item.path.endsWith("/.component")),
	};
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

const oldestSupportedClient = "2.117.0";
const summarizerRuntimeOptions = {
	enableRuntimeIdCompressor: "on" as const,
	summaryOptions: {
		summaryConfigOverrides: {
			state: "disableHeuristics" as const,
			maxAckWaitTime: 15_000,
			maxOpsSinceLastSummary: 7000,
			initialSummarizerDelayMs: 0,
		},
	},
};

function serviceInternals(service: unknown) {
	return service as {
		getDocumentServiceFactory(): any;
	};
}

async function graphCodeLoader(summarizing: boolean) {
	const [
		{ ContainerRuntime },
		{ makeCodeLoader },
	] = await Promise.all([
		import("@fluidframework/container-runtime/internal"),
		import("@fluidframework/runtime-utils/internal"),
	]);
	return makeCodeLoader(
		async (type) => {
			assert.equal(type, GraphStore.type, "Unexpected graph datastore type");
			return GraphStore;
		},
		oldestSupportedClient,
		async (parameters) => {
			const loaded = await ContainerRuntime.loadRuntime2({
				context: parameters.context,
				registry: parameters.registry,
				provideEntryPoint: parameters.provideEntryPoint,
				existing: parameters.existing,
				oldestSupportedClient: parameters.minVersionForCollab,
				runtimeOptions: summarizing
					? summarizerRuntimeOptions
					: { enableRuntimeIdCompressor: "on" },
			});
			return loaded.runtime;
		},
	);
}

async function openGraphContainer(
	service: unknown,
	documentId: string,
	options: { summarizing?: boolean; version?: string } = {},
) {
	const summarizing = options.summarizing === true;
	const [
		{ LoaderHeader },
		{ loadExistingContainer },
		{ DriverHeader },
		{ LocalResolver },
	] = await Promise.all([
		import("@fluidframework/container-definitions/internal"),
		import("@fluidframework/container-loader/internal"),
		import("@fluidframework/driver-definitions/internal"),
		import("@fluidframework/local-driver/internal"),
	]);
	const container = await loadExistingContainer({
		request: {
			url: `http://localhost:3000/${documentId}`,
			headers: {
				...(options.version === undefined ? {} : { [LoaderHeader.version]: options.version }),
				...(summarizing ? {
					[LoaderHeader.cache]: false,
					[LoaderHeader.clientDetails]: {
						capabilities: { interactive: false },
						type: "summarizer",
					},
					[DriverHeader.summarizingClient]: true,
				} : {}),
			},
		},
		urlResolver: new LocalResolver(),
		documentServiceFactory: serviceInternals(service).getDocumentServiceFactory(),
		codeLoader: await graphCodeLoader(summarizing),
	});
	return { container, data: await container.getEntryPoint() as GraphData };
}

async function storedSnapshot(service: unknown, resolvedUrl: unknown, handle: string) {
	const documentService = await serviceInternals(service)
		.getDocumentServiceFactory()
		.createDocumentService(resolvedUrl as any);
	try {
		const storage = await documentService.connectToStorage();
		const versions = await storage.getVersions(null, 1);
		assert.equal(versions[0]?.id, handle, "Published summary is not the stored head");
		const tree = await storage.getSnapshotTree(versions[0]);
		assert(tree !== null, "Published snapshot is missing");
		const blobs: Record<string, string> = {};
		async function visit(node: any): Promise<void> {
			for (const id of Object.values(node.blobs as Record<string, string>)) {
				if (!(id in blobs)) {
					blobs[id] = Buffer.from(await storage.readBlob(id)).toString("base64");
				}
			}
			for (const child of Object.values(node.trees as Record<string, unknown>)) {
				await visit(child);
			}
		}
		await visit(tree);
		const attributesId = tree.trees[".protocol"]?.blobs.attributes;
		assert.equal(typeof attributesId, "string", "Published snapshot has no protocol attributes");
		const attributes = parseJson(Uint8Array.from(Buffer.from(blobs[attributesId], "base64"))) as {
			sequenceNumber?: unknown;
		};
		assert.equal(typeof attributes.sequenceNumber, "number", "Published snapshot sequence");
		const snapshot = {
			version: versions[0],
			tree,
			blobs,
			blobEncoding: "base64",
			sequenceNumber: attributes.sequenceNumber,
		};
		return { snapshot, metadata: snapshotMetadata(tree, blobs) };
	} finally {
		documentService.dispose();
	}
}

async function publishDocument(
	service: unknown,
	documentId: string,
	resolvedUrl: unknown,
	reason: string,
) {
	const summarizer = await openGraphContainer(service, documentId, { summarizing: true });
	try {
		const entryPoint = await summarizer.container.getEntryPoint() as {
			ISummarizer?: {
				summarizeOnDemand(options: { reason: string; fullTree: boolean }): {
					summarySubmitted: Promise<any>;
					summaryOpBroadcasted: Promise<any>;
					receivedSummaryAckOrNack: Promise<any>;
				};
			};
		};
		assert(entryPoint.ISummarizer !== undefined, "Missing upstream summarizer");
		const result = entryPoint.ISummarizer.summarizeOnDemand({ reason, fullTree: true });
		const submitted = await result.summarySubmitted;
		assert(submitted.success, `Summary submission failed: ${submitted.error}`);
		const broadcast = await result.summaryOpBroadcasted;
		assert(broadcast.success, `Summary broadcast failed: ${broadcast.error}`);
		const acknowledged = await result.receivedSummaryAckOrNack;
		assert(acknowledged.success, `Summary acknowledgement failed: ${acknowledged.error}`);
		const handle = acknowledged.data.summaryAckOp.contents.handle;
		assert.equal(typeof handle, "string", "Summary acknowledgement has no handle");
		const stored = await storedSnapshot(service, resolvedUrl, handle);
		return {
			publication: {
				handle,
				referenceSequenceNumber: submitted.data.referenceSequenceNumber,
				summarySequenceNumber: broadcast.data.summarizeOp.sequenceNumber,
				acknowledgementSequenceNumber: acknowledged.data.summaryAckOp.sequenceNumber,
			},
			...stored,
		};
	} finally {
		summarizer.container.dispose();
	}
}

async function attachedGraph() {
	const service = startEphemeralService(false);
	const client = service.newClient({ oldestSupportedClient });
	const container = await client.createAttachedContainer(GraphStore);
	const messages: unknown[] = [];
	const inner = container as unknown as {
		container: {
			resolvedUrl: unknown;
			deltaManager: { on(event: "op", listener: (message: ISequencedDocumentMessage) => void): void };
		};
	};
	inner.container.deltaManager.on("op", (message) => messages.push(copy(message)));
	return { service, client, container, messages, resolvedUrl: inner.container.resolvedUrl };
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

async function activeDocumentAttachment(
	container: { id: string; data: GraphData },
	service: { synchronize(): Promise<void> },
	parentView: RootView,
	messages: unknown[],
) {
	const activeTree = await container.data.createTree();
	const activeView = newRoot(activeTree);
	activeView.root.label = "active-target";
	const targetHandle = activeTree.handle;
	const targetPath = pathOf(targetHandle);
	const targetAttachedBefore = isAttached(activeTree);
	const targetLocalBefore = visible(activeView.root);
	const parentBefore = visible(parentView.root);
	let transactionEntered = false;
	const error = errorOf(() => Tree.runTransaction(activeView, () => {
		transactionEntered = true;
		parentView.root.link = targetHandle;
	}));
	await service.synchronize();
	const transport = messages.splice(0);
	let parentAfter: unknown;
	const parentAfterError = errorOf(() => {
		parentAfter = visible(parentView.root);
	});
	let targetLocalAfter: unknown;
	const targetLocalError = errorOf(() => {
		targetLocalAfter = visible(activeView.root);
	});
	let targetAttachedAfter: unknown;
	const targetAttachedError = errorOf(() => {
		targetAttachedAfter = isAttached(activeTree);
	});
	return {
		documentId: container.id,
		error,
		transactionEntered,
		targetPath,
		target: {
			path: targetPath,
			attached: {
				before: targetAttachedBefore,
				after: targetAttachedAfter,
				error: targetAttachedError,
			},
			local: {
				before: targetLocalBefore,
				after: targetLocalAfter,
				error: targetLocalError,
			},
		},
		parentBefore,
		parentAfter,
		parent: { before: parentBefore, after: parentAfter, error: parentAfterError },
		transport,
		allocation: messageOrder(transport).filter((item) => item === "id-allocation"),
	};
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

			record("serialization", raw, "two-channel-cycle", "map-summary", summaryBlobText((await summarize(left)).summary));
			record("summaries", raw, "detached-tree", "tree-summary", (await summarize(targetTree)).summary);
			deferredLiveAttachment = { scenarios, observations, raw };
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
			deferredTransactionBranch = { scenarios, observations, raw };
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
		const { service, container, messages, resolvedUrl } = await attachedGraph();
		try {
			const publishCheckpoint = async (scenarioId: string) => {
				await service.synchronize();
				const published = await publishDocument(
					service, container.id, resolvedUrl, `watershed ${scenarioId}`,
				);
				const evidence = record(
					"summaries", raw, scenarioId, "published-document", published, scenarioId,
				);
				await service.synchronize();
				messages.length = 0;
				return { published, evidence };
			};
			const tree = await container.data.createTree();
			const view = newRoot(tree);
			container.data.root.set("tree", tree.handle);
			const target = await container.data.createMap();
			target.set("value", "before");
			view.root.link = target.handle;
			await service.synchronize();
			messages.length = 0;

			const beforeSummary = await summarize(tree);
			const beforePublication = await publishCheckpoint("before-removal");
			observations.push({
				id: "before-removal",
				value: {
					routes: gcNodes(tree),
					path: view.root.link === undefined ? undefined : pathOf(view.root.link),
					documentGc: beforePublication.published.metadata.gcNodes,
					snapshotSequenceNumber: beforePublication.published.snapshot.sequenceNumber,
				},
				evidence: [
					record("summaries", raw, "before-removal", "tree-summary", beforeSummary.summary),
					beforePublication.evidence,
				],
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
			const afterPublication = await publishCheckpoint("after-removal");
			observations.push({
				id: "after-removal",
				value: {
					routes: gcNodes(tree),
					attached: isAttached(target),
					documentGc: afterPublication.published.metadata.gcNodes,
					snapshotSequenceNumber: afterPublication.published.snapshot.sequenceNumber,
				},
				evidence: [
					record("summaries", raw, "after-removal", "tree-summary", afterSummary.summary),
					afterPublication.evidence,
				],
			});

			const removal = retainedHandles[0];
			assert(removal !== undefined, "Handle removal must produce a revertible");
			removal.revert();
			await service.synchronize();
			const undoMessages = messages.splice(0);
			const undoPublication = await publishCheckpoint("after-undo");
			observations.push({
				id: "after-undo",
				value: {
					path: view.root.link === undefined ? undefined : pathOf(view.root.link),
					targetValue: target.get("value"),
					documentGc: undoPublication.published.metadata.gcNodes,
					snapshotSequenceNumber: undoPublication.published.snapshot.sequenceNumber,
				},
				evidence: [
					record("messages", raw, "after-undo", "undo", undoMessages),
					undoPublication.evidence,
				],
			});

			const retaining = view.fork() as RootView;
			view.root.link = undefined;
			await service.synchronize();
			const repairPublication = await publishCheckpoint("retained-repair");
			observations.push({
				id: "retained-repair",
				value: {
					routes: gcNodes(tree),
					mainHasReference: view.root.link !== undefined,
					branchPath: retaining.root.link === undefined ? undefined : pathOf(retaining.root.link),
					documentGc: repairPublication.published.metadata.gcNodes,
					snapshotSequenceNumber: repairPublication.published.snapshot.sequenceNumber,
				},
				evidence: [
					record("summaries", raw, "retained-repair", "gc", gcData(tree)),
					repairPublication.evidence,
				],
			});
			retaining.dispose();
			const branchPublication = await publishCheckpoint("branch-disposal");
			observations.push({
				id: "branch-disposal",
				value: {
					routes: gcNodes(tree),
					documentGc: branchPublication.published.metadata.gcNodes,
					snapshotSequenceNumber: branchPublication.published.snapshot.sequenceNumber,
				},
				evidence: [
					record("summaries", raw, "branch-disposal", "gc", gcData(tree)),
					branchPublication.evidence,
				],
			});
			off();
			for (const handle of retainedHandles) {
				if (handle.status === RevertibleStatus.Valid) handle.dispose();
			}
			const revertiblePublication = await publishCheckpoint("revertible-disposal");
			observations.push({
				id: "revertible-disposal",
				value: {
					routes: gcNodes(tree),
					documentGc: revertiblePublication.published.metadata.gcNodes,
					snapshotSequenceNumber: revertiblePublication.published.snapshot.sequenceNumber,
				},
				evidence: [
					record("summaries", raw, "revertible-disposal", "gc", gcData(tree)),
					revertiblePublication.evidence,
				],
			});

			const secondary = await container.createDataStore(GraphStore);
			container.data.root.set("secondary", secondary.root.handle);
			await service.synchronize();
			container.data.root.delete("secondary");
			await service.synchronize();
			const secondaryMessages = messages.splice(0);
			const secondaryPublication = await publishCheckpoint("unreferenced-datastore");
			observations.push({
				id: "unreferenced-datastore",
				value: {
					path: pathOf(secondary.root.handle),
					attached: isAttached(secondary.root),
					rootGc: gcNodes(container.data.root),
					documentGc: secondaryPublication.published.metadata.gcNodes,
					components: secondaryPublication.published.metadata.components,
					snapshotSequenceNumber: secondaryPublication.published.snapshot.sequenceNumber,
				},
				evidence: [
					record("messages", raw, "unreferenced-datastore", "remove", secondaryMessages),
					secondaryPublication.evidence,
				],
			});

			view.root.link = target.handle;
			await service.synchronize();
			const freshPublication = await publishCheckpoint("fresh-load");
			const storedBlobEvidence = record(
				"serialization", raw, "fresh-load", "stored-summary-blobs",
				Object.keys(freshPublication.published.snapshot.blobs),
			);
			const loaded = await openGraphContainer(service, container.id, {
				version: freshPublication.published.publication.handle,
			});
			try {
				const loadedTreeHandle = loaded.data.root.get("tree") as IFluidHandle;
				const loadedTree = await loadedTreeHandle.get() as typeof tree;
				const loadedView = asAlpha(loadedTree.viewWith(
					new TreeViewConfiguration({ schema: Root, enableSchemaValidation: true }),
				));
				const loadedTarget = await loadedView.root.link?.get() as ISharedMap;
				const loadedTargetPath = pathOf(loadedView.root.link as IFluidHandle);
				const loadedTargetBefore = Object.fromEntries(loadedTarget.entries());
				const writerTargetBefore = Object.fromEntries(target.entries());
				loadedTarget.set("continued", true);
				await service.synchronize();
				assert.equal(target.get("continued"), true, "Writer did not observe fresh-client edit");
				const continuationMessages = messages.splice(0);
				const continuation = mapSetObservation(continuationMessages, "continued");
				assert(continuation !== undefined, "Fresh-client continuation transport was not observed");
				assert.equal(continuation.route, loadedTargetPath);
				const continuationEvidence = record(
					"messages", raw, "fresh-load", "continuation", continuationMessages, "after-edit",
				);
				observations.push({
					id: "fresh-load",
					value: {
						path: loadedTargetPath,
						continued: target.get("continued"),
						loadedVersion: freshPublication.published.publication.handle,
						snapshotSequenceNumber: freshPublication.published.snapshot.sequenceNumber,
						documentGc: freshPublication.published.metadata.gcNodes,
						publication: {
							handle: freshPublication.published.publication.handle,
							snapshotSequenceNumber: freshPublication.published.snapshot.sequenceNumber,
							acknowledgementSequenceNumber:
								freshPublication.published.publication.acknowledgementSequenceNumber,
						},
						loadedTree: { path: pathOf(loadedTreeHandle) },
						loadedTarget: {
							path: loadedTargetPath,
							before: loadedTargetBefore,
							after: Object.fromEntries(loadedTarget.entries()),
						},
						writerTarget: {
							path: pathOf(target.handle),
							before: writerTargetBefore,
							after: Object.fromEntries(target.entries()),
						},
						continuation: {
							...continuation,
							publicationHandle: freshPublication.published.publication.handle,
						},
					},
					evidence: [
						record("summaries", raw, "fresh-load", "loaded-tree", (await summarize(loadedTree)).summary),
						freshPublication.evidence,
						storedBlobEvidence,
						continuationEvidence,
					],
				});
			} finally {
				loaded.container.dispose();
			}
			await writeCase("handle-retention", scenarios, observations, raw);
		} finally {
			await service.close();
		}
	});

	it("captures real active target publication attempts after stable case streams", async () => {
		for (const [id, scenarioId, deferred] of [
			["live-channel-attachment", "active-transaction", deferredLiveAttachment],
			["handle-transaction-branch", "active-target", deferredTransactionBranch],
		] as const) {
			assert(deferred !== undefined, `${id}: deferred case`);
			const { service, container, messages } = await attachedGraph();
			try {
				const tree = await container.data.createTree();
				const view = newRoot(tree);
				container.data.root.set("tree", tree.handle);
				await service.synchronize();
				messages.length = 0;
				const active = await activeDocumentAttachment(container, service, view, messages);
				const index = deferred.scenarios.findIndex((scenario) => scenario.id === scenarioId);
				assert(index >= 0, `${id}: active scenario`);
				deferred.observations.splice(index, 0, {
					id: scenarioId,
					value: active,
					evidence: [record(
						"messages", deferred.raw, scenarioId,
						"document-attachment", active, "after-attempt",
					)],
				});
				await writeCase(id, deferred.scenarios, deferred.observations, deferred.raw);
			} finally {
				await service.close();
			}
		}
	});
});
