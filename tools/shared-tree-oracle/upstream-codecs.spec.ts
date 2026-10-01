/*!
 * Copyright (c) Microsoft Corporation and contributors. All rights reserved.
 * Licensed under the MIT License.
 */

import { strict as assert } from "node:assert";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

import type {
	IIdCompressor,
	OpSpaceCompressedId,
	SessionSpaceCompressedId,
} from "@fluidframework/id-compressor";
import {
	deserializeIdCompressor,
	serializeIdCompressor,
	type SerializedIdCompressorWithNoSession,
	type SerializedIdCompressorWithOngoingSession,
} from "@fluidframework/id-compressor/internal";
import {
	MockDeltaConnection,
	MockFluidDataStoreRuntime,
	MockSharedObjectServices,
} from "@fluidframework/test-runtime-utils/internal";

import { FluidClientVersion, FormatValidatorNoOp } from "../codec/index.js";
import {
	fieldBatchCodecBuilder,
	cursorForJsonableTreeField,
	jsonableTreeFromFieldCursor,
	schemaCodecBuilder,
	TreeCompressionStrategy,
	type ModularChangeset,
} from "../feature-libraries/index.js";
import { tagChange, type RevisionTag, type TreeStoredSchema } from "../core/index.js";
import { SchemaFactory, TreeViewConfiguration } from "../simple-tree/index.js";
import { configuredSharedTreeInternal } from "../treeFactory.js";
import { makeTestFieldBatchContexts, assertIsSessionId } from "./utils.js";
import { encodeModularGraph, replayArrayModularInput } from "./watershedArraySupport.js";
import { replayForestInput } from "./watershedSequence.spec.js";

const formatVersion = 1;
const reference = {
	package: "@fluidframework/tree",
	version: "3.1.0",
	commit: "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960",
};

type SummaryTree = {
	type: number;
	tree: Record<string, SummaryTree | { type: number; content: string }>;
};

type ArtifactItem = {
	id: string;
	kind: "schema" | "fieldBatch" | "message" | "summary";
	encoded: unknown;
	schemaProfile?: "map" | "array" | "identifier";
	compressor?: string;
	compressorMode?: "ongoing" | "summary";
	session?: string;
	initialSummary?: SummaryTree;
	allocationRanges?: unknown[];
	sequenceNumber?: number;
	referenceSequenceNumber?: number;
	minimumSequenceNumber?: number;
	indexInBatch?: number | null;
	sequencing?: {
		clientId: string;
		clientSequenceNumber: number;
		referenceSequenceNumber: number;
		sequenceNumber: number;
		minimumSequenceNumber: number;
	}[];
	expectedGraphs?: unknown[];
	nativeGraphs?: unknown[];
	features?: string[];
	application?: {
		initialState: unknown;
		retainIndex: number | null;
		retainPath?: unknown;
		identityCandidates?: unknown;
		wrapFieldsAtIndex?: number;
		preludeGraphs: unknown[];
		followOnGraphs: unknown[];
		followOnMessages?: unknown[];
	};
};

type NativeArtifact = {
	formatVersion: number;
	reference: typeof reference;
	target: "erlang" | "javascript";
	items: ArtifactItem[];
};

const profileSchema = new SchemaFactory("org.watershed.shared-tree.m1");
class Point extends profileSchema.object("Point", {
	x: profileSchema.number,
	y: profileSchema.number,
}) {}
class Root extends profileSchema.object("Root", {
	title: profileSchema.string,
	enabled: profileSchema.boolean,
	rating: profileSchema.number,
	marker: profileSchema.null,
	note: profileSchema.optional(profileSchema.string),
	point: Point,
}) {}
const configuration = new TreeViewConfiguration({ schema: Root });
const factory = configuredSharedTreeInternal({
	minVersionForCollab: FluidClientVersion.v2_117,
}).getFactory();

const captionSchema = new SchemaFactory("org.watershed.shared-tree.m1");
class CaptionPoint extends captionSchema.object("Point", {
	x: captionSchema.number,
	y: captionSchema.number,
}) {}
class CaptionRoot extends captionSchema.object("Root", {
	title: captionSchema.string,
	caption: captionSchema.optional(captionSchema.string),
	enabled: captionSchema.boolean,
	rating: captionSchema.number,
	marker: captionSchema.null,
	note: captionSchema.optional(captionSchema.string),
	point: CaptionPoint,
}) {}
const captionConfiguration = new TreeViewConfiguration({ schema: CaptionRoot });

const detailsSchema = new SchemaFactory("org.watershed.shared-tree.m1");
class DetailsPoint extends detailsSchema.object("Point", {
	x: detailsSchema.number,
	y: detailsSchema.number,
}) {}
class DetailsRoot extends detailsSchema.object("Root", {
	title: detailsSchema.string,
	caption: detailsSchema.optional(detailsSchema.string),
	details: detailsSchema.optional(detailsSchema.string),
	enabled: detailsSchema.boolean,
	rating: detailsSchema.number,
	marker: detailsSchema.null,
	note: detailsSchema.optional(detailsSchema.string),
	point: DetailsPoint,
}) {}
const detailsConfiguration = new TreeViewConfiguration({ schema: DetailsRoot });

const mapSchema = new SchemaFactory("org.watershed.shared-tree.m2");
class MapPoint extends mapSchema.object("Point", {
	x: mapSchema.number,
	y: mapSchema.number,
}) {}
class DynamicMap extends mapSchema.mapRecursive("DynamicMap", [
	mapSchema.string,
	mapSchema.number,
	mapSchema.boolean,
	mapSchema.null,
	MapPoint,
	() => DynamicMap,
]) {}
class MapRoot extends mapSchema.object("Root", { items: DynamicMap }) {}
const mapConfiguration = new TreeViewConfiguration({ schema: MapRoot });
const mapTreeFactory = configuredSharedTreeInternal({
	minVersionForCollab: FluidClientVersion.v2_117,
}).getFactory();

const arraySchema = new SchemaFactory("org.watershed.shared-tree.m3");
class ArrayPoint extends arraySchema.object("Point", {
	label: arraySchema.string,
	x: arraySchema.number,
}) {}
class Items extends arraySchema.arrayRecursive("Items", [
	arraySchema.string,
	arraySchema.number,
	arraySchema.boolean,
	arraySchema.null,
	ArrayPoint,
	() => Items,
	() => ArrayMap,
]) {}
class ArrayMap extends arraySchema.mapRecursive("ArrayMap", [
	arraySchema.string,
	arraySchema.number,
	arraySchema.boolean,
	arraySchema.null,
	ArrayPoint,
	() => Items,
	() => ArrayMap,
]) {}
class Points extends arraySchema.array("Points", ArrayPoint) {}
class ArrayRoot extends arraySchema.object("Root", {
	left: Items,
	right: Items,
	byKey: ArrayMap,
	narrow: Points,
}) {}
const arrayConfiguration = new TreeViewConfiguration({ schema: ArrayRoot });
const arrayTreeFactory = configuredSharedTreeInternal({
	minVersionForCollab: FluidClientVersion.v2_117,
}).getFactory();

const identifierSchema = new SchemaFactory("org.watershed.shared-tree.identifiers");
class IdentifierPoint extends identifierSchema.object("Point", {
	id: identifierSchema.identifier,
	label: identifierSchema.string,
}) {}
class IdentifierPair extends identifierSchema.object("Pair", {
	firstId: identifierSchema.identifier,
	secondId: identifierSchema.identifier,
	label: identifierSchema.string,
	pairOnly: identifierSchema.string,
}) {}
class IdentifierItems extends identifierSchema.array("Items", [IdentifierPoint, IdentifierPair]) {}
class IdentifierMap extends identifierSchema.map("PointsByKey", [IdentifierPoint, IdentifierPair]) {}
class IdentifierRoot extends identifierSchema.object("Root", {
	child: IdentifierPoint,
	left: IdentifierItems,
	right: IdentifierItems,
	byKey: IdentifierMap,
}) {}
const identifierConfiguration = new TreeViewConfiguration({ schema: IdentifierRoot });
const identifierTreeFactory = configuredSharedTreeInternal({
	minVersionForCollab: FluidClientVersion.v2_117,
}).getFactory();

function factoryFor(item: ArtifactItem) {
	return item.schemaProfile === "map"
		? mapTreeFactory
		: item.schemaProfile === "array"
			? arrayTreeFactory
			: item.schemaProfile === "identifier"
				? identifierTreeFactory
				: factory;
}

function compressor(item: ArtifactItem): IIdCompressor {
	assert(typeof item.compressor === "string" && item.compressor.length > 0,
		`${item.id}: missing compressor`);
	if (item.compressorMode === "summary") {
		assert(typeof item.session === "string", `${item.id}: missing compressor session`);
		return deserializeIdCompressor(
			item.compressor as SerializedIdCompressorWithNoSession,
			assertIsSessionId(item.session),
		);
	}
	assert.equal(item.compressorMode, "ongoing", `${item.id}: compressor mode`);
	return deserializeIdCompressor(item.compressor as SerializedIdCompressorWithOngoingSession);
}

function services(summary: Parameters<typeof MockSharedObjectServices.createFromSummary>[0]) {
	const value = MockSharedObjectServices.createFromSummary(summary);
	value.deltaConnection = new MockDeltaConnection(() => 1, () => {});
	return value;
}

async function loadSummary(item: ArtifactItem, idCompressor = compressor(item)) {
	assert(item.encoded !== null && typeof item.encoded === "object",
		`${item.id}: summary encoding`);
	const runtime = new MockFluidDataStoreRuntime({ idCompressor });
	const selectedFactory = factoryFor(item);
	return selectedFactory.load(
		runtime,
		`codec-${item.id}`,
		services(
			item.encoded as Parameters<typeof MockSharedObjectServices.createFromSummary>[0],
		),
		selectedFactory.attributes,
	);
}

function mapValue(value: unknown): unknown {
	if (value instanceof MapPoint) {
		return { x: value.x, y: value.y };
	}
	if (value instanceof DynamicMap) {
		return Object.fromEntries([...value].map(([key, item]) => [key, mapValue(item)]));
	}
	return value;
}

function visibleMap(root: MapRoot | undefined) {
	if (root === undefined) return null;
	return Object.fromEntries(
		[...root.items].map(([key, value]) => [key, mapValue(value)]),
	);
}

function visibleRoot(root: Root | undefined) {
	if (root === undefined) return null;
	return {
		title: root.title,
		enabled: root.enabled,
		rating: root.rating,
		marker: root.marker,
		note: root.note,
		point: { x: root.point.x, y: root.point.y },
	};
}

function arrayValue(value: unknown): unknown {
	if (value instanceof ArrayPoint) return { point: { label: value.label, x: value.x } };
	if (value instanceof Items || value instanceof Points) {
		return Array.from({ length: value.length }, (_, index) => arrayValue(value[index]));
	}
	if (value instanceof ArrayMap) {
		return { map: [...value].map(([key, item]) => [key, arrayValue(item)]) };
	}
	return value;
}

function visibleArray(root: ArrayRoot | undefined) {
	if (root === undefined) return null;
	return {
		left: arrayValue(root.left),
		right: arrayValue(root.right),
		byKey: arrayValue(root.byKey),
		narrow: arrayValue(root.narrow),
	};
}

function visibleIdentifier(root: IdentifierRoot | undefined) {
	const value = (item: IdentifierPoint | IdentifierPair): unknown =>
		item instanceof IdentifierPair
			? {
					firstId: item.firstId,
					secondId: item.secondId,
					label: item.label,
					pairOnly: item.pairOnly,
				}
			: { id: item.id, label: item.label };
	return root === undefined ? null : {
		child: value(root.child),
		left: [...root.left].map(value),
		right: [...root.right].map(value),
		byKey: [...root.byKey].map(([key, item]) => [key, value(item)]),
	};
}

function continueArray(root: ArrayRoot) {
	assert(root.left.length >= 2, "Array continuation needs two source items");
	const first = root.left[0];
	const second = root.left[1];
	const destination = root.right.length;
	root.right.moveRangeToEnd(0, 2, root.left);
	const rangeMoveIdentity =
		root.right[destination] === first && root.right[destination + 1] === second;
	const point = [...root.left, ...root.right].find((value) => value instanceof ArrayPoint);
	assert(point instanceof ArrayPoint, "Array continuation needs a nested point");
	point.label = "upstream-nested";
	return {
		rangeMoveIdentity,
		nestedEdit: point.label,
		visible: visibleArray(root),
	};
}

function decodedGraphs(decoded: unknown, id: string): unknown[] {
	assert(decoded !== null && typeof decoded === "object", `${id}: decoded message`);
	const commit = Reflect.get(decoded, "commit") as {
		change?: { changes?: readonly { type?: unknown; innerChange?: unknown }[] };
	};
	return (commit.change?.changes ?? [])
		.filter(({ type }) => type === "data")
		.map(({ innerChange }) => encodeModularGraph(innerChange as ModularChangeset));
}

function normalizeGraphRevisions(value: unknown, idCompressor: IIdCompressor): unknown {
	if (Array.isArray(value)) {
		return value.map((child) => normalizeGraphRevisions(child, idCompressor));
	}
	if (value === null || typeof value !== "object") return value;
	return Object.fromEntries(
		Object.entries(value).map(([key, child]) => [
			key,
			(key === "revision" || key === "rollbackOf") && typeof child === "number"
				? idCompressor.decompress(child as SessionSpaceCompressedId)
				: normalizeGraphRevisions(child, idCompressor),
		]),
	);
}

function assertAdvancedGraphs(
	actual: unknown[],
	expected: unknown[],
	native: unknown[],
	idCompressor: IIdCompressor,
	id: string,
): void {
	const normalized = normalizeGraphRevisions(actual, idCompressor);
	assert.deepEqual(
		normalized,
		normalizeGraphRevisions(expected, idCompressor),
		`${id}: decoded modular graphs match source expectations`,
	);
	assert.deepEqual(
		normalized,
		normalizeGraphRevisions(native, idCompressor),
		`${id}: decoded modular graphs match native graphs`,
	);
}

function graphRecord(graphs: unknown[], id: string): Record<string, unknown> {
	const messages = graphs[0];
	assert(Array.isArray(messages), `${id}: first graph message`);
	const graph = messages[0];
	assert(graph !== null && typeof graph === "object" && !Array.isArray(graph),
		`${id}: first modular graph`);
	return graph as Record<string, unknown>;
}

function graphRevisions(value: unknown): number[] {
	if (Array.isArray(value)) return value.flatMap(graphRevisions);
	if (value === null || typeof value !== "object") return [];
	return Object.entries(value).flatMap(([key, child]) =>
		key === "revision" && typeof child === "number"
			? [child]
			: graphRevisions(child));
}

function assertAdvancedGraphRegressions(
	actual: unknown[],
	item: ArtifactItem,
	idCompressor: IIdCompressor,
): void {
	assert(Array.isArray(item.expectedGraphs), `${item.id}: expected graph regressions`);
	assert(Array.isArray(item.nativeGraphs), `${item.id}: native graph regressions`);
	const expectedGraphs = item.expectedGraphs;
	const nativeGraphs = item.nativeGraphs;
	const rejects = (
		mutate: (graph: Record<string, unknown>) => void,
		label: string,
	) => {
		const expected = structuredClone(expectedGraphs);
		const native = structuredClone(nativeGraphs);
		mutate(graphRecord(expected, `${item.id}: ${label} expected`));
		mutate(graphRecord(native, `${item.id}: ${label} native`));
		assert.throws(
			() => assertAdvancedGraphs(actual, expected, native, idCompressor, item.id),
			`${item.id}: ${label} corruption must reject`,
		);
	};
	if (item.id === "message-array-advanced-rename") {
		rejects((graph) => {
			delete graph.nodes;
			delete graph.parents;
		}, "node and parent tables");
		rejects((graph) => {
			assert(Array.isArray(graph.nodes) && graph.nodes.length > 0,
				`${item.id}: node table`);
			graph.nodes.pop();
		}, "node table");
		rejects((graph) => {
			assert(Array.isArray(graph.parents) && graph.parents.length > 0,
				`${item.id}: parent table`);
			graph.parents.pop();
		}, "parent table");
		rejects((graph) => {
			assert(Array.isArray(graph.revisions) && graph.revisions.length > 0,
				`${item.id}: revision table`);
			const revision = graph.revisions[0] as Record<string, unknown>;
			const otherRevision = graphRevisions(graph.fields)
				.find((candidate) => candidate !== revision.revision);
			assert(otherRevision !== undefined, `${item.id}: distinct revision identity`);
			revision.revision = otherRevision;
		}, "revision identity");
	}
	if (item.id === "message-array-advanced-move-in-remove") {
		rejects((graph) => {
			assert(Array.isArray(graph.crossFieldKeys) && graph.crossFieldKeys.length > 0,
				`${item.id}: ownership table`);
			const counted = graph.crossFieldKeys.find((entry) =>
				typeof entry === "object" && entry !== null && Reflect.get(entry, "count") === 2);
			assert(counted !== undefined, `${item.id}: counted ownership`);
			Reflect.set(counted, "count", 1);
		}, "ownership count");
		rejects((graph) => {
			assert(Array.isArray(graph.crossFieldKeys) && graph.crossFieldKeys.length > 0,
				`${item.id}: ownership table`);
			const ownership = graph.crossFieldKeys[0];
			assert(ownership !== null && typeof ownership === "object",
				`${item.id}: ownership entry`);
			Reflect.set(
				ownership,
				"target",
				Reflect.get(ownership, "target") === "source" ? "destination" : "source",
			);
		}, "ownership");
	}
}

function advancedEffect(
	decodedMessages: unknown[],
	idCompressor: IIdCompressor,
	item: ArtifactItem,
) {
	const decoded = decodedMessages[0];
	assert(decoded !== null && typeof decoded === "object", `${item.id}: decoded message`);
	const commit = Reflect.get(decoded, "commit") as {
		revision?: RevisionTag;
		change?: { changes?: readonly { type?: unknown; innerChange?: unknown }[] };
	};
	const data = (commit.change?.changes ?? []).find(({ type }) => type === "data");
	assert(data?.innerChange !== undefined && commit.revision !== undefined,
		`${item.id}: advanced data change`);
	const graph = encodeModularGraph(data.innerChange as ModularChangeset);
	assert(item.application !== undefined, `${item.id}: application context`);
	const sessionGraph = (value: unknown): unknown => {
		if (Array.isArray(value)) return value.map(sessionGraph);
		if (value === null || typeof value !== "object") return value;
		return Object.fromEntries(
			Object.entries(value).map(([key, child]) => [
				key,
				key === "revision" && typeof child === "number" && child < 0
					? Number(idCompressor.normalizeToSessionSpace(
							child as OpSpaceCompressedId,
							idCompressor.localSessionId,
						))
					: sessionGraph(child),
			]),
		);
	};
	const followOnGraphs = decodedMessages.slice(1).map((message) => {
		const graphs = decodedGraphs(message, `${item.id}: follow-on`);
		assert.equal(graphs.length, 1, `${item.id}: one follow-on graph`);
		return graphs[0];
	});
	assert.equal(
		followOnGraphs.length,
		item.application.followOnGraphs.length,
		`${item.id}: follow-on wire count`,
	);
	const forestDelta = (value: unknown): unknown => {
		if (Array.isArray(value)) return value.map(forestDelta);
		if (value === null || typeof value !== "object") return value;
		if (Object.hasOwn(value, "revision") && Object.hasOwn(value, "localId")) {
			return {
				major: Reflect.get(value, "revision"),
				minor: Reflect.get(value, "localId"),
			};
		}
		return Object.fromEntries(
			Object.entries(value)
				.filter(([key, child]) =>
					!((key === "attach" || key === "detach") && child === null)
					&& !(key === "fields" && Array.isArray(child) && child.length === 0))
				.map(([key, child]) => [key, forestDelta(child)]),
		);
	};
	const deltaForGraph = (plainGraph: unknown) => {
		const candidate = plainGraph as {
			maxLocalId: number;
			revisions: { revision: number }[];
		};
		const revisions = candidate.revisions.map(({ revision }) => ({
			encoded: revision,
			stable: idCompressor.decompress(revision as SessionSpaceCompressedId),
		}));
		const sourceReplay = replayArrayModularInput({
			operation: "compose",
			initialState: {},
			operands: {
				changes: [{
					revision: candidate.revisions[0]?.revision ?? Number(commit.revision),
					change: plainGraph,
				}],
			},
			revisions,
			allocator: { maxLocalId: candidate.maxLocalId },
			compressor: {
				sessionId: idCompressor.localSessionId,
				serialized: serializeIdCompressor(idCompressor, true),
			},
			sequencing: { minimumSequenceNumber: 0, sequenceNumber: 0 },
		}) as { delta: { fields?: unknown[] } };
		const normalized = forestDelta(sourceReplay.delta) as { fields?: unknown[] };
		const index = item.application?.wrapFieldsAtIndex;
		return index === undefined
			? normalized
			: {
					...normalized,
					fields: [[
						"rootFieldKey",
						{
							marks: [
								...(index === 0 ? [] : [{ count: index }]),
								{ count: 1, fields: normalized.fields },
							],
						},
					]],
				};
	};
	const applicationGraphs = [
		...item.application.preludeGraphs,
		sessionGraph(graph),
		...followOnGraphs.map(sessionGraph),
	] as {
		revisions: { revision: number }[];
	}[];
	const deltas = applicationGraphs.map(deltaForGraph);
	const revisionNumbers = new Set(
		applicationGraphs.flatMap((candidate) =>
			candidate.revisions.map(({ revision }) => revision)),
	);
	const checkpoint = replayForestInput({
		operation: "apply-deltas",
		initialState: item.application.initialState,
		operands: {
			deltas,
			retainIndex: item.application.retainIndex,
			retainPath: item.application.retainPath ?? null,
			identityCandidates: item.application.identityCandidates ?? [],
		},
		revisions: [...revisionNumbers].map((revision) => ({
			encoded: revision,
			stable: idCompressor.decompress(revision as SessionSpaceCompressedId),
		})),
		compressor: {
			session: idCompressor.localSessionId,
			serialized: serializeIdCompressor(idCompressor, true),
		},
	}) as { before: unknown; result: { accepted: boolean }; after: unknown }[];
	const effectIndex = item.application.preludeGraphs.length;
	const effect = checkpoint[effectIndex];
	assert(effect !== undefined, `${item.id}: effect checkpoint`);
	assert.equal(effect.result.accepted, true, `${item.id}: effect accepted`);
	assert.notDeepEqual(
		effect.after,
		effect.before,
		`${item.id}: effect changed source forest or detached state`,
	);
	const followOn = checkpoint.at(-1);
	if (item.application.followOnGraphs.length > 0) {
		assert(followOn !== undefined, `${item.id}: follow-on checkpoint`);
		assert.equal(followOn.result.accepted, true, `${item.id}: follow-on accepted`);
		assert.notDeepEqual(
			followOn.after,
			effect.after,
			`${item.id}: follow-on depends on affected state`,
		);
	}
	return {
		effect,
		...(item.application.followOnGraphs.length === 0 ? {} : { followOn }),
	};
}

function stableRevision(idCompressor: IIdCompressor, revision: unknown): string {
	if (revision === "root") return revision;
	assert(typeof revision === "number", "Revision must be a compressed ID or root");
	return idCompressor.decompress(revision as SessionSpaceCompressedId);
}

const historicalSchemaCodec = schemaCodecBuilder.build({
	jsonValidator: FormatValidatorNoOp,
	minVersionForCollab: FluidClientVersion.v2_117,
});

function historicalSchemaChange(value: unknown, id: string, location: string) {
	const change = asObject(value, `${id}: ${location} schema change`);
	const schemas = asObject(change.schema, `${id}: ${location} schemas`);
	return {
		schema: {
			new: historicalSchemaCodec.encode(schemas.new as TreeStoredSchema),
			old: historicalSchemaCodec.encode(schemas.old as TreeStoredSchema),
		},
		isInverse: change.isInverse,
	};
}

function historyChanges(commit: Record<string, unknown>, id: string, location: string) {
	const change = asObject(commit.change, `${id}: ${location} change`);
	assert(Array.isArray(change.changes), `${id}: ${location} changes`);
	return change.changes.map((value, index) => {
		const entry = asObject(value, `${id}: ${location} change ${index}`);
		return {
			type: entry.type,
			data: entry.type === "data"
				? encodeModularGraph(entry.innerChange as ModularChangeset)
				: historicalSchemaChange(entry.innerChange, id, `${location} change ${index}`),
		};
	});
}

function summaryHistory(
	tree: unknown,
	idCompressor: IIdCompressor,
	id: string,
	includeChanges = false,
) {
	const kernel: unknown = Reflect.get(tree as object, "kernel");
	assert(kernel !== null && typeof kernel === "object", `${id}: missing kernel`);
	const manager: unknown = Reflect.get(kernel, "editManager");
	assert(manager !== null && typeof manager === "object", `${id}: missing edit manager`);
	const getSummaryData: unknown = Reflect.get(manager, "getSummaryData");
	assert(typeof getSummaryData === "function", `${id}: missing summary history`);
	const data = asObject(getSummaryData.call(manager), `${id}: summary history`);
	const main = asObject(data.main, `${id}: main history`);
	assert(Array.isArray(main.trunk), `${id}: trunk history`);
	assert(main.peerLocalBranches instanceof Map, `${id}: peer history`);
	const trunk = main.trunk.map((value, index) => {
		const commit = asObject(value, `${id}: trunk commit ${index}`);
		assert(typeof commit.sessionId === "string", `${id}: trunk session ${index}`);
		assert(Number.isSafeInteger(commit.sequenceNumber), `${id}: trunk sequence ${index}`);
		return {
			revision: stableRevision(idCompressor, commit.revision),
			session: commit.sessionId,
			sequenceNumber: commit.sequenceNumber,
			indexInBatch: commit.indexInBatch ?? null,
			...(includeChanges ? { changes: historyChanges(commit, id, `trunk commit ${index}`) } : {}),
		};
	});
	const peers = [...main.peerLocalBranches.entries()]
		.map(([session, value], index) => {
			assert(typeof session === "string", `${id}: peer session ${index}`);
			const branch = asObject(value, `${id}: peer branch ${index}`);
			assert(Array.isArray(branch.commits), `${id}: peer commits ${index}`);
			return {
				session,
				base: stableRevision(idCompressor, branch.base),
				revisions: branch.commits.map((entry, commitIndex) => {
					const commit = asObject(entry, `${id}: peer commit ${index}.${commitIndex}`);
					return stableRevision(idCompressor, commit.revision);
				}),
				...(includeChanges
					? {
							commits: branch.commits.map((entry, commitIndex) => {
								const commit = asObject(
									entry,
									`${id}: peer commit ${index}.${commitIndex}`,
								);
								return {
									revision: stableRevision(idCompressor, commit.revision),
									changes: historyChanges(
										commit,
										id,
										`peer commit ${index}.${commitIndex}`,
									),
								};
							}),
						}
					: {}),
			};
		})
		.sort((left, right) => left.session.localeCompare(right.session));
	return { trunk, peers };
}

function removedContent(removed: unknown[], idCompressor: IIdCompressor, id: string) {
	return removed.map((value, index) => {
		assert(Array.isArray(value) && value.length === 3, `${id}: removed entry ${index}`);
		const [major, minor, tree] = value;
		assert(Number.isSafeInteger(minor) && minor >= 0, `${id}: removed minor ${index}`);
		assert(tree !== null && typeof tree === "object", `${id}: removed tree ${index}`);
		return {
			major: stableRevision(idCompressor, major),
			minor,
			tree,
		};
	});
}

async function consume(item: ArtifactItem) {
	switch (item.kind) {
		case "schema": {
			const decoder = schemaCodecBuilder.buildDecoder({ jsonValidator: FormatValidatorNoOp });
			const decoded = decoder.decode(item.encoded as never);
			return {
				id: item.id,
				kind: item.kind,
				nodes: decoded.nodeSchema.size,
				rootKind: String(decoded.rootFieldSchema.kind),
			};
		}
		case "fieldBatch": {
			const idCompressor = item.compressor === undefined
				? makeTestFieldBatchContexts({
						encodeType: TreeCompressionStrategy.Uncompressed,
					})
				: makeTestFieldBatchContexts({
						encodeType: TreeCompressionStrategy.Uncompressed,
						idCompressor: compressor(item),
						isSummary: true,
					});
			const codec = fieldBatchCodecBuilder.build({
				jsonValidator: FormatValidatorNoOp,
				minVersionForCollab: FluidClientVersion.v2_117,
			});
			const decoded = codec.decode(item.encoded as never, idCompressor.decode);
			return {
				id: item.id,
				kind: item.kind,
				fields: decoded.map(jsonableTreeFromFieldCursor),
			};
		}
		case "message": {
			assert(item.initialSummary !== undefined, `${item.id}: missing initial summary`);
			assert(Number.isSafeInteger(item.sequenceNumber)
				&& Number.isSafeInteger(item.referenceSequenceNumber)
				&& Number.isSafeInteger(item.minimumSequenceNumber)
				|| item.schemaProfile === "array" && Array.isArray(item.sequencing),
			`${item.id}: missing sequence metadata`);
			const runtime = new MockFluidDataStoreRuntime({ idCompressor: compressor(item) });
			const idCompressor = runtime.idCompressor;
			assert(idCompressor !== undefined, `${item.id}: runtime compressor`);
			const selectedFactory = factoryFor(item);
			const submitted: unknown[] = [];
			const loadedServices = services(
				item.initialSummary as Parameters<
					typeof MockSharedObjectServices.createFromSummary
				>[0],
			);
			loadedServices.deltaConnection =
				new MockDeltaConnection((message) => submitted.push(message), () => {});
			const tree = await selectedFactory.load(
				runtime,
				`codec-${item.id}`,
				loadedServices,
				selectedFactory.attributes,
			);
			const kernel: unknown = Reflect.get(tree, "kernel");
			assert(kernel !== null && typeof kernel === "object", `${item.id}: missing kernel`);
			const messageCodec: unknown = Reflect.get(kernel, "messageCodec");
			assert(messageCodec !== null && typeof messageCodec === "object"
				&& "decode" in messageCodec && typeof messageCodec.decode === "function",
			`${item.id}: missing message codec`);
			const decodeMessage = messageCodec.decode.bind(messageCodec) as (
				value: unknown,
				context: { idCompressor: IIdCompressor },
			) => unknown;
			const process: unknown = Reflect.get(kernel, "processMessagesCore");
			assert(typeof process === "function", `${item.id}: missing process function`);
			if (item.schemaProfile === "array") {
				assert(Array.isArray(item.encoded) && item.encoded.length > 0,
					`${item.id}: array messages`);
				assert(Array.isArray(item.sequencing)
					&& item.sequencing.length >= item.encoded.length,
				`${item.id}: array sequencing`);
				assert(Array.isArray(item.expectedGraphs)
					&& item.expectedGraphs.length === item.encoded.length,
				`${item.id}: native graph evidence`);
				const decoded = item.encoded.map((message) =>
					decodeMessage(message, { idCompressor }));
				const graphs = decoded.map((message) => decodedGraphs(message, item.id));
				const advanced = item.id.startsWith("message-array-advanced-");
				if (advanced) {
					assert(Array.isArray(item.nativeGraphs)
						&& item.nativeGraphs.length === item.encoded.length,
					`${item.id}: native graph evidence`);
					assertAdvancedGraphs(
						graphs,
						item.expectedGraphs,
						item.nativeGraphs,
						idCompressor,
						item.id,
					);
					assertAdvancedGraphRegressions(graphs, item, idCompressor);
					if (
						item.id === "message-array-advanced-aad"
						|| item.id === "message-array-advanced-move-in-remove"
					) {
						assert.notDeepEqual(
							graphs,
							item.expectedGraphs,
							`${item.id}: equivalent revision representations differ before normalization`,
						);
					}
				} else {
					assert.deepEqual(
						graphs,
						item.expectedGraphs,
						`${item.id}: decoded modular graphs`,
					);
				}
				const effect = advanced
					? advancedEffect(decoded, idCompressor, item)
					: undefined;
				if (advanced) {
					const expectedFeatures = {
						"message-array-advanced-rename": [
							"idOverride", "rename", "nestedChanges",
						],
						"message-array-advanced-aad": ["idOverride", "attachAndDetach"],
						"message-array-advanced-move-in-remove": ["finalEndpoint"],
						"message-array-advanced-insert-move-out": ["insertMoveOut"],
						"message-array-advanced-nested": ["nestedChanges"],
					}[item.id];
					assert.deepEqual(item.features, expectedFeatures, `${item.id}: feature list`);
					const graphText = JSON.stringify(graphs);
					const effectText = JSON.stringify(effect);
					for (const feature of item.features ?? []) {
						if (
							feature === "idOverride"
							|| feature === "rename"
							|| feature === "moveInRemove"
						) {
							assert(
								effectText.includes("\"rename\":[{"),
								`${item.id}: decoded ${feature}`,
							);
							continue;
						}
						if (feature === "insertMoveOut") continue;
						const encodedFeature = {
							finalEndpoint: "finalEndpoint",
							attachAndDetach: "\"type\":\"AttachAndDetach\"",
							nestedChanges: "\"nodes\":[[",
						}[feature];
						assert(
							encodedFeature !== undefined && graphText.includes(encodedFeature),
							`${item.id}: decoded ${feature}`,
						);
					}
					assert(effect !== undefined, `${item.id}: source effect`);
					return {
						id: item.id,
						kind: item.kind,
						decoded: true,
						graphs,
						features: item.features,
						effect,
						beforeApply: effect.effect.before,
						afterApply: effect.effect.after,
						continued: effect.followOn?.after ?? effect.effect.after,
						continuation: {
							messages: item.encoded.slice(1).map((message, index) => ({
								encoded: message,
								graphs: graphs[index + 1],
							})),
							compressor: serializeIdCompressor(idCompressor, true),
							session: idCompressor.localSessionId,
						},
					};
				}
				const view = tree.viewWith(arrayConfiguration);
				const beforeApply = visibleArray(view.root);
				for (const [index, message] of item.encoded.entries()) {
					const sequence = item.sequencing[index];
					assert(sequence !== undefined, `${item.id}: sequence ${index}`);
					process.call(kernel, {
						envelope: {
							clientId: sequence.clientId,
							clientSequenceNumber: sequence.clientSequenceNumber,
							contents: message,
							referenceSequenceNumber: sequence.referenceSequenceNumber,
							sequenceNumber: sequence.sequenceNumber,
							minimumSequenceNumber: sequence.minimumSequenceNumber,
							timestamp: 0,
							type: "op",
						},
						local: false,
						messagesContent: [{
							contents: message,
							localOpMetadata: undefined,
							clientSequenceNumber: sequence.clientSequenceNumber,
						}],
					});
				}
				const afterApply = visibleArray(view.root);
				const continued = continueArray(view.root);
				assert(submitted.length >= 2, `${item.id}: continuation messages`);
				const continuationMessages = submitted.map((message, index) => {
					const decoded = decodeMessage(message, { idCompressor });
					const decodedGraph = decodedGraphs(decoded, `${item.id}: continuation ${index}`);
					assert(decodedGraph.length > 0, `${item.id}: continuation graph ${index}`);
					return { encoded: message, graphs: decodedGraph };
				});
				return {
					id: item.id,
					kind: item.kind,
					decoded: true,
					graphs,
					...(item.features === undefined ? {} : { features: item.features }),
					...(effect === undefined ? {} : { effect }),
					beforeApply,
					afterApply,
					continued,
					continuation: {
						messages: continuationMessages,
						compressor: serializeIdCompressor(idCompressor, true),
						session: idCompressor.localSessionId,
					},
				};
			}
			const decoded: unknown = decodeMessage(item.encoded, {
				idCompressor,
			});
			assert(decoded !== null && typeof decoded === "object", `${item.id}: decoded message`);
			if (item.schemaProfile === "map") {
				const view = tree.viewWith(mapConfiguration);
				const beforeApply = visibleMap(view.root);
				process.call(kernel, {
					envelope: {
						clientId: "watershed-codec-consumer",
						clientSequenceNumber: 1,
						contents: item.encoded,
						referenceSequenceNumber: item.referenceSequenceNumber,
						sequenceNumber: item.sequenceNumber,
						minimumSequenceNumber: item.minimumSequenceNumber,
						timestamp: 0,
						type: "op",
					},
					local: false,
					messagesContent: [{
						contents: item.encoded,
						localOpMetadata: undefined,
						clientSequenceNumber: 1,
					}],
				});
				const afterApply = visibleMap(view.root);
				view.root.items.set("upstream-continuation", true);
				return {
					id: item.id,
					kind: item.kind,
					decoded: true,
					beforeApply,
					afterApply,
					continued: view.root.items.get("upstream-continuation"),
				};
			}
			if (item.schemaProfile === "identifier") {
				const view = tree.viewWith(identifierConfiguration);
				const beforeApply = visibleIdentifier(view.root);
				process.call(kernel, {
					envelope: {
						clientId: "watershed-codec-consumer",
						clientSequenceNumber: 1,
						contents: item.encoded,
						referenceSequenceNumber: item.referenceSequenceNumber,
						sequenceNumber: item.sequenceNumber,
						minimumSequenceNumber: item.minimumSequenceNumber,
						timestamp: 0,
						type: "op",
					},
					local: false,
					messagesContent: [{
						contents: item.encoded,
						localOpMetadata: undefined,
						clientSequenceNumber: 1,
					}],
				});
				const afterApply = visibleIdentifier(view.root);
				view.root.child.label = "upstream-continuation";
				return {
					id: item.id,
					kind: item.kind,
					decoded: true,
					beforeApply,
					afterApply,
					continued: view.root.child.label,
				};
			}
			const view = tree.viewWith(configuration);
			const beforeApply = visibleRoot(view.root);
			process.call(kernel, {
				envelope: {
					clientId: "watershed-codec-consumer",
					clientSequenceNumber: 1,
					contents: item.encoded,
					referenceSequenceNumber: item.referenceSequenceNumber,
					sequenceNumber: item.sequenceNumber,
					minimumSequenceNumber: item.minimumSequenceNumber,
					timestamp: 0,
					type: "op",
				},
				local: false,
				messagesContent: [{
					contents: item.encoded,
					localOpMetadata: undefined,
					clientSequenceNumber: 1,
				}],
			});
			const afterApply = visibleRoot(view.root);
			view.root.title = "upstream-continuation";
			return {
				id: item.id,
				kind: item.kind,
				decoded: true,
				beforeApply,
				afterApply,
				continued: view.root.title,
			};
		}
		case "summary": {
			const idCompressor = compressor(item);
			const tree = await loadSummary(item, idCompressor);
			if (item.schemaProfile === "map") {
				const view = tree.viewWith(mapConfiguration);
				const visible = visibleMap(view.root);
				const history = summaryHistory(tree, idCompressor, item.id);
				const contentSnapshot: unknown = Reflect.get(tree, "contentSnapshot");
				assert(typeof contentSnapshot === "function", `${item.id}: missing content snapshot`);
				const snapshot: unknown = contentSnapshot.call(tree);
				assert(snapshot !== null && typeof snapshot === "object"
					&& "removed" in snapshot && Array.isArray(snapshot.removed),
				`${item.id}: missing removed content`);
				view.root.items.set("upstream-continuation", true);
				return {
					id: item.id,
					kind: item.kind,
					visible,
					removed: removedContent(snapshot.removed, idCompressor, item.id),
					history,
					continued: view.root.items.get("upstream-continuation"),
				};
			}
			if (item.schemaProfile === "identifier") {
				const view = tree.viewWith(identifierConfiguration);
				const visible = visibleIdentifier(view.root);
				const history = summaryHistory(tree, idCompressor, item.id, true);
				const contentSnapshot: unknown = Reflect.get(tree, "contentSnapshot");
				assert(typeof contentSnapshot === "function", `${item.id}: missing content snapshot`);
				const snapshot: unknown = contentSnapshot.call(tree);
				assert(snapshot !== null && typeof snapshot === "object"
					&& "removed" in snapshot && Array.isArray(snapshot.removed),
				`${item.id}: missing removed content`);
				view.root.child.label = "upstream-continuation";
				return {
					id: item.id,
					kind: item.kind,
					visible,
					removed: removedContent(snapshot.removed, idCompressor, item.id),
					history,
					continued: view.root.child.label,
				};
			}
			if (item.schemaProfile === "array") {
				assert(typeof item.session === "string", `${item.id}: missing session`);
				const rawInput = summaryRecord(item.encoded as SummaryTree);
				const emittedSummary = (await tree.summarize(true)).summary;
				const emitted = summaryRecord(emittedSummary as unknown as SummaryTree);
				const emittedCompressor = serializeIdCompressor(idCompressor, false);
				const restoredIdCompressor = deserializeIdCompressor(
					emittedCompressor,
					assertIsSessionId(item.session),
				);
				const restoredTree = await loadSummary(
					{
						...item,
						encoded: emittedSummary as unknown as SummaryTree,
						compressor: emittedCompressor,
						compressorMode: "summary",
					},
					restoredIdCompressor,
				);
				const view = restoredTree.viewWith(arrayConfiguration);
				const visible = visibleArray(view.root);
				const history = summaryHistory(
					restoredTree,
					restoredIdCompressor,
					item.id,
					true,
				);
				const contentSnapshot: unknown = Reflect.get(
					restoredTree,
					"contentSnapshot",
				);
				assert(typeof contentSnapshot === "function", `${item.id}: missing content snapshot`);
				const snapshot: unknown = contentSnapshot.call(restoredTree);
				assert(snapshot !== null && typeof snapshot === "object"
					&& "removed" in snapshot && Array.isArray(snapshot.removed),
				`${item.id}: missing removed content`);
				const continued = continueArray(view.root);
				return {
					id: item.id,
					kind: item.kind,
					rawInput: {
						schema: rawInput.schema,
						forest: rawInput.forest,
						compressor: item.compressor,
					},
					emitted: {
						schemaSemantics: decodedSchema(emitted.schema, item.id),
						compressor: emittedCompressor,
					},
					schema: decodedSchema(emitted.schema, item.id),
					visible,
					removed: removedContent(
						snapshot.removed,
						restoredIdCompressor,
						item.id,
					),
					history,
					restoredCompressor: serializeIdCompressor(
						restoredIdCompressor,
						true,
					),
					continued,
				};
			}
			const summaryConfiguration =
				item.id === "summary-schema-peer-before-upgrade"
					? captionConfiguration
					: item.id === "summary-schema-upgrade-tail"
						? detailsConfiguration
						: configuration;
			const view = tree.viewWith(summaryConfiguration);
			const visible = visibleRoot(view.root);
			const history = summaryHistory(tree, idCompressor, item.id);
			const contentSnapshot: unknown = Reflect.get(tree, "contentSnapshot");
			assert(typeof contentSnapshot === "function", `${item.id}: missing content snapshot`);
			const snapshot: unknown = contentSnapshot.call(tree);
			assert(snapshot !== null && typeof snapshot === "object"
				&& "removed" in snapshot && Array.isArray(snapshot.removed),
			`${item.id}: missing removed content`);
			view.root.title = "upstream-continuation";
			return {
				id: item.id,
				kind: item.kind,
				visible,
				removed: removedContent(snapshot.removed, idCompressor, item.id),
				history,
				continued: view.root.title,
			};
		}
	}
}

const nativeInput = process.env.WATERSHED_ORACLE_CODEC_INPUT;
if (nativeInput !== undefined) {
	describe("Watershed codec consumer", () => {
		it("decodes, applies, loads, and continues every native artifact", async () => {
			const output = process.env.WATERSHED_ORACLE_CODEC_OUTPUT;
			assert(output !== undefined, "A codec output directory is required");
			assert.equal(process.env.WATERSHED_ORACLE_COMMIT, reference.commit);
			const artifact: NativeArtifact = JSON.parse(readFileSync(nativeInput, "utf8"));
			assert.equal(artifact.formatVersion, 1);
			assert.deepEqual(artifact.reference, reference);
			assert(artifact.target === "erlang" || artifact.target === "javascript");
			assert(Array.isArray(artifact.items) && artifact.items.length > 0);
			assert.equal(new Set(artifact.items.map(({ id }) => id)).size, artifact.items.length);
			const observations = [];
			for (const item of artifact.items) {
				try {
					observations.push(await consume(item));
				} catch (error) {
					throw new Error(`Failed to consume ${item.id}`, { cause: error });
				}
			}
			assert.equal(observations.length, artifact.items.length);
			mkdirSync(output, { recursive: true });
			writeFileSync(join(output, "codec-observations.json"), `${JSON.stringify({
				formatVersion,
				reference,
				target: artifact.target,
				observations,
			}, null, 2)}\n`);
		});
	});
}

function readCases(output: string, name: string): unknown[] {
	const value: unknown = JSON.parse(readFileSync(join(output, name), "utf8"));
	assert(Array.isArray(value), `${name} must contain cases`);
	return value;
}

function caseById(cases: unknown[], id: string): Record<string, unknown> {
	const value = cases.find((item) =>
		item !== null && typeof item === "object" && Reflect.get(item, "id") === id);
	assert(value !== undefined && value !== null && typeof value === "object", `Missing case ${id}`);
	return value as Record<string, unknown>;
}

function child(tree: SummaryTree, ...path: string[]): SummaryTree | { type: number; content: string } {
	let value: SummaryTree | { type: number; content: string } = tree;
	for (const name of path) {
		assert("tree" in value, `Missing summary tree at ${path.join("/")}`);
		const next: SummaryTree | { type: number; content: string } | undefined =
			value.tree[name];
		assert(next !== undefined, `Missing summary entry ${path.join("/")}`);
		value = next;
	}
	return value;
}

function blob(tree: SummaryTree, ...path: string[]): string {
	const value = child(tree, ...path);
	assert("content" in value && typeof value.content === "string", `Missing blob ${path.join("/")}`);
	return value.content;
}

function asObject(value: unknown, label: string): Record<string, unknown> {
	assert(value !== null && typeof value === "object" && !Array.isArray(value), label);
	return value as Record<string, unknown>;
}

function schedules(value: Record<string, unknown>) {
	const input = asObject(value.input, `${value.id as string}: input`);
	const raw = asObject(value.raw, `${value.id as string}: raw`);
	const expected = asObject(value.expected, `${value.id as string}: expected`);
	assert(Array.isArray(input.schedules) && Array.isArray(raw.schedules)
		&& Array.isArray(expected.observations), `${value.id as string}: schedules`);
	return {
		input: input.schedules as Record<string, unknown>[],
		raw: raw.schedules as Record<string, unknown>[],
		expected: expected.observations as Record<string, unknown>[],
	};
}

function treeMessages(messages: unknown): Record<string, unknown>[] {
	const result: Record<string, unknown>[] = [];
	function visit(value: unknown): void {
		if (Array.isArray(value)) {
			value.forEach(visit);
		} else if (value !== null && typeof value === "object") {
			const object = value as Record<string, unknown>;
			if (typeof object.originatorId === "string"
				&& Array.isArray(object.changeset)
				&& object.version === 7) {
				result.push(object);
			}
			Object.values(object).forEach(visit);
		}
	}
	visit(messages);
	return result;
}

function idAllocationMessages(messages: unknown): Record<string, unknown>[] {
	const result: Record<string, unknown>[] = [];
	function visit(value: unknown): void {
		if (Array.isArray(value)) {
			value.forEach(visit);
		} else if (value !== null && typeof value === "object") {
			const object = value as Record<string, unknown>;
			const contents = object.contents;
			if (contents !== null
				&& typeof contents === "object"
				&& Reflect.get(contents, "type") === "idAllocation") {
				result.push(object);
			}
			Object.values(object).forEach(visit);
		}
	}
	visit(messages);
	return result;
}

function uniqueAllocationMessages(messages: unknown[]): Record<string, unknown>[] {
	const seen = new Set<string>();
	const result: Record<string, unknown>[] = [];
	for (const message of messages) {
		const object = asObject(message, "allocation message");
		const contents = asObject(object.contents, "allocation message contents");
		if (contents.type !== "idAllocation") {
			continue;
		}
		const key = JSON.stringify(contents.contents);
		if (!seen.has(key)) {
			seen.add(key);
			result.push(object);
		}
	}
	return result;
}

function summaryRecord(summary: SummaryTree) {
	const history = blob(summary, "indexes", "EditManager", "String");
	const schema = blob(summary, "indexes", "Schema", "SchemaString");
	const forest = blob(summary, "indexes", "Forest", "contents");
	const detached = blob(summary, "indexes", "DetachedFieldIndex", "DetachedFieldIndexBlob");
	return {
		history,
		schema,
		forest,
		detached,
		parsed: {
			history: JSON.parse(history),
			schema: JSON.parse(schema),
			forest: JSON.parse(forest),
			detached: JSON.parse(detached),
		},
	};
}

function decodedSchema(raw: string, id: string) {
	const encoded: unknown = JSON.parse(raw);
	const decoder = schemaCodecBuilder.buildDecoder({ jsonValidator: FormatValidatorNoOp });
	decoder.decode(encoded as never);
	assert(encoded !== null && typeof encoded === "object", `${id}: decoded schema`);
	return encoded;
}

export function captureCodecEvidence(output: string): void {
	const treeCases = readCases(output, "tree-cases.json");
	const same = schedules(caseById(treeCases, "same-field-both-orders"));
	const parent = schedules(caseById(treeCases, "parent-child-both-orders"));
	const optional = schedules(caseById(treeCases, "optional-set-clear"));
	const numbers = schedules(caseById(treeCases, "unicode-and-numbers"));

	const selected = [
		{ id: "same-field", set: same, index: 0 },
		{ id: "parent-child", set: parent, index: 0 },
		{ id: "optional", set: optional, index: 0 },
		{ id: "unicode-numbers", set: numbers, index: 0 },
	].map(({ id, set, index }) => {
		const input = asObject(set.input[index], `${id}: input schedule`);
		const raw = asObject(set.raw[index], `${id}: raw schedule`);
		const observation = asObject(set.expected[index], `${id}: observation`);
		const initial = asObject(input.initial, `${id}: initial`);
		const compressors = initial.compressors;
		const sessions = initial.sessions;
		assert(Array.isArray(compressors) && compressors.length === 2
			&& compressors.every((value) => typeof value === "string")
			&& Array.isArray(sessions) && sessions.length === 2
			&& sessions.every((value) => typeof value === "string")
			&& Array.isArray(initial.initializationMessages)
			&& Array.isArray(raw.messages), `${id}: compressor context`);
		const initialSummary = initial.summary as SummaryTree;
		const settledSummary = raw.summary as SummaryTree;
		const messages = treeMessages(raw.messages);
		const allocationMessages = uniqueAllocationMessages(idAllocationMessages(raw.messages))
			.filter((message) => {
				const contents = asObject(message.contents, `${id}: allocation contents`);
				const range = asObject(contents.contents, `${id}: allocation range`);
				const ids = asObject(range.ids, `${id}: allocation IDs`);
				return range.sessionId !== sessions[0] || ids.firstGenCount !== 1;
			});
		assert(messages.length > 0, `${id}: raw messages`);
		return {
			id,
			session: sessions[0],
			compressor: compressors[0],
			peerSession: sessions[1],
			peerCompressor: compressors[1],
			allocationMessages,
			actions: input.actions,
			messages,
			rawMessages: raw.messages,
			initialSummary,
			settledSummary,
			settledCompressor: raw.compressor,
			observation,
		};
	});

	const initial = summaryRecord(selected[0].initialSummary);
	const settled = summaryRecord(selected[1].settledSummary);
	const bootstrap = asObject(initial.parsed.history, "initial history");
	assert(Array.isArray(bootstrap.trunk), "initial history trunk");
	const firstCommit = asObject(bootstrap.trunk[0], "initial history commit");
	assert(Array.isArray(firstCommit.change) && firstCommit.change.length === 3,
		"Initial history must contain schema-data-schema");

	const simpleFieldBatch = {
		version: 2,
		identifiers: [],
		shapes: [{ c: { extraFields: 1 } }, { a: 0 }],
		data: [[1, [
			"com.fluidframework.leaf.string", true, "native", [],
		]]],
	};
		const metadataMessage = structuredClone(selected[0].messages.at(-1));
	assert(metadataMessage !== undefined, "Missing metadata message source");
	metadataMessage.customMetadata = {
		m: { source: "watershed", count: 2 },
		c: [{}, { m: { nested: true }, c: [{ m: { label: "leaf" } }] }],
	};
	metadataMessage.toleratedEnvelopeProperty = { preserved: true };

	const oracleCase = {
		formatVersion,
		reference,
		id: "tree-codecs",
		domain: "codec",
		input: {
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
			scenarios: selected.map((scenario) => ({
				id: scenario.id,
				session: scenario.session,
				compressor: scenario.compressor,
				peerSession: scenario.peerSession,
				peerCompressor: scenario.peerCompressor,
				allocationMessages: scenario.allocationMessages,
				actions: scenario.actions,
				messages: scenario.messages.map((message) => JSON.stringify(message)),
				initialSummary: scenario.initialSummary,
				settledSummary: scenario.settledSummary,
				settledCompressor: scenario.settledCompressor,
			})),
			schemas: [
				{ id: "fixed", raw: initial.schema },
				{ id: "empty", raw: JSON.stringify(firstCommit.change[0].schema.old) },
				{ id: "optional", raw: JSON.stringify(firstCommit.change[0].schema.new) },
			],
			fieldBatches: [
				{ id: "initial-forest-compressed", encoded: initial.parsed.forest.fields },
				{
					id: "initial-build-compressed",
					encoded: firstCommit.change[1].data.builds.trees,
				},
				{ id: "simple-uncompressed", encoded: simpleFieldBatch },
			],
			metadataMessage: {
				raw: JSON.stringify(metadataMessage),
				session: selected[0].session,
				compressor: selected[0].compressor,
				allocationMessages: selected[0].allocationMessages.filter((message) => {
					const contents = asObject(message.contents, "allocation message contents");
					const range = asObject(contents.contents, "allocation range");
					return range.sessionId === selected[0].peerSession;
				}),
			},
			summaries: [
				{
					id: "initial",
					summary: selected[0].initialSummary,
					session: selected[0].session,
					compressor: selected[0].compressor,
				},
				{
					id: "settled-detached",
					summary: selected[1].settledSummary,
					session: selected[1].session,
					compressor: selected[1].settledCompressor,
				},
			],
		},
		expected: {
			observations: [
				{ id: "bootstrap-history", value: initial.parsed.history },
				{ id: "initial-schema", value: initial.parsed.schema },
				{ id: "initial-forest", value: initial.parsed.forest },
				{ id: "initial-detached", value: initial.parsed.detached },
				{ id: "settled-history", value: settled.parsed.history },
				{ id: "settled-forest", value: settled.parsed.forest },
				{ id: "settled-detached", value: settled.parsed.detached },
				...selected.map((scenario) => ({
					id: `message-${scenario.id}`,
					value: { messages: scenario.messages },
				})),
				{ id: "metadata", value: metadataMessage.customMetadata },
			],
		},
		raw: {
			scenarios: selected.map((scenario) => ({
				id: scenario.id,
				messages: scenario.rawMessages,
				initialSummary: scenario.initialSummary,
				settledSummary: scenario.settledSummary,
			})),
			blobs: {
				initial,
				settled,
			},
		},
	};

	writeFileSync(
		join(output, "codec-cases.json"),
		`${JSON.stringify([oracleCase], null, 2)}\n`,
	);
}
