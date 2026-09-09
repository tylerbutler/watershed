import fs from "node:fs/promises";
import { join } from "node:path";
import { createHash } from "node:crypto";
import { core } from "./core.mjs";

export function relativePath(path) {
  return core().relative_path(path);
}

export function validateConfig(input) {
  return core().normalize_config(input);
}

export async function loadConfig(root) {
  const path = join(root, "code-map.json");
  try {
    const stat = await fs.lstat(path);
    if (!stat.isFile()) throw new Error(`Invalid config: ${path} must be a regular file, not a symlink`);
    const source = await fs.readFile(path, "utf8");
    let parsed;
    try { parsed = JSON.parse(source); }
    catch (error) {
      if (!(error instanceof SyntaxError)) throw error;
      throw new Error(`Invalid config JSON: ${path}`, { cause: error });
    }
    return validateConfig(parsed);
  } catch (error) {
    if (error.code === "ENOENT") return validateConfig({ version: 1 });
    throw error;
  }
}

export function configHash(config) {
  return createHash("sha256").update(JSON.stringify(validateConfig(config))).digest("hex");
}
