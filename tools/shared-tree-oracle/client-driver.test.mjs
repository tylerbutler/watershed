import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { createConnection, createServer } from "node:net";
import test from "node:test";
import { JsonLinesChannel, TcpGate } from "./client-driver.mjs";

function child(source) {
  return spawn(process.execPath, ["-e", source], { stdio: ["pipe", "pipe", "pipe"] });
}

test("split and coalesced replies retain request correlation", async (t) => {
  const process = child(`
    let data = "";
    process.stdin.on("data", (chunk) => {
      data += chunk;
      if (data.split("\\n").length >= 3) {
        process.stdout.write('{"requestId":1,"ok":true}\\n{"requestId":2,"ok":true}\\n');
      }
    });
  `);
  t.after(() => process.kill());
  const channel = new JsonLinesChannel(process, 2000);
  const first = channel.request({ command: "checkpoint" });
  const second = channel.request({ command: "checkpoint" });
  assert.equal((await first).requestId, 1);
  assert.equal((await second).requestId, 2);
});

test("malformed and mismatched output fails the pending request", async (t) => {
  for (const output of ["not-json", '{"requestId":99,"ok":true}']) {
    const process = child(`process.stdin.once("data", () => process.stdout.write(${JSON.stringify(`${output}\n`)}));`);
    t.after(() => process.kill());
    const channel = new JsonLinesChannel(process, 2000);
    await assert.rejects(channel.request({ command: "checkpoint" }));
  }
});

test("duplicate replies and premature child exit fail closed", async (t) => {
  const process = child(`
    process.stdin.once("data", () => process.stdout.write('{"requestId":1,"ok":true}\\n{"requestId":1,"ok":true}\\n'));
  `);
  t.after(() => process.kill());
  const channel = new JsonLinesChannel(process, 2000);
  await channel.request({ command: "checkpoint" });
  await assert.rejects(channel.request({ command: "checkpoint" }));
  const exiting = child('process.stdin.once("data", () => process.exit(3))');
  const missing = new JsonLinesChannel(exiting, 2000);
  await assert.rejects(missing.request({ command: "checkpoint" }));
});

test("missing executable and unanswered request fail rather than skip", async (t) => {
  const absent = spawn("__missing_watershed_beam_executable__", [], {
    stdio: ["pipe", "pipe", "pipe"],
  });
  await assert.rejects(
    new JsonLinesChannel(absent, 2000).request({ command: "checkpoint" }),
    { code: "ENOENT" },
  );
  const silent = child('process.stdin.resume()');
  t.after(() => silent.kill());
  await assert.rejects(
    new JsonLinesChannel(silent, 50).request({ command: "checkpoint" }),
    /timed out/,
  );
});

test("the byte gate isolates directions and drops old sockets", async (t) => {
  const echo = createServer((socket) => socket.pipe(socket));
  echo.listen(0, "127.0.0.1");
  await once(echo, "listening");
  const gate = await TcpGate.open("127.0.0.1", echo.address().port);
  t.after(async () => { await gate.close(); echo.close(); });
  const socket = createConnection(gate.port, "127.0.0.1");
  await once(socket, "connect");
  socket.write("before");
  assert.equal((await once(socket, "data"))[0].toString(), "before");
  gate.pauseInbound();
  socket.write("withheld");
  socket.on("error", () => {});
  const closed = new Promise((resolve) => socket.once("close", resolve));
  await gate.disconnect();
  await closed;
  const replacement = createConnection(gate.port, "127.0.0.1");
  await once(replacement, "connect");
  await gate.reconnect();
  replacement.write("after");
  assert.equal((await once(replacement, "data"))[0].toString(), "after");
  replacement.destroy();
});

test("disconnecting one gate leaves another client's byte stream intact", async (t) => {
  const echo = createServer((socket) => socket.pipe(socket));
  echo.listen(0, "127.0.0.1");
  await once(echo, "listening");
  const first = await TcpGate.open("127.0.0.1", echo.address().port);
  const second = await TcpGate.open("127.0.0.1", echo.address().port);
  t.after(async () => { await first.close(); await second.close(); echo.close(); });
  const socket = createConnection(second.port, "127.0.0.1");
  await once(socket, "connect");
  await first.disconnect();
  socket.write("independent");
  assert.equal((await once(socket, "data"))[0].toString(), "independent");
  socket.destroy();
});

test("the reconnect gate forwards the upgrade and identity before withholding the tail", async (t) => {
  const connected = Buffer.from('["1","2","document","connect_document_success",{}]');
  const tail = Buffer.from('["1","3","document","op",{}]');
  const frame = (payload) => Buffer.concat([
    Buffer.from([0x81, payload.length]), payload,
  ]);
  const server = createServer((socket) => {
    socket.write(Buffer.concat([
      Buffer.from("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n\r\n"),
      frame(connected), frame(tail),
    ]));
  });

  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  const gate = await TcpGate.open("127.0.0.1", server.address().port);
  t.after(async () => { await gate.close(); server.close(); });
  await gate.reconnect({ pauseAfterConnectSuccess: true });
  const client = createConnection(gate.port, "127.0.0.1");
  t.after(() => client.destroy());
  const received = [];
  const identity = new Promise((resolve) => client.on("data", (chunk) => {
    received.push(chunk);
    if (Buffer.concat(received).includes(frame(connected))) resolve();
  }));
  await identity;
  assert.equal(gate.connectSuccesses, 1);
  assert(Buffer.concat(received).includes(frame(connected)));
  assert(!Buffer.concat(received).includes(frame(tail)));
  gate.resumeInbound();
  await once(client, "data");
  assert(Buffer.concat(received).includes(frame(tail)));
});

test("withheld outbound frames stay off the server but retain their original bytes", async (t) => {
  const upstream = createServer((socket) => {
    socket.on("error", () => {});
    socket.on("data", () => assert.fail("Withheld submission reached the server"));
  });
  upstream.listen(0, "127.0.0.1");
  await once(upstream, "listening");
  const gate = await TcpGate.open("127.0.0.1", upstream.address().port);
  t.after(async () => { await gate.close(); upstream.close(); });
  const client = createConnection(gate.port, "127.0.0.1");
  client.on("error", () => {});
  await once(client, "connect");
  while (!gate.connections) await new Promise((resolve) => setImmediate(resolve));
  gate.pauseOutbound();
  client.write(Buffer.from([0x81, 0x85, 1, 2, 3, 4, 105, 103]));
  const fragmentDeadline = Date.now() + 1000;
  for (;;) {
    try {
      gate.withheldOutboundPayloads();
    } catch {
      break;
    }
    assert(Date.now() < fragmentDeadline, "Partial frame did not reach the gate");
    await new Promise((resolve) => setTimeout(resolve, 5));
  }
  assert.deepEqual(gate.withheldOutboundPayloads({ allowIncomplete: true }), []);
  client.write(Buffer.from([111, 104, 110]));
  const deadline = Date.now() + 1000;
  while (gate.withheldOutboundPayloads({ allowIncomplete: true }).length === 0) {
    assert(Date.now() < deadline, "Gate did not capture outbound bytes");
    await new Promise((resolve) => setTimeout(resolve, 5));
  }
  assert.deepEqual(gate.withheldOutboundPayloads(), ["hello"]);
  client.destroy();
});
