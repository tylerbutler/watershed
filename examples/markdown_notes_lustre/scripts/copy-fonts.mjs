// Materialise the label face out of node_modules and into the served tree.
//
// The page loads its font with a plain `@font-face` and no CSS bundler, so the
// file has to exist at a stable path next to index.html. Copying it here keeps
// @fontsource the single source of truth for the version — the alternative,
// committing the woff2, means the bytes and the manifest can drift apart with
// nothing to catch it.
//
// `fonts/` is generated, like `dist/` and `sw.js`, and gitignored with them.
// This runs before scripts/stamp-sw.mjs, which hashes the shell it produces.
import { copyFileSync, mkdirSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";

const require = createRequire(import.meta.url);
const saira = dirname(require.resolve("@fontsource-variable/saira/package.json"));

// Latin only, and only the upright: the panel sets labels and note titles, and
// the file already carries every weight and width those need on both axes.
const assets = [
  ["files/saira-latin-wdth-normal.woff2", "saira-latin-wdth-normal.woff2"],
  ["LICENSE", "LICENSE-saira.txt"],
];

mkdirSync("fonts", { recursive: true });
for (const [from, to] of assets) {
  copyFileSync(join(saira, from), join("fonts", to));
}
console.log(`fonts/ populated from @fontsource-variable/saira`);
