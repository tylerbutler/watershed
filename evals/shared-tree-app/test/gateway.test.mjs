import assert from "node:assert/strict";
import { once } from "node:events";
import { createServer } from "node:http";
import test from "node:test";
import { startGateway } from "../docker/gateway.mjs";

test("gateway forwards only the selected model route and keeps provider credentials outside clients", async t => {
  const received = [];
  let rejectKey = false;
  const upstream = createServer(async (request, response) => {
    let body = "";
    for await (const chunk of request) body += chunk;
    received.push({ url: request.url, auth: request.headers.authorization, body: JSON.parse(body) });
    if (rejectKey) {
      response.writeHead(401).end(`Incorrect API key: ${request.headers.authorization}`);
      return;
    }
    response.writeHead(200, { "content-type": "text/event-stream" })
      .end('data: {"choices":[{"delta":{"content":"fixture"}}]}\n\ndata: [DONE]\n\n');
  });
  upstream.listen(0, "127.0.0.1");
  await once(upstream, "listening");
  let gateway;
  t.after(async () => {
    try { await gateway?.close(); }
    finally {
      upstream.closeAllConnections();
      await new Promise(resolve => upstream.close(resolve));
    }
  });
  const key = "harmless-provider-canary";
  gateway = await startGateway({
    upstream: `http://127.0.0.1:${upstream.address().port}/v1`,
    apiKey: key, model: "fixture-model", port: 0, host: "127.0.0.1",
  });
  for (const path of ["/", "/v1/models", "/v1/chat/completions?url=https://github.com", "/https://github.com"]) {
    assert.equal((await fetch(gateway.origin + path)).status, 403);
  }
  for (const body of [
    { model: "other-model", messages: [] },
    { model: "fixture-model", messages: [], tools: [{ type: "web_search" }] },
  ]) {
    assert.equal((await fetch(gateway.origin + "/v1/chat/completions", {
      method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body),
    })).status, 400);
  }
  assert.equal(received.length, 0);
  const body = { model: "fixture-model", messages: [{ role: "user", content: "fixture" }], stream: true };
  const response = await fetch(gateway.origin + "/v1/chat/completions", {
    method: "POST", headers: { "content-type": "application/json", authorization: "Bearer client-placeholder" },
    body: JSON.stringify(body),
  });
  assert.equal(response.status, 200);
  const text = await response.text();
  assert.match(text, /data: \[DONE\]/);
  assert.equal(text.includes(key), false);
  assert.deepEqual(received, [{ url: "/v1/chat/completions", auth: `Bearer ${key}`, body }]);
  rejectKey = true;
  const rejected = await fetch(gateway.origin + "/v1/chat/completions", {
    method: "POST", body: JSON.stringify(body),
  });
  assert.equal(rejected.status, 401);
  assert.equal((await rejected.text()).includes(key), false);
});

test("gateway rejects credential-bearing URLs and does not follow provider redirects", async t => {
  await assert.rejects(startGateway({
    upstream: "https://user:password@example.com/v1", apiKey: "fixture", model: "fixture",
  }), /credentials|upstream/i);
  const upstream = createServer((request, response) =>
    response.writeHead(302, { location: "https://github.com" }).end());
  upstream.listen(0, "127.0.0.1");
  await once(upstream, "listening");
  const gateway = await startGateway({
    upstream: `http://127.0.0.1:${upstream.address().port}/v1`,
    apiKey: "fixture", model: "fixture", port: 0, host: "127.0.0.1",
  });
  t.after(async () => {
    try { await gateway.close(); }
    finally {
      upstream.closeAllConnections();
      await new Promise(resolve => upstream.close(resolve));
    }
  });
  const response = await fetch(gateway.origin + "/v1/chat/completions", {
    method: "POST", headers: { "content-type": "application/json" },
    body: JSON.stringify({ model: "fixture", messages: [] }),
  });
  assert.equal(response.status, 502);
  assert.match(await response.text(), /redirect/i);
});
