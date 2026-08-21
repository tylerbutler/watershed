// Stamp sw.template.js with the shell's content hash so the service worker
// cache name changes exactly when the shell does.
//
// Hashing the bundle alone was enough while the bundle was the only cached
// asset. It stopped being true the moment the shell grew a font: the cache
// name would not move, an installed worker would keep serving its old cache,
// and the new asset would never be fetched. So every local file the template
// lists is hashed, in the order it is listed.
import { createHash } from "node:crypto";
import { existsSync, readFileSync, writeFileSync } from "node:fs";

const template = readFileSync("sw.template.js", "utf8");

const shell = template
  .slice(template.indexOf("const SHELL = ["), template.indexOf("];"))
  .matchAll(/"\.\/([^"]+)"/g);

const digest = createHash("sha256");
for (const [, path] of shell) {
  if (existsSync(path)) digest.update(path).update(readFileSync(path));
}

const hash = digest.digest("hex").slice(0, 12);
writeFileSync("sw.js", template.replaceAll("__BUILD_HASH__", hash));
console.log(`sw.js stamped with cache mdnotes-${hash}`);
