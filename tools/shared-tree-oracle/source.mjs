import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import {
  copyFile, lstat, mkdir, mkdtemp, readFile, realpath, rename, rm,
} from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const directory = dirname(fileURLToPath(import.meta.url));
const checkout = join(directory, ".reference/FluidFramework");
const oracleSource = join(directory, "upstream-oracle.spec.ts");

export const reference = {
  version: "3.1.0",
  commit: "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960",
  tag: "client_v3.1.0",
  packages: [
    "@fluidframework/tree",
    "@fluidframework/local-driver",
    "fluid-framework",
  ],
};

export const injectedTestPath = "packages/dds/tree/src/test/watershedOracle.spec.ts";

export async function verifyPackages(root = directory) {
  const versions = {};
  for (const name of reference.packages) {
    const manifest = JSON.parse(
      await readFile(join(root, "node_modules", name, "package.json"), "utf8"),
    );
    if (manifest.name !== name || manifest.version !== reference.version) {
      throw new Error(
        `Expected ${name}@${reference.version}; found ${manifest.name}@${manifest.version}`,
      );
    }
    versions[name] = manifest.version;
  }
  return versions;
}

function git(root, ...args) {
  return execFileSync("git", ["-C", root, ...args], { encoding: "utf8" }).trim();
}

export async function verifyCheckout(root = checkout, expectedCommit = reference.commit) {
  if ((await lstat(root)).isSymbolicLink()) {
    throw new Error("The reference checkout must not be a symbolic link");
  }
  const actualRoot = await realpath(root);
  if (await realpath(git(root, "rev-parse", "--show-toplevel")) !== actualRoot) {
    throw new Error(`Reference directory is not a repository root: ${root}`);
  }
  const commit = git(root, "rev-parse", "HEAD");
  if (commit !== expectedCommit) {
    throw new Error(`Expected reference commit ${expectedCommit}; found ${commit}`);
  }
  const changed = git(root, "diff", "--name-only", "HEAD", "--");
  if (changed !== "") {
    throw new Error(`Reference checkout has changed tracked files:\n${changed}`);
  }
  const untracked = git(root, "ls-files", "--others", "--exclude-standard", "-z")
    .split("\0")
    .filter(Boolean);
  for (const path of untracked) {
    if (path !== injectedTestPath) {
      throw new Error(`Reference checkout has an unrelated untracked file: ${path}`);
    }
    const [actual, expected] = await Promise.all([
      readFile(join(root, path)),
      readFile(oracleSource),
    ]);
    if (!actual.equals(expected)) {
      throw new Error(`The injected oracle test has unexpected content: ${path}`);
    }
  }
  const manifest = JSON.parse(
    await readFile(join(root, "packages/dds/tree/package.json"), "utf8"),
  );
  if (manifest.name !== "@fluidframework/tree" || manifest.version !== reference.version) {
    throw new Error(`Reference source is not @fluidframework/tree@${reference.version}`);
  }
  return { commit, version: manifest.version };
}

function run(command, args, cwd, env = process.env) {
  execFileSync(command, args, { cwd, env, stdio: "inherit" });
}

async function pnpm(args, cwd, env = process.env) {
  const manifest = JSON.parse(await readFile(join(checkout, "package.json"), "utf8"));
  const manager = manifest.packageManager.split("+")[0];
  if (!/^pnpm@\d+\.\d+\.\d+$/.test(manager)) {
    throw new Error(`Unsupported reference package manager: ${manifest.packageManager}`);
  }
  run("npm", ["exec", "--yes", `--package=${manager}`, "--", "pnpm", ...args], cwd, env);
}

async function injectOracle() {
  const target = join(checkout, injectedTestPath);
  await mkdir(dirname(target), { recursive: true });
  await copyFile(oracleSource, target);
}

export async function prepareSource() {
  await verifyPackages();
  if (!existsSync(checkout)) {
    await mkdir(dirname(checkout), { recursive: true });
    run("git", [
      "clone", "--quiet", "--sparse", "--filter=blob:none", "--depth", "1",
      "--branch", reference.tag, "https://github.com/microsoft/FluidFramework.git",
      checkout,
    ], directory);
    run("git", [
      "-C", checkout, "sparse-checkout", "set", "--no-cone",
      "/*", "!/packages/dds/tree/src/test/snapshots/output/",
    ], directory);
  }
  await verifyCheckout();
  await injectOracle();
  await pnpm([
    "install", "--frozen-lockfile",
    "--filter", "@fluidframework/tree...", "--filter", ".",
  ], checkout, { ...process.env, PUPPETEER_SKIP_DOWNLOAD: "true" });
  await verifyCheckout();
}

export function validateCapture(capture) {
  if (capture === null || typeof capture !== "object" || capture.formatVersion !== 1) {
    throw new Error("Missing or invalid source capture");
  }
  if (capture.reference?.commit !== reference.commit
    || capture.reference?.version !== reference.version) {
    throw new Error("Source capture has a different reference identity");
  }
  if (!Array.isArray(capture.messages) || capture.messages.length === 0) {
    throw new Error("Source capture has no messages");
  }
  for (const field of ["codecTree", "compressor", "compressorFormat", "summary", "observations"]) {
    if (capture[field] === undefined || capture[field] === null) {
      throw new Error(`Source capture is missing ${field}`);
    }
  }
  if (capture.kind !== "source-smoke"
    || typeof capture.minVersionForCollab !== "string"
    || capture.minVersionForCollab.length === 0) {
    throw new Error("Source capture has no supported format context");
  }
  for (const state of ["pending", "settled"]) {
    const values = capture.observations[state];
    if (!Array.isArray(values) || values.length !== 2 || !values.every(Number.isFinite)) {
      throw new Error(`Source capture has invalid observations.${state}`);
    }
  }
}

export async function publishCapture(output, produce) {
  await mkdir(output, { recursive: true });
  const temporary = await mkdtemp(join(resolve(output), ".capture-"));
  try {
    await produce(temporary);
    const generated = join(temporary, "source-smoke.json");
    validateCapture(JSON.parse(await readFile(generated, "utf8")));
    await rename(generated, join(output, "source-smoke.json"));
  } finally {
    await rm(temporary, { recursive: true, force: true });
  }
}

export async function captureSource(output) {
  await verifyPackages();
  await verifyCheckout();
  await injectOracle();
  const tree = join(checkout, "packages/dds/tree");
  await pnpm(["run", "build:compile"], tree);
  await pnpm(["run", "build:test:esm"], tree);
  await publishCapture(output, async (temporary) => {
    await pnpm([
      "exec", "mocha", "--no-config", "--fail-zero", "--timeout", "30000",
      "--node-option", "conditions=allow-ff-test-exports",
      "lib/test/watershedOracle.spec.js",
    ], tree, {
      ...process.env,
      WATERSHED_ORACLE_OUTPUT: temporary,
      WATERSHED_ORACLE_COMMIT: reference.commit,
    });
    await verifyCheckout();
  });
}

async function main() {
  const [command, output] = process.argv.slice(2);
  switch (command) {
    case "prepare":
      await prepareSource();
      break;
    case "verify":
      console.log(JSON.stringify({
        packages: await verifyPackages(),
        source: await verifyCheckout(),
      }, null, 2));
      break;
    case "generate":
      await captureSource(resolve(output ?? join(directory, ".output/source")));
      break;
    default:
      throw new Error("Usage: node source.mjs prepare|verify|generate [output-directory]");
  }
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
}
