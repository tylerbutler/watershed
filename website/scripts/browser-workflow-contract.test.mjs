import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const workflow = readFileSync(
  new URL("../../.github/workflows/website-browser.yml", import.meta.url),
  "utf8",
);

test("website browser workflow provides Chrome and runs the required gate", () => {
  assert.match(workflow, /gleam-version:\s*["']?1\.18/);
  assert.match(workflow, /browser-actions\/setup-chrome@/);
  assert.match(workflow, /WATERSHED_CHROME:/);
  assert.match(workflow, /pnpm test:integration:browser:required/);
});
