import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { copyFile, mkdir, mkdtemp, readdir, readFile, rename, rm, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { reference, runSource, validateCapture } from "./source.mjs";

const directory = dirname(fileURLToPath(import.meta.url));
const fixtures = resolve(directory, "../../test/fixtures/shared_tree");

export const requiredCases = [
  ["schema-profile", "schema"],
  ["schema-validation", "schema"],
  ["bootstrap-map-handles", "container"],
  ["independent-fields", "tree"],
  ["same-field-both-orders", "tree"],
  ["optional-set-clear", "tree"],
  ["null-and-absence", "tree"],
  ["nested-independent", "tree"],
  ["parent-child-both-orders", "tree"],
  ["detached-child-edit", "tree"],
  ["multiple-pending", "history"],
  ["batched-commits", "runtime"],
  ["reconnect-before-ack", "history"],
  ["summary-tail", "summary"],
  ["summary-writer-matrix", "summary"],
  ["id-ranges", "ids"],
  ["field-compose-invert-rebase", "field"],
  ["modular-nested-algebra", "modular"],
  ["history-window", "history"],
  ["unicode-and-numbers", "values"],
  ["invalid-profile", "invalid"],
];

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

const identity = { package: "@fluidframework/tree", version: reference.version, commit: reference.commit };
const object = (value) => value !== null && typeof value === "object" && !Array.isArray(value);
const schedules = {
  "independent-fields": ["concurrent"],
  "same-field-both-orders": ["0-then-1", "1-then-0"],
  "optional-set-clear": ["set-then-clear", "clear-then-set", "absent-clear-and-readd"],
  "null-and-absence": ["required-null-and-optional-absence"],
  "nested-independent": ["concurrent"],
  "parent-child-both-orders": ["0-then-1", "1-then-0"],
  "detached-child-edit": ["retained-reference", "delayed-attached-peer-edit"],
  "multiple-pending": ["remote-between-local-flushes"],
  "history-window": ["stale-peer-and-minimum-advance"],
  "unicode-and-numbers": ["unicode-and-finite-doubles"],
};
const observations = {
  "bootstrap-map-handles": ["valid-bootstrap", "missing-tree-handle", "wrong-tree-handle-kind"],
  "batched-commits": ["local-after-batch", "peer-after-delivery"],
  "reconnect-before-ack": ["server-accepted-before-ack", "never-submitted-before-reconnect"],
  "summary-tail": ["summary-captured", "replayed-through-publication", "later-edit-after-reload"],
  "summary-writer-matrix": ["upstream-reader-loaded-summary", "upstream-reader-reload-after-edit"],
  "id-ranges": ["before-finalization", "after-finalization", "remote-normalization", "restoration",
    "document-unique", "precision-limits", "creation-ranges", "serialization",
    "cluster-growth-and-pending", "uuid-carry", "safe-integer-offsets"],
  "field-compose-invert-rebase": ["compose", "invert", "rebase", "simultaneous-swap",
    "simultaneous-swap-direct-application-refusal", "simultaneous-swap-algebra-mapping", "replace-revisions"],
  "modular-nested-algebra": ["compose", "invert", "rebase", "replace-revisions", "prune", "refreshers"],
};
const nonemptyArray = (value) => Array.isArray(value) && value.length > 0;
const summary = (value) => object(value) && value.type === 1 && object(value.tree);

function validateSchemaString(value, label) {
  assert(typeof value === "string" && value.length > 0, `schema-validation: missing ${label}`);
  let schema;
  try {
    schema = JSON.parse(value);
  } catch {
    assert.fail(`schema-validation: malformed ${label}`);
  }
  assert(object(schema) && schema.version === 2 && object(schema.nodes) && object(schema.root),
    `schema-validation: incomplete ${label}`);
  return schema;
}

function validateTaggedValue(value) {
  assert(object(value) && typeof value.kind === "string", "schema-validation: malformed value");
  if (value.kind === "null") {
    assert.deepEqual(Object.keys(value), ["kind"], "schema-validation: malformed null value");
  } else if (value.kind === "string") {
    assert(typeof value.value === "string", "schema-validation: malformed string value");
  } else if (value.kind === "number") {
    assert(typeof value.value === "number" && Number.isFinite(value.value),
      "schema-validation: malformed number value");
  } else if (value.kind === "boolean") {
    assert(typeof value.value === "boolean", "schema-validation: malformed boolean value");
  } else {
    assert.equal(value.kind, "object", "schema-validation: unknown value kind");
    assert(typeof value.type === "string" && value.type.length > 0 && Array.isArray(value.fields),
      "schema-validation: malformed object value");
    for (const entry of value.fields) {
      assert(Array.isArray(entry) && entry.length === 2 && typeof entry[0] === "string",
        "schema-validation: malformed object field");
      validateTaggedValue(entry[1]);
    }
  }
}

function validateSchemaCase(value) {
  const checks = value.input.checks;
  const observed = value.expected.observations;
  const schemas = value.raw.schemas;
  const reports = value.raw.reports;
  assert(nonemptyArray(checks), "schema-validation: checks must be nonempty");
  assert(Array.isArray(observed) && Array.isArray(schemas) && Array.isArray(reports),
    "schema-validation: missing paired evidence");
  assert.deepEqual(checks.map((check) => check.id), schemaValidationCheckIds,
    "schema-validation: required check IDs");
  assert.deepEqual(observed.map((observation) => observation.id), schemaValidationCheckIds,
    "schema-validation: observation order");
  assert.deepEqual(schemas.map((schema) => schema.id), schemaValidationCheckIds,
    "schema-validation: raw schema order");
  assert.deepEqual(reports.map((report) => report.id), schemaValidationCheckIds,
    "schema-validation: raw report order");
  for (let index = 0; index < checks.length; index += 1) {
    const check = checks[index];
    const observation = observed[index];
    const schema = schemas[index];
    const report = reports[index];
    assert(object(check) && typeof check.id === "string", "schema-validation: malformed check");
    const stored = validateSchemaString(check.stored, `${check.id}.stored`);
    assert(object(observation) && observation.id === check.id
      && typeof observation.accepted === "boolean", `schema-validation: malformed observation ${check.id}`);
    assert(object(schema) && schema.id === check.id && object(schema.stored),
      `schema-validation: missing raw schema ${check.id}`);
    assert.deepEqual(schema.stored, stored, `schema-validation: raw stored schema ${check.id}`);
    assert(object(report) && report.id === check.id && Object.hasOwn(report, "report"),
      `schema-validation: missing raw report ${check.id}`);
    if (check.operation === "canView") {
      const view = validateSchemaString(check.view, `${check.id}.view`);
      assert(object(schema.view), `schema-validation: missing raw view ${check.id}`);
      assert.deepEqual(schema.view, view, `schema-validation: raw view schema ${check.id}`);
      assert(object(report.report) && report.report.canView === observation.accepted,
        `schema-validation: raw compatibility report ${check.id}`);
    } else {
      assert(check.operation === "root" || check.operation === "field",
        `schema-validation: unknown operation ${check.id}`);
      assert.equal(report.report === null, observation.accepted,
        `schema-validation: raw validation report ${check.id}`);
      assert(Object.hasOwn(check, "value"), `schema-validation: missing value ${check.id}`);
      if (check.value !== null) validateTaggedValue(check.value);
      if (check.operation === "field") {
        assert(typeof check.parentType === "string" && check.parentType.length > 0,
          `schema-validation: missing parentType ${check.id}`);
        assert(typeof check.field === "string",
          `schema-validation: missing field ${check.id}`);
      }
    }
  }
}

export function validateCases(cases) {
  assert(Array.isArray(cases) && cases.length > 0, "The corpus is empty");
  const ids = new Set();
  for (const value of cases) {
    assert(object(value), "Invalid corpus case");
    assert(!ids.has(value.id), `Duplicate case: ${value.id}`);
    ids.add(value.id);
    assert.equal(value.formatVersion, 1, `${value.id}: formatVersion`);
    assert.deepEqual(value.reference, identity, `${value.id}: reference identity`);
    assert(object(value.input), `${value.id}: input must be an object`);
    assert(object(value.expected), `${value.id}: expected must be an object`);
    assert(Array.isArray(value.expected.observations) && value.expected.observations.length > 0,
      `${value.id}: expected.observations must be nonempty`);
    assert(value.expected.observations.every((item) => object(item) && Object.keys(item).length > 0),
      `${value.id}: observations must be nonempty objects`);
    assert(object(value.raw) && Object.keys(value.raw).length > 0, `${value.id}: missing raw evidence`);
    assert(Object.keys(value.input).length > 0, `${value.id}: empty input`);
    for (const label of observations[value.id] ?? []) {
      assert(value.expected.observations.some((item) =>
        (item.label ?? item.checkpoint ?? item.operation ?? item.stage) === label),
        `${value.id}: missing observation ${label}`);
    }
    for (const label of schedules[value.id] ?? []) {
      assert(nonemptyArray(value.input.schedules), `${value.id}: missing input schedules`);
      const input = value.input.schedules.find((item) => item.label === label);
      assert(input && summary(input.initial?.summary)
        && input.initial.compressors?.length === 2 && input.initial.sessions?.length === 2
        && nonemptyArray(input.initial.initializationMessages) && nonemptyArray(input.actions),
      `${value.id}: incomplete input schedule ${label}`);
      const observation = value.expected.observations.find((item) => item.label === label);
      assert(observation && observation.checkpoints?.length >= 2
        && observation.checkpoints.some((item) => item.label === "reloaded"),
      `${value.id}: incomplete checkpoints ${label}`);
    }
    if (schedules[value.id]) {
      assert(value.raw.schedules?.length === value.input.schedules.length
        && value.raw.schedules.every((item) => nonemptyArray(item.messages) && summary(item.summary)
          && typeof item.compressor === "string"), `${value.id}: missing raw schedule evidence`);
    }
    if (value.input.service === "LocalDeltaConnectionServer") {
      const input = value.input.decoderInput ?? value.input.replayInput ?? value.input.upstreamWriterInput;
      const snapshot = input?.initialSnapshot ?? input?.snapshotAtS ?? input?.snapshot;
      assert(object(input) && object(snapshot?.tree) && Object.keys(snapshot?.blobs ?? {}).length > 0
        && nonemptyArray(value.raw.messages) && object(value.raw.snapshot?.tree)
        && Object.keys(value.raw.snapshot?.blobs ?? {}).length > 0,
      `${value.id}: missing container wire or snapshot evidence`);
      if (value.id === "bootstrap-map-handles") {
        assert(nonemptyArray(input.bootstrapMessages), `${value.id}: missing SharedMap operations`);
      } else if (value.id === "batched-commits") {
        assert(nonemptyArray(input.groupedWireMessages), `${value.id}: missing grouped operations`);
      } else if (value.id === "reconnect-before-ack") {
        for (const name of ["acceptedBeforeAck", "neverSubmitted"]) {
          assert(input[name]?.pendingLocalState?.encoding === "utf8"
            && typeof input[name].pendingLocalState.content === "string"
            && input[name].pendingLocalState.content.length > 0, `${value.id}: missing ${name} pending state`);
        }
      } else {
        assert(nonemptyArray(input.laterTailMessages), `${value.id}: missing later tail`);
        if (value.id === "summary-tail") {
          assert(input.publicationSequenceNumber > input.summaryReferenceSequenceNumber
            && nonemptyArray(input.summaryToPublicationMessages), `${value.id}: missing S-to-P interval`);
        }
      }
    }
    if (value.id === "schema-profile") {
      assert(summary(value.input.summary) && summary(value.raw.summary)
        && object(value.expected.observations[0].compatibility), `${value.id}: missing schema evidence`);
    }
    if (value.id === "schema-validation") validateSchemaCase(value);
    if (value.domain === "field" || value.domain === "modular") {
      assert(object(value.input.changes) && Object.keys(value.input.changes).length > 0
        && object(value.raw.encoded) && Object.keys(value.raw.encoded).length > 0,
      `${value.id}: missing algebra inputs or encoded outputs`);
    }
    if (value.id === "id-ranges") {
      assert(object(value.input.sessions) && typeof value.input.sessions.summaryRestoration === "string"
        && nonemptyArray(value.input.schedule)
        && object(value.raw.serialized) && value.raw.ranges !== undefined,
      `${value.id}: missing compressor inputs or serialized state`);
      const restoration = value.input.operations?.restoration;
      assert(typeof restoration?.ongoing?.serialized === "string"
        && typeof restoration?.summary?.serialized === "string",
      `${value.id}: missing restoration bytes in input`);
      const serialized = value.expected.observations.find((item) => item.stage === "serialization")?.value;
      assert(typeof serialized?.withSession === "string" && typeof serialized?.summary === "string",
        `${value.id}: missing serialized output comparison`);
      assert(nonemptyArray(value.expected.observations.find((item) => item.stage === "creation-ranges")?.value),
        `${value.id}: missing creation range comparison`);
      for (const [name, stage] of [
        ["growth", "cluster-growth-and-pending"],
        ["uuidCarry", "uuid-carry"],
        ["safeIntegers", "safe-integer-offsets"],
      ]) {
        const trace = value.input.traces?.[name];
        const observed = value.expected.observations.find((item) => item.stage === stage)?.value;
        assert(nonemptyArray(trace?.sessions) && nonemptyArray(trace?.steps)
          && Array.isArray(observed) && observed.length === trace.steps.length,
        `${value.id}: incomplete ${name} trace`);
        for (const step of trace.steps) {
          if (step.op === "restore") {
            assert(typeof step.serialized === "string" && typeof step.session === "string",
              `${value.id}: incomplete ${name} restoration input`);
          }
        }
      }
    }
    if (value.id === "invalid-profile") {
      assert(nonemptyArray(value.input.mutations) && nonemptyArray(value.raw.mutations),
        `${value.id}: missing negative inputs`);
      for (const mutation of ["excluded-schema", "message-version", "unknown-required-change", "missing-forest-blob"]) {
        assert(value.input.mutations.some((item) => item.mutation === mutation),
          `${value.id}: missing ${mutation}`);
      }
      assert(value.input.mutations.some((item) => item.operation === "finalizeCreationRange"),
        `${value.id}: missing malformed allocation`);
      for (const mutation of ["message-version", "unknown-required-change"]) {
        assert(value.expected.observations.some((item) =>
          item.mutation === mutation && item.refused === true && item.statePreserved === true),
        `${value.id}: missing atomic refusal observation for ${mutation}`);
      }
      assert(value.expected.observations.some((item) =>
        item.operation === "malformed-allocation-refusal" && item.statePreserved === true),
      `${value.id}: missing allocation state-preservation observation`);
    }
  }
  for (const [id, domain] of requiredCases) {
    const value = cases.find((item) => item.id === id);
    assert(value !== undefined, `Missing case: ${id}`);
    assert.equal(value.domain, domain, `${id}: domain`);
    if (["container", "runtime", "summary"].includes(domain) || id === "reconnect-before-ack") {
      assert.equal(value.input.service, "LocalDeltaConnectionServer", `${id}: missing full-container producer`);
    }
  }
  assert.equal(cases.length, requiredCases.length, "Unexpected corpus cases");
}

async function files(directory, prefix = "") {
  const paths = [];
  for (const entry of await readdir(join(directory, prefix), { withFileTypes: true })) {
    const path = prefix === "" ? entry.name : `${prefix}/${entry.name}`;
    if (entry.isDirectory()) paths.push(...await files(directory, path));
    else {
      assert(entry.isFile(), `Unexpected non-file artifact: ${path}`);
      paths.push(path);
    }
  }
  return paths.sort();
}

export async function compareDirectories(generated, committed) {
  const expected = await files(generated);
  assert.deepEqual(await files(committed), expected, "Corpus files differ");
  for (const path of expected) {
    const [first, second] = await Promise.all([
      readFile(join(generated, path)), readFile(join(committed, path)),
    ]);
    assert(first.equals(second), `Corpus artifact differs: ${path}`);
  }
}

function observedFieldKinds(value, kinds = new Set()) {
  if (Array.isArray(value)) {
    for (const item of value) observedFieldKinds(item, kinds);
  } else if (object(value)) {
    if (typeof value.fieldKind === "string") kinds.add(value.fieldKind);
    if (value.type === 2 && typeof value.content === "string") {
      observedFieldKinds(JSON.parse(value.content), kinds);
    }
    for (const item of Object.values(value)) observedFieldKinds(item, kinds);
  }
  return [...kinds].sort();
}

function summaryMetadata(summary, path = "", result = {}) {
  if (summary.type === 1) {
    for (const [name, child] of Object.entries(summary.tree)) {
      summaryMetadata(child, `${path}/${name}`, result);
    }
  } else if (summary.type === 2 && path.endsWith("/.metadata")) {
    result[path] = JSON.parse(summary.content);
  }
  return result;
}

function storedSchemaFromSnapshot(snapshot) {
  const schemas = [];
  function visit(tree) {
    for (const [name, id] of Object.entries(tree.blobs)) {
      if (name === "SchemaString") {
        assert(typeof snapshot.blobs[id] === "string", "Missing schema blob bytes");
        schemas.push(JSON.parse(Buffer.from(snapshot.blobs[id], "base64").toString("utf8")));
      }
    }
    for (const child of Object.values(tree.trees)) visit(child);
  }
  visit(snapshot.tree);
  assert.equal(schemas.length, 1, "Expected one SharedTree schema in container");
  return schemas[0];
}

function messageInventory(cases) {
  const types = new Set();
  const treeVersions = new Set();
  const fieldKinds = new Set();
  function visit(value) {
    if (Array.isArray(value)) {
      for (const item of value) visit(item);
    } else if (object(value)) {
      if (typeof value.type === "string" && "contents" in value) types.add(value.type);
      if ("originatorId" in value && "changeset" in value) treeVersions.add(value.version);
      if (typeof value.fieldKind === "string") fieldKinds.add(value.fieldKind);
      assert(!("compression" in value), "Unexpected compressed message in fixed profile");
      for (const [key, item] of Object.entries(value)) {
        if (key === "contents" && typeof item === "string" && /^[{[]/.test(item)) {
          visit(JSON.parse(item));
        } else visit(item);
      }
    }
  }
  for (const value of cases) {
    if (value.id === "invalid-profile") continue;
    if (value.raw.messages) visit(value.raw.messages);
    for (const schedule of value.raw.schedules ?? []) visit(schedule.messages);
  }
  assert.deepEqual([...treeVersions], [7], "Unexpected tree message format");
  assert(!types.has("chunkedOp"), "Unexpected chunked runtime message");
  return {
    types: [...types].sort(),
    treeVersions: [...treeVersions],
    fieldKinds: [...fieldKinds].sort(),
  };
}

export async function writeCorpus(output, cases, smoke) {
  validateCases(cases);
  validateCapture(smoke);
  const profile = JSON.parse(await readFile(join(fixtures, "profile.json"), "utf8"));
  assert.deepEqual(profile.reference, identity, "Profile reference differs");
  assert.deepEqual(profile.codecTree, smoke.codecTree, "Profile codecs differ");
  assert.deepEqual(profile.compressorFormat, smoke.compressorFormat, "Profile compressor format differs");
  assert.equal(profile.container.oldestSupportedClient, smoke.minVersionForCollab);
  const sourceSchema = JSON.parse(cases.find((item) => item.id === "schema-profile")
    .raw.summary.tree.indexes.tree.Schema.tree.SchemaString.content);
  for (const value of cases.filter((item) => item.input.service === "LocalDeltaConnectionServer")) {
    assert.deepEqual(storedSchemaFromSnapshot(value.raw.snapshot), sourceSchema,
      `${value.id}: source and container stored schemas differ`);
  }
  await mkdir(join(output, "cases"), { recursive: true });
  const manifest = {
    formatVersion: 1,
    reference: identity,
    provenance: {
      source: reference.commit,
      seed: "watershed-tree-corpus-v1",
      epochMilliseconds: 1_700_000_000_000,
      containerPerformanceMilliseconds: 0,
      identityNormalization: "none",
      scope: "development-only upstream oracle; real-service preflight is separate",
    },
    inventory: {
      codecTree: smoke.codecTree,
      compressorFormat: smoke.compressorFormat,
      observedFieldKinds: observedFieldKinds(cases.filter((item) => item.id !== "invalid-profile")),
      messages: messageInventory(cases),
      treeSummaryMetadata: summaryMetadata(smoke.summary),
      serviceSummaryPaths: profile.container.summaryPaths,
      documentSchema: profile.container.documentSchema,
      gcMetadataVersion: profile.container.gcFeature,
    },
    nativeSemanticRunners: {
      javascript: ["id-ranges", "schema-validation"],
      erlang: ["id-ranges", "schema-validation"],
    },
    cases: requiredCases.map(([id, domain]) => ({ id, domain, file: `cases/${id}.json` })),
  };
  for (const { id, file } of manifest.cases) {
    await writeFile(join(output, file), `${JSON.stringify(cases.find((item) => item.id === id), null, 2)}\n`);
  }
  await writeFile(join(output, "manifest.json"), `${JSON.stringify(manifest, null, 2)}\n`);
  // The independently generated real-service profile is preserved, not regenerated from a mock service.
  await copyFile(join(fixtures, "profile.json"), join(output, "profile.json"));
}

export async function generate({ check = false } = {}) {
  await mkdir(join(directory, ".output"), { recursive: true });
  const temporary = await mkdtemp(join(directory, ".output/corpus-"));
  try {
    const source = join(temporary, "source");
    const container = join(temporary, "container");
    const artifacts = join(temporary, "artifacts");
    await runSource(source, { corpus: true });
    execFileSync(process.execPath, [
      "--import", pathToFileURL(join(directory, "determinism.mjs")).href,
      "--input-type=module", "-e",
      `const {captureContainers}=await import(${JSON.stringify(pathToFileURL(join(directory, "container-corpus.mjs")).href)});
       const {freezePerformanceClock}=await import(${JSON.stringify(pathToFileURL(join(directory, "determinism.mjs")).href)});
       freezePerformanceClock(); await captureContainers(process.argv[1]);`,
      container,
    ], {
      cwd: directory,
      env: { ...process.env, WATERSHED_ORACLE_DETERMINISTIC: "1" },
      stdio: "inherit",
      timeout: 90_000,
    });
    const read = async (path) => JSON.parse(await readFile(path, "utf8"));
    const cases = [
      ...await read(join(source, "tree-cases.json")),
      ...await read(join(source, "algebra-cases.json")),
      ...await read(join(container, "container-cases.json")),
    ];
    const malformed = cases.find((item) => item.id === "id-ranges")?.raw.malformedAllocation;
    assert(object(malformed), "Missing malformed-allocation oracle evidence");
    const invalid = cases.find((item) => item.id === "invalid-profile");
    invalid.input.mutations.push(malformed.input);
    assert(object(malformed.expected.observation), "Missing malformed-allocation observation");
    invalid.expected.observations.push(malformed.expected.observation);
    invalid.raw.mutations.push(malformed.raw);
    await writeCorpus(artifacts, cases, await read(join(source, "source-smoke.json")));
    if (check) {
      await compareDirectories(artifacts, fixtures);
    } else {
      const allowed = new Set(["profile.json", "manifest.json",
        ...requiredCases.map(([id]) => `cases/${id}.json`)]);
      for (const path of await files(fixtures)) {
        assert(allowed.has(path), `Refusing to replace unexpected fixture file: ${path}`);
      }
      await mkdir(join(fixtures, "cases"), { recursive: true });
      for (const [id] of requiredCases) {
        const path = `cases/${id}.json`;
        await rename(join(artifacts, path), join(fixtures, path));
      }
      await rename(join(artifacts, "manifest.json"), join(fixtures, "manifest.json"));
    }
    console.log(`${check ? "Verified" : "Generated"} ${requiredCases.length} upstream SharedTree cases`);
  } finally {
    await rm(temporary, { recursive: true, force: true });
  }
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  const args = process.argv.slice(2);
  if (args.length > 1 || (args.length === 1 && args[0] !== "--check")) {
    throw new Error("Usage: node generate.mjs [--check]");
  }
  generate({ check: args[0] === "--check" }).catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
}
