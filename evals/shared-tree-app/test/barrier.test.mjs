import assert from "node:assert/strict";
import test from "node:test";
import { EventEmitter } from "node:events";
import { createBarrier, createTransport } from "../lib/barrier.mjs";

const operation = { type: "op", contents: { change: "opaque" },
  clientSequenceNumber: 1, referenceSequenceNumber: 1, sequenceNumber: 2 };
function frames(sdk) {
  return sdk === "watershed" ? {
    submit: Buffer.from(JSON.stringify(["1", "2", "document:test", "submitOp",
      { clientId: "native-client", messageBatches: [[operation]] }])),
    delivery: Buffer.from(JSON.stringify([null, null, "document:test", "op", [operation]])),
    control: Buffer.from(JSON.stringify([null, "3", "phoenix", "phx_reply", { status: "ok" }])),
  } : {
    submit: Buffer.from(`42${JSON.stringify(["submitOp", "native-client", [[operation]]])}`),
    delivery: Buffer.from(`42${JSON.stringify(["op", "document", [operation]])}`),
    control: Buffer.from("2"),
  };
}

for (const sdk of ["watershed", "fluid"]) {
  test(`${sdk} barrier forwards submissions and controls but holds actual operation bytes`, async () => {
    const transport = createTransport({ sdk });
    const a = transport.register();
    const b = transport.register();
    const barrier = createBarrier({ transport, clients: [a, b] });
    const frame = frames(sdk);
    const delivered = [];
    barrier.hold();
    for (const client of [a, b]) {
      transport.forward(client, "submit", frame.submit, false, () => delivered.push(`submit:${client}`));
      transport.forward(client, "receive", frame.delivery, false, () => delivered.push(frame.delivery));
    }
    transport.forward(a, "receive", frame.control, false, () => delivered.push("control"));
    await barrier.waitForSubmissions(100);
    assert.deepEqual(delivered, [`submit:${a}`, `submit:${b}`, "control"]);
    assert.equal(barrier.evidence().heldFrames, 2);
    barrier.release();
    assert.deepEqual(delivered.slice(3), [frame.delivery, frame.delivery]);
    assert.deepEqual(barrier.evidence().submittedClients, [a, b]);
    barrier.close();
  });
}

test("barrier does not count repeated submissions from one client as two clients", async () => {
  const transport = createTransport({ sdk: "fluid" });
  const a = transport.register();
  const b = transport.register();
  const barrier = createBarrier({ transport, clients: [a, b] });
  barrier.hold();
  for (let i = 0; i < 3; i++) transport.forward(a, "submit", frames("fluid").submit, false, () => {});
  await assert.rejects(barrier.waitForSubmissions(10), /submission.*timed out/i);
  barrier.close();
});

test("barrier rejects operation delivery during its claimed hold", async () => {
  const transport = new EventEmitter();
  transport.clients = () => ["a", "b"];
  transport.hold = () => {};
  transport.release = () => {};
  const barrier = createBarrier({ transport, clients: ["a", "b"] });
  barrier.hold();
  transport.emit("remote-delivery", { client: "b", operations: 1 });
  transport.emit("submission", { client: "a", operations: 1 });
  transport.emit("submission", { client: "b", operations: 1 });
  await assert.rejects(barrier.waitForSubmissions(10), /delivery.*hold/i);
  barrier.close();
});

test("barrier rejects a selected client disappearing instead of accepting reconnects", async () => {
  const transport = createTransport({ sdk: "watershed" });
  const a = transport.register();
  const b = transport.register();
  const barrier = createBarrier({ transport, clients: [a, b] });
  barrier.hold();
  transport.unregister(b);
  await assert.rejects(barrier.waitForSubmissions(10), /closed/i);
  barrier.close();
});
