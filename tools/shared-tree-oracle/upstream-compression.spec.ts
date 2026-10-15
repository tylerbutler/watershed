import { strict as assert } from "node:assert";
import { createHash } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";

import type { IBatchMessage } from "@fluidframework/container-definitions/internal";
import {
	MessageType,
	type ISequencedDocumentMessage,
} from "@fluidframework/driver-definitions/internal";
import { defaultMinVersionForCollab } from "@fluidframework/runtime-utils/internal";
import {
	createMockLoggerExt,
	MockLogger,
} from "@fluidframework/telemetry-utils/internal";
import { compress, decompress } from "lz4js";

import { enabledCompressionConfig } from "../compressionDefinitions.js";
import { ContainerMessageType } from "../messageTypes.js";
import type {
	OutboundBatch,
	OutboundBatchMessage,
	OutboundSingletonBatch,
} from "../opLifecycle/definitions.js";
import { OpCompressor } from "../opLifecycle/opCompressor.js";
import { OpDecompressor } from "../opLifecycle/opDecompressor.js";
import { OpGroupingManager } from "../opLifecycle/opGroupingManager.js";
import { ensureContentsDeserialized } from "../opLifecycle/opSerialization.js";
import { OpSplitter } from "../opLifecycle/opSplitter.js";
import { RemoteMessageProcessor } from "../opLifecycle/remoteMessageProcessor.js";
import {
	DocumentsSchemaController,
	type IDocumentSchema,
	type IDocumentSchemaFeatures,
} from "../summary/documentSchema.js";
import { chunksBlobName, metadataBlobName } from "../summary/summaryFormat.js";

const expectedCommit = "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960";
const minimumBatchSizeInBytes = enabledCompressionConfig.minimumBatchSizeInBytes;
const chunkSizeInBytes = 204800;

type JsonRecord = Record<string, unknown>;

function deterministicBytes(length: number, seed = 0x6d2b79f5): Uint8Array {
	const bytes = new Uint8Array(length);
	let state = seed >>> 0;
	for (let index = 0; index < bytes.length; index++) {
		state ^= state << 13;
		state ^= state >>> 17;
		state ^= state << 5;
		bytes[index] = state & 0xff;
	}
	return bytes;
}

function base64(bytes: Uint8Array): string {
	return Buffer.from(bytes).toString("base64");
}

function canonical(value: unknown): unknown {
	if (Array.isArray(value)) return value.map(canonical);
	if (value !== null && typeof value === "object") {
		return Object.fromEntries(
			Object.entries(value).sort(([left], [right]) => left.localeCompare(right))
				.map(([key, item]) => [key, canonical(item)]),
		);
	}
	return value;
}

function digestJson(value: unknown): string {
	return createHash("sha256").update(JSON.stringify(canonical(value))).digest("hex");
}

function runtimeMessage(id: string, value: unknown): OutboundBatchMessage {
	return outboundRuntimeMessage(ContainerMessageType.FluidDataStoreOp, {
		address: "A",
		contents: { id, value },
	});
}

function outboundRuntimeMessage(type: ContainerMessageType, contents: unknown): OutboundBatchMessage {
	return {
		referenceSequenceNumber: 7,
		contents: JSON.stringify({
			type,
			contents,
		}),
	};
}

function batch(messages: OutboundBatchMessage[]): OutboundBatch {
	return {
		messages,
		referenceSequenceNumber: 7,
		contentSizeInBytes: messages.reduce(
			(total, message) => total + Buffer.byteLength(message.contents ?? "", "utf8"),
			0,
		),
	};
}

function processor(chunks: [string, string[]][] = []): RemoteMessageProcessor {
	const logger = new MockLogger();
	return new RemoteMessageProcessor(
		new OpSplitter(chunks, undefined, 1, 1, logger),
		new OpDecompressor(logger),
		new OpGroupingManager({ groupedBatchingEnabled: true }, logger),
	);
}

function sequenced(
	message: IBatchMessage,
	clientId: string,
	sequenceNumber: number,
	referenceSequenceNumber = 7,
): ISequencedDocumentMessage {
	const result = {
		type: MessageType.Operation,
		clientId,
		sequenceNumber,
		minimumSequenceNumber: 0,
		clientSequenceNumber: sequenceNumber,
		referenceSequenceNumber,
		timestamp: 1_700_000_000_000 + sequenceNumber,
		contents: message.contents,
		metadata: message.metadata,
		compression: message.compression,
	} as ISequencedDocumentMessage;
	ensureContentsDeserialized(result);
	return result;
}

function simplifyMessage(message: ISequencedDocumentMessage): JsonRecord {
	return {
		clientId: message.clientId,
		sequenceNumber: message.sequenceNumber,
		minimumSequenceNumber: message.minimumSequenceNumber,
		clientSequenceNumber: message.clientSequenceNumber,
		referenceSequenceNumber: message.referenceSequenceNumber,
		timestamp: message.timestamp,
		type: message.type,
		contents: message.contents,
		metadata: message.metadata,
		compression: message.compression,
	};
}

function processMessages(messages: ISequencedDocumentMessage[], initial: [string, string[]][] = []) {
	const remote = processor(initial);
	const results: unknown[] = [];
	for (const message of messages) {
		const result = remote.process(structuredClone(message), () => {});
		if (result !== undefined) {
			results.push({
				type: result.type,
				groupedBatch: result.type === "fullBatch" ? result.groupedBatch : undefined,
				messages:
					result.type === "fullBatch"
						? result.messages.map(simplifyMessage)
						: [simplifyMessage(result.nextMessage)],
			});
		}
	}
	return {
		results,
		partials: structuredClone([...remote.partialMessages.entries()]),
	};
}

function group(input: OutboundBatch): OutboundSingletonBatch {
	return new OpGroupingManager(
		{ groupedBatchingEnabled: true },
		new MockLogger(),
	).groupBatch(input);
}

function compressBatch(input: OutboundSingletonBatch): OutboundSingletonBatch {
	return new OpCompressor(new MockLogger()).compressBatch(input);
}

function splitBatch(
	input: OutboundSingletonBatch,
	maxBatchSizeInBytes = Number.POSITIVE_INFINITY,
	selectedChunkSizeInBytes = chunkSizeInBytes,
): IBatchMessage[] {
	const leading: IBatchMessage[] = [];
	const splitter = new OpSplitter(
		[],
		(messages) => {
			leading.push(...messages);
			return 0;
		},
		selectedChunkSizeInBytes,
		maxBatchSizeInBytes,
		new MockLogger(),
	);
	const trailing = splitter.splitSingletonBatchMessage(input);
	return [...leading, ...trailing.messages];
}

function physical(
	messages: IBatchMessage[],
	clientId = "writer-a",
	firstSequence = 1,
	referenceSequenceNumber = 7,
) {
	return messages.map((message, index) =>
		sequenced(message, clientId, firstSequence + index, referenceSequenceNumber));
}

function decodedOutputBytes(output: IBatchMessage[]): number {
	let envelope: { packedContents?: string };
	if (output.some((message) => {
		const value = JSON.parse(message.contents ?? "null") as { type?: string } | null;
		return value?.type === ContainerMessageType.ChunkedOp;
	})) {
		let decodedBytes = 0;
		let serialized = "";
		for (const message of output) {
			const value = JSON.parse(message.contents ?? "null") as {
				contents: { chunkId: number; totalChunks: number; contents: string };
			};
			if (value.contents.chunkId === 1) serialized = "";
			serialized += value.contents.contents;
			if (value.contents.chunkId === value.contents.totalChunks) {
				envelope = JSON.parse(serialized) as { packedContents?: string };
				assert(typeof envelope.packedContents === "string");
				decodedBytes += decompress(Buffer.from(envelope.packedContents, "base64")).byteLength;
			}
		}
		return decodedBytes;
	} else {
		envelope = JSON.parse(output[0]?.contents ?? "null") as { packedContents?: string };
	}
	if (typeof envelope.packedContents === "string") {
		return decompress(Buffer.from(envelope.packedContents, "base64")).byteLength;
	}
	return output.reduce(
		(total, message) => total + Buffer.byteLength(message.contents ?? "", "utf8"),
		0,
	);
}

function measurements(input: OutboundBatch, output: IBatchMessage[]): JsonRecord {
	return {
		sourceBytes: input.contentSizeInBytes,
		packedBytes: output.reduce(
			(total, message) => total + Buffer.byteLength(message.contents ?? "", "utf8"),
			0,
		),
		decodedBytes: decodedOutputBytes(output),
		chunkCount: output.filter((message) => {
			const value = JSON.parse(message.contents ?? "null") as { type?: string } | null;
			return value?.type === ContainerMessageType.ChunkedOp;
		}).length,
	};
}

function captureCase(
	id: string,
	input: OutboundBatch,
	output: IBatchMessage[],
	clientId = "writer-a",
	firstSequence = 1,
	referenceSequenceNumber = 7,
): JsonRecord {
	const messages = physical(output, clientId, firstSequence, referenceSequenceNumber);
	return {
		id,
		messages: messages.map(simplifyMessage),
		expected: processMessages(messages).results,
		measurements: measurements(input, output),
	};
}

function frame(id: string, decoded: Uint8Array): JsonRecord {
	const compressed = compress(decoded);
	const flag = compressed[4];
	const descriptor = compressed[5];
	let offset = 7;
	let blockCount = 0;
	let hasUncompressedBlock = false;
	while (offset + 4 <= compressed.byteLength) {
		const size = (
			compressed[offset]
			| (compressed[offset + 1] << 8)
			| (compressed[offset + 2] << 16)
			| (compressed[offset + 3] << 24)
		) >>> 0;
		offset += 4;
		if (size === 0) break;
		blockCount += 1;
		hasUncompressedBlock ||= (size & 0x80000000) !== 0;
		offset += size & 0x7fffffff;
	}
	return {
		id,
		compressedBase64: base64(compressed),
		decodedBase64: base64(decoded),
		flags: {
			flagByte: flag,
			blockDescriptorByte: descriptor,
			version: flag >>> 6,
			blockIndependence: (flag & 0x20) !== 0,
			blockChecksum: (flag & 0x10) !== 0,
			contentSize: (flag & 0x08) !== 0,
			contentChecksum: (flag & 0x04) !== 0,
			dictionaryId: (flag & 0x01) !== 0,
			maxBlockCode: descriptor >>> 4,
			blockCount,
			hasUncompressedBlock,
		},
		measurements: {
			compressedBytes: compressed.byteLength,
			decodedBytes: decoded.byteLength,
		},
	};
}

function nativePolicyCase(
	id: string,
	message: ISequencedDocumentMessage,
	expectedNativeError: string,
): JsonRecord {
	let upstreamObservation: JsonRecord;
	try {
		upstreamObservation = {
			status: "accepted",
			result: processMessages([message]).results,
		};
	} catch (error) {
		upstreamObservation = {
			status: "rejected",
			error: error instanceof Error ? error.message : String(error),
		};
	}
	return {
		id,
		messages: [simplifyMessage(message)],
		expected: [],
		measurements: {
			sourceBytes: Buffer.byteLength(JSON.stringify(message.contents), "utf8"),
			packedBytes: Buffer.byteLength(JSON.stringify(message.contents), "utf8"),
			decodedBytes: 0,
			chunkCount:
				(message.contents as { type?: string } | null)?.type ===
				ContainerMessageType.ChunkedOp
					? 1
					: 0,
		},
		expectedNativeError,
		upstreamObservation,
	};
}

function schemaActivation() {
	const logger = createMockLoggerExt();
	const initialSchema: IDocumentSchema = {
		version: 1,
		refSeq: 0,
		info: { minVersionForCollab: defaultMinVersionForCollab },
		runtime: { explicitSchemaControl: true },
	};
	const features: IDocumentSchemaFeatures = {
		explicitSchemaControl: true,
		compressionLz4: true,
		opGroupingEnabled: true,
		idCompressorMode: undefined,
		createBlobPayloadPending: undefined,
		disallowedVersions: [],
	};
	const changes: unknown[] = [];
	const controller = new DocumentsSchemaController(
		true,
		0,
		initialSchema,
		features,
		(schema) => changes.push(schema),
		{ minVersionForCollab: defaultMinVersionForCollab },
		logger,
		false,
	);
	const proposal = controller.maybeGenerateSchemaMessage();
	assert(proposal !== undefined, "Expected a schema activation proposal");
	const accepted = controller.processDocumentSchemaMessages([proposal], true, 10);
	const summary = controller.summarizeDocumentSchema(10);
	assert(summary !== undefined, "Expected a post-activation document schema");
	const staleController = new DocumentsSchemaController(
		true,
		10,
		summary,
		features,
		() => {},
		{ minVersionForCollab: defaultMinVersionForCollab },
		logger,
		false,
	);
	const staleProposal = { ...proposal, refSeq: 0 };
	const currentProposal = { ...proposal, refSeq: 10 };
	const staleArrayResult = staleController.processDocumentSchemaMessages(
		[staleProposal, currentProposal],
		false,
		11,
	);
	const futureController = new DocumentsSchemaController(
		true,
		10,
		summary,
		features,
		() => {},
		{ minVersionForCollab: defaultMinVersionForCollab },
		logger,
		false,
	);
	let futureError = "";
	try {
		futureController.processDocumentSchemaMessages(
			[{ ...proposal, refSeq: 99 }],
			false,
			12,
		);
	} catch (error) {
		futureError = error instanceof Error ? error.message : String(error);
	}
	let invalidError = "";
	try {
		futureController.processDocumentSchemaMessages(
			[{ ...proposal, refSeq: 10.5 }],
			false,
			12,
		);
	} catch (error) {
		invalidError = error instanceof Error ? error.message : String(error);
	}
	return {
		initialSchema,
		proposal,
		accepted,
		callbacks: changes,
		staleCompetingProposals: [staleProposal, currentProposal],
		staleArrayResult,
		staleSummary: staleController.summarizeDocumentSchema(11),
		futureReference: { proposal: { ...proposal, refSeq: 99 }, error: futureError },
		invalidReference: { proposal: { ...proposal, refSeq: 10.5 }, error: invalidError },
		postActivationSummary: summary,
	};
}

describe("Watershed compression source capture", () => {
	it("captures the pinned compression and chunking contract", async () => {
		assert.equal(process.env.WATERSHED_ORACLE_COMMIT, expectedCommit);
		assert.match(process.env.WATERSHED_COMPRESSION_DIGEST ?? "", /^[0-9a-f]{64}$/);
		assert.match(process.env.WATERSHED_COMPRESSION_TREE_DIGEST ?? "", /^[0-9a-f]{64}$/);
		const output = process.env.WATERSHED_COMPRESSION_OUTPUT;
		assert(output !== undefined, "WATERSHED_COMPRESSION_OUTPUT is required");
		const treeInputPath = process.env.WATERSHED_COMPRESSION_TREE_INPUT;
		assert(treeInputPath !== undefined, "WATERSHED_COMPRESSION_TREE_INPUT is required");
		const treeInput = JSON.parse(await readFile(treeInputPath, "utf8")) as {
			allocation: { type: ContainerMessageType; contents: unknown };
			operation: unknown;
			dataStoreAddress: string;
			channelAddress: string;
			treeState: {
				kind: string;
				completeness: string;
				workloads: {
					id: string;
					context: {
						kind: string;
						completeness: string;
						provenance: string;
						sessionId: string;
						dataStoreAddress: string;
						channelAddress: string;
						summary: unknown;
						compressor: string;
						initializationMessages: ISequencedDocumentMessage[];
					};
					messages: ISequencedDocumentMessage[];
				}[];
			};
		};
		const workload = (id: string) => {
			const selected = treeInput.treeState.workloads.find((item) => item.id === id);
			assert(selected !== undefined, `Missing SharedTree workload ${id}`);
			const input = batch(selected.messages.map((message) => {
				const contents = message.contents as {
					type?: ContainerMessageType;
					contents?: unknown;
					changeset?: unknown;
				} | null;
				if (contents?.type === ContainerMessageType.IdAllocation) {
					return outboundRuntimeMessage(ContainerMessageType.IdAllocation, contents.contents);
				}
				assert(Array.isArray(contents?.changeset), `${id}: expected a SharedTree operation`);
				return outboundRuntimeMessage(ContainerMessageType.FluidDataStoreOp, {
					address: selected.context.dataStoreAddress,
					contents: {
						type: "op",
						content: {
							address: selected.context.channelAddress,
							contents,
						},
					},
				});
			}));
			return {
				input,
				context: {
					workloadId: id,
					statePath: `probe.treeState.workloads.${id}.context`,
					kind: selected.context.kind,
					completeness: selected.context.completeness,
				},
			};
		};
		const publishedTreeState = {
			kind: treeInput.treeState.kind,
			completeness: treeInput.treeState.completeness,
			workloads: treeInput.treeState.workloads.map((item) => {
				const operations = item.messages
					.map((message, index, messages) => ({
						contents: message.contents as {
							type?: ContainerMessageType;
							changeset?: unknown;
						} | null,
						previous: messages[index - 1]?.contents as {
							type?: ContainerMessageType;
						} | null | undefined,
					}))
					.filter(({ contents }) => Array.isArray(contents?.changeset))
					.map(({ contents, previous }) => ({
						sha256: digestJson(contents),
						hasAllocationPrelude: previous?.type === ContainerMessageType.IdAllocation,
					}));
				return {
					id: item.id,
					context: item.context,
					operations,
				};
			}),
		};

		const plainSingletonInput = batch([runtimeMessage("plain", "singleton")]);
		const plainGroupInput = batch([
			runtimeMessage("plain-group-a", 1),
			runtimeMessage("plain-group-b", 2),
		]);
		const compressible = workload("compression-tree");
		const chunkWorkload = workload("compression-tree-chunked");
		const singletonMessage = compressible.input.messages.find((message) => {
			const runtime = JSON.parse(message.contents ?? "null") as {
				type?: ContainerMessageType;
			};
			return runtime.type === ContainerMessageType.FluidDataStoreOp;
		});
		assert(singletonMessage !== undefined, "Missing singleton SharedTree edit");
		const singletonInput = batch([singletonMessage]);
		const groupedInput = compressible.input;
		const chunkInput = chunkWorkload.input;
		const compressedSingleton = compressBatch(group(singletonInput));
		const compressedGroup = compressBatch(group(groupedInput));
		const compressedChunk = compressBatch(group(chunkInput));
		const chunked = splitBatch(compressedChunk);
		assert(chunked.length > 1, "Default chunk workload must produce multiple chunks");
		const smallChunkInput = batch([
			runtimeMessage("small-chunk", base64(deterministicBytes(8_192, 4))),
		]);
		const smallCompressedChunk = compressBatch(group(smallChunkInput));
		const smallChunks = splitBatch(
			smallCompressedChunk,
			Number.POSITIVE_INFINITY,
			1024,
		);

		const singletonCase = captureCase(
			"default-compressed-singleton",
			singletonInput,
			compressedSingleton.messages,
		);
		singletonCase.treeContext = {
			...compressible.context,
			sourceOperationIndexes: [0],
			requiredPrelude: "source workload allocation immediately before operation 0",
		};
		const groupCase = captureCase(
			"default-compressed-group",
			groupedInput,
			compressedGroup.messages,
		);
		groupCase.treeContext = {
			...compressible.context,
			sourceOperationIndexes: [0, 1],
		};
		const chunkCase = captureCase("default-chunked-group", chunkInput, chunked);
		chunkCase.treeContext = {
			...chunkWorkload.context,
			sourceOperationIndexes: [0, 1],
		};
		const cases: JsonRecord[] = [
			captureCase("plain-singleton", plainSingletonInput, plainSingletonInput.messages),
			captureCase("plain-group", plainGroupInput, group(plainGroupInput).messages),
			singletonCase,
			groupCase,
			chunkCase,
		];

		const senderA = physical(smallChunks, "sender-a", 1);
		const senderB = physical(smallChunks, "sender-b", 100);
		const interleaved: ISequencedDocumentMessage[] = [];
		for (let index = 0; index < Math.max(senderA.length, senderB.length); index++) {
			if (senderA[index] !== undefined) interleaved.push(senderA[index]);
			if (senderB[index] !== undefined) interleaved.push(senderB[index]);
		}
		cases.push({
			id: "interleaved-senders",
			messages: interleaved.map(simplifyMessage),
			expected: processMessages(interleaved).results,
			measurements: {
				...measurements(smallChunkInput, [...smallChunks, ...smallChunks]),
				chunkCount: interleaved.length,
			},
		});

		const emptyFinal = splitBatch(smallCompressedChunk, 1025, 1024);
		assert.equal(
			(JSON.parse(emptyFinal.at(-1)?.contents ?? "null") as {
				contents: { contents: string };
			}).contents.contents,
			"",
		);
		cases.push(captureCase("empty-final-chunk", smallChunkInput, emptyFinal));

		const empty = new OpGroupingManager(
			{ groupedBatchingEnabled: true },
			new MockLogger(),
		).createEmptyGroupedBatch("empty-batch", 7).outboundBatch;
		cases.push(captureCase("empty-group", empty, empty.messages));

		assert.equal(treeInput.allocation.type, ContainerMessageType.IdAllocation);
		assert.equal(typeof treeInput.operation, "object");
		const allocationInput = batch([
			outboundRuntimeMessage(ContainerMessageType.IdAllocation, treeInput.allocation.contents),
			outboundRuntimeMessage(ContainerMessageType.FluidDataStoreOp, {
				address: treeInput.dataStoreAddress,
				contents: {
					type: "op",
					content: {
						address: treeInput.channelAddress,
						contents: treeInput.operation,
					},
				},
			}),
		]);
		cases.push(captureCase(
			"id-allocation-before-tree-use",
			allocationInput,
			compressBatch(group(allocationInput)).messages,
		));

		const handleInput = batch([
			runtimeMessage("handle-valued-edit", {
				type: "__fluid_handle__",
				url: "/A/root",
			}),
		]);
		cases.push(captureCase(
			"handle-valued-edits",
			handleInput,
			compressBatch(group(handleInput)).messages,
		));

		const prefixLength = chunked.length - 1;
		const prefix = physical(chunked.slice(0, prefixLength), "summary-sender", 200);
		const tail = physical(
			chunked.slice(prefixLength),
			"summary-sender",
			200 + prefixLength,
		);
		const prefixResult = processMessages(prefix);
		const initialSummary = structuredClone(prefixResult.partials);
		const partialSummary = structuredClone(prefixResult.partials);
		const resumed = processMessages(tail, structuredClone(partialSummary));
		cases.push({
			id: "partial-summary-prefix-tail",
			messages: [...prefix, ...tail].map(simplifyMessage),
			expected: resumed.results,
			measurements: measurements(chunkInput, chunked),
			initialSummary,
			partialSummary,
			delivery: { prefixLength, tailLength: tail.length },
			treeContext: {
				...chunkWorkload.context,
				sourceOperationIndexes: [0, 1],
			},
		});

		const firstCompressed = physical(smallCompressedChunk.messages)[0];
		const unmarked = structuredClone(firstCompressed);
		unmarked.compression = undefined;
		cases.push(nativePolicyCase(
			"unmarked-packed-content",
			unmarked,
			"Unmarked packed content is outside the native compression profile",
		));
		const unknown = structuredClone(firstCompressed);
		unknown.compression = "brotli";
		cases.push(nativePolicyCase(
			"unknown-algorithm",
			unknown,
			"Unsupported compression algorithm: brotli",
		));

		const multiDecoded = new TextEncoder().encode(JSON.stringify([
			JSON.parse(runtimeMessage("multi-a", 1).contents ?? "null"),
			JSON.parse(runtimeMessage("multi-b", 2).contents ?? "null"),
		]));
		const multi = structuredClone(firstCompressed);
		multi.contents = { packedContents: base64(compress(multiDecoded)) };
		cases.push(nativePolicyCase(
			"multi-message-compressed-array",
			multi,
			"Compressed payload must contain one runtime message",
		));

		cases.push(nativePolicyCase(
			"missing-prefix",
			physical(smallChunks.slice(1, 2), "missing-prefix")[0],
			"Chunk stream is missing its first piece",
		));

		const malformed = structuredClone(firstCompressed);
		const malformedBytes = Buffer.from(
			(malformed.contents as { packedContents: string }).packedContents,
			"base64",
		);
		malformedBytes[6] ^= 0xff;
		malformed.contents = { packedContents: malformedBytes.toString("base64") };
		cases.push(nativePolicyCase(
			"malformed-frame",
			malformed,
			"Compressed payload has an invalid LZ4 frame checksum",
		));

		const nestedInner = {
			packedContents: (firstCompressed.contents as { packedContents: string }).packedContents,
		};
		const nestedDecoded = new TextEncoder().encode(JSON.stringify([{
			type: ContainerMessageType.FluidDataStoreOp,
			contents: nestedInner,
			compression: "lz4",
		}]));
		const nested = structuredClone(firstCompressed);
		nested.contents = { packedContents: base64(compress(nestedDecoded)) };
		cases.push(nativePolicyCase(
			"nested-compression",
			nested,
			"Nested compression is outside the native compression profile",
		));

		const activation = schemaActivation();
		cases.push({
			id: "native-format-without-compression-lz4",
			messages: [],
			expected: [],
			measurements: { sourceBytes: 0, packedBytes: 0, decodedBytes: 0, chunkCount: 0 },
			initialSummary: activation.initialSchema,
		});
		cases.push({
			id: "schema-activation",
			messages: [{
				type: ContainerMessageType.DocumentSchemaChange,
				contents: [activation.proposal],
				sequenceNumber: 10,
			}],
			expected: [activation.postActivationSummary],
			measurements: { sourceBytes: 0, packedBytes: 0, decodedBytes: 0, chunkCount: 0 },
		});
		cases.push({
			id: "stale-competing-proposals",
			messages: activation.staleCompetingProposals,
			expected: [{ accepted: activation.staleArrayResult, summary: activation.staleSummary }],
			measurements: { sourceBytes: 0, packedBytes: 0, decodedBytes: 0, chunkCount: 0 },
		});
		cases.push({
			id: "future-schema-reference",
			messages: [activation.futureReference],
			expected: [],
			measurements: { sourceBytes: 0, packedBytes: 0, decodedBytes: 0, chunkCount: 0 },
			expectedNativeError: "Schema proposal reference is newer than the active schema",
		});
		cases.push({
			id: "invalid-schema-reference",
			messages: [activation.invalidReference],
			expected: [],
			measurements: { sourceBytes: 0, packedBytes: 0, decodedBytes: 0, chunkCount: 0 },
			expectedNativeError: "Schema proposal reference must be an integer",
		});
		const postActivationOperation = captureCase(
			"post-activation-compressed-operation",
			groupedInput,
			compressedGroup.messages,
			"activated-writer",
			11,
			10,
		);
		postActivationOperation.activation = {
			caseId: "schema-activation",
			sequenceNumber: 10,
			schemaRefSeq: (activation.postActivationSummary as IDocumentSchema).refSeq,
		};
		postActivationOperation.treeContext = {
			...compressible.context,
			sourceOperationIndexes: [0, 1],
		};
		cases.push(postActivationOperation);

		const frames = [
			frame("literal-block", deterministicBytes(8 * 1024, 3)),
			frame("overlapping-match", new TextEncoder().encode("a".repeat(8 * 1024))),
			frame(
				"multi-block-match",
				new TextEncoder().encode("m".repeat(4 * 1024 * 1024 + 1)),
			),
			frame("utf8", new TextEncoder().encode("水源🌊café".repeat(512))),
			frame("benchmark-1mib", new TextEncoder().encode("bench-1mib:".padEnd(1024 * 1024, "x"))),
			frame("benchmark-4mib", new TextEncoder().encode("bench-4mib:".padEnd(4 * 1024 * 1024, "y"))),
		];

		const capture = {
			formatVersion: 1,
			upstream: {
				version: "3.1.0",
				commit: expectedCommit,
				package: "@fluidframework/container-runtime",
			},
			probe: {
				path: "packages/runtime/container-runtime/src/test/watershedCompression.spec.ts",
				digest: process.env.WATERSHED_COMPRESSION_DIGEST,
				treePath: "packages/dds/tree/src/test/watershedCompressionTree.spec.ts",
				treeDigest: process.env.WATERSHED_COMPRESSION_TREE_DIGEST,
				bootstrapSnapshot: {
					kind: "container-runtime-root-blob-context",
					blobEncoding: "utf8-json",
					sequenceNumber: 10,
					rootBlobs: {
						[metadataBlobName]: {
							summaryFormatVersion: 1,
							documentSchema: activation.postActivationSummary,
						},
						[chunksBlobName]: prefixResult.partials,
					},
				},
				treeState: publishedTreeState,
				schemaActivation: activation,
			},
			defaults: {
				minimumBatchSizeInBytes,
				chunkSizeInBytes,
				compressionAlgorithm: enabledCompressionConfig.compressionAlgorithm,
			},
			limits: {
				maxPackedBytes: 16 * 1024 * 1024,
				maxDecodedBytes: 16 * 1024 * 1024,
				maxBufferedBytes: 16 * 1024 * 1024,
				maxStreams: 64,
				maxChunks: 128,
			},
			frames,
			cases,
		};
		await mkdir(output, { recursive: true });
		await writeFile(join(output, "compression.json"), `${JSON.stringify(capture, null, 2)}\n`);
	});
});
