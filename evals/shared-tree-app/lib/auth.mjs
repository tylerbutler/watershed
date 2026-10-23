import { execOwned } from "./process.mjs";

export async function resolveAuthentication({ auth = "provider", env = process.env, signal } = {}) {
  if (!["provider", "copilot"].includes(auth)) throw new TypeError("auth must be provider or copilot");
  if (auth === "provider") {
    const upstream = new URL(env.SHARED_TREE_PROVIDER_URL);
    if (upstream.protocol !== "https:" || upstream.username || upstream.password || upstream.search || upstream.hash ||
        !env.SHARED_TREE_PROVIDER_API_KEY || /[\r\n]/.test(env.SHARED_TREE_PROVIDER_API_KEY)) {
      throw new TypeError("Provider requires a credential-free HTTPS URL and an environment API key");
    }
    return { mode: auth, upstream: upstream.href, apiKey: env.SHARED_TREE_PROVIDER_API_KEY };
  }
  let apiKey = env.COPILOT_GITHUB_TOKEN || env.GH_TOKEN || env.GITHUB_TOKEN;
  if (!apiKey) {
    try {
      apiKey = (await execOwned("gh", ["auth", "token", "--hostname", "github.com"], {
        env, signal, timeout: 10_000, maxBuffer: 64 * 1024,
      })).stdout.trim();
    } catch {
      signal?.throwIfAborted();
      throw new Error("Cannot obtain Copilot account credentials. Set COPILOT_GITHUB_TOKEN or sign in with gh auth login.");
    }
  }
  if (typeof apiKey !== "string" || !apiKey || /[\s\u0000-\u001f\u007f]/.test(apiKey) || apiKey.startsWith("ghp_")) {
    throw new TypeError("Copilot requires a single-line OAuth token or fine-grained token with Copilot Requests permission");
  }
  return { mode: auth, upstream: "https://api.githubcopilot.com/", apiKey };
}

export function trialEnvironment(env, authentication, model) {
  const clean = Object.fromEntries(Object.entries(env).filter(([name]) =>
    !/^(?:COPILOT_|GH_TOKEN$|GITHUB_TOKEN$|GITHUB_COPILOT_API_TOKEN$)/i.test(name)));
  return {
    ...clean,
    SHARED_TREE_PROVIDER_URL: authentication.upstream,
    SHARED_TREE_PROVIDER_API_KEY: authentication.apiKey,
    SHARED_TREE_PROVIDER_MODEL: model,
    SHARED_TREE_GATEWAY_CLIENT_KEY: "gateway-client-placeholder",
  };
}

export async function copilotWireApi(authentication, model, { signal } = {}) {
  let response;
  let catalog;
  try {
    response = await fetch("https://api.githubcopilot.com/models", {
      redirect: "manual", signal: AbortSignal.any([AbortSignal.timeout(15_000), ...(signal ? [signal] : [])]),
      headers: {
        authorization: `Bearer ${authentication.apiKey}`, "copilot-integration-id": "copilot-developer-cli",
        "x-github-api-version": "2026-07-01",
      },
    });
    if (response.ok) catalog = await response.json();
    else await response.body?.cancel();
  } catch {
    signal?.throwIfAborted();
    throw new Error("Copilot model discovery failed: transport error or invalid model catalog");
  }
  if (!response.ok) throw new Error(`Copilot account model discovery rejected the request (HTTP ${response.status})`);
  const models = Array.isArray(catalog?.data) ? catalog.data.filter(entry => entry?.id === model) : [];
  if (models.length !== 1 || models[0].model_picker_enabled === false ||
      (models[0].policy?.state !== undefined && models[0].policy.state !== "enabled")) {
    throw new Error("Selected model is not available to the Copilot account");
  }
  const endpoints = models[0].supported_endpoints;
  for (const [path, protocol] of [
    ["/chat/completions", "completions"], ["/responses", "responses"], ["/v1/messages", "messages"],
  ]) if (Array.isArray(endpoints) && endpoints.includes(path)) return protocol;
  throw new Error("Selected Copilot model does not advertise a supported text inference protocol");
}
