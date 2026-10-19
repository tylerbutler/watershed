import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import { test } from "node:test";
import type { ISignaler } from "@fluid-experimental/data-objects";
import { ConnectionState, type IFluidContainer } from "fluid-framework";
import {
  available, decode, encode, expire, fieldKey, focus, initialPolicy,
  reconcile, reconcileLocal, receive, startPresence,
  type Field, type Peer, type SelectionMetadata,
} from "./selection.ts";

const metadata: SelectionMetadata = {
  name: "Alex", color: "blue", token: 1,
  selected: { kind: "fixed", field: "owner.name" },
};
const brief = {
  review: { reviewer: "", approved: false },
  schedule: { milestones: [{ id: "first" }, { id: "second" }] },
};

test("metadata codec accepts enumerated fields and clamps display names", () => {
  const fixed = ["title", "owner.name", "owner.email", "schedule.start",
    "schedule.target", "review.reviewer", "review.approved"] as const;
  const fields: (Field | null)[] = [
    ...fixed.map((field) => ({ kind: "fixed" as const, field })),
    { kind: "milestone", id: "second", field: "title" },
    { kind: "milestone", id: "second", field: "completed" }, null,
  ];
  for (const selected of fields) {
    for (const color of ["blue", "green", "amber", "violet"] as const) {
      const value = { ...metadata, selected, color };
      assert.deepEqual(decode(encode(value)), value);
    }
  }
  assert.equal(decode({ ...metadata, name: "x".repeat(100) }).name.length, 80);
  assert.equal(decode({ ...metadata, name: "😀".repeat(100) }).name, "😀".repeat(80));
  assert.equal(fieldKey({ kind: "milestone", id: "second", field: "title" }), "milestone/second/title");
  assert.equal(fieldKey(metadata.selected!), "owner.name");
});

test("metadata codec rejects malformed wire data rather than accepting paths or colors", () => {
  for (const value of [
    null, [], {}, { ...metadata, color: "red" }, { ...metadata, name: 1 },
    ...[-1, 1.5, Infinity, Number.MAX_SAFE_INTEGER + 1, "1"].map((token) => ({ ...metadata, token })),
    ...[{}, { kind: "fixed", field: "review.unknown" },
      { kind: "milestone", id: "", field: "title" },
      { kind: "milestone", id: "a/b", field: "title" },
      { kind: "milestone", id: 0, field: "completed" },
      { kind: "milestone", id: "second", field: "id" },
    ].map((selected) => ({ ...metadata, selected })),
  ]) assert.throws(() => decode(value));
});

test("focus transitions including blur increment tokens but heartbeats do not", () => {
  assert.equal(focus(metadata, metadata.selected).token, 1);
  const blurred = focus(metadata, null);
  assert.equal(blurred.token, 2);
  assert.equal(focus(blurred, metadata.selected).token, 3);
  assert.equal(reconcileLocal({ ...metadata, selected: { kind: "fixed", field: "review.approved" } },
    { ...brief, review: undefined }).token, 2);
});

test("expiry removes a peer only after its refreshed liveness window", () => {
  const peers = receive(new Map(), "session-b", metadata, 1_000);
  const refreshed = receive(peers, "session-b", metadata, 3_000);
  assert.equal(peers.get("session-b")!.seenAt, 1_000);
  assert.equal(expire(refreshed, 9_499).size, 1);
  assert.equal(expire(refreshed, 9_500).size, 0);
  const older = receive(refreshed, "session-b", { ...metadata, token: 0, selected: null }, 4_000);
  assert.deepEqual(older.get("session-b"), { metadata, seenAt: 4_000 });
  assert.deepEqual(receive(older, "session-b", { ...metadata, selected: null }, 5_000)
    .get("session-b")!.metadata, metadata);
});

test("review invalidation survives recreation, missing peers and stale tokens; new focus recovers", () => {
  const review: SelectionMetadata = { ...metadata, selected: { kind: "fixed", field: "review.reviewer" } };
  const peers = [{ sessionId: "a", metadata: review }, { sessionId: "b", metadata: review }];
  let state = reconcile(initialPolicy(), peers, brief);
  assert.equal(state.peers.length, 2);
  state = reconcile(state, peers, { ...brief, review: undefined });
  assert.ok(state.peers.every((peer) => peer.metadata.selected === null));
  state = reconcile(state, [], brief);
  state = reconcile(state, peers, brief);
  assert.ok(state.peers.every((peer) => peer.metadata.selected === null));
  state = reconcile(state, [
    { sessionId: "a", metadata: { ...review, token: 2 } },
    { sessionId: "b", metadata: { ...review, token: 0 } },
  ], brief);
  assert.deepEqual(state.peers.map((p) => p.metadata.selected), [review.selected, null]);
});

test("milestone selection stays on its identity when a preceding neighbor disappears", () => {
  const selected: Field = { kind: "milestone", id: "second", field: "completed" };
  const peers = [{ sessionId: "a", metadata: { ...metadata, selected } }];
  const after = { ...brief, schedule: { milestones: [{ id: "second" }] } };
  const state = reconcile(reconcile(initialPolicy(), peers, brief), peers, after);
  assert.deepEqual(state.peers[0].metadata.selected, selected);
  assert.equal(available(selected, after), true);
  const removed = reconcile(state, peers, { ...brief, schedule: { milestones: [] } });
  assert.equal(removed.peers[0].metadata.selected, null);
  assert.equal(reconcile(removed, peers, brief).peers[0].metadata.selected, null);
});

class FakeSignaler extends EventEmitter implements ISignaler {
  sent: { name: string; payload: unknown }[] = [];
  onSignal: ISignaler["onSignal"] = (name, listener) => { this.on(name, listener); return this; };
  offSignal: ISignaler["offSignal"] = (name, listener) => { this.off(name, listener); return this; };
  submitSignal: ISignaler["submitSignal"] = (name, payload) => { this.sent.push({ name, payload }); };
}

test("Signaler adapter sends, refreshes, disconnects, reconnects and removes all listeners", (t) => {
  t.mock.timers.enable({ apis: ["setInterval", "Date"], now: 0 });
  t.mock.method(performance, "now", () => Date.now());
  const signaler = new FakeSignaler();
  const connection = Object.assign(new EventEmitter(), { connectionState: ConnectionState.Connected });
  // The adapter uses only connection state and the public connection events.
  const container = connection as unknown as IFluidContainer;
  const rosters: Peer[][] = [];
  const errors: unknown[] = [];
  const session = startPresence(signaler, container, metadata, (peers) => rosters.push(peers), (e) => errors.push(e));
  assert.deepEqual(signaler.sent, [{ name: "project-brief-selection", payload: metadata }]);
  const emit = (value: unknown, id = "server-b", local = false) =>
    signaler.emit("project-brief-selection", id, local, value);
  emit({ ...metadata, sessionId: "forged" });
  assert.equal(rosters.at(-1)![0].sessionId, "server-b");
  emit(metadata, "local", true);
  assert.equal(rosters.at(-1)!.length, 1);
  signaler.emit("unrelated", "bad", false, {});
  emit({ ...metadata, color: "red" });
  assert.equal(errors.length, 1);
  assert.equal(rosters.at(-1)!.length, 1);
  t.mock.timers.tick(2_000);
  assert.equal(signaler.sent.length, 2);
  emit(metadata);
  t.mock.timers.tick(6_000);
  assert.equal(rosters.at(-1)!.length, 1);
  t.mock.timers.tick(2_000);
  assert.equal(rosters.at(-1)!.length, 0);
  emit(metadata);
  connection.connectionState = ConnectionState.Disconnected;
  connection.emit("disconnected");
  assert.deepEqual(rosters.at(-1), []);
  const sends = signaler.sent.length;
  session.update(focus(metadata, null));
  emit(metadata);
  t.mock.timers.tick(4_000);
  assert.equal(signaler.sent.length, sends);
  assert.deepEqual(rosters.at(-1), []);
  connection.connectionState = ConnectionState.Connected;
  connection.emit("connected", "new-local-id");
  assert.equal(signaler.sent.length, sends + 1);
  assert.deepEqual(signaler.sent.at(-1)!.payload, { ...metadata, token: 2, selected: null });
  session.update(focus(focus(metadata, null), { kind: "fixed", field: "title" }));
  assert.equal(signaler.sent.length, sends + 2);
  const lateSignal = signaler.listeners("project-brief-selection")[0];
  session.stop();
  session.stop();
  const callbacks = rosters.length;
  const errorCount = errors.length;
  const stoppedSends = signaler.sent.length;
  emit({});
  lateSignal("server-b", false, {});
  connection.emit("connected");
  connection.emit("disconnected");
  session.update(metadata);
  t.mock.timers.tick(10_000);
  assert.equal(rosters.length, callbacks);
  assert.equal(errors.length, errorCount);
  assert.equal(signaler.sent.length, stoppedSends);
  assert.equal(signaler.listenerCount("project-brief-selection"), 0);
  assert.equal(connection.listenerCount("connected"), 0);
  assert.equal(connection.listenerCount("disconnected"), 0);
});

test("disconnected startup announces latest valid metadata only on connection and reports send errors", (t) => {
  t.mock.timers.enable({ apis: ["setInterval", "Date"], now: 0 });
  t.mock.method(performance, "now", () => Date.now());
  const signaler = new FakeSignaler();
  const connection = Object.assign(new EventEmitter(), { connectionState: ConnectionState.Disconnected });
  const errors: unknown[] = [];
  const rosters: Peer[][] = [];
  const session = startPresence(signaler, connection as unknown as IFluidContainer,
    metadata, (peers) => rosters.push(peers), (error) => errors.push(error));
  session.update(focus(metadata, null));
  session.update(metadata);
  session.update({ ...metadata, token: 2 });
  assert.equal(errors.length, 2);
  t.mock.timers.tick(8_000);
  assert.equal(signaler.sent.length, 0);
  connection.connectionState = ConnectionState.Connected;
  connection.emit("connected");
  assert.deepEqual(signaler.sent[0].payload, { ...metadata, token: 2, selected: null });
  signaler.emit("project-brief-selection", "", false, metadata);
  assert.equal(errors.length, 3);
  assert.equal(rosters.length, 0);
  const rejection = new Error("Signal rejected");
  signaler.submitSignal = () => { throw rejection; };
  t.mock.timers.tick(2_000);
  assert.equal(errors.at(-1), rejection);
  session.stop();
});
