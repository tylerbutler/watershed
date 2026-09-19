import assert from "node:assert/strict";
import test from "node:test";
import { requiredInstance } from "./dom.ts";

class Expected {}
class Wrong {}

test("returns a required value with the expected constructor", () => {
  const value = new Expected();
  assert.equal(
    requiredInstance(value, Expected, "sudoku demo", "[data-op-log]"),
    value,
  );
});

test("throws a descriptive error for missing required markup", () => {
  assert.throws(
    () => requiredInstance(null, Expected, "sudoku demo", "[data-op-log]"),
    /sudoku demo: missing or invalid \[data-op-log\]/,
  );
});

test("throws a descriptive error for the wrong element type", () => {
  assert.throws(
    () => requiredInstance(new Wrong(), Expected, "sudoku demo", "[data-op-log]"),
    /sudoku demo: missing or invalid \[data-op-log\]/,
  );
});
