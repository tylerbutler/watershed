/*!
 * Copyright (c) Microsoft Corporation and contributors. All rights reserved.
 * Licensed under the MIT License.
 */

import { strict as assert } from "node:assert";
import { mkdirSync, writeFileSync } from "node:fs";
import { isAbsolute, join } from "node:path";

import type { IIdCompressor, OpSpaceCompressedId } from "@fluidframework/id-compressor";
import {
	createIdCompressor,
	isFinalId,
	isStableId,
	serializeIdCompressor,
	toIdCompressorWithCore,
} from "@fluidframework/id-compressor/internal";

import { FluidClientVersion } from "../codec/index.js";
import {
	LeafNodeStoredSchema,
	TreeStoredSchemaRepository,
	type TreeNodeSchemaIdentifier,
	ValueSchema,
} from "../core/index.js";
import {
	defaultSchemaPolicy,
	FieldKinds,
} from "../feature-libraries/index.js";
import { readValue } from "../feature-libraries/chunked-forest/codec/chunkDecoding.js";
import { SpecialField } from "../feature-libraries/chunked-forest/codec/format/formatV1.js";
import { noChangeCodecFamily } from "../feature-libraries/default-schema/noChangeCodecs.js";
import { allowsFieldSuperset } from "../feature-libraries/modular-schema/comparison.js";
import {
	EncodedIdType,
	encodePossiblyCompressedId,
	IdDecodingContext,
} from "../util/index.js";
import {
	extractPersistedSchema,
	FieldKind,
	SchemaFactory,
	TreeViewConfiguration,
} from "../simple-tree/index.js";
import { createFieldSchema } from "../simple-tree/fieldSchema.js";
import { Tree } from "../shared-tree/index.js";
import { configuredSharedTreeInternal } from "../treeFactory.js";
import { MockContainerRuntimeWithOpBunching } from "./mocksForOpBunching.js";
import { assertIsSessionId, TestTreeProviderLite } from "./utils.js";
import { brand } from "../util/index.js";

const formatVersion = 1;
const reference = {
	package: "@fluidframework/tree",
	version: "3.1.0",
	commit: "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960",
};

const sessions = {
	local: assertIsSessionId("10000000-0000-4000-8000-000000000001"),
	remote: assertIsSessionId("20000000-0000-4000-8000-000000000002"),
	summary: assertIsSessionId("30000000-0000-4000-8000-000000000003"),
};

const sf = new SchemaFactory("org.watershed.shared-tree.identifiers");
class Point extends sf.object("Point", {
	id: sf.identifier,
	label: sf.string,
}) {}
class Pair extends sf.object("Pair", {
	firstId: sf.identifier,
	secondId: sf.identifier,
	label: sf.string,
}) {}
class Items extends sf.array("Items", [Point, Pair]) {}
class PointsByKey extends sf.map("PointsByKey", [Point, Pair]) {}
class Root extends sf.object("Root", {
	child: Point,
	left: Items,
	right: Items,
	byKey: PointsByKey,
}) {}

type TreeInstance = TestTreeProviderLite["trees"][number];
type PersistedSchema = {
	nodes: Record<string, {
		kind: {
			object?: Record<string, { kind: string; types: string[] }>;
		};
	}>;
};
type IdentifierInput = {
	version: number;
	schema: unknown;
	initialTree: unknown;
	sessions: typeof sessions;
	compressors: Record<string, string>;
	idRanges: unknown[];
	scenarios: object[];
};

function copy<T>(value: T): T {
	return JSON.parse(JSON.stringify(value));
}

function errorObservation(error: unknown) {
	return {
		originalError: String(error),
		nativeErrorCategory: error instanceof Error ? error.constructor.name : typeof error,
	};
}

function captureRefusal(run: () => unknown) {
	try {
		run();
		assert.fail("Expected the operation to be refused.");
	} catch (error) {
		return errorObservation(error);
	}
}

function caseFile(id: string, domain: string, input: object, observations: object[], raw: object) {
	assert(observations.length > 0);
	return { formatVersion, reference, id, domain, input, expected: { observations }, raw };
}

function schemaJson(schema: Parameters<typeof extractPersistedSchema>[0]) {
	return copy(extractPersistedSchema(
		schema,
		FluidClientVersion.v2_117,
		() => false,
	)) as unknown as PersistedSchema;
}

function compressorInput(compressor: IIdCompressor) {
	return serializeIdCompressor(compressor, true);
}

function sharedTreeFactory() {
	return configuredSharedTreeInternal({
		minVersionForCollab: FluidClientVersion.v2_117,
	}).getFactory();
}

function visible(root: Root) {
	const value = (item: Point | Pair) =>
		item instanceof Pair
			? { firstId: item.firstId, secondId: item.secondId, label: item.label }
			: { id: item.id, label: item.label };
	return {
		child: value(root.child),
		left: [...root.left].map(value),
		right: [...root.right].map(value),
		byKey: [...root.byKey].map(([key, item]) => [key, value(item)]),
	};
}

function messagesIn(value: unknown): Record<string, unknown>[] {
	const messages: Record<string, unknown>[] = [];
	function visit(item: unknown) {
		if (Array.isArray(item)) {
			for (const child of item) visit(child);
		} else if (item !== null && typeof item === "object") {
			const object = item as Record<string, unknown>;
			if ("originatorId" in object && "changeset" in object) {
				messages.push(copy(object));
			}
			for (const child of Object.values(object)) visit(child);
		}
	}
	visit(value);
	return messages;
}

function interceptProcessed(provider: TestTreeProviderLite, client = 0): unknown[] {
	const processed: unknown[] = [];
	const runtime = provider.trees[client].containerRuntime;
	assert(
		runtime instanceof MockContainerRuntimeWithOpBunching,
		"Expected the bunching test runtime.",
	);
	const process = runtime.process.bind(runtime);
	runtime.process = (message) => {
		processed.push(copy(message));
		process(message);
	};
	const processMessages = runtime.processMessages.bind(runtime);
	runtime.processMessages = (batch) => {
		processed.push(...copy(batch));
		processMessages(batch);
	};
	return processed;
}

function scenario(id: string, actions: object[]) {
	return { id, actions };
}

function observe(id: string, value: object) {
	return { id, ...value };
}

function baseInput(scenarios: object[], compressor: IIdCompressor): IdentifierInput {
	return {
		version: 1,
		schema: schemaJson(Root),
		initialTree: {
			schema: Root.identifier,
			fields: {
				child: { schema: Point.identifier, fields: { id: "initial", label: "initial" } },
				left: [],
				right: [],
				byKey: [],
			},
		},
		sessions,
		compressors: { initial: compressorInput(compressor) },
		idRanges: [],
		scenarios,
	};
}

function captureSchema() {
	const compressor = createIdCompressor(sessions.local);
	const persisted = schemaJson(Root);
	const root = persisted.nodes[Root.identifier];
	assert(root?.kind.object !== undefined);
	assert.equal(root.kind.object.child.kind, "Value");
	const point = persisted.nodes[Point.identifier];
	assert(point?.kind.object !== undefined);
	assert.equal(point.kind.object.id.kind, "Identifier");
	assert.deepEqual(point.kind.object.id.types, ["com.fluidframework.leaf.string"]);
	const pair = persisted.nodes[Pair.identifier];
	assert(pair?.kind.object !== undefined);
	assert.equal(pair.kind.object.firstId.kind, "Identifier");
	assert.equal(pair.kind.object.secondId.kind, "Identifier");

	const invalidNumber = createFieldSchema(FieldKind.Identifier, sf.number);
	const invalidUnion = createFieldSchema(FieldKind.Identifier, [sf.string, sf.number]);
	class NumberIdentifier extends sf.object("NumberIdentifier", { id: invalidNumber }) {}
	class UnionIdentifier extends sf.object("UnionIdentifier", { id: invalidUnion }) {}
	const numberRefusal = captureRefusal(() =>
		new TreeViewConfiguration({ schema: NumberIdentifier }));
	const unionRefusal = captureRefusal(() =>
		new TreeViewConfiguration({ schema: UnionIdentifier }));

	const stringType = brand<TreeNodeSchemaIdentifier>("com.fluidframework.leaf.string");
	const repository = new TreeStoredSchemaRepository({
		rootFieldSchema: {
			kind: FieldKinds.required.identifier,
			types: new Set([stringType]),
			persistedMetadata: undefined,
		},
		nodeSchema: new Map([[stringType, new LeafNodeStoredSchema(ValueSchema.String)]]),
	});
	const identifierField = {
		kind: FieldKinds.identifier.identifier,
		types: new Set([stringType]),
		persistedMetadata: undefined,
	};
	const valueField = {
		kind: FieldKinds.required.identifier,
		types: new Set([stringType]),
		persistedMetadata: undefined,
	};
	const identifierToValue = allowsFieldSuperset(
		defaultSchemaPolicy, repository, identifierField, valueField,
	);
	const valueToIdentifier = allowsFieldSuperset(
		defaultSchemaPolicy, repository, valueField, identifierField,
	);
	assert.equal(identifierToValue, true);
	assert.equal(valueToIdentifier, false);

	const codec = noChangeCodecFamily.resolve(1);
	const canonical = codec.encode(0, undefined as never);
	const decodedNoncanonical = codec.decode(17, undefined as never);
	assert.equal(canonical, 0);
	assert.equal(decodedNoncanonical, 0);

	const scenarios = [
		scenario("valid-string-field", [{ op: "validate-schema", schema: persisted }]),
		scenario("two-identifier-fields", [{ op: "validate-schema", schema: persisted }]),
		scenario("non-string-refusal", [{ op: "validate-schema", schema: schemaJson(NumberIdentifier) }]),
		scenario("union-refusal", [{ op: "validate-schema", schema: schemaJson(UnionIdentifier) }]),
		scenario("identifier-to-value", [{ op: "compare-schema", from: "Identifier", to: "Value" }]),
		scenario("value-to-identifier-refusal", [{ op: "compare-schema", from: "Value", to: "Identifier" }]),
		scenario("canonical-field-change", [{ op: "decode-field-change", encoded: 0 }]),
	];
	const observations = [
		observe("valid-string-field", { field: point.kind.object.id }),
		observe("two-identifier-fields", {
			fields: [pair.kind.object.firstId, pair.kind.object.secondId],
		}),
		observe("non-string-refusal", { refused: true, ...numberRefusal }),
		observe("union-refusal", { refused: true, ...unionRefusal }),
		observe("identifier-to-value", { allowed: identifierToValue }),
		observe("value-to-identifier-refusal", { allowed: valueToIdentifier }),
		observe("canonical-field-change", { encoded: canonical, decodedNoncanonical }),
	];
	return caseFile(
		"identifier-schema",
		"schema",
		baseInput(scenarios, compressor),
		observations,
		{ scenarios: copy(observations), persisted },
	);
}

async function captureValues() {
	const compressor = createIdCompressor(sessions.local);
	const custom = new Point({ id: "custom-id", label: "custom" });
	const empty = new Point({ id: "", label: "empty" });
	const uuid = "11111111-2222-4333-8444-555555555555";
	const uuidPoint = new Point({ id: uuid, label: "uuid" });
	const duplicateA = new Point({ id: "duplicate", label: "a" });
	const duplicateB = new Point({ id: "duplicate", label: "b" });
	const generated = new Point({ label: "generated" });
	const pair = new Pair({ label: "pair" });
	const nested = new Root({
		child: new Point({ label: "child" }),
		left: new Items([new Point({ label: "array" })]),
		right: new Items([]),
		byKey: new PointsByKey([["map", new Point({ label: "map" })]]),
	});
	assert.equal(custom.id, "custom-id");
	assert.equal(empty.id, "");
	assert.equal(uuidPoint.id, uuid);
	assert.equal(duplicateA.id, duplicateB.id);
	assert.notEqual(generated.id, "");
	assert.notEqual(pair.firstId, pair.secondId);
	assert.notEqual(nested.child.id, nested.left[0] instanceof Point && nested.left[0].id);

	const provider = new TestTreeProviderLite(2, sharedTreeFactory());
	const processed = interceptProcessed(provider);
	const view = provider.trees[0].viewWith(new TreeViewConfiguration({ schema: Root }));
	view.initialize({
		child: new Point({ id: "attached-child", label: "child" }),
		left: new Items([new Point({ id: "left", label: "left" })]),
		right: new Items([]),
		byKey: new PointsByKey(),
	});
	provider.synchronizeMessages();
	const peer = provider.trees[1].viewWith(new TreeViewConfiguration({ schema: Root }));
	const direct = captureRefusal(() => {
		view.root.child.id = "changed";
	});
	const clear = captureRefusal(() => {
		delete (view.root.child as { id?: string }).id;
	});
	assert.equal(view.root.child.id, "attached-child");
	const oldChild = view.root.child;
	view.root.child = new Point({ id: "replacement", label: "replacement" });
	provider.synchronizeMessages();
	assert.equal(view.root.child.id, "replacement");
	assert.notEqual(view.root.child, oldChild);

	const before = processed.length;
	const inserted = new Pair({ label: "allocation" });
	view.root.left.insertAtEnd(inserted);
	provider.synchronizeMessages();
	assert(peer.root.left[peer.root.left.length - 1] instanceof Pair);
	const allocationMessages = messagesIn(processed.slice(before));
	assert.equal(allocationMessages.length, 1);
	const allocationMessage = allocationMessages[0];
	const revision = allocationMessage.revision;
	const documentCompressor = provider.getCompressor(provider.trees[0]);
	assert(isStableId(inserted.firstId));
	assert(isStableId(inserted.secondId));
	const first = documentCompressor.tryRecompress(inserted.firstId);
	const second = documentCompressor.tryRecompress(inserted.secondId);
	assert(first !== undefined && second !== undefined);
	const allocationOrder = [
		{ kind: "revision", op: revision },
		{ kind: "identifier", field: "firstId", op: documentCompressor.normalizeToOpSpace(first) },
		{ kind: "identifier", field: "secondId", op: documentCompressor.normalizeToOpSpace(second) },
	];
	assert(allocationOrder.every(({ op }) => Number.isSafeInteger(op)));

	const scenarios = [
		scenario("custom-string", [{ op: "construct", schema: Point.identifier, fields: { id: "custom-id", label: "custom" } }]),
		scenario("empty-string", [{ op: "construct", schema: Point.identifier, fields: { id: "", label: "empty" } }]),
		scenario("uuid", [{ op: "construct", schema: Point.identifier, fields: { id: uuid, label: "uuid" } }]),
		scenario("duplicate-custom-strings", [
			{ op: "construct", schema: Point.identifier, fields: { id: "duplicate", label: "a" } },
			{ op: "construct", schema: Point.identifier, fields: { id: "duplicate", label: "b" } },
		]),
		scenario("omitted-default", [{ op: "construct", schema: Point.identifier, fields: { label: "generated" } }]),
		scenario("multiple-defaults", [{ op: "construct", schema: Pair.identifier, fields: { label: "pair" } }]),
		scenario("nested-insertion", [{
			op: "insert",
			path: ["left"],
			index: 0,
			value: { schema: Point.identifier, fields: { label: "array" } },
		}]),
		scenario("direct-assignment-refusal", [{ op: "set", path: ["child", "id"], value: "changed" }]),
		scenario("clear-refusal", [{ op: "clear", path: ["child", "id"] }]),
		scenario("parent-replacement", [{
			op: "set",
			path: ["child"],
			value: { schema: Point.identifier, fields: { id: "replacement", label: "replacement" } },
		}]),
		scenario("allocation-order", [{
			op: "insert",
			path: ["left"],
			index: 1,
			value: { schema: Pair.identifier, fields: { label: "allocation" } },
		}]),
	];
	const observations = [
		observe("custom-string", { value: custom.id }),
		observe("empty-string", { value: empty.id }),
		observe("uuid", { value: uuidPoint.id }),
		observe("duplicate-custom-strings", { values: [duplicateA.id, duplicateB.id] }),
		observe("omitted-default", { value: generated.id }),
		observe("multiple-defaults", { values: [pair.firstId, pair.secondId] }),
		observe("nested-insertion", { value: visible(nested) }),
		observe("direct-assignment-refusal", { refused: true, ...direct }),
		observe("clear-refusal", { refused: true, ...clear }),
		observe("parent-replacement", { value: visible(view.root).child }),
		observe("allocation-order", { order: allocationOrder }),
	];
	const input = baseInput(scenarios, compressor);
	input.compressors.document = serializeIdCompressor(documentCompressor, true);
	return caseFile(
		"identifier-values",
		"values",
		input,
		observations,
		{ scenarios: copy(observations), messages: allocationMessages },
	);
}

function decodeIdentifier(value: unknown, context: IdDecodingContext) {
	return readValue(
		{ data: [value] as never[], offset: 0 },
		SpecialField.Identifier,
		context,
	);
}

function captureFieldBatches() {
	assert.equal(SpecialField.Identifier, 0);
	const local = toIdCompressorWithCore(createIdCompressor(sessions.local));
	const remote = toIdCompressorWithCore(createIdCompressor(sessions.remote));
	const summary = toIdCompressorWithCore(createIdCompressor(sessions.summary));
	const localId = local.generateCompressedId();
	const localStable = local.decompress(localId);
	const localOp = local.normalizeToOpSpace(localId);
	assert(localOp < 0);
	const localContext = new IdDecodingContext({
		idCompressor: local,
		originatorId: sessions.local,
	});
	assert.equal(decodeIdentifier(localOp, localContext), localStable);

	const remoteId = remote.generateCompressedId();
	const remoteStable = remote.decompress(remoteId);
	const remoteRange = remote.takeNextCreationRange();
	local.finalizeCreationRange(remoteRange);
	const remoteOp = remote.normalizeToOpSpace(remoteId);
	const remoteContext = new IdDecodingContext({
		idCompressor: local,
		originatorId: sessions.remote,
	});
	assert.equal(decodeIdentifier(remoteOp, remoteContext), remoteStable);

	const eagerId = summary.generateCompressedId();
	const eagerStable = summary.decompress(eagerId);
	const eagerRange = summary.takeNextCreationRange();
	summary.finalizeCreationRange(eagerRange);
	const eagerEncoded = encodePossiblyCompressedId(
		eagerStable,
		summary,
		EncodedIdType.Originatorless,
	);
	assert.equal(typeof eagerEncoded, "number");
	assert(isFinalId(eagerEncoded as OpSpaceCompressedId));

	const unknownCompressor = createIdCompressor(
		assertIsSessionId("50000000-0000-4000-8000-000000000005"),
	);
	const unknownId = unknownCompressor.generateCompressedId();
	const unknownStable = unknownCompressor.decompress(unknownId);
	assert.equal(
		encodePossiblyCompressedId(unknownStable, local, EncodedIdType.OriginatorDependent),
		unknownStable,
	);
	const messageEncoded = encodePossiblyCompressedId(
		remoteStable, local, EncodedIdType.OriginatorDependent,
	);
	const summaryEncoded = encodePossiblyCompressedId(
		remoteStable, local, EncodedIdType.Originatorless,
	);
	assert.equal(messageEncoded, summaryEncoded);
	const unfinalizedSummary = encodePossiblyCompressedId(
		localStable, local, EncodedIdType.Originatorless,
	);
	assert.equal(unfinalizedSummary, localStable);

	const originatorless = new IdDecodingContext({ idCompressor: local, healing: undefined });
	const originatorlessRefusal = captureRefusal(() => decodeIdentifier(localOp, originatorless));
	const invalidPayloads = [1.5, Number.MAX_SAFE_INTEGER + 1, true, null, [], {}].map((value) => ({
		value,
		...captureRefusal(() => decodeIdentifier(value, localContext)),
	}));
	assert.equal(decodeIdentifier("0", localContext), "0");

	const scenarios = [
		scenario("literal-zero-string", [{ op: "decode-field-batch", path: ["identifier"], encoded: { value: "0" }, purpose: "message", originator: sessions.local }]),
		scenario("local-negative-op-id", [{ op: "decode-field-batch", path: ["identifier"], encoded: { value: localOp }, purpose: "message", originator: sessions.local }]),
		scenario("remote-finalized-id", [{ op: "decode-field-batch", path: ["identifier"], encoded: { value: remoteOp }, purpose: "message", originator: sessions.remote }]),
		scenario("eager-final-id", [{ op: "decode-field-batch", path: ["identifier"], encoded: { value: eagerEncoded }, purpose: "summary" }]),
		scenario("unknown-uuid-string", [{ op: "encode-field-batch", path: ["identifier"], value: unknownStable, purpose: "message" }]),
		scenario("message-summary-same-id", [
			{ op: "encode-field-batch", path: ["identifier"], value: remoteStable, purpose: "message", originator: sessions.local },
			{ op: "encode-field-batch", path: ["identifier"], value: remoteStable, purpose: "summary" },
		]),
		scenario("unfinalized-summary-string", [{ op: "encode-field-batch", path: ["identifier"], value: localStable, purpose: "summary" }]),
		scenario("numeric-originatorless-refusal", [{ op: "decode-field-batch", path: ["identifier"], encoded: { value: localOp }, purpose: "summary" }]),
		scenario("invalid-payload-shapes", invalidPayloads.map(({ value }) => ({
			op: "decode-field-batch",
			path: ["identifier"],
			encoded: { value },
			purpose: "message",
			originator: sessions.local,
		}))),
	];
	const observations = [
		observe("literal-zero-string", { decoded: "0", discriminator: SpecialField.Identifier }),
		observe("local-negative-op-id", { encoded: localOp, decoded: localStable }),
		observe("remote-finalized-id", { encoded: remoteOp, decoded: remoteStable }),
		observe("eager-final-id", { encoded: eagerEncoded, decoded: eagerStable }),
		observe("unknown-uuid-string", { encoded: unknownStable }),
		observe("message-summary-same-id", { message: messageEncoded, summary: summaryEncoded }),
		observe("unfinalized-summary-string", { encoded: unfinalizedSummary }),
		observe("numeric-originatorless-refusal", { refused: true, ...originatorlessRefusal }),
		observe("invalid-payload-shapes", { refusals: invalidPayloads }),
	];
	const input = baseInput(scenarios, local);
	input.compressors.remote = serializeIdCompressor(remote, true);
	input.compressors.summary = serializeIdCompressor(summary, true);
	input.idRanges = [remoteRange, eagerRange];
	return caseFile(
		"identifier-field-batches",
		"codec",
		input,
		observations,
		{ scenarios: copy(observations), discriminator: SpecialField.Identifier },
	);
}

async function capturePersistence() {
	const compressor = createIdCompressor(sessions.local);
	const provider = new TestTreeProviderLite(2, sharedTreeFactory());
	const processed = interceptProcessed(provider);
	const view = provider.trees[0].viewWith(new TreeViewConfiguration({ schema: Root }));
	view.initialize({
		child: new Point({ label: "child" }),
		left: new Items([new Point({ label: "left" }), new Pair({ label: "pair" })]),
		right: new Items([]),
		byKey: new PointsByKey(),
	});
	provider.synchronizeMessages();
	const peer = provider.trees[1].viewWith(new TreeViewConfiguration({ schema: Root }));
	const initial = visible(view.root);
	const initialSummary = (await provider.trees[0].summarize(true)).summary;
	assert(typeof initial.child.id === "string" && initial.child.id.length > 0);

	const tailStart = processed.length;
	view.root.byKey.set("tail", new Point({ label: "tail" }));
	provider.synchronizeMessages();
	const tailMessages = messagesIn(processed.slice(tailStart));
	assert.equal(tailMessages.length, 1);

	const documentCompressor = provider.getCompressor(provider.trees[0]);
	const beforeAbort = serializeIdCompressor(documentCompressor, true);
	let abortedId = "";
	Tree.runTransaction(view, () => {
		const inserted = new Point({ label: "aborted" });
		view.root.left.insertAtEnd(inserted);
		abortedId = inserted.id;
		return Tree.runTransaction.rollback;
	});
	const afterAbort = serializeIdCompressor(documentCompressor, true);
	assert.notEqual(afterAbort, beforeAbort);
	assert.equal([...view.root.left].some((item) => item instanceof Point && item.id === abortedId), false);

	const beforeNested = serializeIdCompressor(documentCompressor, true);
	let nestedId = "";
	Tree.runTransaction(view, () => {
		Tree.runTransaction(view, () => {
			const inserted = new Point({ label: "nested-aborted" });
			view.root.left.insertAtEnd(inserted);
			nestedId = inserted.id;
			return Tree.runTransaction.rollback;
		});
	});
	const afterNested = serializeIdCompressor(documentCompressor, true);
	assert.notEqual(afterNested, beforeNested);
	assert.equal([...view.root.left].some((item) => item instanceof Point && item.id === nestedId), false);

	provider.trees[0].containerRuntime.connected = false;
	const retry = new Point({ label: "retry" });
	view.root.left.insertAtEnd(retry);
	const retryId = retry.id;
	provider.trees[0].containerRuntime.connected = true;
	provider.synchronizeMessages();
	assert([...peer.root.left].some((item) => item instanceof Point && item.id === retryId));

	const removed = view.root.left[0];
	assert(removed instanceof Point);
	const removedId = removed.id;
	view.root.left.removeAt(0);
	const snapshot = Reflect.get(provider.trees[0], "contentSnapshot") as () => { removed: unknown[] };
	const repair = copy(snapshot.call(provider.trees[0]).removed);
	assert(repair.length > 0);

	const oldChild = view.root.child;
	const equalId = oldChild.id;
	view.root.child = new Point({ id: equalId, label: "replacement-equal" });
	assert.equal(view.root.child.id, equalId);
	assert.notEqual(view.root.child, oldChild);

	const moved = view.root.left[0];
	assert(moved instanceof Point || moved instanceof Pair);
	const movedId = moved instanceof Pair ? moved.firstId : moved.id;
	view.root.right.moveRangeToEnd(0, 1, view.root.left);
	const movedAfter = view.root.right[view.root.right.length - 1];
	assert.equal(movedAfter, moved);
	assert.equal(movedAfter instanceof Pair ? movedAfter.firstId : movedAfter.id, movedId);
	provider.synchronizeMessages();

	const scenarios = [
		scenario("initial-summary-defaults", [{ op: "summarize", purpose: "summary" }]),
		scenario("summary-tail", [
			{ op: "load-summary", purpose: "summary" },
			{ op: "apply-tail", purpose: "message" },
		]),
		scenario("transaction-abort", [{
			op: "transaction",
			result: "rollback",
			actions: [{ op: "insert", path: ["left"], index: 2, value: { schema: Point.identifier, fields: { label: "aborted" } } }],
		}]),
		scenario("nested-abort", [{
			op: "transaction",
			actions: [{ op: "transaction", result: "rollback", actions: [{ op: "insert", path: ["left"], index: 2, value: { schema: Point.identifier, fields: { label: "nested-aborted" } } }] }],
		}]),
		scenario("retry-resubmit", [
			{ op: "disconnect" },
			{ op: "insert", path: ["left"], index: 2, value: { schema: Point.identifier, fields: { label: "retry" } } },
			{ op: "reconnect" },
			{ op: "resubmit" },
		]),
		scenario("remove-retain-repair", [{ op: "remove", path: ["left"], index: 0, count: 1 }]),
		scenario("equal-custom-id-replacement", [{ op: "set", path: ["child"], value: { schema: Point.identifier, fields: { id: equalId, label: "replacement-equal" } } }]),
		scenario("node-moves", [{ op: "move", from: ["left", 0], to: ["right", "end"], count: 1 }]),
	];
	const observations = [
		observe("initial-summary-defaults", { value: initial, summary: initialSummary }),
		observe("summary-tail", { messages: tailMessages, value: visible(peer.root) }),
		observe("transaction-abort", {
			id: "transaction-abort",
			generated: abortedId,
			visible: false,
			compressorAdvanced: beforeAbort !== afterAbort,
		}),
		observe("nested-abort", {
			id: "nested-abort",
			generated: nestedId,
			visible: false,
			compressorAdvanced: beforeNested !== afterNested,
		}),
		observe("retry-resubmit", { identifier: retryId, peerObserved: true }),
		observe("remove-retain-repair", { identifier: removedId, repair }),
		observe("equal-custom-id-replacement", { identifier: equalId, nodeReplaced: true }),
		observe("node-moves", { identifier: movedId, identityPreserved: true }),
	];
	const input = baseInput(scenarios, compressor);
	input.compressors.document = serializeIdCompressor(documentCompressor, true);
	return caseFile(
		"identifier-persistence",
		"history",
		input,
		observations,
		{
			scenarios: copy(observations),
			initialSummary,
			tailMessages,
			processed: copy(processed),
		},
	);
}

describe("Watershed Identifier oracle", () => {
	it("captures the pinned Identifier contract", async () => {
		const output = process.env.WATERSHED_ORACLE_OUTPUT;
		assert(output !== undefined && isAbsolute(output), "WATERSHED_ORACLE_OUTPUT must be absolute");
		assert.equal(process.env.WATERSHED_ORACLE_COMMIT, reference.commit);
		mkdirSync(output, { recursive: true });
		const cases = [
			captureSchema(),
			await captureValues(),
			captureFieldBatches(),
			await capturePersistence(),
		];
		writeFileSync(
			join(output, "identifier-cases.json"),
			`${JSON.stringify(cases, undefined, 2)}\n`,
			"utf8",
		);
	});
});
