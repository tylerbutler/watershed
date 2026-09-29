/*!
 * Copyright (c) Microsoft Corporation and contributors. All rights reserved.
 * Licensed under the MIT License.
 */

import { strict as assert } from "node:assert";
import { mkdirSync, writeFileSync } from "node:fs";
import { isAbsolute, join } from "node:path";

import type {
	IIdCompressor,
	SessionSpaceCompressedId,
} from "@fluidframework/id-compressor";
import { serializeIdCompressor } from "@fluidframework/id-compressor/internal";

import { FluidClientVersion } from "../codec/index.js";
import {
	tagChange,
	type GraphCommit,
	type RevisionTag,
	type TaggedChange,
} from "../core/index.js";
import {
	jsonableTreeFromFieldCursor,
	type ModularChangeset,
} from "../feature-libraries/index.js";
import type { NodeChangeset } from "../feature-libraries/modular-schema/modularChangeTypes.js";
import {
	SchemaFactory,
	TreeViewConfiguration,
	type TreeView,
} from "../simple-tree/index.js";
import { Tree, type SharedTreeChange } from "../shared-tree/index.js";
import { configuredSharedTreeInternal } from "../treeFactory.js";
import { MockContainerRuntimeWithOpBunching } from "./mocksForOpBunching.js";
import { TestTreeProviderLite } from "./utils.js";

const formatVersion = 1;
const reference = {
	package: "@fluidframework/tree",
	version: "3.1.0",
	commit: "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960",
};

const sf = new SchemaFactory("org.watershed.shared-tree.transactions");
class Point extends sf.object("Point", {
	label: sf.string,
	x: sf.number,
}) {}
class Items extends sf.array("Items", [sf.string, Point]) {}
class NamedMap extends sf.map("NamedMap", [sf.string, Point, Items]) {}
class Root extends sf.object("Root", {
	title: sf.string,
	count: sf.number,
	left: Items,
	right: Items,
	byKey: NamedMap,
}) {}

type TreeInstance = TestTreeProviderLite["trees"][number];
type Commit = GraphCommit<SharedTreeChange>;
type TransactionView = TreeView<typeof Root>;

function treeFactory() {
	return configuredSharedTreeInternal({
		minVersionForCollab: FluidClientVersion.v2_117,
	}).getFactory();
}

function initialRoot() {
	return new Root({
		title: "base",
		count: 0,
		left: new Items([
			new Point({ label: "left-a", x: 1 }),
			new Point({ label: "left-b", x: 2 }),
		]),
		right: new Items([new Point({ label: "right-a", x: 3 })]),
		byKey: new NamedMap([["seed", "value"]]),
	});
}

function copy<T>(value: T): T {
	return JSON.parse(JSON.stringify(value));
}

function caseFile(id: string, domain: string, input: object, observations: object[], raw: object) {
	assert(observations.length > 0);
	return { formatVersion, reference, id, domain, input, expected: { observations }, raw };
}

function visible(root: Root) {
	const value = (item: string | Point): unknown =>
		item instanceof Point ? { id: item.label, label: item.label, x: item.x } : item;
	return {
		title: root.title,
		count: root.count,
		left: [...root.left].map(value),
		right: [...root.right].map(value),
		byKey: [...root.byKey].map(([key, item]) => [
			key,
			item instanceof Point
				? { id: item.label, label: item.label, x: item.x }
				: item instanceof Items
					? [...item].map(value)
					: item,
		]),
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

function revision(value: RevisionTag | undefined, compressor: IIdCompressor): string | null {
	return value === undefined
		? null
		: compressor.decompress(value as SessionSpaceCompressedId);
}

function atom(
	value: { revision?: RevisionTag; localId: number },
	compressor: IIdCompressor,
) {
	return { revision: revision(value.revision, compressor), localId: value.localId };
}

function fieldChanges(value: ModularChangeset["fieldChanges"]) {
	return [...value].map(([field, change]) => ({
		field,
		kind: change.fieldKind,
	}));
}

function nodeChange(value: NodeChangeset) {
	return {
		fields: fieldChanges(value.fieldChanges ?? new Map()),
		nodeExistsConstraint: value.nodeExistsConstraint ?? null,
		nodeExistsConstraintOnRevert: value.nodeExistsConstraintOnRevert ?? null,
	};
}

function modularChange(value: ModularChangeset, compressor: IIdCompressor) {
	const chunks = (entries: ModularChangeset["builds"]) =>
		[...(entries?.entries() ?? [])].map(([[major, minor], chunk]) => ({
			id: atom({ revision: major, localId: minor }, compressor),
			trees: jsonableTreeFromFieldCursor(chunk.cursor()),
		}));
	return {
		maxId: value.maxId ?? -1,
		revisions: (value.revisions ?? []).map((info) => ({
			revision: revision(info.revision, compressor),
			rollbackOf: revision(info.rollbackOf, compressor),
		})),
		fields: fieldChanges(value.fieldChanges),
		nodes: [...value.nodeChanges.entries()].map(([[major, minor], change]) => ({
			id: atom({ revision: major, localId: minor }, compressor),
			change: nodeChange(change),
		})),
		parents: [...value.nodeToParent.entries()].map(([[major, minor], parent]) => ({
			id: atom({ revision: major, localId: minor }, compressor),
			parent: parent.nodeId === undefined ? null : atom(parent.nodeId, compressor),
			field: parent.field,
		})),
		aliases: [...value.nodeAliases.entries()].map(([[major, minor], target]) => ({
			id: atom({ revision: major, localId: minor }, compressor),
			target: atom(target, compressor),
		})),
		builds: chunks(value.builds),
		refreshers: chunks(value.refreshers),
		constraintViolationCount: value.constraintViolationCount ?? 0,
	};
}

type NormalizedSharedChange =
	| { type: "data"; change: ReturnType<typeof modularChange> }
	| { type: "schema"; change: unknown };

function sharedChange(
	value: SharedTreeChange,
	compressor: IIdCompressor,
): NormalizedSharedChange[] {
	return value.changes.map((change) => ({
		type: change.type,
		change: change.type === "data" ? modularChange(change.innerChange, compressor) : copy(change.innerChange),
	})) as NormalizedSharedChange[];
}

function managerState(tree: TreeInstance, compressor: IIdCompressor) {
	const manager = Reflect.get(tree.kernel, "editManager") as {
		getLocalCommits(branch: string): Commit[];
		getTrunkCommits(branch: string): Commit[];
	};
	const observe = (commit: Commit) => ({
		revision: revision(commit.revision, compressor),
		changes: sharedChange(commit.change, compressor),
	});
	return {
		pending: manager.getLocalCommits("main").map(observe),
		trunk: manager.getTrunkCommits("main").map(observe),
	};
}

function transactionDepth(view: TransactionView): number {
	const checkout = Reflect.get(view, "checkout") as {
		transaction: { size: number };
	};
	return checkout.transaction.size;
}

function captureEvents(view: TransactionView) {
	const events: object[] = [];
	let commits = 0;
	const checkout = Reflect.get(view, "checkout") as {
		events: { on(name: "changed", listener: () => void): () => void };
	};
	const offCommit = view.events.on("commitApplied", () => {
		commits += 1;
	});
	const offChanged = checkout.events.on("changed", () => {
		events.push({ kind: "changed", value: visible(view.root), depth: transactionDepth(view) });
	});
	return {
		events,
		get commits() {
			return commits;
		},
		stop() {
			offCommit();
			offChanged();
		},
	};
}

async function callbackScenario(
	id: string,
	run: (view: TransactionView, reads: object[]) => void,
) {
	const provider = new TestTreeProviderLite(2, treeFactory());
	const processed = interceptProcessed(provider);
	const view = provider.trees[0].viewWith(new TreeViewConfiguration({ schema: Root }));
	view.initialize(initialRoot());
	provider.synchronizeMessages();
	const beforeMessages = processed.length;
	const reads: object[] = [];
	const events = captureEvents(view);
	run(view, reads);
	const pending = managerState(provider.trees[0], provider.getCompressor(provider.trees[0]));
	provider.synchronizeMessages();
	const result = {
		id,
		reads,
		events: events.events,
		commitCount: events.commits,
		pendingCommitCount: pending.pending.length,
		submittedMessages: messagesIn(processed.slice(beforeMessages)),
		final: visible(view.root),
		depth: transactionDepth(view),
	};
	events.stop();
	return result;
}

async function captureCallbacks() {
	const scenarios = [
		await callbackScenario("success-all-fields", (view, reads) => {
			Tree.runTransaction(view, () => {
				assert.equal(transactionDepth(view), 1);
				view.root.title = "object";
				reads.push({ step: "object", value: visible(view.root) });
				view.root.byKey.set("added", "map");
				reads.push({ step: "map", value: visible(view.root) });
				view.root.left.insertAtEnd("array");
				reads.push({ step: "array", value: visible(view.root) });
				view.root.right.moveRangeToEnd(0, 1, view.root.left);
				reads.push({ step: "move", value: visible(view.root) });
			});
		}),
		await callbackScenario("outer-rollback", (view, reads) => {
			const before = visible(view.root);
			const result = Tree.runTransaction(view, () => {
				view.root.title = "rolled-back";
				view.root.left.insertAtEnd("temporary");
				reads.push({ step: "before-rollback", value: visible(view.root) });
				return Tree.runTransaction.rollback;
			});
			assert.equal(result, Tree.runTransaction.rollback);
			assert.deepEqual(visible(view.root), before);
		}),
		await callbackScenario("nested-success", (view, reads) => {
			Tree.runTransaction(view, () => {
				assert.equal(transactionDepth(view), 1);
				view.root.title = "outer";
				Tree.runTransaction(view, () => {
					assert.equal(transactionDepth(view), 2);
					view.root.count = 2;
					reads.push({ step: "inner", value: visible(view.root) });
				});
				assert.equal(transactionDepth(view), 1);
				view.root.left.insertAtEnd("after-inner");
			});
		}),
		await callbackScenario("nested-rollback", (view, reads) => {
			Tree.runTransaction(view, () => {
				view.root.title = "outer";
				const inner = Tree.runTransaction(view, () => {
					view.root.count = 99;
					view.root.left.insertAtEnd("inner");
					reads.push({ step: "inner-before-rollback", value: visible(view.root) });
					return Tree.runTransaction.rollback;
				});
				assert.equal(inner, Tree.runTransaction.rollback);
				reads.push({ step: "after-inner-rollback", value: visible(view.root) });
				view.root.right.insertAtEnd("outer-continued");
			});
		}),
		await callbackScenario("no-op", (view, reads) => {
			Tree.runTransaction(view, () => {
				reads.push({ step: "inside", value: visible(view.root) });
			});
		}),
	];
	for (const scenario of scenarios) {
		assert.equal(scenario.depth, 0, `${scenario.id}: transaction depth`);
		if (scenario.id === "outer-rollback" || scenario.id === "no-op") {
			assert.equal(scenario.pendingCommitCount, 0, `${scenario.id}: pending commits`);
			assert.equal(scenario.submittedMessages.length, 0, `${scenario.id}: messages`);
		} else {
			assert.equal(scenario.pendingCommitCount, 1, `${scenario.id}: pending commits`);
			assert.equal(scenario.commitCount, 1, `${scenario.id}: commit count`);
			assert.equal(scenario.submittedMessages.length, 1, `${scenario.id}: messages`);
		}
	}
	return caseFile(
		"transaction-callbacks",
		"tree",
		{ scenarios: scenarios.map(({ id }) => ({ id, api: "Tree.runTransaction" })) },
		scenarios,
		{ scenarios, messages: scenarios.flatMap(({ submittedMessages }) => submittedMessages) },
	);
}

async function captureConstraints() {
	const moveProvider = new TestTreeProviderLite(2, treeFactory());
	const moveView = moveProvider.trees[0].viewWith(new TreeViewConfiguration({ schema: Root }));
	moveView.initialize(initialRoot());
	moveProvider.synchronizeMessages();
	const target = moveView.root.left[0];
	assert(target instanceof Point);
	Tree.runTransaction(
		moveView,
		() => {
			moveView.root.left.moveRangeToEnd(0, 1);
			target.label = "within-move";
		},
		[{ type: "nodeInDocument", node: target }],
	);
	moveProvider.synchronizeMessages();
	const withinMove = {
		targetAtEnd: moveView.root.left.at(-1) === target,
		value: visible(moveView.root),
	};
	Tree.runTransaction(
		moveView,
		() => {
			const index = [...moveView.root.left].indexOf(target);
			moveView.root.right.moveRangeToEnd(index, index + 1, moveView.root.left);
			target.label = "cross-move";
		},
		[{ type: "nodeInDocument", node: target }],
	);
	moveProvider.synchronizeMessages();
	const crossMove = {
		targetAtEnd: moveView.root.right.at(-1) === target,
		value: visible(moveView.root),
	};

	const refusalProvider = new TestTreeProviderLite(1, treeFactory());
	const refusalView = refusalProvider.trees[0].viewWith(new TreeViewConfiguration({ schema: Root }));
	refusalView.initialize(initialRoot());
	refusalProvider.synchronizeMessages();
	const detached = refusalView.root.left[0];
	assert(detached instanceof Point);
	refusalView.root.left.removeAt(0);
	let callbackRan = false;
	let refusal = "";
	try {
		Tree.runTransaction(
			refusalView,
			() => {
				callbackRan = true;
			},
			[{ type: "nodeInDocument", node: detached }],
		);
	} catch (error) {
		refusal = String(error);
	}
	assert.equal(callbackRan, false);
	assert.match(refusal, /not currently in the document/);

	const provider = new TestTreeProviderLite(2, treeFactory());
	const processed = interceptProcessed(provider);
	const view = provider.trees[0].viewWith(new TreeViewConfiguration({ schema: Root }));
	view.initialize(initialRoot());
	provider.synchronizeMessages();
	const peer = provider.trees[1].viewWith(new TreeViewConfiguration({ schema: Root }));
	const constrained = view.root.left[0];
	assert(constrained instanceof Point);
	provider.trees[0].containerRuntime.connected = false;
	const beforeMessages = processed.length;
	Tree.runTransaction(
		view,
		() => {
			constrained.label = "suppressed";
			view.root.right.insertAtEnd(new Point({ label: "created", x: 9 }));
		},
		[
			{ type: "nodeInDocument", node: constrained },
			{ type: "nodeInDocument", node: constrained },
		],
	);
	const pending = managerState(provider.trees[0], provider.getCompressor(provider.trees[0]));
	peer.root.left.removeAt(0);
	provider.synchronizeMessages();
	provider.trees[0].containerRuntime.connected = true;
	provider.synchronizeMessages();
	const settled = managerState(provider.trees[0], provider.getCompressor(provider.trees[0]));
	const constraintCommit = settled.trunk.find((commit) =>
		commit.changes.some((change) =>
			change.type === "data" && change.change.constraintViolationCount === 1));
	assert(constraintCommit !== undefined, "Expected an explicitly violated transaction.");
	const retainedBuilds = constraintCommit.changes.flatMap((change) =>
		change.type === "data" ? change.change.builds : []);
	assert(retainedBuilds.length > 0, "Violated transactions must retain created content.");
	const observation = {
		id: "node-in-document",
		refusal: { callbackRan, error: refusal },
		withinMove,
		crossMove,
		pending,
		settled,
		final: visible(view.root),
		constraintViolationCount: 1,
		retainedBuilds,
		reconnectMessages: messagesIn(processed.slice(beforeMessages)),
	};
	return caseFile(
		"transaction-constraints",
		"modular",
		{
			scenarios: [
				{ id: "detached-refusal", constraint: "nodeInDocument" },
				{ id: "same-array-move", constraint: "nodeInDocument" },
				{ id: "cross-array-move", constraint: "nodeInDocument" },
				{ id: "concurrent-removal", constraints: ["nodeInDocument", "nodeInDocument"] },
			],
		},
		[observation],
		{ scenarios: [observation], messages: observation.reconnectMessages },
	);
}

async function captureWire() {
	const provider = new TestTreeProviderLite(2, treeFactory());
	const processed = interceptProcessed(provider);
	const view = provider.trees[0].viewWith(new TreeViewConfiguration({ schema: Root }));
	view.initialize(initialRoot());
	provider.synchronizeMessages();
	const target = view.root.left[0];
	assert(target instanceof Point);
	const start = processed.length;
	Tree.runTransaction(
		view,
		() => {
			target.label = "wire";
			view.root.right.insertAtEnd(new Point({ label: "wire-created", x: 10 }));
		},
		[
			{ type: "nodeInDocument", node: target },
			{ type: "nodeInDocument", node: target },
		],
	);
	const pending = managerState(provider.trees[0], provider.getCompressor(provider.trees[0]));
	const checkout = Reflect.get(view, "checkout") as {
		changeFamily: {
			rebaser: {
				compose(changes: TaggedChange<SharedTreeChange>[]): SharedTreeChange;
				invert(
					change: TaggedChange<SharedTreeChange>,
					isRollback: boolean,
					revision: RevisionTag,
				): SharedTreeChange;
			};
		};
	};
	const manager = Reflect.get(provider.trees[0].kernel, "editManager") as {
		getLocalCommits(branch: string): Commit[];
	};
	const local = manager.getLocalCommits("main");
	assert.equal(local.length, 1);
	const compressor = provider.getCompressor(provider.trees[0]);
	const inverseRevision = compressor.generateCompressedId() as RevisionTag;
	const tagged = tagChange(local[0].change, local[0].revision);
	const composed = checkout.changeFamily.rebaser.compose([tagged, tagged]);
	const inverted = checkout.changeFamily.rebaser.invert(tagged, false, inverseRevision);
	provider.synchronizeMessages();
	const messages = messagesIn(processed.slice(start));
	assert.equal(messages.length, 1);
	const observation = {
		id: "modular-v5-shared-tree-v5",
		message: messages[0],
		messageBytes: JSON.stringify(messages[0]),
		pending,
		composed: sharedChange(composed, compressor),
		inverted: sharedChange(inverted, compressor),
	};
	const inverseData = observation.inverted.find((change) => change.type === "data");
	assert(inverseData !== undefined);
	assert(inverseData.change.nodes.some((node) =>
		node.change.nodeExistsConstraintOnRevert !== null));
	return caseFile(
		"transaction-wire",
		"codec",
		{
			scenarios: [{
				id: "modular-v5-shared-tree-v5",
				duplicates: 2,
				nestedPath: ["left", "0"],
				includesBuild: true,
				includesRevisionInfo: true,
			}],
		},
		[observation],
		{ messages, messageBytes: observation.messageBytes, algebra: { composed, inverted } },
	);
}

async function captureHistory() {
	const provider = new TestTreeProviderLite(2, treeFactory());
	const processed = interceptProcessed(provider);
	const view = provider.trees[0].viewWith(new TreeViewConfiguration({ schema: Root }));
	view.initialize(initialRoot());
	provider.synchronizeMessages();
	const target = view.root.left[0];
	assert(target instanceof Point);
	provider.trees[0].containerRuntime.connected = false;
	const start = processed.length;
	Tree.runTransaction(
		view,
		() => {
			target.label = "pending";
			view.root.right.insertAtEnd(new Point({ label: "history-created", x: 11 }));
		},
		[{ type: "nodeInDocument", node: target }],
	);
	const pending = managerState(provider.trees[0], provider.getCompressor(provider.trees[0]));
	const pendingSummary = (await provider.trees[1].summarize(true)).summary;
	const pendingCompressor = serializeIdCompressor(
		provider.getCompressor(provider.trees[0]),
		false,
	);
	provider.trees[0].containerRuntime.connected = true;
	provider.synchronizeMessages();
	const acknowledged = managerState(
		provider.trees[0],
		provider.getCompressor(provider.trees[0]),
	);
	const reconnectMessages = messagesIn(processed.slice(start));
	assert.equal(pending.pending.length, 1);
	assert.equal(acknowledged.pending.length, 0);
	assert.equal(reconnectMessages.length, 1);

	const tailProvider = new TestTreeProviderLite(2, treeFactory());
	const tailProcessed = interceptProcessed(tailProvider, 1);
	const tailView = tailProvider.trees[0].viewWith(new TreeViewConfiguration({ schema: Root }));
	tailView.initialize(initialRoot());
	tailProvider.synchronizeMessages();
	const tailStart = tailProcessed.length;
	const snapshot = (await tailProvider.trees[0].summarize(true)).summary;
	const tailTarget = tailView.root.left[0];
	assert(tailTarget instanceof Point);
	Tree.runTransaction(
		tailView,
		() => {
			tailTarget.label = "tail";
			tailView.root.right.insertAtEnd(new Point({ label: "tail-created", x: 12 }));
		},
		[{ type: "nodeInDocument", node: tailTarget }],
	);
	tailProvider.synchronizeMessages();
	const tailMessages = messagesIn(tailProcessed.slice(tailStart));
	assert.equal(tailMessages.length, 1);
	const observation = {
		id: "reconnect-summary-history",
		pending,
		pendingSummary,
		pendingCompressor,
		reconnectMessages,
		acknowledged,
		final: visible(view.root),
		summaryPlusTail: {
			snapshot,
			tailMessages,
			final: visible(tailView.root),
			history: managerState(
				tailProvider.trees[0],
				tailProvider.getCompressor(tailProvider.trees[0]),
			),
		},
	};
	return caseFile(
		"transaction-history",
		"history",
		{
			scenarios: [{
				id: "reconnect-summary-history",
				actions: [
					{ op: "disconnect" },
					{ op: "transaction", edits: 2, constraints: 1 },
					{ op: "summary" },
					{ op: "reconnect" },
					{ op: "acknowledge" },
					{ op: "summary-plus-tail" },
				],
			}],
		},
		[observation],
		{ messages: reconnectMessages, summary: pendingSummary, observation },
	);
}

describe("Watershed transaction oracle", () => {
	it("captures the pinned transaction contract", async () => {
		const output = process.env.WATERSHED_ORACLE_OUTPUT;
		assert(output !== undefined && isAbsolute(output), "WATERSHED_ORACLE_OUTPUT must be absolute");
		assert.equal(process.env.WATERSHED_ORACLE_COMMIT, reference.commit);
		mkdirSync(output, { recursive: true });
		const cases = [
			await captureCallbacks(),
			await captureConstraints(),
			await captureWire(),
			await captureHistory(),
		];
		writeFileSync(
			join(output, "transaction-cases.json"),
			`${JSON.stringify(cases, undefined, 2)}\n`,
			"utf8",
		);
	});
});
