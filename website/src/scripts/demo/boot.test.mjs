import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import * as runtimeCore from "../../../../build/dev/javascript/watershed/watershed/runtime_core.mjs";
import * as channel from "../../../../build/dev/javascript/watershed/watershed/channel.mjs";
import { Some } from "../../../../build/dev/javascript/gleam_stdlib/gleam/option.mjs";
import { toList } from "../../../../build/dev/javascript/watershed/gleam.mjs";
import * as mv from "../../../../build/dev/javascript/watershed/watershed/mv_register_kernel.mjs";
import * as replica from "../../../../build/dev/javascript/lattice_core/lattice_core/replica_id.mjs";
import * as json from "../../../../build/dev/javascript/gleam_json/gleam/json.mjs";
import * as gCounterKernel from "../../../../build/dev/javascript/watershed/watershed/g_counter_kernel.mjs";
import * as lwwRegisterKernel from "../../../../build/dev/javascript/watershed/watershed/lww_register_kernel.mjs";
import * as gCounter from "../../../../build/dev/javascript/lattice_counters/lattice_counters/g_counter.mjs";
import { lwwRaceTimestamp } from "./lww-register.js";
import * as orMap from "../../../../build/dev/javascript/watershed/watershed/or_map_kernel.mjs";
import * as sharedMap from "../../../../build/dev/javascript/watershed/watershed/map_kernel.mjs";
import * as lwwMapKernel from "../../../../build/dev/javascript/watershed/watershed/lww_map_kernel.mjs";

const ok = (result) => {
  assert.ok(result.isOk(), `Kernel returned ${result[0]?.constructor.name}`);
  return result[0];
};

test("ORMap member deltas union where SharedMap arrays replace in the same stream", () => {
  const key = "inspection-brief";
  const sets = ["a", "b", "c"].map((id) =>
    orMap.new$(replica.new$(id), new orMap.OrSetMode()));
  const maps = sets.map(() => sharedMap.new$());
  const operations = ["draft", "reviewed"].map((member, author) => {
    const [state, , operation, messageId] = ok(orMap.add_member(sets[author], key, member));
    sets[author] = state;
    const [map, , write] = sharedMap.set(
      maps[author], key, json.array(toList([member]), json.string),
    );
    maps[author] = map;
    return { author, operation, messageId, write };
  });
  assert.deepEqual(orMap.sequenced_entries(sets[0]).toArray(), []);
  for (const { author, operation, messageId, write } of operations) {
    for (let target = 0; target < 3; target++) {
      sets[target] = target === author
        ? ok(orMap.ack_local_with_message_id(sets[target], operation, messageId))
        : ok(orMap.apply_remote(sets[target], operation))[0];
      maps[target] = target === author
        ? ok(sharedMap.ack_local(maps[target], write))
        : sharedMap.apply_remote(maps[target], write)[0];
    }
  }
  for (let target = 0; target < 3; target++) {
    assert.deepEqual(ok(orMap.get(sets[target], key))[0].toArray(), ["draft", "reviewed"]);
    assert.equal(json.to_string(sharedMap.get(maps[target], key)[0]), '["reviewed"]');
    assert.equal(sets[target].pending.toArray().length, 0);
  }
  const beforeDuplicate = json.to_string(orMap.summary(sets[0]));
  const [duplicateState, duplicateEvents, duplicate, duplicateId] =
    ok(orMap.add_member(sets[0], key, "draft"));
  assert.equal(duplicateEvents.toArray().length, 0);
  assert.equal(orMap.ack_local_with_message_id(duplicateState, duplicate, duplicateId + 1).isOk(), false);
  sets[0] = ok(orMap.ack_local_with_message_id(duplicateState, duplicate, duplicateId));
  for (let target = 1; target < 3; target++) {
    sets[target] = ok(orMap.apply_remote(sets[target], duplicate))[0];
  }
  assert.notEqual(json.to_string(orMap.summary(sets[0])), beforeDuplicate);
  assert.deepEqual(ok(orMap.get(sets[0], key))[0].toArray(), ["draft", "reviewed"]);

  const firstAdd = operations[0].operation;
  function edit(mutate, ...args) {
    const [state, , operation, messageId] = ok(mutate(sets[0], key, ...args));
    sets[0] = ok(orMap.ack_local_with_message_id(state, operation, messageId));
    for (let i = 1; i < 3; i++) sets[i] = ok(orMap.apply_remote(sets[i], operation))[0];
  }
  edit(orMap.remove);
  assert.equal(orMap.get(sets[0], key).isOk(), false);
  edit(orMap.add_member, "handoff");
  for (let i = 0; i < 3; i++) {
    sets[i] = ok(orMap.apply_remote(sets[i], firstAdd))[0];
    assert.deepEqual(ok(orMap.get(sets[i], key))[0].toArray(), ["handoff"]);
  }
  edit(orMap.remove_member, "handoff");
  edit(orMap.remove_member, "absent");
  assert.deepEqual(ok(orMap.get(sets[0], key))[0].toArray(), []);
  const [next, events, noop, id] = ok(orMap.remove_member(sets[0], "missing", "absent"));
  assert.equal(events.toArray().length, 0);
  sets[0] = ok(orMap.ack_local_with_message_id(next, noop, id));
  assert.equal(orMap.get(sets[0], "missing").isOk(), false);
});

test("LWWMap uses timestamps while SharedMap uses stream order", () => {
  const newer = lwwMapKernel.p2p_set(
    lwwMapKernel.new$(replica.new$("a")), "gate-mode", "open", 1_001,
  );
  const older = lwwMapKernel.p2p_set(
    lwwMapKernel.new$(replica.new$("b")), "gate-mode", "closed", 1_000,
  );
  assert.ok(newer.isOk());
  assert.ok(older.isOk());
  const writes = [
    [newer[0][2], new sharedMap.Set("gate-mode", json.string("open"))],
    [older[0][2], new sharedMap.Set("gate-mode", json.string("closed"))],
  ];
  for (const order of [writes, [...writes].reverse()]) {
    let lww = lwwMapKernel.new$(replica.new$("observer"));
    let shared = sharedMap.new$();
    for (const [fragment, operation] of order) {
      const applied = lwwMapKernel.apply_remote(lww, fragment);
      assert.ok(applied.isOk());
      [lww] = applied[0];
      [shared] = sharedMap.apply_remote(shared, operation);
    }
    assert.equal(lwwMapKernel.get(lww, "gate-mode")[0], "open");
    assert.equal(
      json.to_string(sharedMap.get(shared, "gate-mode")[0]),
      json.to_string(order.at(-1)[1].value),
    );
    const before = json.to_string(lwwMapKernel.summary(lww));
    const replayed = lwwMapKernel.apply_remote(lww, older[0][2]);
    assert.ok(replayed.isOk());
    assert.equal(json.to_string(lwwMapKernel.summary(replayed[0][0])), before);
  }
});

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

// Keep the shared demo connected to the compiled LWW-register kernel rather
// than a JavaScript copy of its merge rule.
test("shared demo wires the compiled LWW register and map kernels", () => {
  const source = readFileSync(
    new URL("../demo.js", import.meta.url),
    "utf8",
  );
  assert.match(source, /lww_register_kernel\.mjs/);
  assert.match(source, /localLwwSet/);
  assert.match(source, /ddsId === "lww-register"/);
  assert.match(source, /lww_map_kernel\.mjs/);
  assert.match(source, /ddsId === "lww-map"/);
  const component = readFileSync(
    new URL("../../components/Demo.astro", import.meta.url),
    "utf8",
  );
  assert.match(component, /writer-tie/);
});

test("LWW register field notes converge by timestamp and author", () => {
  const seeded = lwwRegisterKernel.p2p_set(
    lwwRegisterKernel.new$(replica.new$("survey-lww")),
    "Survey datum",
    100,
  );
  assert.ok(seeded.isOk(), "baseline write failed");
  const summary = json.to_string(lwwRegisterKernel.summary(seeded[0][0]));

  const loadedA = lwwRegisterKernel.from_summary(
    summary,
    replica.new$("client-a"),
  );
  const loadedB = lwwRegisterKernel.from_summary(
    summary,
    replica.new$("client-b"),
  );
  assert.ok(loadedA.isOk(), "client A baseline failed to load");
  assert.ok(loadedB.isOk(), "client B baseline failed to load");
  let a = loadedA[0];
  let b = loadedB[0];

  const writeA = lwwRegisterKernel.set(a, "raise crest", 1_000);
  const writeB = lwwRegisterKernel.set(b, "arm pump", 1_000);
  assert.ok(writeA.isOk(), "client A write failed");
  assert.ok(writeB.isOk(), "client B write failed");
  const [nextA, , operationA, messageA] = writeA[0];
  const [nextB, , operationB, messageB] = writeB[0];
  const acknowledgedA = lwwRegisterKernel.ack_local_with_message_id(
    nextA,
    operationA,
    messageA,
  );
  const acknowledgedB = lwwRegisterKernel.ack_local_with_message_id(
    nextB,
    operationB,
    messageB,
  );
  assert.ok(acknowledgedA.isOk(), "client A acknowledgement failed");
  assert.ok(acknowledgedB.isOk(), "client B acknowledgement failed");
  a = acknowledgedA[0];
  b = acknowledgedB[0];

  const remoteB = lwwRegisterKernel.apply_remote(a, operationB);
  const remoteA = lwwRegisterKernel.apply_remote(b, operationA);
  assert.ok(remoteB.isOk(), "client B operation failed on client A");
  assert.ok(remoteA.isOk(), "client A operation failed on client B");
  [a] = remoteB[0];
  [b] = remoteA[0];
  assert.equal(lwwRegisterKernel.value(a), "arm pump");
  assert.equal(lwwRegisterKernel.value(b), "arm pump");

  const beforeReplay = json.to_string(lwwRegisterKernel.summary(a));
  const replayed = lwwRegisterKernel.apply_remote(a, operationB);
  assert.ok(replayed.isOk(), "duplicate delivery failed");
  [a] = replayed[0];
  assert.equal(json.to_string(lwwRegisterKernel.summary(a)), beforeReplay);

  const sameValue = lwwRegisterKernel.set(a, "arm pump", 1_000);
  assert.ok(sameValue.isOk(), "same-value write failed");
  const [pending, events, operation, messageId] = sameValue[0];
  assert.equal(events.toArray().length, 0);
  const acked = lwwRegisterKernel.ack_local_with_message_id(
    pending,
    operation,
    messageId,
  );
  assert.ok(acked.isOk(), "same-value acknowledgement failed");
  assert.notEqual(
    json.to_string(lwwRegisterKernel.summary(acked[0])),
    beforeReplay,
  );
});

test("LWW race keeps equal timestamps after one replica advances", () => {
  const seeded = lwwRegisterKernel.p2p_set(
    lwwRegisterKernel.new$(replica.new$("survey-lww")),
    "Survey datum",
    100,
  );
  assert.ok(seeded.isOk(), "baseline write failed");
  const summary = json.to_string(lwwRegisterKernel.summary(seeded[0][0]));
  const loadedA = lwwRegisterKernel.from_summary(
    summary,
    replica.new$("client-a"),
  );
  const loadedB = lwwRegisterKernel.from_summary(
    summary,
    replica.new$("client-b"),
  );
  assert.ok(loadedA.isOk(), "client A baseline failed to load");
  assert.ok(loadedB.isOk(), "client B baseline failed to load");

  const advancedA = lwwRegisterKernel.set(loadedA[0], "earlier note", 2_000);
  assert.ok(advancedA.isOk(), "client A advance failed");

  const timestamp = lwwRaceTimestamp(2_000, [advancedA[0][0], loadedB[0]]);
  const raceA = lwwRegisterKernel.set(advancedA[0][0], "raise crest", timestamp);
  const raceB = lwwRegisterKernel.set(loadedB[0], "arm pump", timestamp);
  assert.ok(raceA.isOk(), "client A race write failed");
  assert.ok(raceB.isOk(), "client B race write failed");
  assert.equal(raceA[0][2].timestamp, 2_001);
  assert.equal(raceB[0][2].timestamp, 2_001);
});

test("G-counter inspection tallies race and survive a duplicate", () => {
  let base = gCounter.new$(replica.new$("survey-baseline"));
  for (const id of ["a", "b"]) {
    const seed = gCounter.new$(replica.new$(`client-${id}`));
    base = gCounter.merge(base, ok(gCounter.increment(seed, 9)));
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
