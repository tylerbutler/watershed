import fs from "node:fs/promises";
import { join, extname } from "node:path";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { createHash } from "node:crypto";
import { compare, extensions } from "./symbols.mjs";
import { relativePath } from "./config.mjs";

const execute = promisify(execFile);

export async function git(root, args) {
  const { stdout } = await execute("git", ["-C", root, ...args], { encoding: "utf8", maxBuffer: 32 * 1024 * 1024 });
  return stdout;
}

export async function gitRoot(directory) {
  const root = (await git(directory, ["rev-parse", "--show-toplevel"])).replace(/\r?\n$/, "");
  return fs.realpath(root);
}

export async function pathStat(root, path) {
  let current = root;
  let stat;
  for (const component of path.split("/")) {
    current = join(current, component);
    stat = await fs.lstat(current);
    if (stat.isSymbolicLink()) return stat;
  }
  return stat;
}

export function beneath(path, prefix) {
  return path === prefix || path.startsWith(`${prefix}/`);
}

export async function discoverFiles(root, config) {
  const paths = [...new Set((await git(root, ["ls-files", "--cached", "--others", "--exclude-standard", "--deduplicate", "-z"]))
    .split("\0").filter((path) => path && !beneath(path, ".code-map")))].sort(compare);
  const files = [];
  for (const path of paths) {
    if (!relativePath(path)) throw new Error(`Git returned an unsupported path: ${JSON.stringify(path)}`);
    const extension = extname(path).toLowerCase();
    const language = extension === ".gleam" ? "gleam" : extension === ".astro" ? "astro"
      : [".ts", ".mts", ".cts", ".tsx"].includes(extension) ? "typescript"
      : extensions.includes(extension) ? "javascript" : null;
    const file = { path, language, status: "pending", reason: null, hash: null, symbols: [], diagnostics: [], skippedRegions: [] };
    const exclusion = config.excludePaths.find((prefix) => beneath(path, prefix))
      ?? path.split("/").slice(0, -1).find((component) => config.excludeDirs.includes(component));
    try {
      const stat = await pathStat(root, path);
      if (!stat.isFile() || exclusion) {
        file.status = "excluded";
        file.reason = exclusion ? `Config exclusion: ${exclusion}` : stat.isSymbolicLink() ? "Symlink (not followed)" : "Not a regular file";
      } else if (!language) {
        file.status = "unsupported";
        file.reason = `No parser for ${extension || "extensionless files"}`;
      } else {
        const bytes = await fs.readFile(join(root, path));
        file.hash = createHash("sha256").update(bytes).digest("hex");
        try { file.source = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(bytes); }
        catch (error) {
          if (error.code !== "ERR_ENCODING_INVALID_ENCODED_DATA") throw error;
          file.status = "unreadable";
          file.diagnostics.push({ path, message: "Source is not valid UTF-8", range: null });
        }
      }
    } catch (error) {
      if (error.code === "ENOENT" || error.code === "ENOTDIR") continue;
      if (!["EACCES", "EPERM", "EIO"].includes(error.code)) throw error;
      file.status = "unreadable";
      file.diagnostics.push({ path, message: `Cannot read source: ${error.code}`, range: null });
    }
    files.push(file);
  }
  return files;
}
