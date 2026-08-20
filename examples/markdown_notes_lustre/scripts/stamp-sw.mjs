// Stamp sw.template.js with the bundle's content hash so the service worker
// cache name changes exactly when the shell does.
import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";

const bundle = readFileSync("dist/markdown_notes_lustre.mjs");
const hash = createHash("sha256").update(bundle).digest("hex").slice(0, 12);
const template = readFileSync("sw.template.js", "utf8");
writeFileSync("sw.js", template.replaceAll("__BUILD_HASH__", hash));
console.log(`sw.js stamped with cache mdnotes-${hash}`);
