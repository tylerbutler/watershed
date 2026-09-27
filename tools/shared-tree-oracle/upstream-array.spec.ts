/*!
 * Copyright (c) Microsoft Corporation and contributors. All rights reserved.
 * Licensed under the MIT License.
 */

import { strict as assert } from "node:assert";
import { mkdirSync, writeFileSync } from "node:fs";
import { isAbsolute, join } from "node:path";

import {
	createIdCompressor,
	createSessionId,
	deserializeIdCompressor,
	serializeIdCompressor,
	type SerializedIdCompressorWithNoSession,
	type SerializedIdCompressorWithOngoingSession,
	toIdCompressorWithCore,
} from "@fluidframework/id-compressor/internal";
import type {
	IIdCompressor,
	SessionId,
	SessionSpaceCompressedId,
} from "@fluidframework/id-compressor";
import { FlushMode } from "@fluidframework/runtime-definitions/internal";
import {
	MockDeltaConnection,
	MockFluidDataStoreRuntime,
	MockSharedObjectServices,
	MockStorage,
} from "@fluidframework/test-runtime-utils/internal";

import { FluidClientVersion, FormatValidatorNoOp } from "../codec/index.js";
import {
	tagChange,
	type GraphCommit,
	type JsonableTree,
	type RevisionTag,
	type TaggedChange,
} from "../core/index.js";
import {
	extractPersistedSchema,
	SchemaFactory,
	TreeViewConfiguration,
	type ImplicitFieldSchema,
	type TreeView,
} from "../simple-tree/index.js";
import {
	fieldBatchCodecBuilder,
	intoDelta,
	jsonableTreeFromFieldCursor,
	schemaCodecBuilder,
	TreeCompressionStrategy,
	type ModularChangeset,
} from "../feature-libraries/index.js";
import { Tree, type SharedTreeChange } from "../shared-tree/index.js";
import { configuredSharedTreeInternal } from "../treeFactory.js";
import {
	crossFieldCoordinationInput,
	encodeModularGraph,
	replayArrayModularInput,
	replayArrayModularInputRaw,
} from "./watershedArraySupport.js";
import {
	MockContainerRuntimeFactoryWithOpBunching,
	MockContainerRuntimeWithOpBunching,
} from "./mocksForOpBunching.js";
import {
	assertIsSessionId,
	makeTestFieldBatchContexts,
	TestTreeProviderLite,
} from "./utils.js";

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

type PlainRoot = ReturnType<typeof visible>;

type ReplayClient = {
	readonly id: string;
	readonly sessionId: string;
	readonly compressor: string;
};

type ReplayAction = {
	readonly id: string;
	readonly op: string;
	readonly name?: string;
	readonly client?: number;
	readonly path?: readonly string[];
	readonly sourcePath?: readonly string[];
	readonly index?: number;
	readonly start?: number;
	readonly end?: number;
	readonly gap?: number;
	readonly values?: readonly unknown[];
	readonly connected?: boolean;
	readonly reconnectId?: string;
	readonly edits?: readonly ReplayAction[];
};

type ReplayProvider = {
	readonly trees: readonly ReturnType<ReturnType<typeof treeFactory>["create"]>[];
	readonly views: readonly TreeView<typeof Root>[];
	readonly runtimes: readonly MockContainerRuntimeWithOpBunching[];
	readonly compressors: readonly IIdCompressor[];
	readonly processed: readonly unknown[][];
	readonly transportIds: Map<string, string>;
	synchronize(): void;
	sequenceNumber(): number;
	minimumSequenceNumber(): number;
};

const replayClients: readonly ReplayClient[] = [
	{
		id: "client-0",
		sessionId: "8f95be09-8376-4ff7-8755-ccd7e8124b06",
		compressor:
			"AAAAAAAAAEAAAAAAAADwPwAAAAAAAPA/AAAAAAAAAAAGSxLo18xVx/3bDSb4Vj4CAAAAAAAAAAAAAAAAAADwPwAAAAAAAAAA",
	},
	{
		id: "client-1",
		sessionId: "8cc9b139-f642-4f75-85f7-b5e5297cb6b3",
		compressor:
			"AAAAAAAAAEAAAAAAAADwPwAAAAAAAPA/AAAAAAAAAACztnwp5bX3Rd0L2efEJjMCAAAAAAAAAAAAAAAAAADwPwAAAAAAAAAA",
	},
];

function plainInitialRoot(): PlainRoot {
	return visible(initialRoot());
}

function hydrate(value: unknown): unknown {
	if (value === null || typeof value === "string" || typeof value === "number"
		|| typeof value === "boolean") {
		return value;
	}
	if (Array.isArray(value)) return new Items(value.map(hydrate) as never);
	assert(value !== null && typeof value === "object", "Tree content must be a plain value.");
	if ("point" in value) {
		const point = Reflect.get(value, "point");
		assert(point !== null && typeof point === "object", "Point content must be an object.");
		assert(typeof Reflect.get(point, "label") === "string", "Point label must be a string.");
		assert(typeof Reflect.get(point, "x") === "number", "Point x must be a number.");
		return new Point({
			label: Reflect.get(point, "label") as string,
			x: Reflect.get(point, "x") as number,
		});
	}
	if ("map" in value) {
		const entries = Reflect.get(value, "map");
		assert(Array.isArray(entries), "Map content must contain entries.");
		return new ArrayMap(entries.map((entry) => {
			assert(Array.isArray(entry) && entry.length === 2 && typeof entry[0] === "string",
				"Map content entry must contain a string key and value.");
			return [entry[0], hydrate(entry[1])];
		}) as never);
	}
	if ("left" in value && "right" in value && "byKey" in value && "narrow" in value) {
		const left = hydrate(Reflect.get(value, "left"));
		const right = hydrate(Reflect.get(value, "right"));
		const byKey = hydrate(Reflect.get(value, "byKey"));
		const narrow = Reflect.get(value, "narrow");
		assert(left instanceof Items && right instanceof Items && byKey instanceof ArrayMap
			&& Array.isArray(narrow), "Root content has the wrong shape.");
		return new Root({
			left,
			right,
			byKey,
			narrow: new Points(narrow.map((item) => {
				const point = hydrate(item);
				assert(point instanceof Point, "Points content must contain points.");
				return point;
			})),
		});
	}
	assert.fail("Unsupported tree content.");
}

function configurationFor(selector: unknown): TreeViewConfiguration {
	switch (selector) {
		case "rootArray":
		case "recursiveArrays":
			return new TreeViewConfiguration({ schema: Items });
		case "objectArrays":
			return new TreeViewConfiguration({ schema: Root });
		case "mapArrays":
			return new TreeViewConfiguration({ schema: ArrayMap });
		case "incompatibleArrays":
			return new TreeViewConfiguration({ schema: Points });
		default:
			assert.fail(`Unknown schema selector: ${String(selector)}`);
	}
}

function schemaFor(selector: unknown): ImplicitFieldSchema {
	switch (selector) {
		case "rootArray":
		case "recursiveArrays":
			return Items;
		case "objectArrays":
			return Root;
		case "mapArrays":
			return ArrayMap;
		case "incompatibleArrays":
			return Points;
		default:
			assert.fail(`Unknown schema selector: ${String(selector)}`);
	}
}

function contentFor(selector: unknown, value: unknown): Root | Items | Points | ArrayMap {
	if (selector === "incompatibleArrays") {
		assert(Array.isArray(value), "Points content must be an array.");
		return new Points(value.map((item) => {
			const point = hydrate(item);
			assert(point instanceof Point, "Points content must contain points.");
			return point;
		}));
	}
	const content = hydrate(value);
	if (selector === "objectArrays") {
		assert(content instanceof Root, "Object-array content must contain a Root.");
	} else if (selector === "mapArrays") {
		assert(content instanceof ArrayMap, "Map-array content must contain an ArrayMap.");
	} else {
		assert(content instanceof Items, "Root-array content must contain Items.");
	}
	return content;
}

function readPath(root: unknown, path: readonly string[]): unknown {
	let value = root;
	for (const segment of path) {
		if (value instanceof ArrayMap) {
			value = value.get(segment);
		} else if (value instanceof Items || value instanceof Points) {
			const index = Number(segment);
			assert(Number.isSafeInteger(index), `Array path segment must be an integer: ${segment}`);
			value = value[index];
		} else {
			assert(value !== null && typeof value === "object", `Cannot traverse ${segment}.`);
			value = Reflect.get(value, segment);
		}
	}
	return value;
}

function decodedTreeValue(tree: JsonableTree): unknown {
	const type = String(tree.type);
	if (type === "com.fluidframework.leaf.string") {
		assert(typeof tree.value === "string", "Decoded string leaf must contain a string.");
		return { kind: "string", value: tree.value };
	}
	if (type === "com.fluidframework.leaf.number") {
		assert(typeof tree.value === "number", "Decoded number leaf must contain a number.");
		return { kind: "number", value: tree.value };
	}
	if (type === "com.fluidframework.leaf.boolean") {
		assert(typeof tree.value === "boolean", "Decoded boolean leaf must contain a boolean.");
		return { kind: "boolean", value: tree.value };
	}
	if (type === "com.fluidframework.leaf.null") {
		assert(tree.value === null, "Decoded null leaf must contain null.");
		return { kind: "null" };
	}
	const fields = tree.fields ?? {};
	if (type === String(Items.identifier) || type === String(Points.identifier)) {
		return {
			kind: "array",
			schemaId: type,
			elements: (fields[""] ?? []).map(decodedTreeValue),
		};
	}
	if (type === String(ArrayMap.identifier)) {
		return {
			kind: "map",
			schemaId: type,
			entries: Object.entries(fields)
				.sort(([left], [right]) => left.localeCompare(right))
				.map(([key, children]) => {
					assert(children.length === 1, `Decoded map field ${key} must be optional.`);
					return [key, decodedTreeValue(children[0])];
				}),
		};
	}
	return {
		kind: "object",
		type,
		fields: Object.entries(fields)
			.sort(([left], [right]) => left.localeCompare(right))
			.map(([key, children]) => {
				assert(children.length === 1, `Decoded object field ${key} must contain one tree.`);
				return [key, decodedTreeValue(children[0])];
			}),
	};
}

function decodeSummaryContent(encoded: string): unknown {
	const forest = JSON.parse(encoded) as Record<string, unknown>;
	assert.deepEqual(forest.keys, ["rootFieldKey"], "Summary must contain the root field.");
	const codec = fieldBatchCodecBuilder.build({
		jsonValidator: FormatValidatorNoOp,
		minVersionForCollab: FluidClientVersion.v2_117,
	});
	const context = makeTestFieldBatchContexts({
		encodeType: TreeCompressionStrategy.Uncompressed,
	});
	const decoded = codec.decode(forest.fields as never, context.decode)
		.map(jsonableTreeFromFieldCursor);
	assert.equal(decoded.length, 1, "Summary must contain one detached field.");
	assert.equal(decoded[0].length, 1, "Summary root field must contain one tree.");
	return decodedTreeValue(decoded[0][0]);
}

export async function replayArraySchemaInput(input: Record<string, unknown>): Promise<unknown> {
	assert(typeof input.operation === "string", "Schema replay needs an operation.");
	assert(typeof input.schema === "string", "Schema replay needs a schema selector.");
	assert(typeof input.schemaBytes === "string", "Schema replay needs raw schema bytes.");
	assert.equal(
		schemaString(schemaFor(input.schema)),
		input.schemaBytes,
		"Schema replay bytes must match the selected schema.",
	);
	const provider = new TestTreeProviderLite(1, treeFactory());
	const view = provider.trees[0].viewWith(configurationFor(input.schema));
	if (input.operation === "canView") {
		assert(typeof input.viewSchema === "string", "Compatibility replay needs a view schema.");
		assert(typeof input.viewSchemaBytes === "string", "Compatibility replay needs view bytes.");
		assert.equal(
			schemaString(schemaFor(input.viewSchema)),
			input.viewSchemaBytes,
			"Compatibility view bytes must match the selected schema.",
		);
		view.initialize(contentFor(input.schema, input.initialState) as never);
		provider.synchronizeMessages();
		view.dispose();
		const requested = provider.trees[0].viewWith(configurationFor(input.viewSchema));
		return {
			storedSchema: input.schema,
			viewSchema: input.viewSchema,
			compatibility: copy(requested.compatibility),
			content: visible(requested.root),
		};
	}
	view.initialize(contentFor(input.schema, input.initialState) as never);
	provider.synchronizeMessages();
	switch (input.operation) {
		case "schema":
			return { schema: JSON.parse(input.schemaBytes), content: visible(view.root) };
		case "initialize":
			return { content: visible(view.root), compatibility: copy(view.compatibility) };
		case "read": {
			assert(Array.isArray(input.path), "Read replay needs a path.");
			const value = readPath(view.root, input.path as string[]);
			return { value: visible(value), container: visible(view.root) };
		}
		case "move": {
			assert(input.source !== null && typeof input.source === "object",
				"Move replay needs a source.");
			assert(input.destination !== null && typeof input.destination === "object",
				"Move replay needs a destination.");
			const source = input.source as { path: string[]; start: number; end: number };
			const destination = input.destination as { path: string[]; gap: number };
			const sourceArray = readPath(view.root, source.path);
			const destinationArray = readPath(view.root, destination.path);
			assert(sourceArray instanceof Items || sourceArray instanceof Points,
				"Move source must be an array.");
			assert(destinationArray instanceof Items || destinationArray instanceof Points,
				"Move destination must be an array.");
			return executed(() => {
				destinationArray.moveRangeToIndex(
					destination.gap,
					source.start,
					source.end,
					sourceArray as never,
				);
				return visible(view.root);
			});
		}
		case "summarize": {
			const summary = (await provider.trees[0].summarize(true)).summary;
			assert(typeof input.forestBytes === "string",
				"Summary replay needs source forest bytes.");
			const forest = summaryBlob(summary, "indexes", "Forest", "contents");
			assert.equal(forest, input.forestBytes,
				"Summary replay bytes must match the source summary.");
			return {
				schema: summaryBlob(summary, "indexes", "Schema", "SchemaString"),
				content: decodeSummaryContent(input.forestBytes),
			};
		}
		default:
			assert.fail(`Unknown schema replay operation: ${input.operation}`);
	}
}

function decodeOngoingCompressor(value: ReplayClient): IIdCompressor {
	const compressor = deserializeIdCompressor(
		value.compressor as SerializedIdCompressorWithOngoingSession,
	);
	assert.equal(compressor.localSessionId, value.sessionId, `${value.id}: compressor session`);
	return compressor;
}

function createReplayProvider(input: {
	readonly clients: readonly ReplayClient[];
	readonly initialState: unknown;
}): ReplayProvider {
	assert(input.clients.length >= 1, "History replay needs at least one client.");
	const runtimeFactory = new MockContainerRuntimeFactoryWithOpBunching({
		flushMode: FlushMode.Immediate,
	});
	const trees: ReturnType<ReturnType<typeof treeFactory>["create"]>[] = [];
	const views: TreeView<typeof Root>[] = [];
	const runtimes: MockContainerRuntimeWithOpBunching[] = [];
	const compressors: IIdCompressor[] = [];
	const processed: unknown[][] = [];
	const transportIds = new Map<string, string>();
	const factory = treeFactory();
	for (const [index, client] of input.clients.entries()) {
		const idCompressor = decodeOngoingCompressor(client);
		const runtime = new MockFluidDataStoreRuntime({
			clientId: client.id,
			id: `array-replay-${index}`,
			idCompressor,
		});
		const tree = factory.create(runtime, `array-replay-${index}`);
		const containerRuntime = runtimeFactory.createContainerRuntime(runtime);
		transportIds.set(containerRuntime.clientId, client.id);
		tree.connect({
			deltaConnection: runtime.createDeltaConnection(),
			objectStorage: new MockStorage(),
		});
		const messages: unknown[] = [];
		const process = containerRuntime.process.bind(containerRuntime);
		containerRuntime.process = (message) => {
			messages.push(copy(message));
			process(message);
		};
		const processMessages = containerRuntime.processMessages.bind(containerRuntime);
		containerRuntime.processMessages = (batch) => {
			messages.push(...copy(batch));
			processMessages(batch);
		};
		trees.push(tree);
		runtimes.push(containerRuntime);
		compressors.push(idCompressor);
		processed.push(messages);
	}
	const first = trees[0].viewWith(new TreeViewConfiguration({ schema: Root }));
	first.initialize(contentFor("objectArrays", input.initialState) as Root);
	for (const tree of trees) {
		runtimeFactory.processAllMessages();
		if (tree !== trees[0]) views.push(tree.viewWith(new TreeViewConfiguration({ schema: Root })));
	}
	views.unshift(first);
	for (const items of processed) items.length = 0;
	return {
		trees,
		views,
		runtimes,
		compressors,
		processed,
		transportIds,
		synchronize() {
			for (const runtime of runtimes) runtime.flush();
			runtimeFactory.processAllMessages();
		},
		sequenceNumber: () => runtimeFactory.sequenceNumber,
		minimumSequenceNumber: () => runtimeFactory.getMinSeq(),
	};
}

function arrayAt(root: Root, path: readonly string[]): Items | Points {
	const value = readPath(root, path);
	assert(value instanceof Items || value instanceof Points, "The action path must select an array.");
	return value;
}

function compressorState(compressor: IIdCompressor) {
	return {
		sessionId: compressor.localSessionId,
		serialized: serializeIdCompressor(compressor, true),
	};
}

function replayCheckpoint(provider: ReplayProvider, id: string, messageStarts: readonly number[]) {
	const normalizeTransportIds = (value: unknown): unknown => {
		if (typeof value === "string") return provider.transportIds.get(value) ?? value;
		if (Array.isArray(value)) return value.map(normalizeTransportIds);
		if (value !== null && typeof value === "object") {
			return Object.fromEntries(
				Object.entries(value).map(([key, item]) => [key, normalizeTransportIds(item)]),
			);
		}
		return value;
	};
	return {
		id,
		visible: provider.views.map((view) => visible(view.root)),
		history: provider.trees.map((tree) =>
			managerState(tree as TestTreeProviderLite["trees"][number])),
		sequenceNumber: provider.sequenceNumber(),
		minimumSequenceNumber: provider.minimumSequenceNumber(),
		compressors: provider.compressors.map(compressorState),
		messages: provider.processed.map((items, index) =>
			normalizeTransportIds(copy(items.slice(messageStarts[index])))),
	};
}

function runEdit(view: ReplayProvider["views"][number], action: ReplayAction): void {
	assert(Array.isArray(action.path), `${action.id}: edit path`);
	const target = arrayAt(view.root, action.path);
	switch (action.op) {
		case "insert": {
			assert(typeof action.index === "number" && Number.isSafeInteger(action.index),
				`${action.id}: insert index`);
			assert(Array.isArray(action.values), `${action.id}: insert values`);
			target.insertAt(action.index, ...action.values.map(hydrate) as never[]);
			return;
		}
		case "remove":
			assert(typeof action.start === "number" && Number.isSafeInteger(action.start)
				&& typeof action.end === "number" && Number.isSafeInteger(action.end),
				`${action.id}: remove range`);
			target.removeRange(action.start, action.end);
			return;
		case "move": {
			assert(typeof action.start === "number" && Number.isSafeInteger(action.start)
				&& typeof action.end === "number" && Number.isSafeInteger(action.end)
				&& typeof action.gap === "number" && Number.isSafeInteger(action.gap),
			`${action.id}: move range`);
			const sourcePath = Reflect.get(action, "sourcePath");
			assert(Array.isArray(sourcePath), `${action.id}: move source path`);
			const source = arrayAt(view.root, sourcePath);
			target.moveRangeToIndex(action.gap, action.start, action.end, source as never);
			return;
		}
		default:
			assert.fail(`${action.id}: unsupported edit ${action.op}`);
	}
}

function actionWithEvents(
	provider: ReplayProvider,
	action: ReplayAction,
	run: () => void,
): Record<string, unknown> {
	const client = action.client ?? 0;
	const view = provider.views[client];
	assert(view !== undefined, `${action.id}: unknown client`);
	let commits = 0;
	let changed = 0;
	let nodeEvents = 0;
	const offCommit = view.events.on("commitApplied", () => { commits += 1; });
	const checkout = Reflect.get(view, "checkout") as {
		events: { on(name: "changed", listener: () => void): () => void };
	};
	const offChanged = checkout.events.on("changed", () => { changed += 1; });
	const eventNode = Array.isArray(action.path) ? arrayAt(view.root, action.path) : view.root;
	const identities = eventNode instanceof Items || eventNode instanceof Points
		? Array.from({ length: eventNode.length }, (_, index) => eventNode[index])
		: [];
	const offNode = Tree.on(eventNode, "nodeChanged", () => { nodeEvents += 1; });
	const before = visible(view.root);
	run();
	const after = visible(view.root);
	const identityOrder = eventNode instanceof Items || eventNode instanceof Points
		? Array.from({ length: eventNode.length }, (_, index) => identities.indexOf(eventNode[index]))
		: [];
	offCommit();
	offChanged();
	offNode();
	return { before, after, identityOrder, commits, changed, nodeEvents };
}

async function replayScheduledHistory(input: Record<string, unknown>) {
	assert(Array.isArray(input.clients), "History replay needs client compressor states.");
	assert(Array.isArray(input.schedule), "History replay needs an action schedule.");
	const provider = createReplayProvider({
		clients: input.clients as ReplayClient[],
		initialState: input.initialState,
	});
	const checkpoints: Record<string, unknown>[] = [];
	const retained = new Map<string, unknown>();
	for (const value of input.schedule) {
		assert(value !== null && typeof value === "object", "History actions must be objects.");
		const action = value as ReplayAction;
		assert(typeof action.id === "string" && typeof action.op === "string",
			"History actions need IDs and operations.");
		const messageStarts = provider.processed.map((items) => items.length);
		let events: Record<string, unknown> | undefined;
		let summary: unknown;
		switch (action.op) {
			case "insert":
			case "remove":
			case "move":
				events = actionWithEvents(provider, action, () =>
					runEdit(provider.views[action.client ?? 0], action));
				break;
			case "transaction": {
				assert(Array.isArray(action.edits), `${action.id}: transaction edits`);
				events = actionWithEvents(provider, action, () => {
					Tree.runTransaction(provider.views[action.client ?? 0], () => {
						for (const edit of action.edits ?? []) {
							runEdit(provider.views[action.client ?? 0], edit);
						}
					});
				});
				break;
			}
			case "connect":
				assert(typeof action.connected === "boolean", `${action.id}: connection state`);
				if (action.connected) {
					assert(typeof action.reconnectId === "string", `${action.id}: reconnect client ID`);
				}
				provider.runtimes[action.client ?? 0].connected = action.connected;
				if (action.connected) {
					provider.transportIds.set(
						provider.runtimes[action.client ?? 0].clientId,
						action.reconnectId as string,
					);
				}
				break;
			case "reconnect":
				assert(typeof action.reconnectId === "string", `${action.id}: reconnect client ID`);
				provider.runtimes[action.client ?? 0].connected = true;
				provider.transportIds.set(
					provider.runtimes[action.client ?? 0].clientId,
					action.reconnectId,
				);
				break;
			case "retain": {
				assert(typeof Reflect.get(action, "name") === "string", `${action.id}: retain name`);
				assert(Array.isArray(action.path), `${action.id}: retain path`);
				retained.set(
					Reflect.get(action, "name") as string,
					readPath(provider.views[action.client ?? 0].root, action.path),
				);
				break;
			}
			case "deliver":
			case "ack":
			case "advance-minimum":
				provider.synchronize();
				break;
			case "summarize":
				summary = (await provider.trees[action.client ?? 0].summarize(true)).summary;
				break;
			case "checkpoint":
				break;
			default:
				assert.fail(`${action.id}: unknown history action ${action.op}`);
		}
		checkpoints.push({
			...replayCheckpoint(provider, action.id, messageStarts),
			...(events === undefined ? {} : { events }),
			...(summary === undefined ? {} : { summary: copy(summary) }),
			retained: [...retained].map(([name, node]) => ({
				name,
				status: String(Tree.status(node as never)),
				value: executed(() => visible(node)),
			})),
			removed: provider.trees.map((tree) => {
				const snapshot = Reflect.get(tree, "contentSnapshot") as () => { removed: unknown[] };
				return copy(snapshot.call(tree).removed);
			}),
		});
	}
	return {
		checkpoints,
		final: replayCheckpoint(
			provider,
			"final",
			provider.processed.map(() => 0),
		),
	};
}

type DeliveryEnvelope = {
	readonly clientId: string;
	readonly clientSequenceNumber: number;
	readonly referenceSequenceNumber: number;
	readonly sequenceNumber: number;
	readonly minimumSequenceNumber: number;
	readonly contents: unknown;
};

type IdCreationRange = ReturnType<
	ReturnType<typeof toIdCompressorWithCore>["takeNextCreationRange"]
>;

function deliverEnvelope(
	tree: unknown,
	envelope: DeliveryEnvelope,
): void {
	const kernel = Reflect.get(tree as object, "kernel") as {
		processMessagesCore(batch: unknown, local: boolean): void;
	};
	kernel.processMessagesCore({
		envelope: {
			...copy(envelope),
			timestamp: 0,
			type: "op",
		},
		messagesContent: [{
			contents: copy(envelope.contents),
			localOpMetadata: undefined,
			clientSequenceNumber: envelope.clientSequenceNumber,
		}],
	}, false);
}

async function replaySummaryTail(input: Record<string, unknown>) {
	const context = input.replayContext;
	assert(context !== null && typeof context === "object", "Summary-tail replay context is required.");
	const replayContext = context as {
		initialSummary: Parameters<typeof MockSharedObjectServices.createFromSummary>[0];
		startingCompressors: {
			reader: { serialized: string; sessionId: string };
			peer: { serialized: string; sessionId: string };
		};
		tailEnvelope: DeliveryEnvelope;
		continuationEnvelope: DeliveryEnvelope;
		continuationCreationRange: unknown;
	};
	const load = async (
		name: string,
		item: { serialized: string; sessionId: string },
		submit: (message: unknown) => number,
	) => {
		const runtime = new MockFluidDataStoreRuntime({
			idCompressor: deserializeIdCompressor(
				item.serialized as SerializedIdCompressorWithNoSession,
				assertIsSessionId(item.sessionId),
			),
		});
		const services = MockSharedObjectServices.createFromSummary(replayContext.initialSummary);
		services.deltaConnection = new MockDeltaConnection(submit, () => {});
		const factory = treeFactory();
		const tree = await factory.load(runtime, name, services, factory.attributes);
		return { runtime, tree, view: tree.viewWith(new TreeViewConfiguration({ schema: Root })) };
	};
	assert(Array.isArray(input.schedule), "Summary-tail replay needs an action schedule.");
	let reader: Awaited<ReturnType<typeof load>> | undefined;
	let peer: Awaited<ReturnType<typeof load>> | undefined;
	let readerAfterTail: unknown;
	let readerAfterContinuation: unknown;
	let readerHistoryAfterTail: unknown;
	let readerHistoryAfterContinuation: unknown;
	let creationRange: IdCreationRange | undefined;
	const submitted: unknown[] = [];
	for (const value of input.schedule) {
		assert(value !== null && typeof value === "object", "Summary-tail actions must be objects.");
		const action = value as ReplayAction;
		switch (action.op) {
			case "load-summary":
				reader = await load(
					"array-history-reader",
					replayContext.startingCompressors.reader,
					(message) => {
						submitted.push(copy(message));
						return replayContext.continuationEnvelope.clientSequenceNumber;
					},
				);
				break;
			case "deliver-tail":
				assert(reader !== undefined, "Summary-tail reader must load before tail delivery.");
				deliverEnvelope(reader.tree, replayContext.tailEnvelope);
				readerAfterTail = visible(reader.view.root);
				readerHistoryAfterTail = managerState(
					reader.tree as TestTreeProviderLite["trees"][number],
				);
				break;
			case "continue":
				assert(reader !== undefined, "Summary-tail reader must load before continuation.");
				assert(Array.isArray(action.path) && Number.isSafeInteger(action.index)
					&& Array.isArray(action.values), "Summary-tail continuation edit is incomplete.");
				runEdit(reader.view, { ...action, op: "insert" });
				const continuation = messagesIn(submitted);
				assert.equal(continuation.length, 1,
					"The reader must submit one continuation message.");
				assert.deepEqual(
					continuation[0],
					replayContext.continuationEnvelope.contents,
					"The continuation bytes must match the replay input.",
				);
				assert(reader.runtime.idCompressor !== undefined,
					"The reader needs an ID compressor.");
				creationRange =
					toIdCompressorWithCore(reader.runtime.idCompressor).takeNextCreationRange();
				assert.deepEqual(
					copy(creationRange),
					replayContext.continuationCreationRange,
					"The continuation creation range must match the replay input.",
				);
				readerAfterContinuation = visible(reader.view.root);
				readerHistoryAfterContinuation = managerState(
					reader.tree as TestTreeProviderLite["trees"][number],
				);
				break;
			case "load-peer":
				peer = await load(
					"array-history-peer",
					replayContext.startingCompressors.peer,
					() => 1,
				);
				break;
			case "deliver-continuation":
				assert(peer !== undefined && peer.runtime.idCompressor !== undefined,
					"Summary-tail peer must load before continuation delivery.");
				assert(creationRange !== undefined,
					"Summary-tail continuation must allocate before peer delivery.");
				toIdCompressorWithCore(peer.runtime.idCompressor)
					.finalizeCreationRange(creationRange);
				deliverEnvelope(peer.tree, replayContext.tailEnvelope);
				deliverEnvelope(peer.tree, replayContext.continuationEnvelope);
				break;
			default:
				assert.fail(`Unknown summary-tail action: ${action.op}`);
		}
	}
	assert(reader !== undefined && peer !== undefined,
		"Summary-tail replay must load the reader and peer.");
	assert(reader.runtime.idCompressor !== undefined && peer.runtime.idCompressor !== undefined,
		"Summary-tail replay must retain both ID compressors.");
	return {
		readerAfterTail,
		readerAfterContinuation,
		peer: visible(peer.view.root),
		readerHistoryAfterTail,
		readerHistoryAfterContinuation,
		peerHistory: managerState(peer.tree as TestTreeProviderLite["trees"][number]),
		continuationCreationRange: copy(creationRange),
		readerCompressor: compressorState(reader.runtime.idCompressor),
		peerCompressor: compressorState(peer.runtime.idCompressor),
	};
}

export async function replayArrayHistoryInput(input: Record<string, unknown>): Promise<unknown> {
	assert(typeof input.operation === "string", "History replay needs an operation.");
	if (input.operation === "summary-tail") return replaySummaryTail(input);
	return replayScheduledHistory(input);
}

function replayCodecAuthoring(input: Record<string, unknown>): ReplayProvider {
	assert(Array.isArray(input.clients), "Codec authoring needs client compressor states.");
	assert(Array.isArray(input.schedule), "Codec authoring needs an edit schedule.");
	const provider = createReplayProvider({
		clients: input.clients as ReplayClient[],
		initialState: input.initialState,
	});
	for (const value of input.schedule) {
		assert(value !== null && typeof value === "object", "Codec actions must be objects.");
		const action = value as ReplayAction;
		if (action.op === "deliver") {
			provider.synchronize();
		} else {
			runEdit(provider.views[action.client ?? 0], action);
		}
	}
	return provider;
}

async function loadSummaryInput(input: Record<string, unknown>) {
	assert(input.decodeContext !== null && typeof input.decodeContext === "object",
		"Summary decode context is required.");
	const context = input.decodeContext as { compressor: string; sessionId: string };
	assert(typeof context.compressor === "string", "Summary decode compressor is required.");
	assert(typeof context.sessionId === "string", "Summary decode session is required.");
	assert(input.encodedSummary !== null && typeof input.encodedSummary === "object",
		"Encoded summary is required.");
	const runtime = new MockFluidDataStoreRuntime({
		idCompressor: deserializeIdCompressor(
			context.compressor as SerializedIdCompressorWithNoSession,
			assertIsSessionId(context.sessionId),
		),
	});
	const factory = treeFactory();
	const tree = await factory.load(
		runtime,
		`array-codec-${String(input.operation)}`,
		MockSharedObjectServices.createFromSummary(
			input.encodedSummary as Parameters<typeof MockSharedObjectServices.createFromSummary>[0],
		),
		factory.attributes,
	);
	return {
		tree,
		view: tree.viewWith(new TreeViewConfiguration({ schema: Root })),
		runtime,
	};
}

function normalizedDecodedMessage(value: unknown) {
	assert(value !== null && typeof value === "object", "Decoded message must be an object.");
	const commit = Reflect.get(value, "commit") as {
		revision?: unknown;
		change?: { changes?: readonly { type?: unknown; innerChange?: unknown }[] };
	};
	const changes = commit.change?.changes ?? [];
	return {
		type: Reflect.get(value, "type"),
		branchId: Reflect.get(value, "branchId"),
		revision: commit.revision,
		sessionId: Reflect.get(value, "sessionId"),
		changes: changes.map((change) => ({
			type: change.type,
			data: change.type === "data"
				? encodeModularGraph(change.innerChange as ModularChangeset)
				: copy(change.innerChange),
		})),
	};
}

export async function replayArrayCodecInput(input: Record<string, unknown>): Promise<unknown> {
	assert(typeof input.operation === "string", "Codec replay needs an operation.");
	if (input.operation === "sequence-v3" || input.operation === "message-v7"
		|| input.operation === "builds") {
		assert(Array.isArray(input.encodedMessages) && input.encodedMessages.length > 0,
			`${input.operation}: encoded input messages`);
		assert(input.decodeContext !== null && typeof input.decodeContext === "object",
			`${input.operation}: decode context`);
		const context = input.decodeContext as {
			nativeInput: Record<string, unknown>;
		};
		assert(context.nativeInput !== null && typeof context.nativeInput === "object",
			`${input.operation}: native typed input`);
		const authoring = replayCodecAuthoring(context.nativeInput);
		const authoredMessages = messagesIn(authoring.processed[0]);
		assert.deepEqual(
			authoredMessages,
			input.encodedMessages,
			`${input.operation}: encoded input must match the typed authoring input.`,
		);
		const kernel = Reflect.get(authoring.trees[0], "kernel") as {
			messageCodec: { decode(value: unknown, context: { idCompressor: IIdCompressor }): unknown };
		};
		const decoded = input.encodedMessages.map((message) =>
			kernel.messageCodec.decode(message, { idCompressor: authoring.compressors[0] }));
		const normalized = decoded.map(normalizedDecodedMessage);
		return input.operation === "sequence-v3"
			? {
					encoded: copy(input.encodedMessages),
					sequenceChanges: normalized.flatMap(({ changes }) =>
						changes.filter(({ type }) => type === "data")
							.flatMap(({ data }) =>
								(data as ReturnType<typeof modularStructure>).fields)),
					decoded: normalized,
				}
			: {
					encoded: copy(input.encodedMessages),
					decoded: normalized,
				};
	}
	const loaded = await loadSummaryInput(input);
	const summary = input.encodedSummary as { tree: Record<string, unknown> };
	assert(loaded.runtime.idCompressor !== undefined, "Summary runtime needs an ID compressor.");
	const result = {
		visible: visible(loaded.view.root),
		schema: summaryBlob(summary, "indexes", "Schema", "SchemaString"),
		forest: summaryBlob(summary, "indexes", "Forest", "contents"),
		restoredDetached: copy((Reflect.get(loaded.tree, "contentSnapshot") as () => {
			removed: unknown[];
		}).call(loaded.tree).removed),
		restoredHistory: managerState(loaded.tree as TestTreeProviderLite["trees"][number]),
		compressor: compressorState(loaded.runtime.idCompressor),
	};
	if (input.operation === "empty-arrays" || input.operation === "retained-history"
		|| input.operation === "detached-index" || input.operation === "full-summary") {
		return result;
	}
	assert.fail(`Unknown codec replay operation: ${input.operation}`);
}

export async function replayArrayInvalidInput(input: Record<string, unknown>): Promise<unknown> {
	assert(typeof input.operation === "string", "Invalid replay needs an operation.");
	switch (input.operation) {
		case "corrupt-schema":
			return executed(() => schemaCodecBuilder
				.buildDecoder({ jsonValidator: FormatValidatorNoOp })
				.decode(input.malformed as never));
		case "corrupt-mark":
		case "corrupt-revision": {
			assert(input.malformed !== null && typeof input.malformed === "object",
				`${input.operation}: malformed input`);
			assert(input.valid !== null && typeof input.valid === "object",
				`${input.operation}: valid control`);
			assert(input.decodeContext !== null && typeof input.decodeContext === "object",
				`${input.operation}: decode context`);
			const decodeContext = input.decodeContext as {
				decoder: { compressor: string; sessionId: string };
			};
			const decode = (message: unknown) => {
				assert(typeof decodeContext.decoder.compressor === "string",
					`${input.operation}: decoder compressor`);
				assert(typeof decodeContext.decoder.sessionId === "string",
					`${input.operation}: decoder session`);
				const idCompressor = deserializeIdCompressor(
					decodeContext.decoder.compressor as SerializedIdCompressorWithNoSession,
					assertIsSessionId(decodeContext.decoder.sessionId),
				);
				const runtime = new MockFluidDataStoreRuntime({ idCompressor });
				const tree = treeFactory().create(runtime, `array-invalid-${input.operation}`);
				const kernel = Reflect.get(tree, "kernel") as {
					messageCodec: {
						decode(value: unknown, context: { idCompressor: IIdCompressor }): unknown;
					};
				};
				return normalizedDecodedMessage(
					kernel.messageCodec.decode(message, { idCompressor }),
				);
			};
			return {
				control: executed(() => decode(input.valid)),
				malformed: executed(() => decode(input.malformed)),
			};
		}
		case "corrupt-range": {
			assert(input.malformed !== null && typeof input.malformed === "object",
				"corrupt-range: malformed input");
			const range = input.malformed as { start: number; end: number };
			const provider = new TestTreeProviderLite(1, treeFactory());
			const view = provider.trees[0].viewWith(new TreeViewConfiguration({ schema: Items }));
			view.initialize(contentFor("rootArray", input.initialState) as Items);
			return executed(() => {
				view.root.removeRange(range.start, range.end);
				return visible(view.root);
			});
		}
		case "corrupt-ownership": {
			assert(Array.isArray(input.initialStates) && input.initialStates.length === 2,
				"corrupt-ownership: initial states");
			const initialStates = input.initialStates;
			const makeProviders = () => initialStates.map((state: unknown) => {
				const provider = new TestTreeProviderLite(1, treeFactory());
				const view = provider.trees[0].viewWith(new TreeViewConfiguration({ schema: Root }));
				view.initialize(contentFor("objectArrays", state) as Root);
				return { provider, view };
			});
			const apply = (specification: unknown) => {
				assert(specification !== null && typeof specification === "object",
					"corrupt-ownership: operation specification");
				const source = Reflect.get(specification, "source");
				const destination = Reflect.get(specification, "destination");
				const kind = Reflect.get(specification, "kind");
				assert(kind === "insert" || kind === "move",
					"corrupt-ownership: operation kind");
				assert(source !== null && typeof source === "object",
					"corrupt-ownership: source");
				assert(destination !== null && typeof destination === "object",
					"corrupt-ownership: destination");
				const sourceClient = Reflect.get(source, "client");
				const destinationClient = Reflect.get(destination, "client");
				const sourcePath = Reflect.get(source, "path");
				const destinationPath = Reflect.get(destination, "path");
				const sourceIndex = Reflect.get(source, "index");
				const gap = Reflect.get(destination, "gap");
				assert(Number.isSafeInteger(sourceClient), "corrupt-ownership: source client");
				assert(Number.isSafeInteger(destinationClient),
					"corrupt-ownership: destination client");
				assert(Array.isArray(sourcePath) && sourcePath.every((item) => typeof item === "string"),
					"corrupt-ownership: source path");
				assert(Array.isArray(destinationPath)
					&& destinationPath.every((item) => typeof item === "string"),
				"corrupt-ownership: destination path");
				assert(Number.isSafeInteger(sourceIndex), "corrupt-ownership: source index");
				assert(Number.isSafeInteger(gap), "corrupt-ownership: destination index");
				const providers = makeProviders();
				const sourceArray = arrayAt(
					providers[sourceClient as number].view.root,
					sourcePath as string[],
				);
				const destinationArray = arrayAt(
					providers[destinationClient as number].view.root,
					destinationPath as string[],
				);
				const node = sourceArray[sourceIndex as number];
				assert(node instanceof Point, "corrupt-ownership: source point");
				if (kind === "move") {
					destinationArray.moveRangeToIndex(
						gap as number,
						sourceIndex as number,
						(sourceIndex as number) + 1,
						sourceArray as never,
					);
				} else {
					destinationArray.insertAt(gap as number, node);
				}
				return visible(providers[destinationClient as number].view.root);
			};
			return {
				control: executed(() => apply(input.control)),
				malformed: executed(() => apply(input.malformed)),
			};
		}
		case "corrupt-summary":
			return executedAsync(async () => {
				await loadSummaryInput({
					operation: input.operation,
					encodedSummary: input.malformed,
					decodeContext: input.decodeContext,
				});
				return true;
			});
		case "native-remove-beyond-length": {
			assert(input.malformed !== null && typeof input.malformed === "object",
				"native-remove-beyond-length: malformed input");
			const range = input.malformed as { start: number; end: number };
			const provider = new TestTreeProviderLite(1, treeFactory());
			const view = provider.trees[0].viewWith(new TreeViewConfiguration({ schema: Items }));
			view.initialize(contentFor("rootArray", input.initialState) as Items);
			view.root.removeRange(range.start, range.end);
			return { accepted: true, value: visible(view.root), nativeContract: "error" };
		}
		default:
			assert.fail(`Unknown invalid replay operation: ${input.operation}`);
	}
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
			})),
		},
		expected: {
			observations: scenarios.map((scenario) => ({
				id: scenario.id,
				...(id === "array-modular-algebra" ? { executed: true } : {}),
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
				},
				output: copy(scenario.output),
			})),
		},
	};
}

function managerState(tree: TestTreeProviderLite["trees"][number]) {
	type Commit = GraphCommit<SharedTreeChange>;
	const manager = Reflect.get(tree.kernel, "editManager") as {
		getLocalCommits(branch: string): Commit[];
		getTrunkCommits(branch: string): Commit[];
		getLongestBranchLength(): number;
		sharedBranches: Map<string, object>;
	};
	assert(manager !== undefined, "The public tree must expose its test edit manager.");
	const main = manager.sharedBranches.get("main") as {
		commitMetadata: Map<
			unknown,
			{ sequenceId: { sequenceNumber: number; indexInBatch?: number }; sessionId: unknown }
		>;
		peerLocalBranches: Map<unknown, { getHead(): Commit }>;
	};
	assert(main !== undefined, "The public tree must expose its main branch.");
	const observeCommit = (commit: Commit) => ({
		revision: commit.revision,
		changes: normalizedDecodedMessage({ commit }).changes,
	});
	const trunk = manager.getTrunkCommits("main");
	const trunkRevisions = new Set(trunk.map(({ revision }) => revision));
	return {
		pending: manager.getLocalCommits("main").map(observeCommit),
		trunk: trunk.map((commit) => {
			const metadata = main.commitMetadata.get(commit.revision);
			return {
				...observeCommit(commit),
				sessionId: metadata?.sessionId ?? null,
				sequenceNumber: metadata?.sequenceId.sequenceNumber ?? null,
				indexInBatch: metadata?.sequenceId.indexInBatch ?? null,
			};
		}),
		peers: [...main.peerLocalBranches].map(([sessionId, branch]) => {
			const commits: ReturnType<typeof observeCommit>[] = [];
			let commit = branch.getHead();
			while (commit.parent !== undefined && !trunkRevisions.has(commit.revision)) {
				commits.push(observeCommit(commit));
				commit = commit.parent;
			}
			return { sessionId, base: commit.revision, commits };
		}),
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
	const initialSummaryCompressor = serializeIdCompressor(
		provider.getCompressor(provider.trees[0]),
		false,
	);
	const initialOngoingCompressor = serializeIdCompressor(
		provider.getCompressor(provider.trees[0]),
		true,
	);

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
	const operationEnvelopes = copy(processed.slice(operationStart));
	const operationMessages = messagesIn(operationEnvelopes);
	assert(operationMessages.length > 0, "Array edits must produce SharedTree messages.");
	const operationCompressor = serializeIdCompressor(
		provider.getCompressor(provider.trees[1]),
		false,
	);
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
	const emptySummaryCompressor = serializeIdCompressor(
		emptyProvider.getCompressor(emptyProvider.trees[0]),
		false,
	);

	const retainedProvider = new TestTreeProviderLite(2, factory);
	const retainedView = retainedProvider.trees[0].viewWith(configuration);
	retainedView.initialize(initialRoot());
	retainedProvider.synchronizeMessages();
	retainedProvider.trees[1].containerRuntime.connected = false;
	retainedView.root.left.removeRange(0, 2);
	retainedProvider.synchronizeMessages();
	const retainedSummary = (await retainedProvider.trees[0].summarize(true)).summary;
	const retainedSummaryCompressor = serializeIdCompressor(
		retainedProvider.getCompressor(retainedProvider.trees[0]),
		false,
	);

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
	const tailCompressor = serializeIdCompressor(
		tailProvider.getCompressor(tailProvider.trees[0]),
		false,
	);
	const tailEnvelope = tailProcessed.find((item) =>
		item !== null && typeof item === "object"
		&& Reflect.get(Reflect.get(item, "contents") as object, "version") === 7
	) as Record<string, unknown> | undefined;
	assert(tailEnvelope !== undefined, "The summary-tail probe must retain the tree envelope.");
	const readerSession = createSessionId();
	const tailRuntime = new MockFluidDataStoreRuntime({
		idCompressor: deserializeIdCompressor(tailCompressor, readerSession),
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
	const continuationCreationRange = continuationCompressorCore.takeNextCreationRange();
	continuationCompressorCore.finalizeCreationRange(continuationCreationRange);
	const continuationCompressor = serializeIdCompressor(tailRuntime.idCompressor, false);
	const verifierSession = createSessionId();
	const verifierRuntime = new MockFluidDataStoreRuntime({
		idCompressor: deserializeIdCompressor(tailCompressor, verifierSession),
	});
	assert(verifierRuntime.idCompressor !== undefined,
		"The independent verifier runtime must retain its ID compressor.");
	toIdCompressorWithCore(verifierRuntime.idCompressor)
		.finalizeCreationRange(continuationCreationRange);
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
	const continuationEnvelope = {
		clientId: continuationSession,
		clientSequenceNumber: 1,
		referenceSequenceNumber: tailSequence.sequenceNumber,
		sequenceNumber: tailSequence.sequenceNumber + 1,
		minimumSequenceNumber: tailSequence.minimumSequenceNumber,
		contents: continuationMessages[0],
	};
	assert.deepEqual(visible(verifierView.root), readerAfterContinuation,
		"An independently loaded reader must apply the tail and continuation.");

	return {
		provider,
		view,
		initialSummary,
		initialSummaryCompressor,
		initialOngoingCompressor,
		operationCompressor,
		operationEnvelopes,
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
		emptySummaryCompressor,
		retainedSummary,
		retainedSummaryCompressor,
		summaryTail: {
			snapshot: tailSummary,
			startingCompressors: {
				reader: { serialized: tailCompressor, sessionId: readerSession },
				peer: { serialized: tailCompressor, sessionId: verifierSession },
			},
			tail: tailProcessed,
			tailEnvelope: {
				...tailSequence,
				contents: tailMessages[0],
			},
			writer: visible(tailView.root),
			readerAfterTail,
			readerMessages: tailMessages,
			continuationMessages,
			continuationEnvelope,
			continuationCreationRange: copy(continuationCreationRange),
			continuationCompressor,
			readerAfterContinuation,
			verifier: visible(verifierView.root),
		},
	};
}

async function makeCases() {
	const publicEvidence = await capturePublicEvidence();
	const rootArrayContent = ["root", ["nested"]];
	const mapRootContent = { map: [["0", ["zero"]], ["", []]] };
	const schemas = {
		rootArray: schemaString(Items),
		objectArrays: schemaString(Root),
		mapArrays: schemaString(ArrayMap),
		recursiveArrays: schemaString(Items),
		incompatibleArrays: schemaString(Points),
	};
	const schemaInputs: Record<string, Record<string, unknown>> = {
		"root-array": {
			operation: "schema",
			schema: "rootArray",
			schemaBytes: schemas.rootArray,
			initialState: rootArrayContent,
		},
		"object-arrays": {
			operation: "schema",
			schema: "objectArrays",
			schemaBytes: schemas.objectArrays,
			initialState: plainInitialRoot(),
		},
		"map-arrays": {
			operation: "schema",
			schema: "mapArrays",
			schemaBytes: schemas.mapArrays,
			initialState: mapRootContent,
		},
		"nested-arrays": {
			operation: "read",
			schema: "objectArrays",
			schemaBytes: schemas.objectArrays,
			initialState: plainInitialRoot(),
			path: ["left", "3", "0"],
		},
		"recursive-arrays": {
			operation: "read",
			schema: "objectArrays",
			schemaBytes: schemas.objectArrays,
			initialState: plainInitialRoot(),
			path: ["byKey", "0", "1", "0"],
		},
		"incompatible-arrays": {
			operation: "move",
			schema: "objectArrays",
			schemaBytes: schemas.objectArrays,
			initialState: plainInitialRoot(),
			source: { path: ["left"], start: 0, end: 1 },
			destination: { path: ["narrow"], gap: 0 },
		},
		"empty-content": {
			operation: "initialize",
			schema: "rootArray",
			schemaBytes: schemas.rootArray,
			initialState: [],
		},
		"allowed-leaves": {
			operation: "initialize",
			schema: "rootArray",
			schemaBytes: schemas.rootArray,
			initialState: ["string", 1, true, null],
		},
		compatibility: {
			operation: "canView",
			schema: "objectArrays",
			schemaBytes: schemas.objectArrays,
			viewSchema: "objectArrays",
			viewSchemaBytes: schemas.objectArrays,
			initialState: plainInitialRoot(),
		},
		"schema-content-bytes": {
			operation: "summarize",
			schema: "objectArrays",
			schemaBytes: schemas.objectArrays,
			initialState: plainInitialRoot(),
			forestBytes: summaryBlob(publicEvidence.initialSummary, "indexes", "Forest", "contents"),
		},
	};
	const schemaScenarios: Scenario[] = [];
	for (const id of scenarioIds["array-schema-content"]) {
		const input = copy(schemaInputs[id]);
		const output = await replayArraySchemaInput(copy(input));
		schemaScenarios.push({
			id,
			input,
			observation: id === "incompatible-arrays"
				? { accepted: Reflect.get(output as object, "accepted") }
				: {},
			output,
		});
	}
	const incompatibleCompatibility = copy(schemaInputs.compatibility);
	incompatibleCompatibility.viewSchema = "incompatibleArrays";
	const compatibilityMutation = await executedAsync(() =>
		replayArraySchemaInput(incompatibleCompatibility));
	assert(
		compatibilityMutation.accepted === false,
		"Changing the compatibility schema selector without its bytes must reject replay.",
	);

	const message = publicEvidence.operationMessages.at(-1);
	assert(message !== undefined, "Array operations must yield a final message.");
	const changeset = Reflect.get(message, "changeset") as unknown[];
	assert(changeset[0] !== null && typeof changeset[0] === "object", "Message changeset must be an object.");
	const modular = Reflect.get(changeset[0], "data");
	const modularKinds = fieldKinds(modular);
	assert(modularKinds.includes("Sequence"), "Array operations must encode a Sequence field.");
	const modularCompressor = createIdCompressor(
		"72da8bc7-6340-46de-a690-a911d13bddca" as SessionId,
	);
	const modularRevisions = Array.from(
		{ length: 11 },
		() => modularCompressor.generateCompressedId() as RevisionTag,
	);
	const revisionMap = modularRevisions.map((revision) => ({
		encoded: Number(revision),
		stable: modularCompressor.decompress(revision as SessionSpaceCompressedId),
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
		builds: [],
		refreshers: [],
		destroys: [],
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
			compressor: {
				sessionId: modularCompressor.localSessionId,
				serialized: serializeIdCompressor(modularCompressor, true),
			},
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
		"cross-field-endpoints": crossFieldCoordinationInput(r6, modularCompressor) as unknown as Record<
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
		const rawOutput = replayArrayModularInputRaw(input) as {
			coordination: {
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
		};
		Reflect.set(input, "sourceCoordination", copy(rawOutput.coordination));
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
			const coordination = rawOutput.coordination;
			assert.deepEqual(
				coordination.handlerCalls.slice(0, 3).map(({ field }) => field.field),
				["right", "left", "right"],
				"The source manager must reprocess the destination after discovering the source.",
			);
			assert(
				coordination.managerCalls.some(
					(call) =>
						call.method === "set" &&
						call.invalidateDependents === true,
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

	const codecProfile = {
		message: 7,
		sharedTreeChange: 5,
		modularChange: 5,
		sequence: 3,
		schema: 2,
		forest: 2,
		detachedFieldIndex: 2,
		editManager: 7,
	};
	const codecAuthoring = {
		initialState: plainInitialRoot(),
		clients: [copy(replayClients[0])],
		schedule: [
			{ id: "insert", op: "insert", client: 0, path: ["left"], index: 1,
				values: ["inserted", { point: { label: "new", x: 2 } }] },
			{ id: "remove", op: "remove", client: 0, path: ["left"], start: 0, end: 1 },
			{ id: "interior-move", op: "move", client: 0, path: ["left"],
				sourcePath: ["left"], start: 1, end: 3, gap: 2 },
			{ id: "cross-array-move", op: "move", client: 0, path: ["right"],
				sourcePath: ["left"], start: 1, end: 2, gap: 1 },
			{ id: "deliver", op: "deliver" },
		],
	};
	const messageDecodeContext = {
		nativeInput: codecAuthoring,
		decoder: {
			compressor: publicEvidence.operationCompressor,
			sessionId: "57b377e0-3799-4cec-8d5a-1b204655d87e",
		},
	};
	const summaryInput = (
		operation: string,
		encodedSummary: unknown,
		compressor: string,
	) => ({
		operation,
		profile: codecProfile,
		encodedSummary,
		decodeContext: {
			compressor,
			sessionId: createSessionId(),
		},
	});
	const messageInput = (operation: string, encodedMessages: unknown[]) => ({
		operation,
		profile: codecProfile,
		encodedMessages,
		decodeContext: messageDecodeContext,
		sequencing: (publicEvidence.operationEnvelopes as Record<string, unknown>[]).map((envelope) => ({
			clientId: envelope.clientId,
			clientSequenceNumber: envelope.clientSequenceNumber,
			referenceSequenceNumber: envelope.referenceSequenceNumber,
			sequenceNumber: envelope.sequenceNumber,
			minimumSequenceNumber: envelope.minimumSequenceNumber,
		})),
	});
	const codecInputs: Record<string, Record<string, unknown>> = {
		"sequence-v3": messageInput("sequence-v3", publicEvidence.operationMessages),
		"message-v7": messageInput("message-v7", publicEvidence.operationMessages),
		builds: messageInput("builds", publicEvidence.operationMessages),
		"empty-arrays": summaryInput(
			"empty-arrays",
			publicEvidence.emptySummary,
			publicEvidence.emptySummaryCompressor,
		),
		"retained-history": summaryInput(
			"retained-history",
			publicEvidence.retainedSummary,
			publicEvidence.retainedSummaryCompressor,
		),
		"detached-index": summaryInput(
			"detached-index",
			publicEvidence.retainedSummary,
			publicEvidence.retainedSummaryCompressor,
		),
		"full-summary": summaryInput(
			"full-summary",
			publicEvidence.settledSummary,
			serializeIdCompressor(
				publicEvidence.provider.getCompressor(publicEvidence.provider.trees[0]),
				false,
			),
		),
	};
	const codecScenarios: Scenario[] = [];
	for (const id of scenarioIds["array-codecs"]) {
		const input = copy(codecInputs[id]);
		const output = await replayArrayCodecInput(copy(input));
		codecScenarios.push({ id, input, observation: {}, output });
	}
	const decodedBuild = (Reflect.get(
		codecScenarios.find(({ id }) => id === "builds")?.output as object,
		"decoded",
	) as { changes: { type: string; data: { builds: unknown[] } }[] }[])
		.flatMap(({ changes }) => changes)
		.find(({ type, data }) => type === "data" && data.builds.length > 0);
	assert(decodedBuild !== undefined,
		"The decoded Message V7 build must retain its modular build table.");
	const codecMutation = copy(codecInputs["message-v7"]);
	const nativeCodecInput = Reflect.get(
		Reflect.get(codecMutation, "decodeContext") as object,
		"nativeInput",
	) as { schedule: { index?: number }[] };
	assert(typeof nativeCodecInput.schedule[0].index === "number",
		"The codec mutation needs an insert index.");
	nativeCodecInput.schedule[0].index += 1;
	const changedCodec = await executedAsync(() => replayArrayCodecInput(codecMutation));
	assert(
		changedCodec.accepted === false,
		"Changing a codec authoring argument must reject the supplied encoded messages.",
	);

	const historyInput = (
		operation: string,
		schedule: ReplayAction[],
		initialState: unknown = plainInitialRoot(),
	) => ({
		operation,
		initialState,
		clients: copy(replayClients),
		schedule,
	});
	const windowSchedule: ReplayAction[] = [
		{ id: "retain-left-1", op: "retain", name: "removed-left-1", client: 0,
			path: ["left", "1"] },
		{ id: "remove-retained", op: "remove", client: 0, path: ["left"], start: 1, end: 2 },
		{ id: "deliver-removal", op: "advance-minimum" },
	];
	for (let index = 0; index < 8; index += 1) {
		windowSchedule.push(
			{
				id: `advance-${index}`,
				op: "insert",
				client: index % 2,
				path: ["right"],
				index: index + 1,
				values: [`advance-${index}`],
			},
			{ id: `deliver-advance-${index}`, op: "advance-minimum" },
		);
	}
	const equalRoot = plainInitialRoot() as Record<string, unknown>;
	equalRoot.left = [
		{ point: { label: "equal", x: 1 } },
		{ point: { label: "equal", x: 1 } },
		{ point: { label: "equal", x: 1 } },
	];
	const historyInputs: Record<string, Record<string, unknown>> = {
		"pending-chains": historyInput("pending-chains", [
			{ id: "disconnect-local", op: "connect", client: 0, connected: false },
			{ id: "local-a", op: "insert", client: 0, path: ["left"], index: 4,
				values: ["pending-a"] },
			{ id: "local-b", op: "insert", client: 0, path: ["left"], index: 5,
				values: ["pending-b"] },
			{ id: "remote", op: "insert", client: 1, path: ["right"], index: 1,
				values: ["remote"] },
			{ id: "deliver-remote", op: "deliver" },
			{ id: "pending-checkpoint", op: "checkpoint" },
			{ id: "reconnect-local", op: "connect", client: 0, connected: true,
				reconnectId: "client-0-reconnect-pending" },
			{ id: "settle", op: "deliver" },
		]),
		batching: historyInput("batching", [
			{
				id: "transaction",
				op: "transaction",
				client: 0,
				edits: [
					{ id: "batch-left", op: "insert", path: ["left"], index: 4,
						values: ["batch-a"] },
					{ id: "batch-right", op: "insert", path: ["right"], index: 1,
						values: ["batch-b"] },
				],
			},
			{ id: "deliver-batch", op: "deliver" },
		]),
		acknowledgements: historyInput("acknowledgements", [
			{ id: "local-edit", op: "insert", client: 0, path: ["left"], index: 4,
				values: ["ack"] },
			{ id: "before-ack", op: "checkpoint" },
			{ id: "ack", op: "ack" },
		]),
		reconnect: historyInput("reconnect", [
			{ id: "disconnect", op: "connect", client: 0, connected: false },
			{ id: "local-edit", op: "insert", client: 0, path: ["left"], index: 4,
				values: ["offline"] },
			{ id: "remote-edit", op: "insert", client: 1, path: ["right"], index: 1,
				values: ["remote"] },
			{ id: "deliver-remote", op: "deliver" },
			{ id: "reconnect", op: "reconnect", client: 0,
				reconnectId: "client-0-reconnect" },
			{ id: "deliver-resubmission", op: "deliver" },
		]),
		"window-advance": historyInput("window-advance", windowSchedule),
		"summary-tail": {
			operation: "summary-tail",
			initialState: plainInitialRoot(),
			schedule: [
				{ id: "load-summary", op: "load-summary" },
				{ id: "deliver-tail", op: "deliver-tail" },
				{ id: "author-continuation", op: "continue", client: 0, path: ["left"],
					index: 4, values: ["reader-continuation"] },
				{ id: "load-peer", op: "load-peer" },
				{ id: "deliver-continuation-to-peer", op: "deliver-continuation" },
			],
			replayContext: {
				initialSummary: publicEvidence.summaryTail.snapshot,
				startingCompressors: publicEvidence.summaryTail.startingCompressors,
				tailEnvelope: publicEvidence.summaryTail.tailEnvelope,
				continuationEnvelope: publicEvidence.summaryTail.continuationEnvelope,
				continuationCreationRange: publicEvidence.summaryTail.continuationCreationRange,
			},
		},
		"public-noops": historyInput("public-noops", [
			{ id: "empty-insert", op: "insert", client: 0, path: ["left"], index: 0, values: [] },
			{ id: "empty-remove", op: "remove", client: 0, path: ["left"], start: 1, end: 1 },
			{ id: "empty-move", op: "move", client: 0, path: ["left"], sourcePath: ["left"],
				start: 1, end: 1, gap: 1 },
			{ id: "equal-value-swap", op: "move", client: 0, path: ["left"],
				sourcePath: ["left"], start: 1, end: 2, gap: 3 },
			{ id: "deliver-swap", op: "deliver" },
			{ id: "public-interior-move", op: "move", client: 0, path: ["left"],
				sourcePath: ["left"], start: 0, end: 3, gap: 1 },
			{ id: "deliver-interior", op: "deliver" },
		], equalRoot),
	};
	const historyScenarios: Scenario[] = [];
	for (const id of scenarioIds["array-history"]) {
		const input = copy(historyInputs[id]);
		const output = await replayArrayHistoryInput(copy(input));
		if (id === "summary-tail") {
			assert.deepEqual(
				Reflect.get(output as object, "readerAfterContinuation"),
				Reflect.get(output as object, "peer"),
				"Summary-tail replay must converge with an independent peer.",
			);
		}
		historyScenarios.push({ id, input, observation: {}, output });
	}
	const historyMutation = copy(historyInputs["pending-chains"]);
	const historyInsert = (historyMutation.schedule as { op: string; values?: unknown[] }[])
		.find(({ op }) => op === "insert");
	assert(historyInsert?.values !== undefined, "The history mutation needs an insert action.");
	historyInsert.values[0] = "mutated-pending";
	const originalHistory = historyScenarios.find(({ id }) => id === "pending-chains")?.output;
	const changedHistory = await replayArrayHistoryInput(historyMutation);
	assert.notDeepEqual(
		changedHistory,
		originalHistory,
		"Changing a history edit argument must change replay.",
	);
	const tailMutation = copy(historyInputs["summary-tail"]);
	const continuationEnvelope = Reflect.get(
		Reflect.get(tailMutation, "replayContext") as object,
		"continuationEnvelope",
	) as { sequenceNumber: number };
	continuationEnvelope.sequenceNumber += 1;
	const changedTail = await executedAsync(() => replayArrayHistoryInput(tailMutation));
	assert(
		changedTail.accepted === false
			|| JSON.stringify(Reflect.get(changedTail.value as object, "peerHistory"))
				!== JSON.stringify(Reflect.get(
					historyScenarios.find(({ id }) => id === "summary-tail")?.output as object,
					"peerHistory",
				)),
		"Changing continuation sequencing metadata must change source history or reject replay.",
	);

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
	const summary = publicEvidence.settledSummary;
	const corruptSummary = { ...copy(summary), tree: {} };
	const invalidMessageContext = {
		decodeContext: messageDecodeContext,
		initialSummary: publicEvidence.initialSummary,
		summaryCompressor: publicEvidence.initialSummaryCompressor,
		summarySessionId: createSessionId(),
	};
	const invalidInputs: Record<string, Record<string, unknown>> = {
		"corrupt-schema": {
			operation: "corrupt-schema",
			malformed: { version: 99 },
		},
		"corrupt-mark": {
			operation: "corrupt-mark",
			valid: message,
			malformed: corruptMarkMessage,
			...invalidMessageContext,
		},
		"corrupt-range": {
			operation: "corrupt-range",
			initialState: ["A", "B", "C"],
			malformed: { start: 2, end: 1 },
		},
		"corrupt-revision": {
			operation: "corrupt-revision",
			valid: message,
			malformed: corruptRevisionMessage,
			...invalidMessageContext,
		},
		"corrupt-ownership": {
			operation: "corrupt-ownership",
			initialStates: [plainInitialRoot(), plainInitialRoot()],
			malformed: {
				kind: "insert",
				source: { client: 1, path: ["narrow"], index: 0 },
				destination: { client: 0, path: ["narrow"], gap: 0 },
			},
			control: {
				kind: "move",
				source: { client: 0, path: ["narrow"], index: 0 },
				destination: { client: 0, path: ["narrow"], gap: 1 },
			},
		},
		"corrupt-summary": {
			operation: "corrupt-summary",
			malformed: corruptSummary,
			decodeContext: {
				compressor: serializeIdCompressor(
					publicEvidence.provider.getCompressor(publicEvidence.provider.trees[0]),
					false,
				),
				sessionId: createSessionId(),
			},
		},
		"native-remove-beyond-length": {
			operation: "native-remove-beyond-length",
			initialState: ["A", "B"],
			malformed: { start: 1, end: 99 },
			nativeContract: "error",
		},
	};
	const invalidScenarios: Scenario[] = [];
	for (const id of scenarioIds["array-invalid"]) {
		const input = copy(invalidInputs[id]);
		const output = await replayArrayInvalidInput(copy(input));
		if (id === "corrupt-mark" || id === "corrupt-revision") {
			assert.equal(Reflect.get(Reflect.get(output as object, "control"), "accepted"), true,
				`${id}: the valid payload must decode with the same context.`);
			const malformed = Reflect.get(output as object, "malformed");
			assert.equal(Reflect.get(malformed, "accepted"), false,
				`${id}: the malformed payload must be rejected by the source decoder.`);
			assert.match(
				String(Reflect.get(malformed, "error")),
				new RegExp(id === "corrupt-mark" ? "0xac2" : "0x88d"),
				`${id}: the source decoder must report its pinned assertion.`,
			);
		}
		if (id === "corrupt-ownership") {
			assert.equal(Reflect.get(Reflect.get(output as object, "control"), "accepted"), true,
				"Same-context ownership control must succeed.");
			assert.equal(Reflect.get(Reflect.get(output as object, "malformed"), "accepted"), false,
				"Cross-context ownership must fail.");
		}
		invalidScenarios.push({
			id,
			input,
			observation: {
				rejected: id === "native-remove-beyond-length"
					? false
					: id === "corrupt-mark" || id === "corrupt-revision"
						|| id === "corrupt-ownership"
						? Reflect.get(Reflect.get(output as object, "malformed"), "accepted") === false
						: Reflect.get(output as object, "accepted") === false,
			},
			output,
		});
	}

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
