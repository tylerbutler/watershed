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
  ["forest-delta", "forest"],
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

const fieldScenarioIds = [
  "edit-empty",
  "edit-occupied",
  "clear-empty",
  "clear-occupied",
  "compose-set-set",
  "compose-set-clear",
  "compose-clear-set",
  "compose-clear-clear",
  "compose-child-both",
  "compose-child-first",
  "compose-child-second",
  "compose-move-chain",
  "compose-revive",
  "compose-pin",
  "compose-ordering",
  "invert-set-rollback",
  "invert-set-undo",
  "invert-clear",
  "invert-pin",
  "invert-empty-clear",
  "rebase-set-set-orders",
  "rebase-set-clear-orders",
  "rebase-clear-clear",
  "rebase-child-both",
  "rebase-child-first",
  "rebase-child-base-only",
  "rebase-child-drop",
  "rebase-remove-revive",
  "rebase-empty-reservation",
  "rebase-pinned-reservation",
  "rebase-swap",
  "replace-all-identities",
  "replace-anonymous",
  "replace-unmatched",
  "delta-local-global",
  "forest-compose",
  "forest-inverse",
  "forest-null-clear",
  "law-do-rollback",
  "law-do-undo",
  "law-sandwich",
  "law-compose-inverse",
  "law-associativity",
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
  const scenarios = value.input.scenarios;
  const observed = value.expected.scenarios;
  const raw = value.raw.scenarios;
  const revisionTable = value.input.revisionTable;
  assert(Array.isArray(scenarios) && Array.isArray(observed) && Array.isArray(raw),
    "field-compose-invert-rebase: missing paired scenario evidence");
  assert.deepEqual(scenarios.map(({ id }) => id), fieldScenarioIds,
    "field-compose-invert-rebase: required scenario IDs");
  assert.deepEqual(observed.map(({ id }) => id), fieldScenarioIds,
    "field-compose-invert-rebase: expected scenario order");
  assert.deepEqual(raw.map(({ id }) => id), fieldScenarioIds,
    "field-compose-invert-rebase: raw scenario order");
  assert(Array.isArray(revisionTable) && revisionTable.length > 0,
    "field-compose-invert-rebase: missing revision table");
  const numericRevisions = new Set();
  const stableRevisions = new Set();
  for (const entry of revisionTable) {
    assert(object(entry) && Number.isSafeInteger(entry.revision) && entry.revision >= 0
      && typeof entry.stableId === "string"
      && /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(entry.stableId),
    "field-compose-invert-rebase: malformed revision mapping");
    assert(!numericRevisions.has(entry.revision) && !stableRevisions.has(entry.stableId),
      "field-compose-invert-rebase: duplicate revision mapping");
    numericRevisions.add(entry.revision);
    stableRevisions.add(entry.stableId);
  }

  function atom(value, label) {
    assert(object(value) && Object.keys(value).length === 2
      && Object.hasOwn(value, "revision") && Object.hasOwn(value, "localId")
      && (value.revision === null
        || (Number.isSafeInteger(value.revision) && numericRevisions.has(value.revision)))
      && Number.isSafeInteger(value.localId) && value.localId >= 0,
    `field-compose-invert-rebase: malformed atom ${label}`);
  }

  function register(value, label) {
    assert(object(value) && (value.kind === "active" || value.kind === "detached"),
      `field-compose-invert-rebase: malformed register ${label}`);
    if (value.kind === "active") {
      assert.deepEqual(Object.keys(value), ["kind"],
        `field-compose-invert-rebase: malformed active register ${label}`);
    } else {
      atom(value.id, `${label}.id`);
    }
  }

  function change(value, label) {
    assert(object(value) && Array.isArray(value.moves) && Array.isArray(value.childChanges)
      && Object.hasOwn(value, "replacement"),
    `field-compose-invert-rebase: malformed change ${label}`);
    for (const [index, move] of value.moves.entries()) {
      assert(Array.isArray(move) && move.length === 2,
        `field-compose-invert-rebase: malformed move ${label}[${index}]`);
      atom(move[0], `${label}.moves[${index}].source`);
      atom(move[1], `${label}.moves[${index}].destination`);
    }
    for (const [index, child] of value.childChanges.entries()) {
      assert(Array.isArray(child) && child.length === 2,
        `field-compose-invert-rebase: malformed child change ${label}[${index}]`);
      register(child[0], `${label}.childChanges[${index}].register`);
      atom(child[1], `${label}.childChanges[${index}].node`);
    }
    if (value.replacement !== null) {
      assert(object(value.replacement) && typeof value.replacement.wasEmpty === "boolean"
        && Object.hasOwn(value.replacement, "source"),
      `field-compose-invert-rebase: malformed replacement ${label}`);
      if (value.replacement.source !== null) {
        register(value.replacement.source, `${label}.replacement.source`);
      }
      atom(value.replacement.detachId, `${label}.replacement.detachId`);
    }
  }

  function fieldMap(value, label) {
    assert(Array.isArray(value), `field-compose-invert-rebase: malformed field map ${label}`);
    const keys = new Set();
    for (const [index, entry] of value.entries()) {
      assert(Array.isArray(entry) && entry.length === 2 && typeof entry[0] === "string"
        && object(entry[1]) && Array.isArray(entry[1].marks) && !keys.has(entry[0]),
      `field-compose-invert-rebase: malformed field entry ${label}[${index}]`);
      keys.add(entry[0]);
      for (const [markIndex, mark] of entry[1].marks.entries()) {
        assert(object(mark) && Number.isSafeInteger(mark.count) && mark.count > 0,
          `field-compose-invert-rebase: malformed mark ${label}[${index}].${markIndex}`);
        if (mark.attach !== undefined && mark.attach !== null) {
          atom(mark.attach, `${label}[${index}].${markIndex}.attach`);
        }
        if (mark.detach !== undefined && mark.detach !== null) {
          atom(mark.detach, `${label}[${index}].${markIndex}.detach`);
        }
        if (mark.fields !== undefined) {
          fieldMap(mark.fields, `${label}[${index}].${markIndex}.fields`);
        }
      }
    }
  }

  function delta(value, label) {
    assert(object(value) && Object.hasOwn(value, "local")
      && Array.isArray(value.global) && Array.isArray(value.rename),
    `field-compose-invert-rebase: malformed delta ${label}`);
    if (value.local !== null) {
      assert(object(value.local) && Array.isArray(value.local.marks),
        `field-compose-invert-rebase: malformed local delta ${label}`);
      fieldMap([["root", value.local]], `${label}.local`);
    }
    for (const [index, global] of value.global.entries()) {
      assert(object(global), `field-compose-invert-rebase: malformed global delta ${label}`);
      atom(global.id, `${label}.global[${index}].id`);
      fieldMap(global.fields, `${label}.global[${index}].fields`);
    }
    for (const [index, rename] of value.rename.entries()) {
      assert(object(rename) && rename.count === 1,
        `field-compose-invert-rebase: malformed rename ${label}[${index}]`);
      atom(rename.oldId, `${label}.rename[${index}].oldId`);
      atom(rename.newId, `${label}.rename[${index}].newId`);
    }
  }

  function forestState(value, label) {
    assert(object(value) && object(value.root) && typeof value.root.present === "boolean"
      && Object.hasOwn(value.root, "value") && Array.isArray(value.detachedRegisters),
    `field-compose-invert-rebase: malformed forest state ${label}`);
    for (const [index, detached] of value.detachedRegisters.entries()) {
      assert(object(detached) && Object.hasOwn(detached, "value"),
        `field-compose-invert-rebase: malformed detached register ${label}[${index}]`);
      atom(detached.id, `${label}.detachedRegisters[${index}].id`);
    }
  }

  for (let scenarioIndex = 0; scenarioIndex < scenarios.length; scenarioIndex += 1) {
    const scenario = scenarios[scenarioIndex];
    const observation = observed[scenarioIndex];
    const evidence = raw[scenarioIndex];
    assert(object(scenario) && typeof scenario.id === "string" && object(scenario.changes)
      && nonemptyArray(scenario.actions),
    "field-compose-invert-rebase: malformed scenario");
    assert(object(observation) && observation.id === scenario.id
      && Array.isArray(observation.checkpoints)
      && observation.checkpoints.length === scenario.actions.length,
    `field-compose-invert-rebase: incomplete checkpoints ${scenario.id}`);
    assert(object(evidence) && evidence.id === scenario.id
      && Array.isArray(evidence.checkpoints)
      && evidence.checkpoints.length === scenario.actions.length,
    `field-compose-invert-rebase: missing raw checkpoints ${scenario.id}`);
    const references = new Set(Object.keys(scenario.changes));
    for (const [name, initial] of Object.entries(scenario.changes)) {
      change(initial, `${scenario.id}.changes.${name}`);
    }
    const actionIds = new Set();
    for (let actionIndex = 0; actionIndex < scenario.actions.length; actionIndex += 1) {
      const action = scenario.actions[actionIndex];
      const checkpoint = observation.checkpoints[actionIndex];
      const rawCheckpoint = evidence.checkpoints[actionIndex];
      assert(object(action) && typeof action.id === "string" && action.id.length > 0
        && !actionIds.has(action.id),
      `field-compose-invert-rebase: duplicate or missing action ID ${scenario.id}`);
      actionIds.add(action.id);
      assert(object(checkpoint) && checkpoint.id === action.id
        && object(rawCheckpoint) && rawCheckpoint.id === action.id
        && rawCheckpoint.op === action.op,
      `field-compose-invert-rebase: reordered checkpoint ${scenario.id}.${action.id}`);
      assert(["set", "clear", "replaceRevisions", "compose", "invert", "rebase", "intoDelta"]
        .includes(action.op),
      `field-compose-invert-rebase: unknown operation ${scenario.id}.${action.id}`);
      const actionKeys = {
        set: ["id", "op", "result", "wasEmpty", "fill", "detach"],
        clear: ["id", "op", "result", "wasEmpty", "detach"],
        replaceRevisions: ["id", "op", "result", "change", "obsolete", "updated"],
        compose: ["id", "op", "result", "left", "right", "callbacks"],
        invert: ["id", "op", "result", "change", "isRollback", "inverseRevision", "lastLocalId"],
        rebase: ["id", "op", "result", "change", "over", "callbacks"],
        intoDelta: ["id", "op", "change", "childDeltas", "applyToForest", "revision"],
      }[action.op];
      assert(Object.keys(action).every((key) => actionKeys.includes(key)),
        `field-compose-invert-rebase: unexpected script field ${scenario.id}.${action.id}`);

      const requireReference = (name, field) => {
        assert(typeof name === "string" && references.has(name),
          `field-compose-invert-rebase: unresolved or forward ${field} ${scenario.id}.${action.id}`);
      };
      if (action.op === "compose") {
        requireReference(action.left, "left");
        requireReference(action.right, "right");
        assert(Array.isArray(action.callbacks) && Array.isArray(checkpoint.callbacks)
          && Array.isArray(rawCheckpoint.callbacks)
          && checkpoint.callbacks.length === action.callbacks.length
          && rawCheckpoint.callbacks.length === action.callbacks.length
          && JSON.stringify(checkpoint.callbacks) === JSON.stringify(action.callbacks)
          && JSON.stringify(rawCheckpoint.callbacks) === JSON.stringify(action.callbacks),
        `field-compose-invert-rebase: missing callback evidence ${scenario.id}.${action.id}`);
      } else if (action.op === "rebase") {
        requireReference(action.change, "change");
        requireReference(action.over, "over");
        assert(Array.isArray(action.callbacks) && Array.isArray(checkpoint.callbacks)
          && Array.isArray(rawCheckpoint.callbacks)
          && checkpoint.callbacks.length === action.callbacks.length
          && rawCheckpoint.callbacks.length === action.callbacks.length
          && JSON.stringify(checkpoint.callbacks) === JSON.stringify(action.callbacks)
          && JSON.stringify(rawCheckpoint.callbacks) === JSON.stringify(action.callbacks),
        `field-compose-invert-rebase: missing callback evidence ${scenario.id}.${action.id}`);
      } else if (action.op === "invert") {
        requireReference(action.change, "change");
        assert(typeof action.isRollback === "boolean"
          && Number.isSafeInteger(action.inverseRevision)
          && numericRevisions.has(action.inverseRevision)
          && Number.isSafeInteger(action.lastLocalId)
          && object(checkpoint.allocations) && object(rawCheckpoint.allocations)
          && Array.isArray(checkpoint.allocations.allocated)
          && checkpoint.allocations.end >= checkpoint.allocations.start
          && JSON.stringify(checkpoint.allocations) === JSON.stringify(rawCheckpoint.allocations),
        `field-compose-invert-rebase: missing allocator evidence ${scenario.id}.${action.id}`);
      } else if (action.op === "replaceRevisions") {
        requireReference(action.change, "change");
        assert(nonemptyArray(action.obsolete)
          && action.obsolete.every((revision) =>
            revision === null || numericRevisions.has(revision))
          && numericRevisions.has(action.updated),
        `field-compose-invert-rebase: missing revision mapping ${scenario.id}.${action.id}`);
      } else if (action.op === "intoDelta") {
        requireReference(action.change, "change");
        assert(Array.isArray(action.childDeltas) && object(checkpoint.delta)
          && object(rawCheckpoint.delta),
        `field-compose-invert-rebase: missing delta evidence ${scenario.id}.${action.id}`);
        for (const [index, childDelta] of action.childDeltas.entries()) {
          assert(object(childDelta), `field-compose-invert-rebase: malformed child delta ${scenario.id}`);
          atom(childDelta.node, `${scenario.id}.${action.id}.childDeltas[${index}].node`);
          fieldMap(childDelta.fields, `${scenario.id}.${action.id}.childDeltas[${index}].fields`);
        }
        delta(checkpoint.delta, `${scenario.id}.${action.id}`);
        if (action.applyToForest === true) {
          assert(object(scenario.forest) && object(checkpoint.forest)
            && object(rawCheckpoint.forest),
          `field-compose-invert-rebase: missing forest evidence ${scenario.id}.${action.id}`);
          forestState(checkpoint.forest, `${scenario.id}.${action.id}`);
          assert(object(rawCheckpoint.forest.root)
            && Array.isArray(rawCheckpoint.forest.detachedIndex),
          `field-compose-invert-rebase: malformed raw forest ${scenario.id}.${action.id}`);
        }
      } else if (action.op === "set") {
        assert(typeof action.wasEmpty === "boolean",
          `field-compose-invert-rebase: malformed set ${scenario.id}.${action.id}`);
        atom(action.fill, `${scenario.id}.${action.id}.fill`);
        atom(action.detach, `${scenario.id}.${action.id}.detach`);
      } else if (action.op === "clear") {
        assert(typeof action.wasEmpty === "boolean",
          `field-compose-invert-rebase: malformed clear ${scenario.id}.${action.id}`);
        atom(action.detach, `${scenario.id}.${action.id}.detach`);
      }

      if (action.op !== "intoDelta") {
        assert(typeof action.result === "string" && action.result.length > 0
          && !references.has(action.result),
        `field-compose-invert-rebase: missing or duplicate result ${scenario.id}.${action.id}`);
        change(checkpoint.result, `${scenario.id}.${action.id}.result`);
        assert(object(rawCheckpoint.change),
          `field-compose-invert-rebase: missing raw change ${scenario.id}.${action.id}`);
        references.add(action.result);
      }
    }
    if (scenario.forest !== undefined) {
      assert(object(scenario.forest.schema)
        && object(scenario.forest.initialRoot)
        && typeof scenario.forest.initialRoot.present === "boolean"
        && Array.isArray(scenario.forest.builds)
        && Array.isArray(scenario.forest.detachedRegisters),
      `field-compose-invert-rebase: malformed forest input ${scenario.id}`);
      assert.deepEqual(scenario.forest.schema, {
        rootField: "root",
        cardinality: "optional",
        values: "json-compatible",
      }, `field-compose-invert-rebase: unsupported forest schema ${scenario.id}`);
      for (const [index, build] of scenario.forest.builds.entries()) {
        assert(object(build) && Object.hasOwn(build, "value"),
          `field-compose-invert-rebase: malformed forest build ${scenario.id}[${index}]`);
        atom(build.id, `${scenario.id}.forest.builds[${index}].id`);
      }
      for (const [index, detached] of scenario.forest.detachedRegisters.entries()) {
        assert(object(detached) && Object.hasOwn(detached, "value"),
          `field-compose-invert-rebase: malformed initial detached register ${scenario.id}[${index}]`);
        atom(detached.id, `${scenario.id}.forest.detachedRegisters[${index}].id`);
      }
    }
  }

  const refusal = value.expected.observations.find(({ operation }) =>
    operation === "simultaneous-swap-direct-application-refusal");
  assert(refusal?.status === "rejected" && refusal.reason === "occupied-rename-cycle"
    && !Object.hasOwn(refusal, "error")
    && value.raw.swapApplication?.refusal?.error === "Error: 0x7cf",
  "field-compose-invert-rebase: direct swap refusal evidence disagreement");
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
    if (value.id === "field-compose-invert-rebase") validateFieldCase(value);
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
      javascript: ["id-ranges", "schema-validation", "forest-delta", "field-compose-invert-rebase"],
      erlang: ["id-ranges", "schema-validation", "forest-delta", "field-compose-invert-rebase"],
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
