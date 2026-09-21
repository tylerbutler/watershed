import { strict as assert } from "node:assert";
import { mkdir, writeFile } from "node:fs/promises";
import { endianness } from "node:os";
import { isAbsolute, join } from "node:path";

import { serializeIdCompressor } from "@fluidframework/id-compressor/internal";

import { FluidClientVersion, jsonableCodecTree } from "../codec/index.js";
import { getCodecTreeForSharedTreeFormat } from "../shared-tree/index.js";
import { SchemaFactory, TreeViewConfiguration } from "../simple-tree/index.js";
import { configuredSharedTreeInternal } from "../treeFactory.js";
import { TestTreeProviderLite } from "./utils.js";

describe("Watershed oracle", () => {
	it("captures the pinned source codecs, messages, compressor, and summary", async () => {
		const output = process.env.WATERSHED_ORACLE_OUTPUT;
		assert(output !== undefined && isAbsolute(output), "An absolute output directory is required");
		const commit = process.env.WATERSHED_ORACLE_COMMIT;
		assert.equal(commit, "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960");

		const minVersionForCollab = FluidClientVersion.v2_117;
		const factory = configuredSharedTreeInternal({ minVersionForCollab }).getFactory();
		const provider = new TestTreeProviderLite(2, factory);
		const config = new TreeViewConfiguration({ schema: SchemaFactory.number });
		const first = provider.trees[0].viewWith(config);
		first.initialize(0);

		const messages: unknown[] = [];
		function deliver(): void {
			while (provider.peekNextMessage() !== undefined) {
				messages.push(JSON.parse(JSON.stringify(provider.peekNextMessage())));
				provider.synchronizeMessages({ count: 1 });
			}
		}
		deliver();
		const second = provider.trees[1].viewWith(config);
		first.root = 1;
		second.root = 2;
		const pending = [first.root, second.root];
		deliver();
		assert.equal(first.root, 2);
		assert.equal(second.root, 2);
		assert(messages.length > 0);

		const summary = await provider.trees[0].summarize(true);
		const compressor = serializeIdCompressor(provider.getCompressor(provider.trees[0]), false);
		const compressorBytes = Uint8Array.from(Buffer.from(compressor, "base64"));
		const capture = {
			formatVersion: 1,
			reference: { version: "3.1.0", commit },
			kind: "source-smoke",
			minVersionForCollab,
			codecTree: jsonableCodecTree(getCodecTreeForSharedTreeFormat(minVersionForCollab)),
			messages,
			observations: { pending, settled: [first.root, second.root] },
			compressor,
			compressorFormat: {
				version: new Float64Array(compressorBytes.buffer)[0],
				byteOrder: endianness(),
			},
			summary: summary.summary,
		};
		await mkdir(output, { recursive: true });
		await writeFile(join(output, "source-smoke.json"), `${JSON.stringify(capture, null, 2)}\n`);
	});
});
