import assert from "node:assert/strict";
import { test } from "node:test";
import { performance } from "node:perf_hooks";
import { wait } from "../smoke/conditions.mjs";
import { submitText } from "../smoke/browser.mjs";

test("both contention edits submit even if the other whole-string value already won", async () => {
  const submitted = [];
  const send = async (method, params) => {
    if (method === "Input.insertText") { submitted.push(params.text); return {}; }
    return { result: { value: {
      active: "owner.name", values: { "owner.name": "B" },
      errors: [], browserErrors: [], console: [],
    } } };
  };
  const result = await Promise.race([
    Promise.all([submitText(send, "owner.name", "A"), submitText(send, "owner.name", "B")])
      .then(() => "submitted", error => error.message),
    new Promise(resolve => setTimeout(() => resolve("waiting for overwritten local value"), 150)),
  ]);
  assert.deepEqual(submitted, ["A", "B"]);
  assert.equal(result, "submitted");
});

test("a probe that succeeds after its deadline cannot pass acceptance", async () => {
  await assert.rejects(wait("late phase", () => new Promise(resolve =>
    setTimeout(() => resolve(true), 80)), Boolean, 10), /late phase.*timed out/);
});

test("a stalled probe fails within its budget and reports the phase", async () => {
  const started = performance.now();
  const result = await Promise.race([
    wait("stalled phase", () => new Promise(() => {}), Boolean, 20)
      .then(() => "passed", error => error.message),
    new Promise(resolve => setTimeout(() => resolve("escaped deadline"), 200)),
  ]);
  assert.match(result, /stalled phase.*timed out/);
  assert(performance.now() - started < 180);
});

test("event-loop delay cannot turn a late synchronous probe into success", async () => {
  await assert.rejects(wait("blocked phase", () => {
    const end = performance.now() + 25;
    while (performance.now() < end) {}
    return true;
  }, Boolean, 10), /blocked phase.*timed out.*late result/);
});
