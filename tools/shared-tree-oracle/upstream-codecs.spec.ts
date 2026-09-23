/*!
 * Copyright (c) Microsoft Corporation and contributors. All rights reserved.
 * Licensed under the MIT License.
 */

import { strict as assert } from "node:assert";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

import type { IIdCompressor } from "@fluidframework/id-compressor";
import {
	deserializeIdCompressor,
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
} from "../feature-libraries/index.js";
import { SchemaFactory, TreeViewConfiguration } from "../simple-tree/index.js";
import { configuredSharedTreeInternal } from "../treeFactory.js";
import { makeTestFieldBatchContexts, assertIsSessionId } from "./utils.js";

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
	compressor?: string;
	compressorMode?: "ongoing" | "summary";
	session?: string;
	initialSummary?: SummaryTree;
	allocationRanges?: unknown[];
	sequenceNumber?: number;
	referenceSequenceNumber?: number;
	minimumSequenceNumber?: number;
	indexInBatch?: number | null;
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

async function loadSummary(item: ArtifactItem) {
	assert(item.encoded !== null && typeof item.encoded === "object",
		`${item.id}: summary encoding`);
	const runtime = new MockFluidDataStoreRuntime({ idCompressor: compressor(item) });
	return factory.load(
		runtime,
		`codec-${item.id}`,
		services(
			item.encoded as Parameters<typeof MockSharedObjectServices.createFromSummary>[0],
		),
		factory.attributes,
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
				&& Number.isSafeInteger(item.minimumSequenceNumber),
			`${item.id}: missing sequence metadata`);
			const runtime = new MockFluidDataStoreRuntime({ idCompressor: compressor(item) });
			const tree = await factory.load(
				runtime,
				`codec-${item.id}`,
				services(
					item.initialSummary as Parameters<
						typeof MockSharedObjectServices.createFromSummary
					>[0],
				),
				factory.attributes,
			);
			const kernel: unknown = Reflect.get(tree, "kernel");
			assert(kernel !== null && typeof kernel === "object", `${item.id}: missing kernel`);
			const messageCodec: unknown = Reflect.get(kernel, "messageCodec");
			assert(messageCodec !== null && typeof messageCodec === "object"
				&& "decode" in messageCodec && typeof messageCodec.decode === "function",
			`${item.id}: missing message codec`);
			const decoded: unknown = messageCodec.decode(item.encoded, {
				idCompressor: runtime.idCompressor,
			});
			assert(decoded !== null && typeof decoded === "object", `${item.id}: decoded message`);
			const process: unknown = Reflect.get(kernel, "processMessagesCore");
			assert(typeof process === "function", `${item.id}: missing process function`);
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
			const view = tree.viewWith(configuration);
			const afterApply = visibleRoot(view.root);
			view.root.title = "upstream-continuation";
			return {
				id: item.id,
				kind: item.kind,
				decoded: true,
				afterApply,
				continued: view.root.title,
			};
		}
		case "summary": {
			const tree = await loadSummary(item);
			const view = tree.viewWith(configuration);
			const visible = visibleRoot(view.root);
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
				removedCount: snapshot.removed.length,
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
