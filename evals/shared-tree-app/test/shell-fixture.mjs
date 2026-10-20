import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { existsSync } from "node:fs";
import { cp, copyFile, mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { createServer } from "node:http";
import { join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { snapshotWatershed } from "../lib/source.mjs";

const exec = promisify(execFile);
const root = fileURLToPath(new URL("../", import.meta.url));
const repository = resolve(root, "../..");

export async function buildShellFixture(sdk, { fake = true, solution = false, grader = false, schemaFixture } = {}) {
  const work = join(root, ".work");
  await mkdir(work, { recursive: true });
  const path = await mkdtemp(join(work, `shell-${sdk}-`));
  let server;
  try {
    await cp(join(root, sdk), path, { recursive: true, filter: source =>
      !["node_modules", "dist", "build"].some(name =>
        relative(join(root, sdk), source).split("/").includes(name)) });
    if (solution) {
      const extension = sdk === "fluid" ? "ts" : "gleam";
      const destination = sdk === "fluid" ? "src" : "src/incident_eval";
      for (const name of ["model", "schema"]) {
        await copyFile(join(root, "validation/solutions", sdk, `${name}.${extension}`), join(path, destination, `${name}.${extension}`));
      }
    }
    if (schemaFixture) {
      await copyFile(schemaFixture, join(path, sdk === "fluid" ? "src/schema.ts" : "src/incident_eval/schema.gleam"));
    }
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
    await exec("pnpm", ["install", "--frozen-lockfile"], { cwd: path, timeout: 180_000 });
    await exec("pnpm", ["check"], { cwd: path, timeout: 180_000 });
    await exec("pnpm", ["build"], { cwd: path, timeout: 180_000 });
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
      url: `http://127.0.0.1:${server.address().port}/`,
      async close() {
        await new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
        await rm(path, { recursive: true, force: true });
      },
    };
  } catch (error) {
    if (server?.listening) await new Promise(resolve => server.close(resolve));
    await rm(path, { recursive: true, force: true });
    if (error.cmd) throw new Error(`${error.cmd} failed:\n${error.stdout?.slice(-6000) ?? ""}\n${error.stderr?.slice(-6000) ?? error.message}`);
    throw error;
  }
}
