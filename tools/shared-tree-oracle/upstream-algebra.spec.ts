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
	tagChange,
	type ChangeAtomId,
	type ChangeEncodingContext,
	type ChangesetLocalId,
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
import { rebaseRevisionMetadataFromInfo } from "../feature-libraries/modular-schema/index.js";
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
import { brand, idAllocatorFromMaxId, type JsonCompatibleReadOnly } from "../util/index.js";
import { cursorToJsonObject } from "./json/index.js";
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
	readonly observation: RefusalObservation & {
		readonly operation: "simultaneous-swap-direct-application-refusal";
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
			...refusal,
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

function fieldEncodingContext(revision: RevisionTag): FieldChangeEncodingContext {
	const baseContext: ChangeEncodingContext = {
		originatorId: testIdCompressor.localSessionId,
		idCompressor: testIdCompressor,
		revision,
		isSummary: false,
	};
	return {
		baseContext,
		encodeNode: () => ({}),
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

	const revisionTagCodec = new RevisionTagCodec(testIdCompressor);
	const optionalCodec = optionalChangeHandler.codecsFactory(revisionTagCodec).resolve(2);
	const requiredCodec = requiredFieldChangeHandler.codecsFactory(revisionTagCodec).resolve(2);
	const encoded = {
		optional: optionalCodec.encode(setOptional, fieldEncodingContext(revisionA)),
		required: requiredCodec.encode(setRequired, fieldEncodingContext(revisionB)),
		compose: optionalCodec.encode(composed, fieldEncodingContext(revisionB)),
		invert: optionalCodec.encode(inverted, fieldEncodingContext(revisionInverse)),
		rebase: optionalCodec.encode(rebased, fieldEncodingContext(revisionB)),
		swap: optionalCodec.encode(swap, fieldEncodingContext(revisionA)),
		replacedSwap: optionalCodec.encode(replaced, fieldEncodingContext(revisionReplacement)),
	};

	const observations: (JsonCompatibleReadOnly | object)[] = [
		{ operation: "compose", encoded: encoded.compose },
		{ operation: "invert", encoded: encoded.invert },
		{ operation: "rebase", encoded: encoded.rebase },
		{ operation: "simultaneous-swap", encoded: encoded.swap },
		directSwap.observation,
		algebraSwap.observation,
		{ operation: "replace-revisions", encoded: encoded.replacedSwap },
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

		const cases = [makeIdCase(commit), makeFieldCase(commit), makeModularCase(commit)];
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
