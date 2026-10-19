import assert from "node:assert/strict";
import { test } from "node:test";
import { Composition, reconcileInput } from "./input.ts";

test("composition publishes once and suppresses only the matching follow-up input", () => {
  const input = new Composition();
  assert.equal(input.input("plain"), "plain");
  input.start();
  assert.equal(input.input("partial"), undefined);
  assert.equal(input.end("完成"), "完成");
  assert.equal(input.input("完成"), undefined);
  assert.equal(input.input("完成x"), "完成x");
  input.start();
  input.end("same");
  assert.equal(input.input("different"), "different");
  assert.equal(input.input("same"), "same");
});

test("offline cancellation never publishes a late composition end or partial input", () => {
  const input = new Composition();
  input.start();
  input.cancel();
  assert.equal(input.end("unfinished"), undefined);
  assert.equal(input.input("unfinished"), undefined);
  input.start();
  assert.equal(input.end("fresh"), "fresh");
});

test("resolved values preserve and clamp native selection without redundant writes", () => {
  let writes = 0;
  let value = "long value";
  let range: [number | null, number | null, "forward" | "backward" | "none"] = [3, 8, "backward"];
  const input = {
    get value() { return value; },
    set value(next: string) { writes++; value = next; range = [next.length, next.length, "none"]; },
    get selectionStart() { return range[0]; },
    get selectionEnd() { return range[1]; },
    get selectionDirection() { return range[2]; },
    setSelectionRange(start: number | null, end: number | null, direction?: "forward" | "backward" | "none") {
      range = [start, end, direction ?? "none"];
    },
  };
  reconcileInput(input, "long value", true, false);
  assert.equal(writes, 0);
  reconcileInput(input, "tiny", true, true);
  assert.equal(writes, 0);
  reconcileInput(input, "tiny", true, false);
  assert.equal(value, "tiny");
  assert.equal(writes, 1);
  assert.deepEqual(range, [3, 4, "backward"]);
});
