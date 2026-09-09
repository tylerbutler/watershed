import fs from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { execFileSync, spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

export { fs, join };
export const toolRoot = fileURLToPath(new URL("..", import.meta.url));
export const cli = fileURLToPath(new URL("../cli.mjs", import.meta.url));

export async function temporary(t) {
  const root = await fs.mkdtemp(join(tmpdir(), "code-map-test-"));
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  return root;
}

export async function makeRepo(t, files = {}) {
  const root = await temporary(t);
  git(root, "init", "--quiet");
  for (const [path, content] of Object.entries(files)) await write(root, path, content);
  return root;
}

export async function write(root, path, content) {
  await fs.mkdir(dirname(join(root, path)), { recursive: true });
  await fs.writeFile(join(root, path), content);
}

export function git(root, ...args) {
  return execFileSync("git", ["-C", root, ...args], { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
}

export function runCli(root, args, options = {}) {
  return spawnSync(process.execPath, [cli, ...args], { cwd: root, encoding: "utf8", ...options });
}
