import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { readFile } from "node:fs/promises";
import { createServer } from "node:http";
import { dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { promisify } from "node:util";

const execute = promisify(execFile);
const repository = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const tenant = "tenant";
const token = "creation-smoke-secret";
const marker = "WATERSHED_TREE_CREATION=";
const fixture = JSON.parse(await readFile(resolve(
  repository,
  "test/fixtures/shared_tree/cases/schema-profile.json",
)));
const schema =
  fixture.input.summary.tree.indexes.tree.Schema.tree.SchemaString.content;
const root = {
  kind: "object",
  schemaId: "org.watershed.shared-tree.m1.Root",
  fields: [
    ["title", { kind: "string", value: "created natively" }],
    ["enabled", { kind: "boolean", value: true }],
    ["rating", { kind: "number", value: 42.5 }],
    ["marker", { kind: "null" }],
    ["note", { kind: "string", value: "smoke" }],
    ["point", {
      kind: "object",
      schemaId: "org.watershed.shared-tree.m1.Point",
      fields: [
        ["x", { kind: "number", value: 7 }],
        ["y", { kind: "number", value: -3 }],
      ],
    }],
  ],
};
const invalidRoot = structuredClone(root);
invalidRoot.fields[0][1] = { kind: "number", value: 1 };
const findings = [];

let behavior;
const createRequests = [];
let redirectRequests = 0;
let webSocketConnections = 0;
const webSocketRequests = [];

async function requestBody(request) {
  const chunks = [];
  for await (const chunk of request) chunks.push(chunk);
  return Buffer.concat(chunks).toString("utf8");
}

function json(response, status, value) {
  response.writeHead(status, { "content-type": "application/json" });
  response.end(typeof value === "string" ? value : JSON.stringify(value));
}

const server = createServer(async (request, response) => {
  try {
    const raw = await requestBody(request);
    const body = JSON.parse(raw);
    if (request.url === "/redirected") {
      redirectRequests += 1;
      assert.equal(request.method, "POST");
      return json(response, 201, JSON.stringify("redirected-document"));
    }
    createRequests.push({
      authorization: request.headers.authorization,
      body,
      method: request.method,
      url: request.url,
    });
    assert.equal(request.method, "POST");
    assert.equal(request.url, `/documents/${tenant}`);
    assert.equal(request.headers.authorization, `Bearer ${token}`);
    assert.match(request.headers["content-type"], /^application\/json\b/);
    assert.equal(body.sequenceNumber, 0);
    assert.equal(body.enableDiscovery, false);
    assert.equal(body.generateToken, false);
    assert.equal("id" in body, false);
    await behavior(request, response);
  } catch (error) {
    response.writeHead(500, { "content-type": "text/plain" });
    response.end(error.stack ?? String(error));
  }
});
server.on("upgrade", (request, socket) => {
  webSocketConnections += 1;
  webSocketRequests.push({
    method: request.method,
    url: request.url,
    connection: request.headers.connection,
    upgrade: request.headers.upgrade,
  });
  socket.destroy();
});
await new Promise((resolveListen) => server.listen(0, "127.0.0.1", resolveListen));
const address = server.address();
assert(address && typeof address === "object");
const baseUrl = `http://127.0.0.1:${address.port}`;

function observation(output) {
  const line = output.split(/\r?\n/).find((value) => value.startsWith(marker));
  assert(line, `Creation probe did not emit its result:\n${output}`);
  return JSON.parse(line.slice(marker.length));
}

async function runProbe(target, {
  expected = "failure",
  rootValue = root,
  serviceUrl = baseUrl,
  tenantValue = tenant,
} = {}) {
  const environment = {
    ...process.env,
    WATERSHED_TREE_CREATION_URL: serviceUrl,
    WATERSHED_TREE_CREATION_TENANT: tenantValue,
    WATERSHED_TREE_CREATION_TOKEN: token,
    WATERSHED_TREE_CREATION_SCHEMA: schema,
    WATERSHED_TREE_CREATION_ROOT: JSON.stringify(rootValue),
    WATERSHED_TREE_CREATION_EXPECT: expected,
  };
  let result;
  try {
    if (target === "javascript") {
      const moduleUrl = pathToFileURL(resolve(
        repository,
        "build/dev/javascript/watershed/watershed/shared_tree_creation_probe.mjs",
      )).href;
      result = await execute(process.execPath, [
        "--input-type=module",
        "--eval",
        `const probe = await import(${JSON.stringify(moduleUrl)}); await probe.main();`,
      ], { cwd: repository, env: environment, timeout: 45_000 });
    } else {
      result = await execute("gleam", [
        "run", "--target", "erlang", "-m", "watershed/shared_tree_creation_probe",
      ], { cwd: repository, env: environment, timeout: 45_000 });
    }
  } catch (error) {
    if (!error.stdout?.includes(marker)) throw error;
    result = error;
  }
  assert(!result.stdout.includes(token), "Creation probe echoed its token to stdout");
  assert(!result.stderr.includes(token), "Creation probe echoed its token to stderr");
  return observation(result.stdout);
}

async function scenario(target, name, responder, expected = {}) {
  behavior = responder;
  const before = createRequests.length;
  const beforeRedirects = redirectRequests;
  const result = await runProbe(target, expected);
  await new Promise((resolveWait) => setTimeout(resolveWait, 50));
  assert.equal(
    createRequests.length - before,
    expected.requests ?? 1,
    `${target} ${name} sent an unexpected request count`,
  );
  const redirects = redirectRequests - beforeRedirects;
  if (expected.collectFinding && redirects !== (expected.redirects ?? 0)) {
    findings.push(`${target} ${name} followed ${redirects} redirect(s)`);
  } else {
    assert.equal(
      redirects,
      expected.redirects ?? 0,
      `${target} ${name} followed a redirect`,
    );
  }
  assert.equal(webSocketConnections, 0,
    `${target} ${name} opened a WebSocket: ${JSON.stringify(webSocketRequests)}`);
  return result;
}

function requireFailure(target, name, result) {
  if (result.ok) {
    findings.push(`${target} ${name} returned success: ${result.documentId}`);
  }
}

try {
  await execute("gleam", ["build", "--target", "javascript"], {
    cwd: repository,
    timeout: 120_000,
  });
  await execute("gleam", ["build", "--target", "erlang"], {
    cwd: repository,
    timeout: 120_000,
  });

  for (const target of ["javascript", "erlang"]) {
    const created = await scenario(
      target,
      "201",
      (_request, response) => json(response, 201, JSON.stringify(`${target}-document`)),
      { expected: "success" },
    );
    assert.deepEqual(created, { ok: true, documentId: `${target}-document` });

    const closed = await scenario(
      target,
      "201 and immediate close",
      (_request, response) => {
        response.setHeader("connection", "close");
        json(response, 201, JSON.stringify("closed-document"));
      },
      { expected: "success" },
    );
    assert.deepEqual(closed, { ok: true, documentId: "closed-document" });

    for (const status of [401, 403, 409, 500]) {
      const failed = await scenario(
        target,
        String(status),
        (_request, response) => json(response, status, {
          error: `injected ${status}: ${token}`,
        }),
      );
      assert.equal(failed.ok, false);
      assert(!failed.error.includes(token), `${target} ${status} exposed its token`);
    }

    let retryAfterAttempts = 0;
    const retryAfter = await scenario(
      target,
      "503 Retry-After",
      (_request, response) => {
        retryAfterAttempts += 1;
        if (retryAfterAttempts === 1) {
          response.writeHead(503, {
            "content-type": "application/json",
            "retry-after": "0",
          });
          response.end(JSON.stringify({ error: "retry immediately" }));
          return;
        }
        json(response, 201, JSON.stringify("retried-document"));
      },
    );
    assert.equal(retryAfter.ok, false);
    assert.equal(retryAfterAttempts, 1, `${target} retried HTTP 503`);

    for (const status of [307, 308]) {
      const redirected = await scenario(
        target,
        String(status),
        (_request, response) => {
          response.writeHead(status, { location: "/redirected" });
          response.end();
        },
        { collectFinding: true },
      );
      requireFailure(target, String(status), redirected);
      if (!redirected.ok && !/may have succeeded|do not retry/i.test(redirected.error)) {
        findings.push(`${target} ${status} did not report an uncertain outcome`);
      }
    }

    const wrongSuccessStatus = await scenario(
      target,
      "200 with ID",
      (_request, response) => json(response, 200, JSON.stringify("wrong-status-document")),
    );
    requireFailure(target, "200 with ID", wrongSuccessStatus);

    for (const documentId of [".", "..", "\u0085"]) {
      const invalidId = await scenario(
        target,
        `invalid ID ${JSON.stringify(documentId)}`,
        (_request, response) => json(response, 201, JSON.stringify(documentId)),
      );
      requireFailure(target, `invalid ID ${JSON.stringify(documentId)}`, invalidId);
    }

    const malformed = await scenario(
      target,
      "malformed success",
      (_request, response) => json(response, 201, "{\"document\":"),
    );
    assert.equal(malformed.ok, false);

    const empty = await scenario(
      target,
      "empty ID",
      (_request, response) => json(response, 201, JSON.stringify("")),
    );
    assert.equal(empty.ok, false);

    const beforeInvalidRoot = createRequests.length;
    const invalidValue = await runProbe(target, { rootValue: invalidRoot });
    assert.equal(invalidValue.ok, false);
    assert.equal(createRequests.length, beforeInvalidRoot,
      `${target} sent an invalid local root`);

    const beforeInvalidConfig = createRequests.length;
    const invalidConfig = await runProbe(target, {
      serviceUrl: `${baseUrl}?query=not-allowed`,
    });
    assert.equal(invalidConfig.ok, false);
    assert.equal(createRequests.length, beforeInvalidConfig,
      `${target} sent an invalid local configuration`);
  }

  if (findings.length > 0) {
    console.error(JSON.stringify({ boundaryFindings: findings }));
  }
  for (const target of ["javascript", "erlang"]) {
    const disconnected = await scenario(target, "disconnect after POST", (request) => {
      request.socket.destroy();
    });
    requireFailure(target, "disconnect after POST", disconnected);
  }

  for (const target of ["javascript", "erlang"]) {
    const started = Date.now();
    const stalled = await scenario(target, "partial response deadline", (_request, response) => {
      response.writeHead(201, { "content-type": "application/json" });
      response.write('"');
      const interval = setInterval(() => response.write("a"), 100);
      response.on("close", () => clearInterval(interval));
    });
    assert.equal(stalled.ok, false);
    assert.match(stalled.error, /may have succeeded.*do not retry/i);
    const elapsed = Date.now() - started;
    assert(elapsed >= 29_000 && elapsed < 40_000,
      `${target} response deadline took ${elapsed}ms`);
  }

  assert.deepEqual(findings, [], findings.join("\n"));
  console.log(JSON.stringify({
    targets: ["javascript", "erlang"],
    createRequests: createRequests.length,
    redirectRequests,
    webSocketConnections,
  }));
} finally {
  await new Promise((resolveClose, rejectClose) => {
    server.close((error) => error ? rejectClose(error) : resolveClose());
    server.closeAllConnections();
  });
}
