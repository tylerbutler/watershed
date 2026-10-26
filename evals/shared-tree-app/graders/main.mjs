import { randomUUID } from "node:crypto";
import { cp, copyFile, link, lstat, mkdir, mkdtemp, readFile, realpath, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import { assertSeparateRoots, overlayCandidate, verifyIntegrity } from "../lib/staging.mjs";
import { validateReport, verdict } from "../lib/report.mjs";
import { launchBrowser } from "../lib/cdp.mjs";
import { startServices } from "../lib/services.mjs";
import { runScenarios } from "./scenarios.mjs";
import { execOwned } from "../lib/process.mjs";
import { validateContract } from "../lib/contract.mjs";
import { validateTrack } from "../lib/tracks.mjs";
import { runTransferScenarios } from "./transfers.mjs";

const moduleRoot = fileURLToPath(new URL("../", import.meta.url));

async function bundleProbe({ sdk, root, gradingRoot, run }) {
  await copyFile(join(gradingRoot, "graders", sdk, "native.mjs"), join(root, "grade-native.mjs"));
  const entry = sdk === "fluid" ? "./src/index.tsx"
    : "./build/dev/javascript/incident_eval/incident_eval/shell.mjs";
  await writeFile(join(root, "grade-entry.mjs"),
    `export * from ${JSON.stringify(entry)};\nimport "./grade-native.mjs";\n`);
  await run(process.execPath, ["--input-type=module", "-e", `
import { build } from "esbuild";
await build({ entryPoints: ["grade-entry.mjs"], bundle: true, format: "esm",
outfile: "dist/app.js", define: { "process.env.NODE_ENV": '"production"' } });
`]);
}

export async function grade({ sdk, workspace, gradingRoot = moduleRoot, runId, output, signal }) {
  if (!["watershed", "fluid"].includes(sdk) || typeof runId !== "string" ||
      !/^[a-z0-9][a-z0-9-]*$/.test(runId) || !workspace || !output) {
    throw new TypeError("Grading requires SDK, workspace, lowercase run ID, and report output");
  }
  const contract = validateContract(JSON.parse(await readFile(join(gradingRoot, "contract.json"), "utf8")));
  const target = resolve(output);
  for (const path of [target, `${target}.build.log`]) {
    try {
      await lstat(path);
      throw new Error(`Grading output already exists: ${path}`);
    } catch (error) {
      if (error.code !== "ENOENT") throw error;
    }
  }
  const checks = new Map();
  let classification = "agent";
  let phase = "preflight";
  let stopped = "Grading did not reach this check";
  let temporary;
  let root;
  let services;
  let browser;
  let buildStarted;
  const logs = [];
  const record = check => {
    if (!contract.checks.some(value => value.id === check.id) || checks.has(check.id)) {
      throw new Error(`Unexpected or duplicate grading check: ${check.id}`);
    }
    checks.set(check.id, check);
  };
  const run = async (command, args) => {
    try {
      const result = await execOwned(command, args, {
        cwd: root, timeout: 180_000, maxBuffer: 4 * 1024 * 1024, signal,
      });
      logs.push(`${phase}: ${command} ${args.join(" ")}\n${result.stdout}${result.stderr}`);
    } catch (error) {
      logs.push(`${phase}: ${command} ${args.join(" ")}\n${error.stdout ?? ""}${error.stderr ?? error.message}`);
      throw new Error(`${command} ${args.join(" ")} failed:\n` +
        `${error.stdout?.slice(-6000) ?? ""}\n${error.stderr?.slice(-6000) ?? error.message}`);
    }
  };
  try {
    signal?.throwIfAborted();
    await assertSeparateRoots({ workspace, trusted: gradingRoot });
    const manifest = JSON.parse(await readFile(join(gradingRoot, "integrity.json"), "utf8"));
    const selected = JSON.parse(await readFile(join(gradingRoot, "sdk.json"), "utf8"));
    const track = validateTrack(selected.track ?? "core");
    if (selected.sdk !== sdk || manifest.sdk !== sdk) throw new Error("Grading SDK does not match the trusted manifests");
    const baseline = join(gradingRoot, "workspace");
    const trusted = await verifyIntegrity({ workspace: baseline, manifest });
    if (!trusted.passed) throw new Error(`Trusted baseline integrity failed:\n${trusted.evidence}`);
    phase = "candidate-integrity";
    const started = performance.now();
    const integrity = await verifyIntegrity({ workspace, manifest });
    for (const [id, passed] of [["integrity.assets", integrity.assetsPassed], ["integrity.sdk", integrity.sdkPassed]]) {
      record({ id, passed, durationMs: performance.now() - started, evidence: integrity.evidence });
    }
    if (!integrity.passed) throw new Error(`Candidate integrity failed:\n${integrity.evidence}`);

    phase = "preflight";
    temporary = await mkdtemp(join(tmpdir(), "shared-tree-grade-"));
    root = join(temporary, "workspace");
    await cp(baseline, root, { recursive: true, verbatimSymlinks: true });
    await run("pnpm", ["check"]);
    await run("pnpm", ["build"]);
    await bundleProbe({ sdk, root, gradingRoot, run });
    services = await startServices({ sdk, root, runId });
    if (!await services.health()) throw new Error("Independent native service health preflight failed");
    browser = await launchBrowser();
    signal?.throwIfAborted();

    phase = "candidate-build";
    buildStarted = performance.now();
    await overlayCandidate({ workspace, manifest, trusted: root });
    await run("pnpm", ["check"]);
    await run("pnpm", ["build"]);
    await bundleProbe({ sdk, root, gradingRoot, run });
    record({ id: "integrity.build", passed: true, durationMs: performance.now() - buildStarted,
      evidence: "Candidate sources passed native checking and a fresh trusted app/probe build" });
    phase = "scenarios";
    await runScenarios({ sdk, services, browser, record, signal });
    if (track === "transfers") await runTransferScenarios({ services, browser, record, signal });
  } catch (error) {
    stopped = `${phase} failed: ${error.stack ?? error.message}`;
    if (phase === "preflight" || signal?.aborted) classification = "infrastructure";
    if (phase === "candidate-build" && !checks.has("integrity.build")) {
      record({ id: "integrity.build", passed: false,
        durationMs: performance.now() - buildStarted, evidence: stopped });
    }
    if (services) {
      try {
        if (!await services.health()) {
          classification = "infrastructure";
          stopped += "\nIndependent native service health probe failed";
        }
      } catch (healthError) {
        classification = "infrastructure";
        stopped += `\nIndependent health probe could not run: ${healthError.message}`;
      }
    }
  } finally {
    for (const [label, close] of [
      ["browser", () => browser?.close()], ["services", () => services?.close()],
      ["grading workspace", () => temporary && rm(temporary, { recursive: true, force: true })],
    ]) {
      try { await close(); }
      catch (error) {
        classification = "infrastructure";
        stopped += `\n${label} cleanup failed: ${error.stack ?? error.message}`;
      }
    }
  }
  if (signal?.aborted) {
    classification = "infrastructure";
    stopped += `\nGrading interrupted: ${signal.reason?.message ?? "Cancellation requested"}`;
  }
  const report = {
    version: 1, runId, sdk, classification,
    checks: contract.checks.map(({ id }) => checks.get(id) ?? {
      id, passed: false, durationMs: 0, evidence: `Not reached: ${stopped}`,
    }),
  };
  if (classification === "infrastructure") {
    report.checks[0] = { ...report.checks[0], evidence: report.checks[0].evidence + `\nInfrastructure: ${stopped}` };
  }
  validateReport(report, contract);
  await mkdir(dirname(target), { recursive: true });
  await writeFile(`${target}.build.log`, logs.join("\n"), { flag: "wx" });
  const pending = join(dirname(target), `.${basename(target)}.${randomUUID()}.tmp`);
  try {
    await writeFile(pending, JSON.stringify(report, null, 2) + "\n", { flag: "wx" });
    await link(pending, target);
  } finally { await rm(pending, { force: true }); }
  return report;
}

if (process.argv[1] && process.argv[1] !== "-" &&
    await realpath(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const controller = new AbortController();
  const interrupt = () => controller.abort(new Error("Grading interrupted"));
  process.on("SIGINT", interrupt);
  process.on("SIGTERM", interrupt);
  try {
    const { values } = parseArgs({ options: Object.fromEntries(
      ["sdk", "workspace", "grading-root", "run-id", "output"].map(name => [name, { type: "string" }])) });
    const report = await grade({
      sdk: values.sdk, workspace: values.workspace ?? process.cwd(),
      gradingRoot: values["grading-root"] ?? moduleRoot, runId: values["run-id"], output: values.output,
      signal: controller.signal,
    });
    const contract = JSON.parse(await readFile(join(values["grading-root"] ?? moduleRoot, "contract.json"), "utf8"));
    const outcome = verdict(report, contract);
    if (outcome === "passed") console.log("SHARED_TREE_EVAL_ALL_REQUIRED_PASSED");
    else {
      console.error(`SharedTree grading ${outcome}; complete report: ${values.output}`);
      process.exitCode = outcome === "invalid" ? 2 : 1;
    }
  } catch (error) {
    console.error(error.stack ?? String(error));
    process.exitCode = 2;
  } finally {
    process.off("SIGINT", interrupt);
    process.off("SIGTERM", interrupt);
  }
}
