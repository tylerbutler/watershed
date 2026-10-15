import { strict as assert } from "node:assert";
import { mkdir, writeFile } from "node:fs/promises";
import { isAbsolute, join } from "node:path";

import {
	createIdCompressor,
	serializeIdCompressor,
} from "@fluidframework/id-compressor/internal";
import type { ISequencedDocumentMessage } from "@fluidframework/driver-definitions/internal";
import {
	MockFluidDataStoreRuntime,
	MockStorage,
} from "@fluidframework/test-runtime-utils/internal";

import { FluidClientVersion } from "../codec/index.js";
import {
	SchemaFactory,
	TreeViewConfiguration,
} from "../simple-tree/index.js";
import { configuredSharedTreeInternal } from "../treeFactory.js";
import {
	MockContainerRuntimeFactoryWithOpBunching,
	type MockContainerRuntimeWithOpBunching,
} from "./mocksForOpBunching.js";
import { assertIsSessionId } from "./utils.js";

const expectedCommit = "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960";
const sf = new SchemaFactory("org.watershed.shared-tree.compression");
class Root extends sf.object("Root", {
	id: sf.identifier,
	label: sf.string,
}) {}

function copy<T>(value: T): T {
	return JSON.parse(JSON.stringify(value));
}

function deterministicBytes(length: number, seed: number): Uint8Array {
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

async function captureWorkload(
	sessionId: string,
	id: string,
	labels: [string, string],
) {
	const compressor = createIdCompressor(assertIsSessionId(sessionId));
	const runtime = new MockFluidDataStoreRuntime({
		clientId: `${id}-client`,
		id: `${id}-store`,
		idCompressor: compressor,
	});
	const factory = configuredSharedTreeInternal({
		minVersionForCollab: FluidClientVersion.v2_117,
	}).getFactory();
	const tree = factory.create(runtime, `${id}-tree`) as ReturnType<typeof factory.create>;
	const runtimeFactory = new MockContainerRuntimeFactoryWithOpBunching();
	const containerRuntime: MockContainerRuntimeWithOpBunching =
		runtimeFactory.createContainerRuntime(runtime);
	tree.connect({
		deltaConnection: runtime.createDeltaConnection(),
		objectStorage: new MockStorage(),
	});
	Reflect.set(tree, "containerRuntime", containerRuntime);

	const processed: ISequencedDocumentMessage[] = [];
	const originalProcess = containerRuntime.process.bind(containerRuntime);
	containerRuntime.process = (message) => {
		processed.push(copy(message));
		originalProcess(message);
	};
	const originalProcessMessages = containerRuntime.processMessages.bind(containerRuntime);
	containerRuntime.processMessages = (messages) => {
		processed.push(...copy(messages));
		originalProcessMessages(messages);
	};

	const view = tree.viewWith(new TreeViewConfiguration({ schema: Root }));
	view.initialize({ label: "compression-baseline" });
	runtimeFactory.processAllMessages();
	const initializationMessages = copy(processed);
	const initialSummary = (await tree.summarize(true)).summary;
	const workloadStart = processed.length;
	for (const label of labels) {
		view.root.label = label;
	}
	runtimeFactory.processAllMessages();
	const messages = copy(processed.slice(workloadStart));
	assert(
		messages.filter((message) =>
			Array.isArray((message.contents as { changeset?: unknown } | null)?.changeset))
			.length === labels.length,
		`${id}: expected one real SharedTree edit per label`,
	);

	return {
		id,
		context: {
			kind: "shared-tree-channel-summary-context",
			completeness: "channel-summary-and-id-compressor-not-container-snapshot",
			provenance: "pinned SharedTree summarize(true) after source-produced initialization",
			sessionId,
			dataStoreAddress: runtime.id,
			channelAddress: tree.id,
			summary: initialSummary,
			compressor: serializeIdCompressor(compressor, false),
			initializationMessages,
		},
		messages,
	};
}

describe("Watershed compression tree source capture", () => {
	it("captures real routed tree edits and compatible initial state", async () => {
		assert.equal(process.env.WATERSHED_ORACLE_COMMIT, expectedCommit);
		const output = process.env.WATERSHED_COMPRESSION_TREE_OUTPUT;
		assert(output !== undefined && isAbsolute(output));

		const compressible = await captureWorkload(
			"10000000-0000-4000-8000-000000000001",
			"compression-tree",
			["a".repeat(615_000), "compressed-group-second-edit"],
		);
		const chunked = await captureWorkload(
			"20000000-0000-4000-8000-000000000002",
			"compression-tree-chunked",
			[
				Buffer.from(deterministicBytes(232_000, 1)).toString("base64"),
				Buffer.from(deterministicBytes(232_000, 2)).toString("base64"),
			],
		);
		const allocation = compressible.context.initializationMessages.find((message) =>
			(message.contents as { type?: string } | null)?.type === "idAllocation");
		const operation = compressible.context.initializationMessages.find((message) =>
			Array.isArray((message.contents as { changeset?: unknown } | null)?.changeset));
		assert(allocation !== undefined, "Expected an ID allocation message");
		assert(operation !== undefined, "Expected a SharedTree operation");

		await mkdir(output, { recursive: true });
		await writeFile(join(output, "compression-tree.json"), `${JSON.stringify({
			allocation: allocation.contents,
			operation: operation.contents,
			dataStoreAddress: compressible.context.dataStoreAddress,
			channelAddress: compressible.context.channelAddress,
			treeState: {
				kind: "source-produced-shared-tree-channel-state",
				completeness: "channel-summary-contexts-not-full-container-snapshots",
				workloads: [compressible, chunked],
			},
		}, null, 2)}\n`);
	});
});
