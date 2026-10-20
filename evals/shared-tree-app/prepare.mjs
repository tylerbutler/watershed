import { execFile } from "node:child_process";
import { cp, mkdir, readFile, realpath, rm, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs, promisify } from "node:util";
import { parse, stringify } from "yaml";
import { materializeSdk } from "./lib/sdk-build.mjs";
import { createIntegrityManifest } from "./lib/staging.mjs";

const exec = promisify(execFile);
const benchmark = fileURLToPath(new URL("./", import.meta.url));
const json = value => JSON.stringify(value, null, 2) + "\n";

export async function prepare({ sdk, source, revision, out }) {
  if (!["watershed", "fluid"].includes(sdk)) throw new TypeError("Unknown preparation SDK");
  if (!source || !out || typeof revision !== "string" || !/^[a-f0-9]{40}$/.test(revision)) {
    throw new TypeError("Preparation requires source, full commit revision, and output directory");
  }
  const root = resolve(out);
  await mkdir(root, { recursive: false });
  try {
    const agentRoot = join(root, "agent");
    const gradingRoot = join(root, "grading");
    await mkdir(agentRoot);
    await mkdir(gradingRoot);
    const starter = join(benchmark, sdk);
    for (const path of ["AGENTS.md", "package.json", "pnpm-lock.yaml", "pnpm-workspace.yaml",
      "index.html", "build.mjs", "src", ...(sdk === "fluid" ? ["tsconfig.json"] : [])]) {
      await cp(join(starter, path), join(agentRoot, path), { recursive: true });
    }
    await cp(join(benchmark, "task.md"), join(agentRoot, "task.md"));
    await mkdir(join(agentRoot, "sdk"));
    const sdkPath = `sdk/${sdk}`;
    const selected = await materializeSdk({ sdk, source, revision, out: join(agentRoot, sdkPath) });
    if (sdk === "watershed") {
      for (const name of ["gleam.toml", "manifest.toml"]) {
        const template = await readFile(join(starter, `${name}.in`), "utf8");
        await writeFile(join(agentRoot, name), template
          .replaceAll("../sdk/watershed_lustre", "sdk/watershed/watershed_lustre")
          .replaceAll("../sdk/watershed", "sdk/watershed"));
      }
    } else {
      const manifest = JSON.parse(await readFile(join(agentRoot, "package.json"), "utf8"));
      const config = parse(await readFile(join(agentRoot, "pnpm-workspace.yaml"), "utf8"));
      const local = new Map(selected.packages.map(pkg => [pkg.name, `file:./${sdkPath}/${pkg.stagedPath}`]));
      for (const group of ["dependencies", "devDependencies"]) {
        for (const name of Object.keys(manifest[group])) {
          if (local.has(name)) manifest[group][name] = local.get(name);
        }
      }
      config.overrides = {};
      for (const pkg of selected.packages) {
        for (const dependency of pkg.workspaceDependencies) {
          config.overrides[`${pkg.name}@${pkg.version}>${dependency}`] = local.get(dependency);
        }
      }
      await writeFile(join(agentRoot, "package.json"), json(manifest));
      await writeFile(join(agentRoot, "pnpm-workspace.yaml"), stringify(config));
      try {
        await exec("pnpm", ["install", "--lockfile-only", "--ignore-scripts", "--no-frozen-lockfile"],
          { cwd: agentRoot, timeout: 300_000, maxBuffer: 4 * 1024 * 1024 });
      } catch (error) {
        throw new Error(`Could not lock staged Fluid dependencies:\n${error.stdout ?? ""}\n${error.stderr ?? error.message}`);
      }
      const lock = parse(await readFile(join(agentRoot, "pnpm-lock.yaml"), "utf8"));
      for (const pkg of selected.packages) {
        if (lock.packages[`${pkg.name}@${pkg.version}`] ||
            !Object.keys(lock.packages).some(key =>
              key.startsWith(`${pkg.name}@file:${sdkPath}/${pkg.stagedPath}`))) {
          throw new Error(`Selected SDK package fell back to the registry: ${pkg.name}@${pkg.version}`);
        }
      }
    }
    const sdkManifest = {
      version: 1, sdk, revision, root: sdkPath, packages: selected.packages,
      sourceFiles: selected.sourceFiles, docs: selected.docs, toolchain: selected.toolchain,
      sourceProvenance: selected.sourceProvenance, build: selected.build,
    };
    await writeFile(join(agentRoot, "SDK.json"), json(sdkManifest));
    const integrityManifest = await createIntegrityManifest({ workspace: agentRoot, sdk });
    const hashes = new Map(integrityManifest.files.map(file => [file.path, file.sha256]));
    const docsManifest = {
      version: 1, sdk, revision,
      files: selected.docs.map(path => {
        const staged = `${sdkPath}/${sdk === "fluid" ? "source/" : ""}${path}`;
        const sha256 = hashes.get(staged);
        if (!sha256) throw new Error(`Staged SDK documentation is missing: ${staged}`);
        return { path: staged, sha256 };
      }),
    };
    await cp(agentRoot, join(gradingRoot, "workspace"), { recursive: true });
    for (const path of ["graders", "lib", "docker/compose.yaml", "contract.json",
      "package.json", "pnpm-lock.yaml", "pnpm-workspace.yaml"]) {
      await cp(join(benchmark, path), join(gradingRoot, path), { recursive: true });
    }
    for (const [name, value] of Object.entries({
      integrity: integrityManifest, sdk: sdkManifest, docs: docsManifest,
    })) await writeFile(join(gradingRoot, `${name}.json`), json(value));
    if (selected.buildLog) await writeFile(join(gradingRoot, "sdk-build.log"), selected.buildLog);
    return { agentRoot, gradingRoot, integrityManifest, sdkManifest, docsManifest };
  } catch (error) {
    await rm(root, { recursive: true, force: true });
    throw error;
  }
}

if (process.argv[1] && process.argv[1] !== "-" &&
    await realpath(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const { values } = parseArgs({ options: Object.fromEntries(
      ["sdk", "source", "revision", "out"].map(name => [name, { type: "string" }])) });
    const prepared = await prepare(values);
    console.log(json({ agentRoot: prepared.agentRoot, gradingRoot: prepared.gradingRoot }).trim());
  } catch (error) {
    console.error(error.stack ?? String(error));
    process.exitCode = 1;
  }
}
