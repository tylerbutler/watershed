import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { compareDirectories, requiredCases, validateCases } from "./generate.mjs";

function cases() {
  return requiredCases.map(([id]) => JSON.parse(readFileSync(
    new URL(`../../test/fixtures/shared_tree/cases/${id}.json`, import.meta.url), "utf8",
  )));
}

test("corpus validation requires every named case and nonempty observations", () => {
  assert.equal(requiredCases.length, 20);
  assert.doesNotThrow(() => validateCases(cases()));
  assert.throws(() => validateCases([]), /empty|missing/i);
  assert.throws(() => validateCases(cases().slice(1)), /schema-profile/);
  const empty = cases();
  empty[0].expected.observations = [];
  assert.throws(() => validateCases(empty), /schema-profile.*observations/);
  const wrong = cases();
  wrong[0].reference.version = "3.0.0";
  assert.throws(() => validateCases(wrong), /schema-profile.*reference/);
  const duplicate = cases();
  duplicate.push(duplicate[0]);
  assert.throws(() => validateCases(duplicate), /duplicate/i);
});

test("corpus validation refuses placeholder observations and incomplete domain evidence", () => {
  const nullObservations = cases();
  nullObservations[0].expected.observations = [null];
  assert.throws(() => validateCases(nullObservations), /observations/);
  const noInput = cases();
  noInput[0].input = {};
  assert.throws(() => validateCases(noInput), /empty input/);
  const missingOrder = cases();
  missingOrder.find((item) => item.id === "same-field-both-orders").input.schedules.pop();
  assert.throws(() => validateCases(missingOrder), /1-then-0/);
  const missingWire = cases();
  delete missingWire.find((item) => item.id === "summary-tail").raw.messages;
  assert.throws(() => validateCases(missingWire), /wire or snapshot/);
  const missingAlgebra = cases();
  delete missingAlgebra.find((item) => item.id === "field-compose-invert-rebase").raw.encoded;
  assert.throws(() => validateCases(missingAlgebra), /algebra/);
});

test("ID corpus requires replayable restoration and complete cluster and precision traces", () => {
  for (const mutate of [
    (value) => { delete value.input.operations.restoration.ongoing.serialized; },
    (value) => { delete value.input.operations.restoration.summary.serialized; },
    (value) => { delete value.input.traces.growth; },
    (value) => { value.input.traces.uuidCarry.steps = []; },
    (value) => { delete value.input.traces.safeIntegers; },
    (value) => {
      delete value.input.traces.growth.steps.find((step) => step.op === "restore").serialized;
    },
    (value) => {
      delete value.input.traces.growth.steps.find((step) => step.op === "restore").session;
    },
    (value) => {
      value.expected.observations.find((item) => item.stage === "cluster-growth-and-pending").value.pop();
    },
    (value) => {
      value.expected.observations.find((item) => item.stage === "creation-ranges").value = [];
    },
    (value) => {
      delete value.expected.observations.find((item) => item.stage === "serialization").value.withSession;
    },
  ]) {
    const corpus = cases();
    mutate(corpus.find((value) => value.id === "id-ranges"));
    assert.throws(() => validateCases(corpus), /id-ranges/);
  }
});

test("artifact comparison rejects changed content, missing files, and extra files", async (t) => {
  const root = await mkdtemp(join(tmpdir(), "watershed-tree-compare-"));
  t.after(() => rm(root, { recursive: true, force: true }));
  const first = join(root, "first");
  const second = join(root, "second");
  for (const directory of [first, second]) {
    await mkdir(join(directory, "cases"), { recursive: true });
    await writeFile(join(directory, "cases/a.json"), '{"observation":1}\n');
  }
  await compareDirectories(first, second);
  await writeFile(join(second, "cases/a.json"), '{"observation":2}\n');
  await assert.rejects(compareDirectories(first, second), /cases\/a.json/);
  await rm(join(second, "cases/a.json"));
  await assert.rejects(compareDirectories(first, second), /files|missing/i);
  await writeFile(join(second, "cases/a.json"), '{"observation":1}\n');
  await writeFile(join(second, "unexpected.json"), "{}");
  await assert.rejects(compareDirectories(first, second), /files|unexpected/i);
});

test("source-only deterministic entropy preserves distinct UUIDs across reproducible runs", () => {
  const program = `import { randomUUID } from "node:crypto";
    import { freezePerformanceClock } from ${JSON.stringify(new URL("./determinism.mjs", import.meta.url).href)};
    const liveClockBeforeFreeze = performance.now() > 0;
    freezePerformanceClock();
    console.log(JSON.stringify({ids:[randomUUID(),randomUUID()],now:Date.now(),date:new Date().getTime(),performance:performance.now(),liveClockBeforeFreeze}));`;
  function run() {
    return JSON.parse(execFileSync(process.execPath, [
      "--import", new URL("./determinism.mjs", import.meta.url).href,
      "--input-type=module", "-e", program,
    ], {
      encoding: "utf8",
      env: { ...process.env, WATERSHED_ORACLE_DETERMINISTIC: "1" },
      stdio: ["ignore", "pipe", "pipe"],
    }));
  }
  const first = run();
  assert.deepEqual(first, run());
  assert.notEqual(first.ids[0], first.ids[1]);
  assert.match(first.ids[0], /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
  assert.equal(first.now, 1_700_000_000_000);
  assert.equal(first.date, first.now);
  assert.equal(first.performance, 0);
  assert.equal(first.liveClockBeforeFreeze, true);
});

test("deterministic entropy refuses an unmarked process", () => {
  assert.throws(() => execFileSync(process.execPath, [
    "--import", new URL("./determinism.mjs", import.meta.url).href,
    "-e", "",
  ], {
    env: { ...process.env, WATERSHED_ORACLE_DETERMINISTIC: "0" },
    stdio: ["ignore", "pipe", "pipe"],
  }), /restricted to the isolated development oracle/);
});
