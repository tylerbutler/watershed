import test from "node:test";
import assert from "node:assert/strict";

import { unwrap as rootUnwrap } from "../../../../build/dev/javascript/gleam_stdlib/gleam/option.mjs";
import { unwrap as lustreUnwrap } from "../../../../watershed_lustre/build/dev/javascript/gleam_stdlib/gleam/option.mjs";
import { none, some } from "./gleam-values.ts";

test("constructs Options with the selected Gleam runtime", () => {
  assert.equal(rootUnwrap(some("root"), "fallback"), "root");
  assert.equal(rootUnwrap(none(), "fallback"), "fallback");
  assert.equal(
    lustreUnwrap(some("lustre", "lustre"), "fallback"),
    "lustre",
  );
  assert.equal(lustreUnwrap(none("lustre"), "fallback"), "fallback");
});
