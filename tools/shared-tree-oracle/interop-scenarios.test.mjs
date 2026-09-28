import assert from "node:assert/strict";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import {
  commitKinds,
  decodeReconnectPayload,
  decodeTreeSubmissions,
  decodedEvidence,
  executeScheduleAction,
  freshReload,
  interceptedTreeMessageCount,
  generateSchedules,
  nativeAdapter,
  matchReconnectOperations,
  reconciledRaceCheckpoint,
  requiredFailureCells,
  requiredSchemaRaceCells,
  requiredScenarioCells,
  replayFailure,
  sameReplayFailure,
  settle,
  upstreamAdapter,
  runDeterministicCases,
  runFailureCases,
  runSchemaCompatibility,
  runSchemaRaces,
  runSchemaReconnect,
  runSeededSchedule,
  validateReplayArtifact,
  waitForGapRepair,
  waitForRemoteNotifications,
  writeSeededFailure,
} from "./interop-scenarios.mjs";
import { initialMapRoot } from "./schema.mjs";

function positionalStoredSchema(label) {
  return "FixedSchema(StoredSchema(Repository("
    + 'FieldSchema(Required, ["root"]), dict.from_list([]), '
    + 'ComparisonField(RequiredKind, ["root"]), dict.from_list([]), '
    + `VObject([#("label", VString("${label}"))]), True)))`;
}

function namedStoredSchema(label) {
  return "FixedSchema(StoredSchema("
    + `persisted: VObject([#("label", VString("${label}"))]), `
    + "profile_supported: True))";
}

test("combined schema and data changes retain both kinds", () => {
  assert.deepEqual(commitKinds({
    changeset: [{ schema: { old: {}, new: {} }, data: { changes: [] } }],
  }), ["schema", "data"]);
});

test("race polling waits for every client and the loser's empty changeset", () => {
  const checkpoint = {
    observations: [
      {
        implementation: "upstream",
        sequenceNumber: 12,
        events: [{ kind: "schema" }],
        history: { pending: [] },
      },
      {
        implementation: "javascript",
        sequenceNumber: 12,
        events: [{ kind: "data" }],
        history: {
          pending: [{ changeset: { changeCount: 0, raw: "Changeset([])" } }],
        },
      },
      {
        implementation: "erlang",
        sequenceNumber: 11,
        events: [],
        history: { pending: [] },
      },
    ],
  };
  assert.equal(reconciledRaceCheckpoint(checkpoint, "javascript", 12), false);
  checkpoint.observations[2].sequenceNumber = 12;
  assert.equal(reconciledRaceCheckpoint(checkpoint, "javascript", 12), true);
  checkpoint.observations[1].history.pending[0].changeset.changeCount = 1;
  assert.equal(reconciledRaceCheckpoint(checkpoint, "javascript", 12), false);
});

test("reconnect matching is one-to-one by semantic content and originator", () => {
  const oldSchema = {
    version: 2,
    metadata: { scope: "document" },
    nodes: {
      "com.fluidframework.leaf.number": { kind: { leaf: 0 } },
      "com.fluidframework.leaf.string": { kind: { leaf: 1 } },
      "org.watershed.shared-tree.m4.Root": {
        kind: {
          object: {
            title: {
              kind: "Value",
              types: ["com.fluidframework.leaf.string"],
            },
          },
        },
      },
    },
    root: {
      kind: "Value",
      types: ["org.watershed.shared-tree.m4.Root"],
    },
  };
  const newSchema = structuredClone(oldSchema);
  newSchema.nodes["org.watershed.shared-tree.m4.Root"].kind.object.score = {
    kind: "Optional",
    types: ["com.fluidframework.leaf.number"],
  };
  const originals = [
    {
      revision: "local-schema",
      originatorId: "origin",
      payload: [{ schema: { old: oldSchema, new: newSchema } }],
    },
    {
      revision: "local-data",
      originatorId: "origin",
      payload: [{ data: { path: ["score"], value: 81 } }],
    },
  ];
  const accepted = [
    {
      revision: 41,
      originatorId: "origin",
      payload: [{ schema: { old: oldSchema, new: newSchema } }],
    },
    {
      revision: 42,
      originatorId: "origin",
      payload: [{ data: { path: ["score"], value: 81 } }],
    },
  ];
  assert.deepEqual(matchReconnectOperations(originals, accepted), [
    { originalRevision: "local-schema", acceptedRevision: 41 },
    { originalRevision: "local-data", acceptedRevision: 42 },
  ]);
  assert.throws(() => matchReconnectOperations(originals, [
    accepted[0],
    { ...accepted[0], revision: 43 },
  ]), /one-to-one|unmatched/i);
  {
    const changedType = structuredClone(accepted);
    changedType[0].payload[0].schema.new.nodes[
      "org.watershed.shared-tree.m4.Root"
    ].kind.object.score.types = ["com.fluidframework.leaf.string"];
    assert.throws(
      () => matchReconnectOperations(originals, changedType),
      /one-to-one|unmatched/i,
    );
  }
  {
    const removedTitle = structuredClone(accepted);
    delete removedTitle[0].payload[0].schema.new.nodes[
      "org.watershed.shared-tree.m4.Root"
    ].kind.object.title;
    assert.throws(
      () => matchReconnectOperations(originals, removedTitle),
      /one-to-one|unmatched/i,
    );
  }
  assert.throws(() => matchReconnectOperations(originals, [
    accepted[1],
    accepted[0],
  ]), /order/i);
  assert.throws(() => matchReconnectOperations(originals, [
    accepted[0],
    { ...accepted[1], payload: [{ data: { path: ["score"], value: 999 } }] },
  ]), /one-to-one|unmatched/i);
  assert.throws(() => matchReconnectOperations(originals, [
    ...accepted,
    {
      revision: 43,
      originatorId: "other",
      payload: [{ data: { path: ["title"], value: "unrelated" } }],
    },
  ]), /one-to-one|unrelated/i);
});

test("native schema diagnostics reject compact stored-schema shorthand", () => {
  assert.throws(
    () => decodeReconnectPayload(
      'Changeset([SchemaChange(FixedSchema(#("title", Required)), '
        + 'FixedSchema([#("title", Required), #("score", Optional)]), False)])',
    ),
    /invalid|requires|schema|unsupported/i,
  );
});

test("native schema diagnostics reject schema-state aliases", () => {
  assert.throws(
    () => decodeReconnectPayload(
      "Changeset([SchemaChange(v1, optional, False)])",
    ),
    /invalid|requires|schema|unsupported/i,
  );
});

test("native persisted data diagnostics decode exponential numbers", () => {
  assert.deepEqual(
    decodeReconnectPayload(
      'Changeset([DataChange(Changeset(ChangeData('
        + '2, [], [#("score", OptionalField(FieldChange([], [], '
        + "Some(Replacement(False, Some(Detached(AtomId(None, 0))), "
        + "AtomId(None, 1))))))], [], [], [], "
        + "[Build(AtomId(None, 0), [NumberValue(1.0e3)])], [], [], []), "
        + "IdentityOrder([]), []))])",
    ),
    { kind: "data", field: "score", value: 1000 },
  );
});

test("native named data diagnostics decode complete changesets", () => {
  assert.deepEqual(
    decodeReconnectPayload(
      "Changeset([DataChange(Changeset("
        + "data: ChangeData(max_local_id: 2, revisions: [], "
        + 'fields: [#("score", OptionalField(FieldChange(moves: [], '
        + "child_changes: [], replacement: Some(Replacement(was_empty: False, "
        + "source: Some(Detached(AtomId(revision: None, local_id: 0))), "
        + "detach_id: AtomId(revision: None, local_id: 1))))))], "
        + "nodes: [], parents: [], aliases: [], "
        + "builds: [Build(id: AtomId(revision: None, local_id: 0), "
        + "trees: [NumberValue(1000)])], destroys: [], refreshers: [], "
        + "cross_field_keys: []), identity_order: IdentityOrder([]), "
        + "cross_field_keys: []))])",
    ),
    { kind: "data", field: "score", value: 1000 },
  );
});

test("native persisted diagnostics reject empty replacement without source", () => {
  assert.throws(
    () => decodeReconnectPayload(
      'Changeset([DataChange(Changeset(ChangeData('
        + '1, [], [#("score", OptionalField(FieldChange([], [], '
        + "Some(Replacement(True, None, AtomId(None, 0))))))], "
        + "[], [], [], "
        + "[Build(AtomId(None, 0), [NumberValue(1000)])], [], [], []), "
        + "IdentityOrder([]), []))])",
    ),
    /non-substantive|attach|built value/i,
  );
});

test("native named diagnostics reject replacement from active register", () => {
  assert.throws(
    () => decodeReconnectPayload(
      "Changeset([DataChange(Changeset("
        + "data: ChangeData(max_local_id: 1, revisions: [], "
        + 'fields: [#("score", OptionalField(FieldChange(moves: [], '
        + "child_changes: [], replacement: Some(Replacement(was_empty: True, "
        + "source: Some(Active), "
        + "detach_id: AtomId(revision: None, local_id: 0))))))], "
        + "nodes: [], parents: [], aliases: [], "
        + "builds: [Build(id: AtomId(revision: None, local_id: 0), "
        + "trees: [NumberValue(1000)])], destroys: [], refreshers: [], "
        + "cross_field_keys: []), identity_order: IdentityOrder([]), "
        + "cross_field_keys: []))])",
    ),
    /non-substantive|attach|built value/i,
  );
});

test("native persisted diagnostics accept optional insertion from detached register", () => {
  assert.deepEqual(
    decodeReconnectPayload(
      'Changeset([DataChange(Changeset(ChangeData('
        + '2, [], [#("score", OptionalField(FieldChange([], [], '
        + "Some(Replacement(True, Some(Detached(AtomId(None, 0))), "
        + "AtomId(None, 1))))))], [], [], [], "
        + "[Build(AtomId(None, 0), [NumberValue(1000)])], [], [], []), "
        + "IdentityOrder([]), []))])",
    ),
    { kind: "data", field: "score", value: 1000 },
  );
});

test("native persisted diagnostics reject one-argument data changesets", () => {
  assert.throws(
    () => decodeReconnectPayload(
      'Changeset([DataChange(Changeset(ChangeData('
        + '2, [], [#("score", OptionalField(FieldChange([], [], '
        + "Some(Replacement(False, Some(Detached(AtomId(None, 0))), "
        + "AtomId(None, 1))))))], [], [], [], "
        + "[Build(AtomId(None, 0), [NumberValue(1000)])], [], [])))])",
    ),
    /invalid|arguments|identity.order/i,
  );
});

test("native persisted diagnostics reject fabricated constructor shortcuts", () => {
  assert.throws(
    () => decodeReconnectPayload(
      'Changeset([DataChange(Changeset(ChangeData('
        + '[#("score", OptionalField(FieldChange()))], '
        + '[Build(AtomId(0), [NumberValue(1000)])])))])',
    ),
    /invalid|arguments|replacement/i,
  );
});

test("native persisted diagnostics reject operation-shaped arbitrary text", () => {
  assert.throws(
    () => decodeReconnectPayload(
      'Changeset([DataChange(invented #("score", OptionalField) '
        + "NumberValue(1000))])",
    ),
    /invalid|unsupported|exactly|operation/i,
  );
});

test("native persisted diagnostics reject unknown nested constructors", () => {
  assert.throws(
    () => decodeReconnectPayload(
      'Changeset([DataChange(Changeset(ChangeData('
        + 'Invented(#("score", OptionalField(Bogus())), NumberValue(1000))'
        + ")))])",
    ),
    /invalid|unsupported|constructor|operation/i,
  );
});

test("native schema diagnostics retain escaped quotes while scanning arguments", () => {
  const decoded = decodeReconnectPayload(
    `Changeset([SchemaChange(${positionalStoredSchema('ti\\"tle, old')}, `
      + `${positionalStoredSchema('ti\\"tle, new')}, False)])`,
  );
  assert.equal(decoded.kind, "schema");
  assert.match(decoded.old, /ti\\"tle,old/);
  assert.match(decoded.new, /ti\\"tle,new/);
});

test("native named outer changesets decode schema operations", () => {
  const before = namedStoredSchema("before");
  const after = namedStoredSchema("after");
  assert.deepEqual(
    decodeReconnectPayload(
      `Changeset(changes: [SchemaChange(before: ${before}, `
        + `after: ${after}, is_inverse: False)])`,
    ),
    {
      kind: "schema",
      old: { label: "before" },
      new: { label: "after" },
    },
  );
});

test("native persisted data diagnostics decode exponential numbers", () => {
  assert.deepEqual(
    decodeReconnectPayload(
      'Changeset([DataChange(Changeset(ChangeData('
        + '[#("score", OptionalField(FieldChange()))], '
        + '[Build(AtomId(1), [NumberValue(1.0e3)])])))])',
    ),
    { kind: "data", field: "score", value: 1000 },
  );
});

test("native named data diagnostics decode complete changesets", () => {
  assert.deepEqual(
    decodeReconnectPayload(
      "Changeset([DataChange(Changeset("
        + "data: ChangeData(max_local_id: 2, "
        + 'fields: [#("score", OptionalField(FieldChange()))], '
        + "builds: [Build(AtomId(1), [NumberValue(1000)])]), "
        + "identity_order: IdentityOrder([])))])",
    ),
    { kind: "data", field: "score", value: 1000 },
  );
});

test("native persisted diagnostics reject operation-shaped arbitrary text", () => {
  assert.throws(
    () => decodeReconnectPayload(
      'Changeset([DataChange(invented #("score", OptionalField) '
        + "NumberValue(1000))])",
    ),
    /invalid|unsupported|exactly|operation/i,
  );
});

test("native schema diagnostics retain escaped quotes while scanning arguments", () => {
  assert.deepEqual(
    decodeReconnectPayload(
      'Changeset([SchemaChange(FixedSchema(#("ti\\"tle, old", Required)), '
        + 'FixedSchema(#("ti\\"tle, new", Optional)), False)])',
    ),
    {
      kind: "schema",
      old: 'FixedSchema(#("ti\\"tle,old",Required))',
      new: 'FixedSchema(#("ti\\"tle,new",Optional))',
    },
  );
});

test("native named outer changesets decode schema operations", () => {
  assert.deepEqual(
    decodeReconnectPayload(
      'Changeset(changes: [SchemaChange(FixedSchema(#("title", Required)), '
        + 'FixedSchema([#("title", Required), #("score", Optional)]), False)])',
    ),
    {
      kind: "schema",
      old: 'FixedSchema(#("title",Required))',
      new: 'FixedSchema([#("title",Required),#("score",Optional)])',
    },
  );
});

test("reconnect schema matching canonicalizes runtime and stored schema forms", () => {
  const runtimeSchema = (includeScore) => ({
    nodeSchema: {
      type: "Map",
      entries: [
        ["com.fluidframework.leaf.number", { leafValue: 0 }],
        ["com.fluidframework.leaf.string", { leafValue: 1 }],
        ["org.watershed.shared-tree.m4.Root", {
          objectNodeFields: {
            type: "Map",
            entries: [
              ["title", {
                kind: "Value",
                types: {
                  type: "Set",
                  values: ["com.fluidframework.leaf.string"],
                },
              }],
              ...(includeScore ? [["score", {
                kind: "Optional",
                types: {
                  type: "Set",
                  values: ["com.fluidframework.leaf.number"],
                },
              }]] : []),
            ],
          },
        }],
      ],
    },
    rootFieldSchema: {
      kind: "Value",
      types: {
        type: "Set",
        values: ["org.watershed.shared-tree.m4.Root"],
      },
    },
  });
  const storedSchema = (includeScore) => ({
    version: 2,
    nodes: {
      "com.fluidframework.leaf.number": { kind: { leaf: 0 } },
      "com.fluidframework.leaf.string": { kind: { leaf: 1 } },
      "org.watershed.shared-tree.m4.Root": {
        kind: {
          object: {
            ...(includeScore ? {
              score: {
                kind: "Optional",
                types: ["com.fluidframework.leaf.number"],
              },
            } : {}),
            title: {
              kind: "Value",
              types: ["com.fluidframework.leaf.string"],
            },
          },
        },
      },
    },
    root: {
      kind: "Value",
      types: ["org.watershed.shared-tree.m4.Root"],
    },
  });
  assert.deepEqual(matchReconnectOperations([{
    revision: "local-schema",
    originatorId: "origin",
    payload: [{
      type: "schema",
      innerChange: {
        schema: {
          old: runtimeSchema(false),
          new: runtimeSchema(true),
        },
      },
    }],
  }, {
    revision: "local-data",
    originatorId: "origin",
    payload: [{ data: { path: ["score"], value: 81 } }],
  }], [{
    revision: 41,
    originatorId: "origin",
    payload: [{
      schema: {
        old: storedSchema(false),
        new: storedSchema(true),
      },
    }],
  }, {
    revision: 42,
    originatorId: "origin",
    payload: [{ data: { path: ["score"], value: 81 } }],
  }]), [
    { originalRevision: "local-schema", acceptedRevision: 41 },
    { originalRevision: "local-data", acceptedRevision: 42 },
  ]);
});

test("reconnect schema matching canonicalizes native persisted diagnostics", () => {
  const storedSchema = (includeScore) => ({
    version: 2,
    nodes: {
      "com.fluidframework.leaf.number": { kind: { leaf: 0 } },
      "com.fluidframework.leaf.string": { kind: { leaf: 1 } },
      "org.watershed.shared-tree.m4.Root": {
        kind: {
          object: {
            ...(includeScore ? {
              score: {
                kind: "Optional",
                types: ["com.fluidframework.leaf.number"],
              },
            } : {}),
            title: {
              kind: "Value",
              types: ["com.fluidframework.leaf.string"],
            },
          },
        },
      },
    },
    root: {
      kind: "Value",
      types: ["org.watershed.shared-tree.m4.Root"],
    },
  });
  const diagnosticSchema = (includeScore) =>
    `FixedSchema(StoredSchema(persisted: VObject([`
    + `#("nodes", VObject([`
    + `#("com.fluidframework.leaf.number", VObject([`
    + `#("kind", VObject([#("leaf", VNumber(NInt(0)))]))])),`
    + `#("com.fluidframework.leaf.string", VObject([`
    + `#("kind", VObject([#("leaf", VNumber(NInt(1)))]))])),`
    + `#("org.watershed.shared-tree.m4.Root", VObject([`
    + `#("kind", VObject([#("object", VObject([`
    + `${includeScore ? `#("score", VObject([`
      + `#("kind", VString("Optional")),`
      + `#("types", VArray([VString("com.fluidframework.leaf.number")]))`
      + `])),` : ""}`
    + `#("title", VObject([#("kind", VString("Value")),`
    + `#("types", VArray([VString("com.fluidframework.leaf.string")]))]))`
    + `]))]))]))])),`
    + `#("root", VObject([#("kind", VString("Value")),`
    + `#("types", VArray([VString("org.watershed.shared-tree.m4.Root")]))])),`
    + `#("version", VNumber(NInt(2)))`
    + `]), profile_supported: True))`;
  assert.deepEqual(matchReconnectOperations([{
    revision: "local-schema",
    originatorId: "origin",
    payload: `Changeset([SchemaChange(before: ${diagnosticSchema(false)}, `
      + `after: ${diagnosticSchema(true)}, is_inverse: False)])`,
  }, {
    revision: "local-data",
    originatorId: "origin",
    payload: [{ data: { path: ["score"], value: 81 } }],
  }], [{
    revision: 41,
    originatorId: "origin",
    payload: [{
      schema: {
        old: storedSchema(false),
        new: storedSchema(true),
      },
    }],
  }, {
    revision: 42,
    originatorId: "origin",
    payload: [{ data: { path: ["score"], value: 81 } }],
  }]), [
    { originalRevision: "local-schema", acceptedRevision: 41 },
    { originalRevision: "local-data", acceptedRevision: 42 },
  ]);
});

test("standalone component submissions retain reconnect revisions", () => {
  assert.deepEqual(decodeTreeSubmissions([{
    type: "op",
    sequenceNumber: 10,
    clientId: "reconnected-client",
    referenceSequenceNumber: 8,
    metadata: { batchId: "batch_[2]" },
    contents: JSON.stringify({
      type: "component",
      contents: {
        contents: {
          content: {
            contents: {
              revision: -2,
              originatorId: "originator",
              changeset: [{ data: { changes: [] } }],
            },
          },
        },
      },
    }),
  }]), [{
    outerSequenceNumber: 10,
    clientId: "reconnected-client",
    referenceSequenceNumber: 8,
    batchId: "batch_[2]",
    allocations: [],
    commits: [{
      innerIndex: 0,
      revision: -2,
      originatorId: "originator",
      changeset: [{ data: { changes: [] } }],
    }],
  }]);
});

test("settling preserves notifications drained while polling", async () => {
  const adapters = Object.fromEntries(["upstream", "javascript", "erlang"].map(
    (implementation) => {
      let first = true;
      return [implementation, {
        async checkpoint() {
          const events = first ? [{ local: false }, { local: false }, { local: false }] : [];
          first = false;
          return {
            implementation, sequenceNumber: 4, wholeTree: { value: "same" },
            pendingTreeCount: 0, inflightSubmissionCount: 0, events,
          };
        },
        async awaitSynced() {},
      }];
    },
  ));
  const checkpoint = await settle(adapters);
  assert(checkpoint.observations.every(({ events }) => events.length === 3));
});

test("remote notification evidence waits for deferred native events", async () => {
  let javascriptChecks = 0;
  let syncs = 0;
  const adapters = Object.fromEntries(["upstream", "javascript", "erlang"].map(
    (implementation) => [implementation, {
      async checkpoint() {
        if (implementation === "javascript") javascriptChecks += 1;
        return {
          implementation,
          sequenceNumber: 4,
          wholeTree: { value: "same" },
          pendingTreeCount: 0,
          inflightSubmissionCount: 0,
          events: implementation === "javascript" && javascriptChecks > 1
            ? [{ local: false }]
            : implementation === "erlang"
              ? [{ local: false }]
              : [],
        };
      },
      async awaitSynced() { syncs += 1; },
    }],
  ));
  const checkpoints = [];
  const observers = await waitForRemoteNotifications(
    adapters,
    checkpoints,
    ["upstream"],
    100,
  );
  assert.deepEqual(observers, ["javascript", "erlang"]);
  assert(checkpoints.length >= 2);
  assert(syncs > 0, "notification evidence was labeled quiescent without synchronization");
});

test("refusal traffic accounting includes held submissions without counting delivery twice", () => {
  const message = { id: 2, direction: "outbound", kind: "op" };
  assert.equal(interceptedTreeMessageCount({
    held: [message], outboundTreeMessages: [],
  }), 1);
  assert.equal(interceptedTreeMessageCount({
    held: [message], outboundTreeMessages: [message],
  }), 1);
});

test("fresh reload preserves the primary mismatch when cleanup fails", async () => {
  const cleanup = new Error("reload close failed");
  await assert.rejects(() => freshReload({}, {}, "document", "javascript", "", {
    value: "expected",
  }, {
    async createNative() {
      return {
        async awaitSynced() {},
        async checkpoint() { return { wholeTree: { value: "wrong" } }; },
        async close() { throw cleanup; },
      };
    },
  }), (error) => {
    assert.match(error.message, /reload observed another tree/);
    assert.deepEqual(error.cleanupErrors, [cleanup]);
    return true;
  });
});

test("gap-repair evidence waits for the outbound request observation", async () => {
  let checks = 0;
  const adapter = {
    evidence() {
      checks += 1;
      return {
        repairRequests: checks > 1 ? [{ from: 7 }] : [],
      };
    },
  };
  const evidence = await waitForGapRepair(adapter, 0, 100);
  assert.equal(evidence.repairRequests[0].from, 7);
  assert(checks >= 2);
});

test("a failed settle exposes the latest observations, not a stale optimistic state", async () => {
  const adapters = Object.fromEntries(["upstream", "javascript", "erlang"].map(
    (implementation) => [implementation, {
      async checkpoint() {
        return {
          implementation, sequenceNumber: 4, wholeTree: { value: implementation },
          pendingTreeCount: 0, inflightSubmissionCount: 0, events: [],
        };
      },
      async awaitSynced() { throw new Error("synchronization failed"); },
    }],
  ));
  await assert.rejects(() => settle(adapters), (error) => {
    assert.equal(error.checkpoint.stage, "failed");
    assert.deepEqual(error.checkpoint.observations.map(({ wholeTree }) => wholeTree.value),
      ["upstream", "javascript", "erlang"]);
    return true;
  });
});

test("failed native subscription closes the newly acquired client", async () => {
  const original = new Error("subscription failed");
  const cleanup = new Error("client close failed");
  let closed = false;
  await assert.rejects(() => nativeAdapter("javascript", {}, {}, "", {
    createClient: async () => ({
      async request() { throw original; },
      async close() { closed = true; throw cleanup; },
    }),
  }), (error) => error === original);
  assert.equal(closed, true);
  assert.deepEqual(original.cleanupErrors, [cleanup]);
});

test("map adapters preserve keys, tagged values, and canonical entries", async () => {
  const session = {
    container: {
      connected: true,
      clientId: "upstream-map",
      deltaManager: {
        on() {},
        lastSequenceNumber: 0,
        outbound: [],
        inbound: [],
      },
    },
    data: {
      tree: {
        kernel: {
          editManager: {
            constructor: { name: "EditManager" },
            getLocalCommits() { return []; },
          },
        },
      },
      view: { root: initialMapRoot() },
    },
  };
  const upstream = upstreamAdapter(session);
  const nested = {
    kind: "map",
    schemaId: "org.watershed.shared-tree.m2.DynamicMap",
    entries: [["inside", { kind: "string", value: "value" }]],
  };
  await upstream.mapSet(["items"], "😀", nested);
  await upstream.mapSet(["items"], "", { kind: "null" });
  await upstream.mapSet(["items"], "point", {
    kind: "object",
    schemaId: "org.watershed.shared-tree.m2.Point",
    fields: [
      ["x", { kind: "number", value: 1 }],
      ["y", { kind: "number", value: 2 }],
    ],
  });

  await upstream.set(["items", "point", "x"], 9);
  assert.deepEqual(await upstream.mapGet(["items"], "missing"), { present: false });
  assert.deepEqual(await upstream.mapGet(["items"], "😀"), {
    present: true,
    value: nested,
  });
  assert.deepEqual(await upstream.mapGet(["items"], "point"), {
    present: true,
    value: {
      kind: "object",
      schemaId: "org.watershed.shared-tree.m2.Point",
      fields: [
        ["x", { kind: "number", value: 9 }],
        ["y", { kind: "number", value: 2 }],
      ],
    },
  });
  assert.deepEqual(await upstream.mapKeys(["items"]), ["", "point", "😀"]);
  assert.deepEqual(await upstream.mapEntries(["items"]), [
    ["", { kind: "null" }],
    ["point", {
      kind: "object",
      schemaId: "org.watershed.shared-tree.m2.Point",
      fields: [
        ["x", { kind: "number", value: 9 }],
        ["y", { kind: "number", value: 2 }],
      ],
    }],
    ["😀", nested],
  ]);
  await upstream.mapDelete(["items"], "");
  assert.deepEqual(await upstream.mapGet(["items"], ""), { present: false });
  const upstreamCheckpoint = await upstream.checkpoint();
  assert(upstreamCheckpoint.events.length > 0);
  assert.deepEqual(upstreamCheckpoint.wholeTree, {
    present: true,
    value: {
      kind: "object",
      schemaId: "org.watershed.shared-tree.m2.Root",
      fields: [["items", {
        kind: "map",
        schemaId: "org.watershed.shared-tree.m2.DynamicMap",
        entries: [
          ["point", {
            kind: "object",
            schemaId: "org.watershed.shared-tree.m2.Point",
            fields: [
              ["x", { kind: "number", value: 9 }],
              ["y", { kind: "number", value: 2 }],
            ],
          }],
          ["😀", nested],
        ],
      }]],
    },
  });

  const calls = [];
  const native = await nativeAdapter("javascript", {}, {}, "", {
    createClient: async () => ({
      instanceId: "native-map",
      gate: {
        evidence() { return { held: [], delivered: [] }; },
        hold() {},
        async release() {},
        async disconnect() {},
        async reconnect() {},
      },
      async request({ command }) {
        if (command === "subscribe") return { ok: true };
        throw new Error(`Unexpected request: ${command}`);
      },
      async mapGet(path, key) {
        calls.push(["mapGet", path, key]);
        return { present: false };
      },
      async mapSet(path, key, value) {
        calls.push(["mapSet", path, key, value]);
        return null;
      },
      async mapDelete(path, key) {
        calls.push(["mapDelete", path, key]);
        return null;
      },
      async mapKeys(path) {
        calls.push(["mapKeys", path]);
        return ["😀", ""];
      },
      async mapEntries(path) {
        calls.push(["mapEntries", path]);
        return [["😀", nested], ["", { kind: "null" }]];
      },
      async close() {},
    }),
  });
  assert.deepEqual(await native.mapGet(["items"], "__proto__"), { present: false });
  await native.mapSet(["items"], "😀", nested);
  await native.mapDelete(["items"], "");
  assert.deepEqual(await native.mapKeys(["items"]), ["", "😀"]);
  assert.deepEqual(await native.mapEntries(["items"]), [
    ["", { kind: "null" }],
    ["😀", nested],
  ]);
  assert.deepEqual(calls, [
    ["mapGet", ["items"], "__proto__"],
    ["mapSet", ["items"], "😀", nested],
    ["mapDelete", ["items"], ""],
    ["mapKeys", ["items"]],
    ["mapEntries", ["items"]],
  ]);
  await native.close();
});

test("upstream checkpoint preserves history when its active view is stale", async () => {
  const stale = new Error("active view is stale");
  const session = {
    container: {
      connected: true,
      clientId: "upstream-stale",
      deltaManager: {
        on() {},
        lastSequenceNumber: 7,
        outbound: [],
        inbound: [],
      },
    },
    data: {
      tree: {
        kernel: {
          editManager: {
            constructor: { name: "EditManager" },
            getLocalCommits() {
              return [{ revision: "pending", change: { changes: [] } }];
            },
            getTrunkCommits() { return []; },
          },
        },
      },
      view: {
        compatibility: { canView: false },
        events: { on() {} },
        get root() { throw stale; },
      },
    },
  };
  const checkpoint = await upstreamAdapter(session).checkpoint();
  assert.equal(checkpoint.wholeTree, null);
  assert.equal(checkpoint.readError, stale.message);
  assert.equal(checkpoint.history.pending.length, 1);
});

test("native schema operations call the public command-client facade", async () => {
  const calls = [];
  const native = await nativeAdapter("javascript", {}, {}, "", {
    createClient: async () => ({
      instanceId: "native-schema",
      gate: {
        evidence() { return { held: [], delivered: [] }; },
        hold() {},
        async release() {},
        async disconnect() {},
        async reconnect() {},
      },
      async request({ command }) {
        if (command === "subscribe") return { ok: true };
        throw new Error(`Unexpected request: ${command}`);
      },
      async schemaCompatibility(view) {
        calls.push(["schemaCompatibility", view]);
        return { canView: true, canUpgrade: true, isEquivalent: false };
      },
      async schemaUpgrade(view) {
        calls.push(["schemaUpgrade", view]);
      },
      async openView(view) {
        calls.push(["openView", view]);
      },
      async close() {},
    }),
  });
  assert.deepEqual(await native.schemaCompatibility("optional"), {
    canView: true,
    canUpgrade: true,
    isEquivalent: false,
  });
  await native.schemaUpgrade("optional");
  await native.openView("optional");
  assert.deepEqual(calls, [
    ["schemaCompatibility", "optional"],
    ["schemaUpgrade", "optional"],
    ["openView", "optional"],
  ]);
  await native.close();
});

test("native reconnect retries one transient transport timeout", async () => {
  let reconnects = 0;
  let syncs = 0;
  const gate = {
    async disconnect() {},
    async reconnect() {},
    async release() {},
    evidence() { return {}; },
  };
  const adapter = await nativeAdapter("erlang", {}, {}, "", {
    createClient: async () => ({
      gate,
      async request({ command }) {
        if (command === "subscribe") return { ok: true };
        if (command === "reconnect") {
          reconnects += 1;
          return { ok: true };
        }
        if (command === "await-synced") {
          syncs += 1;
          return syncs === 1
            ? {
              ok: false,
              error: {
                code: "connection-failed",
                operation: "await-synced",
                message: "secret prefix Transport(Timeout) secret suffix",
              },
            }
            : { ok: true, observation: { clientId: "second" } };
        }
        if (command === "checkpoint") {
          return {
            ok: true,
            sequenceNumber: 7,
            observation: {
              clientId: "second",
              pendingTreeCount: 0,
              inFlightCount: 0,
            },
            result: { root: { kind: "null" }, events: [] },
          };
        }
        return { ok: true };
      },
      async close() {},
    }),
  });
  await adapter.reconnect();
  assert.equal(reconnects, 2);
  assert.equal(syncs, 2);
  const expectedRetry = [{
    attempt: 1,
    code: "connection-failed",
    operation: "await-synced",
    message: "channel connect failed: Transport(Timeout)",
  }];
  assert.deepEqual((await adapter.checkpoint()).reconnectRetries, expectedRetry);
  assert.deepEqual(adapter.evidence().reconnectRetries, expectedRetry);
});

test("native reconnect permits only one transient retry per client", async () => {
  let reconnects = 0;
  let syncs = 0;
  const gate = {
    async disconnect() {},
    async reconnect() {},
    async release() {},
    evidence() { return {}; },
  };
  const adapter = await nativeAdapter("erlang", {}, {}, "", {
    createClient: async () => ({
      gate,
      async request({ command }) {
        if (command === "subscribe") return { ok: true };
        if (command === "reconnect") {
          reconnects += 1;
          return { ok: true };
        }
        if (command === "await-synced") {
          syncs += 1;
          return [1, 3].includes(syncs)
            ? {
              ok: false,
              error: {
                code: "connection-failed",
                operation: "await-synced",
                message: "channel connect failed: Transport(Timeout)",
              },
            }
            : { ok: true, observation: { clientId: "connected" } };
        }
        return { ok: true };
      },
      async close() {},
    }),
  });
  await adapter.reconnect();
  await assert.rejects(() => adapter.reconnect(), /Transport\(Timeout\)/);
  assert.equal(reconnects, 3);
  assert.equal(syncs, 3);
});

test("native reconnect retries one transient closed transport stream", async () => {
  let reconnects = 0;
  let syncs = 0;
  const gate = {
    async disconnect() {},
    async reconnect() {},
    async release() {},
    evidence() { return {}; },
  };
  const adapter = await nativeAdapter("erlang", {}, {}, "", {
    createClient: async () => ({
      gate,
      async request({ command }) {
        if (command === "subscribe") return { ok: true };
        if (command === "reconnect") {
          reconnects += 1;
          return { ok: true };
        }
        if (command === "await-synced") {
          syncs += 1;
          return syncs === 1
            ? {
              ok: false,
              error: {
                code: "connection-failed",
                operation: "await-synced",
                message: 'channel connect failed: Transport(StreamError("Closed"))',
              },
            }
            : { ok: true, observation: { clientId: "second" } };
        }
        return { ok: true };
      },
      async close() {},
    }),
  });
  await adapter.reconnect();
  assert.equal(reconnects, 2);
  assert.equal(syncs, 2);
});

test("failed refusal-control acquisition closes every successful control", async () => {
  let closed = false;
  const original = new Error("second control failed");
  await assert.rejects(() => runFailureCases({}, {
    runId: "run", profileDigest: "a".repeat(64), viewSchema: "schema",
    artifactDirectory: "/unused",
  }, {
    async createControl(_config, _context, target) {
      if (target === "erlang") throw original;
      return { async close() { closed = true; } };
    },
  }), (error) => error === original);
  assert.equal(closed, true);
});

test("optional conflicts start from an acknowledged present note", () => {
  const schedules = generateSchedules({ seed: 42, iterations: 200 });
  for (const schedule of schedules.filter(({ template }) => template === "optional-conflict")) {
    assert.equal(schedule.actions[0].type, "set");
    assert.deepEqual(schedule.actions[0].path, ["note"]);
    assert.equal(schedule.actions[1].stage, "quiescent");
    assert.equal(schedule.actions[1].label, "initial");
  }
});

test("seeded schedules never request unsupported upstream queue reordering", () => {
  const schedules = generateSchedules({ seed: 42, iterations: 200 });
  for (const { actions } of schedules) {
    assert(actions.filter(({ author, type }) => author === "upstream" && type === "release")
      .every(({ order, duplicate }) => order === "fifo" && duplicate === false));
  }
});

test("outbound release waits for every pending tree commit, not an allocation or socket write", async () => {
  const commits = [2, 3].map((sequenceNumber) => ({
    type: "op", sequenceNumber, clientId: "client", referenceSequenceNumber: 0,
    contents: { type: "component", contents: { contents: { content: { contents: {
      revision: sequenceNumber, originatorId: "origin", changeset: [],
    } } } } },
  }));
  const history = [{
    type: "op", sequenceNumber: 1, clientId: "client", referenceSequenceNumber: 0,
    contents: { type: "idAllocation", contents: { sessionId: "origin", ids: { first: 0, last: 2 } } },
  }, ...commits].map((message) => ({
    ...message,
    contents: { type: "groupedBatch", contents: [{ contents: message.contents }] },
  }));
  let reads = 0;
  let released = false;
  const state = {
    connected: { javascript: true },
    held: { javascript: { outbound: true } },
    checkpoints: [{ observations: [{ implementation: "javascript", pendingTreeCount: 2 }] }],
    deliveries: [],
    creator: {
      container: { resolvedUrl: {} },
      documentServiceFactory: {
        async createDocumentService() {
          const messages = history.slice(0, reads++);
          return {
            dispose() {},
            async connectToDeltaStorage() {
              return { fetchMessages() {
                let done = false;
                return { async read() {
                  if (done) return { done: true };
                  done = true;
                  return { done: false, value: messages };
                } };
              } };
            },
          };
        },
      },
    },
    adapters: { javascript: {
      clientIds: new Set(["client"]),
      async releaseOutbound() { released = true; },
    } },
  };
  await executeScheduleAction({}, {}, {}, {
    type: "release", author: "javascript", direction: "outbound", order: "fifo",
    duplicate: false, preconditions: { connected: ["javascript"], outboundHeld: true },
  }, state);
  assert.equal(released, true);
  assert(reads >= 4, "release returned before both tree commits sequenced");
  assert.deepEqual(state.deliveries[0].acceptedSequenceNumbers, [2, 3]);
});

test("inbound release waits for measured frames before releasing the recorded order", async () => {
  const calls = [];
  const state = {
    connected: { javascript: true },
    held: { javascript: { inbound: true } },
    deliveries: [{ direction: "outbound", acceptedSequenceNumbers: [2, 3] }],
    adapters: { javascript: {
      async awaitInbound(sequences) {
        calls.push(["await", sequences]);
        return { heldSequenceNumbers: sequences };
      },
      async releaseInbound(options) {
        calls.push(["release", options.order]);
        return { deliveredSequenceNumbers: [3, 2] };
      },
    } },
  };
  await executeScheduleAction({}, {}, {}, {
    type: "release", author: "javascript", direction: "inbound", order: "reverse",
    duplicate: false, preconditions: { connected: ["javascript"], inboundHeld: true },
  }, state);
  assert.deepEqual(calls, [["await", [2, 3]], ["release", "reverse"]]);
  assert.deepEqual(state.deliveries[1].deliveredSequenceNumbers, [3, 2]);
});

test("seeded map actions keep path and key separate", async () => {
  const calls = [];
  const state = {
    adapters: {
      javascript: {
        async mapSet(path, key, value) {
          calls.push(["set", path, key, value]);
        },
        async mapDelete(path, key) {
          calls.push(["delete", path, key]);
        },
      },
    },
    connected: { javascript: true },
    held: { javascript: { inbound: false, outbound: true } },
    quiescent: true,
    summaries: [],
  };
  await executeScheduleAction({}, {}, { profile: "map" }, {
    type: "map-set",
    author: "javascript",
    path: ["items"],
    key: "__proto__",
    value: { kind: "string", value: "safe" },
    preconditions: {
      connected: ["javascript"],
      outboundHeld: true,
      pathType: "dynamic-map",
    },
  }, state);
  await executeScheduleAction({}, {}, { profile: "map" }, {
    type: "map-delete",
    author: "javascript",
    path: ["items"],
    key: "水",
    preconditions: {
      connected: ["javascript"],
      outboundHeld: true,
      pathType: "dynamic-map",
    },
  }, state);
  assert.deepEqual(calls, [
    ["set", ["items"], "__proto__", { kind: "string", value: "safe" }],
    ["delete", ["items"], "水"],
  ]);
  assert.equal(state.quiescent, false);
});

test("replay cannot label a different or infrastructure failure as reproduced", () => {
  const original = {
    error: { name: "AssertionError", code: "ERR_ASSERTION", message: "roots differ" },
    firstDifferencePath: "$.point.x",
  };
  assert.equal(sameReplayFailure(original, structuredClone(original)), true);
  for (const different of [
    { error: { name: "Error", code: "ECONNREFUSED", message: "connect refused" },
      firstDifferencePath: null },
    { ...original, error: { ...original.error, message: "missing native client" } },
    { ...original, firstDifferencePath: "$.note" },
  ]) {
    assert.equal(sameReplayFailure(original, different), false);
  }
});

test("replay distinguishes the failing action and actual failed-barrier roots", () => {
  const original = {
    error: { name: "AssertionError", code: "ERR_ASSERTION", message: "quiescence failed" },
    firstDifferencePath: "$.value",
    failedAction: { index: 3, type: "checkpoint", label: "settled" },
    failedCheckpoint: { observations: [{
      implementation: "javascript", wholeTree: { value: 1 },
      pendingTreeCount: 0, inflightSubmissionCount: 0,
    }] },
  };
  assert.equal(sameReplayFailure(original, structuredClone(original)), true);
  const anotherAction = structuredClone(original);
  anotherAction.failedAction.index = 7;
  assert.equal(sameReplayFailure(original, anotherAction), false);
  const anotherValue = structuredClone(original);
  anotherValue.failedCheckpoint.observations[0].wholeTree.value = 9;
  assert.equal(sameReplayFailure(original, anotherValue), false);
});
test("failure capture reports a failed history read without hiding the original error", async (t) => {
  const directory = await mkdtemp(join(tmpdir(), "watershed-failure-capture-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const schedule = generateSchedules({ seed: 42, iterations: 1 })[0];
  const failurePath = await writeSeededFailure({
    runId: "capture-run",
    profileDigest: "a".repeat(64),
    artifactDirectory: directory,
  }, schedule, {
    documentId: "owned-document",
    creator: {
      container: { resolvedUrl: { id: "owned-document" } },
      documentServiceFactory: {
        async createDocumentService() { throw new Error("delta store unavailable"); },
      },
    },
    checkpoints: [],
    summaries: [],
  }, new Error("original divergence"));
  const failure = JSON.parse(await readFile(failurePath, "utf8"));
  assert.equal(failure.error.message, "original divergence");
  assert.equal(failure.captureErrors.length, 1);
  assert.equal(failure.captureErrors[0].operation, "read-sequenced-history");
  assert.equal(failure.captureErrors[0].error.message, "delta store unavailable");
});

test("failure artifacts persist the failing barrier rather than prior optimistic differences", async (t) => {
  const directory = await mkdtemp(join(tmpdir(), "watershed-failed-barrier-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const schedule = generateSchedules({ seed: 42, iterations: 1 })[0];
  const action = { index: schedule.actions.length - 1, type: "checkpoint", label: "settled" };
  const error = new Error("quiescence failed");
  error.checkpoint = {
    label: "settled", stage: "failed",
    observations: [1, 2].map((value) => ({ wholeTree: { settled: value } })),
  };
  const path = await writeSeededFailure({
    runId: "barrier-run", profileDigest: "a".repeat(64), artifactDirectory: directory,
  }, schedule, {
    currentAction: action,
    checkpoints: [{ observations: [1, 2].map((value) =>
      ({ wholeTree: { optimistic: value } })) }],
    summaries: [],
  }, error);
  const artifact = JSON.parse(await readFile(path, "utf8"));
  assert.equal(artifact.firstDifferencePath, "$.settled");
  assert.deepEqual(artifact.failedAction, action);
  assert.deepEqual(artifact.failedCheckpoint, error.checkpoint);
});

const expectedScenarioIds = [
  "independent-scalar:upstream->javascript",
  "independent-scalar:upstream->erlang",
  "independent-scalar:javascript->upstream",
  "independent-scalar:javascript->erlang",
  "independent-scalar:erlang->upstream",
  "independent-scalar:erlang->javascript",
  "independent-nested:upstream->javascript",
  "independent-nested:upstream->erlang",
  "independent-nested:javascript->upstream",
  "independent-nested:javascript->erlang",
  "independent-nested:erlang->upstream",
  "independent-nested:erlang->javascript",
  "same-field:upstream->javascript:upstream-first",
  "same-field:upstream->javascript:javascript-first",
  "same-field:upstream->erlang:upstream-first",
  "same-field:upstream->erlang:erlang-first",
  "same-field:javascript->upstream:javascript-first",
  "same-field:javascript->upstream:upstream-first",
  "same-field:javascript->erlang:javascript-first",
  "same-field:javascript->erlang:erlang-first",
  "same-field:erlang->upstream:erlang-first",
  "same-field:erlang->upstream:upstream-first",
  "same-field:erlang->javascript:erlang-first",
  "same-field:erlang->javascript:javascript-first",
  "optional-set-clear:upstream->javascript:upstream-first",
  "optional-set-clear:upstream->javascript:javascript-first",
  "optional-set-clear:upstream->erlang:upstream-first",
  "optional-set-clear:upstream->erlang:erlang-first",
  "optional-set-clear:javascript->upstream:javascript-first",
  "optional-set-clear:javascript->upstream:upstream-first",
  "optional-set-clear:javascript->erlang:javascript-first",
  "optional-set-clear:javascript->erlang:erlang-first",
  "optional-set-clear:erlang->upstream:erlang-first",
  "optional-set-clear:erlang->upstream:upstream-first",
  "optional-set-clear:erlang->javascript:erlang-first",
  "optional-set-clear:erlang->javascript:javascript-first",
  "optional-set-clear:repeated-clear:upstream",
  "optional-set-clear:repeated-clear:javascript",
  "optional-set-clear:repeated-clear:erlang",
  "optional-set-clear:absent-clear:upstream",
  "optional-set-clear:absent-clear:javascript",
  "optional-set-clear:absent-clear:erlang",
  "optional-set-clear:re-add:upstream",
  "optional-set-clear:re-add:javascript",
  "optional-set-clear:re-add:erlang",
  "null-absence:upstream",
  "null-absence:javascript",
  "null-absence:erlang",
  "parent-replacement-child-edit:upstream->javascript:upstream-first",
  "parent-replacement-child-edit:upstream->javascript:javascript-first",
  "parent-replacement-child-edit:upstream->erlang:upstream-first",
  "parent-replacement-child-edit:upstream->erlang:erlang-first",
  "parent-replacement-child-edit:javascript->upstream:javascript-first",
  "parent-replacement-child-edit:javascript->upstream:upstream-first",
  "parent-replacement-child-edit:javascript->erlang:javascript-first",
  "parent-replacement-child-edit:javascript->erlang:erlang-first",
  "parent-replacement-child-edit:erlang->upstream:erlang-first",
  "parent-replacement-child-edit:erlang->upstream:upstream-first",
  "parent-replacement-child-edit:erlang->javascript:erlang-first",
  "parent-replacement-child-edit:erlang->javascript:javascript-first",
  "detached-child-reconciliation:upstream",
  "detached-child-reconciliation:javascript",
  "detached-child-reconciliation:erlang",
  "several-pending-edits:upstream",
  "several-pending-edits:javascript",
  "several-pending-edits:erlang",
  "grouped-commits:upstream",
  "grouped-commits:javascript",
  "grouped-commits:erlang",
  "delivery-duplicates-gaps:javascript",
  "delivery-duplicates-gaps:erlang",
  "multi-session-ids:upstream+javascript+erlang",
  "unicode-finite-values:upstream",
  "unicode-finite-values:javascript",
  "unicode-finite-values:erlang",
];

const mapImplementations = ["upstream", "javascript", "erlang"];
const mapOrderedPairs = mapImplementations.flatMap((first) =>
  mapImplementations.filter((second) => second !== first)
    .map((second) => [first, second]));
const mapPairIds = (family, ordered = false) => mapOrderedPairs.flatMap((authors) =>
  ordered
    ? authors.map((first) => `${family}:${authors.join("->")}:${first}-first`)
    : [`${family}:${authors.join("->")}`]);
const expectedMapScenarioIds = [
  ...mapPairIds("map-independent-keys"),
  ...mapPairIds("map-same-key-set-set", true),
  ...mapPairIds("map-set-delete", true),
  ...mapPairIds("map-nested-object-replace", true),
  ...mapPairIds("map-nested-delete-edit", true),
  ...mapPairIds("map-recursive-conflict", true),
  ...mapImplementations.map((author) => `map-reconnect-pending:${author}`),
  ...mapImplementations.map((author) => `map-summary-tail:${author}`),
];

const expectedFailureIds = [
  "clear-required-title:javascript",
  "clear-required-title:erlang",
  "numeric-title:javascript",
  "numeric-title:erlang",
  "null-optional-note:javascript",
  "null-optional-note:erlang",
  "unknown-field:javascript",
  "unknown-field:erlang",
  "wrong-schema-id:javascript",
  "wrong-schema-id:erlang",
  "unsupported-array-schema:javascript",
  "unsupported-array-schema:erlang",
  "unsupported-map-schema:javascript",
  "unsupported-map-schema:erlang",
  "unsupported-message-version:javascript",
  "unsupported-message-version:erlang",
  "unsupported-summary-version:javascript",
  "unsupported-summary-version:erlang",
  "malformed-allocation-range:javascript",
  "malformed-allocation-range:erlang",
  "missing-summary-blob:javascript",
  "missing-summary-blob:erlang",
  "unknown-runtime-message:javascript",
  "unknown-runtime-message:erlang",
];

test("the deterministic catalogue expands every required Task 3 cell", () => {
  const cells = requiredScenarioCells();
  assert.equal(cells.length, 147);
  assert.deepEqual(cells.map(({ id }) => id), [
    ...expectedScenarioIds,
    ...expectedMapScenarioIds,
  ]);
  assert(cells.slice(expectedScenarioIds.length)
    .every(({ profile }) => profile === "map"));
  assert.deepEqual(cells[0], {
    id: "independent-scalar:upstream->javascript",
    family: "independent-scalar",
    authors: ["upstream", "javascript"],
    order: null,
    variation: null,
  });
  assert.deepEqual(cells[48], {
    id: "parent-replacement-child-edit:upstream->javascript:upstream-first",
    family: "parent-replacement-child-edit",
    authors: ["upstream", "javascript"],
    order: "upstream-first",
    variation: null,
  });
});

test("the failure catalogue covers every native refusal target", () => {
  const cells = requiredFailureCells();
  assert.equal(cells.length, 24);
  assert.deepEqual(cells.map(({ id }) => id), expectedFailureIds);
  assert.deepEqual(cells[0], {
    id: "clear-required-title:javascript",
    caseId: "clear-required-title",
    target: "javascript",
    kind: "local-refusal",
    expectedStage: "local-edit",
    errorCode: "facade-error",
    errorOperation: "clear",
    diagnosticTerms: ["title", "required field"],
    clientState: "ready-local",
  });

  assert.deepEqual(cells[10], {
    id: "unsupported-array-schema:javascript",
    caseId: "unsupported-array-schema",
    target: "javascript",
    kind: "stored-schema-refusal",
    expectedStage: "resolve-view",
    errorCode: "view-resolution-failed",
    errorOperation: "resolve-view",
    diagnosticTerms: ["root", "incompatible field schema"],
    clientState: "never-ready",
  });
  assert.deepEqual(cells[12], {
    id: "unsupported-map-schema:javascript",
    caseId: "unsupported-map-schema",
    target: "javascript",
    kind: "stored-schema-refusal",
    expectedStage: "resolve-view",
    errorCode: "view-resolution-failed",
    errorOperation: "resolve-view",
    diagnosticTerms: ["root", "incompatible field schema"],
    clientState: "never-ready",
  });
  assert.deepEqual(cells.at(-1), {
    id: "unknown-runtime-message:erlang",
    caseId: "unknown-runtime-message",
    target: "erlang",
    kind: "injected-input-refusal",
    expectedStage: "runtime-message",
    errorCode: "connection-failed",
    errorOperation: "await-synced",
    diagnosticTerms: [
      "message.changeset[0]",
      "exactly one data or schema member",
    ],
    clientState: "stopped-after-ready",
  });
});

test("the schema race catalogue covers every directed mixed-client order", () => {
  const cells = requiredSchemaRaceCells();
  assert.equal(cells.length, 27);
  for (const [upgrader, competitor] of [
    ["upstream", "javascript"],
    ["javascript", "upstream"],
    ["upstream", "erlang"],
    ["erlang", "upstream"],
    ["javascript", "erlang"],
    ["erlang", "javascript"],
  ]) {
    for (const family of ["schema-data", "schema-schema"]) {
      for (const order of ["upgrade-first", "competitor-first"]) {
        assert(cells.some((cell) =>
          cell.upgrader === upgrader
          && cell.competitor === competitor
          && cell.family === family
          && cell.order === order));
      }
    }
  }
  for (const author of ["upstream", "javascript", "erlang"]) {
    assert(cells.some((cell) =>
      cell.family === "upgrade-then-edit"
      && cell.upgrader === author
      && cell.order === "causal"));
  }
});

test("schema section runners execute every required target and race cell", async () => {
  const compatibility = [];
  const races = [];
  const reconnect = [];
  assert.equal((await runSchemaCompatibility({}, {}, {
    runTarget: async (_config, _context, target) => {
      compatibility.push(target);
      return { target };
    },
  })).length, 3);
  assert.equal((await runSchemaRaces({}, {}, {
    runCell: async (_config, _context, cell) => {
      races.push(cell.id);
      return { id: cell.id };
    },
  })).length, 27);
  assert.equal((await runSchemaReconnect({}, {}, {
    runTarget: async (_config, _context, target) => {
      reconnect.push(target);
      return { target };
    },
  })).length, 3);
  assert.deepEqual(compatibility, ["upstream", "javascript", "erlang"]);
  assert.deepEqual(races, requiredSchemaRaceCells().map(({ id }) => id));
  assert.deepEqual(reconnect, ["upstream", "javascript", "erlang"]);
});

test("catalogue callers cannot mutate later results", () => {
  const scenarios = requiredScenarioCells();
  const failures = requiredFailureCells();
  scenarios.pop();
  failures[0].caseId = "changed";
  assert.equal(requiredScenarioCells().length, 147);
  assert.equal(requiredFailureCells()[0].caseId, "clear-required-title");
});

test("grouped decoding preserves every allocation and inner tree commit", () => {
  const messages = [{
    type: "op",
    sequenceNumber: 12,
    clientId: "client",
    referenceSequenceNumber: 8,
    contents: JSON.stringify({
      type: "groupedBatch",
      contents: [
        {
          metadata: { batchId: "batch" },
          contents: {
            type: "idAllocation",
            contents: {
              sessionId: "session",
              ids: { first: 4, last: 9 },
            },
          },
        },
        ...[0, 1, 2].map((revision) => ({
          contents: {
            type: "component",
            contents: {
              contents: {
                content: {
                  contents: {
                    revision,
                    originatorId: "origin",
                    changeset: [],
                  },
                },
              },
            },
          },
        })),
      ],
    }),
  }];
  assert.deepEqual(decodeTreeSubmissions(messages), [{
    outerSequenceNumber: 12,
    clientId: "client",
    referenceSequenceNumber: 8,
    batchId: "batch",
    allocations: [{
      sessionId: "session",
      first: 4,
      last: 9,
    }],
    commits: [1, 2, 3].map((innerIndex, revision) => ({
      innerIndex,
      revision,
      originatorId: "origin",
      changeset: [],
    })),
  }]);
});

test("measured upstream submissions omit unavailable batch IDs", () => {
  const messages = [{
    type: "op",
    sequenceNumber: 12,
    clientId: "upstream-client",
    referenceSequenceNumber: 8,
    contents: JSON.stringify({
      type: "groupedBatch",
      contents: [{
        contents: {
          type: "component",
          contents: {
            contents: {
              content: {
                contents: {
                  revision: -1,
                  originatorId: "origin",
                  changeset: [],
                },
              },
            },
          },
        },
      }],
    }),
  }];
  const adapters = {
    upstream: { clientIds: new Set(["upstream-client"]) },
    javascript: { clientIds: new Set() },
    erlang: { clientIds: new Set() },
  };
  const submission = decodedEvidence(messages, adapters, ["upstream"]).submissions[0];
  assert.equal(Object.hasOwn(submission, "batchId"), false);
});

test("the deterministic runner rejects an incomplete coordinator context", async () => {
  await assert.rejects(
    () => runDeterministicCases({}, {}),
    /runId/,
  );
});

test("the deterministic runner routes object and map cells to separate executors", async () => {
  const routed = [];
  const results = await runDeterministicCases({}, {
    runId: "routing",
    profileDigest: "a".repeat(64),
    viewSchema: "object-schema",
    mapViewSchema: "map-schema",
    artifactDirectory: "/unused",
  }, {
    async runObject(_config, _context, cell) {
      routed.push(["object", cell.id]);
      return cell.id;
    },
    async runMap(_config, _context, cell) {
      routed.push(["map", cell.id]);
      return cell.id;
    },
  });
  assert.equal(results.length, 147);
  assert.equal(routed.filter(([profile]) => profile === "object").length, 75);
  assert.equal(routed.filter(([profile]) => profile === "map").length, 72);
  assert(routed.slice(75).every(([profile]) => profile === "map"));
});

test("the failure runner rejects an incomplete coordinator context", async () => {
  await assert.rejects(
    () => runFailureCases({}, {}),
    /runId/,
  );
});

test("seed 42 expands a literal three-author schedule", () => {
  const [schedule] = generateSchedules({ seed: 42, iterations: 1 });
  assert.deepEqual(schedule, {
    formatVersion: 1,
    profile: "object",
    index: 0,
    seed: 42,
    subSeed: 551831576,
    template: "nested-conflict",
    authors: ["upstream", "javascript", "erlang"],
    roles: {
      first: "javascript",
      second: "erlang",
      third: "upstream",
      reload: "javascript",
    },
    actions: [
      {
        type: "checkpoint",
        label: "initial",
        stage: "quiescent",
        preconditions: { connected: ["upstream", "javascript", "erlang"] },
      },
      {
        type: "hold-inbound",
        author: "javascript",
        preconditions: { connected: ["javascript"], inboundHeld: false },
      },
      {
        type: "hold-outbound",
        author: "javascript",
        preconditions: { connected: ["javascript"], outboundHeld: false },
      },
      {
        type: "hold-inbound",
        author: "erlang",
        preconditions: { connected: ["erlang"], inboundHeld: false },
      },
      {
        type: "hold-outbound",
        author: "erlang",
        preconditions: { connected: ["erlang"], outboundHeld: false },
      },
      {
        type: "hold-inbound",
        author: "upstream",
        preconditions: { connected: ["upstream"], inboundHeld: false },
      },
      {
        type: "hold-outbound",
        author: "upstream",
        preconditions: { connected: ["upstream"], outboundHeld: false },
      },
      {
        type: "set",
        author: "javascript",
        path: ["point", "x"],
        value: 142,
        preconditions: {
          connected: ["javascript"],
          pathType: "number",
          outboundHeld: true,
        },
      },
      {
        type: "set",
        author: "erlang",
        path: ["point", "y"],
        value: -143,
        preconditions: {
          connected: ["erlang"],
          pathType: "number",
          outboundHeld: true,
        },
      },
      {
        type: "set",
        author: "upstream",
        path: ["title"],
        value: "seed-42-0-upstream",
        preconditions: { connected: ["upstream"], pathType: "string" },
      },
      {
        type: "checkpoint",
        label: "optimistic",
        stage: "intermediate",
        preconditions: { connected: ["upstream", "javascript", "erlang"] },
      },
      {
        type: "release",
        author: "javascript",
        direction: "outbound",
        order: "fifo",
        duplicate: false,
        preconditions: { connected: ["javascript"], outboundHeld: true },
      },
      {
        type: "release",
        author: "erlang",
        direction: "outbound",
        order: "fifo",
        duplicate: false,
        preconditions: { connected: ["erlang"], outboundHeld: true },
      },
      {
        type: "release",
        author: "upstream",
        direction: "outbound",
        order: "fifo",
        duplicate: false,
        preconditions: { connected: ["upstream"], outboundHeld: true },
      },
      {
        type: "release",
        author: "javascript",
        direction: "inbound",
        order: "reverse",
        duplicate: false,
        preconditions: { connected: ["javascript"], inboundHeld: true },
      },
      {
        type: "release",
        author: "erlang",
        direction: "inbound",
        order: "reverse",
        duplicate: false,
        preconditions: { connected: ["erlang"], inboundHeld: true },
      },
      {
        type: "release",
        author: "upstream",
        direction: "inbound",
        order: "fifo",
        duplicate: false,
        preconditions: { connected: ["upstream"], inboundHeld: true },
      },
      {
        type: "checkpoint",
        label: "settled",
        stage: "quiescent",
        preconditions: { connected: ["upstream", "javascript", "erlang"] },
      },
    ],
  });
});

test("schedule generation is deterministic, sized, unique, and covers every author", () => {
  const normal = generateSchedules({ seed: 42, iterations: 200 });
  assert.equal(normal.length, 200);
  assert.deepEqual(normal, generateSchedules({ seed: 42, iterations: 200 }));
  assert.notDeepEqual(normal, generateSchedules({ seed: 43, iterations: 200 }));
  assert.equal(generateSchedules({ seed: 42, iterations: 5000 }).length, 5000);
  assert.deepEqual(normal.map(({ index }) => index),
    Array.from({ length: 200 }, (_, index) => index));
  for (const schedule of normal) {
    assert.deepEqual([...new Set(schedule.authors)].sort(),
      ["erlang", "javascript", "upstream"]);
    assert(schedule.actions.every(({ preconditions }) =>
      preconditions && typeof preconditions === "object"));
    const actionAuthors = new Set(schedule.actions
      .filter(({ type }) =>
        ["set", "clear", "map-set", "map-delete", "schema-upgrade"].includes(type))
      .map(({ author }) => author));
    assert.deepEqual([...actionAuthors].sort(),
      ["erlang", "javascript", "upstream"]);
    assert(schedule.actions
      .filter(({ type }) => type === "release")
      .every(({ order }) => order === "fifo" || order === "reverse"));
    assert(schedule.actions
      .filter(({ type, direction }) => type === "release" && direction === "outbound")
      .every(({ order }) => order === "fifo"));
    if (schedule.template === "optional-conflict") {
      const clearIndex = schedule.actions.findIndex(({ type }) => type === "clear");
      const clear = schedule.actions[clearIndex];
      assert(schedule.actions.slice(0, clearIndex).some((action) =>
        action.type === "set"
          && action.author === clear.author
          && action.path[0] === "note"),
      "Optional clear author must first create a local value");
    }
  }
  assert(normal.some(({ template }) => template === "optional-conflict"));
  assert(normal.some(({ template }) => template === "parent-child-conflict"));
  assert(normal.some(({ template }) => template === "multiple-pending"));
  assert(normal.some(({ profile }) => profile === "map"));
  assert(normal.some(({ profile }) => profile === "schema"));
  assert(normal.filter(({ profile }) => profile === "map").every(({ actions }) =>
    actions.some(({ type }) => type === "map-set")));
  assert(normal.some(({ profile, actions }) =>
    profile === "map" && actions.some(({ type }) => type === "map-delete")));
  assert(normal.filter(({ profile }) => profile === "schema").every(({ actions }) =>
    actions.some(({ type }) => type === "schema-compatibility")
      && actions.some(({ type }) => type === "schema-upgrade")
      && actions.some(({ type }) => type === "open-view")
      && actions.some(({ type }) => type === "summarize")
      && actions.some(({ type }) => type === "reload")));
  assert(normal.filter(({ profile }) => profile === "schema").every(({ actions }) => {
    const upgrade = actions.findIndex(({ type }) => type === "schema-upgrade");
    const optimistic = actions.findIndex(({ label }) => label === "optimistic");
    return actions.slice(upgrade + 1, optimistic).some(({ type, author, view }) =>
      type === "open-view"
        && author === actions[upgrade].author
        && view === "optional");
  }), "Schema schedules must replace the upgrader's stale view before inspection");
  assert(normal.filter(({ profile }) => profile === "schema").every(({ actions }) => {
    const acknowledged = actions.findIndex(
      ({ label }) => label === "after-acknowledgement",
    );
    const lastInboundRelease = actions.findLastIndex(
      ({ type, direction }) => type === "release" && direction === "inbound",
    );
    const opened = new Set(actions.slice(lastInboundRelease + 1, acknowledged)
      .filter(({ type, view }) => type === "open-view" && view === "optional")
      .map(({ author }) => author));
    return ["upstream", "javascript", "erlang"].every((implementation) =>
      opened.has(implementation));
  }), "Schema schedules must replace every stale view before settlement");
  assert(normal.some(({ profile, actions }) =>
    profile === "schema" && actions.some(({ type }) => type === "disconnect")));
  assert(normal.some(({ actions }) => actions.some(({ type }) => type === "reconnect")));
  for (const schedule of normal.filter(({ actions }) =>
    actions.some(({ type }) => type === "reconnect"))) {
    const disconnectIndex = schedule.actions.findIndex(
      ({ type }) => type === "disconnect",
    );
    assert.deepEqual(schedule.actions[disconnectIndex - 1], {
      type: "checkpoint",
      label: "before-reconnect",
      stage: "quiescent",
      preconditions: { connected: ["upstream", "javascript", "erlang"] },
    });
  }
  assert(normal.some(({ actions }) => actions.some(({ type }) => type === "summarize")));
  for (const schedule of normal.filter(({ actions }) =>
    actions.some(({ type }) => type === "summarize"))) {
    const summarizeIndex = schedule.actions.findIndex(
      ({ type }) => type === "summarize",
    );
    assert.deepEqual(schedule.actions[summarizeIndex - 1], {
      type: "checkpoint",
      label: "before-publish",
      stage: "quiescent",
      preconditions: { connected: ["upstream", "javascript", "erlang"] },
    });
  }
  assert(normal.some(({ actions }) => actions.some(({ type }) => type === "reload")));
});

function replayArtifact() {
  const schedule = generateSchedules({ seed: 42, iterations: 1 })[0];
  return {
    formatVersion: 1,
    kind: "seeded-failure",
    runId: "original-run",
    profileDigest: "a".repeat(64),
    reference: {
      package: "@fluidframework/tree",
      version: "3.1.0",
      commit: "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960",
    },
    service: {
      implementation: "floodgate",
      revision: "0eb493fc46d1bb9baf1151a6ccdde93544e057e7",
    },
    seed: 42,
    index: 0,
    subSeed: schedule.subSeed,
    profile: "object",
    schedule,
    originalDocumentId: "document",
    identityMapping: {
      upstream: { instanceId: "u", clientIds: ["uc"], originatorIds: ["uo"] },
      javascript: { instanceId: "j", clientIds: ["jc"], originatorIds: ["jo"] },
      erlang: { instanceId: "e", clientIds: ["ec"], originatorIds: ["eo"] },
    },
    checkpoints: [{ label: "initial", stage: "quiescent", observations: [] }],
    rawSequencedOperations: [{ sequenceNumber: 1 }],
    summaries: [],
    firstDifferencePath: "$.value.fields[0]",
    error: { name: "AssertionError", message: "roots differ" },
  };
}

test("replay artifacts reject malformed, stale, and incomplete records", () => {
  const valid = replayArtifact();
  assert.equal(validateReplayArtifact(valid, { profileDigest: "a".repeat(64) }), valid);
  for (const [name, mutate] of [
    ["bad version", (copy) => { copy.formatVersion = 2; }],
    ["wrong kind", (copy) => { copy.kind = "failure"; }],
    ["stale profile", (copy) => { copy.profileDigest = "b".repeat(64); }],
    ["stale reference", (copy) => { copy.reference.version = "3.2.0"; }],
    ["stale service", (copy) => { copy.service.revision = "stale"; }],
    ["changed profile", (copy) => { copy.profile = "map"; }],
    ["omitted author", (copy) => { copy.schedule.authors.pop(); }],
    ["changed expansion", (copy) => { copy.schedule.actions.pop(); }],
    ["missing operations", (copy) => { delete copy.rawSequencedOperations; }],
    ["missing identities", (copy) => { delete copy.identityMapping.erlang; }],
  ]) {
    const copy = structuredClone(valid);
    mutate(copy);
    assert.throws(
      () => validateReplayArtifact(copy, { profileDigest: "a".repeat(64) }),
      undefined,
      name,
    );
  }
});

test("a replay infrastructure failure does not reproduce a saved tree divergence", async (t) => {
  const directory = await mkdtemp(join(tmpdir(), "watershed-replay-failure-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const result = await replayFailure({
    get httpUrl() { throw new Error("service configuration unavailable"); },
  }, {
    runId: "replay-run",
    profileDigest: "a".repeat(64),
    viewSchema: "schema",
    artifactDirectory: directory,
  }, replayArtifact());
  assert.equal(result.reproduced, false);
  assert.equal(result.accepted, false);
  assert.equal(result.diagnostic.message, "service configuration unavailable");
});

test("failure-artifact write errors do not replace the original schedule error", async (t) => {
  const directory = await mkdtemp(join(tmpdir(), "watershed-artifact-failure-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const blocked = join(directory, "not-a-directory");
  await writeFile(blocked, "not a directory");
  const original = new Error("service configuration unavailable");
  const schedule = generateSchedules({ seed: 42, iterations: 1 })[0];
  await assert.rejects(() => runSeededSchedule({
    get httpUrl() { throw original; },
  }, {
    runId: "capture-run",
    profileDigest: "a".repeat(64),
    viewSchema: "schema",
    artifactDirectory: join(blocked, "run"),
  }, schedule), (error) => {
    assert.equal(error, original);
    assert.equal(error.artifactCaptureError.code, "ENOTDIR");
    return true;
  });
});

test("the seeded runner validates context and the expanded schedule before connecting", async () => {
  const schedule = generateSchedules({ seed: 42, iterations: 1 })[0];
  await assert.rejects(() => runSeededSchedule({}, {}, schedule), /runId/);
  const invalid = structuredClone(schedule);
  invalid.actions[5].path = ["unknown"];
  await assert.rejects(() => runSeededSchedule({}, {
    runId: "run",
    profileDigest: "a".repeat(64),
    viewSchema: "schema",
    artifactDirectory: "/tmp",
  }, invalid), /path/);
});

test("replay validates the profile before connecting", async () => {
  const schedule = generateSchedules({ seed: 42, iterations: 1 })[0];
  await assert.rejects(() => replayFailure({}, {
    runId: "replay",
    profileDigest: "a".repeat(64),
    viewSchema: "schema",
    artifactDirectory: "/tmp",
  }, {
    formatVersion: 1,
    kind: "seeded-failure",
    runId: "original",
    profileDigest: "b".repeat(64),
    reference: {
      package: "@fluidframework/tree",
      version: "3.1.0",
      commit: "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960",
    },
    service: {
      implementation: "floodgate",
      revision: "0eb493fc46d1bb9baf1151a6ccdde93544e057e7",
    },
    seed: schedule.seed,
    index: schedule.index,
    subSeed: schedule.subSeed,
    schedule,
    originalDocumentId: null,
    identityMapping: Object.fromEntries([
      "upstream", "javascript", "erlang",
    ].map((implementation) => [implementation, {
      instanceId: null,
      clientIds: [],
      originatorIds: [],
      revisions: [],
      sessionIds: [],
    }])),
    checkpoints: [],
    rawSequencedOperations: [],
    summaries: [],
    firstDifferencePath: null,
    error: { name: "Error", message: "original" },
  }), /another profile/);
});
