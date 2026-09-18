import assert from "node:assert/strict";
import { access } from "node:fs/promises";
import { readFile } from "node:fs/promises";
import { constants } from "node:fs";
import { dirname, resolve } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const netlifyBuildPath = resolve(repoRoot, "website_lustre/scripts/netlify-build.sh");
const productionBuildPath = resolve(repoRoot, "tools/build-website-lustre.sh");
const netlify = await readFile(resolve(repoRoot, "netlify.toml"), "utf8");
const build = await readFile(netlifyBuildPath, "utf8");
const workflow = await readFile(
  resolve(repoRoot, ".github/workflows/website-lustre.yml"),
  "utf8",
);

test("Netlify publishes the generated Lustre artifact", () => {
  assert.match(netlify, /base\s*=\s*"\."/);
  assert.match(netlify, /command\s*=\s*"\.\/website_lustre\/scripts\/netlify-build\.sh"/);
  assert.match(netlify, /publish\s*=\s*"website_lustre\/dist"/);
  assert.match(netlify, /GLEAM_VERSION\s*=\s*"1\.18\.1"/);
  assert.match(netlify, /PNPM_VERSION\s*=\s*"11\.13\.1"/);
  assert.doesNotMatch(netlify, /base\s*=\s*"website"/);
});

test("Netlify runs the same checked-in production build", async () => {
  await access(netlifyBuildPath, constants.X_OK);
  await access(productionBuildPath, constants.X_OK);
  assert.match(build, /run_pnpm --dir website install --frozen-lockfile/);
  assert.match(build, /run_pnpm --dir website_lustre install --frozen-lockfile/);
  assert.match(build, /corepack "pnpm@\$\{PNPM_VERSION\}"/);
  assert.match(build, /website_lustre && gleam deps download/);
  assert.match(build, /\.\/tools\/build-website-lustre\.sh/);
  assert.doesNotMatch(build, /astro build/);
});

test("Actions deploys tested previews while Netlify owns production", () => {
  assert.match(workflow, /^name: Lustre website$/m);
  assert.match(workflow, /netlify deploy/);
  assert.match(workflow, /--dir website_lustre\/dist/);
  assert.match(workflow, /--no-build/);
  assert.match(workflow, /working-directory: website\n\s+run: pnpm install --frozen-lockfile/);
  assert.doesNotMatch(workflow, /--prod/);
});
