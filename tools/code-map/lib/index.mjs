import fs from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { createHash, randomUUID } from "node:crypto";
import { loadConfig, validateConfig, configHash, relativePath } from "./config.mjs";
import { discoverFiles, gitRoot, pathStat } from "./inventory.mjs";
import { parseGleam } from "./gleam.mjs";
import { parseJavaScript } from "./javascript.mjs";
import { parseAstro } from "./astro.mjs";
import { compare, kinds, statuses } from "./symbols.mjs";

export { queryIndex } from "./queries.mjs";

const sha256 = /^[a-f0-9]{64}$/;
const object = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const strings = (v) => Array.isArray(v) && v.every((s) => typeof s === "string");
const position = (v) => object(v) && Number.isSafeInteger(v.byte) && v.byte >= 0
  && Number.isSafeInteger(v.line) && v.line > 0 && Number.isSafeInteger(v.column) && v.column > 0;
const range = (v) => object(v) && position(v.start) && position(v.end)
  && v.start.byte <= v.end.byte && v.start.line <= v.end.line;
const diagnostic = (v) => object(v) && relativePath(v.path) && typeof v.message === "string"
  && (v.range === null || range(v.range));
const region = (v) => object(v) && typeof v.reason === "string" && range(v.range);

function validSymbol(s, path) {
  return object(s) && typeof s.id === "string" && typeof s.name === "string" && s.name.length > 0
    && strings(s.container) && kinds.includes(s.kind) && typeof s.signature === "string"
    && ["public", "protected", "private", "local", "unknown"].includes(s.visibility)
    && typeof s.exported === "boolean" && [null, "erlang", "javascript"].includes(s.target) && range(s.range)
    && s.id === JSON.stringify([path, s.container, s.name, s.range.start.byte, s.range.end.byte])
    && s.qualifiedName === `${path}::${[...s.container, s.name].join(".")}`;
}

function validIndex(index) {
  return object(index) && index.version === 1 && sha256.test(index.toolHash) && sha256.test(index.configHash)
    && typeof index.complete === "boolean" && Array.isArray(index.files)
    && new Set(index.files.map((f) => f?.path)).size === index.files.length
    && index.files.every((f) => object(f) && relativePath(f.path) && statuses.includes(f.status)
      && [null, "gleam", "javascript", "typescript", "astro"].includes(f.language)
      && (f.reason === null || typeof f.reason === "string") && (f.hash === null || sha256.test(f.hash))
      && Array.isArray(f.symbols) && f.symbols.every((s) => validSymbol(s, f.path))
      && Array.isArray(f.diagnostics) && f.diagnostics.every((d) => diagnostic(d) && d.path === f.path)
      && Array.isArray(f.skippedRegions) && f.skippedRegions.every(region)
      && (f.status === "indexed" ? f.hash !== null && f.language !== null && !f.diagnostics.length : !f.symbols.length))
    && index.complete === !index.files.some((f) => ["parse-error", "unreadable"].includes(f.status));
}

async function toolHash() {
  const root = fileURLToPath(new URL("..", import.meta.url));
  const hash = createHash("sha256");
  async function add(path) {
    const full = join(root, path);
    const stat = await fs.lstat(full);
    if (stat.isDirectory()) {
      for (const name of (await fs.readdir(full)).sort(compare)) await add(`${path}/${name}`);
    } else if (stat.isFile()) {
      hash.update(path).update("\0").update(await fs.readFile(full)).update("\0");
    } else {
      throw new Error(`Unexpected tool resource: ${path}`);
    }
  }
  for (const path of ["cli.mjs", "lib", "src", "gleam.toml", "manifest.toml", "package.json", "pnpm-lock.yaml", "build/dev/javascript"]) {
    try { await add(path); }
    catch (error) {
      if (error.code !== "ENOENT" || !path.startsWith("build/")) throw error;
      throw new Error("Code map's compiled helper is missing. Run pnpm run build in the code-map tool directory.", { cause: error });
    }
  }
  return hash.digest("hex");
}

async function regularOrMissing(root, path) {
  try {
    const stat = await pathStat(root, path);
    if (stat.isSymbolicLink()) throw new Error(`Refusing symlink cache path: ${path}`);
    return stat;
  } catch (error) {
    if (error.code === "ENOENT") return null;
    throw error;
  }
}

async function readCache(root, rebuild) {
  const directory = await regularOrMissing(root, ".code-map");
  if (directory && !directory.isDirectory()) throw new Error(".code-map must be a directory");
  const stat = await regularOrMissing(root, ".code-map/index.json");
  if (stat && !stat.isFile()) throw new Error(".code-map/index.json must be a regular file");
  if (!stat || rebuild) return null;
  const source = await fs.readFile(join(root, ".code-map/index.json"), "utf8");
  let index;
  try { index = JSON.parse(source); }
  catch (error) {
    if (!(error instanceof SyntaxError)) throw error;
    throw new Error("Invalid code-map cache. Run refresh --rebuild.", { cause: error });
  }
  if (!validIndex(index)) throw new Error("Invalid code-map cache schema. Run refresh --rebuild.");
  return index;
}

async function persist(root, index, previous) {
  const encoded = `${JSON.stringify(index)}\n`;
  if (previous && encoded === `${JSON.stringify(previous)}\n`) return;
  const directory = join(root, ".code-map");
  await fs.mkdir(directory, { recursive: true });
  await regularOrMissing(root, ".code-map/index.json");
  const temporary = join(directory, `${randomUUID()}.tmp`);
  try {
    await fs.writeFile(temporary, encoded, { flag: "wx" });
    await fs.rename(temporary, join(directory, "index.json"));
  } finally {
    await fs.rm(temporary, { force: true });
  }
}

/** Refresh on-disk source snapshots in a Git worktree. No project build or source execution. */
export async function refreshIndex(root, options = {}) {
  if (typeof root !== "string" || !root || !object(options)
      || Object.keys(options).some((key) => !["rebuild", "config"].includes(key))
      || (options.rebuild !== undefined && typeof options.rebuild !== "boolean")) {
    throw new Error("Invalid index options");
  }
  root = await gitRoot(root);
  const config = options.config === undefined ? await loadConfig(root) : validateConfig(options.config);
  const previous = await readCache(root, options.rebuild ?? false);
  const index = { version: 1, toolHash: await toolHash(), configHash: configHash(config), complete: true, files: [] };
  const cached = new Map(previous?.toolHash === index.toolHash && previous?.configHash === index.configHash
    ? previous.files.map((file) => [file.path, file]) : []);
  for (const candidate of await discoverFiles(root, config)) {
    const { source, ...file } = candidate;
    if (file.status === "pending") {
      const prior = cached.get(file.path);
      if (prior?.hash === file.hash && prior.status === "indexed") {
        index.files.push(prior);
        continue;
      }
      const parse = file.language === "gleam" ? parseGleam : file.language === "astro" ? parseAstro : parseJavaScript;
      const parsed = await parse({ path: file.path, source });
      Object.assign(file, parsed, { status: parsed.diagnostics.length ? "parse-error" : "indexed" });
    }
    index.files.push(file);
  }
  index.complete = !index.files.some((file) => ["parse-error", "unreadable"].includes(file.status));
  if (!validIndex(index)) throw new Error("Parser produced an invalid code-map index");
  await persist(root, index, previous);
  return index;
}
