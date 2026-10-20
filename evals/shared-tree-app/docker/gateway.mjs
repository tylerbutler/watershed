import { once } from "node:events";
import { realpath } from "node:fs/promises";
import { createServer } from "node:http";
import { Readable } from "node:stream";
import { pipeline } from "node:stream/promises";
import { fileURLToPath } from "node:url";

export async function startGateway({ upstream, apiKey, model, port = 8080, host = "0.0.0.0" }) {
  const base = new URL(upstream);
  const loopback = base.protocol === "http:" && ["127.0.0.1", "[::1]"].includes(base.hostname);
  if ((!loopback && base.protocol !== "https:") || base.username || base.password || base.search || base.hash) {
    throw new TypeError("Provider upstream must use HTTPS without embedded credentials");
  }
  if (typeof apiKey !== "string" || !apiKey || /[\r\n]/.test(apiKey) ||
      typeof model !== "string" || !model.trim()) {
    throw new TypeError("Provider gateway requires an API key and selected model");
  }
  const target = new URL(base.href.replace(/\/$/, "") + "/chat/completions");
  const active = new Set();
  let closing;
  const server = createServer(async (request, response) => {
    const reply = (status, message) => response.writeHead(status, {
      "content-type": "application/json", "cache-control": "no-store",
    }).end(JSON.stringify({ error: message }));
    if (request.method === "GET" && request.url === "/health") {
      response.writeHead(200, { "content-type": "application/json" }).end('{"ready":true}');
      return;
    }
    if (request.method !== "POST" || request.url !== "/v1/chat/completions") {
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
      const value = JSON.parse(body);
      if (value?.model !== model || !Array.isArray(value.messages) ||
          (value.tools !== undefined && (!Array.isArray(value.tools) ||
            value.tools.some(tool => tool?.type !== "function")))) {
        reply(400, "Only the selected model and function tools are allowed");
        return;
      }
      forwarding = true;
      const signal = AbortSignal.any([controller.signal, AbortSignal.timeout(600_000)]);
      const result = await fetch(target, {
        method: "POST", redirect: "manual", body, signal,
        headers: { "content-type": "application/json", authorization: `Bearer ${apiKey}` },
      });
      if (result.status >= 300 && result.status < 400) {
        await result.body?.cancel();
        reply(502, "Provider redirects are not allowed");
        return;
      }
      if (result.status >= 400) {
        // Provider error bodies can echo authentication credentials.
        await result.body?.cancel();
        reply(result.status, `Provider rejected the request (HTTP ${result.status})`);
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
      else reply(forwarding ? 502 : 400, forwarding ? "Provider request failed" : "Invalid JSON request");
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
