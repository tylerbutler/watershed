import assert from "node:assert/strict";
import { createServer } from "node:http";
import test from "node:test";

import { startChecklistServer } from "../serve.mjs";

test("server proxies document creation to Floodgate", async (context) => {
  let request = null;
  const upstream = createServer((incoming, response) => {
    let body = "";
    incoming.setEncoding("utf8");
    incoming.on("data", (chunk) => {
      body += chunk;
    });
    incoming.on("end", () => {
      request = {
        method: incoming.method,
        url: incoming.url,
        authorization: incoming.headers.authorization,
        body,
      };
      response.writeHead(201, { "content-type": "application/json" });
      response.end('"doc-1"');
    });
  });
  await listen(upstream);
  context.after(() => upstream.close());

  const server = await startChecklistServer({
    appRoot: new URL("..", import.meta.url),
    upstream: "http://127.0.0.1:" + upstream.address().port,
    port: 0,
  });
  context.after(() => server.close());

  const response = await fetch(
    "http://127.0.0.1:" + server.port + "/documents/dev-tenant",
    {
      method: "POST",
      headers: {
        authorization: "Bearer token",
        "content-type": "application/json",
      },
      body: '{"sequenceNumber":0}',
    },
  );

  assert.equal(response.status, 201);
  assert.equal(await response.text(), '"doc-1"');
  assert.deepEqual(request, {
    method: "POST",
    url: "/documents/dev-tenant",
    authorization: "Bearer token",
    body: '{"sequenceNumber":0}',
  });

  const history = await fetch(
    "http://127.0.0.1:" + server.port + "/repos/dev-tenant/git/commits/abc",
  );
  assert.equal(history.status, 201);
  assert.equal(request.url, "/repos/dev-tenant/git/commits/abc");
});

function listen(server) {
  return new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });
}
