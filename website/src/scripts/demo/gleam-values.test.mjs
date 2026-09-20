import test from "node:test";
import assert from "node:assert/strict";

import {
  isSome,
  none,
  optionValue,
  some,
} from "./gleam-interop.ts";

test("constructs Options from the website's single Gleam runtime", () => {
  assert.equal(optionValue(some("value")), "value");
  assert.equal(optionValue(none()), null);
  assert.equal(isSome(some("value")), true);
});
