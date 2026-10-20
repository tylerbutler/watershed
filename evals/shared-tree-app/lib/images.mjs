import { execFile } from "node:child_process";
import { createHash, randomUUID } from "node:crypto";
import { cp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
import { parse } from "yaml";
import { verifyIntegrity } from "./staging.mjs";

const exec = promisify(execFile);
const benchmark = fileURLToPath(new URL("../", import.meta.url));
const json = value => JSON.stringify(value, null, 2) + "\n";

export async function buildImages({ prepared, out, registry }) {
  const sdk = prepared.sdkManifest.sdk;
  if (!["watershed", "fluid"].includes(sdk) || !out) throw new TypeError("Images require a prepared SDK and output directory");
  const manifest = JSON.parse(await readFile(join(prepared.gradingRoot, "integrity.json"), "utf8"));
  const baseline = join(prepared.gradingRoot, "workspace");
  const integrity = await verifyIntegrity({ workspace: baseline, manifest });
  if (!integrity.passed) throw new Error(`Image baseline integrity failed: ${integrity.evidence}`);
  const registryUrl = new URL(registry ?? (await exec("npm", ["config", "get", "registry"])).stdout.trim());
  if (registryUrl.protocol !== "https:" || registryUrl.username || registryUrl.password ||
      registryUrl.search || registryUrl.hash) {
    throw new TypeError("Image registry must be an HTTPS URL without credentials");
  }
  await exec("podman", ["info"], { timeout: 30_000 });
  const root = resolve(out);
  await mkdir(root);
  const context = join(root, "context");
  const host = JSON.parse(await readFile(
    new URL("../package.json", import.meta.resolve("@microsoft/vally")), "utf8"));
  const result = { version: 1, sdk, revision: prepared.sdkManifest.revision, registry: registryUrl.href };
  result.vallyPatchSha256 = createHash("sha256").update(
    await readFile(join(benchmark, "patches/@microsoft__vally@0.19.0.patch"))).digest("hex");
  const tag = `localhost/shared-tree-eval-${sdk}-${randomUUID().slice(0, 8)}`;
  const build = async (role, args) => {
    try {
      const built = await exec("podman", ["build", ...args],
        { timeout: 1_200_000, maxBuffer: 16 * 1024 * 1024 });
      await writeFile(join(root, `${role}.build.log`), built.stdout + built.stderr);
    } catch (error) {
      await writeFile(join(root, `${role}.build.log`), `${error.stdout ?? ""}\n${error.stderr ?? error.message}`);
      throw new Error(`${role} image build failed:\n${error.stdout?.slice(-8000) ?? ""}\n` +
        `${error.stderr?.slice(-8000) ?? error.message}`, { cause: error });
    }
  };
  try {
    await mkdir(join(context, "benchmark"), { recursive: true });
    for (const path of ["package.json", "pnpm-lock.yaml", "pnpm-workspace.yaml", "patches", "public",
      "lib/services.mjs", "lib/conditions.mjs", "lib/barrier.mjs", "lib/cdp.mjs", "docker/gateway.mjs"]) {
      await cp(join(benchmark, path), join(context, "benchmark", path), { recursive: true });
    }
    await cp(join(benchmark, "docker/Dockerfile"), join(context, "Dockerfile"));
    const copy = source => ({ recursive: true, filter: path => {
      const parts = relative(source, path).split(sep);
      const first = parts[0] === "workspace" ? parts[1] : parts[0];
      return !["node_modules", "build", "dist", ".git"].includes(first);
    } });
    await cp(baseline, join(context, "baseline"), copy(baseline));
    await cp(prepared.gradingRoot, join(context, "grading"), copy(prepared.gradingRoot));
    for (const role of ["task", "grade"]) {
      await build(role, ["--target", role, "--tag", `${tag}:${role}`,
        "--build-arg", `NPM_REGISTRY=${registryUrl.href}`, context]);
      const inspected = JSON.parse((await exec("podman", ["image", "inspect", `${tag}:${role}`])).stdout)[0];
      const id = `sha256:${inspected.Id.replace(/^sha256:/, "")}`;
      const probe = await exec("podman", ["run", "--rm", "--network=none", id,
        "node", "--input-type=module", "-e", `
import { readFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
console.log(JSON.stringify({
  coreVersion: JSON.parse(readFileSync("node_modules/@microsoft/vally/package.json")).version,
  cliVersion: JSON.parse(readFileSync("node_modules/@microsoft/vally-cli/package.json")).version,
  uid: process.getuid(),
  toolchain: Object.fromEntries(["node", "pnpm", "gleam", "chromium"].map(command =>
    [command, execFileSync(command, ["--version"], { encoding: "utf8" }).trim()])),
}));
`], { timeout: 30_000 });
      const metadata = JSON.parse(probe.stdout);
      if (metadata.uid !== 1000 || metadata.coreVersion !== host.version || metadata.cliVersion !== host.version) {
        throw new Error(`Invalid ${role} image identity: non-root and matching Vally core/CLI are required`);
      }
      result[role] = { id, architecture: inspected.Architecture, ...metadata };
    }
    if (sdk === "watershed") {
      const selected = parse(await readFile(join(benchmark, "docker/compose.yaml"), "utf8")).services.floodgate.build;
      const revision = new URL(selected.context).hash.slice(1);
      if (!/^[a-f0-9]{40}$/.test(revision)) throw new Error("Floodgate build requires a full source revision");
      await build("service", ["--target", selected.target, "--tag", `${tag}:service`,
        "--label", `org.opencontainers.image.revision=${revision}`,
        "--file", selected.dockerfile, selected.context]);
      const inspected = JSON.parse((await exec("podman", ["image", "inspect", `${tag}:service`])).stdout)[0];
      result.service = {
        kind: "floodgate", source: selected.context.split("#")[0], revision,
        id: `sha256:${inspected.Id.replace(/^sha256:/, "")}`, architecture: inspected.Architecture,
      };
    } else {
      result.service = {
        kind: "azure-local-service", id: result.task.id, architecture: result.task.architecture,
      };
    }
    if (result.service.architecture !== result.task.architecture) {
      throw new Error("Native service and task image architectures differ");
    }
    await writeFile(join(root, "images.json"), json(result), { flag: "wx" });
    return result;
  } finally {
    await rm(context, { recursive: true, force: true });
  }
}
