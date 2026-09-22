import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { compareDirectories, requiredCases, validateCases } from "./generate.mjs";

const schemaValidationCheckIds = [
  "matching-view",
  "string-root-mismatch",
  "required-stored-optional-view",
  "optional-stored-required-view",
  "field-cardinality-mismatch",
  "field-type-mismatch",
  "added-object-field",
  "removed-object-field",
  "allowed-types-reordered",
  "allowed-types-duplicated",
  "allowed-types-widened",
  "empty-allowed-types",
  "unused-definition",
  "common-node-mismatch",
  "metadata-tolerance",
  "recursive-matching-view",
  "recursive-node-mismatch",
  "valid-profile-root",
  "absent-required-root",
  "absent-optional-root",
  "absent-note",
  "present-note",
  "null-marker",
  "null-note",
  "required-field-absence",
  "wrong-nested-type",
  "missing-nested-field",
  "unknown-field",
  "unicode-and-empty-keys",
  "minimum-finite-number",
  "maximum-finite-number",
];

function cases() {
  return requiredCases.map(([id]) => JSON.parse(readFileSync(
    new URL(`../../test/fixtures/shared_tree/cases/${id}.json`, import.meta.url), "utf8",
  )));
}

test("corpus validation requires every named case and nonempty observations", () => {
  assert.equal(requiredCases.length, 22);
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

test("schema validation requires independently replayable paired evidence", () => {
  const corpus = cases();
  const schemaCase = corpus.find((item) => item.id === "schema-validation");
  assert(schemaCase, "schema-validation case is required");
  assert.deepEqual(schemaCase.input.checks.map(({ id }) => id), schemaValidationCheckIds);
  assert.deepEqual(schemaCase.expected.observations.map(({ id }) => id), schemaValidationCheckIds);
  assert.deepEqual(schemaCase.raw.schemas.map(({ id }) => id), schemaValidationCheckIds);
  assert.deepEqual(schemaCase.raw.reports.map(({ id }) => id), schemaValidationCheckIds);
  assert.doesNotThrow(() => validateCases(corpus));

  for (const mutate of [
    (value) => { delete value.input.checks[0].stored; },
    (value) => { value.input.checks[0].stored = "{"; },
    (value) => { delete value.input.checks[0].view; },
    (value) => { delete value.input.checks.find(({ operation }) => operation === "field").parentType; },
    (value) => { delete value.input.checks.find(({ operation }) => operation === "field").field; },
    (value) => { value.input.checks[0].operation = "unknown"; },
    (value) => { value.input.checks[1].id = value.input.checks[0].id; },
    (value) => {
      const index = value.input.checks.findIndex(({ id }) => id === "metadata-tolerance");
      value.input.checks.splice(index, 1);
      value.expected.observations.splice(index, 1);
      value.raw.schemas.splice(index, 1);
      value.raw.reports.splice(index, 1);
    },
    (value) => { value.expected.observations.reverse(); },
    (value) => { value.expected.observations[0].accepted = "yes"; },
    (value) => { value.raw.schemas.pop(); },
    (value) => { value.raw.schemas[0].stored.version = 1; },
    (value) => { value.raw.reports[1].report.canView = true; },
    (value) => { delete value.raw.reports[0].report; },
  ]) {
    const changed = cases();
    mutate(changed.find((item) => item.id === "schema-validation"));
    assert.throws(() => validateCases(changed), /schema-validation/);
  }
});

test("schema validation refuses malformed tagged values", () => {
  for (const mutate of [
    (value) => { value.kind = "unknown"; },
    (value) => { value.kind = "number"; value.value = "1"; },
    (value) => { value.kind = "null"; value.value = null; },
    (value) => { value.kind = "object"; value.type = ""; value.fields = []; },
    (value) => { value.kind = "object"; value.type = "Example"; value.fields = [["field"]]; },
  ]) {
    const corpus = cases();
    const schemaCase = corpus.find((item) => item.id === "schema-validation");
    assert(schemaCase, "schema-validation case is required");
    const root = schemaCase.input.checks.find((item) =>
      item.operation === "root" && item.value !== null);
    assert(root, "schema-validation requires a present root value");
    mutate(root.value);
    assert.throws(() => validateCases(corpus), /schema-validation/);
  }
});

test("forest corpus requires replayable inputs and paired observations", () => {
  const corpus = cases();
  const fixture = corpus.find((item) => item.id === "forest-delta");
  assert(fixture, "forest-delta case is required");
  assert.equal(fixture.domain, "forest");
  assert(fixture.input.scenarios.length > 0);
  assert.equal(fixture.expected.observations.length, fixture.input.scenarios.length);
  assert.doesNotThrow(() => validateCases(corpus));

  for (const mutate of [
    (value) => { delete value.input.scenarios[0].schema; },
    (value) => { value.input.scenarios.pop(); },
    (value) => { value.input.scenarios[1].id = value.input.scenarios[0].id; },
    (value) => { delete value.input.scenarios[0].root; },
    (value) => { value.input.scenarios[0].root = { kind: "unknown" }; },
    (value) => { value.input.scenarios[0].actions[0].op = "unknown"; },
    (value) => {
      value.input.scenarios
        .flatMap((scenario) => scenario.actions)
        .find((item) => item.op === "apply").delta.build[0].id.revision = "not-a-stable-id";
    },
    (value) => {
      const action = value.input.scenarios
        .flatMap((scenario) => scenario.actions)
        .find((item) => item.op === "apply" && item.delta.fields.length > 0);
      action.delta.fields.push(action.delta.fields[0]);
    },
    (value) => { value.raw.scenarios.pop(); },
    (value) => { value.raw.scenarios[0].actions.pop(); },
    (value) => { value.raw.scenarios[0].actions[0].forest = {}; },
    (value) => {
      value.raw.scenarios
        .flatMap((scenario) => scenario.actions)
        .find((item) => item.delta).delta = {};
    },
    (value) => {
      value.raw.scenarios
        .flatMap((scenario) => scenario.actions)
        .find((item) => item.postFailureState).postFailureState = {};
    },
    (value) => { value.expected.observations.reverse(); },
    (value) => { value.expected.observations[0].checkpoints.pop(); },
  ]) {
    const changed = structuredClone(corpus);
    mutate(changed.find((item) => item.id === "forest-delta"));
    assert.throws(() => validateCases(changed), /forest-delta/);
  }
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
