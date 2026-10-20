import assert from "node:assert/strict";
import test from "node:test";
import { bounded, wait } from "../lib/conditions.mjs";

test("rejects a successful probe that returns after its deadline", async () => {
  await assert.rejects(bounded("late", () => {
    const end = performance.now() + 15;
    while (performance.now() < end) {}
    return true;
  }, 5), /late.*timed out/);
});

test("wait observes changed state rather than relying on one initial read", async () => {
  const states = ["opening", "ready"];
  assert.equal(await wait("connect", () => states.shift(), value => value === "ready", 1000), "ready");
});

test("wait preserves a probe error instead of treating it as an empty state", async () => {
  const error = new Error("Service rejected the document");
  await assert.rejects(wait("document", () => { throw error; }, Boolean), value => value === error);
});
