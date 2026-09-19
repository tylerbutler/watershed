import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import * as websiteRuntime from "../../../../tools/website-runtime/build/dev/javascript/website_runtime/website_runtime.mjs";
import * as dict from "../../../../tools/website-runtime/build/dev/javascript/gleam_stdlib/gleam/dict.mjs";
import { toList } from "../../../../tools/website-runtime/build/dev/javascript/watershed/gleam.mjs";
import * as mv from "../../../../tools/website-runtime/build/dev/javascript/watershed/watershed/mv_register_kernel.mjs";
import * as replica from "../../../../tools/website-runtime/build/dev/javascript/lattice_core/lattice_core/replica_id.mjs";
import * as json from "../../../../tools/website-runtime/build/dev/javascript/gleam_json/gleam/json.mjs";
import * as gCounterKernel from "../../../../tools/website-runtime/build/dev/javascript/watershed/watershed/g_counter_kernel.mjs";
import * as lwwRegisterKernel from "../../../../tools/website-runtime/build/dev/javascript/watershed/watershed/lww_register_kernel.mjs";
import * as gCounter from "../../../../tools/website-runtime/build/dev/javascript/lattice_counters/lattice_counters/g_counter.mjs";
import { lwwRaceTimestamp } from "./lww-register.js";
import * as orMap from "../../../../tools/website-runtime/build/dev/javascript/watershed/watershed/or_map_kernel.mjs";
import * as sharedMap from "../../../../tools/website-runtime/build/dev/javascript/watershed/watershed/map_kernel.mjs";
import * as lwwMapKernel from "../../../../tools/website-runtime/build/dev/javascript/watershed/watershed/lww_map_kernel.mjs";
import { expectOk, none, some } from "./gleam-values.ts";

function orMapMembers(state: orMap.OrMapState$, key: string) {
  const value = expectOk(
    orMap.get(state, key),
    "Kernel returned an error",
  );
  assert.ok(value instanceof orMap.SetMembers, "ORMap returned a non-set value");
  return value[0];
}

test("ORMap member deltas union where SharedMap arrays replace in the same stream", () => {
  const key = "inspection-brief";
  const sets = ["a", "b", "c"].map((id) =>
    orMap.new$(replica.new$(id), new orMap.OrSetMode()));
  const maps = sets.map(() => sharedMap.new$());
  const operations = ["draft", "reviewed"].map((member, author) => {
    const [state, , operation, messageId] = expectOk(
      orMap.add_member(sets[author], key, member),
      "Kernel returned an error",
    );
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
        ? expectOk(
            orMap.ack_local_with_message_id(
              sets[target],
              operation,
              messageId,
            ),
            "Kernel returned an error",
          )
        : expectOk(
            orMap.apply_remote(sets[target], operation),
            "Kernel returned an error",
          )[0];
      maps[target] = target === author
        ? expectOk(
            sharedMap.ack_local(maps[target], write),
            "Kernel returned an error",
          )
        : sharedMap.apply_remote(maps[target], write)[0];
    }
  }
  for (let target = 0; target < 3; target++) {
    assert.deepEqual(
      orMapMembers(sets[target], key).toArray(),
      ["draft", "reviewed"],
    );
    assert.equal(
      json.to_string(
        expectOk(
          sharedMap.get(maps[target], key),
          "Kernel returned an error",
        ),
      ),
      '["reviewed"]',
    );
    assert.equal(sets[target].pending.toArray().length, 0);
  }
  const beforeDuplicate = json.to_string(orMap.summary(sets[0]));
  const [duplicateState, duplicateEvents, duplicate, duplicateId] =
    expectOk(
      orMap.add_member(sets[0], key, "draft"),
      "Kernel returned an error",
    );
  assert.equal(duplicateEvents.toArray().length, 0);
  assert.equal(orMap.ack_local_with_message_id(duplicateState, duplicate, duplicateId + 1).isOk(), false);
  sets[0] = expectOk(
    orMap.ack_local_with_message_id(duplicateState, duplicate, duplicateId),
    "Kernel returned an error",
  );
  for (let target = 1; target < 3; target++) {
    sets[target] = expectOk(
      orMap.apply_remote(sets[target], duplicate),
      "Kernel returned an error",
    )[0];
  }
  assert.notEqual(json.to_string(orMap.summary(sets[0])), beforeDuplicate);
  assert.deepEqual(
    orMapMembers(sets[0], key).toArray(),
    ["draft", "reviewed"],
  );

  const firstAdd = operations[0].operation;
  function edit(result: ReturnType<typeof orMap.remove>) {
    const [state, , operation, messageId] = expectOk(
      result,
      "Kernel returned an error",
    );
    sets[0] = expectOk(
      orMap.ack_local_with_message_id(state, operation, messageId),
      "Kernel returned an error",
    );
    for (let i = 1; i < 3; i++) {
      sets[i] = expectOk(
        orMap.apply_remote(sets[i], operation),
        "Kernel returned an error",
      )[0];
    }
  }
  edit(orMap.remove(sets[0], key));
  assert.equal(orMap.get(sets[0], key).isOk(), false);
  edit(orMap.add_member(sets[0], key, "handoff"));
  for (let i = 0; i < 3; i++) {
    sets[i] = expectOk(
      orMap.apply_remote(sets[i], firstAdd),
      "Kernel returned an error",
    )[0];
    assert.deepEqual(
      orMapMembers(sets[i], key).toArray(),
      ["handoff"],
    );
  }
  edit(orMap.remove_member(sets[0], key, "handoff"));
  edit(orMap.remove_member(sets[0], key, "absent"));
  assert.deepEqual(orMapMembers(sets[0], key).toArray(), []);
  const [next, events, noop, id] = expectOk(
    orMap.remove_member(sets[0], "missing", "absent"),
    "Kernel returned an error",
  );
  assert.equal(events.toArray().length, 0);
  sets[0] = expectOk(
    orMap.ack_local_with_message_id(next, noop, id),
    "Kernel returned an error",
  );
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
  const newerValue = expectOk(newer, "newer LWWMap write failed");
  const olderValue = expectOk(older, "older LWWMap write failed");
  const writes: Array<[lwwMapKernel.LwwMapOperation$, sharedMap.Set]> = [
    [newerValue[2], new sharedMap.Set("gate-mode", json.string("open"))],
    [olderValue[2], new sharedMap.Set("gate-mode", json.string("closed"))],
  ];
  for (const order of [writes, [...writes].reverse()]) {
    let lww = lwwMapKernel.new$(replica.new$("observer"));
    let shared = sharedMap.new$();
    for (const [fragment, operation] of order) {
      const applied = lwwMapKernel.apply_remote(lww, fragment);
      assert.ok(applied.isOk());
      [lww] = expectOk(applied, "LWWMap remote apply failed");
      [shared] = sharedMap.apply_remote(shared, operation);
    }
    assert.equal(
      expectOk(
        lwwMapKernel.get(lww, "gate-mode"),
        "LWWMap value lookup failed",
      ),
      "open",
    );
    const lastWrite = order.at(-1);
    assert.ok(lastWrite);
    assert.equal(
      json.to_string(
        expectOk(
          sharedMap.get(shared, "gate-mode"),
          "SharedMap value lookup failed",
        ),
      ),
      json.to_string(lastWrite[1].value),
    );
    const before = json.to_string(lwwMapKernel.summary(lww));
    const replayed = lwwMapKernel.apply_remote(lww, olderValue[2]);
    assert.ok(replayed.isOk());
    assert.equal(
      json.to_string(
        lwwMapKernel.summary(
          expectOk(replayed, "LWWMap duplicate delivery failed")[0],
        ),
      ),
      before,
    );
  }
});

test("MV revision slate loads a baseline under independent writers", () => {
  const [baseline] = mv.p2p_set(mv.new$(replica.new$("survey")), "Survey datum");
  const summary = json.to_string(mv.summary(baseline));
  let a = expectOk(
    mv.from_summary(summary, replica.new$("a")),
    "Kernel returned an error",
  );
  let b = expectOk(
    mv.from_summary(summary, replica.new$("b")),
    "Kernel returned an error",
  );
  assert.deepEqual(mv.values(a).toArray(), ["Survey datum"]);
  const [nextA, , writeA, idA] = mv.set(a, "raise crest");
  const [nextB, , writeB, idB] = mv.set(b, "arm pump");
  a = expectOk(
    mv.ack_local_with_message_id(nextA, writeA, idA),
    "Kernel returned an error",
  );
  b = expectOk(
    mv.ack_local_with_message_id(nextB, writeB, idB),
    "Kernel returned an error",
  );
  [a] = mv.apply_remote(a, writeB);
  [b] = mv.apply_remote(b, writeA);
  assert.deepEqual(mv.values(a).toArray(), ["arm pump", "raise crest"]);
  assert.deepEqual(mv.values(b).toArray(), ["arm pump", "raise crest"]);
  const [pending, , resolved, id] = mv.set(a, "raise crest + arm pump");
  a = expectOk(
    mv.ack_local_with_message_id(pending, resolved, id),
    "Kernel returned an error",
  );
  [b] = mv.apply_remote(b, resolved);
  [b] = mv.apply_remote(b, writeA);
  assert.deepEqual(mv.values(b).toArray(), ["raise crest + arm pump"]);
});

// Regression: the website bridge owns generated record construction so a
// generated constructor change fails in Gleam instead of deep in TypeScript.
test("demo counter core boots from the baseline summary", () => {
  const core = expectOk(
    websiteRuntime.counter_core(
      "demo-client-a",
      "sandbags-counter",
      120,
    ),
    "bootstrap returned an error",
  );
  assert.equal(
    expectOk(
      websiteRuntime.counter_value(core, "sandbags-counter"),
      "counter value lookup failed",
    ),
    120,
  );
});

// Keep the shared demo connected to the compiled LWW-register kernel rather
// than a JavaScript copy of its merge rule.
test("shared demo wires the compiled LWW register and map kernels", () => {
  const source = readFileSync(
    new URL("../demo.ts", import.meta.url),
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
  const seededValue = expectOk(seeded, "baseline write failed");
  const summary = json.to_string(lwwRegisterKernel.summary(seededValue[0]));

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
  let a = expectOk(loadedA, "client A baseline failed to load");
  let b = expectOk(loadedB, "client B baseline failed to load");

  const writeA = lwwRegisterKernel.set(a, "raise crest", 1_000);
  const writeB = lwwRegisterKernel.set(b, "arm pump", 1_000);
  assert.ok(writeA.isOk(), "client A write failed");
  assert.ok(writeB.isOk(), "client B write failed");
  const [nextA, , operationA, messageA] = expectOk(
    writeA,
    "client A write failed",
  );
  const [nextB, , operationB, messageB] = expectOk(
    writeB,
    "client B write failed",
  );
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
  a = expectOk(acknowledgedA, "client A acknowledgement failed");
  b = expectOk(acknowledgedB, "client B acknowledgement failed");

  const remoteB = lwwRegisterKernel.apply_remote(a, operationB);
  const remoteA = lwwRegisterKernel.apply_remote(b, operationA);
  assert.ok(remoteB.isOk(), "client B operation failed on client A");
  assert.ok(remoteA.isOk(), "client A operation failed on client B");
  [a] = expectOk(remoteB, "client B operation failed on client A");
  [b] = expectOk(remoteA, "client A operation failed on client B");
  assert.equal(lwwRegisterKernel.value(a), "arm pump");
  assert.equal(lwwRegisterKernel.value(b), "arm pump");

  const beforeReplay = json.to_string(lwwRegisterKernel.summary(a));
  const replayed = lwwRegisterKernel.apply_remote(a, operationB);
  assert.ok(replayed.isOk(), "duplicate delivery failed");
  [a] = expectOk(replayed, "duplicate delivery failed");
  assert.equal(json.to_string(lwwRegisterKernel.summary(a)), beforeReplay);

  const sameValue = lwwRegisterKernel.set(a, "arm pump", 1_000);
  assert.ok(sameValue.isOk(), "same-value write failed");
  const [pending, events, operation, messageId] = expectOk(
    sameValue,
    "same-value write failed",
  );
  assert.equal(events.toArray().length, 0);
  const acked = lwwRegisterKernel.ack_local_with_message_id(
    pending,
    operation,
    messageId,
  );
  assert.ok(acked.isOk(), "same-value acknowledgement failed");
  assert.notEqual(
    json.to_string(
      lwwRegisterKernel.summary(
        expectOk(acked, "same-value acknowledgement failed"),
      ),
    ),
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
  const seededValue = expectOk(seeded, "baseline write failed");
  const summary = json.to_string(lwwRegisterKernel.summary(seededValue[0]));
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
  const loadedAValue = expectOk(loadedA, "client A baseline failed to load");
  const loadedBValue = expectOk(loadedB, "client B baseline failed to load");

  const advancedA = lwwRegisterKernel.set(
    loadedAValue,
    "earlier note",
    2_000,
  );
  assert.ok(advancedA.isOk(), "client A advance failed");
  const advancedAValue = expectOk(advancedA, "client A advance failed");

  const timestamp = lwwRaceTimestamp(2_000, [advancedAValue[0], loadedBValue]);
  const raceA = lwwRegisterKernel.set(
    advancedAValue[0],
    "raise crest",
    timestamp,
  );
  const raceB = lwwRegisterKernel.set(loadedBValue, "arm pump", timestamp);
  assert.ok(raceA.isOk(), "client A race write failed");
  assert.ok(raceB.isOk(), "client B race write failed");
  assert.equal(
    expectOk(raceA, "client A race write failed")[2].timestamp,
    2_001,
  );
  assert.equal(
    expectOk(raceB, "client B race write failed")[2].timestamp,
    2_001,
  );
});

test("G-counter inspection tallies race and survive a duplicate", () => {
  let base = gCounter.new$(replica.new$("survey-baseline"));
  for (const id of ["a", "b"]) {
    const seed = gCounter.new$(replica.new$(`client-${id}`));
    base = gCounter.merge(
      base,
      expectOk(gCounter.increment(seed, 9), "Kernel returned an error"),
    );
  }
  const summary = json.to_string(gCounter.to_json(base));

  let a = expectOk(
    gCounterKernel.from_summary(summary, replica.new$("client-a")),
    "Kernel returned an error",
  );
  let b = expectOk(
    gCounterKernel.from_summary(summary, replica.new$("client-b")),
    "Kernel returned an error",
  );
  assert.equal(gCounterKernel.value(a), 18);
  assert.equal(gCounterKernel.value(b), 18);

  const [nextA, , opA] = expectOk(
    gCounterKernel.increment(a, 7),
    "Kernel returned an error",
  );
  const [nextB, , opB] = expectOk(
    gCounterKernel.increment(b, 3),
    "Kernel returned an error",
  );
  // Optimistic locally, before either has sequenced.
  assert.equal(gCounterKernel.value(nextA), 25);

  a = expectOk(
    gCounterKernel.ack_local(nextA, opA),
    "Kernel returned an error",
  );
  b = expectOk(
    gCounterKernel.ack_local(nextB, opB),
    "Kernel returned an error",
  );
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
