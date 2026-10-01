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
	deserializeIdCompressor,
	isFinalId,
	isStableId,
	serializeIdCompressor,
	toIdCompressorWithCore,
} from "@fluidframework/id-compressor/internal";
import {
	MockDeltaConnection,
	MockFluidDataStoreRuntime,
	MockSharedObjectServices,
	MockStorage,
} from "@fluidframework/test-runtime-utils/internal";

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
import {
	MockContainerRuntimeFactoryWithOpBunching,
	MockContainerRuntimeWithOpBunching,
} from "./mocksForOpBunching.js";
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
	unknown: assertIsSessionId("50000000-0000-4000-8000-000000000005"),
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
	pairOnly: sf.string,
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
type ConstructResult = {
	value: Record<string, unknown>;
	allocationEvents: ReturnType<typeof allocationEvents>;
};
type ValueExecution = {
	input: { id: string; actions: object[] };
	before: unknown;
	after: unknown;
	result?: ConstructResult[];
	refusal?: ReturnType<typeof errorObservation>;
	beforeNode?: number;
	afterNode?: number;
	allocationEvents?: ReturnType<typeof allocationEvents>;
	messages?: Record<string, unknown>[];
};
type PersistenceExecution = {
	input: { id: string; actions: object[] };
	before: unknown;
	after: unknown;
	summary?: unknown;
	initialAllocationEvents?: ReturnType<typeof allocationEvents>;
	idRanges?: unknown[];
	messages?: unknown[];
	generated?: string;
	visible?: boolean;
	compressorAdvanced?: boolean;
	identifier?: string;
	peerObserved?: boolean;
	repair?: unknown[];
	beforeNode?: string;
	afterNode?: string;
	identityPreserved?: boolean;
};
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
type FixedProvider = {
	trees: TreeInstance[];
	compressors: IIdCompressor[];
	runtimes: MockContainerRuntimeWithOpBunching[];
	synchronizeMessages: () => void;
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
	} catch (error) {
		return errorObservation(error);
	}
	assert.fail("Expected the operation to be refused.");
}

function captureOutcome(run: () => unknown) {
	try {
		run();
		return { upstreamAccepted: true };
	} catch (error) {
		return { upstreamAccepted: false, ...errorObservation(error) };
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

function fixedProvider(initialCompressor: string, treeCount = 2): FixedProvider {
	const factory = sharedTreeFactory();
	const runtimeFactory = new MockContainerRuntimeFactoryWithOpBunching();
	const treeSessions = [sessions.local, sessions.remote];
	const trees: TreeInstance[] = [];
	const compressors: IIdCompressor[] = [];
	const runtimes: MockContainerRuntimeWithOpBunching[] = [];
	for (let index = 0; index < treeCount; index++) {
		const compressor = index === 0
			? deserializeIdCompressor(initialCompressor as never)
			: createIdCompressor(treeSessions[index]);
		const runtime = new MockFluidDataStoreRuntime({
			clientId: `identifier-client-${index}`,
			id: `identifier-tree-${index}`,
			idCompressor: compressor,
		});
		const tree = factory.create(runtime, `identifier-tree-${index}`) as TreeInstance;
		const containerRuntime = runtimeFactory.createContainerRuntime(runtime);
		tree.connect({
			deltaConnection: runtime.createDeltaConnection(),
			objectStorage: new MockStorage(),
		});
		Reflect.set(tree, "containerRuntime", containerRuntime);
		trees.push(tree);
		compressors.push(compressor);
		runtimes.push(containerRuntime);
	}
	return {
		trees,
		compressors,
		runtimes,
		synchronizeMessages: () => runtimeFactory.processAllMessages(),
	};
}

function trackedAllocations(compressor: IIdCompressor) {
	const generated: { ordinal: number; id: number }[] = [];
	const original = compressor.generateCompressedId.bind(compressor);
	Reflect.set(compressor, "generateCompressedId", () => {
		const id = original();
		generated.push({ ordinal: generated.length + 1, id });
		return id;
	});
	return generated;
}

function identifierEntries(value: Point | Pair | Root) {
	const entries: { path: (string | number)[]; value: string }[] = [];
	const stack: { path: (string | number)[]; value: Point | Pair | Root }[] = [{
		path: [],
		value,
	}];
	while (stack.length > 0) {
		const current = stack.pop();
		assert(current !== undefined);
		if (current.value instanceof Point) {
			entries.push({ path: [...current.path, "id"], value: current.value.id });
		} else if (current.value instanceof Pair) {
			entries.push(
				{ path: [...current.path, "firstId"], value: current.value.firstId },
				{ path: [...current.path, "secondId"], value: current.value.secondId },
			);
		} else {
			for (const [key, item] of [...current.value.byKey].reverse()) {
				stack.push({ path: [...current.path, "byKey", key], value: item });
			}
			for (let index = current.value.right.length - 1; index >= 0; index--) {
				stack.push({ path: [...current.path, "right", index], value: current.value.right[index] });
			}
			for (let index = current.value.left.length - 1; index >= 0; index--) {
				stack.push({ path: [...current.path, "left", index], value: current.value.left[index] });
			}
			stack.push({ path: [...current.path, "child"], value: current.value.child });
		}
	}
	return entries;
}

function allocationEvents(
	compressor: IIdCompressor,
	generated: { ordinal: number; id: number }[],
	value: Point | Pair | Root,
	revision?: unknown,
) {
	const paths = new Map<number, (string | number)[]>();
	for (const entry of identifierEntries(value)) {
		if (!isStableId(entry.value)) continue;
		const compressed = compressor.tryRecompress(entry.value as never);
		if (compressed !== undefined) {
			paths.set(compressor.normalizeToOpSpace(compressed), entry.path);
		}
	}
	return generated.map(({ ordinal, id }) => {
		const op = compressor.normalizeToOpSpace(id as never);
		const path = paths.get(op);
		if (path !== undefined) return { ordinal, kind: "identifier", path, op };
		assert(
			id === revision || op === revision,
			`Unclassified allocation ${op}`,
		);
		return { ordinal, kind: "revision", path: [], op };
	});
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

function interceptRuntime(runtime: MockContainerRuntimeWithOpBunching): unknown[] {
	const processed: unknown[] = [];
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

function baseInput(
	scenarios: object[],
	compressor: IIdCompressor,
	initialTree: unknown = {
		schema: Root.identifier,
		fields: {
			child: {
				schema: Point.identifier,
				fields: { id: "literal-custom-id", label: "initial" },
			},
			left: [],
			right: [],
			byKey: [],
		},
	},
): IdentifierInput {
	return {
		version: 1,
		schema: schemaJson(Root),
		initialTree,
		sessions,
		compressors: { initial: compressorInput(compressor) },
		idRanges: [],
		scenarios,
	};
}

function captureSchema() {
	assert.throws(
		() => captureRefusal(() => undefined),
		/Expected the operation to be refused/,
	);
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
	const numberOutcome = captureOutcome(() =>
		new TreeViewConfiguration({ schema: NumberIdentifier }));
	const unionOutcome = captureOutcome(() =>
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
		scenario("non-string-refusal", [{
			op: "validate-schema",
			schema: schemaJson(NumberIdentifier),
			nativeProfileSupported: false,
		}]),
		scenario("union-refusal", [{
			op: "validate-schema",
			schema: schemaJson(UnionIdentifier),
			nativeProfileSupported: false,
		}]),
		scenario("identifier-to-value", [{ op: "compare-schema", from: "Identifier", to: "Value" }]),
		scenario("value-to-identifier-refusal", [{ op: "compare-schema", from: "Value", to: "Identifier" }]),
		scenario("canonical-field-change", [{ op: "decode-field-change", encoded: 0 }]),
	];
	const observations = [
		observe("valid-string-field", { field: point.kind.object.id }),
		observe("two-identifier-fields", {
			fields: [pair.kind.object.firstId, pair.kind.object.secondId],
		}),
		observe("non-string-refusal", {
			...numberOutcome,
			nativeProfileSupported: false,
		}),
		observe("union-refusal", {
			...unionOutcome,
			nativeProfileSupported: false,
		}),
		observe("identifier-to-value", { allowed: identifierToValue }),
		observe("value-to-identifier-refusal", { allowed: valueToIdentifier }),
		observe("canonical-field-change", { encoded: canonical, decodedNoncanonical }),
	];
	return caseFile(
		"identifier-schema",
		"schema",
		baseInput(scenarios, compressor),
		observations,
		{
			scenarios: scenarios.map((input, index) => ({
				id: input.id,
				input: copy(input),
				before: null,
				after: copy(observations[index]),
				observation: copy(observations[index]),
			})),
			persisted,
		},
	);
}

function pointInput(value: { fields: Record<string, unknown> }) {
	return copy(value.fields);
}

function pairInput(value: { fields: Record<string, unknown> }) {
	return copy(value.fields);
}

function typedItem(
	view: object,
	value: { schema: string; fields: Record<string, unknown> },
) {
	const manager = Reflect.get(view, "nodeKeyManager") as {
		generateLocalNodeIdentifier: () => unknown;
		stabilizeNodeIdentifier: (id: unknown) => string;
	};
	const identifier = () =>
		manager.stabilizeNodeIdentifier(manager.generateLocalNodeIdentifier());
	if (value.schema === Pair.identifier) {
		return new Pair({
			...pairInput(value),
			firstId: value.fields.firstId ?? identifier(),
			secondId: value.fields.secondId ?? identifier(),
		} as never);
	}
	return new Point({
		...pointInput(value),
		id: value.fields.id ?? identifier(),
	} as never);
}

function rootInput(value: {
	fields: {
		child: { fields: Record<string, unknown> };
		left: { schema: string; fields: Record<string, unknown> }[];
		right: { schema: string; fields: Record<string, unknown> }[];
		byKey: [string, { schema: string; fields: Record<string, unknown> }][];
	};
}, view?: object) {
	const item = (entry: { schema: string; fields: Record<string, unknown> }) =>
		view === undefined
			? entry.schema === Pair.identifier ? pairInput(entry) : pointInput(entry)
			: typedItem(view, entry);
	const left = new Array(value.fields.left.length);
	for (let index = value.fields.left.length - 1; index >= 0; index--) {
		left[index] = item(value.fields.left[index]);
	}
	const right = new Array(value.fields.right.length);
	for (let index = value.fields.right.length - 1; index >= 0; index--) {
		right[index] = item(value.fields.right[index]);
	}
	const byKey = new Map<string, Point | Pair | Record<string, unknown>>();
	for (let index = value.fields.byKey.length - 1; index >= 0; index--) {
		const [key, entry] = value.fields.byKey[index];
		byKey.set(key, item(entry));
	}
	return {
		child: pointInput(value.fields.child),
		left,
		right,
		byKey,
	};
}

function constructValue(
	input: IdentifierInput,
	action: { schema: string; fields: Record<string, unknown> },
): ConstructResult {
	const provider = fixedProvider(input.compressors.initial, 1);
	const processed = interceptRuntime(provider.runtimes[0]);
	const generated = trackedAllocations(provider.compressors[0]);
	if (action.schema === Point.identifier) {
		const view = provider.trees[0].viewWith(new TreeViewConfiguration({ schema: Point }));
		view.initialize(pointInput(action) as never);
		provider.synchronizeMessages();
		const revision = messagesIn(processed).at(-1)?.revision;
		return {
			value: { id: view.root.id, label: view.root.label },
			allocationEvents: allocationEvents(
				provider.compressors[0], generated, view.root, revision,
			),
		};
	}
	if (action.schema === Pair.identifier) {
		const view = provider.trees[0].viewWith(new TreeViewConfiguration({ schema: Pair }));
		view.initialize(pairInput(action) as never);
		provider.synchronizeMessages();
		const revision = messagesIn(processed).at(-1)?.revision;
		return {
			value: {
				firstId: view.root.firstId,
				secondId: view.root.secondId,
				label: view.root.label,
			},
			allocationEvents: allocationEvents(
				provider.compressors[0], generated, view.root, revision,
			),
		};
	}
	assert.equal(action.schema, Root.identifier);
	const view = provider.trees[0].viewWith(new TreeViewConfiguration({ schema: Root }));
	view.initialize(rootInput(action as never, view) as never);
	provider.synchronizeMessages();
	const revision = messagesIn(processed).at(-1)?.revision;
	return {
		value: visible(view.root) as unknown as Record<string, unknown>,
		allocationEvents: allocationEvents(
			provider.compressors[0], generated, view.root, revision,
		),
	};
}

function executeValueScenario(input: IdentifierInput, item: {
	id: string;
	actions: {
		op: string;
		path?: (string | number)[];
		index?: number;
		value?: { schema: string; fields: Record<string, unknown> } | string;
		schema?: string;
		fields?: Record<string, unknown>;
	}[];
}): ValueExecution {
	if (item.actions.every(({ op }) => op === "construct")) {
		const results = item.actions.map((action) =>
			constructValue(input, action as { schema: string; fields: Record<string, unknown> }));
		return {
			input: copy(item),
			before: null,
			after: results.map(({ value }) => value),
			result: results,
		};
	}
	const provider = fixedProvider(input.compressors.initial, 1);
	const processed = interceptRuntime(provider.runtimes[0]);
	const view = provider.trees[0].viewWith(new TreeViewConfiguration({ schema: Root }));
	view.initialize(rootInput(input.initialTree as never, view) as never);
	provider.synchronizeMessages();
	const before = visible(view.root);
	processed.length = 0;
	const generated = trackedAllocations(provider.compressors[0]);
	let refusal: ReturnType<typeof errorObservation> | undefined;
	let beforeNode: number | undefined;
	let afterNode: number | undefined;
	const nodeTokens = new WeakMap<object, number>();
	let nextNodeToken = 1;
	const token = (node: object) => {
		const existing = nodeTokens.get(node);
		if (existing !== undefined) return existing;
		const next = nextNodeToken++;
		nodeTokens.set(node, next);
		return next;
	};
	for (const action of item.actions) {
		if (action.op === "insert") {
			assert.deepEqual(action.path, ["left"]);
			assert(typeof action.index === "number" && typeof action.value === "object");
			view.root.left.insertAt(
				action.index,
				typedItem(view, action.value),
			);
		} else if (action.op === "set" && action.path?.at(-1) === "id") {
			refusal = captureRefusal(() => {
				view.root.child.id = action.value as string;
			});
		} else if (action.op === "clear") {
			refusal = captureRefusal(() => {
				delete (view.root.child as { id?: string }).id;
			});
		} else if (action.op === "set") {
			assert.deepEqual(action.path, ["child"]);
			assert(typeof action.value === "object");
			beforeNode = token(view.root.child);
			view.root.child = pointInput(action.value) as never;
			afterNode = token(view.root.child);
		} else {
			assert.fail(`Unsupported Identifier value action: ${action.op}`);
		}
	}
	provider.synchronizeMessages();
	const after = visible(view.root);
	const revision = messagesIn(processed).at(-1)?.revision;
	return {
		input: copy(item),
		before,
		after,
		refusal,
		beforeNode,
		afterNode,
		allocationEvents: allocationEvents(
			provider.compressors[0], generated, view.root, revision,
		),
		messages: messagesIn(processed),
	};
}

async function captureValues() {
	const compressor = createIdCompressor(sessions.local);
	compressor.generateCompressedId();
	const compressorCore = toIdCompressorWithCore(compressor);
	compressorCore.finalizeCreationRange(compressorCore.takeNextCreationRange());
	const uuid = "11111111-2222-4333-8444-555555555555";
	const scenarios = [
		scenario("custom-string", [{ op: "construct", schema: Point.identifier, fields: { id: "custom-id", label: "custom" } }]),
		scenario("empty-string", [{ op: "construct", schema: Point.identifier, fields: { id: "", label: "empty" } }]),
		scenario("uuid", [{ op: "construct", schema: Point.identifier, fields: { id: uuid, label: "uuid" } }]),
		scenario("duplicate-custom-strings", [
			{ op: "construct", schema: Point.identifier, fields: { id: "duplicate", label: "a" } },
			{ op: "construct", schema: Point.identifier, fields: { id: "duplicate", label: "b" } },
		]),
		scenario("omitted-default", [{ op: "construct", schema: Point.identifier, fields: { label: "generated" } }]),
		scenario("multiple-defaults", [{
			op: "construct",
			schema: Pair.identifier,
			fields: { label: "pair", pairOnly: "pair" },
		}]),
		scenario("nested-insertion", [{
			op: "construct",
			schema: Root.identifier,
			fields: {
				child: { schema: Point.identifier, fields: { label: "child" } },
				left: [{ schema: Point.identifier, fields: { label: "array" } }],
				right: [],
				byKey: [["map", { schema: Point.identifier, fields: { label: "map" } }]],
			},
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
			value: {
				schema: Pair.identifier,
				fields: { label: "allocation", pairOnly: "allocation" },
			},
		}]),
	];
	const input = baseInput(scenarios, compressor, {
		schema: Root.identifier,
		fields: {
			child: {
				schema: Point.identifier,
				fields: { id: "attached-child", label: "child" },
			},
			left: [{
				schema: Point.identifier,
				fields: { id: "left", label: "left" },
			}],
			right: [],
			byKey: [],
		},
	});
	const executions = scenarios.map((item) => executeValueScenario(input, item as never));
	const execution = (id: string) => {
		const found = executions.find((item) => item.input.id === id);
		assert(found !== undefined);
		return found;
	};
	const constructed = (id: string, index = 0) => {
		const result = execution(id).result?.[index];
		assert(result !== undefined);
		return result;
	};
	const observations = [
		observe("custom-string", { value: constructed("custom-string").value.id }),
		observe("empty-string", { value: constructed("empty-string").value.id }),
		observe("uuid", { value: constructed("uuid").value.id }),
		observe("duplicate-custom-strings", {
			values: [0, 1].map((index) =>
				constructed("duplicate-custom-strings", index).value.id),
		}),
		observe("omitted-default", { value: constructed("omitted-default").value.id }),
		observe("multiple-defaults", {
			values: [
				constructed("multiple-defaults").value.firstId,
				constructed("multiple-defaults").value.secondId,
			],
		}),
		observe("nested-insertion", {
			value: constructed("nested-insertion").value,
			allocationEvents: constructed("nested-insertion").allocationEvents,
		}),
		observe("direct-assignment-refusal", {
			refused: true,
			...execution("direct-assignment-refusal").refusal,
		}),
		observe("clear-refusal", {
			refused: true,
			...execution("clear-refusal").refusal,
		}),
		observe("parent-replacement", {
			value: (execution("parent-replacement").after as ReturnType<typeof visible>).child,
		}),
		observe("allocation-order", {
			events: execution("allocation-order").allocationEvents,
		}),
	];
	return caseFile(
		"identifier-values",
		"values",
		input,
		observations,
		{
			scenarios: executions.map((item, index) => ({
				id: item.input.id,
				...copy(item),
				observation: copy(observations[index]),
			})),
		},
	);
}

function decodeIdentifier(value: unknown, context: IdDecodingContext) {
	return readValue(
		{ data: [value] as never[], offset: 0 },
		SpecialField.Identifier,
		context,
	);
}

function executeFieldScenario(input: IdentifierInput, item: {
	id: string;
	actions: {
		op: string;
		compressor?: string;
		range?: number;
		encoded?: { value: unknown };
		value?: string;
		purpose?: "message" | "summary";
		originator?: typeof sessions[keyof typeof sessions];
	}[];
}) {
	const compressors = Object.fromEntries(Object.entries(input.compressors).map(
		([name, serialized]) => [
			name,
			toIdCompressorWithCore(deserializeIdCompressor(serialized as never)),
		],
	));
	const before = Object.fromEntries(Object.entries(compressors).map(
		([name, value]) => [name, serializeIdCompressor(value, true)],
	));
	const results: { op: string; value: unknown }[] = [];
	const errors: { op: string; value: unknown; originalError: string; nativeErrorCategory: string }[] = [];
	for (const action of item.actions) {
		if (action.op === "allocate-id") {
			assert(action.compressor !== undefined);
			const compressor = compressors[action.compressor];
			assert(compressor !== undefined);
			const id = compressor.generateCompressedId();
			results.push({
				op: action.op,
				value: {
					stable: compressor.decompress(id),
					encoded: compressor.normalizeToOpSpace(id),
				},
			});
		} else if (action.op === "deliver-range") {
			assert(action.compressor !== undefined && action.range !== undefined);
			const compressor = compressors[action.compressor];
			const range = input.idRanges[action.range];
			assert(compressor !== undefined && range !== undefined);
			compressor.finalizeCreationRange(range as never);
			results.push({ op: action.op, value: copy(range) });
		} else if (action.op === "decode-field-batch") {
			assert(action.encoded !== undefined && action.purpose !== undefined);
			const compressor = compressors[action.compressor ?? "initial"];
			assert(compressor !== undefined);
			let context: IdDecodingContext;
			if (action.purpose === "message") {
				assert(action.originator !== undefined);
				context = new IdDecodingContext({
					idCompressor: compressor,
					originatorId: action.originator,
				});
			} else {
				context = new IdDecodingContext({ idCompressor: compressor, healing: undefined });
			}
			try {
				results.push({
					op: action.op,
					value: decodeIdentifier(action.encoded.value, context),
				});
			} catch (error) {
				errors.push({
					op: action.op,
					value: copy(action.encoded.value),
					...errorObservation(error),
				});
			}
		} else if (action.op === "encode-field-batch") {
			assert(action.value !== undefined && action.purpose !== undefined);
			results.push({
				op: action.op,
				value: encodePossiblyCompressedId(
					action.value,
					compressors.initial,
					action.purpose === "message"
						? EncodedIdType.OriginatorDependent
						: EncodedIdType.Originatorless,
				),
			});
		} else {
			assert.fail(`Unsupported Identifier FieldBatch action: ${action.op}`);
		}
	}
	return {
		id: item.id,
		input: copy(item),
		before,
		after: {
			compressors: Object.fromEntries(Object.entries(compressors).map(
				([name, value]) => [name, serializeIdCompressor(value, true)],
			)),
			results: copy(results),
			errors: copy(errors),
		},
		results,
		errors,
	};
}

function captureFieldBatches() {
	assert.equal(SpecialField.Identifier, 0);
	const local = toIdCompressorWithCore(createIdCompressor(sessions.local));
	const remote = toIdCompressorWithCore(createIdCompressor(sessions.remote));
	const summary = toIdCompressorWithCore(createIdCompressor(sessions.summary));
	const localInitial = serializeIdCompressor(local, true);
	const remoteInitial = serializeIdCompressor(remote, true);
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

	const establishedId = summary.generateCompressedId();
	const eagerRange = summary.takeNextCreationRange();
	summary.finalizeCreationRange(eagerRange);
	assert(isFinalId(summary.normalizeToOpSpace(establishedId)));
	const summaryInitial = serializeIdCompressor(summary, true);
	const eagerId = summary.generateCompressedId();
	const eagerStable = summary.decompress(eagerId);
	const eagerEncoded = encodePossiblyCompressedId(
		eagerStable,
		summary,
		EncodedIdType.Originatorless,
	);
	assert.equal(typeof eagerEncoded, "number");
	assert(isFinalId(eagerEncoded as OpSpaceCompressedId));
	const eagerDecoded = decodeIdentifier(
		eagerEncoded,
		new IdDecodingContext({ idCompressor: summary, healing: undefined }),
	);
	assert.equal(eagerDecoded, eagerStable);

	const unknownCompressor = createIdCompressor(sessions.unknown);
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
		scenario("local-negative-op-id", [
			{ op: "allocate-id", compressor: "initial" },
			{ op: "decode-field-batch", path: ["identifier"], encoded: { value: localOp }, purpose: "message", originator: sessions.local },
		]),
		scenario("remote-finalized-id", [
			{ op: "allocate-id", compressor: "remote" },
			{ op: "deliver-range", compressor: "initial", range: 0 },
			{ op: "decode-field-batch", path: ["identifier"], encoded: { value: remoteOp }, purpose: "message", originator: sessions.remote },
		]),
		scenario("eager-final-id", [
			{ op: "allocate-id", compressor: "summary" },
			{ op: "decode-field-batch", compressor: "summary", path: ["identifier"], encoded: { value: eagerEncoded }, purpose: "summary" },
		]),
		scenario("unknown-uuid-string", [{ op: "encode-field-batch", path: ["identifier"], value: unknownStable, purpose: "message" }]),
		scenario("message-summary-same-id", [
			{ op: "allocate-id", compressor: "remote" },
			{ op: "deliver-range", compressor: "initial", range: 0 },
			{ op: "encode-field-batch", path: ["identifier"], value: remoteStable, purpose: "message", originator: sessions.local },
			{ op: "encode-field-batch", path: ["identifier"], value: remoteStable, purpose: "summary" },
		]),
		scenario("unfinalized-summary-string", [
			{ op: "allocate-id", compressor: "initial" },
			{ op: "encode-field-batch", path: ["identifier"], value: localStable, purpose: "summary" },
		]),
		scenario("numeric-originatorless-refusal", [
			{ op: "allocate-id", compressor: "initial" },
			{ op: "decode-field-batch", path: ["identifier"], encoded: { value: localOp }, purpose: "summary" },
		]),
		scenario("invalid-payload-shapes", [
			{ op: "allocate-id", compressor: "initial" },
			...invalidPayloads.map(({ value }) => ({
				op: "decode-field-batch",
				path: ["identifier"],
				encoded: { value },
				purpose: "message",
				originator: sessions.local,
			})),
		]),
	];
	const observations = [
		observe("literal-zero-string", { decoded: "0", discriminator: SpecialField.Identifier }),
		observe("local-negative-op-id", { encoded: localOp, decoded: localStable }),
		observe("remote-finalized-id", { encoded: remoteOp, decoded: remoteStable }),
		observe("eager-final-id", {
			encoded: eagerEncoded,
			value: eagerStable,
			decodedByUpstream: eagerDecoded,
			allocatedAfterFinalization: true,
		}),
		observe("unknown-uuid-string", { encoded: unknownStable }),
		observe("message-summary-same-id", { message: messageEncoded, summary: summaryEncoded }),
		observe("unfinalized-summary-string", { encoded: unfinalizedSummary }),
		observe("numeric-originatorless-refusal", { refused: true, ...originatorlessRefusal }),
		observe("invalid-payload-shapes", { refusals: invalidPayloads }),
	];
	const input = baseInput(scenarios, local);
	input.compressors.initial = localInitial;
	input.compressors.remote = remoteInitial;
	input.compressors.summary = summaryInitial;
	input.idRanges = [remoteRange, eagerRange];
	const executions = scenarios.map((item) => executeFieldScenario(input, item as never));
	const executed = (id: string) => {
		const value = executions.find((item) => item.id === id);
		assert(value !== undefined);
		return value;
	};
	assert.equal(executed("literal-zero-string").results[0].value, "0");
	assert.equal(executed("local-negative-op-id").results.at(-1)?.value, localStable);
	assert.equal(executed("remote-finalized-id").results.at(-1)?.value, remoteStable);
	assert.equal(executed("eager-final-id").results.at(-1)?.value, eagerStable);
	assert.equal(executed("unknown-uuid-string").results[0].value, unknownStable);
	assert.equal(executed("message-summary-same-id").results.at(-2)?.value, messageEncoded);
	assert.equal(executed("message-summary-same-id").results.at(-1)?.value, summaryEncoded);
	assert.equal(executed("unfinalized-summary-string").results.at(-1)?.value, unfinalizedSummary);
	assert.equal(executed("numeric-originatorless-refusal").errors.length, 1);
	assert.equal(executed("invalid-payload-shapes").errors.length, invalidPayloads.length);
	return caseFile(
		"identifier-field-batches",
		"codec",
		input,
		observations,
		{
			scenarios: executions.map((execution, index) => ({
				...copy(execution),
				observation: copy(observations[index]),
			})),
			discriminator: SpecialField.Identifier,
		},
	);
}

async function prepareSummaryTail(input: IdentifierInput) {
	const provider = fixedProvider(input.compressors.initial);
	const processed = interceptRuntime(provider.runtimes[0]);
	const view = provider.trees[0].viewWith(new TreeViewConfiguration({ schema: Root }));
	view.initialize(rootInput(input.initialTree as never, view) as never);
	provider.synchronizeMessages();
	const summary = (await provider.trees[0].summarize(true)).summary;
	const summaryCompressor = serializeIdCompressor(provider.compressors[0], false);
	processed.length = 0;
	view.root.byKey.set("tail", { label: "tail" });
	provider.synchronizeMessages();
	const idRanges = processed.flatMap((message) => {
		const contents = (message as { contents?: {
			type?: string;
			contents?: unknown;
		} }).contents;
		return contents?.type === "idAllocation" ? [copy(contents.contents)] : [];
	});
	const messages = processed.filter((message) => {
		const contents = (message as { contents?: Record<string, unknown> }).contents;
		return contents !== undefined && "changeset" in contents;
	}).map(copy);
	assert(idRanges.length > 0);
	assert(messages.length > 0);
	return scenario("summary-tail", [
		{
			op: "load-summary",
			purpose: "summary",
			summary,
			compressor: summaryCompressor,
			session: sessions.summary,
		},
		{
			op: "apply-tail",
			purpose: "message",
			idRanges,
			messages,
		},
	]);
}

async function loadSummaryTail(item: {
	id: string;
	actions: {
		op: string;
		summary?: unknown;
		compressor?: string;
		session?: typeof sessions.summary;
		idRanges?: unknown[];
		messages?: Record<string, unknown>[];
	}[];
}): Promise<PersistenceExecution> {
	const load = item.actions.find(({ op }) => op === "load-summary");
	const apply = item.actions.find(({ op }) => op === "apply-tail");
	assert(load?.summary !== undefined && load.compressor !== undefined && load.session !== undefined);
	assert(apply?.idRanges !== undefined && apply.messages !== undefined);
	const compressor = deserializeIdCompressor(load.compressor as never, load.session);
	const runtime = new MockFluidDataStoreRuntime({ idCompressor: compressor });
	const services = MockSharedObjectServices.createFromSummary(load.summary as never);
	services.deltaConnection = new MockDeltaConnection(() => 1, () => {});
	const tree = await sharedTreeFactory().load(
		runtime,
		"identifier-summary-reader",
		services,
		sharedTreeFactory().attributes,
	);
	const view = tree.viewWith(new TreeViewConfiguration({ schema: Root }));
	const before = visible(view.root);
	const compressorCore = toIdCompressorWithCore(compressor);
	for (const range of apply.idRanges) compressorCore.finalizeCreationRange(range as never);
	const kernel = Reflect.get(tree, "kernel") as object;
	const process = Reflect.get(kernel, "processMessagesCore");
	assert(typeof process === "function");
	for (const message of apply.messages) {
		process.call(kernel, {
			envelope: {
				clientId: message.clientId,
				clientSequenceNumber: message.clientSequenceNumber,
				contents: message.contents,
				referenceSequenceNumber: message.referenceSequenceNumber,
				sequenceNumber: message.sequenceNumber,
				minimumSequenceNumber: message.minimumSequenceNumber,
				timestamp: 0,
				type: "op",
			},
			local: false,
			messagesContent: [{
				contents: message.contents,
				localOpMetadata: undefined,
				clientSequenceNumber: message.clientSequenceNumber,
			}],
		});
	}
	return {
		input: copy(item),
		before,
		after: visible(view.root),
		idRanges: copy(apply.idRanges),
		messages: copy(apply.messages),
	};
}

async function executePersistenceScenario(input: IdentifierInput, item: {
	id: string;
	actions: {
		op: string;
		path?: (string | number)[];
		from?: (string | number)[];
		to?: (string | number)[];
		index?: number;
		count?: number;
		result?: string;
		actions?: object[];
		value?: { schema: string; fields: Record<string, unknown> };
	}[];
}): Promise<PersistenceExecution> {
	if (item.id === "summary-tail") return loadSummaryTail(item as never);
	const provider = fixedProvider(input.compressors.initial);
	const processed = interceptRuntime(provider.runtimes[0]);
	const generated = trackedAllocations(provider.compressors[0]);
	const view = provider.trees[0].viewWith(new TreeViewConfiguration({ schema: Root }));
	view.initialize(rootInput(input.initialTree as never, view) as never);
	provider.synchronizeMessages();
	const peer = provider.trees[1].viewWith(new TreeViewConfiguration({ schema: Root }));
	const initialRevision = messagesIn(processed).at(-1)?.revision;
	const initialAllocationEvents = allocationEvents(
		provider.compressors[0], generated, view.root, initialRevision,
	);
	const before = visible(view.root);
	processed.length = 0;
	const compressorBefore = serializeIdCompressor(provider.compressors[0], true);
	let generatedIdentifier: string | undefined;
	let removedIdentifier: string | undefined;
	let repair: unknown[] | undefined;
	let movedIdentifier: string | undefined;
	let movedNode: Point | Pair | undefined;
	const replacementNodes: object[] = [];
	let summary: unknown;
	const runActions = (actions: typeof item.actions): void => {
		for (const action of actions) {
			if (action.op === "transaction") {
				const result = Tree.runTransaction(view, () => {
					runActions(action.actions as typeof item.actions);
					return action.result === "rollback" ? Tree.runTransaction.rollback : undefined;
				});
				assert(action.result !== "rollback" || result === Tree.runTransaction.rollback);
			} else if (action.op === "insert") {
				assert.deepEqual(action.path, ["left"]);
				assert(action.index !== undefined && action.value !== undefined);
				view.root.left.insertAt(action.index, typedItem(view, action.value));
				const inserted = view.root.left[action.index];
				generatedIdentifier = inserted instanceof Pair ? inserted.firstId : inserted.id;
			} else if (action.op === "disconnect") {
				provider.runtimes[0].connected = false;
			} else if (action.op === "reconnect") {
				provider.runtimes[0].connected = true;
			} else if (action.op === "resubmit") {
				provider.synchronizeMessages();
			} else if (action.op === "remove") {
				assert.deepEqual(action.path, ["left"]);
				assert(action.index !== undefined && action.count !== undefined);
				const removed = view.root.left[action.index];
				removedIdentifier = removed instanceof Pair ? removed.firstId : removed.id;
				view.root.left.removeRange(action.index, action.index + action.count);
				const snapshot = Reflect.get(provider.trees[0], "contentSnapshot") as
					() => { removed: unknown[] };
				repair = copy(snapshot.call(provider.trees[0]).removed);
			} else if (action.op === "set") {
				assert.deepEqual(action.path, ["child"]);
				assert(action.value !== undefined);
				view.root.child = pointInput(action.value) as never;
				replacementNodes.push(view.root.child);
			} else if (action.op === "move") {
				assert.deepEqual(action.from, ["left", 0]);
				assert.deepEqual(action.to, ["right", "end"]);
				assert(action.count !== undefined);
				movedNode = view.root.left[0];
				movedIdentifier = movedNode instanceof Pair ? movedNode.firstId : movedNode.id;
				view.root.right.moveRangeToEnd(0, action.count, view.root.left);
			} else if (action.op === "summarize") {
				summary = provider.trees[0].summarize(true);
			} else {
				assert.fail(`Unsupported Identifier persistence action: ${action.op}`);
			}
		}
	};
	runActions(item.actions);
	provider.synchronizeMessages();
	if (summary instanceof Promise) summary = (await summary).summary;
	const after = visible(view.root);
	const compressorAfter = serializeIdCompressor(provider.compressors[0], true);
	const nodeToken = (node: object | undefined, index: number) =>
		node === undefined ? undefined : `${index}:${Object.prototype.toString.call(node)}`;
	return {
		input: copy(item),
		before,
		after,
		summary,
		initialAllocationEvents,
		generated: generatedIdentifier,
		visible: generatedIdentifier === undefined
			? undefined
			: [...view.root.left].some((entry) =>
				(entry instanceof Pair ? entry.firstId : entry.id) === generatedIdentifier),
		compressorAdvanced: compressorBefore !== compressorAfter,
		identifier: generatedIdentifier ?? removedIdentifier ?? movedIdentifier,
		peerObserved: generatedIdentifier === undefined
			? undefined
			: [...peer.root.left].some((entry) =>
				(entry instanceof Pair ? entry.firstId : entry.id) === generatedIdentifier),
		repair,
		beforeNode: nodeToken(replacementNodes.at(-2), 1),
		afterNode: nodeToken(replacementNodes.at(-1), 2),
		identityPreserved: movedNode === view.root.right.at(-1),
		messages: copy(processed),
	};
}

async function capturePersistence() {
	const compressor = createIdCompressor(sessions.local);
	const initialTree = {
		schema: Root.identifier,
		fields: {
			child: { schema: Point.identifier, fields: { label: "child" } },
			left: [
				{ schema: Point.identifier, fields: { label: "left" } },
				{
					schema: Pair.identifier,
					fields: { label: "pair", pairOnly: "pair" },
				},
			],
			right: [],
			byKey: [],
		},
	};
	const scenarios: ReturnType<typeof scenario>[] = [
		scenario("initial-summary-defaults", [{ op: "summarize", purpose: "summary" }]),
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
		scenario("equal-custom-id-replacement", [
			{ op: "set", path: ["child"], value: { schema: Point.identifier, fields: { id: "literal-custom-id", label: "custom-before" } } },
			{ op: "set", path: ["child"], value: { schema: Point.identifier, fields: { id: "literal-custom-id", label: "custom-after" } } },
		]),
		scenario("node-moves", [{ op: "move", from: ["left", 0], to: ["right", "end"], count: 1 }]),
	];
	const input = baseInput(scenarios, compressor, initialTree);
	const tailInput = await prepareSummaryTail(input);
	scenarios.splice(1, 0, tailInput);
	const executions: PersistenceExecution[] = [];
	for (const item of scenarios) {
		executions.push(await executePersistenceScenario(input, item as never));
	}
	const execution = (id: string) => {
		const found = executions.find((item) => item.input.id === id);
		assert(found !== undefined);
		return found;
	};
	const initial = execution("initial-summary-defaults");
	const tail = execution("summary-tail");
	const aborted = execution("transaction-abort");
	const nested = execution("nested-abort");
	const retry = execution("retry-resubmit");
	const removed = execution("remove-retain-repair");
	const replaced = execution("equal-custom-id-replacement");
	const moved = execution("node-moves");
	const observations = [
		observe("initial-summary-defaults", {
			value: initial.after,
			summary: initial.summary,
			allocationEvents: initial.initialAllocationEvents,
		}),
		observe("summary-tail", {
			value: tail.after,
			before: tail.before,
			messages: tail.messages,
			idRanges: tail.idRanges,
		}),
		observe("transaction-abort", {
			generated: aborted.generated,
			visible: aborted.visible,
			compressorAdvanced: aborted.compressorAdvanced,
		}),
		observe("nested-abort", {
			generated: nested.generated,
			visible: nested.visible,
			compressorAdvanced: nested.compressorAdvanced,
		}),
		observe("retry-resubmit", { identifier: retry.identifier, peerObserved: retry.peerObserved }),
		observe("remove-retain-repair", { identifier: removed.identifier, repair: removed.repair }),
		observe("equal-custom-id-replacement", {
			identifier: "literal-custom-id",
			nodeReplaced: replaced.beforeNode !== replaced.afterNode,
			beforeNode: replaced.beforeNode,
			afterNode: replaced.afterNode,
		}),
		observe("node-moves", {
			identifier: moved.identifier,
			identityPreserved: moved.identityPreserved,
		}),
	];
	return caseFile(
		"identifier-persistence",
		"history",
		input,
		observations,
		{
			scenarios: executions.map((item, index) => ({
				id: item.input.id,
				...copy(item),
				observation: copy(observations[index]),
			})),
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
