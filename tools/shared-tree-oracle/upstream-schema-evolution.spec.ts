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
import type { SessionSpaceCompressedId } from "@fluidframework/id-compressor";
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
	tagChange,
	type TreeStoredSchema,
} from "../core/index.js";
import { FormatValidatorBasic } from "../external-utilities/index.js";
import {
	FieldBatchFormatVersion,
	TreeCompressionStrategy,
	fieldBatchCodecBuilder,
	makeSchemaChangeCodec,
} from "../feature-libraries/index.js";
import { SharedTreeChangeFamily } from "../shared-tree/sharedTreeChangeFamily.js";
import {
	checkSchemaCompatibility,
	comparePersistedSchema,
	extractPersistedSchema,
	SchemaFactory,
	toUpgradeSchema,
	TreeViewConfigurationAlpha,
	type ImplicitFieldSchema,
} from "../simple-tree/index.js";
import { configuredSharedTreeInternal } from "../treeFactory.js";
import { testIdCompressor, TestTreeProviderLite } from "./utils.js";

const formatVersion = 1;
const packageName = "@fluidframework/tree";
const packageVersion = "3.1.0";
const expectedCommit = "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960";

const historyScenarioIds = [
	"upgrade-then-edit-causal",
	"edit-then-upgrade-causal",
	"schema-data-schema-first",
	"schema-data-data-first",
	"schema-schema-left-first",
	"schema-schema-right-first",
	"same-upgrade-concurrent",
	"pending-upgrade-dependent-data-loses",
	"pending-data-remote-upgrade",
	"ack-common-prefix-keeps-upgrade",
	"empty-conflict-acknowledged",
	"rollback-retains-new-type-content",
	"old-view-invalidated",
	"new-view-reopens",
	"reconnect-upgrade-unacknowledged",
	"reconnect-upgrade-accepted-before-drop",
	"summary-before-pending-upgrade",
	"summary-upgrade-plus-tail",
	"historical-peer-schema-context",
] as const;

type SchemaBundle = ReturnType<typeof applicationSchema>;

function applicationSchema(includeScore: boolean) {
	const sf = new SchemaFactory("org.watershed.shared-tree.m4");
	class Point extends sf.object("Point", { x: sf.number, y: sf.number }) {}
	class Items extends sf.map("Items", [sf.string, Point]) {}
	const fields = {
		title: sf.string,
		point: Point,
		note: sf.optional(sf.string),
		items: Items,
	};
	const Root = includeScore
		? sf.object("Root", { ...fields, score: sf.optional(sf.number) })
		: sf.object("Root", fields);
	return { Root, Point, Items, config: new TreeViewConfigurationAlpha({ schema: Root }) };
}

function objectUnionSchema() {
	const sf = new SchemaFactory("org.watershed.shared-tree.m4");
	class Point extends sf.object("Point", { x: sf.number, y: sf.number }) {}
	class Items extends sf.map("Items", [sf.string, Point]) {}
	class Root extends sf.object("Root", {
		title: sf.string,
		point: Point,
		note: sf.optional([sf.string, sf.number]),
		items: Items,
	}) {}
	return { Root, Point, Items, config: new TreeViewConfigurationAlpha({ schema: Root }) };
}

function mapUnionSchema() {
	const sf = new SchemaFactory("org.watershed.shared-tree.m4");
	class Point extends sf.object("Point", { x: sf.number, y: sf.number }) {}
	class Items extends sf.map("Items", [sf.string, Point, sf.number]) {}
	class Root extends sf.object("Root", {
		title: sf.string,
		point: Point,
		note: sf.optional(sf.string),
		items: Items,
	}) {}
	return { Root, Point, Items, config: new TreeViewConfigurationAlpha({ schema: Root }) };
}

function optionalTitleSchema() {
	const sf = new SchemaFactory("org.watershed.shared-tree.m4");
	class Point extends sf.object("Point", { x: sf.number, y: sf.number }) {}
	class Items extends sf.map("Items", [sf.string, Point]) {}
	class Root extends sf.object("Root", {
		title: sf.optional(sf.string),
		point: Point,
		note: sf.optional(sf.string),
		items: Items,
	}) {}
	return { Root, Point, Items, config: new TreeViewConfigurationAlpha({ schema: Root }) };
}

function rootUnionSchema() {
	const bundle = applicationSchema(false);
	return {
		...bundle,
		config: new TreeViewConfigurationAlpha({ schema: [bundle.Root, SchemaFactory.string] }),
	};
}

function optionalRootSchema() {
	const bundle = applicationSchema(false);
	return {
		...bundle,
		config: new TreeViewConfigurationAlpha({ schema: SchemaFactory.optional(bundle.Root) }),
	};
}

function combinedSchema() {
	const sf = new SchemaFactory("org.watershed.shared-tree.m4");
	class Point extends sf.object("Point", { x: sf.number, y: sf.number }) {}
	class Items extends sf.map("Items", [sf.string, Point, sf.number]) {}
	class Root extends sf.object("Root", {
		title: sf.optional(sf.string),
		point: Point,
		note: sf.optional([sf.string, sf.number]),
		items: Items,
		score: sf.optional(sf.number),
	}) {}
	return {
		Root,
		Point,
		Items,
		config: new TreeViewConfigurationAlpha({ schema: SchemaFactory.optional([Root, sf.string]) }),
	};
}

function narrowSchema() {
	const sf = new SchemaFactory("org.watershed.shared-tree.m4");
	class Point extends sf.object("Point", { x: sf.number, y: sf.number }) {}
	class Items extends sf.map("Items", sf.string) {}
	class Root extends sf.object("Root", {
		title: sf.string,
		point: Point,
		note: sf.optional(sf.string),
		items: Items,
	}) {}
	return { Root, Point, Items, config: new TreeViewConfigurationAlpha({ schema: Root }) };
}

function newRequiredSchema() {
	const sf = new SchemaFactory("org.watershed.shared-tree.m4");
	class Point extends sf.object("Point", { x: sf.number, y: sf.number }) {}
	class Items extends sf.map("Items", [sf.string, Point]) {}
	class Root extends sf.object("Root", {
		title: sf.string,
		point: Point,
		note: sf.optional(sf.string),
		items: Items,
		score: sf.number,
	}) {}
	return { Root, Point, Items, config: new TreeViewConfigurationAlpha({ schema: Root }) };
}

function optionalToRequiredSchema() {
	const sf = new SchemaFactory("org.watershed.shared-tree.m4");
	class Point extends sf.object("Point", { x: sf.number, y: sf.number }) {}
	class Items extends sf.map("Items", [sf.string, Point]) {}
	class Root extends sf.object("Root", {
		title: sf.string,
		point: Point,
		note: sf.string,
		items: Items,
	}) {}
	return { Root, Point, Items, config: new TreeViewConfigurationAlpha({ schema: Root }) };
}

function nodeKindReplacementSchema() {
	const sf = new SchemaFactory("org.watershed.shared-tree.m4");
	class Point extends sf.map("Point", sf.number) {}
	class Items extends sf.map("Items", [sf.string, Point]) {}
	class Root extends sf.object("Root", {
		title: sf.string,
		point: Point,
		note: sf.optional(sf.string),
		items: Items,
	}) {}
	return { Root, Point, Items, config: new TreeViewConfigurationAlpha({ schema: Root }) };
}

function newNodeSchema() {
	const sf = new SchemaFactory("org.watershed.shared-tree.m4");
	class Point extends sf.object("Point", { x: sf.number, y: sf.number }) {}
	class Extra extends sf.object("Extra", { value: sf.string }) {}
	class Items extends sf.map("Items", [sf.string, Point]) {}
	class Root extends sf.object("Root", {
		title: sf.string,
		point: Point,
		note: sf.optional(sf.string),
		items: Items,
		extra: sf.optional(Extra),
	}) {}
	return { Root, Point, Extra, Items, config: new TreeViewConfigurationAlpha({ schema: Root }) };
}

function sequenceSchema() {
	const bundle = applicationSchema(false);
	const sf = new SchemaFactory("org.watershed.shared-tree.m4");
	return new TreeViewConfigurationAlpha({ schema: [bundle.Root, sf.array("Sequence", sf.string)] });
}

function handleSchema() {
	const bundle = applicationSchema(false);
	return new TreeViewConfigurationAlpha({ schema: [bundle.Root, SchemaFactory.handle] });
}

function persisted(schema: ImplicitFieldSchema): unknown {
	return extractPersistedSchema(schema, FluidClientVersion.v2_117, () => false);
}

function json<T>(value: T): T {
	return JSON.parse(JSON.stringify(value)) as T;
}

function losslessJson<T>(value: T): T {
	return JSON.parse(JSON.stringify(value, (_key, item: unknown) => {
		if (item instanceof Map) {
			return { $type: "Map", entries: [...item.entries()] };
		}
		if (item instanceof Set) {
			return { $type: "Set", values: [...item.values()] };
		}
		return item;
	})) as T;
}

function rootInput(bundle: SchemaBundle) {
	return new bundle.Root({
		title: "base",
		point: new bundle.Point({ x: 1, y: 2 }),
		items: new bundle.Items([["label", "value"]]),
	});
}

function rootSnapshot(tree: TestTreeProviderLite["trees"][number]) {
	const snapshot = json(tree.contentSnapshot()) as {
		tree: unknown;
		removed: unknown;
	};
	return { tree: snapshot.tree, removed: snapshot.removed };
}

function failure(action: () => void): string | undefined {
	try {
		action();
		return undefined;
	} catch (error) {
		return String(error);
	}
}

async function compatibilityCases() {
	const profiles = {
		v1: applicationSchema(false),
		optional: applicationSchema(true),
		"object-union": objectUnionSchema(),
		"map-union": mapUnionSchema(),
		"optional-title": optionalTitleSchema(),
		"root-union": rootUnionSchema(),
		"optional-root": optionalRootSchema(),
		combined: combinedSchema(),
		narrow: narrowSchema(),
		"new-required": newRequiredSchema(),
	};
	const refusalProfiles = {
		narrow: profiles.narrow.config,
		"new-required": profiles["new-required"].config,
		"optional-to-required": optionalToRequiredSchema().config,
		"node-kind-replacement": nodeKindReplacementSchema().config,
		sequence: sequenceSchema(),
		handle: handleSchema(),
	};
	const oldStored = toUpgradeSchema(profiles.v1.config.schema);
	const catalog = Object.entries(profiles).map(([id, bundle]) => ({
		id,
		raw: JSON.stringify(persisted(bundle.config.schema)),
	}));
	const compatibilityCatalog = [
		...catalog,
		...Object.entries(refusalProfiles)
			.filter(([id]) => !(id in profiles))
			.map(([id, config]) => ({
				id,
				raw: JSON.stringify(persisted(config.schema)),
			})),
	];
	const scenarios = Object.entries(profiles).map(([id, bundle]) => ({
		id,
		stored: "v1",
		requested: id,
		operation: "compatibility",
	}));
	const attempt = async (id: string, config: TreeViewConfigurationAlpha) => {
		const factory = configuredSharedTreeInternal({
			minVersionForCollab: FluidClientVersion.v2_117,
		}).getFactory();
		const provider = new TestTreeProviderLite(2, factory);
		const old = applicationSchema(false);
		const oldView = provider.trees[0].viewWith(old.config);
		oldView.initialize(rootInput(old));
		drain(provider);
		const beforeRoot = rootSnapshot(provider.trees[0]);
		oldView.dispose();
		const view = provider.trees[0].viewWith(config);
		const compatibility = json(view.compatibility);
		const error = failure(() => view.upgradeSchema());
		const messages = drain(provider);
		return {
			id,
			compatibility,
			attempt: {
				attempted: true,
				outcome: error === undefined ? "accepted" : "refused",
				error,
				submittedMessages: messages.length,
				beforeRoot,
				afterRoot: rootSnapshot(provider.trees[1]),
			},
		};
	};
	const observations = await Promise.all(Object.entries(profiles).map(([id, bundle]) =>
		attempt(id, bundle.config)));
	const refusals = Object.entries(refusalProfiles).map(([id]) => ({
		id,
		stored: "v1",
		requested: id,
		operation: "prepare-upgrade",
	}));
	const classification = (id: string) =>
		["node-kind-replacement", "sequence", "handle"].includes(id)
			? "m4-profile-exclusion"
			: "upstream-refusal";
	const refusalAttempts = await Promise.all(Object.entries(refusalProfiles).map(
		async ([id, config]) => {
			const result = await attempt(id, config);
			return {
				id,
				classification: classification(id),
				compatibility: result.compatibility,
				...result.attempt,
			};
		},
	));

	const baseRaw = JSON.stringify(persisted(profiles.v1.config.schema));
	const parsedBase = JSON.parse(baseRaw) as {
		version: number;
		nodes: Record<string, unknown>;
		root: unknown;
		[key: string]: unknown;
	};
	const rawProbe = (
		id: string,
		mutate: (schema: typeof parsedBase) => string | undefined,
	) => {
		const schema = json(parsedBase);
		const overridden = mutate(schema);
		const raw = overridden ?? JSON.stringify(schema);
		const parsed = JSON.parse(raw) as typeof parsedBase;
		return {
			input: { id, raw },
			result: {
				id,
				parsed: true,
				compatibility: json(comparePersistedSchema(
					parsed as Parameters<typeof comparePersistedSchema>[0],
					profiles.v1.config.schema,
					{ jsonValidator: FormatValidatorNoOp },
				)),
			},
		};
	};
	const probes = [
		rawProbe("metadata", (schema) => {
			schema.metadataProbe = { ignored: true };
			return undefined;
		}),
		rawProbe("duplicate-keys", (schema) => {
			const root = JSON.stringify(schema.root);
			const nodes = JSON.stringify(schema.nodes);
			return `{"version":2,"nodes":${nodes},"root":${root},"root":${root}}`;
		}),
		rawProbe("ordering", (schema) => {
			schema.nodes = Object.fromEntries(Object.entries(schema.nodes).reverse());
			return undefined;
		}),
		rawProbe("unused-definitions", (schema) => {
			schema.nodes["org.watershed.shared-tree.m4.Unused"] = { kind: { object: {} } };
			return undefined;
		}),
		rawProbe("required-cycle", (schema) => {
			schema.nodes["org.watershed.shared-tree.m4.CycleA"] = {
				kind: {
					object: {
						next: { kind: "Value", types: ["org.watershed.shared-tree.m4.CycleB"] },
					},
				},
			};
			schema.nodes["org.watershed.shared-tree.m4.CycleB"] = {
				kind: {
					object: {
						next: { kind: "Value", types: ["org.watershed.shared-tree.m4.CycleA"] },
					},
				},
			};
			schema.root = { kind: "Value", types: ["org.watershed.shared-tree.m4.CycleA"] };
			return undefined;
		}),
	];
	return {
		catalog,
		scenarios,
		observations,
		refusals,
		refusalAttempts,
		rawProbes: probes.map(({ input }) => input),
		rawProbeResults: probes.map(({ result }) => result),
		compatibilityCatalog,
		profiles,
	};
}

function drain(provider: TestTreeProviderLite): object[] {
	const messages: object[] = [];
	let message = provider.peekNextMessage();
	while (message !== undefined) {
		const captured = json(message) as unknown as Record<string, unknown>;
		provider.synchronizeMessages({ count: 1 });
		captured.sequenceNumber = provider.sequenceNumber;
		captured.minimumSequenceNumber ??= provider.minimumSequenceNumber;
		captured.indexInBatch = 0;
		messages.push(captured);
		message = provider.peekNextMessage();
	}
	return messages;
}

async function captureUpgrade() {
	const old = applicationSchema(false);
	const next = applicationSchema(true);
	const factory = configuredSharedTreeInternal({
		minVersionForCollab: FluidClientVersion.v2_117,
	}).getFactory();
	const provider = new TestTreeProviderLite(2, factory);
	const oldView = provider.trees[0].viewWith(old.config);
	oldView.initialize(rootInput(old));
	const initializationMessages = drain(provider);
	const before = { title: oldView.root.title, note: oldView.root.note };
	oldView.dispose();
	const nextView = provider.trees[0].viewWith(next.config);
	assert.equal(provider.peekNextMessage(), undefined);
	const opened = json(nextView.compatibility);
	nextView.upgradeSchema();
	const submitted = drain(provider);
	const after = {
		title: nextView.root.title,
		note: nextView.root.note,
		score: Reflect.get(nextView.root, "score") as unknown,
	};
	const summary = await provider.trees[0].summarize(true);
	nextView.upgradeSchema();
	assert.equal(provider.peekNextMessage(), undefined);
	return { before, opened, after, initializationMessages, submitted, summary: summary.summary };
}

async function captureHistoryRuntime(
	profiles: Awaited<ReturnType<typeof compatibilityCases>>["profiles"],
) {
	const factory = configuredSharedTreeInternal({
		minVersionForCollab: FluidClientVersion.v2_117,
	}).getFactory();
	const historyProfiles = { ...profiles, "new-node": newNodeSchema() };

	function schemaId(tree: TestTreeProviderLite["trees"][number]): string {
		for (const [id, bundle] of Object.entries(historyProfiles)) {
			if (checkSchemaCompatibility(bundle.config, tree.kernel.storedSchema).isEquivalent) {
				return id;
			}
		}
		return "other";
	}

	function managerState(tree: TestTreeProviderLite["trees"][number]) {
		const manager = Reflect.get(tree.kernel, "editManager") as {
			getLocalCommits(branch: string): readonly {
				revision: unknown;
				change: { changes: readonly { type: string }[] };
			}[];
			getTrunkCommits(branch: string): readonly {
				revision: unknown;
				change: { changes: readonly { type: string }[] };
			}[];
		};
		const commits = (values: readonly {
			revision: unknown;
			change: { changes: readonly { type: string }[] };
		}[]) => values.map(({ revision, change }) => ({
			revision,
			kinds: change.changes.map(({ type }) => type),
		}));
		return {
			pending: commits(manager.getLocalCommits("main")),
			trunk: commits(manager.getTrunkCommits("main")),
		};
	}

	function checkpoint(
		provider: TestTreeProviderLite,
		view: { readonly compatibility: unknown },
		messages: object[],
		events: string[],
		localIndex = 0,
		peerIndex = 1,
	) {
		const localTree = provider.trees[localIndex];
		const peerTree = provider.trees[peerIndex];
		const local = managerState(localTree);
		const sequenced = managerState(peerTree);
		return {
			visibleSchema: schemaId(localTree),
			sequencedSchema: schemaId(peerTree),
			visibleRoot: rootSnapshot(localTree),
			pendingRevisions: local.pending,
			outerChanges: [...local.pending, ...local.trunk],
			trunkRevisions: sequenced.trunk,
			peerRevisions: managerState(peerTree).trunk,
			detachedIdentities: json(localTree.kernel.checkout.getRemovedRoots()),
			compatibility: json(view.compatibility),
			events,
			sequencePoints: messages.map((message) => {
				const metadata = message as Record<string, unknown>;
				assert(Number.isSafeInteger(metadata.referenceSequenceNumber));
				assert(Number.isSafeInteger(metadata.clientSequenceNumber));
				assert(typeof metadata.clientId === "string");
				return {
					sequenceNumber: Number.isSafeInteger(metadata.sequenceNumber)
						? metadata.sequenceNumber
						: null,
					referenceSequenceNumber: metadata.referenceSequenceNumber,
					minimumSequenceNumber: Number.isSafeInteger(metadata.minimumSequenceNumber)
						? metadata.minimumSequenceNumber
						: null,
					clientSequenceNumber: metadata.clientSequenceNumber,
					clientId: metadata.clientId,
					indexInBatch: Number.isSafeInteger(metadata.indexInBatch)
						? metadata.indexInBatch
						: null,
				};
			}),
			identities: provider.trees.map((tree) => ({
				tree: tree.id,
				session: provider.getCompressor(tree).localSessionId,
				compressor: {
					state: serializeIdCompressor(provider.getCompressor(tree), false),
					allocations: messages.filter((message) =>
						Reflect.get(Reflect.get(message, "contents") ?? {}, "type") === "idAllocation"
						&& Reflect.get(
							Reflect.get(Reflect.get(message, "contents") ?? {}, "contents") ?? {},
							"sessionId",
						) === provider.getCompressor(tree).localSessionId)
						.map((message) => json(Reflect.get(
							Reflect.get(Reflect.get(message, "contents") ?? {}, "contents") ?? {},
							"ids",
						))),
				},
			})),
			messages,
		};
	}

	function initialized() {
		const provider = new TestTreeProviderLite(2, factory);
		const old = applicationSchema(false);
		const left = provider.trees[0].viewWith(old.config);
		left.initialize(rootInput(old));
		drain(provider);
		const right = provider.trees[1].viewWith(old.config);
		return { provider, old, left, right };
	}

	function events(view: { events: { on(name: "schemaChanged" | "rootChanged", listener: () => void): () => void } }) {
		const values: string[] = [];
		view.events.on("schemaChanged", () => values.push("schemaChanged"));
		view.events.on("rootChanged", () => values.push("rootChanged"));
		return values;
	}

	const hasSchemaChange = (message: object) => JSON.stringify(message).includes("\"schema\"");
	const dataChange = (message: object) => {
		const changeset = Reflect.get(Reflect.get(message, "contents") ?? {}, "changeset");
		return Array.isArray(changeset)
			&& changeset.some((change) => Reflect.has(change, "data"));
	};
	const retainedString = (value: unknown, expected: string): boolean => {
		if (value === expected) return true;
		if (Array.isArray(value)) return value.some((item) => retainedString(item, expected));
		if (value !== null && typeof value === "object") {
			return Object.values(value).some((item) => retainedString(item, expected));
		}
		return false;
	};
	const nodeWithType = (value: unknown, type: string): Record<string, unknown> | undefined => {
		if (value !== null && typeof value === "object") {
			if (Reflect.get(value, "type") === type) return value as Record<string, unknown>;
			for (const child of Object.values(value)) {
				const found = nodeWithType(child, type);
				if (found !== undefined) return found;
			}
		}
		return undefined;
	};

	const observations = new Map<
		string,
		ReturnType<typeof checkpoint> & Record<string, unknown>
	>();
	let tailSummary: unknown;

	{
		const { provider, left } = initialized();
		left.dispose();
		const next = applicationSchema(true);
		const view = provider.trees[0].viewWith(next.config);
		const log = events(view);
		view.upgradeSchema();
		Reflect.set(view.root, "score", 7);
		const messages = drain(provider);
		observations.set("upgrade-then-edit-causal", checkpoint(provider, view, messages, log));
	}
	{
		const { provider, left } = initialized();
		const log = events(left);
		left.root.title = "edited";
		const first = drain(provider);
		left.dispose();
		const next = applicationSchema(true);
		const view = provider.trees[0].viewWith(next.config);
		view.upgradeSchema();
		const messages = [...first, ...drain(provider)];
		observations.set("edit-then-upgrade-causal", checkpoint(provider, view, messages, log));
	}
	for (const schemaFirst of [true, false]) {
		const { provider, left, right } = initialized();
		left.dispose();
		const next = applicationSchema(true);
		const view = provider.trees[0].viewWith(next.config);
		const log = events(view);
		if (schemaFirst) {
			view.upgradeSchema();
			right.root.title = "data";
		} else {
			right.root.title = "data";
			view.upgradeSchema();
		}
		const messages = drain(provider);
		observations.set(
			schemaFirst ? "schema-data-schema-first" : "schema-data-data-first",
			checkpoint(provider, view, messages, log),
		);
	}
	for (const leftFirst of [true, false]) {
		const { provider, left, right } = initialized();
		left.dispose();
		right.dispose();
		const leftView = provider.trees[0].viewWith(applicationSchema(true).config);
		const rightView = provider.trees[1].viewWith(objectUnionSchema().config);
		const log = events(leftView);
		if (leftFirst) {
			leftView.upgradeSchema();
			rightView.upgradeSchema();
		} else {
			rightView.upgradeSchema();
			leftView.upgradeSchema();
		}
		const messages = drain(provider);
		observations.set(
			leftFirst ? "schema-schema-left-first" : "schema-schema-right-first",
			checkpoint(provider, leftView, messages, log),
		);
	}
	{
		const { provider, left, right } = initialized();
		left.dispose();
		right.dispose();
		const leftView = provider.trees[0].viewWith(applicationSchema(true).config);
		const rightView = provider.trees[1].viewWith(applicationSchema(true).config);
		const log = events(leftView);
		leftView.upgradeSchema();
		rightView.upgradeSchema();
		const messages = drain(provider);
		observations.set("same-upgrade-concurrent", checkpoint(provider, leftView, messages, log));
	}
	{
		const { provider, left, right } = initialized();
		left.dispose();
		const next = applicationSchema(true);
		const view = provider.trees[0].viewWith(next.config);
		const log = events(view);
		right.root.title = "wins";
		view.upgradeSchema();
		Reflect.set(view.root, "score", 7);
		const messages = drain(provider);
		observations.set(
			"pending-upgrade-dependent-data-loses",
			checkpoint(provider, view, messages, log),
		);
	}
	{
		const { provider, left, right } = initialized();
		const log = events(left);
		provider.trees[0].containerRuntime.connected = false;
		left.root.title = "pending";
		right.dispose();
		const remote = provider.trees[1].viewWith(applicationSchema(true).config);
		remote.upgradeSchema();
		const first = drain(provider);
		provider.trees[0].containerRuntime.connected = true;
		const messages = [...first, ...drain(provider)];
		observations.set("pending-data-remote-upgrade", checkpoint(provider, left, messages, log));
	}
	{
		const { provider, left } = initialized();
		left.dispose();
		const view = provider.trees[0].viewWith(applicationSchema(true).config);
		const log = events(view);
		view.upgradeSchema();
		Reflect.set(view.root, "score", 7);
		const messages: object[] = [];
		while (!messages.some(hasSchemaChange)) {
			const nextMessage = provider.peekNextMessage();
			assert(nextMessage !== undefined, "Schema acknowledgement was not queued");
			const captured = json(nextMessage) as unknown as Record<string, unknown>;
			provider.synchronizeMessages({ count: 1 });
			captured.sequenceNumber = provider.sequenceNumber;
			captured.minimumSequenceNumber ??= provider.minimumSequenceNumber;
			captured.indexInBatch = 0;
			messages.push(captured);
		}
		const commonPrefix = checkpoint(provider, view, messages, log);
		const remainingDependentEdit = commonPrefix.pendingRevisions.find(
			(change) => change.kinds.includes("data"),
		);
		assert.equal(commonPrefix.sequencedSchema, "optional");
		assert(remainingDependentEdit !== undefined, "Dependent edit must remain pending");
		observations.set(
			"ack-common-prefix-keeps-upgrade",
			{
				...commonPrefix,
				acknowledgedSchema: true,
				remainingDependentEdit,
			},
		);
		drain(provider);
	}
	{
		const { provider, left, right } = initialized();
		left.dispose();
		const view = provider.trees[0].viewWith(applicationSchema(true).config);
		const log = events(view);
		view.upgradeSchema();
		right.root.title = "conflict";
		const messages = drain(provider);
		observations.set("empty-conflict-acknowledged", checkpoint(provider, view, messages, log));
	}

	const rollbackProvider = new TestTreeProviderLite(2, factory);
	const rollbackOld = applicationSchema(false);
	const oldLeft = rollbackProvider.trees[0].viewWith(rollbackOld.config);
	const oldRight = rollbackProvider.trees[1].viewWith(rollbackOld.config);
	oldLeft.initialize(rootInput(rollbackOld));
	drain(rollbackProvider);
	oldRight.dispose();
	const widened = newNodeSchema();
	const widenedRight = rollbackProvider.trees[1].viewWith(widened.config);
	oldLeft.root.title = "wins";
	widenedRight.upgradeSchema();
	Reflect.set(widenedRight.root, "extra", new widened.Extra({ value: "retained" }));
	const losingAuthorBefore = rootSnapshot(rollbackProvider.trees[1]);
	const losingStateBefore = managerState(rollbackProvider.trees[1]);
	const losingSchemaBefore = schemaId(rollbackProvider.trees[1]);
	const rollbackCompatibility = json(widenedRight.compatibility);
	const competingMessages: object[] = [];
	while (!competingMessages.some(dataChange)) {
		const nextMessage = rollbackProvider.peekNextMessage();
		assert(nextMessage !== undefined, "Competing data edit was not queued");
		const captured = json(nextMessage) as unknown as Record<string, unknown>;
		rollbackProvider.synchronizeMessages({ count: 1 });
		captured.sequenceNumber = rollbackProvider.sequenceNumber;
		captured.minimumSequenceNumber ??= rollbackProvider.minimumSequenceNumber;
		captured.indexInBatch = 0;
		competingMessages.push(captured);
	}
	const losingAuthorAfter = rootSnapshot(rollbackProvider.trees[1]);
	const losingStateAfter = managerState(rollbackProvider.trees[1]);
	const losingSchemaAfter = schemaId(rollbackProvider.trees[1]);
	const rollbackMessages = [...competingMessages, ...drain(rollbackProvider)];
	widenedRight.dispose();
	const reopenedOld = rollbackProvider.trees[1].viewWith(rollbackOld.config);
	const detached = json(rollbackProvider.trees[1].kernel.checkout.getRemovedRoots());
	assert.equal(reopenedOld.root.title, "wins");
	assert(detached.length > 0, "Rollback must retain detached repair content");
	const retainedExtra = nodeWithType(losingAuthorBefore, widened.Extra.identifier);
	assert(retainedExtra !== undefined && retainedString(retainedExtra, "retained"),
		"Losing-author checkpoint must capture the Extra value");
	const retainedExtraFields = Reflect.get(retainedExtra, "fields") as Record<string, unknown[]>;
	const retainedExtraValue = Reflect.get(retainedExtraFields.value[0] as object, "value");
	assert.equal(retainedExtraValue, "retained");
	observations.set(
		"rollback-retains-new-type-content",
		{
			...checkpoint(rollbackProvider, reopenedOld, rollbackMessages, [], 1, 0),
			losingAuthorBefore,
			losingAuthorAfter,
			losingAuthorSchema: losingSchemaBefore,
			losingAuthorSchemaAfter: losingSchemaAfter,
			losingAuthorPending: losingStateBefore.pending,
			pendingAfterCompetingEdit: losingStateAfter.pending,
			retainedExtra: {
				type: widened.Extra.identifier,
				value: retainedExtraValue,
				content: retainedExtra,
				detached,
			},
			pendingBeforeCompetingEdit: losingStateBefore.pending,
		},
	);

	{
		const { provider, left, right } = initialized();
		const oldLog = events(right);
		left.dispose();
		const view = provider.trees[0].viewWith(applicationSchema(true).config);
		view.upgradeSchema();
		const messages = drain(provider);
		observations.set("old-view-invalidated", {
			...checkpoint(provider, view, messages, oldLog),
			compatibility: json(right.compatibility),
		});
		right.dispose();
		const reopened = provider.trees[1].viewWith(applicationSchema(true).config);
		observations.set("new-view-reopens", {
			...checkpoint(provider, reopened, messages, events(reopened), 1, 0),
			reopenedPeer: {
				tree: provider.trees[1].id,
				schema: schemaId(provider.trees[1]),
				root: rootSnapshot(provider.trees[1]),
				compatibility: json(reopened.compatibility),
			},
		});
	}
	{
		const { provider, left } = initialized();
		left.dispose();
		const view = provider.trees[0].viewWith(applicationSchema(true).config);
		const log = events(view);
		provider.trees[0].containerRuntime.connected = false;
		view.upgradeSchema();
		provider.trees[0].containerRuntime.connected = true;
		const messages = drain(provider);
		observations.set(
			"reconnect-upgrade-unacknowledged",
			checkpoint(provider, view, messages, log),
		);
	}
	{
		const { provider, left } = initialized();
		left.dispose();
		const view = provider.trees[0].viewWith(applicationSchema(true).config);
		const log = events(view);
		view.upgradeSchema();
		const accepted: object[] = [];
		while (provider.peekNextMessage() !== undefined
			&& !hasSchemaChange(provider.peekNextMessage() as object)) {
			const nextMessage = provider.peekNextMessage();
			assert(nextMessage !== undefined);
			const captured = json(nextMessage) as unknown as Record<string, unknown>;
			provider.synchronizeMessages({ count: 1 });
			captured.sequenceNumber = provider.sequenceNumber;
			captured.minimumSequenceNumber ??= provider.minimumSequenceNumber;
			captured.indexInBatch = 0;
			accepted.push(captured);
		}
		provider.trees[0].containerRuntime.pauseInboundProcessing();
		while (schemaId(provider.trees[1]) !== "optional") {
			const nextMessage = provider.peekNextMessage();
			assert(nextMessage !== undefined, "Upgrade was not submitted for acceptance");
			const captured = json(nextMessage) as unknown as Record<string, unknown>;
			provider.synchronizeMessages({ count: 1 });
			captured.sequenceNumber = provider.sequenceNumber;
			captured.minimumSequenceNumber ??= provider.minimumSequenceNumber;
			captured.indexInBatch = 0;
			accepted.push(captured);
		}
		const acceptedMessage = accepted.find(hasSchemaChange);
		assert(acceptedMessage !== undefined, "Accepted upgrade message was not captured");
		const peerSchemaCommits = managerState(provider.trees[1]).trunk
			.filter(({ kinds }) => kinds.includes("schema")).length;
		provider.trees[0].containerRuntime.connected = false;
		provider.trees[0].containerRuntime.connected = true;
		const replayMessages = drain(provider);
		provider.trees[0].containerRuntime.resumeInboundProcessing();
		provider.synchronizeMessages();
		const final = checkpoint(provider, view, [...accepted, ...replayMessages], log);
		const finalPeerSchemaCommits = managerState(provider.trees[1]).trunk
			.filter(({ kinds }) => kinds.includes("schema")).length;
		const replay = {
			submitted: replayMessages.length,
			bytes: replayMessages.map((message) => JSON.stringify(message)),
			originalRevision: Reflect.get(
				Reflect.get(acceptedMessage, "contents") as object,
				"revision",
			),
			replayRevisions: replayMessages.map((message) =>
				Reflect.get(Reflect.get(message, "contents") as object, "revision")),
			peerSchemaCommitDelta: finalPeerSchemaCommits - peerSchemaCommits,
			finalSchema: final.visibleSchema,
			finalPending: final.pendingRevisions.length,
		};
		assert(replay.submitted > 0 && replay.finalPending === 0);
		observations.set(
			"reconnect-upgrade-accepted-before-drop",
			{
				...final,
				acceptedMessage: {
					sequenceNumber: Reflect.get(acceptedMessage, "sequenceNumber"),
					bytes: JSON.stringify(acceptedMessage),
				},
				replay,
			},
		);
	}

	const pendingProvider = new TestTreeProviderLite(2, factory);
	const pendingOld = applicationSchema(false);
	const pendingNext = applicationSchema(true);
	const pendingInitial = pendingProvider.trees[0].viewWith(pendingOld.config);
	pendingInitial.initialize(rootInput(pendingOld));
	drain(pendingProvider);
	pendingInitial.dispose();
	const pendingView = pendingProvider.trees[0].viewWith(pendingNext.config);
	pendingView.upgradeSchema();
	const pendingSummary = await pendingProvider.trees[1].summarize(true);
	const pendingMessage = json(pendingProvider.peekNextMessage()
		?? assert.fail("Pending upgrade did not submit a message"));
	observations.set(
		"summary-before-pending-upgrade",
		checkpoint(pendingProvider, pendingView, [pendingMessage], []),
	);

	{
		const { provider, left } = initialized();
		left.dispose();
		const view = provider.trees[0].viewWith(applicationSchema(true).config);
		const log = events(view);
		view.upgradeSchema();
		const messages = drain(provider);
		const summary = await provider.trees[0].summarize(true);
		tailSummary = summary.summary;
		view.root.title = "tail";
		const tailMessages = drain(provider);
		const compressor = serializeIdCompressor(provider.getCompressor(provider.trees[0]), false);
		const reloadRuntime = new MockFluidDataStoreRuntime({
			idCompressor: deserializeIdCompressor(compressor, createSessionId()),
		});
		const reloadMessages: unknown[] = [];
		const services = MockSharedObjectServices.createFromSummary(summary.summary);
		services.deltaConnection = new MockDeltaConnection(
			(message: unknown) => {
				reloadMessages.push(json(message));
				return 1;
			},
			() => {},
		);
		const loadedTree = await factory.load(
			reloadRuntime,
			"schema-evolution-summary-continuation",
			services,
			factory.attributes,
		);
		const loadedView = loadedTree.viewWith(applicationSchema(true).config);
		const loadedBefore = rootSnapshot(loadedTree as TestTreeProviderLite["trees"][number]);
		const kernel: unknown = Reflect.get(loadedTree, "kernel");
		const process: unknown = Reflect.get(kernel as object, "processMessagesCore");
		assert(typeof process === "function");
		for (const message of tailMessages.filter(dataChange)) {
			const metadata = message as Record<string, unknown>;
			process.call(kernel, {
				envelope: {
					clientId: metadata.clientId,
					clientSequenceNumber: metadata.clientSequenceNumber,
					contents: metadata.contents,
					referenceSequenceNumber: metadata.referenceSequenceNumber,
					sequenceNumber: metadata.sequenceNumber,
					minimumSequenceNumber: metadata.minimumSequenceNumber,
					timestamp: 0,
					type: "op",
				},
				local: false,
				messagesContent: [{
					contents: metadata.contents,
					localOpMetadata: undefined,
					clientSequenceNumber: metadata.clientSequenceNumber,
				}],
			});
		}
		observations.set(
			"summary-upgrade-plus-tail",
			{
				...checkpoint(provider, view, [...messages, ...tailMessages], log),
				continuation: {
					loadedSummary: true,
					summary: summary.summary,
					before: loadedBefore,
					tailBytes: tailMessages.filter(dataChange).map((message) => JSON.stringify(message)),
					replayed: loadedView.root.title === "tail",
					root: rootSnapshot(loadedTree as TestTreeProviderLite["trees"][number]),
					submitted: reloadMessages,
				},
			},
		);
	}
	{
		const { provider, left, right } = initialized();
		const log = events(left);
		const authoringSchema = schemaId(provider.trees[1]);
		right.root.title = "historical";
		const allocationMessage = provider.peekNextMessage()
			?? assert.fail("Historical edit did not submit an ID allocation");
		assert.equal(
			Reflect.get(Reflect.get(allocationMessage, "contents") as object, "type"),
			"idAllocation",
		);
		const capturedAllocation = json(allocationMessage) as unknown as Record<string, unknown>;
		provider.synchronizeMessages({ count: 1 });
		capturedAllocation.sequenceNumber = provider.sequenceNumber;
		capturedAllocation.minimumSequenceNumber ??= provider.minimumSequenceNumber;
		capturedAllocation.indexInBatch = 0;
		provider.trees[0].containerRuntime.pauseInboundProcessing();
		const historicalMessages = [capturedAllocation, ...drain(provider)];
		const historicalMessage = historicalMessages.find(dataChange);
		assert(historicalMessage !== undefined, "Historical data message was not captured");
		left.dispose();
		const view = provider.trees[0].viewWith(applicationSchema(true).config);
		view.upgradeSchema();
		const first = drain(provider);
		const kernel: unknown = Reflect.get(provider.trees[0], "kernel");
		const messageCodec: unknown = Reflect.get(kernel as object, "messageCodec");
		assert(messageCodec !== null && typeof messageCodec === "object"
			&& "decode" in messageCodec && typeof messageCodec.decode === "function");
		const visibleSchema = schemaId(provider.trees[0]);
		assert.equal(visibleSchema, "optional");
		const decoded = messageCodec.decode(
			Reflect.get(historicalMessage, "contents"),
			{ idCompressor: provider.getCompressor(provider.trees[0]) },
		) as { commit?: { change?: { changes?: unknown[] } } };
		const decodedChange = decoded.commit?.change;
		assert(Array.isArray(decodedChange?.changes) && decodedChange.changes.length > 0,
			"Historical data must decode before rebase");
		provider.trees[0].containerRuntime.resumeInboundProcessing();
		provider.synchronizeMessages();
		const visibleSchemaAfterSynchronization = schemaId(provider.trees[0]);
		const messages = [...historicalMessages, ...first];
		observations.set(
			"historical-peer-schema-context",
			{
				...checkpoint(provider, view, messages, log),
				historicalDecode: {
					operation: "decode",
					bytes: JSON.stringify(Reflect.get(historicalMessage, "contents")),
					decoded: losslessJson(decodedChange),
					envelope: losslessJson(decoded),
					authoringSchema,
					visibleSchema,
					visibleSchemaAfterSynchronization,
					decodedBeforeInboundResume: true,
					context: {
						authoringSchema,
						visibleSchema,
						inboundProcessing: "paused",
					},
				},
			},
		);
	}

	return {
		observations,
		rollbackReplay: {
			scenario: "rollback-retains-new-type-content",
			detachedId: {
				revision: rollbackProvider.getCompressor(
					rollbackProvider.trees[1],
				).decompress(-2 as SessionSpaceCompressedId),
				localId: 0,
			},
		},
		rollback: {
			...observations.get("rollback-retains-new-type-content"),
			messages: rollbackMessages,
			compatibility: rollbackCompatibility,
			detached,
		},
		pendingSummary: {
			message: pendingMessage,
			summary: pendingSummary.summary,
			visibleCompatibility: json(pendingView.compatibility),
		},
		tailSummary,
	};
}

async function captureAlgebra(
	oldSchema: TreeStoredSchema,
	newSchema: TreeStoredSchema,
	secondSchema: TreeStoredSchema,
) {
	const options: CodecWriteOptions = {
		jsonValidator: FormatValidatorBasic,
		minVersionForCollab: FluidClientVersion.v2_117,
	};
	const revisionCodec = new RevisionTagCodec(testIdCompressor);
	const fieldBatchCodec = fieldBatchCodecBuilder.build(options);
	assert.equal(fieldBatchCodec.writeVersion, FieldBatchFormatVersion.v2);
	const family = new SharedTreeChangeFamily(
		revisionCodec,
		fieldBatchCodec,
		options,
		TreeCompressionStrategy.Compressed,
		testIdCompressor,
	);
	const schemaRevision = testIdCompressor.generateCompressedId();
	const dataRevision = testIdCompressor.generateCompressedId();
	const secondDataRevision = testIdCompressor.generateCompressedId();
	const secondSchemaRevision = testIdCompressor.generateCompressedId();
	const inverseRevision = testIdCompressor.generateCompressedId();
	const schemaChange = {
		changes: [{
			type: "schema" as const,
			innerChange: { schema: { old: oldSchema, new: newSchema }, isInverse: false },
		}],
	};
	const secondSchemaChange = {
		changes: [{
			type: "schema" as const,
			innerChange: {
				schema: { old: newSchema, new: secondSchema },
				isInverse: false,
			},
		}],
	};
	const dataProvider = new TestTreeProviderLite(1, configuredSharedTreeInternal({
		minVersionForCollab: FluidClientVersion.v2_117,
	}).getFactory());
	const dataBundle = applicationSchema(false);
	const dataView = dataProvider.trees[0].viewWith(dataBundle.config);
	dataView.initialize(rootInput(dataBundle));
	drain(dataProvider);
	dataView.root.title = "algebra";
	type FamilyChange = Parameters<typeof family.compose>[0][number]["change"];
	const dataManager = Reflect.get(dataProvider.trees[0].kernel, "editManager") as {
		getLocalCommits(branch: string): readonly {
			change: FamilyChange;
		}[];
	};
	const dataChange = dataManager.getLocalCommits("main").at(-1)?.change
		?? assert.fail("Missing authored data operand");
	assert(dataChange.changes.some(({ type }) => type === "data"));
	const metadata = revisionMetadataSourceFromInfo([]);
	const conflict = family.rebase(
		tagChange(schemaChange, schemaRevision),
		tagChange(dataChange, dataRevision),
		metadata,
	);
	assert.deepEqual(conflict, { changes: [] });
	const opposite = family.rebase(
		tagChange(dataChange, dataRevision),
		tagChange(schemaChange, schemaRevision),
		metadata,
	);
	const schemaConflict = family.rebase(
		tagChange(schemaChange, schemaRevision),
		tagChange(schemaChange, dataRevision),
		metadata,
	);
	const emptyOver = family.rebase(
		tagChange(schemaChange, schemaRevision),
		tagChange(SharedTreeChangeFamily.emptyChange, dataRevision),
		metadata,
	);
	const composed = family.compose([
		tagChange(dataChange, dataRevision),
		tagChange(schemaChange, schemaRevision),
		tagChange(dataChange, secondDataRevision),
		tagChange(secondSchemaChange, secondSchemaRevision),
	]);
	const inverted = family.invert(tagChange(composed, secondSchemaRevision), true, inverseRevision);
	const schemaCodec = makeSchemaChangeCodec(options);
	let inverseEncodingError = "";
	try {
		schemaCodec.encode(inverted.changes.find((change) => change.type === "schema")?.innerChange
			?? assert.fail("Missing inverse schema change"));
	} catch (error) {
		inverseEncodingError = String(error);
	}
	assert(inverseEncodingError.length > 0);
	return {
		input: {
			revisions: {
				schema: Number(schemaRevision),
				data: Number(dataRevision),
				secondData: Number(secondDataRevision),
				secondSchema: Number(secondSchemaRevision),
				inverse: Number(inverseRevision),
			},
			operands: {
				schemaChange: losslessJson(schemaChange),
				dataChange: losslessJson(dataChange),
				secondSchemaChange: losslessJson(secondSchemaChange),
				emptyChange: losslessJson(SharedTreeChangeFamily.emptyChange),
			},
			transitions: [
				{
					revision: Number(schemaRevision),
					before: "v1",
					after: "optional",
					change: losslessJson(schemaChange),
				},
				{
					revision: Number(secondSchemaRevision),
					before: "optional",
					after: "object-union",
					change: losslessJson(secondSchemaChange),
				},
			],
			scenarios: [
				{ id: "schema-over-data" },
				{ id: "data-over-schema" },
				{ id: "schema-over-schema" },
				{ id: "empty-operand" },
				{ id: "data-schema-data-schema-compose" },
				{ id: "inverse-schema-encoding-refusal" },
			],
		},
		observations: [
			{ id: "schema-over-data", change: losslessJson(conflict) },
			{ id: "data-over-schema", change: losslessJson(opposite) },
			{ id: "schema-over-schema", change: losslessJson(schemaConflict) },
			{ id: "empty-operand", change: losslessJson(emptyOver) },
			{
				id: "data-schema-data-schema-compose",
				kinds: composed.changes.map((change) => change.type),
				change: losslessJson(composed),
				revisions: [
					Number(dataRevision),
					Number(schemaRevision),
					Number(secondDataRevision),
					Number(secondSchemaRevision),
				],
			},
			{
				id: "inverse-schema-encoding-refusal",
				error: inverseEncodingError,
				change: losslessJson(inverted),
				revision: Number(inverseRevision),
			},
		],
		raw: {
			composed: losslessJson(composed),
			inverted: losslessJson(inverted),
			conflicts: [
				losslessJson(conflict),
				losslessJson(opposite),
				losslessJson(schemaConflict),
			],
			revisionResults: {
				composed: Number(secondSchemaRevision),
				inverted: Number(inverseRevision),
			},
		},
	};
}

function envelope(id: string, domain: string, input: object, observations: object[], raw: object) {
	return {
		formatVersion,
		reference: { package: packageName, version: packageVersion, commit: expectedCommit },
		id,
		domain,
		input,
		expected: { observations },
		raw,
	};
}

describe("Watershed schema evolution oracle", () => {
	it("captures the pinned schema evolution contract", async () => {
		const output = process.env.WATERSHED_ORACLE_OUTPUT;
		assert(output !== undefined && isAbsolute(output), "An absolute output directory is required");
		assert.equal(process.env.WATERSHED_ORACLE_COMMIT, expectedCommit);

		const compatibility = await compatibilityCases();
		const upgrade = await captureUpgrade();
		const oldSchema = toUpgradeSchema(compatibility.profiles.v1.config.schema);
		const newSchema = toUpgradeSchema(compatibility.profiles.optional.config.schema);
		const secondSchema = toUpgradeSchema(compatibility.profiles["object-union"].config.schema);
		const algebra = await captureAlgebra(oldSchema, newSchema, secondSchema);
		const historyRuntime = await captureHistoryRuntime(compatibility.profiles);
		const historyPlans = {
			"upgrade-then-edit-causal": [{ op: "upgrade", schema: "optional" }, { op: "set", path: ["score"], value: 7 }, { op: "sequence", count: "all" }],
			"edit-then-upgrade-causal": [{ op: "set", path: ["title"], value: "edited" }, { op: "sequence", count: "all" }, { op: "upgrade", schema: "optional" }],
			"schema-data-schema-first": [{ op: "upgrade", tree: 0, schema: "optional" }, { op: "set", tree: 1, path: ["title"], value: "data" }, { op: "sequence", order: "schema-first" }],
			"schema-data-data-first": [{ op: "set", tree: 1, path: ["title"], value: "data" }, { op: "upgrade", tree: 0, schema: "optional" }, { op: "sequence", order: "data-first" }],
			"schema-schema-left-first": [{ op: "upgrade", tree: 0, schema: "optional" }, { op: "upgrade", tree: 1, schema: "object-union" }, { op: "sequence", order: "left-first" }],
			"schema-schema-right-first": [{ op: "upgrade", tree: 1, schema: "object-union" }, { op: "upgrade", tree: 0, schema: "optional" }, { op: "sequence", order: "right-first" }],
			"same-upgrade-concurrent": [{ op: "upgrade", tree: 0, schema: "optional" }, { op: "upgrade", tree: 1, schema: "optional" }],
			"pending-upgrade-dependent-data-loses": [{ op: "set", tree: 1, path: ["title"], value: "wins" }, { op: "upgrade", tree: 0, schema: "optional" }, { op: "set", tree: 0, path: ["score"], value: 7 }],
			"pending-data-remote-upgrade": [{ op: "disconnect", tree: 0 }, { op: "set", tree: 0, path: ["title"], value: "pending" }, { op: "upgrade", tree: 1, schema: "optional" }, { op: "reconnect", tree: 0 }],
			"ack-common-prefix-keeps-upgrade": [{ op: "upgrade", tree: 0, schema: "optional" }, { op: "set", tree: 0, path: ["score"], value: 7 }, { op: "sequence-through", change: "schema" }],
			"empty-conflict-acknowledged": [{ op: "upgrade", tree: 0, schema: "optional" }, { op: "set", tree: 1, path: ["title"], value: "conflict" }, { op: "sequence", count: "all" }],
			"rollback-retains-new-type-content": [{ op: "upgrade", tree: 1, schema: "new-node" }, { op: "set", tree: 1, path: ["extra", "value"], value: "retained", identity: { revision: -2, localId: 0 } }, { op: "set", tree: 0, path: ["title"], value: "wins", identity: { revision: -2, localId: 0 }, detachedLocalId: 1 }, { op: "sequence", order: "tree-0-first" }],
			"old-view-invalidated": [{ op: "upgrade", tree: 0, schema: "optional" }, { op: "observe-view", tree: 1, schema: "v1" }],
			"new-view-reopens": [{ op: "upgrade", tree: 0, schema: "optional" }, { op: "sequence", count: "all" }, { op: "dispose-view", tree: 1 }, { op: "open-view", tree: 1, schema: "optional" }],
			"reconnect-upgrade-unacknowledged": [{ op: "disconnect", tree: 0 }, { op: "upgrade", tree: 0, schema: "optional" }, { op: "reconnect", tree: 0 }, { op: "sequence", count: "all" }],
			"reconnect-upgrade-accepted-before-drop": [{ op: "pause-inbound", tree: 0 }, { op: "upgrade", tree: 0, schema: "optional" }, { op: "sequence-through", change: "schema" }, { op: "disconnect", tree: 0 }, { op: "reconnect", tree: 0 }, { op: "resume-inbound", tree: 0 }],
			"summary-before-pending-upgrade": [{ op: "upgrade", tree: 0, schema: "optional" }, { op: "summarize", tree: 1 }],
			"summary-upgrade-plus-tail": [{ op: "upgrade", tree: 0, schema: "optional" }, { op: "sequence", count: "all" }, { op: "summarize", tree: 0 }, { op: "set", tree: 0, path: ["title"], value: "tail" }, { op: "load-summary" }, { op: "replay-tail" }],
			"historical-peer-schema-context": [{ op: "set", tree: 1, path: ["title"], value: "historical", schema: "v1" }, { op: "sequence-through", change: "id-allocation" }, { op: "pause-inbound", tree: 0 }, { op: "upgrade", tree: 0, schema: "optional" }, { op: "decode", schema: "v1" }, { op: "resume-inbound", tree: 0 }],
		} as const;
		const historyScenarios = historyScenarioIds.map((id) => {
			const observation = historyRuntime.observations.get(id)
				?? assert.fail(`Missing history capture: ${id}`);
			return {
			id,
			sessions: observation.identities,
			actions: historyPlans[id],
				sequencePoints: observation.sequencePoints,
			};
		});
		const historyObservations = historyScenarioIds.map((id) => {
			const observation = historyRuntime.observations.get(id)
				?? assert.fail(`Missing history capture: ${id}`);
			const { messages: _, sequencePoints: __, ...expected } = observation;
			return { id, ...expected };
		});
		const rawSchemaMessages = upgrade.submitted.filter((message) =>
			JSON.stringify(message).includes("\"schema\""));
		assert(rawSchemaMessages.length > 0);

		const cases = [
			envelope(
				"schema-evolution-compatibility",
				"schema",
				{
					schemas: compatibility.compatibilityCatalog,
					scenarios: compatibility.scenarios,
					refusals: compatibility.refusals,
					rawProbes: compatibility.rawProbes,
				},
				compatibility.observations,
				{
					schemas: compatibility.compatibilityCatalog,
					schemaMessages: rawSchemaMessages,
					schemaMessageBytes: rawSchemaMessages.map((message) => JSON.stringify(message)),
					initializationMessages: upgrade.initializationMessages,
					refusalAttempts: compatibility.refusalAttempts,
					rawProbeResults: compatibility.rawProbeResults,
				},
			),
			envelope(
				"schema-evolution-algebra",
				"tree",
				{
					schemas: compatibility.catalog,
					...algebra.input,
				},
				algebra.observations,
				{
					...algebra.raw,
					schemaMessages: rawSchemaMessages,
					schemaMessageBytes: rawSchemaMessages.map((message) => JSON.stringify(message)),
				},
			),
			envelope(
				"schema-evolution-history",
				"history",
				{
					schemas: [
						...compatibility.catalog,
						{
							id: "new-node",
							raw: JSON.stringify(persisted(newNodeSchema().config.schema)),
						},
					],
					scenarios: historyScenarios,
					initialRoot: {
						kind: "object",
						type: "org.watershed.shared-tree.m4.Root",
						fields: [
							["title", { kind: "string", value: "base" }],
							["point", {
								kind: "object",
								type: "org.watershed.shared-tree.m4.Point",
								fields: [
									["x", { kind: "number", value: 1 }],
									["y", { kind: "number", value: 2 }],
								],
							}],
							["items", {
								kind: "object",
								type: "org.watershed.shared-tree.m4.Items",
								fields: [["label", { kind: "string", value: "value" }]],
							}],
						],
					},
					initializationHistory: {
						schema: "EmptySchema",
						messages: upgrade.initializationMessages,
					},
					rollbackReplay: historyRuntime.rollbackReplay,
				},
				historyObservations,
				{
					schemaMessages: rawSchemaMessages,
					schemaMessageBytes: rawSchemaMessages.map((message) => JSON.stringify(message)),
					upgradeMessages: upgrade.submitted,
					rollback: historyRuntime.rollback,
					scenarios: Object.fromEntries(historyRuntime.observations),
					pendingSummary: historyRuntime.pendingSummary,
					tailSummary: historyRuntime.tailSummary,
				},
			),
			envelope(
				"schema-evolution-codecs",
				"codec",
				{
					schemas: compatibility.catalog,
					scenarios: [
						{ id: "schema-only-commit", authoringSchema: "v1" },
						{ id: "empty-outer-commit", authoringSchema: "optional" },
						{ id: "historical-schema-decode", authoringSchema: "v1", visibleSchema: "optional" },
						{ id: "pending-upgrade-summary", authoringSchema: "optional" },
					],
				},
				[
					{ id: "old-schema-bytes", bytes: compatibility.catalog[0].raw },
					{ id: "new-schema-bytes", bytes: compatibility.catalog[1].raw },
					{ id: "schema-only-commit", messages: rawSchemaMessages.length },
					{ id: "empty-outer-commit", change: { changes: [] } },
					{
						id: "historical-schema-decode",
						operations: [historyRuntime.observations.get(
							"historical-peer-schema-context",
						)?.historicalDecode],
					},
					{ id: "pending-upgrade-summary", capturedSequencedSchema: "v1" },
				],
				{
					schemaMessages: rawSchemaMessages,
					schemaMessageBytes: rawSchemaMessages.map((message) => JSON.stringify(message)),
					allMessages: upgrade.submitted,
					summary: historyRuntime.pendingSummary.summary,
					inverseEncodingError: algebra.observations.at(-1),
					historical: historyRuntime.observations.get("historical-peer-schema-context")
						?.historicalDecode,
				},
			),
		];

		mkdirSync(output, { recursive: true });
		writeFileSync(
			join(output, "schema-evolution-cases.json"),
			`${JSON.stringify(cases, undefined, 2)}\n`,
			"utf8",
		);
	});
});
