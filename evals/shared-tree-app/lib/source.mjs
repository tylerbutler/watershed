import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { mkdir, rm } from "node:fs/promises";
import { join, resolve } from "node:path";

const exec = promisify(execFile);
const watershedPaths = [
  "gleam.toml", "manifest.toml", "src",
  "watershed_lustre/gleam.toml", "watershed_lustre/manifest.toml", "watershed_lustre/src",
];

export async function snapshotWatershed({ source, revision, out }) {
  if (!/^[a-f0-9]{40}$/.test(revision)) throw new TypeError("SDK revision must be a full commit SHA");
  const resolved = await exec("git", ["rev-parse", `${revision}^{commit}`], { cwd: source });
  if (resolved.stdout.trim() !== revision) throw new Error("SDK commit did not resolve exactly");
  await mkdir(out, { recursive: false });
  const archive = join(resolve(out), ".source.tar");
  try {
    await exec("git", ["archive", "--format=tar", "--output", archive, revision, ...watershedPaths], {
      cwd: source, maxBuffer: 4 * 1024 * 1024,
    });
    await exec("tar", ["-xf", archive, "-C", resolve(out)]);
  } catch (error) {
    await rm(out, { recursive: true, force: true });
    throw error;
  }
  await rm(archive);
  return { revision, root: resolve(out), paths: [...watershedPaths] };
}
