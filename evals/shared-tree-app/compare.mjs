import { readFile, realpath } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { agentDurationMs, getBenchmark } from "./generate.mjs";
import { summarize, validateReport, verdict } from "./lib/report.mjs";

export function compare(trials) {
  if (!Array.isArray(trials) || trials.length === 0) throw new TypeError("Comparison requires trial records");
  const track = trials[0].manifest?.track ?? "core";
  const { contract, identity: benchmarkIdentity } = getBenchmark(track);
  let shared;
  const revisions = new Map();
  for (const { manifest, report } of trials) {
    getBenchmark(manifest?.track ?? "core");
    if ((manifest?.track ?? "core") !== track) throw new TypeError("Comparison track mismatch");
    validateReport(report, contract);
    if (manifest?.version !== 1 || manifest.runId !== report.runId || manifest.sdk !== report.sdk) {
      throw new TypeError("Trial manifest/report identity mismatch");
    }
    if (manifest.taskSha256 !== benchmarkIdentity.taskSha256 ||
        manifest.contractSha256 !== benchmarkIdentity.contractSha256) {
      throw new TypeError("Task or contract hash mismatch with this benchmark");
    }
    const authMode = manifest.authMode === undefined ? "provider" : manifest.authMode;
    if (!["provider", "copilot"].includes(authMode)) throw new TypeError("Invalid trial authentication mode");
    const wireApi = manifest.wireApi === undefined ? "completions" : manifest.wireApi;
    if (!["completions", "responses", "messages"].includes(wireApi) || (authMode === "provider" && wireApi !== "completions")) {
      throw new TypeError("Invalid trial authentication/protocol combination");
    }
    if (typeof manifest.model !== "string" || !manifest.model.trim() ||
        !["low", "medium", "high", "xhigh"].includes(manifest.reasoningEffort) ||
        !["copilot-sdk", "mock"].includes(manifest.executor) ||
        !/^[a-f0-9]{64}$/.test(manifest.evalSha256 ?? "") ||
        !/^[a-f0-9]{64}$/.test(manifest.starterSha256 ?? "") ||
        typeof manifest.revision !== "string" || !/^[a-f0-9]{40}$/.test(manifest.revision)) {
      throw new TypeError("Invalid trial settings or SDK revision");
    }
    const provider = new URL(manifest.providerUrl);
    if (authMode === "copilot" && provider.href !== "https://api.githubcopilot.com/") {
      throw new TypeError("Copilot authentication requires the GitHub Copilot provider identity");
    }
    if (provider.username || provider.password || provider.search || provider.hash) {
      throw new TypeError("Provider identity must not contain credentials or query parameters");
    }
    const runtime = ["task", "grade"].map(role => {
      const image = manifest.images?.[role];
      if (!image || image.uid !== 1000 || !image.toolchain) throw new TypeError("Missing non-root image runtime identity");
      const values = [image.architecture, image.coreVersion, image.cliVersion,
        ...["node", "pnpm", "gleam", "chromium"].map(tool => image.toolchain[tool])];
      if (values.some(value => typeof value !== "string" || !value)) throw new TypeError("Incomplete image runtime identity");
      return values;
    });
    if (!/^[a-f0-9]{64}$/.test(manifest.images.vallyPatchSha256 ?? "")) {
      throw new TypeError("Missing Vally compatibility patch identity");
    }
    const settings = JSON.stringify({
      model: manifest.model, reasoningEffort: manifest.reasoningEffort,
      durationMs: agentDurationMs(manifest.limits), executor: manifest.executor, provider: provider.href,
      authMode, wireApi,
      evalSha256: manifest.evalSha256,
      runtime, vallyPatchSha256: manifest.images.vallyPatchSha256,
    });
    if (shared !== undefined && settings !== shared) {
      throw new TypeError("Comparison model, effort, authentication, protocol, provider, executor, working-limit, or runtime mismatch");
    }
    shared = settings;
    const revision = `${manifest.revision}/${manifest.starterSha256}`;
    if (revisions.has(report.sdk) && revisions.get(report.sdk) !== revision) {
      throw new TypeError(`Mixed SDK revision or starter for ${report.sdk}`);
    }
    revisions.set(report.sdk, revision);
  }
  const result = summarize(trials.map(trial => trial.report), contract);
  for (const sdk of ["watershed", "fluid"]) {
    result[sdk].trials = trials.filter(trial => trial.report.sdk === sdk).map(({ manifest, report, metrics }) => ({
      runId: report.runId, outcome: verdict(report, contract), manifest, metrics: metrics ?? null,
    }));
  }
  return result;
}

if (process.argv[1] && process.argv[1] !== "-" &&
    await realpath(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    if (process.argv.length < 3) throw new TypeError("Usage: node compare.mjs PAIR_JSON [...]");
    const values = await Promise.all(process.argv.slice(2).map(async path => JSON.parse(await readFile(path, "utf8"))));
    console.log(JSON.stringify(compare(values.flatMap(value => {
      if (value.version !== 1 || !Array.isArray(value.trials)) throw new TypeError("Unsupported pair record");
      return value.trials;
    })), null, 2));
  } catch (error) {
    console.error(error.message);
    process.exitCode = 2;
  }
}
