/*!
 * Copyright (c) Microsoft Corporation and contributors. All rights reserved.
 * Licensed under the MIT License.
 */

import { strict as assert } from "node:assert";
import { mkdirSync, writeFileSync } from "node:fs";
import { isAbsolute, join } from "node:path";

import type {
	IIdCompressor,
	SessionId,
} from "@fluidframework/id-compressor";
import {
	createIdCompressor,
	toIdCompressorWithCore,
} from "@fluidframework/id-compressor/internal";

import { FormatValidatorNoOp } from "../codec/index.js";
import {
	CommitKind,
	type DeltaDetachedNodeId,
	findCommonAncestor,
	rootFieldKey,
	tagChange,
	type FieldUpPath,
	type GraphCommit,
	type RevisionTag,
	type TaggedChange,
	type UpPath,
} from "../core/index.js";
import {
	DefaultEditBuilder,
	intoDelta,
	relevantRemovedRoots,
	schemaCodecBuilder,
	updateRefreshers,
	type ModularChangeset,
} from "../feature-libraries/index.js";
import { EditManager, minimumPossibleSequenceNumber } from "../shared-tree-core/index.js";
import { SchemaFactory } from "../simple-tree/index.js";
import { brand } from "../util/index.js";
import { assertIsSessionId } from "./utils.js";
import { makeModularFamily } from "./watershedAlgebra.spec.js";
import {
	root,
	runScenario,
	schemaString,
	treeChunk,
	type Atom,
	type Scenario,
	type TaggedValue,
} from "./watershedForest.spec.js";
import {
	deltaDataWithCompressor,
	detachedWithCompressor,
	structureWithCompressor,
} from "./watershedModular.spec.js";

const formatVersion = 1;
const packageName = "@fluidframework/tree";
const packageVersion = "3.1.0";
const expectedCommit = "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960";
const pointType = "org.watershed.shared-tree.m1.Point";

type Authored = {
	readonly revision: RevisionTag;
	readonly originator: SessionId;
	readonly change: ModularChangeset;
};

type SequenceId = {
	readonly sequenceNumber: number;
	readonly indexInBatch?: number;
};

type InternalBranch = {
	readonly commitMetadata: Map<
		RevisionTag,
		{ readonly sequenceId: SequenceId; readonly sessionId: SessionId }
	>;
	readonly sequenceIdToCommit: {
		entries(): IterableIterator<[SequenceId, GraphCommit<ModularChangeset>]>;
	};
	getCommitSequenceId(revision: RevisionTag): SequenceId;
	getPeerBranchOrTrunk(sessionId: SessionId): {
		getHead(): GraphCommit<ModularChangeset>;
	};
};

type InternalManager = {
	readonly trunkBase: GraphCommit<ModularChangeset>;
	readonly minimumSequenceNumber: number;
	readonly sharedBranches: Map<string, InternalBranch>;
};

type Allocation = {
	readonly revision: string;
	readonly identityOrder: { readonly stable: string; readonly encoded: number }[];
};

type HistoryAction = {
	readonly id: string;
	readonly op: string;
	readonly [key: string]: unknown;
};

function taggedString(value: string): TaggedValue {
	return { kind: "string", value };
}

function taggedNumber(value: number): TaggedValue {
	return { kind: "number", value };
}

function taggedBoolean(value: boolean): TaggedValue {
	return { kind: "boolean", value };
}

function point(x: number, y: number): TaggedValue {
	return {
		kind: "object",
		type: pointType,
		fields: [
			["x", taggedNumber(x)],
			["y", taggedNumber(y)],
		],
	};
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

function stable(compressor: IIdCompressor, revision: RevisionTag): string {
	assert(typeof revision === "number", "The history profile requires compressed revisions");
	return compressor.decompress(revision);
}

function session(value: string): SessionId {
	return assertIsSessionId(value);
}

function commitInput(name: string, change: Authored, compressor: IIdCompressor) {
	return {
		change: name,
		revision: stable(compressor, change.revision),
		originator: change.originator,
	};
}

export function captureHistoryEvidence(output: string): void {
	assert(isAbsolute(output), "An absolute output directory is required");
	assert.equal(process.env.WATERSHED_ORACLE_COMMIT, expectedCommit);

	const sessions = {
		local: session("10000000-0000-4000-8000-000000000001"),
		peerA: session("20000000-0000-4000-8000-000000000002"),
		peerB: session("30000000-0000-4000-8000-000000000003"),
		restored: session("40000000-0000-4000-8000-000000000004"),
	};
	const compressor = toIdCompressorWithCore(createIdCompressor(sessions.local));
	const producers = new Map<SessionId, ReturnType<typeof toIdCompressorWithCore>>();
	const known = new Map<string, RevisionTag>();

	function producer(originator: SessionId) {
		let value = producers.get(originator);
		if (value === undefined) {
			value = toIdCompressorWithCore(createIdCompressor(originator));
			producers.set(originator, value);
		}
		return value;
	}

	function remember(revision: RevisionTag): RevisionTag {
		known.set(stable(compressor, revision), revision);
		return revision;
	}

	function authoredRevision(originator: SessionId): RevisionTag {
		if (originator === sessions.local) {
			return remember(compressor.generateCompressedId());
		}
		const source = producer(originator);
		const local = source.generateCompressedId();
		compressor.finalizeCreationRange(source.takeNextCreationRange());
		return remember(compressor.recompress(source.decompress(local)));
	}

	function identityOrder() {
		return [...known].map(([stableId, revision]) => ({
			stable: stableId,
			encoded: Number(revision),
		}));
	}

	const { family, codecOptions } = makeModularFamily();
	const sf = new SchemaFactory("org.watershed.shared-tree.m1");
	class Point extends sf.object("Point", { x: sf.number, y: sf.number }) {}
	class Root extends sf.object("Root", {
		title: sf.string,
		enabled: sf.boolean,
		rating: sf.number,
		marker: sf.null,
		note: sf.optional(sf.string),
		point: Point,
	}) {}
	const schema = schemaString(Root);
	const decoder = schemaCodecBuilder.buildDecoder({ jsonValidator: FormatValidatorNoOp });
	const changes = new Map<string, Authored>();

	function author(
		name: string,
		originator: SessionId,
		path: string[],
		value: TaggedValue | null,
		options: { readonly optional?: boolean; readonly wasEmpty?: boolean } = {},
	): Authored {
		assert(!changes.has(name), `Repeated authored change: ${name}`);
		const revision = authoredRevision(originator);
		let authored: TaggedChange<ModularChangeset> | undefined;
		const editor = new DefaultEditBuilder(family, () => revision, (change) => {
			assert.equal(authored, undefined, "An edit must emit one change");
			authored = change;
		}, codecOptions);
		const chunk = value === null ? undefined : treeChunk([value], compressor);
		if (options.optional === true) {
			editor.optionalField(fieldPath(path)).set(chunk, options.wasEmpty ?? false);
		} else {
			assert(chunk !== undefined, "A required field needs a value");
			editor.valueField(fieldPath(path)).set(chunk);
		}
		assert(authored !== undefined, "The edit did not emit a change");
		const result = { revision, originator, change: authored.change };
		changes.set(name, result);
		return result;
	}

	author("local-title-a", sessions.local, ["title"], taggedString("local-a"));
	author("local-title-b", sessions.local, ["title"], taggedString("local-b"));
	author("local-enabled", sessions.local, ["enabled"], taggedBoolean(false));
	author("local-rating", sessions.local, ["rating"], taggedNumber(7));
	author("local-parent", sessions.local, ["point"], point(10, 20));
	author("local-child-x", sessions.local, ["point", "x"], taggedNumber(42));
	author("local-child-y", sessions.local, ["point", "y"], taggedNumber(9));
	author("local-note", sessions.local, ["note"], taggedString("local-note"), {
		optional: true,
		wasEmpty: true,
	});
	author("accepted-a", sessions.local, ["title"], taggedString("accepted-a"));
	author("pending-b", sessions.local, ["enabled"], taggedBoolean(false));
	author("never-c", sessions.local, ["rating"], taggedNumber(11));

	const nonlexicalPeerB = author(
		"nonlexical-peer-b",
		sessions.peerB,
		["title"],
		taggedString("peer-b"),
	);
	author("remote-title-b", sessions.peerB, ["title"], taggedString("remote-b"));
	author("remote-rating-b", sessions.peerB, ["rating"], taggedNumber(13));
	const nonlexicalPeerA = author(
		"nonlexical-peer-a",
		sessions.peerA,
		["title"],
		taggedString("peer-a"),
	);
	author("remote-title-a", sessions.peerA, ["title"], taggedString("remote-a"));
	author("remote-enabled-a", sessions.peerA, ["enabled"], taggedBoolean(false));
	author("remote-rating-a", sessions.peerA, ["rating"], taggedNumber(17));
	author("remote-note-set", sessions.peerA, ["note"], taggedString("peer-note"), {
		optional: true,
		wasEmpty: true,
	});
	author("remote-note-clear", sessions.peerA, ["note"], null, {
		optional: true,
		wasEmpty: false,
	});
	author("remote-child-x", sessions.peerA, ["point", "x"], taggedNumber(77));
	author("remote-child-y", sessions.peerA, ["point", "y"], taggedNumber(88));
	author("remote-parent", sessions.peerA, ["point"], point(100, 200));
	author("remote-parent-b", sessions.peerB, ["point"], point(300, 400));
	author("restored-title", sessions.restored, ["title"], taggedString("restored"));

	assert(
		stable(compressor, nonlexicalPeerA.revision)
			< stable(compressor, nonlexicalPeerB.revision),
		"Nonlexical stable revisions must have lexical order",
	);
	assert(
		Number(nonlexicalPeerA.revision) > Number(nonlexicalPeerB.revision),
		"Compressed revision order must differ from stable revision order",
	);

	const scheduleInputs: object[] = [];
	const scheduleObservations: object[] = [];
	const scheduleRaw: object[] = [];

	function runSchedule(
		label: string,
		build: (schedule: {
			append(id: string, name: string): void;
			receive(
				id: string,
				name: string,
				sequenceNumber: number,
				indexInBatch: number,
				referenceSequenceNumber: number,
				minimumSequenceNumber: number,
			): void;
			advance(
				id: string,
				sequenceNumber: number,
				minimumSequenceNumber: number,
			): void;
			snapshotRestore(id: string, nextSession: SessionId): void;
			resubmit(
				id: string,
				repair?: (
					commit: GraphCommit<ModularChangeset>,
					index: number,
					roots: readonly DeltaDetachedNodeId[],
				) => TaggedValue,
			): void;
		}) => void,
	): void {
		let currentLocalSession = sessions.local;
		let observedSequenceNumber = 0;
		let minimumSequenceNumber = minimumPossibleSequenceNumber as number;
		let activeAllocations: Allocation[] = [];
		const peers = new Set<SessionId>();
		const forestActions: Scenario["actions"] = [];
		const actions: HistoryAction[] = [];
		const checkpoints: object[] = [];
		const rawActions: object[] = [];

		function mintRevision(): RevisionTag {
			const revision = remember(compressor.generateCompressedId());
			activeAllocations.push({
				revision: stable(compressor, revision),
				identityOrder: identityOrder(),
			});
			return revision;
		}

		function createManager(localSession: SessionId) {
			return new EditManager(family, localSession, mintRevision);
		}

		let manager = createManager(currentLocalSession);

		function internal(): InternalManager {
			return manager as unknown as InternalManager;
		}

		function mainBranch(): InternalBranch {
			const branch = internal().sharedBranches.get("main");
			assert(branch !== undefined, "The main branch must exist");
			return branch;
		}

		function sequencePoint(id: SequenceId) {
			return {
				sequenceNumber: id.sequenceNumber,
				indexInBatch: id.indexInBatch ?? 0,
			};
		}

		function encodeCommit(
			commit: GraphCommit<ModularChangeset>,
			originator?: SessionId,
		) {
			const metadata = mainBranch().commitMetadata.get(commit.revision);
			return {
				revision: stable(compressor, commit.revision),
				originator: originator ?? metadata?.sessionId ?? currentLocalSession,
				change: structureWithCompressor(commit.change, compressor),
			};
		}

		function view() {
			const state = internal();
			const trunk = manager.getTrunkCommits("main").map((commit) => {
				const metadata = mainBranch().commitMetadata.get(commit.revision);
				assert(metadata !== undefined, "A trunk commit needs sequencing metadata");
				return {
					commit: encodeCommit(commit, metadata.sessionId),
					point: sequencePoint(metadata.sequenceId),
				};
			});
			const peerBranches = [...peers].map((peer) => {
				const branch = mainBranch().getPeerBranchOrTrunk(peer);
				const path: GraphCommit<ModularChangeset>[] = [];
				const ancestor = findCommonAncestor(
					[branch.getHead(), path],
					manager.getTrunkHead("main"),
				);
				assert(ancestor !== undefined, "A peer branch must share trunk ancestry");
				return {
					originator: peer,
					base: ancestor === state.trunkBase
						? null
						: stable(compressor, ancestor.revision),
					commits: path.map((commit) => encodeCommit(commit, peer)),
				};
			});
			peerBranches.sort((left, right) => String(left.originator).localeCompare(String(right.originator)));
			const base = state.trunkBase.revision === "root"
				? { kind: "initial" }
				: {
						kind: "sequenced",
						point: (() => {
							for (const [id, commit] of mainBranch().sequenceIdToCommit.entries()) {
								if (commit === state.trunkBase) return sequencePoint(id);
							}
							assert.fail("The sequenced trunk base must remain in the sequence map");
						})(),
					};
			return {
				sequenced: {
					base,
					trunk,
					peers: peerBranches,
					sequenceNumber: observedSequenceNumber,
					minimumSequenceNumber,
				},
				pending: manager.getLocalCommits("main").map((commit) =>
					encodeCommit(commit, currentLocalSession)),
				longestBranchLength: manager.getLongestBranchLength(),
			};
		}

		function netChange(run: () => void): {
			readonly change: TaggedChange<ModularChangeset> | undefined;
			readonly trimmed: string[];
		} {
			const emitted: TaggedChange<ModularChangeset>[] = [];
			const trimmed: RevisionTag[] = [];
			const branch = manager.getLocalBranch("main");
			const offChange = branch.events.on("afterChange", (event) => {
				if (event.change !== undefined) emitted.push(event.change);
			});
			const offTrim = branch.events.on("ancestryTrimmed", (revisions) => {
				trimmed.push(...revisions);
			});
			run();
			offChange();
			offTrim();
			const change = emitted.length === 0
				? undefined
				: emitted.length === 1
					? emitted[0]
					: tagChange(family.compose(emitted), undefined);
			return {
				change,
				trimmed: trimmed.map((revision) => stable(compressor, revision)),
			};
		}

		function record(
			action: HistoryAction,
			outcome: {
				readonly change?: TaggedChange<ModularChangeset>;
				readonly trimmed?: string[];
				readonly snapshot?: object;
				readonly resubmitted?: object[];
			},
		): void {
			const allocations = activeAllocations;
			activeAllocations = [];
			const input = { ...action, allocations };
			actions.push(input);
			if (outcome.change === undefined) {
				forestActions.push({ id: action.id, op: "observe" });
			} else {
				forestActions.push({
					id: action.id,
					op: "apply",
					delta: deltaDataWithCompressor(
						intoDelta(outcome.change),
						outcome.change.revision,
						compressor,
					),
				});
			}
			const forest = runScenario(
				{ id: label, schema, root: root(), actions: forestActions },
				compressor,
				decoder,
			);
			const checkpoint = forest.observation.checkpoints.at(-1);
			assert(checkpoint?.accepted === true, `${label}.${action.id}: forest delta must apply`);
			checkpoints.push({
				id: action.id,
				operation: action.op,
				history: view(),
				delta: outcome.change === undefined
					? null
					: deltaDataWithCompressor(
							intoDelta(outcome.change),
							outcome.change.revision,
							compressor,
						),
				forest: checkpoint.state,
				trimmedRevisions: outcome.trimmed ?? [],
				allocator: { consumed: allocations },
				...(outcome.snapshot === undefined ? {} : { snapshot: outcome.snapshot }),
				...(outcome.resubmitted === undefined
					? {}
					: { resubmitted: outcome.resubmitted }),
			});
			rawActions.push({
				id: action.id,
				forest: forest.raw.actions.at(-1),
				allocations,
			});
		}

		function append(id: string, name: string): void {
			const authored = changes.get(name);
			assert(authored !== undefined, `Unknown authored change: ${name}`);
			assert.equal(
				authored.originator,
				currentLocalSession,
				`${label}.${id}: local commit session`,
			);
			const outcome = netChange(() => {
				manager.getLocalBranch("main").apply(
					tagChange(authored.change, authored.revision),
					CommitKind.Default,
					undefined,
				);
			});
			record({
				id,
				op: "append-local",
				commit: commitInput(name, authored, compressor),
			}, outcome);
		}

		function receive(
			id: string,
			name: string,
			sequenceNumber: number,
			indexInBatch: number,
			referenceSequenceNumber: number,
			suppliedMinimumSequenceNumber: number,
		): void {
			const authored = changes.get(name);
			assert(authored !== undefined, `Unknown authored change: ${name}`);
			if (authored.originator !== currentLocalSession) peers.add(authored.originator);
			const outcome = netChange(() => {
				manager.addSequencedChanges(
					[{
						change: authored.change,
						revision: authored.revision,
						customMetadata: undefined,
					}],
					authored.originator,
					brand(sequenceNumber),
					brand(referenceSequenceNumber),
					"main",
				);
				if (suppliedMinimumSequenceNumber >= minimumSequenceNumber) {
					manager.advanceMinimumSequenceNumber(brand(suppliedMinimumSequenceNumber));
					minimumSequenceNumber = suppliedMinimumSequenceNumber;
				}
			});
			observedSequenceNumber = Math.max(observedSequenceNumber, sequenceNumber);
			const trunk = manager.getTrunkCommits("main")
				.find((commit) => commit.revision === authored.revision);
			if (trunk !== undefined) {
				assert.deepEqual(
					sequencePoint(mainBranch().getCommitSequenceId(trunk.revision)),
					{ sequenceNumber, indexInBatch },
					`${label}.${id}: source sequence point`,
				);
			}
			record({
				id,
				op: "receive",
				commit: commitInput(name, authored, compressor),
				point: { sequenceNumber, indexInBatch },
				referenceSequenceNumber,
				minimumSequenceNumber: suppliedMinimumSequenceNumber,
			}, outcome);
		}

		function advance(
			id: string,
			sequenceNumber: number,
			suppliedMinimumSequenceNumber: number,
		): void {
			const outcome = netChange(() => {
				manager.advanceMinimumSequenceNumber(brand(suppliedMinimumSequenceNumber));
			});
			observedSequenceNumber = Math.max(observedSequenceNumber, sequenceNumber);
			minimumSequenceNumber = suppliedMinimumSequenceNumber;
			record({
				id,
				op: "advance-minimum",
				sequenceNumber,
				minimumSequenceNumber: suppliedMinimumSequenceNumber,
			}, outcome);
		}

		function snapshotRestore(id: string, nextSession: SessionId): void {
			let snapshot: object | undefined;
			const outcome = netChange(() => {
				const summary = manager.getSummaryData();
				snapshot = view().sequenced;
				const restored = createManager(nextSession);
				restored.loadSummaryData(summary);
				if (minimumSequenceNumber > (minimumPossibleSequenceNumber as number)) {
					restored.advanceMinimumSequenceNumber(brand(minimumSequenceNumber));
				}
				manager = restored;
				currentLocalSession = nextSession;
			});
			assert(snapshot !== undefined, "Snapshot capture must complete");
			record({
				id,
				op: "snapshot-restore",
				localSession: nextSession,
			}, { ...outcome, snapshot });
		}

		function resubmit(
			id: string,
			repair?: (
				commit: GraphCommit<ModularChangeset>,
				index: number,
				roots: readonly DeltaDetachedNodeId[],
			) => TaggedValue,
		): void {
			const repairEntries: object[] = [];
			const resubmitted = manager.getLocalCommits("main").map((commit, index) => {
				const roots = [...relevantRemovedRoots(commit.change)];
				const builds: object[] = [];
				const updated = updateRefreshers(
					commit.change,
					(rootId) => {
						const trees = [repair?.(commit, index, roots) ?? point(1, 2)];
						builds.push({
							id: detachedWithCompressor(rootId, compressor),
							trees,
						});
						return treeChunk(trees, compressor);
					},
					roots,
				);
				if (builds.length > 0) {
					repairEntries.push({
						revision: stable(compressor, commit.revision),
						builds,
					});
				}
				return {
					revision: stable(compressor, commit.revision),
					originator: currentLocalSession,
					change: structureWithCompressor(updated, compressor),
				};
			});
			record({
				id,
				op: "resubmit",
				repair: repairEntries,
			}, { resubmitted });
		}

		build({ append, receive, advance, snapshotRestore, resubmit });
		scheduleInputs.push({
			label,
			initial: {
				localSession: sessions.local,
				schema,
				forest: { root: root() },
			},
			actions,
		});
		scheduleObservations.push({ label, checkpoints });
		scheduleRaw.push({ label, actions: rawActions });
	}

	runSchedule("local-ack", ({ append, receive }) => {
		append("append-a", "local-title-a");
		receive("ack-a", "local-title-a", 1, 0, 0, 0);
	});

	runSchedule("remote-between-pending", ({ append, receive }) => {
		append("append-title", "local-title-a");
		append("append-enabled", "local-enabled");
		append("append-rating", "local-rating");
		receive("remote-note", "remote-note-set", 1, 0, 0, 0);
		receive("ack-title", "local-title-a", 2, 0, 0, 0);
		receive("ack-enabled", "local-enabled", 3, 0, 1, 0);
		receive("ack-rating", "local-rating", 4, 0, 2, 0);
	});

	runSchedule("same-field-local-first", ({ append, receive }) => {
		append("append-local", "local-title-a");
		receive("ack-local", "local-title-a", 1, 0, 0, 0);
		receive("remote-after", "remote-title-a", 2, 0, 0, 0);
	});

	runSchedule("same-field-remote-first", ({ append, receive }) => {
		append("append-local", "local-title-b");
		receive("remote-before", "remote-title-a", 1, 0, 0, 0);
		receive("ack-local", "local-title-b", 2, 0, 0, 0);
	});

	runSchedule("stale-peer-chain", ({ receive }) => {
		receive("peer-b-parent", "remote-parent-b", 1, 0, 0, 0);
		receive("peer-a-parent", "remote-parent", 2, 0, 0, 0);
		receive("peer-a-child", "remote-child-y", 3, 0, 0, 0);
	});

	runSchedule("parent-child-local-first", ({ append, receive }) => {
		append("append-parent", "local-parent");
		receive("ack-parent", "local-parent", 1, 0, 0, 0);
		receive("remote-child", "remote-child-x", 2, 0, 0, 0);
	});

	runSchedule("parent-child-remote-first", ({ append, receive }) => {
		append("append-parent", "local-parent");
		receive("remote-child", "remote-child-x", 1, 0, 0, 0);
		receive("ack-parent", "local-parent", 2, 0, 0, 0);
	});

	runSchedule("optional-clear-and-null", ({ append, receive }) => {
		append("append-note", "local-note");
		receive("ack-note", "local-note", 1, 0, 0, 0);
		receive("clear-note", "remote-note-clear", 2, 0, 1, 0);
		receive("set-note", "remote-note-set", 3, 0, 2, 0);
	});

	runSchedule("two-inner-commits", ({ receive }) => {
		receive("first-inner", "remote-title-a", 5, 0, 0, 0);
		receive("second-inner", "remote-enabled-a", 5, 1, 0, 0);
		receive("after-batch", "remote-rating-b", 6, 0, 5, 0);
	});

	runSchedule("non-tree-sequence-gap", ({ receive, advance }) => {
		receive("tree-at-two", "remote-title-a", 2, 0, 0, 0);
		advance("system-through-five", 5, 2);
		receive("tree-at-seven", "remote-rating-b", 7, 0, 5, 2);
	});

	runSchedule("window-advance-with-pending", ({ append, receive, advance }) => {
		receive("peer-b-parent", "remote-parent-b", 1, 0, 0, 0);
		receive("peer-b-barrier", "remote-rating-b", 2, 0, 1, 0);
		receive("peer-a-parent", "remote-parent", 3, 0, 0, 0);
		receive("peer-a-child", "remote-child-y", 4, 0, 0, 0);
		append("append-pending", "local-enabled");
		advance("advance-window", 5, 1);
	});

	runSchedule("settled-snapshot-tail", ({ append, receive, advance, snapshotRestore }) => {
		receive("peer-b-parent", "remote-parent-b", 1, 0, 0, 0);
		receive("peer-a-parent", "remote-parent", 2, 0, 0, 0);
		receive("peer-a-child", "remote-child-y", 3, 0, 0, 0);
		advance("minimum-before-snapshot", 4, 0);
		snapshotRestore("restore", sessions.restored);
		receive("stale-peer-after-restore", "remote-child-x", 5, 0, 0, 0);
		append("append-after-restore", "restored-title");
		receive("ack-after-restore", "restored-title", 6, 0, 5, 0);
	});

	runSchedule("accepted-before-ack", ({ append, receive, resubmit }) => {
		append("append-a", "accepted-a");
		append("append-b", "pending-b");
		receive("server-accepted-a", "accepted-a", 1, 0, 0, 0);
		receive("remote-between", "remote-title-a", 2, 0, 1, 0);
		resubmit("prepare-b");
	});

	runSchedule("never-submitted", ({ append, receive, resubmit }) => {
		append("append-c", "never-c");
		receive("catch-up", "remote-title-a", 1, 0, 0, 0);
		resubmit("prepare-c-first");
		resubmit("prepare-c-again");
		receive("ack-c", "never-c", 2, 0, 1, 0);
		resubmit("prepare-empty");
	});

	runSchedule("resubmit-detached-repair", ({ append, receive, resubmit }) => {
		append("append-child-x", "local-child-x");
		append("append-child-y", "local-child-y");
		receive("remote-parent", "remote-parent", 1, 0, 0, 0);
		resubmit("prepare-detached", (_commit, index, roots) => {
			assert(roots.length > 0, "Detached resubmission must require repair content");
			return index === 0 ? point(1, 2) : point(42, 2);
		});
	});

	runSchedule("nonlexical-rollback-order", ({ append, receive }) => {
		append("append-local", "local-title-a");
		receive("peer-b-first", "nonlexical-peer-b", 1, 0, 0, 0);
		receive("peer-a-second", "nonlexical-peer-a", 2, 0, 0, 0);
		receive("peer-a-continues", "remote-note-set", 3, 0, 0, 0);
		receive("peer-a-continues-again", "remote-rating-a", 4, 0, 0, 0);
		receive("ack-local", "local-title-a", 5, 0, 0, 0);
	});

	const changeInput = Object.fromEntries([...changes].map(([name, authored]) => [
		name,
		structureWithCompressor(authored.change, compressor),
	]));
	const oracleCase = {
		formatVersion,
		reference: {
			package: packageName,
			version: packageVersion,
			commit: expectedCommit,
		},
		id: "history-reconciliation",
		domain: "history",
		input: {
			sessions,
			revisions: identityOrder(),
			schema,
			root: root(),
			changes: changeInput,
			schedules: scheduleInputs,
		},
		expected: { observations: scheduleObservations },
		raw: {
			engine: "EditManager",
			schedules: scheduleRaw,
			nonlexical: {
				left: {
					stable: stable(compressor, nonlexicalPeerA.revision),
					encoded: Number(nonlexicalPeerA.revision),
				},
				right: {
					stable: stable(compressor, nonlexicalPeerB.revision),
					encoded: Number(nonlexicalPeerB.revision),
				},
			},
		},
	};
	mkdirSync(output, { recursive: true });
	writeFileSync(
		join(output, "history-cases.json"),
		`${JSON.stringify([oracleCase], null, 2)}\n`,
	);
}
