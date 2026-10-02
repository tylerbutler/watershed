import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import * as generator from "./generate.mjs";
import {
  compareDirectories,
  requiredCases,
  validateArrayCase,
  schemaEvolutionCaseIds,
  schemaEvolutionHistoryScenarioIds,
  validateCases,
  writeCorpus,
} from "./generate.mjs";

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

const identifierCases = [
  ["identifier-schema", "schema"],
  ["identifier-values", "values"],
  ["identifier-field-batches", "codec"],
  ["identifier-persistence", "history"],
];

const identifierScenarioIds = {
  "identifier-schema": [
    "valid-string-field",
    "two-identifier-fields",
    "non-string-refusal",
    "union-refusal",
    "identifier-to-value",
    "value-to-identifier-refusal",
    "canonical-field-change",
  ],
  "identifier-values": [
    "custom-string",
    "empty-string",
    "uuid",
    "duplicate-custom-strings",
    "omitted-default",
    "multiple-defaults",
    "nested-insertion",
    "direct-assignment-refusal",
    "clear-refusal",
    "parent-replacement",
    "allocation-order",
  ],
  "identifier-field-batches": [
    "literal-zero-string",
    "local-negative-op-id",
    "remote-finalized-id",
    "eager-final-id",
    "unknown-uuid-string",
    "message-summary-same-id",
    "unfinalized-summary-string",
    "numeric-originatorless-refusal",
    "invalid-payload-shapes",
  ],
  "identifier-persistence": [
    "initial-summary-defaults",
    "summary-tail",
    "transaction-abort",
    "nested-abort",
    "retry-resubmit",
    "remove-retain-repair",
    "equal-custom-id-replacement",
    "node-moves",
  ],
};

function identifierCaseFixture(id, domain) {
  const scenarios = identifierScenarioIds[id].map((scenarioId) => ({
    id: scenarioId,
    actions: [{ op: "observe", path: [], purpose: "message" }],
  }));
  if (id === "identifier-field-batches") {
    scenarios.find(({ id: scenarioId }) => scenarioId === "local-negative-op-id").actions = [{
      op: "decode-field-batch",
      path: ["identifier"],
      encoded: { value: -1 },
      purpose: "message",
      originator: "11111111-1111-4111-8111-111111111111",
    }];
    scenarios.find(({ id: scenarioId }) => scenarioId === "eager-final-id").actions = [
      { op: "allocate-id", compressor: "summary" },
      {
        op: "decode-field-batch",
        path: ["identifier"],
        encoded: { value: 0 },
        purpose: "summary",
      },
    ];
  }
  if (id === "identifier-persistence") {
    scenarios.find(({ id: scenarioId }) => scenarioId === "summary-tail").actions = [
      {
        op: "load-summary",
        purpose: "summary",
        summary: { type: "tree", tree: {} },
        compressor: "summary-compressor",
        session: "33333333-3333-4333-8333-333333333333",
      },
      {
        op: "apply-tail",
        purpose: "message",
        messages: [{ contents: { changeset: [] } }],
        idRanges: [{
          sessionId: "11111111-1111-4111-8111-111111111111",
          ids: { firstGenCount: 1, count: 1, localIdRanges: [[1, 1]] },
        }],
      },
    ];
    scenarios.find(({ id: scenarioId }) =>
      scenarioId === "equal-custom-id-replacement").actions = [0, 1].map(() => ({
        op: "set",
        path: ["child"],
        value: {
          schema: "org.watershed.shared-tree.identifiers.Point",
          fields: { id: "literal-custom-id", label: "replacement" },
        },
      }));
  }
  const observations = scenarios.map(({ id: scenarioId }) => ({
    id: scenarioId,
    observed: true,
  }));
  if (id === "identifier-values") {
    observations.find(({ id: scenarioId }) => scenarioId === "allocation-order").events = [
      { ordinal: 1, kind: "identifier", path: ["left", 1, "firstId"], op: 2 },
      { ordinal: 2, kind: "identifier", path: ["left", 1, "secondId"], op: 3 },
      { ordinal: 3, kind: "revision", path: [], op: 4 },
    ];
    observations.find(({ id: scenarioId }) => scenarioId === "nested-insertion")
      .allocationEvents = [
        { ordinal: 1, kind: "identifier", path: ["byKey", "map", "id"], op: 1 },
        { ordinal: 2, kind: "identifier", path: ["left", 0, "id"], op: 2 },
        { ordinal: 3, kind: "identifier", path: ["child", "id"], op: 3 },
        { ordinal: 4, kind: "revision", path: [], op: 4 },
      ];
  }
  if (id === "identifier-schema") {
    for (const scenarioId of ["non-string-refusal", "union-refusal"]) {
      Object.assign(observations.find(({ id }) => id === scenarioId), {
        upstreamAccepted: true,
        nativeProfileSupported: false,
      });
    }
  }
  if (id === "identifier-field-batches") {
    observations.find(({ id: scenarioId }) => scenarioId === "literal-zero-string")
      .discriminator = 0;
    Object.assign(
      observations.find(({ id: scenarioId }) => scenarioId === "numeric-originatorless-refusal"),
      {
        refused: true,
        originalError: "Error: refused",
        nativeErrorCategory: "Error",
      },
    );
    observations.find(({ id: scenarioId }) => scenarioId === "invalid-payload-shapes")
      .refusals = [{
        value: null,
        originalError: "Error: refused",
        nativeErrorCategory: "Error",
      }];
    Object.assign(
      observations.find(({ id: scenarioId }) => scenarioId === "eager-final-id"),
      {
        value: "eager",
        decodedByUpstream: "eager",
        allocatedAfterFinalization: true,
      },
    );
  }
  if (id === "identifier-persistence") {
    observations.find(({ id: scenarioId }) => scenarioId === "summary-tail").value =
      { child: { id: "tail" } };
    Object.assign(
      observations.find(({ id: scenarioId }) => scenarioId === "equal-custom-id-replacement"),
      {
        nodeReplaced: true,
        beforeNode: "1:node",
        afterNode: "2:node",
        sameNodeTokenStable: true,
      },
    );
  }
  return {
    formatVersion: 1,
    reference: {
      package: "@fluidframework/tree",
      version: "3.1.0",
      commit: "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960",
    },
    id,
    domain,
    input: {
      version: 1,
      schema: { version: 2 },
      initialTree: null,
      sessions: {
        local: "11111111-1111-4111-8111-111111111111",
        remote: "22222222-2222-4222-8222-222222222222",
      },
      compressors: {
        initial: "serialized-compressor",
      },
      idRanges: [],
      scenarios,
    },
    expected: {
      observations,
    },
    raw: {
      scenarios: scenarios.map((input, index) => ({
        id: input.id,
        input: structuredClone(input),
        before: null,
        after: id === "identifier-persistence" && input.id === "summary-tail"
          ? structuredClone(observations[index].value)
          : structuredClone(observations[index]),
        observation: structuredClone(observations[index]),
      })),
    },
  };
}

function cases(exclude = []) {
  const synthetic = {
    "map-schema-content": mapSchemaCaseFixture,
    "map-field-algebra": mapFieldCaseFixture,
    "map-history-codecs": mapHistoryCaseFixture,
    "schema-evolution-compatibility": () => schemaEvolutionCaseFixture(
      "schema-evolution-compatibility",
      "schema",
      ["v1", "optional", "object-union", "map-union", "optional-title", "root-union",
        "optional-root", "combined", "narrow", "new-required"],
    ),
    "schema-evolution-algebra": () => schemaEvolutionCaseFixture(
      "schema-evolution-algebra",
      "tree",
      ["schema-over-data", "data-over-schema", "schema-over-schema", "empty-operand",
        "data-schema-data-schema-compose", "inverse-schema-encoding-refusal"],
    ),
    "schema-evolution-history": () => schemaEvolutionCaseFixture(
      "schema-evolution-history",
      "history",
      schemaEvolutionHistoryScenarioIds,
    ),
    "schema-evolution-codecs": () => schemaEvolutionCaseFixture(
      "schema-evolution-codecs",
      "codec",
      ["schema-only-commit", "empty-outer-commit", "historical-schema-decode",
        "pending-upgrade-summary"],
    ),
    "transaction-callbacks": () => transactionCaseFixture("transaction-callbacks", "tree"),
    "transaction-constraints": () => transactionCaseFixture(
      "transaction-constraints",
      "modular",
    ),
    "transaction-wire": () => transactionCaseFixture("transaction-wire", "codec"),
    "transaction-history": () => transactionCaseFixture("transaction-history", "history"),
    ...Object.fromEntries(identifierCases.map(([id, domain]) => [
      id,
      () => identifierCaseFixture(id, domain),
    ])),
  };
  return requiredCases.filter(([id]) => !exclude.includes(id)).map(([id]) =>
    synthetic[id]?.() ?? JSON.parse(readFileSync(
      new URL(`../../test/fixtures/shared_tree/cases/${id}.json`, import.meta.url), "utf8",
    )));
}

function transactionMessage() {
  return {
    version: 7,
    revision: 0,
    originatorId: "00000000-0000-4000-8000-000000000001",
    changeset: [{ data: { changes: [] } }],
  };
}

function transactionDataChange(constraintViolationCount = 0) {
  return {
    maxId: 0,
    revisions: [{ revision: "00000000-0000-4000-8000-000000000002", rollbackOf: null }],
    fields: [],
    nodes: [],
    parents: [],
    aliases: [],
    builds: [],
    destroys: [],
    refreshers: [],
    constraintViolationCount,
    delta: {
      fields: [],
      builds: [],
      refreshers: [],
      global: [],
      renames: [],
      destroys: [],
    },
  };
}

function transactionCommit(constraintViolationCount = 0) {
  return {
    revision: "00000000-0000-4000-8000-000000000002",
    changes: [{ type: "data", change: transactionDataChange(constraintViolationCount) }],
  };
}

function transactionCaseFixture(id, domain) {
  const value = {
    formatVersion: 1,
    reference: {
      package: "@fluidframework/tree",
      version: "3.1.0",
      commit: "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960",
    },
    id,
    domain,
    input: {
      scenarios: [{ id: `${id}-source`, actions: [{ op: "capture" }] }],
    },
    expected: {
      observations: [{ id: `${id}-source`, captured: true }],
    },
    raw: {
      messages: [{ version: 7, changeset: { changes: [] } }],
    },
  };
  if (id === "transaction-callbacks") {
    value.input.scenarios = [
      {
        id: "success-all-fields",
        operations: [
          "object-set", "object-delete", "map-set", "map-delete",
          "array-insert", "array-remove", "array-replace",
          "same-array-move", "cross-array-move",
        ],
      },
      { id: "outer-rollback" },
      { id: "nested-success" },
      { id: "nested-rollback" },
      { id: "no-op" },
      { id: "invalid-edit-rollback", operation: "array-remove-negative-index" },
    ];
    value.expected.observations = value.input.scenarios.map(({ id: scenario }) => ({
      id: scenario,
      identity: { nodes: ["node"], before: ["node"], preserved: ["node"] },
      allocation: {
        before: {
          sessionId: "session",
          ongoing: "before",
        },
        after: {
          sessionId: "session",
          ongoing: "after",
        },
      },
      compressor: "state",
      reads: scenario === "success-all-fields"
        ? [
          "object-set", "object-delete", "map-set", "map-delete",
          "array-insert", "array-remove", "array-replace",
          "same-array-move", "cross-array-move",
        ].map((step) => ({ step }))
        : [{
          step: scenario === "invalid-edit-rollback" ? "valid-edit-before-invalid" : "inside",
          ...(scenario === "invalid-edit-rollback"
            ? { value: { title: "before-invalid" } }
            : {}),
        }],
      final: { state: scenario },
      retainedDetached: [],
      history: { pending: [], trunk: [] },
      events: ["outer-rollback", "no-op", "invalid-edit-rollback"].includes(scenario)
        ? []
        : [{ kind: "changed" }],
      commitCount: ["outer-rollback", "no-op", "invalid-edit-rollback"].includes(scenario) ? 0 : 1,
      pendingCommitCount: ["outer-rollback", "no-op", "invalid-edit-rollback"].includes(scenario)
        ? 0
        : 1,
      submittedMessages: ["outer-rollback", "no-op", "invalid-edit-rollback"].includes(scenario)
        ? []
        : [transactionMessage()],
      ...(scenario === "invalid-edit-rollback" ? {
        error: "Error: Expected non-negative index passed to TreeArrayNode.removeAt, got -1.",
        transactionResult: "rollback",
        localCompressorAdvanced: true,
        state: {
          before: {
            visible: { state: "unchanged" },
            identities: ["node"],
            retainedDetached: [],
            compressor: "state",
            allocation: { sessionId: "session", ongoing: "state" },
            history: { pending: [], trunk: [] },
          },
          after: {
            visible: { state: "unchanged" },
            identities: ["node"],
            retainedDetached: [],
            compressor: "state",
            allocation: { sessionId: "session", ongoing: "state" },
            history: { pending: [], trunk: [] },
          },
        },
      } : {}),
    }));
    value.raw.scenarios = structuredClone(value.expected.observations);
    value.raw.messages = value.expected.observations.flatMap(
      ({ submittedMessages }) => submittedMessages,
    );
  }
  if (id === "transaction-constraints") {
    value.expected.observations = [{
      id: "node-in-document",
      clients: { writer: { state: "same" }, peer: { state: "same" } },
      converged: true,
      constraintViolationCount: 1,
      retainedBuilds: [{ id: "build" }],
      refusal: { callbackRan: false, error: "not currently in the document" },
      withinMove: { identityPreserved: true },
      crossMove: { identityPreserved: true },
      pending: { pending: [transactionCommit()], trunk: [] },
      settled: { pending: [], trunk: [transactionCommit(1)] },
      reconnectMessages: [transactionMessage()],
    }];
  }
  if (id === "transaction-wire") {
    const nonviolatedChangeset = [{ data: { change: 1 } }];
    const violatedChangeset = [{ data: { change: 2 } }];
    const overChangeset = [{ data: { changes: [{ fieldKey: "left" }] } }];
    value.input.scenarios[0].duplicates = 2;
    value.input.messageBytes = {
      nonviolated: JSON.stringify({
        version: 7,
        originatorId: "author-session",
        changeset: nonviolatedChangeset,
        nodeExistsConstraint: { violated: false },
        builds: {},
        left: { label: "value" },
      }),
      violated: JSON.stringify({
        version: 7,
        changeset: violatedChangeset,
        nodeExistsConstraint: { violated: true },
        violations: 1,
        builds: {},
        refreshers: {},
      }),
      over: JSON.stringify({
        version: 7,
        changeset: overChangeset,
      }),
    };
    value.input.compressor = JSON.parse(readFileSync(
      new URL(
        "../../test/fixtures/shared_tree/cases/transaction-wire.json",
        import.meta.url,
      ),
      "utf8",
    )).input.compressor;
    value.input.context = {
      message: 7,
      sharedTreeChange: 5,
      modularChange: 5,
      minVersionForCollab: "2.117.0",
    };
    value.input.operands = {
      nonviolated: { revision: "r", changeset: nonviolatedChangeset },
      violated: { revision: "r", changeset: violatedChangeset },
      compose: { changes: [{ revision: "r", changeset: nonviolatedChangeset }] },
      invert: {
        change: { revision: "r", changeset: nonviolatedChangeset },
        isRollback: false,
      },
      rebase: {
        change: {
          revision: "r",
          changeset: violatedChangeset,
          decoded: [{ change: { constraintViolationCount: 1 } }],
        },
        over: { revision: "o", changeset: overChangeset, decoded: [{ change: ["over"] }] },
        revisionMetadata: [
          { revision: "r", rollbackOf: null },
          { revision: "o", rollbackOf: null },
        ],
      },
    };
    value.input.operands.invert.inverseRevision = "inverse";
    value.expected.observations = [{
      id: "modular-v5-shared-tree-v5",
      nonviolated: { revision: "r", changes: [{ change: [1] }] },
      violated: { revision: "r", changes: [{ change: [2] }] },
      composed: [{ change: [3] }],
      inverted: [{ change: [4] }],
      rebased: { changes: [{ change: [5] }] },
    }];
    value.raw.algebra = {
      nonviolatedOperand: {
        revision: value.expected.observations[0].nonviolated.revision,
        changes: value.expected.observations[0].nonviolated.changes,
      },
      composed: value.expected.observations[0].composed,
      inverted: value.expected.observations[0].inverted,
      rebaseOperands: {
        change: {
          revision: "r",
          changes: value.input.operands.rebase.change.decoded,
        },
        over: {
          revision: "o",
          changes: value.input.operands.rebase.over.decoded,
        },
      },
      rebased: value.expected.observations[0].rebased.changes,
    };
  }
  if (id === "transaction-history") {
    value.input.summary = { tree: {} };
    value.input.compressor = { serialized: "summary-compressor", sessionId: "session" };
    value.input.tailEnvelope = { contents: { version: 7, changeset: [{ data: {} }] } };
    value.input.tailAllocationRanges = [{
      sessionId: "tail-session",
      ids: {
        firstGenCount: 1,
        count: 1,
        requestedClusterSize: 512,
        localIdRanges: [[1, 1]],
      },
    }];
    value.input.continuation = {
      edits: [{ op: "insert" }],
      creationRange: {
        sessionId: "continuation-session",
        ids: {
          firstGenCount: 1,
          count: 1,
          requestedClusterSize: 512,
          localIdRanges: [[1, 1]],
        },
      },
    };
    value.expected.observations = [{
      id: "reconnect-summary-history",
      pending: { state: "pending" },
      pendingViolation: transactionCommit(1),
      pendingCompressor: "summary-compressor",
      missingTailAllocationError: "Error: unknown compressed ID",
      loaded: { state: "loaded" },
      afterTail: { state: "tail" },
      afterContinuation: { state: "continued" },
      peer: { state: "continued" },
      reconnectMessages: [transactionMessage()],
      checkpoints: [
        "pending", "sequenced-summary", "acknowledged-violation", "loaded-summary",
        "after-tail", "after-continuation", "peer-after-continuation",
      ].map((checkpoint) => ({
        id: checkpoint,
        identities: ["node"],
        retainedDetached: [],
        compressor: "state",
        allocation: { sessionId: "session", ongoing: "captured" },
        history: { pending: [], trunk: [] },
        visible: { state: checkpoint },
      })),
    }];
    value.expected.observations[0].afterContinuation = {
      visible: { state: "continued" },
      identities: ["node"],
    };
    value.expected.observations[0].peer = {
      visible: { state: "continued" },
      identities: ["node"],
    };
    value.raw.tailAllocationRanges = structuredClone(value.input.tailAllocationRanges);
    value.raw.summary = structuredClone(value.input.summary);
    value.raw.tailEnvelope = structuredClone(value.input.tailEnvelope);
    value.raw.continuationEnvelope = transactionMessage();
    value.raw.messages = [transactionMessage()];
    value.raw.observation = structuredClone(value.expected.observations[0]);
  }
  return value;
}

function schemaEvolutionCaseFixture(id, domain, scenarioIds) {
  const schema = JSON.stringify({
    version: 2,
    nodes: {},
    root: { kind: "Forbidden", types: [] },
  });
  const schemaIds = [
    "v1", "optional", "object-union", "map-union", "optional-title",
    "root-union", "optional-root", "combined", "narrow", "new-required",
    ...(id === "schema-evolution-history" ? ["new-node"] : []),
    ...(id === "schema-evolution-compatibility"
      ? ["optional-to-required", "node-kind-replacement", "sequence", "handle"]
      : []),
  ];
  const schemas = schemaIds.map((schemaId) => ({ id: schemaId, raw: schema }));
  const scenario = (scenarioId) => ({
    id: scenarioId,
    actions: {
      "upgrade-then-edit-causal": [
        { op: "upgrade", schema: "optional" },
        { op: "set", path: ["score"], value: 7 },
        { op: "sequence", count: "all" },
      ],
      "pending-upgrade-dependent-data-loses": [
        { op: "set", tree: 1, path: ["title"], value: "wins" },
        { op: "upgrade", tree: 0, schema: "optional" },
        { op: "set", tree: 0, path: ["score"], value: 7 },
      ],
      "ack-common-prefix-keeps-upgrade": [
        { op: "upgrade", tree: 0, schema: "optional" },
        { op: "set", tree: 0, path: ["score"], value: 7 },
        { op: "sequence-through", change: "schema" },
      ],
      "rollback-retains-new-type-content": [
        { op: "upgrade", tree: 1, schema: "new-node" },
        {
          op: "set",
          tree: 1,
          path: ["extra", "value"],
          value: "retained",
          identity: { revision: -2, localId: 0 },
        },
        {
          op: "set",
          tree: 0,
          path: ["title"],
          value: "wins",
          identity: { revision: -2, localId: 0 },
          detachedLocalId: 1,
        },
        { op: "sequence", order: "tree-0-first" },
      ],
      "new-view-reopens": [
        { op: "upgrade", tree: 0, schema: "optional" },
        { op: "sequence", count: "all" },
        { op: "dispose-view", tree: 1 },
        { op: "open-view", tree: 1, schema: "optional" },
      ],
      "historical-peer-schema-context": [
        { op: "set", tree: 1, path: ["title"], value: "historical", schema: "v1" },
        { op: "sequence-through", change: "id-allocation" },
        { op: "pause-inbound", tree: 0 },
        { op: "upgrade", tree: 0, schema: "optional" },
        { op: "decode", schema: "v1" },
        { op: "resume-inbound", tree: 0 },
      ],
    }[scenarioId] ?? [{ op: "capture", target: scenarioId }],
    sessions: scenarioId === "rollback-retains-new-type-content" ? [
      {
        tree: "tree-0",
        session: "8f95be09-8376-4ff7-8755-ccd7e8124b06",
        compressor: {
          state: "compressor-state",
          allocations: [{ firstGenCount: 2, count: 1 }],
        },
      },
      {
        tree: "tree-1",
        session: "a0693eac-892a-4396-86f7-ad20dc1cade2",
        compressor: {
          state: "compressor-state",
          allocations: [{ firstGenCount: 2, count: 1 }],
        },
      },
    ] : [{
      tree: "tree-0",
      session: "session-0",
      compressor: { state: "compressor-state", allocations: [{ firstGenCount: 1, count: 1 }] },
    }],
    sequencePoints: [{
      sequenceNumber: 1,
      referenceSequenceNumber: 0,
      minimumSequenceNumber: 0,
      clientSequenceNumber: 1,
      clientId: "client-0",
      indexInBatch: 0,
    }],
  });
  const checkpoint = (scenarioId) => ({
    id: scenarioId,
    visibleSchema: "optional",
    sequencedSchema: "optional",
    visibleRoot: {
      tree: [{
        type: "org.watershed.shared-tree.m4.Root",
        fields: {
          title: [{ type: "com.fluidframework.leaf.string", value: "base" }],
          point: [{
            type: "org.watershed.shared-tree.m4.Point",
            fields: {
              x: [{ type: "com.fluidframework.leaf.number", value: 1 }],
              y: [{ type: "com.fluidframework.leaf.number", value: 2 }],
            },
          }],
          items: [{
            type: "org.watershed.shared-tree.m4.Items",
            fields: {
              label: [{ type: "com.fluidframework.leaf.string", value: "value" }],
            },
          }],
        },
      }],
      removed: [],
    },
    pendingRevisions: [{ revision: 2, kinds: ["data"] }],
    outerChanges: [{ revision: 2, kinds: ["data"] }],
    trunkRevisions: [{ revision: 1, kinds: ["schema"] }],
    peerRevisions: [{ revision: 1, kinds: ["schema"] }],
    detachedIdentities: [],
    events: [],
    compatibility: { canView: true, canUpgrade: true, isEquivalent: true },
  });
  const observations = scenarioIds.map(checkpoint);
  const raw = {
    schemaMessages: [{ changeset: [{ schema: { old: {}, new: {} } }] }],
    schemaMessageBytes: ["{\"schema\":true}"],
  };
  const input = {
    schemas,
    scenarios: scenarioIds.map(scenario),
  };
  if (id === "schema-evolution-compatibility") {
    input.refusals = [
      "narrow", "new-required", "optional-to-required",
      "node-kind-replacement", "sequence", "handle",
    ].map((profileId) => ({ id: profileId, operation: "upgrade-attempt" }));
    input.rawProbes = [
      "metadata", "duplicate-keys", "ordering", "unused-definitions", "required-cycle",
    ].map((probeId) => ({ id: probeId, raw: "{\"version\":2}" }));
    for (const observation of observations) {
      observation.compatibility = { canView: true, canUpgrade: true, isEquivalent: true };
      observation.attempt = {
        attempted: true,
        outcome: "accepted",
        submittedMessages: 1,
        beforeRoot: checkpoint(observation.id).visibleRoot,
        afterRoot: checkpoint(observation.id).visibleRoot,
      };
    }
    raw.rawProbeResults = input.rawProbes.map(({ id: probeId }) => ({
      id: probeId,
      parsed: true,
      compatibility: { canView: true, canUpgrade: true, isEquivalent: true },
    }));
    raw.refusalAttempts = input.refusals.map(({ id: profileId }) => ({
      id: profileId,
      attempted: true,
      outcome: ["node-kind-replacement", "sequence", "handle"].includes(profileId)
        ? "accepted"
        : "refused",
      classification: ["node-kind-replacement", "sequence", "handle"].includes(profileId)
        ? "m4-profile-exclusion"
        : "upstream-refusal",
      compatibility: { canView: false, canUpgrade: true, isEquivalent: false },
      error: ["node-kind-replacement", "sequence", "handle"].includes(profileId)
        ? undefined
        : "Refused by pinned upstream",
      submittedMessages: 1,
      beforeRoot: checkpoint(profileId).visibleRoot,
      afterRoot: checkpoint(profileId).visibleRoot,
    }));
  } else if (id === "schema-evolution-algebra") {
    input.operands = {
      schemaChange: {
        changes: [{
          type: "schema",
          innerChange: {
            schema: {
              old: { nodeSchema: { $type: "Map", entries: [["old", {}]] } },
              new: { nodeSchema: { $type: "Map", entries: [["new", {}]] } },
            },
          },
        }],
      },
      dataChange: {
        changes: [{
          type: "data",
          innerChange: { nodeChanges: { $type: "Map", entries: [[0, {}]] } },
        }],
      },
      secondSchemaChange: {
        changes: [{
          type: "schema",
          innerChange: {
            schema: {
              old: { nodeSchema: { $type: "Map", entries: [["optional", {}]] } },
              new: { nodeSchema: { $type: "Map", entries: [["object-union", {}]] } },
            },
          },
        }],
      },
    };
    input.revisions = { schema: 1, data: 2, secondData: 3, secondSchema: 4, inverse: 5 };
    input.transitions = [
      {
        from: "data",
        to: "schema",
        revision: 1,
        before: "v1",
        after: "optional",
        change: input.operands.schemaChange,
      },
      {
        from: "secondData",
        to: "secondSchema",
        revision: 4,
        before: "optional",
        after: "object-union",
        change: input.operands.secondSchemaChange,
      },
    ];
    raw.composed = { changes: [{ type: "schema" }, { type: "data" }] };
    raw.inverted = { changes: [{ type: "schema", revision: 4 }] };
    raw.revisionResults = { composed: 3, inverted: 4 };
  } else if (id === "schema-evolution-history") {
    input.rollbackReplay = {
      scenario: "rollback-retains-new-type-content",
      detachedId: {
        revision: "a0693eac-892a-4396-86f7-ad20dc1cade3",
        localId: 0,
      },
    };
    Object.assign(observations.find(({ id: scenarioId }) =>
      scenarioId === "ack-common-prefix-keeps-upgrade"), {
      acknowledgedSchema: true,
      remainingDependentEdit: { revision: 2, kinds: ["data"] },
    });
    Object.assign(observations.find(({ id: scenarioId }) =>
      scenarioId === "rollback-retains-new-type-content"), {
      losingAuthorBefore: checkpoint("rollback").visibleRoot,
      losingAuthorAfter: checkpoint("rollback").visibleRoot,
      losingAuthorSchema: "new-node",
      losingAuthorSchemaAfter: "v1",
      losingAuthorPending: [{ revision: 2, kinds: ["schema", "data"] }],
      pendingAfterCompetingEdit: [{ revision: 3, kinds: ["schema"] }],
      retainedExtra: { type: "org.watershed.shared-tree.m4.Extra", value: "retained" },
    });
    Object.assign(observations.find(({ id: scenarioId }) =>
      scenarioId === "reconnect-upgrade-accepted-before-drop"), {
      acceptedMessage: { sequenceNumber: 3, bytes: "{\"schema\":true}" },
      replay: {
        submitted: 1,
        bytes: ["{\"schema\":true}"],
        originalRevision: 1,
        replayRevisions: [1],
        peerSchemaCommitDelta: 1,
        finalSchema: "optional",
        finalPending: 0,
      },
    });
    Object.assign(observations.find(({ id: scenarioId }) =>
      scenarioId === "new-view-reopens"), {
      reopenedPeer: { tree: "tree-1", schema: "optional", root: checkpoint("reopen").visibleRoot },
    });
    Object.assign(observations.find(({ id: scenarioId }) =>
      scenarioId === "summary-upgrade-plus-tail"), {
      continuation: {
        loadedSummary: true,
        summary: { type: 1, tree: { indexes: { type: 1, tree: {} } } },
        before: checkpoint("summary-before").visibleRoot,
        tailBytes: ["{\"tail\":true}"],
        replayed: true,
        root: checkpoint("summary").visibleRoot,
      },
    });
    Object.assign(observations.find(({ id: scenarioId }) =>
      scenarioId === "historical-peer-schema-context"), {
      historicalDecode: {
        operation: "decode",
        bytes: "{\"data\":true}",
        decoded: {
          changes: [{
            type: "data",
            innerChange: {
              fieldChanges: { $type: "Map", entries: [["rootFieldKey", {}]] },
            },
          }],
        },
        envelope: { type: "commit", commit: { revision: 1 } },
        authoringSchema: "v1",
        visibleSchema: "optional",
        visibleSchemaAfterSynchronization: "v1",
        decodedBeforeInboundResume: true,
        context: {
          authoringSchema: "v1",
          visibleSchema: "optional",
          inboundProcessing: "paused",
        },
      },
    });
  } else if (id === "schema-evolution-codecs") {
    Object.assign(observations.find(({ id: scenarioId }) =>
      scenarioId === "historical-schema-decode"), {
      operations: [{
        operation: "decode",
        bytes: "{\"data\":true}",
        decoded: {
          changes: [{
            type: "data",
            innerChange: {
              fieldChanges: { $type: "Map", entries: [["rootFieldKey", {}]] },
            },
          }],
        },
        envelope: { type: "commit", commit: { revision: 1 } },
        visibleSchemaAfterSynchronization: "v1",
        decodedBeforeInboundResume: true,
        context: {
          authoringSchema: "v1",
          visibleSchema: "optional",
          inboundProcessing: "paused",
        },
      }],
    });
  }
  return {
    formatVersion: 1,
    reference: {
      package: "@fluidframework/tree",
      version: "3.1.0",
      commit: "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960",
    },
    id,
    domain,
    input,
    expected: {
      observations,
    },
    raw,
  };
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
  assert.equal(requiredCases.length, 50);
  assert(requiredCases.some(([id, domain]) => id === "tree-codecs" && domain === "codec"));
});

test("corpus registers the complete Identifier contract", () => {
  assert.deepEqual(
    requiredCases.filter(([id]) => id.startsWith("identifier-")),
    identifierCases,
  );
});

test("Identifier corpus rejects missing cases and incomplete executable evidence", () => {
  const withoutIdentifierCase = (capture, id) =>
    capture.filter(({ id: candidate }) => candidate !== id);
  const complete = cases();
  assert.doesNotThrow(() => validateCases(complete));
  assert.throws(
    () => validateCases(withoutIdentifierCase(complete, "identifier-field-batches")),
    /identifier-field-batches/,
  );

  const withoutCompressor = structuredClone(complete);
  delete withoutCompressor.find(({ id }) => id === "identifier-values").input.compressors;
  assert.throws(() => validateCases(withoutCompressor), /identifier-values/);

  const withoutNumericId = structuredClone(complete);
  withoutNumericId.find(({ id }) => id === "identifier-field-batches").input.scenarios
    .find(({ id }) => id === "local-negative-op-id").actions = [];
  assert.throws(() => validateCases(withoutNumericId), /identifier-field-batches/);

  const withoutObservation = structuredClone(complete);
  withoutObservation.find(({ id }) => id === "identifier-persistence")
    .expected.observations.pop();
  assert.throws(() => validateCases(withoutObservation), /identifier-persistence/);

  const withoutOriginalError = structuredClone(complete);
  delete withoutOriginalError.find(({ id }) => id === "identifier-field-batches")
    .expected.observations.find(({ id }) => id === "numeric-originatorless-refusal")
    .originalError;
  delete withoutOriginalError.find(({ id }) => id === "identifier-field-batches")
    .raw.scenarios.find(({ id }) => id === "numeric-originatorless-refusal")
    .observation.originalError;
  assert.throws(() => validateCases(withoutOriginalError), /original error/);

  const withoutErrorCategory = structuredClone(complete);
  delete withoutErrorCategory.find(({ id }) => id === "identifier-field-batches")
    .expected.observations.find(({ id }) => id === "invalid-payload-shapes")
    .refusals[0].nativeErrorCategory;
  delete withoutErrorCategory.find(({ id }) => id === "identifier-field-batches")
    .raw.scenarios.find(({ id }) => id === "invalid-payload-shapes")
    .observation.refusals[0].nativeErrorCategory;
  assert.throws(() => validateCases(withoutErrorCategory), /error category/);
});

test("Identifier fixtures preserve executable capture evidence", () => {
  const fixture = (id) => JSON.parse(readFileSync(
    new URL(`../../test/fixtures/shared_tree/cases/${id}.json`, import.meta.url),
    "utf8",
  ));
  const schema = fixture("identifier-schema");
  for (const id of ["non-string-refusal", "union-refusal"]) {
    const observation = schema.expected.observations.find((item) => item.id === id);
    assert.equal(typeof observation.upstreamAccepted, "boolean", id);
    assert.equal(observation.nativeProfileSupported, false, id);
    assert.doesNotMatch(observation.originalError ?? "", /Expected the operation to be refused/);
  }

  const values = fixture("identifier-values");
  const allocation = values.expected.observations
    .find(({ id }) => id === "allocation-order").events;
  assert.deepEqual(allocation.map(({ ordinal, kind, path }) => ({ ordinal, kind, path })), [
    { ordinal: 1, kind: "identifier", path: ["left", 1, "firstId"] },
    { ordinal: 2, kind: "identifier", path: ["left", 1, "secondId"] },
    { ordinal: 3, kind: "revision", path: [] },
  ]);
  const nested = values.expected.observations
    .find(({ id }) => id === "nested-insertion").allocationEvents;
  assert.deepEqual(nested.map(({ ordinal, kind, path }) => ({ ordinal, kind, path })), [
    { ordinal: 1, kind: "identifier", path: ["byKey", "map", "id"] },
    { ordinal: 2, kind: "identifier", path: ["left", 0, "id"] },
    { ordinal: 3, kind: "identifier", path: ["child", "id"] },
    { ordinal: 4, kind: "revision", path: [] },
  ]);
  for (const scenario of values.input.scenarios) {
    const execution = values.raw.scenarios.find(({ id }) => id === scenario.id);
    assert.deepEqual(execution.input, scenario);
    assert(Object.hasOwn(execution, "before"));
    assert(Object.hasOwn(execution, "after"));
  }
  assert.deepEqual(Object.keys(values.input.compressors), ["initial"]);

  const batches = fixture("identifier-field-batches");
  const eager = batches.expected.observations.find(({ id }) => id === "eager-final-id");
  assert.equal(eager.allocatedAfterFinalization, true);
  assert.equal(eager.decodedByUpstream, eager.value);

  const persistence = fixture("identifier-persistence");
  const tail = persistence.input.scenarios.find(({ id }) => id === "summary-tail");
  const load = tail.actions.find(({ op }) => op === "load-summary");
  const apply = tail.actions.find(({ op }) => op === "apply-tail");
  assert(load.summary && typeof load.compressor === "string");
  assert(Array.isArray(apply.messages) && apply.messages.length > 0);
  assert(Array.isArray(apply.idRanges));
  const tailExecution = persistence.raw.scenarios.find(({ id }) => id === "summary-tail");
  assert.deepEqual(
    persistence.expected.observations.find(({ id }) => id === "summary-tail").value,
    tailExecution.after,
  );
  const replacement = persistence.input.scenarios
    .find(({ id }) => id === "equal-custom-id-replacement").actions[0];
  assert.equal(replacement.value.fields.id, "literal-custom-id");
  const replacementObservation = persistence.expected.observations
    .find(({ id }) => id === "equal-custom-id-replacement");
  assert.notEqual(replacementObservation.beforeNode, replacementObservation.afterNode);
  assert.equal(replacementObservation.sameNodeTokenStable, true);
});

test("M3 requires sequence replay evidence", () => {
  assert.equal(new Map(requiredCases).get("sequence-rebase"), "field");
});

test("sequence empty insert preserves raw evidence and checked normalization", () => {
  const value = JSON.parse(readFileSync(
    new URL("../../test/fixtures/shared_tree/cases/sequence-field-editor.json", import.meta.url),
    "utf8",
  ));
  const raw = value.raw.scenarios.find(({ id }) => id === "empty-insert").output;
  const normalized = value.expected.observations.find(({ id }) => id === "empty-insert").value;
  assert(raw.change.some((mark) => mark.type === "Insert" && mark.count === 0));
  assert.deepEqual(normalized, { change: [], delta: {} });
});

test("sequence normalization cannot hide other raw editor output", () => {
  const value = JSON.parse(readFileSync(
    new URL("../../test/fixtures/shared_tree/cases/sequence-field-editor.json", import.meta.url),
    "utf8",
  ));
  const raw = value.raw.scenarios.find(({ id }) => id === "insert");
  const observation = value.expected.observations.find(({ id }) => id === "insert");
  raw.normalizedOutput = { change: [], delta: {} };
  observation.value = raw.normalizedOutput;
  observation.result = raw.normalizedOutput;
  assert.throws(() => validateArrayCase(value), /empty insert normalization/i);
});

test("sequence compose codec evidence preserves raw bytes behind semantic normalization", () => {
  const value = JSON.parse(readFileSync(
    new URL("../../test/fixtures/shared_tree/cases/sequence-compose-invert.json", import.meta.url),
    "utf8",
  ));
  const raw = value.raw.scenarios.find(({ id }) => id === "mark-families");
  const observation = value.expected.observations.find(({ id }) => id === "mark-families");
  assert(raw.output.codec?.encoded !== undefined);
  assert(Array.isArray(raw.output.codec?.decoded));
  assert(Array.isArray(raw.normalizedOutput?.changes));
  assert(raw.normalizedOutput?.delta !== undefined);
  assert.equal("codec" in raw.normalizedOutput, false);
  assert.deepEqual(observation.result, raw.normalizedOutput);
});

test("sequence compose codec normalization rejects missing raw codec evidence", () => {
  const value = JSON.parse(readFileSync(
    new URL("../../test/fixtures/shared_tree/cases/sequence-compose-invert.json", import.meta.url),
    "utf8",
  ));
  const raw = value.raw.scenarios.find(({ id }) => id === "mark-families");
  delete raw.output.codec;
  assert.throws(() => validateArrayCase(value), /Task 5 codec normalization/i);
});

test("sequence compose codec normalization must use source-decoded marks", () => {
  const value = JSON.parse(readFileSync(
    new URL("../../test/fixtures/shared_tree/cases/sequence-compose-invert.json", import.meta.url),
    "utf8",
  ));
  const raw = value.raw.scenarios.find(({ id }) => id === "mark-families");
  const observation = value.expected.observations.find(({ id }) => id === "mark-families");
  raw.normalizedOutput.changes = [];
  observation.value = raw.normalizedOutput;
  observation.result = raw.normalizedOutput;
  assert.throws(() => validateArrayCase(value), /decoded codec normalization/i);
});

test("sequence empty insert normalization requires checked operands", () => {
  const fixture = JSON.parse(readFileSync(
    new URL("../../test/fixtures/shared_tree/cases/sequence-field-editor.json", import.meta.url),
    "utf8",
  ));
  for (const mutate of [
    (operands) => { operands.index = -1; },
    (operands) => { operands.index = Number.MAX_SAFE_INTEGER + 1; },
    (operands) => { operands.firstId.localId = -1; },
    (operands) => { operands.firstId.localId = Number.MAX_SAFE_INTEGER + 1; },
    (operands) => { operands.revision = {}; },
    (operands) => { operands.revision = "revision-a"; },
    (operands) => { operands.firstId.revision = "revision-a"; },
    (operands) => { operands.firstId.revision = null; },
    (operands) => {
      operands.firstId.minor = operands.firstId.localId;
      delete operands.firstId.localId;
    },
  ]) {
    const value = structuredClone(fixture);
    const input = value.input.scenarios.find(({ id }) => id === "empty-insert");
    const raw = value.raw.scenarios.find(({ id }) => id === "empty-insert");
    mutate(input.operands);
    mutate(raw.input.operands);
    assert.throws(() => validateArrayCase(value), /empty-insert insert operands/i);
  }
});

function arrayCaseFixture() {
  const scenarios = [
    {
      id: "move-interior",
      operation: "move",
      initialState: { left: ["A", "B"], right: [] },
      source: { path: ["left"], start: 0, end: 2 },
      destination: { path: ["left"], gap: 1 },
      operands: {
        sourceIndex: 0,
        count: 2,
        destinationIndex: 1,
        detachId: 5,
        attachId: { revision: "revision-a", localId: 7 },
        revision: "revision-a",
      },
      revisions: ["revision-a"],
      algorithm: {
        localIds: "supplied-by-operands",
        composeAllocator: "unused-by-pinned-source",
        rebaseAllocator: "unused-by-pinned-source",
      },
      compressor: { mode: "test", session: "session-a", serialized: "state-a" },
      sequencing: { sequenceNumber: 0, referenceSequenceNumber: 0, minimumSequenceNumber: 0 },
      schedule: [{ step: "move" }],
    },
    {
      id: "empty-remove",
      operation: "remove",
      initialState: { left: [], right: ["A", "B"] },
      source: { path: ["right"], start: 1, end: 1 },
      operands: {
        sourceIndex: 1,
        count: 0,
        detachId: 4,
        revision: "revision-b",
      },
      revisions: ["revision-b"],
      algorithm: {
        localIds: "supplied-by-operands",
        composeAllocator: "unused-by-pinned-source",
        rebaseAllocator: "unused-by-pinned-source",
      },
      compressor: { mode: "test", session: "session-a", serialized: "state-a" },
      sequencing: { sequenceNumber: 0, referenceSequenceNumber: 0, minimumSequenceNumber: 0 },
      schedule: [{ step: "remove" }],
    },
  ];
  return {
    formatVersion: 1,
    reference: {
      package: "@fluidframework/tree",
      version: "3.1.0",
      commit: "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960",
    },
    id: "sequence-field-editor",
    domain: "field",
    input: { scenarios },
    expected: {
      observations: scenarios.map(({ id }) => ({
        id,
        executed: true,
        emitted: [],
        visible: ["A", "B"],
        result: [],
      })),
    },
    raw: {
      scenarios: scenarios.map((input) => ({
        id: input.id,
        input: structuredClone(input),
        output: [],
      })),
    },
  };
}

test("array validation rejects missing and duplicate scenario IDs", () => {
  const valid = arrayCaseFixture();
  assert.doesNotThrow(() => validateArrayCase(valid, valid.input.scenarios.map(({ id }) => id)));
  for (const mutate of [
    (value) => { value.expected.observations.pop(); },
    (value) => { value.raw.scenarios[1].id = value.raw.scenarios[0].id; },
  ]) {
    const broken = arrayCaseFixture();
    mutate(broken);
    assert.throws(
      () => validateArrayCase(broken, valid.input.scenarios.map(({ id }) => id)),
      /scenario|duplicate/i,
    );
  }
});

test("array validation rejects malformed endpoints and wrong references", () => {
  for (const mutate of [
    (value) => { value.input.scenarios[0].source.end = -1; },
    (value) => { value.input.scenarios[0].destination.gap = 1.5; },
    (value) => { value.reference.commit = "other"; },
  ]) {
    const broken = arrayCaseFixture();
    mutate(broken);
    assert.throws(
      () => validateArrayCase(broken, broken.input.scenarios.map(({ id }) => id)),
      /endpoint|reference/i,
    );
  }
});

test("array validation rejects missing operation endpoints", () => {
  const broken = arrayCaseFixture();
  delete broken.input.scenarios[0].destination;
  delete broken.raw.scenarios[0].input.destination;
  assert.throws(
    () => validateArrayCase(broken, broken.input.scenarios.map(({ id }) => id)),
    /move-interior.*destination endpoint/i,
  );
});

test("array validation rejects raw and normalized input inconsistencies", () => {
  const broken = arrayCaseFixture();
  broken.raw.scenarios[0].input.destination.gap = 2;
  assert.throws(
    () => validateArrayCase(broken, broken.input.scenarios.map(({ id }) => id)),
    /raw.*input|normalized/i,
  );
});

test("sequence replay validation requires source call operands", () => {
  const valid = arrayCaseFixture();
  Object.assign(valid.input.scenarios[0], {
    detachId: 5,
    attachId: { revision: "revision-a", localId: 7 },
    revision: "revision-a",
  });
  valid.input.scenarios[0].operands = {
    sourceIndex: 0,
    count: 2,
    destinationIndex: 1,
    detachId: 5,
    attachId: { revision: "revision-a", localId: 7 },
    revision: "revision-a",
  };
  valid.raw.scenarios[0].input = structuredClone(valid.input.scenarios[0]);
  assert.doesNotThrow(() =>
    validateArrayCase(valid, valid.input.scenarios.map(({ id }) => id)));

  for (const name of ["detachId", "attachId", "revision"]) {
    const broken = structuredClone(valid);
    delete broken.input.scenarios[0].operands[name];
    delete broken.raw.scenarios[0].input.operands[name];
    assert.throws(
      () => validateArrayCase(broken, broken.input.scenarios.map(({ id }) => id)),
      /move-interior.*operand/i,
    );
  }
});

test("forest replay validation rejects lossy deltas", () => {
  const value = JSON.parse(readFileSync(
    new URL("../../test/fixtures/shared_tree/cases/array-forest-delta.json", import.meta.url),
    "utf8",
  ));
  const scenario = value.input.scenarios[0];
  scenario.operation = "apply-deltas";
  scenario.operands = {
    retainIndex: null,
    deltas: [{
      build: [{
        id: { major: scenario.revisions[0], minor: 0 },
        trees: [
          { type: "com.fluidframework.leaf.string", value: "A", fields: [] },
          { type: "com.fluidframework.leaf.string", value: "B", fields: [] },
          { type: "com.fluidframework.leaf.string", value: "C", fields: [] },
        ],
      }],
      fields: [["root", { marks: [{
        count: 3,
        attach: { major: scenario.revisions[0], minor: 0 },
      }] }]],
    }],
  };
  value.raw.scenarios[0].input = structuredClone(scenario);
  assert.doesNotThrow(() => validateArrayCase(value));

  scenario.operands.deltas[0].fields = [];
  value.raw.scenarios[0].input = structuredClone(scenario);
  assert.throws(() => validateArrayCase(value), /counted-build.*delta fields/i);
});

test("M3 cases require complete replay inputs and substantive observations", () => {
  for (const [id, mutate, message] of [
    ["array-schema-content", (value) => {
      delete value.input.scenarios[0].initialState;
      delete value.raw.scenarios[0].input.initialState;
    }, /typed initial content/i],
    ["sequence-field-editor", (value) => {
      value.expected.observations[0] = { id: "move-interior", captured: true };
    }, /source result/i],
  ]) {
    const value = id === "sequence-field-editor"
      ? arrayCaseFixture()
      : JSON.parse(readFileSync(
          new URL(`../../test/fixtures/shared_tree/cases/${id}.json`, import.meta.url), "utf8",
        ));
    mutate(value);
    assert.throws(
      () => validateArrayCase(
        value,
        id === "sequence-field-editor"
          ? value.input.scenarios.map(({ id: scenarioId }) => scenarioId)
          : undefined,
      ),
      message,
    );
  }
});

test("array validation requires contract-defining source evidence", () => {
  for (const [id, mutate, message] of [
    ["array-schema-content", (value) => {
      const schema = JSON.parse(value.input.schemas.rootArray);
      schema.nodes["org.watershed.shared-tree.m3.Items"].kind.object[""].kind = "Value";
      value.input.schemas.rootArray = JSON.stringify(schema);
      value.raw.schemas.rootArray.bytes = value.input.schemas.rootArray;
      for (const scenario of value.input.scenarios.filter(({ schema: selector }) =>
        selector === "rootArray")) {
        scenario.schemaBytes = value.input.schemas.rootArray;
        value.raw.scenarios.find(({ id }) => id === scenario.id).input =
          structuredClone(scenario);
      }
    }, /Sequence field/],
    ["sequence-field-editor", (value) => {
      const observation = value.expected.observations.find(({ id }) => id === "move-interior");
      observation.value.change[1].type = "MoveOut";
      observation.result.change[1].type = "MoveOut";
      value.raw.scenarios.find(({ id }) => id === "move-interior")
        .output.change[1].type = "MoveOut";
    }, /interior move split/],
    ["array-modular-algebra", (value) => {
      value.expected.observations[0].fieldKinds.pop();
    }, /field kinds/],
    ["array-modular-algebra", (value) => {
      const observation = value.expected.observations.find(
        ({ id }) => id === "nested-cross-field-endpoints",
      );
      observation.result.coordination.causalCalls.reverse();
    }, /normalized output|nested-cross-field-endpoints/],
    ["array-modular-algebra", (value) => {
      const observation = value.expected.observations.find(
        ({ id }) => id === "cross-field-endpoints",
      );
      observation.result.coordination.readEvidence.retry = false;
    }, /normalized output|coordination evidence|substantive source result/],
    ["array-modular-algebra", (value) => {
      const observation = value.expected.observations.find(
        ({ id }) => id === "generic-to-sequence",
      );
      observation.result.conversion.calls = [];
    }, /normalized output|conversion/],
    ["array-codecs", (value) => {
      value.input.scenarios[0].profile.sequence = 2;
      value.raw.scenarios[0].input.profile.sequence = 2;
    }, /codec profile/],
    ["array-history", (value) => {
      value.raw.scenarios.find(({ input }) => input.id === "public-noops")
        .output.checkpoints[0].events.commits = 1;
      value.expected.observations.find(({ id }) => id === "public-noops")
        .result.checkpoints[0].events.commits = 1;
    }, /no-op emission/],
    ["array-invalid", (value) => {
      value.raw.scenarios.find(({ input }) => input.id === "native-remove-beyond-length")
        .output.nativeContract = "clamp";
      value.expected.observations.find(({ id }) => id === "native-remove-beyond-length")
        .result.nativeContract = "clamp";
    }, /removal-bound difference/],
  ]) {
    const value = JSON.parse(readFileSync(
      new URL(`../../test/fixtures/shared_tree/cases/${id}.json`, import.meta.url), "utf8",
    ));
    mutate(value);
    assert.throws(() => validateArrayCase(value), message);
  }
});

test("array schema compatibility input selects the executed stored and view schemas", () => {
  const value = JSON.parse(readFileSync(
    new URL("../../test/fixtures/shared_tree/cases/array-schema-content.json", import.meta.url),
    "utf8",
  ));
  const scenario = value.input.scenarios.find(({ id }) => id === "compatibility");
  const raw = value.raw.scenarios.find(({ id }) => id === "compatibility");
  scenario.viewSchema = "incompatibleArrays";
  raw.input = structuredClone(scenario);
  assert.throws(() => validateArrayCase(value), /compatibility.*schema execution/i);
});

test("array codec validation rejects decoded outputs and incomplete decode context as input", () => {
  const value = JSON.parse(readFileSync(
    new URL("../../test/fixtures/shared_tree/cases/array-codecs.json", import.meta.url),
    "utf8",
  ));
  for (const [mutate, message] of [
    [(copy) => {
      copy.input.scenarios[0].encodedMessages = [copy.raw.scenarios[0].output];
      copy.raw.scenarios[0].input = structuredClone(copy.input.scenarios[0]);
    }, /sequence-v3.*encoded input/i],
    [(copy) => {
      delete copy.input.scenarios[1].decodeContext.nativeInput.clients[0].compressor;
      delete copy.raw.scenarios[1].input.decodeContext.nativeInput.clients[0].compressor;
    }, /message-v7.*compressor/i],
    [(copy) => {
      delete copy.input.scenarios[6].encodedSummary;
      delete copy.raw.scenarios[6].input.encodedSummary;
    }, /full-summary.*encoded summary/i],
    [(copy) => {
      copy.input.scenarios[0].advancedExpected = [{ marker: "poison" }];
      copy.raw.scenarios[0].input.advancedExpected = [{ marker: "poison" }];
    }, /sequence-v3.*advanced expected/i],
    [(copy) => {
      delete copy.input.scenarios[0].advancedDecodeContext.compressor;
      delete copy.raw.scenarios[0].input.advancedDecodeContext.compressor;
    }, /sequence-v3.*advanced compressor/i],
  ]) {
    const broken = structuredClone(value);
    mutate(broken);
    assert.throws(() => validateArrayCase(broken), message);
  }
});

test("array history validation requires action schedules and full replay context", () => {
  const value = JSON.parse(readFileSync(
    new URL("../../test/fixtures/shared_tree/cases/array-history.json", import.meta.url),
    "utf8",
  ));
  for (const [mutate, message] of [
    [(copy) => {
      copy.input.scenarios[0].schedule = copy.raw.scenarios[0].output;
      copy.raw.scenarios[0].input = structuredClone(copy.input.scenarios[0]);
    }, /pending-chains.*action schedule/i],
    [(copy) => {
      copy.input.scenarios.find(({ id }) => id === "window-advance").schedule =
        [{ id: "reconnect", op: "connect", client: 0, connected: true }];
      copy.raw.scenarios.find(({ id }) => id === "window-advance").input =
        structuredClone(copy.input.scenarios.find(({ id }) => id === "window-advance"));
    }, /window-advance.*minimum sequence/i],
    [(copy) => {
      delete copy.input.scenarios.find(({ id }) => id === "summary-tail")
        .replayContext.continuationEnvelope;
      copy.raw.scenarios.find(({ id }) => id === "summary-tail").input =
        structuredClone(copy.input.scenarios.find(({ id }) => id === "summary-tail"));
    }, /summary-tail.*continuation envelope/i],
  ]) {
    const broken = structuredClone(value);
    mutate(broken);
    assert.throws(() => validateArrayCase(broken), message);
  }
});

test("array invalid validation requires executable malformed operands", () => {
  const value = JSON.parse(readFileSync(
    new URL("../../test/fixtures/shared_tree/cases/array-invalid.json", import.meta.url),
    "utf8",
  ));
  const scenario = value.input.scenarios.find(({ id }) => id === "corrupt-range");
  const raw = value.raw.scenarios.find(({ id }) => id === "corrupt-range");
  scenario.malformed = value.raw.scenarios.find(({ id }) => id === "corrupt-range").output;
  raw.input = structuredClone(scenario);
  assert.throws(() => validateArrayCase(value), /corrupt-range.*malformed input/i);
});

test("array modular validation requires replayable graphs and observed source coordination", () => {
  const value = JSON.parse(readFileSync(
    new URL("../../test/fixtures/shared_tree/cases/array-modular-algebra.json", import.meta.url),
    "utf8",
  ));
  const scenarios = new Map(value.input.scenarios.map((scenario) => [scenario.id, scenario]));
  const outputs = new Map(value.raw.scenarios.map((scenario) => [scenario.id, scenario.output]));

  for (const scenario of scenarios.values()) {
    assert.match(scenario.operation, /^(compose|invert|rebase)$/);
    assert(Array.isArray(scenario.operands.changes));
    for (const tagged of scenario.operands.changes) {
      assert(Number.isSafeInteger(tagged.revision));
      for (const table of ["fields", "nodes", "parents", "aliases", "crossFieldKeys"]) {
        assert(Array.isArray(tagged.change[table]), `${scenario.id}: ${table}`);
      }
    }
    const graph = outputs.get(scenario.id).graph;
    for (const table of ["fields", "nodes", "parents", "aliases", "crossFieldKeys"]) {
      assert(Array.isArray(graph[table]), `${scenario.id}: output ${table}`);
    }
    assert(Array.isArray(outputs.get(scenario.id).delta.fields));
  }

  assert.deepEqual(outputs.get("generic-to-sequence").conversion.directions, ["generic-left"]);
  assert.deepEqual(outputs.get("sequence-to-generic").conversion.directions, ["generic-right"]);
  const coordination = outputs.get("cross-field-endpoints").coordination;
  const sourceCoordination = scenarios.get("cross-field-endpoints").sourceCoordination;
  assert(coordination.handlerCalls.filter(({ field }) => field.field === "right").length > 1);
  assert(sourceCoordination.managerCalls.some(({ method, field, addDependency }) =>
    method === "get" && field.field === "right" && addDependency === true));
  assert(coordination.managerCalls.some(({ method, field, invalidateDependents }) =>
    method === "set" && field.field === "right" && invalidateDependents === true));
  assert(sourceCoordination.managerCalls.some(({ count, returnedLength }) =>
    count > returnedLength && returnedLength > 0));
  assert.doesNotThrow(() => validateArrayCase(value));
});

test("array modular validation binds conversion evidence to the serialized child index", () => {
  const value = JSON.parse(readFileSync(
    new URL("../../test/fixtures/shared_tree/cases/array-modular-algebra.json", import.meta.url),
    "utf8",
  ));
  const input = value.input.scenarios.find(({ id }) => id === "generic-to-sequence");
  const raw = value.raw.scenarios.find(({ id }) => id === "generic-to-sequence");
  input.operands.changes[0].change.fields[0][1].change.children[0][0] += 1;
  raw.input = structuredClone(input);
  assert.throws(() => validateArrayCase(value), /generic-to-sequence.*conversion/i);
});

test("M3 replay observations retain nested deltas and decoded source state", () => {
  const sequence = JSON.parse(readFileSync(
    new URL("../../test/fixtures/shared_tree/cases/sequence-field-editor.json", import.meta.url),
    "utf8",
  ));
  const indexed = sequence.raw.scenarios.find(({ id }) => id === "indexed-children").output;
  assert(Array.isArray(indexed.delta.local.marks[1].fields));
  assert.match(JSON.stringify(indexed.delta.local.marks[1].fields), /testIntentions/);

  const codecs = JSON.parse(readFileSync(
    new URL("../../test/fixtures/shared_tree/cases/array-codecs.json", import.meta.url),
    "utf8",
  ));
  const build = codecs.raw.scenarios.find(({ id }) => id === "builds").output.decoded
    .flatMap(({ changes }) => changes)
    .find(({ type, data }) => type === "data" && data.builds.length > 0).data;
  assert(build.builds[0][1].length > 0);
  assert(Array.isArray(build.refreshers));
  assert(Array.isArray(build.destroys));

  for (const id of ["retained-history", "detached-index", "full-summary"]) {
    const output = codecs.raw.scenarios.find((scenario) => scenario.id === id).output;
    assert(Array.isArray(output.restoredHistory.trunk), `${id}: restored history`);
    assert(Array.isArray(output.restoredDetached), `${id}: restored detached roots`);
    assert.equal("history" in output, false, `${id}: echoed history blob`);
    assert.equal("detached" in output, false, `${id}: echoed detached blob`);
  }
});

test("M3 sequence inputs record unused compose and rebase allocators", () => {
  for (const name of [
    "sequence-field-editor",
    "sequence-compose-invert",
    "sequence-rebase",
  ]) {
    const value = JSON.parse(readFileSync(
      new URL(`../../test/fixtures/shared_tree/cases/${name}.json`, import.meta.url),
      "utf8",
    ));
    for (const scenario of value.input.scenarios) {
      assert.equal(scenario.algorithm.composeAllocator, "unused-by-pinned-source");
      assert.equal(scenario.algorithm.rebaseAllocator, "unused-by-pinned-source");
      assert.equal("algebraAllocator" in scenario.algorithm, false);
    }
  }
});

test("corpus requires every schema evolution case", () => {
  assert.deepEqual(schemaEvolutionCaseIds, [
    "schema-evolution-compatibility",
    "schema-evolution-algebra",
    "schema-evolution-history",
    "schema-evolution-codecs",
  ]);
  for (const id of schemaEvolutionCaseIds) {
    assert(requiredCases.some(([caseId]) => caseId === id));
  }
});

test("schema evolution cases require complete source-backed contracts", () => {
  const baseSchemaIds = [
    "v1", "optional", "object-union", "map-union", "optional-title",
    "root-union", "optional-root", "combined", "narrow", "new-required",
  ];
  for (const id of schemaEvolutionCaseIds) {
    const schemaIds = [
      ...baseSchemaIds,
      ...(id === "schema-evolution-compatibility"
        ? ["optional-to-required", "node-kind-replacement", "sequence", "handle"]
        : []),
    ];
    for (const mutate of [
      (value) => { value.reference.commit = "other"; },
      (value) => { delete value.input; },
      (value) => { value.expected.observations = []; },
      (value) => { value.raw.schemaMessages = []; },
    ]) {
      const corpus = cases();
      mutate(corpus.find((value) => value.id === id));
      assert.throws(() => validateCases(corpus), new RegExp(id));
    }
    const scenarioIds = cases()
      .find((value) => value.id === id)
      .input.scenarios.map(({ id: scenarioId }) => scenarioId);
    for (const scenarioId of scenarioIds) {
      const corpus = cases();
      const value = corpus.find((item) => item.id === id);
      value.input.scenarios = value.input.scenarios.filter(({ id: candidate }) =>
        candidate !== scenarioId);
      assert.throws(() => validateCases(corpus), new RegExp(id));
    }
    for (const schemaId of schemaIds) {
      const corpus = cases();
      const value = corpus.find((item) => item.id === id);
      value.input.schemas = value.input.schemas.filter(({ id: candidate }) =>
        candidate !== schemaId);
      assert.throws(() => validateCases(corpus), new RegExp(id));
    }
  }
});

test("corpus requires every transaction case", () => {
  assert.deepEqual(generator.requiredTransactionCases, [
    "transaction-callbacks",
    "transaction-constraints",
    "transaction-wire",
    "transaction-history",
  ]);
  for (const id of generator.requiredTransactionCases) {
    assert(requiredCases.some(([caseId]) => caseId === id));
  }
});

test("transaction cases require complete source-backed contracts", () => {
  const required = [
    "transaction-callbacks",
    "transaction-constraints",
    "transaction-wire",
    "transaction-history",
  ];
  for (const id of required) {
    for (const mutate of [
      (value) => { value.reference.commit = "other"; },
      (value) => { delete value.input; },
      (value) => { value.expected.observations = []; },
    ]) {
      const corpus = cases();
      mutate(corpus.find((value) => value.id === id));
      assert.throws(() => validateCases(corpus), new RegExp(id));
    }
    assert.throws(() => validateCases(cases([id])), new RegExp(`Missing case: ${id}`));
  }
});

function transactionCorpus(id) {
  const corpus = cases();
  const index = corpus.findIndex((value) => value.id === id);
  corpus[index] = JSON.parse(readFileSync(
    new URL(`../../test/fixtures/shared_tree/cases/${id}.json`, import.meta.url),
    "utf8",
  ));
  return corpus;
}

test("transaction wire requires executable codec and algebra inputs and results", () => {
  const mutations = [
    (value) => { delete value.input.messageBytes; },
    (value) => { delete value.input.messageBytes.over; },
    (value) => { value.input.messageBytes.nonviolated = "{}"; },
    (value) => { value.input.messageBytes.violated = "{}"; },
    (value) => { delete value.input.compressor; },
    (value) => { delete value.input.compressor.violated; },
    (value) => { value.input.compressor.nonviolated.sessionId = "not-a-session"; },
    (value) => { value.input.compressor.nonviolated.serialized = "not-a-compressor"; },
    (value) => {
      value.input.compressor.nonviolated.sessionId =
        JSON.parse(value.input.messageBytes.nonviolated).originatorId;
    },
    (value) => { delete value.input.context; },
    (value) => { value.input.context.message = 6; },
    (value) => { delete value.input.operands.nonviolated; },
    (value) => { delete value.input.operands.violated; },
    (value) => { delete value.input.operands.compose; },
    (value) => { delete value.input.operands.invert; },
    (value) => { delete value.input.operands.rebase; },
    (value) => { delete value.input.operands.rebase.change; },
    (value) => { delete value.input.operands.rebase.change.decoded; },
    (value) => { delete value.input.operands.rebase.over.decoded; },
    (value) => { delete value.input.operands.nonviolated.revision; },
    (value) => { delete value.input.operands.compose.changes[0].revision; },
    (value) => { delete value.input.operands.invert.inverseRevision; },
    (value) => { value.input.operands.invert.inverseRevision = ""; },
    (value) => { delete value.input.operands.invert.isRollback; },
    (value) => { value.input.operands.invert.isRollback = "false"; },
    (value) => { delete value.input.operands.rebase.revisionMetadata[0].revision; },
    (value) => { delete value.input.operands.rebase.revisionMetadata[0].rollbackOf; },
    (value) => {
      value.input.operands.rebase.revisionMetadata[0].revision =
        "00000000-0000-4000-8000-000000000000";
    },
    (value) => { delete value.expected.observations[0].nonviolated; },
    (value) => { delete value.expected.observations[0].violated; },
    (value) => { delete value.expected.observations[0].composed; },
    (value) => { delete value.expected.observations[0].inverted; },
    (value) => { value.expected.observations[0].inverted = [{ garbage: true }]; },
    (value) => { delete value.expected.observations[0].rebased; },
    (value) => { delete value.raw.messages; },
    (value) => { delete value.raw.algebra; },
    (value) => { delete value.raw.algebra.nonviolatedOperand; },
    (value) => { value.raw.algebra.composed = [{ corrupted: true }]; },
    (value) => { value.raw.algebra.inverted = [{ corrupted: true }]; },
    (value) => { delete value.raw.algebra.rebaseOperands; },
    (value) => { value.raw.algebra.rebased = [{ corrupted: true }]; },
  ];
  for (const [mutationIndex, mutate] of mutations.entries()) {
    const corpus = transactionCorpus("transaction-wire");
    const value = corpus.find(({ id }) => id === "transaction-wire");
    value.input.messageBytes ??= {
      nonviolated: value.expected.observations[0].messageBytes,
      violated: value.expected.observations[0].messageBytes,
      over: value.expected.observations[0].messageBytes,
    };
    value.input.compressor ??= {
      nonviolated: { serialized: "compressor", sessionId: "session" },
      violated: { serialized: "compressor", sessionId: "session" },
      over: { serialized: "compressor", sessionId: "session" },
    };
    value.input.context ??= {
      message: 7,
      sharedTreeChange: 5,
      modularChange: 5,
      minVersionForCollab: "2.117.0",
    };
    value.input.operands ??= {
      nonviolated: { changeset: [1] },
      violated: { changeset: [2] },
      compose: { changes: ["nonviolated", "nonviolated"] },
      invert: { change: "nonviolated" },
      rebase: { change: "nonviolated", over: "violated", revisionMetadata: [{ revision: "r" }] },
    };
    value.expected.observations[0].nonviolated ??= { changes: [1] };
    value.expected.observations[0].violated ??= { changes: [2] };
    value.expected.observations[0].rebased ??= { changes: [3] };
    assert.doesNotThrow(() => validateCases(corpus));
    mutate(value);
    assert.throws(() => validateCases(corpus), /transaction-wire/);
  }
});

test("transaction rebase input uses the captured violated change", () => {
  const value = JSON.parse(readFileSync(
    new URL("../../test/fixtures/shared_tree/cases/transaction-wire.json", import.meta.url),
    "utf8",
  ));
  const violated = JSON.parse(value.input.messageBytes.violated);
  assert.deepEqual(value.input.operands.rebase.change.changeset, violated.changeset);
  assert.deepEqual(
    value.raw.algebra.rebaseOperands.change,
    {
      revision: value.input.operands.rebase.change.revision,
      changes: value.input.operands.rebase.change.decoded,
    },
  );
  assert.deepEqual(
    value.raw.algebra.rebased,
    value.expected.observations[0].rebased.changes,
  );

  value.input.operands.rebase.change.changeset =
    JSON.parse(value.input.messageBytes.nonviolated).changeset;
  assert.throws(() => validateCases(cases().map((item) =>
    item.id === value.id ? value : item)), /transaction-wire.*rebase change/i);
});

test("transaction history replays from the summary compressor with captured tail ranges", () => {
  const value = JSON.parse(readFileSync(
    new URL("../../test/fixtures/shared_tree/cases/transaction-history.json", import.meta.url),
    "utf8",
  ));
  assert.equal(value.input.compressor.serialized, value.expected.observations[0].pendingCompressor);
  assert(value.input.tailAllocationRanges.length > 0);
});

test("transaction callbacks capture invalid-edit rollback and every field-operation read", () => {
  const value = JSON.parse(readFileSync(
    new URL("../../test/fixtures/shared_tree/cases/transaction-callbacks.json", import.meta.url),
    "utf8",
  ));
  const success = value.expected.observations.find(({ id }) => id === "success-all-fields");
  assert.deepEqual(success.reads.map(({ step }) => step), [
    "object-set", "object-delete", "map-set", "map-delete",
    "array-insert", "array-remove", "array-replace",
    "same-array-move", "cross-array-move",
  ]);
  const invalid = value.expected.observations.find(({ id }) => id === "invalid-edit-rollback");
  assert(invalid, "missing invalid-edit rollback scenario");
  assert.deepEqual(invalid.reads.map(({ step }) => step), ["valid-edit-before-invalid"]);
  assert.equal(invalid.reads[0].value.title, "before-invalid");
  assert.equal(invalid.transactionResult, "rollback");
  assert.match(invalid.error, /Expected non-negative index/);
  for (const field of ["visible", "identities", "retainedDetached", "compressor", "history"]) {
    assert.deepEqual(invalid.state.after[field], invalid.state.before[field]);
  }
  assert.notEqual(invalid.allocation.after.ongoing, invalid.allocation.before.ongoing);
  assert.equal(invalid.localCompressorAdvanced, true);
  assert.deepEqual(invalid.events, []);
  assert.equal(invalid.commitCount, 0);
  assert.equal(invalid.pendingCommitCount, 0);
  assert.deepEqual(invalid.submittedMessages, []);
});

test("transaction history requires replayable summary continuation checkpoints", () => {
  const mutations = [
    (value) => { delete value.input.summary; },
    (value) => { value.input.summary = {}; },
    (value) => { delete value.input.compressor; },
    (value) => { value.input.compressor.serialized = ""; },
    (value) => { delete value.input.tailEnvelope; },
    (value) => { value.input.tailEnvelope.contents = {}; },
    (value) => { delete value.input.tailEnvelope.contents.changeset; },
    (value) => { delete value.input.tailAllocationRanges; },
    (value) => { value.input.tailAllocationRanges = []; },
    (value) => { delete value.input.tailAllocationRanges[0].sessionId; },
    (value) => { delete value.input.tailAllocationRanges[0].ids.firstGenCount; },
    (value) => { value.input.tailAllocationRanges[0].ids.count = 0; },
    (value) => { value.input.tailAllocationRanges[0].ids.localIdRanges = [[1]]; },
    (value) => { delete value.input.continuation; },
    (value) => { value.input.continuation.edits = []; },
    (value) => { delete value.input.continuation.creationRange; },
    (value) => { delete value.expected.observations[0].pending; },
    (value) => { delete value.expected.observations[0].pendingViolation; },
    (value) => { delete value.expected.observations[0].missingTailAllocationError; },
    (value) => { delete value.expected.observations[0].loaded; },
    (value) => { delete value.expected.observations[0].afterTail; },
    (value) => { delete value.expected.observations[0].afterContinuation; },
    (value) => { delete value.expected.observations[0].peer; },
    (value) => { delete value.expected.observations[0].checkpoints; },
    (value) => { value.expected.observations[0].checkpoints[0].identities = []; },
    (value) => { delete value.expected.observations[0].checkpoints[0].retainedDetached; },
    (value) => { value.expected.observations[0].checkpoints[0].compressor = ""; },
    (value) => { value.expected.observations[0].checkpoints[0].allocation = {}; },
    (value) => { delete value.expected.observations[0].checkpoints[0].history; },
    (value) => { delete value.expected.observations[0].checkpoints[0].visible; },
    (value) => { value.expected.observations[0].peer.visible = { corrupted: true }; },
  ];
  for (const mutate of mutations) {
    const corpus = transactionCorpus("transaction-history");
    const value = corpus.find(({ id }) => id === "transaction-history");
    value.input.summary ??= value.expected.observations[0].pendingSummary;
    value.input.compressor ??= {
      serialized: value.expected.observations[0].pendingCompressor,
      sessionId: "session",
    };
    value.input.tailEnvelope ??= { contents: value.expected.observations[0].summaryPlusTail.tailMessages[0] };
    value.input.continuation ??= { op: "transaction", edits: [{ op: "set" }] };
    value.input.tailAllocationRanges ??= [{
      sessionId: "tail-session",
      ids: {
        firstGenCount: 1,
        count: 1,
        requestedClusterSize: 512,
        localIdRanges: [[1, 1]],
      },
    }];
    value.expected.observations[0].pendingViolation ??= {
      change: { constraintViolationCount: 1 },
    };
    value.expected.observations[0].loaded ??= { final: "loaded" };
    value.expected.observations[0].afterTail ??= { final: "tail" };
    value.expected.observations[0].afterContinuation ??= { final: "continued" };
    value.expected.observations[0].peer ??= { final: "continued" };
    value.expected.observations[0].checkpoints ??= [{
      retainedDetached: ["content"],
      identities: ["node"],
      compressor: "state",
      allocation: { state: "captured" },
    }];
    assert.doesNotThrow(() => validateCases(corpus));
    mutate(value);
    assert.throws(() => validateCases(corpus), /transaction-history/);
  }
});

test("transaction callbacks require field coverage and exact state checkpoints", () => {
  const mutations = [
    (value) => { value.input.scenarios[0].operations.pop(); },
    (value) => {
      value.expected.observations
        .find(({ id }) => id === "success-all-fields").reads.pop();
    },
    (value) => {
      value.input.scenarios = value.input.scenarios.filter(
        ({ id }) => id !== "invalid-edit-rollback",
      );
    },
    (value) => {
      value.expected.observations = value.expected.observations.filter(
        ({ id }) => id !== "invalid-edit-rollback",
      );
    },
    ...Array.from({ length: 6 }, (_, index) => [
      (value) => { value.expected.observations[index].identity.nodes = []; },
      (value) => { value.expected.observations[index].allocation = {}; },
      (value) => { value.expected.observations[index].compressor = ""; },
    ]).flat(),
    (value) => { value.expected.observations[0].events = []; },
    (value) => { value.expected.observations[1].submittedMessages = [{}]; },
    (value) => { delete value.expected.observations[0].reads; },
    (value) => { delete value.expected.observations[0].final; },
    (value) => { delete value.expected.observations[0].retainedDetached; },
    (value) => { delete value.expected.observations[0].history; },
    (value) => {
      delete value.expected.observations
        .find(({ id }) => id === "invalid-edit-rollback").error;
    },
    (value) => {
      delete value.expected.observations
        .find(({ id }) => id === "invalid-edit-rollback").localCompressorAdvanced;
    },
    (value) => {
      value.expected.observations
        .find(({ id }) => id === "invalid-edit-rollback").events = [{ kind: "changed" }];
    },
    (value) => {
      value.expected.observations
        .find(({ id }) => id === "invalid-edit-rollback").state.after.visible = {
          state: "changed",
        };
    },
    (value) => { delete value.raw.scenarios; },
  ];
  for (const [mutationIndex, mutate] of mutations.entries()) {
    const corpus = transactionCorpus("transaction-callbacks");
    const value = corpus.find(({ id }) => id === "transaction-callbacks");
    const complete = transactionCaseFixture("transaction-callbacks", "tree");
    if (!value.input.scenarios.some(({ id }) => id === "invalid-edit-rollback")) {
      value.input.scenarios.push(structuredClone(
        complete.input.scenarios.find(({ id }) => id === "invalid-edit-rollback"),
      ));
      value.expected.observations.push(structuredClone(
        complete.expected.observations.find(({ id }) => id === "invalid-edit-rollback"),
      ));
    }
    value.raw.scenarios ??= structuredClone(value.expected.observations);
    value.raw.messages ??= value.expected.observations.flatMap(
      ({ submittedMessages }) => submittedMessages,
    );
    value.input.scenarios[0].operations ??= [
      "object-set", "object-delete", "map-set", "map-delete",
      "array-insert", "array-remove", "array-replace",
      "same-array-move", "cross-array-move",
    ];
    for (const observation of value.expected.observations) {
      observation.identity ??= { nodes: ["node"] };
      observation.allocation ??= { before: "a", after: "b" };
      observation.compressor ??= "state";
    }
    assert.doesNotThrow(() => validateCases(corpus));
    mutate(value);
    assert.throws(
      () => validateCases(corpus),
      /transaction-callbacks/,
      `mutation ${mutationIndex}`,
    );
  }
});

test("transaction callbacks reject missing rollback checkpoints in expected and raw", () => {
  const corpus = transactionCorpus("transaction-callbacks");
  const value = corpus.find(({ id }) => id === "transaction-callbacks");
  value.expected.observations
    .find(({ id }) => id === "invalid-edit-rollback").state.before = {};
  value.raw.scenarios
    .find(({ id }) => id === "invalid-edit-rollback").state.before = {};
  assert.deepEqual(
    value.expected.observations
      .find(({ id }) => id === "invalid-edit-rollback").state.before,
    {},
  );
  assert.throws(() => generator.validateTransactionCallbacks(value), /transaction-callbacks/);
});

function privateImplementationPaths(value) {
  const paths = [];
  function visit(item, path) {
    if (Array.isArray(item)) {
      item.forEach((child, index) => visit(child, [...path, index]));
      return;
    }
    if (item === null || typeof item !== "object") return;
    for (const [key, child] of Object.entries(item)) {
      const childPath = [...path, key];
      if (
        ["_root", "_maxNodeSize", "_events", "isShared"].includes(key)
        || (key === "events" && child !== null && typeof child === "object" && !Array.isArray(child))
      ) {
        paths.push(childPath.join("."));
      }
      visit(child, childPath);
    }
  }
  visit(value, []);
  return paths;
}

test("transaction history uses only stable semantic and wire projections", () => {
  for (const id of ["transaction-callbacks", "transaction-constraints", "transaction-history"]) {
    const value = transactionCorpus(id).find((item) => item.id === id);
    assert.deepEqual(privateImplementationPaths(value), [], `${id}: private implementation state`);
  }
});

function transactionDataChanges(value) {
  const changes = [];
  function visit(item) {
    if (Array.isArray(item)) {
      item.forEach(visit);
      return;
    }
    if (item === null || typeof item !== "object") return;
    if (item.type === "data" && item.change !== null && typeof item.change === "object") {
      changes.push(item.change);
    }
    Object.values(item).forEach(visit);
  }
  visit(value.expected.observations);
  return changes;
}

function atomKey(value) {
  return `${value.revision ?? ""}:${value.localId}`;
}

test("transaction history canonicalizes alias and parent graph evidence", () => {
  for (const id of ["transaction-callbacks", "transaction-constraints", "transaction-history"]) {
    const value = transactionCorpus(id).find((item) => item.id === id);
    for (const change of transactionDataChanges(value)) {
      const aliases = new Set(change.aliases.map(({ id: alias }) => atomKey(alias)));
      assert(change.aliases.every(({ target }) => !aliases.has(atomKey(target))),
        `${id}: alias target is not final`);
      assert(change.parents.every(({ parent }) => parent === null || !aliases.has(atomKey(parent))),
        `${id}: parent target is not final`);
      const graphIds = new Set();
      function collectAtoms(item) {
        if (Array.isArray(item)) {
          item.forEach(collectAtoms);
        } else if (item !== null && typeof item === "object") {
          if (
            Object.keys(item).length === 2
            && Object.hasOwn(item, "revision")
            && Object.hasOwn(item, "localId")
          ) {
            graphIds.add(item.localId);
          } else {
            Object.values(item).forEach(collectAtoms);
          }
        }
      }
      collectAtoms(change);
      assert.deepEqual([...graphIds].sort((left, right) => left - right),
        Array.from({ length: change.maxId + 1 }, (_, index) => index),
        `${id}: anonymous graph IDs are not canonical`);
      const aliasTargets = new Set();
      for (const alias of change.aliases) {
        const key = atomKey(alias.target);
        assert(!aliasTargets.has(key), `${id}: duplicate intermediate alias`);
        aliasTargets.add(key);
      }
      for (const build of [...change.builds, ...change.refreshers]) {
        assert(build.trees.every((tree) => typeof tree.kind === "string"),
          `${id}: build tree is not semantic`);
      }
    }
  }
});

test("transaction semantic history keeps every load-bearing field mandatory", () => {
  const mutations = {
    "transaction-callbacks": [
      (value) => { delete value.expected.observations[0].history.pending[0].revision; },
      (value) => { delete value.expected.observations[0].history.pending[0].changes[0].change.fields; },
      (value) => {
        value.expected.observations[0].history.pending[0]
          .changes[0].change.aliases[0].target.localId += 1;
      },
      (value) => {
        value.expected.observations[0].history.pending[0]
          .changes[0].change.parents[1].parent.localId += 1;
      },
      (value) => { delete value.expected.observations[0].submittedMessages[0].changeset; },
      (value) => { value.expected.observations[0].identity.nodes = []; },
      (value) => { delete value.expected.observations[0].allocation.after.ongoing; },
    ],
    "transaction-constraints": [
      (value) => { delete value.expected.observations[0].pending.pending[0].revision; },
      (value) => {
        delete value.expected.observations[0].pending.pending[0]
          .changes[0].change.revisions;
      },
      (value) => {
        delete value.expected.observations[0].pending.pending[0]
          .changes[0].change.fields;
      },
      (value) => {
        delete value.expected.observations[0].pending.pending[0]
          .changes[0].change.nodes;
      },
      (value) => {
        delete value.expected.observations[0].pending.pending[0]
          .changes[0].change.parents;
      },
      (value) => {
        delete value.expected.observations[0].pending.pending[0]
          .changes[0].change.aliases;
      },
      (value) => {
        delete value.expected.observations[0].pending.pending[0]
          .changes[0].change.builds;
      },
      (value) => {
        delete value.expected.observations[0].pending.pending[0]
          .changes[0].change.refreshers;
      },
      (value) => {
        delete value.expected.observations[0].pending.pending[0]
          .changes[0].change.constraintViolationCount;
      },
      (value) => { delete value.expected.observations[0].reconnectMessages[0].changeset; },
    ],
    "transaction-history": [
      (value) => { delete value.expected.observations[0].pending.history.pending; },
      (value) => { delete value.expected.observations[0].pending.history.trunk; },
      (value) => { delete value.expected.observations[0].pending.history.pending[0].revision; },
      (value) => {
        delete value.expected.observations[0].pending.history.pending[0]
          .changes[0].change.fields;
      },
      (value) => { delete value.expected.observations[0].pending.identities; },
      (value) => { delete value.expected.observations[0].pending.allocation; },
      (value) => { delete value.expected.observations[0].pendingSummary; },
      (value) => { delete value.raw.continuationEnvelope; },
      (value) => { delete value.expected.observations[0].reconnectMessages[0].changeset; },
    ],
  };
  for (const [id, caseMutations] of Object.entries(mutations)) {
    for (const [mutationIndex, mutate] of caseMutations.entries()) {
      const corpus = transactionCorpus(id);
      mutate(corpus.find((value) => value.id === id));
      assert.throws(
        () => validateCases(corpus),
        new RegExp(id),
        `${id}: mutation ${mutationIndex}`,
      );
    }
  }
});

test("transaction constraints require converged client outcomes and retained evidence", () => {
  const mutations = [
    (value) => { delete value.expected.observations[0].clients; },
    (value) => { value.expected.observations[0].clients.peer = { corrupted: true }; },
    (value) => { value.expected.observations[0].clients = {
      writer: { created: true },
      peer: { created: true },
    }; },
    (value) => { delete value.expected.observations[0].converged; },
    (value) => { delete value.expected.observations[0].constraintViolationCount; },
    (value) => { delete value.expected.observations[0].retainedBuilds; },
    (value) => { delete value.expected.observations[0].refusal; },
    (value) => { delete value.expected.observations[0].withinMove.identityPreserved; },
    (value) => { delete value.expected.observations[0].crossMove.identityPreserved; },
  ];
  for (const mutate of mutations) {
    const corpus = transactionCorpus("transaction-constraints");
    const value = corpus.find(({ id }) => id === "transaction-constraints");
    const observation = value.expected.observations[0];
    observation.clients ??= { writer: observation.final, peer: observation.final };
    observation.converged ??= true;
    observation.withinMove.identityPreserved ??= observation.withinMove.targetAtEnd;
    observation.crossMove.identityPreserved ??= observation.crossMove.targetAtEnd;
    assert.doesNotThrow(() => validateCases(corpus));
    mutate(value);
    assert.throws(() => validateCases(corpus), /transaction-constraints/);
  }
});

test("M3 invalid cases execute source controls and exact malformed operands", () => {
  const value = JSON.parse(readFileSync(
    new URL("../../test/fixtures/shared_tree/cases/array-invalid.json", import.meta.url),
    "utf8",
  ));
  for (const [id, assertion] of [
    ["corrupt-mark", "0xac2"],
    ["corrupt-revision", "0x88d"],
  ]) {
    const output = value.raw.scenarios.find((scenario) => scenario.id === id).output;
    assert.equal(output.control.accepted, true, `${id}: valid decoder control`);
    assert.equal(output.malformed.accepted, false, `${id}: malformed decoder result`);
    assert.match(output.malformed.error, new RegExp(assertion), `${id}: source assertion`);
  }
  const ownership = value.raw.scenarios.find(({ id }) => id === "corrupt-ownership");
  assert.equal(ownership.output.control.accepted, true);
  assert.equal(ownership.output.malformed.accepted, false);
  for (const [mutate, message] of [
    [(input) => { delete input.malformed; }, /corrupt-ownership.*malformed input/i],
    [(input) => { delete input.malformed.source.path; }, /corrupt-ownership.*source path/i],
    [(input) => { delete input.malformed.source.client; }, /corrupt-ownership.*source client/i],
    [(input) => { delete input.malformed.source.index; }, /corrupt-ownership.*source index/i],
    [(input) => { delete input.malformed.destination.path; }, /corrupt-ownership.*destination path/i],
    [(input) => { delete input.malformed.destination.client; }, /corrupt-ownership.*destination client/i],
    [(input) => { delete input.malformed.destination.gap; }, /corrupt-ownership.*destination index/i],
  ]) {
    const broken = structuredClone(value);
    const input = broken.input.scenarios.find(({ id }) => id === "corrupt-ownership");
    mutate(input);
    broken.raw.scenarios.find(({ id }) => id === "corrupt-ownership").input =
      structuredClone(input);
    assert.throws(() => validateArrayCase(broken), message);
  }
});

test("M3 history observations expose source sequencing and deterministic reconnect IDs", () => {
  const value = JSON.parse(readFileSync(
    new URL("../../test/fixtures/shared_tree/cases/array-history.json", import.meta.url),
    "utf8",
  ));
  for (const id of ["pending-chains", "reconnect"]) {
    const input = value.input.scenarios.find((scenario) => scenario.id === id);
    const reconnect = input.schedule.find((action) =>
      action.op === "reconnect" || action.connected === true);
    assert.equal(typeof reconnect.reconnectId, "string", `${id}: reconnect identity`);
  }
  const tail = value.raw.scenarios.find(({ id }) => id === "summary-tail").output;
  assert(Array.isArray(tail.readerHistoryAfterTail.trunk));
  assert(Array.isArray(tail.readerHistoryAfterContinuation.trunk));
  assert(Array.isArray(tail.peerHistory.trunk));
  assert.equal("tailEnvelope" in tail, false);
  assert.equal("continuationEnvelope" in tail, false);
});

test("schema evolution validation rejects label-only evidence", () => {
  const mutations = {
    "schema-evolution-compatibility": [
      (value) => { delete value.expected.observations[0].attempt; },
      (value) => { value.expected.observations[0].attempt.beforeRoot.tree[0].fields = {}; },
      (value) => { value.input.rawProbes.pop(); },
      (value) => { value.raw.rawProbeResults[0].compatibility = {}; },
      (value) => { delete value.raw.refusalAttempts[0].compatibility; },
      (value) => {
        value.raw.refusalAttempts.find(({ id }) =>
          id === "node-kind-replacement").classification = "upstream-refusal";
      },
    ],
    "schema-evolution-algebra": [
      (value) => { delete value.input.operands; },
      (value) => { value.input.operands.schemaChange.changes[0].innerChange.schema.old.nodeSchema = {}; },
      (value) => { value.input.transitions = []; },
      (value) => { value.input.transitions[1].before = "v1"; },
      (value) => {
        value.input.operands.secondSchemaChange.changes[0].innerChange.schema.old.nodeSchema = {};
      },
      (value) => { delete value.raw.revisionResults; },
    ],
    "schema-evolution-history": [
      (value) => { value.input.scenarios[0].actions = ["upgrade:optional"]; },
      (value) => { value.input.scenarios[0].sessions = ["test-client-0"]; },
      (value) => { delete value.input.scenarios[0].sequencePoints[0].sequenceNumber; },
      (value) => { value.expected.observations[0].peerRevisions = []; },
      (value) => { value.expected.observations[0].visibleRoot.tree[0].fields.point = []; },
      (value) => { value.expected.observations[0].visibleRoot.tree[0].fields.title = [{}]; },
      (value) => {
        value.input.scenarios.find(({ id }) =>
          id === "upgrade-then-edit-causal").actions[1].value = 1;
      },
      (value) => {
        value.input.scenarios.find(({ id }) =>
          id === "new-view-reopens").actions.shift();
      },
      (value) => {
        value.input.scenarios.find(({ id }) =>
          id === "historical-peer-schema-context").actions.shift();
      },
      (value) => {
        value.expected.observations.find(({ id }) =>
          id === "ack-common-prefix-keeps-upgrade").acknowledgedSchema = false;
      },
      (value) => {
        delete value.expected.observations.find(({ id }) =>
          id === "ack-common-prefix-keeps-upgrade").remainingDependentEdit;
      },
      (value) => {
        delete value.expected.observations.find(({ id }) =>
          id === "rollback-retains-new-type-content").losingAuthorPending;
      },
      (value) => {
        delete value.expected.observations.find(({ id }) =>
          id === "rollback-retains-new-type-content").losingAuthorSchemaAfter;
      },
      (value) => {
        delete value.expected.observations.find(({ id }) =>
          id === "rollback-retains-new-type-content").pendingAfterCompetingEdit;
      },
      (value) => {
        delete value.expected.observations.find(({ id }) =>
          id === "rollback-retains-new-type-content").retainedExtra;
      },
      (value) => {
        value.input.rollbackReplay.detachedId.revision =
          "00000000-0000-4000-8000-000000000001";
      },
      (value) => {
        value.input.rollbackReplay.detachedId.localId = 1;
      },
      (value) => {
        delete value.expected.observations.find(({ id }) =>
          id === "reconnect-upgrade-accepted-before-drop").acceptedMessage;
      },
      (value) => {
        delete value.expected.observations.find(({ id }) =>
          id === "reconnect-upgrade-accepted-before-drop").replay;
      },
      (value) => {
        delete value.expected.observations.find(({ id }) =>
          id === "new-view-reopens").reopenedPeer;
      },
      (value) => {
        value.expected.observations.find(({ id }) =>
          id === "summary-upgrade-plus-tail").continuation.tailBytes = [];
      },
      (value) => {
        value.expected.observations.find(({ id }) =>
          id === "summary-upgrade-plus-tail").continuation.loadedSummary = false;
      },
      (value) => {
        delete value.expected.observations.find(({ id }) =>
          id === "summary-upgrade-plus-tail").continuation.summary;
      },
      (value) => {
        value.expected.observations.find(({ id }) =>
          id === "historical-peer-schema-context").historicalDecode.decoded = { changes: [] };
      },
      (value) => {
        value.expected.observations.find(({ id }) =>
          id === "historical-peer-schema-context").historicalDecode.decoded = {
            changes: [{ type: "data" }],
          };
      },
      (value) => {
        value.expected.observations.find(({ id }) =>
          id === "historical-peer-schema-context").historicalDecode.decodedBeforeInboundResume =
            false;
      },
    ],
    "schema-evolution-codecs": [
      (value) => {
        value.expected.observations.find(({ id }) =>
          id === "historical-schema-decode").operations = [];
      },
      (value) => {
        delete value.expected.observations.find(({ id }) =>
          id === "historical-schema-decode").operations[0].context;
      },
      (value) => {
        value.expected.observations.find(({ id }) =>
          id === "historical-schema-decode").operations[0].decoded = {
            changes: [{ type: "data" }],
          };
      },
      (value) => { value.raw.schemaMessageBytes = [""]; },
    ],
  };
  for (const [id, mutateCases] of Object.entries(mutations)) {
    for (const mutate of mutateCases) {
      const corpus = cases();
      mutate(corpus.find((value) => value.id === id));
      assert.throws(() => validateCases(corpus), new RegExp(id));
    }
  }
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
    ["ModularEditBuilder.Generic", "Optional", "Sequence", "Value"]);
  assert.deepEqual(manifest.inventory.identifierContract, {
    cases: identifierCases.map(([id]) => id),
    valueShapeDiscriminator: 0,
    allocationOrder: [
      { ordinal: 1, kind: "identifier", path: ["left", 1, "firstId"], op: 2 },
      { ordinal: 2, kind: "identifier", path: ["left", 1, "secondId"], op: 3 },
      { ordinal: 3, kind: "revision", path: [], op: 4 },
    ],
  });
  for (const target of ["javascript", "erlang"]) {
    assert.deepEqual(manifest.nativeSemanticRunners[target], [
      "id-ranges", "schema-validation", "forest-delta",
      "field-compose-invert-rebase", "modular-nested-algebra",
      "container-foundations", "summary-foundations",
      "history-reconciliation", "tree-codecs", "tree-kernel",
      "bootstrap-map-handles", "batched-commits",
      "map-schema-content", "map-field-algebra", "map-history-codecs",
      "array-schema-content", "array-forest-delta", "sequence-field-editor",
      "sequence-compose-invert", "sequence-rebase", "array-modular-algebra",
      "schema-evolution-compatibility", "schema-evolution-algebra",
      "schema-evolution-history", "schema-evolution-codecs",
      "identifier-schema", "identifier-values",
      "identifier-field-batches", "identifier-persistence",
    ]);
  }
});

test("corpus validation requires every named case and nonempty observations", () => {
  assert.equal(requiredCases.length, 50);
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
