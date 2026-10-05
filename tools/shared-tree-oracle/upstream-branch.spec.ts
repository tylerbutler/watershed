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
	type IdCreationRange,
	type SerializedIdCompressorWithNoSession,
} from "@fluidframework/id-compressor/internal";
import {
	MockDeltaConnection,
	MockFluidDataStoreRuntime,
	MockSharedObjectServices,
} from "@fluidframework/test-runtime-utils/internal";

import { asAlpha } from "../api.js";
import { FluidClientVersion } from "../codec/index.js";
import {
	CommitKind,
	CommitOutcome,
	RevertibleStatus,
	type ChangeMetadata,
	type RevertibleAlpha,
} from "../core/index.js";
import {
	SchemaFactory,
	TreeViewConfiguration,
	type TreeBranchCommitMetadata,
	type TreeViewAlpha,
} from "../simple-tree/index.js";
import { Tree } from "../shared-tree/index.js";
import type { TreeCheckout } from "../shared-tree/treeCheckout.js";
import { configuredSharedTreeInternal } from "../treeFactory.js";
import { MockContainerRuntimeWithOpBunching } from "./mocksForOpBunching.js";
import { TestTreeProviderLite } from "./utils.js";

const formatVersion = 1;
const reference = {
	package: "@fluidframework/tree",
	version: "3.1.0",
	commit: "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960",
};

const sf = new SchemaFactory("org.watershed.shared-tree.branch");
class Point extends sf.object("Point", {
	id: sf.identifier,
	label: sf.string,
}) {}
class Items extends sf.array("Items", [sf.string, Point]) {}
class Root extends sf.object("Root", {
	title: sf.string,
	count: sf.number,
	featured: Point,
	left: Items,
	right: Items,
}) {}

type BranchView = TreeViewAlpha<typeof Root>;
type TreeInstance = TestTreeProviderLite["trees"][number];

function treeFactory() {
	return configuredSharedTreeInternal({
		minVersionForCollab: FluidClientVersion.v2_117,
	}).getFactory();
}

function initialRoot() {
	return new Root({
		title: "base",
		count: 0,
		featured: new Point({ label: "featured" }),
		left: new Items([new Point({ label: "left" })]),
		right: new Items([]),
	});
}

function copy<T>(value: T): T {
	return JSON.parse(JSON.stringify(value));
}

function errorOf(action: () => void): string {
	try {
		action();
		return "";
	} catch (error) {
		return String(error);
	}
}

function enumName(values: object, value: number): string {
	const name = Reflect.get(values, value);
	assert.equal(typeof name, "string");
	return name;
}

function visible(root: Root) {
	const value = (item: string | Point): unknown =>
		item instanceof Point ? { id: item.id, label: item.label } : item;
	return {
		title: root.title,
		count: root.count,
		featured: value(root.featured),
		left: [...root.left].map(value),
		right: [...root.right].map(value),
	};
}

function history(view: BranchView) {
	const revisions: string[] = [];
	let commit: TreeBranchCommitMetadata | undefined = view.branchHistory.getHead();
	while (commit !== undefined) {
		revisions.push(commit.revision);
		commit = commit.getParent();
	}
	return revisions.reverse();
}

function fork(view: BranchView): BranchView {
	return view.fork() as BranchView;
}

function checkoutOf(view: object): TreeCheckout {
	const checkout = Reflect.get(view, "checkout");
	assert(checkout !== undefined);
	return checkout as TreeCheckout;
}

function caseFile(id: string, input: object, observations: object[], raw: object) {
	assert(observations.length > 0);
	return {
		formatVersion,
		reference,
		id,
		domain: "branch",
		input,
		expected: { observations },
		raw,
	};
}

function createViews(count = 2) {
	const provider = new TestTreeProviderLite(count, treeFactory());
	const main = asAlpha(provider.trees[0].viewWith(
		new TreeViewConfiguration({ schema: Root, enableSchemaValidation: true }),
	));
	main.initialize(initialRoot());
	provider.synchronizeMessages();
	const peers = [];
	for (let index = 1; index < count; index++) {
		peers.push(asAlpha(provider.trees[index].viewWith(
			new TreeViewConfiguration({ schema: Root, enableSchemaValidation: true }),
		)));
	}
	return { provider, main, peers };
}

function interceptProcessed(provider: TestTreeProviderLite, client = 0): unknown[] {
	const processed: unknown[] = [];
	const runtime = provider.trees[client].containerRuntime;
	assert(runtime instanceof MockContainerRuntimeWithOpBunching);
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

function messagesIn(value: unknown): Record<string, unknown>[] {
	const messages: Record<string, unknown>[] = [];
	function visit(item: unknown) {
		if (Array.isArray(item)) {
			for (const child of item) visit(child);
		} else if (item !== null && typeof item === "object") {
			const object = item as Record<string, unknown>;
			if ("originatorId" in object && "changeset" in object) messages.push(copy(object));
			for (const child of Object.values(object)) visit(child);
		}
	}
	visit(value);
	return messages;
}

function allocationRangesIn(value: unknown): IdCreationRange[] {
	const ranges = new Map<string, IdCreationRange>();
	function visit(item: unknown) {
		if (Array.isArray(item)) {
			for (const child of item) visit(child);
		} else if (item !== null && typeof item === "object") {
			const object = item as Record<string, unknown>;
			const contents = object.contents as Record<string, unknown> | undefined;
			if (contents?.type === "idAllocation" && typeof contents.contents === "object") {
				const range = copy(contents.contents as IdCreationRange);
				ranges.set(JSON.stringify(range), range);
			}
			for (const child of Object.values(object)) visit(child);
		}
	}
	visit(value);
	return [...ranges.values()];
}

function watch(view: BranchView, acquire = false) {
	const events: object[] = [];
	const settled: object[] = [];
	const handles: RevertibleAlpha[] = [];
	const off = view.events.on("changed", (metadata: ChangeMetadata, getRevertible) => {
		const index = events.length;
		const change = metadata.isLocal ? copy(metadata.getChange()) : null;
		events.push({
			index,
			kind: enumName(CommitKind, metadata.kind),
			local: metadata.isLocal,
			factory: getRevertible !== undefined,
			change,
		});
		if (metadata.isLocal) {
			metadata.events.on("settled", (outcome) => {
				settled.push({ index, outcome: enumName(CommitOutcome, outcome) });
			});
		}
		if (acquire && getRevertible !== undefined) handles.push(getRevertible());
	});
	return { events, settled, handles, off };
}

async function captureIsolation() {
	const { provider, main } = createViews();
	const processed = interceptProcessed(provider);
	const start = processed.length;
	const parent = fork(main);
	const nested = fork(parent);
	const baseIdentity = main.root.featured.id;
	parent.root.title = "parent";
	nested.root.count = 7;
	const beforeMerge = {
		main: visible(main.root),
		parent: visible(parent.root),
		nested: visible(nested.root),
		identities: {
			main: main.root.featured.id,
			parent: parent.root.featured.id,
			nested: nested.root.featured.id,
		},
		treeMessages: messagesIn(processed.slice(start)),
	};
	assert.equal(beforeMerge.main.title, "base");
	assert.equal(beforeMerge.parent.title, "parent");
	assert.equal(beforeMerge.nested.count, 7);
	assert.deepEqual(Object.values(beforeMerge.identities), [baseIdentity, baseIdentity, baseIdentity]);
	assert.equal(beforeMerge.treeMessages.length, 0);

	const detachedBranch = fork(main);
	const detachedNode = detachedBranch.root.left[0];
	assert(detachedNode instanceof Point);
	detachedBranch.root.left.removeAt(0);
	const detachedEditError = errorOf(() => {
		detachedNode.label = "detached-branch";
	});
	const detachedIsolation = {
		detached: { id: detachedNode.id, label: detachedNode.label },
		main: visible(main.root),
		editError: detachedEditError,
	};
	const mainNode = main.root.left[0];
	assert(mainNode instanceof Point);
	assert.equal(detachedNode.id, mainNode.id);
	assert.equal(mainNode.label, "left");
	assert.notEqual(detachedEditError, "");

	const left = fork(main);
	const right = fork(main);
	left.root.title = "arbitrary-target";
	right.merge(left, false);
	assert.equal(right.root.title, "arbitrary-target");
	assert.equal(main.root.title, "base");

	parent.dispose();
	const doubleDisposeError = errorOf(() => parent.dispose());
	nested.root.title = "descendant-live";
	assert.equal(doubleDisposeError, "");
	assert.equal(nested.root.title, "descendant-live");

	main.merge(right);
	provider.synchronizeMessages();
	const afterMerge = visible(main.root);
	assert.equal(afterMerge.title, "arbitrary-target");

	const mainCheckout = provider.trees[0].kernel.checkout;
	main.dispose();
	const replacement = asAlpha(provider.trees[0].viewWith(
		new TreeViewConfiguration({ schema: Root, enableSchemaValidation: true }),
	));
	assert.equal(mainCheckout.disposed, false);
	assert.equal(replacement.root.title, "arbitrary-target");

	return caseFile(
		"local-branch-isolation",
		{
			scenarios: [
				"main-and-nested-forks",
				"stable-attached-identity",
				"detached-identity-isolation",
				"arbitrary-related-local-target",
				"parent-disposal-descendant-lifetime",
				"public-double-disposal",
				"main-view-disposal",
				"no-branch-tree-submission",
			],
		},
		[
			{ id: "isolation", beforeMerge, detachedIsolation, afterMerge },
			{
				id: "lifetime",
				doubleDisposeError,
				parentDisposed: checkoutOf(parent).disposed,
				descendantDisposed: checkoutOf(nested).disposed,
				descendant: visible(nested.root),
				mainCheckoutDisposed: mainCheckout.disposed,
			},
		],
		{ messages: messagesIn(processed.slice(start)), processed: processed.slice(start) },
	);
}

async function captureRebase() {
	const { provider, main } = createViews();
	const source = fork(main);
	const target = fork(main);
	main.root.title = "main-first";
	source.root.count = 1;
	target.root.title = "target";
	const targetBefore = visible(target.root);
	source.rebaseOnto(target);
	assert.deepEqual(visible(target.root), targetBefore);
	assert.equal(source.root.title, "target");
	assert.equal(source.root.count, 1);
	const sourceThenTarget = {
		source: visible(source.root),
		target: visible(target.root),
		sourceRevisions: history(source),
		targetRevisions: history(target),
	};

	const targetFirstViews = createViews();
	const targetFirstSource = fork(targetFirstViews.main);
	const targetFirstTarget = fork(targetFirstViews.main);
	targetFirstTarget.root.title = "target-first";
	targetFirstSource.root.count = 2;
	const targetFirstBefore = visible(targetFirstTarget.root);
	targetFirstSource.rebaseOnto(targetFirstTarget);
	assert.deepEqual(visible(targetFirstTarget.root), targetFirstBefore);
	assert.equal(targetFirstSource.root.title, "target-first");
	assert.equal(targetFirstSource.root.count, 2);
	const targetThenSource = {
		source: visible(targetFirstSource.root),
		target: visible(targetFirstTarget.root),
		sourceRevisions: history(targetFirstSource),
		targetRevisions: history(targetFirstTarget),
	};

	provider.trees[0].containerRuntime.connected = false;
	main.root.title = "optimistic-main";
	const optimistic = fork(main);
	assert.equal(optimistic.root.title, "optimistic-main");
	provider.trees[0].containerRuntime.connected = true;
	provider.synchronizeMessages();

	const selfBefore = history(source);
	source.rebaseOnto(source);
	assert.deepEqual(history(source), selfBefore);

	const schemaProvider = new TestTreeProviderLite(1, treeFactory());
	const oldFactory = new SchemaFactory("org.watershed.branch.schema");
	const oldSchema = oldFactory.array(oldFactory.string);
	const oldView = asAlpha(schemaProvider.trees[0].viewWith(
		new TreeViewConfiguration({ schema: oldSchema, enableSchemaValidation: true }),
	));
	oldView.initialize(["A", "B", "C"]);
	const schemaFork = checkoutOf(oldView).fork();
	const wideFactory = new SchemaFactory("org.watershed.branch.schema");
	const wideSchema = [
		wideFactory.array(wideFactory.string),
		wideFactory.array([wideFactory.string, wideFactory.number]),
	];
	const wideView = schemaFork.viewWith(
		new TreeViewConfiguration({ schema: wideSchema, enableSchemaValidation: true }),
	);
	wideView.upgradeSchema();
	wideView.root.removeAt(2);
	oldView.root.removeAt(0);
	schemaFork.rebaseOnto(checkoutOf(oldView));
	const schemaDivergence = {
		main: [...oldView.root],
		forkCanViewWideSchema: wideView.compatibility.canView,
		forkHistory: history(wideView as unknown as BranchView),
	};
	assert.deepEqual(schemaDivergence.main, ["B", "C"]);
	assert.equal(schemaDivergence.forkCanViewWideSchema, false);

	return caseFile(
		"local-branch-rebase",
		{
			scenarios: [
				"both-edit-orders",
				"target-unchanged",
				"common-revision-rewrite",
				"optimistic-main-base",
				"self-rebase",
				"schema-divergence",
			],
		},
		[
			{ id: "related-target", sourceThenTarget, targetThenSource },
			{ id: "optimistic-main", value: visible(optimistic.root), revisions: history(optimistic) },
			{ id: "self-rebase", revisions: history(source) },
			{ id: "schema-divergence", ...schemaDivergence },
		],
		{ messages: [{ sourceRevisions: history(source), targetRevisions: history(target) }] },
	);
}

async function captureMerge() {
	const { provider, main } = createViews();
	const processed = interceptProcessed(provider);
	const targetWatch = watch(main);
	const source = fork(main);
	const sourceWatch = watch(source);
	source.root.title = "first";
	source.root.count = 2;
	const sourceRevisions = history(source);
	const before = targetWatch.events.length;
	main.merge(source, false);
	const mergeEvents = targetWatch.events.slice(before);
	assert.equal(mergeEvents.length, 2);
	assert.equal(checkoutOf(source).disposed, false);
	assert.equal(main.root.title, "first");
	assert.equal(main.root.count, 2);
	const firstMergeHistory = history(main);

	const repeatedBefore = targetWatch.events.length;
	main.merge(source, false);
	assert.equal(targetWatch.events.length, repeatedBefore);
	assert.deepEqual(history(main), firstMergeHistory);
	const repeatedEventCount = targetWatch.events.length - repeatedBefore;

	const empty = fork(main);
	main.merge(empty);
	assert.equal(checkoutOf(empty).disposed, true);

	const selfPreserved = fork(main);
	const selfBefore = history(selfPreserved);
	selfPreserved.merge(selfPreserved, false);
	assert.deepEqual(history(selfPreserved), selfBefore);
	assert.equal(checkoutOf(selfPreserved).disposed, false);
	selfPreserved.merge(selfPreserved);
	assert.equal(checkoutOf(selfPreserved).disposed, true);

	const defaultDisposed = fork(main);
	defaultDisposed.root.title = "default-disposed";
	main.merge(defaultDisposed);
	assert.equal(checkoutOf(defaultDisposed).disposed, true);
	provider.synchronizeMessages();

	targetWatch.off();
	sourceWatch.off();
	return caseFile(
		"local-branch-merge",
		{
			scenarios: [
				"surviving-source-revisions",
				"one-event-per-source-commit",
				"preserved-source-repeat",
				"empty-merge",
				"self-merge-preserved-and-default",
				"default-source-disposal",
			],
		},
		[
			{
				id: "commit-boundaries",
				sourceRevisions,
				targetRevisions: firstMergeHistory,
				events: mergeEvents,
				sourceEvents: sourceWatch.events,
			},
			{
				id: "merge-edge-cases",
				repeatedEventCount,
				emptyDisposed: checkoutOf(empty).disposed,
				selfPreservedDisposed: false,
				selfDefaultDisposed: checkoutOf(selfPreserved).disposed,
				defaultDisposed: checkoutOf(defaultDisposed).disposed,
			},
		],
		{ messages: messagesIn(processed), processed, encodedChanges: mergeEvents.map((event) => Reflect.get(event, "change")) },
	);
}

async function captureTransactions() {
	const { main } = createViews();
	const source = fork(main);
	const before = history(source).length;
	const events = watch(source);
	Tree.runTransaction(source, () => {
		source.root.title = "outer";
		const result = Tree.runTransaction(source, () => {
			source.root.count = 99;
			return Tree.runTransaction.rollback;
		});
		assert.equal(result, Tree.runTransaction.rollback);
		source.root.count = 3;
	});
	assert.equal(history(source).length, before + 1);
	assert.equal(events.events.length, 1);

	const rebaseGuard = (active: "source" | "target") => {
		const { main: guardMain } = createViews();
		const guardSource = fork(guardMain);
		const guardTarget = fork(guardMain);
		let error = "";
		Tree.runTransaction(active === "source" ? guardSource : guardTarget, () => {
			error = errorOf(() => guardSource.rebaseOnto(guardTarget));
			return Tree.runTransaction.rollback;
		});
		return error;
	};
	const sourceGuard = rebaseGuard("source");
	const targetGuard = rebaseGuard("target");
	const mergeGuard = (active: "source" | "target") => {
		const { main: mergeMain } = createViews();
		const mergeSource = fork(mergeMain);
		const mergeTarget = fork(mergeMain);
		let error = "";
		Tree.runTransaction(active === "source" ? mergeSource : mergeTarget, () => {
			error = errorOf(() => mergeTarget.merge(mergeSource, false));
			return Tree.runTransaction.rollback;
		});
		return error;
	};
	const sourceMergeGuard = mergeGuard("source");
	const targetMergeGuard = mergeGuard("target");
	const { main: forkMain } = createViews();
	const forkActive = fork(forkMain);
	let forkGuard = "";
	Tree.runTransaction(forkActive, () => {
		forkGuard = errorOf(() => fork(forkActive));
		return Tree.runTransaction.rollback;
	});
	assert.notEqual(sourceGuard, "");
	assert.notEqual(targetGuard, "");
	assert.notEqual(sourceMergeGuard, "");
	assert.notEqual(targetMergeGuard, "");
	assert.notEqual(forkGuard, "");

	const { main: crossMain } = createViews();
	const crossSource = fork(crossMain);
	let crossCheckoutError = "";
	const crossBefore = visible(crossMain.root);
	Tree.runTransaction(crossSource, () => {
		crossCheckoutError = errorOf(() => {
			crossMain.root.title = "cross-checkout";
		});
		return Tree.runTransaction.rollback;
	});
	const crossCheckoutChangedMain = crossMain.root.title !== crossBefore.title;

	const { main: constraintMain } = createViews();
	const constraintSource = fork(constraintMain);
	const constrained = constraintSource.root.featured;
	Tree.runTransaction(
		constraintSource,
		() => {
			constraintSource.root.title = "constrained-change";
		},
		[{ type: "nodeInDocument", node: constrained }],
	);
	constraintMain.root.featured = new Point({ label: "replacement" });
	constraintSource.rebaseOnto(constraintMain);
	const constraintResult = {
		source: visible(constraintSource.root),
		target: visible(constraintMain.root),
		revisions: history(constraintSource),
	};
	assert.equal(constraintResult.source.title, "base");
	assert.equal(constraintResult.target.title, "base");

	const { provider: abortProvider, main: abortMain } = createViews();
	const abortSource = fork(abortMain);
	const compressor = abortProvider.getCompressor(abortProvider.trees[0]);
	const allocationBefore = serializeIdCompressor(compressor, true);
	const abortBefore = visible(abortSource.root);
	Tree.runTransaction(abortSource, () => {
		abortSource.root.right.insertAtEnd(new Point({ label: "aborted-allocation" }));
		return Tree.runTransaction.rollback;
	});
	const allocationAfter = serializeIdCompressor(compressor, true);
	assert.deepEqual(visible(abortSource.root), abortBefore);
	assert.notEqual(allocationAfter, allocationBefore);

	events.off();
	return caseFile(
		"local-branch-transactions",
		{
			scenarios: [
				"nested-abort-and-outer-commit",
				"source-and-target-operation-guards",
				"active-transaction-fork-guard",
				"node-in-document-constraint",
				"cross-checkout-callback",
				"allocation-survives-abort",
			],
		},
		[
			{ id: "outer-commit", value: visible(source.root), revisions: history(source), events: events.events },
			{
				id: "guards",
				sourceGuard,
				targetGuard,
				sourceMergeGuard,
				targetMergeGuard,
				forkGuard,
			},
			{ id: "constraint", ...constraintResult },
			{ id: "cross-checkout", error: crossCheckoutError, changedMain: crossCheckoutChangedMain },
			{
				id: "abort-allocation",
				stateRestored: true,
				allocationAdvanced: allocationAfter !== allocationBefore,
				before: allocationBefore,
				after: allocationAfter,
			},
		],
		{ messages: [{ allocationBefore, allocationAfter }] },
	);
}

async function captureUndo() {
	const { provider, main } = createViews();
	const targetWatch = watch(main, true);
	const source = fork(main);
	const sourceWatch = watch(source, true);
	source.root.title = "branch-change";
	const sourceHandle = sourceWatch.handles[0];
	assert(sourceHandle !== undefined);
	const beforeMerge = {
		sourceSettled: copy(sourceWatch.settled),
		sourceHandle: enumName(RevertibleStatus, sourceHandle.status),
	};
	assert.deepEqual(beforeMerge.sourceSettled, []);

	main.merge(source, false);
	assert.equal(targetWatch.handles.length, 1);
	const targetHandle = targetWatch.handles[0];
	assert(targetHandle !== undefined);
	provider.synchronizeMessages();
	assert.deepEqual(sourceWatch.settled.map((item) => Reflect.get(item, "outcome")), ["FullyApplied"]);
	assert.deepEqual(targetWatch.settled.map((item) => Reflect.get(item, "outcome")), ["FullyApplied"]);

	targetHandle.revert(false);
	assert.equal(main.root.title, "base");
	const targetAfterUndo = visible(main.root);
	const undoHandle = targetWatch.handles.at(-1);
	assert(undoHandle !== undefined && undoHandle !== targetHandle);
	undoHandle.revert(false);
	assert.equal(main.root.title, "branch-change");
	const targetAfterRedo = visible(main.root);
	sourceHandle.revert(false);
	assert.equal(source.root.title, "base");

	const disposedSource = fork(main);
	const disposedWatch = watch(disposedSource, true);
	disposedSource.root.count = 4;
	const disposedHandle = disposedWatch.handles[0];
	assert(disposedHandle !== undefined);
	main.merge(disposedSource);
	assert.equal(enumName(RevertibleStatus, disposedHandle.status), "Disposed");
	const disposedRevertError = errorOf(() => disposedHandle.revert());
	assert.notEqual(disposedRevertError, "");

	const factoryProbe = fork(main);
	let lateFactory: (() => RevertibleAlpha) | undefined;
	let duplicateFactoryError = "";
	const offFactoryProbe = factoryProbe.events.on("changed", (_metadata, getRevertible) => {
		if (getRevertible !== undefined) {
			const handle = getRevertible();
			duplicateFactoryError = errorOf(() => getRevertible());
			handle.dispose();
			lateFactory = getRevertible;
		}
	});
	factoryProbe.root.title = "factory-probe";
	const retainedLateFactory = lateFactory ?? assert.fail("Expected a local revertible factory");
	const lateFactoryError = errorOf(() => retainedLateFactory());
	assert.notEqual(duplicateFactoryError, "");
	assert.notEqual(lateFactoryError, "");
	offFactoryProbe();
	factoryProbe.dispose();

	targetWatch.off();
	sourceWatch.off();
	disposedWatch.off();
	return caseFile(
		"local-branch-undo",
		{
			scenarios: [
				"branch-local-factory",
				"duplicate-factory-call",
				"late-factory-call",
				"branch-settlement-before-and-after-merge",
				"target-merge-factory",
				"redo-from-undo-handle",
				"source-handle-scope",
				"source-disposal-invalidates-handle",
			],
		},
		[
			{
				id: "settlement",
				beforeMerge,
				afterMerge: {
					sourceSettled: sourceWatch.settled,
					targetSettled: targetWatch.settled,
				},
			},
			{
				id: "handles",
				sourceStatus: enumName(RevertibleStatus, sourceHandle.status),
				targetStatus: enumName(RevertibleStatus, targetHandle.status),
				undoStatus: enumName(RevertibleStatus, undoHandle.status),
				targetAfterUndo,
				targetAfterRedo,
				disposedSourceStatus: enumName(RevertibleStatus, disposedHandle.status),
				disposedRevertError,
				duplicateFactoryError,
				lateFactoryError,
			},
		],
		{
			messages: targetWatch.events.map((event) => Reflect.get(event, "change")).filter(Boolean),
			sourceEvents: sourceWatch.events,
			targetEvents: targetWatch.events,
		},
	);
}

async function captureAllocation() {
	const { provider, main } = createViews();
	const processed = interceptProcessed(provider);
	const start = processed.length;
	const branch = fork(main);
	const compressor = provider.getCompressor(provider.trees[0]);
	const beforeBranchReservation = serializeIdCompressor(compressor, true);
	branch.root.right.insertAtEnd(new Point({ label: "branch-id" }));
	provider.synchronizeMessages();
	const afterBranchReservation = serializeIdCompressor(compressor, true);
	const branchOnlyProcessed = processed.slice(start);
	const branchOnlyMessages = messagesIn(branchOnlyProcessed);
	const branchOnlyRanges = allocationRangesIn(branchOnlyProcessed);
	assert.equal(branchOnlyMessages.length, 0);
	assert.equal(branchOnlyRanges.length, 0);
	assert.notEqual(afterBranchReservation, beforeBranchReservation);

	const mainStart = processed.length;
	main.root.left.insertAtEnd(new Point({ label: "main-id" }));
	provider.synchronizeMessages();
	const mainProcessed = processed.slice(mainStart);
	const mainMessages = messagesIn(mainProcessed);
	const mainRanges = allocationRangesIn(mainProcessed);
	assert(mainMessages.some((message) => JSON.stringify(message).includes("main-id")));
	assert(mainMessages.every((message) => !JSON.stringify(message).includes("branch-id")));
	assert(mainRanges.length > 0);

	const beforeAbort = serializeIdCompressor(compressor, true);
	Tree.runTransaction(branch, () => {
		branch.root.right.insertAtEnd(new Point({ label: "aborted-id" }));
		return Tree.runTransaction.rollback;
	});
	const afterAbort = serializeIdCompressor(compressor, true);
	assert.notEqual(afterAbort, beforeAbort);

	const mergeStart = processed.length;
	main.merge(branch);
	provider.synchronizeMessages();
	const mergeProcessed = processed.slice(mergeStart);
	const mergeMessages = messagesIn(mergeProcessed);
	const mergeRanges = allocationRangesIn(mergeProcessed);
	const identifiers = [
		...main.root.left.filter((item): item is Point => item instanceof Point).map((item) => item.id),
		...main.root.right.filter((item): item is Point => item instanceof Point).map((item) => item.id),
	];
	assert.equal(new Set(identifiers).size, identifiers.length);
	assert(mergeMessages.some((message) => JSON.stringify(message).includes("branch-id")));

	return caseFile(
		"local-branch-allocation",
		{
			scenarios: [
				"shared-compressor",
				"interleaved-identifiers",
				"branch-only-reservation",
				"main-triggered-publication",
				"aborted-range-retained",
				"merge-range-before-tree-use",
			],
		},
		[
			{
				id: "branch-only",
				messages: branchOnlyMessages,
				allocationRanges: branchOnlyRanges,
				reservationAdvanced: beforeBranchReservation !== afterBranchReservation,
				before: beforeBranchReservation,
				after: afterBranchReservation,
			},
			{
				id: "main-publication",
				allocationRanges: mainRanges,
				messages: mainMessages,
			},
			{
				id: "merge-publication",
				identifiers,
				allocationRanges: mergeRanges,
				messages: mergeMessages,
			},
			{
				id: "abort-range",
				allocationAdvanced: afterAbort !== beforeAbort,
				before: beforeAbort,
				after: afterAbort,
			},
		],
		{
			messages: [...mainMessages, ...mergeMessages],
			ranges: [...mainRanges, ...mergeRanges],
			branchOnlyProcessed,
			mainProcessed,
			mergeProcessed,
		},
	);
}

async function captureRetention() {
	const { provider, main } = createViews();
	const parent = fork(main);
	const descendant = fork(parent);
	const watched = watch(descendant, true);
	descendant.root.title = "retained";
	const handle = watched.handles[0];
	assert(handle !== undefined);
	const initialMinimum = provider.minimumSequenceNumber;
	for (let index = 0; index < 8; index++) {
		main.root.count = index + 1;
		provider.synchronizeMessages();
	}
	assert(provider.minimumSequenceNumber > initialMinimum);
	const beforeDisposal = {
		minimumSequenceNumber: provider.minimumSequenceNumber,
		mainHistory: main.branchHistory.length,
		parentHistory: parent.branchHistory.length,
		descendantHistory: descendant.branchHistory.length,
		handleStatus: enumName(RevertibleStatus, handle.status),
	};
	parent.dispose();
	descendant.root.count = 99;
	handle.revert(false);
	assert.equal(descendant.root.title, "base");
	const afterParentDisposal = {
		parentDisposed: checkoutOf(parent).disposed,
		descendantDisposed: checkoutOf(descendant).disposed,
		descendant: visible(descendant.root),
		handleStatus: enumName(RevertibleStatus, handle.status),
	};
	descendant.rebaseOnto(main);
	const afterRebase = {
		history: history(descendant),
		value: visible(descendant.root),
	};
	const historyBeforeRelease = main.branchHistory.length;
	handle.dispose();
	descendant.dispose();
	assert.equal(enumName(RevertibleStatus, handle.status), "Disposed");
	for (let index = 0; index < 3; index++) {
		main.root.count = 100 + index;
		provider.synchronizeMessages();
	}
	const historyAfterRelease = main.branchHistory.length;
	assert(historyAfterRelease < historyBeforeRelease);
	const release = {
		historyBeforeRelease,
		historyAfterRelease,
		minimumSequenceNumber: provider.minimumSequenceNumber,
	};
	watched.off();
	return caseFile(
		"local-branch-retention",
		{
			scenarios: [
				"multiple-branch-pins",
				"live-revertible-and-fork",
				"minimum-sequence-advance",
				"parent-disposal-descendant-pin",
				"rebase-advances-pin",
				"disposal-releases-handle",
				"post-release-reclamation",
			],
		},
		[
			{ id: "minimum-sequence-retention", beforeDisposal },
			{ id: "parent-disposal", afterParentDisposal },
			{
				id: "rebase-release",
				afterRebase,
				finalHandleStatus: enumName(RevertibleStatus, handle.status),
				release,
			},
		],
		{ messages: [{ minimumSequenceNumber: provider.minimumSequenceNumber, revisions: afterRebase.history }] },
	);
}

async function loadSummary(
	summary: Awaited<ReturnType<TreeInstance["summarize"]>>["summary"],
	compressor: SerializedIdCompressorWithNoSession,
	id: string,
) {
	const runtime = new MockFluidDataStoreRuntime({
		idCompressor: deserializeIdCompressor(compressor, createSessionId()),
	});
	const factory = treeFactory();
	const submitted: unknown[] = [];
	const services = MockSharedObjectServices.createFromSummary(summary);
	services.deltaConnection = new MockDeltaConnection((message) => {
		submitted.push(copy(message));
		return 1;
	}, () => {});
	const tree = await factory.load(
		runtime,
		id,
		services,
		factory.attributes,
	);
	return {
		view: asAlpha(tree.viewWith(
			new TreeViewConfiguration({ schema: Root, enableSchemaValidation: true }),
		)),
		submitted,
	};
}

async function captureRecovery() {
	const acceptedProvider = createViews(2);
	const acceptedPeer = acceptedProvider.peers[0];
	assert(acceptedPeer !== undefined);
	const acceptedProcessed = interceptProcessed(acceptedProvider.provider);
	acceptedProvider.main.root.title = "accepted-before-drop";
	const acceptedBranch = fork(acceptedProvider.main);
	acceptedBranch.root.count = 23;
	const acceptedBranchBeforeRecovery = visible(acceptedBranch.root);
	while (acceptedProvider.provider.peekNextMessage() !== undefined
		&& messagesIn(acceptedProvider.provider.peekNextMessage()).length === 0) {
		acceptedProvider.provider.synchronizeMessages({ count: 1 });
	}
	acceptedProvider.provider.trees[0].containerRuntime.pauseInboundProcessing();
	const accepted: unknown[] = [];
	while (acceptedPeer.root.title !== "accepted-before-drop") {
		const next = acceptedProvider.provider.peekNextMessage();
		assert(next !== undefined, "Pending main edit was not submitted");
		accepted.push(copy(next));
		acceptedProvider.provider.synchronizeMessages({ count: 1 });
	}
	acceptedProvider.provider.trees[0].containerRuntime.connected = false;
	const acceptedReplayStart = acceptedProcessed.length;
	acceptedProvider.provider.trees[0].containerRuntime.resumeInboundProcessing();
	acceptedProvider.provider.trees[0].containerRuntime.connected = true;
	acceptedProvider.provider.synchronizeMessages();
	assert.equal(acceptedProvider.main.root.title, "accepted-before-drop");
	assert.equal(acceptedBranch.root.title, "accepted-before-drop");
	assert.equal(acceptedBranch.root.count, 23);
	const acceptedMergeStart = acceptedProcessed.length;
	acceptedProvider.main.merge(acceptedBranch);
	acceptedProvider.provider.synchronizeMessages();
	const acceptedMergeMessages = messagesIn(acceptedProcessed.slice(acceptedMergeStart));
	assert.equal(acceptedProvider.main.root.count, 23);
	assert.equal(acceptedPeer.root.title, "accepted-before-drop");
	assert.equal(acceptedPeer.root.count, 23);
	assert.equal(acceptedMergeMessages.length, 1);
	const acceptedBeforeDrop = {
		acceptedMessages: messagesIn(accepted),
		reconnectMessages: messagesIn(acceptedProcessed.slice(acceptedReplayStart, acceptedMergeStart)),
		mergeMessages: acceptedMergeMessages,
		branchBeforeRecovery: acceptedBranchBeforeRecovery,
		main: visible(acceptedProvider.main.root),
		peer: visible(acceptedPeer.root),
		sourceDisposed: checkoutOf(acceptedBranch).disposed,
	};

	const { provider, main, peers: [peer] } = createViews(2);
	assert(peer !== undefined);
	const processed = interceptProcessed(provider);
	provider.trees[0].containerRuntime.connected = false;
	main.root.title = "pending-main";
	const branch = fork(main);
	branch.root.count = 17;
	const unmergedSummary = (await provider.trees[1].summarize(true)).summary;
	const compressor = serializeIdCompressor(provider.getCompressor(provider.trees[1]), false);
	const unmergedReader = await loadSummary(unmergedSummary, compressor, "branch-unmerged-reader");
	assert.equal(unmergedReader.view.root.title, "base");
	assert.equal(unmergedReader.view.root.count, 0);

	const reconnectStart = processed.length;
	provider.trees[0].containerRuntime.connected = true;
	provider.synchronizeMessages();
	const replayAfterReconnect = messagesIn(processed.slice(reconnectStart));
	assert.equal(main.root.title, "pending-main");
	assert.equal(peer.root.title, "pending-main");

	const branchBeforeMerge = visible(branch.root);
	const mergeStart = processed.length;
	main.merge(branch);
	provider.synchronizeMessages();
	const mergeMessages = messagesIn(processed.slice(mergeStart));
	assert.equal(main.root.count, 17);
	assert.equal(peer.root.count, 17);
	const mergedSummary = (await provider.trees[1].summarize(true)).summary;
	const mergedCompressor = serializeIdCompressor(provider.getCompressor(provider.trees[1]), false);
	const mergedReader = await loadSummary(mergedSummary, mergedCompressor, "branch-merged-reader");
	assert.equal(mergedReader.view.root.title, "pending-main");
	assert.equal(mergedReader.view.root.count, 17);
	mergedReader.view.root.title = "continued";
	assert.equal(mergedReader.view.root.title, "continued");
	assert(mergedReader.submitted.length > 0);

	return caseFile(
		"local-branch-recovery",
		{
			scenarios: [
				"pending-main-fork-origin",
				"reconnect-accepted-before-drop",
				"nonduplicated-merge",
				"unmerged-summary-exclusion",
				"merged-summary-continuation",
			],
		},
		[
			{
				id: "pending-origin",
				branchBeforeMerge,
				sourceDisposedAfterMerge: checkoutOf(branch).disposed,
				mainAfterReconnect: visible(main.root),
				replayAfterReconnect,
			},
			{ id: "accepted-before-drop", ...acceptedBeforeDrop },
			{
				id: "summary-exclusion",
				unmergedLoaded: visible(unmergedReader.view.root),
				summaryContainsForkCount: JSON.stringify(unmergedSummary).includes("17"),
			},
			{
				id: "merged-continuation",
				mergeMessages,
				mergedLoaded: visible(mergedReader.view.root),
				continuationMessages: messagesIn(mergedReader.submitted),
			},
		],
		{
			messages: [
				...acceptedBeforeDrop.acceptedMessages,
				...acceptedBeforeDrop.reconnectMessages,
				...acceptedBeforeDrop.mergeMessages,
				...replayAfterReconnect,
				...mergeMessages,
				...messagesIn(mergedReader.submitted),
			],
			unmergedSummary,
			mergedSummary,
		},
	);
}

describe("Watershed local branch oracle", () => {
	it("captures the pinned local branch contract", async () => {
		const output = process.env.WATERSHED_ORACLE_OUTPUT;
		assert(output !== undefined && isAbsolute(output), "WATERSHED_ORACLE_OUTPUT must be absolute");
		assert.equal(process.env.WATERSHED_ORACLE_COMMIT, reference.commit);
		mkdirSync(output, { recursive: true });
		const cases = [
			await captureIsolation(),
			await captureRebase(),
			await captureMerge(),
			await captureTransactions(),
			await captureUndo(),
			await captureAllocation(),
			await captureRetention(),
			await captureRecovery(),
		];
		writeFileSync(
			join(output, "branch-cases.json"),
			`${JSON.stringify(cases, undefined, 2)}\n`,
			"utf8",
		);
	});
});
