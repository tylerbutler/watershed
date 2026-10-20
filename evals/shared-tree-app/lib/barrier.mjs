import { EventEmitter } from "node:events";
import { wait } from "./conditions.mjs";

function operationCount(sdk, direction, data, binary) {
  if (binary) return 0;
  const text = data.toString();
  let event;
  let payload;
  if (sdk === "watershed") {
    if (!text.startsWith("[")) return 0;
    const frame = JSON.parse(text);
    if (!Array.isArray(frame) || frame.length !== 5) return 0;
    event = frame[3];
    payload = frame[4];
  } else {
    if (!text.startsWith("42[")) return 0;
    const frame = JSON.parse(text.slice(2));
    event = frame[0];
    payload = frame[2];
  }
  const expected = direction === "submit" ? "submitOp" : "op";
  if (event !== expected) return 0;
  const batches = direction === "submit"
    ? (sdk === "watershed" ? payload?.messageBatches : payload)
    : (Array.isArray(payload) ? payload : payload?.op);
  if (!Array.isArray(batches)) throw new Error(`Malformed native ${expected} payload`);
  const operations = direction === "submit" ? batches.flat() : batches;
  return operations.filter(op => op?.type === "op" && op.contents !== undefined
    && Number.isInteger(op.clientSequenceNumber)
    && (direction === "submit" || Number.isInteger(op.sequenceNumber))).length;
}

export function createTransport({ sdk }) {
  if (!["watershed", "fluid"].includes(sdk)) throw new TypeError("Unknown transport SDK");
  const transport = new EventEmitter();
  const clients = new Set();
  let next = 1;
  let held;
  let queue = [];
  return Object.assign(transport, {
    register() {
      const id = `client-${next++}`;
      clients.add(id);
      return id;
    },
    unregister(id) {
      if (clients.delete(id)) transport.emit("closed", { client: id });
    },
    clients: () => [...clients],
    hold(ids) {
      if (held) throw new Error("A delivery barrier is already active");
      if (ids.some(id => !clients.has(id))) throw new Error("Barrier client is not connected");
      held = new Set(ids);
    },
    release() {
      held = undefined;
      const pending = queue;
      queue = [];
      for (const deliver of pending) deliver();
    },
    forward(client, direction, data, binary, send) {
      if (!clients.has(client)) throw new Error("Unknown transport client");
      if (!["submit", "receive"].includes(direction)) throw new TypeError("Unknown frame direction");
      const operations = operationCount(sdk, direction, data, binary);
      const event = { client, operations };
      if (direction === "submit" && operations) transport.emit("submission", event);
      const deliver = () => {
        send();
        if (direction === "receive" && operations) transport.emit("remote-delivery", event);
      };
      if (direction === "receive" && operations && held?.has(client)) {
        queue.push(deliver);
        transport.emit("held", event);
      } else deliver();
    },
  });
}

export function createBarrier({ transport, clients }) {
  if (!Array.isArray(clients) || clients.length !== 2 || new Set(clients).size !== 2) {
    throw new TypeError("A concurrency barrier requires two distinct clients");
  }
  let active = false;
  let proven = false;
  let failure;
  let heldFrames = 0;
  const submitted = new Set();
  const selected = event => active && clients.includes(event.client);
  const onSubmission = event => { if (selected(event)) submitted.add(event.client); };
  const onHeld = event => { if (selected(event)) heldFrames++; };
  const onDelivery = event => {
    if (selected(event)) failure = new Error("Operation delivery escaped the active hold");
  };
  const onClosed = event => {
    if (selected(event)) failure = new Error("A barrier client closed during the hold");
  };
  const listeners = { submission: onSubmission, held: onHeld,
    "remote-delivery": onDelivery, closed: onClosed };
  for (const [name, listener] of Object.entries(listeners)) transport.on(name, listener);
  return {
    hold() {
      if (active || proven) throw new Error("A barrier can only be held once");
      transport.hold(clients);
      active = true;
    },
    async waitForSubmissions(timeoutMs = 10_000) {
      if (!active) throw new Error("Hold delivery before waiting for submissions");
      await wait("two-client native submissions", async () => {
        if (failure) throw failure;
        return submitted.size === clients.length && heldFrames > 0;
      }, Boolean, timeoutMs);
      proven = true;
    },
    evidence: () => ({ submittedClients: [...submitted], heldFrames, proven,
      deliveryViolation: failure?.message ?? null }),
    release() {
      if (!proven || failure) throw new Error("Cannot release an unverified concurrency barrier");
      active = false;
      transport.release();
    },
    close() {
      const release = active;
      active = false;
      for (const [name, listener] of Object.entries(listeners)) transport.off(name, listener);
      if (release) transport.release();
    },
  };
}
