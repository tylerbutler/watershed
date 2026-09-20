import assert from "node:assert/strict";
import test from "node:test";
import {
  expectOk,
  jsonOt,
  resultError,
  sluice,
  watershed,
  websiteRuntime,
} from "./generated-runtime.ts";

test("bootstraps the atlas counter core", () => {
  const core = expectOk(
    websiteRuntime.counter_core(
      "demo-client-a",
      "sandbags-counter",
      120,
    ),
    "counter bootstrap failed",
  );
  assert.equal(
    expectOk(
      websiteRuntime.counter_value(core, "sandbags-counter"),
      "counter value lookup failed",
    ),
    120,
  );

  const change = expectOk(
    websiteRuntime.counter_increment(core, "sandbags-counter", 5),
    "counter increment failed",
  );
  const pending = websiteRuntime.counter_pending(
    change.core,
    "sandbags-counter",
  );
  assert.deepEqual(
    { count: pending.count, delta: pending.delta },
    { count: 1, delta: 5 },
  );
  assert.equal(
    expectOk(
      websiteRuntime.counter_value(change.core, "sandbags-counter"),
      "optimistic counter value lookup failed",
    ),
    125,
  );

  const delivered = expectOk(
    websiteRuntime.deliver_counter(
      change.core,
      "demo-client-a",
      1,
      change.write,
    ),
    "counter delivery failed",
  );
  assert.equal(
    expectOk(
      websiteRuntime.counter_value(delivered, "sandbags-counter"),
      "settled counter value lookup failed",
    ),
    125,
  );
  const settled = websiteRuntime.counter_pending(
    delivered,
    "sandbags-counter",
  );
  assert.deepEqual(
    { count: settled.count, delta: settled.delta },
    { count: 0, delta: 0 },
  );
});

test("converts JSON-OT values", () => {
  const value = expectOk(
    websiteRuntime.json_ot_parse(
      '{"site":"Mill Race","crew":["Ada","Ben"],"stage":24}',
    ),
    "JSON-OT parse failed",
  );
  assert.equal(
    websiteRuntime.json_ot_stringify(value),
    '{"crew":["Ada","Ben"],"site":"Mill Race","stage":24}',
  );
  assert.equal(
    resultError(websiteRuntime.json_ot_parse("{")),
    "invalid JSON",
  );
});

test("constructs JSON-OT path keys and integers", () => {
  const key = websiteRuntime.json_ot_key("gauge");
  const index = websiteRuntime.json_ot_index(2);
  const integer = websiteRuntime.json_ot_integer(-1);
  const nonInteger = new jsonOt.NFloat(1.5);

  assert.equal(
    expectOk(websiteRuntime.json_ot_key_value(key), "path key decode failed"),
    "gauge",
  );
  assert.equal(
    expectOk(
      websiteRuntime.json_ot_index_value(index),
      "path index decode failed",
    ),
    2,
  );
  assert.equal(
    expectOk(
      websiteRuntime.json_ot_integer_value(integer),
      "integer decode failed",
    ),
    -1,
  );
  assert.equal(
    resultError(websiteRuntime.json_ot_key_value(index)),
    "JSON-OT path is not an object key",
  );
  assert.equal(
    resultError(websiteRuntime.json_ot_index_value(key)),
    "JSON-OT path is not an array index",
  );
  assert.equal(
    resultError(websiteRuntime.json_ot_integer_value(nonInteger)),
    "JSON-OT number is not an integer",
  );
});

test("creates and decodes register OR maps", () => {
  const rig = sluice.start("default", "website-runtime-register");
  const document = sluice.connect(rig, "a");
  sluice.settle(rig);
  const orMap = expectOk(
    websiteRuntime.create_register_or_map(document),
    "register OR-map creation failed",
  );
  watershed.or_map_set(orMap, "note-1", "ship week went smoothly");

  const entries = expectOk(
    websiteRuntime.register_entries(orMap),
    "register OR-map decode failed",
  ).toArray();
  assert.equal(entries.length, 1);
  const entry = websiteRuntime.read_register_entry(entries[0]);
  assert.deepEqual(
    { key: entry.key, value: entry.value },
    { key: "note-1", value: "ship week went smoothly" },
  );
});

test("creates and decodes tally OR maps", () => {
  const rig = sluice.start("default", "website-runtime-tally");
  const document = sluice.connect(rig, "a");
  sluice.settle(rig);
  const orMap = expectOk(
    websiteRuntime.create_tally_or_map(document),
    "tally OR-map creation failed",
  );
  watershed.or_map_increment(orMap, "note-1", 2);

  const entries = expectOk(
    websiteRuntime.tally_entries(orMap),
    "tally OR-map decode failed",
  ).toArray();
  assert.equal(entries.length, 1);
  const entry = websiteRuntime.read_tally_entry(entries[0]);
  assert.deepEqual(
    { key: entry.key, value: entry.value },
    { key: "note-1", value: 2 },
  );
});

test("rejects wrong OR-map entry modes", () => {
  const rig = sluice.start("default", "website-runtime-wrong-mode");
  const document = sluice.connect(rig, "a");
  sluice.settle(rig);

  const tally = expectOk(
    websiteRuntime.create_tally_or_map(document),
    "tally OR-map creation failed",
  );
  watershed.or_map_increment(tally, "votes", 1);
  assert.equal(
    resultError(websiteRuntime.register_entries(tally)),
    "register OR-map contains tally value at key: votes",
  );

  const register = expectOk(
    websiteRuntime.create_register_or_map(document),
    "register OR-map creation failed",
  );
  watershed.or_map_set(register, "notes", "ready");
  assert.equal(
    resultError(websiteRuntime.tally_entries(register)),
    "tally OR-map contains register value at key: notes",
  );
});
