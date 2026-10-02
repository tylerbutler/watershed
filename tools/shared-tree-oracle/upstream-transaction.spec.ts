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
import {
	createSessionId,
	deserializeIdCompressor,
	serializeIdCompressor,
	toIdCompressorWithCore,
	type IdCreationRange,
} from "@fluidframework/id-compressor/internal";
import {
	MockDeltaConnection,
	MockFluidDataStoreRuntime,
	MockSharedObjectServices,
} from "@fluidframework/test-runtime-utils/internal";

import { FluidClientVersion, FormatValidatorNoOp } from "../codec/index.js";
import {
	revisionMetadataSourceFromInfo,
	tagChange,
	type GraphCommit,
	type RevisionTag,
	type TaggedChange,
} from "../core/index.js";
import {
	jsonableTreeFromFieldCursor,
	intoDelta,
	schemaCodecBuilder,
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
	id: sf.identifier,
	label: sf.string,
	x: sf.number,
}) {}
class Items extends sf.array("Items", [sf.string, Point]) {}
class NamedMap extends sf.map("NamedMap", [sf.string, Point, Items]) {}
class Root extends sf.object("Root", {
	title: sf.string,
	note: sf.optional(sf.string),
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
		note: "seed",
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
		item instanceof Point ? { id: item.id, label: item.label, x: item.x } : item;
	return {
		title: root.title,
		note: root.note ?? null,
		count: root.count,
		left: [...root.left].map(value),
		right: [...root.right].map(value),
		byKey: [...root.byKey]
			.sort(([left], [right]) => left.localeCompare(right))
			.map(([key, item]) => [
				key,
				item instanceof Point
					? { id: item.label, label: item.label, x: item.x }
					: item instanceof Items
						? [...item].map(value)
						: item,
			]),
	};
}

function contentState(tree: TreeInstance, view: TransactionView) {
	const snapshot = Reflect.get(tree, "contentSnapshot") as () => { removed: unknown[] };
	const removed = copy(snapshot.call(tree).removed) as [unknown, unknown, SemanticTreeInput][];
	return {
		visible: visible(view.root),
		identities: [
			...[...view.root.left, ...view.root.right]
				.filter((item): item is Point => item instanceof Point)
				.map((item) => item.id),
			...[...view.root.byKey.values()]
				.filter((item): item is Point => item instanceof Point)
				.map((item) => item.id),
		],
		retainedDetached: removed.map(([revision, localId, value]) => [
			revision,
			localId,
			semanticTree(value),
		]),
	};
}

function compressorState(compressor: IIdCompressor) {
	return {
		sessionId: compressor.localSessionId,
		ongoing: serializeIdCompressor(compressor, true),
		summary: serializeIdCompressor(compressor, false),
	};
}

function checkpoint(tree: TreeInstance, view: TransactionView, compressor: IIdCompressor, id: string) {
	const content = contentState(tree, view);
	const state = compressorState(compressor);
	return {
		id,
		...content,
		compressor: state.summary,
		allocation: {
			sessionId: state.sessionId,
			ongoing: state.ongoing,
		},
		history: managerState(tree, compressor),
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

function treeEnvelopesIn(value: unknown): Record<string, unknown>[] {
	const envelopes: Record<string, unknown>[] = [];
	function visit(item: unknown) {
		if (Array.isArray(item)) {
			for (const child of item) visit(child);
		} else if (item !== null && typeof item === "object") {
			const object = item as Record<string, unknown>;
			if (
				typeof object.sequenceNumber === "number"
				&& object.contents !== null
				&& typeof object.contents === "object"
				&& Reflect.get(object.contents, "version") === 7
			) {
				envelopes.push(copy(object));
				return;
			}
			for (const child of Object.values(object)) visit(child);
		}
	}
	visit(value);
	return envelopes;
}

function allocationRangesIn(value: unknown): IdCreationRange[] {
	const ranges = new Map<string, IdCreationRange>();
	function visit(item: unknown) {
		if (Array.isArray(item)) {
			for (const child of item) visit(child);
		} else if (item !== null && typeof item === "object") {
			const object = item as Record<string, unknown>;
			const contents = object.contents as Record<string, unknown> | undefined;
			if (
				typeof object.sequenceNumber === "number"
				&& contents?.type === "idAllocation"
				&& contents.contents !== null
				&& typeof contents.contents === "object"
			) {
				const range = copy(contents.contents as IdCreationRange);
				ranges.set(JSON.stringify(range), range);
				return;
			}
			for (const child of Object.values(object)) visit(child);
		}
	}
	visit(value);
	return [...ranges.values()];
}

function deliver(tree: TreeInstance, envelope: Record<string, unknown>) {
	const kernel = Reflect.get(tree, "kernel") as {
		processMessagesCore(batch: unknown, local: boolean): void;
	};
	kernel.processMessagesCore(
		{
			envelope: {
				clientId: String(envelope.clientId),
				clientSequenceNumber: Number(envelope.clientSequenceNumber),
				contents: envelope.contents,
				referenceSequenceNumber: Number(envelope.referenceSequenceNumber),
				sequenceNumber: Number(envelope.sequenceNumber),
				minimumSequenceNumber: Number(envelope.minimumSequenceNumber),
				timestamp: 0,
				type: "op",
			},
			messagesContent: [{
				contents: envelope.contents,
				localOpMetadata: undefined,
				clientSequenceNumber: Number(envelope.clientSequenceNumber),
			}],
		},
		false,
	);
}

function decodeMessage(tree: TreeInstance, encoded: unknown, compressor: IIdCompressor) {
	const codec = Reflect.get(tree.kernel, "messageCodec") as {
		decode(value: unknown, context: { idCompressor: IIdCompressor }): unknown;
	};
	return codec.decode(encoded, { idCompressor: compressor });
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

function fieldKind(value: string) {
	return value === "ModularEditBuilder.Generic" ? "Generic" : value;
}

function register(value: unknown, compressor: IIdCompressor) {
	if (value === "self") return "self";
	return atom(value as { revision?: RevisionTag; localId: number }, compressor);
}

function sequenceEffect(value: Record<string, unknown>, compressor: IIdCompressor): object {
	const type = typeof value.type === "string" ? value.type : "Noop";
	const revision = value.revision as RevisionTag | undefined;
	const endpoint = (item: unknown) =>
		item === undefined
			? null
			: atom(item as { revision?: RevisionTag; localId: number }, compressor);
	const id = (item: unknown) =>
		item === undefined
			? null
			: atom({ revision, localId: Number(item) }, compressor);
	if (type === "AttachAndDetach") {
		return {
			type,
			attach: sequenceEffect(value.attach as Record<string, unknown>, compressor),
			detach: sequenceEffect(value.detach as Record<string, unknown>, compressor),
		};
	}
	return {
		type,
		id: id(value.id),
		finalEndpoint: endpoint(value.finalEndpoint),
		idOverride: endpoint(value.idOverride),
	};
}

function fieldOperation(value: { fieldKind: string; change: unknown }, compressor: IIdCompressor) {
	if (value.fieldKind === "ModularEditBuilder.Generic") {
		const changes = value.change as Map<number, { revision?: RevisionTag; localId: number }>;
		return {
			children: [...changes].map(([index, child]) => [index, atom(child, compressor)]),
		};
	}
	if (value.fieldKind === "Value" || value.fieldKind === "Optional") {
		const change = value.change as {
			moves: [{ revision?: RevisionTag; localId: number }, { revision?: RevisionTag; localId: number }][];
			childChanges: [unknown, { revision?: RevisionTag; localId: number }][];
			valueReplace?: {
				isEmpty: boolean;
				src?: unknown;
				dst: { revision?: RevisionTag; localId: number };
			};
		};
		return {
			moves: change.moves.map(([source, target]) => [
				atom(source, compressor),
				atom(target, compressor),
			]),
			children: change.childChanges.map(([source, child]) => [
				register(source, compressor),
				atom(child, compressor),
			]),
			replacement: change.valueReplace === undefined
				? null
				: {
					wasEmpty: change.valueReplace.isEmpty,
					source: change.valueReplace.src === undefined
						? null
						: register(change.valueReplace.src, compressor),
					detach: atom(change.valueReplace.dst, compressor),
				},
		};
	}
	if (value.fieldKind === "Sequence") {
		const marks = value.change as Record<string, unknown>[];
		return {
			marks: marks.map((mark) => ({
				count: Number(mark.count),
				cell: mark.cellId === undefined
					? null
					: atom(mark.cellId as { revision?: RevisionTag; localId: number }, compressor),
				effect: sequenceEffect(mark, compressor),
				child: mark.changes === undefined
					? null
					: atom(mark.changes as { revision?: RevisionTag; localId: number }, compressor),
			})),
		};
	}
	assert.equal(value.fieldKind, "Identifier");
	return {};
}

function fieldChanges(
	value: ModularChangeset["fieldChanges"],
	compressor: IIdCompressor,
) {
	return [...value].map(([field, change]) => ({
		field,
		kind: fieldKind(change.fieldKind),
		operation: fieldOperation(change, compressor),
	}));
}

function nodeChange(value: NodeChangeset, compressor: IIdCompressor) {
	return {
		fields: fieldChanges(value.fieldChanges ?? new Map(), compressor),
		nodeExistsConstraint: value.nodeExistsConstraint ?? null,
		nodeExistsConstraintOnRevert: value.nodeExistsConstraintOnRevert ?? null,
	};
}

type StableAtom = ReturnType<typeof atom>;

function atomKey(value: StableAtom) {
	return `${value.revision ?? ""}:${value.localId}`;
}

function canonicalGraph<T extends {
	maxId: number;
	parents: { id: StableAtom; parent: StableAtom | null; field: string }[];
	aliases: { id: StableAtom; target: StableAtom }[];
}>(value: T): T {
	const aliases = new Map(value.aliases.map(({ id, target }) => [atomKey(id), target]));
	const resolve = (start: StableAtom) => {
		let current = start;
		const seen = new Set<string>();
		while (aliases.has(atomKey(current))) {
			const key = atomKey(current);
			assert(!seen.has(key), "Transaction alias graph must be acyclic.");
			seen.add(key);
			current = aliases.get(key) as StableAtom;
		}
		return current;
	};
	const aliasTargets = new Set<string>();
	const flattenedAliases = value.aliases
		.map(({ id, target }) => ({ id, target: resolve(target) }))
		.filter(({ target }) => {
			const key = atomKey(target);
			if (aliasTargets.has(key)) return false;
			aliasTargets.add(key);
			return true;
		});
	const parents = value.parents.map(({ id, parent, field }) => ({
		id,
		parent: parent === null ? null : resolve(parent),
		field,
	}));
	const parentById = new Map(parents.map((entry) => [atomKey(entry.id), entry]));
	const parentDepth = (id: StableAtom, seen = new Set<string>()): number => {
		const key = atomKey(id);
		assert(!seen.has(key), "Transaction parent graph must be acyclic.");
		const entry = parentById.get(key);
		if (entry?.parent === null || entry === undefined) return 0;
		return 1 + parentDepth(entry.parent, new Set([...seen, key]));
	};
	parents.sort((left, right) =>
		parentDepth(left.id) - parentDepth(right.id)
		|| left.field.localeCompare(right.field)
		|| left.id.localId - right.id.localId);
	const graph = {
		...value,
		parents,
		aliases: flattenedAliases,
	};
	const graphRecord = graph as T & Record<string, unknown>;
	const nodes = graphRecord.nodes;
	if (Array.isArray(nodes)) {
		nodes.sort((left, right) => {
			const leftId = (left as { id: StableAtom }).id;
			const rightId = (right as { id: StableAtom }).id;
			return parentDepth(leftId) - parentDepth(rightId)
				|| leftId.localId - rightId.localId;
		});
	}
	for (const key of ["aliases", "builds", "refreshers", "destroys"]) {
		const entries = graphRecord[key];
		if (Array.isArray(entries)) {
			entries.sort((left, right) => {
				const leftId = (left as { id: StableAtom }).id;
				const rightId = (right as { id: StableAtom }).id;
				return leftId.localId - rightId.localId;
			});
		}
	}
	const ids = new Map<string, StableAtom>();
	let next = 0;
	const canonicalize = (item: unknown): unknown => {
		if (Array.isArray(item)) return item.map(canonicalize);
		if (item === null || typeof item !== "object") return item;
		const object = item as Record<string, unknown>;
		if (
			Object.keys(object).length === 2
			&& Object.hasOwn(object, "revision")
			&& Object.hasOwn(object, "localId")
			&& (object.revision === null || typeof object.revision === "string")
			&& Number.isSafeInteger(object.localId)
		) {
			const stable = object as StableAtom;
			const key = atomKey(stable);
			const existing = ids.get(key);
			if (existing !== undefined) return existing;
			const canonical = { revision: stable.revision, localId: next };
			next += 1;
			ids.set(key, canonical);
			return canonical;
		}
		return Object.fromEntries(
			Object.entries(object)
				.sort(([left], [right]) => left.localeCompare(right))
				.map(([key, child]) => [key, canonicalize(child)]),
		);
	};
	const canonical = canonicalize(graph) as T;
	const canonicalRecord = canonical as T & Record<string, unknown>;
	for (const key of ["aliases", "parents", "nodes", "builds", "refreshers", "destroys"]) {
		const entries = canonicalRecord[key];
		if (Array.isArray(entries)) {
			entries.sort((left, right) => {
				const leftId = (left as { id: StableAtom }).id;
				const rightId = (right as { id: StableAtom }).id;
				return leftId.localId - rightId.localId;
			});
		}
	}
	canonical.maxId = next - 1;
	return canonical;
}

interface SemanticTreeInput {
	type: string;
	value?: unknown;
	fields?: Record<string, SemanticTreeInput[]>;
}

function semanticTree(value: SemanticTreeInput): unknown {
	switch (value.type) {
		case "com.fluidframework.leaf.string":
			return { kind: "string", value: value.value };
		case "com.fluidframework.leaf.number":
			return { kind: "number", value: value.value };
		case "com.fluidframework.leaf.boolean":
			return { kind: "boolean", value: value.value };
		case "com.fluidframework.leaf.null":
			return { kind: "null" };
		default:
			break;
	}
	const fields = value.fields ?? {};
	if (value.type === "org.watershed.shared-tree.transactions.Items") {
		return {
			kind: "array",
			schemaId: value.type,
			elements: (fields[""] ?? []).map(semanticTree),
		};
	}
	if (value.type === "org.watershed.shared-tree.transactions.NamedMap") {
		return {
			kind: "map",
			schemaId: value.type,
			entries: Object.entries(fields)
				.sort(([left], [right]) => left.localeCompare(right))
				.map(([key, children]) => {
					assert.equal(children.length, 1, `Map entry ${key} must contain one tree.`);
					return [key, semanticTree(children[0])];
				}),
		};
	}
	return {
		kind: "object",
		type: value.type,
		fields: Object.entries(fields)
			.sort(([left], [right]) => left.localeCompare(right))
			.map(([field, children]) => {
				assert.equal(children.length, 1, `Object field ${field} must contain one tree.`);
				return [field, semanticTree(children[0])];
			}),
	};
}

function modularChange(value: ModularChangeset, compressor: IIdCompressor) {
	const chunks = (entries: ModularChangeset["builds"]) =>
		[...(entries?.entries() ?? [])].map(([[major, minor], chunk]) => ({
			id: atom({ revision: major, localId: minor }, compressor),
			trees: jsonableTreeFromFieldCursor(chunk.cursor()).map(semanticTree),
		}));
	const deltaAtom = (value: { major?: RevisionTag; minor: number }) =>
		atom({ revision: value.major, localId: value.minor }, compressor);
	const deltaFields = (value: ReturnType<typeof intoDelta>["fields"]): object[] =>
		[...(value ?? [])].map(([field, change]) => ({
			field,
			marks: change.marks.map((mark) => ({
				count: mark.count,
				attach: mark.attach === undefined ? null : deltaAtom(mark.attach),
				detach: mark.detach === undefined ? null : deltaAtom(mark.detach),
				fields: deltaFields(mark.fields),
			})),
		}));
	const delta = intoDelta(tagChange(value, undefined));
	return canonicalGraph({
		maxId: value.maxId ?? -1,
		revisions: (value.revisions ?? []).map((info) => ({
			revision: revision(info.revision, compressor),
			rollbackOf: revision(info.rollbackOf, compressor),
		})),
		fields: fieldChanges(value.fieldChanges, compressor),
		nodes: [...value.nodeChanges.entries()].map(([[major, minor], change]) => ({
			id: atom({ revision: major, localId: minor }, compressor),
			change: nodeChange(change, compressor),
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
		destroys: [...(value.destroys?.entries() ?? [])].map(([[major, minor], count]) => ({
			id: atom({ revision: major, localId: minor }, compressor),
			count,
		})),
		refreshers: chunks(value.refreshers),
		constraintViolationCount: value.constraintViolationCount ?? 0,
		delta: {
			fields: deltaFields(delta.fields),
			builds: (delta.build ?? []).map((build) => ({
				id: deltaAtom(build.id),
				trees: jsonableTreeFromFieldCursor(build.trees.cursor()).map(semanticTree),
			})),
			refreshers: (delta.refreshers ?? []).map((build) => ({
				id: deltaAtom(build.id),
				trees: jsonableTreeFromFieldCursor(build.trees.cursor()).map(semanticTree),
			})),
			global: (delta.global ?? []).map((change) => ({
				id: deltaAtom(change.id),
				fields: deltaFields(change.fields),
			})),
			renames: (delta.rename ?? []).map((rename) => ({
				old: deltaAtom(rename.oldId),
				new: deltaAtom(rename.newId),
				count: rename.count,
			})),
			destroys: (delta.destroy ?? []).map((destroy) => ({
				id: deltaAtom(destroy.id),
				count: destroy.count,
			})),
		},
	});
}

type NormalizedSharedChange =
	| { type: "data"; change: ReturnType<typeof modularChange> }
	| { type: "schema"; change: unknown };

const schemaCodec = schemaCodecBuilder.build({
	jsonValidator: FormatValidatorNoOp,
	minVersionForCollab: FluidClientVersion.v2_117,
});

function sharedChange(
	value: SharedTreeChange,
	compressor: IIdCompressor,
): NormalizedSharedChange[] {
	return value.changes.map((change) => ({
		type: change.type,
		change: change.type === "data"
			? modularChange(change.innerChange, compressor)
			: {
				schema: {
					old: schemaCodec.encode(change.innerChange.schema.old),
					new: schemaCodec.encode(change.innerChange.schema.new),
				},
				isInverse: change.innerChange.isInverse,
			},
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
	run: (view: TransactionView, reads: object[]) => object | void,
) {
	const provider = new TestTreeProviderLite(2, treeFactory());
	const processed = interceptProcessed(provider);
	const view = provider.trees[0].viewWith(new TreeViewConfiguration({ schema: Root }));
	view.initialize(initialRoot());
	provider.synchronizeMessages();
	const beforeMessages = processed.length;
	const compressor = provider.getCompressor(provider.trees[0]);
	const before = checkpoint(provider.trees[0], view, compressor, "before");
	const reads: object[] = [];
	const events = captureEvents(view);
	const outcome = run(view, reads);
	const pending = managerState(provider.trees[0], provider.getCompressor(provider.trees[0]));
	const after = checkpoint(provider.trees[0], view, compressor, "after");
	provider.synchronizeMessages();
	const result = {
		id,
		reads,
		events: events.events,
		commitCount: events.commits,
		pendingCommitCount: pending.pending.length,
		submittedMessages: messagesIn(processed.slice(beforeMessages)),
		final: visible(view.root),
		identity: {
			nodes: after.identities,
			before: before.identities,
			preserved: before.identities.filter((identity) => after.identities.includes(identity)),
		},
		allocation: {
			before: before.allocation,
			after: after.allocation,
		},
		compressor: after.compressor,
		retainedDetached: after.retainedDetached,
		history: after.history,
		depth: transactionDepth(view),
		...(outcome ?? {}),
		...(id === "invalid-edit-rollback"
			? {
				state: {
					before: { ...before, id: undefined },
					after: { ...after, id: undefined },
				},
			}
			: {}),
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
				reads.push({ step: "object-set", value: visible(view.root) });
				view.root.note = undefined;
				reads.push({ step: "object-delete", value: visible(view.root) });
				view.root.byKey.set("added", "map");
				reads.push({ step: "map-set", value: visible(view.root) });
				view.root.byKey.delete("seed");
				reads.push({ step: "map-delete", value: visible(view.root) });
				view.root.left.insertAtEnd("inserted");
				reads.push({ step: "array-insert", value: visible(view.root) });
				view.root.left.removeAt(view.root.left.length - 1);
				reads.push({ step: "array-remove", value: visible(view.root) });
				view.root.left.removeAt(1);
				view.root.left.insertAt(1, new Point({ label: "replacement", x: 4 }));
				reads.push({ step: "array-replace", value: visible(view.root) });
				view.root.left.moveToEnd(0);
				reads.push({ step: "same-array-move", value: visible(view.root) });
				view.root.right.moveRangeToEnd(1, 2, view.root.left);
				reads.push({ step: "cross-array-move", value: visible(view.root) });
			});
		}),
		await callbackScenario("outer-rollback", (view, reads) => {
			const before = visible(view.root);
			const result = Tree.runTransaction(view, () => {
				view.root.title = "rolled-back";
				view.root.left.insertAtEnd(new Point({ label: "temporary", x: 99 }));
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
		if (
			scenario.id === "outer-rollback"
			|| scenario.id === "no-op"
		) {
			assert.equal(scenario.pendingCommitCount, 0, `${scenario.id}: pending commits`);
			assert.equal(scenario.submittedMessages.length, 0, `${scenario.id}: messages`);
			assert.equal(scenario.commitCount, 0, `${scenario.id}: commits`);
			assert.equal(scenario.events.length, 0, `${scenario.id}: events`);
			assert.deepEqual(
				scenario.identity.nodes,
				scenario.identity.before,
				`${scenario.id}: identity state`,
			);
			assert.equal(scenario.retainedDetached.length, 0, `${scenario.id}: detached content`);
			if (scenario.id === "no-op") {
				assert.deepEqual(
					scenario.allocation.after,
					scenario.allocation.before,
					`${scenario.id}: allocation state`,
				);
			}
		} else {
			assert.equal(scenario.pendingCommitCount, 1, `${scenario.id}: pending commits`);
			assert.equal(scenario.commitCount, 1, `${scenario.id}: commit count`);
			assert.equal(scenario.submittedMessages.length, 1, `${scenario.id}: messages`);
		}
	}
	return caseFile(
		"transaction-callbacks",
		"tree",
		{
			scenarios: scenarios.map(({ id }) => ({
				id,
				api: "Tree.runTransaction",
				...(id === "success-all-fields"
					? {
						operations: [
							"object-set", "object-delete", "map-set", "map-delete",
							"array-insert", "array-remove", "array-replace",
							"same-array-move", "cross-array-move",
						],
					}
					: {}),
			})),
		},
		scenarios,
		{ scenarios, messages: scenarios.flatMap(({ submittedMessages }) => submittedMessages) },
	);
}

async function captureInvalidEditCallback() {
	const scenario = await callbackScenario("invalid-edit-rollback", (view, reads) => {
		let error = "";
		const result = Tree.runTransaction(view, () => {
			view.root.title = "before-invalid";
			reads.push({ step: "valid-edit-before-invalid", value: visible(view.root) });
			try {
				view.root.left.removeAt(-1);
			} catch (caught) {
				error = String(caught);
				return Tree.runTransaction.rollback;
			}
		});
		assert.match(error, /Expected non-negative index passed to TreeArrayNode\.removeAt/);
		assert.equal(result, Tree.runTransaction.rollback);
		return { error, nativeFailure: true, transactionResult: "rollback" };
	});
	assert.equal(scenario.pendingCommitCount, 0);
	assert.equal(scenario.submittedMessages.length, 0);
	assert.equal(scenario.commitCount, 0);
	assert.equal(scenario.events.length, 0);
	assert.deepEqual(scenario.identity.nodes, scenario.identity.before);
	assert.equal(scenario.retainedDetached.length, 0);
	assert(scenario.state !== undefined);
	assert.deepEqual(scenario.state.after.visible, scenario.state.before.visible);
	assert.deepEqual(scenario.state.after.identities, scenario.state.before.identities);
	assert.deepEqual(scenario.state.after.retainedDetached, scenario.state.before.retainedDetached);
	assert.deepEqual(scenario.state.after.history, scenario.state.before.history);
	assert.equal(scenario.state.after.compressor, scenario.state.before.compressor);
	assert.equal(scenario.allocation.after.sessionId, scenario.allocation.before.sessionId);
	assert.notEqual(scenario.allocation.after.ongoing, scenario.allocation.before.ongoing);
	return { ...scenario, localCompressorAdvanced: true };
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
		identityPreserved: moveView.root.left.at(-1) === target,
		identity: target.id,
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
		identityPreserved: moveView.root.right.at(-1) === target,
		identity: target.id,
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
	const writerFinal = visible(view.root);
	const peerFinal = visible(peer.root);
	assert.deepEqual(writerFinal, peerFinal, "Violated transactions must converge.");
	assert.equal(
		JSON.stringify(writerFinal).includes("suppressed"),
		false,
		"Violated field effects must be suppressed on every client.",
	);
	const observation = {
		id: "node-in-document",
		refusal: { callbackRan, error: refusal },
		withinMove,
		crossMove,
		pending,
		settled,
		final: writerFinal,
		clients: { writer: writerFinal, peer: peerFinal },
		converged: true,
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
				rebase(
					change: TaggedChange<SharedTreeChange>,
					over: TaggedChange<SharedTreeChange>,
					metadata: ReturnType<typeof revisionMetadataSourceFromInfo>,
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
	provider.synchronizeMessages();
	const messages = messagesIn(processed.slice(start));
	assert.equal(messages.length, 1);

	const violatedProvider = new TestTreeProviderLite(2, treeFactory());
	const violatedProcessed = interceptProcessed(violatedProvider);
	const violatedView = violatedProvider.trees[0].viewWith(
		new TreeViewConfiguration({ schema: Root }),
	);
	violatedView.initialize(initialRoot());
	violatedProvider.synchronizeMessages();
	const violatedPeer = violatedProvider.trees[1].viewWith(
		new TreeViewConfiguration({ schema: Root }),
	);
	const violatedTarget = violatedView.root.left[0];
	assert(violatedTarget instanceof Point);
	violatedProvider.trees[0].containerRuntime.connected = false;
	const violatedStart = violatedProcessed.length;
	Tree.runTransaction(
		violatedView,
		() => {
			violatedTarget.label = "violated-wire";
			violatedView.root.right.insertAtEnd(
				new Point({ label: "violated-created", x: 20 }),
			);
		},
		[
			{ type: "nodeInDocument", node: violatedTarget },
			{ type: "nodeInDocument", node: violatedTarget },
		],
	);
	const violatedManager = Reflect.get(violatedProvider.trees[0].kernel, "editManager") as {
		getLocalCommits(branch: string): Commit[];
		getTrunkCommits(branch: string): Commit[];
	};
	const original = violatedManager.getLocalCommits("main")[0];
	assert(original !== undefined);
	violatedPeer.root.left.removeAt(0);
	violatedProvider.synchronizeMessages();
	violatedProvider.trees[0].containerRuntime.connected = true;
	violatedProvider.synchronizeMessages();
	const violatedCompressor = violatedProvider.getCompressor(violatedProvider.trees[0]);
	const trunk = violatedManager.getTrunkCommits("main");
	const violatedCommit = trunk.find((commit) =>
		sharedChange(commit.change, violatedCompressor).some((change) =>
			change.type === "data" && change.change.constraintViolationCount === 1));
	assert(violatedCommit !== undefined, "Expected a violated wire commit.");
	const over = trunk.find((commit) =>
		commit.revision !== violatedCommit.revision
		&& commit.revision !== original.revision
		&& sharedChange(commit.change, violatedCompressor).some((change) => change.type === "data"));
	assert(over !== undefined, "Expected the concurrent removal commit.");
	const violatedCheckout = Reflect.get(violatedView, "checkout") as typeof checkout;
	const violatedMessages = messagesIn(violatedProcessed.slice(violatedStart))
		.filter((message) =>
			message.originatorId === violatedCompressor.localSessionId);
	assert.equal(violatedMessages.length, 1);
	const overMessages = [
		...new Map(
			messagesIn(violatedProcessed.slice(violatedStart))
				.filter((message) =>
					message.originatorId !== violatedCompressor.localSessionId)
				.map((message) => [JSON.stringify(message), message]),
		).values(),
	];
	assert.equal(overMessages.length, 1);
	const nonviolatedReplaySession = createSessionId();
	const nonviolatedReplayCompressor = deserializeIdCompressor(
		serializeIdCompressor(compressor, false),
		nonviolatedReplaySession,
	);
	const decodedNonviolated = decodeMessage(
		provider.trees[0],
		messages[0],
		nonviolatedReplayCompressor,
	) as { commit: Commit };
	const inverseRevision = nonviolatedReplayCompressor.generateCompressedId() as RevisionTag;
	const decodedTagged = tagChange(
		decodedNonviolated.commit.change,
		decodedNonviolated.commit.revision,
	);
	const composed = checkout.changeFamily.rebaser.compose([decodedTagged, decodedTagged]);
	const inverted = checkout.changeFamily.rebaser.invert(
		decodedTagged,
		false,
		inverseRevision,
	);
	const violatedReplayCompressor = deserializeIdCompressor(
		serializeIdCompressor(violatedCompressor, false),
		createSessionId(),
	);
	const decodedViolated = decodeMessage(
		violatedProvider.trees[0],
		violatedMessages[0],
		violatedReplayCompressor,
	) as { commit: Commit };
	const decodedOver = decodeMessage(
		violatedProvider.trees[0],
		overMessages[0],
		violatedReplayCompressor,
	) as { commit: Commit };
	const revisionMetadata = [
		{ revision: decodedViolated.commit.revision },
		{ revision: decodedOver.commit.revision },
	];
	const rebased = violatedCheckout.changeFamily.rebaser.rebase(
		tagChange(decodedViolated.commit.change, decodedViolated.commit.revision),
		tagChange(decodedOver.commit.change, decodedOver.commit.revision),
		revisionMetadataSourceFromInfo(revisionMetadata),
	);
	const nonviolatedResult = sharedChange(
		decodedNonviolated.commit.change,
		nonviolatedReplayCompressor,
	);
	const violatedResult = sharedChange(
		decodedViolated.commit.change,
		violatedReplayCompressor,
	);
	const rebasedResult = sharedChange(rebased, violatedReplayCompressor);
	const nonviolatedOperand = {
		revision: revision(
			decodedNonviolated.commit.revision,
			nonviolatedReplayCompressor,
		),
		changes: nonviolatedResult,
	};
	const rebaseOperands = {
		change: {
			revision: revision(decodedViolated.commit.revision, violatedReplayCompressor),
			changes: sharedChange(decodedViolated.commit.change, violatedReplayCompressor),
		},
		over: {
			revision: revision(decodedOver.commit.revision, violatedReplayCompressor),
			changes: sharedChange(decodedOver.commit.change, violatedReplayCompressor),
		},
	};
	const observation = {
		id: "modular-v5-shared-tree-v5",
		message: messages[0],
		messageBytes: JSON.stringify(messages[0]),
		pending,
		nonviolated: {
			revision: nonviolatedOperand.revision,
			changes: nonviolatedResult,
		},
		violated: {
			revision: revision(decodedViolated.commit.revision, violatedReplayCompressor),
			changes: violatedResult,
		},
		composed: sharedChange(composed, nonviolatedReplayCompressor),
		inverted: sharedChange(inverted, nonviolatedReplayCompressor),
		rebased: { changes: rebasedResult },
	};
	const inverseData = observation.inverted.find((change) => change.type === "data");
	assert(inverseData !== undefined);
	assert(inverseData.change.nodes.some((node) =>
		node.change.nodeExistsConstraintOnRevert !== null));
	return caseFile(
		"transaction-wire",
		"codec",
		{
			messageBytes: {
				nonviolated: JSON.stringify(messages[0]),
				violated: JSON.stringify(violatedMessages[0]),
				over: JSON.stringify(overMessages[0]),
			},
			compressor: {
				nonviolated: {
					serialized: serializeIdCompressor(compressor, false),
					sessionId: nonviolatedReplaySession,
				},
				violated: {
					serialized: serializeIdCompressor(violatedCompressor, false),
					sessionId: violatedReplayCompressor.localSessionId,
				},
				over: {
					serialized: serializeIdCompressor(violatedCompressor, false),
					sessionId: violatedReplayCompressor.localSessionId,
				},
			},
			context: {
				message: 7,
				sharedTreeChange: 5,
				modularChange: 5,
				minVersionForCollab: "2.117.0",
			},
			operands: {
				nonviolated: {
					revision: observation.nonviolated.revision,
					changeset: messages[0].changeset,
				},
				violated: {
					revision: observation.violated.revision,
					changeset: violatedMessages[0].changeset,
				},
				compose: {
					changes: [
						{
							revision: observation.nonviolated.revision,
							changeset: messages[0].changeset,
						},
						{
							revision: observation.nonviolated.revision,
							changeset: messages[0].changeset,
						},
					],
				},
				invert: {
					change: {
						revision: observation.nonviolated.revision,
						changeset: messages[0].changeset,
					},
					inverseRevision: revision(inverseRevision, nonviolatedReplayCompressor),
					isRollback: false,
				},
				rebase: {
					change: {
						revision: rebaseOperands.change.revision,
						changeset: violatedMessages[0].changeset,
						decoded: rebaseOperands.change.changes,
					},
					over: {
						revision: rebaseOperands.over.revision,
						changeset: overMessages[0].changeset,
						decoded: rebaseOperands.over.changes,
					},
					revisionMetadata: revisionMetadata.map(({ revision: tag }) => ({
						revision: revision(tag, violatedReplayCompressor),
						rollbackOf: null,
					})),
				},
			},
			scenarios: [{
				id: "modular-v5-shared-tree-v5",
				duplicates: 2,
				nestedPath: ["left", "0"],
				includesBuild: true,
				includesRevisionInfo: true,
			}],
		},
		[observation],
		{
			messages: [...messages, ...violatedMessages],
			messageBytes: {
				nonviolated: observation.messageBytes,
				violated: JSON.stringify(violatedMessages[0]),
			},
			algebra: {
				nonviolatedOperand,
				composed: sharedChange(composed, nonviolatedReplayCompressor),
				inverted: sharedChange(inverted, nonviolatedReplayCompressor),
				rebaseOperands,
				rebased: rebasedResult,
			},
		},
	);
}

async function captureHistory() {
	const provider = new TestTreeProviderLite(2, treeFactory());
	const processed = interceptProcessed(provider);
	const view = provider.trees[0].viewWith(new TreeViewConfiguration({ schema: Root }));
	view.initialize(initialRoot());
	provider.synchronizeMessages();
	const peer = provider.trees[1].viewWith(new TreeViewConfiguration({ schema: Root }));
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
	const authorCompressor = provider.getCompressor(provider.trees[0]);
	const pending = checkpoint(provider.trees[0], view, authorCompressor, "pending");
	peer.root.left.removeAt(0);
	provider.synchronizeMessages();
	const pendingSummary = (await provider.trees[1].summarize(true)).summary;
	const peerCompressor = provider.getCompressor(provider.trees[1]);
	const pendingCompressor = compressorState(peerCompressor);
	const summaryState = checkpoint(
		provider.trees[1],
		peer,
		peerCompressor,
		"sequenced-summary",
	);
	assert.equal(
		JSON.stringify(summaryState.visible).includes("pending"),
		false,
		"Sequenced summary state must exclude pending local work.",
	);
	provider.trees[0].containerRuntime.connected = true;
	provider.synchronizeMessages();
	const acknowledged = checkpoint(
		provider.trees[0],
		view,
		authorCompressor,
		"acknowledged-violation",
	);
	const reconnectMessages = messagesIn(processed.slice(start))
		.filter((message) => message.originatorId === authorCompressor.localSessionId);
	const tailEnvelope = treeEnvelopesIn(processed.slice(start)).find((envelope) =>
		messagesIn(envelope).some((message) =>
			message.originatorId === authorCompressor.localSessionId));
	assert(tailEnvelope !== undefined, "Expected the captured tail envelope.");
	assert.equal(pending.history.pending.length, 1);
	assert.equal(acknowledged.history.pending.length, 0);
	assert.equal(reconnectMessages.length, 1);
	const violated = acknowledged.history.trunk.find((commit) =>
		commit.changes.some((change) =>
			change.type === "data" && change.change.constraintViolationCount === 1));
	assert(violated !== undefined, "Pending rebase must record an explicit violation.");
	const tailAllocationRanges = allocationRangesIn(processed.slice(start))
		.filter((range) => Reflect.get(range, "sessionId") === authorCompressor.localSessionId);
	assert(tailAllocationRanges.length > 0, "Expected tail ID allocation ranges.");
	const factory = treeFactory();
	const missingRangeRuntime = new MockFluidDataStoreRuntime({
		idCompressor: deserializeIdCompressor(pendingCompressor.summary, createSessionId()),
	});
	const missingRangeTree = await factory.load(
		missingRangeRuntime,
		"watershed-transaction-history-missing-range",
		MockSharedObjectServices.createFromSummary(pendingSummary),
		factory.attributes,
	);
	let missingTailAllocationError = "";
	try {
		deliver(missingRangeTree as TreeInstance, tailEnvelope);
	} catch (error) {
		missingTailAllocationError = String(error);
	}
	assert.notEqual(
		missingTailAllocationError,
		"",
		"Tail replay without captured allocation ranges must fail.",
	);

	const readerSession = createSessionId();
	const readerRuntime = new MockFluidDataStoreRuntime({
		idCompressor: deserializeIdCompressor(pendingCompressor.summary, readerSession),
	});
	assert(readerRuntime.idCompressor !== undefined);
	for (const range of tailAllocationRanges) {
		toIdCompressorWithCore(readerRuntime.idCompressor).finalizeCreationRange(range);
	}
	const continuationSubmitted: unknown[] = [];
	const readerServices = MockSharedObjectServices.createFromSummary(pendingSummary);
	readerServices.deltaConnection = new MockDeltaConnection(
		(message) => {
			continuationSubmitted.push(copy(message));
			return Number(tailEnvelope.sequenceNumber) + 1;
		},
		() => {},
	);
	const readerTree = await factory.load(
		readerRuntime,
		"watershed-transaction-history-reader",
		readerServices,
		factory.attributes,
	);
	const readerView = readerTree.viewWith(new TreeViewConfiguration({ schema: Root }));
	const loaded = checkpoint(
		readerTree as TreeInstance,
		readerView,
		readerRuntime.idCompressor,
		"loaded-summary",
	);
	assert.deepEqual(loaded.visible, summaryState.visible);
	deliver(readerTree as TreeInstance, tailEnvelope);
	const afterTail = checkpoint(
		readerTree as TreeInstance,
		readerView,
		readerRuntime.idCompressor,
		"after-tail",
	);
	assert.deepEqual(afterTail.visible, acknowledged.visible);
	assert.deepEqual(afterTail.identities, acknowledged.identities);

	Tree.runTransaction(readerView, () => {
		readerView.root.right.insertAtEnd(
			new Point({ label: "reader-continuation", x: 12 }),
		);
	});
	const afterContinuation = checkpoint(
		readerTree as TreeInstance,
		readerView,
		readerRuntime.idCompressor,
		"after-continuation",
	);
	const continuationMessages = messagesIn(continuationSubmitted);
	assert.equal(continuationMessages.length, 1);
	const continuationRange = toIdCompressorWithCore(
		readerRuntime.idCompressor,
	).takeNextCreationRange();
	const continuationEnvelope = {
		clientId: readerRuntime.idCompressor.localSessionId,
		clientSequenceNumber: 1,
		referenceSequenceNumber: Number(tailEnvelope.sequenceNumber),
		sequenceNumber: Number(tailEnvelope.sequenceNumber) + 1,
		minimumSequenceNumber: Number(tailEnvelope.minimumSequenceNumber),
		contents: continuationMessages[0],
	};

	const peerSession = createSessionId();
	const loadedPeerRuntime = new MockFluidDataStoreRuntime({
		idCompressor: deserializeIdCompressor(pendingCompressor.summary, peerSession),
	});
	assert(loadedPeerRuntime.idCompressor !== undefined);
	for (const range of tailAllocationRanges) {
		toIdCompressorWithCore(loadedPeerRuntime.idCompressor).finalizeCreationRange(range);
	}
	toIdCompressorWithCore(loadedPeerRuntime.idCompressor).finalizeCreationRange(continuationRange);
	const loadedPeerTree = await factory.load(
		loadedPeerRuntime,
		"watershed-transaction-history-peer",
		MockSharedObjectServices.createFromSummary(pendingSummary),
		factory.attributes,
	);
	const loadedPeerView = loadedPeerTree.viewWith(new TreeViewConfiguration({ schema: Root }));
	deliver(loadedPeerTree as TreeInstance, tailEnvelope);
	deliver(loadedPeerTree as TreeInstance, continuationEnvelope);
	const peerAfterContinuation = checkpoint(
		loadedPeerTree as TreeInstance,
		loadedPeerView,
		loadedPeerRuntime.idCompressor,
		"peer-after-continuation",
	);
	assert.deepEqual(peerAfterContinuation.visible, afterContinuation.visible);
	assert.deepEqual(peerAfterContinuation.identities, afterContinuation.identities);

	const checkpoints = [
		pending,
		summaryState,
		acknowledged,
		loaded,
		afterTail,
		afterContinuation,
		peerAfterContinuation,
	];
	const observation = {
		id: "reconnect-summary-history",
		pending,
		pendingViolation: violated,
		pendingSummary,
		pendingCompressor: pendingCompressor.summary,
		missingTailAllocationError,
		reconnectMessages,
		acknowledged,
		loaded,
		afterTail,
		afterContinuation,
		peer: peerAfterContinuation,
		checkpoints,
		final: acknowledged.visible,
	};
	return caseFile(
		"transaction-history",
		"history",
		{
			summary: pendingSummary,
			compressor: {
				serialized: pendingCompressor.summary,
				sessionId: readerSession,
			},
			tailEnvelope,
			tailAllocationRanges,
			continuation: {
				edits: [{
					op: "array-insert",
					path: ["right"],
					values: [{ label: "reader-continuation", x: 12 }],
				}],
				envelope: continuationEnvelope,
				creationRange: copy(continuationRange),
				peerSessionId: peerSession,
			},
			scenarios: [{
				id: "reconnect-summary-history",
				actions: [
					{ op: "disconnect" },
					{ op: "transaction", edits: 2, constraints: 1 },
					{ op: "summary" },
					{ op: "reconnect" },
					{ op: "acknowledge" },
					{ op: "load-summary" },
					{ op: "apply-tail" },
					{ op: "continue" },
					{ op: "peer-observe" },
				],
			}],
		},
		[observation],
		{
			messages: [...reconnectMessages, ...continuationMessages],
			resubmittedMessage: reconnectMessages[0],
			nativeContinuation: continuationMessages[0],
			summary: pendingSummary,
			tailEnvelope,
			tailAllocationRanges,
			continuationEnvelope,
			observation,
		},
	);
}

describe("Watershed transaction oracle", () => {
	it("captures the pinned transaction contract", async () => {
		const output = process.env.WATERSHED_ORACLE_OUTPUT;
		assert(output !== undefined && isAbsolute(output), "WATERSHED_ORACLE_OUTPUT must be absolute");
		assert.equal(process.env.WATERSHED_ORACLE_COMMIT, reference.commit);
		mkdirSync(output, { recursive: true });
		const callbacks = await captureCallbacks();
		const cases = [callbacks, await captureConstraints(), await captureWire(), await captureHistory()];
		const invalid = await captureInvalidEditCallback();
		const callbackInput = callbacks.input as { scenarios: object[] };
		const callbackRaw = callbacks.raw as { scenarios: object[] };
		callbackInput.scenarios.push({
			id: invalid.id,
			api: "Tree.runTransaction",
			operation: "array-remove-negative-index",
		});
		callbacks.expected.observations = [...callbacks.expected.observations, invalid];
		callbackRaw.scenarios = [...callbackRaw.scenarios, invalid];
		writeFileSync(
			join(output, "transaction-cases.json"),
			`${JSON.stringify(cases, undefined, 2)}\n`,
			"utf8",
		);
	});
});
