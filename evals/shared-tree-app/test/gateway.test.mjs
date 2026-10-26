import assert from "node:assert/strict";
import { once } from "node:events";
import { createServer } from "node:http";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { CopilotSdkExecutor } from "@microsoft/vally/executor";
import { startGateway } from "../docker/gateway.mjs";
import { buildSpec } from "../generate.mjs";

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
    { model: "fixture-model", messages: [], web_search_options: {} },
    { model: "fixture-model", messages: [], extra_body: { mcp_servers: [{ url: "https://github.com" }] } },
    { model: "fixture-model", messages: [{
      role: "user", content: [{ type: "image_url", image_url: { url: "https://github.com" } }],
    }] },
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

test("Copilot gateway forwards only the selected text protocol without exposing account credentials", async t => {
    const received = [];
    const diagnostics = [];
    t.mock.method(console, "error", line => diagnostics.push(JSON.parse(line)));
    const key = "harmless-copilot-account-canary";
    let reject = false;
    const upstream = createServer(async (request, response) => {
      let text = "";
      for await (const chunk of request) text += chunk;
      received.push({ path: request.url, headers: request.headers, body: text && JSON.parse(text) });
      if (reject) {
        response.writeHead(401).end(`Rejected token: ${key}`);
      } else {
        response.writeHead(200, { "content-type": "text/event-stream" }).end("data: [DONE]\n\n");
      }
    });
    upstream.listen(0, "127.0.0.1");
    await once(upstream, "listening");
    let gateway;
    const select = async wireApi => {
      await gateway?.close();
      gateway = await startGateway({
        auth: "copilot", wireApi, upstream: `http://127.0.0.1:${upstream.address().port}`,
        apiKey: key, model: "fixture-model", port: 0, host: "127.0.0.1",
      });
    };
    t.after(async () => {
      try { await gateway.close(); }
      finally { upstream.closeAllConnections(); await new Promise(resolve => upstream.close(resolve)); }
    });
    const bodies = [
      ["/chat/completions", { model: "fixture-model", messages: [{ role: "user", content: "fixture" }] }],
      ["/responses", { model: "fixture-model", input: [
        { role: "user", content: [{ type: "input_text", text: "fixture" }] },
        { type: "reasoning", summary: [], encrypted_content: "opaque-fixture" },
        { type: "function_call", name: "shell", arguments: "{}", call_id: "fixture" },
        { type: "function_call_output", call_id: "fixture", output: "done" },
        { type: "custom_tool_call", name: "apply_patch", input: "fixture", call_id: "patch" },
        { type: "custom_tool_call_output", call_id: "patch", output: "done" },
      ], tools: [{
        type: "custom", name: "apply_patch",
        format: { type: "grammar", syntax: "lark", definition: 'start: "fixture"' },
      }], tool_choice: { type: "custom", name: "apply_patch" }, stream: true }],
      ...[undefined, { type: "text" }, { type: "grammar", syntax: "regex", definition: "fixture" }]
        .map(format => ["/responses", { model: "fixture-model", input: "fixture",
          tools: [{ type: "custom", name: "local_tool", ...(format ? { format } : {}) }] }]),
      ["/v1/messages", { model: "fixture-model", messages: [
        { role: "assistant", content: [
          { type: "thinking", thinking: "fixture", signature: "fixture" },
          { type: "tool_use", id: "fixture", name: "shell", input: {} },
        ] },
        { role: "user", content: [{ type: "tool_result", tool_use_id: "fixture", content: "done" }] },
      ], max_tokens: 20 }],
    ];
    for (const [path, body] of bodies) {
      await select(path === "/responses" ? "responses" : path === "/v1/messages" ? "messages" : "completions");
      const response = await fetch(gateway.origin + path, {
        method: "POST", headers: {
          authorization: "Bearer client-placeholder", "content-type": "application/json",
          "copilot-integration-id": "copilot-developer-cli", "x-github-api-version": "2025-04-01",
          "x-initiator": "agent", "x-untrusted-header": key,
        }, body: JSON.stringify(body),
      });
      assert.equal(response.status, 200, path);
      assert.equal((await response.text()).includes(key), false);
    }
    assert.deepEqual(received.map(request => request.path), bodies.map(([path]) => path));
    for (const request of received) {
      assert.equal(request.headers.authorization, `Bearer ${key}`);
      assert.equal(request.headers["x-untrusted-header"], undefined);
    }
    assert.equal(received[0].headers["copilot-integration-id"], "copilot-developer-cli");
    const before = received.length;
    for (const [path, body] of [
      ["/responses", { model: "other-model", input: "fixture" }],
      ["/responses", { model: "fixture-model", input: "fixture", tools: [{ type: "web_search" }] }],
      ["/responses", { model: "fixture-model", input: "fixture", tools: [{
        type: "custom", name: "apply_patch", format: { type: "url", url: "https://example.com" },
      }] }],
      ["/responses", { model: "fixture-model", input: "fixture", tools: [{
        type: "custom", name: "apply_patch",
        format: { type: "grammar", syntax: "lark", definition: 'start: "fixture"', url: "https://example.com" },
      }] }],
      ["/responses", { model: "fixture-model", input: "fixture", tools: [{
        type: "custom", name: "apply_patch", format: { type: "grammar", syntax: "javascript", definition: "fixture" },
      }] }],
      ["/responses", { model: "fixture-model", input: "fixture", tools: [{ type: "custom", name: "" }] }],
      ["/responses", { model: "fixture-model", input: "fixture", tools: [{
        type: "custom", name: "apply_patch", endpoint: "https://example.com",
      }] }],
      ["/responses", { model: "fixture-model", input: "fixture",
        tool_choice: { type: "custom", name: "apply_patch", endpoint: "https://example.com" } }],
      ["/responses", { model: "fixture-model", input: [{
        type: "custom_tool_call", name: "apply_patch", input: { url: "https://example.com" }, call_id: "patch",
      }] }],
      ["/responses", { model: "fixture-model", input: [{
        type: "custom_tool_call_output", call_id: "patch",
        output: [{ type: "input_image", image_url: "https://example.com" }],
      }] }],
      ["/responses", { model: "fixture-model", input: [{
        role: "user", content: [{ type: "input_image", image_url: "https://example.com" }],
      }] }],
      ["/v1/messages", { model: "fixture-model", messages: [], tools: [{ type: "web_search_20250305", name: "web_search" }] }],
      ["/v1/messages", { model: "fixture-model", messages: [{
        role: "user", content: [{ type: "image", source: { type: "url", url: "https://example.com" } }],
      }] }],
    ]) {
      await select(path === "/responses" ? "responses" : "messages");
      assert.equal((await fetch(gateway.origin + path, { method: "POST", body: JSON.stringify(body) })).status, 400);
    }
    await select("completions");
    assert.equal((await fetch(gateway.origin + "/responses", {
      method: "POST", body: JSON.stringify({ model: "fixture-model", input: "fixture" }),
    })).status, 403);
    assert.equal((await fetch(gateway.origin + "/models")).status, 403);
    assert.equal((await fetch(gateway.origin + "/models?url=https://example.com")).status, 403);
    assert.equal((await fetch(gateway.origin + "/copilot_internal/v2/token")).status, 403);
    assert.equal(received.length, before);
    reject = true;
    const response = await fetch(gateway.origin + "/chat/completions", {
      method: "POST", body: JSON.stringify(bodies[0][1]),
    });
    assert.equal(response.status, 401);
    assert.equal((await response.text()).includes(key), false);
    assert.ok(diagnostics.some(entry => entry.source === "gateway" && entry.status === 400));
    assert.ok(diagnostics.some(entry => entry.source === "upstream" && entry.status === 401));
    for (const entry of diagnostics) {
      assert.deepEqual(Object.keys(entry).sort(), ["event", "protocol", "source", "status"]);
      assert.equal(JSON.stringify(entry).includes(key), false);
    }
});

for (const wireApi of ["completions", "responses", "messages"]) {
test(`pinned Vally uses the Copilot account gateway over ${wireApi} with only fixture credentials`, { timeout: 45_000 }, async t => {
    const root = await mkdtemp(join(tmpdir(), "native-copilot-gateway-"));
    const received = [];
    const model = wireApi === "messages" ? "claude-sonnet-4.5" : wireApi === "responses" ? "gpt-6.1-sol" : "gpt-5";
    const path = { completions: "/chat/completions", responses: "/responses", messages: "/v1/messages" }[wireApi];
    const upstream = createServer(async (request, response) => {
      let body = "";
      for await (const chunk of request) body += chunk;
      received.push(request.url);
      assert.equal(request.headers.authorization, "Bearer harmless-account-fixture");
      assert.equal(request.url, path);
      const value = JSON.parse(body);
      if (wireApi !== "completions") {
        const patch = wireApi === "responses" && !value.input.some(item => item.type === "custom_tool_call_output");
        if (patch) assert.ok(value.tools.some(tool => tool.type === "custom" && tool.name === "apply_patch"));
        const result = wireApi === "responses" ? {
          id: "resp_fixture", object: "response", created_at: 1, status: "completed", model,
          output: patch ? [{
            id: "ctc_fixture", type: "custom_tool_call", call_id: "patch_fixture", name: "apply_patch",
            input: "*** Begin Patch\n*** Add File: gateway-fixture.txt\n+patched\n*** End Patch",
          }] : [{
            id: "msg_fixture", type: "message", status: "completed", role: "assistant",
            content: [{ type: "output_text", text: "gateway-ready", annotations: [] }],
          }],
          usage: { input_tokens: 1, output_tokens: 1, total_tokens: 2 },
        } : {
          id: "msg_fixture", type: "message", role: "assistant", model,
          content: [{ type: "text", text: "gateway-ready" }], stop_reason: "end_turn", stop_sequence: null,
          usage: { input_tokens: 1, output_tokens: 1 },
        };
        if (!value.stream) {
          response.writeHead(200, { "content-type": "application/json" }).end(JSON.stringify(result));
          return;
        }
        response.writeHead(200, { "content-type": "text/event-stream" });
        const events = patch ? [
          ["response.created", { response: { ...result, output: [], status: "in_progress" } }],
          ["response.output_item.added", { output_index: 0, item: { ...result.output[0], input: "" } }],
          ["response.custom_tool_call_input.delta", { item_id: "ctc_fixture", output_index: 0,
            delta: result.output[0].input }],
          ["response.custom_tool_call_input.done", { item_id: "ctc_fixture", output_index: 0,
            input: result.output[0].input }],
          ["response.output_item.done", { output_index: 0, item: result.output[0] }],
          ["response.completed", { response: result }],
        ] : wireApi === "responses" ? [
          ["response.created", { response: { ...result, output: [], status: "in_progress" } }],
          ["response.output_item.added", { output_index: 0, item: { ...result.output[0], content: [], status: "in_progress" } }],
          ["response.content_part.added", { item_id: "msg_fixture", output_index: 0, content_index: 0,
            part: { type: "output_text", text: "", annotations: [] } }],
          ["response.output_text.delta", { item_id: "msg_fixture", output_index: 0, content_index: 0, delta: "gateway-ready" }],
          ["response.output_text.done", { item_id: "msg_fixture", output_index: 0, content_index: 0, text: "gateway-ready" }],
          ["response.content_part.done", { item_id: "msg_fixture", output_index: 0, content_index: 0,
            part: result.output[0].content[0] }],
          ["response.output_item.done", { output_index: 0, item: result.output[0] }],
          ["response.completed", { response: result }],
        ] : [
          ["message_start", { message: { ...result, content: [], stop_reason: null } }],
          ["content_block_start", { index: 0, content_block: { type: "text", text: "" } }],
          ["content_block_delta", { index: 0, delta: { type: "text_delta", text: "gateway-ready" } }],
          ["content_block_stop", { index: 0 }],
          ["message_delta", { delta: { stop_reason: "end_turn", stop_sequence: null }, usage: { output_tokens: 1 } }],
          ["message_stop", {}],
        ];
        for (const [index, [type, data]] of events.entries()) {
          response.write(`event: ${type}\ndata: ${JSON.stringify({ type, sequence_number: index, ...data })}\n\n`);
        }
        response.end();
        return;
      }
      const result = {
        id: "chatcmpl-fixture", object: "chat.completion", created: 1, model,
        choices: [{ index: 0, message: { role: "assistant", content: "gateway-ready" }, finish_reason: "stop" }],
        usage: { prompt_tokens: 1, completion_tokens: 1, total_tokens: 2 },
      };
      if (value.stream) {
        response.writeHead(200, { "content-type": "text/event-stream" });
        for (const [delta, finish_reason] of [
          [{ role: "assistant", content: "gateway-ready" }, null], [{}, "stop"],
        ]) response.write("data: " + JSON.stringify({
          ...result, object: "chat.completion.chunk", choices: [{ index: 0, delta, finish_reason }],
        }) + "\n\n");
        response.end("data: [DONE]\n\n");
      } else response.writeHead(200, { "content-type": "application/json" }).end(JSON.stringify(result));
    });
    upstream.listen(0, "127.0.0.1");
    await once(upstream, "listening");
    const gateway = await startGateway({
      auth: "copilot", wireApi, upstream: `http://127.0.0.1:${upstream.address().port}`,
      apiKey: "harmless-account-fixture", model, port: 0, host: "127.0.0.1",
    });
    const executor = new CopilotSdkExecutor();
    t.after(async () => {
      try { await executor.shutdown(); }
      finally {
        try { await gateway.close(); }
        finally {
          upstream.closeAllConnections();
          await new Promise(resolve => upstream.close(resolve));
          await rm(root, { recursive: true, force: true });
        }
      }
    });
    const spec = buildSpec({
      sdk: "watershed", prepared: { agentRoot: root, sdkManifest: { sdk: "watershed" } },
      auth: "copilot", wireApi, model, reasoningEffort: "high", limits: { agentDuration: "20s" }, runId: "fixture",
    });
    spec.defaults.executor.config.provider.baseUrl = gateway.origin;
    const previous = process.env.SHARED_TREE_GATEWAY_CLIENT_KEY;
    process.env.SHARED_TREE_GATEWAY_CLIENT_KEY = "gateway-client-placeholder";
    t.after(() => {
      if (previous === undefined) delete process.env.SHARED_TREE_GATEWAY_CLIENT_KEY;
      else process.env.SHARED_TREE_GATEWAY_CLIENT_KEY = previous;
    });
    const trajectory = await executor.execute({ name: "account-gateway-fixture", prompt: "Reply gateway-ready" }, {
      workDir: root, model, reasoningEffort: "high", timeout: 30_000, maxAgentDurationMs: 20_000,
      executorConfig: spec.defaults.executor.config,
      env: {
        ...spec.agent_environment.env, COPILOT_GITHUB_TOKEN: "", GH_TOKEN: "", GITHUB_TOKEN: "",
        GITHUB_COPILOT_API_TOKEN: "",
      },
    });
    assert.match(trajectory.output, /gateway-ready/);
    assert.deepEqual(received, wireApi === "responses" ? [path, path] : [path]);
    if (wireApi === "responses") assert.equal(await readFile(join(root, "gateway-fixture.txt"), "utf8"), "patched\n");
    assert.equal(JSON.stringify(trajectory).includes("harmless-account-fixture"), false);
});
}
