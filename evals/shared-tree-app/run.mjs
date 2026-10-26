import { randomUUID } from "node:crypto";
import { mkdir, readFile, readdir, realpath, symlink, writeFile } from "node:fs/promises";
import { isAbsolute, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import { stringify } from "yaml";
import { compare } from "./compare.mjs";
import { agentDurationMs, getBenchmark, benchmarkProvenance, buildSpec } from "./generate.mjs";
import { copilotWireApi, resolveAuthentication, trialEnvironment } from "./lib/auth.mjs";
import { buildImages } from "./lib/images.mjs";
import { cleanupVallyRun, writeRoleCompose } from "./lib/isolation.mjs";
import { execOwned } from "./lib/process.mjs";
import { validateReport, verdict } from "./lib/report.mjs";
import { prepare } from "./prepare.mjs";

const json = value => JSON.stringify(value, null, 2) + "\n";
const marker = "SHARED_TREE_EVAL_ALL_REQUIRED_PASSED";
const benchmark = fileURLToPath(new URL("./", import.meta.url));

export function trialOrder(runs) {
  if (!Number.isSafeInteger(runs) || runs <= 0) throw new TypeError("runs must be a positive integer");
  return Array.from({ length: runs }, (_, index) =>
    (index % 2 === 0 ? ["watershed", "fluid"] : ["fluid", "watershed"])
      .map(sdk => ({ sdk, trial: index + 1 }))).flat();
}

async function vallyCli() {
  const location = new URL(import.meta.resolve("@microsoft/vally-cli/package.json"));
  const metadata = JSON.parse(await readFile(location, "utf8"));
  if (metadata.version !== "0.19.0") throw new Error("Runner requires pinned Vally CLI 0.19.0");
  return fileURLToPath(new URL(metadata.bin.vally, location));
}

async function jsonLines(path) {
  const content = (await readFile(path, "utf8")).trim();
  if (!content) throw new TypeError(`Empty Vally artifact: ${path}`);
  return content.split("\n").map(line => JSON.parse(line));
}

function observed(value) {
  return typeof value === "number" && Number.isFinite(value) && value >= 0 ? value : null;
}

function phaseTimings(spans) {
  const phase = name => {
    const selected = spans.filter(span => span.attributes?.["vally.docker.phase"] === name);
    if (selected.length !== 1 || selected[0].attributes["vally.docker.result"] !== "success") {
      throw new Error(`Missing, repeated, or unsuccessful Vally phase: ${name}`);
    }
    return selected[0];
  };
  const time = value => {
    if (!Array.isArray(value) || value.length !== 2 || value.some(part => observed(part) === null)) {
      throw new TypeError("Unsupported Vally phase timestamp");
    }
    return value[0] * 1000 + value[1] / 1_000_000;
  };
  const task = phase("task.start"), down = phase("task.down");
  const grade = phase("grade.start"), finished = phase("grade.down");
  if (!task.attributes["vally.docker.project"] || !grade.attributes["vally.docker.project"] ||
      task.attributes["vally.docker.project"] === grade.attributes["vally.docker.project"] ||
      time(down.endTime) > time(grade.startTime)) {
    throw new Error("Task teardown must finish before an independently owned grading project starts");
  }
  const gradingEnvironmentMs = time(finished.endTime) - time(grade.startTime);
  if (gradingEnvironmentMs < 0) throw new Error("Invalid grading phase order");
  return { gradingEnvironmentMs };
}

export async function runVallyTrial({ spec, images, composeFile, root, env = process.env,
  cli, authorizePaid = false, signal }) {
  const { contract } = getBenchmark(spec.tags?.track ?? "core");
  const executor = typeof spec.defaults.executor === "string"
    ? spec.defaults.executor : spec.defaults.executor.name;
  if (executor !== "mock" && !authorizePaid) throw new TypeError("Paid execution requires explicit authorization");
  const grader = spec.stimuli[0].graders[0].config;
  const sdk = grader.args[grader.args.indexOf("--sdk") + 1];
  const runId = grader.args[grader.args.indexOf("--run-id") + 1];
  const started = performance.now();
  let metrics = null;
  const redact = value => env.SHARED_TREE_PROVIDER_API_KEY
    ? String(value).replaceAll(env.SHARED_TREE_PROVIDER_API_KEY, "[REDACTED]") : String(value);
  const invoke = async (phase, args) => {
    let outcome;
    let failure;
    try {
      const result = await execOwned(process.execPath, [cli ?? await vallyCli(), ...args], {
        cwd: benchmark, env, timeout: phase === "lint" ? 30_000 :
          agentDurationMs({ agentDuration: spec.stimuli[0].constraints.max_agent_duration }) + 1_200_000,
        maxBuffer: 8 * 1024 * 1024, signal, killGraceMs: 75_000,
      });
      outcome = { code: 0, stdout: result.stdout, stderr: result.stderr };
    } catch (error) {
      if (!Number.isInteger(error.code) || error.killed || error.signal) failure = error;
      outcome = { code: error.code, stdout: error.stdout ?? "", stderr: error.stderr ?? error.message };
    }
    await writeFile(join(root, `${phase}.log`), redact(outcome.stdout + "\n" + outcome.stderr), { flag: "wx" });
    if (failure) throw failure;
    return outcome.code;
  };
  const invalid = error => {
    const evidence = redact(`Controller infrastructure failure: ${error.message}`);
    const report = {
      version: 1, sdk, runId, classification: "infrastructure",
      checks: contract.checks.map(({ id }) => ({ id, passed: false, durationMs: 0, evidence })),
    };
    validateReport(report, contract);
    return { report, metrics, controllerError: evidence };
  };
  let result;
  await writeFile(join(root, "eval.yaml"), stringify(spec), { flag: "wx", mode: 0o600 });
  try {
    if (await invoke("lint", ["lint", "--eval-spec", join(root, "eval.yaml")]) !== 0) {
      throw new Error("Installed Vally linter rejected generated spec; see lint.log");
    }
    const exitCode = await invoke("eval", ["eval", "--eval-spec", join(root, "eval.yaml"),
      "--backend", "docker", "--backend-args", `task-image=${images.task.id}`,
      "--backend-args", `grade-image=${images.grade.id}`, "--backend-args", `compose-file=${composeFile}`,
      "--workers", "1", "--max-retries", "0", "--require-pass", "--run-id", runId,
      "--shutdown-timeout", "60s", "--output-dir", join(root, "vally")]);
    const files = await readdir(join(root, "vally"), { recursive: true, withFileTypes: true });
    const artifact = name => {
      const matches = files.filter(file => file.isFile() && file.name === name);
      if (matches.length !== 1) throw new Error(`Expected one Vally ${name}, found ${matches.length}`);
      return join(matches[0].parentPath, matches[0].name);
    };
    const records = (await jsonLines(artifact("results.jsonl"))).filter(record => record.type === "trial-result");
    if (records.length !== 1) throw new Error("Expected exactly one supported Vally trial result");
    const record = records[0];
    if (record.status !== "success" || record.model !== spec.defaults.model ||
        record.trajectory?.metadata?.model !== spec.defaults.model) {
      throw new Error("Vally execution failed or its effective model mismatched the requested model");
    }
    const timing = phaseTimings(await jsonLines(artifact("otel-spans.jsonl")));
    const observedMetrics = record.trajectory.metrics;
    const unavailable = [];
    const number = (value, name) => {
      if (value === undefined || value === null) {
        unavailable.push(`${name} was not reported by Vally`);
        return null;
      }
      if (observed(value) === null) throw new TypeError(`Unsupported Vally ${name} metric`);
      return value;
    };
    let tokens = observedMetrics?.tokenUsage ?? null;
    if (tokens !== null) {
      if (typeof tokens !== "object" || Array.isArray(tokens)) throw new TypeError("Unsupported Vally token usage");
      const { cost: ignoredCost, ...counts } = tokens;
      for (const [key, value] of Object.entries(counts)) {
        if (key === "byModel") {
          if (!value || typeof value !== "object" || Array.isArray(value) ||
              Object.values(value).some(model => !model || typeof model !== "object" ||
                Array.isArray(model) || Object.values(model).some(count => observed(count) === null))) {
            throw new TypeError("Unsupported Vally per-model token usage");
          }
        } else if (observed(value) === null) throw new TypeError(`Unsupported Vally token usage: ${key}`);
      }
      tokens = counts;
      if (counts.callCount === 0) {
        tokens = null;
        unavailable.push("Vally recorded no token-usage observations");
      }
    } else unavailable.push("Token usage was not reported by Vally");
    metrics = {
      agentDurationMs: number(observedMetrics?.wallTimeMs, "agent working duration"),
      toolCalls: number(observedMetrics?.toolCallCount, "tool calls"),
      tokens, unavailable,
      cost: null, costUnavailable: "Complete comparable provider cost identity is unavailable",
      ...timing,
    };
    const report = validateReport(JSON.parse(await readFile(join(root, "native/report.json"), "utf8")), contract);
    if (report.sdk !== sdk || report.runId !== runId) throw new Error("Native report identity mismatch");
    await readFile(join(root, "native/report.json.build.log"));
    const details = record.gradeResult?.details?.filter(detail => detail.configuredName === "native-board");
    if (details?.length !== 1 || typeof details[0].passed !== "boolean" ||
        typeof details[0].metadata?.stdout !== "string") {
      throw new Error("Missing supported native-board grader result");
    }
    const passed = verdict(report, contract) === "passed";
    if (details[0].passed !== passed || record.gradeResult.passed !== passed ||
        details[0].metadata.stdout.includes(marker) !== passed || exitCode !== (passed ? 0 : 1)) {
      throw new Error("Native report, grader marker, Vally verdict, and CLI exit are inconsistent");
    }
    result = { report, metrics, controllerError: null };
  } catch (error) {
    result = invalid(error);
  }
  try {
    const cleanup = await cleanupVallyRun({ runId, env });
    if (cleanup.removed.length || cleanup.preserved.length) result = invalid(new Error(
      `${result.controllerError ?? ""}\nVally left owned resources; controller removed runtime resources ` +
      "and preserved any recovery volumes for manual export"));
    result.cleanup = cleanup;
  } catch (error) {
    result = invalid(new Error(`${result.controllerError ?? ""}\nOwned resource cleanup failed: ${error.message}`));
    result.cleanup = { error: redact(error.message) };
  }
  if (signal?.aborted && result.controllerError === null) {
    result = { ...invalid(signal.reason ?? new Error("Trial interrupted")), cleanup: result.cleanup };
  }
  return { ...result, controllerDurationMs: performance.now() - started };
}

export async function runPair({ sources, revisions, model, reasoningEffort, runs, limits, out,
  authorizePaid = false, registry, auth = "provider", env = process.env, signal, track = "core" }) {
  const { identity: benchmarkIdentity } = getBenchmark(track);
  const order = trialOrder(runs);
  agentDurationMs(limits);
  if (typeof out !== "string" || !isAbsolute(out)) throw new TypeError("out must be an absolute fresh directory");
  for (const sdk of ["watershed", "fluid"]) {
    if (typeof sources?.[sdk] !== "string" || !isAbsolute(sources[sdk]) ||
        !/^[a-f0-9]{40}$/.test(revisions?.[sdk] ?? "")) {
      throw new TypeError(`${sdk} requires an absolute source and full commit revision`);
    }
    buildSpec({ sdk, prepared: { agentRoot: resolve(out, sdk), sdkManifest: { sdk, track }, track },
      model, reasoningEffort, limits, runId: "preflight", auth, track });
  }
  if (!authorizePaid) throw new TypeError("Supply --authorize-paid to explicitly authorize model trials");
  const authentication = await resolveAuthentication({ auth, env, signal });
  const wireApi = auth === "copilot" ? await copilotWireApi(authentication, model, { signal }) : "completions";
  const root = resolve(out);
  await mkdir(root, { mode: 0o700 });
  const config = join(root, "docker-client");
  await mkdir(join(config, "cli-plugins"), { recursive: true });
  const compose = (await execOwned("sh", ["-c", "command -v docker-compose"], { env, signal })).stdout.trim();
  await symlink(compose, join(config, "cli-plugins/docker-compose"));
  await writeFile(join(config, "config.json"), "{}\n", { flag: "wx" });
  const executionEnv = { ...trialEnvironment(env, authentication, model), DOCKER_CONFIG: config };
  await execOwned("docker", ["info"], { env: executionEnv, timeout: 30_000, signal });
  const prepared = {}, images = {}, preparationMs = {}, provenance = {};
  for (const sdk of ["watershed", "fluid"]) {
    const started = performance.now();
    provenance[sdk] = await benchmarkProvenance({ sdk, track });
    prepared[sdk] = await prepare({ sdk, source: sources[sdk], revision: revisions[sdk], out: join(root, sdk), signal, track });
    images[sdk] = await buildImages({ prepared: prepared[sdk], out: join(root, `${sdk}-images`), registry, signal });
    preparationMs[sdk] = performance.now() - started;
  }
  for (const sdk of ["watershed", "fluid"]) {
    if (JSON.stringify(await benchmarkProvenance({ sdk, track })) !== JSON.stringify(provenance[sdk])) {
      throw new Error("Benchmark inputs changed during preparation; no agent trials started");
    }
  }
  const pairId = randomUUID();
  const pair = { version: 1, pairId, plannedTrials: order.length, completed: false, trials: [] };
  for (const { sdk, trial } of order) {
    signal?.throwIfAborted();
    const runId = `pair-${pairId}-${sdk}-${trial}`;
    const trialRoot = join(root, runId);
    await mkdir(trialRoot, { mode: 0o700 });
    const role = await writeRoleCompose({ sdk, images: images[sdk], serviceImage: images[sdk].service.id,
      gradingOutput: join(trialRoot, "native"), out: join(trialRoot, "compose.yaml"), runId, auth, wireApi });
    const spec = buildSpec({ sdk, prepared: prepared[sdk], model, reasoningEffort, limits, runId, auth, wireApi, track });
    const manifest = {
      version: 1, pairId, runId, sdk, trial, track, ...benchmarkIdentity, ...provenance[sdk],
      revision: revisions[sdk], model, reasoningEffort, limits, executor: "copilot-sdk",
      providerUrl: authentication.upstream, authMode: auth, wireApi, executorTimeoutMs: agentDurationMs(limits) + 60_000,
      preparationMs: preparationMs[sdk], images: images[sdk],
      sdkManifest: prepared[sdk].sdkManifest, docsManifest: prepared[sdk].docsManifest,
    };
    await writeFile(join(trialRoot, "manifest.json"), json(manifest), { flag: "wx" });
    const result = await runVallyTrial({ spec, images: images[sdk], composeFile: role.composeFile,
      root: trialRoot, env: executionEnv, authorizePaid, signal });
    const record = { manifest, ...result };
    await writeFile(join(trialRoot, "trial.json"), json(record), { flag: "wx" });
    pair.trials.push(record);
    await writeFile(join(root, "pair.json"), json(pair));
    if (signal?.aborted) break;
  }
  pair.completed = pair.trials.length === order.length && !signal?.aborted;
  await writeFile(join(root, "pair.json"), json(pair));
  const summary = compare(pair.trials);
  await writeFile(join(root, "comparison.json"), json(summary), { flag: "wx" });
  return { root, pair, summary };
}

if (process.argv[1] && process.argv[1] !== "-" &&
    await realpath(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const controller = new AbortController();
  const interrupt = () => controller.abort(new Error("Operator interrupted the benchmark"));
  process.on("SIGINT", interrupt);
  process.on("SIGTERM", interrupt);
  try {
    const strings = ["watershed-source", "watershed-revision", "fluid-source", "fluid-revision",
      "model", "reasoning-effort", "runs", "max-agent-duration", "out", "registry", "auth", "track"];
    const { values } = parseArgs({ options: {
      ...Object.fromEntries(strings.map(name => [name, { type: "string" }])),
      "authorize-paid": { type: "boolean", default: false },
    } });
    if (!/^[1-9]\d*$/.test(values.runs ?? "")) throw new TypeError("--runs requires a positive integer");
    const result = await runPair({
      sources: { watershed: values["watershed-source"], fluid: values["fluid-source"] },
      revisions: { watershed: values["watershed-revision"], fluid: values["fluid-revision"] },
      model: values.model, reasoningEffort: values["reasoning-effort"], runs: Number(values.runs),
      limits: { agentDuration: values["max-agent-duration"] }, out: values.out,
      registry: values.registry, authorizePaid: values["authorize-paid"], auth: values.auth,
      signal: controller.signal, track: values.track,
    });
    console.log(`Comparison saved to ${join(result.root, "comparison.json")}`);
    process.exitCode = !result.pair.completed ||
      result.pair.trials.some(trial =>
        verdict(trial.report, getBenchmark(trial.manifest.track).contract) === "invalid") ? 2 : 0;
  } catch (error) {
    console.error(error.message);
    process.exitCode = 2;
  } finally {
    process.off("SIGINT", interrupt);
    process.off("SIGTERM", interrupt);
  }
}
