import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { captureContracts } from "./contracts.mjs";

export const baseline = JSON.parse(await readFile(new URL("./fixtures/contracts.json", import.meta.url), "utf8"));

test("public indexes, views and text preserve the pre-migration contract", async (t) => {
  assert.deepEqual(await captureContracts(t), baseline);
});
