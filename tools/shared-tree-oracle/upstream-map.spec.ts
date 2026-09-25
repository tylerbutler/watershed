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

import {
	FluidClientVersion,
	FormatValidatorNoOp,
	type CodecWriteOptions,
} from "../codec/index.js";
import {
	RevisionTagCodec,
	revisionMetadataSourceFromInfo,
	rootFieldKey,
	tagChange,
	type ChangeEncodingContext,
	type FieldUpPath,
	type MapTree,
	type RevisionTag,
	type TaggedChange,
	type TreeChunk,
	type UpPath,
} from "../core/index.js";
import {
	chunkField,
	combineChunks,
	cursorForMapTreeField,
	defaultChunkPolicy,
	DefaultEditBuilder,
	fieldBatchCodecBuilder,
	fieldKindConfigurations,
	fieldKinds,
	intoDelta,
	makeModularChangeCodecFamily,
	ModularChangeFamily,
	ModularChangeFormatVersion,
	relevantRemovedRoots,
	schemaCodecBuilder,
	TreeCompressionStrategy,
	updateRefreshers,
	type ModularChangeset,
} from "../feature-libraries/index.js";
import { FormatValidatorBasic } from "../external-utilities/index.js";
import { EditManager } from "../shared-tree-core/index.js";
import {
	extractPersistedSchema,
	type ImplicitFieldSchema,
	SchemaFactory,
	TreeViewConfiguration,
} from "../simple-tree/index.js";
import { configuredSharedTreeInternal } from "../treeFactory.js";
import { brand } from "../util/index.js";
import { MockContainerRuntimeWithOpBunching } from "./mocksForOpBunching.js";
import { TestTreeProviderLite, mintRevisionTag, testIdCompressor } from "./utils.js";
import { deltaDataWithCompressor } from "./watershedModular.spec.js";
import {
	runScenario,
	type Scenario as ForestScenario,
	type TaggedValue as ForestTaggedValue,
} from "./watershedForest.spec.js";

const formatVersion = 1;
const reference = {
	package: "@fluidframework/tree",
	version: "3.1.0",
	commit: "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960",
};
const requiredMapCases = [
	"map-schema-content",
	"map-field-algebra",
	"map-history-codecs",
] as const;
const requiredMapScenarios = [
	"set-absent",
	"replace-present",
	"delete-present",
	"delete-absent",
	"different-keys",
	"same-key-set-set-left-last",
	"same-key-set-set-right-last",
	"same-key-set-delete",
	"same-key-delete-set",
	"nested-edit-vs-replace",
	"nested-edit-vs-delete",
	"nested-map-independent",
	"nested-map-conflict",
] as const;

const mapFactory = new SchemaFactory("org.watershed.shared-tree.m2");
class MapPoint extends mapFactory.object("Point", {
	x: mapFactory.number,
	y: mapFactory.number,
}) {}
class NamedMap extends mapFactory.map("NamedMap", [
	mapFactory.string,
	mapFactory.number,
	mapFactory.boolean,
	mapFactory.null,
	MapPoint,
]) {}
class DynamicMap extends mapFactory.mapRecursive("DynamicMap", [
	mapFactory.string,
	mapFactory.number,
	mapFactory.boolean,
	mapFactory.null,
	MapPoint,
	() => DynamicMap,
]) {}
class MapRoot extends mapFactory.object("Root", { items: DynamicMap }) {}

function sharedTreeFactory() {
	return configuredSharedTreeInternal({
		minVersionForCollab: FluidClientVersion.v2_117,
	}).getFactory();
}

type MapValue = string | number | boolean | null | MapPoint | DynamicMap;
type TaggedValue =
	| { kind: "string"; value: string }
	| { kind: "number"; value: number }
	| { kind: "boolean"; value: boolean }
	| { kind: "null" }
	| { kind: "object"; type: string; fields: [string, TaggedValue][] };

const leafTypes = {
	string: "com.fluidframework.leaf.string",
	number: "com.fluidframework.leaf.number",
	boolean: "com.fluidframework.leaf.boolean",
	null: "com.fluidframework.leaf.null",
} as const;

function copy<T>(value: T): T {
	return JSON.parse(JSON.stringify(value));
}

function caseFile(
	id: typeof requiredMapCases[number],
	domain: string,
	input: object,
	observations: object[],
	raw: object,
) {
	assert(observations.length > 0);
	return { formatVersion, reference, id, domain, input, expected: { observations }, raw };
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
		case "number":
		case "boolean":
			return { type: brand(leafTypes[value.kind]), value: value.value, fields: new Map() };
		case "null":
			return { type: brand(leafTypes.null), value: null, fields: new Map() };
		case "object":
			return {
				type: brand(value.type),
				fields: new Map(value.fields.map(([key, child]) => [brand(key), [mapTree(child)]])),
			};
	}
}

function treeChunk(trees: TaggedValue[]): TreeChunk {
	const cursor = cursorForMapTreeField(trees.map(mapTree));
	return combineChunks(chunkField(cursor, {
		policy: defaultChunkPolicy,
		idCompressor: testIdCompressor,
	}));
}

function makeModularFamily(): {
	readonly family: ModularChangeFamily;
	readonly codecOptions: CodecWriteOptions;
} {
	const codecOptions: CodecWriteOptions = {
		jsonValidator: FormatValidatorBasic,
		minVersionForCollab: FluidClientVersion.v2_117,
	};
	const revisionTagCodec = new RevisionTagCodec(testIdCompressor);
	const fieldBatchCodec = fieldBatchCodecBuilder.build(codecOptions);
	const codecs = makeModularChangeCodecFamily(
		fieldKindConfigurations,
		revisionTagCodec,
		fieldBatchCodec,
		codecOptions,
		TreeCompressionStrategy.Compressed,
	);
	return {
		family: new ModularChangeFamily(fieldKinds, codecs, codecOptions),
		codecOptions,
	};
}

function mapValue(value: MapValue): unknown {
	if (value instanceof MapPoint) {
		return { kind: "object", type: MapPoint.identifier, fields: [["x", value.x], ["y", value.y]] };
	}
	if (value instanceof DynamicMap) {
		return { kind: "map", type: DynamicMap.identifier, entries: [...value].map(([key, item]) =>
			[key, mapValue(item)]) };
	}
	return value;
}

function visible(root: MapRoot) {
	return {
		keys: [...root.items.keys()],
		entries: [...root.items.entries()].map(([key, value]) => [key, mapValue(value)]),
	};
}

function treeMessages(messages: unknown): Record<string, unknown>[] {
	const result: Record<string, unknown>[] = [];
	function visit(value: unknown): void {
		if (Array.isArray(value)) {
			value.forEach(visit);
		} else if (value !== null && typeof value === "object") {
			const object = value as Record<string, unknown>;
			if (object.version === 7 && typeof object.originatorId === "string"
				&& Array.isArray(object.changeset)) {
				result.push(object);
			}
			Object.values(object).forEach(visit);
		}
	}
	visit(messages);
	return result;
}

function modularData(message: Record<string, unknown>): unknown {
	const changeset = message.changeset;
	assert(Array.isArray(changeset) && changeset.length > 0);
	const data = Reflect.get(changeset[0], "data");
	assert(data !== null && typeof data === "object");
	return data;
}

function summaryBlob(summary: { tree: Record<string, unknown> }, ...path: string[]): string {
	let value: unknown = summary;
	for (const key of path) {
		assert(value !== null && typeof value === "object");
		const tree = Reflect.get(value, "tree");
		assert(tree !== null && typeof tree === "object");
		value = Reflect.get(tree, key);
		assert(value !== undefined);
	}
	assert(value !== null && typeof value === "object");
	const content = Reflect.get(value, "content");
	assert(typeof content === "string");
	return content;
}

function managerState(tree: TestTreeProviderLite["trees"][number]) {
	const manager: unknown = Reflect.get(tree.kernel, "editManager");
	assert(manager instanceof EditManager);
	return {
		pending: manager.getLocalCommits("main").map(({ revision }) => revision),
		sequenced: manager.getTrunkCommits("main").map(({ revision }) => revision),
		longestBranchLength: manager.getLongestBranchLength(),
	};
}

function populatedMap() {
	return new DynamicMap([
		["", ""],
		["2", 2],
		["10", true],
		["01", null],
		["__proto__", new MapPoint({ x: 1, y: 2 })],
		["é", new DynamicMap([["nested", "value"]])],
		["水", "水"],
	]);
}

async function schemaContentCase() {
	const treeFactory = sharedTreeFactory();
	const configuration = new TreeViewConfiguration({ schema: MapRoot });
	const emptyProvider = new TestTreeProviderLite(1, treeFactory);
	const emptyView = emptyProvider.trees[0].viewWith(configuration);
	emptyView.initialize(new MapRoot({ items: new DynamicMap([]) }));
	emptyProvider.synchronizeMessages();
	const emptySummary = (await emptyProvider.trees[0].summarize(true)).summary;

	const populatedProvider = new TestTreeProviderLite(1, treeFactory);
	const populatedView = populatedProvider.trees[0].viewWith(configuration);
	populatedView.initialize(new MapRoot({ items: populatedMap() }));
	populatedProvider.synchronizeMessages();
	const populatedSummary = (await populatedProvider.trees[0].summarize(true)).summary;
	const schemas = {
		named: schemaString(NamedMap),
		recursive: schemaString(DynamicMap),
		rootMap: schemaString(DynamicMap),
		objectContainedMap: schemaString(MapRoot),
	};
	const observation = visible(populatedView.root);
	return caseFile("map-schema-content", "schema", {
		profile: { schema: 2, forest: 2 },
		schemas,
		keys: ["", "2", "10", "01", "__proto__", "é", "水"],
		content: {
			empty: emptyProvider.trees[0].contentSnapshot(),
			populated: populatedProvider.trees[0].contentSnapshot(),
		},
	}, [{
		id: "schema-and-content",
		keys: observation.keys,
		entries: observation.entries,
	}], {
		schemas: Object.fromEntries(Object.entries(schemas).map(([key, value]) => [key, {
			bytes: value,
			parsed: JSON.parse(value),
		}])),
		forest: {
			empty: summaryBlob(emptySummary, "indexes", "Forest", "contents"),
			populated: summaryBlob(populatedSummary, "indexes", "Forest", "contents"),
		},
		summaries: { empty: emptySummary, populated: populatedSummary },
	});
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

function tagged(value: string | number | boolean | null | { x: number; y: number } | Map<string, string>): TaggedValue {
	if (value === null) return { kind: "null" };
	if (typeof value === "string") return { kind: "string", value };
	if (typeof value === "number") return { kind: "number", value };
	if (typeof value === "boolean") return { kind: "boolean", value };
	if (value instanceof Map) {
		return {
			kind: "object",
			type: DynamicMap.identifier,
			fields: [...value].map(([key, item]) => [key, tagged(item)]),
		};
	}
	return {
		kind: "object",
		type: MapPoint.identifier,
		fields: [["x", tagged(value.x)], ["y", tagged(value.y)]],
	};
}

function fieldAlgebraCase() {
	const { family, codecOptions } = makeModularFamily();
	const codec = family.codecs.resolve(ModularChangeFormatVersion.v5);
	const revisions = Array.from({ length: 48 }, () => mintRevisionTag());
	let nextRevision = 0;
	const schema = schemaString(MapRoot);
	const encodingContext: ChangeEncodingContext = {
		originatorId: testIdCompressor.localSessionId,
		idCompressor: testIdCompressor,
		revision: undefined,
		isSummary: false,
	};
	const refreshers: Record<string, unknown> = {};

	function edit(
		path: string[],
		value: Parameters<typeof tagged>[0] | undefined,
		wasEmpty: boolean,
	): TaggedChange<ModularChangeset> {
		const revision = revisions[nextRevision++];
		let change: TaggedChange<ModularChangeset> | undefined;
		const editor = new DefaultEditBuilder(family, () => revision, (authored) => {
			assert(change === undefined);
			change = authored;
		}, codecOptions);
		editor.optionalField(fieldPath(path)).set(
			value === undefined ? undefined : treeChunk([tagged(value)]),
			wasEmpty,
		);
		assert(change !== undefined);
		return change;
	}

	function requiredEdit(path: string[], value: Parameters<typeof tagged>[0]) {
		const revision = revisions[nextRevision++];
		let change: TaggedChange<ModularChangeset> | undefined;
		const editor = new DefaultEditBuilder(family, () => revision, (authored) => {
			assert(change === undefined);
			change = authored;
		}, codecOptions);
		editor.valueField(fieldPath(path)).set(treeChunk([tagged(value)]));
		assert(change !== undefined);
		return change;
	}

	function encoded(change: TaggedChange<ModularChangeset>) {
		return codec.encode(change.change, { ...encodingContext, revision: change.revision });
	}

	function stableRevision(revision: RevisionTag | undefined): string | null {
		if (revision === undefined) return null;
		assert(typeof revision === "number");
		return testIdCompressor.decompress(revision);
	}

	function changeEvidence(id: string, change: TaggedChange<ModularChangeset>) {
		const revision = stableRevision(change.revision);
		return {
			id,
			revision,
			encodingContext: {
				originatorId: encodingContext.originatorId,
				revision,
				encodedRevision: change.revision ?? null,
				isSummary: encodingContext.isSummary,
			},
			encoded: encoded(change),
		};
	}

	function root(entries: [string, Parameters<typeof tagged>[0]][]): ForestTaggedValue {
		return {
			kind: "object",
			type: MapRoot.identifier,
			fields: [[
				"items",
				{
					kind: "object",
					type: DynamicMap.identifier,
					fields: entries.map(([key, value]) => [key, tagged(value)]),
				},
			]],
		};
	}

	function visibleState(state: unknown) {
		assert(state !== null && typeof state === "object");
		const root = Reflect.get(state, "root");
		assert(root !== null && typeof root === "object" && Reflect.get(root, "kind") === "object");
		const rootFields = Reflect.get(root, "fields");
		assert(Array.isArray(rootFields));
		const items = rootFields.find(([key]) => key === "items")?.[1];
		assert(items !== null && typeof items === "object" && Reflect.get(items, "kind") === "object");
		const entries = Reflect.get(items, "fields");
		const detached = Reflect.get(state, "detached");
		assert(Array.isArray(entries) && Array.isArray(detached));
		return { entries, detached };
	}

	function scenario(
		id: typeof requiredMapScenarios[number],
		left: TaggedChange<ModularChangeset>,
		initialEntries: [string, Parameters<typeof tagged>[0]][],
		right?: TaggedChange<ModularChangeset>,
		reverseCompose = false,
	) {
		const composeChanges = right === undefined
			? [left]
			: reverseCompose ? [right, left] : [left, right];
		const composed = tagChange(family.compose(composeChanges), undefined);
		const inverseRevision = revisions[nextRevision++];
		const inverted = tagChange(family.invert(composed, false, inverseRevision), inverseRevision);
		const changes = new Map<string, TaggedChange<ModularChangeset>>([
			["left", left],
			["composed", composed],
			["inverted", inverted],
		]);
		const algebra: {
			operation: string;
			output: string;
			changes?: string[];
			change?: string;
			inverseRevision?: string | null;
			over?: string;
			revisionMetadata?: { revision: string | null }[];
		}[] = [
			{
				operation: "compose",
				changes: right === undefined
					? ["left"]
					: reverseCompose ? ["right", "left"] : ["left", "right"],
				output: "composed",
			},
			{
				operation: "invert",
				change: "composed",
				inverseRevision: stableRevision(inverseRevision),
				output: "inverted",
			},
		];
		const replays = new Map<string, string[]>([
			["compose", ["composed"]],
			["invert", ["composed", "inverted"]],
		]);
		let detachedIdentity: object[] | undefined;
		if (right !== undefined) {
			assert(left.revision !== undefined && right.revision !== undefined);
			changes.set("right", right);
			const revisionMetadata = [
				{ revision: left.revision },
				{ revision: right.revision },
			];
			const metadata = revisionMetadataSourceFromInfo(revisionMetadata);
			const leftOverRight = tagChange(
				family.rebase(left, right, metadata),
				left.revision,
			);
			const rightOverLeft = tagChange(
				family.rebase(right, left, metadata),
				right.revision,
			);
			changes.set("left-over-right", leftOverRight);
			changes.set("right-over-left", rightOverLeft);
			const normalizedMetadata = revisionMetadata.map(({ revision }) => ({
				revision: stableRevision(revision),
			}));
			algebra.push(
				{
					operation: "rebase-left-over-right",
					change: "left",
					over: "right",
					revisionMetadata: normalizedMetadata,
					output: "left-over-right",
				},
				{
					operation: "rebase-right-over-left",
					change: "right",
					over: "left",
					revisionMetadata: normalizedMetadata,
					output: "right-over-left",
				},
			);
			replays.set("rebase-left-over-right", ["right", "left-over-right"]);
			replays.set("rebase-right-over-left", ["left", "right-over-left"]);
			if (id === "nested-edit-vs-replace" || id === "nested-edit-vs-delete") {
				const roots = [...relevantRemovedRoots(leftOverRight.change)];
				assert(roots.length > 0);
				detachedIdentity = roots.map((root) => {
					assert(root.major !== "root");
					return {
						revision: root.major === undefined ? null : testIdCompressor.decompress(root.major),
						localId: root.minor,
					};
				});
				refreshers[id] = codec.encode(updateRefreshers(
					leftOverRight.change,
					() => treeChunk([tagged({ x: 1, y: 2 })]),
					roots,
				), { ...encodingContext, revision: leftOverRight.revision });
			}
		}
		const initial = { schema, root: root(initialEntries) };
		const decoder = schemaCodecBuilder.buildDecoder({ jsonValidator: FormatValidatorNoOp });
		const intermediate = algebra.map((operation) => {
			const replay = replays.get(operation.operation);
			assert(replay !== undefined);
			const definition: ForestScenario = {
				id: `${id}-${operation.operation}`,
				...initial,
				actions: [
					{ id: "initial", op: "observe" },
					...replay.map((name) => {
						const change = changes.get(name);
						assert(change !== undefined);
						return {
							id: name,
							op: "apply" as const,
							delta: deltaDataWithCompressor(
								intoDelta(change),
								change.revision,
								testIdCompressor,
							),
						};
					}),
				],
			};
			const result = runScenario(definition, testIdCompressor, decoder);
			assert(result.observation.checkpoints.every(({ accepted }) => accepted));
			const checkpoints = result.observation.checkpoints.map((checkpoint) => {
				assert(checkpoint.state !== null);
				return { id: checkpoint.id, visible: visibleState(checkpoint.state) };
			});
			return {
				operation: operation.operation,
				encoded: encoded(changes.get(operation.output) ?? assert.fail()),
				checkpoints,
				final: checkpoints.at(-1)?.visible ?? assert.fail(),
				raw: result.raw,
			};
		});
		const initialVisible = intermediate[0].checkpoints[0].visible;
		const final = intermediate.find(({ operation }) => operation === "compose")?.final;
		assert(final !== undefined);
		const fieldKinds: string[] = [];
		const fieldKeys: string[] = [];
		function collect(value: unknown): void {
			if (Array.isArray(value)) {
				value.forEach(collect);
			} else if (value !== null && typeof value === "object") {
				const object = value as Record<string, unknown>;
				if (typeof object.fieldKind === "string") fieldKinds.push(object.fieldKind);
				if (typeof object.fieldKey === "string") fieldKeys.push(object.fieldKey);
				Object.values(object).forEach(collect);
			}
		}
	const normalizedChanges = [...changes].map(([name, change]) => changeEvidence(name, change));
	const compressor = {
		localSessionId: testIdCompressor.localSessionId,
		revisions: normalizedChanges
			.filter(({ revision }) => revision !== null)
			.map(({ revision, encodingContext: { encodedRevision } }) => ({
				stable: revision,
				encoded: encodedRevision,
			})),
	};
	collect(normalizedChanges);
	assert(!fieldKinds.includes("Sequence"));
	return {
		input: {
			id,
			initial,
			compressor,
			changes: normalizedChanges,
			operations: algebra.map(({ operation }) => operation),
			algebra,
			finalOperation: "compose",
		},
		observation: {
			id,
			initial: initialVisible,
			intermediate: intermediate.map(({ raw: _raw, ...item }) => item),
			final,
			...(detachedIdentity === undefined ? {} : { detachedIdentity }),
		},
		raw: {
			id,
			changes: Object.fromEntries(normalizedChanges.map((change) => [change.id, {
				revision: change.revision,
				encodingContext: change.encodingContext,
				encoded: change.encoded,
			}])),
			operations: intermediate.map(({ operation, raw }) => ({ operation, ...raw })),
			fieldKeys,
			fieldKinds,
		},
	};
	}

	const scenarios = [
	scenario("set-absent", edit(["items", "new"], "value", true), []),
	scenario("replace-present", edit(["items", "key"], "after", false), [["key", "before"]]),
	scenario("delete-present", edit(["items", "key"], undefined, false), [["key", "before"]]),
	scenario("delete-absent", edit(["items", "missing"], undefined, true), []),
	scenario("different-keys",
		edit(["items", "left"], "left", true),
		[],
		edit(["items", "right"], "right", true)),
	scenario("same-key-set-set-left-last",
		edit(["items", "same"], "left", true),
		[],
		edit(["items", "same"], "right", true),
		true),
	scenario("same-key-set-set-right-last",
		edit(["items", "same"], "left", true),
		[],
		edit(["items", "same"], "right", true)),
	scenario("same-key-set-delete",
		edit(["items", "same"], "left", false),
		[["same", "before"]],
		edit(["items", "same"], undefined, false)),
	scenario("same-key-delete-set",
		edit(["items", "same"], undefined, false),
		[["same", "before"]],
		edit(["items", "same"], "right", false)),
	scenario("nested-edit-vs-replace",
		requiredEdit(["items", "point", "x"], 7),
		[["point", { x: 1, y: 2 }]],
		edit(["items", "point"], { x: 10, y: 20 }, false)),
	scenario("nested-edit-vs-delete",
		requiredEdit(["items", "point", "x"], 7),
		[["point", { x: 1, y: 2 }]],
		edit(["items", "point"], undefined, false)),
	scenario("nested-map-independent",
		edit(["items", "nested", "left"], "left", true),
		[["nested", new Map<string, string>()]],
		edit(["items", "nested", "right"], "right", true)),
	scenario("nested-map-conflict",
		edit(["items", "nested", "same"], "left", true),
		[["nested", new Map<string, string>()]],
		edit(["items", "nested", "same"], "right", true)),
	];
	return {
	oracleCase: caseFile("map-field-algebra", "field", {
		profile: { modularChange: 5, optionalField: 2, genericField: 1 },
		schema,
		scenarios: scenarios.map((item) => item.input),
	}, scenarios.map((item) => item.observation), {
		scenarios: scenarios.map((item) => item.raw),
	}),
		refreshers,
	};
}

async function historyCodecsCase(refreshers: Record<string, unknown>) {
	const treeFactory = sharedTreeFactory();
	const configuration = new TreeViewConfiguration({ schema: MapRoot });
	const provider = new TestTreeProviderLite(2, treeFactory);
	const messages: unknown[] = [];
	for (const [index, tree] of provider.trees.entries()) {
		const runtime = tree.containerRuntime;
		assert(runtime instanceof MockContainerRuntimeWithOpBunching);
		const process = runtime.process.bind(runtime);
		runtime.process = (message) => {
			if (index === 0) messages.push(copy(message));
			process(message);
		};
		const processMessages = runtime.processMessages.bind(runtime);
		runtime.processMessages = (batch) => {
			if (index === 0) messages.push(...copy(batch));
			processMessages(batch);
		};
	}
	const first = provider.trees[0].viewWith(configuration);
	first.initialize(new MapRoot({ items: new DynamicMap([["key", "before"]]) }));
	provider.synchronizeMessages();
	const second = provider.trees[1].viewWith(configuration);
	const initialSummary = (await provider.trees[0].summarize(true)).summary;

	const messageStart = messages.length;
	first.root.items.set("set", "value");
	provider.synchronizeMessages();
	const setMessage = treeMessages(messages.slice(messageStart)).at(-1);
	assert(setMessage !== undefined);

	const replaceStart = messages.length;
	first.root.items.set("key", new MapPoint({ x: 1, y: 2 }));
	provider.synchronizeMessages();
	const replacementMessage = treeMessages(messages.slice(replaceStart)).at(-1);
	assert(replacementMessage !== undefined);
	const afterReplacement = copy(provider.trees[0].contentSnapshot());

	const deleteStart = messages.length;
	first.root.items.delete("key");
	provider.synchronizeMessages();
	const deleteMessage = treeMessages(messages.slice(deleteStart)).at(-1);
	assert(deleteMessage !== undefined);
	const afterDeletion = copy(provider.trees[0].contentSnapshot());

	const runtime = provider.trees[0].containerRuntime;
	first.root.items.set("replace-on-reconnect", "before");
	first.root.items.set("delete-on-reconnect", "before");
	provider.synchronizeMessages();
	runtime.connected = false;
	first.root.items.set("replace-on-reconnect", new DynamicMap([["inner", "pending"]]));
	first.root.items.delete("delete-on-reconnect");
	second.root.items.set("remote-crossing", "sequenced");
	provider.synchronizeMessages();
	const pending = managerState(provider.trees[0]);
	const reconnectStart = messages.length;
	runtime.connected = true;
	provider.synchronizeMessages();
	const localSession = provider.getCompressor(provider.trees[0]).localSessionId;
	const reconnectMessages = treeMessages(messages.slice(reconnectStart))
		.filter((message) => message.originatorId === localSession);
	assert.equal(reconnectMessages.length, 2);
	const sequenced = managerState(provider.trees[0]);

	second.root.items.set("nested", new DynamicMap([["before", "value"]]));
	provider.synchronizeMessages();
	const nested = second.root.items.get("nested");
	assert(nested instanceof DynamicMap);
	nested.set("after", "continued");
	provider.synchronizeMessages();
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
	const reloadedTree = await treeFactory.load(
		reloadRuntime,
		"watershed-map-reload",
		reloadServices,
		treeFactory.attributes,
	);
	const reloadedView = reloadedTree.viewWith(configuration);
	reloadedView.root.items.set("after-reload", true);
	const afterReload = visible(reloadedView.root);
	assert("contentSnapshot" in reloadedTree && typeof reloadedTree.contentSnapshot === "function");

	const messageBytes = {
		set: JSON.stringify(setMessage),
		replacement: JSON.stringify(replacementMessage),
		delete: JSON.stringify(deleteMessage),
	};
	const modularBytes = {
		map: JSON.stringify(modularData(setMessage)),
		nestedMap: JSON.stringify(modularData(treeMessages(messages).at(-1) ?? {})),
	};
	return caseFile("map-history-codecs", "codec", {
		profile: {
			message: 7,
			sharedTreeChange: 5,
			modularChange: 5,
			optionalField: 2,
			genericField: 1,
			fieldBatch: 2,
			schema: 2,
			forest: 2,
			detachedFieldIndex: 2,
			editManager: 7,
		},
		actions: ["set", "replacement", "delete", "disconnect", "pending-set", "reconnect", "reload-edit"],
		messageBytes,
		modularBytes,
		history: { pending, sequenced },
	}, [
		{ id: "messages", versions: [setMessage.version, replacementMessage.version, deleteMessage.version] },
		{ id: "history", pending, sequenced },
		{ id: "detached-after-replacement", value: afterReplacement.removed },
		{ id: "detached-after-deletion", value: afterDeletion.removed },
		{ id: "reconnect-resubmission", bytes: reconnectMessages.map((message) => JSON.stringify(message)) },
		{ id: "refreshers-after-replacement", value: refreshers["nested-edit-vs-replace"] },
		{ id: "refreshers-after-deletion", value: refreshers["nested-edit-vs-delete"] },
		{ id: "reload-and-edit", value: afterReload },
	], {
		messages: { set: setMessage, replacement: replacementMessage, delete: deleteMessage },
		modular: {
			map: modularData(setMessage),
			nestedMap: modularData(treeMessages(messages).at(-1) ?? {}),
		},
		detached: { afterReplacement, afterDeletion },
		reconnect: reconnectMessages,
		refreshers: {
			replacement: refreshers["nested-edit-vs-replace"],
			deletion: refreshers["nested-edit-vs-delete"],
		},
		summary: {
			bytes: JSON.stringify(settledSummary),
			value: settledSummary,
			schema: summaryBlob(settledSummary, "indexes", "Schema", "SchemaString"),
			forest: summaryBlob(settledSummary, "indexes", "Forest", "contents"),
			detached: summaryBlob(
				settledSummary,
				"indexes",
				"DetachedFieldIndex",
				"DetachedFieldIndexBlob",
			),
			history: summaryBlob(settledSummary, "indexes", "EditManager", "String"),
		},
		initialSummary,
		reload: {
			compressor,
			afterEdit: copy(reloadedTree.contentSnapshot()),
			messages: reloadMessages,
		},
	});
}

if (process.env.WATERSHED_ORACLE_CORPUS === "map") {
	describe("Watershed dynamic map oracle", () => {
		it("records schema, algebra, history, codec, and reload evidence", async () => {
			const output = process.env.WATERSHED_ORACLE_OUTPUT;
			assert(output !== undefined && isAbsolute(output));
			assert.equal(process.env.WATERSHED_ORACLE_COMMIT, reference.commit);
			const algebra = fieldAlgebraCase();
			const cases = [
				await schemaContentCase(),
				algebra.oracleCase,
				await historyCodecsCase(algebra.refreshers),
			];
			assert.deepEqual(cases.map(({ id }) => id), requiredMapCases);
			mkdirSync(output, { recursive: true });
			writeFileSync(join(output, "map-cases.json"), `${JSON.stringify(cases, null, 2)}\n`);
		});
	});
}
