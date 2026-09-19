import test from "node:test";
import assert from "node:assert/strict";

import {
  is_none,
  unwrap,
} from "../../../../tools/website-runtime/build/dev/javascript/gleam_stdlib/gleam/option.mjs";
import { none, some } from "./gleam-values.ts";

test("constructs Options from the website's single Gleam runtime", () => {
  assert.equal(unwrap(some("value"), "fallback"), "value");
  assert.equal(unwrap(none(), "fallback"), "fallback");
  assert.equal(is_none(none()), true);
});
