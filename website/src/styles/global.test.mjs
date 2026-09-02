import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

test("file chips keep an explicit keyboard focus ring", () => {
  const css = readFileSync(new URL("./global.css", import.meta.url), "utf8");

  assert.match(
    css,
    /\.doc-body a\.g-file:focus-visible\s*\{\s*outline:\s*2px solid var\(--overprint\);\s*outline-offset:\s*2px;\s*\}/s,
  );
});
