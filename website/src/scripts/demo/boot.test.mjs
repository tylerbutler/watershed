import test from "node:test";
import assert from "node:assert/strict";
import * as runtimeCore from "../../../../build/dev/javascript/watershed/watershed/runtime_core.mjs";
import * as channel from "../../../../build/dev/javascript/watershed/watershed/channel.mjs";
import { Some } from "../../../../build/dev/javascript/gleam_stdlib/gleam/option.mjs";
import { toList } from "../../../../build/dev/javascript/watershed/gleam.mjs";

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
