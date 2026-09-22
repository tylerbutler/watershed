/*!
 * Copyright (c) Microsoft Corporation and contributors. All rights reserved.
 * Licensed under the MIT License.
 */

import { strict as assert } from "node:assert";
import { mkdirSync, writeFileSync } from "node:fs";
import path from "node:path";

import type {
	IIdCompressor,
	OpSpaceCompressedId,
	SessionSpaceCompressedId,
	StableId,
} from "@fluidframework/id-compressor";
import {
	assertIsStableId,
	createIdCompressor,
	deserializeIdCompressor,
	isFinalId,
	serializeIdCompressor,
	toIdCompressorWithCore,
	type IdCreationRange,
	type SerializedIdCompressor,
	type SerializedIdCompressorWithNoSession,
	type SerializedIdCompressorWithOngoingSession,
} from "@fluidframework/id-compressor/internal";
import { modifyClusterSize } from "@fluidframework/id-compressor/internal/test-utils";

import { FluidClientVersion, type CodecWriteOptions } from "../codec/index.js";
import {
	DetachedFieldIndex,
	RevisionTagCodec,
	applyDelta,
	makeDetachedFieldIndex,
	makeDetachedNodeId,
	moveToDetachedField,
	revisionMetadataSourceFromInfo,
	rootFieldKey,
	tagChange,
	type ChangeAtomId,
	type ChangeEncodingContext,
	type ChangesetLocalId,
	type DeltaFieldMap,
	type DeltaRoot,
	type DeltaDetachedNodeId,
	type DetachedField,
	type FieldKey,
	type IEditableForest,
	type RevisionTag,
} from "../core/index.js";
import { FormatValidatorBasic } from "../external-utilities/index.js";
import {
	DefaultAtomIdAliasAllocator,
	DefaultRevisionReplacer,
	ModularChangeFamily,
	ModularChangeFormatVersion,
	TreeCompressionStrategy,
	fieldBatchCodecBuilder,
	fieldKindConfigurations,
	fieldKinds,
	makeModularChangeCodecFamily,
	newChangeAtomIdBTree,
	relevantRemovedRoots,
	updateRefreshers,
	type CrossFieldManager,
	type FieldChangeEncodingContext,
	type FieldChangeset,
	type ModularChangeset,
	type NodeId,
} from "../feature-libraries/index.js";
import {
	NodeAttachState,
	rebaseRevisionMetadataFromInfo,
} from "../feature-libraries/modular-schema/index.js";
import { makeModularChangeset } from "../feature-libraries/modular-schema/modularChangeUtils.js";
import { pruneChangeset } from "../feature-libraries/modular-schema/prune.js";
import { optional } from "../feature-libraries/optional-field/index.js";
import {
	optionalChangeHandler,
	optionalChangeRebaser,
	optionalFieldEditor,
	optionalFieldIntoDelta,
} from "../feature-libraries/optional-field/optionalField.js";
import type { OptionalChangeset } from "../feature-libraries/optional-field/optionalFieldChangeTypes.js";
import {
	requiredFieldChangeHandler,
	requiredFieldEditor,
	required,
} from "../feature-libraries/optional-field/requiredField.js";
import {
	brand,
	idAllocatorFromMaxId,
	type JsonCompatible,
	type JsonCompatibleReadOnly,
} from "../util/index.js";
import { cursorToJsonObject, fieldJsonCursor } from "./json/index.js";
import { initializeForest } from "./feature-libraries/index.js";
import {
	assertIsSessionId,
	buildTestForest,
	chunkFromJsonTrees,
	mintRevisionTag,
	testIdCompressor,
} from "./utils.js";

const formatVersion = 1;
const packageName = "@fluidframework/tree";
const packageVersion = "3.1.0";
const expectedCommit = "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960";

interface OracleCase {
	readonly formatVersion: 1;
	readonly reference: {
		readonly package: typeof packageName;
		readonly version: typeof packageVersion;
		readonly commit: string;
	};
	readonly id: string;
	readonly domain: string;
	readonly input: JsonCompatibleReadOnly | object;
	readonly expected: {
		readonly observations: readonly (JsonCompatibleReadOnly | object)[];
		readonly scenarios?: readonly object[];
	};
	readonly raw: JsonCompatibleReadOnly | object;
}

interface RefusalObservation {
	readonly status: "rejected";
	readonly error: string;
}

interface MalformedAllocationFragment {
	readonly input: {
		readonly operation: "finalizeCreationRange";
		readonly targetSession: string;
		readonly initialSerializedState: string;
		readonly corruption: {
			readonly path: "$.ids.count";
			readonly valid: number;
			readonly corrupted: 0;
		};
		readonly range: IdCreationRange;
	};
	readonly expected: {
		readonly observation: RefusalObservation & {
			readonly operation: "malformed-allocation-refusal";
			readonly statePreserved: true;
			readonly postState: string;
		};
	};
	readonly raw: {
		readonly validRange: IdCreationRange;
		readonly corruptedRange: IdCreationRange;
		readonly error: RefusalObservation;
		readonly serialized: {
			readonly before: string;
			readonly after: string;
		};
	};
}

interface DirectSwapApplication {
	readonly input: {
		readonly operation: "apply-original-simultaneous-swap";
		readonly revision: RevisionTag;
		readonly registers: readonly [
			{
				readonly id: ChangeAtomId;
				readonly content: JsonCompatibleReadOnly;
			},
			{
				readonly id: ChangeAtomId;
				readonly content: JsonCompatibleReadOnly;
			},
		];
	};
	readonly observation: {
		readonly operation: "simultaneous-swap-direct-application-refusal";
		readonly status: "rejected";
		readonly reason: "occupied-rename-cycle";
		readonly postFailureForestRead: JsonCompatibleReadOnly | object;
	};
	readonly raw: {
		readonly sourceDelta: ReturnType<typeof optionalFieldIntoDelta>;
		readonly before: {
			readonly registers: readonly [JsonCompatibleReadOnly, JsonCompatibleReadOnly];
			readonly detachedIndex: readonly object[];
		};
		readonly refusal: RefusalObservation;
		readonly postFailureForestRead: JsonCompatibleReadOnly | object;
		readonly detachedIndexAfterRefusal: readonly object[];
	};
}

interface SwapAlgebraMapping {
	readonly input: {
		readonly operation: "rebase-child-changes-over-simultaneous-swap";
		readonly change: OptionalChangeset;
		readonly over: OptionalChangeset;
	};
	readonly observation: {
		readonly operation: "simultaneous-swap-algebra-mapping";
		readonly mappings: readonly {
			readonly node: NodeId;
			readonly from: ChangeAtomId;
			readonly to: ChangeAtomId;
		}[];
	};
	readonly raw: {
		readonly rebased: OptionalChangeset;
		readonly callbacks: readonly object[];
	};
}

const failCrossFieldManager: CrossFieldManager = {
	get: () => assert.fail("This field change must not query cross-field state."),
	set: () => assert.fail("This field change must not modify cross-field state."),
	onMoveIn: () => assert.fail("This field change must not move a node."),
	moveKey: () => assert.fail("This field change must not move a cross-field key."),
};

function atom(revision: RevisionTag, localId: number): ChangeAtomId {
	return { revision, localId: brand(localId) };
}

function fieldKey(name: string): FieldKey {
	return brand(name);
}

function nodeKey(id: NodeId): readonly [RevisionTag | undefined, ChangesetLocalId] {
	return [id.revision, id.localId];
}

function reference(commit: string): OracleCase["reference"] {
	return {
		package: packageName,
		version: packageVersion,
		commit,
	};
}

function capture(action: () => JsonCompatibleReadOnly): JsonCompatibleReadOnly | object {
	try {
		return { status: "accepted", value: action() };
	} catch (error) {
		return {
			status: "rejected",
			error: error instanceof Error ? `${error.name}: ${error.message}` : String(error),
		};
	}
}

function captureRefusal(action: () => void): RefusalObservation {
	try {
		action();
	} catch (error) {
		return {
			status: "rejected",
			error: error instanceof Error ? `${error.name}: ${error.message}` : String(error),
		};
	}
	return assert.fail("The malformed creation range was accepted.");
}

function readDetachedRegister(
	forest: IEditableForest,
	index: DetachedFieldIndex,
	id: DeltaDetachedNodeId,
): JsonCompatibleReadOnly {
	const root = index.getEntry(id);
	const detachedField = brand<DetachedField>(index.toFieldKey(root));
	const cursor = forest.allocateCursor("watershed simultaneous swap");
	try {
		moveToDetachedField(forest, cursor, detachedField);
		assert(cursor.firstNode(), "The detached register must contain one node.");
		const content = cursorToJsonObject(cursor);
		assert.equal(cursor.nextNode(), false, "The detached register must contain one node.");
		return content;
	} finally {
		cursor.free();
	}
}

function applyDirectSimultaneousSwap(
	revision: RevisionTag,
	change: OptionalChangeset,
): DirectSwapApplication {
	const firstId = atom(revision, 4);
	const secondId = atom(revision, 5);
	const firstDetachedId = makeDetachedNodeId(firstId.revision, firstId.localId);
	const secondDetachedId = makeDetachedNodeId(secondId.revision, secondId.localId);
	const firstContent = "register-four";
	const secondContent = "register-five";
	const forest = buildTestForest({ additionalAsserts: true });
	const index = makeDetachedFieldIndex("watershed-swap");

	applyDelta(
		{
			build: [
				{ id: firstDetachedId, trees: chunkFromJsonTrees([firstContent]) },
				{ id: secondDetachedId, trees: chunkFromJsonTrees([secondContent]) },
			],
		},
		revision,
		forest,
		index,
	);
	const before = {
		registers: [
			readDetachedRegister(forest, index, firstDetachedId),
			readDetachedRegister(forest, index, secondDetachedId),
		] as const,
		detachedIndex: [...index.entries()],
	};
	const sourceDelta = optionalFieldIntoDelta(change, () => new Map());
	assert.equal(sourceDelta.rename?.length, 2);
	const [firstRename, secondRename] = sourceDelta.rename;
	assert.deepEqual(firstRename.newId, secondRename.oldId);
	assert.deepEqual(secondRename.newId, firstRename.oldId);
	const refusal = captureRefusal(() =>
		applyDelta({ rename: sourceDelta.rename }, revision, forest, index),
	);
	assert.deepEqual(refusal, {
		status: "rejected",
		error: "Error: 0x7cf",
	});
	const postFailureForestRead = capture(() => ({
		first: readDetachedRegister(forest, index, firstDetachedId),
		second: readDetachedRegister(forest, index, secondDetachedId),
	}));
	const detachedIndexAfterRefusal = [...index.entries()];
	assert.deepEqual(postFailureForestRead, {
		status: "accepted",
		value: {
			first: firstContent,
			second: secondContent,
		},
	});
	assert.deepEqual(detachedIndexAfterRefusal, before.detachedIndex);

	return {
		input: {
			operation: "apply-original-simultaneous-swap",
			revision,
			registers: [
				{ id: firstId, content: firstContent },
				{ id: secondId, content: secondContent },
			],
		},
		observation: {
			operation: "simultaneous-swap-direct-application-refusal",
			status: refusal.status,
			reason: "occupied-rename-cycle",
			postFailureForestRead,
		},
		raw: {
			sourceDelta,
			before,
			refusal,
			postFailureForestRead,
			detachedIndexAfterRefusal,
		},
	};
}

function rebaseChildrenThroughSimultaneousSwap(
	revision: RevisionTag,
	swap: OptionalChangeset,
	metadata: ReturnType<typeof rebaseRevisionMetadataFromInfo>,
): SwapAlgebraMapping {
	const firstRegister = atom(revision, 4);
	const secondRegister = atom(revision, 5);
	const firstNode = atom(revision, 40);
	const secondNode = atom(revision, 41);
	const change: OptionalChangeset = {
		moves: [],
		childChanges: [
			[firstRegister, firstNode],
			[secondRegister, secondNode],
		],
	};
	const callbacks: object[] = [];
	const rebased = optionalChangeRebaser.rebase(
		change,
		swap,
		(node, over, state) => {
			callbacks.push({ node, over: over ?? null, state });
			return node;
		},
		idAllocatorFromMaxId(),
		failCrossFieldManager,
		metadata,
	);
	const [firstMapping, secondMapping] = rebased.childChanges;
	assert.deepEqual(firstMapping, [secondRegister, firstNode]);
	assert.deepEqual(secondMapping, [firstRegister, secondNode]);
	const firstOutput = firstMapping[0];
	const secondOutput = secondMapping[0];
	assert(typeof firstOutput !== "string");
	assert(typeof secondOutput !== "string");

	return {
		input: {
			operation: "rebase-child-changes-over-simultaneous-swap",
			change,
			over: swap,
		},
		observation: {
			operation: "simultaneous-swap-algebra-mapping",
			mappings: [
				{ node: firstNode, from: firstRegister, to: firstOutput },
				{ node: secondNode, from: secondRegister, to: secondOutput },
			],
		},
		raw: { rebased, callbacks },
	};
}

function offsetStableId(base: StableId, offset: bigint): StableId {
	const hex = base.replaceAll("-", "");
	const value = (BigInt(`0x${hex}`) + offset).toString(16).padStart(32, "0");
	return assertIsStableId(
		`${value.slice(0, 8)}-${value.slice(8, 12)}-${value.slice(12, 16)}-${value.slice(16, 20)}-${value.slice(20)}`,
	);
}

function describeCompressedId(
	compressor: IIdCompressor,
	id: SessionSpaceCompressedId,
): JsonCompatibleReadOnly | object {
	const op = compressor.normalizeToOpSpace(id);
	return {
		session: id,
		op,
		final: isFinalId(id),
		stable: compressor.decompress(id),
		recompressed: compressor.recompress(compressor.decompress(id)),
	};
}

function makeMalformedAllocationFragment(): MalformedAllocationFragment {
	const producerSession = assertIsSessionId("40000000-0000-4000-8000-000000000004");
	const targetSession = assertIsSessionId("50000000-0000-4000-8000-000000000005");
	const producer = toIdCompressorWithCore(createIdCompressor(producerSession));
	const target = toIdCompressorWithCore(createIdCompressor(targetSession));
	producer.generateCompressedId();
	producer.generateCompressedId();
	const validRange = producer.takeNextCreationRange();
	assert(validRange.ids !== undefined, "The generated creation range must contain IDs.");
	const corruptedRange: IdCreationRange = {
		sessionId: validRange.sessionId,
		ids: {
			...validRange.ids,
			count: 0,
		},
	};
	const before = serializeIdCompressor(target, true);
	const refusal = captureRefusal(() => target.finalizeCreationRange(corruptedRange));
	assert.deepEqual(refusal, {
		status: "rejected",
		error: "Error: 0x755",
	});
	const after = serializeIdCompressor(target, true);
	assert.equal(after, before);
	const observation = {
		operation: "malformed-allocation-refusal" as const,
		...refusal,
		statePreserved: true as const,
		postState: after,
	};

	return {
		input: {
			operation: "finalizeCreationRange",
			targetSession,
			initialSerializedState: before,
			corruption: {
				path: "$.ids.count",
				valid: validRange.ids.count,
				corrupted: 0,
			},
			range: corruptedRange,
		},
		expected: { observation },
		raw: {
			validRange,
			corruptedRange,
			error: refusal,
			serialized: { before, after },
		},
	};
}

type IdStep =
	| { op: "generate"; client: number; count: number }
	| { op: "take"; client: number }
	| { op: "finalize"; client: number; range: number }
	| { op: "finalize-input"; client: number; range: IdCreationRange }
	| { op: "save"; client: number; local: boolean }
	| { op: "restore"; client: number; saved: number; session?: string }
	| { op: "describe"; client: number; ids: number[] }
	| { op: "normalize"; client: number; origin: string; id: number };

function makeIdTrace(sessions: string[], clusterSize: number, steps: IdStep[]) {
	const clients = sessions.map((session) => {
		const compressor = toIdCompressorWithCore(createIdCompressor(assertIsSessionId(session)));
		modifyClusterSize(compressor, clusterSize);
		return compressor;
	});
	const ranges: IdCreationRange[] = [];
	const saved: SerializedIdCompressor[] = [];
	const inputSteps: object[] = [];
	const observations: object[] = [];
	for (const step of steps) {
		let value: unknown;
		if (step.op === "restore") {
			const serialized = saved[step.saved];
			assert(serialized !== undefined);
			const compressor = step.session === undefined
				? deserializeIdCompressor(serialized as SerializedIdCompressorWithOngoingSession)
				: deserializeIdCompressor(serialized as SerializedIdCompressorWithNoSession, assertIsSessionId(step.session));
			clients[step.client] = toIdCompressorWithCore(compressor);
			inputSteps.push({ op: step.op, client: step.client, serialized, session: compressor.localSessionId });
			value = compressor.localSessionId;
		} else {
			inputSteps.push(step);
			const compressor = clients[step.client];
			assert(compressor !== undefined);
			switch (step.op) {
				case "generate":
					value = Array.from({ length: step.count }, () =>
						describeCompressedId(compressor, compressor.generateCompressedId()));
					break;
				case "take": {
					const range = compressor.takeNextCreationRange();
					ranges.push(range);
					value = range;
					break;
				}
				case "finalize":
				case "finalize-input": {
					const range = step.op === "finalize" ? ranges[step.range] : step.range;
					assert(range !== undefined);
					compressor.finalizeCreationRange(range);
					value = serializeIdCompressor(compressor, false);
					break;
				}
				case "save": {
					const serialized = step.local
						? serializeIdCompressor(compressor, true)
						: serializeIdCompressor(compressor, false);
					saved.push(serialized);
					value = serialized;
					break;
				}
				case "describe":
					value = step.ids.map((id) =>
						describeCompressedId(compressor, id as SessionSpaceCompressedId));
					break;
				case "normalize": {
					const id = compressor.normalizeToSessionSpace(
						step.id as OpSpaceCompressedId, assertIsSessionId(step.origin));
					value = describeCompressedId(compressor, id);
					break;
				}
			}
		}
		observations.push({ op: step.op, client: step.client, value });
	}
	return { input: { sessions, clusterSize, steps: inputSteps }, observations };
}

function makeIdCase(commit: string): OracleCase {
	const sessionA = assertIsSessionId("10000000-0000-4000-8000-000000000001");
	const sessionB = assertIsSessionId("20000000-0000-4000-8000-000000000002");
	const restoredSession = assertIsSessionId("30000000-0000-4000-8000-000000000003");
	const compressorA = toIdCompressorWithCore(createIdCompressor(sessionA));
	const compressorB = toIdCompressorWithCore(createIdCompressor(sessionB));
	modifyClusterSize(compressorA, 3);
	modifyClusterSize(compressorB, 3);

	const initialA = [compressorA.generateCompressedId(), compressorA.generateCompressedId()];
	const initialB = [compressorB.generateCompressedId(), compressorB.generateCompressedId()];
	const beforeFinalization = {
		a: initialA.map((id) => describeCompressedId(compressorA, id)),
		b: initialB.map((id) => describeCompressedId(compressorB, id)),
	};

	const rangeA0 = compressorA.takeNextCreationRange();
	const rangeB0 = compressorB.takeNextCreationRange();
	for (const compressor of [compressorA, compressorB]) {
		compressor.finalizeCreationRange(rangeA0);
		compressor.finalizeCreationRange(rangeB0);
	}

	const eagerA = compressorA.generateCompressedId();
	const eagerB = compressorB.generateCompressedId();
	const expansionA = [compressorA.generateCompressedId(), compressorA.generateCompressedId()];
	const expansionB = [compressorB.generateCompressedId(), compressorB.generateCompressedId()];
	const rangeA1 = compressorA.takeNextCreationRange();
	const rangeB1 = compressorB.takeNextCreationRange();
	for (const compressor of [compressorA, compressorB]) {
		compressor.finalizeCreationRange(rangeA1);
		compressor.finalizeCreationRange(rangeB1);
	}

	const opFromA = compressorA.normalizeToOpSpace(expansionA[1]);
	const remoteAtB = compressorB.normalizeToSessionSpace(opFromA, sessionA);
	const opFromB = compressorB.normalizeToOpSpace(expansionB[1]);
	const remoteAtA = compressorA.normalizeToSessionSpace(opFromB, sessionB);

	const serializedWithSession = serializeIdCompressor(compressorA, true);
	const serializedSummary = serializeIdCompressor(compressorA, false);
	const restoredOngoing = toIdCompressorWithCore(
		deserializeIdCompressor(serializedWithSession),
	);
	const restoredSummary = toIdCompressorWithCore(
		deserializeIdCompressor(serializedSummary, restoredSession),
	);
	const restoredOngoingNext = restoredOngoing.generateCompressedId();
	const restoredSummaryNext = restoredSummary.generateCompressedId();

	const stableDocumentId = compressorA.generateDocumentUniqueId();
	const precisionInputs = {
		lastExactOffset: offsetStableId(sessionA, BigInt(Number.MAX_SAFE_INTEGER - 1)),
		firstRejectedOffset: offsetStableId(sessionA, BigInt(Number.MAX_SAFE_INTEGER)),
	};
	const precision = {
		lastExactOffset: capture(
			() => compressorA.tryRecompress(precisionInputs.lastExactOffset) ?? null,
		),
		firstRejectedOffset: capture(
			() => compressorA.tryRecompress(precisionInputs.firstRejectedOffset) ?? null,
		),
	};
	const malformedAllocation = makeMalformedAllocationFragment();
	const growth = makeIdTrace(
		["60000000-0000-4000-8000-000000000006", "70000000-0000-4000-8000-000000000007"],
		2,
		[
			{ op: "generate", client: 0, count: 3 },
			{ op: "take", client: 0 },
			{ op: "finalize", client: 0, range: 0 },
			{ op: "finalize", client: 1, range: 0 },
			{ op: "generate", client: 1, count: 1 },
			{ op: "take", client: 1 },
			{ op: "finalize", client: 0, range: 1 },
			{ op: "finalize", client: 1, range: 1 },
			{ op: "generate", client: 0, count: 5 },
			{ op: "take", client: 0 },
			{ op: "generate", client: 0, count: 2 },
			{ op: "save", client: 0, local: true },
			{ op: "save", client: 0, local: false },
			{ op: "restore", client: 2, saved: 0 },
			{ op: "restore", client: 3, saved: 1, session: "80000000-0000-4000-8000-000000000008" },
			{ op: "describe", client: 2, ids: [-1, 3, 4, -6, -8, -9, -10] },
			{ op: "take", client: 2 },
			{ op: "take", client: 2 },
			{ op: "generate", client: 3, count: 1 },
			{ op: "finalize", client: 0, range: 2 },
			{ op: "finalize", client: 1, range: 2 },
			{ op: "finalize", client: 2, range: 2 },
			{ op: "generate", client: 0, count: 1 },
			{ op: "take", client: 0 },
			{ op: "finalize", client: 0, range: 5 },
			{ op: "finalize", client: 1, range: 5 },
			{ op: "generate", client: 0, count: 2 },
			{ op: "normalize", client: 0, origin: sessionB, id: 0 },
			{ op: "normalize", client: 1, origin: "60000000-0000-4000-8000-000000000006", id: -8 },
			{ op: "describe", client: 0, ids: [-1, -6, -8, -9, -10, -11, 14, 15] },
			{ op: "save", client: 0, local: true },
			{ op: "save", client: 0, local: false },
		],
	);
	const uuidCarry = makeIdTrace(
		["00000000-0000-4fff-bfff-fffffffffffe"], 1,
		[
			{ op: "generate", client: 0, count: 3 },
			{ op: "take", client: 0 },
			{ op: "finalize", client: 0, range: 0 },
			{ op: "generate", client: 0, count: 1 },
			{ op: "save", client: 0, local: true },
			{ op: "restore", client: 1, saved: 0 },
			{ op: "generate", client: 1, count: 1 },
		],
	);
	const half = 2 ** 52;
	const safeIntegers = makeIdTrace([sessionA], 1, [
		{
			op: "finalize-input", client: 0,
			range: {
				sessionId: sessionB,
				ids: { firstGenCount: 1, count: half, requestedClusterSize: 1, localIdRanges: [[1, half]] },
			},
		},
		{
			op: "finalize-input", client: 0,
			range: {
				sessionId: restoredSession,
				ids: { firstGenCount: 1, count: 1, requestedClusterSize: 1, localIdRanges: [[1, 1]] },
			},
		},
		{
			op: "finalize-input", client: 0,
			range: {
				sessionId: sessionB,
				ids: { firstGenCount: half + 1, count: 3, requestedClusterSize: 1, localIdRanges: [[half + 2, 2]] },
			},
		},
		{ op: "normalize", client: 0, origin: sessionB, id: -half - 2 },
		{ op: "describe", client: 0, ids: [half + 3, half + 4] },
		{ op: "save", client: 0, local: true },
		{ op: "restore", client: 1, saved: 0 },
		{ op: "describe", client: 1, ids: [half + 3, half + 4] },
	]);

	const observations: (JsonCompatibleReadOnly | object)[] = [
		{
			stage: "before-finalization",
			value: beforeFinalization,
		},
		{
			stage: "after-finalization",
			value: {
				initialA: initialA.map((id) => describeCompressedId(compressorA, id)),
				initialB: initialB.map((id) => describeCompressedId(compressorB, id)),
				eagerA: describeCompressedId(compressorA, eagerA),
				eagerB: describeCompressedId(compressorB, eagerB),
				expansionA: expansionA.map((id) => describeCompressedId(compressorA, id)),
				expansionB: expansionB.map((id) => describeCompressedId(compressorB, id)),
			},
		},
		{
			stage: "remote-normalization",
			value: {
				aToB: {
					op: opFromA,
					session: remoteAtB,
					stable: compressorB.decompress(remoteAtB),
					matchesOrigin:
						compressorB.decompress(remoteAtB) === compressorA.decompress(expansionA[1]),
				},
				bToA: {
					op: opFromB,
					session: remoteAtA,
					stable: compressorA.decompress(remoteAtA),
					matchesOrigin:
						compressorA.decompress(remoteAtA) === compressorB.decompress(expansionB[1]),
				},
			},
		},
		{
			stage: "restoration",
			value: {
				ongoingSession: restoredOngoing.localSessionId,
				ongoingNext: describeCompressedId(restoredOngoing, restoredOngoingNext),
				summarySession: restoredSummary.localSessionId,
				summaryNext: describeCompressedId(restoredSummary, restoredSummaryNext),
			},
		},
		{
			stage: "document-unique",
			value: {
				id: stableDocumentId,
				isStable: typeof stableDocumentId === "string",
			},
		},
		{ stage: "precision-limits", value: precision },
		malformedAllocation.expected.observation,
		{ stage: "creation-ranges", value: [rangeA0, rangeB0, rangeA1, rangeB1] },
		{ stage: "serialization", value: { withSession: serializedWithSession, summary: serializedSummary } },
		{ stage: "cluster-growth-and-pending", value: growth.observations },
		{ stage: "uuid-carry", value: uuidCarry.observations },
		{ stage: "safe-integer-offsets", value: safeIntegers.observations },
	];

	return {
		formatVersion,
		reference: reference(commit),
		id: "id-ranges",
		domain: "ids",
		input: {
			sessions: {
				a: sessionA,
				b: sessionB,
				summaryRestoration: restoredSession,
				malformedProducer: malformedAllocation.input.range.sessionId,
				malformedTarget: malformedAllocation.input.targetSession,
			},
			clusterSize: 3,
			schedule: [
				"generate-two-each",
				"finalize-a0",
				"finalize-b0",
				"generate-eager-and-expansion",
				"finalize-a1",
				"finalize-b1",
			],
			operations: {
				restoration: {
					ongoing: { includeLocalState: true, serialized: serializedWithSession },
					summary: {
						includeLocalState: false,
						newSessionId: restoredSession,
						serialized: serializedSummary,
					},
				},
				precision: precisionInputs,
				malformedAllocation: malformedAllocation.input,
			},
			traces: { growth: growth.input, uuidCarry: uuidCarry.input, safeIntegers: safeIntegers.input },
		},
		expected: { observations },
		raw: {
			ranges: [rangeA0, rangeB0, rangeA1, rangeB1],
			serialized: {
				withSession: serializedWithSession,
				summary: serializedSummary,
			},
			stableDocumentId,
			precision: { inputs: precisionInputs, results: precision },
			malformedAllocation,
		},
	};
}

function fieldEncodingContext(
	revision: RevisionTag,
	encodeNodeIds = false,
): FieldChangeEncodingContext {
	const baseContext: ChangeEncodingContext = {
		originatorId: testIdCompressor.localSessionId,
		idCompressor: testIdCompressor,
		revision,
		isSummary: false,
	};
	return {
		baseContext,
		encodeNode: (node) =>
			encodeNodeIds
				? node.revision === undefined
					? { localId: node.localId }
					: { revision: node.revision, localId: node.localId }
				: {},
	};
}

type FixtureAtom = { revision: number | null; localId: number };
type FixtureRegister =
	| { kind: "active" }
	| { kind: "detached"; id: FixtureAtom };
type FixtureChange = {
	moves: [FixtureAtom, FixtureAtom][];
	childChanges: [FixtureRegister, FixtureAtom][];
	replacement: {
		wasEmpty: boolean;
		source: FixtureRegister | null;
		detachId: FixtureAtom;
	} | null;
};
type FixtureAction = {
	id: string;
	op: "set" | "clear" | "replaceRevisions" | "compose" | "invert" | "rebase" | "intoDelta";
	result?: string;
	[key: string]: unknown;
};
type FieldScenario = {
	id: string;
	changes: Record<string, FixtureChange>;
	actions: FixtureAction[];
	forest?: {
		schema: { rootField: "root"; cardinality: "optional"; values: "json-compatible" };
		initialRoot: { present: boolean; value: JsonCompatible | null };
		builds: { id: FixtureAtom; value: JsonCompatible }[];
		detachedRegisters: { id: FixtureAtom; value: JsonCompatible }[];
	};
};

const activeRegister: FixtureRegister = { kind: "active" };

function fixtureAtom(revision: RevisionTag | null, localId: number): FixtureAtom {
	return { revision: revision as number | null, localId };
}

function detachedRegister(id: FixtureAtom): FixtureRegister {
	return { kind: "detached", id };
}

function fixtureChange(
	moves: [FixtureAtom, FixtureAtom][] = [],
	childChanges: [FixtureRegister, FixtureAtom][] = [],
	replacement: FixtureChange["replacement"] = null,
): FixtureChange {
	return { moves, childChanges, replacement };
}

function fixtureReplacement(
	wasEmpty: boolean,
	source: FixtureRegister | null,
	detachId: FixtureAtom,
): NonNullable<FixtureChange["replacement"]> {
	return { wasEmpty, source, detachId };
}

function fromFixtureAtom(value: FixtureAtom): ChangeAtomId {
	const id: { revision?: RevisionTag; localId: ChangesetLocalId } = {
		localId: brand(value.localId),
	};
	if (value.revision !== null) id.revision = value.revision as RevisionTag;
	return id;
}

function toFixtureAtom(value: ChangeAtomId | NodeId): FixtureAtom {
	return fixtureAtom((value.revision ?? null) as RevisionTag | null, value.localId);
}

function fromFixtureRegister(value: FixtureRegister): "self" | ChangeAtomId {
	return value.kind === "active" ? "self" : fromFixtureAtom(value.id);
}

function toFixtureRegister(value: "self" | ChangeAtomId): FixtureRegister {
	return value === "self" ? activeRegister : detachedRegister(toFixtureAtom(value));
}

function fromFixtureChange(value: FixtureChange): OptionalChangeset {
	const change: {
		moves: [ChangeAtomId, ChangeAtomId][];
		childChanges: ["self" | ChangeAtomId, NodeId][];
		valueReplace?: {
			isEmpty: boolean;
			src?: "self" | ChangeAtomId;
			dst: ChangeAtomId;
		};
	} = {
		moves: value.moves.map(([src, dst]) => [fromFixtureAtom(src), fromFixtureAtom(dst)]),
		childChanges: value.childChanges.map(([register, node]) => [
			fromFixtureRegister(register),
			fromFixtureAtom(node),
		]),
	};
	if (value.replacement !== null) {
		change.valueReplace = {
			isEmpty: value.replacement.wasEmpty,
			dst: fromFixtureAtom(value.replacement.detachId),
		};
		if (value.replacement.source !== null) {
			change.valueReplace.src = fromFixtureRegister(value.replacement.source);
		}
	}
	return change;
}

function toFixtureChange(value: OptionalChangeset): FixtureChange {
	return fixtureChange(
		value.moves.map(([src, dst]) => [toFixtureAtom(src), toFixtureAtom(dst)]),
		value.childChanges.map(([register, node]) => [
			toFixtureRegister(register),
			toFixtureAtom(node),
		]),
		value.valueReplace === undefined
			? null
			: fixtureReplacement(
					value.valueReplace.isEmpty,
					value.valueReplace.src === undefined
						? null
						: toFixtureRegister(value.valueReplace.src),
					toFixtureAtom(value.valueReplace.dst),
				),
	);
}

function fixtureFieldMap(value: unknown): [string, object][] {
	assert(Array.isArray(value), "A child delta field map must be an array.");
	return value as [string, object][];
}

function fromFixtureFieldMap(value: unknown): DeltaFieldMap {
	return new Map(fixtureFieldMap(value).map(([key, field]) => [
		fieldKey(key),
		field as DeltaFieldMap extends ReadonlyMap<FieldKey, infer Field> ? Field : never,
	]));
}

function toFixtureFieldMap(value: DeltaFieldMap | undefined): [string, object][] {
	return value === undefined ? [] : [...value].map(([key, field]) => [key, field]);
}

function toFixtureDelta(value: ReturnType<typeof optionalFieldIntoDelta>): object {
	return {
		local: value.local === undefined
			? null
			: {
					marks: value.local.marks.map((mark) => ({
						count: mark.count,
						attach: mark.attach === undefined
							? null
							: fixtureAtom((mark.attach.major ?? null) as RevisionTag | null, mark.attach.minor),
						detach: mark.detach === undefined
							? null
							: fixtureAtom((mark.detach.major ?? null) as RevisionTag | null, mark.detach.minor),
						fields: toFixtureFieldMap(mark.fields),
					})),
				},
		global: (value.global ?? []).map(({ id, fields }) => ({
			id: fixtureAtom((id.major ?? null) as RevisionTag | null, id.minor),
			fields: toFixtureFieldMap(fields),
		})),
		rename: (value.rename ?? []).map(({ oldId, newId, count }) => ({
			oldId: fixtureAtom((oldId.major ?? null) as RevisionTag | null, oldId.minor),
			newId: fixtureAtom((newId.major ?? null) as RevisionTag | null, newId.minor),
			count,
		})),
	};
}

function rawFieldMap(value: DeltaFieldMap | undefined): [string, object][] {
	return value === undefined ? [] : [...value].map(([key, field]) => [key, field]);
}

function rawFieldDelta(value: ReturnType<typeof optionalFieldIntoDelta>): object {
	return {
		local: value.local === undefined
			? null
			: {
					marks: value.local.marks.map((mark) => ({
						...mark,
						attach: mark.attach ?? null,
						detach: mark.detach ?? null,
						fields: rawFieldMap(mark.fields),
					})),
				},
		global: (value.global ?? []).map(({ id, fields }) => ({
			id,
			fields: rawFieldMap(fields),
		})),
		rename: value.rename ?? [],
	};
}

function fieldScenarios(revisions: readonly RevisionTag[]): FieldScenario[] {
	type ForestInput = NonNullable<FieldScenario["forest"]>;
	const [a, b, inverse, replacement] = revisions;
	const id = (revision: RevisionTag | null, localId: number) => fixtureAtom(revision, localId);
	const detached = (revision: RevisionTag | null, localId: number) =>
		detachedRegister(id(revision, localId));
	const set = (wasEmpty: boolean, fill: FixtureAtom, detachId: FixtureAtom) =>
		fixtureChange([], [], fixtureReplacement(wasEmpty, detachedRegister(fill), detachId));
	const clear = (wasEmpty: boolean, detachId: FixtureAtom) =>
		fixtureChange([], [], fixtureReplacement(wasEmpty, null, detachId));
	const child = (register: FixtureRegister, node: FixtureAtom) =>
		fixtureChange([], [[register, node]]);
	const move = (src: FixtureAtom, dst: FixtureAtom) => fixtureChange([[src, dst]]);
	const callback = (
		input: FixtureAtom | null,
		over: FixtureAtom | null,
		result: FixtureAtom | null,
		state?: "attached" | "detached",
	) => ({ input, over, ...(state === undefined ? {} : { state }), result });
	const scenario = (
		scenarioId: string,
		changes: Record<string, FixtureChange>,
		actions: FixtureAction[],
		forest?: FieldScenario["forest"],
	): FieldScenario => ({ id: scenarioId, changes, actions, ...(forest === undefined ? {} : { forest }) });
	const forest = (
		initialRoot: ForestInput["initialRoot"],
		builds: ForestInput["builds"],
	): ForestInput => ({
		schema: { rootField: "root", cardinality: "optional", values: "json-compatible" },
		initialRoot,
		builds,
		detachedRegisters: builds,
	});

	const setEmptyA = set(true, id(a, 10), id(a, 11));
	const setOccupiedA = set(false, id(a, 12), id(a, 13));
	const setEmptyB = set(true, id(b, 20), id(b, 21));
	const setOccupiedB = set(false, id(b, 22), id(b, 23));
	const clearEmptyA = clear(true, id(a, 30));
	const clearOccupiedA = clear(false, id(a, 31));
	const clearEmptyB = clear(true, id(b, 32));
	const clearOccupiedB = clear(false, id(b, 33));

	return [
		scenario("edit-empty", {}, [
			{ id: "set-empty", op: "set", result: "set", wasEmpty: true, fill: id(a, 10), detach: id(a, 11) },
		]),
		scenario("edit-occupied", {}, [
			{ id: "set-occupied", op: "set", result: "set", wasEmpty: false, fill: id(a, 12), detach: id(a, 13) },
		]),
		scenario("clear-empty", {}, [
			{ id: "clear-empty", op: "clear", result: "clear", wasEmpty: true, detach: id(a, 30) },
		]),
		scenario("clear-occupied", {}, [
			{ id: "clear-occupied", op: "clear", result: "clear", wasEmpty: false, detach: id(a, 31) },
		]),
		scenario("compose-set-set", { first: setEmptyA, second: setOccupiedB }, [
			{ id: "compose", op: "compose", result: "composed", left: "first", right: "second", callbacks: [] },
		]),
		scenario("compose-set-clear", { first: setEmptyA, second: clearOccupiedB }, [
			{ id: "compose", op: "compose", result: "composed", left: "first", right: "second", callbacks: [] },
		]),
		scenario("compose-clear-set", { first: clearOccupiedA, second: setEmptyB }, [
			{ id: "compose", op: "compose", result: "composed", left: "first", right: "second", callbacks: [] },
		]),
		scenario("compose-clear-clear", { first: clearOccupiedA, second: clearEmptyB }, [
			{ id: "compose", op: "compose", result: "composed", left: "first", right: "second", callbacks: [] },
		]),
		scenario("compose-child-both", {
			first: fixtureChange([], [[detached(a, 40), id(a, 140)]],
				fixtureReplacement(true, detached(a, 40), id(a, 41))),
			second: child(activeRegister, id(b, 141)),
		}, [
			{ id: "compose", op: "compose", result: "composed", left: "first", right: "second",
				callbacks: [callback(id(a, 140), id(b, 141), id(b, 142))] },
		]),
		scenario("compose-child-first", { first: child(activeRegister, id(a, 143)), second: fixtureChange() }, [
			{ id: "compose", op: "compose", result: "composed", left: "first", right: "second",
				callbacks: [callback(id(a, 143), null, id(a, 144))] },
		]),
		scenario("compose-child-second", { first: fixtureChange(), second: child(activeRegister, id(b, 145)) }, [
			{ id: "compose", op: "compose", result: "composed", left: "first", right: "second",
				callbacks: [callback(null, id(b, 145), id(b, 146))] },
		]),
		scenario("compose-move-chain", {
			first: move(id(a, 50), id(a, 51)),
			second: move(id(a, 51), id(b, 52)),
		}, [
			{ id: "compose", op: "compose", result: "composed", left: "first", right: "second", callbacks: [] },
		]),
		scenario("compose-revive", {
			first: set(true, id(a, 53), id(a, 54)),
			second: fixtureChange([], [], fixtureReplacement(false, detached(a, 54), id(b, 55))),
		}, [
			{ id: "compose", op: "compose", result: "composed", left: "first", right: "second", callbacks: [] },
		]),
		scenario("compose-pin", {
			first: setOccupiedA,
			second: fixtureChange([], [], fixtureReplacement(false, activeRegister, id(b, 56))),
		}, [
			{ id: "compose", op: "compose", result: "composed", left: "first", right: "second", callbacks: [] },
		]),
		scenario("compose-ordering", {
			first: fixtureChange([
				[id(a, 60), id(a, 61)],
				[id(b, 60), id(b, 61)],
				[id(a, 62), id(a, 63)],
			]),
			second: move(id(a, 61), id(b, 64)),
		}, [
			{ id: "compose", op: "compose", result: "composed", left: "first", right: "second", callbacks: [] },
		]),
		scenario("invert-set-rollback", { change: setOccupiedA }, [
			{ id: "invert", op: "invert", result: "inverse", change: "change", isRollback: true,
				inverseRevision: inverse as number, lastLocalId: 200 },
		]),
		scenario("invert-set-undo", { change: setOccupiedA }, [
			{ id: "invert", op: "invert", result: "inverse", change: "change", isRollback: false,
				inverseRevision: inverse as number, lastLocalId: 200 },
		]),
		scenario("invert-clear", { change: clearOccupiedA }, [
			{ id: "invert", op: "invert", result: "inverse", change: "change", isRollback: false,
				inverseRevision: inverse as number, lastLocalId: 201 },
		]),
		scenario("invert-pin", {
			change: fixtureChange([], [], fixtureReplacement(false, activeRegister, id(a, 70))),
		}, [
			{ id: "invert", op: "invert", result: "inverse", change: "change", isRollback: false,
				inverseRevision: inverse as number, lastLocalId: 202 },
		]),
		scenario("invert-empty-clear", { change: clearEmptyA }, [
			{ id: "invert", op: "invert", result: "inverse", change: "change", isRollback: false,
				inverseRevision: inverse as number, lastLocalId: 203 },
		]),
		scenario("rebase-set-set-orders", { first: setEmptyA, second: setEmptyB }, [
			{ id: "first-over-second", op: "rebase", result: "firstOverSecond", change: "first", over: "second", callbacks: [] },
			{ id: "second-over-first", op: "rebase", result: "secondOverFirst", change: "second", over: "first", callbacks: [] },
		]),
		scenario("rebase-set-clear-orders", { set: setEmptyA, clear: clearEmptyB }, [
			{ id: "set-over-clear", op: "rebase", result: "setOverClear", change: "set", over: "clear", callbacks: [] },
			{ id: "clear-over-set", op: "rebase", result: "clearOverSet", change: "clear", over: "set", callbacks: [] },
		]),
		scenario("rebase-clear-clear", { first: clearOccupiedA, second: clearOccupiedB }, [
			{ id: "rebase", op: "rebase", result: "rebased", change: "first", over: "second", callbacks: [] },
		]),
		scenario("rebase-child-both", {
			change: child(activeRegister, id(a, 150)),
			over: child(activeRegister, id(b, 151)),
		}, [
			{ id: "rebase", op: "rebase", result: "rebased", change: "change", over: "over",
				callbacks: [callback(id(a, 150), id(b, 151), id(b, 152), "attached")] },
		]),
		scenario("rebase-child-first", { change: child(activeRegister, id(a, 153)), over: fixtureChange() }, [
			{ id: "rebase", op: "rebase", result: "rebased", change: "change", over: "over",
				callbacks: [callback(id(a, 153), null, id(a, 154), "attached")] },
		]),
		scenario("rebase-child-base-only", { change: fixtureChange(), over: child(activeRegister, id(b, 155)) }, [
			{ id: "rebase", op: "rebase", result: "rebased", change: "change", over: "over",
				callbacks: [callback(null, id(b, 155), id(b, 156), "attached")] },
		]),
		scenario("rebase-child-drop", {
			change: child(detached(a, 80), id(a, 157)),
			over: child(detached(a, 80), id(b, 158)),
		}, [
			{ id: "rebase", op: "rebase", result: "rebased", change: "change", over: "over",
				callbacks: [callback(id(a, 157), id(b, 158), null, "detached")] },
		]),
		scenario("rebase-remove-revive", {
			change: child(activeRegister, id(a, 160)),
			over: clearOccupiedB,
		}, [
			{ id: "remove", op: "rebase", result: "removed", change: "change", over: "over",
				callbacks: [callback(id(a, 160), null, id(a, 161), "detached")] },
			{ id: "revive", op: "rebase", result: "revived", change: "removed", over: "over",
				callbacks: [callback(id(a, 161), null, id(a, 162), "detached")] },
		]),
		scenario("rebase-empty-reservation", { change: setEmptyA, over: clearEmptyB }, [
			{ id: "rebase", op: "rebase", result: "rebased", change: "change", over: "over", callbacks: [] },
		]),
		scenario("rebase-pinned-reservation", {
			change: fixtureChange([], [], fixtureReplacement(false, activeRegister, id(a, 81))),
			over: clearEmptyB,
		}, [
			{ id: "rebase", op: "rebase", result: "rebased", change: "change", over: "over", callbacks: [] },
		]),
		scenario("rebase-swap", {
			change: fixtureChange([], [
				[detached(a, 4), id(a, 40)],
				[detached(a, 5), id(a, 41)],
			]),
			over: fixtureChange([
				[id(a, 4), id(a, 5)],
				[id(a, 5), id(a, 4)],
			]),
		}, [
			{ id: "rebase", op: "rebase", result: "rebased", change: "change", over: "over",
				callbacks: [
					callback(id(a, 40), null, id(a, 40), "detached"),
					callback(id(a, 41), null, id(a, 41), "detached"),
				] },
		]),
		scenario("replace-all-identities", {
			change: fixtureChange(
				[[id(a, 90), id(b, 91)]],
				[[detached(a, 92), id(b, 192)], [activeRegister, id(a, 193)]],
				fixtureReplacement(false, detached(b, 93), id(a, 94)),
			),
		}, [
			{ id: "replace", op: "replaceRevisions", result: "replaced", change: "change",
				obsolete: [a as number, b as number], updated: replacement as number },
		]),
		scenario("replace-anonymous", {
			change: fixtureChange(
				[[id(null, 95), id(a, 96)]],
				[[detached(null, 97), id(null, 197)]],
				fixtureReplacement(true, detached(null, 98), id(null, 99)),
			),
		}, [
			{ id: "replace", op: "replaceRevisions", result: "replaced", change: "change",
				obsolete: [null], updated: replacement as number },
		]),
		scenario("replace-unmatched", {
			change: fixtureChange([[id(a, 100), id(b, 101)]], [[activeRegister, id(b, 200)]]),
		}, [
			{ id: "replace", op: "replaceRevisions", result: "replaced", change: "change",
				obsolete: [inverse as number], updated: replacement as number },
		]),
		scenario("delta-local-global", {
			change: fixtureChange(
				[[id(a, 110), id(b, 111)]],
				[[activeRegister, id(a, 210)], [detached(a, 112), id(b, 211)]],
				fixtureReplacement(false, detached(a, 113), id(a, 114)),
			),
		}, [
			{ id: "delta", op: "intoDelta", change: "change", childDeltas: [
				{ node: id(a, 210), fields: [["active-child", { marks: [{ count: 1 }] }]] },
				{ node: id(b, 211), fields: [["detached-child", { marks: [{ count: 1 }] }]] },
			] },
		]),
		scenario("forest-compose", { first: setEmptyA, second: clearOccupiedB }, [
			{ id: "compose", op: "compose", result: "composed", left: "first", right: "second", callbacks: [] },
			{ id: "apply", op: "intoDelta", change: "composed", childDeltas: [], applyToForest: true,
				revision: b as number },
		], forest(
			{ present: false, value: null },
			[{ id: id(a, 10), value: "first" }],
		)),
		scenario("forest-inverse", { change: setOccupiedA }, [
			{ id: "invert", op: "invert", result: "inverse", change: "change", isRollback: true,
				inverseRevision: inverse as number, lastLocalId: 220 },
			{ id: "apply-change", op: "intoDelta", change: "change", childDeltas: [], applyToForest: true,
				revision: a as number },
			{ id: "apply-inverse", op: "intoDelta", change: "inverse", childDeltas: [], applyToForest: true,
				revision: inverse as number },
		], forest({ present: true, value: "old" }, [{ id: id(a, 12), value: "new" }])),
		scenario("forest-null-clear", { change: clearOccupiedA }, [
			{ id: "apply", op: "intoDelta", change: "change", childDeltas: [], applyToForest: true,
				revision: a as number },
		], forest({ present: true, value: null }, [])),
		scenario("law-do-rollback", { change: setEmptyA }, [
			{ id: "inverse", op: "invert", result: "inverse", change: "change", isRollback: true,
				inverseRevision: inverse as number, lastLocalId: 230 },
			{ id: "compose", op: "compose", result: "lawResult", left: "change", right: "inverse", callbacks: [] },
			{ id: "delta", op: "intoDelta", change: "lawResult", childDeltas: [] },
		]),
		scenario("law-do-undo", { change: setOccupiedA }, [
			{ id: "inverse", op: "invert", result: "inverse", change: "change", isRollback: false,
				inverseRevision: inverse as number, lastLocalId: 231 },
			{ id: "compose", op: "compose", result: "lawResult", left: "change", right: "inverse", callbacks: [] },
			{ id: "delta", op: "intoDelta", change: "lawResult", childDeltas: [] },
		]),
		scenario("law-sandwich", { change: setEmptyA, base: clearEmptyB }, [
			{ id: "base-inverse", op: "invert", result: "baseInverse", change: "base", isRollback: true,
				inverseRevision: inverse as number, lastLocalId: 232 },
			{ id: "first", op: "rebase", result: "first", change: "change", over: "base", callbacks: [] },
			{ id: "second", op: "rebase", result: "second", change: "first", over: "baseInverse", callbacks: [] },
			{ id: "third", op: "rebase", result: "lawResult", change: "second", over: "base", callbacks: [] },
		]),
		scenario("law-compose-inverse", { change: clearOccupiedA }, [
			{ id: "inverse", op: "invert", result: "inverse", change: "change", isRollback: true,
				inverseRevision: inverse as number, lastLocalId: 233 },
			{ id: "forward", op: "compose", result: "forward", left: "change", right: "inverse", callbacks: [] },
			{ id: "reverse", op: "compose", result: "reverse", left: "inverse", right: "change", callbacks: [] },
			{ id: "forward-delta", op: "intoDelta", change: "forward", childDeltas: [] },
			{ id: "reverse-delta", op: "intoDelta", change: "reverse", childDeltas: [] },
		]),
		scenario("law-associativity", {
			first: setEmptyA,
			second: clearOccupiedB,
			third: set(true, id(inverse, 120), id(inverse, 121)),
		}, [
			{ id: "first-second", op: "compose", result: "firstSecond", left: "first", right: "second", callbacks: [] },
			{ id: "left-associated", op: "compose", result: "left", left: "firstSecond", right: "third", callbacks: [] },
			{ id: "second-third", op: "compose", result: "secondThird", left: "second", right: "third", callbacks: [] },
			{ id: "right-associated", op: "compose", result: "right", left: "first", right: "secondThird", callbacks: [] },
			{ id: "left-delta", op: "intoDelta", change: "left", childDeltas: [] },
			{ id: "right-delta", op: "intoDelta", change: "right", childDeltas: [] },
		]),
	];
}

function sameFixtureValue(left: unknown, right: unknown): boolean {
	return JSON.stringify(left) === JSON.stringify(right);
}

function readActiveField(forest: IEditableForest): { present: boolean; value: JsonCompatibleReadOnly | null } {
	const cursor = forest.allocateCursor("watershed field algebra root");
	try {
		moveToDetachedField(forest, cursor);
		if (!cursor.firstNode()) return { present: false, value: null };
		const value = cursorToJsonObject(cursor);
		assert.equal(cursor.nextNode(), false, "The optional root must contain at most one node.");
		return { present: true, value };
	} finally {
		cursor.free();
	}
}

function fieldForestState(forest: IEditableForest, index: DetachedFieldIndex): object {
	return {
		root: readActiveField(forest),
		detachedRegisters: [...index.entries()].map((entry) => ({
			id: fixtureAtom((entry.id.major ?? null) as RevisionTag | null, entry.id.minor),
			value: readDetachedRegister(forest, index, entry.id),
		})),
	};
}

function rawFieldForestState(forest: IEditableForest, index: DetachedFieldIndex): object {
	return {
		root: readActiveField(forest),
		detachedIndex: [...index.entries()].map((entry) => ({
			id: { major: entry.id.major ?? null, minor: entry.id.minor },
			root: entry.root,
			latestRelevantRevision: entry.latestRelevantRevision ?? null,
		})),
	};
}

function makeFieldForest(scenario: FieldScenario): {
	forest: IEditableForest;
	index: DetachedFieldIndex;
} | undefined {
	if (scenario.forest === undefined) return undefined;
	const forest = buildTestForest({ additionalAsserts: true });
	if (scenario.forest.initialRoot.present) {
		initializeForest(forest, fieldJsonCursor([scenario.forest.initialRoot.value]));
	}
	const index = makeDetachedFieldIndex(`watershed-field-${scenario.id}`);
	if (scenario.forest.builds.length > 0) {
		applyDelta({
			build: scenario.forest.builds.map(({ id, value }) => ({
				id: makeDetachedNodeId(
					id.revision === null ? undefined : id.revision as RevisionTag,
					brand<ChangesetLocalId>(id.localId),
				),
				trees: chunkFromJsonTrees([value]),
			})),
		}, undefined, forest, index);
	}
	assert.deepEqual(
		scenario.forest.detachedRegisters,
		(fieldForestState(forest, index) as {
			detachedRegisters: { id: FixtureAtom; value: JsonCompatible }[];
		}).detachedRegisters,
		`${scenario.id}: initial detached registers`,
	);
	return { forest, index };
}

function runFieldScenario(scenario: FieldScenario): {
	observation: { id: string; checkpoints: object[] };
	raw: { id: string; checkpoints: object[] };
} {
	const changes = new Map<string, OptionalChangeset>(
		Object.entries(scenario.changes).map(([name, change]) => [name, fromFixtureChange(change)]),
	);
	const fieldForest = makeFieldForest(scenario);
	const checkpoints: object[] = [];
	const rawCheckpoints: object[] = [];
	const resolveChange = (name: unknown): OptionalChangeset => {
		assert(typeof name === "string", `${scenario.id}: change reference must be a string.`);
		const value = changes.get(name);
		assert(value !== undefined, `${scenario.id}: unresolved or forward change reference ${name}.`);
		return value;
	};

	for (const action of scenario.actions) {
		let result: OptionalChangeset | undefined;
		let callbacks: object[] | undefined;
		let allocations: object | undefined;
		let delta: ReturnType<typeof optionalFieldIntoDelta> | undefined;
		let forestState: object | undefined;
		const rawCheckpoint: Record<string, unknown> = { id: action.id, op: action.op };

		if (action.op === "set") {
			assert(typeof action.wasEmpty === "boolean");
			result = optionalFieldEditor.set(action.wasEmpty, {
				fill: fromFixtureAtom(action.fill as FixtureAtom),
				detach: fromFixtureAtom(action.detach as FixtureAtom),
			});
		} else if (action.op === "clear") {
			assert(typeof action.wasEmpty === "boolean");
			result = optionalFieldEditor.clear(
				action.wasEmpty,
				fromFixtureAtom(action.detach as FixtureAtom),
			);
		} else if (action.op === "replaceRevisions") {
			const obsolete = action.obsolete as (number | null)[];
			assert(Array.isArray(obsolete));
			result = optionalChangeRebaser.replaceRevisions(
				resolveChange(action.change),
				new DefaultRevisionReplacer(
					action.updated as RevisionTag,
					new Set(obsolete.map((revision) =>
						revision === null ? undefined : revision as RevisionTag)),
				),
			);
		} else if (action.op === "compose") {
			const expectedCallbacks = action.callbacks as {
				input: FixtureAtom | null;
				over: FixtureAtom | null;
				result: FixtureAtom | null;
			}[];
			assert(Array.isArray(expectedCallbacks));
			callbacks = [];
			let callbackIndex = 0;
			result = optionalChangeRebaser.compose(
				resolveChange(action.left),
				resolveChange(action.right),
				(input, over) => {
					const actual = {
						input: input === undefined ? null : toFixtureAtom(input),
						over: over === undefined ? null : toFixtureAtom(over),
					};
					const expected = expectedCallbacks[callbackIndex];
					assert(expected !== undefined
						&& sameFixtureValue(actual.input, expected.input)
						&& sameFixtureValue(actual.over, expected.over),
					`${scenario.id}.${action.id}: unexpected compose callback.`);
					assert(expected.result !== null,
						`${scenario.id}.${action.id}: compose callbacks must return a node.`);
					const returned = fromFixtureAtom(expected.result);
					callbacks?.push({ ...actual, result: expected.result });
					callbackIndex += 1;
					return returned;
				},
				idAllocatorFromMaxId(),
				failCrossFieldManager,
				revisionMetadataSourceFromInfo([]),
			);
			assert.equal(callbackIndex, expectedCallbacks.length,
				`${scenario.id}.${action.id}: missing compose callback.`);
		} else if (action.op === "invert") {
			const allocated: number[] = [];
			const delegate = new DefaultAtomIdAliasAllocator();
			const lastLocalId = action.lastLocalId as number;
			if (lastLocalId >= 0) delegate.allocate(lastLocalId + 1);
			const allocator = {
				allocate: (count = 1) => {
					const value = delegate.allocate(count);
					allocated.push(value);
					return value;
				},
				getMaxId: () => delegate.getMaxId(),
				reserve: (
					originalRevision: RevisionTag | undefined,
					originalMaxLocalId: ChangesetLocalId,
				) => delegate.reserve(originalRevision, originalMaxLocalId),
				getAlias: (
					originalRevision: RevisionTag | undefined,
					originalLocalId: ChangesetLocalId,
				) => delegate.getAlias(originalRevision, originalLocalId),
			};
			result = optionalChangeRebaser.invert(
				resolveChange(action.change),
				action.isRollback as boolean,
				allocator,
				action.inverseRevision as RevisionTag,
				failCrossFieldManager,
				revisionMetadataSourceFromInfo([]),
			);
			allocations = {
				start: lastLocalId,
				allocated,
				end: allocator.getMaxId(),
			};
		} else if (action.op === "rebase") {
			const expectedCallbacks = action.callbacks as {
				input: FixtureAtom | null;
				over: FixtureAtom | null;
				state: "attached" | "detached";
				result: FixtureAtom | null;
			}[];
			assert(Array.isArray(expectedCallbacks));
			callbacks = [];
			let callbackIndex = 0;
			result = optionalChangeRebaser.rebase(
				resolveChange(action.change),
				resolveChange(action.over),
				(input, over, state) => {
					const actual = {
						input: input === undefined ? null : toFixtureAtom(input),
						over: over === undefined ? null : toFixtureAtom(over),
						state: state === 0 ? "attached" : "detached",
					};
					const expected = expectedCallbacks[callbackIndex];
					assert(expected !== undefined
						&& sameFixtureValue(actual.input, expected.input)
						&& sameFixtureValue(actual.over, expected.over)
						&& actual.state === expected.state,
					`${scenario.id}.${action.id}: unexpected rebase callback.`);
					const returned = expected.result === null ? undefined : fromFixtureAtom(expected.result);
					callbacks?.push({ ...actual, result: expected.result });
					callbackIndex += 1;
					return returned;
				},
				idAllocatorFromMaxId(),
				failCrossFieldManager,
				rebaseRevisionMetadataFromInfo([], undefined, []),
			);
			assert.equal(callbackIndex, expectedCallbacks.length,
				`${scenario.id}.${action.id}: missing rebase callback.`);
		} else {
			assert.equal(action.op, "intoDelta");
			const childDeltas = action.childDeltas as { node: FixtureAtom; fields: [string, object][] }[];
			assert(Array.isArray(childDeltas));
			let childIndex = 0;
			delta = optionalFieldIntoDelta(resolveChange(action.change), (node) => {
				const expected = childDeltas[childIndex];
				assert(expected !== undefined && sameFixtureValue(toFixtureAtom(node), expected.node),
					`${scenario.id}.${action.id}: unexpected child delta callback.`);
				childIndex += 1;
				return fromFixtureFieldMap(expected.fields);
			});
			assert.equal(childIndex, childDeltas.length,
				`${scenario.id}.${action.id}: missing child delta callback.`);
			rawCheckpoint.delta = rawFieldDelta(delta);
			if (action.applyToForest === true) {
				assert(fieldForest !== undefined,
					`${scenario.id}.${action.id}: forest application without forest input.`);
				const rootDelta: DeltaRoot = {
					...(delta.local === undefined
						? {}
						: { fields: new Map([[rootFieldKey, delta.local]]) }),
					...(delta.global === undefined ? {} : { global: delta.global }),
					...(delta.rename === undefined ? {} : { rename: delta.rename }),
				};
				try {
					applyDelta(
						rootDelta,
						action.revision as RevisionTag,
						fieldForest.forest,
						fieldForest.index,
					);
				} catch (error) {
					throw new Error(`${scenario.id}.${action.id}: field delta application failed`, {
						cause: error,
					});
				}
				forestState = fieldForestState(fieldForest.forest, fieldForest.index);
				rawCheckpoint.forest = rawFieldForestState(fieldForest.forest, fieldForest.index);
			}
		}

		if (result !== undefined) {
			assert(typeof action.result === "string" && action.result.length > 0,
				`${scenario.id}.${action.id}: result name is required.`);
			assert(!changes.has(action.result),
				`${scenario.id}.${action.id}: duplicate result name ${action.result}.`);
			changes.set(action.result, result);
			rawCheckpoint.change = result;
		}
		if (callbacks !== undefined) rawCheckpoint.callbacks = callbacks;
		if (allocations !== undefined) rawCheckpoint.allocations = allocations;
		checkpoints.push({
			id: action.id,
			...(result === undefined ? {} : { result: toFixtureChange(result) }),
			...(callbacks === undefined ? {} : { callbacks }),
			...(allocations === undefined ? {} : { allocations }),
			...(delta === undefined ? {} : { delta: toFixtureDelta(delta) }),
			...(forestState === undefined ? {} : { forest: forestState }),
		});
		rawCheckpoints.push(rawCheckpoint);
	}

	return {
		observation: { id: scenario.id, checkpoints },
		raw: { id: scenario.id, checkpoints: rawCheckpoints },
	};
}

function expandFieldCase(value: OracleCase): OracleCase {
	const input = value.input as {
		revisions: Record<string, RevisionTag>;
		[key: string]: unknown;
	};
	const revisions = [
		input.revisions.first,
		input.revisions.second,
		input.revisions.inverse,
		input.revisions.replacement,
	];
	const scenarios = fieldScenarios(revisions);
	const captures = scenarios.map(runFieldScenario);
	const checkpoint = (scenarioId: string, actionId: string): Record<string, unknown> => {
		const scenario = captures.find(({ observation }) => observation.id === scenarioId);
		assert(scenario !== undefined, `Missing law scenario ${scenarioId}.`);
		const value = scenario.observation.checkpoints.find((item) =>
			(item as { id?: string }).id === actionId);
		assert(value !== undefined, `Missing law checkpoint ${scenarioId}.${actionId}.`);
		return value as Record<string, unknown>;
	};
	for (const scenarioId of ["law-do-rollback", "law-do-undo"]) {
		assert.equal((checkpoint(scenarioId, "delta").delta as { local: unknown }).local, null,
			`${scenarioId}: composed inverse must have no visible local delta.`);
	}
	assert.deepEqual(
		checkpoint("law-sandwich", "first").result,
		checkpoint("law-sandwich", "third").result,
		"law-sandwich: rebasing over inverse and original must restore the first rebase.",
	);
	assert.equal(
		(checkpoint("law-compose-inverse", "forward-delta").delta as { local: unknown }).local,
		null,
		"law-compose-inverse: forward composition must have no visible local delta.",
	);
	assert.equal(
		(checkpoint("law-compose-inverse", "reverse-delta").delta as { local: unknown }).local,
		null,
		"law-compose-inverse: reverse composition must have no visible local delta.",
	);
	assert.deepEqual(
		checkpoint("law-associativity", "left-delta").delta,
		checkpoint("law-associativity", "right-delta").delta,
		"law-associativity: both groupings must produce the same delta.",
	);
	const revisionTable = revisions.map((revision) => ({
		revision: revision as number,
		stableId: testIdCompressor.decompress(revision as SessionSpaceCompressedId),
	}));
	return {
		...value,
		input: { ...input, revisionTable, scenarios },
		expected: {
			...value.expected,
			scenarios: captures.map(({ observation }) => observation),
		},
		raw: {
			...(value.raw as object),
			scenarios: captures.map(({ raw }) => raw),
		},
	};
}

function makeFieldCase(commit: string): OracleCase {
	const revisionA = mintRevisionTag();
	const revisionB = mintRevisionTag();
	const revisionInverse = mintRevisionTag();
	const revisionReplacement = mintRevisionTag();
	const metadata = rebaseRevisionMetadataFromInfo(
		[{ revision: revisionA }, { revision: revisionB }],
		revisionB,
		[revisionA],
	);

	const setOptional = optionalFieldEditor.set(true, {
		fill: atom(revisionA, 0),
		detach: atom(revisionA, 1),
	});
	const setRequired = requiredFieldEditor.set({
		fill: atom(revisionB, 2),
		detach: atom(revisionB, 3),
	});
	const clearPresent = optionalFieldEditor.clear(false, atom(revisionA, 6));
	const clearAbsent = optionalFieldEditor.clear(true, atom(revisionA, 7));
	const activeSourceNoop: OptionalChangeset = {
		moves: [],
		childChanges: [],
		valueReplace: {
			isEmpty: false,
			src: "self",
			dst: atom(revisionA, 8),
		},
	};
	const childThenClear: OptionalChangeset = {
		moves: [],
		childChanges: [["self", atom(revisionA, 40)]],
		valueReplace: {
			isEmpty: false,
			dst: atom(revisionA, 9),
		},
	};
	const childOnClearedRegister: OptionalChangeset = {
		moves: [],
		childChanges: [[atom(revisionA, 9), atom(revisionB, 41)]],
	};
	const baseChildThenClear: OptionalChangeset = {
		moves: [],
		childChanges: [["self", atom(revisionA, 42)]],
		valueReplace: {
			isEmpty: false,
			dst: atom(revisionA, 10),
		},
	};
	const authoredChild: OptionalChangeset = {
		moves: [],
		childChanges: [["self", atom(revisionB, 43)]],
	};
	const richRevisionChange: OptionalChangeset = {
		moves: [[atom(revisionA, 11), atom(revisionB, 12)]],
		childChanges: [[atom(revisionA, 13), atom(revisionB, 44)]],
		valueReplace: {
			isEmpty: false,
			src: atom(revisionB, 14),
			dst: atom(revisionA, 15),
		},
	};
	const swap: OptionalChangeset = {
		moves: [
			[atom(revisionA, 4), atom(revisionA, 5)],
			[atom(revisionA, 5), atom(revisionA, 4)],
		],
		childChanges: [],
	};
	const directSwap = applyDirectSimultaneousSwap(revisionA, swap);
	const algebraSwap = rebaseChildrenThroughSimultaneousSwap(revisionA, swap, metadata);

	const composed = optionalChangeRebaser.compose(
		setOptional,
		setRequired,
		(left, right) => left ?? right ?? assert.fail("A child change is required."),
		idAllocatorFromMaxId(),
		failCrossFieldManager,
		metadata,
	);
	const inverted = optionalChangeRebaser.invert(
		composed,
		false,
		new DefaultAtomIdAliasAllocator(),
		revisionInverse,
		failCrossFieldManager,
		metadata,
	);
	const rebased = optionalChangeRebaser.rebase(
		setRequired,
		setOptional,
		(change) => change,
		idAllocatorFromMaxId(),
		failCrossFieldManager,
		metadata,
	);
	const replaced = optionalChangeRebaser.replaceRevisions(
		swap,
		new DefaultRevisionReplacer(revisionReplacement, new Set([revisionA, revisionB])),
	);
	const replacedRich = optionalChangeRebaser.replaceRevisions(
		richRevisionChange,
		new DefaultRevisionReplacer(revisionReplacement, new Set([revisionA, revisionB])),
	);

	const revisionTagCodec = new RevisionTagCodec(testIdCompressor);
	const optionalCodec = optionalChangeHandler.codecsFactory(revisionTagCodec).resolve(2);
	const requiredCodec = requiredFieldChangeHandler.codecsFactory(revisionTagCodec).resolve(2);
	const encodeOptional = (change: OptionalChangeset, revision: RevisionTag) =>
		optionalCodec.encode(change, fieldEncodingContext(revision, true));
	const composeCases = [
		{
			id: "set-set-forward",
			first: setOptional,
			firstRevision: revisionA,
			second: setRequired,
			secondRevision: revisionB,
			outputRevision: revisionB,
		},
		{
			id: "set-set-reverse",
			first: setRequired,
			firstRevision: revisionB,
			second: setOptional,
			secondRevision: revisionA,
			outputRevision: revisionA,
		},
		{
			id: "set-clear",
			first: setRequired,
			firstRevision: revisionB,
			second: clearPresent,
			secondRevision: revisionA,
			outputRevision: revisionA,
		},
		{
			id: "clear-set",
			first: clearPresent,
			firstRevision: revisionA,
			second: setRequired,
			secondRevision: revisionB,
			outputRevision: revisionB,
		},
		{
			id: "absent-clear-set",
			first: clearAbsent,
			firstRevision: revisionA,
			second: setOptional,
			secondRevision: revisionA,
			outputRevision: revisionA,
		},
	];
	const composeObservations = composeCases.map((scenario) => {
		const callbacks: object[] = [];
		const result = optionalChangeRebaser.compose(
			scenario.first,
			scenario.second,
			(first, second) => {
				callbacks.push({ first: first ?? null, second: second ?? null });
				return first ?? second ?? assert.fail("A child change is required.");
			},
			idAllocatorFromMaxId(),
			failCrossFieldManager,
			metadata,
		);
		return {
			operation: "compose-expanded",
			id: scenario.id,
			encoded: encodeOptional(result, scenario.outputRevision),
			callbacks,
		};
	});

	const overlapComposeCallbacks: object[] = [];
	const overlapComposeResult = optionalChangeRebaser.compose(
		childThenClear,
		childOnClearedRegister,
		(first, second) => {
			overlapComposeCallbacks.push({
				first: first ?? null,
				second: second ?? null,
			});
			return atom(revisionInverse, 45);
		},
		idAllocatorFromMaxId(),
		failCrossFieldManager,
		metadata,
	);

	const invertCases = [
		{
			id: "set-rollback",
			change: setRequired,
			changeRevision: revisionB,
			isRollback: true,
			maxLocalId: 20,
		},
		{
			id: "set-undo",
			change: setRequired,
			changeRevision: revisionB,
			isRollback: false,
			maxLocalId: 20,
		},
		{
			id: "clear-rollback",
			change: clearPresent,
			changeRevision: revisionA,
			isRollback: true,
			maxLocalId: 20,
		},
		{
			id: "clear-undo",
			change: clearPresent,
			changeRevision: revisionA,
			isRollback: false,
			maxLocalId: 20,
		},
		{
			id: "active-source-noop-rollback",
			change: activeSourceNoop,
			changeRevision: revisionA,
			isRollback: true,
			maxLocalId: 20,
		},
		{
			id: "active-source-noop-undo",
			change: activeSourceNoop,
			changeRevision: revisionA,
			isRollback: false,
			maxLocalId: 20,
		},
	];
	const invertObservations = invertCases.map((scenario) => {
		const allocator = idAllocatorFromMaxId(scenario.maxLocalId);
		const result = optionalChangeRebaser.invert(
			scenario.change,
			scenario.isRollback,
			allocator,
			revisionInverse,
			failCrossFieldManager,
			metadata,
		);
		return {
			operation: "invert-expanded",
			id: scenario.id,
			encoded: encodeOptional(result, revisionInverse),
			allocator: {
				before: scenario.maxLocalId,
				after: allocator.getMaxId(),
			},
		};
	});

	const rebaseCases = [
		{
			id: "authored-child-over-clear",
			change: authoredChild,
			changeRevision: revisionB,
			over: clearPresent,
			overRevision: revisionA,
		},
		{
			id: "base-only-child-over-clear",
			change: { moves: [], childChanges: [] } satisfies OptionalChangeset,
			changeRevision: revisionB,
			over: baseChildThenClear,
			overRevision: revisionA,
		},
		{
			id: "both-children",
			change: authoredChild,
			changeRevision: revisionB,
			over: {
				moves: [],
				childChanges: [["self", atom(revisionA, 46)]],
			} satisfies OptionalChangeset,
			overRevision: revisionA,
		},
	];
	const rebaseObservations = rebaseCases.map((scenario) => {
		const callbacks: object[] = [];
		const result = optionalChangeRebaser.rebase(
			scenario.change,
			scenario.over,
			(change, over, state) => {
				callbacks.push({
					change: change ?? null,
					over: over ?? null,
					attachState:
						state === NodeAttachState.Attached ? "attached" : "detached",
				});
				return change ?? over;
			},
			idAllocatorFromMaxId(),
			failCrossFieldManager,
			metadata,
		);
		return {
			operation: "rebase-expanded",
			id: scenario.id,
			encoded: encodeOptional(result, scenario.changeRevision),
			callbacks,
		};
	});

	const childDelta = optionalFieldIntoDelta(
		{
			moves: [[atom(revisionA, 16), atom(revisionB, 17)]],
			childChanges: [
				["self", atom(revisionA, 47)],
				[atom(revisionA, 18), atom(revisionB, 48)],
			],
			valueReplace: {
				isEmpty: false,
				src: atom(revisionB, 19),
				dst: atom(revisionA, 20),
			},
		},
		(child) =>
			new Map([
				[
					fieldKey("child"),
					{
						marks: [{ count: child.localId }],
					},
				],
			]),
	);
	const childDeltaObservation = {
		local:
			childDelta.local === undefined
				? null
				: {
						marks: childDelta.local.marks.map((mark) => ({
							count: mark.count,
							attach: mark.attach ?? null,
							detach: mark.detach ?? null,
							fields:
								mark.fields === undefined
									? []
									: [...mark.fields].map(([key, change]) => [
											key,
											{
												marks: change.marks.map((nested) => ({
													count: nested.count,
													attach: nested.attach ?? null,
													detach: nested.detach ?? null,
												})),
											},
										]),
						})),
					},
		global:
			childDelta.global?.map((change) => ({
				id: change.id,
				fields: [...change.fields].map(([key, fieldChange]) => [
					key,
					{
						marks: fieldChange.marks.map((mark) => ({
							count: mark.count,
							attach: mark.attach ?? null,
							detach: mark.detach ?? null,
						})),
					},
				]),
			})) ?? [],
		rename: childDelta.rename ?? [],
	};
	const encoded = {
		optional: optionalCodec.encode(setOptional, fieldEncodingContext(revisionA)),
		required: requiredCodec.encode(setRequired, fieldEncodingContext(revisionB)),
		compose: optionalCodec.encode(composed, fieldEncodingContext(revisionB)),
		invert: optionalCodec.encode(inverted, fieldEncodingContext(revisionInverse)),
		rebase: optionalCodec.encode(rebased, fieldEncodingContext(revisionB)),
		swap: optionalCodec.encode(swap, fieldEncodingContext(revisionA)),
		replacedSwap: encodeOptional(replaced, revisionReplacement),
		replacedRich: encodeOptional(replacedRich, revisionReplacement),
		clearPresent: encodeOptional(clearPresent, revisionA),
		clearAbsent: encodeOptional(clearAbsent, revisionA),
		activeSourceNoop: encodeOptional(activeSourceNoop, revisionA),
		childThenClear: encodeOptional(childThenClear, revisionA),
		childOnClearedRegister: encodeOptional(childOnClearedRegister, revisionB),
		baseChildThenClear: encodeOptional(baseChildThenClear, revisionA),
		authoredChild: encodeOptional(authoredChild, revisionB),
		richRevisionChange: encodeOptional(richRevisionChange, revisionB),
	};

	const observations: (JsonCompatibleReadOnly | object)[] = [
		{ operation: "compose", encoded: encoded.compose },
		{ operation: "invert", encoded: encoded.invert },
		{ operation: "rebase", encoded: encoded.rebase },
		{ operation: "simultaneous-swap", encoded: encoded.swap },
		directSwap.observation,
		algebraSwap.observation,
		{ operation: "replace-revisions", encoded: encoded.replacedSwap },
		...composeObservations,
		{
			operation: "compose-expanded",
			id: "overlapping-children",
			encoded: encodeOptional(overlapComposeResult, revisionInverse),
			callbacks: overlapComposeCallbacks,
		},
		...invertObservations,
		...rebaseObservations,
		{
			operation: "into-delta-expanded",
			delta: childDeltaObservation,
		},
		{
			operation: "replace-revisions-expanded",
			id: "all-atom-positions",
			encoded: encoded.replacedRich,
		},
	];

	return {
		formatVersion,
		reference: reference(commit),
		id: "field-compose-invert-rebase",
		domain: "field",
		input: {
			codecs: { optional: 2, required: 2 },
			revisions: {
				first: revisionA,
				second: revisionB,
				inverse: revisionInverse,
				replacement: revisionReplacement,
			},
			changes: {
				optional: encoded.optional,
				required: encoded.required,
				swap: encoded.swap,
			},
			operations: {
				compose: {
					left: "optional",
					right: "required",
					revisionMetadata: {
						revisions: [revisionA, revisionB],
						base: revisionB,
						rollbackRevisions: [revisionA],
					},
				},
				invert: {
					change: "compose",
					isRollback: false,
					inverseRevision: revisionInverse,
				},
				rebase: {
					change: "required",
					over: "optional",
				},
				replaceRevisions: {
					change: "swap",
					obsolete: [revisionA, revisionB],
					updated: revisionReplacement,
				},
			},
			expanded: {
				changes: {
					clearPresent: {
						revision: revisionA,
						data: encoded.clearPresent,
					},
					clearAbsent: {
						revision: revisionA,
						data: encoded.clearAbsent,
					},
					activeSourceNoop: {
						revision: revisionA,
						data: encoded.activeSourceNoop,
					},
					childThenClear: {
						revision: revisionA,
						data: encoded.childThenClear,
					},
					childOnClearedRegister: {
						revision: revisionB,
						data: encoded.childOnClearedRegister,
					},
					baseChildThenClear: {
						revision: revisionA,
						data: encoded.baseChildThenClear,
					},
					authoredChild: {
						revision: revisionB,
						data: encoded.authoredChild,
					},
					richRevisionChange: {
						revision: revisionB,
						data: encoded.richRevisionChange,
					},
				},
				compose: [
					...composeCases.map((scenario) => ({
						id: scenario.id,
						first: {
							revision: scenario.firstRevision,
							data: encodeOptional(scenario.first, scenario.firstRevision),
						},
						second: {
							revision: scenario.secondRevision,
							data: encodeOptional(scenario.second, scenario.secondRevision),
						},
						outputRevision: scenario.outputRevision,
						childCallback: { selector: "prefer-first-then-second" },
					})),
					{
						id: "overlapping-children",
						first: {
							revision: revisionA,
							data: encoded.childThenClear,
						},
						second: {
							revision: revisionB,
							data: encoded.childOnClearedRegister,
						},
						outputRevision: revisionInverse,
						childCallback: {
							selector: "constant",
							result: atom(revisionInverse, 45),
						},
					},
				],
				invert: invertCases.map((scenario) => ({
					id: scenario.id,
					change: {
						revision: scenario.changeRevision,
						data: encodeOptional(scenario.change, scenario.changeRevision),
					},
					isRollback: scenario.isRollback,
					inverseRevision: revisionInverse,
					maxLocalId: scenario.maxLocalId,
				})),
				rebase: rebaseCases.map((scenario) => ({
					id: scenario.id,
					change: {
						revision: scenario.changeRevision,
						data: encodeOptional(scenario.change, scenario.changeRevision),
					},
					over: {
						revision: scenario.overRevision,
						data: encodeOptional(scenario.over, scenario.overRevision),
					},
					outputRevision: scenario.changeRevision,
					childCallback: { selector: "prefer-change-then-base" },
				})),
				intoDelta: {
					change: {
						revision: revisionB,
						data: encodeOptional(
							{
								moves: [[atom(revisionA, 16), atom(revisionB, 17)]],
								childChanges: [
									["self", atom(revisionA, 47)],
									[atom(revisionA, 18), atom(revisionB, 48)],
								],
								valueReplace: {
									isEmpty: false,
									src: atom(revisionB, 19),
									dst: atom(revisionA, 20),
								},
							},
							revisionB,
						),
					},
					childDelta: {
						selector: "local-id-count",
						field: "child",
					},
				},
				replaceRevisions: {
					id: "all-atom-positions",
					change: {
						revision: revisionB,
						data: encoded.richRevisionChange,
					},
					obsolete: [revisionA, revisionB],
					updated: revisionReplacement,
					outputRevision: revisionReplacement,
				},
				invalidMappings: [
					{
						id: "duplicate-move-source",
						change: {
							moves: [
								[atom(revisionA, 30), atom(revisionA, 31)],
								[atom(revisionA, 30), atom(revisionA, 32)],
							],
							childChanges: [],
						},
					},
					{
						id: "duplicate-move-destination",
						change: {
							moves: [
								[atom(revisionA, 33), atom(revisionA, 35)],
								[atom(revisionA, 34), atom(revisionA, 35)],
							],
							childChanges: [],
						},
					},
					{
						id: "duplicate-child-register",
						change: {
							moves: [],
							childChanges: [
								["self", atom(revisionA, 49)],
								["self", atom(revisionB, 50)],
							],
						},
					},
				],
			},
			swapApplication: directSwap.input,
			swapAlgebra: algebraSwap.input,
		},
		expected: { observations },
		raw: {
			changes: {
				setOptional,
				setRequired,
				swap,
				composed,
				inverted,
				rebased,
				replaced,
				replacedRich,
				clearPresent,
				clearAbsent,
				activeSourceNoop,
				childThenClear,
				childOnClearedRegister,
				baseChildThenClear,
				authoredChild,
				richRevisionChange,
			},
			encoded,
			swapApplication: directSwap.raw,
			swapAlgebra: algebraSwap.raw,
			revisionReplacement: {
				obsolete: [revisionA, revisionB],
				updated: revisionReplacement,
			},
		},
	};
}

function makeModularFamily(): {
	readonly family: ModularChangeFamily;
	readonly codecOptions: CodecWriteOptions;
} {
	const codecOptions: CodecWriteOptions = {
		jsonValidator: FormatValidatorBasic,
		minVersionForCollab: FluidClientVersion.v2_117,
	};
	const revisionTagCodec = new RevisionTagCodec(testIdCompressor);
	const fieldBatchCodec = fieldBatchCodecBuilder.build(codecOptions);
	const codecs = makeModularChangeCodecFamily(
		fieldKindConfigurations,
		revisionTagCodec,
		fieldBatchCodec,
		codecOptions,
		TreeCompressionStrategy.Compressed,
	);
	return {
		family: new ModularChangeFamily(fieldKinds, codecs, codecOptions),
		codecOptions,
	};
}

function withRootAndNestedChanges(
	revision: RevisionTag,
	rootField: FieldKey,
	nestedField: FieldKey,
	leafField: FieldKey,
	rootNode: NodeId,
	rootAlias: NodeId,
	prunedNode: NodeId,
	fill: ChangeAtomId,
	detach: ChangeAtomId,
	buildId: ChangeAtomId,
	staleRefresherId: ChangeAtomId,
): ModularChangeset {
	const rootChange: OptionalChangeset = {
		...optionalFieldEditor.set(true, { fill, detach }),
		childChanges: [["self", rootAlias]],
	};
	const nestedChange = requiredFieldEditor.set({
		fill: atom(revision, 40),
		detach: atom(revision, 41),
	});
	const emptyNestedChange = optionalFieldEditor.buildChildChanges([[0, prunedNode]]);

	const nodeChanges = newChangeAtomIdBTree([
		[
			nodeKey(rootNode),
			{
				fieldChanges: new Map([
					[
						nestedField,
						{
							fieldKind: required.identifier,
							change: brand<FieldChangeset>(nestedChange),
						},
					],
					[
						leafField,
						{
							fieldKind: optional.identifier,
							change: brand<FieldChangeset>(emptyNestedChange),
						},
					],
				]),
			},
		],
		[nodeKey(prunedNode), {}],
	]);
	const nodeToParent = newChangeAtomIdBTree([
		[nodeKey(rootNode), { nodeId: undefined, field: rootField }],
		[nodeKey(prunedNode), { nodeId: rootNode, field: leafField }],
	]);
	const nodeAliases = newChangeAtomIdBTree([[nodeKey(rootAlias), rootNode]]);
	const builds = newChangeAtomIdBTree([[nodeKey(buildId), chunkFromJsonTrees(["built"])]]);
	const refreshers = newChangeAtomIdBTree([
		[nodeKey(staleRefresherId), chunkFromJsonTrees(["stale"])],
	]);

	return makeModularChangeset({
		maxId: 41,
		revisions: [{ revision }],
		fieldChanges: new Map([
			[
				rootField,
				{
					fieldKind: optional.identifier,
					change: brand<FieldChangeset>(rootChange),
				},
			],
		]),
		nodeChanges,
		nodeToParent,
		nodeAliases,
		builds,
		refreshers,
	});
}

function makeModularCase(commit: string): OracleCase {
	const revisionA = mintRevisionTag();
	const revisionB = mintRevisionTag();
	const replacementRevision = mintRevisionTag();
	const rootField = fieldKey("root");
	const nestedField = fieldKey("nested-required");
	const leafField = fieldKey("pruned-optional");
	const rootNode = atom(revisionA, 4);
	const rootAlias = atom(revisionB, 4);
	const prunedNode = atom(revisionA, 5);
	const fill = atom(revisionA, 30);
	const detach = atom(revisionA, 31);
	const buildId = atom(revisionA, 20);
	const staleRefresherId = atom(revisionB, 21);

	const change = withRootAndNestedChanges(
		revisionA,
		rootField,
		nestedField,
		leafField,
		rootNode,
		rootAlias,
		prunedNode,
		fill,
		detach,
		buildId,
		staleRefresherId,
	);
	const second = makeModularChangeset({
		maxId: 51,
		revisions: [{ revision: revisionB }],
		fieldChanges: new Map([
			[
				rootField,
				{
					fieldKind: optional.identifier,
					change: brand<FieldChangeset>(
						optionalFieldEditor.set(false, {
							fill: atom(revisionB, 50),
							detach: atom(revisionB, 51),
						}),
					),
				},
			],
		]),
	});

	const { family, codecOptions } = makeModularFamily();
	const composed = family.compose([
		tagChange(change, revisionA),
		tagChange(second, revisionB),
	]);
	const inverted = family.invert(tagChange(change, revisionA), false, revisionB);
	const rebased = family.rebase(
		tagChange(second, revisionB),
		tagChange(change, revisionA),
		revisionMetadataSourceFromInfo([{ revision: revisionA }, { revision: revisionB }]),
	);
	const replaced = family.changeRevision(
		second,
		new DefaultRevisionReplacer(replacementRevision, new Set([revisionB])),
	);
	const pruned = pruneChangeset(change, fieldKinds);
	const removedRoots = [...relevantRemovedRoots(change)];
	const refresherInputs = removedRoots.map((id) => ({
		id,
		trees: [`refreshed:${id.major ?? "anonymous"}:${id.minor}`],
	}));
	const refreshed = updateRefreshers(
		change,
		(id) => {
			const input = refresherInputs.find(
				(candidate) => candidate.id.major === id.major && candidate.id.minor === id.minor,
			);
			assert(input !== undefined, "The refresher input must exist.");
			return chunkFromJsonTrees(input.trees);
		},
		removedRoots,
	);

	const codec = family.codecs.resolve(ModularChangeFormatVersion.v5);
	const encodingContext: ChangeEncodingContext = {
		originatorId: testIdCompressor.localSessionId,
		idCompressor: testIdCompressor,
		revision: undefined,
		isSummary: false,
	};
	const encoded = {
		input: codec.encode(change, encodingContext),
		second: codec.encode(second, encodingContext),
		compose: codec.encode(composed, encodingContext),
		invert: codec.encode(inverted, encodingContext),
		rebase: codec.encode(rebased, encodingContext),
		replaced: codec.encode(replaced, encodingContext),
		pruned: codec.encode(pruned, encodingContext),
		refreshed: codec.encode(refreshed, encodingContext),
	};

	const observations: (JsonCompatibleReadOnly | object)[] = [
		{ operation: "compose", encoded: encoded.compose },
		{ operation: "invert", encoded: encoded.invert },
		{ operation: "rebase", encoded: encoded.rebase },
		{ operation: "replace-revisions", encoded: encoded.replaced },
		{ operation: "prune", encoded: encoded.pruned },
		{
			operation: "refreshers",
			removedRoots,
			encoded: encoded.refreshed,
		},
	];

	return {
		formatVersion,
		reference: reference(commit),
		id: "modular-nested-algebra",
		domain: "modular",
		input: {
			compiler: FluidClientVersion.v2_117,
			codecs: {
				modular: ModularChangeFormatVersion.v5,
				optional: 2,
				required: 2,
			},
			compression: TreeCompressionStrategy.Compressed,
			oldestCompatibleClient: codecOptions.minVersionForCollab,
			changes: {
				first: encoded.input,
				second: encoded.second,
			},
			revisions: {
				first: revisionA,
				second: revisionB,
				replacement: replacementRevision,
			},
			operations: {
				compose: {
					changes: ["first", "second"],
					revisions: [revisionA, revisionB],
				},
				invert: {
					change: "first",
					revision: revisionA,
					isRollback: false,
					inverseRevision: revisionB,
				},
				rebase: {
					change: "second",
					revision: revisionB,
					over: "first",
					overRevision: revisionA,
					revisionMetadata: [revisionA, revisionB],
				},
				replaceRevisions: {
					change: "second",
					obsolete: [revisionB],
					updated: replacementRevision,
				},
				prune: { change: "first" },
				refreshers: {
					change: "first",
					roots: refresherInputs,
				},
			},
		},
		expected: { observations },
		raw: {
			encoded,
			removedRoots,
			revisionReplacement: {
				obsolete: [revisionB],
				updated: replacementRevision,
			},
			ids: {
				rootNode,
				rootAlias,
				prunedNode,
				fill,
				detach,
				buildId,
				staleRefresherId,
			},
		},
	};
}

describe("watershed upstream algebra oracle", () => {
	it("writes the pinned algebra corpus", () => {
		const output = process.env.WATERSHED_ORACLE_OUTPUT;
		assert(output !== undefined, "WATERSHED_ORACLE_OUTPUT is required.");
		assert(path.isAbsolute(output), "WATERSHED_ORACLE_OUTPUT must be absolute.");
		const commit = process.env.WATERSHED_ORACLE_COMMIT;
		assert.equal(
			commit,
			expectedCommit,
			"WATERSHED_ORACLE_COMMIT must match the pinned Fluid commit.",
		);

		const idCase = makeIdCase(commit);
		const fieldCase = makeFieldCase(commit);
		const modularCase = makeModularCase(commit);
		const cases = [idCase, expandFieldCase(fieldCase), modularCase];
		assert.deepEqual(
			cases.map(({ id, domain }) => ({ id, domain })),
			[
				{ id: "id-ranges", domain: "ids" },
				{ id: "field-compose-invert-rebase", domain: "field" },
				{ id: "modular-nested-algebra", domain: "modular" },
			],
		);
		for (const fixture of cases) {
			assert(fixture.expected.observations.length > 0);
		}

		mkdirSync(output, { recursive: true });
		writeFileSync(
			path.join(output, "algebra-cases.json"),
			`${JSON.stringify(cases, undefined, 2)}\n`,
			"utf8",
		);
	});
});
