import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import * as generator from "./generate.mjs";
import { compareDirectories, requiredCases, validateCases, writeCorpus } from "./generate.mjs";

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

function cases(exclude = []) {
  const synthetic = {
    "map-schema-content": mapSchemaCaseFixture,
    "map-field-algebra": mapFieldCaseFixture,
    "map-history-codecs": mapHistoryCaseFixture,
  };
  return requiredCases.filter(([id]) => !exclude.includes(id)).map(([id]) =>
    synthetic[id]?.() ?? JSON.parse(readFileSync(
      new URL(`../../test/fixtures/shared_tree/cases/${id}.json`, import.meta.url), "utf8",
    )));
}

test("summary persistence validation refuses missing or nonreplayable inputs", () => {
  for (const mutate of [
    (value) => { delete value.input.persistenceStates; },
    (value) => { value.input.persistenceStates.pop(); },
    (value) => { value.input.persistenceStates[1].tail.shift(); },
    (value) => { value.input.persistenceStates[1].sequenceNumber += 1; },
    (value) => { value.input.persistenceStates[1].snapshot.blobs = {}; },
    (value) => { value.expected.persistenceObservations[1].continuationObserved = false; },
  ]) {
    const values = cases();
    mutate(values.find(({ id }) => id === "summary-writer-matrix"));
    assert.throws(() => validateCases(values), /summary-writer-matrix.*persistence/);
  }
});

function codecCaseFixture() {
  const summary = {
    type: 1,
    tree: {
      ".metadata": { type: 2, content: "{\"version\":2}" },
      indexes: { type: 1, tree: {} },
    },
  };
  const message = {
    revision: 0,
    originatorId: "11111111-1111-4111-8111-111111111111",
    changeset: [{ data: { maxId: 0, changes: [] } }],
    version: 7,
  };
  const fieldBatch = {
    version: 2,
    identifiers: [],
    shapes: [{ c: { extraFields: 1 } }, { a: 0 }],
    data: [[1, []]],
  };
  return {
    formatVersion: 1,
    reference: {
      package: "@fluidframework/tree",
      version: "3.1.0",
      commit: "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960",
    },
    id: "tree-codecs",
    domain: "codec",
    input: {
      profile: {
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
      },
      scenarios: [{
        id: "ordinary",
        session: "11111111-1111-4111-8111-111111111111",
        compressor: "serialized",
        peerSession: "22222222-2222-4222-8222-222222222222",
        peerCompressor: "peer-serialized",
        allocationMessages: [{ contents: { type: "idAllocation" } }],
        actions: [{ op: "set" }],
        messages: [JSON.stringify(message)],
        initialSummary: summary,
        settledSummary: summary,
        settledCompressor: "settled",
      }],
      schemas: [
        { id: "fixed", raw: "{\"version\":2,\"nodes\":{},\"root\":{\"kind\":\"Value\",\"types\":[\"x\"]}}" },
        { id: "empty", raw: "{\"version\":2,\"nodes\":{},\"root\":{\"kind\":\"Forbidden\",\"types\":[]}}" },
        { id: "optional", raw: "{\"version\":2,\"nodes\":{},\"root\":{\"kind\":\"Optional\",\"types\":[\"x\"]}}" },
      ],
      fieldBatches: [
        { id: "initial-forest-compressed", encoded: fieldBatch },
        { id: "initial-build-compressed", encoded: fieldBatch },
        { id: "simple-uncompressed", encoded: fieldBatch },
      ],
      metadataMessage: {
        raw: JSON.stringify({ ...message, customMetadata: { m: { value: true } }, extra: true }),
        session: "11111111-1111-4111-8111-111111111111",
        compressor: "serialized",
      },
      summaries: [
        { id: "initial", summary, session: "11111111-1111-4111-8111-111111111111", compressor: "serialized" },
        { id: "settled-detached", summary, session: "11111111-1111-4111-8111-111111111111", compressor: "settled" },
      ],
    },
    expected: {
      observations: [
        { id: "bootstrap-history", value: { version: 7, trunk: [], branches: [] } },
        { id: "initial-schema", value: {} },
        { id: "initial-forest", value: {} },
        { id: "initial-detached", value: {} },
        { id: "settled-history", value: {} },
        { id: "settled-forest", value: {} },
        { id: "settled-detached", value: {} },
        { id: "metadata", value: { m: { value: true } } },
      ],
    },
    raw: {
      scenarios: [{ id: "ordinary", messages: [{}], initialSummary: summary, settledSummary: summary }],
      blobs: {
        initial: { history: "{}", schema: "{}", forest: "{}", detached: "{}" },
        settled: { history: "{}", schema: "{}", forest: "{}", detached: "{}" },
      },
    },
  };
}

function mapFieldCaseFixture() {
  const scenarioIds = [
    "set-absent",
    "replace-present",
    "delete-present",
    "delete-absent",
    "different-keys",
    "same-key-set-set-left-last",
    "same-key-set-set-right-last",
    "same-key-set-delete",
    "same-key-delete-set",
    "nested-edit-vs-replace",
    "nested-edit-vs-delete",
    "nested-map-independent",
    "nested-map-conflict",
  ];
  const schema = JSON.stringify({
    version: 2,
    nodes: {
      "org.watershed.shared-tree.m2.DynamicMap": {
        kind: { map: { kind: "Optional", types: ["com.fluidframework.leaf.string"] } },
      },
      "org.watershed.shared-tree.m2.Root": {
        kind: {
          object: {
            fields: {
              items: {
                kind: "Value",
                types: ["org.watershed.shared-tree.m2.DynamicMap"],
              },
            },
          },
        },
      },
    },
    root: { kind: "Value", types: ["org.watershed.shared-tree.m2.Root"] },
  });
  const root = {
    kind: "object",
    type: "org.watershed.shared-tree.m2.Root",
    fields: [[
      "items",
      {
        kind: "object",
        type: "org.watershed.shared-tree.m2.DynamicMap",
        fields: [],
      },
    ]],
  };
  const state = { entries: [], detached: [] };
  const encodedChange = {
    maxId: 0,
    changes: [{
      fieldKey: "rootFieldKey",
      fieldKind: "ModularEditBuilder.Generic",
      change: [[0, {
        fieldChanges: [{
          fieldKey: "items",
          fieldKind: "ModularEditBuilder.Generic",
          change: [[0, {
            fieldChanges: [{
              fieldKey: "key",
              fieldKind: "Optional",
              change: { r: { e: true, d: 0 } },
            }],
          }]],
        }],
      }]],
    }],
  };
  const delta = {
    latestRevision: null,
    fields: [[
      "rootFieldKey",
      {
        marks: [{
          count: 1,
          attach: null,
          detach: null,
          fields: [],
        }],
      },
    ]],
    build: [],
    refreshers: [],
    global: [],
    rename: [],
    destroy: [],
  };
  const change = (id, revision) => ({
    id,
    revision,
    encodingContext: {
      originatorId: "11111111-1111-4111-8111-111111111111",
      revision,
      encodedRevision: revision === null ? null : 1,
      isSummary: false,
    },
    encoded: structuredClone(encodedChange),
  });
  const scenario = (id) => {
    const conflict = !["set-absent", "replace-present", "delete-present", "delete-absent"]
      .includes(id);
    const changes = [
      change("left", "left-revision"),
      ...(conflict ? [change("right", "right-revision")] : []),
      change("composed", null),
      change("inverted", "inverse-revision"),
      ...(conflict
        ? [
          change("left-over-right", "left-revision"),
          change("right-over-left", "right-revision"),
        ]
        : []),
    ];
    const operations = [
      { operation: "compose", changes: conflict ? ["left", "right"] : ["left"], output: "composed" },
      {
        operation: "invert",
        change: "composed",
        inverseRevision: "inverse-revision",
        output: "inverted",
      },
      ...(conflict
        ? [
          {
            operation: "rebase-left-over-right",
            change: "left",
            over: "right",
            revisionMetadata: [
              { revision: "left-revision" },
              { revision: "right-revision" },
            ],
            output: "left-over-right",
          },
          {
            operation: "rebase-right-over-left",
            change: "right",
            over: "left",
            revisionMetadata: [
              { revision: "left-revision" },
              { revision: "right-revision" },
            ],
            output: "right-over-left",
          },
        ]
        : []),
    ];
    const replay = (operation) => {
      switch (operation) {
        case "compose":
          return ["initial", "composed"];
        case "invert":
          return ["initial", "composed", "inverted"];
        case "rebase-left-over-right":
          return ["initial", "right", "left-over-right"];
        case "rebase-right-over-left":
          return ["initial", "left", "right-over-left"];
        default:
          throw new Error(`Unknown synthetic operation: ${operation}`);
      }
    };
    return {
      input: {
        id,
        initial: { schema, root },
        compressor: {
          localSessionId: "11111111-1111-4111-8111-111111111111",
          revisions: changes
            .filter(({ revision }) => revision !== null)
            .map(({ revision, encodingContext }) => ({
              stable: revision,
              encoded: encodingContext.encodedRevision,
            })),
        },
        changes,
        operations: operations.map(({ operation }) => operation),
        algebra: operations,
        finalOperation: "compose",
      },
      observation: {
        id,
        initial: structuredClone(state),
        intermediate: operations.map(({ operation, output }) => ({
          operation,
          encoded: changes.find(({ id: changeId }) => changeId === output).encoded,
          checkpoints: replay(operation).map((checkpoint) => ({
            id: checkpoint,
            visible: structuredClone(state),
          })),
          final: structuredClone(state),
        })),
        final: structuredClone(state),
        ...(["nested-edit-vs-replace", "nested-edit-vs-delete"].includes(id)
          ? { detachedIdentity: [{ revision: "revision", localId: 0 }] }
          : {}),
      },
      raw: {
        id,
        changes: Object.fromEntries(changes.map((item) => [item.id, {
          revision: item.revision,
          encodingContext: item.encodingContext,
          encoded: item.encoded,
        }])),
        operations: operations.map(({ operation, output }) => ({
          operation,
          actions: replay(operation).map((action) => ({
            id: action,
            forest: {
              fields: [["rootFieldKey", [structuredClone(root)]]],
            },
            detachedIndex: [],
            ...(action === "initial" ? {} : { delta: structuredClone(delta) }),
          })),
        })),
        fieldKeys: ["key"],
        fieldKinds: ["Optional"],
      },
    };
  };
  const scenarios = scenarioIds.map(scenario);
  return {
    formatVersion: 1,
    reference: {
      package: "@fluidframework/tree",
      version: "3.1.0",
      commit: "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960",
    },
    id: "map-field-algebra",
    domain: "field",
    input: {
      profile: { modularChange: 5, optionalField: 2, genericField: 1 },
      schema,
      scenarios: scenarios.map((item) => item.input),
    },
    expected: {
      observations: scenarios.map((item) => item.observation),
    },
    raw: {
      scenarios: scenarios.map((item) => item.raw),
    },
  };
}

function mapSchemaCaseFixture() {
  const schema = JSON.stringify({
    version: 2,
    nodes: {
      "org.watershed.shared-tree.m2.DynamicMap": {
        kind: { map: { kind: "Optional", types: ["com.fluidframework.leaf.string"] } },
      },
    },
    root: { kind: "Value", types: ["org.watershed.shared-tree.m2.DynamicMap"] },
  });
  const keys = ["", "2", "10", "01", "__proto__", "é", "水"];
  return {
    formatVersion: 1,
    reference: {
      package: "@fluidframework/tree",
      version: "3.1.0",
      commit: "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960",
    },
    id: "map-schema-content",
    domain: "schema",
    input: {
      profile: { schema: 2, forest: 2 },
      schemas: {
        named: schema,
        recursive: schema,
        rootMap: schema,
        objectContainedMap: schema,
      },
      keys,
      content: { empty: {}, populated: {} },
    },
    expected: {
      observations: [{
        id: "schema-and-content",
        keys,
        entries: keys.map((key) => [key, key]),
      }],
    },
    raw: {
      schemas: Object.fromEntries(["named", "recursive", "rootMap", "objectContainedMap"]
        .map((name) => [name, { bytes: schema, parsed: JSON.parse(schema) }])),
      forest: { empty: "empty", populated: "populated" },
      summaries: {},
    },
  };
}

function mapHistoryCaseFixture() {
  const message = JSON.stringify({ version: 7, originatorId: "session", changeset: [{}] });
  const state = { pending: [1], sequenced: [2], longestBranchLength: 1 };
  return {
    formatVersion: 1,
    reference: {
      package: "@fluidframework/tree",
      version: "3.1.0",
      commit: "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960",
    },
    id: "map-history-codecs",
    domain: "codec",
    input: {
      profile: {
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
      },
      actions: ["set"],
      messageBytes: { set: message, replacement: message, delete: message },
      modularBytes: { map: "[{}]", nestedMap: "[{}]" },
      history: { pending: state, sequenced: { ...state, pending: [] } },
    },
    expected: {
      observations: [
        { id: "messages" },
        { id: "history" },
        { id: "detached-after-replacement" },
        { id: "detached-after-deletion" },
        { id: "reconnect-resubmission" },
        { id: "refreshers-after-replacement" },
        { id: "refreshers-after-deletion" },
        { id: "reload-and-edit" },
      ],
    },
    raw: {
      messages: {},
      modular: {},
      detached: {
        afterReplacement: { removed: [{}] },
        afterDeletion: { removed: [{}] },
      },
      reconnect: [{}],
      refreshers: {
        replacement: { refreshers: {} },
        deletion: { refreshers: {} },
      },
      summary: { bytes: "{}" },
      reload: { messages: [{}] },
    },
  };
}

test("map field validation rejects a missing scenario", () => {
  const validMapCase = mapFieldCaseFixture();
  assert.doesNotThrow(() => generator.validateMapFieldCase(validMapCase));
  const broken = structuredClone(validMapCase);
  broken.input.scenarios.pop();
  assert.throws(() => generator.validateMapFieldCase(broken), /scenario/i);
});

test("map history validation requires replacement and deletion refreshers", () => {
  const validMapCase = mapHistoryCaseFixture();
  assert.doesNotThrow(() => generator.validateMapHistoryCase(validMapCase));
  delete validMapCase.raw.refreshers.deletion;
  assert.throws(() => generator.validateMapHistoryCase(validMapCase), /refresher/i);
});

test("map field validation requires detached identity observations", () => {
  const validMapCase = mapFieldCaseFixture();
  assert.doesNotThrow(() => generator.validateMapFieldCase(validMapCase));
  delete validMapCase.expected.observations
    .find(({ id }) => id === "nested-edit-vs-delete").detachedIdentity;
  assert.throws(() => generator.validateMapFieldCase(validMapCase), /detached/i);
});

test("map field validation requires every rebase observation", () => {
  const validMapCase = mapFieldCaseFixture();
  assert.doesNotThrow(() => generator.validateMapFieldCase(validMapCase));
  const observation = validMapCase.expected.observations
    .find(({ id }) => id === "same-key-set-set-right-last");
  observation.intermediate = observation.intermediate
    .filter(({ operation }) => operation !== "rebase-right-over-left");
  assert.throws(() => generator.validateMapFieldCase(validMapCase), /rebase.*observation/i);
});

test("map field validation requires encoded changes and paired raw payloads", () => {
  for (const mutate of [
    (value) => {
      delete value.input.scenarios[0].changes
        .find(({ id }) => id === "composed").encoded;
    },
    (value) => {
      delete value.raw.scenarios[0].changes.composed;
    },
  ]) {
    const validMapCase = mapFieldCaseFixture();
    assert.doesNotThrow(() => generator.validateMapFieldCase(validMapCase));
    mutate(validMapCase);
    assert.throws(() => generator.validateMapFieldCase(validMapCase), /encoded|raw payload/i);
  }
});

test("map field validation rejects empty encoded payloads even when raw copies match", () => {
  const validMapCase = mapFieldCaseFixture();
  assert.doesNotThrow(() => generator.validateMapFieldCase(validMapCase));
  const scenario = validMapCase.input.scenarios[0];
  const change = scenario.changes.find(({ id }) => id === "composed");
  change.encoded = {};
  validMapCase.raw.scenarios[0].changes.composed.encoded = {};
  validMapCase.expected.observations[0].intermediate
    .find(({ operation }) => operation === "compose").encoded = {};
  assert.throws(
    () => generator.validateMapFieldCase(validMapCase),
    /ModularChange payload/i,
  );
});

test("map field validation requires raw replay forest evidence", () => {
  const validMapCase = mapFieldCaseFixture();
  assert.doesNotThrow(() => generator.validateMapFieldCase(validMapCase));
  delete validMapCase.raw.scenarios[0].operations[0].actions[0].forest;
  assert.throws(
    () => generator.validateMapFieldCase(validMapCase),
    /raw replay forest/i,
  );
});

test("map field validation requires raw replay detached-index evidence", () => {
  const validMapCase = mapFieldCaseFixture();
  assert.doesNotThrow(() => generator.validateMapFieldCase(validMapCase));
  delete validMapCase.raw.scenarios[0].operations[0].actions[0].detachedIndex;
  assert.throws(
    () => generator.validateMapFieldCase(validMapCase),
    /raw replay detached index/i,
  );
});

test("map field validation requires raw replay apply delta evidence", () => {
  const validMapCase = mapFieldCaseFixture();
  assert.doesNotThrow(() => generator.validateMapFieldCase(validMapCase));
  delete validMapCase.raw.scenarios[0].operations[0].actions[1].delta;
  assert.throws(
    () => generator.validateMapFieldCase(validMapCase),
    /raw replay apply delta/i,
  );
});

test("map field validation requires final visible map state", () => {
  const validMapCase = mapFieldCaseFixture();
  assert.doesNotThrow(() => generator.validateMapFieldCase(validMapCase));
  delete validMapCase.expected.observations[0].final.entries;
  assert.throws(() => generator.validateMapFieldCase(validMapCase), /final/i);
});

test("tree codec case validator requires complete replayable evidence", () => {
  assert.doesNotThrow(() => generator.validateCodecCase(codecCaseFixture()));
});

test("tree codec case validator rejects missing context and observations", () => {
  for (const mutate of [
    (value) => { delete value.input.scenarios[0].compressor; },
    (value) => { value.input.scenarios[0].messages = []; },
    (value) => { delete value.raw.blobs.initial.detached; },
    (value) => { value.expected.observations = []; },
    (value) => { value.input.fieldBatches[0].encoded.version = 99; },
    (value) => { value.input.scenarios.push(structuredClone(value.input.scenarios[0])); },
  ]) {
    const value = codecCaseFixture();
    mutate(value);
    assert.throws(() => generator.validateCodecCase(value), /tree-codecs/);
  }
});

test("corpus requires the tree codecs case", () => {
  assert.equal(requiredCases.length, 29);
  assert(requiredCases.some(([id, domain]) => id === "tree-codecs" && domain === "codec"));
});

test("corpus validation requires independent container and summary foundations", () => {
  const originalCases = cases(["container-foundations", "summary-foundations"]);
  assert.throws(() => validateCases(originalCases), /Missing case: container-foundations/);
});

test("field corpus requires independently replayable expanded operations", () => {
  const corpus = cases(["container-foundations", "summary-foundations"]);
  delete corpus.find(({ id }) => id === "field-compose-invert-rebase").input.expanded;
  assert.throws(() => validateCases(corpus), /field-compose-invert-rebase.*expanded/);
});

test("modular corpus includes replayable identity state and forest observations", () => {
  const corpus = cases();
  const fixture = corpus.find(({ id }) => id === "modular-nested-algebra");
  assert(fixture.input.expanded, "modular input must include expanded evidence");
  assert(fixture.input.expanded.changes.first.aliases.length > 0);
  assert(fixture.input.expanded.changes.first.parents.length > 0);
  assert(fixture.input.expanded.scenarios.length > 0);
  assert.doesNotThrow(() => validateCases(corpus));
  delete fixture.input.expanded.changes.first.aliases;
  assert.throws(() => validateCases(corpus), /modular-nested-algebra/);
});

test("modular corpus rejects incomplete operations and retained identity observations", () => {
  for (const mutate of [
    (fixture) => { delete fixture.input.expanded; },
    (fixture) => { delete fixture.input.expanded.changes.first.parents; },
    (fixture) => { fixture.input.expanded.changes.first.crossFieldKeys = []; },
    (fixture) => { fixture.input.expanded.revisions[0].stable = "not-a-revision"; },
    (fixture) => { fixture.input.expanded.operations[0].op = "unknown"; },
    (fixture) => { fixture.input.expanded.operations[0].revision = "unknown"; },
    (fixture) => { fixture.input.expanded.operations.find(({ op }) => op === "compose").changes = ["missing"]; },
    (fixture) => { delete fixture.input.expanded.operations.find(({ op }) => op === "invert").isRollback; },
    (fixture) => { fixture.input.expanded.operations.find(({ op }) => op === "rebase").revisionMetadata = []; },
    (fixture) => { fixture.input.expanded.operations.find(({ op }) => op === "refreshers").repair[0].trees = null; },
    (fixture) => { fixture.input.expanded.scenarios.pop(); },
    (fixture) => { fixture.input.expanded.scenarios[0].actions[1].change = "missing"; },
    (fixture) => { fixture.expected.observations[6].change.fields[0][1].children[0][0] = 1; },
    (fixture) => { delete fixture.expected.observations[6].delta.global; },
    (fixture) => { fixture.expected.observations[6].delta.fields[0][1].marks[0].count = -1; },
    (fixture) => { fixture.expected.observations[6].delta.build[0].id.localId = "zero"; },
    (fixture) => { fixture.expected.observations[6].delta.build[0].trees = []; },
    (fixture) => { fixture.expected.observations.find(({ operation }) => operation === "modular-forest").checkpoints.pop(); },
    (fixture) => { delete fixture.expected.observations.at(-1).checkpoints[0].state.detached; },
    (fixture) => {
      fixture.expected.observations.find(({ operation }) => operation === "modular-forest")
        .checkpoints[0].state.references[0].value = { kind: "unknown" };
    },
    (fixture) => {
      fixture.expected.observations.find(({ operation }) => operation === "modular-forest")
        .checkpoints[1].state.detached[0].latestRelevantRevision = "not-a-revision";
    },
  ]) {
    const corpus = cases();
    mutate(corpus.find(({ id }) => id === "modular-nested-algebra"));
    assert.throws(() => validateCases(corpus), /modular-nested-algebra/);
  }
});

test("modular evidence covers optional roots and repeated detached-child rebasing", () => {
  const fixture = cases().find(({ id }) => id === "modular-nested-algebra");
  const operations = new Map(fixture.input.expanded.operations.map((entry) => [entry.id, entry]));
  assert.equal(operations.get("optional-root-set")?.root, null);
  assert.equal(operations.get("optional-root-clear")?.value, null);
  assert.deepEqual(operations.get("optional-root-null")?.value, { kind: "null" });
  assert.equal(operations.get("delayed-after-two-parents")?.change, "x-over-parent");
  assert.equal(operations.get("delayed-after-two-parents")?.over, "parent-again");
  assert.deepEqual(operations.get("nested-reversed")?.changes, ["child-y", "child-x"]);
  const final = fixture.expected.observations.find(({ id }) => id === "replace-twice-then-delayed");
  assert(final, "missing repeated-replacement forest evidence");
  const retained = final.checkpoints.at(-1).state.references.find(({ name }) => name === "old-point");
  assert.equal(retained.status, "detached");
  assert.deepEqual(retained.value.fields.find(([key]) => key === "x")[1], { kind: "number", value: 42 });
});

test("modular evidence distinguishes root names and compressed revision order", () => {
  const fixture = cases().find(({ id }) => id === "modular-nested-algebra");
  const operations = new Map(fixture.input.expanded.operations.map((entry) => [entry.id, entry]));
  assert.deepEqual(operations.get("root-named-child")?.path, ["rootFieldKey"]);
  const left = operations.get("nonlexical-left");
  const right = operations.get("nonlexical-right");
  assert(left && right, "missing nonlexical revision evidence");
  assert(left.revision < right.revision);
  const revisions = new Map(fixture.input.expanded.revisions.map(({ stable, encoded }) => [stable, encoded]));
  assert(revisions.get(left.revision) > revisions.get(right.revision));
  const inverse = fixture.expected.observations.find(({ id }) => id === "nonlexical-undo");
  const root = inverse.delta.fields.find(([key]) => key === "rootFieldKey")[1].marks[0];
  const detach = (side) => root.fields.find(([key]) => key === side)[1].marks[0]
    .fields.find(([key]) => key === "x")[1].marks[0].detach.localId;
  assert.equal(detach("right"), 8);
  assert.equal(detach("left"), 9);
  const nested = fixture.expected.observations.find(({ id }) => id === "nested-global-order");
  assert.deepEqual(nested.delta.global.map(({ id }) => id.localId), [20, 10]);
});

test("history corpus requires the complete source-backed schedule matrix", () => {
  const corpus = cases();
  const fixture = corpus.find(({ id }) => id === "history-reconciliation");
  assert.equal(fixture.domain, "history");
  assert.equal(fixture.input.schedules.length, 16);
  assert.equal(fixture.expected.observations.length, 16);
  assert.doesNotThrow(() => validateCases(corpus));
});

test("history corpus rejects incomplete allocation, branch, point, and checkpoint evidence", () => {
  for (const mutate of [
    (value) => { delete value.input.schedules[0].actions[0].allocations; },
    (value) => {
      const peer = value.expected.observations
        .flatMap(({ checkpoints }) => checkpoints)
        .flatMap(({ history }) => history.sequenced.peers)[0];
      delete peer.base;
    },
    (value) => {
      delete value.input.schedules
        .flatMap(({ actions }) => actions)
        .find(({ op }) => op === "receive").point;
    },
    (value) => { value.expected.observations[1].checkpoints.splice(2, 1); },
    (value) => { delete value.expected.observations[0].checkpoints[0].forest.detached; },
    (value) => {
      value.input.schedules
        .find(({ label }) => label === "resubmit-detached-repair")
        .actions.at(-1).repair[0].builds = [];
    },
  ]) {
    const corpus = cases();
    mutate(corpus.find(({ id }) => id === "history-reconciliation"));
    assert.throws(() => validateCases(corpus), /history-reconciliation/);
  }
});

test("field corpus refuses incomplete operations, callbacks, identities and observations", () => {
  for (const mutate of [
    (value) => { value.input.operations.compose = null; },
    (value) => { value.input.operations.invert.change = "missing"; },
    (value) => { value.input.operations.invert.isRollback = "false"; },
    (value) => { value.input.expanded.compose.pop(); },
    (value) => { delete value.input.expanded.compose[0].first; },
    (value) => { value.input.expanded.compose[0].childCallback.selector = "unknown"; },
    (value) => { value.input.expanded.invert[0].maxLocalId = -2; },
    (value) => { value.input.expanded.rebase[0].outputRevision = 99; },
    (value) => { value.input.expanded.rebase[0].over.data.c = [[null, null]]; },
    (value) => { delete value.input.expanded.intoDelta.childDelta.field; },
    (value) => { value.input.expanded.replaceRevisions.obsolete = [99]; },
    (value) => { value.input.expanded.invalidMappings.pop(); },
    (value) => { value.input.expanded.invalidMappings[0].change.moves[1][0].localId = 36; },
    (value) => { value.input.expanded.invalidMappings[2].change.childChanges = []; },
    (value) => { value.expected.observations.pop(); },
    (value) => { value.expected.observations.reverse(); },
    (value) => { delete value.expected.observations[7].callbacks; },
    (value) => { delete value.expected.observations[13].allocator.after; },
    (value) => { delete value.raw.encoded.richRevisionChange; },
  ]) {
    const corpus = cases(["container-foundations", "summary-foundations"]);
    mutate(corpus.find(({ id }) => id === "field-compose-invert-rebase"));
    assert.throws(() => validateCases(corpus), /field-compose-invert-rebase/);
  }
});

test("manifest records complete native runners and actual wire field kinds", async (t) => {
  const output = await mkdtemp(join(tmpdir(), "watershed-wire-inventory-"));
  t.after(() => rm(output, { recursive: true, force: true }));
  const corpus = cases();
  const profile = JSON.parse(readFileSync(
    new URL("../../test/fixtures/shared_tree/profile.json", import.meta.url), "utf8",
  ));
  const smoke = {
    formatVersion: 1,
    reference: profile.reference,
    kind: "source-smoke",
    minVersionForCollab: profile.container.oldestSupportedClient,
    messages: corpus.find(({ id }) => id === "batched-commits").raw.messages,
    codecTree: profile.codecTree,
    compressor: "unused-by-manifest",
    compressorFormat: profile.compressorFormat,
    summary: corpus.find(({ id }) => id === "schema-profile").raw.summary,
    observations: { pending: [1, 2], settled: [2, 2] },
  };
  await writeCorpus(output, corpus, smoke);
  const manifest = JSON.parse(readFileSync(join(output, "manifest.json"), "utf8"));
  assert.deepEqual(manifest.inventory.observedFieldKinds,
    ["ModularEditBuilder.Generic", "Optional", "Value"]);
  for (const target of ["javascript", "erlang"]) {
    assert.deepEqual(manifest.nativeSemanticRunners[target], [
      "id-ranges", "schema-validation", "forest-delta",
      "field-compose-invert-rebase", "modular-nested-algebra",
      "container-foundations", "summary-foundations",
      "history-reconciliation", "tree-codecs", "tree-kernel",
      "bootstrap-map-handles", "batched-commits",
    ]);
  }
});

test("corpus validation requires every named case and nonempty observations", () => {
  assert.equal(requiredCases.length, 29);
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
