import { access } from "node:fs/promises";
import { makeSymbol, rangeAt } from "./symbols.mjs";

let helper;
async function loadHelper() {
  const url = new URL("../build/dev/javascript/code_map/code_map.mjs", import.meta.url);
  try {
    await access(url);
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
    throw new Error("Code map's Gleam helper is missing. Run pnpm run build in the code-map tool directory.");
  }
  return import(url.href);
}

export async function parseGleam({ path, source }) {
  helper ??= loadHelper();
  const raw = JSON.parse((await helper).extract_json(source));
  if (raw.version !== 1 || raw.offsetEncoding !== "utf16"
      || !Array.isArray(raw.declarations) || !Array.isArray(raw.diagnostics)) {
    throw new Error("Invalid Gleam parser response");
  }
  return {
    symbols: raw.declarations.map((d) => makeSymbol(path, source, {
      ...d, visibility: d.public ? "public" : "private", exported: d.public,
    })),
    diagnostics: raw.diagnostics.map((d) => ({
      path, message: d.message, range: d.offset < 0 ? null : rangeAt(source, d.offset, d.offset),
    })),
    skippedRegions: [],
  };
}
