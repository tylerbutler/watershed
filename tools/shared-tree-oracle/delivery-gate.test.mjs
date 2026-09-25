import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { once } from "node:events";
import { createServer } from "node:http";
import { createRequire } from "node:module";
import test from "node:test";
import { DeliveryGate } from "./delivery-gate.mjs";

const require = createRequire(new URL("../../package.json", import.meta.url));
const WebSocket = require("ws");
const WebSocketServer = WebSocket.WebSocketServer ?? WebSocket.Server;

async function service() {
  const received = [];
  const server = createServer((request, response) => {
    const chunks = [];
    request.on("data", (chunk) => chunks.push(chunk));
    request.on("end", () => {
      const body = Buffer.concat(chunks);
      response.writeHead(206, {
        "content-type": "application/octet-stream",
        "x-private-token": "must-not-be-recorded",
      });
      response.end(Buffer.concat([Buffer.from("echo:"), body]));
    });
  });
  const sockets = new Set();
  const webSockets = new WebSocketServer({
    noServer: true,
    perMessageDeflate: true,
    maxPayload: 1024 * 1024,
  });
  server.on("upgrade", (request, socket, head) => {
    webSockets.handleUpgrade(request, socket, head, (client) => {
      webSockets.emit("connection", client, request);
    });
  });
  webSockets.on("connection", (socket) => {
    sockets.add(socket);
    socket.on("close", () => sockets.delete(socket));
    socket.on("message", (payload, binary) => {
      const bytes = Buffer.from(payload);
      received.push(bytes);
      socket.send(bytes, { binary, compress: true });
    });
  });
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  return {
    port: server.address().port,
    received,
    connections() {
      return sockets.size;
    },
    broadcast(payload) {
      for (const socket of sockets) socket.send(payload);
    },
    async close() {
      for (const socket of sockets) socket.terminate();
      await new Promise((resolve) => webSockets.close(resolve));
      await new Promise((resolve) => server.close(resolve));
    },
  };
}

async function connected(port) {
  const socket = new WebSocket(
    `ws://127.0.0.1:${port}/socket/websocket?vsn=2.0.0&token=secret`,
    { perMessageDeflate: true },
  );
  await once(socket, "open");
  return socket;
}

function collect(socket, count) {
  const messages = [];
  return new Promise((resolve, reject) => {
    const timer = setTimeout(
      () => reject(new Error(`Received ${messages.length} of ${count} messages`)),
      2000,
    );
    socket.on("message", (payload) => {
      messages.push(Buffer.from(payload).toString());
      if (messages.length === count) {
        clearTimeout(timer);
        resolve(messages);
      }
    });
  });
}

async function until(predicate, message) {
  const deadline = Date.now() + 2000;
  while (!predicate()) {
    assert(Date.now() < deadline, message);
    await new Promise((resolve) => setImmediate(resolve));
  }
}

test("complete compressed and fragmented messages release in reverse order with one duplicate", async (t) => {
  const upstream = await service();
  const gate = await DeliveryGate.open("127.0.0.1", upstream.port);
  const socket = await connected(gate.port);
  t.after(async () => {
    socket.terminate();
    await gate.close();
    await upstream.close();
  });
  gate.hold("outbound", "op");
  const payloads = [
    '["1",null,"document:test","op",{"sequenceNumber":10}]',
    '["2",null,"document:test","op",{"sequenceNumber":11}]',
  ];
  socket.send(payloads[0].slice(0, 18), { fin: false, compress: true });
  socket.send(payloads[0].slice(18), { fin: true, compress: true });
  socket.send(payloads[1], { compress: true });
  await until(() => gate.evidence().held.length === 2, "Gate did not hold both messages");
  const echoed = collect(socket, 3);
  await gate.release("outbound", { order: "reverse", duplicate: true });
  await until(() => upstream.received.length === 3, "Upstream did not receive released messages");
  assert.deepEqual(
    upstream.received.map((payload) => payload.toString()),
    [payloads[1], payloads[0], payloads[0]],
  );
  assert.deepEqual(await echoed, [payloads[1], payloads[0], payloads[0]]);
  const evidence = gate.evidence();
  assert.deepEqual(
    evidence.delivered
      .filter(({ direction }) => direction === "outbound")
      .map(({ direction, kind, duplicate }) => ({ direction, kind, duplicate })),
    [
      { direction: "outbound", kind: "op", duplicate: false },
      { direction: "outbound", kind: "op", duplicate: false },
      { direction: "outbound", kind: "op", duplicate: true },
    ],
  );
  assert.equal(evidence.outboundTreeMessages.length, 3);
  assert.deepEqual(evidence.outboundTreeMessages[0].sequenceNumbers, [11]);
  assert(!JSON.stringify(evidence).includes("secret"));
});

test("one Phoenix op payload records every contained sequence number", async (t) => {
  const upstream = await service();
  const gate = await DeliveryGate.open("127.0.0.1", upstream.port);
  const socket = await connected(gate.port);
  t.after(async () => {
    socket.terminate();
    await gate.close();
    await upstream.close();
  });
  const payload = JSON.stringify([
    "1", "2", "document:test", "op",
    [{ sequenceNumber: 20 }, { sequenceNumber: 21 }],
  ]);
  const echoed = collect(socket, 1);
  socket.send(payload);
  assert.deepEqual(await echoed, [payload]);
  assert.deepEqual(gate.evidence().outboundTreeMessages[0].sequenceNumbers, [20, 21]);
});

test("requestOps forwards unchanged and records only sanitized repair evidence", async (t) => {
  const upstream = await service();
  const gate = await DeliveryGate.open("127.0.0.1", upstream.port);
  const socket = await connected(gate.port);
  t.after(async () => {
    socket.terminate();
    await gate.close();
    await upstream.close();
  });
  const payload = JSON.stringify([
    "1", "2", "document:test", "requestOps",
    { from: 37, token: "must-not-be-recorded" },
  ]);
  const echoed = collect(socket, 1);
  socket.send(payload);
  assert.deepEqual(await echoed, [payload]);
  await until(() => upstream.received.length === 1,
    "Upstream did not receive the repair request");
  assert.deepEqual(upstream.received[0].toString(), payload);
  assert.deepEqual(gate.evidence().repairRequests, [{
    from: 37,
    topic: "document:test",
    hash: createHash("sha256").update(payload).digest("hex"),
  }]);
  assert.deepEqual(gate.evidence().delivered, []);
  assert(!JSON.stringify(gate.evidence()).includes("must-not-be-recorded"));
});

test("duplicate release callback runs after originals and before the duplicate", async (t) => {
  const upstream = await service();
  const gate = await DeliveryGate.open("127.0.0.1", upstream.port);
  const socket = await connected(gate.port);
  t.after(async () => {
    socket.terminate();
    await gate.close();
    await upstream.close();
  });
  gate.hold("outbound", "op");
  const payloads = [
    '["1",null,"document:test","op",{"sequenceNumber":50}]',
    '["2",null,"document:test","op",{"sequenceNumber":51}]',
  ];
  socket.send(payloads[0]);
  socket.send(payloads[1]);
  await until(() => gate.evidence().held.length === 2, "Gate did not hold both messages");
  let callbackCalled = false;
  await gate.release("outbound", {
    duplicate: true,
    async beforeDuplicate() {
      callbackCalled = true;
      assert.deepEqual(
        gate.evidence().delivered.map(({ duplicate }) => duplicate),
        [false, false],
      );
    },
  });
  assert.equal(callbackCalled, true);
  assert.deepEqual(
    gate.evidence().delivered.map(({ duplicate }) => duplicate),
    [false, false, true],
  );
  await until(() => upstream.received.length === 3,
    "Upstream did not receive original and duplicate messages");
  assert.deepEqual(
    upstream.received.map((payload) => payload.toString()),
    [payloads[0], payloads[1], payloads[1]],
  );
});

test("connection handshake records only safe replay sequence metadata", async (t) => {
  const upstream = await service();
  const gate = await DeliveryGate.open("127.0.0.1", upstream.port);
  const socket = await connected(gate.port);
  t.after(async () => {
    socket.terminate();
    await gate.close();
    await upstream.close();
  });
  await until(() => upstream.connections() === 1, "Gate did not connect upstream");
  const payload = JSON.stringify([
    "1", "2", "document:test", "connect_document_success",
    {
      token: "must-not-be-recorded",
      checkpointSequenceNumber: 124,
      summaryContext: {
        handle: "must-not-be-recorded",
        sequenceNumber: 123,
      },
      initialMessages: [
        { sequenceNumber: 124, contents: { authorization: "must-not-be-recorded" } },
      ],
    },
  ]);
  const received = collect(socket, 1);
  upstream.broadcast(payload);
  assert.deepEqual(await received, [payload]);
  assert.deepEqual(gate.evidence().handshakes, [{
    checkpointSequenceNumber: 124,
    summarySequenceNumber: 123,
    initialMessageSequenceNumbers: [124],
  }]);
  assert(!JSON.stringify(gate.evidence()).includes("must-not-be-recorded"));
});

test("one-shot injection mutates only the owned document and records sanitized payloads", async (t) => {
  const upstream = await service();
  const gate = await DeliveryGate.open("127.0.0.1", upstream.port, {
    documentId: "owned",
  });
  const socket = await connected(gate.port);
  t.after(async () => {
    socket.terminate();
    await gate.close();
    await upstream.close();
  });
  gate.inject({
    documentId: "owned",
    mutation: "unknown-runtime-message",
    expectedStage: "runtime-message",
    direction: "inbound",
    kind: "op",
    transform(payload) {
      payload[4].contents = {
        requiredUnsupportedChange: {},
        token: "must-not-be-recorded",
      };
      return payload;
    },
  });
  await until(() => upstream.connections() === 1, "Gate did not connect upstream");
  const received = collect(socket, 3);
  upstream.broadcast(JSON.stringify([
    "1", null, "document:fluid:other", "op",
    { sequenceNumber: 40, contents: { title: "other" } },
  ]));
  upstream.broadcast(JSON.stringify([
    "2", null, "document:fluid:owned", "op",
    {
      sequenceNumber: 41,
      contents: {
        title: "original",
        authorization: "must-not-be-recorded",
        url: "/socket?token=must-not-be-recorded",
      },
    },
  ]));
  upstream.broadcast(JSON.stringify([
    "3", null, "document:fluid:owned", "op",
    { sequenceNumber: 42, contents: { title: "after" } },
  ]));
  const messages = (await received).map(JSON.parse);
  assert.equal(messages[0][4].contents.title, "other");
  assert.deepEqual(messages[1][4].contents, {
    requiredUnsupportedChange: {},
    token: "must-not-be-recorded",
  });
  assert.equal(messages[2][4].contents.title, "after");
  const evidence = gate.evidence();
  assert.equal(evidence.injections.length, 1);
  assert.deepEqual(
    {
      documentId: evidence.injections[0].documentId,
      mutation: evidence.injections[0].mutation,
      expectedStage: evidence.injections[0].expectedStage,
      direction: evidence.injections[0].direction,
      kind: evidence.injections[0].kind,
    },
    {
      documentId: "owned",
      mutation: "unknown-runtime-message",
      expectedStage: "runtime-message",
      direction: "inbound",
      kind: "op",
    },
  );
  assert.equal(evidence.injections[0].originalPayload[4].contents.title, "original");
  assert.deepEqual(evidence.injections[0].mutatedPayload[4].contents, {
    requiredUnsupportedChange: {},
    token: "[redacted]",
  });
  assert(!JSON.stringify(evidence).includes("must-not-be-recorded"));
  assert(!JSON.stringify(evidence).includes("sec-websocket"));
});

test("gates isolate clients and drop held data on disconnect", async (t) => {
  const upstream = await service();
  const first = await DeliveryGate.open("127.0.0.1", upstream.port);
  const second = await DeliveryGate.open("127.0.0.1", upstream.port);
  const firstSocket = await connected(first.port);
  const secondSocket = await connected(second.port);
  t.after(async () => {
    firstSocket.terminate();
    secondSocket.terminate();
    await first.close();
    await second.close();
    await upstream.close();
  });
  first.hold("outbound", "op");
  firstSocket.send('["1",null,"document:test","op",{"sequenceNumber":30}]');
  const secondEcho = collect(secondSocket, 1);
  secondSocket.send('["2",null,"document:test","op",{"sequenceNumber":31}]');
  assert.deepEqual(await secondEcho, [
    '["2",null,"document:test","op",{"sequenceNumber":31}]',
  ]);
  await first.disconnect();
  await assert.rejects(first.release("outbound"), /disconnected|dropped/);
  await first.reconnect();
  const replacement = await connected(first.port);
  t.after(() => replacement.terminate());
  const replacementEcho = collect(replacement, 1);
  replacement.send('["3",null,"document:test","op",{"sequenceNumber":32}]');
  assert.deepEqual(await replacementEcho, [
    '["3",null,"document:test","op",{"sequenceNumber":32}]',
  ]);
});

test("summary loads hold complete HTTP responses and preserve bytes and status", async (t) => {
  const upstream = await service();
  const gate = await DeliveryGate.open("127.0.0.1", upstream.port);
  t.after(async () => {
    await gate.close();
    await upstream.close();
  });
  gate.hold("inbound", "summary-load");
  const responsePromise = fetch(
    `http://127.0.0.1:${gate.port}/repos/fluid/git/blobs/blob-id?token=secret`,
    {
      method: "POST",
      headers: {
        authorization: "Bearer private",
        "content-type": "application/octet-stream",
      },
      body: Buffer.from([0, 1, 2, 255]),
    },
  );
  await until(
    () => gate.evidence().held.some(({ kind }) => kind === "summary-load"),
    "Gate did not hold the summary response",
  );
  await gate.release("inbound");
  const response = await responsePromise;
  assert.equal(response.status, 206);
  assert.deepEqual(
    Buffer.from(await response.arrayBuffer()),
    Buffer.from([101, 99, 104, 111, 58, 0, 1, 2, 255]),
  );
  const evidence = gate.evidence();
  assert.deepEqual(evidence.http, [{
    id: 1,
    method: "POST",
    path: "/repos/fluid/git/blobs/blob-id",
    status: 206,
    requestHash: createHash("sha256").update(Buffer.from([0, 1, 2, 255])).digest("hex"),
    responseHash: createHash("sha256")
      .update(Buffer.from([101, 99, 104, 111, 58, 0, 1, 2, 255])).digest("hex"),
  }]);
  assert(!JSON.stringify(evidence).includes("private"));
  assert(!JSON.stringify(evidence).includes("token=secret"));
});

test("summary-load injection changes one scoped response without recording secrets", async (t) => {
  const upstream = await service();
  const gate = await DeliveryGate.open("127.0.0.1", upstream.port, {
    documentId: "owned",
  });
  t.after(async () => {
    await gate.close();
    await upstream.close();
  });
  gate.inject({
    documentId: "owned",
    mutation: "unsupported-summary-version",
    expectedStage: "summary-load",
    direction: "inbound",
    kind: "summary-load",
    transform(payload) {
      assert.equal(payload.path, "/repos/fluid/git/blobs/blob-id");
      return {
        ...payload,
        bytes: Buffer.from(JSON.stringify({
          version: 999,
          token: "must-not-be-recorded",
        })),
      };
    },
  });
  const response = await fetch(
    `http://127.0.0.1:${gate.port}/repos/fluid/git/blobs/blob-id?token=secret`,
    { method: "POST", body: Buffer.from("original") },
  );
  assert.deepEqual(await response.json(), {
    version: 999,
    token: "must-not-be-recorded",
  });
  const evidence = gate.evidence();
  assert.equal(evidence.injections.length, 1);
  assert.deepEqual(evidence.injections[0].originalPayload, {
    byteLength: 13,
    hash: createHash("sha256").update("echo:original").digest("hex"),
  });
  assert.deepEqual(evidence.injections[0].mutatedPayload, {
    version: 999,
    token: "[redacted]",
  });
  assert(!JSON.stringify(evidence).includes("must-not-be-recorded"));
  assert(!JSON.stringify(evidence).includes("token=secret"));
});

test("invalid controls and release after close fail explicitly", async () => {
  const upstream = await service();
  const gate = await DeliveryGate.open("127.0.0.1", upstream.port);
  assert.throws(() => gate.hold("sideways", "op"), /direction/);
  assert.throws(() => gate.hold("outbound", "heartbeat"), /kind/);
  await assert.rejects(gate.release("outbound", { order: "random" }), /order/);
  await assert.rejects(
    gate.release("outbound", { duplicate: true, beforeDuplicate: "later" }),
    /beforeDuplicate/,
  );
  await assert.rejects(
    gate.release("outbound", { beforeDuplicate() {} }),
    /requires duplicate/,
  );
  await gate.close();
  await assert.rejects(gate.release("outbound"), /closed/);
  await upstream.close();
});

test("client close tears down the upstream socket before later broadcasts", async (t) => {
  const upstream = await service();
  const gate = await DeliveryGate.open("127.0.0.1", upstream.port);
  const socket = await connected(gate.port);
  t.after(async () => {
    await gate.close();
    await upstream.close();
  });
  await until(() => upstream.connections() === 1, "Gate did not connect upstream");
  socket.close();
  await until(
    () => upstream.connections() === 0,
    "Upstream socket remained connected after client close",
  );
  upstream.broadcast("heartbeat");
  await new Promise((resolve) => setImmediate(resolve));
  assert.deepEqual(gate.evidence().errors, []);
});
