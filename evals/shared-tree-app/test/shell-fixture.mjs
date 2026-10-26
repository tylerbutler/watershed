import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { existsSync } from "node:fs";
import { cp, copyFile, mkdir, mkdtemp, readFile, rename, rm, rmdir, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { createServer } from "node:http";
import { join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { snapshotWatershed } from "../lib/source.mjs";
import { wait } from "../lib/conditions.mjs";
import { validateTrack } from "../lib/tracks.mjs";

const exec = promisify(execFile);
const root = fileURLToPath(new URL("../", import.meta.url));
const repository = resolve(root, "../..");

export async function buildShellFixture(sdk, { fake = true, solution = false, grader = false,
  schemaFixture, modelFixture, dependencyCache = join(root, ".work/dependency-cache"), track = "core",
  mutate } = {}) {
  validateTrack(track);
  const work = join(root, ".work");
  await mkdir(work, { recursive: true });
  const path = await mkdtemp(join(work, `shell-${sdk}-`));
  let server;
  let cacheEntry;
  let cacheLock;
  let cacheTemp;
  const releaseCache = async () => {
    if (cacheLock) {
      const owned = cacheLock;
      cacheLock = undefined;
      await rmdir(owned);
    }
  };
  const fingerprints = ["watershed.config_fingerprint", "watershed_lustre.config_fingerprint"];
  try {
    await cp(join(root, sdk), path, { recursive: true, filter: source =>
      !["node_modules", "dist", "build"].some(name =>
        relative(join(root, sdk), source).split("/").includes(name)) });
    if (track !== "core") {
      await cp(join(root, "tracks", track, sdk), path, { recursive: true });
    }
    if (solution) {
      const extension = sdk === "fluid" ? "ts" : "gleam";
      const destination = sdk === "fluid" ? "src" : "src/incident_eval";
      for (const name of ["model", "schema"]) {
        await copyFile(join(root, "validation/solutions", ...(track === "core" ? [] : [track]),
          sdk, `${name}.${extension}`), join(path, destination, `${name}.${extension}`));
      }
    }
    if (schemaFixture) {
      await copyFile(schemaFixture, join(path, sdk === "fluid" ? "src/schema.ts" : "src/incident_eval/schema.gleam"));
    }
    if (modelFixture) {
      if (sdk !== "fluid") throw new Error("The selected model fixture requires Fluid");
      await copyFile(join(path, "src/model.ts"), join(path, "src/reference-model.ts"));
      await copyFile(modelFixture, join(path, "src/model.ts"));
    }
    if (mutate) await mutate(path);
    if (sdk === "fluid" && fake && !solution) {
      const fixture = await readFile(join(root, "test/fixtures/fluid-model.ts"), "utf8");
      await writeFile(join(path, "src/model.ts"), fixture.replace(
        '"../../fluid/src/domain.ts"', '"./domain.ts"',
      ));
    } else if (sdk === "watershed") {
      const revision = (await exec("git", ["rev-parse", "HEAD"], { cwd: repository })).stdout.trim();
      const sdkRoot = join(path, "sdk");
      await snapshotWatershed({ source: repository, revision, out: sdkRoot });
      const manifest = (await readFile(join(path, "gleam.toml.in"), "utf8"))
        .replace("../sdk/watershed\"", `${sdkRoot}"`)
        .replace("../sdk/watershed_lustre\"", `${join(sdkRoot, "watershed_lustre")}"`);
      await writeFile(join(path, "gleam.toml"), manifest);
      const lock = join(path, "manifest.toml.in");
      if (existsSync(lock)) {
        const content = (await readFile(lock, "utf8"))
          .replaceAll("../sdk/watershed_lustre", join(sdkRoot, "watershed_lustre"))
          .replaceAll("../sdk/watershed", sdkRoot);
        await writeFile(join(path, "manifest.toml"), content);
      }
      if (fake && !solution) {
        await copyFile(join(root, "test/fixtures/watershed-model.gleam"), join(path, "src/incident_eval/model.gleam"));
        await writeFile(join(path, "src/incident_eval/fixture.mjs"),
          `globalThis.__actions = [];
export function record(text) { globalThis.__actions.push(JSON.parse(text)); }
export function empty() { return new URL(location.href).searchParams.has("empty"); }
export function failEdit() { return new URL(location.href).searchParams.has("fail-edit"); }
`);
      }
    }
    if (sdk === "watershed") {
      const inputs = await Promise.all(["sdk/gleam.toml", "sdk/watershed_lustre/gleam.toml",
        "gleam.toml.in", "manifest.toml.in"].map(name => readFile(join(path, name), "utf8")));
      const version = (await exec("gleam", ["--version"])).stdout;
      const key = createHash("sha256").update(JSON.stringify([version, ...inputs])).digest("hex");
      await mkdir(dependencyCache, { recursive: true });
      cacheEntry = join(dependencyCache, key);
      const lock = `${cacheEntry}.lock`;
      await wait("Gleam dependency fingerprint cache lock", async () => {
        try { await mkdir(lock); cacheLock = lock; return true; }
        catch (error) { if (error.code === "EEXIST") return false; throw error; }
      }, Boolean, 180_000);
      if (existsSync(cacheEntry)) {
        await mkdir(join(path, "build/packages"), { recursive: true });
        for (const name of fingerprints) {
          await copyFile(join(cacheEntry, name), join(path, "build/packages", name));
        }
        await releaseCache();
      }
    }
    await exec("pnpm", ["install", "--frozen-lockfile"], { cwd: path, timeout: 180_000 });
    const checked = await exec("pnpm", ["check"], { cwd: path, timeout: 180_000 });
    const built = await exec("pnpm", ["build"], { cwd: path, timeout: 180_000 });
    if (cacheLock) {
      cacheTemp = await mkdtemp(`${cacheEntry}.tmp-`);
      for (const name of fingerprints) await copyFile(join(path, "build/packages", name), join(cacheTemp, name));
      await rename(cacheTemp, cacheEntry);
      cacheTemp = undefined;
      await releaseCache();
    }
    if (grader) {
      await copyFile(join(root, "graders", sdk, "native.mjs"), join(path, "grade-native.mjs"));
      const entry = sdk === "fluid" ? "./src/index.tsx" : "./build/dev/javascript/incident_eval/incident_eval/shell.mjs";
      await writeFile(join(path, "grade-entry.mjs"), `export * from ${JSON.stringify(entry)};\nimport "./grade-native.mjs";\n`);
      await exec(process.execPath, ["--input-type=module", "-e", `
import { build } from "esbuild";
await build({ entryPoints: ["grade-entry.mjs"], bundle: true, format: "esm", outfile: "dist/app.js",
define: { "process.env.NODE_ENV": '"production"' } });
`], { cwd: path, timeout: 180_000 });
    }
    server = createServer(async (request, response) => {
      const url = new URL(request.url, "http://fixture");
      const file = url.pathname === "/" ? "index.html" : url.pathname.slice(1);
      if (!["index.html", "app.js"].includes(file)) { response.writeHead(404).end(); return; }
      try {
        const content = await readFile(join(path, "dist", file));
        response.writeHead(200, { "content-type": file.endsWith(".js") ? "text/javascript" : "text/html" });
        response.end(content);
      } catch (error) {
        response.writeHead(500).end(String(error));
      }
    });
    await new Promise((resolve, reject) => {
      server.once("error", reject);
      server.listen(0, "127.0.0.1", resolve);
    });
    return {
      workspace: path,
      compilation: checked.stdout + checked.stderr + built.stdout + built.stderr,
      url: `http://127.0.0.1:${server.address().port}/`,
      async close() {
        await new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
        await rm(path, { recursive: true, force: true });
      },
    };
  } catch (error) {
    if (cacheTemp) await rm(cacheTemp, { recursive: true, force: true });
    await releaseCache();
    if (server?.listening) await new Promise(resolve => server.close(resolve));
    await rm(path, { recursive: true, force: true });
    if (error.cmd) throw new Error(`${error.cmd} failed:\n${error.stdout?.slice(-6000) ?? ""}\n${error.stderr?.slice(-6000) ?? error.message}`);
    throw error;
  }
}
