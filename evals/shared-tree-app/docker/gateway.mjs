import { once } from "node:events";
import { realpath } from "node:fs/promises";
import { createServer } from "node:http";
import { Readable } from "node:stream";
import { pipeline } from "node:stream/promises";
import { fileURLToPath } from "node:url";

const completionFields = new Set([
  "model", "messages", "stream", "stream_options", "tools", "tool_choice", "parallel_tool_calls",
  "temperature", "top_p", "max_tokens", "max_completion_tokens", "frequency_penalty", "presence_penalty",
  "stop", "seed", "user", "n", "logprobs", "top_logprobs", "logit_bias", "response_format",
  "reasoning_effort", "reasoning", "verbosity", "prediction", "store", "metadata", "service_tier",
  "prompt_cache_key", "prompt_cache_retention", "safety_identifier",
]);
const messageFields = new Set([
  "role", "content", "name", "tool_calls", "tool_call_id", "refusal",
  "reasoning_content", "reasoning", "reasoning_details",
]);
const textMessage = message => message && typeof message === "object" &&
  Object.keys(message).every(key => messageFields.has(key)) &&
  (message.content == null || typeof message.content === "string" ||
    (Array.isArray(message.content) && message.content.every(part =>
      part?.type === "text" && typeof part.text === "string")));

const responseFields = new Set([
  "model", "input", "instructions", "stream", "tools", "tool_choice", "parallel_tool_calls",
  "temperature", "top_p", "max_output_tokens", "reasoning", "text", "store", "metadata",
  "truncation", "include", "service_tier", "prompt_cache_key", "prompt_cache_retention",
  "safety_identifier", "user",
]);
const anthropicFields = new Set([
  "model", "messages", "system", "max_tokens", "stream", "tools", "tool_choice",
  "temperature", "top_p", "top_k", "stop_sequences", "metadata", "thinking", "output_config",
]);
const nativeHeaders = [
  "x-github-api-version", "editor-version", "editor-plugin-version", "user-agent",
  "x-request-id", "x-client-request-id", "x-initiator", "x-interaction-id", "x-interaction-type",
  "anthropic-version", "anthropic-beta", "openai-beta", "x-session-id",
];
const textContent = (value, types) => typeof value === "string" ||
  (Array.isArray(value) && value.every(part => part && types.includes(part.type) &&
    typeof part.text === "string"));
const responseInput = value => typeof value === "string" || (Array.isArray(value) && value.every(item =>
  item && (
    ((!item.type || item.type === "message") && textContent(item.content, ["input_text", "output_text"])) ||
    (item.type === "function_call" && typeof item.arguments === "string") ||
    (item.type === "custom_tool_call" && typeof item.name === "string" &&
      typeof item.call_id === "string" && typeof item.input === "string") ||
    (["function_call_output", "custom_tool_call_output"].includes(item.type) &&
      textContent(item.output, ["input_text"])) ||
    (item.type === "reasoning" && Array.isArray(item.summary) &&
      item.summary.every(part => part?.type === "summary_text" && typeof part.text === "string"))
  )));
const responseTool = tool => tool?.type === "function" || (
  tool?.type === "custom" && typeof tool.name === "string" && tool.name.trim() &&
  Object.keys(tool).every(key => ["type", "name", "description", "format"].includes(key)) &&
  (tool.description === undefined || typeof tool.description === "string") &&
  (tool.format === undefined ||
    (tool.format?.type === "text" && Object.keys(tool.format).every(key => key === "type")) ||
    (tool.format?.type === "grammar" && ["lark", "regex"].includes(tool.format.syntax) &&
      typeof tool.format.definition === "string" &&
      Object.keys(tool.format).every(key => ["type", "syntax", "definition"].includes(key))))
);
const anthropicContent = value => typeof value === "string" || (Array.isArray(value) && value.every(part =>
  part && (
    (part.type === "text" && typeof part.text === "string") ||
    (part.type === "tool_use" && typeof part.name === "string" && part.input && typeof part.input === "object") ||
    (part.type === "tool_result" && anthropicContent(part.content)) ||
    (part.type === "thinking" && typeof part.thinking === "string") ||
    (part.type === "redacted_thinking" && typeof part.data === "string")
  )));

function allowedInference(path, value, model) {
  if (!value || value.model !== model) return false;
  if (path === "/responses") {
    return Object.keys(value).every(key => responseFields.has(key)) && responseInput(value.input) &&
      (value.tools === undefined || (Array.isArray(value.tools) && value.tools.every(responseTool))) &&
      (typeof value.tool_choice !== "object" || value.tool_choice?.type === "function" ||
        (value.tool_choice?.type === "custom" && typeof value.tool_choice.name === "string" &&
          value.tool_choice.name.trim() &&
          Object.keys(value.tool_choice).every(key => ["type", "name"].includes(key))));
  }
  if (path === "/v1/messages") {
    return Object.keys(value).every(key => anthropicFields.has(key)) &&
      Array.isArray(value.messages) && value.messages.every(message => message && anthropicContent(message.content)) &&
      (value.system === undefined || textContent(value.system, ["text"])) &&
      (value.tools === undefined || (Array.isArray(value.tools) && value.tools.every(tool =>
        tool && (tool.type === undefined || tool.type === "custom") && typeof tool.name === "string"))) &&
      (value.tool_choice === undefined || ["auto", "any", "none", "tool"].includes(value.tool_choice?.type));
  }
  return Object.keys(value).every(key => completionFields.has(key)) &&
    Array.isArray(value.messages) && value.messages.every(textMessage) &&
    (typeof value.tool_choice !== "object" || value.tool_choice?.type === "function") &&
    (value.tools === undefined || (Array.isArray(value.tools) && value.tools.every(tool => tool?.type === "function")));
}

export async function startGateway({ upstream, apiKey, model, auth = "provider", wireApi = "completions",
  port = 8080, host = "0.0.0.0" }) {
  if (!["provider", "copilot"].includes(auth)) throw new TypeError("auth must be provider or copilot");
  if (!["completions", "responses", "messages"].includes(wireApi) || (auth === "provider" && wireApi !== "completions")) {
    throw new TypeError("Unsupported authentication/protocol combination");
  }
  const base = new URL(upstream);
  const loopback = base.protocol === "http:" && ["127.0.0.1", "[::1]"].includes(base.hostname);
  if ((!loopback && base.protocol !== "https:") || base.username || base.password || base.search || base.hash) {
    throw new TypeError("Provider upstream must use HTTPS without embedded credentials");
  }
  if (auth === "copilot" && !loopback && base.href !== "https://api.githubcopilot.com/") {
    throw new TypeError("Copilot credentials may only be sent to the GitHub Copilot API");
  }
  if (typeof apiKey !== "string" || !apiKey || /[\r\n]/.test(apiKey) ||
      typeof model !== "string" || !model.trim()) {
    throw new TypeError("Provider gateway requires an API key and selected model");
  }
  const routes = auth === "copilot" ? {
    completions: ["/chat/completions"], responses: ["/responses"], messages: ["/v1/messages"],
  }[wireApi]
    : ["/v1/chat/completions"];
  const active = new Set();
  let closing;
  const server = createServer(async (request, response) => {
    const reply = (status, message, source = "gateway") => {
      console.error(JSON.stringify({ event: "provider-gateway-rejection", protocol: wireApi, source, status }));
      response.writeHead(status, {
        "content-type": "application/json", "cache-control": "no-store",
      }).end(JSON.stringify({ error: message }));
    };
    if (request.method === "GET" && request.url === "/health") {
      response.writeHead(200, { "content-type": "application/json" }).end('{"ready":true}');
      return;
    }
    if (request.method !== "POST" || !routes.includes(request.url)) {
      request.resume();
      reply(403, "Provider route is not allowed");
      return;
    }
    const controller = new AbortController();
    active.add(controller);
    response.once("close", () => controller.abort());
    let forwarding = false;
    try {
      const chunks = [];
      let size = 0;
      for await (const chunk of request) {
        size += chunk.length;
        if (size > 16 * 1024 * 1024) {
          reply(413, "Provider request exceeds the body limit");
          return;
        }
        chunks.push(chunk);
      }
      const body = Buffer.concat(chunks);
      if (!allowedInference(request.url, JSON.parse(body), model)) {
        reply(400, "Only text inference, standard fields, the selected model, and client-executed tools are allowed");
        return;
      }
      forwarding = true;
      const signal = AbortSignal.any([controller.signal, AbortSignal.timeout(600_000)]);
      const path = auth === "copilot" ? request.url : "/chat/completions";
      const target = new URL(base.href.replace(/\/$/, "") + path);
      const headers = { "content-type": "application/json", authorization: `Bearer ${apiKey}` };
      if (auth === "copilot") {
        for (const name of nativeHeaders) {
          if (typeof request.headers[name] === "string") headers[name] = request.headers[name];
        }
        headers["copilot-integration-id"] = "copilot-developer-cli";
      }
      const result = await fetch(target, {
        method: request.method, redirect: "manual", body, signal, headers,
      });
      if (result.status >= 300 && result.status < 400) {
        await result.body?.cancel();
        reply(502, "Provider redirects are not allowed", "upstream");
        return;
      }
      if (result.status >= 400) {
        // Provider error bodies can echo authentication credentials.
        await result.body?.cancel();
        reply(result.status, `Provider rejected the request (HTTP ${result.status})`, "upstream");
        return;
      }
      response.writeHead(result.status, {
        "content-type": result.headers.get("content-type") ?? "application/json",
        "cache-control": "no-store",
      });
      if (result.body) await pipeline(Readable.fromWeb(result.body), response, { signal });
      else response.end();
    } catch (error) {
      if (controller.signal.aborted) return;
      if (forwarding) console.error("Provider gateway upstream request failed");
      if (response.headersSent) response.destroy(error);
      else reply(forwarding ? 502 : 400, forwarding ? "Provider request failed" : "Invalid JSON request",
        forwarding ? "upstream" : "gateway");
    } finally {
      active.delete(controller);
    }
  });
  server.requestTimeout = 30_000;
  server.headersTimeout = 10_000;
  for (const event of ["connect", "upgrade"]) {
    server.on(event, (request, socket) =>
      socket.end("HTTP/1.1 403 Forbidden\r\nConnection: close\r\nContent-Length: 0\r\n\r\n"));
  }
  server.listen(port, host);
  await once(server, "listening");
  return {
    origin: `http://127.0.0.1:${server.address().port}`,
    close: () => closing ??= (async () => {
      for (const controller of active) controller.abort();
      const stopped = new Promise((resolve, reject) =>
        server.close(error => error ? reject(error) : resolve()));
      server.closeAllConnections();
      await stopped;
    })(),
  };
}

if (process.argv[1] && process.argv[1] !== "-" &&
    await realpath(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const gateway = await startGateway({
      upstream: process.env.SHARED_TREE_PROVIDER_URL,
      auth: process.env.SHARED_TREE_AUTH_MODE,
      wireApi: process.env.SHARED_TREE_WIRE_API,
      apiKey: process.env.SHARED_TREE_PROVIDER_API_KEY,
      model: process.env.SHARED_TREE_PROVIDER_MODEL,
    });
    for (const signal of ["SIGINT", "SIGTERM"]) process.once(signal, () => {
      gateway.close().catch(error => { console.error(error.message); process.exitCode = 1; });
    });
    console.log("Provider gateway ready");
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
