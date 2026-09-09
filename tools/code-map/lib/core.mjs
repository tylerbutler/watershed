import { access } from "node:fs/promises";

const entry = new URL("../build/dev/javascript/code_map/code_map/bridge.mjs", import.meta.url);
let missing;
try { await access(entry); }
catch (error) {
  if (error.code !== "ENOENT") throw error;
  missing = new Error("Code map's compiled core is missing. Run pnpm run build in the code-map tool directory.", { cause: error });
}
const loaded = missing ? null : await import(entry.href);

export function core() {
  if (missing) throw missing;
  return loaded;
}
