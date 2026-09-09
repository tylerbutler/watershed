import fs from "node:fs/promises";
import { join, extname } from "node:path";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { createHash } from "node:crypto";
import { core } from "./core.mjs";

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
  const paths = core().inventory_paths((await git(root, ["ls-files", "--cached", "--others", "--exclude-standard", "--deduplicate", "-z"])).split("\0"));
  const configuration = core().decode_config(config);
  const files = [];
  for (const path of paths) {
    const extension = extname(path).toLowerCase();
    const file = { path, ...core().classify(configuration, path, extension, true, false),
      hash: null, symbols: [], diagnostics: [], skippedRegions: [] };
    try {
      const stat = await pathStat(root, path);
      Object.assign(file, core().classify(configuration, path, extension, stat.isFile(), stat.isSymbolicLink()));
      if (file.status === "pending") {
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
