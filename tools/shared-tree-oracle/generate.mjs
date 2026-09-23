import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { copyFile, mkdir, mkdtemp, readdir, readFile, rename, rm, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { reference, runSource, validateCapture } from "./source.mjs";
import { validateContainerFoundationsCase } from "./container-foundations.mjs";
import { validateSummaryFoundationsCase } from "./summary-foundations.mjs";

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
  ["forest-delta", "forest"],
  ["container-foundations", "container"],
  ["summary-foundations", "summary"],
  ["history-reconciliation", "history"],
  ["tree-codecs", "codec"],
];

const forestScenarioIds = [
  "primitives-and-optional-root",
  "optional-field-set-clear",
  "unicode-field-keys",
  "replacement-retained-child",
  "nested-replacement-old-child",
  "reattach-keeps-identity",
  "detached-range-build",
  "rename-chain-and-self",
  "rename-cycle-refused",
  "duplicate-build-refused",
  "refreshers",
  "destroy-and-revision-metadata",
  "copy-retains-detached",
  "missing-attach-source-refused",
  "missing-global-source-refused",
  "missing-rename-source-refused",
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

const historyScheduleIds = [
  "local-ack",
  "remote-between-pending",
  "same-field-local-first",
  "same-field-remote-first",
  "stale-peer-chain",
  "parent-child-local-first",
  "parent-child-remote-first",
  "optional-clear-and-null",
  "two-inner-commits",
  "non-tree-sequence-gap",
  "window-advance-with-pending",
  "settled-snapshot-tail",
  "accepted-before-ack",
  "never-submitted",
  "resubmit-detached-repair",
  "nonlexical-rollback-order",
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

function validateTaggedValue(value, label = "schema-validation") {
  assert(object(value) && typeof value.kind === "string", `${label}: malformed value`);
  if (value.kind === "null") {
    assert.deepEqual(Object.keys(value), ["kind"], `${label}: malformed null value`);
  } else if (value.kind === "string") {
    assert(typeof value.value === "string", `${label}: malformed string value`);
  } else if (value.kind === "number") {
    assert(typeof value.value === "number" && Number.isFinite(value.value),
      `${label}: malformed number value`);
  } else if (value.kind === "boolean") {
    assert(typeof value.value === "boolean", `${label}: malformed boolean value`);
  } else {
    assert.equal(value.kind, "object", `${label}: unknown value kind`);
    assert(typeof value.type === "string" && value.type.length > 0 && Array.isArray(value.fields),
      `${label}: malformed object value`);
    const fields = new Set();
    for (const entry of value.fields) {
      assert(Array.isArray(entry) && entry.length === 2 && typeof entry[0] === "string",
        `${label}: malformed object field`);
      assert(!fields.has(entry[0]), `${label}: duplicate object field ${entry[0]}`);
      fields.add(entry[0]);
      validateTaggedValue(entry[1], label);
    }
  }
}

function validateForestCase(value) {
  const scenarios = value.input.scenarios;
  const observed = value.expected.observations;
  const raw = value.raw.scenarios;
  assert(nonemptyArray(scenarios) && Array.isArray(observed) && Array.isArray(raw),
    "forest-delta: missing paired evidence");
  assert.deepEqual(scenarios.map(({ id }) => id), forestScenarioIds,
    "forest-delta: required scenario IDs");
  assert.deepEqual(observed.map(({ id }) => id), forestScenarioIds,
    "forest-delta: observation order");
  assert.deepEqual(raw.map(({ id }) => id), forestScenarioIds,
    "forest-delta: raw scenario order");

  function stableId(value, label) {
    assert(typeof value === "string"
      && /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(value),
    `forest-delta: malformed stable ID ${label}`);
  }

  function atom(value, label) {
    assert(object(value) && Object.keys(value).length === 2
      && Object.hasOwn(value, "revision") && Object.hasOwn(value, "localId"),
    `forest-delta: malformed atom ${label}`);
    if (value.revision !== null) stableId(value.revision, `${label}.revision`);
    assert(Number.isSafeInteger(value.localId) && value.localId >= 0,
      `forest-delta: malformed localId ${label}`);
  }

  function fieldMap(value, label) {
    assert(Array.isArray(value), `forest-delta: malformed field map ${label}`);
    const fields = new Set();
    for (const entry of value) {
      assert(Array.isArray(entry) && entry.length === 2 && typeof entry[0] === "string"
        && object(entry[1]) && Array.isArray(entry[1].marks),
      `forest-delta: malformed field entry ${label}`);
      assert(!fields.has(entry[0]), `forest-delta: duplicate field ${entry[0]} in ${label}`);
      fields.add(entry[0]);
      for (const [index, mark] of entry[1].marks.entries()) {
        assert(object(mark) && Number.isSafeInteger(mark.count) && mark.count > 0,
          `forest-delta: malformed mark ${label}[${index}]`);
        assert(mark.attach === null || object(mark.attach),
          `forest-delta: malformed attach ${label}[${index}]`);
        assert(mark.detach === null || object(mark.detach),
          `forest-delta: malformed detach ${label}[${index}]`);
        if (mark.attach !== null) atom(mark.attach, `${label}[${index}].attach`);
        if (mark.detach !== null) atom(mark.detach, `${label}[${index}].detach`);
        fieldMap(mark.fields, `${label}[${index}].fields`);
      }
    }
  }

  function delta(value, label) {
    assert(object(value), `forest-delta: malformed delta ${label}`);
    if (value.latestRevision !== null) stableId(value.latestRevision, `${label}.latestRevision`);
    fieldMap(value.fields, `${label}.fields`);
    for (const collection of ["build", "refreshers"]) {
      assert(Array.isArray(value[collection]), `forest-delta: malformed ${collection} ${label}`);
      for (const [index, item] of value[collection].entries()) {
        assert(object(item) && nonemptyArray(item.trees),
          `forest-delta: malformed ${collection} ${label}[${index}]`);
        atom(item.id, `${label}.${collection}[${index}].id`);
        for (const tree of item.trees) validateTaggedValue(tree, "forest-delta");
      }
    }
    assert(Array.isArray(value.global) && Array.isArray(value.rename)
      && Array.isArray(value.destroy), `forest-delta: incomplete delta ${label}`);
    for (const [index, item] of value.global.entries()) {
      assert(object(item), `forest-delta: malformed global ${label}[${index}]`);
      atom(item.id, `${label}.global[${index}].id`);
      fieldMap(item.fields, `${label}.global[${index}].fields`);
    }
    for (const [index, item] of value.rename.entries()) {
      assert(object(item) && Number.isSafeInteger(item.count) && item.count > 0,
        `forest-delta: malformed rename ${label}[${index}]`);
      atom(item.oldId, `${label}.rename[${index}].oldId`);
      atom(item.newId, `${label}.rename[${index}].newId`);
    }
    for (const [index, item] of value.destroy.entries()) {
      assert(object(item) && Number.isSafeInteger(item.count) && item.count > 0,
        `forest-delta: malformed destroy ${label}[${index}]`);
      atom(item.id, `${label}.destroy[${index}].id`);
    }
  }

  function state(value, label) {
    assert(object(value) && Object.hasOwn(value, "root") && Array.isArray(value.references)
      && Array.isArray(value.detached) && Number.isSafeInteger(value.nextDetachedRootId)
      && value.nextDetachedRootId >= 0, `forest-delta: malformed state ${label}`);
    if (value.root !== null) validateTaggedValue(value.root, "forest-delta");
    const names = new Set();
    for (const reference of value.references) {
      assert(object(reference) && typeof reference.name === "string" && reference.name.length > 0
        && ["attached", "detached", "destroyed", "invalidated-by-copy"].includes(reference.status)
        && Object.hasOwn(reference, "value"), `forest-delta: malformed reference ${label}`);
      assert(!names.has(reference.name), `forest-delta: duplicate reference ${reference.name}`);
      names.add(reference.name);
      if (reference.value !== null) validateTaggedValue(reference.value, "forest-delta");
    }
    const detached = new Set();
    for (const item of value.detached) {
      assert(object(item) && Number.isSafeInteger(item.forestRootId) && item.forestRootId >= 0,
      `forest-delta: malformed detached state ${label}`);
      if (item.latestRelevantRevision !== null) {
        stableId(item.latestRelevantRevision, `${label}.detached.latestRelevantRevision`);
      }
      atom(item.id, `${label}.detached.id`);
      validateTaggedValue(item.value, "forest-delta");
      const key = `${item.id.revision ?? ""}:${item.id.localId}`;
      assert(!detached.has(key), `forest-delta: duplicate detached state ${label}`);
      detached.add(key);
    }
  }

  function rawAtom(value, label) {
    assert(object(value) && (value.major === null || Number.isSafeInteger(value.major))
      && Number.isSafeInteger(value.minor) && value.minor >= 0,
    `forest-delta: malformed raw atom ${label}`);
  }

  function rawFieldMap(value, label) {
    assert(Array.isArray(value), `forest-delta: malformed raw field map ${label}`);
    const fields = new Set();
    for (const entry of value) {
      assert(Array.isArray(entry) && entry.length === 2 && typeof entry[0] === "string"
        && object(entry[1]) && Array.isArray(entry[1].marks),
      `forest-delta: malformed raw field entry ${label}`);
      assert(!fields.has(entry[0]), `forest-delta: duplicate raw field ${entry[0]} in ${label}`);
      fields.add(entry[0]);
      for (const mark of entry[1].marks) {
        assert(object(mark) && Number.isSafeInteger(mark.count) && mark.count > 0
          && Array.isArray(mark.fields), `forest-delta: malformed raw mark ${label}`);
        if (mark.attach !== null) rawAtom(mark.attach, `${label}.attach`);
        if (mark.detach !== null) rawAtom(mark.detach, `${label}.detach`);
        rawFieldMap(mark.fields, `${label}.fields`);
      }
    }
  }

  function rawForest(value, label) {
    assert(object(value) && Array.isArray(value.fields),
      `forest-delta: malformed raw forest ${label}`);
    for (const entry of value.fields) {
      assert(Array.isArray(entry) && entry.length === 2 && typeof entry[0] === "string"
        && Array.isArray(entry[1]), `forest-delta: malformed raw forest field ${label}`);
      for (const tree of entry[1]) validateTaggedValue(tree, "forest-delta");
    }
  }

  function rawIndex(value, label) {
    assert(Array.isArray(value), `forest-delta: malformed raw index ${label}`);
    for (const entry of value) {
      assert(object(entry) && Number.isSafeInteger(entry.root) && entry.root >= 0
        && (entry.latestRelevantRevision === null
          || Number.isSafeInteger(entry.latestRelevantRevision)),
      `forest-delta: malformed raw index entry ${label}`);
      rawAtom(entry.id, `${label}.id`);
    }
  }

  function rawDelta(value, label) {
    assert(object(value) && (value.latestRevision === null
      || Number.isSafeInteger(value.latestRevision)),
    `forest-delta: malformed raw delta ${label}`);
    rawFieldMap(value.fields, `${label}.fields`);
    for (const collection of ["build", "refreshers"]) {
      assert(Array.isArray(value[collection]), `forest-delta: malformed raw ${collection} ${label}`);
      for (const item of value[collection]) {
        assert(object(item) && nonemptyArray(item.trees),
          `forest-delta: malformed raw ${collection} entry ${label}`);
        rawAtom(item.id, `${label}.${collection}.id`);
        for (const tree of item.trees) validateTaggedValue(tree, "forest-delta");
      }
    }
    assert(Array.isArray(value.global) && Array.isArray(value.rename)
      && Array.isArray(value.destroy), `forest-delta: incomplete raw delta ${label}`);
    for (const item of value.global) {
      assert(object(item), `forest-delta: malformed raw global ${label}`);
      rawAtom(item.id, `${label}.global.id`);
      rawFieldMap(item.fields, `${label}.global.fields`);
    }
    for (const item of value.rename) {
      assert(object(item) && Number.isSafeInteger(item.count) && item.count > 0,
        `forest-delta: malformed raw rename ${label}`);
      rawAtom(item.oldId, `${label}.rename.oldId`);
      rawAtom(item.newId, `${label}.rename.newId`);
    }
    for (const item of value.destroy) {
      assert(object(item) && Number.isSafeInteger(item.count) && item.count > 0,
        `forest-delta: malformed raw destroy ${label}`);
      rawAtom(item.id, `${label}.destroy.id`);
    }
  }

  for (let index = 0; index < scenarios.length; index += 1) {
    const scenario = scenarios[index];
    const observation = observed[index];
    const evidence = raw[index];
    assert(object(scenario) && typeof scenario.id === "string",
      "forest-delta: malformed scenario");
    validateSchemaString(scenario.schema, `forest-delta.${scenario.id}.schema`);
    assert(Object.hasOwn(scenario, "root"), `forest-delta: missing initial content ${scenario.id}`);
    if (scenario.root !== null) validateTaggedValue(scenario.root, "forest-delta");
    assert(nonemptyArray(scenario.actions), `forest-delta: missing actions ${scenario.id}`);
    const actionIds = new Set();
    for (const action of scenario.actions) {
      assert(object(action) && typeof action.id === "string" && action.id.length > 0
        && !actionIds.has(action.id), `forest-delta: duplicate or missing action ID ${scenario.id}`);
      actionIds.add(action.id);
      if (action.op === "retain") {
        assert(typeof action.name === "string" && action.name.length > 0
          && Array.isArray(action.path) && action.path.every((part) => typeof part === "string"),
        `forest-delta: malformed retain ${scenario.id}`);
      } else if (action.op === "retainDetached") {
        assert(typeof action.name === "string" && action.name.length > 0,
          `forest-delta: malformed retainDetached ${scenario.id}`);
        atom(action.atom, `${scenario.id}.${action.id}.atom`);
      } else if (action.op === "apply") {
        delta(action.delta, `${scenario.id}.${action.id}`);
      } else {
        assert(action.op === "observe" || action.op === "copy",
          `forest-delta: unknown action ${scenario.id}.${action.id}`);
      }
    }
    assert(object(observation) && observation.id === scenario.id
      && Array.isArray(observation.checkpoints)
      && observation.checkpoints.length === scenario.actions.length,
    `forest-delta: incomplete checkpoints ${scenario.id}`);
    assert(object(evidence) && evidence.id === scenario.id && Array.isArray(evidence.actions)
      && evidence.actions.length === scenario.actions.length,
    `forest-delta: missing raw evidence ${scenario.id}`);
    for (let actionIndex = 0; actionIndex < scenario.actions.length; actionIndex += 1) {
      const action = scenario.actions[actionIndex];
      const checkpoint = observation.checkpoints[actionIndex];
      const rawAction = evidence.actions[actionIndex];
      assert(object(checkpoint) && checkpoint.id === action.id
        && typeof checkpoint.accepted === "boolean",
      `forest-delta: malformed checkpoint ${scenario.id}.${action.id}`);
      assert(object(rawAction) && rawAction.id === action.id && object(rawAction.forest)
        && Array.isArray(rawAction.detachedIndex),
      `forest-delta: incomplete raw action ${scenario.id}.${action.id}`);
      rawForest(rawAction.forest, `${scenario.id}.${action.id}`);
      rawIndex(rawAction.detachedIndex, `${scenario.id}.${action.id}`);
      if (action.op === "apply") {
        rawDelta(rawAction.delta, `${scenario.id}.${action.id}`);
      }
      if (checkpoint.accepted) {
        state(checkpoint.state, `${scenario.id}.${action.id}`);
      } else {
        assert.equal(checkpoint.state, null,
          `forest-delta: rejected checkpoint state ${scenario.id}.${action.id}`);
        assert.equal(actionIndex, scenario.actions.length - 1,
          `forest-delta: refusal must end scenario ${scenario.id}`);
        assert(typeof rawAction.error === "string" && rawAction.error.length > 0
          && object(rawAction.postFailureState),
        `forest-delta: incomplete refusal evidence ${scenario.id}.${action.id}`);
        rawForest(rawAction.postFailureState.forest, `${scenario.id}.${action.id}.postFailure`);
        rawIndex(rawAction.postFailureState.detachedIndex,
          `${scenario.id}.${action.id}.postFailure`);
      }
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

function validateFieldCase(value) {
  const label = value.id;
  const check = (condition, detail) => assert(condition, `${label}: ${detail}`);
  const input = value.input;
  const expanded = input.expanded;
  check(object(expanded), "missing expanded operations");
  check(object(input.revisions), "missing revisions");
  const revisions = Object.values(input.revisions);
  check(revisions.length === 4 && new Set(revisions).size === 4
    && revisions.every(Number.isSafeInteger), "invalid revision identities");
  const revision = (id) => check(revisions.includes(id), "unknown revision");
  const localId = (id) => check(Number.isSafeInteger(id) && id >= 0, "invalid local ID");
  function atom(id) {
    if (Array.isArray(id)) {
      check(id.length === 2, "invalid encoded atom");
      localId(id[0]);
      revision(id[1]);
    } else localId(id);
  }
  function change(data) {
    check(object(data), "missing field change");
    if (data.m !== undefined) {
      check(Array.isArray(data.m), "invalid moves");
      for (const pair of data.m) {
        check(Array.isArray(pair) && pair.length === 2, "invalid move pair");
        pair.forEach(atom);
      }
    }
    if (data.r !== undefined) {
      check(object(data.r) && typeof data.r.e === "boolean", "invalid replacement");
      atom(data.r.d);
      if (data.r.s !== undefined && data.r.s !== null) atom(data.r.s);
    }
    if (data.c !== undefined) {
      check(Array.isArray(data.c), "invalid child changes");
      for (const pair of data.c) {
        check(Array.isArray(pair) && pair.length === 2, "invalid child pair");
        if (pair[0] !== null) atom(pair[0]);
        const fields = pair[1]?.fieldChanges;
        check(Array.isArray(fields) && fields.length === 1 && object(fields[0])
          && fields[0].fieldKey === "watershed-node-id"
          && fields[0].fieldKind === "watershed-node-id"
          && object(fields[0].change), "invalid child identity callback encoding");
        localId(fields[0].change.localId);
        if (fields[0].change.revision !== undefined) revision(fields[0].change.revision);
      }
    }
  }
  function tagged(item) {
    check(object(item), "missing tagged change");
    revision(item.revision);
    change(item.data);
  }
  check(object(input.operations) && object(input.changes), "missing original operations");
  const names = new Set([...Object.keys(input.changes), "compose"]);
  const select = (name) => check(names.has(name), "unknown named change");
  for (const name of ["compose", "invert", "rebase", "replaceRevisions"]) {
    check(object(input.operations[name]), `invalid original ${name}`);
  }
  const operations = input.operations;
  select(operations.compose.left);
  select(operations.compose.right);
  const metadata = operations.compose.revisionMetadata;
  check(object(metadata) && Array.isArray(metadata.revisions)
    && Array.isArray(metadata.rollbackRevisions), "invalid revision metadata");
  metadata.revisions.forEach(revision);
  metadata.rollbackRevisions.forEach(revision);
  revision(metadata.base);
  select(operations.invert.change);
  check(typeof operations.invert.isRollback === "boolean", "invalid rollback flag");
  revision(operations.invert.inverseRevision);
  select(operations.rebase.change);
  select(operations.rebase.over);
  select(operations.replaceRevisions.change);
  check(Array.isArray(operations.replaceRevisions.obsolete), "missing obsolete revisions");
  operations.replaceRevisions.obsolete.forEach(revision);
  revision(operations.replaceRevisions.updated);

  const expected = observations[label].map((operation) => ({ operation }));
  const groups = {
    compose: ["set-set-forward", "set-set-reverse", "set-clear", "clear-set",
      "absent-clear-set", "overlapping-children"],
    invert: ["set-rollback", "set-undo", "clear-rollback", "clear-undo",
      "active-source-noop-rollback", "active-source-noop-undo"],
    rebase: ["authored-child-over-clear", "base-only-child-over-clear", "both-children"],
  };
  for (const [operation, ids] of Object.entries(groups)) {
    check(Array.isArray(expanded[operation]), `missing expanded ${operation}`);
    assert.deepEqual(expanded[operation].map((item) => item.id), ids,
      `${label}: expanded ${operation} coverage`);
    for (const item of expanded[operation]) {
      if (operation === "invert") {
        tagged(item.change);
        check(typeof item.isRollback === "boolean", "invalid expanded rollback flag");
        check(Number.isSafeInteger(item.maxLocalId) && item.maxLocalId >= -1,
          "invalid allocator watermark");
        revision(item.inverseRevision);
      } else {
        tagged(operation === "compose" ? item.first : item.change);
        tagged(operation === "compose" ? item.second : item.over);
        revision(item.outputRevision);
        const callback = item.childCallback;
        check(object(callback), "missing child callback");
        if (operation === "compose" && callback.selector === "constant") {
          check(object(callback.result), "missing constant child result");
          localId(callback.result.localId);
          revision(callback.result.revision);
        } else {
          check(callback.selector === (operation === "compose"
            ? "prefer-first-then-second" : "prefer-change-then-base"), "unknown child callback");
        }
      }
      expected.push({ operation: `${operation}-expanded`, id: item.id });
    }
  }
  check(object(expanded.intoDelta), "missing expanded delta");
  tagged(expanded.intoDelta.change);
  check(expanded.intoDelta.childDelta?.selector === "local-id-count"
    && typeof expanded.intoDelta.childDelta.field === "string", "invalid child delta callback");
  expected.push({ operation: "into-delta-expanded" });
  const replacement = expanded.replaceRevisions;
  check(object(replacement) && replacement.id === "all-atom-positions",
    "missing expanded revision replacement");
  tagged(replacement.change);
  check(Array.isArray(replacement.obsolete), "invalid expanded obsolete revisions");
  replacement.obsolete.forEach(revision);
  revision(replacement.updated);
  revision(replacement.outputRevision);
  expected.push({ operation: "replace-revisions-expanded", id: replacement.id });
  check(Array.isArray(expanded.invalidMappings), "missing invalid mapping inputs");
  assert.deepEqual(expanded.invalidMappings.map((item) => item.id),
    ["duplicate-move-source", "duplicate-move-destination", "duplicate-child-register"],
    `${label}: invalid mapping coverage`);
  for (const item of expanded.invalidMappings) {
    const data = item.change;
    check(object(data) && Array.isArray(data.moves) && Array.isArray(data.childChanges),
      "invalid refusal change");
    if (item.id === "duplicate-child-register") {
      check(data.childChanges.length === 2, "missing duplicate child entries");
      assert.deepEqual(data.childChanges[0][0], data.childChanges[1][0],
        `${label}: refusal requires duplicate child registers`);
    } else {
      check(data.moves.length === 2 && data.moves.every((pair) =>
        Array.isArray(pair) && pair.length === 2 && pair.every(object)),
      "missing duplicate move entries");
      const index = item.id === "duplicate-move-source" ? 0 : 1;
      assert.deepEqual(data.moves[0][index], data.moves[1][index],
        `${label}: refusal requires duplicate move identities`);
    }
  }
  check(object(expanded.changes), "missing expanded source changes");
  for (const [name, data] of Object.entries(expanded.changes)) {
    tagged(data);
    check(object(value.raw.changes[name]) && object(value.raw.encoded[name]),
      `missing paired source change ${name}`);
    assert.deepEqual(value.raw.encoded[name], data.data, `${label}: source encoding ${name}`);
  }
  assert.deepEqual(value.expected.observations.map(({ operation, id }) =>
    id === undefined ? { operation } : { operation, id }), expected,
  `${label}: complete ordered observations`);
  for (const item of value.expected.observations.slice(7)) {
    if (item.operation === "into-delta-expanded") {
      check(object(item.delta) && Array.isArray(item.delta.global)
        && Array.isArray(item.delta.rename), "missing full field delta");
    } else {
      change(item.encoded);
      if (item.operation === "invert-expanded") {
        check(Number.isSafeInteger(item.allocator?.before)
          && Number.isSafeInteger(item.allocator?.after), "missing allocator observations");
      } else if (item.operation !== "replace-revisions-expanded") {
        check(Array.isArray(item.callbacks), "missing child callback observations");
      }
    }
  }
}

function validateModularCase(value) {
  const label = "modular-nested-algebra";
  const check = (condition, detail) => assert(condition, `${label}: ${detail}`);
  const exact = (value, keys, location) => {
    check(object(value), `${location} must be an object`);
    assert.deepEqual(Object.keys(value).sort(), [...keys].sort(), `${label}: ${location} fields`);
  };
  const stable = (id) => typeof id === "string"
    && /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(id);
  const safe = (value) => Number.isSafeInteger(value) && value >= 0;
  const atom = (value) => {
    exact(value, ["revision", "localId"], "atom");
    check(value.revision === null || stable(value.revision), "atom revision");
    check(safe(value.localId), "atom local ID");
  };
  const register = (value) => { if (value !== "active") atom(value); };
  const entries = (value, key, item, name) => {
    check(Array.isArray(value), `${name} must be an array`);
    const seen = new Set();
    for (const entry of value) {
      check(Array.isArray(entry) && entry.length === 2, `${name} entry`);
      key(entry[0]);
      const identity = JSON.stringify(entry[0]);
      check(!seen.has(identity), `${name} duplicate key`);
      seen.add(identity);
      item(entry[1]);
    }
  };
  const text = (value) => check(typeof value === "string", "field name");
  function fields(value) {
    entries(value, text, (field) => {
      check(object(field), "field change");
      if (field.kind === "Generic") {
        exact(field, ["kind", "children"], "Generic field");
        entries(field.children, (index) => check(index === 0, "unsupported Generic index"), atom, "Generic children");
      } else {
        exact(field, ["kind", "moves", "children", "replacement"], "register field");
        check(["Value", "Optional"].includes(field.kind), "unsupported field kind");
        entries(field.moves, atom, atom, "moves");
        entries(field.children, register, atom, "children");
        if (field.replacement !== null) {
          exact(field.replacement, ["wasEmpty", "source", "detach"], "replacement");
          check(typeof field.replacement.wasEmpty === "boolean", "replacement presence");
          if (field.replacement.source !== null) register(field.replacement.source);
          atom(field.replacement.detach);
        }
      }
    }, "fields");
  }
  function builds(value) {
    check(Array.isArray(value), "build list");
    for (const build of value) {
      exact(build, ["id", "trees"], "build");
      atom(build.id);
      check(nonemptyArray(build.trees) && safe(build.id.localId + build.trees.length - 1), "build trees");
      for (const tree of build.trees) validateTaggedValue(tree, label);
    }
  }
  function deltaFields(value) {
    entries(value, text, (field) => {
      exact(field, ["marks"], "delta field");
      check(Array.isArray(field.marks), "delta marks");
      for (const mark of field.marks) {
        exact(mark, ["count", "attach", "detach", "fields"], "delta mark");
        check(safe(mark.count) && mark.count > 0, "delta mark count");
        if (mark.attach !== null) atom(mark.attach);
        if (mark.detach !== null) atom(mark.detach);
        deltaFields(mark.fields);
      }
    }, "delta fields");
  }
  function delta(value) {
    exact(value, ["latestRevision", "fields", "build", "refreshers", "global", "rename", "destroy"], "delta");
    check(value.latestRevision === null || stable(value.latestRevision), "delta revision");
    deltaFields(value.fields);
    builds(value.build); builds(value.refreshers);
    check(Array.isArray(value.global) && Array.isArray(value.rename) && Array.isArray(value.destroy), "delta sections");
    for (const entry of value.global) {
      exact(entry, ["id", "fields"], "global change");
      atom(entry.id); deltaFields(entry.fields);
    }
    for (const entry of value.rename) {
      exact(entry, ["oldId", "newId", "count"], "delta rename");
      atom(entry.oldId); atom(entry.newId);
      check(safe(entry.count) && entry.count > 0, "delta rename count");
    }
    for (const entry of value.destroy) {
      exact(entry, ["id", "count"], "delta destroy");
      atom(entry.id);
      check(safe(entry.count) && entry.count > 0, "delta destroy count");
    }
  }
  function structure(value) {
    exact(value, ["maxLocalId", "revisions", "fields", "nodes", "parents", "aliases",
      "builds", "destroys", "refreshers"], "change");
    check(Number.isSafeInteger(value.maxLocalId) && value.maxLocalId >= -1, "allocation watermark");
    check(Array.isArray(value.revisions), "revision metadata");
    for (const info of value.revisions) {
      exact(info, ["revision", "rollbackOf"], "revision metadata");
      check(stable(info.revision) && (info.rollbackOf === null || stable(info.rollbackOf)), "revision identity");
    }
    fields(value.fields);
    entries(value.nodes, atom, (node) => {
      exact(node, ["fields"], "node"); fields(node.fields);
    }, "nodes");
    entries(value.parents, atom, (parent) => {
      exact(parent, ["parent", "field"], "parent");
      if (parent.parent !== null) atom(parent.parent);
      text(parent.field);
    }, "parents");
    entries(value.aliases, atom, atom, "aliases");
    builds(value.builds); builds(value.refreshers);
    check(Array.isArray(value.destroys), "destroys");
    for (const destroy of value.destroys) {
      exact(destroy, ["id", "count"], "destroy");
      atom(destroy.id); check(safe(destroy.count) && destroy.count > 0, "destroy count");
    }
  }
  const expanded = value.input.expanded;
  exact(expanded, ["changes", "tags", "revisions", "operations", "scenarios"], "expanded");
  exact(expanded.changes, ["first", "second", "nested-detached"], "input changes");
  exact(expanded.tags, Object.keys(expanded.changes), "input tags");
  Object.values(expanded.changes).forEach(structure);
  check(expanded.changes.first.aliases.length > 0 && expanded.changes.first.parents.length > 0,
    "missing alias and parent evidence");
  check(nonemptyArray(expanded.revisions), "revision identity mapping");
  const revisions = new Set();
  const encoded = new Set();
  for (const entry of expanded.revisions) {
    exact(entry, ["encoded", "stable"], "revision mapping");
    check(safe(entry.encoded) && stable(entry.stable), "revision mapping value");
    check(!revisions.has(entry.stable) && !encoded.has(entry.encoded), "duplicate revision mapping");
    revisions.add(entry.stable); encoded.add(entry.encoded);
  }
  check(Object.values(expanded.tags).every((tag) => revisions.has(tag)), "unknown input tag");
  const names = new Set(Object.keys(expanded.changes));
  const requireName = (name) => check(names.has(name), `unknown change ${name}`);
  check(nonemptyArray(expanded.operations), "operations");
  for (const action of expanded.operations) {
    check(object(action) && typeof action.id === "string" && !names.has(action.id), "operation identity");
    switch (action.op) {
      case "edit":
        exact(action, ["op", "id", "revision", "schema", "root", "path", "value"], "edit");
        check(revisions.has(action.revision), "edit revision");
        check(typeof action.schema === "string" && JSON.parse(action.schema).version === 2, "edit schema");
        check(Array.isArray(action.path) && action.path.every((key) => typeof key === "string"), "edit path");
        if (action.root !== null) validateTaggedValue(action.root, label);
        if (action.value !== null) validateTaggedValue(action.value, label);
        break;
      case "compose":
        exact(action, ["op", "id", "changes"], "compose");
        check(nonemptyArray(action.changes), "compose inputs");
        action.changes.forEach(requireName);
        break;
      case "invert":
        exact(action, ["op", "id", "change", "isRollback", "inverseRevision"], "invert");
        requireName(action.change);
        check(typeof action.isRollback === "boolean" && revisions.has(action.inverseRevision), "inverse arguments");
        break;
      case "rebase":
        exact(action, ["op", "id", "change", "over", "revisionMetadata"], "rebase");
        requireName(action.change); requireName(action.over);
        check(nonemptyArray(action.revisionMetadata), "rebase revision metadata");
        for (const info of action.revisionMetadata) {
          exact(info, ["revision", "rollbackOf"], "rebase revision");
          check(revisions.has(info.revision) && (info.rollbackOf === null || revisions.has(info.rollbackOf)),
            "rebase revision identity");
        }
        break;
      case "replace-revisions":
        exact(action, ["op", "id", "change", "obsolete", "updated"], "revision replacement");
        requireName(action.change);
        check(nonemptyArray(action.obsolete) && action.obsolete.every((id) => id === null || revisions.has(id))
          && revisions.has(action.updated), "revision replacement identities");
        break;
      case "prune":
        exact(action, ["op", "id", "change"], "prune"); requireName(action.change);
        break;
      case "refreshers":
        exact(action, ["op", "id", "change", "roots", "repair"], "refreshers"); requireName(action.change);
        check(Array.isArray(action.roots), "refresher roots");
        action.roots.forEach(atom); builds(action.repair);
        break;
      default: check(false, `unsupported operation ${action.op}`);
    }
    names.add(action.id);
  }
  const operationIds = [
    "child-x", "child-y", "parent", "title", "optional-set", "optional-clear-empty",
    "nested-composed", "three-composed", "four-composed", "synthetic-composed",
    "child-rollback", "child-undo", "multi-rollback", "multi-undo",
    "x-over-y", "x-over-parent", "parent-over-x", "parent-then-detached",
    "collision-replaced", "alias-replaced", "pruned", "refreshed", "build-destroy-cancelled",
    "optional-root-set", "optional-root-clear", "optional-root-null", "optional-clear-present",
    "parent-again", "delayed-after-two-parents", "nested-reversed",
    "root-named-child", "nonlexical-left", "nonlexical-right",
    "nonlexical-composed", "nonlexical-undo", "nested-global-order",
  ];
  assert.deepEqual(expanded.operations.map(({ id }) => id), operationIds, `${label}: operation coverage`);
  const scenarioIds = ["nested-independent", "nested-composed", "parent-then-child", "child-then-parent",
    "composed-detached-child", "rollback-restores", "undo-restores-value", "three-fields", "four-fields",
    "optional-root-set", "optional-root-clear", "optional-root-null", "optional-clear-present",
    "replace-twice-then-delayed", "nested-reversed",
    "root-named-child", "nonlexical-undo", "nested-global-order"];
  check(nonemptyArray(expanded.scenarios), "forest scenarios");
  assert.deepEqual(expanded.scenarios.map(({ id }) => id), scenarioIds, `${label}: scenario coverage`);
  for (const scenario of expanded.scenarios) {
    exact(scenario, ["id", "schema", "root", "actions"], "scenario");
    check(typeof scenario.schema === "string" && JSON.parse(scenario.schema).version === 2, "scenario schema");
    if (scenario.root !== null) validateTaggedValue(scenario.root, label);
    check(nonemptyArray(scenario.actions), "scenario actions");
    for (const action of scenario.actions) {
      if (action.op === "retain") {
        exact(action, ["id", "op", "name", "path"], "retain");
        check(typeof action.name === "string" && Array.isArray(action.path)
          && action.path.every((key) => typeof key === "string"), "retained reference");
      } else {
        exact(action, ["id", "op", "change"], "apply");
        check(action.op === "apply", "unsupported forest action");
        requireName(action.change);
      }
    }
  }
  const observed = value.expected.observations.slice(6);
  check(observed.length === operationIds.length + scenarioIds.length, "observation count");
  assert.deepEqual(observed.map(({ id }) => id), [...operationIds, ...scenarioIds], `${label}: observation order`);
  for (const observation of observed.slice(0, operationIds.length)) {
    check(observation.operation === "modular" && typeof observation.accepted === "boolean", "operation observation");
    if (!observation.accepted) {
      exact(observation, ["operation", "id", "accepted"], "refusal");
      check(observation.id === "alias-replaced", "unexpected source refusal");
    } else {
      structure(observation.change);
      delta(observation.delta);
      if (observation.id === "refreshed") check(nonemptyArray(observation.removedRoots), "removed-root observations");
    }
  }
  for (const [index, observation] of observed.slice(operationIds.length).entries()) {
    check(observation.operation === "modular-forest"
      && observation.checkpoints.length === expanded.scenarios[index].actions.length, "forest checkpoints");
    for (const [checkpointIndex, checkpoint] of observation.checkpoints.entries()) {
      check(checkpoint.accepted === true && object(checkpoint.state), "forest application failure");
      exact(checkpoint.state, ["root", "references", "detached", "nextDetachedRootId"], "forest state");
      check(Array.isArray(checkpoint.state.references) && Array.isArray(checkpoint.state.detached), "retained state");
      if (checkpoint.state.root !== null) validateTaggedValue(checkpoint.state.root, label);
      check(safe(checkpoint.state.nextDetachedRootId), "forest allocation watermark");
      for (const reference of checkpoint.state.references) {
        exact(reference, ["name", "status", "value"], "retained reference");
        check(typeof reference.name === "string"
          && ["attached", "detached", "destroyed", "invalidated-by-copy"].includes(reference.status), "reference status");
        if (reference.value !== null) validateTaggedValue(reference.value, label);
        check((reference.value !== null) === ["attached", "detached"].includes(reference.status), "reference content");
      }
      for (const entry of checkpoint.state.detached) {
        exact(entry, ["id", "forestRootId", "latestRelevantRevision", "value"], "detached tree");
        atom(entry.id); validateTaggedValue(entry.value, label);
        check(safe(entry.forestRootId) && (entry.latestRelevantRevision === null || stable(entry.latestRelevantRevision)), "detached identity");
      }
      const retained = expanded.scenarios[index].actions.slice(0, checkpointIndex + 1)
        .filter(({ op }) => op === "retain").map(({ name }) => name).sort();
      assert.deepEqual(checkpoint.state.references.map(({ name }) => name).sort(), retained, `${label}: retained names`);
    }
  }
}

function validateHistoryCase(value) {
  const label = "history-reconciliation";
  const check = (condition, detail) => assert(condition, `${label}: ${detail}`);
  const stable = (value, detail) => check(typeof value === "string"
    && /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(value),
  detail);
  const safe = (value, detail) => check(Number.isSafeInteger(value), detail);
  const point = (value, detail) => {
    check(object(value), `${detail} must be an object`);
    safe(value.sequenceNumber, `${detail}.sequenceNumber`);
    safe(value.indexInBatch, `${detail}.indexInBatch`);
    check(value.indexInBatch >= 0, `${detail}.indexInBatch must be nonnegative`);
  };
  const commit = (value, detail) => {
    check(object(value), `${detail} must be an object`);
    stable(value.revision, `${detail}.revision`);
    stable(value.originator, `${detail}.originator`);
    check(object(value.change) && Array.isArray(value.change.revisions)
      && Array.isArray(value.change.fields) && Array.isArray(value.change.nodes)
      && Array.isArray(value.change.parents) && Array.isArray(value.change.aliases)
      && Array.isArray(value.change.builds) && Array.isArray(value.change.destroys)
      && Array.isArray(value.change.refreshers), `${detail}.change`);
  };
  const build = (value, detail) => {
    check(object(value) && object(value.id) && nonemptyArray(value.trees), detail);
    if (value.id.revision !== null) stable(value.id.revision, `${detail}.id.revision`);
    safe(value.id.localId, `${detail}.id.localId`);
    for (const tree of value.trees) validateTaggedValue(tree, label);
  };
  const history = (value, detail) => {
    check(object(value) && object(value.sequenced) && Array.isArray(value.pending)
      && Number.isSafeInteger(value.longestBranchLength)
      && value.longestBranchLength >= 0, detail);
    const sequenced = value.sequenced;
    check(object(sequenced.base)
      && ["initial", "sequenced"].includes(sequenced.base.kind)
      && Array.isArray(sequenced.trunk) && Array.isArray(sequenced.peers),
    `${detail}.sequenced`);
    if (sequenced.base.kind === "sequenced") point(sequenced.base.point, `${detail}.base.point`);
    safe(sequenced.sequenceNumber, `${detail}.sequenceNumber`);
    safe(sequenced.minimumSequenceNumber, `${detail}.minimumSequenceNumber`);
    for (const [index, entry] of sequenced.trunk.entries()) {
      check(object(entry), `${detail}.trunk[${index}]`);
      commit(entry.commit, `${detail}.trunk[${index}].commit`);
      point(entry.point, `${detail}.trunk[${index}].point`);
    }
    const peerSessions = new Set();
    for (const [index, peer] of sequenced.peers.entries()) {
      check(object(peer) && Object.hasOwn(peer, "base") && Array.isArray(peer.commits),
        `${detail}.peers[${index}]`);
      stable(peer.originator, `${detail}.peers[${index}].originator`);
      check(!peerSessions.has(peer.originator), `${detail}: duplicate peer session`);
      peerSessions.add(peer.originator);
      if (peer.base !== null) stable(peer.base, `${detail}.peers[${index}].base`);
      for (const [commitIndex, entry] of peer.commits.entries()) {
        commit(entry, `${detail}.peers[${index}].commits[${commitIndex}]`);
      }
    }
    for (const [index, entry] of value.pending.entries()) {
      commit(entry, `${detail}.pending[${index}]`);
    }
  };

  check(object(value.input.sessions)
    && Object.keys(value.input.sessions).sort().join(",") === "local,peerA,peerB,restored",
  "sessions");
  for (const session of Object.values(value.input.sessions)) stable(session, "session");
  check(nonemptyArray(value.input.revisions), "revision identity order");
  const stableIds = new Set();
  const encodedIds = new Set();
  for (const revision of value.input.revisions) {
    stable(revision.stable, "revision stable ID");
    safe(revision.encoded, "revision encoded ID");
    check(!stableIds.has(revision.stable), "duplicate stable revision");
    check(!encodedIds.has(revision.encoded), "duplicate encoded revision");
    stableIds.add(revision.stable);
    encodedIds.add(revision.encoded);
  }
  check(typeof value.input.schema === "string" && JSON.parse(value.input.schema).version === 2,
    "stored schema");
  validateTaggedValue(value.input.root, label);
  check(object(value.input.changes) && Object.keys(value.input.changes).length > 0,
    "authored changes");
  check(nonemptyArray(value.input.schedules)
    && Array.isArray(value.expected.observations)
    && Array.isArray(value.raw.schedules), "paired schedules");
  assert.deepEqual(value.input.schedules.map(({ label: id }) => id), historyScheduleIds,
    `${label}: input schedule order`);
  assert.deepEqual(value.expected.observations.map(({ label: id }) => id), historyScheduleIds,
    `${label}: observation schedule order`);
  assert.deepEqual(value.raw.schedules.map(({ label: id }) => id), historyScheduleIds,
    `${label}: raw schedule order`);

  for (const [scheduleIndex, schedule] of value.input.schedules.entries()) {
    const observed = value.expected.observations[scheduleIndex];
    const raw = value.raw.schedules[scheduleIndex];
    check(object(schedule.initial) && stableIds.has(schedule.initial.localSession)
      && schedule.initial.schema === value.input.schema
      && object(schedule.initial.forest), `${schedule.label}: initial state`);
    check(nonemptyArray(schedule.actions)
      && observed.checkpoints.length === schedule.actions.length
      && raw.actions.length === schedule.actions.length,
    `${schedule.label}: action and checkpoint count`);
    const actionIds = new Set();
    for (const [index, action] of schedule.actions.entries()) {
      check(object(action) && typeof action.id === "string" && action.id.length > 0
        && typeof action.op === "string" && Array.isArray(action.allocations),
      `${schedule.label}: action ${index}`);
      check(!actionIds.has(action.id), `${schedule.label}: duplicate action ${action.id}`);
      actionIds.add(action.id);
      for (const [allocationIndex, allocation] of action.allocations.entries()) {
        stable(allocation.revision,
          `${schedule.label}.${action.id}.allocations[${allocationIndex}].revision`);
        check(nonemptyArray(allocation.identityOrder),
          `${schedule.label}.${action.id}.allocations[${allocationIndex}].identityOrder`);
        check(allocation.identityOrder.some(({ stable: id }) => id === allocation.revision),
          `${schedule.label}.${action.id}: allocation mapping`);
      }
      if (action.op === "append-local") {
        check(object(action.commit) && typeof action.commit.change === "string",
          `${schedule.label}.${action.id}: local commit`);
        stable(action.commit.revision, `${schedule.label}.${action.id}.revision`);
        stable(action.commit.originator, `${schedule.label}.${action.id}.originator`);
      } else if (action.op === "receive") {
        check(object(action.commit), `${schedule.label}.${action.id}: received commit`);
        point(action.point, `${schedule.label}.${action.id}.point`);
        safe(action.referenceSequenceNumber,
          `${schedule.label}.${action.id}.referenceSequenceNumber`);
        safe(action.minimumSequenceNumber,
          `${schedule.label}.${action.id}.minimumSequenceNumber`);
      } else if (action.op === "advance-minimum") {
        safe(action.sequenceNumber, `${schedule.label}.${action.id}.sequenceNumber`);
        safe(action.minimumSequenceNumber,
          `${schedule.label}.${action.id}.minimumSequenceNumber`);
      } else if (action.op === "snapshot-restore") {
        stable(action.localSession, `${schedule.label}.${action.id}.localSession`);
      } else if (action.op === "resubmit") {
        check(Array.isArray(action.repair), `${schedule.label}.${action.id}.repair`);
        const repairs = new Set();
        for (const [repairIndex, entry] of action.repair.entries()) {
          stable(entry.revision,
            `${schedule.label}.${action.id}.repair[${repairIndex}].revision`);
          check(!repairs.has(entry.revision),
            `${schedule.label}.${action.id}: duplicate repair revision`);
          repairs.add(entry.revision);
          check(nonemptyArray(entry.builds),
            `${schedule.label}.${action.id}.repair[${repairIndex}].builds`);
          entry.builds.forEach((item, buildIndex) =>
            build(item, `${schedule.label}.${action.id}.repair[${repairIndex}].builds[${buildIndex}]`));
        }
      } else {
        assert.fail(`${label}: unsupported action ${action.op}`);
      }

      const checkpoint = observed.checkpoints[index];
      check(object(checkpoint) && checkpoint.id === action.id
        && checkpoint.operation === action.op
        && Object.hasOwn(checkpoint, "delta")
        && object(checkpoint.forest)
        && Array.isArray(checkpoint.forest.detached)
        && Array.isArray(checkpoint.trimmedRevisions)
        && object(checkpoint.allocator)
        && Array.isArray(checkpoint.allocator.consumed),
      `${schedule.label}.${action.id}: checkpoint`);
      history(checkpoint.history, `${schedule.label}.${action.id}.history`);
      assert.deepEqual(checkpoint.allocator.consumed, action.allocations,
        `${label}: ${schedule.label}.${action.id} allocation observations`);
      for (const revision of checkpoint.trimmedRevisions) {
        stable(revision, `${schedule.label}.${action.id}.trimmedRevision`);
      }
      if (action.op === "snapshot-restore") {
        check(object(checkpoint.snapshot), `${schedule.label}.${action.id}.snapshot`);
      }
      if (action.op === "resubmit") {
        check(Array.isArray(checkpoint.resubmitted),
          `${schedule.label}.${action.id}.resubmitted`);
        checkpoint.resubmitted.forEach((entry, commitIndex) =>
          commit(entry, `${schedule.label}.${action.id}.resubmitted[${commitIndex}]`));
      }
      check(object(raw.actions[index]) && raw.actions[index].id === action.id,
        `${schedule.label}.${action.id}: raw action`);
    }
  }

  const inner = value.expected.observations.find(({ label: id }) => id === "two-inner-commits");
  assert.deepEqual(inner.checkpoints[1].history.sequenced.trunk.map(({ point: value }) => value),
    [{ sequenceNumber: 5, indexInBatch: 0 }, { sequenceNumber: 5, indexInBatch: 1 }],
    `${label}: same-sequence inner ordering`);
  const staleInput = value.input.schedules
    .find(({ label: id }) => id === "stale-peer-chain");
  const stale = value.expected.observations
    .find(({ label: id }) => id === "stale-peer-chain");
  assert.deepEqual(staleInput.actions.map((action) => [
    action.commit.change,
    action.referenceSequenceNumber,
  ]), [
    ["remote-parent-b", 0],
    ["remote-parent", 0],
    ["remote-child-y", 0],
  ], `${label}: stale peer divergent continuation inputs`);
  const stalePeer = stale.checkpoints.at(-1).history.sequenced.peers
    .find((peer) => peer.originator === value.input.sessions.peerA);
  check(stalePeer.commits.length === 2
    && stalePeer.commits[0].revision === staleInput.actions[1].commit.revision
    && stalePeer.commits[1].revision === staleInput.actions[2].commit.revision
    && staleInput.actions[2].allocations.length === 1,
  "stale peer continuation and rollback reuse");
  const trimmed = value.expected.observations
    .find(({ label: id }) => id === "window-advance-with-pending").checkpoints.at(-1);
  check(trimmed.history.sequenced.base.kind === "sequenced"
    && trimmed.history.sequenced.base.point.sequenceNumber === 1
    && nonemptyArray(trimmed.trimmedRevisions)
    && trimmed.history.pending.length === 1
    && trimmed.history.sequenced.peers.some((peer) => peer.commits.length > 0),
  "window trimming with pending divergent peer state");
  const snapshot = value.expected.observations
    .find(({ label: id }) => id === "settled-snapshot-tail");
  const restored = snapshot.checkpoints.find((item) => object(item.snapshot));
  const snapshotPeer = restored.snapshot.peers
    .find((peer) => peer.originator === value.input.sessions.peerA);
  const tailPeer = snapshot.checkpoints.at(-1).history.sequenced.peers
    .find((peer) => peer.originator === value.input.sessions.peerA);
  check(snapshotPeer.commits.length === 2
    && tailPeer.commits.length === 3
    && tailPeer.commits[0].revision === snapshotPeer.commits[0].revision
    && tailPeer.commits[1].revision === snapshotPeer.commits[1].revision
    && snapshot.checkpoints.at(-1).history.pending.length === 0,
  "snapshot restore divergent peer continuation");
  const accepted = value.expected.observations
    .find(({ label: id }) => id === "accepted-before-ack").checkpoints.at(-1).resubmitted;
  check(accepted.length === 1, "accepted-before-ack pending result");
  const never = value.expected.observations.find(({ label: id }) => id === "never-submitted");
  const neverInput = value.input.schedules.find(({ label: id }) => id === "never-submitted");
  const resubmits = never.checkpoints.filter((item) => Array.isArray(item.resubmitted));
  check(resubmits[0].resubmitted.length === 1
    && resubmits[1].resubmitted[0].revision === resubmits[0].resubmitted[0].revision
    && resubmits.at(-1).resubmitted.length === 0
    && neverInput.actions.filter((action) => action.op === "resubmit")
      .every((action) => action.repair.length === 0),
  "never-submitted stable resubmission without external repair");
  const detachedRepair = value.input.schedules
    .find(({ label: id }) => id === "resubmit-detached-repair").actions.at(-1).repair;
  check(detachedRepair.length === 2, "per-commit detached repair");
  const firstIds = detachedRepair[0].builds.map(({ id }) => JSON.stringify(id));
  check(detachedRepair[1].builds.some(({ id }) => firstIds.includes(JSON.stringify(id))),
    "shared removed root repair");
  check(JSON.stringify(detachedRepair[0].builds) !== JSON.stringify(detachedRepair[1].builds),
    "distinct per-commit repair");
  check(value.raw.nonlexical.left.stable < value.raw.nonlexical.right.stable
    && value.raw.nonlexical.left.encoded > value.raw.nonlexical.right.encoded,
  "nonlexical compressed revision order");
  const nonlexicalInput = value.input.schedules
    .find(({ label: id }) => id === "nonlexical-rollback-order");
  const nonlexical = value.expected.observations
    .find(({ label: id }) => id === "nonlexical-rollback-order");
  const firstContinuation = nonlexical.checkpoints
    .find((checkpoint) => checkpoint.id === "peer-a-continues");
  const secondContinuation = nonlexical.checkpoints
    .find((checkpoint) => checkpoint.id === "peer-a-continues-again");
  const firstPeer = firstContinuation.history.sequenced.peers
    .find((peer) => peer.originator === value.input.sessions.peerA);
  const secondPeer = secondContinuation.history.sequenced.peers
    .find((peer) => peer.originator === value.input.sessions.peerA);
  check(firstPeer.commits.length === 2
    && secondPeer.commits.length === 3
    && secondPeer.commits[0].revision === firstPeer.commits[0].revision
    && nonlexicalInput.actions
      .find((action) => action.id === "peer-a-continues").allocations.length === 2
    && nonlexicalInput.actions
      .find((action) => action.id === "peer-a-continues-again").allocations.length === 2,
  "nonlexical immutable peer node rollback reuse");
}

export function validateCodecCase(value) {
  const label = "tree-codecs";
  const check = (condition, detail) => assert(condition, `${label}: ${detail}`);
  check(object(value) && value.id === label && value.domain === "codec", "identity");
  const input = value.input;
  check(object(input), "input");
  assert.deepEqual(input.profile, {
    message: 7,
    sharedTreeChange: 5,
    modularChange: 5,
    optionalField: 2,
    genericField: 1,
    fieldBatch: 2,
    schema: 2,
    forest: 2,
    detachedFieldIndex: 2,
    editManager: 7,
  }, `${label}: profile`);

  check(nonemptyArray(input.scenarios), "scenarios");
  const scenarioIds = new Set();
  for (const scenario of input.scenarios) {
    check(object(scenario) && typeof scenario.id === "string" && scenario.id.length > 0
      && !scenarioIds.has(scenario.id), "duplicate or missing scenario ID");
    scenarioIds.add(scenario.id);
    for (const field of ["session", "compressor", "peerSession", "peerCompressor",
      "settledCompressor"]) {
      check(typeof scenario[field] === "string" && scenario[field].length > 0,
        `${scenario.id}: ${field}`);
    }
    check(nonemptyArray(scenario.allocationMessages), `${scenario.id}: allocationMessages`);
    check(nonemptyArray(scenario.actions), `${scenario.id}: actions`);
    check(nonemptyArray(scenario.messages), `${scenario.id}: messages`);
    for (const raw of scenario.messages) {
      check(typeof raw === "string" && raw.length > 0, `${scenario.id}: raw message`);
      const message = JSON.parse(raw);
      check(object(message) && message.version === 7
        && typeof message.originatorId === "string"
        && Array.isArray(message.changeset), `${scenario.id}: message envelope`);
    }
    check(summary(scenario.initialSummary) && summary(scenario.settledSummary),
      `${scenario.id}: summaries`);
  }

  check(Array.isArray(input.schemas), "schemas");
  assert.deepEqual(input.schemas.map(({ id }) => id), ["fixed", "empty", "optional"],
    `${label}: schema IDs`);
  for (const schema of input.schemas) {
    check(object(schema) && typeof schema.raw === "string", `${schema?.id}: schema`);
    const parsed = JSON.parse(schema.raw);
    check(object(parsed) && parsed.version === 2 && object(parsed.nodes) && object(parsed.root),
      `${schema.id}: schema value`);
  }

  check(Array.isArray(input.fieldBatches), "field batches");
  assert.deepEqual(input.fieldBatches.map(({ id }) => id), [
    "initial-forest-compressed",
    "initial-build-compressed",
    "simple-uncompressed",
  ], `${label}: field batch IDs`);
  for (const field of input.fieldBatches) {
    check(object(field) && object(field.encoded) && field.encoded.version === 2
      && Array.isArray(field.encoded.identifiers)
      && Array.isArray(field.encoded.shapes)
      && Array.isArray(field.encoded.data), `${field?.id}: field batch`);
  }

  const metadata = input.metadataMessage;
  check(object(metadata) && typeof metadata.raw === "string"
    && typeof metadata.session === "string" && typeof metadata.compressor === "string",
  "metadata message context");
  const metadataMessage = JSON.parse(metadata.raw);
  check(object(metadataMessage) && object(metadataMessage.customMetadata)
    && Object.keys(metadataMessage).some((key) =>
      !["revision", "originatorId", "changeset", "version", "customMetadata"].includes(key)),
  "metadata and tolerated envelope property");

  check(Array.isArray(input.summaries), "summaries");
  assert.deepEqual(input.summaries.map(({ id }) => id), ["initial", "settled-detached"],
    `${label}: summary IDs`);
  for (const entry of input.summaries) {
    check(object(entry) && summary(entry.summary)
      && typeof entry.session === "string" && entry.session.length > 0
      && typeof entry.compressor === "string" && entry.compressor.length > 0,
    `${entry?.id}: summary context`);
  }

  check(object(value.expected) && nonemptyArray(value.expected.observations),
    "expected observations");
  const observations = new Set(value.expected.observations.map(({ id }) => id));
  for (const id of ["bootstrap-history", "initial-schema", "initial-forest",
    "initial-detached", "settled-history", "settled-forest", "settled-detached", "metadata"]) {
    check(observations.has(id), `missing observation ${id}`);
  }

  check(object(value.raw) && Array.isArray(value.raw.scenarios)
    && value.raw.scenarios.length === input.scenarios.length
    && object(value.raw.blobs), "raw evidence");
  assert.deepEqual(value.raw.scenarios.map(({ id }) => id), [...scenarioIds],
    `${label}: raw scenario order`);
  for (const name of ["initial", "settled"]) {
    const blobs = value.raw.blobs[name];
    check(object(blobs), `raw ${name} blobs`);
    for (const field of ["history", "schema", "forest", "detached"]) {
      check(typeof blobs[field] === "string" && blobs[field].length > 0,
        `raw ${name}.${field}`);
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
    if (value.id === "forest-delta") validateForestCase(value);
    if (value.id === "container-foundations") validateContainerFoundationsCase(value);
    if (value.id === "summary-foundations") validateSummaryFoundationsCase(value);
    if (value.domain === "field" || value.domain === "modular") {
      assert(object(value.input.changes) && Object.keys(value.input.changes).length > 0
        && object(value.raw.encoded) && Object.keys(value.raw.encoded).length > 0,
      `${value.id}: missing algebra inputs or encoded outputs`);
    }
    if (value.id === "field-compose-invert-rebase") validateFieldCase(value);
    if (value.id === "modular-nested-algebra") validateModularCase(value);
    if (value.id === "history-reconciliation") validateHistoryCase(value);
    if (value.id === "tree-codecs") validateCodecCase(value);
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
    if ((["container", "runtime", "summary"].includes(domain) || id === "reconnect-before-ack")
      && id !== "container-foundations" && id !== "summary-foundations") {
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
  const messages = messageInventory(cases);
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
      observedFieldKinds: messages.fieldKinds,
      messages,
      treeSummaryMetadata: summaryMetadata(smoke.summary),
      serviceSummaryPaths: profile.container.summaryPaths,
      documentSchema: profile.container.documentSchema,
      gcMetadataVersion: profile.container.gcFeature,
    },
    nativeSemanticRunners: {
      javascript: [
        "id-ranges", "schema-validation", "forest-delta",
        "field-compose-invert-rebase", "modular-nested-algebra",
        "container-foundations", "summary-foundations",
        "history-reconciliation", "tree-codecs",
      ],
      erlang: [
        "id-ranges", "schema-validation", "forest-delta",
        "field-compose-invert-rebase", "modular-nested-algebra",
        "container-foundations", "summary-foundations",
        "history-reconciliation", "tree-codecs",
      ],
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
      ...await read(join(source, "forest-cases.json")),
      ...await read(join(source, "history-cases.json")),
      ...await read(join(source, "codec-cases.json")),
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
