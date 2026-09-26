/*!
 * Copyright (c) Microsoft Corporation and contributors. All rights reserved.
 * Licensed under the MIT License.
 */

import { strict as assert } from "node:assert";
import { mkdirSync, writeFileSync } from "node:fs";
import { isAbsolute, join } from "node:path";

import { FluidClientVersion, type CodecWriteOptions } from "../codec/index.js";
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
import { makeModularChangeset } from "../feature-libraries/modular-schema/modularChangeUtils.js";
import { SharedTreeChangeFamily } from "../shared-tree/sharedTreeChangeFamily.js";
import {
	checkSchemaCompatibility,
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

function rootInput(bundle: SchemaBundle) {
	return new bundle.Root({
		title: "base",
		point: new bundle.Point({ x: 1, y: 2 }),
		items: new bundle.Items([["label", "value"]]),
	});
}

function compatibilityCases() {
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
	const oldStored = toUpgradeSchema(profiles.v1.config.schema);
	const catalog = Object.entries(profiles).map(([id, bundle]) => ({
		id,
		raw: JSON.stringify(persisted(bundle.config.schema)),
	}));
	const scenarios = Object.entries(profiles).map(([id, bundle]) => ({
		id,
		stored: "v1",
		requested: id,
		operation: "compatibility",
	}));
	const observations = Object.entries(profiles).map(([id, bundle]) => ({
		id,
		...json(checkSchemaCompatibility(bundle.config, oldStored)),
		profileRestriction: ["narrow", "new-required"].includes(id) ? "refused" : undefined,
	}));
	const refusalProfiles = {
		narrow: profiles.narrow.config,
		"new-required": profiles["new-required"].config,
		"optional-to-required": optionalToRequiredSchema().config,
		"node-kind-replacement": nodeKindReplacementSchema().config,
		sequence: sequenceSchema(),
		handle: handleSchema(),
	};
	const refusals = Object.entries(refusalProfiles).map(([id]) => ({
		id,
		stored: "v1",
		requested: id,
		operation: "prepare-upgrade",
	}));
	const refusalObservations = Object.entries(refusalProfiles).map(([id, config]) => {
		const status = json(checkSchemaCompatibility(config, oldStored));
		return {
			id,
			status,
			classification: ["node-kind-replacement", "sequence", "handle"].includes(id)
				? "profile-restriction"
				: "upstream-refusal",
		};
	});
	return { catalog, scenarios, observations, refusals, refusalObservations, profiles };
}

function drain(provider: TestTreeProviderLite): object[] {
	const messages: object[] = [];
	let message = provider.peekNextMessage();
	while (message !== undefined) {
		messages.push(json(message));
		provider.synchronizeMessages({ count: 1 });
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

async function captureHistoryRuntime() {
	const factory = configuredSharedTreeInternal({
		minVersionForCollab: FluidClientVersion.v2_117,
	}).getFactory();
	const profiles = compatibilityCases().profiles;

	function schemaId(tree: TestTreeProviderLite["trees"][number]): string {
		for (const [id, bundle] of Object.entries(profiles)) {
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
	) {
		const local = managerState(provider.trees[0]);
		const sequenced = managerState(provider.trees[1]);
		const message = messages.at(-1) as {
			referenceSequenceNumber?: number;
			minimumSequenceNumber?: number;
		} | undefined;
		return {
			visibleSchema: schemaId(provider.trees[0]),
			sequencedSchema: schemaId(provider.trees[1]),
			visibleRoot: json(provider.trees[0].contentSnapshot()),
			pendingRevisions: local.pending,
			outerChanges: [...local.pending, ...local.trunk],
			trunkRevisions: sequenced.trunk,
			peerRevisions: local.trunk,
			detachedIdentities: json(provider.trees[0].kernel.checkout.getRemovedRoots()),
			compatibility: json(view.compatibility),
			events,
			sequencePoints: [{
				referenceSequenceNumber: message?.referenceSequenceNumber ?? provider.sequenceNumber,
				minimumSequenceNumber: message?.minimumSequenceNumber ?? provider.minimumSequenceNumber,
				indexInBatch: 0,
			}],
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

	const observations = new Map<string, ReturnType<typeof checkpoint>>();
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
		const first = provider.peekNextMessage();
		assert(first !== undefined);
		const message = json(first);
		provider.synchronizeMessages({ count: 1 });
		observations.set(
			"ack-common-prefix-keeps-upgrade",
			checkpoint(provider, view, [message], log),
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
	const rollbackMessages = drain(rollbackProvider);
	const rollbackCompatibility = json(widenedRight.compatibility);
	widenedRight.dispose();
	const reopenedOld = rollbackProvider.trees[1].viewWith(rollbackOld.config);
	const detached = json(rollbackProvider.trees[1].kernel.checkout.getRemovedRoots());
	assert.equal(reopenedOld.root.title, "wins");
	assert(detached.length > 0, "Rollback must retain detached repair content");
	observations.set(
		"rollback-retains-new-type-content",
		checkpoint(rollbackProvider, reopenedOld, rollbackMessages, []),
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
		observations.set("new-view-reopens", checkpoint(provider, view, messages, events(view)));
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
		provider.trees[0].containerRuntime.connected = false;
		const messages = drain(provider);
		provider.trees[0].containerRuntime.connected = true;
		provider.synchronizeMessages();
		observations.set(
			"reconnect-upgrade-accepted-before-drop",
			checkpoint(provider, view, messages, log),
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
		observations.set(
			"summary-upgrade-plus-tail",
			checkpoint(provider, view, messages, log),
		);
	}
	{
		const { provider, left, right } = initialized();
		const log = events(left);
		provider.trees[1].containerRuntime.connected = false;
		right.root.title = "historical";
		left.dispose();
		const view = provider.trees[0].viewWith(applicationSchema(true).config);
		view.upgradeSchema();
		const first = drain(provider);
		provider.trees[1].containerRuntime.connected = true;
		const messages = [...first, ...drain(provider)];
		observations.set(
			"historical-peer-schema-context",
			checkpoint(provider, view, messages, log),
		);
	}

	return {
		observations,
		rollback: {
			messages: rollbackMessages,
			root: { title: reopenedOld.root.title },
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

function captureAlgebra(oldSchema: TreeStoredSchema, newSchema: TreeStoredSchema) {
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
	const schemaChange = {
		changes: [{
			type: "schema" as const,
			innerChange: { schema: { old: oldSchema, new: newSchema }, isInverse: false },
		}],
	};
	const dataChange = {
		changes: [{ type: "data" as const, innerChange: makeModularChangeset() }],
	};
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
		tagChange(dataChange, dataRevision),
		tagChange(schemaChange, schemaRevision),
	]);
	const inverted = family.invert(tagChange(composed, schemaRevision), true, dataRevision);
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
			revisions: { schema: Number(schemaRevision), data: Number(dataRevision) },
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
			{ id: "schema-over-data", change: json(conflict) },
			{ id: "data-over-schema", change: json(opposite) },
			{ id: "schema-over-schema", change: json(schemaConflict) },
			{ id: "empty-operand", change: json(emptyOver) },
			{ id: "data-schema-data-schema-compose", kinds: composed.changes.map((change) => change.type) },
			{ id: "inverse-schema-encoding-refusal", error: inverseEncodingError },
		],
		raw: {
			composed: json(composed),
			inverted: json(inverted),
			conflicts: [json(conflict), json(opposite), json(schemaConflict)],
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

		const compatibility = compatibilityCases();
		const upgrade = await captureUpgrade();
		const oldSchema = toUpgradeSchema(compatibility.profiles.v1.config.schema);
		const newSchema = toUpgradeSchema(compatibility.profiles.optional.config.schema);
		const algebra = captureAlgebra(oldSchema, newSchema);
		const historyRuntime = await captureHistoryRuntime();
		const historyPlans = {
			"upgrade-then-edit-causal": ["upgrade:optional", "edit:score=1", "sequence:all"],
			"edit-then-upgrade-causal": ["edit:title=edited", "sequence:edit", "upgrade:optional"],
			"schema-data-schema-first": ["concurrent:upgrade:optional", "concurrent:edit:title=data", "sequence:schema-first"],
			"schema-data-data-first": ["concurrent:edit:title=data", "concurrent:upgrade:optional", "sequence:data-first"],
			"schema-schema-left-first": ["concurrent:upgrade:optional", "concurrent:upgrade:object-union", "sequence:left-first"],
			"schema-schema-right-first": ["concurrent:upgrade:optional", "concurrent:upgrade:object-union", "sequence:right-first"],
			"same-upgrade-concurrent": ["concurrent:upgrade:optional", "concurrent:upgrade:optional"],
			"pending-upgrade-dependent-data-loses": ["upgrade:optional", "edit:score=1", "sequence:competing-data-first"],
			"pending-data-remote-upgrade": ["edit:title=pending", "remote:upgrade:optional"],
			"ack-common-prefix-keeps-upgrade": ["upgrade:optional", "edit:score=1", "ack:upgrade"],
			"empty-conflict-acknowledged": ["concurrent:upgrade:optional", "concurrent:edit:title=data", "ack:empty"],
			"rollback-retains-new-type-content": ["upgrade:new-node", "edit:new-node", "sequence:competing-data-first"],
			"old-view-invalidated": ["upgrade:optional", "open:v1"],
			"new-view-reopens": ["upgrade:optional", "open:optional"],
			"reconnect-upgrade-unacknowledged": ["upgrade:optional", "disconnect", "reconnect", "resubmit"],
			"reconnect-upgrade-accepted-before-drop": ["upgrade:optional", "server-accept", "disconnect-before-ack", "reconnect"],
			"summary-before-pending-upgrade": ["upgrade:optional", "summarize-before-ack"],
			"summary-upgrade-plus-tail": ["upgrade:optional", "sequence:upgrade", "summarize", "edit:title=tail"],
			"historical-peer-schema-context": ["upgrade:optional", "decode-peer-data:v1", "rebase"],
		} as const;
		const historyScenarios = historyScenarioIds.map((id) => {
			const observation = historyRuntime.observations.get(id)
				?? assert.fail(`Missing history capture: ${id}`);
			return {
			id,
			sessions: ["test-client-0", "test-client-1"],
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
					schemas: compatibility.catalog,
					scenarios: compatibility.scenarios,
					refusals: compatibility.refusals,
				},
				[
					...compatibility.observations,
					...compatibility.refusalObservations,
					{
						id: "explicit-optional-upgrade",
						opened: upgrade.opened,
						before: upgrade.before,
						after: upgrade.after,
						submittedSchemaMessages: rawSchemaMessages.length,
					},
					{ id: "equivalent-upgrade-no-op", submittedSchemaMessages: 0 },
				],
				{
					schemas: compatibility.catalog,
					schemaMessages: rawSchemaMessages,
					initializationMessages: upgrade.initializationMessages,
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
				{ ...algebra.raw, schemaMessages: rawSchemaMessages },
			),
			envelope(
				"schema-evolution-history",
				"history",
				{
					schemas: compatibility.catalog,
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
				},
				historyObservations,
				{
					schemaMessages: rawSchemaMessages,
					upgradeMessages: upgrade.submitted,
					rollback: {
						activeSchema: "v1",
						retainedContentSchema: "new-node",
						attached: historyRuntime.rollback.root,
						detached: historyRuntime.rollback.detached,
						pendingChanges: [{ changes: [] }],
					},
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
					{ id: "historical-schema-decode", needsAuthoringSchema: true },
					{ id: "pending-upgrade-summary", capturedSequencedSchema: "v1" },
				],
				{
					schemaMessages: rawSchemaMessages,
					allMessages: upgrade.submitted,
					summary: historyRuntime.pendingSummary.summary,
					inverseEncodingError: algebra.observations.at(-1),
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
