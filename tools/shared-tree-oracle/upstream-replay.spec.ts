/*!
 * Copyright (c) Microsoft Corporation and contributors. All rights reserved.
 * Licensed under the MIT License.
 */

import { strict as assert } from "node:assert";
import { readFileSync } from "node:fs";
import { isAbsolute, join } from "node:path";

import {
	replayArrayCodecInput,
	replayArrayHistoryInput,
	replayArrayInvalidInput,
	replayArraySchemaInput,
} from "./watershedArray.spec.js";
import { replayArrayModularInput } from "./watershedArraySupport.js";
import {
	replayForestInput,
	replaySequenceAlgebraInput,
	replaySequenceEditorInput,
	replaySequenceRebaseInput,
} from "./watershedSequence.spec.js";

type Replay = (input: Record<string, unknown>) => unknown | Promise<unknown>;

function copy<T>(value: T): T {
	return JSON.parse(JSON.stringify(value));
}

function cases(path: string): {
	readonly id: string;
	readonly input: { readonly scenarios: readonly Record<string, unknown>[] };
	readonly raw: {
		readonly scenarios: readonly {
			readonly id: string;
			readonly output: unknown;
		}[];
	};
}[] {
	return JSON.parse(readFileSync(path, "utf8"));
}

if (process.env.WATERSHED_ORACLE_CORPUS === "replay") {
	describe("Watershed serialized-input replay", () => {
		it("observes decoded retained-history changes, not only revision metadata", async () => {
			const output = process.env.WATERSHED_ORACLE_OUTPUT;
			assert(output !== undefined && isAbsolute(output),
				"WATERSHED_ORACLE_OUTPUT must be absolute.");
			const input = cases(join(output, "array-cases.json"))
				.find(({ id }) => id === "array-codecs")?.input.scenarios
				.find(({ id }) => id === "retained-history");
			assert(input !== undefined, "Retained-history input must exist.");
			const mutated = copy(input);
			let blob: unknown = mutated.encodedSummary;
			for (const key of ["tree", "indexes", "tree", "EditManager", "tree", "String"]) {
				assert(blob !== null && typeof blob === "object", `Summary history path: ${key}`);
				blob = Reflect.get(blob, key);
			}
			assert(blob !== null && typeof blob === "object", "Summary history blob must exist.");
			const content: unknown = Reflect.get(blob, "content");
			assert(typeof content === "string", "Summary history must be encoded JSON.");
			const history: unknown = JSON.parse(content);
			function shrinkRemoval(value: unknown): boolean {
				if (value === null || typeof value !== "object") return false;
				const effect: unknown = Reflect.get(value, "effect");
				if (effect !== null && typeof effect === "object"
					&& Reflect.has(effect, "remove") && Reflect.get(value, "count") === 2) {
					Reflect.set(value, "count", 1);
					return true;
				}
				return Object.values(value).some(shrinkRemoval);
			}
			assert(shrinkRemoval(history), "Retained history must contain a count-two removal.");
			Reflect.set(blob, "content", JSON.stringify(history));
			const original = await replayArrayCodecInput(copy(input)) as {
				restoredHistory: unknown;
				visible: unknown;
			};
			const changed = await replayArrayCodecInput(mutated) as typeof original;
			assert.deepEqual(changed.visible, original.visible,
				"Changing retained history must not change the independently stored forest.");
			assert.notDeepEqual(changed.restoredHistory, original.restoredHistory,
				"Decoded retained changes must be observable even with identical revision metadata.");
		});

		it("replays every exported M3 domain twice in a fresh process", async () => {
			const output = process.env.WATERSHED_ORACLE_OUTPUT;
			assert(output !== undefined && isAbsolute(output),
				"WATERSHED_ORACLE_OUTPUT must be absolute.");
			const replays = new Map<string, Replay>([
				["array-forest-delta", replayForestInput],
				["sequence-field-editor", replaySequenceEditorInput],
				["sequence-compose-invert", replaySequenceAlgebraInput],
				["sequence-rebase", replaySequenceRebaseInput],
				["array-schema-content", replayArraySchemaInput],
				["array-modular-algebra", replayArrayModularInput],
				["array-codecs", replayArrayCodecInput],
				["array-history", replayArrayHistoryInput],
				["array-invalid", replayArrayInvalidInput],
			]);
			const captured = [
				...cases(join(output, "sequence-cases.json")),
				...cases(join(output, "array-cases.json")),
			];
			for (const oracleCase of captured) {
				const replay = replays.get(oracleCase.id);
				assert(replay !== undefined, `${oracleCase.id}: missing replay entrypoint`);
				const expected = new Map(
					oracleCase.raw.scenarios.map((scenario) => [scenario.id, scenario.output]),
				);
				for (const scenario of oracleCase.input.scenarios) {
					assert(typeof scenario.id === "string", `${oracleCase.id}: scenario ID`);
					const first: unknown = copy(await replay(copy(scenario)));
					const second: unknown = copy(await replay(copy(scenario)));
					assert.deepEqual(first, expected.get(scenario.id),
						`${oracleCase.id}/${scenario.id}: fresh replay result`);
					assert.deepEqual(second, first,
						`${oracleCase.id}/${scenario.id}: deterministic replay result`);
				}
			}
		});
	});
}
