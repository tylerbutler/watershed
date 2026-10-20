import { execFile } from "node:child_process";
import { realpath } from "node:fs/promises";
import { dirname } from "node:path";
import { promisify } from "node:util";
import { watershedPaths } from "./source.mjs";

const exec = promisify(execFile);
const fluidRoots = [
  "fluid-framework", "@fluidframework/azure-client",
  "@fluidframework/test-runtime-utils", "@fluidframework/azure-local-service",
];
const excluded = /(^|\/)(\.git|test|tests|examples|fixtures|validation|graders|benchmarks)(\/|$)/;
const watershedDocs = [
  "README.md", "watershed_lustre/README.md",
  "docs/shared-tree-schema-authoring.md", "docs/shared-tree-client-compatibility.md",
];
const dependencies = manifest => ({
  ...manifest.dependencies, ...manifest.optionalDependencies, ...manifest.peerDependencies,
});

export async function resolveSdk({ sdk, source, revision }) {
  if (!["watershed", "fluid"].includes(sdk)) throw new TypeError("Unknown SDK");
  if (typeof revision !== "string" || !/^[a-f0-9]{40}$/.test(revision)) {
    throw new TypeError("SDK revision must be a full commit SHA");
  }
  const root = await realpath(source);
  const git = async args => (await exec("git", args, { cwd: root, maxBuffer: 16 * 1024 * 1024 })).stdout;
  if (await realpath((await git(["rev-parse", "--show-toplevel"])).trim()) !== root) {
    throw new Error("SDK source must be its repository root");
  }
  if ((await git(["rev-parse", `${revision}^{commit}`])).trim() !== revision) {
    throw new Error("SDK revision did not resolve exactly");
  }
  const tree = (await git(["ls-tree", "-rz", "--full-tree", revision])).split("\0").filter(Boolean)
    .map(line => {
      const tab = line.indexOf("\t");
      const metadata = line.slice(0, tab);
      const path = line.slice(tab + 1);
      return { path, mode: metadata.split(" ")[0] };
    });
  const paths = new Set(tree.map(entry => entry.path));
  const read = path => git(["show", `${revision}:${path}`]);
  const required = path => {
    if (!paths.has(path)) throw new Error(`Selected SDK is missing ${path}`);
  };
  let packages;
  let sourceFiles;
  let docs;
  let toolchain;
  if (sdk === "watershed") {
    for (const path of ["gleam.toml", "manifest.toml", "watershed_lustre/gleam.toml",
      "watershed_lustre/manifest.toml", "src/watershed/tree.gleam",
      "watershed_lustre/src/watershed_lustre/tree.gleam"]) required(path);
    const scalar = (text, name) => {
      const value = text.match(new RegExp(`^${name}\\s*=\\s*"([^"]+)"`, "m"))?.[1];
      if (!value) throw new Error(`Missing ${name} in SDK Gleam manifest`);
      return value;
    };
    const manifest = await read("gleam.toml");
    const lustre = await read("watershed_lustre/gleam.toml");
    packages = [
      { name: scalar(manifest, "name"), version: scalar(manifest, "version"), path: "." },
      { name: scalar(lustre, "name"), version: scalar(lustre, "version"), path: "watershed_lustre" },
    ];
    if (packages[0].name !== "watershed" || packages[1].name !== "watershed_lustre") {
      throw new Error("The selected Gleam packages are not Watershed and Watershed Lustre");
    }
    sourceFiles = [...paths].filter(path => watershedPaths.some(base => path === base || path.startsWith(`${base}/`)));
    docs = watershedDocs.filter(path => paths.has(path));
    toolchain = { kind: "gleam", gleam: scalar(manifest, "gleam") };
  } else {
    if ((await git(["rev-parse", "HEAD"])).trim() !== revision) {
      throw new Error("Fluid revision must match checked-out HEAD for the local build");
    }
    if ((await git(["status", "--porcelain=v1", "--untracked-files=no"])).trim()) {
      throw new Error("Fluid SDK has dirty tracked input files; use a clean source checkout");
    }
    for (const path of ["package.json", "pnpm-lock.yaml", "pnpm-workspace.yaml"]) required(path);
    const rootManifest = JSON.parse(await read("package.json"));
    if (!/^pnpm@\d+\.\d+\.\d+(?:\+[^ ]+)?$/.test(rootManifest.packageManager)) {
      throw new Error("Fluid must declare an exact pnpm toolchain");
    }
    const available = new Map();
    for (const path of paths) {
      if (!/^(packages|azure\/packages)\/.+\/package\.json$/.test(path) ||
          excluded.test(path) || /\/(src|dist|lib)\//.test(path)) continue;
      const manifest = JSON.parse(await read(path));
      if (!manifest.name || !manifest.version) continue;
      if (available.has(manifest.name)) throw new Error(`Duplicate local SDK package: ${manifest.name}`);
      available.set(manifest.name, { path: dirname(path), manifest });
    }
    const selected = new Map();
    const version = available.get("fluid-framework")?.manifest.version;
    const visit = name => {
      if (selected.has(name)) return;
      const value = available.get(name);
      if (!value) throw new Error(`Missing local workspace SDK package: ${name}`);
      if (value.manifest.version !== version) {
        throw new Error(`Mixed Fluid client versions: ${name}@${value.manifest.version}, expected ${version}`);
      }
      selected.set(name, value);
      for (const [dependency, range] of Object.entries(dependencies(value.manifest))) {
        if (typeof range !== "string") throw new Error(`Invalid dependency range: ${name} > ${dependency}`);
        if (range.startsWith("workspace:")) {
          if (!["workspace:*", "workspace:~", "workspace:^"].includes(range)) {
            throw new Error(`Unsupported workspace selector: ${name} > ${dependency}: ${range}`);
          }
          visit(dependency);
        }
      }
    };
    for (const name of fluidRoots) visit(name);
    packages = [...selected].map(([name, value]) => ({
      name, version: value.manifest.version, path: value.path,
      workspaceDependencies: Object.entries(dependencies(value.manifest))
        .filter(([, range]) => range.startsWith("workspace:")).map(([name]) => name),
    }));
    const runtimeSource = path => !excluded.test(path) && packages.some(pkg =>
      path === `${pkg.path}/package.json` || path.startsWith(`${pkg.path}/src/`) ||
      path === `${pkg.path}/index.js`);
    const untracked = (await git(["ls-files", "--others", "--exclude-standard", "-z"])).split("\0").filter(Boolean);
    const unexpected = untracked.filter(runtimeSource);
    if (unexpected.length) throw new Error(`Untracked runtime SDK build inputs: ${unexpected.join(", ")}`);
    sourceFiles = [...paths].filter(runtimeSource);
    docs = [...paths].filter(path => packages.some(pkg => path === `${pkg.path}/README.md`));
    toolchain = { kind: "typescript", packageManager: rootManifest.packageManager };
  }
  sourceFiles.push(...["LICENSE", "LICENSE.md"].filter(path => paths.has(path)));
  const selectedFiles = new Set([...sourceFiles, ...docs]);
  for (const entry of tree) {
    if (selectedFiles.has(entry.path) && !["100644", "100755"].includes(entry.mode)) {
      throw new Error(`SDK source contains a symlink or unsupported file: ${entry.path}`);
    }
  }
  return {
    version: 1, sdk, source: root, revision, packages,
    sourceFiles: sourceFiles.sort(), docs: docs.sort(), toolchain,
    sourceProvenance: sdk === "watershed" ? "immutable-git-archive" : "clean-checked-out-build-input",
  };
}
