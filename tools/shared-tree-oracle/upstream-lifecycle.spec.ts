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
interface LifecycleScenario {
	id: string;
	operation: string;
	input?: unknown;
	codec?: unknown;
	commands?: unknown[];
	replay?: unknown;
}
interface GraphReplayCheckpoint {
	published: false;
	prefixEndSequenceNumber: number;
	deliveryPrefixLength?: number;
}
interface DeferredCase {
	scenarios: LifecycleScenario[];
	observations: Observation[];
	raw: {
		messages: RawRecord[];
		serialization: RawRecord[];
		summaries: RawRecord[];
	};
	input?: Record<string, unknown>;
}
let deferredLiveAttachment: DeferredCase | undefined;
let deferredTransactionBranch: DeferredCase | undefined;
let deferredHandleLeaves: (() => Promise<void>) | undefined;

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

function serializerFor(handle: IFluidHandle): FluidSerializer {
	const context = (internalHandle(handle) as IFluidHandleInternal & {
		routeContext?: ConstructorParameters<typeof FluidSerializer>[0];
	}).routeContext;
	assert(context !== undefined, "The handle must have a datastore route context");
	return new FluidSerializer(context);
}

function mapValue(map: ISharedMap) {
	return serializerFor(map.handle).encode(
		Object.fromEntries(map.entries()), internalHandle(map.handle),
	);
}

function mapType(map: ISharedMap): string {
	const type = (map as unknown as { attributes?: { type?: unknown } }).attributes?.type;
	assert(typeof type === "string", "The resolved map must expose its channel type");
	return type;
}

async function errorOfAsync(action: () => Promise<unknown>): Promise<string> {
	try {
		await action();
		return "";
	} catch (error) {
		try {
			if (typeof error === "object" && error !== null) {
				const value = error as {
					errorFromRequestFluidObject?: unknown;
					message?: unknown;
					name?: unknown;
					code?: unknown;
				};
				return JSON.stringify({
					errorFromRequestFluidObject: value.errorFromRequestFluidObject,
					message: value.message,
					name: value.name,
					code: value.code,
				});
			}
			return String(error);
		} catch {
			return String(error);
		}
	}
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

function storedSchemaFromSummary(value: unknown): unknown {
	const schemas = summaryBlobText(value).flatMap((blob) => {
		try {
			const parsed = JSON.parse(blob);
			return parsed?.version === 2
				&& parsed?.nodes !== undefined
				&& parsed?.root !== undefined
				? [parsed]
				: [];
		} catch {
			return [];
		}
	});
	assert.equal(schemas.length, 1, "The summary must contain one stored schema");
	return schemas[0];
}

function messageOrder(messages: unknown[]): string[] {
	const order: string[] = [];
	for (const message of messages) {
		if ((message as { type?: string }).type === "join") continue;
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
	scenarios: LifecycleScenario[],
	observations: Observation[],
	raw: {
		messages: RawRecord[];
		serialization: RawRecord[];
		summaries: RawRecord[];
	},
	input: Record<string, unknown> = {},
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
		input: { ...input, scenarios },
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

function mockTree(id: string, datastoreId?: string) {
	const runtime = new MockFluidDataStoreRuntime({
		...(datastoreId === undefined ? {} : { id: datastoreId }),
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

function createMapWithId(root: ISharedMap, id: string): ISharedMap {
	const runtime = (root as unknown as {
		runtime: { createChannel(id: string, type: string): unknown };
	}).runtime;
	return runtime.createChannel(id, SharedMapAlpha.getFactory().type) as ISharedMap;
}

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

async function initialGraphSnapshot(service: unknown, resolvedUrl: unknown) {
	const documentService = await serviceInternals(service)
		.getDocumentServiceFactory()
		.createDocumentService(resolvedUrl as any);
	try {
		const storage = await documentService.connectToStorage();
		const versions = await storage.getVersions(null, 1);
		assert(versions[0] !== undefined, "Initial graph snapshot version is missing");
		const tree = await storage.getSnapshotTree(versions[0]);
		assert(tree !== null, "Initial graph snapshot is missing");
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
		assert.equal(typeof attributesId, "string", "Initial graph snapshot has no protocol attributes");
		const attributes = parseJson(Uint8Array.from(Buffer.from(blobs[attributesId], "base64"))) as {
			sequenceNumber?: unknown;
		};
		assert.equal(typeof attributes.sequenceNumber, "number", "Initial graph snapshot sequence");
		const sequenceNumber = attributes.sequenceNumber as number;
		const compressorId = tree.blobs[".idCompressor"];
		assert.equal(typeof compressorId, "string", "Initial graph snapshot has no compressor");
		assert.equal(typeof blobs[compressorId], "string", "Initial compressor bytes are missing");
		return {
			snapshot: {
				version: versions[0],
				tree,
				blobs,
				blobEncoding: "base64",
				sequenceNumber,
			},
			compressor: {
				blobId: compressorId,
				encoding: "base64",
				bytes: blobs[compressorId],
			},
		};
	} finally {
		documentService.dispose();
	}
}

async function graphMessages(service: unknown, resolvedUrl: unknown) {
	const documentService = await serviceInternals(service)
		.getDocumentServiceFactory()
		.createDocumentService(resolvedUrl as any);
	try {
		const storage = await documentService.connectToDeltaStorage();
		const stream = storage.fetchMessages(1, undefined);
		const messages: unknown[] = [];
		for (;;) {
			const chunk = await stream.read();
			if (chunk.done) return messages as ISequencedDocumentMessage[];
			messages.push(...chunk.value);
		}
	} finally {
		documentService.dispose();
	}
}

function graphPrefix(
	snapshot: { sequenceNumber: number },
	messages: ISequencedDocumentMessage[],
	lastSequenceNumber: number,
) {
	const prefix = messages.filter((message) =>
		message.sequenceNumber > snapshot.sequenceNumber
		&& message.sequenceNumber <= lastSequenceNumber);
	assert.deepEqual(
		prefix.map((message) => message.sequenceNumber),
		Array.from(
			{ length: lastSequenceNumber - snapshot.sequenceNumber },
			(_, index) => snapshot.sequenceNumber + index + 1,
		),
		"Incomplete graph delivery prefix",
	);
	return copy(prefix);
}

function graphStoredSchema() {
	return {
		version: 2,
		nodes: {
			"com.fluidframework.leaf.handle": { kind: { leaf: 3 } },
			"com.fluidframework.leaf.string": { kind: { leaf: 1 } },
			"org.watershed.shared-tree.handles.Links": {
				kind: { map: { kind: "Optional", types: ["com.fluidframework.leaf.handle"] } },
			},
			"org.watershed.shared-tree.handles.Root": {
				kind: {
					object: {
						label: { kind: "Value", types: ["com.fluidframework.leaf.string"] },
						link: { kind: "Optional", types: ["com.fluidframework.leaf.handle"] },
						links: {
							kind: "Value",
							types: ["org.watershed.shared-tree.handles.Links"],
						},
						sequence: {
							kind: "Value",
							types: ["org.watershed.shared-tree.handles.Sequence"],
						},
					},
				},
			},
			"org.watershed.shared-tree.handles.Sequence": {
				kind: {
					object: {
						"": { kind: "Sequence", types: ["com.fluidframework.leaf.handle"] },
					},
				},
			},
		},
		root: { kind: "Value", types: ["org.watershed.shared-tree.handles.Root"] },
	};
}

function graphInitialRoot(label: string) {
	return {
		kind: "object",
		type: "org.watershed.shared-tree.handles.Root",
		fields: [
			["label", { kind: "string", value: label }],
			["links", {
				kind: "map",
				schemaId: "org.watershed.shared-tree.handles.Links",
				entries: [],
			}],
			["sequence", {
				kind: "array",
				schemaId: "org.watershed.shared-tree.handles.Sequence",
				elements: [],
			}],
		],
	};
}

function graphHandle(path: string) {
	return { kind: "handle", value: { type: "__fluid_handle__", url: path } };
}

function graphClientId(container: unknown) {
	const value = container as { clientId?: unknown; container?: { clientId?: unknown } };
	const clientId = value.clientId ?? value.container?.clientId;
	assert.equal(typeof clientId, "string", "Graph client ID is missing");
	return clientId;
}

function graphWriter(root: ISharedMap) {
	const runtime = (root as unknown as {
		runtime: { idCompressor: { localSessionId: string; serialize(local: boolean): string } };
	}).runtime;
	assert(runtime.idCompressor !== undefined, "Graph writer compressor is missing");
	return {
		sessionId: runtime.idCompressor.localSessionId,
		compressor: runtime.idCompressor.serialize(true),
	};
}

async function resolveGraphTarget(root: ISharedMap, path: string) {
	const handle = serializerFor(root.handle).decode({
		type: "__fluid_handle__",
		url: path,
	}) as IFluidHandle;
	return handle.get();
}

function mapReceiverTarget(map: ISharedMap) {
	return {
		path: pathOf(map.handle),
		channelType: mapType(map),
		data: mapValue(map),
	};
}

function treeReceiverTarget(tree: ITree, view: RootView) {
	return {
		path: pathOf(tree.handle),
		channelType: "https://graph.microsoft.com/types/tree",
		data: visible(view.root),
	};
}

function graphDecoderInput(
	container: unknown,
	initial: Awaited<ReturnType<typeof initialGraphSnapshot>>,
	writer: ReturnType<typeof graphWriter>,
	receiver: unknown,
	deliveryPrefix: ISequencedDocumentMessage[],
	receiverClientId = graphClientId(receiver),
) {
	return {
		documentId: (container as { id: string }).id,
		initialSnapshot: initial.snapshot,
		compressor: initial.compressor,
		deliveryPrefix,
		runtime: {
			oldestSupportedClient,
			enableRuntimeIdCompressor: "on",
			graphStoreType: GraphStore.type,
			registry: [
				{ channelType: SharedMapAlpha.getFactory().type, role: "entry-point" },
				{ channelType: treeFactory().type, role: "declared" },
			],
			entryPoint: {
				datastoreId: "A", channelId: "root", packagePath: [GraphStore.type],
			},
		},
		sessions: {
			writerClientId: graphClientId(container),
			receiverClientId,
			...(graphClientId(receiver) === receiverClientId ? {} : {
				receiverWriteClientId: graphClientId(receiver),
			}),
			writer,
		},
	};
}

function createChannelCommand(value: ISharedMap | ITree) {
	return {
		type: "create-channel",
		datastoreId: pathOf(value.handle).split("/")[1],
		channelId: pathOf(value.handle).split("/")[2],
		channelType: mapType(value as ISharedMap),
	};
}

function initializeTreeCommand(tree: ITree) {
	return {
		type: "initialize-tree", target: pathOf(tree.handle),
		storedSchema: graphStoredSchema(), initialValue: graphInitialRoot("root"),
	};
}

function historyCapture(
	graph: Awaited<ReturnType<typeof attachedGraph>>,
	peer: Awaited<ReturnType<typeof openGraphContainer>>,
	tree: ITree,
	view: RootView,
	peerTree: ITree,
	peerView: RootView,
	scenarios: LifecycleScenario[],
	observations: Observation[],
	raw: DeferredCase["raw"],
) {
	const commands: unknown[] = [
		createChannelCommand(tree), initializeTreeCommand(tree),
		{ type: "map-set", target: "/A/root", key: "tree", value: graphHandle(pathOf(tree.handle)) },
		{ type: "settle", checkpoint: "initial-tree" },
	];
	const targets: ISharedMap[] = [];
	const receiverClientId = graphClientId(peer.container);
	let previousSequence = 0;
	const checkpoints = async (
		id: string,
		branches: { id: string; disposed: boolean; view?: RootView }[] = [],
		stages: unknown[] = [],
	) => {
		await graph.service.synchronize();
		const messages = await graphMessages(graph.service, graph.resolvedUrl);
		const prefixEndSequenceNumber = messages.at(-1)?.sequenceNumber ?? 0;
		const prefix = graphPrefix(graph.initial.snapshot, messages, prefixEndSequenceNumber);
		const checkpoint = {
			tree: treeReceiverTarget(tree, view),
			receiver: {
				clientId: graphClientId(peer.container),
				tree: treeReceiverTarget(peerTree, peerView),
			},
			targets: await Promise.all(targets.map(async (target) => {
				const attached = isAttached(target);
				const resolved = attached
					? await resolveGraphTarget(peer.data.root, pathOf(target.handle)) as ISharedMap
					: undefined;
				return {
					...mapReceiverTarget(target),
					attached,
					...(resolved === undefined ? {} : { receiver: mapReceiverTarget(resolved) }),
				};
			})),
			branches: branches.map((branch) => ({
				id: branch.id,
				disposed: branch.disposed,
				...(branch.view === undefined ? {} : { data: visible(branch.view.root) }),
			})),
			compressor: graphWriter(graph.container.data.root),
			stages,
		};
		const observation = observations.find((item) => item.id === id);
		const scenario = scenarios.find((item) => item.id === id);
		assert(observation !== undefined && scenario !== undefined, `${id}: history checkpoint`);
		scenario.commands = copy(commands);
		scenario.replay = {
			published: raw.summaries.some((record) =>
				record.scenarioId === id && record.kind === "published-document"),
			prefixEndSequenceNumber,
			deliveryPrefixLength: prefix.length,
		};
		observation.value = { ...(observation.value as object), checkpoint };
		const transport = prefix.filter((message) => message.sequenceNumber > previousSequence);
		observation.evidence.push(
			record("messages", raw, id, transport.length === 0 ? "checkpoint" : "replay-transport",
				transport, id),
			record("serialization", raw, id, "history-checkpoint", checkpoint),
			record("summaries", raw, id, "checkpoint-tree", (await summarize(tree)).summary),
		);
		previousSequence = prefixEndSequenceNumber;
		return prefix;
	};
	return { commands, targets, receiverClientId, checkpoint: checkpoints };
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
	const messages: ISequencedDocumentMessage[] = [];
	const inner = container as unknown as {
		container: {
			resolvedUrl: unknown;
			deltaManager: { on(event: "op", listener: (message: ISequencedDocumentMessage) => void): void };
		};
	};
	inner.container.deltaManager.on("op", (message) => messages.push(copy(message)));
	const initial = await initialGraphSnapshot(service, inner.container.resolvedUrl);
	const writer = graphWriter(container.data.root);
	return {
		service,
		client,
		container,
		messages,
		resolvedUrl: inner.container.resolvedUrl,
		initial,
		writer,
	};
}

function newRoot(tree: Awaited<ReturnType<GraphData["createTree"]>>) {
	const view = existingRoot(tree);
	view.initialize(new Root({
		label: "root",
		links: new Links(),
		sequence: new Sequence(),
	}));
	return view;
}

function existingRoot(tree: ITree) {
	return asAlpha(tree.viewWith(
		new TreeViewConfiguration({ schema: Root, enableSchemaValidation: true }),
	));
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
		const scenarios: LifecycleScenario[] = [
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

		runtimeFactory.processAllMessages();
		const summary = await summarize(tree);
		const blobs = summaryBlobText(summary.summary);
		const uncompressed = blobs.find((blob) =>
			blob.includes('"builds"') && blob.includes('"trees":{"version":2'));
		assert(uncompressed !== undefined, "The summary must contain nonincremental FieldBatch V2");
		const schemaAware = blobs.find((blob) => blob.includes('"fields":{"version":2'));
		assert(schemaAware !== undefined, "The summary must contain schema-aware FieldBatch V2");
		const assignmentEvidence = new Map<string, { section: EvidenceSection; id: string }>();
		for (const [id, marker] of [
			["malformed-marker", { type: "__fluid_handle__" }],
			["unsupported-marker", { type: "__fluid_handle_v3__", url: "/unsupported" }],
		] as const) {
			const outcome = {
				error: errorOf(() => {
					(view.root as unknown as { link: unknown }).link = marker;
				}),
			};
			assert.notEqual(outcome.error, "", `${id}: tree assignment must refuse ordinary JSON`);
			assignmentEvidence.set(id, record(
				"serialization",
				raw,
				id,
				"tree-assignment-outcome",
				{ marker, outcome },
			));
		}

		deferredHandleLeaves = async () => {
			const live = await attachedGraph();
			try {
			const target = createMapWithId(live.container.data.root, "leaf-target");
			target.set("value", "target");
			const escapedLogicalId = "space and#hash";
			const escapedTarget = createMapWithId(live.container.data.root, escapedLogicalId);
			escapedTarget.set("value", "escaped-target");
			live.container.data.root.set("target", target.handle);
			live.container.data.root.set("escaped", escapedTarget.handle);

			const firstContext = await live.container.createDataStore(GraphStore);
			const firstChild = createMapWithId(firstContext.root, "child");
			firstChild.set("context", "first");
			firstContext.root.set("child", firstChild.handle);
			live.container.data.root.set("first-context", firstContext.root.handle);

			const secondContext = await live.container.createDataStore(GraphStore);
			const secondChild = createMapWithId(secondContext.root, "child");
			secondChild.set("context", "second");
			secondContext.root.set("child", secondChild.handle);
			live.container.data.root.set("second-context", secondContext.root.handle);
			await live.service.synchronize();

			const liveSerializer = serializerFor(live.container.data.root.handle);
			const encoded = liveSerializer.stringify(
				firstChild.handle,
				internalHandle(live.container.data.root.handle),
			);
			const decoded = liveSerializer.parse(encoded) as IFluidHandle;
			const sourceTarget = await firstChild.handle.get() as ISharedMap;
			const decodedTarget = await decoded.get() as ISharedMap;
			const sameTargetEvidence = {
				encoded: JSON.parse(encoded),
				sourcePath: pathOf(firstChild.handle),
				decodedPath: pathOf(decoded),
				sourceTarget: {
					path: pathOf(sourceTarget.handle),
					type: mapType(sourceTarget),
					data: mapValue(sourceTarget),
				},
				decodedTarget: {
					path: pathOf(decodedTarget.handle),
					type: mapType(decodedTarget),
					data: mapValue(decodedTarget),
				},
				sameHandleInstance: decoded === firstChild.handle,
				sameResolvedInstance: decodedTarget === sourceTarget,
			};
			observations.push({
				id: "same-target-handles",
				value: sameTargetEvidence,
				evidence: [record(
					"serialization",
					raw,
					"same-target-handles",
					"live-handle-resolution",
					sameTargetEvidence,
				)],
			});

			const relativeContexts = [];
			for (const [context, child] of [
				[firstContext, firstChild],
				[secondContext, secondChild],
			] as const) {
				const contextSerializer = serializerFor(context.root.handle);
				const marker = { type: "__fluid_handle__", url: "child" };
				const relative = contextSerializer.decode(marker) as IFluidHandle;
				const resolved = await relative.get() as ISharedMap;
				relativeContexts.push({
					sourceDatastorePath: pathOf(context.root.handle).replace(/\/root$/, ""),
					relativeUrl: marker.url,
					decodedPath: pathOf(relative),
					resolvedTarget: {
						path: pathOf(resolved.handle),
						type: mapType(resolved),
						data: mapValue(resolved),
					},
				});
			}
			observations.push({
				id: "relative-path",
				value: { contexts: relativeContexts },
				evidence: [record(
					"serialization",
					raw,
					"relative-path",
					"legacy-relative-resolution",
					{ marker: { type: "__fluid_handle__", url: "child" }, contexts: relativeContexts },
				)],
			});

			const escapedMarker = {
				type: "__fluid_handle__",
				url: `${pathOf(escapedTarget.handle).replace(" ", "%20").replace("#", "%23")}`,
			};
			const escaped = liveSerializer.decode(escapedMarker) as IFluidHandle;
			const escapedResolved = await escaped.get() as ISharedMap;
			const escapedValue = {
				logicalId: escapedLogicalId,
				sourcePath: pathOf(escapedTarget.handle),
				serializedMarker: escapedMarker,
				decodedPath: pathOf(escaped),
				resolvedTarget: {
					path: pathOf(escapedResolved.handle),
					type: mapType(escapedResolved),
					data: mapValue(escapedResolved),
				},
				sameHandleInstance: escaped === escapedTarget.handle,
				sameResolvedInstance: escapedResolved === escapedTarget,
			};
			observations.push({
				id: "escaped-path",
				value: escapedValue,
				evidence: [record(
					"serialization",
					raw,
					"escaped-path",
					"escaped-live-resolution",
					escapedValue,
				)],
			});

			const replayTree = await live.container.data.createTree();
			const replayView = newRoot(replayTree);
			replayView.root.link = firstChild.handle;
			replayView.root.links.set("target", firstChild.handle);
			replayView.root.sequence.insertAtEnd(firstChild.handle);
			live.container.data.root.set("leaf-codec-tree", replayTree.handle);
			await live.service.synchronize();

			const codecCapture = mockTree("leaf-codec", "B");
			const codecTarget = SharedMapAlpha.create(codecCapture.runtime, "child");
			codecTarget.set("context", "codec");
			codecCapture.view.root.link = codecTarget.handle;
			codecCapture.view.root.links.set("target", codecTarget.handle);
			codecCapture.view.root.sequence.insertAtEnd(codecTarget.handle);

			const createEditTree = (id: string) => treeFactory().create(codecCapture.runtime, id);
			const requiredEditTree = createEditTree("required-root-input");
			const requiredEditView = requiredEditTree.viewWith(
				new TreeViewConfiguration({ schema: sf.handle }),
			);
			requiredEditView.initialize(codecTarget.handle);
			codecCapture.runtimeFactory.processAllMessages();

			const optionalEditTree = createEditTree("optional-root-input");
			const optionalEditView = optionalEditTree.viewWith(
				new TreeViewConfiguration({ schema: sf.optional(sf.handle) }),
			);
			optionalEditView.initialize(codecTarget.handle);
			codecCapture.runtimeFactory.processAllMessages();
			const optionalBeforeClear = pathOf(optionalEditView.root as IFluidHandle);
			optionalEditView.root = undefined;
			codecCapture.runtimeFactory.processAllMessages();

			const rootEdit = (id: string) => {
				const editTree = createEditTree(`${id}-input`);
				const editView = asAlpha(editTree.viewWith(
					new TreeViewConfiguration({ schema: Root, enableSchemaValidation: true }),
				));
				editView.initialize(new Root({
					label: id,
					links: new Links(),
					sequence: new Sequence(),
				}));
				codecCapture.runtimeFactory.processAllMessages();
				return {
					tree: editTree,
					view: editView,
					initialRoot: {
						kind: "object",
						type: "org.watershed.shared-tree.handles.Root",
						fields: [
							["label", { kind: "string", value: id }],
							["links", {
								kind: "map",
								schemaId: "org.watershed.shared-tree.handles.Links",
								entries: [],
							}],
							["sequence", {
								kind: "array",
								schemaId: "org.watershed.shared-tree.handles.Sequence",
								elements: [],
							}],
						],
					},
				};
			};
			const objectEdit = rootEdit("object-field");
			objectEdit.view.root.link = codecTarget.handle;
			codecCapture.runtimeFactory.processAllMessages();
			const mapEdit = rootEdit("map-entry");
			mapEdit.view.root.links.set("target", codecTarget.handle);
			codecCapture.runtimeFactory.processAllMessages();
			const arrayEdit = rootEdit("array-element");
			arrayEdit.view.root.sequence.insertAtEnd(codecTarget.handle);
			codecCapture.runtimeFactory.processAllMessages();

			const taggedValue = {
				kind: "handle",
				value: { type: "__fluid_handle__", url: "/B/child" },
			};
			const editCaptures = [
				{
					id: "required-root",
					tree: requiredEditTree,
					initialRoot: null,
					edit: { operation: "initialize-root", value: taggedValue },
					output: { path: pathOf(requiredEditView.root) },
				},
				{
					id: "optional-root",
					tree: optionalEditTree,
					initialRoot: null,
					edit: { operation: "initialize-clear-root", value: taggedValue },
					output: { beforeClear: optionalBeforeClear, afterClear: null },
				},
				{
					id: "object-field",
					tree: objectEdit.tree,
					initialRoot: objectEdit.initialRoot,
					edit: {
						operation: "set-object-field",
						field: "link",
						value: taggedValue,
					},
					output: copy(visible(objectEdit.view.root)),
				},
				{
					id: "map-entry",
					tree: mapEdit.tree,
					initialRoot: mapEdit.initialRoot,
					edit: {
						operation: "set-map-entry",
						field: "links",
						key: "target",
						value: taggedValue,
					},
					output: copy(visible(mapEdit.view.root)),
				},
				{
					id: "array-element",
					tree: arrayEdit.tree,
					initialRoot: arrayEdit.initialRoot,
					edit: {
						operation: "insert-array-element",
						field: "sequence",
						index: 0,
						value: taggedValue,
					},
					output: copy(visible(arrayEdit.view.root)),
				},
			];
			for (const capture of editCaptures) {
				const input = {
					storedSchema: storedSchemaFromSummary((await summarize(capture.tree)).summary),
					sourceDatastoreContext: "/B",
					taggedValue,
					initialRoot: capture.initialRoot,
					edit: capture.edit,
					expectedOutput: capture.output,
				};
				const scenario = scenarios.find((item) => item.id === capture.id);
				const observationIndex = observations.findIndex((item) => item.id === capture.id);
				assert(scenario !== undefined && observationIndex >= 0);
				scenario.input = input;
				observations[observationIndex] = {
					id: capture.id,
					value: capture.output,
					evidence: [record(
						"serialization",
						raw,
						capture.id,
						"executable-edit",
						{ input, output: capture.output },
					)],
				};
			}

			const replaySummary = await summarize(codecCapture.tree);
			const replayBlobs = summaryBlobText(replaySummary.summary);
			const storedSchemaText = replayBlobs.find((blob) =>
				blob.includes('"nodes"')
				&& blob.includes('"org.watershed.shared-tree.handles.Root"')
				&& blob.includes('"com.fluidframework.leaf.handle"'));
			const uncompressedText = replayBlobs.find((blob) =>
				blob.includes('"builds"') && blob.includes('"trees":{"version":2'));
			const schemaAwareText = replayBlobs.find((blob) =>
				blob.includes('"fields":{"version":2'));
			assert(storedSchemaText !== undefined, "The summary must contain the stored schema");
			assert(uncompressedText !== undefined, "The summary must contain replayable builds");
			assert(schemaAwareText !== undefined, "The summary must contain the replayable forest");
			const storedSchema = JSON.parse(storedSchemaText);
			const uncompressedPayload = JSON.parse(uncompressedText).trunk[0].change[0]
				.data.builds.trees;
			const schemaAwarePayload = JSON.parse(schemaAwareText);
			const marker = { type: "__fluid_handle__", url: "/B/child" };
			const handleNode = { type: "com.fluidframework.leaf.handle", value: marker, fields: {} };
			const codecInput = {
				storedSchema,
				sourceDatastoreContext: "/B",
				taggedValue: { kind: "handle", value: marker },
			};
			const uncompressedScenario = scenarios.find((item) => item.id === "uncompressed-v2");
			const schemaAwareScenario = scenarios.find((item) => item.id === "schema-aware-v2");
			assert(uncompressedScenario !== undefined && schemaAwareScenario !== undefined);
			const uncompressedCodec = {
				...codecInput,
				form: "nonincremental-field-batch-v2",
				fieldKeys: ["build"],
				payload: uncompressedPayload,
				expectedDecoded: [handleNode],
			};
			const schemaAwareCodec = {
				...codecInput,
				form: "schema-aware-field-batch-v2",
				fieldKeys: schemaAwarePayload.keys,
				payload: schemaAwarePayload.fields,
				expectedDecoded: [{
					type: "org.watershed.shared-tree.handles.Root",
					fields: {
						label: [{ type: "com.fluidframework.leaf.string", value: "leaf-codec", fields: {} }],
						link: [handleNode],
						links: [{
							type: "org.watershed.shared-tree.handles.Links",
							fields: { target: [handleNode] },
						}],
						sequence: [{
							type: "org.watershed.shared-tree.handles.Sequence",
							fields: { "": [handleNode] },
						}],
					},
				}],
			};
			uncompressedScenario.codec = uncompressedCodec;
			schemaAwareScenario.codec = schemaAwareCodec;

			observations.push({
				id: "uncompressed-v2",
				value: {
					version: 2,
					decoded: uncompressedCodec.expectedDecoded,
				},
				evidence: [record(
					"summaries",
					raw,
					"uncompressed-v2",
					"field-batch-v2",
					uncompressedCodec,
				)],
			});
			observations.push({
				id: "schema-aware-v2",
				value: {
					version: 2,
					decoded: schemaAwareCodec.expectedDecoded,
				},
				evidence: [record(
					"summaries",
					raw,
					"schema-aware-v2",
					"schema-aware-field-batch-v2",
					schemaAwareCodec,
				)],
			});

			const serializerCases = [
				{
					id: "missing-url",
					method: "decode",
					value: { type: "__fluid_handle__" },
					profile: { outcome: "refused", reason: "invalid handle marker" },
				},
				{
					id: "non-string-url",
					method: "parse",
					value: { type: "__fluid_handle__", url: 7 },
					profile: { outcome: "refused", reason: "invalid handle marker" },
				},
				{
					id: "nested-late-malformed",
					method: "decode",
					value: {
						first: marker,
						later: { type: "__fluid_handle__" },
					},
					profile: { outcome: "refused", reason: "invalid handle marker" },
				},
				{
					id: "pending-payload",
					method: "decode",
					value: { ...marker, payloadPending: true },
					profile: { outcome: "refused", reason: "pending handle payload" },
				},
			] as const;
			const malformedOutcomes = [];
			for (const item of serializerCases) {
				let decodedValue: unknown;
				const serializerError = errorOf(() => {
					decodedValue = item.method === "parse"
						? liveSerializer.parse(JSON.stringify(item.value))
						: liveSerializer.decode(item.value);
				});
				const handle = decodedValue as IFluidHandle | undefined;
				const decodedPath = handle === undefined || typeof handle.get !== "function"
					? undefined
					: pathOf(handle);
				const treeImportError = errorOf(() => {
					(replayView.root as unknown as { link: unknown }).link =
						decodedValue ?? item.value;
				});
				replayView.root.link = firstChild.handle;
				malformedOutcomes.push({
					id: item.id,
					method: item.method,
					input: item.value,
					serializer: {
						kind: serializerError === "" ? "handle" : "error",
						error: serializerError,
						decodedPath,
					},
					resolution: {
						attempted: false,
						reason: item.id === "pending-payload"
							? "payload pending"
							: "serializer did not produce a resolvable handle",
					},
					treeImport: {
						kind: treeImportError === "" ? "accepted" : "refused",
						error: treeImportError,
					},
					nativeProfile: item.profile,
				});
			}
			observations.push({
				id: "malformed-marker",
				value: { outcomes: malformedOutcomes },
				evidence: [
					assignmentEvidence.get("malformed-marker") as {
						section: EvidenceSection;
						id: string;
					},
					record(
						"serialization",
						raw,
						"malformed-marker",
						"serializer-outcomes",
						{ outcomes: malformedOutcomes },
					),
				],
			});

			const unsupportedCases = [
				{
					id: "unknown-marker-kind",
					value: { type: "__fluid_handle_v3__", url: "/unsupported" },
					profile: { outcome: "refused", reason: "invalid handle marker" },
				},
				{
					id: "external-url",
					value: { type: "__fluid_handle__", url: "https://example.test/object" },
					profile: { outcome: "refused", reason: "external handle path" },
				},
				{
					id: "traversal",
					value: { type: "__fluid_handle__", url: "../child" },
					profile: { outcome: "refused", reason: "path traversal" },
				},
				{
					id: "invalid-escape",
					value: { type: "__fluid_handle__", url: "/B/bad%ZZ" },
					profile: { outcome: "refused", reason: "invalid path escape" },
				},
			] as const;
			const unsupportedOutcomes = [];
			for (const item of unsupportedCases) {
				const decodedValue = liveSerializer.decode(item.value);
				const handle = decodedValue as IFluidHandle;
				const isHandle = typeof handle?.get === "function";
				const resolutionError = isHandle
					? await errorOfAsync(async () => handle.get())
					: "";
				const treeImportError = errorOf(() => {
					(replayView.root as unknown as { link: unknown }).link = decodedValue;
				});
				replayView.root.link = firstChild.handle;
				unsupportedOutcomes.push({
					id: item.id,
					method: "decode",
					input: item.value,
					serializer: isHandle
						? { kind: "handle", decodedPath: pathOf(handle) }
						: { kind: "json", value: decodedValue },
					resolution: isHandle
						? { attempted: true, error: resolutionError }
						: { attempted: false, reason: "ordinary JSON" },
					treeImport: {
						kind: treeImportError === "" ? "accepted" : "refused",
						error: treeImportError,
					},
					nativeProfile: item.profile,
				});
			}
			observations.push({
				id: "unsupported-marker",
				value: { outcomes: unsupportedOutcomes },
				evidence: [
					assignmentEvidence.get("unsupported-marker") as {
						section: EvidenceSection;
						id: string;
					},
					record(
						"serialization",
						raw,
						"unsupported-marker",
						"serializer-outcomes",
						{ outcomes: unsupportedOutcomes },
					),
				],
			});

			record("messages", raw, "object-field", "checkpoint", [], "mock-runtime-drained");
			await writeCase("handle-leaves", scenarios, observations, raw, {
				sourceDatastoreContext: "/B",
				storedSchema,
				taggedValues: {
					target: { kind: "handle", value: marker },
				},
			});
			} finally {
				await live.service.close();
			}
		};
	});

	it("captures live channel attachment", async () => {
		const raw = { messages: [] as RawRecord[], serialization: [] as RawRecord[], summaries: [] as RawRecord[] };
		const scenarios: LifecycleScenario[] = [
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
		const { service, container, messages, resolvedUrl, initial, writer } = await attachedGraph();
		let receiver: Awaited<ReturnType<typeof openGraphContainer>> | undefined;
		try {
			const tree = await container.data.createTree();
			const view = newRoot(tree);
			container.data.root.set("tree", tree.handle);
			await service.synchronize();
			const commands: unknown[] = [
				{
					type: "create-channel",
					datastoreId: "A",
					channelId: pathOf(tree.handle).split("/")[2],
					channelType: "https://graph.microsoft.com/types/tree",
				},
				{
					type: "initialize-tree",
					target: pathOf(tree.handle),
					storedSchema: graphStoredSchema(),
					initialValue: graphInitialRoot("root"),
				},
				{
					type: "map-set",
					target: "/A/root",
					key: "tree",
					value: graphHandle(pathOf(tree.handle)),
				},
				{ type: "settle", checkpoint: "initial-tree" },
			];
			receiver = await openGraphContainer(service, container.id);
			const receiverTree = await (receiver.data.root.get("tree") as IFluidHandle).get() as ITree;
			const receiverView = existingRoot(receiverTree);
			messages.length = 0;

			const map = await container.data.createMap();
			map.set("local", "map-edit");
			view.root.link = map.handle;
			await service.synchronize();
			commands.push(
				{
					type: "create-channel",
					datastoreId: "A",
					channelId: pathOf(map.handle).split("/")[2],
					channelType: mapType(map),
				},
				{
					type: "map-set",
					target: pathOf(map.handle),
					key: "local",
					value: { kind: "string", value: "map-edit" },
				},
				{
					type: "tree-set-handle",
					target: pathOf(tree.handle),
					field: { kind: "optional", name: "link" },
					value: graphHandle(pathOf(map.handle)),
				},
				{ type: "settle", checkpoint: "detached-map" },
			);
			const detachedMapMessages = messages.splice(0);
			const receiverMap = await (receiverView.root.link as IFluidHandle).get() as ISharedMap;
			const detachedMapReceiver = {
				clientId: graphClientId(receiver.container),
				targets: [treeReceiverTarget(receiverTree, receiverView), mapReceiverTarget(receiverMap)],
				graph: {
					source: pathOf(receiverTree.handle),
					edge: "link",
					target: pathOf(receiverMap.handle),
					targetData: mapValue(receiverMap),
				},
			};
			const detachedMapScenario = scenarios.find((item) => item.id === "detached-map")!;
			const detachedMapLast = detachedMapMessages.at(-1)!.sequenceNumber;
			detachedMapScenario.commands = copy(commands);
			detachedMapScenario.replay = {
				published: false,
				prefixEndSequenceNumber: detachedMapLast,
			};
			observations.push({
				id: "detached-map",
				value: {
					path: pathOf(map.handle),
					local: map.get("local"),
					transportOrder: messageOrder(detachedMapMessages),
					receiver: detachedMapReceiver,
				},
				evidence: [
					record("messages", raw, "detached-map", "attach", detachedMapMessages),
					record("serialization", raw, "detached-map", "receiver-graph", detachedMapReceiver),
				],
			});

			const targetTree = await container.data.createTree();
			const targetView = newRoot(targetTree);
			targetView.root.label = "detached-tree-edit";
			view.root.links.set("tree", targetTree.handle);
			await service.synchronize();
			commands.push(
				{
					type: "create-channel",
					datastoreId: "A",
					channelId: pathOf(targetTree.handle).split("/")[2],
					channelType: "https://graph.microsoft.com/types/tree",
				},
				{
					type: "initialize-tree",
					target: pathOf(targetTree.handle),
					storedSchema: graphStoredSchema(),
					initialValue: graphInitialRoot("root"),
				},
				{
					type: "tree-set-string",
					target: pathOf(targetTree.handle),
					field: "label",
					value: "detached-tree-edit",
				},
				{
					type: "tree-map-set-handle",
					target: pathOf(tree.handle),
					field: "links",
					key: "tree",
					value: graphHandle(pathOf(targetTree.handle)),
				},
				{ type: "settle", checkpoint: "detached-tree" },
			);
			const detachedTreeMessages = messages.splice(0);
			const receivedTargetTree = await (receiverView.root.links.get("tree") as IFluidHandle)
				.get() as ITree;
			const receivedTargetView = existingRoot(receivedTargetTree);
			const detachedTreeReceiver = {
				clientId: graphClientId(receiver.container),
				targets: [
					treeReceiverTarget(receiverTree, receiverView),
					treeReceiverTarget(receivedTargetTree, receivedTargetView),
				],
				graph: {
					source: pathOf(receiverTree.handle),
					edge: "links/tree",
					target: pathOf(receivedTargetTree.handle),
					targetData: visible(receivedTargetView.root),
				},
			};
			const detachedTreeScenario = scenarios.find((item) => item.id === "detached-tree")!;
			detachedTreeScenario.commands = copy(commands);
			detachedTreeScenario.replay = {
				published: false,
				prefixEndSequenceNumber: detachedTreeMessages.at(-1)!.sequenceNumber,
			};
			observations.push({
				id: "detached-tree",
				value: {
					path: pathOf(targetTree.handle),
					label: targetView.root.label,
					transportOrder: messageOrder(detachedTreeMessages),
					receiver: detachedTreeReceiver,
				},
				evidence: [
					record("messages", raw, "detached-tree", "attach", detachedTreeMessages),
					record("serialization", raw, "detached-tree", "receiver-graph",
						detachedTreeReceiver),
				],
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
			commands.push(
				{
					type: "create-channel",
					datastoreId: "A",
					channelId: pathOf(removed.handle).split("/")[2],
					channelType: mapType(removed),
				},
				{
					type: "create-channel",
					datastoreId: "A",
					channelId: pathOf(removedOwner.handle).split("/")[2],
					channelType: mapType(removedOwner),
				},
				{
					type: "map-set",
					target: pathOf(removedOwner.handle),
					key: "removed",
					value: graphHandle(pathOf(removed.handle)),
				},
				{ type: "serialize-channel-summary", target: pathOf(removedOwner.handle) },
				{ type: "map-delete", target: pathOf(removedOwner.handle), key: "removed" },
				{
					type: "tree-map-set-handle",
					target: pathOf(tree.handle),
					field: "links",
					key: "removed-owner",
					value: graphHandle(pathOf(removedOwner.handle)),
				},
				{ type: "settle", checkpoint: "serialize-remove" },
			);
			const removedMessages = messages.splice(0);
			const receivedOwner = await (receiverView.root.links.get("removed-owner") as IFluidHandle)
				.get() as ISharedMap;
			const receivedRemoved = await resolveGraphTarget(
				receiver.data.root, pathOf(removed.handle),
			) as ISharedMap;
			const removedReceiver = {
				clientId: graphClientId(receiver.container),
				targets: [mapReceiverTarget(receivedOwner), mapReceiverTarget(receivedRemoved)],
				graph: {
					source: pathOf(receivedOwner.handle),
					edge: "removed",
					visible: receivedOwner.has("removed"),
					boundTarget: pathOf(receivedRemoved.handle),
				},
			};
			const removedScenario = scenarios.find((item) => item.id === "serialize-remove")!;
			removedScenario.commands = copy(commands);
			removedScenario.replay = {
				published: false,
				prefixEndSequenceNumber: removedMessages.at(-1)!.sequenceNumber,
			};
			observations.push({
				id: "serialize-remove",
				value: {
					ownerPath: pathOf(removedOwner.handle),
					targetPath: pathOf(removed.handle),
					attached: isAttached(removed),
					visibleValue: removedOwner.has("removed"),
					transportOrder: messageOrder(removedMessages),
					receiver: removedReceiver,
				},
				evidence: [
					bindingEvidence,
					record("messages", raw, "serialize-remove", "attach-then-remove", removedMessages),
					record("serialization", raw, "serialize-remove", "receiver-graph",
						removedReceiver),
				],
			});

			const outer = await container.data.createMap();
			const inner = await container.data.createMap();
			inner.set("value", "nested");
			outer.set("inner", inner.handle);
			view.root.links.set("nested", outer.handle);
			await service.synchronize();
			commands.push(
				{
					type: "create-channel",
					datastoreId: "A",
					channelId: pathOf(outer.handle).split("/")[2],
					channelType: mapType(outer),
				},
				{
					type: "create-channel",
					datastoreId: "A",
					channelId: pathOf(inner.handle).split("/")[2],
					channelType: mapType(inner),
				},
				{
					type: "map-set",
					target: pathOf(inner.handle),
					key: "value",
					value: { kind: "string", value: "nested" },
				},
				{
					type: "map-set",
					target: pathOf(outer.handle),
					key: "inner",
					value: graphHandle(pathOf(inner.handle)),
				},
				{
					type: "tree-map-set-handle",
					target: pathOf(tree.handle),
					field: "links",
					key: "nested",
					value: graphHandle(pathOf(outer.handle)),
				},
				{ type: "settle", checkpoint: "nested-dependency" },
			);
			const nestedMessages = messages.splice(0);
			const receivedOuter = await (receiverView.root.links.get("nested") as IFluidHandle)
				.get() as ISharedMap;
			const receivedInner = await (receivedOuter.get("inner") as IFluidHandle)
				.get() as ISharedMap;
			const nestedReceiver = {
				clientId: graphClientId(receiver.container),
				targets: [mapReceiverTarget(receivedOuter), mapReceiverTarget(receivedInner)],
				graph: {
					source: pathOf(receivedOuter.handle),
					edge: "inner",
					target: pathOf(receivedInner.handle),
					targetData: mapValue(receivedInner),
				},
			};
			const nestedScenario = scenarios.find((item) => item.id === "nested-dependency")!;
			nestedScenario.commands = copy(commands);
			nestedScenario.replay = {
				published: false,
				prefixEndSequenceNumber: nestedMessages.at(-1)!.sequenceNumber,
			};
			observations.push({
				id: "nested-dependency",
				value: {
					outer: pathOf(outer.handle),
					inner: pathOf(inner.handle),
					transportOrder: messageOrder(nestedMessages),
					receiver: nestedReceiver,
				},
				evidence: [
					record("messages", raw, "nested-dependency", "attach", nestedMessages),
					record("serialization", raw, "nested-dependency", "receiver-graph",
						nestedReceiver),
				],
			});

			const self = await container.data.createMap();
			self.set("self", self.handle);
			view.root.links.set("self", self.handle);
			await service.synchronize();
			commands.push(
				{
					type: "create-channel",
					datastoreId: "A",
					channelId: pathOf(self.handle).split("/")[2],
					channelType: mapType(self),
				},
				{
					type: "map-set",
					target: pathOf(self.handle),
					key: "self",
					value: graphHandle(pathOf(self.handle)),
				},
				{
					type: "tree-map-set-handle",
					target: pathOf(tree.handle),
					field: "links",
					key: "self",
					value: graphHandle(pathOf(self.handle)),
				},
				{ type: "settle", checkpoint: "self-reference" },
			);
			const selfMessages = messages.splice(0);
			const receivedSelf = await (receiverView.root.links.get("self") as IFluidHandle)
				.get() as ISharedMap;
			const receivedSelfAgain = await (receivedSelf.get("self") as IFluidHandle)
				.get() as ISharedMap;
			const selfReceiver = {
				clientId: graphClientId(receiver.container),
				targets: [mapReceiverTarget(receivedSelf)],
				graph: {
					source: pathOf(receivedSelf.handle),
					edge: "self",
					target: pathOf(receivedSelfAgain.handle),
					resolvesToSource: receivedSelfAgain === receivedSelf,
				},
			};
			const selfScenario = scenarios.find((item) => item.id === "self-reference")!;
			selfScenario.commands = copy(commands);
			selfScenario.replay = {
				published: false,
				prefixEndSequenceNumber: selfMessages.at(-1)!.sequenceNumber,
			};
			observations.push({
				id: "self-reference",
				value: {
					path: pathOf(self.handle),
					resolved: pathOf(self.get("self") as IFluidHandle),
					transportOrder: messageOrder(selfMessages),
					receiver: selfReceiver,
				},
				evidence: [
					record("messages", raw, "self-reference", "attach", selfMessages),
					record("serialization", raw, "self-reference", "receiver-graph", selfReceiver),
				],
			});

			const left = await container.data.createMap();
			const right = await container.data.createMap();
			left.set("right", right.handle);
			right.set("left", left.handle);
			view.root.links.set("cycle", left.handle);
			await service.synchronize();
			commands.push(
				{
					type: "create-channel",
					datastoreId: "A",
					channelId: pathOf(left.handle).split("/")[2],
					channelType: mapType(left),
				},
				{
					type: "create-channel",
					datastoreId: "A",
					channelId: pathOf(right.handle).split("/")[2],
					channelType: mapType(right),
				},
				{
					type: "map-set",
					target: pathOf(left.handle),
					key: "right",
					value: graphHandle(pathOf(right.handle)),
				},
				{
					type: "map-set",
					target: pathOf(right.handle),
					key: "left",
					value: graphHandle(pathOf(left.handle)),
				},
				{
					type: "tree-map-set-handle",
					target: pathOf(tree.handle),
					field: "links",
					key: "cycle",
					value: graphHandle(pathOf(left.handle)),
				},
				{ type: "settle", checkpoint: "two-channel-cycle" },
			);
			const cycleMessages = messages.splice(0);
			const receivedLeft = await (receiverView.root.links.get("cycle") as IFluidHandle)
				.get() as ISharedMap;
			const receivedRight = await (receivedLeft.get("right") as IFluidHandle)
				.get() as ISharedMap;
			const receivedLeftAgain = await (receivedRight.get("left") as IFluidHandle)
				.get() as ISharedMap;
			const cycleReceiver = {
				clientId: graphClientId(receiver.container),
				targets: [mapReceiverTarget(receivedLeft), mapReceiverTarget(receivedRight)],
				graph: {
					source: pathOf(receivedLeft.handle),
					edge: "right",
					target: pathOf(receivedRight.handle),
					returnEdge: "left",
					returnTarget: pathOf(receivedLeftAgain.handle),
					resolvesToSource: receivedLeftAgain === receivedLeft,
				},
			};
			const cycleScenario = scenarios.find((item) => item.id === "two-channel-cycle")!;
			cycleScenario.commands = copy(commands);
			cycleScenario.replay = {
				published: false,
				prefixEndSequenceNumber: cycleMessages.at(-1)!.sequenceNumber,
			};
			observations.push({
				id: "two-channel-cycle",
				value: {
					left: pathOf(left.handle),
					right: pathOf(right.handle),
					transportOrder: messageOrder(cycleMessages),
					receiver: cycleReceiver,
				},
				evidence: [
					record("messages", raw, "two-channel-cycle", "attach", cycleMessages),
					record("serialization", raw, "two-channel-cycle", "receiver-graph",
						cycleReceiver),
				],
			});

			const completed = await container.data.createTree();
			const completedView = newRoot(completed);
			Tree.runTransaction(completedView, () => {
				completedView.root.label = "committed";
			});
			view.root.links.set("completed", completed.handle);
			await service.synchronize();
			commands.push(
				{
					type: "create-channel",
					datastoreId: "A",
					channelId: pathOf(completed.handle).split("/")[2],
					channelType: "https://graph.microsoft.com/types/tree",
				},
				{
					type: "initialize-tree",
					target: pathOf(completed.handle),
					storedSchema: graphStoredSchema(),
					initialValue: graphInitialRoot("root"),
				},
				{ type: "begin-transaction", target: pathOf(completed.handle) },
				{
					type: "tree-set-string",
					target: pathOf(completed.handle),
					field: "label",
					value: "committed",
				},
				{ type: "commit-transaction", target: pathOf(completed.handle) },
				{
					type: "tree-map-set-handle",
					target: pathOf(tree.handle),
					field: "links",
					key: "completed",
					value: graphHandle(pathOf(completed.handle)),
				},
				{ type: "settle", checkpoint: "completed-transaction" },
			);
			const completedMessages = messages.splice(0);
			const receivedCompleted = await (receiverView.root.links.get("completed") as IFluidHandle)
				.get() as ITree;
			const receivedCompletedView = existingRoot(receivedCompleted);
			const completedReceiver = {
				clientId: graphClientId(receiver.container),
				targets: [treeReceiverTarget(receivedCompleted, receivedCompletedView)],
				graph: {
					source: pathOf(receiverTree.handle),
					edge: "links/completed",
					target: pathOf(receivedCompleted.handle),
					targetData: visible(receivedCompletedView.root),
				},
			};
			const completedScenario = scenarios.find((item) =>
				item.id === "completed-transaction")!;
			completedScenario.commands = copy(commands);
			completedScenario.replay = {
				published: false,
				prefixEndSequenceNumber: completedMessages.at(-1)!.sequenceNumber,
			};
			observations.push({
				id: "completed-transaction",
				value: {
					path: pathOf(completed.handle),
					label: completedView.root.label,
					attached: isAttached(completed),
					transportOrder: messageOrder(completedMessages),
					receiver: completedReceiver,
				},
				evidence: [
					record("messages", raw, "completed-transaction", "attach", completedMessages),
					record("serialization", raw, "completed-transaction", "receiver-graph",
						completedReceiver),
				],
			});

			record("serialization", raw, "two-channel-cycle", "map-summary", summaryBlobText((await summarize(left)).summary));
			record("summaries", raw, "detached-tree", "tree-summary", (await summarize(targetTree)).summary);
			const allMessages = await graphMessages(service, resolvedUrl);
			const finalSequenceNumber = completedMessages.at(-1)!.sequenceNumber;
			const deliveryPrefix = graphPrefix(initial.snapshot, allMessages, finalSequenceNumber);
			for (const scenario of scenarios.filter((item) => item.id !== "active-transaction")) {
				const replay = scenario.replay as GraphReplayCheckpoint;
				replay.deliveryPrefixLength = replay.prefixEndSequenceNumber
					- initial.snapshot.sequenceNumber;
			}
			deferredLiveAttachment = {
				scenarios,
				observations,
				raw,
				input: {
					decoderInput: {
						documentId: container.id,
						initialSnapshot: initial.snapshot,
						compressor: initial.compressor,
						deliveryPrefix,
						runtime: {
							oldestSupportedClient,
							enableRuntimeIdCompressor: "on",
							graphStoreType: GraphStore.type,
							registry: [
								{ channelType: mapType(container.data.root), role: "entry-point" },
								{
									channelType: "https://graph.microsoft.com/types/tree",
									role: "declared",
								},
							],
							entryPoint: {
								datastoreId: "A",
								channelId: "root",
								packagePath: [GraphStore.type],
							},
						},
						sessions: {
							writerClientId: graphClientId(container),
							receiverClientId: graphClientId(receiver.container),
							writer,
						},
					},
				},
			};
		} finally {
			receiver?.container.dispose();
			await service.close();
		}
	});

	it("captures cross-datastore attachment", async () => {
		const raw = { messages: [] as RawRecord[], serialization: [] as RawRecord[], summaries: [] as RawRecord[] };
		const scenarios: LifecycleScenario[] = [
			{ id: "map-cross-datastore", operation: "reference a map in a secondary datastore" },
			{ id: "map-cycle", operation: "create mutual map references across datastores" },
			{ id: "tree-cross-datastore", operation: "reference a tree in a secondary datastore" },
			{ id: "tree-cycle", operation: "create mutual tree references across datastores" },
		];
		const observations: Observation[] = [];
		const { service, container, messages, resolvedUrl, initial, writer } = await attachedGraph();
		let receiver: Awaited<ReturnType<typeof openGraphContainer>> | undefined;
		try {
			const commands: unknown[] = [];
			receiver = await openGraphContainer(service, container.id);
			await service.synchronize();
			messages.length = 0;

			const secondary = await container.createDataStore(GraphStore);
			container.data.root.set("secondary", secondary.root.handle);
			await service.synchronize();
			const crossMessages = messages.splice(0);
			const secondaryId = pathOf(secondary.root.handle).split("/")[1];
			commands.push(
				{
					type: "create-datastore",
					datastoreId: secondaryId,
					storeType: GraphStore.type,
					packagePath: [GraphStore.type],
					entryPointChannelId: "root",
					channels: [{ id: "root", type: mapType(secondary.root) }],
				},
				{
					type: "map-set",
					target: "/A/root",
					key: "secondary",
					value: graphHandle(pathOf(secondary.root.handle)),
				},
				{ type: "settle", checkpoint: "map-cross-datastore" },
			);
			const receivedSecondary = await (receiver.data.root.get("secondary") as IFluidHandle)
				.get() as ISharedMap;
			const mapCrossReceiver = {
				clientId: graphClientId(receiver.container),
				targets: [
					mapReceiverTarget(receiver.data.root),
					mapReceiverTarget(receivedSecondary),
				],
				graph: {
					source: pathOf(receiver.data.root.handle),
					edge: "secondary",
					target: pathOf(receivedSecondary.handle),
					targetData: mapValue(receivedSecondary),
				},
			};
			const mapCrossScenario = scenarios.find((item) =>
				item.id === "map-cross-datastore")!;
			mapCrossScenario.commands = copy(commands);
			mapCrossScenario.replay = {
				published: false,
				prefixEndSequenceNumber: crossMessages.at(-1)!.sequenceNumber,
			};
			observations.push({
				id: "map-cross-datastore",
				value: {
					primary: pathOf(container.data.root.handle),
					secondary: pathOf(secondary.root.handle),
					entryPoint: "root",
					attachOrder: messageOrder(crossMessages),
					receiver: mapCrossReceiver,
				},
				evidence: [
					record("messages", raw, "map-cross-datastore", "attach", crossMessages),
					record("serialization", raw, "map-cross-datastore", "receiver-graph",
						mapCrossReceiver),
				],
			});

			const leftStore = await container.createDataStore(GraphStore);
			const rightStore = await container.createDataStore(GraphStore);
			leftStore.root.set("right", rightStore.root.handle);
			rightStore.root.set("left", leftStore.root.handle);
			container.data.root.set("cycle", leftStore.root.handle);
			await service.synchronize();
			const mapCycleMessages = messages.splice(0);
			const leftStoreId = pathOf(leftStore.root.handle).split("/")[1];
			const rightStoreId = pathOf(rightStore.root.handle).split("/")[1];
			for (const [datastoreId, root] of [
				[leftStoreId, leftStore.root],
				[rightStoreId, rightStore.root],
			] as const) {
				commands.push({
					type: "create-datastore",
					datastoreId,
					storeType: GraphStore.type,
					packagePath: [GraphStore.type],
					entryPointChannelId: "root",
					channels: [{ id: "root", type: mapType(root) }],
				});
			}
			commands.push(
				{
					type: "map-set",
					target: pathOf(leftStore.root.handle),
					key: "right",
					value: graphHandle(pathOf(rightStore.root.handle)),
				},
				{
					type: "map-set",
					target: pathOf(rightStore.root.handle),
					key: "left",
					value: graphHandle(pathOf(leftStore.root.handle)),
				},
				{
					type: "map-set",
					target: "/A/root",
					key: "cycle",
					value: graphHandle(pathOf(leftStore.root.handle)),
				},
				{ type: "settle", checkpoint: "map-cycle" },
			);
			const receivedLeftStore = await (receiver.data.root.get("cycle") as IFluidHandle)
				.get() as ISharedMap;
			const receivedRightStore = await (receivedLeftStore.get("right") as IFluidHandle)
				.get() as ISharedMap;
			const receivedLeftStoreAgain = await (
				receivedRightStore.get("left") as IFluidHandle
			).get() as ISharedMap;
			const mapCycleReceiver = {
				clientId: graphClientId(receiver.container),
				targets: [
					mapReceiverTarget(receivedLeftStore),
					mapReceiverTarget(receivedRightStore),
				],
				graph: {
					source: pathOf(receivedLeftStore.handle),
					edge: "right",
					target: pathOf(receivedRightStore.handle),
					returnEdge: "left",
					returnTarget: pathOf(receivedLeftStoreAgain.handle),
					resolvesToSource: receivedLeftStoreAgain === receivedLeftStore,
				},
			};
			const mapCycleScenario = scenarios.find((item) => item.id === "map-cycle")!;
			mapCycleScenario.commands = copy(commands);
			mapCycleScenario.replay = {
				published: false,
				prefixEndSequenceNumber: mapCycleMessages.at(-1)!.sequenceNumber,
			};
			observations.push({
				id: "map-cycle",
				value: {
					left: pathOf(leftStore.root.handle),
					right: pathOf(rightStore.root.handle),
					attachOrder: messageOrder(mapCycleMessages),
					receiver: mapCycleReceiver,
				},
				evidence: [
					record("messages", raw, "map-cycle", "attach", mapCycleMessages),
					record("serialization", raw, "map-cycle", "receiver-graph",
						mapCycleReceiver),
				],
			});

			const primaryTree = await container.data.createTree();
			const primaryView = newRoot(primaryTree);
			container.data.root.set("primaryTree", primaryTree.handle);
			await service.synchronize();
			commands.push(
				{
					type: "create-channel",
					datastoreId: "A",
					channelId: pathOf(primaryTree.handle).split("/")[2],
					channelType: "https://graph.microsoft.com/types/tree",
				},
				{
					type: "initialize-tree",
					target: pathOf(primaryTree.handle),
					storedSchema: graphStoredSchema(),
					initialValue: graphInitialRoot("root"),
				},
				{
					type: "map-set",
					target: "/A/root",
					key: "primaryTree",
					value: graphHandle(pathOf(primaryTree.handle)),
				},
				{ type: "settle", checkpoint: "initial-tree" },
			);
			const receiverPrimaryTree = await (receiver.data.root.get("primaryTree") as IFluidHandle)
				.get() as ITree;
			const receiverPrimaryView = existingRoot(receiverPrimaryTree);

			const secondaryTree = await secondary.createTree();
			const secondaryView = newRoot(secondaryTree);
			secondaryView.root.label = "secondary";
			secondary.root.set("tree", secondaryTree.handle);
			primaryView.root.link = secondaryTree.handle;
			await service.synchronize();
			const treeCrossMessages = messages.splice(0);
			commands.push(
				{
					type: "create-channel",
					datastoreId: secondaryId,
					channelId: pathOf(secondaryTree.handle).split("/")[2],
					channelType: "https://graph.microsoft.com/types/tree",
				},
				{
					type: "initialize-tree",
					target: pathOf(secondaryTree.handle),
					storedSchema: graphStoredSchema(),
					initialValue: graphInitialRoot("root"),
				},
				{
					type: "tree-set-string",
					target: pathOf(secondaryTree.handle),
					field: "label",
					value: "secondary",
				},
				{
					type: "map-set",
					target: pathOf(secondary.root.handle),
					key: "tree",
					value: graphHandle(pathOf(secondaryTree.handle)),
				},
				{
					type: "tree-set-handle",
					target: pathOf(primaryTree.handle),
					field: { kind: "optional", name: "link" },
					value: graphHandle(pathOf(secondaryTree.handle)),
				},
				{ type: "settle", checkpoint: "tree-cross-datastore" },
			);
			const receivedSecondaryTree = await (receiverPrimaryView.root.link as IFluidHandle)
				.get() as ITree;
			const receivedSecondaryView = existingRoot(receivedSecondaryTree);
			const receivedSecondaryFromMap = await (
				receivedSecondary.get("tree") as IFluidHandle
			).get() as ITree;
			const treeCrossReceiver = {
				clientId: graphClientId(receiver.container),
				targets: [
					treeReceiverTarget(receiverPrimaryTree, receiverPrimaryView),
					treeReceiverTarget(receivedSecondaryTree, receivedSecondaryView),
				],
				graph: {
					source: pathOf(receiverPrimaryTree.handle),
					edge: "link",
					target: pathOf(receivedSecondaryTree.handle),
					secondaryEntryPoint: pathOf(receivedSecondary.handle),
					entryPointEdge: "tree",
					entryPointTarget: pathOf(receivedSecondaryFromMap.handle),
					sameResolvedInstance: receivedSecondaryFromMap === receivedSecondaryTree,
				},
			};
			const treeCrossScenario = scenarios.find((item) =>
				item.id === "tree-cross-datastore")!;
			treeCrossScenario.commands = copy(commands);
			treeCrossScenario.replay = {
				published: false,
				prefixEndSequenceNumber: treeCrossMessages.at(-1)!.sequenceNumber,
			};
			observations.push({
				id: "tree-cross-datastore",
				value: {
					path: pathOf(secondaryTree.handle),
					label: secondaryView.root.label,
					attachOrder: messageOrder(treeCrossMessages),
					receiver: treeCrossReceiver,
				},
				evidence: [
					record("messages", raw, "tree-cross-datastore", "attach",
						treeCrossMessages),
					record("serialization", raw, "tree-cross-datastore", "receiver-graph",
						treeCrossReceiver),
				],
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
			const leftTreeStoreId = pathOf(leftTreeStore.root.handle).split("/")[1];
			const rightTreeStoreId = pathOf(rightTreeStore.root.handle).split("/")[1];
			for (const [datastoreId, root] of [
				[leftTreeStoreId, leftTreeStore.root],
				[rightTreeStoreId, rightTreeStore.root],
			] as const) {
				commands.push({
					type: "create-datastore",
					datastoreId,
					storeType: GraphStore.type,
					packagePath: [GraphStore.type],
					entryPointChannelId: "root",
					channels: [
						{ id: "root", type: mapType(root) },
					],
				});
			}
			commands.push(
				{
					type: "create-channel",
					datastoreId: leftTreeStoreId,
					channelId: pathOf(leftTree.handle).split("/")[2],
					channelType: "https://graph.microsoft.com/types/tree",
				},
				{
					type: "create-channel",
					datastoreId: rightTreeStoreId,
					channelId: pathOf(rightTree.handle).split("/")[2],
					channelType: "https://graph.microsoft.com/types/tree",
				},
				{
					type: "initialize-tree",
					target: pathOf(leftTree.handle),
					storedSchema: graphStoredSchema(),
					initialValue: graphInitialRoot("root"),
				},
				{
					type: "initialize-tree",
					target: pathOf(rightTree.handle),
					storedSchema: graphStoredSchema(),
					initialValue: graphInitialRoot("root"),
				},
				{
					type: "tree-set-handle",
					target: pathOf(leftTree.handle),
					field: { kind: "optional", name: "link" },
					value: graphHandle(pathOf(rightTree.handle)),
				},
				{
					type: "tree-set-handle",
					target: pathOf(rightTree.handle),
					field: { kind: "optional", name: "link" },
					value: graphHandle(pathOf(leftTree.handle)),
				},
				{
					type: "tree-set-handle",
					target: pathOf(primaryTree.handle),
					field: { kind: "optional", name: "link" },
					value: graphHandle(pathOf(leftTree.handle)),
				},
				{ type: "settle", checkpoint: "tree-cycle" },
			);
			const receivedLeftTree = await (receiverPrimaryView.root.link as IFluidHandle)
				.get() as ITree;
			const receivedLeftTreeView = existingRoot(receivedLeftTree);
			const receivedRightTree = await (receivedLeftTreeView.root.link as IFluidHandle)
				.get() as ITree;
			const receivedRightTreeView = existingRoot(receivedRightTree);
			const receivedLeftTreeAgain = await (
				receivedRightTreeView.root.link as IFluidHandle
			).get() as ITree;
			const treeCycleReceiver = {
				clientId: graphClientId(receiver.container),
				targets: [
					treeReceiverTarget(receivedLeftTree, receivedLeftTreeView),
					treeReceiverTarget(receivedRightTree, receivedRightTreeView),
				],
				graph: {
					source: pathOf(receivedLeftTree.handle),
					edge: "link",
					target: pathOf(receivedRightTree.handle),
					returnEdge: "link",
					returnTarget: pathOf(receivedLeftTreeAgain.handle),
					resolvesToSource: receivedLeftTreeAgain === receivedLeftTree,
				},
			};
			const treeCycleSummary = record("summaries", raw, "tree-cycle", "cycle-trees", {
				left: { path: pathOf(leftTree.handle), summary: (await summarize(leftTree)).summary },
				right: { path: pathOf(rightTree.handle), summary: (await summarize(rightTree)).summary },
			});
			const treeCycleScenario = scenarios.find((item) => item.id === "tree-cycle")!;
			treeCycleScenario.commands = copy(commands);
			treeCycleScenario.replay = {
				published: false,
				prefixEndSequenceNumber: treeCycleMessages.at(-1)!.sequenceNumber,
			};
			observations.push({
				id: "tree-cycle",
				value: {
					left: pathOf(leftTree.handle),
					right: pathOf(rightTree.handle),
					attachOrder: messageOrder(treeCycleMessages),
					receiver: treeCycleReceiver,
				},
				evidence: [
					record("messages", raw, "tree-cycle", "attach", treeCycleMessages),
					treeCycleSummary,
					record("serialization", raw, "tree-cycle", "receiver-graph",
						treeCycleReceiver),
				],
			});
			record("serialization", raw, "map-cross-datastore", "paths", {
				primary: pathOf(container.data.root.handle),
				secondary: pathOf(secondary.root.handle),
			});
			const allMessages = await graphMessages(service, resolvedUrl);
			const finalSequenceNumber = treeCycleMessages.at(-1)!.sequenceNumber;
			const deliveryPrefix = graphPrefix(initial.snapshot, allMessages, finalSequenceNumber);
			for (const scenario of scenarios) {
				const replay = scenario.replay as GraphReplayCheckpoint;
				replay.deliveryPrefixLength = replay.prefixEndSequenceNumber
					- initial.snapshot.sequenceNumber;
			}
			await writeCase("cross-datastore-attachment", scenarios, observations, raw, {
				decoderInput: {
					documentId: container.id,
					initialSnapshot: initial.snapshot,
					compressor: initial.compressor,
					deliveryPrefix,
					runtime: {
						oldestSupportedClient,
						enableRuntimeIdCompressor: "on",
						graphStoreType: GraphStore.type,
						registry: [
							{ channelType: mapType(container.data.root), role: "entry-point" },
							{
								channelType: "https://graph.microsoft.com/types/tree",
								role: "declared",
							},
						],
						entryPoint: {
							datastoreId: "A",
							channelId: "root",
							packagePath: [GraphStore.type],
						},
					},
					sessions: {
						writerClientId: graphClientId(container),
						receiverClientId: graphClientId(receiver.container),
						writer,
					},
				},
			});
		} finally {
			receiver?.container.dispose();
			await service.close();
		}
	});

	it("captures transaction, branch, and undo side effects", async () => {
		const raw = { messages: [] as RawRecord[], serialization: [] as RawRecord[], summaries: [] as RawRecord[] };
		const scenarios: LifecycleScenario[] = [
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
		const graph = await attachedGraph();
		const { service, container, messages } = graph;
		let peer: Awaited<ReturnType<typeof openGraphContainer>> | undefined;
		try {
			const tree = await container.data.createTree();
			const view = newRoot(tree);
			container.data.root.set("tree", tree.handle);
			await service.synchronize();
			peer = await openGraphContainer(service, container.id);
			const peerTree = await (peer.data.root.get("tree") as IFluidHandle).get() as ITree;
			const peerView = existingRoot(peerTree);
			const history = historyCapture(graph, peer, tree, view, peerTree, peerView,
				scenarios, observations, raw);
			const setHandle = (target: ISharedMap, checkout?: string) => ({
				type: "tree-set-handle", target: pathOf(tree.handle),
				field: { kind: "optional", name: "link" },
				value: graphHandle(pathOf(target.handle)),
				...(checkout === undefined ? {} : { checkout }),
			});
			const stage = (target: ISharedMap) => ({
				tree: visible(view.root), target: pathOf(target.handle),
				attached: isAttached(target), compressor: graphWriter(container.data.root),
				transportLength: messages.length,
			});
			messages.length = 0;

			const success = await container.data.createMap();
			history.targets.push(success);
			const successStages: unknown[] = [];
			Tree.runTransaction(view, () => {
				view.root.link = success.handle;
				successStages.push(stage(success));
			});
			history.commands.push(createChannelCommand(success),
				{ type: "begin-transaction", target: pathOf(tree.handle) }, setHandle(success),
				{ type: "commit-transaction", target: pathOf(tree.handle) },
				{ type: "settle", checkpoint: "successful-transaction" });
			await service.synchronize();
			observations.push({
				id: "successful-transaction",
				value: {
					path: view.root.link === undefined ? undefined : pathOf(view.root.link),
					attached: isAttached(success),
				},
				evidence: [record("messages", raw, "successful-transaction", "attach", messages.splice(0))],
			});
			await history.checkpoint("successful-transaction", [], successStages);

			const aborted = await container.data.createMap();
			history.targets.push(aborted);
			const abortedStages: unknown[] = [stage(aborted)];
			const abortedResult = Tree.runTransaction(view, () => {
				view.root.link = aborted.handle;
				abortedStages.push(stage(aborted));
				return Tree.runTransaction.rollback;
			});
			abortedStages.push(stage(aborted));
			history.commands.push(createChannelCommand(aborted),
				{ type: "begin-transaction", target: pathOf(tree.handle) }, setHandle(aborted),
				{ type: "rollback-transaction", target: pathOf(tree.handle) },
				{ type: "settle", checkpoint: "aborted-transaction" });
			observations.push({
				id: "aborted-transaction",
				value: {
					result: abortedResult === Tree.runTransaction.rollback ? "rollback" : "commit",
					attached: isAttached(aborted),
					referringPath: view.root.link === undefined ? undefined : pathOf(view.root.link),
				},
				evidence: [record("messages", raw, "aborted-transaction", "checkpoint", messages.splice(0), "after-rollback")],
			});
			await history.checkpoint("aborted-transaction", [], abortedStages);

			const nested = await container.data.createMap();
			history.targets.push(nested);
			const nestedStages: unknown[] = [];
			Tree.runTransaction(view, () => {
				view.root.links.set("outer", nested.handle);
				nestedStages.push(stage(nested));
				Tree.runTransaction(view, () => {
					view.root.sequence.insertAtEnd(nested.handle);
					nestedStages.push(stage(nested));
				});
				nestedStages.push(stage(nested));
			});
			history.commands.push(createChannelCommand(nested),
				{ type: "begin-transaction", target: pathOf(tree.handle) },
				{
					type: "tree-map-set-handle", target: pathOf(tree.handle), field: "links",
					key: "outer", value: graphHandle(pathOf(nested.handle)),
				},
				{ type: "begin-transaction", target: pathOf(tree.handle) },
				{
					type: "tree-array-insert-handle", target: pathOf(tree.handle),
					field: "sequence", index: 0, value: graphHandle(pathOf(nested.handle)),
				},
				{ type: "commit-transaction", target: pathOf(tree.handle) },
				{ type: "commit-transaction", target: pathOf(tree.handle) },
				{ type: "settle", checkpoint: "nested-transaction" });
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
			await history.checkpoint("nested-transaction", [], nestedStages);

			const branchTarget = await container.data.createMap();
			history.targets.push(branchTarget);
			const branch = view.fork() as RootView;
			branch.root.link = branchTarget.handle;
			history.commands.push(createChannelCommand(branchTarget),
				{ type: "fork", target: pathOf(tree.handle), checkout: "working" },
				setHandle(branchTarget, "working"),
				{ type: "settle", checkpoint: "branch-before-merge" });
			observations.push({
				id: "branch-before-merge",
				value: {
					branchPath: branch.root.link === undefined ? undefined : pathOf(branch.root.link),
					mainPath: view.root.link === undefined ? undefined : pathOf(view.root.link),
					attached: isAttached(branchTarget),
				},
				evidence: [record("messages", raw, "branch-before-merge", "checkpoint", messages.splice(0), "before-merge")],
			});
			await history.checkpoint("branch-before-merge", [{ id: "working", disposed: false, view: branch }]);
			view.merge(branch);
			history.commands.push({ type: "merge", target: pathOf(tree.handle), checkout: "working" },
				{ type: "settle", checkpoint: "branch-after-merge" });
			await service.synchronize();
			observations.push({
				id: "branch-after-merge",
				value: { mainPath: view.root.link === undefined ? undefined : pathOf(view.root.link), attached: isAttached(branchTarget) },
				evidence: [record("messages", raw, "branch-after-merge", "attach", messages.splice(0))],
			});
			await history.checkpoint("branch-after-merge", [{ id: "working", disposed: true }]);

			const droppedTarget = await container.data.createMap();
			history.targets.push(droppedTarget);
			const dropped = view.fork() as RootView;
			dropped.root.link = droppedTarget.handle;
			dropped.dispose();
			history.commands.push(createChannelCommand(droppedTarget),
				{ type: "fork", target: pathOf(tree.handle), checkout: "dropped" },
				setHandle(droppedTarget, "dropped"),
				{ type: "dispose-checkout", target: pathOf(tree.handle), checkout: "dropped" },
				{ type: "settle", checkpoint: "branch-dropped" });
			observations.push({
				id: "branch-dropped",
				value: { mainPath: view.root.link === undefined ? undefined : pathOf(view.root.link), attached: isAttached(droppedTarget) },
				evidence: [record("messages", raw, "branch-dropped", "checkpoint", messages.splice(0), "after-drop")],
			});
			await history.checkpoint("branch-dropped", [{ id: "dropped", disposed: true }]);

			const disposedTarget = await container.data.createMap();
			history.targets.push(disposedTarget);
			const disposed = view.fork() as RootView;
			disposed.root.link = disposedTarget.handle;
			disposed.dispose();
			history.commands.push(createChannelCommand(disposedTarget),
				{ type: "fork", target: pathOf(tree.handle), checkout: "disposed" },
				setHandle(disposedTarget, "disposed"),
				{ type: "dispose-checkout", target: pathOf(tree.handle), checkout: "disposed" },
				{ type: "settle", checkpoint: "branch-disposal" });
			observations.push({
				id: "branch-disposal",
				value: { attached: isAttached(disposedTarget) },
				evidence: [record("messages", raw, "branch-disposal", "checkpoint", messages.splice(0), "after-disposal")],
			});
			await history.checkpoint("branch-disposal", [{ id: "disposed", disposed: true }]);

			const undoTarget = await container.data.createMap();
			history.targets.push(undoTarget);
			let revertible: RevertibleAlpha | undefined;
			const off = view.events.on("changed", (metadata, getRevertible) => {
				if (metadata.isLocal && getRevertible !== undefined && revertible === undefined) {
					revertible = getRevertible();
				}
			});
			view.root.link = undoTarget.handle;
			await service.synchronize();
			off();
			assert(peerView.root.link !== undefined);
			const peerTarget = await peerView.root.link.get() as ISharedMap;
			peerTarget.set("peer", "survives");
			await service.synchronize();
			assert(revertible !== undefined, "Handle insertion must produce a revertible");
			const beforeRevert = revertible.status;
			revertible.revert();
			await service.synchronize();
			const afterRevert = revertible.status;
			history.commands.push(createChannelCommand(undoTarget),
				{ type: "capture-next-revertible", target: pathOf(tree.handle), id: "insertion" },
				setHandle(undoTarget),
				{ type: "settle", checkpoint: "before-peer-edit" },
				{
					type: "map-set", client: "receiver", target: pathOf(undoTarget.handle),
					key: "peer", value: { kind: "string", value: "survives" },
				},
				{ type: "settle", checkpoint: "before-undo" },
				{ type: "revert", target: pathOf(tree.handle), id: "insertion", dispose: true },
				{ type: "settle", checkpoint: "handle-undo-peer-edit" });
			const undoSummary = record(
				"summaries", raw, "handle-undo-peer-edit", "tree-summary", (await summarize(tree)).summary,
			);
			observations.push({
				id: "handle-undo-peer-edit",
				value: {
					referringPath: view.root.link === undefined ? undefined : pathOf(view.root.link),
					targetPath: pathOf(undoTarget.handle),
					targetValue: undoTarget.get("peer"),
					revertibleStatus: { before: beforeRevert, after: afterRevert },
				},
				evidence: [
					record("messages", raw, "handle-undo-peer-edit", "undo", messages.splice(0)),
					undoSummary,
				],
			});
			const deliveryPrefix = await history.checkpoint("handle-undo-peer-edit");
			deferredTransactionBranch = {
				scenarios, observations, raw,
				input: { decoderInput: graphDecoderInput(container, graph.initial, graph.writer,
					peer.container, deliveryPrefix, history.receiverClientId) },
			};
		} finally {
			peer?.container.dispose();
			await service.close();
		}
	});

	it("captures summary and retained GC behavior", async () => {
		const raw = { messages: [] as RawRecord[], serialization: [] as RawRecord[], summaries: [] as RawRecord[] };
		const scenarios: LifecycleScenario[] = [
			{ id: "before-removal", operation: "summarize a visible handle" },
			{ id: "after-removal", operation: "summarize after removing the handle" },
			{ id: "after-undo", operation: "undo handle removal" },
			{ id: "retained-repair", operation: "retain removed content through a branch" },
			{ id: "branch-disposal", operation: "dispose the retaining branch" },
			{ id: "revertible-disposal", operation: "dispose the removal revertible" },
			{ id: "unreferenced-datastore", operation: "remove a secondary datastore reference" },
			{ id: "fresh-load", operation: "load the named published document, then continue editing" },
		];
		const observations: Observation[] = [];
		const graph = await attachedGraph();
		const { service, container, messages, resolvedUrl } = graph;
		let receiver: Awaited<ReturnType<typeof openGraphContainer>> | undefined;
		try {
			let history: ReturnType<typeof historyCapture>;
			const publishCheckpoint = async (scenarioId: string) => {
				await service.synchronize();
				history.commands.push({
					type: "publish-summary", id: scenarioId, fullTree: true,
					reason: `watershed ${scenarioId}`,
				});
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
			await service.synchronize();
			receiver = await openGraphContainer(service, container.id);
			const receiverTree = await (receiver.data.root.get("tree") as IFluidHandle).get() as ITree;
			const receiverView = existingRoot(receiverTree);
			history = historyCapture(graph, receiver, tree, view, receiverTree, receiverView,
				scenarios, observations, raw);
			const target = await container.data.createMap();
			history.targets.push(target);
			target.set("value", "before");
			view.root.link = target.handle;
			history.commands.push(createChannelCommand(target),
				{
					type: "map-set", target: pathOf(target.handle), key: "value",
					value: { kind: "string", value: "before" },
				},
				{
					type: "tree-set-handle", target: pathOf(tree.handle),
					field: { kind: "optional", name: "link" },
					value: graphHandle(pathOf(target.handle)),
				},
				{ type: "settle", checkpoint: "before-removal" });
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
			await history.checkpoint("before-removal");

			const retainedHandles: RevertibleAlpha[] = [];
			const off = view.events.on("changed", (metadata, getRevertible) => {
				if (metadata.isLocal && getRevertible !== undefined) {
					retainedHandles.push(getRevertible());
				}
			});
			view.root.link = undefined;
			history.commands.push(
				{ type: "subscribe-revertibles", target: pathOf(tree.handle), id: "retention" },
				{
					type: "tree-clear-handle", target: pathOf(tree.handle),
					field: { kind: "optional", name: "link" },
				},
				{ type: "settle", checkpoint: "after-removal" });
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
			await history.checkpoint("after-removal");

			const removal = retainedHandles[0];
			assert(removal !== undefined, "Handle removal must produce a revertible");
			removal.revert();
			history.commands.push(
				{ type: "revert", target: pathOf(tree.handle), id: "retention:0", dispose: true },
				{ type: "settle", checkpoint: "after-undo" });
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
			await history.checkpoint("after-undo");

			const retaining = view.fork() as RootView;
			view.root.link = undefined;
			history.commands.push(
				{ type: "fork", target: pathOf(tree.handle), checkout: "retaining" },
				{
					type: "tree-clear-handle", target: pathOf(tree.handle),
					field: { kind: "optional", name: "link" },
				},
				{ type: "settle", checkpoint: "retained-repair" });
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
			await history.checkpoint("retained-repair", [{ id: "retaining", disposed: false, view: retaining }]);
			retaining.dispose();
			history.commands.push({
				type: "dispose-checkout", target: pathOf(tree.handle), checkout: "retaining",
			});
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
			await history.checkpoint("branch-disposal", [{ id: "retaining", disposed: true }]);
			off();
			for (const handle of retainedHandles) {
				if (handle.status === RevertibleStatus.Valid) handle.dispose();
			}
			history.commands.push({ type: "dispose-revertibles", target: pathOf(tree.handle), id: "retention" });
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
			await history.checkpoint("revertible-disposal");

			const secondary = await container.createDataStore(GraphStore);
			history.targets.push(secondary.root);
			container.data.root.set("secondary", secondary.root.handle);
			await service.synchronize();
			container.data.root.delete("secondary");
			history.commands.push(
				{
					type: "create-datastore", datastoreId: pathOf(secondary.root.handle).split("/")[1],
					storeType: GraphStore.type, packagePath: [GraphStore.type],
					entryPointChannelId: "root",
					channels: [{ id: "root", type: SharedMapAlpha.getFactory().type }],
				},
				{
					type: "map-set", target: "/A/root", key: "secondary",
					value: graphHandle(pathOf(secondary.root.handle)),
				},
				{ type: "settle", checkpoint: "secondary-visible" },
				{ type: "map-delete", target: "/A/root", key: "secondary" },
				{ type: "settle", checkpoint: "unreferenced-datastore" });
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
			await history.checkpoint("unreferenced-datastore");

			view.root.link = target.handle;
			history.commands.push({
				type: "tree-set-handle", target: pathOf(tree.handle),
				field: { kind: "optional", name: "link" }, value: graphHandle(pathOf(target.handle)),
			}, { type: "settle", checkpoint: "before-fresh-publication" });
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
				history.commands.push(
					{
						type: "load-publication", client: "fresh", publicationId: "fresh-load",
						version: freshPublication.published.publication.handle,
					},
					{
						type: "map-set", client: "fresh", target: loadedTargetPath,
						key: "continued", value: { kind: "boolean", value: true },
					},
					{ type: "settle", checkpoint: "fresh-load" });
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
				await history.checkpoint("fresh-load");
			} finally {
				loaded.container.dispose();
			}
			const deliveryPrefix = graphPrefix(graph.initial.snapshot,
				await graphMessages(service, resolvedUrl),
				(scenarios.at(-1)!.replay as GraphReplayCheckpoint).prefixEndSequenceNumber);
			await writeCase("handle-retention", scenarios, observations, raw, {
				decoderInput: graphDecoderInput(container, graph.initial, graph.writer,
					receiver.container, deliveryPrefix, history.receiverClientId),
			});
		} finally {
			receiver?.container.dispose();
			await service.close();
		}
	});

	it("captures real active target publication attempts after stable case streams", async () => {
		for (const [id, scenarioId, deferred] of [
			["live-channel-attachment", "active-transaction", deferredLiveAttachment],
			["handle-transaction-branch", "active-target", deferredTransactionBranch],
		] as const) {
			assert(deferred !== undefined, `${id}: deferred case`);
			const { service, container, messages, resolvedUrl, initial, writer } = await attachedGraph();
			try {
				const tree = await container.data.createTree();
				const view = newRoot(tree);
				container.data.root.set("tree", tree.handle);
				await service.synchronize();
				messages.length = 0;
				const active = await activeDocumentAttachment(container, service, view, messages);
				const index = deferred.scenarios.findIndex((scenario) => scenario.id === scenarioId);
				assert(index >= 0, `${id}: active scenario`);
				{
					const prefixEndSequenceNumber = Math.max(...active.transport.map(
						(message) => (message as ISequencedDocumentMessage).sequenceNumber,
					));
					deferred.scenarios[index].input = {
						decoderInput: {
							documentId: container.id,
							initialSnapshot: initial.snapshot,
							compressor: initial.compressor,
							deliveryPrefix: graphPrefix(
								initial.snapshot, await graphMessages(service, resolvedUrl),
								prefixEndSequenceNumber,
							),
							sessions: { writerClientId: graphClientId(container), writer },
						},
					};
					deferred.scenarios[index].commands = [
						{
							type: "create-channel", datastoreId: "A",
							channelId: pathOf(tree.handle).split("/")[2],
							channelType: "https://graph.microsoft.com/types/tree",
						},
						{
							type: "initialize-tree", target: pathOf(tree.handle),
							storedSchema: graphStoredSchema(), initialValue: graphInitialRoot("root"),
						},
						{
							type: "map-set", target: "/A/root", key: "tree",
							value: graphHandle(pathOf(tree.handle)),
						},
						{ type: "settle", checkpoint: "initial-tree" },
						{
							type: "create-channel", datastoreId: "A",
							channelId: active.targetPath.split("/")[2],
							channelType: "https://graph.microsoft.com/types/tree",
						},
						{
							type: "initialize-tree", target: active.targetPath,
							storedSchema: graphStoredSchema(), initialValue: graphInitialRoot("root"),
						},
						{
							type: "tree-set-string", target: active.targetPath,
							field: "label", value: "active-target",
						},
						{ type: "begin-transaction", target: active.targetPath },
						{
							type: "tree-set-handle", target: pathOf(tree.handle),
							field: { kind: "optional", name: "link" },
							value: graphHandle(active.targetPath),
						},
					];
					deferred.scenarios[index].replay = {
						published: false,
						nativeBoundary: "preflight-refusal",
						prefixEndSequenceNumber,
						deliveryPrefixLength: prefixEndSequenceNumber - initial.snapshot.sequenceNumber,
					};
				}
				deferred.observations.splice(index, 0, {
					id: scenarioId,
					value: active,
					evidence: [record(
						"messages", deferred.raw, scenarioId,
						"document-attachment", active, "after-attempt",
					)],
				});
				await writeCase(
					id,
					deferred.scenarios,
					deferred.observations,
					deferred.raw,
					deferred.input,
				);
			} finally {
				await service.close();
			}
		}
		assert(deferredHandleLeaves !== undefined, "handle-leaves: deferred case");
		await deferredHandleLeaves();
	});
});
