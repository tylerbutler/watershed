import { createHash } from "node:crypto";
import { copyFile, lstat, mkdir, readFile, readdir, realpath } from "node:fs/promises";
import { dirname, join, relative, resolve, sep } from "node:path";

const generated = new Set(["node_modules", "build", "dist", ".git"]);
const editable = {
  fluid: new Set(["src/model.ts", "src/schema.ts"]),
  watershed: new Set(["src/incident_eval/model.gleam", "src/incident_eval/schema.gleam"]),
};
const candidateOwned = (sdk, path) => editable[sdk].has(path) || path.startsWith("test/");
const sdkFile = path => path.startsWith("sdk/");
const hash = async path => createHash("sha256").update(await readFile(path)).digest("hex");

function validatePath(path) {
  if (typeof path !== "string" || !path || path.includes("\\") || path.includes("\0") ||
      path.includes(":") || path.split("/").some(part => !part || part === "." || part === "..")) {
    throw new TypeError(`Invalid manifest path: ${JSON.stringify(path)}`);
  }
}

function validateManifest(manifest) {
  if (manifest?.version !== 1 || !Object.hasOwn(editable, manifest.sdk) ||
      !Array.isArray(manifest.files) || manifest.files.length === 0) {
    throw new TypeError("Invalid integrity manifest");
  }
  const seen = new Set();
  for (const file of manifest.files) {
    validatePath(file?.path);
    if (seen.has(file.path) || !/^[a-f0-9]{64}$/.test(file.sha256)) {
      throw new TypeError(`Invalid or duplicate manifest file: ${file.path}`);
    }
    if (generated.has(file.path.split("/")[0])) {
      throw new TypeError(`Generated path in integrity manifest: ${file.path}`);
    }
    seen.add(file.path);
  }
}

async function entries(workspace) {
  const root = resolve(workspace);
  const stat = await lstat(root);
  if (!stat.isDirectory() || stat.isSymbolicLink()) {
    throw new Error("Workspace must be a real directory, not a symlink");
  }
  const result = [];
  async function walk(directory, prefix = "") {
    for (const entry of (await readdir(directory, { withFileTypes: true })).sort((a, b) =>
      a.name < b.name ? -1 : a.name > b.name ? 1 : 0)) {
      if (!prefix && generated.has(entry.name)) continue;
      const path = prefix + entry.name;
      validatePath(path);
      if (entry.isDirectory()) await walk(join(directory, entry.name), `${path}/`);
      else result.push({ path, kind: entry.isFile() ? "file" : entry.isSymbolicLink() ? "symlink" : "special" });
    }
  }
  await walk(root);
  return result;
}

export async function createIntegrityManifest({ workspace, sdk }) {
  if (!Object.hasOwn(editable, sdk)) throw new TypeError("Unknown integrity SDK");
  const files = [];
  for (const entry of await entries(workspace)) {
    if (entry.kind !== "file") throw new Error(`Cannot stage ${entry.kind}: ${entry.path}`);
    files.push({ path: entry.path, sha256: await hash(join(workspace, entry.path)) });
  }
  const manifest = { version: 1, sdk, files };
  validateManifest(manifest);
  return manifest;
}

export async function verifyIntegrity({ workspace, manifest }) {
  validateManifest(manifest);
  const failures = [];
  const fail = (path, reason) => failures.push({ path, reason });
  const expected = new Map(manifest.files.map(file => [file.path, file.sha256]));
  const actual = new Map((await entries(workspace)).map(entry => [entry.path, entry.kind]));
  for (const [path, kind] of actual) {
    if (kind !== "file") fail(path, kind);
    else if (!expected.has(path) && !candidateOwned(manifest.sdk, path)) fail(path, "unexpected file");
  }
  for (const [path, sha256] of expected) {
    if (editable[manifest.sdk].has(path) && !actual.has(path)) fail(path, "missing candidate source");
    if (candidateOwned(manifest.sdk, path)) continue;
    if (!actual.has(path)) fail(path, "missing protected file");
    else if (actual.get(path) === "file" && await hash(join(workspace, path)) !== sha256) {
      fail(path, "modified protected file");
    }
  }
  const assetsPassed = !failures.some(failure => !sdkFile(failure.path));
  const sdkPassed = !failures.some(failure => sdkFile(failure.path));
  return {
    passed: assetsPassed && sdkPassed, assetsPassed, sdkPassed,
    evidence: failures.length ? failures.map(({ path, reason }) => `${reason}: ${path}`).join("\n")
      : "Protected shell, build configuration, dependencies, and staged SDK match the trusted manifest",
  };
}

export async function assertSeparateRoots({ workspace, trusted }) {
  const source = await realpath(workspace);
  const destination = await realpath(trusted);
  const nested = (parent, child) => {
    const path = relative(parent, child);
    return path === "" || (path !== ".." && !path.startsWith(`..${sep}`) && !path.startsWith(sep));
  };
  if (nested(source, destination) || nested(destination, source)) {
    throw new Error("Trusted grading root must be separate from and outside the agent workspace");
  }
  return { source, destination };
}

export async function overlayCandidate({ workspace, manifest, trusted }) {
  const { source, destination } = await assertSeparateRoots({ workspace, trusted });
  const integrity = await verifyIntegrity({ workspace, manifest });
  if (!integrity.passed) throw new Error(`Candidate integrity failed:\n${integrity.evidence}`);
  for (const entry of await entries(workspace)) {
    if (!candidateOwned(manifest.sdk, entry.path)) continue;
    const target = join(destination, entry.path);
    await mkdir(dirname(target), { recursive: true });
    await copyFile(join(source, entry.path), target);
  }
  return integrity;
}
