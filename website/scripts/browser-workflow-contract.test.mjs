import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const workflow = readFileSync(
  new URL("../../.github/workflows/website-browser.yml", import.meta.url),
  "utf8",
);
const mise = readFileSync(
  new URL("../../mise.toml", import.meta.url),
  "utf8",
);

test("website browser workflow provides Chrome and runs the required gate", () => {
  assert.match(mise, /^gleam = "1\.18"$/m);
  assert.match(workflow, /jdx\/mise-action@v3/);
  assert.doesNotMatch(workflow, /gleam-lang\/setup-gleam/);
  assert.doesNotMatch(workflow, /^\s*install_args:/m);
  assert.match(workflow, /browser-actions\/setup-chrome@/);
  assert.match(workflow, /WATERSHED_CHROME:/);
  assert.match(workflow, /pnpm test:integration:browser:required/);
});
