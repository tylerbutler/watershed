import { createHash } from "node:crypto";
import { lstat, readFile, readdir } from "node:fs/promises";
import { isAbsolute, join } from "node:path";
import { fileURLToPath } from "node:url";
import { offlineSetupCommands } from "./lib/isolation.mjs";
import { loadTrack } from "./lib/tracks.mjs";

const toolPrompt = "\n\nDevelopment tools: run `pnpm check` and `pnpm build`. " +
  "Serve the app with `node /opt/shared-tree/public/serve.mjs --sdk <sdk> --root /workspace`, " +
  "using the sdk value from SDK.json. Run `node /opt/shared-tree/public/smoke.mjs <app-url>` " +
  "against the URL printed by that server. The local service and dependencies are already available.\n";
const sha256 = value => createHash("sha256").update(value).digest("hex");
const tracks = Object.fromEntries(await Promise.all(["core", "transfers"].map(async name => {
  const selected = await loadTrack(name);
  const prompt = selected.task + toolPrompt;
  return [name, { ...selected, prompt, identity: Object.freeze({
    taskSha256: sha256(prompt), contractSha256: sha256(selected.contractText),
  }) }];
})));
export function getBenchmark(track = "core") {
  if (!Object.hasOwn(tracks, track)) throw new TypeError(`Unsupported eval track: ${track}`);
  return tracks[track];
}
export const benchmarkIdentity = getBenchmark().identity;

export async function benchmarkProvenance({ sdk, track = "core", root = fileURLToPath(new URL("./", import.meta.url)) }) {
  getBenchmark(track);
  if (!["watershed", "fluid"].includes(sdk)) throw new TypeError("Unknown provenance SDK");
  const hash = async paths => {
    const files = [];
    const collect = async path => {
      const entry = await lstat(join(root, path));
      if (entry.isSymbolicLink()) throw new Error(`Benchmark source contains a symlink: ${path}`);
      if (entry.isDirectory()) {
        const names = (await readdir(join(root, path))).filter(name =>
          !["node_modules", "build", "dist", ".git", ".work"].includes(name));
        await Promise.all(names.map(name => collect(`${path}/${name}`)));
      } else if (entry.isFile()) files.push(path);
      else throw new Error(`Unsupported benchmark source: ${path}`);
    };
    await Promise.all(paths.map(collect));
    return sha256(JSON.stringify(await Promise.all(files.sort().map(async path =>
      [path, sha256(await readFile(join(root, path)))]))));
  };
  return {
    evalSha256: await hash(["generate.mjs", "run.mjs", "compare.mjs", "prepare.mjs",
      "package.json", "pnpm-lock.yaml", "pnpm-workspace.yaml", "patches", "task.md",
      "contract.json", "lib", "graders", "docker", "public",
      ...(track === "core" ? [] : [`tracks/${track}/task.md`, `tracks/${track}/contract.json`])]),
    starterSha256: await hash([sdk, ...(track === "core" ? [] : [`tracks/${track}/${sdk}`])]),
  };
}

export function agentDurationMs(limits) {
  if (!limits || Object.keys(limits).some(key => key !== "agentDuration") ||
      typeof limits.agentDuration !== "string") {
    throw new TypeError("limits requires agentDuration only");
  }
  const match = limits.agentDuration.match(/^(\d+(?:\.\d+)?)(ms|s|m|h)$/);
  const value = match && Number(match[1]) * { ms: 1, s: 1000, m: 60_000, h: 3_600_000 }[match[2]];
  if (!Number.isSafeInteger(value) || value <= 0 || !Number.isSafeInteger(value + 60_000)) {
    throw new TypeError("agentDuration must be a finite positive duration with millisecond precision");
  }
  return value;
}

export function buildSpec({ sdk, prepared, model, reasoningEffort, limits, runId,
  auth = "provider", wireApi = "completions", track = "core" }) {
  const { prompt, contract, identity } = getBenchmark(track);
  const duration = agentDurationMs(limits);
  if (!["provider", "copilot"].includes(auth)) throw new TypeError("auth must be provider or copilot");
  if (!["completions", "responses", "messages"].includes(wireApi) || (auth === "provider" && wireApi !== "completions")) {
    throw new TypeError("Unsupported authentication/protocol combination");
  }
  if (!["watershed", "fluid"].includes(sdk) || prepared?.sdkManifest?.sdk !== sdk ||
      typeof prepared.agentRoot !== "string" || !isAbsolute(prepared.agentRoot)) {
    throw new TypeError("Spec requires a matching prepared SDK and absolute agent root");
  }
  if ((prepared.track ?? "core") !== track || (prepared.sdkManifest.track ?? "core") !== track) {
    throw new TypeError("Prepared workspace track mismatch");
  }
  if (typeof model !== "string" || !model.trim() || /[\u0000-\u001f\u007f]/.test(model) ||
      !["low", "medium", "high", "xhigh"].includes(reasoningEffort) ||
      typeof runId !== "string" || !/^[a-z0-9][a-z0-9-]*$/.test(runId)) {
    throw new TypeError("Spec requires operator model, reasoning effort, and lowercase run ID");
  }
  return {
    name: `shared-tree-app-${sdk}`, version: "1.0", type: "capability",
    tags: { api: "shared-tree", sdk, track, ...identity },
    defaults: {
      executor: { name: "copilot-sdk", config: { provider: {
        type: wireApi === "messages" ? "anthropic" : "openai",
        baseUrl: auth === "copilot" ? "http://provider-gateway:8080" : "http://provider-gateway:8080/v1",
        ...(wireApi === "messages" ? {} : { wireApi, transport: "http" }),
        apiKeyEnv: "SHARED_TREE_GATEWAY_CLIENT_KEY", modelId: model, wireModel: model,
      } } },
      model, reasoning_effort: reasoningEffort, runs: 1, timeout: `${duration + 60_000}ms`,
    },
    agent_environment: {
      files: [{ src: prepared.agentRoot, dest: "." }],
      commands: offlineSetupCommands(sdk),
      env: {
        SHARED_TREE_GATEWAY_CLIENT_KEY: "gateway-client-placeholder",
        ...(auth === "copilot" ? { COPILOT_OFFLINE: "true" } : {}),
      },
    },
    stimuli: [{
      name: contract.task, prompt,
      constraints: { max_agent_duration: limits.agentDuration },
      graders: [{ type: "run-command", name: "native-board", config: {
        command: "node", args: ["/opt/shared-tree/grading/graders/main.mjs",
          "--sdk", sdk, "--workspace", "/workspace", "--run-id", runId,
          "--output", "/eval-results/report.json"],
        expected_exit_code: 0, stdout_contains: "SHARED_TREE_EVAL_ALL_REQUIRED_PASSED", timeout: "10m",
      } }],
    }],
    scoring: { threshold: 1 },
  };
}
