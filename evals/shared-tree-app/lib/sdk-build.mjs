import { execFile } from "node:child_process";
import { createHash } from "node:crypto";
import { copyFile, lstat, mkdir, mkdtemp, realpath, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { basename, dirname, join, resolve, sep } from "node:path";
import { promisify } from "node:util";
import { resolveSdk } from "./sdk.mjs";

const exec = promisify(execFile);
const excluded = /(^|\/)(\.git|test|tests|examples|fixtures|validation|graders|benchmarks)(\/|$)/;

async function archive({ source, revision, out, archivePath, files = [] }) {
  await exec("git", ["archive", "--format=tar", "--output", archivePath, revision, "--", ...files],
    { cwd: source, maxBuffer: 4 * 1024 * 1024 });
  await exec("tar", ["-xf", archivePath, "-C", out], { maxBuffer: 4 * 1024 * 1024 });
  await rm(archivePath);
}

async function fluidBuild(selected, out, scratch) {
  const source = join(scratch, "source");
  await mkdir(source);
  await archive({ ...selected, source: selected.source, out: source, archivePath: join(scratch, "full.tar") });
  const logs = [];
  const run = async (command, args, cwd = source) => {
    try {
      const result = await exec(command, args, {
        cwd, timeout: 600_000, maxBuffer: 16 * 1024 * 1024,
        env: { ...process.env, npm_config_ignore_scripts: "true" },
      });
      logs.push(result.stdout, result.stderr);
      return result.stdout;
    } catch (error) {
      throw new Error(`SDK preparation failed: ${command} ${args.join(" ")}\n` +
        `${error.stdout?.slice(-6000) ?? ""}\n${error.stderr?.slice(-6000) ?? error.message}`);
    }
  };
  const packageManager = (await run("pnpm", ["--version"])).trim();
  if (`pnpm@${packageManager}` !== selected.toolchain.packageManager.split("+")[0]) {
    throw new Error(`Fluid requires ${selected.toolchain.packageManager}, found pnpm@${packageManager}`);
  }
  const filters = ["fluid-framework...", "@fluidframework/azure-client...",
    "@fluidframework/test-runtime-utils...", "@fluidframework/azure-local-service..."];
  await run("pnpm", [...filters.flatMap(value => ["--filter", value]),
    "install", "--frozen-lockfile", "--ignore-scripts"]);
  const buildArgs = ["exec", "fluid-build", "--root", source, "--task", "build:package:esm",
    "^fluid-framework$|^@fluidframework/(azure-client|test-runtime-utils|azure-local-service)$"];
  await run("pnpm", buildArgs);
  const packages = [];
  const names = new Set();
  for (const pkg of selected.packages) {
    const directory = pkg.name.replace(/^@/, "").replaceAll("/", "-");
    if (!/^[a-z0-9-]+$/.test(directory) || names.has(directory)) {
      throw new Error(`Unsupported or colliding SDK package name: ${pkg.name}`);
    }
    names.add(directory);
    const packed = join(scratch, directory);
    await mkdir(packed);
    const packageRoot = await realpath(join(source, pkg.path));
    const metadata = JSON.parse(await run("pnpm", ["pack", "--json", "--pack-destination", packed],
      packageRoot));
    if (metadata.name !== pkg.name || metadata.version !== pkg.version || !Array.isArray(metadata.files)) {
      throw new Error(`Packed SDK identity does not match ${pkg.name}@${pkg.version}`);
    }
    const packageJson = await run("tar", ["-xOf", join(packed, basename(metadata.filename)),
      "package/package.json"]);
    const stagedPath = `packages/${directory}`;
    const destination = join(out, stagedPath);
    await mkdir(destination, { recursive: true });
    await writeFile(join(destination, "package.json"), packageJson);
    let runtimeFiles = 0;
    for (const { path } of metadata.files) {
      if (typeof path !== "string" || path.includes("\\") ||
          path.split("/").some(part => !part || part === "." || part === "..")) {
        throw new Error(`Invalid SDK package path: ${JSON.stringify(path)}`);
      }
      if (excluded.test(path) || path.endsWith(".map")) continue;
      if (!path.startsWith("lib/") && !["index.js", "README.md", "LICENSE", "LICENSE.md"].includes(path) &&
          !/^[a-z]+\.d\.ts$/.test(path)) continue;
      const original = join(source, pkg.path, path);
      const canonical = await realpath(original);
      if (!(await lstat(original)).isFile() ||
          !canonical.startsWith(packageRoot + sep)) {
        throw new Error(`SDK package contains a symlink escape or non-file: ${pkg.name}/${path}`);
      }
      const target = join(destination, path);
      await mkdir(dirname(target), { recursive: true });
      await copyFile(original, target);
      if (path.startsWith("lib/") || path === "index.js") runtimeFiles++;
    }
    if (runtimeFiles === 0) throw new Error(`Local SDK build has no runtime output for ${pkg.name}`);
    packages.push({ ...pkg, stagedPath });
  }
  return {
    packages,
    buildLog: logs.join(""),
    build: {
      mode: "esm", revision: selected.revision, node: process.version, packageManager,
      task: "build:package:esm", freshSourceArchive: true,
      logSha256: createHash("sha256").update(logs.join("")).digest("hex"),
    },
  };
}

export async function materializeSdk({ sdk, source, revision, out }) {
  const selected = await resolveSdk({ sdk, source, revision });
  const destination = resolve(out);
  await mkdir(destination, { recursive: false });
  let scratch;
  try {
    scratch = await mkdtemp(join(tmpdir(), "shared-tree-sdk-build-"));
    const sources = sdk === "fluid" ? join(destination, "source") : destination;
    if (sdk === "fluid") await mkdir(sources);
    await archive({
      ...selected, out: sources, archivePath: join(scratch, "allowed.tar"),
      files: [...selected.sourceFiles, ...selected.docs],
    });
    const built = sdk === "fluid" ? await fluidBuild(selected, destination, scratch)
      : { packages: selected.packages, build: { mode: "source", revision } };
    return { ...selected, root: destination, ...built };
  } catch (error) {
    await rm(destination, { recursive: true, force: true });
    throw error;
  } finally {
    if (scratch) await rm(scratch, { recursive: true, force: true });
  }
}
