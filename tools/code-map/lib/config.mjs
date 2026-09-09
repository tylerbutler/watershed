import fs from "node:fs/promises";
import { join } from "node:path";
import { createHash } from "node:crypto";
import { compare } from "./symbols.mjs";

export function relativePath(path) {
  return typeof path === "string" && path.length > 0 && !path.includes("\\")
    && !path.includes("\0") && !/^[A-Za-z]:/.test(path)
    && path.split("/").every((part) => part && part !== "." && part !== "..");
}

export function validateConfig(input) {
  if (!input || typeof input !== "object" || Array.isArray(input) || input.version !== 1
      || Object.keys(input).some((k) => !["version", "excludeDirs", "excludePaths"].includes(k))) {
    throw new Error("Invalid code-map config: expected version 1 and known fields");
  }
  const result = { version: 1, excludeDirs: [], excludePaths: [] };
  for (const key of ["excludeDirs", "excludePaths"]) {
    const entries = input[key] === undefined ? [] : input[key];
    if (!Array.isArray(entries) || new Set(entries).size !== entries.length
        || entries.some((entry) => !relativePath(entry) || (key === "excludeDirs" && entry.includes("/")))) {
      throw new Error(`Invalid code-map config: ${key} must contain unique relative ${key === "excludeDirs" ? "directory names" : "paths"}`);
    }
    result[key] = [...entries].sort(compare);
  }
  return result;
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
