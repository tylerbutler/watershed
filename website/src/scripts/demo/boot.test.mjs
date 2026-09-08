import test from "node:test";
import assert from "node:assert/strict";
import * as runtimeCore from "../../../../build/dev/javascript/watershed/watershed/runtime_core.mjs";
import * as channel from "../../../../build/dev/javascript/watershed/watershed/channel.mjs";
import { Some } from "../../../../build/dev/javascript/gleam_stdlib/gleam/option.mjs";
import { toList } from "../../../../build/dev/javascript/watershed/gleam.mjs";
import * as mv from "../../../../build/dev/javascript/watershed/watershed/mv_register_kernel.mjs";
import * as replica from "../../../../build/dev/javascript/lattice_core/lattice_core/replica_id.mjs";
import * as json from "../../../../build/dev/javascript/gleam_json/gleam/json.mjs";

test("MV revision slate loads a baseline under independent writers", () => {
  const [baseline] = mv.p2p_set(mv.new$(replica.new$("survey")), "Survey datum");
  const summary = json.to_string(mv.summary(baseline));
  let a = mv.from_summary(summary, replica.new$("a"))[0];
  let b = mv.from_summary(summary, replica.new$("b"))[0];
  assert.deepEqual(mv.values(a).toArray(), ["Survey datum"]);
  const [nextA, , writeA, idA] = mv.set(a, "raise crest");
  const [nextB, , writeB, idB] = mv.set(b, "arm pump");
  a = mv.ack_local_with_message_id(nextA, writeA, idA)[0];
  b = mv.ack_local_with_message_id(nextB, writeB, idB)[0];
  [a] = mv.apply_remote(a, writeB);
  [b] = mv.apply_remote(b, writeA);
  assert.deepEqual(mv.values(a).toArray(), ["arm pump", "raise crest"]);
  assert.deepEqual(mv.values(b).toArray(), ["arm pump", "raise crest"]);
  const [pending, , resolved, id] = mv.set(a, "raise crest + arm pump");
  a = mv.ack_local_with_message_id(pending, resolved, id)[0];
  [b] = mv.apply_remote(b, resolved);
  [b] = mv.apply_remote(b, writeA);
  assert.deepEqual(mv.values(b).toArray(), ["raise crest + arm pump"]);
});

// Regression: compiled-record arity drift fails silently — a Summary built
// with too few arguments carries `undefined` fields and only throws deep
// inside bootstrap, which is how the homepage demo once shipped broken.
// Mirrors bootstrapCounterCore() in ../demo.js.
test("demo counter core boots from the baseline summary", () => {
  const summary = new runtimeCore.Summary(
    0,
    toList([["sandbags-counter", new channel.CounterSnapshot(120)]]),
    toList([]),
  );
  const connected = {
    client_id: "demo-client-a",
    initial_clients: toList([]),
    initial_messages: toList([]),
    checkpoint_sequence_number: new Some(0),
  };
  const booted = runtimeCore.bootstrap(connected, new Some(summary));
  assert.ok(booted.isOk(), "bootstrap returned an error");
  assert.ok(
    booted[0] instanceof runtimeCore.Complete,
    "bootstrap requested catch-up unexpectedly",
  );
});
