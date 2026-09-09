import test from "node:test";
import assert from "node:assert/strict";
import * as runtimeCore from "../../../../build/dev/javascript/watershed/watershed/runtime_core.mjs";
import * as channel from "../../../../build/dev/javascript/watershed/watershed/channel.mjs";
import { Some } from "../../../../build/dev/javascript/gleam_stdlib/gleam/option.mjs";
import { toList } from "../../../../build/dev/javascript/watershed/gleam.mjs";
import * as mv from "../../../../build/dev/javascript/watershed/watershed/mv_register_kernel.mjs";
import * as replica from "../../../../build/dev/javascript/lattice_core/lattice_core/replica_id.mjs";
import * as json from "../../../../build/dev/javascript/gleam_json/gleam/json.mjs";
import * as gCounterKernel from "../../../../build/dev/javascript/watershed/watershed/g_counter_kernel.mjs";
import * as gCounter from "../../../../build/dev/javascript/lattice_counters/lattice_counters/g_counter.mjs";

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

// Mirrors the G-counter path in ../demo.js: build the surveyed baseline, load
// it per client under that client's own replica id, race two increments, and
// re-deliver one. Grow-only means the join keeps each replica's high-water
// mark, so both increments survive and the duplicate changes nothing.
test("G-counter inspection tallies race and survive a duplicate", () => {
  let base = gCounter.new$(replica.new$("survey-baseline"));
  for (const id of ["a", "b"]) {
    const seed = gCounter.new$(replica.new$(`client-${id}`));
    base = gCounter.merge(base, gCounter.increment(seed, 9));
  }
  const summary = json.to_string(gCounter.to_json(base));

  let a = gCounterKernel.from_summary(summary, replica.new$("client-a"))[0];
  let b = gCounterKernel.from_summary(summary, replica.new$("client-b"))[0];
  assert.equal(gCounterKernel.value(a), 18);
  assert.equal(gCounterKernel.value(b), 18);

  const [nextA, , opA] = gCounterKernel.increment(a, 7)[0];
  const [nextB, , opB] = gCounterKernel.increment(b, 3)[0];
  // Optimistic locally, before either has sequenced.
  assert.equal(gCounterKernel.value(nextA), 25);

  a = gCounterKernel.ack_local(nextA, opA)[0];
  b = gCounterKernel.ack_local(nextB, opB)[0];
  [a] = gCounterKernel.apply_remote(a, opB);
  [b] = gCounterKernel.apply_remote(b, opA);
  assert.equal(gCounterKernel.value(a), 28);
  assert.equal(gCounterKernel.value(b), 28);

  // The replay button: the same op again is absorbed by the merge.
  [a] = gCounterKernel.apply_remote(a, opB);
  [b] = gCounterKernel.apply_remote(b, opB);
  assert.equal(gCounterKernel.value(a), 28);
  assert.equal(gCounterKernel.value(b), 28);

  // A decrement is not expressible: the kernel refuses it outright.
  assert.ok(!gCounterKernel.increment(a, -1).isOk());
});
