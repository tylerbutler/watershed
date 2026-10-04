import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import { isDeepStrictEqual } from "node:util";
import {
  SchemaFactory,
  TreeViewConfiguration,
} from "fluid-framework/alpha";
import { SharedMap } from "@fluidframework/map/internal";
import { SummaryType } from "@fluidframework/driver-definitions/internal";
import {
  defineDataStore,
  sharedObjectRegistryFromIterable,
} from "@fluidframework/shared-object-base/internal";
import { SharedTree } from "@fluidframework/tree/internal";
import {
  CommitKind,
  RevertibleStatus,
  Tree,
} from "@fluidframework/tree/internal";
import { startClient } from "./client-driver.mjs";
import { DeliveryGate } from "./delivery-gate.mjs";
import {
  arrayServiceStore,
  identifierServiceStore,
  mapServiceStore,
  openSession,
  schemaEvolutionServiceStore,
  tokenProvider,
} from "./service.mjs";
import {
  ArrayMap,
  ArrayPoint,
  ArrayRoot,
  DynamicMap,
  IdentifierItems,
  IdentifierPair,
  IdentifierPoint,
  IdentifierPointsByKey,
  IdentifierRoot,
  Items,
  MapPoint,
  Points,
  schemaEvolutionConfigurations,
} from "./schema.mjs";

const implementations = ["upstream", "javascript", "erlang"];
const nativeTargets = ["javascript", "erlang"];
const seededTemplates = [
  "multiple-pending",
  "optional-conflict",
  "parent-child-conflict",
  "nested-conflict",
];
const mapSeededTemplates = [
  "map-scalar-conflict",
  "map-object-conflict",
  "map-nested-conflict",
  "map-recursive-delete",
];
const schemaSeededTemplates = [
  "schema-data-concurrent",
  "schema-reconnect-summary",
];
const arraySeededTemplates = [
  "array-same-gap",
  "array-insert-remove",
  "array-cross-parent",
  "array-nested-reconnect",
];
const identifierSeededTemplates = ["identifier-default-explicit"];
const replayReference = {
  package: "@fluidframework/tree",
  version: "3.1.0",
  commit: "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960",
};
const replayService = {
  implementation: "floodgate",
  revision: "0eb493fc46d1bb9baf1151a6ccdde93544e057e7",
};
const orderedPairs = implementations.flatMap((first) =>
  implementations.filter((second) => second !== first)
    .map((second) => [first, second]));
const identifierPairs = [
  ["upstream", "javascript"],
  ["upstream", "erlang"],
  ["javascript", "erlang"],
];
const identifierFailureIds = [
  "missing-allocation",
  "wrong-originator",
  "corrupt-numeric-identifier",
  "negative-originatorless-summary",
];
const invalidProfilePath = join(
  import.meta.dirname,
  "../../test/fixtures/shared_tree/cases/invalid-profile.json",
);

const excludedFactory = new SchemaFactory("org.watershed.shared-tree.m1");
const ExcludedMap = excludedFactory.map("ExcludedMap", [excludedFactory.number]);

const transactionPairs = [
  ["upstream", "javascript"],
  ["upstream", "erlang"],
  ["javascript", "erlang"],
];
const transactionConstraintAuthors = {
  "upstream<->javascript": "upstream",
  "upstream<->erlang": "erlang",
  "javascript<->erlang": "javascript",
};
const transactionRaceOrders = ["transaction-first", "remove-first"];

export function transactionPairCells() {
  return transactionPairs.map((authors) => ({
    id: `transaction:${authors.join("<->")}`,
    profile: "array",
    authors,
  }));
}

export function transactionConstraintCells() {
  return transactionPairs.flatMap((authors) => {
    const pair = authors.join("<->");
    const author = transactionConstraintAuthors[pair];
    const remover = authors.find((target) => target !== author);
    return transactionRaceOrders.map((order) => ({
      id: `transaction-constraint:${pair}:${order}`,
      profile: "array",
      authors,
      author,
      remover,
      order,
    }));
  });
}

export function validateTransactionCallbacks(section) {
  assert(section && typeof section === "object" && !Array.isArray(section),
    "Transaction callback evidence must be an object");
  assert(Array.isArray(section.pairs)
    && section.pairs.length === transactionPairs.length,
  "Transaction callback evidence requires three client pairs");
  const pairs = new Map(section.pairs.map((item) => [item.id, item]));
  for (const expected of transactionPairCells()) {
    const item = pairs.get(expected.id);
    assert(item, `Transaction callback evidence lacks ${expected.id}`);
    assert.equal(item.profile, "array", "Transaction pair has another profile");
    assert.equal(item.passed, true, "Transaction pair failed");
    assert.equal(item.skipped, false, "Transaction pair was skipped");
    assert(typeof item.runId === "string" && item.runId.length > 0,
      "Transaction pair lacks a run ID");
    assert.match(item.profileDigest ?? "", /^[0-9a-f]{64}$/,
      "Transaction pair lacks a profile digest");
    assert(typeof item.documentId === "string" && item.documentId.length > 0,
      "Transaction pair lacks a document");
    assert(Array.isArray(item.artifacts) && item.artifacts.length > 0,
      "Transaction pair lacks artifacts");
    assert.deepEqual(Object.keys(item.authors ?? {}).sort(),
      [...expected.authors].sort(), "Transaction pair lacks a real author");
    for (const author of expected.authors) {
      const evidence = item.authors[author];
      assert(evidence && typeof evidence === "object",
        `${author} lacks transaction evidence`);
      const commit = evidence.commit;
      assert(commit && typeof commit === "object",
        `${author} lacks a committed transaction observation`);
      assert.equal(commit.outcome, "committed",
        `${author} did not commit its transaction`);
      assert.equal(commit.callbackObservedEdits, true,
        `${author} callback did not observe its own edits`);
      assert.equal(commit.nestedScopes, 1,
        `${author} lacks a nested transaction scope`);
      assert.equal(commit.nestedOutcome, "committed",
        `${author} nested scope reported another outcome`);
      assert.equal(commit.editsApplied, 2,
        `${author} commit applied another edit count`);
      assert(typeof commit.commitRevision === "string"
        && commit.commitRevision.length > 0,
      `${author} commit lacks a revision`);
      assert.equal(commit.outboundCount, 1,
        `${author} commit submitted another operation count`);
      assert.equal(commit.acceptedCommitCount, 1,
        `${author} commit was not one sequenced commit`);
      assert.equal(commit.peerObservedAtomically, true,
        `${author} commit was not observed by every peer`);
      const abort = evidence.abort;
      assert(abort && typeof abort === "object",
        `${author} lacks an aborted transaction observation`);
      assert.equal(abort.outcome, "aborted",
        `${author} did not abort its transaction`);
      assert.equal(abort.callbackObservedEdits, true,
        `${author} abort callback did not observe its own edits`);
      assert.equal(abort.editsApplied, 1,
        `${author} abort applied another edit count`);
      assert.equal(abort.commitRevision, null,
        `${author} abort produced a commit revision`);
      assert.equal(abort.outboundCount, 0,
        `${author} abort submitted an operation`);
      assert.equal(abort.acceptedCommitCount, 0,
        `${author} abort reached the service`);
      assert.equal(abort.treeUnchanged, true,
        `${author} abort changed its own tree`);
      assert.equal(abort.peerObserved, false,
        `${author} abort reached a peer`);
      if (author !== "upstream") {
        assert.equal(commit.localEventCount, 1,
          `${author} commit emitted another local event count`);
        assert.equal(abort.localEventCount, 0,
          `${author} abort emitted a local event`);
      } else {
        // Fluid 3.1.0 fires one tree event per edit inside a transaction, and
        // also fires on rollback. The strict native contract does not apply.
        // The bound still catches an upstream regression to silence.
        assert(Number.isInteger(commit.localEventCount)
          && commit.localEventCount >= 1,
        `${author} commit emitted no local event`);
        assert(Number.isInteger(abort.localEventCount)
          && abort.localEventCount >= 0,
        `${author} abort lacks a local event count`);
      }
      assert.equal(evidence.movedWithinArray, true,
        `${author} lacks an in-array move inside a transaction`);
      assert.equal(evidence.movedBetweenArrays, true,
        `${author} lacks a cross-array move inside a transaction`);
    }
  }
  return section;
}

export function validateTransactionConstraints(section) {
  assert(Array.isArray(section),
    "Transaction constraint evidence must be an array");
  const expectedCells = transactionConstraintCells();
  assert.equal(section.length, expectedCells.length,
    "Transaction constraint evidence requires both race orderings for every pair");
  const cells = new Map(section.map((item) => [item.id, item]));
  for (const expected of expectedCells) {
    const item = cells.get(expected.id);
    assert(item, `Transaction constraint evidence lacks ${expected.id}`);
    assert.equal(item.order, expected.order,
      "Transaction constraint race ordering changed");
    assert.equal(item.author, expected.author,
      "Transaction constraint author changed");
    assert.equal(item.remover, expected.remover,
      "Transaction constraint remover changed");
    assert.deepEqual(item.authors, expected.authors,
      "Transaction constraint authors changed");
    assert.equal(item.passed, true, "Transaction constraint cell failed");
    assert.equal(item.skipped, false, "Transaction constraint cell was skipped");
    assert(typeof item.runId === "string" && item.runId.length > 0,
      "Transaction constraint cell lacks a run ID");
    assert.match(item.profileDigest ?? "", /^[0-9a-f]{64}$/,
      "Transaction constraint cell lacks a profile digest");
    assert(typeof item.documentId === "string" && item.documentId.length > 0,
      "Transaction constraint cell lacks a document");
    assert(Array.isArray(item.artifacts) && item.artifacts.length > 0,
      "Transaction constraint cell lacks artifacts");
    const applied = expected.order === "transaction-first";
    assert.equal(item.transactionApplied, applied,
      `${expected.id} applied the constrained transaction against its race ordering`);
    assert.equal(item.constraintViolated, !applied,
      `${expected.id} reported another constraint outcome`);
    assert.equal(item.converged, true, `${expected.id} did not converge`);
    assert(Array.isArray(item.sequenced), `${expected.id} lacks sequencing evidence`);
    assert.deepEqual(item.sequenced.map(({ author }) => author),
      applied
        ? [expected.author, expected.remover]
        : [expected.remover, expected.author],
      `${expected.id} sequenced its operations in another order`);
  }
  return section;
}

export function identifierPairCells() {
  return identifierPairs.map((authors) => ({
    id: `identifier:${authors.join("<->")}`,
    profile: "identifier",
    authors,
  }));
}

export function validateIdentifierFields(section) {
  assert(section && typeof section === "object" && !Array.isArray(section),
    "Identifier fields evidence must be an object");
  assert(Array.isArray(section.pairs)
    && section.pairs.length === identifierPairs.length,
  "Identifier fields evidence requires three client pairs");
  const pairs = new Map(section.pairs.map((item) => [item.id, item]));
  for (const expected of identifierPairCells()) {
    const item = pairs.get(expected.id);
    assert(item, `Identifier fields evidence lacks ${expected.id}`);
    assert.equal(item.profile, "identifier", "Identifier pair has another profile");
    assert.equal(item.passed, true, "Identifier pair failed");
    assert.equal(item.skipped, false, "Identifier pair was skipped");
    assert(typeof item.runId === "string" && item.runId.length > 0,
      "Identifier pair lacks a run ID");
    assert.match(item.profileDigest, /^[0-9a-f]{64}$/,
      "Identifier pair lacks a profile digest");
    assert(typeof item.documentId === "string" && item.documentId.length > 0,
      "Identifier pair lacks a document");
    assert(Array.isArray(item.artifacts) && item.artifacts.length > 0,
      "Identifier pair lacks artifacts");
    assert.deepEqual(Object.keys(item.authors ?? {}).sort(), [...expected.authors].sort(),
      "Identifier pair lacks a real author");
    for (const author of expected.authors) {
      const evidence = item.authors[author];
      assert(typeof evidence?.defaultId === "string" && evidence.defaultId.length > 0,
        `${author} lacks a generated Identifier`);
      assert.equal(evidence.explicitId, "shared-custom-id",
        `${author} changed the explicit Identifier`);
      assert.equal(evidence.peerObserved, true, `${author} lacks peer observation`);
      assert.equal(evidence.constraintsUseNodeIdentity, true,
        `${author} constraints used Identifier equality`);
      assert.equal(evidence.movedWithinArray, true, `${author} lacks an in-array move`);
      assert.equal(evidence.movedBetweenArrays, true, `${author} lacks a cross-array move`);
      assert.equal(evidence.equalIdReplacementChangedReference, true,
        `${author} lacks equal-ID replacement identity evidence`);
    }
  }
  assert(Array.isArray(section.failures)
    && section.failures.length === identifierFailureIds.length * nativeTargets.length,
  "Identifier fields evidence requires every protocol refusal target");
  assert.deepEqual([...new Set(section.failures.map(({ caseId }) => caseId))].sort(),
    [...identifierFailureIds].sort(), "Identifier protocol refusal coverage changed");
  assert.equal(new Set(section.failures.map(({ caseId, target }) =>
    `${caseId}:${target}`)).size, section.failures.length,
  "Identifier protocol refusal coverage repeats a cell");
  assert.deepEqual([...new Set(section.failures.map(({ target }) => target))].sort(),
    [...nativeTargets].sort(), "Identifier refusals lack a native target");
  assert.deepEqual(
    section.failures.map(({ caseId, target }) => `${caseId}:${target}`).sort(),
    identifierFailureIds.flatMap((caseId) =>
      nativeTargets.map((target) => `${caseId}:${target}`)).sort(),
    "Identifier protocol refusal coverage changed",
  );
  for (const item of section.failures) {
    assert.equal(item.outcome, "refused", `${item.caseId} was not refused`);
    assert.equal(item.failureObserved, true, `${item.caseId} lacks failure evidence`);
    assert.equal(item.partialReadinessObserved, false,
      `${item.caseId} exposed partial readiness`);
    assert.equal(item.partialMutationObserved, false,
      `${item.caseId} exposed partial mutation`);
    assert(typeof item.typedError?.code === "string"
      && typeof item.typedError.operation === "string"
      && typeof item.typedError.message === "string",
    `${item.caseId} lacks a typed error`);
    assert(Array.isArray(item.artifacts) && item.artifacts.length > 0,
      `${item.caseId} lacks artifacts`);
  }
  return section;
}

function identifierPoint(label, id) {
  return {
    kind: "object",
    schemaId: "org.watershed.shared-tree.identifiers.Point",
    fields: [
      ...(id === undefined ? [] : [["id", { kind: "string", value: id }]]),
      ["label", { kind: "string", value: label }],
    ],
  };
}

export async function runIdentifierPairActions({
  authors,
  adapters,
  afterAuthor = () => {},
  beforeConstrainedRemove = () => {},
  beforeReplacement = () => {},
}) {
  assert.equal(authors.length, 2, "Identifier pair requires two authors");
  for (const [index, author] of authors.entries()) {
    const adapter = adapters[author];
    assert(adapter, `Identifier pair lacks ${author}`);
    await adapter.arrayInsert(["left"], index, [
      identifierPoint(`${author}-default`),
    ]);
    await adapter.arrayInsert(["right"], index, [
      identifierPoint(`${author}-explicit`, "shared-custom-id"),
    ]);
    await afterAuthor(author);
  }
  await adapters[authors[0]].arrayMove(["left"], 0, 1, ["left"], 2);
  await adapters[authors[1]].arrayMove(["right"], 0, 1, ["left"], 0);
  await beforeConstrainedRemove();
  await adapters[authors[1]].constrainedArrayRemove(
    ["left", "0"],
    ["right"],
    0,
    1,
  );
  await beforeReplacement();
  await adapters[authors[1]].arrayInsert(["right"], 0, [
    identifierPoint(`${authors[1]}-replacement`, "shared-custom-id"),
  ]);
}

function excludedStore() {
  const schema = ExcludedMap;
  const config = new TreeViewConfiguration({ schema });
  return defineDataStore({
    type: "org.watershed.shared-tree.m1.excluded-map",
    registry: sharedObjectRegistryFromIterable([SharedMap, SharedTree]),
    async instantiateFirstTime(rootCreator, creator) {
      const bootstrap = await rootCreator.createSharedObject(SharedMap);
      const tree = await creator.createSharedObject(SharedTree);
      const view = tree.viewWith(config);
      view.initialize(new ExcludedMap([["key", 1]]));
      view.dispose();
      bootstrap.set("tree", tree.handle);
      return bootstrap;
    },
    async view(bootstrap) {
      const handle = bootstrap.get("tree");
      assert.equal(typeof handle?.get, "function", "Excluded bootstrap tree handle is missing");
      const tree = await handle.get();
      assert.equal(tree.attributes.type, SharedTree.getFactory().type,
        "Excluded bootstrap handle is not a tree");
      return { bootstrap, tree, view: tree.viewWith(config) };
    },
  });
}

function notificationEvidence(checkpoints) {
  return Object.fromEntries(implementations.map((implementation) => {
    const events = checkpoints.flatMap(({ observations }) =>
      observations.find((observation) =>
        observation.implementation === implementation)?.events ?? []);
    return [implementation, {
      schema: events.filter(({ kind }) => kind === "schema"),
      data: events.filter(({ kind }) => kind === "data"),
    }];
  }));
}

export function reconciledRaceCheckpoint(checkpoint, losingAuthor, winnerSequenceNumber) {
  const loser = checkpoint.observations.find(
    ({ implementation }) => implementation === losingAuthor,
  );
  return checkpoint.observations.every(
    ({ sequenceNumber }) => sequenceNumber >= winnerSequenceNumber,
  )
    && loser?.history?.pending?.length > 0
    && loser.history.pending.every(
      ({ changeset }) => changeset?.changeCount === 0,
    );
}

export function matchReconnectOperations(originals, accepted) {
  assert.equal(originals.length, 2, "Reconnect requires exactly two original operations");
  assert.equal(accepted.length, 2, "Reconnect has unrelated accepted operations");
  const remaining = [...accepted];
  const mappings = originals.map((original, originalIndex) => {
    const originalPayload = decodeReconnectPayload(original.payload);
    const matches = remaining.flatMap((candidate, index) =>
      candidate.originatorId === original.originatorId
        && isDeepStrictEqual(decodeReconnectPayload(candidate.payload), originalPayload)
        ? [{ candidate, index }]
        : []);
    assert.equal(matches.length, 1, "Reconnect operation mapping is not one-to-one");
    const [{ candidate, index }] = matches;
    remaining.splice(index, 1);
    return {
      originalRevision: original.revision,
      acceptedRevision: candidate.revision,
    };
  });
  assert.equal(remaining.length, 0, "Reconnect has unrelated accepted operations");
  assert.deepEqual(mappings.map(({ acceptedRevision }) => acceptedRevision),
    accepted.map(({ revision }) => revision),
  "Reconnect operation order changed");
  return mappings;
}

export function commitKinds(commit) {
  return commit.changeset.flatMap((change) => {
    const kinds = [];
    if (change?.schema !== undefined) kinds.push("schema");
    if (change?.data !== undefined) kinds.push("data");
    return kinds;
  });
}

function parsedPayload(payload) {
  if (typeof payload !== "string") return payload;
  try {
    return JSON.parse(payload);
  } catch {
    return payload;
  }
}

function canonicalSchemaValue(value, key = "") {
  if (Array.isArray(value)) {
    const items = value.map((item) => canonicalSchemaValue(item));
    if (key === "types" || key === "entries") {
      return items.sort((left, right) =>
        JSON.stringify(left).localeCompare(JSON.stringify(right)));
    }
    return items;
  }
  if (!value || typeof value !== "object") return value;
  return Object.fromEntries(Object.keys(value).sort().map((name) => [
    name,
    canonicalSchemaValue(value[name], name),
  ]));
}

function schemaEntries(value) {
  if (Array.isArray(value)) return value;
  if (Array.isArray(value?.entries)) return value.entries;
  if (Array.isArray(value?._root?.keys)
    && Array.isArray(value._root.values)
    && value._root.keys.length === value._root.values.length) {
    return value._root.keys.map((name, index) => [
      name,
      value._root.values[index],
    ]);
  }
  return Object.entries(value ?? {});
}

function schemaMetadata(value, ignored) {
  const metadata = Object.fromEntries(Object.entries(value ?? {})
    .filter(([name]) => !ignored.includes(name))
    .map(([name, item]) => [name, canonicalSchemaValue(item, name)]));
  return Object.keys(metadata).length === 0 ? undefined : metadata;
}

function canonicalSchemaTypes(value) {
  const types = Array.isArray(value) ? value : value?.values ?? [];
  return types.map((type) => canonicalSchemaValue(type))
    .sort((left, right) =>
      JSON.stringify(left).localeCompare(JSON.stringify(right)));
}

function canonicalFieldSchema(field) {
  const metadata = schemaMetadata(field, ["kind", "types"]);
  return {
    kind: field?.kind,
    types: canonicalSchemaTypes(field?.types),
    ...(metadata === undefined ? {} : { metadata }),
  };
}

function canonicalNodeSchema(node) {
  const storedKind = node?.kind;
  const kindMetadata = schemaMetadata(storedKind, ["leaf", "object", "map"]);
  if (storedKind?.leaf !== undefined || node?.leafValue !== undefined) {
    const metadata = schemaMetadata(node, ["kind", "leafValue", "isShared"]);
    return {
      kind: "leaf",
      value: storedKind?.leaf ?? node.leafValue,
      ...(kindMetadata === undefined ? {} : { kindMetadata }),
      ...(metadata === undefined ? {} : { metadata }),
    };
  }
  const object = storedKind?.object ?? node?.objectNodeFields;
  if (object !== undefined) {
    const metadata = schemaMetadata(node,
      ["kind", "objectNodeFields", "isShared"]);
    return {
      kind: "object",
      fields: schemaEntries(object)
        .map(([name, field]) => [name, canonicalFieldSchema(field)])
        .sort(([left], [right]) => left.localeCompare(right)),
      ...(kindMetadata === undefined ? {} : { kindMetadata }),
      ...(metadata === undefined ? {} : { metadata }),
    };
  }
  const map = storedKind?.map ?? node?.mapFields;
  if (map !== undefined) {
    const metadata = schemaMetadata(node, ["kind", "mapFields", "isShared"]);
    return {
      kind: "map",
      field: canonicalFieldSchema(map),
      ...(kindMetadata === undefined ? {} : { kindMetadata }),
      ...(metadata === undefined ? {} : { metadata }),
    };
  }
  return canonicalSchemaValue(node);
}

function canonicalSchema(schema) {
  if (!schema || typeof schema !== "object" || Array.isArray(schema)) {
    return canonicalSchemaValue(schema);
  }
  const nodes = schema.nodes
    ?? schema.nodeSchema
    ?? schema.nodeSchemaData;
  const root = schema.root
    ?? schema.rootFieldSchema
    ?? schema.rootFieldSchemaData;
  if (nodes === undefined || root === undefined) {
    return canonicalSchemaValue(schema);
  }
  const metadata = schemaMetadata(schema, [
    "nodes",
    "nodeSchema",
    "nodeSchemaData",
    "root",
    "rootFieldSchema",
    "rootFieldSchemaData",
    "version",
    "_events",
    "events",
  ]);
  return {
    version: schema.version ?? 2,
    nodes: schemaEntries(nodes)
      .map(([name, node]) => [name, canonicalNodeSchema(node)])
      .sort(([left], [right]) => left.localeCompare(right)),
    root: canonicalFieldSchema(root),
    ...(metadata === undefined ? {} : { metadata }),
  };
}

function schemaDiagnostic(value) {
  return value.replace(/\s+/g, " ").replace(/\s*([,[\]()])\s*/g, "$1").trim();
}

function persistedSchemaDiagnostic(value) {
  const persisted = value.indexOf("persisted:");
  const positional = value.indexOf('VObject([#("nodes"');
  if (persisted < 0 && positional < 0) return schemaDiagnostic(value);
  let index = persisted < 0 ? positional : value.indexOf("VObject", persisted);
  assert(index >= 0, "Reconnect schema diagnostic lacks persisted schema content");

  const skipSpace = () => {
    while (/\s/.test(value[index])) index += 1;
  };
  const consume = (token) => {
    skipSpace();
    assert.equal(value.slice(index, index + token.length), token,
      "Reconnect schema diagnostic has invalid persisted schema content");
    index += token.length;
  };
  const parseString = () => {
    skipSpace();
    const start = index;
    consume("\"");
    let escaped = false;
    while (index < value.length) {
      const character = value[index];
      index += 1;
      if (!escaped && character === "\"") {
        return JSON.parse(value.slice(start, index));
      }
      escaped = !escaped && character === "\\";
      if (character !== "\\") escaped = false;
    }
    assert.fail("Reconnect schema diagnostic has an unterminated string");
  };
  const parseList = (parseItem) => {
    const items = [];
    consume("[");
    skipSpace();
    while (value[index] !== "]") {
      items.push(parseItem());
      skipSpace();
      if (value[index] === ",") {
        index += 1;
        skipSpace();
      } else {
        break;
      }
    }
    consume("]");
    return items;
  };
  const parseValue = () => {
    skipSpace();
    if (value.startsWith("VObject", index)) {
      consume("VObject(");
      const entries = parseList(() => {
        consume("#(");
        const name = parseString();
        consume(",");
        const item = parseValue();
        consume(")");
        return [name, item];
      });
      consume(")");
      return Object.fromEntries(entries);
    }
    if (value.startsWith("VArray", index)) {
      consume("VArray(");
      const items = parseList(parseValue);
      consume(")");
      return items;
    }
    if (value.startsWith("VString", index)) {
      consume("VString(");
      const text = parseString();
      consume(")");
      return text;
    }
    if (value.startsWith("VNumber", index)) {
      consume("VNumber(");
      const kind = value.startsWith("NInt", index) ? "NInt" : "NFloat";
      consume(`${kind}(`);
      skipSpace();
      const match = value.slice(index).match(/^-?\d+(?:\.\d+)?(?:e[+-]?\d+)?/i);
      assert(match, "Reconnect schema diagnostic has an invalid number");
      index += match[0].length;
      consume("))");
      return Number(match[0]);
    }
    if (value.startsWith("VBool", index)) {
      consume("VBool(");
      skipSpace();
      const boolean = value.startsWith("True", index);
      consume(boolean ? "True" : "False");
      consume(")");
      return boolean;
    }
    if (value.startsWith("VNull", index)) {
      consume("VNull");
      return null;
    }
    assert.fail("Reconnect schema diagnostic has an unsupported persisted value");
  };

  return canonicalSchema(parseValue());
}

function parseNativeDiagnostic(value) {
  let index = 0;
  const skipSpace = () => {
    while (/\s/.test(value[index])) index += 1;
  };
  const consume = (token) => {
    skipSpace();
    assert.equal(value.slice(index, index + token.length), token,
      "Reconnect payload has invalid native operation structure");
    index += token.length;
  };
  const parseDelimited = (end) => {
    const items = [];
    skipSpace();
    while (value[index] !== end) {
      items.push(parseValue());
      skipSpace();
      if (value[index] === ",") {
        index += 1;
        skipSpace();
      } else {
        break;
      }
    }
    consume(end);
    return items;
  };
  const parseString = () => {
    skipSpace();
    const start = index;
    consume("\"");
    let escaped = false;
    while (index < value.length) {
      const character = value[index];
      index += 1;
      const wasEscaped = escaped;
      if (character === "\"" && !wasEscaped) {
        return {
          kind: "string",
          value: JSON.parse(value.slice(start, index)),
          raw: value.slice(start, index),
        };
      }
      escaped = character === "\\" && !wasEscaped;
    }
    assert.fail("Reconnect payload has an unterminated native string");
  };
  const parseValue = () => {
    skipSpace();
    const start = index;
    if (value[index] === "\"") return parseString();
    if (value.startsWith("#(", index)) {
      index += 2;
      const items = parseDelimited(")");
      return {
        kind: "tuple",
        items,
        raw: value.slice(start, index),
      };
    }
    if (value[index] === "[") {
      index += 1;
      const items = parseDelimited("]");
      return {
        kind: "list",
        items,
        raw: value.slice(start, index),
      };
    }
    const number = value.slice(index).match(/^-?\d+(?:\.\d+)?(?:e[+-]?\d+)?/i);
    if (number) {
      index += number[0].length;
      return {
        kind: "number",
        value: Number(number[0]),
        raw: value.slice(start, index),
      };
    }
    const identifier = value.slice(index).match(/^[A-Za-z_][A-Za-z0-9_.]*/);
    assert(identifier, "Reconnect payload has invalid native operation structure");
    index += identifier[0].length;
    skipSpace();
    if (value[index] === ":") {
      index += 1;
      const item = parseValue();
      return {
        kind: "named",
        name: identifier[0],
        value: item,
        raw: value.slice(start, index),
      };
    }
    if (value[index] !== "(") {
      return {
        kind: "atom",
        name: identifier[0],
        raw: value.slice(start, index).trim(),
      };
    }
    index += 1;
    const args = parseDelimited(")");
    return {
      kind: "call",
      name: identifier[0],
      args,
      raw: value.slice(start, index),
    };
  };

  const parsed = parseValue();
  skipSpace();
  assert.equal(index, value.length,
    "Reconnect payload has trailing native operation content");
  return parsed;
}

function nativeCall(value, name, argumentCount) {
  assert(value?.kind === "call" && value.name === name,
    `Reconnect payload requires ${name}`);
  if (argumentCount !== undefined) {
    assert.equal(value.args.length, argumentCount,
      `Reconnect payload has invalid ${name} arguments`);
  }
  return value;
}

function nativeArguments(value, name, fields) {
  const call = nativeCall(value, name);
  const named = call.args.some(({ kind }) => kind === "named");
  if (!named) {
    assert.equal(call.args.length, fields.length,
      `Reconnect payload has invalid ${name} arguments`);
    return call.args;
  }
  assert(call.args.every(({ kind }) => kind === "named"),
    `Reconnect payload has mixed ${name} arguments`);
  assert.equal(call.args.length, fields.length,
    `Reconnect payload has invalid ${name} arguments`);
  const entries = new Map(call.args.map((argument) => [
    argument.name,
    argument.value,
  ]));
  assert.equal(entries.size, fields.length,
    `Reconnect payload has duplicate ${name} arguments`);
  assert.deepEqual([...entries.keys()].sort(), [...fields].sort(),
    `Reconnect payload has invalid ${name} argument names`);
  return fields.map((field) => entries.get(field));
}

function nativeAtom(value, names, label) {
  assert(value?.kind === "atom" && names.includes(value.name),
    `Reconnect payload has invalid ${label}`);
  return value.name;
}

function nativeNumber(value, label, integer = false) {
  assert(value?.kind === "number" && Number.isFinite(value.value),
    `Reconnect payload has invalid ${label}`);
  if (integer) {
    assert(Number.isSafeInteger(value.value),
      `Reconnect payload has invalid ${label}`);
  }
  return value.value;
}

function nativeString(value, label) {
  assert(value?.kind === "string",
    `Reconnect payload has invalid ${label}`);
  return value.value;
}

function nativeList(value, validate, label) {
  assert(value?.kind === "list",
    `Reconnect payload has invalid ${label}`);
  return value.items.map(validate);
}

function nativeTuple(value, length, label) {
  assert(value?.kind === "tuple" && value.items.length === length,
    `Reconnect payload has invalid ${label}`);
  return value.items;
}

function nativeBoolean(value, label) {
  return nativeAtom(value, ["True", "False"], label) === "True";
}

function validateNativeOption(value, validate, label) {
  if (value?.kind === "atom") {
    nativeAtom(value, ["None"], label);
    return undefined;
  }
  const [item] = nativeArguments(value, "Some", ["value"]);
  return validate(item);
}

function validateNativeUuid(value) {
  const limbs = nativeArguments(value, "Uuid", [
    "high",
    "middle_high",
    "middle_low",
    "low",
  ]);
  for (const limb of limbs) {
    const number = nativeNumber(limb, "UUID limb", true);
    assert(number >= 0 && number <= 0xffff_ffff,
      "Reconnect payload has invalid UUID limb");
  }
}

function validateNativeStableId(value) {
  const [uuid] = nativeArguments(value, "StableId", ["uuid"]);
  validateNativeUuid(uuid);
}

function validateNativeAtomId(value) {
  const [revision, localId] = nativeArguments(value, "AtomId", [
    "revision",
    "local_id",
  ]);
  validateNativeOption(revision, validateNativeStableId, "atom revision");
  nativeNumber(localId, "atom local ID", true);
}

function validateNativeRevisionInfo(value) {
  const [revision, rollbackOf] = nativeArguments(value, "RevisionInfo", [
    "revision",
    "rollback_of",
  ]);
  validateNativeStableId(revision);
  validateNativeOption(rollbackOf, validateNativeStableId, "rollback revision");
}

function validateNativeRegister(value) {
  if (value?.kind === "atom") {
    nativeAtom(value, ["Active"], "register");
    return { kind: "active" };
  }
  const [id] = nativeArguments(value, "Detached", ["id"]);
  validateNativeAtomId(id);
  return { kind: "detached", id: id.raw };
}

function validateNativeReplacement(value) {
  const [wasEmpty, source, detachId] = nativeArguments(value, "Replacement", [
    "was_empty",
    "source",
    "detach_id",
  ]);
  const empty = nativeBoolean(wasEmpty, "replacement empty marker");
  const sourceRegister =
    validateNativeOption(source, validateNativeRegister, "replacement source");
  validateNativeAtomId(detachId);
  if (sourceRegister?.kind === "detached") return sourceRegister.id;
  if (sourceRegister?.kind === "active" || empty) {
    assert.fail("Reconnect payload has a non-substantive field replacement");
  }
  assert.fail(
    "Reconnect payload field replacement does not attach a built value",
  );
}

function validateNativeOptionalFieldChange(value) {
  const [moves, childChanges, replacement] = nativeArguments(
    value,
    "FieldChange",
    ["moves", "child_changes", "replacement"],
  );
  nativeList(moves, (move) => {
    const [source, destination] = nativeTuple(move, 2, "field move");
    validateNativeAtomId(source);
    validateNativeAtomId(destination);
  }, "field moves");
  nativeList(childChanges, (change) => {
    const [register, child] = nativeTuple(change, 2, "child change");
    validateNativeRegister(register);
    validateNativeAtomId(child);
  }, "child changes");
  const source =
    validateNativeOption(replacement, validateNativeReplacement, "replacement");
  assert(source !== undefined,
    "Reconnect payload has a non-substantive field replacement");
  return source;
}

function validateNativeFieldChange(value) {
  if (value?.kind !== "call") {
    assert.fail("Reconnect payload has invalid field change");
  }
  if (value.name === "ValueField" || value.name === "OptionalField") {
    const [change] = nativeArguments(value, value.name, ["change"]);
    return {
      kind: value.name,
      source: validateNativeOptionalFieldChange(change),
    };
  }
  if (value.name === "GenericField") {
    const [children] = nativeArguments(value, "GenericField", ["children"]);
    nativeList(children, (child) => {
      const [index, id] = nativeTuple(child, 2, "generic child");
      nativeNumber(index, "generic child index", true);
      validateNativeAtomId(id);
    }, "generic children");
    return { kind: value.name, source: undefined };
  }
  assert.fail(`Reconnect payload has unsupported ${value.name} constructor`);
}

function validateNativeFieldEntries(value) {
  return nativeList(value, (entry) => {
    const [name, change] = nativeTuple(entry, 2, "field entry");
    const field = nativeString(name, "field name");
    const validated = validateNativeFieldChange(change);
    return validated.kind === "GenericField"
      ? []
      : [{ field, source: validated.source }];
  }, "field entries").flat();
}

function validateNativeNodeChange(value) {
  const call = nativeCall(value, "NodeChange");
  let fields;
  if (call.args.length === 1) {
    [fields] = nativeArguments(value, "NodeChange", ["fields"]);
  } else {
    const [
      currentFields,
      constraint,
      revertConstraint,
    ] = nativeArguments(value, "NodeChange", [
      "fields",
      "node_exists_constraint",
      "node_exists_constraint_on_revert",
    ]);
    const validateConstraint = (item) => {
      const [violated] = nativeArguments(
        item,
        "NodeExistsConstraint",
        ["violated"],
      );
      nativeBoolean(violated, "node-exists constraint violation");
    };
    validateNativeOption(constraint, validateConstraint, "node-exists constraint");
    validateNativeOption(
      revertConstraint,
      validateConstraint,
      "revert node-exists constraint",
    );
    fields = currentFields;
  }
  return validateNativeFieldEntries(fields);
}

function validateNativeParentField(value) {
  const [parent, field] = nativeArguments(value, "ParentField", [
    "parent",
    "field",
  ]);
  validateNativeOption(parent, validateNativeAtomId, "parent atom");
  nativeString(field, "parent field");
}

function validateNativeTreeValue(value) {
  if (value?.kind === "atom") {
    nativeAtom(value, ["NullValue"], "tree value");
    return [null];
  }
  if (value?.kind !== "call") {
    assert.fail("Reconnect payload has invalid tree value");
  }
  if (value.name === "StringValue") {
    const [item] = nativeArguments(value, "StringValue", ["value"]);
    return [nativeString(item, "string value")];
  }
  if (value.name === "NumberValue") {
    const [item] = nativeArguments(value, "NumberValue", ["value"]);
    return [nativeNumber(item, "number value")];
  }
  if (value.name === "BooleanValue") {
    const [item] = nativeArguments(value, "BooleanValue", ["value"]);
    return [nativeBoolean(item, "boolean value")];
  }
  if (value.name === "ObjectValue" || value.name === "MapValue") {
    const [schemaId, entries] = nativeArguments(value, value.name, [
      "schema_id",
      value.name === "ObjectValue" ? "fields" : "entries",
    ]);
    nativeString(schemaId, "tree schema ID");
    return nativeList(entries, (entry) => {
      const [name, item] = nativeTuple(entry, 2, "tree value entry");
      nativeString(name, "tree value field");
      return validateNativeTreeValue(item);
    }, "tree value entries").flat();
  }
  assert.fail(`Reconnect payload has unsupported ${value.name} constructor`);
}

function validateNativeBuild(value) {
  const [id, trees] = nativeArguments(value, "Build", ["id", "trees"]);
  validateNativeAtomId(id);
  return {
    id: id.raw,
    values: nativeList(trees, validateNativeTreeValue, "built trees").flat(),
  };
}

function validateNativeDestroy(value) {
  const [id, count] = nativeArguments(value, "Destroy", ["id", "count"]);
  validateNativeAtomId(id);
  nativeNumber(count, "destroy count", true);
}

function validateNativeCrossFieldKey(value) {
  const [key, count, field] = nativeArguments(value, "CrossFieldKey", [
    "key",
    "count",
    "field",
  ]);
  const [side, revision, localId] = nativeArguments(key, "Key", [
    "side",
    "revision",
    "local_id",
  ]);
  nativeAtom(side, ["Source", "Destination"], "cross-field side");
  validateNativeOption(revision, validateNativeStableId, "cross-field revision");
  nativeNumber(localId, "cross-field local ID", true);
  nativeNumber(count, "cross-field count", true);
  const [parent, name] = nativeArguments(field, "FieldId", ["parent", "field"]);
  validateNativeOption(parent, validateNativeAtomId, "cross-field parent");
  nativeString(name, "cross-field name");
}

function validateNativeChangeData(value) {
  const call = nativeCall(value, "ChangeData");
  const named = call.args.some(({ kind }) => kind === "named");
  let values;
  if (named) {
    assert(call.args.every(({ kind }) => kind === "named"),
      "Reconnect payload has mixed ChangeData arguments");
    const names = call.args.map(({ name }) => name).sort();
    const complete = [
      "aliases",
      "builds",
      "cross_field_keys",
      "destroys",
      "fields",
      "max_local_id",
      "nodes",
      "parents",
      "refreshers",
      "revisions",
    ];
    assert.deepEqual(
      names.filter((name) => name !== "constraint_violation_count"),
      complete,
      "Reconnect payload has invalid ChangeData argument names");
    const entries = new Map(call.args.map((argument) => [
      argument.name,
      argument.value,
    ]));
    assert.equal(entries.size, call.args.length,
      "Reconnect payload has duplicate ChangeData arguments");
    values = entries;
  } else {
    assert([10, 11].includes(call.args.length),
      "Reconnect payload has invalid ChangeData arguments");
    values = new Map([
      ["max_local_id", call.args[0]],
      ["revisions", call.args[1]],
      ["fields", call.args[2]],
      ["nodes", call.args[3]],
      ["parents", call.args[4]],
      ["aliases", call.args[5]],
      ["builds", call.args[6]],
      ["destroys", call.args[7]],
      ["refreshers", call.args[8]],
      ["cross_field_keys", call.args[9]],
      ...(call.args.length === 11
        ? [["constraint_violation_count", call.args[10]]]
        : []),
    ]);
  }
  if (values.has("max_local_id")) {
    nativeNumber(values.get("max_local_id"), "maximum local ID", true);
  }
  if (values.has("constraint_violation_count")) {
    nativeNumber(
      values.get("constraint_violation_count"),
      "constraint violation count",
      true,
    );
  }
  if (values.has("revisions")) {
    nativeList(values.get("revisions"), validateNativeRevisionInfo, "revisions");
  }
  const fields = validateNativeFieldEntries(values.get("fields"));
  if (values.has("nodes")) {
    fields.push(...nativeList(values.get("nodes"), (entry) => {
      const [id, change] = nativeTuple(entry, 2, "node change entry");
      validateNativeAtomId(id);
      return validateNativeNodeChange(change);
    }, "node changes").flat());
  }
  if (values.has("parents")) {
    nativeList(values.get("parents"), (entry) => {
      const [id, parent] = nativeTuple(entry, 2, "parent entry");
      validateNativeAtomId(id);
      validateNativeParentField(parent);
    }, "parents");
  }
  if (values.has("aliases")) {
    nativeList(values.get("aliases"), (entry) => {
      const [oldId, newId] = nativeTuple(entry, 2, "alias entry");
      validateNativeAtomId(oldId);
      validateNativeAtomId(newId);
    }, "aliases");
  }
  const builds = nativeList(
    values.get("builds"),
    validateNativeBuild,
    "builds",
  );
  if (values.has("destroys")) {
    nativeList(values.get("destroys"), validateNativeDestroy, "destroys");
  }
  if (values.has("refreshers")) {
    nativeList(values.get("refreshers"), validateNativeBuild, "refreshers");
  }
  nativeList(
    values.get("cross_field_keys"),
    validateNativeCrossFieldKey,
    "cross-field keys",
  );
  assert(fields.every(({ source }) =>
    builds.some(({ id }) => id === source)),
  "Reconnect payload field replacement does not use a built value");
  return {
    fields: fields.map(({ field }) => field),
    values: builds.flatMap(({ values }) => values),
  };
}

function validateNativeIdentityOrder(value) {
  const [entries] = nativeArguments(value, "IdentityOrder", ["entries"]);
  nativeList(entries, (entry) => {
    const [revision, position] = nativeTuple(entry, 2, "identity entry");
    validateNativeStableId(revision);
    nativeNumber(position, "identity position", true);
  }, "identity entries");
}

function validateNativeStringList(value, label) {
  nativeList(value, (item) => nativeString(item, label), label);
}

function validateNativeFieldSchema(value) {
  const [cardinality, allowedTypes] = nativeArguments(value, "FieldSchema", [
    "cardinality",
    "allowed_types",
  ]);
  nativeAtom(cardinality, ["Required", "Optional"], "field cardinality");
  validateNativeStringList(allowedTypes, "allowed schema types");
}

function validateNativeDictionary(value, validate, label) {
  const [entries] = nativeArguments(value, "dict.from_list", ["entries"]);
  nativeList(entries, (entry) => {
    const [name, item] = nativeTuple(entry, 2, label);
    nativeString(name, `${label} name`);
    validate(item);
  }, label);
}

function validateNativeNodeSchema(value) {
  if (value?.kind !== "call") {
    assert.fail("Reconnect payload has invalid node schema");
  }
  if (value.name === "Leaf") {
    const [kind] = nativeArguments(value, "Leaf", ["kind"]);
    nativeAtom(kind, ["StringLeaf", "NumberLeaf", "BooleanLeaf", "NullLeaf"],
      "leaf kind");
    return;
  }
  if (value.name === "Object") {
    const [fields] = nativeArguments(value, "Object", ["fields"]);
    nativeList(fields, (entry) => {
      const [name, field] = nativeTuple(entry, 2, "object schema field");
      nativeString(name, "object schema field name");
      validateNativeFieldSchema(field);
    }, "object schema fields");
    return;
  }
  if (value.name === "Map") {
    const [entries] = nativeArguments(value, "Map", ["entries"]);
    validateNativeFieldSchema(entries);
    return;
  }
  assert.fail(`Reconnect payload has unsupported ${value.name} constructor`);
}

function validateNativeComparisonField(value) {
  const [kind, allowedTypes] = nativeArguments(value, "ComparisonField", [
    "kind",
    "allowed_types",
  ]);
  nativeAtom(kind, [
    "ForbiddenKind",
    "OptionalKind",
    "RequiredKind",
    "SequenceKind",
    "IdentifierKind",
  ], "comparison field kind");
  validateNativeStringList(allowedTypes, "comparison allowed types");
}

function validateNativeComparisonNode(value) {
  if (value?.kind !== "call") {
    assert.fail("Reconnect payload has invalid comparison node");
  }
  if (value.name === "ComparisonLeaf") {
    const [kind] = nativeArguments(value, "ComparisonLeaf", ["kind"]);
    nativeAtom(kind, [
      "ComparisonStringLeaf",
      "ComparisonNumberLeaf",
      "ComparisonBooleanLeaf",
      "ComparisonHandleLeaf",
      "ComparisonNullLeaf",
    ], "comparison leaf kind");
    return;
  }
  if (value.name === "ComparisonObject") {
    const [fields] = nativeArguments(value, "ComparisonObject", ["fields"]);
    nativeList(fields, (entry) => {
      const [name, field] = nativeTuple(entry, 2, "comparison object field");
      nativeString(name, "comparison object field name");
      validateNativeComparisonField(field);
    }, "comparison object fields");
    return;
  }
  if (value.name === "ComparisonMap") {
    const [entries] = nativeArguments(value, "ComparisonMap", ["entries"]);
    validateNativeComparisonField(entries);
    return;
  }
  assert.fail(`Reconnect payload has unsupported ${value.name} constructor`);
}

function validateNativeJson(value) {
  if (value?.kind === "atom") {
    nativeAtom(value, ["VNull"], "persisted JSON value");
    return;
  }
  if (value?.kind !== "call") {
    assert.fail("Reconnect payload has invalid persisted JSON value");
  }
  if (value.name === "VBool") {
    const [item] = nativeArguments(value, "VBool", ["value"]);
    nativeBoolean(item, "persisted JSON boolean");
    return;
  }
  if (value.name === "VString") {
    const [item] = nativeArguments(value, "VString", ["value"]);
    nativeString(item, "persisted JSON string");
    return;
  }
  if (value.name === "VNumber") {
    const [item] = nativeArguments(value, "VNumber", ["value"]);
    assert(item?.kind === "call" && ["NInt", "NFloat"].includes(item.name),
      "Reconnect payload has invalid persisted JSON number");
    const [number] = nativeArguments(item, item.name, ["value"]);
    nativeNumber(number, "persisted JSON number", item.name === "NInt");
    return;
  }
  if (value.name === "VArray") {
    const [items] = nativeArguments(value, "VArray", ["items"]);
    nativeList(items, validateNativeJson, "persisted JSON array");
    return;
  }
  if (value.name === "VObject") {
    const [entries] = nativeArguments(value, "VObject", ["entries"]);
    nativeList(entries, (entry) => {
      const [name, item] = nativeTuple(entry, 2, "persisted JSON member");
      nativeString(name, "persisted JSON member name");
      validateNativeJson(item);
    }, "persisted JSON object");
    return;
  }
  assert.fail(`Reconnect payload has unsupported ${value.name} constructor`);
}

function validateNativeStoredSchema(value) {
  if (value?.kind === "call"
    && value.name === "StoredSchema"
    && value.args.length === 2
    && value.args.every(({ kind }) => kind === "named")) {
    const entries = new Map(value.args.map((argument) => [
      argument.name,
      argument.value,
    ]));
    assert.deepEqual([...entries.keys()].sort(),
      ["persisted", "profile_supported"],
    "Reconnect payload has invalid StoredSchema argument names");
    validateNativeJson(entries.get("persisted"));
    nativeBoolean(entries.get("profile_supported"), "schema profile marker");
    return;
  }
  const [repository] = nativeArguments(value, "StoredSchema", ["repository"]);
  const [root, nodes, comparisonRoot, comparisonNodes, persisted, supported] =
    nativeArguments(repository, "Repository", [
      "root",
      "nodes",
      "comparison_root",
      "comparison_nodes",
      "persisted",
      "profile_supported",
    ]);
  validateNativeFieldSchema(root);
  validateNativeDictionary(nodes, validateNativeNodeSchema, "schema nodes");
  validateNativeComparisonField(comparisonRoot);
  validateNativeDictionary(
    comparisonNodes,
    validateNativeComparisonNode,
    "comparison nodes",
  );
  validateNativeJson(persisted);
  nativeBoolean(supported, "schema profile marker");
}

function validateNativeSchemaState(value) {
  if (value?.kind === "atom") {
    nativeAtom(value, ["EmptySchema"], "schema state");
    return;
  }
  const [schema] = nativeArguments(value, "FixedSchema", ["schema"]);
  validateNativeStoredSchema(schema);
}

function nativeOperation(value) {
  const changeset = nativeCall(parseNativeDiagnostic(value), "Changeset", 1);
  const changes = changeset.args[0]?.kind === "named"
    && changeset.args[0].name === "changes"
    ? changeset.args[0].value
    : changeset.args[0];
  assert(changes?.kind === "list" && changes.items.length === 1,
    "Reconnect payload must contain exactly one change");
  return changes.items[0];
}

function builtValues(value) {
  if (!Array.isArray(value)) return [];
  if (typeof value[1] === "string"
    && value[1].includes("com.fluidframework.leaf.")
    && value[2] === true) {
    return [value[3]];
  }
  if (value.length === 2
    && (typeof value[1] === "string" || Number.isFinite(value[1]))) {
    return [value[1]];
  }
  return value.flatMap(builtValues);
}

export function decodeReconnectPayload(payload) {
  const value = parsedPayload(payload);
  if (typeof value === "string") {
    const operation = nativeOperation(value);
    if (operation?.kind === "call" && operation.name === "SchemaChange") {
      const [oldSchema, newSchema, inverse] = nativeArguments(
        operation,
        "SchemaChange",
        ["before", "after", "is_inverse"],
      );
      validateNativeSchemaState(oldSchema);
      validateNativeSchemaState(newSchema);
      assert.equal(nativeBoolean(inverse, "inverse marker"), false,
      "Reconnect schema payload has an invalid inverse marker");
      return {
        kind: "schema",
        old: persistedSchemaDiagnostic(oldSchema.raw),
        new: persistedSchemaDiagnostic(newSchema.raw),
      };
    }
    if (operation?.kind === "call" && operation.name === "DataChange") {
      const [innerValue] = nativeArguments(operation, "DataChange", ["change"]);
      const inner = nativeCall(innerValue, "Changeset");
      const [data, identityOrder, crossFieldKeys] = nativeArguments(
        inner,
        "Changeset",
        [
          "data",
          "identity_order",
          "cross_field_keys",
        ],
      );
      validateNativeIdentityOrder(identityOrder);
      nativeList(
        crossFieldKeys,
        validateNativeCrossFieldKey,
        "cross-field keys",
      );
      const { fields, values } = validateNativeChangeData(data);
      assert.equal(fields.length, 1,
        "Reconnect data payload lacks one edited field");
      assert.equal(values.length, 1,
        "Reconnect data payload lacks one built value");
      return {
        kind: "data",
        field: fields[0],
        value: values[0],
      };
    }
    assert.fail("Reconnect payload is not a schema or data operation");
  }
  const changes = Array.isArray(value)
    ? value
    : value?.changeset ?? value?.changes;
  assert(Array.isArray(changes) && changes.length === 1,
    "Reconnect payload must contain exactly one change");
  const change = changes[0];
  if (change?.schema !== undefined) {
    return {
      kind: "schema",
      old: canonicalSchema(change.schema.old),
      new: canonicalSchema(change.schema.new),
    };
  }
  if (change?.type === "schema") {
    const schema = change.innerChange?.schema;
    assert(schema, "Reconnect schema payload is missing schema content");
    return {
      kind: "schema",
      old: canonicalSchema(schema.old),
      new: canonicalSchema(schema.new),
    };
  }
  const data = change?.data ?? (change?.type === "data" ? change.innerChange : undefined);
  assert(data, "Reconnect payload is not a schema or data operation");
  if (Array.isArray(data.path) && data.path.length > 0 && "value" in data) {
    return { kind: "data", field: data.path.at(-1), value: data.value };
  }
  const fields = change?.data
    ? data.changes?.flatMap(({ change: entries }) =>
      entries.flatMap(([, node]) =>
        node.fieldChanges?.map(({ fieldKey }) => fieldKey) ?? [])) ?? []
    : data.nodeChanges?._root?.values?.flatMap((node) =>
      node.fieldChanges?.entries?.map(([field]) => field) ?? []) ?? [];
  const values = change?.data
    ? builtValues(data.builds?.trees?.data)
    : data.builds?._root?.values?.flatMap(({ value: built }) =>
      typeof built === "string" || Number.isFinite(built) ? [built] : []) ?? [];
  assert.equal(fields.length, 1, "Reconnect data payload lacks one edited field");
  assert.equal(values.length, 1, "Reconnect data payload lacks one built value");
  return { kind: "data", field: fields[0], value: values[0] };
}

const excludedStores = {
  map: excludedStore(),
};

function parsed(value) {
  return typeof value === "string" ? JSON.parse(value) : value;
}

function summaryEntryEvidence(entry) {
  if (entry?.type === SummaryType.Tree) {
    return {
      type: "tree",
      entries: Object.entries(entry.tree).map(([name, child]) =>
        [name, summaryEntryEvidence(child)]),
    };
  }
  if (entry?.type === SummaryType.Blob) {
    const bytes = typeof entry.content === "string"
      ? Buffer.from(entry.content)
      : Buffer.from(entry.content);
    return { type: "blob", base64: bytes.toString("base64") };
  }
  if (entry?.type === SummaryType.Handle) {
    return { type: "handle", handleType: entry.handleType, path: entry.handle };
  }
  throw new Error("Unsupported pending summary entry");
}

function allocation(contents) {
  const ids = contents?.ids;
  const first = ids?.first ?? ids?.firstGenCount;
  const last = ids?.last
    ?? (Number.isSafeInteger(first) && Number.isSafeInteger(ids?.count)
      ? first + ids.count - 1
      : undefined);
  if (typeof contents?.sessionId !== "string"
    || !Number.isSafeInteger(first) || !Number.isSafeInteger(last)) {
    return undefined;
  }
  return { sessionId: contents.sessionId, first, last };
}

export function decodeTreeSubmissions(messages) {
  return messages.flatMap((message) => {
    if (message.type !== "op") return [];
    const outer = parsed(message.contents);
    const items = outer?.type === "groupedBatch" && Array.isArray(outer.contents)
      ? outer.contents
      : outer?.type === "component"
        ? [{ contents: outer, metadata: message.metadata }]
        : [];
    if (items.length === 0) return [];
    const allocations = items.flatMap((item) => {
      if (item.contents?.type !== "idAllocation") return [];
      const decoded = allocation(item.contents.contents);
      return decoded ? [decoded] : [];
    });
    const batchId = items
      .map(({ metadata }) => metadata?.batchId)
      .find((value) => typeof value === "string" && value.length > 0);
    const commits = items.flatMap((item, innerIndex) => {
      const tree = item.contents?.type === "component"
        ? item.contents.contents?.contents?.content?.contents
        : undefined;
      if (!Number.isSafeInteger(tree?.revision)
        || typeof tree?.originatorId !== "string"
        || !Array.isArray(tree?.changeset)) {
        return [];
      }
      return [{
        innerIndex,
        revision: tree.revision,
        originatorId: tree.originatorId,
        changeset: tree.changeset,
      }];
    });
    if (commits.length === 0) return [];
    return [{
      outerSequenceNumber: message.sequenceNumber,
      clientId: message.clientId,
      clientSequenceNumber: message.clientSequenceNumber,
      referenceSequenceNumber: message.referenceSequenceNumber,
      batchId,
      allocations,
      commits,
    }];
  });
}

function pairCells(family, ordered = false) {
  return orderedPairs.flatMap((authors) => {
    const base = {
      family,
      authors,
      variation: null,
    };
    if (!ordered) {
      return [{
        ...base,
        id: `${family}:${authors.join("->")}`,
        order: null,
      }];
    }
    return authors.map((first) => ({
      ...base,
      id: `${family}:${authors.join("->")}:${first}-first`,
      order: `${first}-first`,
    }));
  });
}

function authorCells(family, authors = implementations) {
  return authors.map((author) => ({
    id: `${family}:${author}`,
    family,
    authors: [author],
    order: null,
    variation: null,
  }));
}

function allAuthorCell(family) {
  return {
    id: `${family}:${implementations.join("+")}`,
    family,
    authors: [...implementations],
    order: null,
    variation: null,
  };
}

function mapCells(cells) {
  return cells.map((cell) => ({ ...cell, profile: "map" }));
}

function arrayCells(cells) {
  return cells.map((cell) => ({ ...cell, profile: "array" }));
}

const scenarioCells = [
  ...pairCells("independent-scalar"),
  ...pairCells("independent-nested"),
  ...pairCells("same-field", true),
  ...pairCells("optional-set-clear", true),
  ...["repeated-clear", "absent-clear", "re-add"].flatMap((variation) =>
    implementations.map((author) => ({
      id: `optional-set-clear:${variation}:${author}`,
      family: "optional-set-clear",
      authors: [author],
      order: null,
      variation,
    }))),
  ...authorCells("null-absence"),
  ...pairCells("parent-replacement-child-edit", true),
  ...authorCells("detached-child-reconciliation"),
  ...authorCells("several-pending-edits"),
  ...authorCells("grouped-commits"),
  ...authorCells("delivery-duplicates-gaps", nativeTargets),
  allAuthorCell("multi-session-ids"),
  ...authorCells("unicode-finite-values"),
  ...mapCells(pairCells("map-independent-keys")),
  ...mapCells(pairCells("map-same-key-set-set", true)),
  ...mapCells(pairCells("map-set-delete", true)),
  ...mapCells(pairCells("map-nested-object-replace", true)),
  ...mapCells(pairCells("map-nested-delete-edit", true)),
  ...mapCells(pairCells("map-recursive-conflict", true)),
  ...mapCells(authorCells("map-reconnect-pending")),
  ...mapCells(authorCells("map-summary-tail")),
  ...arrayCells(pairCells("array-independent-insert")),
  ...arrayCells(pairCells("array-same-gap-insert", true)),
  ...arrayCells(pairCells("array-insert-remove", true)),
  ...arrayCells(pairCells("array-overlapping-remove", true)),
  ...arrayCells(pairCells("array-move-child-edit", true)),
  ...arrayCells(pairCells("array-move-delete", true)),
  ...arrayCells(pairCells("array-competing-moves", true)),
  ...arrayCells(pairCells("array-overlapping-moves", true)),
  ...arrayCells(pairCells("array-cross-parent-move", true)),
  ...arrayCells(pairCells("array-ancestor-replace", true)),
  ...arrayCells(pairCells("array-recursive-map-path", true)),
  ...arrayCells(authorCells("array-reconnect-pending")),
  ...arrayCells(authorCells("array-summary-tail")),
];

const schemaRaceCells = [
  ...orderedPairs.flatMap(([upgrader, competitor]) =>
    ["schema-data", "schema-schema"].flatMap((family) =>
      ["upgrade-first", "competitor-first"].map((order) => ({
        id: `${family}:${upgrader}->${competitor}:${order}`,
        family,
        upgrader,
        competitor,
        order,
      })))),
  ...implementations.map((upgrader) => ({
    id: `upgrade-then-edit:${upgrader}:causal`,
    family: "upgrade-then-edit",
    upgrader,
    competitor: upgrader,
    order: "causal",
  })),
];

const localRefusals = [
  ["clear-required-title", "clear", ["title", "required field"]],
  ["numeric-title", "set", ["title", "leaf.number"]],
  ["null-optional-note", "set", ["note", "leaf.null"]],
  ["unknown-field", "set", ["notAField", "unknown field"]],
  ["wrong-schema-id", "set", ["NotPoint", "unknown node schema"]],
];
const sequenceRefusalCases = new Set([
  "malformed-sequence-payload",
  "malformed-range-count",
  "missing-range-endpoint",
  "bad-child-ownership",
  "invalid-sequence-content",
]);
const identifierOperationRefusalCases = new Set([
  "missing-allocation",
  "wrong-originator",
  "corrupt-numeric-identifier",
]);
const identifierRefusalCases = new Set([
  ...identifierOperationRefusalCases,
  "negative-originatorless-summary",
]);
const injectedRefusals = [
  ["malformed-sequence-payload", "operation-decode", "connection-failed",
    "stopped-after-ready", ["changes[0].change", "expected an array"]],
  ["malformed-range-count", "operation-decode", "connection-failed",
    "stopped-after-ready", ["change[0].count", "positive integer"]],
  ["missing-range-endpoint", "operation-decode", "connection-failed",
    "stopped-after-ready", ["finalEndpoint", "atom"]],
  ["bad-child-ownership", "operation-decode", "connection-failed",
    "stopped-after-ready", ["cross-field ownership", "overlap"]],
  ["invalid-sequence-content", "operation-decode", "connection-failed",
    "stopped-after-ready", [".change[0].changes", "unknown property content"]],
  ["corrupt-retained-summary", "summary-load", "bootstrap-failed",
    "never-ready", ["DetachedFieldIndex", "sequence"]],
  ["unsupported-message-version", "operation-decode", "connection-failed",
    "stopped-after-ready", ["Message", "999"]],
  ["unsupported-summary-version", "summary-load", "bootstrap-failed",
    "never-ready", ["summary metadata", "999", "expected 2"]],
  ["malformed-allocation-range", "operation-decode", "connection-failed",
    "stopped-after-ready", ["groupedBatch[0]", "invalid creation range"]],
  ["missing-summary-blob", "summary-load", "bootstrap-failed", "never-ready",
    ["Forest/contents", "missing"]],
  ["unknown-runtime-message", "runtime-message", "connection-failed",
    "stopped-after-ready",
    ["message.changeset[0]", "exactly one data or schema member"]],
  ["missing-allocation", "operation-decode", "connection-failed",
    "stopped-after-ready", ["ID compressor", "UnknownSession"]],
  ["wrong-originator", "operation-decode", "connection-failed",
    "stopped-after-ready", ["message.revision", "UnknownSession"]],
  ["corrupt-numeric-identifier", "operation-decode", "connection-failed",
    "stopped-after-ready", ["builds.trees", "identifier value is invalid"]],
  ["negative-originatorless-summary", "summary-load", "bootstrap-failed",
    "never-ready", ["summary identifier", "finalized"]],
];
const failureCells = [
  ...localRefusals.flatMap(([caseId, errorOperation, diagnosticTerms]) =>
    nativeTargets.map((target) => ({
      id: `${caseId}:${target}`,
      caseId,
      target,
      kind: "local-refusal",
      expectedStage: "local-edit",
      errorCode: "facade-error",
      errorOperation,
      diagnosticTerms,
      clientState: "ready-local",
    }))),
  ...nativeTargets.map((target) => ({
      id: `unsupported-map-schema:${target}`,
      caseId: "unsupported-map-schema",
      target,
      kind: "stored-schema-refusal",
      expectedStage: "resolve-view",
      errorCode: "view-resolution-failed",
      errorOperation: "resolve-view",
      diagnosticTerms: ["root", "incompatible field schema"],
      clientState: "never-ready",
    })),
  ...injectedRefusals.flatMap(([
    caseId,
    expectedStage,
    errorCode,
    clientState,
    diagnosticTerms,
  ]) =>
    nativeTargets.map((target) => ({
      id: `${caseId}:${target}`,
      caseId,
      target,
      kind: "injected-input-refusal",
      expectedStage,
      errorCode,
      errorOperation: clientState === "never-ready" ? "connect" : "await-synced",
      diagnosticTerms,
      clientState,
    }))),
];

export function requiredScenarioCells() {
  return structuredClone(scenarioCells);
}

export function requiredSchemaRaceCells() {
  return structuredClone(schemaRaceCells);
}

export function requiredFailureCells() {
  return structuredClone(failureCells);
}

function mix32(value) {
  let mixed = value >>> 0;
  mixed = Math.imul(mixed ^ (mixed >>> 16), 0x21f0aaad) >>> 0;
  mixed = Math.imul(mixed ^ (mixed >>> 15), 0x735a2d97) >>> 0;
  return (mixed ^ (mixed >>> 15)) >>> 0;
}

function scheduleSubSeed(seed, index) {
  return mix32((seed + Math.imul(index + 1, 0x9e3779b9)) >>> 0);
}

function connected(author) {
  return { connected: [author] };
}

function control(type, author, held) {
  return {
    type,
    author,
    preconditions: {
      ...connected(author),
      [`${type.slice("hold-".length)}Held`]: held,
    },
  };
}

function edit(type, author, path, value, outboundHeld = false) {
  const pathTypes = {
    title: "string",
    note: "optional-string",
    enabled: "boolean",
    rating: "number",
    point: path.length === 1 ? "point" : "number",
  };
  return {
    type,
    author,
    path,
    ...(type === "set" ? { value } : {}),
    preconditions: {
      ...connected(author),
      pathType: pathTypes[path[0]] ?? (path.at(-1) === "x" ? "number" : undefined),
      ...(outboundHeld ? { outboundHeld: true } : {}),
    },
  };
}

function mapEdit(type, author, key, value, outboundHeld = false) {
  return {
    type,
    author,
    path: ["items"],
    key,
    ...(type === "map-set" ? { value } : {}),
    preconditions: {
      ...connected(author),
      pathType: "dynamic-map",
      ...(outboundHeld ? { outboundHeld: true } : {}),
    },
  };
}

function arrayEdit(type, author, fields, outboundHeld = false) {
  return {
    type,
    author,
    ...fields,
    preconditions: {
      ...connected(author),
      pathType: "array",
      ...(outboundHeld ? { outboundHeld: true } : {}),
    },
  };
}

function transactionAction(author, scope, outboundHeld = true) {
  return {
    type: "transaction",
    author,
    constraints: scope.constraints,
    edits: scope.edits,
    result: scope.result,
    preconditions: {
      ...connected(author),
      pathType: "array",
      ...(outboundHeld ? { outboundHeld: true } : {}),
    },
  };
}

function release(author, direction, order, duplicate) {
  return {
    type: "release",
    author,
    direction,
    order,
    duplicate,
    preconditions: {
      ...connected(author),
      [`${direction}Held`]: true,
    },
  };
}

function generatedActions(seed, index, template, roles, random) {
  const actions = [{
    type: "checkpoint",
    label: "initial",
    stage: "quiescent",
    preconditions: { connected: [...implementations] },
  }];
  if (template === "optional-conflict") {
    actions.unshift(edit("set", roles.third, ["note"], `initial-${seed}-${index}`));
  }
  for (const author of [roles.first, roles.second, roles.third]) {
    actions.push(control("hold-inbound", author, false));
    actions.push(control("hold-outbound", author, false));
  }
  const magnitude = 100 + seed + index;
  if (template === "nested-conflict") {
    actions.push(edit("set", roles.first, ["point", "x"], magnitude, true));
    actions.push(edit("set", roles.second, ["point", "y"], -magnitude - 1, true));
  } else if (template === "optional-conflict") {
    actions.push(edit("set", roles.first, ["note"],
      `seed-${seed}-${index}-${roles.first}`, true));
    actions.push(edit("set", roles.second, ["note"],
      `clear-${seed}-${index}-${roles.second}`, true));
    actions.push(edit("clear", roles.second, ["note"], undefined, true));
  } else if (template === "parent-child-conflict") {
    actions.push(edit("set", roles.first, ["point"], {
      x: magnitude,
      y: magnitude + 1,
    }, true));
    actions.push(edit("set", roles.second, ["point", random() % 2 === 0 ? "x" : "y"],
      -magnitude, true));
  } else {
    actions.push(edit("set", roles.first, ["title"],
      `pending-${seed}-${index}-a`, true));
    actions.push(edit("set", roles.first, ["rating"], magnitude, true));
    actions.push(edit("set", roles.second, ["title"],
      `pending-${seed}-${index}-b`, true));
  }
  actions.push(edit("set", roles.third, ["title"],
    `seed-${seed}-${index}-${roles.third}`));
  actions.push({
    type: "checkpoint",
    label: "optimistic",
    stage: "intermediate",
    preconditions: { connected: [...implementations] },
  });
  const inboundOrder = random() % 2 === 0 ? "fifo" : "reverse";
  const conflictOrder = random() % 2 === 0
    ? [roles.first, roles.second]
    : [roles.second, roles.first];
  const releaseOrder = [...conflictOrder, roles.third];
  for (const author of releaseOrder) {
    actions.push(release(author, "outbound", "fifo", false));
  }
  for (const author of releaseOrder) {
    actions.push(release(author, "inbound", author === "upstream" ? "fifo" : inboundOrder, false));
  }
  if ((index + seed) % 5 === 4) {
    actions.push({
      type: "checkpoint",
      label: "before-reconnect",
      stage: "quiescent",
      preconditions: { connected: [...implementations] },
    });
    actions.push({
      type: "disconnect",
      author: roles.reload,
      preconditions: connected(roles.reload),
    });
    actions.push({
      type: "reconnect",
      author: roles.reload,
      preconditions: { disconnected: [roles.reload] },
    });
  }
  if ((index + seed) % 7 === 6) {
    actions.push({
      type: "checkpoint",
      label: "before-publish",
      stage: "quiescent",
      preconditions: { connected: [...implementations] },
    });
    actions.push({
      type: "summarize",
      author: roles.first,
      preconditions: { connected: [...implementations], quiescent: true },
    });
    actions.push({
      type: "reload",
      author: roles.reload,
      preconditions: {
        connected: [...implementations],
        summaryAvailable: true,
      },
    });
  }
  actions.push({
    type: "checkpoint",
    label: "settled",
    stage: "quiescent",
    preconditions: { connected: [...implementations] },
  });
  return actions;
}

function generatedMapActions(seed, index, template, roles, random) {
  const actions = [
    mapEdit(
      "map-set",
      roles.third,
      "delete-me",
      { kind: "string", value: `seed-${seed}-${index}` },
    ),
    {
      type: "checkpoint",
      label: "initial",
      stage: "quiescent",
      preconditions: { connected: [...implementations] },
    },
  ];
  for (const author of [roles.first, roles.second, roles.third]) {
    actions.push(control("hold-inbound", author, false));
    actions.push(control("hold-outbound", author, false));
  }

  const magnitude = 100 + seed + index;
  if (template === "map-object-conflict") {
    actions.push(mapEdit(
      "map-set",
      roles.first,
      "point",
      taggedPoint(magnitude, magnitude + 1),
      true,
    ));
    actions.push(mapEdit(
      "map-set",
      roles.second,
      "point",
      taggedPoint(-magnitude, -magnitude - 1),
      true,
    ));
  } else if (template === "map-nested-conflict") {
    actions.push(mapEdit(
      "map-set",
      roles.first,
      "nested",
      taggedMap([["shared", { kind: "string", value: roles.first }]]),
      true,
    ));
    actions.push(mapEdit(
      "map-set",
      roles.second,
      "nested",
      taggedMap([["shared", { kind: "string", value: roles.second }]]),
      true,
    ));
  } else if (template === "map-recursive-delete") {
    actions.push(mapEdit(
      "map-set",
      roles.first,
      "nested",
      taggedMap([["recursive", taggedMap([
        ["leaf", { kind: "number", value: magnitude }],
      ])]]),
      true,
    ));
    actions.push(mapEdit(
      "map-delete",
      roles.second,
      "delete-me",
      undefined,
      true,
    ));
  } else {
    actions.push(mapEdit(
      "map-set",
      roles.first,
      "__proto__",
      { kind: "string", value: roles.first },
      true,
    ));
    actions.push(mapEdit(
      "map-delete",
      roles.second,
      "delete-me",
      undefined,
      true,
    ));
  }
  actions.push(mapEdit(
    "map-set",
    roles.third,
    "水",
    { kind: "number", value: magnitude },
    true,
  ));
  actions.push({
    type: "checkpoint",
    label: "optimistic",
    stage: "intermediate",
    preconditions: { connected: [...implementations] },
  });
  const inboundOrder = random() % 2 === 0 ? "fifo" : "reverse";
  const conflictOrder = random() % 2 === 0
    ? [roles.first, roles.second]
    : [roles.second, roles.first];
  const releaseOrder = [...conflictOrder, roles.third];
  for (const author of releaseOrder) {
    actions.push(release(author, "outbound", "fifo", false));
  }
  for (const author of releaseOrder) {
    actions.push(release(
      author,
      "inbound",
      author === "upstream" ? "fifo" : inboundOrder,
      false,
    ));
  }
  if ((index + seed) % 5 === 4) {
    actions.push({
      type: "checkpoint",
      label: "before-reconnect",
      stage: "quiescent",
      preconditions: { connected: [...implementations] },
    });
    actions.push({
      type: "disconnect",
      author: roles.reload,
      preconditions: connected(roles.reload),
    });
    actions.push({
      type: "reconnect",
      author: roles.reload,
      preconditions: { disconnected: [roles.reload] },
    });
  }
  if ((index + seed) % 7 === 6) {
    actions.push({
      type: "checkpoint",
      label: "before-publish",
      stage: "quiescent",
      preconditions: { connected: [...implementations] },
    });
    actions.push({
      type: "summarize",
      author: roles.first,
      preconditions: { connected: [...implementations], quiescent: true },
    });
    actions.push({
      type: "reload",
      author: roles.reload,
      preconditions: {
        connected: [...implementations],
        summaryAvailable: true,
      },
    });
  }
  actions.push({
    type: "checkpoint",
    label: "settled",
    stage: "quiescent",
    preconditions: { connected: [...implementations] },
  });
  return actions;
}

function generatedSchemaActions(seed, index, template, roles, random) {
  const actions = [{
    type: "checkpoint",
    label: "initial",
    stage: "quiescent",
    preconditions: { connected: [...implementations] },
  }];
  for (const author of implementations) {
    actions.push(control("hold-inbound", author, false));
    actions.push(control("hold-outbound", author, false));
  }
  actions.push({
    type: "schema-compatibility",
    author: roles.first,
    view: "optional",
    preconditions: connected(roles.first),
  });
  actions.push({
    type: "schema-upgrade",
    author: roles.first,
    fromView: "v1",
    view: "optional",
    preconditions: connected(roles.first, "outbound", true),
  });
  actions.push({
    type: "open-view",
    author: roles.first,
    view: "optional",
    preconditions: connected(roles.first),
  });
  actions.push({
    type: "set",
    author: roles.second,
    path: ["title"],
    value: `schema-${seed}-${index}`,
    preconditions: {
      connected: [roles.second],
      pathType: "string",
      outboundHeld: true,
    },
  });
  actions.push({
    type: "set",
    author: roles.third,
    path: ["point", random() % 2 === 0 ? "x" : "y"],
    value: 200 + index,
    preconditions: {
      connected: [roles.third],
      pathType: "number",
      outboundHeld: true,
    },
  });
  actions.push({
    type: "checkpoint",
    label: "optimistic",
    stage: "intermediate",
    preconditions: { connected: [...implementations] },
  });
  for (const author of [roles.first, roles.second, roles.third]) {
    actions.push(release(author, "outbound", "fifo", false));
  }
  const inboundOrder = random() % 2 === 0 ? "fifo" : "reverse";
  for (const author of [roles.first, roles.second, roles.third]) {
    actions.push(release(
      author,
      "inbound",
      author === "upstream" ? "fifo" : inboundOrder,
      false,
    ));
  }
  for (const author of implementations) {
    actions.push({
      type: "open-view",
      author,
      view: "optional",
      preconditions: connected(author),
    });
  }
  actions.push({
    type: "checkpoint",
    label: "after-acknowledgement",
    stage: "quiescent",
    preconditions: { connected: [...implementations] },
  });
  actions.push({
    type: "set",
    author: roles.first,
    path: ["score"],
    value: index,
    preconditions: { connected: [roles.first], pathType: "number" },
  });
  if (template === "schema-reconnect-summary") {
    actions.push({
      type: "checkpoint",
      label: "before-reconnect",
      stage: "quiescent",
      preconditions: { connected: [...implementations] },
    });
    actions.push({
      type: "disconnect",
      author: roles.reload,
      preconditions: connected(roles.reload),
    });
    actions.push({
      type: "reconnect",
      author: roles.reload,
      preconditions: { disconnected: [roles.reload] },
    });
  }
  actions.push({
    type: "checkpoint",
    label: "before-publish",
    stage: "quiescent",
    preconditions: { connected: [...implementations] },
  });
  actions.push({
    type: "summarize",
    author: roles.first,
    preconditions: { connected: [...implementations], quiescent: true },
  });
  actions.push({
    type: "reload",
    author: roles.reload,
    view: "optional",
    preconditions: {
      connected: [...implementations],
      summaryAvailable: true,
    },
  });
  actions.push({
    type: "checkpoint",
    label: "settled",
    stage: "quiescent",
    preconditions: { connected: [...implementations] },
  });
  return actions;
}

function arrayPoint(label, x) {
  return {
    kind: "object",
    schemaId: "org.watershed.shared-tree.m3.Point",
    fields: [
      ["label", { kind: "string", value: label }],
      ["x", { kind: "number", value: x }],
    ],
  };
}

function generatedArrayActions(seed, index, template, roles, random) {
  const magnitude = 100 + seed + index;
  const actions = [
    arrayEdit("array-insert", roles.third, {
      path: ["left"],
      index: 0,
      values: [
        arrayPoint(`base-${seed}-${index}-a`, magnitude),
        arrayPoint(`base-${seed}-${index}-b`, magnitude + 1),
        {
          kind: "array",
          schemaId: "org.watershed.shared-tree.m3.Items",
          elements: [arrayPoint(`nested-${seed}-${index}`, magnitude + 2)],
        },
        arrayPoint(`base-${seed}-${index}-c`, magnitude + 3),
      ],
    }),
    arrayEdit("array-insert", roles.third, {
      path: ["right"],
      index: 0,
      values: [
        arrayPoint(`right-${seed}-${index}-a`, magnitude + 4),
        arrayPoint(`right-${seed}-${index}-b`, magnitude + 5),
        arrayPoint(`right-${seed}-${index}-c`, magnitude + 6),
      ],
    }),
    {
      type: "checkpoint",
      label: "initial",
      stage: "quiescent",
      preconditions: { connected: [...implementations] },
    },
  ];
  for (const author of [roles.first, roles.second, roles.third]) {
    actions.push(control("hold-inbound", author, false));
    actions.push(control("hold-outbound", author, false));
  }

  actions.push(arrayEdit("array-insert", roles.first, {
    path: ["left"],
    index: 1,
    values: [
      { kind: "string", value: `${template}-${roles.first}` },
      { kind: "number", value: magnitude + 7 },
    ],
  }, true));
  actions.push(transactionAction(roles.first, {
    constraints: [{ type: "nodeInDocument", path: ["left", "0"] }],
    edits: [
      {
        op: "array-insert",
        path: ["right"],
        index: 0,
        values: [arrayPoint(`tx-${seed}-${index}`, magnitude + 9)],
      },
      {
        op: "transaction",
        constraints: [],
        result: "commit",
        edits: [{
          op: "array-move",
          sourcePath: ["right"],
          sourceStart: 0,
          sourceEnd: 1,
          destinationPath: ["right"],
          destinationGap: 2,
        }],
      },
    ],
    result: "commit",
  }));
  actions.push(transactionAction(roles.first, {
    constraints: [],
    edits: [{
      op: "array-insert",
      path: ["right"],
      index: 0,
      values: [arrayPoint(`tx-abort-${seed}-${index}`, magnitude + 10)],
    }],
    result: "abort",
  }));
  switch (template) {
    case "array-same-gap":
      actions.push(arrayEdit("array-insert", roles.second, {
        path: ["left"],
        index: 1,
        values: [
          { kind: "string", value: `${template}-${roles.second}` },
          { kind: "number", value: magnitude + 8 },
        ],
      }, true));
      break;
    case "array-insert-remove":
      actions.push(arrayEdit("array-remove", roles.second, {
        path: ["left"], start: 0, end: 2,
      }, true));
      break;
    case "array-cross-parent":
      actions.push(arrayEdit("array-move", roles.second, {
        sourcePath: ["left"],
        sourceStart: 0,
        sourceEnd: 2,
        destinationPath: ["right"],
        destinationGap: 1,
      }, true));
      break;
    case "array-nested-reconnect":
      actions.push(arrayEdit("array-move", roles.second, {
        sourcePath: ["left"],
        sourceStart: 0,
        sourceEnd: 2,
        destinationPath: ["left"],
        destinationGap: 3,
      }, true));
      break;
    default:
      assert.fail(`Unknown array seeded template: ${template}`);
  }
  actions.push(edit("set", roles.third, ["left", "2", "0", "x"], -magnitude, true));
  actions.push({
    type: "checkpoint",
    label: "optimistic",
    stage: "intermediate",
    preconditions: { connected: [...implementations] },
  });
  const inboundOrder = random() % 2 === 0 ? "fifo" : "reverse";
  const conflictOrder = random() % 2 === 0
    ? [roles.first, roles.second]
    : [roles.second, roles.first];
  const releaseOrder = [...conflictOrder, roles.third];
  for (const author of releaseOrder) {
    actions.push(release(author, "outbound", "fifo", false));
  }
  for (const author of releaseOrder) {
    actions.push(release(
      author,
      "inbound",
      author === "upstream" ? "fifo" : inboundOrder,
      false,
    ));
  }
  if (template === "array-nested-reconnect" || (index + seed) % 5 === 4) {
    actions.push({
      type: "checkpoint",
      label: "before-reconnect",
      stage: "quiescent",
      preconditions: { connected: [...implementations] },
    });
    actions.push({
      type: "disconnect",
      author: roles.reload,
      preconditions: connected(roles.reload),
    });
    actions.push({
      type: "reconnect",
      author: roles.reload,
      preconditions: { disconnected: [roles.reload] },
    });
  }
  if ((index + seed) % 7 === 6) {
    actions.push({
      type: "checkpoint",
      label: "before-publish",
      stage: "quiescent",
      preconditions: { connected: [...implementations] },
    });
    actions.push({
      type: "summarize",
      author: roles.first,
      preconditions: { connected: [...implementations], quiescent: true },
    });
    actions.push({
      type: "reload",
      author: roles.reload,
      preconditions: {
        connected: [...implementations],
        summaryAvailable: true,
      },
    });
  }
  actions.push({
    type: "checkpoint",
    label: "settled",
    stage: "quiescent",
    preconditions: { connected: [...implementations] },
  });
  return actions;
}

function generatedIdentifierActions(seed, index, template, roles, random) {
  assert.equal(template, "identifier-default-explicit");
  const actions = [{
    type: "checkpoint",
    label: "initial",
    stage: "quiescent",
    preconditions: { connected: [...implementations] },
  }];
  for (const author of [roles.first, roles.second, roles.third]) {
    actions.push(control("hold-inbound", author, false));
    actions.push(control("hold-outbound", author, false));
  }
  for (const author of [roles.first, roles.second, roles.third]) {
    actions.push(arrayEdit("array-insert", author, {
      path: ["left"],
      index: 0,
      values: [
        identifierPoint(`seed-${seed}-${index}-${author}-default`),
        identifierPoint(
          `seed-${seed}-${index}-${author}-explicit`,
          "shared-custom-id",
        ),
      ],
    }, true));
  }
  actions.push(arrayEdit("array-move", roles.first, {
    sourcePath: ["left"],
    sourceStart: 0,
    sourceEnd: 1,
    destinationPath: ["right"],
    destinationGap: 0,
  }, true));
  actions.push({
    type: "checkpoint",
    label: "optimistic",
    stage: "intermediate",
    preconditions: { connected: [...implementations] },
  });
  const inboundOrder = random() % 2 === 0 ? "fifo" : "reverse";
  for (const author of [roles.first, roles.second, roles.third]) {
    actions.push(release(author, "outbound", "fifo", false));
  }
  for (const author of [roles.first, roles.second, roles.third]) {
    actions.push(release(
      author,
      "inbound",
      author === "upstream" ? "fifo" : inboundOrder,
      false,
    ));
  }
  if ((index + seed) % 7 === 6) {
    actions.push({
      type: "checkpoint",
      label: "before-publish",
      stage: "quiescent",
      preconditions: { connected: [...implementations] },
    });
    actions.push({
      type: "summarize",
      author: roles.first,
      preconditions: { connected: [...implementations], quiescent: true },
    });
    actions.push({
      type: "reload",
      author: roles.reload,
      preconditions: {
        connected: [...implementations],
        summaryAvailable: true,
      },
    });
  }
  actions.push({
    type: "checkpoint",
    label: "settled",
    stage: "quiescent",
    preconditions: { connected: [...implementations] },
  });
  return actions;
}

function generateSchedule({ seed, index, profile }) {
  const subSeed = scheduleSubSeed(seed, index);
  let state = subSeed;
  const random = () => {
    state ^= state << 13;
    state ^= state >>> 17;
    state ^= state << 5;
    return state >>>= 0;
  };
  const templates = profile === "map"
    ? mapSeededTemplates
    : profile === "array"
      ? arraySeededTemplates
      : profile === "identifier"
        ? identifierSeededTemplates
      : profile === "schema"
        ? schemaSeededTemplates
        : seededTemplates;
  const template = templates[random() % templates.length];
  const rotation = (seed + index + 1) % implementations.length;
  const authors = [
    ...implementations.slice(rotation),
    ...implementations.slice(0, rotation),
  ];
  const roles = {
    first: authors[0],
    second: authors[1],
    third: authors[2],
    reload: authors[0],
  };
  const actions = profile === "map"
    ? generatedMapActions(seed, index, template, roles, random)
    : profile === "array"
      ? generatedArrayActions(seed, index, template, roles, random)
      : profile === "identifier"
        ? generatedIdentifierActions(seed, index, template, roles, random)
      : profile === "schema"
        ? generatedSchemaActions(seed, index, template, roles, random)
        : generatedActions(seed, index, template, roles, random);
  const author = roles.first;
  const peer = roles.second;
  const editName = `edit-${index}`;
  const undoName = `undo-${index}`;
  const authorEdit = profile === "map"
    ? {
        type: "map-set",
        author,
        path: ["items"],
        key: `undo-edit-${index}`,
        value: treeValue(`edit-${index}`),
        preconditions: { connected: [...implementations] },
      }
    : profile === "array"
      ? {
          type: "array-insert",
          author,
          path: ["left"],
          index: 0,
          values: [treeValue(`edit-${index}`)],
          preconditions: { connected: [...implementations] },
        }
      : profile === "identifier"
        ? {
            type: "array-insert",
            author,
            path: ["left"],
            index: 0,
            values: [identifierPoint(`undo-edit-${index}`)],
            preconditions: { connected: [...implementations] },
          }
        : {
            type: "set",
            author,
            path: ["title"],
            value: `undo-edit-${index}`,
            preconditions: { connected: [...implementations] },
          };
  const start = [authorEdit, {
      type: "retain",
      author,
      name: editName,
      lifecycle: "edit",
      preconditions: { connected: [...implementations] },
    }];
  const peerEdit = profile === "map"
    ? {
        type: "map-set",
        author: peer,
        path: ["items"],
        key: `undo-peer-${index}`,
        value: treeValue(`peer-${index}`),
        preconditions: { connected: [...implementations] },
      }
    : profile === "array"
      ? {
          type: "array-insert",
          author: peer,
          path: ["right"],
          index: 0,
          values: [treeValue(`peer-${index}`)],
          preconditions: { connected: [...implementations] },
        }
      : profile === "identifier"
        ? {
            type: "array-insert",
            author: peer,
            path: ["right"],
            index: 0,
            values: [identifierPoint(`undo-peer-${index}`)],
            preconditions: { connected: [...implementations] },
          }
        : {
            type: "set",
            author: peer,
            path: ["title"],
            value: `undo-peer-${index}`,
            preconditions: { connected: [...implementations] },
          };
  const finish = [
    peerEdit,
    ...(profile === "array" ? [{
      type: "checkpoint",
      label: `undo-peer-settled-${index}`,
      stage: "quiescent",
      preconditions: { connected: [...implementations] },
    }, transactionAction(peer, {
        constraints: [],
        edits: [{
          op: "array-insert",
          path: ["right"],
          index: 0,
          values: [treeValue(`undo-transaction-${index}`)],
        }],
        result: "commit",
      }, false)] : []),
    {
      type: "revert",
      author,
      name: editName,
      dispose: false,
      lifecycle: "undo",
      preconditions: { connected: [...implementations] },
    },
    {
      type: "checkpoint",
      label: `undo-settled-${index}`,
      stage: "quiescent",
      preconditions: { connected: [...implementations] },
    },
    {
      type: "retain",
      author,
      name: undoName,
      lifecycle: "undo",
      preconditions: { connected: [...implementations] },
    },
    {
      type: "revert",
      author,
      name: undoName,
      dispose: true,
      lifecycle: "redo",
      preconditions: { connected: [...implementations] },
    },
    {
      type: "checkpoint",
      label: `redo-settled-${index}`,
      stage: "quiescent",
      preconditions: { connected: [...implementations] },
    },
    {
      type: "dispose",
      author,
      name: editName,
      lifecycle: "edit",
      preconditions: { connected: [...implementations] },
    },
  ];
  const reconnect = actions.findIndex(({ type }) => type === "disconnect");
  const summary = actions.findIndex(({ type }) => type === "summarize");
  if (index % 3 === 0 && reconnect >= 0) {
    actions.splice(reconnect, 0, ...start);
    const afterReconnect = actions.findIndex(
      ({ type }, actionIndex) => actionIndex > reconnect && type === "reconnect",
    );
    actions.splice(afterReconnect + 1, 0, ...finish);
  } else if (index % 3 === 1 && summary >= 0) {
    actions.splice(summary, 0, ...start, {
      type: "checkpoint",
      label: `undo-before-summary-${index}`,
      stage: "quiescent",
      preconditions: { connected: [...implementations] },
    });
    const afterReload = actions.findIndex(
      ({ type }, actionIndex) => actionIndex > summary && type === "reload",
    );
    actions.splice(afterReload + 1, 0, ...finish);
  } else {
    const release = actions.findIndex(
      ({ type, direction, author: actionAuthor }) =>
        type === "release" && direction === "outbound" && actionAuthor === author,
    );
    assert(release >= 0, "Generated undo/redo lifecycle lacks an outbound release");
    actions.splice(release, 0, authorEdit, {
      type: "checkpoint",
      label: `undo-held-${index}`,
      stage: "intermediate",
      preconditions: { connected: [...implementations] },
    }, start[1]);
    const settled = actions.findLastIndex(
      ({ type, stage }) => type === "checkpoint" && stage === "quiescent",
    );
    actions.splice(settled, 0, ...finish);
  }
  return {
    formatVersion: 1,
    profile,
    index,
    seed,
    subSeed,
    template,
    authors: [...implementations],
    roles,
    actions,
  };
}

export function generateSchedules({ seed, iterations }) {
  assert(Number.isSafeInteger(seed) && seed >= 0 && seed <= 0xffff_ffff,
    "Schedule seed must be an unsigned 32-bit integer");
  assert(Number.isSafeInteger(iterations) && iterations >= 0,
    "Schedule iterations must be a nonnegative integer");
  return Array.from({ length: iterations }, (_, index) => {
    const profile = ["object", "map", "schema", "array", "identifier"][index % 5];
    return generateSchedule({ seed, index, profile });
  });
}

function validateSchedule(schedule) {
  assert(schedule && typeof schedule === "object" && !Array.isArray(schedule),
    "Seeded schedule must be an object");
  assert.equal(schedule.formatVersion, 1, "Unsupported seeded schedule format");
  assert(Number.isSafeInteger(schedule.index) && schedule.index >= 0,
    "Seeded schedule has an invalid index");
  assert(Number.isSafeInteger(schedule.seed)
    && schedule.seed >= 0 && schedule.seed <= 0xffff_ffff,
  "Seeded schedule has an invalid seed");
  assert(["object", "map", "schema", "array", "identifier"].includes(schedule.profile),
    "Seeded schedule has an invalid profile");
  const expected = generateSchedule({
    seed: schedule.seed,
    index: schedule.index,
    profile: schedule.profile,
  });
  assert.deepEqual(schedule, expected, "Seeded schedule expansion or path is invalid");
  return schedule;
}

export function validateReplayArtifact(artifact, expected) {
  assert(artifact && typeof artifact === "object" && !Array.isArray(artifact),
    "Replay artifact must be an object");
  assert.equal(artifact.formatVersion, 1, "Unsupported replay artifact format");
  assert.equal(artifact.kind, "seeded-failure", "Replay artifact has another kind");
  assert(typeof artifact.runId === "string" && artifact.runId.length > 0,
    "Replay artifact lacks the original run ID");
  assert.equal(artifact.profileDigest, expected?.profileDigest,
    "Replay artifact uses another profile");
  assert.deepEqual(artifact.reference, replayReference,
    "Replay artifact uses another upstream reference");
  assert.deepEqual(artifact.service, replayService,
    "Replay artifact uses another service revision");
  validateSchedule(artifact.schedule);
  assert.equal(artifact.seed, artifact.schedule.seed, "Replay seed changed");
  assert.equal(artifact.index, artifact.schedule.index, "Replay index changed");
  assert.equal(artifact.subSeed, artifact.schedule.subSeed, "Replay sub-seed changed");
  assert.equal(artifact.profile, artifact.schedule.profile, "Replay profile changed");
  assert(artifact.originalDocumentId === null
    || (typeof artifact.originalDocumentId === "string"
      && artifact.originalDocumentId.length > 0),
  "Replay artifact has an invalid original document ID");
  assert.deepEqual(Object.keys(artifact.identityMapping).sort(),
    [...implementations].sort(), "Replay artifact lacks an original identity");
  for (const implementation of implementations) {
    const identity = artifact.identityMapping[implementation];
    assert(identity.instanceId === null
      || (typeof identity.instanceId === "string" && identity.instanceId.length > 0),
    "Replay identity has an invalid instance ID");
    assert(Array.isArray(identity.clientIds), "Replay identity lacks client IDs");
    assert(Array.isArray(identity.originatorIds), "Replay identity lacks originator IDs");
  }
  assert(Array.isArray(artifact.checkpoints) && artifact.checkpoints.length > 0,
    "Replay artifact lacks checkpoints");
  const actionFailure = artifact.failedCheckpoint === null
    && artifact.failedAction
    && typeof artifact.failedAction === "object"
    && !Array.isArray(artifact.failedAction)
    && Number.isSafeInteger(artifact.failedAction.index)
    && typeof artifact.failedAction.type === "string"
    && artifact.failedAction.type !== "checkpoint";
  if (artifact.profile === "array") {
    if (actionFailure) {
      assert.equal(artifact.firstDifferencePath, null,
        "Array action failure has a difference path");
    } else {
      assert(artifact.checkpoints.some(({ stage }) => stage === "intermediate"),
        "Array replay artifact lacks an intermediate checkpoint");
      assert(typeof artifact.firstDifferencePath === "string"
        && artifact.firstDifferencePath.length > 0,
      "Array replay artifact lacks the first difference path");
    }
  }
  assert(Array.isArray(artifact.rawSequencedOperations),
  "Replay artifact lacks sequenced operations");
  assert(Array.isArray(artifact.summaries), "Replay artifact lacks summaries");
  assert(artifact.firstDifferencePath === null
    || (typeof artifact.firstDifferencePath === "string"
      && artifact.firstDifferencePath.length > 0),
  "Replay artifact has an invalid first difference path");
  assert(typeof artifact.error?.name === "string"
    && typeof artifact.error?.message === "string",
  "Replay artifact lacks the original error");
  if (artifact.error.cause !== undefined) {
    assert(artifact.error.cause
      && typeof artifact.error.cause === "object"
      && !Array.isArray(artifact.error.cause)
      && typeof artifact.error.cause.code === "string"
      && typeof artifact.error.cause.operation === "string"
      && typeof artifact.error.cause.message === "string",
    "Replay artifact has an invalid structured error cause");
  }
  return artifact;
}

export async function until(predicate, stage, milliseconds = 30_000) {
  const deadline = Date.now() + milliseconds;
  while (!await predicate()) {
    assert(Date.now() < deadline, `Timed out: ${stage}`);
    await delay(25);
  }
}

export async function waitForGapRepair(adapter, requestCount, milliseconds = 5_000) {
  let evidence;
  await until(() => {
    evidence = adapter.evidence();
    return evidence.repairRequests.length > requestCount;
  }, "gap-repair request evidence", milliseconds);
  return evidence;
}

export function success(reply, stage) {
  assert.equal(reply.ok, true, `${stage}: ${JSON.stringify(reply.error ?? reply)}`);
  return reply;
}

export function rootValue(root) {
  return {
    present: true,
    value: {
      kind: "object",
      schemaId: "org.watershed.shared-tree.m1.Root",
      fields: [
        ["enabled", { kind: "boolean", value: root.enabled }],
        ["marker", { kind: "null" }],
        ...(root.note === undefined ? [] : [
          ["note", { kind: "string", value: root.note }],
        ]),
        ["point", {
          kind: "object",
          schemaId: "org.watershed.shared-tree.m1.Point",
          fields: [
            ["x", { kind: "number", value: root.point.x }],
            ["y", { kind: "number", value: root.point.y }],
          ],
        }],
        ["rating", { kind: "number", value: root.rating }],
        ["title", { kind: "string", value: root.title }],
      ],
    },
  };
}

function mapRootValue(root) {
  return {
    present: true,
    value: {
      kind: "object",
      schemaId: "org.watershed.shared-tree.m2.Root",
      fields: [["items", mapTreeValue(root.items)]],
    },
  };
}

function schemaRootValue(root) {
  const fields = [
    ["items", {
      kind: "map",
      schemaId: "org.watershed.shared-tree.m4.Items",
      entries: [...root.items.entries()].map(([key, value]) => [
        key,
        typeof value === "string"
          ? { kind: "string", value }
          : {
            kind: "object",
            schemaId: "org.watershed.shared-tree.m4.Point",
            fields: [
              ["x", { kind: "number", value: value.x }],
              ["y", { kind: "number", value: value.y }],
            ],
          },
      ]),
    }],
    ["note", root.note === undefined
      ? undefined
      : { kind: typeof root.note === "number" ? "number" : "string", value: root.note }],
    ["point", {
      kind: "object",
      schemaId: "org.watershed.shared-tree.m4.Point",
      fields: [
        ["x", { kind: "number", value: root.point.x }],
        ["y", { kind: "number", value: root.point.y }],
      ],
    }],
    ["score", root.score === undefined
      ? undefined
      : { kind: "number", value: root.score }],
    ["title", root.title === undefined
      ? undefined
      : { kind: "string", value: root.title }],
  ].filter(([, value]) => value !== undefined);
  return {
    present: true,
    value: {
      kind: "object",
      schemaId: "org.watershed.shared-tree.m4.Root",
      fields,
    },
  };
}

function hasSchema(value, schema) {
  return value !== null
    && typeof value === "object"
    && Tree.schema(value).identifier === schema.identifier;
}

function arrayTreeValue(value) {
  if (value === null) return { kind: "null" };
  if (typeof value === "string") return { kind: "string", value };
  if (typeof value === "number") return { kind: "number", value };
  if (typeof value === "boolean") return { kind: "boolean", value };
  if (hasSchema(value, ArrayPoint)) {
    return {
      kind: "object",
      schemaId: "org.watershed.shared-tree.m3.Point",
      fields: [
        ["label", arrayTreeValue(value.label)],
        ["x", arrayTreeValue(value.x)],
      ],
    };
  }
  if (hasSchema(value, IdentifierPoint)) {
    return {
      kind: "object",
      schemaId: "org.watershed.shared-tree.identifiers.Point",
      fields: [
        ["id", { kind: "string", value: value.id }],
        ["label", { kind: "string", value: value.label }],
      ],
    };
  }
  if (hasSchema(value, IdentifierPair)) {
    return {
      kind: "object",
      schemaId: "org.watershed.shared-tree.identifiers.Pair",
      fields: [
        ["firstId", { kind: "string", value: value.firstId }],
        ["label", { kind: "string", value: value.label }],
        ["pairOnly", { kind: "string", value: value.pairOnly }],
        ["secondId", { kind: "string", value: value.secondId }],
      ],
    };
  }
  if (hasSchema(value, Items) || hasSchema(value, Points)) {
    return {
      kind: "array",
      schemaId: hasSchema(value, Points)
        ? "org.watershed.shared-tree.m3.Points"
        : "org.watershed.shared-tree.m3.Items",
      elements: [...value].map(arrayTreeValue),
    };
  }
  if (hasSchema(value, IdentifierItems)) {
    return {
      kind: "array",
      schemaId: "org.watershed.shared-tree.identifiers.Items",
      elements: [...value].map(arrayTreeValue),
    };
  }
  if (hasSchema(value, ArrayMap)) {
    return {
      kind: "map",
      schemaId: "org.watershed.shared-tree.m3.ArrayMap",
      entries: [...value.entries()].map(([key, item]) => [key, arrayTreeValue(item)]),
    };
  }
  if (hasSchema(value, IdentifierPointsByKey)) {
    return {
      kind: "map",
      schemaId: "org.watershed.shared-tree.identifiers.PointsByKey",
      entries: [...value.entries()].map(([key, item]) => [key, arrayTreeValue(item)]),
    };
  }
  throw new TypeError("Unsupported upstream array value");
}

function arrayRootValue(root) {
  return {
    present: true,
    value: {
      kind: "object",
      schemaId: "org.watershed.shared-tree.m3.Root",
      fields: [
        ["byKey", arrayTreeValue(root.byKey)],
        ["left", arrayTreeValue(root.left)],
        ["narrow", arrayTreeValue(root.narrow)],
        ["right", arrayTreeValue(root.right)],
      ],
    },
  };
}

function identifierRootValue(root) {
  return {
    present: true,
    value: {
      kind: "object",
      schemaId: "org.watershed.shared-tree.identifiers.Root",
      fields: [
        ["byKey", arrayTreeValue(root.byKey)],
        ["child", arrayTreeValue(root.child)],
        ["left", arrayTreeValue(root.left)],
        ["right", arrayTreeValue(root.right)],
      ],
    },
  };
}

export function canonicalValue(value) {
  if (Array.isArray(value)) return value.map(canonicalValue);
  if (!value || typeof value !== "object") return value;
  const result = Object.fromEntries(Object.entries(value)
    .map(([key, item]) => [key, canonicalValue(item)]));
  if (Array.isArray(result.fields)) {
    result.fields = result.fields
      .map(([key, item]) => [key, canonicalValue(item)])
      .sort(([left], [right]) => Buffer.from(left).compare(Buffer.from(right)));
  }
  if (Array.isArray(result.entries)) {
    result.entries = result.entries
      .map(([key, item]) => [key, canonicalValue(item)])
      .sort(([left], [right]) => Buffer.from(left).compare(Buffer.from(right)));
  }
  return result;
}

function pendingTreeCommits(session) {
  const kernel = Reflect.get(session.data.tree, "kernel");
  assert(kernel && typeof kernel === "object", "Missing pinned SharedTree kernel");
  const manager = Reflect.get(kernel, "editManager");
  assert.equal(manager?.constructor.name, "EditManager", "Unexpected pinned edit manager");
  const commits = manager.getLocalCommits("main");
  assert(Array.isArray(commits), "Missing local tree commits");
  return commits.length;
}

function upstreamHistoryEvidence(session) {
  const kernel = Reflect.get(session.data.tree, "kernel");
  assert(kernel && typeof kernel === "object", "Missing pinned SharedTree kernel");
  const manager = Reflect.get(kernel, "editManager");
  assert.equal(manager?.constructor.name, "EditManager", "Unexpected pinned edit manager");
  const persist = (value) => {
    const encoded = JSON.stringify(value, (_key, item) =>
      item instanceof Map
        ? { type: "Map", entries: [...item.entries()] }
        : item instanceof Set
          ? { type: "Set", values: [...item.values()] }
          : item);
    return encoded === undefined ? null : JSON.parse(encoded);
  };
  const commits = (values, originatorId) => values.map(({ revision, change }) => ({
    revision: String(revision),
    originatorId,
    changeset: {
      changeCount: change.changes.length,
      raw: persist(change),
    },
  }));
  const originatorId = String(manager.localSessionId);
  return {
    pending: commits(manager.getLocalCommits("main"), originatorId),
    trunk: commits(manager.getTrunkCommits?.("main") ?? [], null),
    forest: persist(session.data.tree.contentSnapshot?.()),
  };
}

function upstreamHistoryRevisions(session) {
  const history = upstreamHistoryEvidence(session);
  return [...history.trunk, ...history.pending].map(({ revision }) => revision);
}

function setUpstream(root, path, value) {
  assert(path.length > 0, "Upstream path must not be empty");
  let parent = root;
  for (const segment of path.slice(0, -1)) {
    parent = hasSchema(parent, DynamicMap) || hasSchema(parent, ArrayMap)
      ? parent.get(segment)
      : parent[segment];
    assert(parent !== undefined, `Missing upstream path segment: ${segment}`);
  }
  const field = path.at(-1);
  if (hasSchema(parent, DynamicMap) || hasSchema(parent, ArrayMap)) {
    parent.set(field, value);
  }
  else parent[field] = value;
}

function treeValue(value) {
  if (value === null) return { kind: "null" };
  if (typeof value === "string") return { kind: "string", value };
  if (typeof value === "number") return { kind: "number", value };
  if (typeof value === "boolean") return { kind: "boolean", value };
  if (value && typeof value === "object") {
    return {
      kind: "object",
      schemaId: "org.watershed.shared-tree.m1.Point",
      fields: [
        ["x", treeValue(value.x)],
        ["y", treeValue(value.y)],
      ],
    };
  }
  throw new TypeError("Unsupported tree value");
}

function upstreamMapValue(value) {
  assert(value && typeof value === "object", "Map value must be tagged");
  switch (value.kind) {
    case "null":
      return null;
    case "string":
    case "number":
    case "boolean":
      return value.value;
    case "object": {
      assert.equal(
        value.schemaId,
        "org.watershed.shared-tree.m2.Point",
        "Unsupported map object schema",
      );
      const fields = Object.fromEntries(value.fields);
      assert.deepEqual(Object.keys(fields).sort(), ["x", "y"]);
      return new MapPoint({
        x: upstreamMapValue(fields.x),
        y: upstreamMapValue(fields.y),
      });
    }
    case "map": {
      assert.equal(
        value.schemaId,
        "org.watershed.shared-tree.m2.DynamicMap",
        "Unsupported map schema",
      );
      const keys = value.entries.map(([key]) => key);
      assert.equal(new Set(keys).size, keys.length, "Duplicate map key");
      return new DynamicMap(value.entries.map(([key, item]) =>
        [key, upstreamMapValue(item)]));
    }
    default:
      throw new TypeError(`Unsupported map value kind: ${value.kind}`);
  }
}

function upstreamArrayValue(value) {
  assert(value && typeof value === "object", "Array value must be tagged");
  switch (value.kind) {
    case "null":
      return null;
    case "string":
    case "number":
    case "boolean":
      return value.value;
    case "object": {
      if (value.schemaId === "org.watershed.shared-tree.identifiers.Point") {
        const fields = Object.fromEntries(value.fields);
        assert.deepEqual(Object.keys(fields).sort(),
          Object.hasOwn(fields, "id") ? ["id", "label"] : ["label"]);
        return new IdentifierPoint({
          ...(fields.id ? { id: upstreamArrayValue(fields.id) } : {}),
          label: upstreamArrayValue(fields.label),
        });
      }
      assert.equal(
        value.schemaId,
        "org.watershed.shared-tree.m3.Point",
        "Unsupported array object schema",
      );
      const fields = Object.fromEntries(value.fields);
      assert.deepEqual(Object.keys(fields).sort(), ["label", "x"]);
      return new ArrayPoint({
        label: upstreamArrayValue(fields.label),
        x: upstreamArrayValue(fields.x),
      });
    }
    case "array": {
      const values = value.elements.map(upstreamArrayValue);
      if (value.schemaId === "org.watershed.shared-tree.m3.Items") {
        return new Items(values);
      }
      if (value.schemaId === "org.watershed.shared-tree.m3.Points") {
        return new Points(values);
      }
      throw new TypeError(`Unsupported array schema: ${value.schemaId}`);
    }
    case "map": {
      assert.equal(
        value.schemaId,
        "org.watershed.shared-tree.m3.ArrayMap",
        "Unsupported array map schema",
      );
      const keys = value.entries.map(([key]) => key);
      assert.equal(new Set(keys).size, keys.length, "Duplicate array map key");
      return new ArrayMap(value.entries.map(([key, item]) =>
        [key, upstreamArrayValue(item)]));
    }
    default:
      throw new TypeError(`Unsupported array value kind: ${value.kind}`);
  }
}

function mapTreeValue(value) {
  if (value === null) return { kind: "null" };
  if (typeof value === "string") return { kind: "string", value };
  if (typeof value === "number") return { kind: "number", value };
  if (typeof value === "boolean") return { kind: "boolean", value };
  if (hasSchema(value, MapPoint)) {
    return {
      kind: "object",
      schemaId: "org.watershed.shared-tree.m2.Point",
      fields: [
        ["x", mapTreeValue(value.x)],
        ["y", mapTreeValue(value.y)],
      ],
    };
  }
  if (hasSchema(value, DynamicMap)) {
    return {
      kind: "map",
      schemaId: "org.watershed.shared-tree.m2.DynamicMap",
      entries: [...value.entries()].map(([key, item]) =>
        [key, mapTreeValue(item)]),
    };
  }
  throw new TypeError("Unsupported upstream map value");
}

function mapAt(root, path) {
  const value = path.reduce((node, segment) =>
    hasSchema(node, DynamicMap) || hasSchema(node, ArrayMap)
      ? node.get(segment)
      : node[segment], root);
  assert(hasSchema(value, DynamicMap) || hasSchema(value, ArrayMap),
    `Path is not a dynamic map: ${path.join(".")}`);
  return value;
}

function mapInput(map, value) {
  return hasSchema(map, ArrayMap)
    ? upstreamArrayValue(value)
    : upstreamMapValue(value);
}

function mapOutput(map, value) {
  return hasSchema(map, ArrayMap)
    ? arrayTreeValue(value)
    : mapTreeValue(value);
}

function arrayAt(root, path) {
  const value = path.reduce((node, segment) => {
    if (hasSchema(node, ArrayMap)) return node.get(segment);
    return node[segment];
  }, root);
  assert(hasSchema(value, Items) || hasSchema(value, Points)
    || hasSchema(value, IdentifierItems),
    `Path is not an array: ${path.join(".")}`);
  return value;
}

function canonicalMapKeys(keys) {
  return [...keys].sort((left, right) =>
    Buffer.from(left).compare(Buffer.from(right)));
}

function canonicalMapEntries(entries) {
  return [...entries]
    .map(([key, value]) => [key, canonicalValue(value)])
    .sort(([left], [right]) => Buffer.from(left).compare(Buffer.from(right)));
}

function upstreamNodeAt(root, path) {
  const node = path.reduce((value, segment) =>
    Array.isArray(value) || typeof value?.at === "function"
      ? value.at(Number(segment))
      : value[segment], root);
  assert(node, `Missing upstream transaction node: ${path.join("/")}`);
  return node;
}

function applyUpstreamTransactionEdit(view, root, edit) {
  switch (edit.op) {
    case "set":
      setUpstream(root, edit.path, edit.value);
      return { nested: [] };
    case "clear":
      assert.deepEqual(edit.path, ["note"],
        "Only the optional note can be cleared");
      delete root.note;
      return { nested: [] };
    case "map-set": {
      const map = mapAt(root, edit.path);
      map.set(edit.key, mapInput(map, edit.value));
      return { nested: [] };
    }
    case "map-delete":
      mapAt(root, edit.path).delete(edit.key);
      return { nested: [] };
    case "array-insert":
      arrayAt(root, edit.path).insertAt(
        edit.index,
        ...edit.values.map(upstreamArrayValue),
      );
      return { nested: [] };
    case "array-remove":
      arrayAt(root, edit.path).removeRange(edit.start, edit.end);
      return { nested: [] };
    case "array-move": {
      const source = arrayAt(root, edit.sourcePath);
      arrayAt(root, edit.destinationPath).moveRangeToIndex(
        edit.destinationGap,
        edit.sourceStart,
        edit.sourceEnd,
        source,
      );
      return { nested: [] };
    }
    case "transaction":
      return { nested: [runUpstreamScope(view, root, edit)] };
    default:
      return assert.fail(`Unsupported upstream transaction edit: ${edit.op}`);
  }
}

function runUpstreamScope(view, root, scope) {
  const preconditions = scope.constraints.map((constraint) => {
    assert.equal(constraint.type, "nodeInDocument",
      `Unsupported upstream transaction constraint: ${constraint.type}`);
    return { type: "nodeInDocument", node: upstreamNodeAt(root, constraint.path) };
  });
  let observation;
  const aborted = scope.result === "abort";
  const result = view.runTransaction(() => {
    let applied = 0;
    const nested = [];
    for (const edit of scope.edits) {
      nested.push(...applyUpstreamTransactionEdit(view, root, edit).nested);
      applied += 1;
    }
    observation = {
      outcome: aborted ? "aborted" : "committed",
      constraints: scope.constraints.map(({ path }) => path),
      editsApplied: applied,
      observedTree: canonicalValue(arrayRootValue(root)),
      nested,
    };
    return aborted ? { rollback: true } : undefined;
  }, { preconditions });
  assert.equal(result.success, !aborted,
    "Upstream transaction reported another outcome");
  return observation;
}

export function canonicalTransactionResult(result) {
  return {
    outcome: result.outcome,
    callback: canonicalValue(result.callback),
    events: result.events,
    commitRevision: result.commitRevision ?? null,
    outboundCount: result.outboundCount,
    tree: canonicalValue(result.tree),
  };
}

function normalizeOutboundRecords(
  records,
  authoredEventId,
  clientInstanceId,
  stableRevision,
) {
  const seen = new Map();
  let connectionEpoch = 0;
  let previousTransportId;
  return records.flatMap(({ sendId, payload }) =>
    (payload?.messageBatches ?? []).flatMap((batch, batchIndex) =>
      batch.map((operation, operationIndex) => {
        const clientId = payload.clientId;
        const transportId = clientId;
        if (transportId !== previousTransportId) {
          connectionEpoch += 1;
          previousTransportId = transportId;
        }
        const clientSequenceNumber = operation.clientSequenceNumber;
        const commits = decodeTreeSubmissions([{
          ...operation,
          clientId,
        }]).flatMap((submission) => submission.commits);
        const operationId = commits.length > 0
          ? `revision:${commits.map(({ originatorId, revision }) =>
            `${originatorId}:${revision}`).join(",")}`
          : `${clientId}:${clientSequenceNumber}`;
        const originalTransportId = seen.get(operationId);
        const classification = originalTransportId === undefined
          ? "original"
          : originalTransportId === transportId
            ? "duplicate-send"
            : "reconnect-retry";
        if (originalTransportId === undefined) seen.set(operationId, transportId);
        return {
          sendId,
          batchIndex,
          operationIndex,
          classification,
          operationId,
          clientId,
          clientInstanceId,
          transportId,
          connectionEpoch,
          clientSequenceNumber,
          authoredEventId,
          stableRevision,
          payload,
        };
      })));
}

function outboundTransportEvidence(records) {
  const connections = [];
  const epochs = new Map();
  const observations = records.map((record, index) => {
    let epoch = epochs.get(record.clientId);
    if (epoch === undefined) {
      epoch = connections.length + 1;
      epochs.set(record.clientId, epoch);
      connections.push({
        connectionId: record.clientId,
        epoch,
        state: "opened",
      });
    }
    record.transportId = record.clientId;
    record.connectionEpoch = epoch;
    return {
      occurrenceId: index + 1,
      connectionId: record.clientId,
      submissions: [structuredClone(record.payload)],
    };
  });
  return { connections, observations };
}

function bindOutboundTransport(records, gateEvidence) {
  const occurrences = gateEvidence.outboundOccurrences ?? [];
  const connections = gateEvidence.connections ?? [];
  const matched = new Set();
  const seen = new Map();
  const bound = records.map((record) => {
    const match = occurrences.find(({ id, submissions }) =>
      !matched.has(id) && submissions?.some((payload) =>
        payload.clientId === record.clientId
          && (payload.messageBatches ?? []).flat().some((operation) =>
            operation.clientSequenceNumber === record.clientSequenceNumber
              && decodeTreeSubmissions([{
                ...operation,
                clientId: payload.clientId,
              }]).some(({ commits }) =>
                record.operationId
                  === `revision:${commits.map(({ originatorId, revision }) =>
                    `${originatorId}:${revision}`).join(",")}`))));
    assert(match,
      `Native outbound record lacks its transport occurrence: ${JSON.stringify({
        record: {
          clientId: record.clientId,
          clientSequenceNumber: record.clientSequenceNumber,
          operationId: record.operationId,
        },
        occurrences: occurrences.map(({ id, connectionId, submissions }) => ({
          id,
          connectionId,
          submissions: submissions?.map((payload) => ({
            clientId: payload.clientId,
            clientSequenceNumbers: (payload.messageBatches ?? []).flat()
              .map(({ clientSequenceNumber }) => clientSequenceNumber),
          })),
        })),
      })}`);
    matched.add(match.id);
    const connection = connections.find(
      ({ connectionId }) => connectionId === match.connectionId,
    );
    assert(connection, "Native outbound occurrence lacks its connection");
    const original = seen.get(record.operationId);
    const classification = original === undefined
      ? "original"
      : original.connectionId === match.connectionId
        ? "duplicate-send"
        : "reconnect-retry";
    if (original === undefined) {
      seen.set(record.operationId, {
        connectionId: match.connectionId,
        epoch: connection.epoch,
      });
    }
    return {
      ...record,
      classification,
      transportId: match.connectionId,
      connectionEpoch: connection.epoch,
    };
  });
  return {
    outboundRecords: bound,
    transportConnections: structuredClone(connections),
    transportObservations: structuredClone(
      occurrences.filter(({ id }) => matched.has(id)),
    ),
  };
}

async function awaitOutboundTransport(records, gate, label) {
  let evidence;
  await until(() => {
    evidence = gate.evidence();
    return records.every((record) =>
      evidence.outboundOccurrences.some(({ submissions }) =>
        submissions?.some((payload) =>
          payload.clientId === record.clientId
            && (payload.messageBatches ?? []).flat().some(
              ({ clientSequenceNumber }) =>
                clientSequenceNumber === record.clientSequenceNumber,
            ))));
  }, `${label} transport occurrence`, 5_000);
  return bindOutboundTransport(records, evidence);
}

function outboundRecordsForRevision(
  records,
  revision,
  authoredEventId,
  clientInstanceId,
) {
  return normalizeOutboundRecords(
    records,
    authoredEventId,
    clientInstanceId,
    revision,
  ).filter((record) => {
    const operation = record.payload.messageBatches
      ?.at(record.batchIndex)?.at(record.operationIndex);
    if (operation === undefined) return false;
    return decodeTreeSubmissions([{
      ...operation,
      clientId: record.clientId,
    }]).some(({ commits }) =>
      commits.some((commit) => String(commit.revision) === String(revision)));
  });
}

function offsetStableId(value, offset) {
  if (offset === 0) return value;
  assert.match(value,
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i,
    "Outbound allocation session is not a UUID");
  const hex = value.replaceAll("-", "");
  const next = (BigInt(`0x${hex}`) + BigInt(offset))
    .toString(16).padStart(32, "0");
  return `${next.slice(0, 8)}-${next.slice(8, 12)}-${next.slice(12, 16)}-${next.slice(16, 20)}-${next.slice(20)}`;
}

function stableRevisionFromOutbound(records, localRevision, stableRevision) {
  assert(Number.isSafeInteger(Number(localRevision))
    && Number(localRevision) !== 0,
  "Outbound action lacks its local revision generation");
  assert(typeof stableRevision === "string" && stableRevision.length > 0,
    "Outbound action lacks its decompressed stable revision");
  const revisions = records.flatMap((record) => {
    const operation = record.payload.messageBatches
      ?.at(record.batchIndex)?.at(record.operationIndex);
    if (operation === undefined) return [];
    return decodeTreeSubmissions([{
      ...operation,
      clientId: record.clientId,
    }]).flatMap((submission) => submission.commits.map((commit) => {
      assert.equal(commit.revision, Number(localRevision),
        "Outbound commit differs from its local revision");
      const allocations = submission.allocations.filter(
        ({ sessionId, first, last }) => sessionId === commit.originatorId
          && Array.from(
            { length: last - first + 1 },
            (_, index) => offsetStableId(sessionId, first + index - 1),
          ).includes(stableRevision),
      );
      assert.equal(allocations.length, 1,
        "Outbound commit lacks one exact revision allocation");
      return stableRevision;
    }));
  });
  assert.equal(new Set(revisions).size, 1,
    "Outbound action does not resolve to one stable revision");
  return revisions[0];
}

export function upstreamAdapter(session, viewConfigurations = {}) {
  const instanceId = randomUUID();
  const events = [];
  const commits = [];
  const handles = new Map();
  const resolvedRevisions = new Map();
  let lastLocal;
  let commitEventCount = 0;
  const outboundSends = [];
  const actionEvidence = new Set();
  const refreshActionEvidence = (evidence) => {
    let outboundRecords = outboundRecordsForRevision(
      outboundSends,
      evidence.localRevision,
      evidence.eventId,
      instanceId,
    ).map((record) => ({
      ...record,
      stableRevision: evidence.stableRevision,
    }));
    const transport = outboundTransportEvidence(outboundRecords);
    Object.assign(evidence.result, {
      outboundRecords,
      transportConnections: transport.connections,
      transportObservations: transport.observations,
    });
  };
  const trackActionEvidence = (
    result,
    localRevision,
    stableRevision,
    eventId,
  ) => {
    const evidence = { result, localRevision, stableRevision, eventId };
    actionEvidence.add(evidence);
    refreshActionEvidence(evidence);
    return result;
  };
  session.container.deltaManager.on("submitOp", (message) => {
    outboundSends.push({
      sendId: outboundSends.length + 1,
      payload: {
        clientId: session.container.clientId,
        messageBatches: [[structuredClone(message)]],
      },
    });
    for (const evidence of actionEvidence) refreshActionEvidence(evidence);
  });
  const connectionEvents = [];
  session.container.deltaManager.on("disconnect", (reason, error) => {
    connectionEvents.push({ reason, ...(error ? { error: replayError(error) } : {}) });
  });
  let connected = session.container.connected;
  let activeView = session.data.view;
  let activeViewLabel = viewConfigurations.v1 ? "v1" : null;
  let unsubscribeActiveView;
  let unsubscribeSchema;
  let unsubscribeCommits;
  const enumName = (enumeration, value) =>
    typeof value === "number" ? enumeration[value] : String(value);
  const subscribeActiveView = () => {
    unsubscribeSchema = activeView.events?.on(
      "schemaChanged",
      () => events.push({ kind: "schema" }),
    );
    if (activeView.compatibility?.canView !== false) {
      unsubscribeActiveView = Tree.on(
        activeView.root,
        "treeChanged",
        () => events.push({ kind: "data" }),
      );
    }
    unsubscribeCommits = activeView.events.on(
      "changed",
      (metadata, getRevertible) => {
        commitEventCount += 1;
        const eventId = commitEventCount;
        const actionId = `event-${eventId}`;
        const revision = upstreamHistoryRevisions(session).at(-1);
        let handle;
        if (metadata.isLocal && getRevertible !== undefined) {
          handle = getRevertible();
          lastLocal = {
            handle,
            kind: metadata.kind,
            eventId,
            actionId,
            revision,
          };
        }
        commits.push({
          type: "commit",
          kind: enumName(CommitKind, metadata.kind),
          local: metadata.isLocal,
          factoryAvailable: getRevertible !== undefined,
          handleAcquired: handle !== undefined,
          eventId,
          actionId,
          revision,
        });
        if (metadata.isLocal) {
          metadata.events.on("settled", (outcome) => {
            commits.push({
              type: "settlement",
              kind: enumName(CommitKind, metadata.kind),
              outcome: enumName(
                { 0: "FullyApplied", 1: "FullyDropped", 2: "NewContentOnly" },
                outcome,
              ),
              eventId,
              actionId,
              revision: resolvedRevisions.get(actionId) ?? revision,
            });
          });
        }
      },
    );
  };
  const replaceActiveView = (label) => {
    const config = viewConfigurations[label]?.config;
    assert(config, `Unknown upstream view: ${label}`);
    unsubscribeActiveView?.();
    unsubscribeSchema?.();
    unsubscribeCommits?.();
    activeView.dispose();
    activeView = session.data.tree.viewWith(config);
    activeViewLabel = label;
    subscribeActiveView();
    return activeView;
  };
  subscribeActiveView();
  const clientIds = new Set();
  if (session.container.clientId) clientIds.add(session.container.clientId);
  return {
    implementation: "upstream",
    instanceId,
    session,
    clientIds,
    connectionEvents,
    async set(path, value) {
      setUpstream(activeView.root, path, value);
    },
    async clear(path) {
      assert.deepEqual(path, ["note"], "Only the optional note can be cleared");
      delete activeView.root.note;
    },
    async mapGet(path, key) {
      const map = mapAt(activeView.root, path);
      return map.has(key)
        ? { present: true, value: canonicalValue(mapOutput(map, map.get(key))) }
        : { present: false };
    },
    async mapSet(path, key, value) {
      const map = mapAt(activeView.root, path);
      map.set(key, mapInput(map, value));
    },
    async mapDelete(path, key) {
      mapAt(activeView.root, path).delete(key);
    },
    async mapKeys(path) {
      return canonicalMapKeys(mapAt(activeView.root, path).keys());
    },
    async mapEntries(path) {
      const map = mapAt(activeView.root, path);
      return canonicalMapEntries(
        [...map.entries()]
          .map(([key, value]) => [key, mapOutput(map, value)]),
      );
    },
    async arrayGet(path, index) {
      const array = arrayAt(session.data.view.root, path);
      return index < array.length
        ? { present: true, value: canonicalValue(arrayTreeValue(array[index])) }
        : { present: false };
    },
    async arrayValues(path) {
      return [...arrayAt(session.data.view.root, path)]
        .map((value) => canonicalValue(arrayTreeValue(value)));
    },
    async arrayInsert(path, index, values) {
      arrayAt(session.data.view.root, path).insertAt(
        index,
        ...values.map(upstreamArrayValue),
      );
    },
    async arrayRemove(path, start, end) {
      arrayAt(session.data.view.root, path).removeRange(start, end);
    },
    async constrainedArrayRemove(targetPath, path, start, end) {
      const target = targetPath.reduce((value, segment) =>
        Array.isArray(value) || typeof value?.at === "function"
          ? value.at(Number(segment))
          : value[segment], session.data.view.root);
      assert(target, "Missing upstream constraint target");
      const removal = arrayAt(session.data.view.root, path);
      removal.removeRange(start, end);
      assert(targetPath.reduce((value, segment) =>
        typeof value?.at === "function"
          ? value.at(Number(segment))
          : value[segment], session.data.view.root) === target,
      "Upstream constraint target changed during unrelated removal");
    },
    async arrayMove(sourcePath, sourceStart, sourceEnd, destinationPath, destinationGap) {
      const source = arrayAt(session.data.view.root, sourcePath);
      const destination = arrayAt(session.data.view.root, destinationPath);
      destination.moveRangeToIndex(
        destinationGap,
        sourceStart,
        sourceEnd,
        source,
      );
    },
    async transaction(scope) {
      const root = session.data.view.root;
      const beforeEvents = events.length;
      const beforePending = pendingTreeCommits(session);
      const callback = runUpstreamScope(activeView, root, scope);
      const emitted = events.splice(beforeEvents);
      const outboundCount = Math.max(pendingTreeCommits(session) - beforePending, 0);
      const pending = upstreamHistoryEvidence(session).pending;
      return canonicalTransactionResult({
        outcome: callback.outcome,
        callback,
        events: emitted,
        commitRevision: outboundCount > 0
          ? String(pending.at(-1).revision)
          : null,
        outboundCount,
        tree: arrayRootValue(root),
      });
    },
    async retainLastLocalCommit(name) {
      assert(lastLocal, "No unretained local commit is available");
      handles.set(name, lastLocal);
      const retained = lastLocal;
      lastLocal = undefined;
      let outboundRecords = [];
      await until(() => {
        outboundRecords = outboundRecordsForRevision(
          outboundSends,
          retained.revision,
          retained.eventId,
          instanceId,
        );
        return outboundRecords.length > 0;
      }, `upstream retained ${name} outbound send`, 5_000);
      const stableRevision = stableRevisionFromOutbound(
        outboundRecords,
        retained.revision,
        session.runtime.idCompressor.decompress(Number(retained.revision)),
      );
      resolvedRevisions.set(retained.actionId, stableRevision);
      for (const event of commits) {
        if (event.actionId === retained.actionId) event.revision = stableRevision;
      }
      outboundRecords = outboundRecords.map((record) => ({
        ...record,
        stableRevision,
      }));
      const transport = outboundTransportEvidence(outboundRecords);
      return trackActionEvidence({
        name,
        kind: enumName(CommitKind, retained.kind),
        factoryAvailable: true,
        status: enumName(RevertibleStatus, retained.handle.status),
        eventId: retained.eventId,
        actionId: retained.actionId,
        revision: stableRevision,
        revisionResolution: {
          actionId: retained.actionId,
          localRevision: retained.revision,
          stableRevision,
        },
        outboundRecords,
        transportConnections: transport.connections,
        transportObservations: transport.observations,
      }, retained.revision, stableRevision, retained.eventId);
    },
    async revert(name, dispose) {
      const retained = handles.get(name);
      assert(retained, `Unknown upstream revertible handle: ${name}`);
      const beforeRevisions = upstreamHistoryRevisions(session);
      const beforeEventCount = commitEventCount;
      const beforeOutboundCount = outboundSends.length;
      retained.handle.revert(dispose);
      const authored = commits.filter(
        ({ type, local, eventId }) =>
          type === "commit" && local === true && eventId > beforeEventCount,
      );
      const submittedRevisions = upstreamHistoryRevisions(session).filter(
        (revision) => !beforeRevisions.includes(revision),
      );
      assert.equal(authored.length, 1,
        `Upstream revert ${name} authored another local commit count`);
      assert.equal(submittedRevisions.length, 1,
        `Upstream revert ${name} submitted another operation count`);
      assert.equal(authored[0].revision, submittedRevisions[0],
        `Upstream revert ${name} event differs from its submission`);
      let outboundRecords = [];
      await until(() => {
        outboundRecords = outboundRecordsForRevision(
          outboundSends.slice(beforeOutboundCount),
          submittedRevisions[0],
          authored[0].eventId,
          instanceId,
        );
        return outboundRecords.length > 0;
      }, `upstream revert ${name} outbound send`, 5_000);
      const localRevision = submittedRevisions[0];
      const stableRevision = stableRevisionFromOutbound(
        outboundRecords,
        localRevision,
        session.runtime.idCompressor.decompress(Number(localRevision)),
      );
      resolvedRevisions.set(authored[0].actionId, stableRevision);
      for (const event of commits) {
        if (event.actionId === authored[0].actionId) {
          event.revision = stableRevision;
        }
      }
      outboundRecords = outboundRecords.map((record) => ({
        ...record,
        stableRevision,
      }));
      const transport = outboundTransportEvidence(outboundRecords);
      return trackActionEvidence({
        name,
        authoredKind: authored[0].kind,
        status: enumName(RevertibleStatus, retained.handle.status),
        settlement: "Pending",
        authoredCount: authored.length,
        outboundCount: submittedRevisions.length,
        authoredEventIds: authored.map(({ eventId }) => eventId),
        actionId: authored[0].actionId,
        submittedRevisions: [stableRevision],
        revisionResolution: {
          actionId: authored[0].actionId,
          localRevision,
          stableRevision,
        },
        outboundRecords,
        transportConnections: transport.connections,
        transportObservations: transport.observations,
      }, localRevision, stableRevision, authored[0].eventId);
    },
    async revertibleStatus(name) {
      const retained = handles.get(name);
      assert(retained, `Unknown upstream revertible handle: ${name}`);
      return {
        name,
        status: enumName(RevertibleStatus, retained.handle.status),
      };
    },
    async disposeRevertible(name) {
      const retained = handles.get(name);
      assert(retained, `Unknown upstream revertible handle: ${name}`);
      retained.handle.dispose();
      return {
        name,
        status: enumName(RevertibleStatus, retained.handle.status),
      };
    },
    async checkpoint() {
      if (session.container.clientId) clientIds.add(session.container.clientId);
      const captured = events.splice(0);
      let wholeTree = null;
      let readError;
      let arrayRetained;
      try {
        const root = activeView.root;
        wholeTree = canonicalValue(
          hasSchema(root, ArrayRoot)
            ? arrayRootValue(root)
            : hasSchema(root, IdentifierRoot)
              ? identifierRootValue(root)
            : root.items instanceof DynamicMap
              ? mapRootValue(root)
              : Tree.schema(root).identifier
                  === "org.watershed.shared-tree.m4.Root"
                ? schemaRootValue(root)
                : rootValue(root),
        );
        if (hasSchema(root, ArrayRoot)) {
          arrayRetained = { removed: session.data.tree.contentSnapshot().removed };
        }
      } catch (error) {
        readError = error instanceof Error ? error.message : String(error);
      }
      return {
        implementation: "upstream",
        instanceId,
        sequenceNumber: session.container.deltaManager.lastSequenceNumber,
        pendingTreeCount: pendingTreeCommits(session),
        inflightSubmissionCount: session.container.deltaManager.outbound.length,
        wholeTree,
        events: captured,
        commits: commits.splice(0),
        history: upstreamHistoryEvidence(session),
        readError,
        clientId: session.container.clientId,
        connectionEvents: [...connectionEvents],
        ...(arrayRetained ? { retained: arrayRetained } : {}),
      };
    },
    async pendingSummaryEvidence() {
      const kernel = Reflect.get(session.data.tree, "kernel");
      const serializer = Reflect.get(kernel, "serializer");
      assert(serializer, "Missing pinned SharedTree serializer");
      const entries = Reflect.get(kernel, "summarizables").slice(1).map(
        (summarizable) => [
          summarizable.key,
          summarizable.summarize({
            stringify: (contents) =>
              serializer.stringify(contents, session.data.tree.handle),
            fullTree: true,
            telemetryContext: undefined,
            incrementalSummaryContext: undefined,
          }).summary,
        ],
      );
      return {
        sequenceNumber: session.container.deltaManager.lastSequenceNumber,
        tree: summaryEntryEvidence({
          type: SummaryType.Tree,
          tree: Object.fromEntries(entries),
        }),
      };
    },
    async holdInbound() {
      assert.equal(session.container.connectionMode, "write",
        "Upstream must establish its write connection before pausing inbound delivery");
      await session.container.deltaManager.inbound.pause();
    },
    async holdOutbound() {
      await session.container.deltaManager.outbound.pause();
    },
    async awaitInbound(sequenceNumbers) {
      const watermark = Math.max(...sequenceNumbers);
      await until(() => session.container.deltaManager.lastKnownSeqNumber >= watermark
        && session.container.deltaManager.inbound.length > 0,
      "upstream held inbound sequence");
      return {
        receivedThrough: session.container.deltaManager.lastKnownSeqNumber,
        queuedCount: session.container.deltaManager.inbound.length,
      };
    },
    async releaseInbound({ order = "fifo", duplicate = false } = {}) {
      assert.equal(order, "fifo", "Upstream inbound queue supports FIFO only");
      assert.equal(duplicate, false, "Upstream inbound queue cannot duplicate messages");
      if (session.container.deltaManager.inbound.paused) {
        session.container.deltaManager.inbound.resume();
      }
    },
    async releaseOutbound({ order = "fifo", duplicate = false } = {}) {
      assert.equal(order, "fifo", "Upstream outbound queue supports FIFO only");
      assert.equal(duplicate, false, "Upstream outbound queue cannot duplicate messages");
      if (session.container.deltaManager.outbound.paused) {
        session.container.deltaManager.outbound.resume();
      }
    },
    async awaitSynced(sequenceNumber = 0) {
      await until(() =>
        !session.container.isDirty
        && session.container.deltaManager.inbound.length === 0
        && session.container.deltaManager.outbound.length === 0
        && session.container.deltaManager.lastSequenceNumber >= sequenceNumber,
      "upstream synchronization");
    },
    async reconnect() {
      if (session.container.connected) {
        session.container.disconnect();
        await until(() => !session.container.connected, "upstream disconnect");
      }
      session.container.connect();
      await until(() => session.container.connected, "upstream reconnect");
      connected = true;
      if (session.container.clientId) clientIds.add(session.container.clientId);
    },
    async disconnect() {
      if (session.container.connected) {
        session.container.disconnect();
        await until(() => !session.container.connected, "upstream disconnect");
      }
      connected = false;
    },
    async schemaCompatibility(label) {
      assert(activeViewLabel, "Upstream schema adapter has no active view label");
      const previous = activeViewLabel;
      const {
        canView,
        canUpgrade,
        isEquivalent,
      } = replaceActiveView(label).compatibility;
      replaceActiveView(previous);
      return { canView, canUpgrade, isEquivalent };
    },
    async schemaUpgrade(label) {
      assert(activeViewLabel, "Upstream schema adapter has no active view label");
      const previous = activeViewLabel;
      replaceActiveView(label).upgradeSchema();
      replaceActiveView(previous);
    },
    async openView(label) {
      replaceActiveView(label);
    },
    isConnected: () => connected && session.container.connected,
  };
}

export async function nativeAdapter(
  target, config, descriptor, token, { createClient = startClient } = {},
) {
  const client = await createClient(
    target,
    descriptor,
    { socketUrl: config.socketUrl, token },
    {
      gateFactory: (host, port) =>
        DeliveryGate.open(host, port, { documentId: descriptor.documentId }),
    },
  );
  const clientIds = new Set();
  let connected = true;
  let inboundEvidenceOffset = 0;
  let reconnectRetryUsed = false;
  const reconnectRetries = [];
  const nativeLoadIdentities = [];
  const resolvedRevisions = new Map();
  try {
    success(await client.request({ command: "subscribe" }), `${target} subscribe`);
  } catch (error) {
    try {
      await client.close();
    } catch (cleanupError) {
      error.cleanupErrors = [...(error.cleanupErrors ?? []), cleanupError];
    }
    throw error;
  }
  return {
    implementation: target,
    instanceId: client.instanceId,
    client,
    clientIds,
    async set(path, value) {
      success(await client.request({
        command: "set",
        path,
        value: treeValue(value),
      }), `${target} set ${path.join(".")}`);
    },
    async clear(path) {
      success(await client.request({ command: "clear", path }),
        `${target} clear ${path.join(".")}`);
    },
    async mapGet(path, key) {
      return canonicalValue(await client.mapGet(path, key));
    },
    async mapSet(path, key, value) {
      try {
        await client.mapSet(path, key, value);
      } catch (error) {
        throw new Error(
          `${target} map-set ${path.join(".")}[${JSON.stringify(key)}]: `
            + JSON.stringify(error.cause ?? replayError(error)),
          { cause: error },
        );
      }
    },
    async mapDelete(path, key) {
      await client.mapDelete(path, key);
    },
    async mapKeys(path) {
      return canonicalMapKeys(await client.mapKeys(path));
    },
    async mapEntries(path) {
      return canonicalMapEntries(await client.mapEntries(path));
    },
    async schemaCompatibility(view) {
      return canonicalValue(await client.schemaCompatibility(view));
    },
    async schemaUpgrade(view) {
      await client.schemaUpgrade(view);
    },
    async openView(view) {
      await client.openView(view);
    },
    async arrayGet(path, index) {
      return canonicalValue(await client.arrayGet(path, index));
    },
    async arrayValues(path) {
      return canonicalValue(await client.arrayValues(path));
    },
    async arrayInsert(path, index, values) {
      await client.arrayInsert(path, index, values);
    },
    async arrayRemove(path, start, end) {
      await client.arrayRemove(path, start, end);
    },
    async constrainedArrayRemove(targetPath, path, start, end) {
      await client.constrainedArrayRemove(targetPath, path, start, end);
    },
    async arrayMove(sourcePath, sourceStart, sourceEnd, destinationPath, destinationGap) {
      await client.arrayMove(
        sourcePath,
        sourceStart,
        sourceEnd,
        destinationPath,
        destinationGap,
      );
    },
    async transaction(scope) {
      return canonicalTransactionResult(await client.transaction(scope));
    },
    async retainLastLocalCommit(name) {
      const result = await client.retainLastLocalCommit(name);
      if (typeof result.actionId === "string"
        && typeof result.revision === "string") {
        resolvedRevisions.set(result.actionId, result.revision);
      }
      const outboundRecords = normalizeOutboundRecords(
          result.outboundRecords ?? [],
          result.eventId,
          client.instanceId,
          result.revision,
        );
      const transport = await awaitOutboundTransport(
        outboundRecords,
        client.gate,
        `${target} retained ${name}`,
      );
      return {
        ...result,
        ...transport,
        revisionResolution: {
          actionId: result.actionId,
          localRevision: null,
          stableRevision: result.revision,
        },
      };
    },
    async revertibleStatus(name) {
      return client.revertibleStatus(name);
    },
    async disposeRevertible(name) {
      return client.disposeRevertible(name);
    },
    async revert(name, dispose) {
      const result = await client.revert(name, dispose);
      const outboundRecords = normalizeOutboundRecords(
          result.outboundRecords ?? [],
          result.authoredEventIds?.[0],
          client.instanceId,
          result.submittedRevisions?.[0],
        );
      const transport = await awaitOutboundTransport(
        outboundRecords,
        client.gate,
        `${target} revert ${name}`,
      );
      if (typeof result.actionId === "string"
        && typeof result.submittedRevisions?.[0] === "string") {
        resolvedRevisions.set(result.actionId, result.submittedRevisions[0]);
      }
      return {
        ...result,
        ...transport,
        revisionResolution: {
          actionId: result.actionId,
          localRevision: null,
          stableRevision: result.submittedRevisions?.[0],
        },
      };
    },
    async checkpoint() {
      const reply = success(await client.request({ command: "checkpoint" }),
        `${target} checkpoint`);
      if (reply.observation.clientId) clientIds.add(reply.observation.clientId);
      if (Number.isSafeInteger(reply.result.summarySequenceNumber)
        && !nativeLoadIdentities.some(({ snapshotSequenceNumber }) =>
          snapshotSequenceNumber === reply.result.summarySequenceNumber)) {
        nativeLoadIdentities.push({
          snapshotSequenceNumber: reply.result.summarySequenceNumber,
          observedSequenceNumber: reply.sequenceNumber,
        });
      }
      return {
        implementation: target,
        instanceId: client.instanceId,
        sequenceNumber: reply.sequenceNumber,
        pendingTreeCount: reply.observation.pendingTreeCount,
        inflightSubmissionCount: reply.observation.inFlightCount,
        wholeTree: canonicalValue(reply.result.root),
        events: reply.result.events,
        commits: reply.result.commits.map((event) => {
          const revision = resolvedRevisions.get(event.actionId);
          return revision === undefined ? event : { ...event, revision };
        }),
        history: reply.result.history,
        readError: reply.result.readError,
        connection: reply.observation,
        clientId: reply.observation.clientId,
        reconnectRetries: structuredClone(reconnectRetries),
        ...(reply.result.retained ? { retained: reply.result.retained } : {}),
      };
    },
    async pendingSummaryEvidence() {
      return success(await client.request({
        command: "pending-summary-evidence",
      }), `${target} pending summary evidence`).result;
    },
    async holdInbound() {
      inboundEvidenceOffset = client.gate.evidence().held.length;
      client.gate.hold("inbound", "op");
    },
    async holdOutbound() {
      client.gate.hold("outbound", "op");
    },
    async awaitInbound(sequenceNumbers) {
      let held;
      await until(() => {
        held = client.gate.evidence().held.slice(inboundEvidenceOffset)
          .filter(({ direction, kind }) => direction === "inbound" && kind === "op");
        const sequences = new Set(held.flatMap(({ sequenceNumbers }) => sequenceNumbers));
        return sequenceNumbers.every((sequenceNumber) => sequences.has(sequenceNumber));
      }, `${target} held inbound sequences`);
      return { heldSequenceNumbers: held.flatMap(({ sequenceNumbers }) => sequenceNumbers) };
    },
    async releaseInbound(options = {}) {
      const held = client.gate.evidence().held.slice(inboundEvidenceOffset)
        .filter(({ direction, kind }) => direction === "inbound" && kind === "op");
      await client.gate.release("inbound", options);
      const ids = new Set(held.map(({ id }) => id));
      const delivered = client.gate.evidence().delivered
        .filter(({ id, duplicate }) => ids.has(id) && !duplicate);
      assert.deepEqual(delivered.map(({ id }) => id),
        (options.order === "reverse" ? held.toReversed() : held).map(({ id }) => id),
        `${target} inbound release differs from the scheduled order`);
      return { deliveredSequenceNumbers: delivered.flatMap(({ sequenceNumbers }) => sequenceNumbers) };
    },
    async releaseOutbound(options) {
      await client.gate.release("outbound", options);
    },
    async awaitSynced(sequenceNumber = 0) {
      const response = await client.request({
        command: "await-synced",
        minimumSequenceNumber: sequenceNumber,
      });
      let reply;
      try {
        reply = success(response, `${target} await-synced`);
      } catch (error) {
        if (response?.error && typeof response.error === "object") {
          error.nativeError = structuredClone(response.error);
        }
        throw error;
      }
      if (reply.observation.clientId) clientIds.add(reply.observation.clientId);
    },
    async reconnect() {
      for (let attempt = 0; attempt < 2; attempt += 1) {
        if (connected) await this.disconnect();
        await client.gate.reconnect();
        try {
          success(await client.request({ command: "reconnect" }), `${target} reconnect`);
          connected = true;
          await this.awaitSynced();
          return;
        } catch (error) {
          const nativeError = error.nativeError;
          const transport = nativeError?.message?.match(
            /Transport\((?:Timeout|StreamError\("Closed"\))\)/,
          )?.[0];
          if (attempt === 0
            && !reconnectRetryUsed
            && nativeError?.code === "connection-failed"
            && nativeError.operation === "await-synced"
            && transport) {
            reconnectRetryUsed = true;
            reconnectRetries.push({
              attempt: attempt + 1,
              code: nativeError.code,
              operation: nativeError.operation,
              message: `channel connect failed: ${transport}`,
            });
            continue;
          }
          throw error;
        }
      }
    },
    async disconnect() {
      if (!connected) return;
      await client.gate.disconnect();
      for (const direction of ["inbound", "outbound"]) {
        try {
          await client.gate.release(direction);
        } catch (error) {
          assert.match(error.message, /deliveries were dropped while disconnected/);
        }
      }
      await client.request({ command: "disconnect" });
      connected = false;
    },
    isConnected: () => connected,
    async summarizePublication() {
      const result = success(await client.request({ command: "summarize" }),
        `${target} summarize`).result;
      assert(typeof result?.version === "string" && result.version.length > 0,
        `${target} summarize lacks a published version`);
      assert(Number.isSafeInteger(result.snapshotSequenceNumber)
        && result.snapshotSequenceNumber >= 0,
      `${target} summarize lacks a snapshot sequence`);
      return result;
    },
    async summarize() {
      return (await this.summarizePublication()).version;
    },
    evidence() {
      return {
        ...client.gate.evidence(),
        nativeLoadIdentities: structuredClone(nativeLoadIdentities),
        reconnectRetries: structuredClone(reconnectRetries),
      };
    },
    close: () => client.close(),
  };
}

export async function serverHistory(session, sequenceNumber) {
  const service = await session.documentServiceFactory
    .createDocumentService(session.container.resolvedUrl);
  try {
    const storage = await service.connectToDeltaStorage();
    const stream = storage.fetchMessages(
      1,
      sequenceNumber === undefined ? undefined : sequenceNumber + 1,
      AbortSignal.timeout(30_000),
      false,
    );
    const messages = [];
    for (;;) {
      const chunk = await stream.read();
      if (chunk.done) break;
      messages.push(...chunk.value);
    }
    assert(messages.every((message, index) => message.sequenceNumber === index + 1),
      "Server history has a missing or repeated sequence number");
    return messages;
  } finally {
    service.dispose();
  }
}

async function schemaEnvironment(config, context) {
  const containers = [];
  const natives = [];
  const creator = await openSession(config, containers, undefined, false, {
    store: schemaEvolutionServiceStore,
  });
  const documentId = creator.container.resolvedUrl.id;
  await publishUpstreamSummary(
    config,
    containers,
    documentId,
    "Task 10 schema bootstrap",
    { store: schemaEvolutionServiceStore },
  );
  const upstream = upstreamAdapter(await openSession(
    config,
    containers,
    documentId,
    false,
    { store: schemaEvolutionServiceStore },
  ), schemaEvolutionConfigurations);
  const { jwt } = await tokenProvider(config).fetchOrdererToken(
    config.tenantId,
    documentId,
  );
  for (const target of nativeTargets) {
    natives.push(await nativeAdapter(target, config, {
      runId: context.runId,
      documentId,
      tenant: config.tenantId,
      viewSchema: context.schemaViews.v1,
      viewSchemas: context.schemaViews,
    }, jwt));
  }
  const adapters = {
    upstream,
    javascript: natives[0],
    erlang: natives[1],
  };
  await Promise.all(nativeTargets.map((target) => adapters[target].awaitSynced()));
  await settle(adapters);
  return { adapters, containers, creator, documentId, jwt, natives };
}

function cleanupSchemaEnvironment(environment, originalError) {
  const failures = [];
  return (async () => {
    for (const native of environment.natives.toReversed()) {
      try {
        await native.close();
      } catch (error) {
        failures.push(error);
      }
    }
    for (const container of environment.containers.toReversed()) {
      try {
        if (!container.closed) container.dispose();
      } catch (error) {
        failures.push(error);
      }
    }
    if (failures.length === 0) return;
    if (originalError) {
      originalError.cleanupErrors = failures;
      return;
    }
    throw new AggregateError(failures, "Schema environment cleanup failed");
  })();
}

async function runSchemaCompatibilityTarget(config, context, target) {
  const environment = await schemaEnvironment(config, context);
  let failure;
  try {
    const adapter = environment.adapters[target];
    const compatibility = await adapter.schemaCompatibility("optional");
    assert.deepEqual(compatibility, {
      canView: false,
      canUpgrade: true,
      isEquivalent: false,
    }, `${target} reported another optional-schema compatibility`);
    return {
      target,
      protocolVersion: replayReference.version,
      skipped: false,
      observations: [{
        storedView: "v1",
        requestedView: "optional",
        compatibility,
        documentId: environment.documentId,
        instanceId: adapter.instanceId,
      }],
    };
  } catch (error) {
    failure = error;
    throw error;
  } finally {
    await cleanupSchemaEnvironment(environment, failure);
  }
}

export async function runSchemaCompatibility(config, context, {
  runTarget = runSchemaCompatibilityTarget,
} = {}) {
  return Promise.all(implementations.map((target) =>
    runTarget(config, context, target)));
}

async function openSchemaView(adapters, label) {
  await Promise.all(implementations.map((target) =>
    adapters[target].openView(label)));
}

async function runCausalSchemaRace(config, context, cell) {
  const environment = await schemaEnvironment(config, context);
  let failure;
  try {
    const adapter = environment.adapters[cell.upgrader];
    const before = await adapter.checkpoint();
    await adapter.schemaUpgrade("optional");
    await Promise.all(implementations.map((target) =>
      environment.adapters[target].awaitSynced()));
    await openSchemaView(environment.adapters, "optional");
    await adapter.set(["score"], 7);
    const final = await settle(environment.adapters);
    assert(final.observations.every(({ wholeTree }) =>
      wholeTree.value.fields.some(([name, value]) =>
        name === "score" && value.value === 7)),
    "Causal schema upgrade lost its dependent edit");
    const history = decodeTreeSubmissions(await serverHistory(environment.creator));
    return {
      ...cell,
      documentId: environment.documentId,
      instanceIds: Object.fromEntries(implementations.map((target) =>
        [target, environment.adapters[target].instanceId])),
      skipped: false,
      observations: [{
        before,
        final,
        referenceSequenceNumbers: history.flatMap(({ commits, referenceSequenceNumber }) =>
          commits.map(() => referenceSequenceNumber)),
        dependentEditRetained: true,
      }],
    };
  } catch (error) {
    failure = error;
    throw error;
  } finally {
    await cleanupSchemaEnvironment(environment, failure);
  }
}

async function runConcurrentSchemaRace(config, context, cell) {
  const environment = await schemaEnvironment(config, context);
  let failure;
  try {
    const { adapters } = environment;
    const before = await captureCheckpoint("initial", "quiescent", adapters);
    const participants = [cell.upgrader, cell.competitor];
    for (const target of implementations) {
      await adapters[target].holdInbound();
    }
    for (const author of participants) {
      await adapters[author].holdOutbound();
    }
    const upgrade = () => adapters[cell.upgrader].schemaUpgrade("optional");
    const compete = cell.family === "schema-data"
      ? () => adapters[cell.competitor].set(["title"], `race-${cell.id}`)
      : () => adapters[cell.competitor].schemaUpgrade("object-union");
    if (cell.order === "upgrade-first") {
      await upgrade();
      await compete();
    } else {
      await compete();
      await upgrade();
    }
    let oldViewRejected = false;
    try {
      await adapters[cell.upgrader].set(["title"], "stale-view-write");
    } catch {
      oldViewRejected = true;
    }
    await adapters[cell.upgrader].openView("optional");
    if (cell.family === "schema-schema") {
      await adapters[cell.competitor].openView("object-union");
    }
    const optimistic = await captureCheckpoint("optimistic", "intermediate", adapters);
    const releaseOrder = cell.order === "upgrade-first"
      ? [cell.upgrader, cell.competitor]
      : [cell.competitor, cell.upgrader];
    const accepted = [];
    const firstAuthor = releaseOrder[0];
    const losingAuthor = releaseOrder[1];
    let after = (await serverHistory(environment.creator)).at(-1)?.sequenceNumber ?? 0;
    await adapters[firstAuthor].releaseOutbound({ order: "fifo", duplicate: false });
    accepted.push(await waitForAuthorSubmission(
      environment.creator,
      adapters,
      firstAuthor,
      after,
      1,
    ));
    const firstSequenceNumber = accepted[0].outerSequenceNumber;
    for (const target of implementations) {
      if (participants.includes(target)) {
        await adapters[target].awaitInbound([firstSequenceNumber]);
      }
      await adapters[target].releaseInbound({ order: "fifo", duplicate: false });
    }
    let rollback;
    const polling = [];
    await until(async () => {
      const checkpoint = await captureCheckpoint(
        "loser-before-ack",
        "intermediate",
        adapters,
      );
      polling.push(checkpoint);
      if (!reconciledRaceCheckpoint(
        checkpoint,
        losingAuthor,
        firstSequenceNumber,
      )) return false;
      rollback = checkpoint;
      return true;
    }, `${cell.id} losing reconciliation`, 5_000);
    for (const author of participants) await adapters[author].holdInbound();
    after = (await serverHistory(environment.creator)).at(-1)?.sequenceNumber ?? 0;
    await adapters[losingAuthor].releaseOutbound({ order: "fifo", duplicate: false });
    accepted.push(await waitForAuthorSubmission(
      environment.creator,
      adapters,
      losingAuthor,
      after,
      1,
    ));
    const sequenceNumbers = accepted.map(({ outerSequenceNumber }) => outerSequenceNumber);
    for (const target of implementations) {
      await adapters[target].releaseInbound({ order: "fifo", duplicate: false });
    }
    await Promise.all(implementations.map((target) =>
      adapters[target].awaitSynced(Math.max(...sequenceNumbers))));
    const compatibility = await Promise.all(implementations.map(async (target) => ({
      target,
      optional: await adapters[target].schemaCompatibility("optional"),
      objectUnion: await adapters[target].schemaCompatibility("object-union"),
    })));
    const winnerView = compatibility[0].optional.isEquivalent
      ? "optional"
      : compatibility[0].objectUnion.isEquivalent
        ? "object-union"
        : "v1";
    await openSchemaView(adapters, winnerView);
    const final = await settle(adapters);
    const submissions = decodeTreeSubmissions(await serverHistory(environment.creator))
      .filter(({ outerSequenceNumber }) => sequenceNumbers.includes(outerSequenceNumber));
    const referenceSequenceNumbers = submissions.map(
      ({ referenceSequenceNumber }) => referenceSequenceNumber,
    );
    assert.equal(new Set(referenceSequenceNumbers).size, 1,
      `${cell.id} submissions were not concurrent`);
    const losingView = winnerView === "optional" ? "objectUnion" : "optional";
    const losingCompatibility = compatibility.find(
      ({ target }) => target === losingAuthor,
    )?.[losingView];
    const losingSettled = final.observations.find(
      ({ implementation }) => implementation === losingAuthor,
    );
    const losingBeforeAck = rollback.observations.find(
      ({ implementation }) => implementation === losingAuthor,
    );
    const reconciledPending = losingBeforeAck?.history?.pending?.find(
      ({ changeset }) => changeset?.changeCount === 0,
    );
    assert(reconciledPending, `${cell.id} lacks an empty losing changeset`);
    if (cell.family === "schema-schema") {
      assert(reconciledPending, `${cell.id} lacks the losing empty outer change`);
    }
    const losingSubmission = submissions.find(({ clientId }) =>
      adapters[losingAuthor].clientIds.has(clientId));
    assert(losingSubmission, `${cell.id} lacks the losing submission identity`);
    const losingCommit = losingSubmission.commits[0];
    const originalPending = optimistic.observations.find(
      ({ implementation }) => implementation === losingAuthor,
    )?.history?.pending?.find(({ originatorId, changeset }) =>
      originatorId === losingCommit.originatorId
      && changeset?.changeCount > 0);
    assert(originalPending, `${cell.id} lacks the original losing pending change`);
    const intermediateRollback =
      losingBeforeAck.pendingTreeCount > 0
      && losingSettled?.pendingTreeCount === 0;
    assert.equal(intermediateRollback, true,
      `${cell.id} lacks rollback evidence before acknowledgement`);
    assert.equal(oldViewRejected, true, `${cell.id} did not invalidate the old view`);
    const notifications = notificationEvidence([optimistic, ...polling, final]);
    assert(Object.values(notifications).some(({ schema }) => schema.length > 0),
      `${cell.id} lacks schema notification evidence`);
    if (cell.family === "schema-data") {
      assert(Object.values(notifications).some(({ data }) => data.length > 0),
        `${cell.id} lacks data notification evidence`);
    }
    return {
      ...cell,
      documentId: environment.documentId,
      instanceIds: Object.fromEntries(implementations.map((target) =>
        [target, adapters[target].instanceId])),
      skipped: false,
      observations: [{
        before,
        optimistic,
        rollback,
        final,
        compatibility,
        submissions,
        losingAuthor,
        losingSubmission,
        originalPending,
        reconciledPending,
        notifications,
        sequenceNumbers,
        referenceSequenceNumbers,
        intermediateRollback,
        oldViewRejected,
        documentHealthy: true,
      }],
    };
  } catch (error) {
    failure = error;
    throw error;
  } finally {
    await cleanupSchemaEnvironment(environment, failure);
  }
}

async function runSchemaRaceCell(config, context, cell) {
  return cell.family === "upgrade-then-edit"
    ? runCausalSchemaRace(config, context, cell)
    : runConcurrentSchemaRace(config, context, cell);
}

export async function runSchemaRaces(config, context, {
  runCell = runSchemaRaceCell,
} = {}) {
  const results = [];
  for (const cell of schemaRaceCells) {
    results.push(await runCell(config, context, structuredClone(cell)));
  }
  return results;
}

async function runSchemaReconnectTarget(config, context, target) {
  const observations = [];
  for (const acceptedBeforeDrop of [false, true]) {
    const environment = await schemaEnvironment(config, context);
    let failure;
    try {
      const adapter = environment.adapters[target];
      const historyBeforeChanges = await serverHistory(environment.creator);
      const baselineSequenceNumber =
        historyBeforeChanges.at(-1)?.sequenceNumber ?? 0;
      await adapter.holdInbound();
      await adapter.holdOutbound();
      const before = await adapter.checkpoint();
      await adapter.schemaUpgrade("optional");
      await adapter.openView("optional");
      await adapter.set(["score"], acceptedBeforeDrop ? 82 : 81);
      const pending = await adapter.checkpoint();
      assert(pending.pendingTreeCount >= 2,
        `${target} reconnect upgrade and dependent data were not pending`);
      assert(pending.history?.pending?.length >= 2,
        `${target} reconnect lacks original pending history`);
      const originalRevisions = pending.history.pending.map(({ revision }) => revision);
      const originatorIds = [...new Set(pending.history.pending.map(
        ({ originatorId }) => originatorId,
      ))];
      assert.equal(originatorIds.length, 1,
        `${target} reconnect lacks one pending operation originator`);
      const finalScore = 81 + Number(acceptedBeforeDrop);
      const originalOperations = pending.history.pending.map((commit) => ({
        revision: commit.revision,
        originatorId: commit.originatorId,
        payload: commit.changeset.payload ?? commit.changeset.raw,
      }));
      let acceptedSequenceNumber = null;
      if (acceptedBeforeDrop) {
        await adapter.releaseOutbound({ order: "fifo", duplicate: false });
        const accepted = await waitForAuthorSubmission(
          environment.creator,
          environment.adapters,
          target,
          baselineSequenceNumber,
          2,
        );
        acceptedSequenceNumber = accepted.outerSequenceNumber;
      }
      await adapter.disconnect();
      if (target === "upstream") {
        await adapter.releaseInbound({ order: "fifo", duplicate: false });
      }
      await adapter.reconnect();
      if (target === "upstream" && !acceptedBeforeDrop) {
        await adapter.releaseOutbound({ order: "fifo", duplicate: false });
      }
      await Promise.all(implementations.map((implementation) =>
        environment.adapters[implementation].awaitSynced()));
      await openSchemaView(environment.adapters, "optional");
      const final = await settle(environment.adapters);
      const rawHistory = await serverHistory(environment.creator);
      const history = decodeTreeSubmissions(rawHistory);
      const acceptedSubmissions = history.filter(
        ({ outerSequenceNumber, clientId }) =>
          outerSequenceNumber > baselineSequenceNumber
          && adapter.clientIds.has(clientId),
      );
      const acceptedCommits = acceptedSubmissions.flatMap(
        ({ outerSequenceNumber, commits }) => commits.map((commit) => ({
          outerSequenceNumber,
          revision: commit.revision,
          originatorId: commit.originatorId,
          kinds: commitKinds(commit),
          changeset: commit.changeset,
        })),
      );
      assert(acceptedCommits.some(({ kinds }) => kinds.includes("schema")),
        `${target} reconnect did not accept the upgrade`);
      assert(acceptedCommits.some(({ kinds }) => kinds.includes("data")),
        `${target} reconnect did not accept dependent data: ${JSON.stringify({
          originalRevisions,
          knownClientIds: [...adapter.clientIds],
          submissionsAfterBaseline: history.filter(
            ({ outerSequenceNumber }) => outerSequenceNumber > baselineSequenceNumber,
          ),
          rawMessagesAfterBaseline: rawHistory.filter(
            ({ sequenceNumber }) => sequenceNumber > baselineSequenceNumber,
          ),
          acceptedSubmissions,
          acceptedCommits,
          final: final.observations.map(
            ({ implementation, pendingTreeCount, wholeTree }) =>
              ({ implementation, pendingTreeCount, wholeTree }),
          ),
        })}`);
      const acceptedOperations = acceptedCommits.map((commit) => ({
        ...commit,
        payload: commit.changeset,
      }));
      const acceptedMappings = matchReconnectOperations(
        originalOperations,
        acceptedOperations,
      );
      const schemaIndex = acceptedCommits.findIndex(({ kinds }) => kinds.includes("schema"));
      const dataIndex = acceptedCommits.findIndex(({ kinds }) => kinds.includes("data"));
      assert(schemaIndex >= 0 && dataIndex > schemaIndex,
        `${target} reconnect replayed dependent data before its upgrade`);
      assert(final.observations.every(({ wholeTree }) =>
        wholeTree.value.fields.some(([name, field]) =>
          name === "score" && field.value === finalScore)),
      `${target} reconnect did not converge dependent data on every client`);
      observations.push({
        caseId: acceptedBeforeDrop
          ? "upgrade-accepted-before-drop"
          : "upgrade-unacknowledged",
        documentId: environment.documentId,
        instanceId: adapter.instanceId,
        acceptedBeforeDrop,
        acceptedSequenceNumber,
        pendingTreeCount: pending.pendingTreeCount,
        originalRevisions,
        originalOperations,
        acceptedCommits,
        acceptedMappings,
        orderedReplay: true,
        exactlyOnce: true,
        allClientsObservedDependentData: true,
        before,
        pending,
        final,
      });
    } catch (error) {
      failure = error;
      throw error;
    } finally {
      await cleanupSchemaEnvironment(environment, failure);
    }
  }
  return {
    target,
    skipped: false,
    observations,
  };
}

export async function runSchemaReconnect(config, context, {
  runTarget = runSchemaReconnectTarget,
} = {}) {
  const results = [];
  for (const target of implementations) {
    results.push(await runTarget(config, context, target));
  }
  return results;
}

export async function publishUpstreamSummary(
  config,
  containers,
  documentId,
  reason,
  options,
) {
  const summarizer = await openSession(config, containers, documentId, true, options);
  assert(summarizer.data.ISummarizer, "Missing upstream summarizer");
  const result = summarizer.data.ISummarizer.summarizeOnDemand({ reason, fullTree: true });
  const submitted = await result.summarySubmitted;
  assert(submitted.success, `Summary submission failed: ${submitted.error}`);
  const broadcast = await result.summaryOpBroadcasted;
  assert(broadcast.success, `Summary broadcast failed: ${broadcast.error}`);
  const acknowledged = await result.receivedSummaryAckOrNack;
  assert(acknowledged.success, `Summary acknowledgement failed: ${acknowledged.error}`);
  return {
    ...acknowledged.data,
    summarizeOp: broadcast.data.summarizeOp,
    summaryReferenceSequenceNumber: submitted.data.referenceSequenceNumber,
  };
}

function safeName(value) {
  return value.replace(/[^a-z0-9._-]+/gi, "_");
}

function measuredPayload(item) {
  return {
    id: item.id,
    documentId: item.documentId,
    instanceIds: item.instanceIds,
    authorCoverage: item.authorCoverage,
    checkpoints: item.checkpoints,
    evidence: item.evidence,
  };
}

async function writeArtifact(context, item, raw) {
  const relative = `deterministic/${safeName(item.id)}.json`;
  const path = join(context.artifactDirectory, relative);
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, `${JSON.stringify({
    formatVersion: 1,
    runId: context.runId,
    profileDigest: context.profileDigest,
    kind: "deterministic",
    subject: item.id,
    documentId: item.documentId,
    measured: measuredPayload(item),
    raw,
  })}\n`, { mode: 0o600 });
  return relative;
}

async function collectCheckpointObservations(label, stage, adapters) {
  const entries = Object.entries(adapters);
  const settled = await Promise.allSettled(
    entries.map(([, adapter]) => adapter.checkpoint()),
  );
  const observations = [];
  const clientErrors = [];
  for (const [index, result] of settled.entries()) {
    const implementation = entries[index][0];
    if (result.status === "fulfilled") {
      observations.push(result.value);
      continue;
    }
    clientErrors.push({ implementation, error: result.reason });
    const partial = result.reason?.checkpoint;
    if (Array.isArray(partial?.observations)) {
      observations.push(...partial.observations);
    } else if (partial !== undefined) {
      observations.push(partial);
    }
  }
  return {
    checkpoint: { label, stage, observations },
    clientErrors,
  };
}

async function captureCheckpoint(label, stage, adapters) {
  const collected = await collectCheckpointObservations(label, stage, adapters);
  if (collected.clientErrors.length > 0) {
    const primary = collected.clientErrors[0].error;
    primary.checkpoint = collected.checkpoint;
    primary.clientErrors = collected.clientErrors;
    throw primary;
  }
  return collected.checkpoint;
}

export function mergeCheckpoints(label, stage, ...checkpoints) {
  return {
    label,
    stage,
    observations: checkpoints.flatMap(
      (checkpoint) => checkpoint?.observations ?? [],
    ),
  };
}

export async function captureFailureCheckpoint(
  label,
  stage,
  adapters,
  priorCheckpoint,
) {
  const collected = await collectCheckpointObservations(label, stage, adapters);
  return {
    checkpoint: mergeCheckpoints(
      label,
      stage,
      priorCheckpoint,
      collected.checkpoint,
    ),
    errors: collected.clientErrors.map(({ error }) => error),
    clientErrors: collected.clientErrors,
  };
}

export function preserveFailureCheckpoints(error, drainCheckpoint) {
  const primaryCheckpoint = error.checkpoint ?? null;
  error.primaryCheckpoint = primaryCheckpoint;
  error.drainCheckpoint = drainCheckpoint;
  return { primaryCheckpoint, drainCheckpoint };
}

export async function settle(adapters) {
  let observations;
  const events = Object.fromEntries(implementations.map((implementation) => [implementation, []]));
  const commits = Object.fromEntries(
    implementations.map((implementation) => [implementation, []]),
  );
  const observe = async () => {
    const captured = await captureCheckpoint("settled", "collecting", adapters);
    observations = captured.observations.map((observation) => {
      events[observation.implementation].push(...observation.events);
      commits[observation.implementation].push(...(observation.commits ?? []));
      return {
        ...observation,
        events: [...events[observation.implementation]],
        commits: [...commits[observation.implementation]],
      };
    });
  };
  try {
    await until(async () => {
      await observe();
      const watermark = Math.max(...observations.map(({ sequenceNumber }) => sequenceNumber));
      await Promise.all(implementations.map((implementation) =>
        adapters[implementation].awaitSynced(watermark)));
      await observe();
      const [first, ...rest] = observations;
      return rest.every(({ sequenceNumber, wholeTree }) =>
        sequenceNumber === first.sequenceNumber
          && JSON.stringify(wholeTree) === JSON.stringify(first.wholeTree))
        && observations.every(({ pendingTreeCount, inflightSubmissionCount }) =>
          pendingTreeCount === 0 && inflightSubmissionCount === 0);
    }, "three-client quiescence", 60_000);
  } catch (error) {
    error.checkpoint = mergeCheckpoints(
      "settled",
      "failed",
      observations === undefined ? undefined : { observations },
      error.checkpoint,
    );
    throw error;
  }
  return { label: "settled", stage: "quiescent", observations };
}

function measuredRemoteObservers(checkpoints, authors) {
  return implementations.filter((implementation) =>
    !authors.includes(implementation)
    && checkpoints.slice(1).some(({ observations }) => observations.some((observation) =>
      observation.implementation === implementation
      && observation.events.some((event) =>
        implementation === "upstream" || event.local === false))));
}

function measuredLocalAuthors(checkpoints, authors) {
  return authors.filter((author) => checkpoints.some(
    ({ stage, observations }) => stage === "intermediate"
      && observations.some(({ implementation, events }) =>
        implementation === author
        && events.some((event) => author === "upstream" || event.local === true)),
  ));
}

async function waitForLocalNotifications(adapters, checkpoints, authors) {
  let observed = measuredLocalAuthors(checkpoints, authors);
  await until(async () => {
    if (observed.length === authors.length) return true;
    checkpoints.push(await captureCheckpoint(
      "local-notifications",
      "intermediate",
      adapters,
    ));
    observed = measuredLocalAuthors(checkpoints, authors);
    return observed.length === authors.length;
  }, "map local notifications", 5_000);
  return observed;
}

export async function waitForRemoteNotifications(
  adapters,
  checkpoints,
  authors,
  milliseconds = 5_000,
) {
  const expected = implementations.filter(
    (implementation) => !authors.includes(implementation),
  );
  let observers = measuredRemoteObservers(checkpoints, authors);
  if (observers.length === expected.length) return observers;
  await until(async () => {
    const checkpoint = await settle(adapters);
    checkpoint.label = `notification-drain-${checkpoints.length}`;
    checkpoints.push(checkpoint);
    observers = measuredRemoteObservers(checkpoints, authors);
    return observers.length === expected.length;
  }, "remote tree notifications", milliseconds);
  return observers;
}

function authorForClient(adapters, clientId) {
  return implementations.find((implementation) =>
    adapters[implementation].clientIds.has(clientId));
}

export function decodedEvidence(history, adapters, authors) {
  const decoded = decodeTreeSubmissions(history);
  const submissions = decoded.flatMap((outer) => {
    const author = authorForClient(adapters, outer.clientId);
    if (!authors.includes(author)) return [];
    return outer.commits.map((commit) => ({
      author,
      outerSequenceNumber: outer.outerSequenceNumber,
      innerIndex: commit.innerIndex,
      referenceSequenceNumber: outer.referenceSequenceNumber,
      ...(outer.batchId === undefined ? {} : { batchId: outer.batchId }),
      revision: commit.revision,
      originatorId: commit.originatorId,
      allocations: outer.allocations,
    }));
  });
  assert.deepEqual([...new Set(submissions.map(({ author }) => author))].sort(),
    [...authors].sort(), "Not every required author produced a tree submission");
  return { decoded, submissions };
}

export async function waitForAuthorSubmission(
  session,
  adapters,
  author,
  afterSequence,
  minimumCommits = 1,
) {
  const deadline = Date.now() + 30_000;
  let decoded = [];
  let history = [];
  for (;;) {
    history = await serverHistory(session);
    decoded = decodeTreeSubmissions(history);
    const submissions = decoded.filter((outer) =>
      outer.outerSequenceNumber > afterSequence
      && adapters[author].clientIds.has(outer.clientId)
      && outer.commits.length > 0);
    let count = 0;
    for (const submission of submissions) {
      count += submission.commits.length;
      if (count >= minimumCommits) return submission;
    }
    if (Date.now() >= deadline) {
      assert.fail(`${author} sequenced submission missing after ${afterSequence}; `
        + `known=${JSON.stringify([...adapters[author].clientIds])}; `
        + `history=${JSON.stringify(history.map(({ sequenceNumber, clientId, type,
          contents }) => ({
          sequenceNumber,
          clientId,
          type,
          outerType: parsed(contents)?.type,
        })))}; `
        + (author === "upstream"
          ? `queue=${JSON.stringify({
            paused: adapters.upstream.session.container.deltaManager.outbound.paused,
            length: adapters.upstream.session.container.deltaManager.outbound.length,
            dirty: adapters.upstream.session.container.isDirty,
            lastSequenceNumber:
              adapters.upstream.session.container.deltaManager.lastSequenceNumber,
            connectionEvents: adapters.upstream.connectionEvents,
          })}; `
          : "")
        + `decoded=${JSON.stringify(decoded.map(({ outerSequenceNumber, clientId,
          referenceSequenceNumber, commits }) => ({
          outerSequenceNumber,
          clientId,
          referenceSequenceNumber,
          revisions: commits.map(({ revision }) => revision),
        })))}`);
    }
    await delay(25);
  }
}

function firstAuthor(cell) {
  return cell.order === null
    ? cell.authors[0]
    : cell.order.slice(0, -"-first".length);
}

function otherAuthor(cell) {
  const first = firstAuthor(cell);
  return cell.authors.find((author) => author !== first);
}

async function concurrentEdits(cell, adapters, upstream, actions) {
  const baseline = (await captureCheckpoint(
    "concurrent-baseline",
    "intermediate",
    Object.fromEntries(cell.authors.map((author) => [author, adapters[author]])),
  )).observations;
  await Promise.all(cell.authors.flatMap((author) => [
    adapters[author].holdInbound(),
    adapters[author].holdOutbound(),
  ]));
  for (const author of cell.authors) await actions[author]();
  const intermediate = await captureCheckpoint("optimistic", "intermediate", adapters);
  for (const author of cell.authors) {
    const observation = intermediate.observations.find(
      ({ implementation }) => implementation === author,
    );
    assert(observation.pendingTreeCount > 0,
      `${cell.id}: ${author} lacks pending optimistic state`);
  }
  const order = [firstAuthor(cell), otherAuthor(cell)];
  const sequenced = [];
  for (const author of order) {
    await adapters[author].releaseOutbound();
    sequenced.push(await waitForAuthorSubmission(
      upstream.session,
      adapters,
      author,
      baseline.find(({ implementation }) => implementation === author).sequenceNumber,
    ));
  }
  await Promise.all(cell.authors.map((author) => adapters[author].releaseInbound()));
  const settled = await settle(adapters);
  return {
    checkpoints: [intermediate, settled],
    authoredPrefixes: baseline.map(({ implementation, sequenceNumber }) => ({
      author: implementation,
      referenceSequenceNumber: sequenceNumber,
    })),
    sequenced,
  };
}

export function refresherValues(commit) {
  const pending = [commit.changeset];
  while (pending.length > 0) {
    const current = pending.pop();
    if (Array.isArray(current)) {
      pending.push(...current);
    } else if (current && typeof current === "object") {
      if (current.refreshers?.builds?.length === 1) {
        const point = current.refreshers.trees.data?.[0]?.[1];
        const fields = point?.[3];
        if (fields?.[0] === "x" && fields?.[2] === "y") {
          return [fields[1]?.[3], fields[3]?.[3]];
        }
      }
      pending.push(...Object.values(current));
    }
  }
  return undefined;
}

async function retainedEvidence(config, containers, documentId, upstream, nativeWriter) {
  if (nativeWriter) await nativeWriter.summarize();
  else await publishUpstreamSummary(config, containers, documentId, "Task 3 retained state");
  const fresh = await openSession(config, containers, documentId, false, {
    cache: false,
    observeStorage: true,
  });
  const removed = fresh.data.tree.contentSnapshot().removed;
  assert(removed.length > 0, "Published retained state has no removed content");
  fresh.data.view.root.title = `continued-${randomUUID()}`;
  await until(() => upstream.session.data.view.root.title === fresh.data.view.root.title,
    "retained-state continuation");
  return {
    removed,
    storageObservations: fresh.storageObservations,
    summaryConsumed: fresh.storageObservations.length > 0,
    continuationObserved: true,
  };
}

async function runCell(config, context, cell) {
  const containers = [];
  const natives = [];
  let scenarioError;
  try {
    const creator = await openSession(config, containers);
    const documentId = creator.container.resolvedUrl.id;
    if (["parent-replacement-child-edit", "detached-child-reconciliation"]
      .includes(cell.family)) {
      creator.data.view.root.point = { x: 1, y: 2 };
      await until(() => !creator.container.isDirty, `${cell.id} initial point`);
    }
    if (cell.family === "optional-set-clear"
      && cell.variation !== "absent-clear"
      && cell.variation !== "re-add") {
      creator.data.view.root.note = "seed";
      await until(() => !creator.container.isDirty, `${cell.id} initial note`);
    }
    await publishUpstreamSummary(config, containers, documentId, `Task 3 ${cell.id} bootstrap`);
    const upstream = upstreamAdapter(await openSession(config, containers, documentId));
    const { jwt } = await tokenProvider(config).fetchOrdererToken(config.tenantId, documentId);
    for (const target of nativeTargets) {
      natives.push(await nativeAdapter(target, config, {
        runId: context.runId,
        documentId,
        tenant: config.tenantId,
        viewSchema: identifierRefusalCases.has(cell.caseId)
          ? context.identifierViewSchema
          : context.viewSchema,
      }, jwt));
    }
    const adapters = {
      upstream,
      javascript: natives[0],
      erlang: natives[1],
    };
    await Promise.all(nativeTargets.map((target) => adapters[target].awaitSynced()));
    const initial = await settle(adapters);
    initial.label = "initial";
    let checkpoints = [initial];
    let authoredPrefixes = [];
    let retained;
    let delivery;
    let sessions;
    let grouped;
    const raw = {};

    if (["independent-scalar", "independent-nested", "same-field",
      "optional-set-clear", "parent-replacement-child-edit"].includes(cell.family)
      && cell.authors.length === 2) {
      const [left, right] = cell.authors;
      const oldPoint = cell.family === "parent-replacement-child-edit"
        ? upstream.session.data.view.root.point : undefined;
      const actions = {
        [left]: async () => {
          if (cell.family === "independent-scalar") {
            await adapters[left].set(["title"], `${left}-title`);
          } else if (cell.family === "independent-nested") {
            await adapters[left].set(["point", "x"], 11);
          } else if (cell.family === "same-field") {
            await adapters[left].set(["title"], `${left}-wins-if-later`);
          } else if (cell.family === "optional-set-clear") {
            await adapters[left].set(["note"], `${left}-note`);
          } else {
            await adapters[left].set(["point"], { x: 3, y: 4 });
          }
        },
        [right]: async () => {
          if (cell.family === "independent-scalar") {
            await adapters[right].set(["enabled"], true);
          } else if (cell.family === "independent-nested") {
            await adapters[right].set(["point", "y"], 22);
          } else if (cell.family === "same-field") {
            await adapters[right].set(["title"], `${right}-wins-if-later`);
          } else if (cell.family === "optional-set-clear") {
            await adapters[right].clear(["note"]);
          } else {
            await adapters[right].set(["point", "x"], 42);
          }
        },
      };
      const result = await concurrentEdits(cell, adapters, upstream, actions);
      checkpoints.push(...result.checkpoints);
      authoredPrefixes = result.authoredPrefixes;
      if (cell.family === "parent-replacement-child-edit") {
        const extra = await retainedEvidence(config, containers, documentId, upstream);
        retained = {
          upstreamReference: {
            before: { x: 1, y: 2 },
            after: { x: oldPoint.x, y: oldPoint.y },
          },
          ...extra,
          refreshers: [],
        };
      }
    } else if (cell.family === "detached-child-reconciliation") {
      const author = cell.authors[0];
      const baseline = await adapters[author].checkpoint();
      authoredPrefixes = [{
        author,
        referenceSequenceNumber: baseline.sequenceNumber,
      }];
      const oldPoint = upstream.session.data.view.root.point;
      if (author === "upstream") {
        const replacer = adapters.javascript;
        await Promise.all([
          adapters.upstream.holdInbound(),
          adapters.upstream.holdOutbound(),
        ]);
        oldPoint.x = 42;
        oldPoint.y = 7;
        let upstreamObservation;
        await until(async () => {
          upstreamObservation = await adapters.upstream.checkpoint();
          return upstreamObservation.pendingTreeCount > 0
            || upstreamObservation.inflightSubmissionCount > 0;
        }, "upstream retained edit queue");
        checkpoints.push({
          label: "two-retained-child-edits",
          stage: "intermediate",
          observations: [
            upstreamObservation,
            ...(await captureCheckpoint(
              "two-retained-child-edits-native",
              "intermediate",
              Object.fromEntries(nativeTargets.map((implementation) =>
                [implementation, adapters[implementation]])),
            )).observations,
          ],
        });
        const optimistic = checkpoints.at(-1).observations.find(
          ({ implementation }) => implementation === author,
        );
        assert(optimistic.pendingTreeCount > 0
          || optimistic.inflightSubmissionCount > 0,
        "Upstream retained edit did not remain pending");
        await replacer.set(["point"], { x: 3, y: 4 });
        await replacer.awaitSynced();
        await adapters.upstream.releaseOutbound();
        await adapters.upstream.releaseInbound();
      } else {
        await Promise.all([
          adapters[author].holdInbound(),
          adapters[author].holdOutbound(),
        ]);
        await adapters[author].set(["point", "x"], 42);
        await adapters[author].set(["point", "y"], 7);
        checkpoints.push(await captureCheckpoint(
          "two-stale-child-edits",
          "intermediate",
          adapters,
        ));
        assert.equal(checkpoints.at(-1).observations.find(
          ({ implementation }) => implementation === author,
        ).pendingTreeCount, 2, "Native detached case requires two pending child edits");
        await adapters.upstream.set(["point"], { x: 3, y: 4 });
        await adapters.upstream.awaitSynced();
        await adapters[author].reconnect();
      }
      checkpoints.push(await settle(adapters));
      const beforeSummary = await serverHistory(creator);
      const decodedBeforeSummary = decodeTreeSubmissions(beforeSummary);
      const authorCommits = decodedBeforeSummary
        .filter(({ clientId }) => adapters[author].clientIds.has(clientId))
        .flatMap(({ commits }) => commits);
      const refreshers = authorCommits.map(refresherValues).filter(Boolean);
      const extra = await retainedEvidence(
        config,
        containers,
        documentId,
        upstream,
        author === "upstream" ? undefined : adapters[author],
      );
      retained = {
        upstreamReference: {
          before: { x: 1, y: 2 },
          after: { x: oldPoint.x, y: oldPoint.y },
        },
        ...extra,
        refreshers,
      };
      if (author !== "upstream") {
        assert.deepEqual(refreshers, [[1, 2], [42, 2]],
          "Native detached refreshers differ from the pinned upstream history");
      }
    } else if (cell.family === "several-pending-edits") {
      const author = cell.authors[0];
      const observer = implementations.find((implementation) => implementation !== author);
      const baseline = await adapters[author].checkpoint();
      authoredPrefixes = [{
        author,
        referenceSequenceNumber: baseline.sequenceNumber,
      }];
      await adapters[author].holdInbound();
      await adapters[author].holdOutbound();
      await adapters[author].set(["title"], `${author}-accepted-prefix`);
      await adapters[author].releaseOutbound();
      await waitForAuthorSubmission(creator, adapters, author, baseline.sequenceNumber);
      await adapters[author].holdOutbound();
      await adapters[author].set(["note"], `${author}-suffix`);
      await adapters[author].set(["rating"], 77);
      await adapters[observer].set(["enabled"], true);
      checkpoints.push(await captureCheckpoint(
        "accepted-prefix-unsent-suffix",
        "intermediate",
        adapters,
      ));
      assert(checkpoints.at(-1).observations.find(
        ({ implementation }) => implementation === author,
      ).pendingTreeCount >= 3, "Several-pending case lacks three local commits");
      await adapters[author].releaseOutbound();
      await adapters[author].releaseInbound();
      checkpoints.push(await settle(adapters));
    } else if (cell.family === "grouped-commits") {
      const author = cell.authors[0];
      const baseline = await adapters[author].checkpoint();
      authoredPrefixes = [{
        author,
        referenceSequenceNumber: baseline.sequenceNumber,
      }];
      await Promise.all([
        adapters[author].holdInbound(),
        adapters[author].holdOutbound(),
      ]);
      if (author === "upstream") {
        upstream.session.runtime.orderSequentially(() => {
          upstream.session.data.view.root.title = "grouped";
          upstream.session.data.view.root.enabled = true;
          upstream.session.data.view.root.rating = 3;
        });
      } else {
        await adapters[author].set(["title"], "native-grouped");
        await adapters[author].set(["enabled"], true);
        await adapters[author].set(["rating"], 3);
      }
      checkpoints.push(await captureCheckpoint("grouped-local", "intermediate", adapters));
      assert(checkpoints.at(-1).observations.find(
        ({ implementation }) => implementation === author,
      ).pendingTreeCount >= 3, "Grouped case lacks three pending commits");
      await adapters[author].releaseOutbound();
      await adapters[author].releaseInbound();
      checkpoints.push(await settle(adapters));
    } else if (cell.family === "delivery-duplicates-gaps") {
      const receiver = cell.authors[0];
      const baseline = await adapters[receiver].checkpoint();
      authoredPrefixes = [{
        author: receiver,
        referenceSequenceNumber: baseline.sequenceNumber,
      }];
      await adapters[receiver].holdOutbound();
      await adapters[receiver].set(["rating"], 5);
      checkpoints.push(await captureCheckpoint(
        "receiver-allocation-pending",
        "intermediate",
        adapters,
      ));
      await adapters[receiver].releaseOutbound();
      await settle(adapters);
      await adapters[receiver].checkpoint();
      await adapters[receiver].holdInbound();
      const senders = implementations.filter((implementation) => implementation !== receiver);
      await adapters[senders[0]].set(["title"], "gap-first");
      await adapters[senders[0]].awaitSynced();
      await adapters[senders[1]].set(["note"], "gap-second");
      await adapters[senders[1]].awaitSynced();
      await until(() => adapters[receiver].evidence().held
        .filter(({ direction, kind }) => direction === "inbound" && kind === "op")
        .length >= 2, "two held receiver frames");
      const beforeRelease = adapters[receiver].evidence();
      const allocationsBefore = decodeTreeSubmissions(await serverHistory(creator))
        .filter(({ clientId }) => adapters[receiver].clientIds.has(clientId))
        .flatMap(({ allocations }) => allocations).length;
      let originalCheckpoint;
      await adapters[receiver].releaseInbound({
        order: "reverse",
        duplicate: true,
        beforeDuplicate: async () => {
          originalCheckpoint = await settle(adapters);
          originalCheckpoint.label = "before-duplicate";
          checkpoints.push(originalCheckpoint);
          const receiverEvents = originalCheckpoint.observations.find(
            ({ implementation }) => implementation === receiver,
          ).events;
          assert.equal(receiverEvents.length, 2,
            "Original gap-repaired operations did not emit exactly two invalidations");
        },
      });
      assert(originalCheckpoint, "Duplicate delivery lacks a pre-duplicate barrier");
      await adapters[senders[0]].set(["enabled"], true);
      await adapters[senders[0]].awaitSynced();
      checkpoints.push(await settle(adapters));
      const afterRelease = await waitForGapRepair(
        adapters[receiver],
        beforeRelease.repairRequests.length,
      );
      const duplicate = afterRelease.delivered.find(({ duplicate }) => duplicate);
      assert(duplicate, "Delivery case did not duplicate an applied frame");
      const held = beforeRelease.held.filter(
        ({ direction, kind }) => direction === "inbound" && kind === "op",
      );
      const delivered = afterRelease.delivered.filter(
        ({ direction, kind }) => direction === "inbound" && kind === "op",
      );
      const finalReceiver = checkpoints.at(-1).observations.find(
        ({ implementation }) => implementation === receiver,
      );
      const allocationsAfter = decodeTreeSubmissions(await serverHistory(creator))
        .filter(({ clientId }) => adapters[receiver].clientIds.has(clientId))
        .flatMap(({ allocations }) => allocations).length;
      delivery = {
        heldSequenceNumbers: held.flatMap(({ sequenceNumbers }) => sequenceNumbers),
        deliveredSequenceNumbers: delivered.flatMap(
          ({ sequenceNumbers }) => sequenceNumbers,
        ),
        duplicateSequenceNumber: duplicate.sequenceNumbers.at(-1),
        repairRequests: afterRelease.repairRequests.slice(beforeRelease.repairRequests.length),
        gapRepairObserved: afterRelease.repairRequests.length > beforeRelease.repairRequests.length,
        duplicateInvalidations: finalReceiver.events.length - 1,
        duplicateAllocations: allocationsAfter - allocationsBefore,
      };
      assert.equal(delivery.duplicateInvalidations, 0,
        "Duplicate delivery caused a visible invalidation");
      assert.equal(delivery.gapRepairObserved, true,
        "Out-of-order delivery did not produce a measured gap-repair request");
      assert.equal(delivery.duplicateAllocations, 0,
        "Duplicate delivery caused an ID allocation");
    } else if (cell.family === "multi-session-ids") {
      const baseline = (await captureCheckpoint(
        "multi-session-baseline",
        "intermediate",
        adapters,
      )).observations;
      authoredPrefixes = baseline.map(({ implementation, sequenceNumber }) => ({
        author: implementation,
        referenceSequenceNumber: sequenceNumber,
      }));
      await Promise.all(implementations.flatMap((implementation) => [
        adapters[implementation].holdInbound(),
        adapters[implementation].holdOutbound(),
      ]));
      await adapters.upstream.set(["title"], "multi-upstream");
      await adapters.javascript.set(["enabled"], true);
      await adapters.erlang.set(["rating"], 9);
      checkpoints.push(await captureCheckpoint("multi-session-pending", "intermediate", adapters));
      assert(checkpoints.at(-1).observations.every(({ pendingTreeCount }) =>
        pendingTreeCount > 0), "Multi-session case lacks three pending authors");
      for (const implementation of implementations) {
        await adapters[implementation].releaseOutbound();
      }
      for (const implementation of implementations) {
        await adapters[implementation].releaseInbound();
      }
      await settle(adapters);
      const beforeReconnect = (await captureCheckpoint(
        "multi-session-before-reconnect",
        "intermediate",
        adapters,
      )).observations;
      const historyBefore = decodeTreeSubmissions(await serverHistory(creator));
      await Promise.all(implementations.map((implementation) =>
        adapters[implementation].reconnect()));
      await adapters.upstream.set(["title"], "multi-upstream-restored");
      await adapters.javascript.set(["enabled"], false);
      await adapters.erlang.set(["rating"], 10);
      checkpoints.push(await settle(adapters));
      const historyAfter = decodeTreeSubmissions(await serverHistory(creator));
      sessions = implementations.map((implementation) => {
        const beforeIds = new Set(adapters[implementation].clientIds);
        const before = beforeReconnect.find(
          ({ implementation: name }) => name === implementation,
        ).clientId;
        const after = checkpoints.at(-1).observations.find(
          ({ implementation: name }) => name === implementation,
        ).clientId;
        const first = historyBefore.find(({ clientId }) => beforeIds.has(clientId));
        const last = historyAfter.findLast(({ clientId }) => beforeIds.has(clientId));
        assert(first && last, `${implementation} lacks session identity evidence`);
        assert.equal(first.commits[0].originatorId, last.commits[0].originatorId,
          `${implementation} did not restore its compressor session`);
        return {
          implementation,
          before,
          after,
          restored: first.commits[0].originatorId,
          restoredAfter: last.commits[0].originatorId,
        };
      });
      await publishUpstreamSummary(config, containers, documentId, "Task 3 multi-session IDs");
      const restored = await openSession(config, containers, documentId, false, { cache: false });
      assert.deepEqual(canonicalValue(rootValue(restored.data.view.root)),
        checkpoints.at(-1).observations[0].wholeTree,
      "Multi-session publication restored another root");
    } else {
      const author = cell.authors[0];
      const baseline = await adapters[author].checkpoint();
      authoredPrefixes = [{
        author,
        referenceSequenceNumber: baseline.sequenceNumber,
      }];
      await Promise.all([
        adapters[author].holdInbound(),
        adapters[author].holdOutbound(),
      ]);
      if (cell.family === "optional-set-clear") {
        if (cell.variation === "repeated-clear") {
          await adapters[author].clear(["note"]);
          await adapters[author].clear(["note"]);
          await adapters[author].set(["title"], "repeated-clear");
        } else if (cell.variation === "absent-clear") {
          await adapters[author].clear(["note"]);
          await adapters[author].set(["title"], "absent-clear");
        } else {
          await adapters[author].set(["note"], "first");
          await adapters[author].clear(["note"]);
          await adapters[author].set(["note"], "second");
        }
      } else if (cell.family === "null-absence") {
        await adapters[author].set(["title"], "null-absence");
        await adapters[author].set(["marker"], null);
        await adapters[author].clear(["note"]);
      } else {
        await adapters[author].set(["title"], "");
        await adapters[author].set(["note"], "supplementary-\u{1F642}");
        await adapters[author].set(["rating"], Number.MAX_VALUE);
      }
      checkpoints.push(await captureCheckpoint(`${cell.family}-pending`, "intermediate", adapters));
      await adapters[author].releaseOutbound();
      await adapters[author].releaseInbound();
      checkpoints.push(await settle(adapters));
      if (cell.family === "null-absence") {
        const fields = checkpoints.at(-1).observations[0].wholeTree.value.fields;
        assert.deepEqual(fields.find(([name]) => name === "marker")?.[1], { kind: "null" });
        assert.equal(fields.some(([name]) => name === "note"), false);
      }
    }

    const finalHistory = await serverHistory(creator);
    const decoded = decodedEvidence(finalHistory, adapters, cell.authors);
    if (cell.family === "grouped-commits") {
      const authored = decoded.decoded.filter(({ clientId }) =>
        adapters[cell.authors[0]].clientIds.has(clientId));
      const selected = cell.authors[0] === "upstream"
        ? authored.find(({ commits }) => commits.length >= 3)
        : authored.find(({ allocations, commits }) =>
          allocations.length > 0 && commits.length > 0);
      assert(selected, "Grouped case lacks the required wire batch");
      grouped = {
        outerSequenceNumber: selected.outerSequenceNumber,
        commits: selected.commits.map(({ innerIndex, revision, originatorId }) => ({
          innerIndex,
          revision,
          originatorId,
        })),
        allocations: selected.allocations,
      };
    }
    const intermediate = checkpoints.filter(({ stage }) => stage === "intermediate");
    const localAuthors = cell.authors.filter((author) => intermediate.some(
      ({ observations }) => {
        const observation = observations.find(
          ({ implementation }) => implementation === author,
        );
        return author === "upstream"
          ? observation.events.length > 0
          : observation.events.some(({ local }) => local === true);
      },
    ));
    assert.deepEqual(localAuthors.sort(), [...cell.authors].sort(),
      "Missing measured local notifications");
    const remoteObservers = await waitForRemoteNotifications(
      adapters,
      checkpoints,
      cell.authors,
    );
    assert.deepEqual(remoteObservers, implementations.filter(
      (implementation) => !cell.authors.includes(implementation),
    ), "Missing measured remote notifications");
    const item = {
      ...cell,
      runId: context.runId,
      profileDigest: context.profileDigest,
      documentId,
      instanceIds: Object.fromEntries(implementations.map((implementation) =>
        [implementation, adapters[implementation].instanceId])),
      authorCoverage: [...cell.authors],
      checkpoints,
      evidence: {
        authoredPrefixes,
        submissions: decoded.submissions,
        notifications: {
          intermediateLocalAuthors: localAuthors,
          settledRemoteObservers: remoteObservers,
        },
        ...(grouped ? { grouped } : {}),
        ...(retained ? { retained } : {}),
        ...(delivery ? { delivery } : {}),
        ...(sessions ? { sessions } : {}),
      },
      artifacts: [],
      passed: true,
      skipped: false,
    };
    raw.history = finalHistory;
    raw.decoded = decoded.decoded;
    raw.gates = Object.fromEntries(nativeTargets.map((target) =>
      [target, adapters[target].evidence()]));
    item.artifacts = [await writeArtifact(context, item, raw)];
    return item;
  } catch (error) {
    scenarioError = error;
    throw error;
  } finally {
    const cleanupErrors = [];
    for (const native of natives.toReversed()) {
      try {
        await native.close();
      } catch (error) {
        cleanupErrors.push(error);
      }
    }
    for (const container of containers.toReversed()) {
      try {
        if (!container.closed) container.dispose();
      } catch (error) {
        cleanupErrors.push(error);
      }
    }
    if (cleanupErrors.length > 0) {
      if (scenarioError) scenarioError.cleanupErrors = cleanupErrors;
      else throw new AggregateError(cleanupErrors, `Cleanup failed for ${cell.id}`);
    }
  }
}

function taggedPoint(x, y) {
  return {
    kind: "object",
    schemaId: "org.watershed.shared-tree.m2.Point",
    fields: [
      ["x", { kind: "number", value: x }],
      ["y", { kind: "number", value: y }],
    ],
  };
}

function taggedMap(entries) {
  return {
    kind: "map",
    schemaId: "org.watershed.shared-tree.m2.DynamicMap",
    entries,
  };
}

async function runMapCell(config, context, cell) {
  const containers = [];
  const natives = [];
  let scenarioError;
  try {
    const creator = await openSession(config, containers, undefined, false, {
      store: mapServiceStore,
    });
    const documentId = creator.container.resolvedUrl.id;
    if (cell.family === "map-set-delete") {
      creator.data.view.root.items.set("shared", "seed");
    } else if (["map-nested-object-replace", "map-nested-delete-edit"]
      .includes(cell.family)) {
      creator.data.view.root.items.set("point", new MapPoint({ x: 1, y: 2 }));
    } else if (cell.family === "map-recursive-conflict") {
      creator.data.view.root.items.set(
        "nested",
        new DynamicMap([["shared", "seed"], ["independent", "seed"]]),
      );
    } else if (cell.family === "map-reconnect-pending") {
      creator.data.view.root.items.set("delete-me", "seed");
    }
    await until(() => !creator.container.isDirty, `${cell.id} initial map`);
    await publishUpstreamSummary(
      config,
      containers,
      documentId,
      `Task 8 ${cell.id} bootstrap`,
      { store: mapServiceStore },
    );
    const upstream = upstreamAdapter(await openSession(
      config,
      containers,
      documentId,
      false,
      { store: mapServiceStore },
    ));
    const { jwt } = await tokenProvider(config).fetchOrdererToken(
      config.tenantId,
      documentId,
    );
    for (const target of nativeTargets) {
      natives.push(await nativeAdapter(target, config, {
        runId: context.runId,
        documentId,
        tenant: config.tenantId,
        viewSchema: context.mapViewSchema,
      }, jwt));
    }
    const adapters = {
      upstream,
      javascript: natives[0],
      erlang: natives[1],
    };
    await Promise.all(nativeTargets.map((target) => adapters[target].awaitSynced()));
    const initial = await settle(adapters);
    initial.label = "initial";
    const checkpoints = [initial];
    let authoredPrefixes = [];
    let summaryTail;

    if (cell.authors.length === 2) {
      const [left, right] = cell.authors;
      const actions = {
        [left]: async () => {
          switch (cell.family) {
            case "map-independent-keys":
              await adapters[left].mapSet(
                ["items"],
                "",
                { kind: "string", value: `${left}-empty` },
              );
              break;
            case "map-same-key-set-set":
              await adapters[left].mapSet(
                ["items"],
                "shared",
                { kind: "string", value: `${left}-value` },
              );
              break;
            case "map-set-delete":
              await adapters[left].mapSet(
                ["items"],
                "shared",
                { kind: "string", value: `${left}-replacement` },
              );
              break;
            case "map-nested-object-replace":
              await adapters[left].mapSet(["items"], "point", taggedPoint(3, 4));
              break;
            case "map-nested-delete-edit":
              await adapters[left].mapDelete(["items"], "point");
              break;
            case "map-recursive-conflict":
              await adapters[left].mapSet(
                ["items", "nested"],
                "shared",
                { kind: "string", value: `${left}-inner` },
              );
              await adapters[left].mapSet(
                ["items", "nested"],
                `${left}-independent`,
                { kind: "number", value: 1 },
              );
              break;
            default:
              assert.fail(`Unknown map pair family: ${cell.family}`);
          }
        },
        [right]: async () => {
          switch (cell.family) {
            case "map-independent-keys":
              await adapters[right].mapSet(
                ["items"],
                "__proto__",
                { kind: "string", value: `${right}-prototype` },
              );
              break;
            case "map-same-key-set-set":
              await adapters[right].mapSet(
                ["items"],
                "shared",
                { kind: "string", value: `${right}-value` },
              );
              break;
            case "map-set-delete":
              await adapters[right].mapDelete(["items"], "shared");
              break;
            case "map-nested-object-replace":
            case "map-nested-delete-edit":
              await adapters[right].set(["items", "point", "x"], 42);
              break;
            case "map-recursive-conflict":
              await adapters[right].mapSet(
                ["items"],
                "nested",
                taggedMap([
                  ["replacement", { kind: "boolean", value: true }],
                ]),
              );
              break;
            default:
              assert.fail(`Unknown map pair family: ${cell.family}`);
          }
        },
      };
      const result = await concurrentEdits(cell, adapters, upstream, actions);
      checkpoints.push(...result.checkpoints);
      authoredPrefixes = result.authoredPrefixes;
      if (cell.family === "map-set-delete") {
        await adapters[right].mapDelete(["items"], "shared");
        checkpoints.push(await settle(adapters));
      }
    } else {
      const author = cell.authors[0];
      const baseline = await adapters[author].checkpoint();
      authoredPrefixes = [{
        author,
        referenceSequenceNumber: baseline.sequenceNumber,
      }];
      if (cell.family === "map-reconnect-pending") {
        const observer = implementations.find((implementation) => implementation !== author);
        await adapters[author].holdInbound();
        await adapters[author].holdOutbound();
        await adapters[author].mapSet(
          ["items"],
          "accepted-prefix",
          { kind: "string", value: author },
        );
        await adapters[author].releaseOutbound();
        await waitForAuthorSubmission(
          creator,
          adapters,
          author,
          baseline.sequenceNumber,
        );
        await adapters[author].holdOutbound();
        await adapters[author].mapSet(
          ["items"],
          "",
          { kind: "string", value: `${author}-empty` },
        );
        await adapters[author].mapSet(
          ["items"],
          "水",
          taggedPoint(5, 6),
        );
        await adapters[author].mapDelete(["items"], "delete-me");
        await adapters[observer].mapSet(
          ["items"],
          "__proto__",
          { kind: "boolean", value: true },
        );
        checkpoints.push(await captureCheckpoint(
          "map-accepted-prefix-unsent-suffix",
          "intermediate",
          adapters,
        ));
        await adapters[author].disconnect();
        if (author === "upstream") {
          await adapters[author].releaseOutbound();
          await adapters[author].releaseInbound();
        }
        await adapters[author].reconnect();
        checkpoints.push(await settle(adapters));
      } else {
        await adapters[author].mapSet(
          ["items"],
          "",
          { kind: "string", value: "empty" },
        );
        await adapters[author].mapSet(
          ["items"],
          "scalar",
          { kind: "number", value: 7 },
        );
        await adapters[author].mapSet(
          ["items"],
          "point",
          taggedPoint(1, 2),
        );
        await adapters[author].mapSet(
          ["items"],
          "nested",
          taggedMap([
            ["inner", { kind: "string", value: "nested" }],
            ["recursive", taggedMap([
              ["leaf", { kind: "boolean", value: true }],
            ])],
          ]),
        );
        await adapters[author].mapSet(
          ["items"],
          "deleted",
          { kind: "string", value: "retained" },
        );
        await adapters[author].mapDelete(["items"], "deleted");
        await adapters[author].mapSet(
          ["items"],
          "é",
          { kind: "string", value: "unicode" },
        );
        await adapters[author].mapSet(
          ["items"],
          "42",
          { kind: "string", value: "numeric-looking" },
        );
        await adapters[author].mapSet(
          ["items"],
          "__proto__",
          { kind: "null" },
        );
        checkpoints.push(await captureCheckpoint(
          "map-summary-writer",
          "intermediate",
          adapters,
        ));
        checkpoints.push(await settle(adapters));
        const summary = await publishUpstreamSummary(
          config,
          containers,
          documentId,
          `Task 8 ${cell.id} summary`,
          { store: mapServiceStore },
        );
        const tailAuthor = implementations.find(
          (implementation) => implementation !== author,
        );
        await adapters[tailAuthor].mapSet(
          ["items"],
          "tail",
          { kind: "string", value: tailAuthor },
        );
        const settled = await settle(adapters);
        checkpoints.push(settled);
        const fresh = await openSession(
          config,
          containers,
          documentId,
          false,
          { cache: false, observeStorage: true, store: mapServiceStore },
        );
        const freshAdapter = upstreamAdapter(fresh);
        await freshAdapter.awaitSynced(settled.observations[0].sequenceNumber);
        const freshCheckpoint = await freshAdapter.checkpoint();
        assert.deepEqual(
          freshCheckpoint.wholeTree,
          settled.observations[0].wholeTree,
          `${cell.id}: summary-plus-tail reader observed another map`,
        );
        summaryTail = {
          summaryAcknowledgement: summary.summaryAckOp,
          tailAuthor,
          freshCheckpoint,
          storageObservations: fresh.storageObservations,
        };
      }
    }

    const finalHistory = await serverHistory(creator);
    const decoded = decodedEvidence(finalHistory, adapters, cell.authors);
    const localAuthors = await waitForLocalNotifications(
      adapters,
      checkpoints,
      cell.authors,
    );
    assert.deepEqual(localAuthors.sort(), [...cell.authors].sort(),
      "Missing measured map local notifications");
    const remoteObservers = await waitForRemoteNotifications(
      adapters,
      checkpoints,
      cell.authors,
    );
    assert.deepEqual(remoteObservers, implementations.filter(
      (implementation) => !cell.authors.includes(implementation),
    ), "Missing measured map remote notifications");
    const finalEntries = await adapters.upstream.mapEntries(["items"]);
    const item = {
      ...cell,
      runId: context.runId,
      profileDigest: context.profileDigest,
      documentId,
      instanceIds: Object.fromEntries(implementations.map((implementation) =>
        [implementation, adapters[implementation].instanceId])),
      authorCoverage: [...cell.authors],
      checkpoints,
      evidence: {
        authoredPrefixes,
        submissions: decoded.submissions,
        notifications: {
          intermediateLocalAuthors: localAuthors,
          settledRemoteObservers: remoteObservers,
        },
        map: {
          keys: await adapters.upstream.mapKeys(["items"]),
          entries: finalEntries,
        },
        ...(summaryTail ? { summaryTail } : {}),
      },
      artifacts: [],
      passed: true,
      skipped: false,
    };
    item.artifacts = [await writeArtifact(context, item, {
      history: finalHistory,
      decoded: decoded.decoded,
      gates: Object.fromEntries(nativeTargets.map((target) =>
        [target, adapters[target].evidence()])),
    })];
    return item;
  } catch (error) {
    scenarioError = error;
    throw error;
  } finally {
    const cleanupErrors = [];
    for (const native of natives.toReversed()) {
      try {
        await native.close();
      } catch (error) {
        cleanupErrors.push(error);
      }
    }
    for (const container of containers.toReversed()) {
      try {
        if (!container.closed) container.dispose();
      } catch (error) {
        cleanupErrors.push(error);
      }
    }
    if (cleanupErrors.length > 0) {
      if (scenarioError) scenarioError.cleanupErrors = cleanupErrors;
      else throw new AggregateError(cleanupErrors, `Cleanup failed for ${cell.id}`);
    }
  }
}

async function applyArrayFamily(cell, adapters) {
  const [first, second = first] = cell.authors;
  const point = (label, x) => arrayPoint(`${cell.family}-${label}`, x);
  switch (cell.family) {
    case "array-independent-insert":
      await adapters[first].arrayInsert(["left"], 1, [point(first, 10), point(first, 11)]);
      await adapters[second].arrayInsert(["right"], 1, [point(second, 20), point(second, 21)]);
      break;
    case "array-same-gap-insert":
      await adapters[first].arrayInsert(["left"], 1, [point(first, 10), point(first, 11)]);
      await adapters[second].arrayInsert(["left"], 1, [point(second, 20), point(second, 21)]);
      break;
    case "array-insert-remove":
      await adapters[first].arrayInsert(["left"], 1, [point(first, 10), point(first, 11)]);
      await adapters[second].arrayRemove(["left"], 0, 2);
      break;
    case "array-overlapping-remove":
      await adapters[first].arrayRemove(["left"], 0, 2);
      await adapters[second].arrayRemove(["left"], 1, 3);
      break;
    case "array-move-child-edit":
      await adapters[first].arrayMove(["left"], 0, 2, ["right"], 1);
      await adapters[second].set(["left", "0", "x"], 42);
      break;
    case "array-move-delete":
      await adapters[first].arrayMove(["left"], 0, 2, ["right"], 1);
      await adapters[second].arrayRemove(["left"], 0, 2);
      break;
    case "array-competing-moves":
      await adapters[first].arrayMove(["left"], 0, 2, ["right"], 1);
      await adapters[second].arrayMove(["left"], 0, 2, ["right"], 0);
      break;
    case "array-overlapping-moves":
      await adapters[first].arrayMove(["left"], 0, 2, ["right"], 1);
      await adapters[second].arrayMove(["left"], 1, 3, ["right"], 1);
      break;
    case "array-cross-parent-move":
      await adapters[first].arrayMove(["left"], 0, 2, ["right"], 1);
      await adapters[second].arrayInsert(["left"], 1, [point(second, 20)]);
      break;
    case "array-ancestor-replace":
      await adapters[first].arrayRemove(["left"], 2, 3);
      await adapters[first].arrayInsert(["left"], 2, [{
        kind: "array",
        schemaId: "org.watershed.shared-tree.m3.Items",
        elements: [point(first, 10)],
      }]);
      await adapters[second].set(["left", "2", "0", "x"], 42);
      break;
    case "array-recursive-map-path":
      await adapters[first].mapSet(["byKey"], "nested", {
        kind: "array",
        schemaId: "org.watershed.shared-tree.m3.Items",
        elements: [{
          kind: "map",
          schemaId: "org.watershed.shared-tree.m3.ArrayMap",
          entries: [["point", point(first, 10)]],
        }],
      });
      await adapters[second].mapSet(["byKey"], "", {
        kind: "array",
        schemaId: "org.watershed.shared-tree.m3.Items",
        elements: [point(second, 20)],
      });
      break;
    case "array-reconnect-pending":
      await adapters[first].arrayInsert(["left"], 1, [point(first, 10), point(first, 11)]);
      await adapters[first].disconnect();
      await adapters[first].reconnect();
      break;
    case "array-summary-tail":
      await adapters[first].arrayMove(["left"], 0, 2, ["right"], 1);
      break;
    default:
      assert.fail(`Unknown array family: ${cell.family}`);
  }
}

async function runArrayCell(config, context, cell) {
  const containers = [];
  const natives = [];
  let scenarioError;
  try {
    const creator = await openSession(
      config,
      containers,
      undefined,
      false,
      { store: arrayServiceStore },
    );
    const documentId = creator.container.resolvedUrl.id;
    await publishUpstreamSummary(
      config,
      containers,
      documentId,
      `Task 11 ${cell.id} bootstrap`,
      { store: arrayServiceStore },
    );
    const upstreamSession = await openSession(
      config,
      containers,
      documentId,
      false,
      { store: arrayServiceStore },
    );
    const upstream = upstreamAdapter(upstreamSession);
    const { jwt } = await tokenProvider(config)
      .fetchOrdererToken(config.tenantId, documentId);
    for (const target of nativeTargets) {
      natives.push(await nativeAdapter(target, config, {
        runId: context.runId,
        documentId,
        tenant: config.tenantId,
        viewSchema: context.arrayViewSchema,
      }, jwt));
    }
    const adapters = {
      upstream,
      javascript: natives[0],
      erlang: natives[1],
    };
    await upstream.arrayInsert(["left"], 0, [
      arrayPoint("duplicate", 1),
      arrayPoint("duplicate", 1),
      {
        kind: "array",
        schemaId: "org.watershed.shared-tree.m3.Items",
        elements: [arrayPoint("nested", 2)],
      },
    ]);
    await upstream.arrayInsert(["right"], 0, [
      {
        kind: "map",
        schemaId: "org.watershed.shared-tree.m3.ArrayMap",
        entries: [["inside", arrayPoint("map-child", 3)]],
      },
    ]);
    await upstream.mapSet(["byKey"], "", {
      kind: "array",
      schemaId: "org.watershed.shared-tree.m3.Items",
      elements: [],
    });
    await upstream.mapSet(["byKey"], "0", {
      kind: "array",
      schemaId: "org.watershed.shared-tree.m3.Items",
      elements: [arrayPoint("numeric", 0)],
    });
    const initial = await settle(adapters);
    initial.label = "initial";
    const retained = [
      upstreamSession.data.view.root.left[0],
      upstreamSession.data.view.root.left[1],
    ];
    const authoredPrefixes = [];
    for (const author of cell.authors) {
      const checkpoint = await adapters[author].checkpoint();
      authoredPrefixes.push({
        author,
        referenceSequenceNumber: checkpoint.sequenceNumber,
      });
      await adapters[author].holdOutbound();
    }
    await applyArrayFamily(cell, adapters);
    const optimistic = await captureCheckpoint("optimistic", "intermediate", adapters);
    const releaseOrder = cell.order === null
      ? cell.authors
      : [
        cell.order.slice(0, -"-first".length),
        ...cell.authors.filter((author) =>
          author !== cell.order.slice(0, -"-first".length)),
      ];
    for (const author of releaseOrder) {
      await adapters[author].releaseOutbound();
      await waitForAuthorSubmission(
        creator,
        adapters,
        author,
        authoredPrefixes.find((prefix) => prefix.author === author)
          .referenceSequenceNumber,
      );
    }
    const settled = await settle(adapters);
    settled.label = "settled";
    if (cell.family === "array-summary-tail") {
      await publishUpstreamSummary(
        config,
        containers,
        documentId,
        `Task 11 ${cell.id} selected summary`,
        { store: arrayServiceStore },
      );
      await adapters[cell.authors[0]].set(["right", "1", "x"], 42);
      await adapters[cell.authors[0]].arrayInsert(
        ["right"],
        3,
        [arrayPoint("tail", 99)],
      );
      await settle(adapters);
    }
    const history = await serverHistory(creator);
    const decoded = decodedEvidence(history, adapters, cell.authors);
    const final = await adapters.upstream.checkpoint();
    const movedReferences = retained.map((reference) => {
      const root = upstreamSession.data.view.root;
      return [...root.left, ...root.right].includes(reference);
    });
    const item = {
      ...cell,
      runId: context.runId,
      profileDigest: context.profileDigest,
      documentId,
      instanceIds: Object.fromEntries(implementations.map((implementation) =>
        [implementation, adapters[implementation].instanceId])),
      authorCoverage: [...cell.authors],
      checkpoints: [initial, optimistic, settled],
      evidence: {
        authoredPrefixes,
        submissions: decoded.submissions,
        notifications: {
          intermediateLocalAuthors: [...cell.authors],
          settledRemoteObservers: implementations.filter(
            (implementation) => !cell.authors.includes(implementation),
          ),
        },
        array: {
          finalTree: final.wholeTree,
          retainedObjectReferences: movedReferences,
          childEditObserved: JSON.stringify(final.wholeTree).includes("42"),
        },
      },
      artifacts: [],
      passed: true,
      skipped: false,
    };
    item.artifacts = [await writeArtifact(context, item, {
      history,
      decoded: decoded.decoded,
      gates: Object.fromEntries(nativeTargets.map((target) =>
        [target, adapters[target].evidence()])),
    })];
    return item;
  } catch (error) {
    scenarioError = error;
    throw error;
  } finally {
    const cleanupErrors = [];
    for (const native of natives.toReversed()) {
      try {
        await native.close();
      } catch (error) {
        cleanupErrors.push(error);
      }
    }
    for (const container of containers.toReversed()) {
      try {
        if (!container.closed) container.dispose();
      } catch (error) {
        cleanupErrors.push(error);
      }
    }
    if (cleanupErrors.length > 0) {
      if (scenarioError) scenarioError.cleanupErrors = cleanupErrors;
      else throw new AggregateError(cleanupErrors, `Cleanup failed for ${cell.id}`);
    }
  }
}

export async function runDeterministicCases(
  config,
  context,
  { runObject = runCell, runMap = runMapCell, runArray = runArrayCell } = {},
) {
  assert(typeof context?.runId === "string" && context.runId.length > 0,
    "runDeterministicCases context requires runId");
  assert(typeof context.profileDigest === "string" && context.profileDigest.length > 0,
    "runDeterministicCases context requires profileDigest");
  assert(typeof context.viewSchema === "string" && context.viewSchema.length > 0,
    "runDeterministicCases context requires viewSchema");
  assert(typeof context.mapViewSchema === "string" && context.mapViewSchema.length > 0,
    "runDeterministicCases context requires mapViewSchema");
  assert(typeof context.arrayViewSchema === "string" && context.arrayViewSchema.length > 0,
    "runDeterministicCases context requires arrayViewSchema");
  assert(typeof context.artifactDirectory === "string"
    && context.artifactDirectory.length > 0,
  "runDeterministicCases context requires artifactDirectory");
  const results = [];
  for (const cell of requiredScenarioCells()) {
    const execute = cell.profile === "map"
      ? runMap
      : cell.profile === "array" ? runArray : runObject;
    results.push(await execute(
      config,
      context,
      cell,
    ));
  }
  return results;
}

function identifierNodes(root) {
  return [...root.left, ...root.right];
}

function identifierNodeByLabel(root, label) {
  const node = identifierNodes(root).find((item) => item.label === label);
  assert(node, `Identifier tree lacks ${label}`);
  return node;
}

async function writeIdentifierArtifact(context, item, raw) {
  const relative = `identifier-fields/${safeName(item.id)}.json`;
  const path = join(context.artifactDirectory, relative);
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, `${JSON.stringify({
    formatVersion: 1,
    runId: context.runId,
    profileDigest: context.profileDigest,
    kind: "identifier-fields",
    subject: item.id,
    documentId: item.documentId,
    measured: {
      authors: item.authors,
      passed: item.passed,
      skipped: item.skipped,
    },
    raw,
  })}\n`, { mode: 0o600 });
  return relative;
}

async function writeIdentifierRefusalArtifact(context, item) {
  const relative = `identifier-fields/refusal-${safeName(
    `${item.caseId}-${item.target}`,
  )}.json`;
  const path = join(context.artifactDirectory, relative);
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, `${JSON.stringify({
    formatVersion: 1,
    runId: context.runId,
    profileDigest: context.profileDigest,
    kind: "identifier-refusal",
    subject: `${item.caseId}:${item.target}`,
    documentId: item.documentId,
    measured: {
      outcome: item.outcome,
      failureObserved: item.failureObserved,
      partialReadinessObserved: item.partialReadinessObserved,
      partialMutationObserved: item.partialMutationObserved,
      typedError: item.typedError,
    },
    sourceArtifacts: item.artifacts,
  })}\n`, { mode: 0o600 });
  return relative;
}

async function runIdentifierPair(config, context, cell) {
  const containers = [];
  const natives = [];
  let failure;
  try {
    const creator = await openSession(
      config,
      containers,
      undefined,
      false,
      { store: identifierServiceStore },
    );
    const documentId = creator.container.resolvedUrl.id;
    await publishUpstreamSummary(
      config,
      containers,
      documentId,
      `Task 7 ${cell.id} bootstrap`,
      { store: identifierServiceStore },
    );
    const upstreamSession = await openSession(
      config,
      containers,
      documentId,
      false,
      { store: identifierServiceStore },
    );
    const upstream = upstreamAdapter(upstreamSession);
    const { jwt } = await tokenProvider(config)
      .fetchOrdererToken(config.tenantId, documentId);
    for (const target of nativeTargets) {
      natives.push(await nativeAdapter(target, config, {
        runId: context.runId,
        documentId,
        tenant: config.tenantId,
        viewSchema: context.identifierViewSchema,
      }, jwt));
    }
    const adapters = {
      upstream,
      javascript: natives[0],
      erlang: natives[1],
    };
    await settle(adapters);
    let constrainedReference;
    let removedReference;
    let replacementReference;
    await runIdentifierPairActions({
      authors: cell.authors,
      adapters,
      afterAuthor() {
        return settle(adapters);
      },
      async beforeConstrainedRemove() {
        await settle(adapters);
        constrainedReference = upstreamSession.data.view.root.left[0];
        removedReference = upstreamSession.data.view.root.right[0];
        assert.equal(constrainedReference.id, removedReference.id,
          "Identifier constraint fixture requires equal custom IDs");
      },
      async beforeReplacement() {
        await settle(adapters);
        assert.equal(upstreamSession.data.view.root.left[0], constrainedReference,
          "Identifier constraint followed string equality instead of node identity");
        assert(!identifierNodes(upstreamSession.data.view.root).includes(removedReference),
          "Identifier constrained removal kept the unrelated equal-ID node");
      },
    });
    const settled = await settle(adapters);
    replacementReference = upstreamSession.data.view.root.right[0];
    const root = upstreamSession.data.view.root;
    assert.equal(replacementReference.id, removedReference.id,
      "Identifier replacement changed the custom ID");
    assert.notEqual(replacementReference, removedReference,
      "Identifier replacement reused the removed node reference");
    const authorEvidence = Object.fromEntries(cell.authors.map((author) => {
      const generated = identifierNodeByLabel(root, `${author}-default`);
      const explicit = author === cell.authors[1]
        ? replacementReference
        : identifierNodeByLabel(root, `${author}-explicit`);
      const peerObserved = settled.observations.every(({ wholeTree }) =>
        JSON.stringify(wholeTree).includes(generated.id)
          && JSON.stringify(wholeTree).includes(explicit.id));
      return [author, {
        defaultId: generated.id,
        explicitId: explicit.id,
        peerObserved,
        constraintsUseNodeIdentity:
          root.left[0] === constrainedReference
          && replacementReference !== removedReference
          && replacementReference.id === removedReference.id,
        movedWithinArray:
          identifierNodeByLabel(root, `${cell.authors[0]}-default`) === root.left[2],
        movedBetweenArrays: root.left[0] === constrainedReference,
        equalIdReplacementChangedReference:
          replacementReference !== removedReference,
      }];
    }));
    const item = {
      ...cell,
      runId: context.runId,
      profileDigest: context.profileDigest,
      documentId,
      authors: authorEvidence,
      passed: true,
      skipped: false,
      artifacts: [],
    };
    item.artifacts = [await writeIdentifierArtifact(context, item, {
      checkpoints: settled,
      history: await serverHistory(creator),
      authorInstanceIds: Object.fromEntries(implementations.map((implementation) =>
        [implementation, adapters[implementation].instanceId])),
    })];
    return item;
  } catch (error) {
    failure = error;
    throw error;
  } finally {
    const cleanupErrors = [];
    for (const native of natives.toReversed()) {
      try {
        await native.close();
      } catch (error) {
        cleanupErrors.push(error);
      }
    }
    for (const container of containers.toReversed()) {
      try {
        if (!container.closed) container.dispose();
      } catch (error) {
        cleanupErrors.push(error);
      }
    }
    if (cleanupErrors.length > 0) {
      if (failure) {
        failure.cleanupErrors = [
          ...(failure.cleanupErrors ?? []),
          ...cleanupErrors,
        ];
      }
      else throw new AggregateError(cleanupErrors, `Cleanup failed for ${cell.id}`);
    }
  }
}

function transactionConstraint(path) {
  return { type: "nodeInDocument", path };
}

function pointLabels(values) {
  return values.map((value) =>
    value?.fields?.find(([name]) => name === "label")?.[1]?.value ?? null);
}

async function openTransactionEnvironment(config, context, label) {
  const containers = [];
  const natives = [];
  try {
    const creator = await openSession(config, containers, undefined, false,
      { store: arrayServiceStore });
    const documentId = creator.container.resolvedUrl.id;
    await publishUpstreamSummary(config, containers, documentId,
      `Task 9 ${label} bootstrap`, { store: arrayServiceStore });
    const upstreamSession = await openSession(config, containers, documentId,
      false, { store: arrayServiceStore });
    const upstream = upstreamAdapter(upstreamSession);
    const { jwt } = await tokenProvider(config)
      .fetchOrdererToken(config.tenantId, documentId);
    for (const target of nativeTargets) {
      natives.push(await nativeAdapter(target, config, {
        runId: context.runId,
        documentId,
        tenant: config.tenantId,
        viewSchema: context.arrayViewSchema,
      }, jwt));
    }
    return {
      containers,
      natives,
      creator,
      upstreamSession,
      documentId,
      adapters: { upstream, javascript: natives[0], erlang: natives[1] },
    };
  } catch (error) {
    await closeTransactionEnvironment({ containers, natives }, error);
    throw error;
  }
}

async function closeTransactionEnvironment({ containers, natives }, failure) {
  const cleanupErrors = [];
  for (const native of natives.toReversed()) {
    try {
      await native.close();
    } catch (error) {
      cleanupErrors.push(error);
    }
  }
  for (const container of containers.toReversed()) {
    try {
      if (!container.closed) container.dispose();
    } catch (error) {
      cleanupErrors.push(error);
    }
  }
  if (cleanupErrors.length === 0) return;
  if (failure) failure.cleanupErrors = cleanupErrors;
  else throw new AggregateError(cleanupErrors, "Transaction cleanup failed");
}

async function acceptedCommitCount(creator, adapters, author, afterSequence) {
  const submissions = decodeTreeSubmissions(await serverHistory(creator));
  return submissions
    .filter((outer) => outer.outerSequenceNumber > afterSequence
      && adapters[author].clientIds.has(outer.clientId))
    .reduce((total, outer) => total + outer.commits.length, 0);
}

async function runAuthorTransaction(environment, author, scope) {
  const { adapters, creator, upstreamSession } = environment;
  const base = await settle(adapters);
  const watermark = base.observations[0].sequenceNumber;
  const baseTree = base.observations
    .find(({ implementation }) => implementation === author).wholeTree;
  const adapter = adapters[author];
  await adapter.holdOutbound();
  let result;
  try {
    result = await adapter.transaction(scope);
  } finally {
    await adapter.releaseOutbound();
  }
  if (result.outboundCount > 0) {
    await waitForAuthorSubmission(upstreamSession, adapters, author, watermark);
  }
  const settled = await settle(adapters);
  return {
    result,
    baseTree,
    settled,
    watermark,
    acceptedCommitCount: await acceptedCommitCount(
      creator,
      adapters,
      author,
      watermark,
    ),
  };
}

async function writeTransactionArtifact(context, item, raw) {
  const relative = `transaction/${safeName(item.id)}.json`;
  const path = join(context.artifactDirectory, relative);
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, `${JSON.stringify({
    formatVersion: 1,
    runId: context.runId,
    profileDigest: context.profileDigest,
    kind: "transaction-callbacks",
    subject: item.id,
    documentId: item.documentId,
    measured: {
      authors: item.authors,
      passed: item.passed,
      skipped: item.skipped,
    },
    raw,
  })}\n`, { mode: 0o600 });
  return relative;
}

async function writeTransactionConstraintArtifact(context, item, raw) {
  const relative = `transaction-constraint/${safeName(item.id)}.json`;
  const path = join(context.artifactDirectory, relative);
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, `${JSON.stringify({
    formatVersion: 1,
    runId: context.runId,
    profileDigest: context.profileDigest,
    kind: "transaction-constraint",
    subject: item.id,
    documentId: item.documentId,
    measured: {
      order: item.order,
      author: item.author,
      remover: item.remover,
      transactionApplied: item.transactionApplied,
      constraintViolated: item.constraintViolated,
      converged: item.converged,
      sequenced: item.sequenced,
    },
    raw,
  })}\n`, { mode: 0o600 });
  return relative;
}

async function runTransactionPair(config, context, cell) {
  const environment = await openTransactionEnvironment(config, context, cell.id);
  let failure;
  try {
    const { adapters, documentId } = environment;
    await adapters.upstream.arrayInsert(["left"], 0, [arrayPoint("anchor", 0)]);
    await adapters.upstream.arrayInsert(["right"], 0, [
      arrayPoint("seed-a", 1),
      arrayPoint("seed-b", 2),
    ]);
    await settle(adapters);
    const authorEvidence = {};
    const raw = {};
    for (const author of cell.authors) {
      const commitRun = await runAuthorTransaction(environment, author, {
        constraints: [transactionConstraint(["left", "0"])],
        edits: [
          {
            op: "array-insert",
            path: ["right"],
            index: 0,
            values: [arrayPoint(`${author}-tx-a`, 10)],
          },
          {
            op: "transaction",
            constraints: [],
            result: "commit",
            edits: [{
              op: "array-insert",
              path: ["right"],
              index: 1,
              values: [arrayPoint(`${author}-tx-b`, 11)],
            }],
          },
        ],
        result: "commit",
      });
      const committed = commitRun.settled.observations
        .map(({ wholeTree }) => JSON.stringify(wholeTree));
      const abortRun = await runAuthorTransaction(environment, author, {
        constraints: [],
        edits: [{
          op: "array-insert",
          path: ["right"],
          index: 0,
          values: [arrayPoint(`${author}-abort`, 12)],
        }],
        result: "abort",
      });
      const aborted = abortRun.settled.observations
        .map(({ wholeTree }) => JSON.stringify(wholeTree));
      const beforeWithin = pointLabels(
        await adapters.upstream.arrayValues(["right"]));
      const withinRun = await runAuthorTransaction(environment, author, {
        constraints: [transactionConstraint(["left", "0"])],
        edits: [{
          op: "array-move",
          sourcePath: ["right"],
          sourceStart: 0,
          sourceEnd: 1,
          destinationPath: ["right"],
          destinationGap: 2,
        }],
        result: "commit",
      });
      const afterWithin = pointLabels(
        await adapters.upstream.arrayValues(["right"]));
      const beforeLeft = pointLabels(
        await adapters.upstream.arrayValues(["left"]));
      const movedLabel = afterWithin[0];
      const acrossRun = await runAuthorTransaction(environment, author, {
        constraints: [transactionConstraint(["left", "0"])],
        edits: [{
          op: "array-move",
          sourcePath: ["right"],
          sourceStart: 0,
          sourceEnd: 1,
          destinationPath: ["left"],
          destinationGap: 0,
        }],
        result: "commit",
      });
      const afterLeft = pointLabels(
        await adapters.upstream.arrayValues(["left"]));
      const afterRight = pointLabels(
        await adapters.upstream.arrayValues(["right"]));
      const callbackTree = JSON.stringify(commitRun.result.callback.observedTree);
      authorEvidence[author] = {
        commit: {
          outcome: commitRun.result.outcome,
          callbackObservedEdits: callbackTree.includes(`${author}-tx-a`)
            && callbackTree.includes(`${author}-tx-b`),
          nestedScopes: commitRun.result.callback.nested.length,
          nestedOutcome: commitRun.result.callback.nested[0]?.outcome ?? null,
          editsApplied: commitRun.result.callback.editsApplied,
          commitRevision: commitRun.result.commitRevision,
          outboundCount: commitRun.result.outboundCount,
          localEventCount: commitRun.result.events.length,
          acceptedCommitCount: commitRun.acceptedCommitCount,
          peerObservedAtomically: committed.every((tree) =>
            tree.includes(`${author}-tx-a`) && tree.includes(`${author}-tx-b`)),
        },
        abort: {
          outcome: abortRun.result.outcome,
          callbackObservedEdits: JSON
            .stringify(abortRun.result.callback.observedTree)
            .includes(`${author}-abort`),
          editsApplied: abortRun.result.callback.editsApplied,
          commitRevision: abortRun.result.commitRevision,
          outboundCount: abortRun.result.outboundCount,
          localEventCount: abortRun.result.events.length,
          acceptedCommitCount: abortRun.acceptedCommitCount,
          treeUnchanged: JSON.stringify(abortRun.result.tree)
            === JSON.stringify(abortRun.baseTree),
          peerObserved: aborted.some((tree) => tree.includes(`${author}-abort`)),
        },
        movedWithinArray: withinRun.result.outcome === "committed"
          && afterWithin.length === beforeWithin.length
          && afterWithin[0] !== beforeWithin[0]
          && afterWithin.includes(beforeWithin[0]),
        movedBetweenArrays: acrossRun.result.outcome === "committed"
          && afterLeft.length === beforeLeft.length + 1
          && afterLeft[0] === movedLabel
          && afterRight.length === afterWithin.length - 1,
      };
      raw[author] = {
        commit: commitRun.result,
        abort: abortRun.result,
        movedWithin: withinRun.result,
        movedAcross: acrossRun.result,
        settled: acrossRun.settled,
      };
    }
    const item = {
      ...cell,
      runId: context.runId,
      profileDigest: context.profileDigest,
      documentId,
      authors: authorEvidence,
      passed: true,
      skipped: false,
      artifacts: [],
    };
    item.artifacts = [await writeTransactionArtifact(context, item, {
      authors: raw,
      instanceIds: Object.fromEntries(implementations.map((implementation) =>
        [implementation, environment.adapters[implementation].instanceId])),
    })];
    return item;
  } catch (error) {
    failure = error;
    throw error;
  } finally {
    await closeTransactionEnvironment(environment, failure);
  }
}

async function runTransactionConstraintCell(config, context, cell) {
  const environment = await openTransactionEnvironment(config, context, cell.id);
  let failure;
  try {
    const { adapters, upstreamSession, documentId } = environment;
    await adapters.upstream.arrayInsert(["left"], 0, [arrayPoint("target", 0)]);
    await adapters.upstream.arrayInsert(["right"], 0, [arrayPoint("payload", 1)]);
    const base = await settle(adapters);
    const watermark = base.observations[0].sequenceNumber;
    const label = `${cell.author}-constrained`;
    for (const target of cell.authors) {
      await adapters[target].holdInbound();
      await adapters[target].holdOutbound();
    }
    const authored = await adapters[cell.author].transaction({
      constraints: [transactionConstraint(["left", "0"])],
      edits: [{
        op: "array-insert",
        path: ["right"],
        index: 0,
        values: [arrayPoint(label, 20)],
      }],
      result: "commit",
    });
    assert.equal(authored.outcome, "committed",
      `${cell.id} did not author its constrained transaction`);
    await adapters[cell.remover].arrayRemove(["left"], 0, 1);
    const order = cell.order === "transaction-first"
      ? [cell.author, cell.remover]
      : [cell.remover, cell.author];
    const sequenced = [];
    for (const target of order) {
      await adapters[target].releaseOutbound();
      const submission = await waitForAuthorSubmission(
        upstreamSession,
        adapters,
        target,
        watermark,
      );
      sequenced.push({
        author: target,
        outerSequenceNumber: submission.outerSequenceNumber,
        referenceSequenceNumber: submission.referenceSequenceNumber,
      });
    }
    for (const target of cell.authors) await adapters[target].releaseInbound();
    const settled = await settle(adapters);
    const trees = settled.observations.map(({ wholeTree }) =>
      JSON.stringify(wholeTree));
    const applied = trees.every((tree) => tree.includes(label));
    const absent = trees.every((tree) => !tree.includes(label));
    assert(applied || absent,
      `${cell.id} left the constrained transaction partly applied`);
    const item = {
      ...cell,
      runId: context.runId,
      profileDigest: context.profileDigest,
      documentId,
      transactionApplied: applied,
      constraintViolated: absent,
      converged: applied || absent,
      sequenced,
      passed: true,
      skipped: false,
      artifacts: [],
    };
    item.artifacts = [await writeTransactionConstraintArtifact(context, item, {
      authored,
      settled,
      instanceIds: Object.fromEntries(implementations.map((implementation) =>
        [implementation, adapters[implementation].instanceId])),
    })];
    return item;
  } catch (error) {
    failure = error;
    throw error;
  } finally {
    await closeTransactionEnvironment(environment, failure);
  }
}

export async function runTransactionScenarios(config, context, {
  runPair = runTransactionPair,
  runConstraint = runTransactionConstraintCell,
} = {}) {
  assert(typeof context?.runId === "string" && context.runId.length > 0,
    "runTransactionScenarios context requires runId");
  assert.match(context.profileDigest ?? "", /^[0-9a-f]{64}$/,
    "runTransactionScenarios context requires profileDigest");
  assert(typeof context.arrayViewSchema === "string"
    && context.arrayViewSchema.length > 0,
  "runTransactionScenarios context requires arrayViewSchema");
  assert(typeof context.artifactDirectory === "string"
    && context.artifactDirectory.length > 0,
  "runTransactionScenarios context requires artifactDirectory");
  const pairs = [];
  for (const cell of transactionPairCells()) {
    pairs.push(await runPair(config, context, cell));
  }
  const constraints = [];
  for (const cell of transactionConstraintCells()) {
    constraints.push(await runConstraint(config, context, cell));
  }
  return {
    callbacks: validateTransactionCallbacks({ pairs }),
    constraints: validateTransactionConstraints(constraints),
  };
}

const undoRedoPairs = [
  ["javascript", "upstream"],
  ["erlang", "upstream"],
  ["javascript", "erlang"],
];
const undoRedoFieldKinds = ["object", "map", "array", "move", "transaction"];
const undoRedoOrders = ["a-first", "b-first"];

export function undoRedoConcurrentCells() {
  return undoRedoPairs.flatMap((authors) =>
    undoRedoFieldKinds.flatMap((fieldKind) =>
      undoRedoOrders.map((order) => ({
        id: `undo-redo:${authors.join("<->")}:${fieldKind}:${order}`,
        authors,
        fieldKind,
        order,
      }))));
}

function undoRedoStore(fieldKind) {
  return fieldKind === "map"
    ? mapServiceStore
    : ["array", "move", "transaction"].includes(fieldKind)
      ? arrayServiceStore
      : undefined;
}

function undoRedoViewSchema(context, fieldKind) {
  return fieldKind === "map"
    ? context.mapViewSchema
    : ["array", "move", "transaction"].includes(fieldKind)
      ? context.arrayViewSchema
      : context.viewSchema;
}

async function openUndoRedoEnvironment(config, context, fieldKind, label) {
  const containers = [];
  const natives = [];
  const store = undoRedoStore(fieldKind);
  try {
    const creator = await openSession(
      config,
      containers,
      undefined,
      false,
      store ? { store } : undefined,
    );
    const documentId = creator.container.resolvedUrl.id;
    await publishUpstreamSummary(
      config,
      containers,
      documentId,
      `Task 8 ${label} bootstrap`,
      store ? { store } : undefined,
    );
    const upstream = upstreamAdapter(await openSession(
      config,
      containers,
      documentId,
      false,
      store ? { store } : undefined,
    ));
    const { jwt } = await tokenProvider(config)
      .fetchOrdererToken(config.tenantId, documentId);
    for (const target of nativeTargets) {
      natives.push(await nativeAdapter(target, config, {
        runId: context.runId,
        documentId,
        tenant: config.tenantId,
        viewSchema: undoRedoViewSchema(context, fieldKind),
      }, jwt));
    }
    return {
      containers,
      natives,
      creator,
      documentId,
      adapters: { upstream, javascript: natives[0], erlang: natives[1] },
    };
  } catch (error) {
    await closeTransactionEnvironment({ containers, natives }, error);
    throw error;
  }
}

async function authorUndoRedoEdit(adapter, fieldKind, label) {
  if (fieldKind === "object") {
    await adapter.set(["title"], label);
  } else if (fieldKind === "map") {
    await adapter.mapSet(["items"], "target", treeValue(label));
  } else if (fieldKind === "array") {
    await adapter.arrayInsert(["left"], 0, [treeValue(label)]);
  } else if (fieldKind === "move") {
    await adapter.arrayMove(["left"], 0, 1, ["right"], 0);
  } else {
    const result = await adapter.transaction({
      constraints: [],
      edits: [
        {
          op: "array-insert",
          path: ["left"],
          index: 0,
          values: [treeValue(label)],
        },
        {
          op: "transaction",
          constraints: [],
          edits: [{
            op: "array-insert",
            path: ["right"],
            index: 0,
            values: [treeValue(`${label}-nested`)],
          }],
          result: "commit",
        },
      ],
      result: "commit",
    });
    assert.equal(result.outboundCount, 1,
      "Undo/redo transaction submitted another operation count");
  }
}

async function authorUndoRedoPeerEdit(adapter, fieldKind, label) {
  if (fieldKind === "object") {
    await adapter.set(["rating"], label.length);
  } else if (fieldKind === "map") {
    await adapter.mapSet(["items"], "peer", treeValue(label));
  } else {
    await adapter.arrayInsert(
      ["right"],
      0,
      [treeValue(`${label}-peer`)],
    );
  }
}

function checkpointFor(checkpoint, implementation) {
  return checkpoint.observations.find(
    (observation) => observation.implementation === implementation,
  );
}

function commitTrace(checkpoints, implementation) {
  return checkpoints.flatMap((checkpoint) =>
    checkpointFor(checkpoint, implementation)?.commits ?? []);
}

function treeField(tree, name) {
  return tree.value.fields.find(([field]) => field === name)?.[1];
}

function setTreeField(tree, name, value) {
  const fields = tree.value.fields;
  const index = fields.findIndex(([field]) => field === name);
  if (index >= 0) fields[index] = [name, value];
  else fields.push([name, value]);
  fields.sort(([left], [right]) => left.localeCompare(right));
}

function expectedUndoRedoTrees(baseline, cell) {
  const editLabel = `${cell.id}-edit`;
  const peerLabel = `${cell.id}-peer`;
  const authored = structuredClone(baseline);
  const concurrent = structuredClone(baseline);
  const undone = structuredClone(baseline);
  if (cell.fieldKind === "object") {
    const title = { kind: "string", value: editLabel };
    const rating = { kind: "number", value: cell.id.length };
    setTreeField(authored, "title", title);
    setTreeField(concurrent, "title", title);
    setTreeField(concurrent, "rating", rating);
    setTreeField(undone, "rating", rating);
  } else if (cell.fieldKind === "map") {
    treeField(authored, "items").entries.push([
      "target",
      { kind: "string", value: editLabel },
    ]);
    treeField(concurrent, "items").entries.push(
      ["target", { kind: "string", value: editLabel }],
      ["peer", { kind: "string", value: cell.id }],
    );
    treeField(undone, "items").entries.push([
      "peer",
      { kind: "string", value: cell.id },
    ]);
    for (const tree of [authored, concurrent, undone]) {
      treeField(tree, "items").entries.sort(([left], [right]) =>
        left.localeCompare(right));
    }
  } else {
    const authoredLeft = treeField(authored, "left").elements;
    const concurrentLeft = treeField(concurrent, "left").elements;
    const concurrentRight = treeField(concurrent, "right").elements;
    const undoneRight = treeField(undone, "right").elements;
    const peer = { kind: "string", value: peerLabel };
    if (cell.fieldKind === "array") {
      const edit = { kind: "string", value: editLabel };
      authoredLeft.unshift(edit);
      concurrentLeft.unshift(edit);
      concurrentRight.unshift(peer);
      undoneRight.unshift(peer);
    } else if (cell.fieldKind === "move") {
      const movedAuthored = authoredLeft.shift();
      treeField(authored, "right").elements.unshift(movedAuthored);
      const movedConcurrent = concurrentLeft.shift();
      if (cell.order === "a-first") {
        concurrentRight.unshift(movedConcurrent);
        concurrentRight.unshift(peer);
      } else {
        concurrentRight.unshift(peer);
        concurrentRight.unshift(movedConcurrent);
      }
      undoneRight.unshift(peer);
    } else {
      const edit = { kind: "string", value: editLabel };
      const nested = { kind: "string", value: `${editLabel}-nested` };
      authoredLeft.unshift(edit);
      treeField(authored, "right").elements.unshift(nested);
      concurrentLeft.unshift(edit);
      if (cell.order === "a-first") {
        concurrentRight.unshift(nested);
        concurrentRight.unshift(peer);
      } else {
        concurrentRight.unshift(peer);
        concurrentRight.unshift(nested);
      }
      undoneRight.unshift(peer);
    }
  }
  return { authored, concurrent, undone, redone: structuredClone(concurrent) };
}

async function writeUndoRedoArtifact(context, item, raw, kind = "undo-redo") {
  const relative = `${kind}/${safeName(item.id)}.json`;
  const path = join(context.artifactDirectory, relative);
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, `${JSON.stringify({
    formatVersion: 1,
    runId: context.runId,
    profileDigest: context.profileDigest,
    kind,
    subject: item.id,
    documentId: item.documentId,
    measured: Object.fromEntries(Object.entries(item)
      .filter(([name]) => name !== "artifacts")),
    raw,
  })}\n`, { mode: 0o600 });
  return relative;
}

async function writeUndoRedoFailure(context, identity, state, error, kind) {
  const relative = `${kind}-failure/${safeName(identity.id)}.json`;
  const path = join(context.artifactDirectory, relative);
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, `${JSON.stringify({
    formatVersion: 1,
    kind: `${kind}-failure`,
    runId: context.runId,
    profileDigest: context.profileDigest,
    subject: identity.id,
    documentId: state.documentId ?? null,
    identity,
    handleNames: [...new Set((state.undoRedo ?? [])
      .map(({ name }) => name).filter(Boolean))],
    commitKinds: (state.checkpoints ?? []).flatMap(({ observations }) =>
      observations.flatMap(({ commits }) =>
        (commits ?? []).filter(({ type }) => type === "commit")
          .map(({ kind: commitKind }) => commitKind))),
    settlements: (state.checkpoints ?? []).flatMap(({ observations }) =>
      observations.flatMap(({ commits }) =>
        (commits ?? []).filter(({ type }) => type === "settlement")
          .map(({ outcome }) => outcome))),
    eventTrace: state.checkpoints ?? [],
    primaryCheckpoint: error.primaryCheckpoint ?? error.checkpoint ?? null,
    drainCheckpoint: error.drainCheckpoint ?? null,
    undoRedo: state.undoRedo ?? [],
    error: replayError(error),
  })}\n`, { mode: 0o600 });
  return path;
}

function checkpointSequencedRevisions(checkpoints) {
  return [...new Set(checkpoints.flatMap(({ observations }) =>
    observations.flatMap(({ history }) =>
      (history?.trunk ?? []).flatMap((entry) => {
        const revision = entry.commit?.revision ?? entry.revision;
        return revision === undefined ? [] : [String(revision)];
      }))))]
    .map((revision) => ({ revision }));
}

export function acceptedTreeOperations(history) {
  return decodeTreeSubmissions(history).map((submission) => ({
    operationId: submission.commits.length > 0
      ? `revision:${submission.commits.map(({ originatorId, revision }) =>
        `${originatorId}:${revision}`).join(",")}`
      : `${submission.clientId}:${submission.clientSequenceNumber}`,
    clientId: submission.clientId,
    clientSequenceNumber: submission.clientSequenceNumber,
    outerSequenceNumber: submission.outerSequenceNumber,
    commits: submission.commits.map(
      ({ revision, originatorId, changeset }) => ({
        revision,
        originatorId,
        changeset,
      }),
    ),
  }));
}

async function runUndoRedoCell(config, context, cell) {
  const environment = await openUndoRedoEnvironment(
    config,
    context,
    cell.fieldKind,
    cell.id,
  );
  let failure;
  const failureState = {
    documentId: environment.documentId,
    checkpoints: [],
    undoRedo: [],
  };
  try {
    const { adapters, creator } = environment;
    const [author, peer] = cell.authors;
    let baseline = await settle(adapters);
    if (cell.fieldKind === "move") {
      await adapters.upstream.arrayInsert(
        ["left"],
        0,
        [treeValue(`${cell.id}-moved`)],
      );
      baseline = await settle(adapters);
    }
    const baselineTree = checkpointFor(baseline, author).wholeTree;
    const expectedSnapshots = expectedUndoRedoTrees(baselineTree, cell);
    await Promise.all(cell.authors.map((implementation) =>
      adapters[implementation].holdOutbound()));
    await authorUndoRedoEdit(adapters[author], cell.fieldKind, `${cell.id}-edit`);
    const retainedEdit = await adapters[author].retainLastLocalCommit("edit");
    await authorUndoRedoPeerEdit(adapters[peer], cell.fieldKind, cell.id);
    const authored = await captureCheckpoint(
      "undo-redo-authored",
      "intermediate",
      adapters,
    );
    failureState.checkpoints.push(authored);
    failureState.undoRedo.push({
      type: "retain",
      name: "edit",
      result: retainedEdit,
    });
    const releaseOrder = cell.order === "a-first"
      ? [author, peer]
      : [peer, author];
    for (const implementation of releaseOrder) {
      const checkpoint = checkpointFor(authored, implementation);
      await adapters[implementation].releaseOutbound({
        order: "fifo",
        duplicate: false,
      });
      await waitForAuthorSubmission(
        creator,
        adapters,
        implementation,
        checkpoint.sequenceNumber,
      );
    }
    const concurrent = await settle(adapters);
    failureState.checkpoints.push(concurrent);
    const undo = await adapters[author].revert("edit", true);
    failureState.undoRedo.push({ type: "undo", name: "edit", result: undo });
    const retainedUndo = await adapters[author].retainLastLocalCommit("undo");
    failureState.undoRedo.push({
      type: "retain",
      name: "undo",
      result: retainedUndo,
    });
    const undone = await settle(adapters);
    failureState.checkpoints.push(undone);
    const redo = await adapters[author].revert("undo", true);
    failureState.undoRedo.push({ type: "redo", name: "undo", result: redo });
    const redone = await settle(adapters);
    failureState.checkpoints.push(redone);
    const checkpoints = [authored, concurrent, undone, redone];
    const authorCommits = commitTrace(checkpoints, author);
    const localCommits = authorCommits.filter(
      ({ type, local }) => type === "commit" && local === true,
    );
    const settlements = authorCommits.filter(
      ({ type }) => type === "settlement",
    );
    const remoteCommits = commitTrace(checkpoints, peer).filter(
      ({ type, local }) => type === "commit" && local === false,
    );
    const actionEvidence = [
      {
        authoredEventIds: [retainedEdit.eventId],
        submittedRevisions: [retainedEdit.revision],
        outboundRecords: retainedEdit.outboundRecords,
      },
      undo,
      redo,
    ];
    assert(actionEvidence.every(({
      authoredEventIds,
      submittedRevisions,
      outboundRecords,
    }) =>
      authoredEventIds.length === 1
        && Number.isSafeInteger(authoredEventIds[0])
        && submittedRevisions.length === 1
        && typeof submittedRevisions[0] === "string"
        && submittedRevisions[0].length > 0
        && outboundRecords.filter(
          ({ classification }) => classification === "original",
        ).length === 1),
    `${cell.id} lacks action-scoped commit evidence`);
    const item = {
      ...cell,
      runId: context.runId,
      profileDigest: context.profileDigest,
      documentId: environment.documentId,
      snapshots: {
        authored: checkpointFor(authored, author).wholeTree,
        concurrent: checkpointFor(concurrent, author).wholeTree,
        undone: checkpointFor(undone, author).wholeTree,
        redone: checkpointFor(redone, author).wholeTree,
      },
      expectedSnapshots,
      localKinds: localCommits.slice(-3).map(({ kind }) => kind),
      factoryAvailability: [
        retainedEdit.factoryAvailable,
        retainedUndo.factoryAvailable,
        localCommits.at(-1)?.factoryAvailable,
      ],
      handleStatuses: [retainedEdit.status, undo.status, redo.status],
      settlements: settlements.slice(-3).map(({ outcome }) => outcome),
      authoredCounts: actionEvidence.map(
        ({ authoredEventIds }) => authoredEventIds.length,
      ),
      outboundCounts: actionEvidence.map(
        ({ outboundRecords }) => outboundRecords.filter(
          ({ classification }) => classification === "original",
        ).length,
      ),
      remoteFactoryAvailable: remoteCommits.some(
        ({ factoryAvailable }) => factoryAvailable,
      ),
      finalTree: checkpointFor(redone, author).wholeTree,
      passed: true,
      failed: false,
      skipped: false,
      error: null,
      artifacts: [],
    };
    assert.deepEqual(item.localKinds, ["Default", "Undo", "Redo"],
      `${cell.id} local kinds changed`);
    assert.deepEqual(item.settlements,
      ["FullyApplied", "FullyApplied", "FullyApplied"],
      `${cell.id} settlement outcomes changed`);
    assert.equal(item.remoteFactoryAvailable, false,
      `${cell.id} gave the peer a factory`);
    for (const phase of ["authored", "concurrent", "undone", "redone"]) {
      assert.deepEqual(item.snapshots[phase], expectedSnapshots[phase],
        `${cell.id} ${phase} tree changed`);
    }
    assert.deepEqual(item.finalTree, expectedSnapshots.redone,
      `${cell.id} final tree changed`);
    for (const checkpoint of checkpoints.slice(1)) {
      const first = checkpoint.observations[0].wholeTree;
      assert(checkpoint.observations.every(({ wholeTree }) =>
        isDeepStrictEqual(wholeTree, first)),
      `${cell.id} did not converge`);
    }
    const history = await serverHistory(creator);
    item.artifacts = [await writeUndoRedoArtifact(context, item, {
      checkpoints: Object.fromEntries([
        ["authored", authored],
        ["concurrent", concurrent],
        ["undone", undone],
        ["redone", redone],
      ].map(([phase, checkpoint]) => [
        phase,
        checkpointFor(checkpoint, author),
      ])),
      history,
      eventTrace: Object.fromEntries(implementations.map((implementation) => [
        implementation,
        commitTrace(checkpoints, implementation),
      ])),
      lifecycle: failureState.undoRedo,
      sequencedHistory: checkpointSequencedRevisions(checkpoints),
      acceptedOperationPayloads: history,
      acceptedOperations: acceptedTreeOperations(history),
      handleNames: ["edit", "undo"],
    })];
    return item;
  } catch (error) {
    failure = error;
    if (error.checkpoint) failureState.checkpoints.push(error.checkpoint);
    const drained = await captureFailureCheckpoint(
      "undo-redo-failure-drain",
      "intermediate",
      environment.adapters,
    );
    preserveFailureCheckpoints(error, drained.checkpoint);
    failureState.checkpoints.push(drained.checkpoint);
    error.drainErrors = drained.errors.map(replayError);
    try {
      error.failurePath = await writeUndoRedoFailure(
        context,
        cell,
        failureState,
        error,
        "undo-redo",
      );
    } catch (captureError) {
      error.artifactCaptureError = captureError;
    }
    throw error;
  } finally {
    await closeTransactionEnvironment(environment, failure);
  }
}

async function runUndoRedoReconnectTarget(config, context, implementation) {
  const id = `undo-redo-reconnect:${implementation}`;
  const environment = await openUndoRedoEnvironment(
    config,
    context,
    "object",
    id,
  );
  let failure;
  const failureState = { checkpoints: [] };
  try {
    const adapter = environment.adapters[implementation];
    const baseline = await settle(environment.adapters);
    const expectedTree = checkpointFor(baseline, implementation).wholeTree;
    await adapter.set(["title"], `${implementation}-reconnect`);
    const retained = await adapter.retainLastLocalCommit("edit");
    const edited = await settle(environment.adapters);
    await adapter.disconnect();
    await adapter.reconnect();
    const reconnectedStatus = await adapter.revertibleStatus("edit");
    const undo = await adapter.revert("edit", true);
    const postUndoStatus = await adapter.revertibleStatus("edit");
    const undone = await settle(environment.adapters);
    const commits = commitTrace([edited, undone], implementation);
    const settlement = commits.findLast(
      ({ type, kind }) => type === "settlement" && kind === "Undo",
    )?.outcome;
    const item = {
      id,
      implementation,
      runId: context.runId,
      profileDigest: context.profileDigest,
      documentId: environment.documentId,
      liveHandleBeforeDisconnect: retained.status,
      liveHandleAfterReconnect: reconnectedStatus.status,
      postUndoHandleStatus: postUndoStatus.status,
      undoKind: undo.authoredKind,
      settlement,
      authoredCount: undo.authoredCount,
      outboundCount: undo.outboundCount,
      finalTree: checkpointFor(undone, implementation).wholeTree,
      expectedTree,
      passed: true,
      failed: false,
      skipped: false,
      error: null,
      artifacts: [],
    };
    assert.deepEqual(item.finalTree, item.expectedTree,
      `${implementation} reconnect undo restored another tree`);
    const history = await serverHistory(environment.creator);
    item.artifacts = [await writeUndoRedoArtifact(context, item, {
      checkpoint: undone,
      eventTrace: commits,
      retained,
      reconnectLifecycle: {
        beforeDisconnect: retained,
        afterReconnect: reconnectedStatus,
        postUndo: postUndoStatus,
      },
      lifecycle: { ...undo, settlement },
      sequencedHistory: checkpointSequencedRevisions([undone]),
      acceptedOperationPayloads: history,
      acceptedOperations: acceptedTreeOperations(history),
      handleNames: ["edit"],
    }, "undo-redo-reconnect")];
    return item;
  } catch (error) {
    failure = error;
    if (error.checkpoint) failureState.checkpoints.push(error.checkpoint);
    const drained = await captureFailureCheckpoint(
      "undo-redo-reconnect-failure-drain",
      "intermediate",
      environment.adapters,
    );
    preserveFailureCheckpoints(error, drained.checkpoint);
    failureState.checkpoints.push(drained.checkpoint);
    error.drainErrors = drained.errors.map(replayError);
    try {
      error.failurePath = await writeUndoRedoFailure(
        context,
        { id, implementation },
        {
          documentId: environment.documentId,
          checkpoints: failureState.checkpoints,
          undoRedo: [],
        },
        error,
        "undo-redo-reconnect",
      );
    } catch (captureError) {
      error.artifactCaptureError = captureError;
    }
    throw error;
  } finally {
    await closeTransactionEnvironment(environment, failure);
  }
}

export async function runUndoRedoScenarios(config, context, {
  runCell = runUndoRedoCell,
  runReconnect = runUndoRedoReconnectTarget,
} = {}) {
  const concurrent = [];
  for (const cell of undoRedoConcurrentCells()) {
    concurrent.push(await runCell(config, context, cell));
  }
  const reconnect = [];
  for (const implementation of nativeTargets) {
    reconnect.push(await runReconnect(config, context, implementation));
  }
  const kindsByImplementation = new Map();
  for (const item of concurrent) {
    const implementation = item.authors[0];
    if (!kindsByImplementation.has(implementation)) {
      const kindItem = {
        id: implementation,
        implementation,
        localKinds: item.localKinds,
        factoryAvailability: item.factoryAvailability,
        handleStatuses: item.handleStatuses.slice(0, 2),
        settlements: item.settlements,
        authoredCounts: item.authoredCounts,
        outboundCounts: item.outboundCounts,
        finalTree: item.finalTree,
        sourceId: item.id,
        sourceArtifacts: item.artifacts,
        runId: item.runId,
        profileDigest: item.profileDigest,
        documentId: item.documentId,
        passed: item.passed,
        failed: item.failed,
        skipped: item.skipped,
        error: item.error,
        artifacts: [],
      };
      kindItem.artifacts = [await writeUndoRedoArtifact(context, kindItem, {
        sourceId: item.id,
        sourceArtifacts: item.artifacts,
      }, "undo-redo-kind")];
      kindsByImplementation.set(implementation, kindItem);
    }
  }
  const upstreamCell = await runCell(config, context, {
    id: "undo-redo-kinds:upstream",
    authors: ["upstream", "javascript"],
    fieldKind: "object",
    order: "a-first",
  });
  const upstreamKind = {
    id: "upstream",
    implementation: "upstream",
    localKinds: upstreamCell.localKinds,
    factoryAvailability: upstreamCell.factoryAvailability,
    handleStatuses: upstreamCell.handleStatuses.slice(0, 2),
    settlements: upstreamCell.settlements,
    authoredCounts: upstreamCell.authoredCounts,
    outboundCounts: upstreamCell.outboundCounts,
    finalTree: upstreamCell.finalTree,
    sourceId: upstreamCell.id,
    sourceArtifacts: upstreamCell.artifacts,
    runId: upstreamCell.runId,
    profileDigest: upstreamCell.profileDigest,
    documentId: upstreamCell.documentId,
    passed: upstreamCell.passed,
    failed: upstreamCell.failed,
    skipped: upstreamCell.skipped,
    error: upstreamCell.error,
    artifacts: [],
  };
  upstreamKind.artifacts = [await writeUndoRedoArtifact(
    context,
    upstreamKind,
    {
      sourceId: upstreamCell.id,
      sourceArtifacts: upstreamCell.artifacts,
    },
    "undo-redo-kind",
  )];
  kindsByImplementation.set("upstream", upstreamKind);
  return {
    kinds: {
      implementations: implementations.map((implementation) =>
        kindsByImplementation.get(implementation)),
    },
    concurrent,
    reconnect,
  };
}

export async function runIdentifierFields(config, context, {
  runPair = runIdentifierPair,
  failures = [],
} = {}) {
  assert(typeof context?.runId === "string" && context.runId.length > 0,
    "runIdentifierFields context requires runId");
  assert.match(context.profileDigest ?? "", /^[0-9a-f]{64}$/,
    "runIdentifierFields context requires profileDigest");
  assert(typeof context.identifierViewSchema === "string"
    && context.identifierViewSchema.length > 0,
  "runIdentifierFields context requires identifierViewSchema");
  assert(typeof context.artifactDirectory === "string"
    && context.artifactDirectory.length > 0,
  "runIdentifierFields context requires artifactDirectory");
  const pairs = [];
  for (const cell of identifierPairCells()) {
    pairs.push(await runPair(config, context, cell));
  }
  const refusals = [];
  for (const failure of failures) {
    refusals.push({
      ...failure,
      artifacts: [await writeIdentifierRefusalArtifact(context, failure)],
    });
  }
  return validateIdentifierFields({ pairs, failures: refusals });
}

function seededMeasuredPayload(item) {
  return {
    index: item.index,
    seed: item.seed,
    subSeed: item.subSeed,
    template: item.template,
    roles: item.roles,
    actions: item.actions,
    documentId: item.documentId,
    instanceIds: item.instanceIds,
    authorCoverage: item.authorCoverage,
    checkpoints: item.checkpoints,
    identityMapping: item.identityMapping,
    summaries: item.summaries,
    reloads: item.reloads,
    schemaTransitions: item.schemaTransitions,
    transactions: item.transactions,
    undoRedo: item.undoRedo,
    evidence: item.evidence,
  };
}

async function writeSeededArtifact(context, item, raw) {
  const relative = `seeded/${item.index}.json`;
  const path = join(context.artifactDirectory, relative);
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, `${JSON.stringify({
    formatVersion: 1,
    runId: context.runId,
    profileDigest: context.profileDigest,
    kind: "seeded",
    subject: String(item.index),
    documentId: item.documentId,
    measured: seededMeasuredPayload(item),
    raw,
  })}\n`, { mode: 0o600 });
  return relative;
}

function firstDifferencePath(left, right, path = "$") {
  if (Object.is(left, right)) return null;
  if (Array.isArray(left) && Array.isArray(right)) {
    const length = Math.max(left.length, right.length);
    for (let index = 0; index < length; index += 1) {
      const difference = firstDifferencePath(left[index], right[index], `${path}[${index}]`);
      if (difference !== null) return difference;
    }
    return null;
  }
  if (left && right && typeof left === "object" && typeof right === "object") {
    const keys = [...new Set([...Object.keys(left), ...Object.keys(right)])].sort();
    for (const key of keys) {
      const difference = firstDifferencePath(left[key], right[key],
        `${path}.${key}`);
      if (difference !== null) return difference;
    }
    return null;
  }
  return path;
}

function checkpointDifference(checkpoints) {
  const observations = checkpoints.at(-1)?.observations;
  if (!Array.isArray(observations) || observations.length < 2) return null;
  const [first, ...rest] = observations;
  for (const observation of rest) {
    const difference = firstDifferencePath(first.wholeTree, observation.wholeTree);
    if (difference !== null) return difference;
  }
  return null;
}

function identityMapping(adapters, decoded) {
  return Object.fromEntries(implementations.map((implementation) => {
    const clientIds = [...adapters[implementation].clientIds];
    const authored = decoded.filter(({ clientId }) =>
      adapters[implementation].clientIds.has(clientId));
    return [implementation, {
      instanceId: adapters[implementation].instanceId,
      clientIds,
      originatorIds: [...new Set(authored.flatMap(({ commits }) =>
        commits.map(({ originatorId }) => originatorId)))],
      revisions: authored.flatMap(({ commits }) =>
        commits.map(({ revision }) => revision)),
      sessionIds: [...new Set(authored.flatMap(({ allocations }) =>
        allocations.map(({ sessionId }) => sessionId)))],
    }];
  }));
}

function structuredNativeCause(error) {
  const seen = new Set();
  let current = error?.cause;
  while (current && typeof current === "object" && !seen.has(current)) {
    seen.add(current);
    if (typeof current.code === "string"
      && typeof current.operation === "string"
      && typeof current.message === "string") {
      return {
        code: current.code,
        operation: current.operation,
        message: current.message,
      };
    }
    current = current.cause;
  }
  return undefined;
}

function replayError(error) {
  const cause = structuredNativeCause(error);
  return {
    name: error?.name ?? "Error",
    message: error?.message ?? String(error),
    ...(error?.code === undefined ? {} : { code: error.code }),
    ...(cause === undefined ? {} : { cause }),
    ...(error?.stack === undefined ? {} : { stack: error.stack }),
  };
}

export async function writeSeededFailure(context, schedule, state, error) {
  const captureErrors = [];
  let history = [];
  let decoded = [];
  if (state.creator) {
    try {
      history = await serverHistory(state.creator);
    } catch (captureError) {
      captureErrors.push({
        operation: "read-sequenced-history",
        error: replayError(captureError),
      });
    }
  }
  try {
    decoded = decodeTreeSubmissions(history);
  } catch (captureError) {
    captureErrors.push({
      operation: "decode-sequenced-history",
      error: replayError(captureError),
    });
  }
  const mapping = state.adapters
    ? identityMapping(state.adapters, decoded)
    : Object.fromEntries(implementations.map((implementation) => [
      implementation,
      {
        instanceId: null,
        clientIds: [],
        originatorIds: [],
        revisions: [],
        sessionIds: [],
      },
    ]));
  const artifact = {
    formatVersion: 1,
    kind: "seeded-failure",
    runId: context.runId,
    profileDigest: context.profileDigest,
    reference: replayReference,
    service: replayService,
    seed: schedule.seed,
    index: schedule.index,
    subSeed: schedule.subSeed,
    profile: schedule.profile,
    schedule,
    originalDocumentId: state.documentId ?? null,
    identityMapping: mapping,
    checkpoints: state.checkpoints,
    rawSequencedOperations: history,
    summaries: state.summaries,
    captureErrors,
    failedAction: state.currentAction ?? null,
    actionIndex: state.currentAction?.index ?? null,
    action: state.currentAction
      ? Object.fromEntries(Object.entries(state.currentAction)
        .filter(([key]) => key !== "index"))
      : null,
    failedCheckpoint: error.checkpoint ?? null,
    primaryCheckpoint: error.primaryCheckpoint ?? error.checkpoint ?? null,
    drainCheckpoint: error.drainCheckpoint ?? null,
    schemaTransitions: state.schemaTransitions,
    transactions: state.transactions ?? [],
    undoRedo: state.undoRedo ?? [],
    handleNames: [...new Set((state.undoRedo ?? [])
      .map(({ name }) => name).filter(Boolean))],
    commitKinds: state.checkpoints.flatMap(({ observations }) =>
      observations.flatMap(({ commits }) =>
        (commits ?? []).filter(({ type }) => type === "commit")
          .map(({ kind }) => kind))),
    settlements: state.checkpoints.flatMap(({ observations }) =>
      observations.flatMap(({ commits }) =>
        (commits ?? []).filter(({ type }) => type === "settlement")
          .map(({ outcome }) => outcome))),
    eventTrace: state.checkpoints,
    drainErrors: state.drainErrors ?? [],
    firstDifferencePath: error.checkpoint ? checkpointDifference([error.checkpoint]) : null,
    error: replayError(error),
  };
  const path = join(context.artifactDirectory, "failure.json");
  await mkdir(dirname(path), { recursive: true });
  try {
    await writeFile(path, `${JSON.stringify(artifact)}\n`, {
      mode: 0o600,
      flag: "wx",
    });
  } catch (writeError) {
    if (writeError.code !== "EEXIST") throw writeError;
  }
  return path;
}

export async function freshReload(
  config, context, documentId, author, token, expectedTree,
  {
    createNative = nativeAdapter,
    createSession = openSession,
    profile = "object",
    view = profile === "schema" ? "optional" : undefined,
  } = {},
) {
  const store = profile === "map"
    ? mapServiceStore
    : profile === "schema"
      ? schemaEvolutionServiceStore
      : profile === "array"
        ? arrayServiceStore
        : profile === "identifier"
          ? identifierServiceStore
        : undefined;
  const viewSchema = profile === "map"
    ? context.mapViewSchema
    : profile === "schema"
      ? context.schemaViews[view]
      : profile === "array"
        ? context.arrayViewSchema
        : profile === "identifier"
          ? context.identifierViewSchema
        : context.viewSchema;
  if (author === "upstream") {
    const containers = [];
    let failure;
    try {
      const session = await createSession(config, containers, documentId, false, {
        cache: false,
        observeStorage: true,
        ...(store ? { store } : {}),
      });
      const adapter = upstreamAdapter(session, profile === "schema"
        ? schemaEvolutionConfigurations
        : undefined);
      if (profile === "schema") await adapter.openView(view);
      const observation = await adapter.checkpoint();
      assert.deepEqual(observation.wholeTree, expectedTree,
        "Fresh upstream reload observed another tree");
      return {
        author,
        instanceId: adapter.instanceId,
        observation,
        selectedSummaryRequests: session.storageObservations ?? [],
      };
    } catch (error) {
      failure = error;
      throw error;
    } finally {
      const cleanupErrors = [];
      for (const container of containers.toReversed()) {
        try {
          if (!container.closed) container.dispose();
        } catch (error) {
          cleanupErrors.push(error);
        }
      }
      if (cleanupErrors.length > 0) {
        if (failure) failure.cleanupErrors = [...(failure.cleanupErrors ?? []), ...cleanupErrors];
        else throw new AggregateError(cleanupErrors, "Fresh upstream reload cleanup failed");
      }
    }
  }
  const adapter = await createNative(author, config, {
    runId: context.runId,
    documentId,
    tenant: config.tenantId,
    viewSchema,
    ...(profile === "schema" ? { viewSchemas: context.schemaViews } : {}),
  }, token);
  let failure;
  try {
    await adapter.awaitSynced();
    if (profile === "schema") await adapter.openView(view);
    const observation = await adapter.checkpoint();
    assert.deepEqual(observation.wholeTree, expectedTree,
      `Fresh ${author} reload observed another tree`);
    return {
      author,
      instanceId: adapter.instanceId,
      observation,
      selectedSummaryRequests: adapter.evidence().http,
    };
  } catch (error) {
    failure = error;
    throw error;
  } finally {
    try {
      await adapter.close();
    } catch (error) {
      if (failure) failure.cleanupErrors = [...(failure.cleanupErrors ?? []), error];
      else throw error;
    }
  }
}

export async function executeScheduleAction(
  config,
  context,
  schedule,
  action,
  state,
) {
  const { adapters } = state;
  const preconditions = action.preconditions;
  for (const author of preconditions.connected ?? []) {
    assert.equal(state.connected[author], true,
      `${action.type} requires connected ${author}`);
  }
  for (const author of preconditions.disconnected ?? []) {
    assert.equal(state.connected[author], false,
      `${action.type} requires disconnected ${author}`);
  }
  if (action.author && preconditions.inboundHeld !== undefined) {
    assert.equal(state.held[action.author].inbound, preconditions.inboundHeld,
      `${action.type} has another inbound hold state`);
  }
  if (action.author && preconditions.outboundHeld !== undefined) {
    assert.equal(state.held[action.author].outbound, preconditions.outboundHeld,
      `${action.type} has another outbound hold state`);
  }
  if (preconditions.quiescent !== undefined) {
    assert.equal(state.quiescent, preconditions.quiescent,
      `${action.type} requires a quiescent barrier`);
  }
  if (preconditions.summaryAvailable !== undefined) {
    assert.equal(state.summaries.length > 0, preconditions.summaryAvailable,
      `${action.type} requires a published summary`);
  }
  if (action.type === "set") {
    await adapters[action.author].set(action.path, action.value);
    state.quiescent = false;
  } else if (action.type === "clear") {
    await adapters[action.author].clear(action.path);
    state.quiescent = false;
  } else if (action.type === "map-set") {
    await adapters[action.author].mapSet(action.path, action.key, action.value);
    state.quiescent = false;
  } else if (action.type === "map-delete") {
    await adapters[action.author].mapDelete(action.path, action.key);
    state.quiescent = false;
  } else if (action.type === "schema-compatibility") {
    const compatibility = await adapters[action.author]
      .schemaCompatibility(action.view);
    state.schemaTransitions.push({
      author: action.author,
      operation: action.type,
      view: action.view,
      compatibility,
    });
  } else if (action.type === "schema-upgrade") {
    await adapters[action.author].schemaUpgrade(action.view);
    state.schemaTransitions.push({
      author: action.author,
      operation: action.type,
      fromView: action.fromView,
      view: action.view,
    });
    state.quiescent = false;
  } else if (action.type === "open-view") {
    await adapters[action.author].openView(action.view);
    state.schemaTransitions.push({
      author: action.author,
      operation: action.type,
      view: action.view,
    });
  } else if (action.type === "array-insert") {
    await adapters[action.author].arrayInsert(action.path, action.index, action.values);
    state.quiescent = false;
  } else if (action.type === "array-remove") {
    await adapters[action.author].arrayRemove(action.path, action.start, action.end);
    state.quiescent = false;
  } else if (action.type === "array-move") {
    await adapters[action.author].arrayMove(
      action.sourcePath,
      action.sourceStart,
      action.sourceEnd,
      action.destinationPath,
      action.destinationGap,
    );
    state.quiescent = false;
  } else if (action.type === "transaction") {
    const scope = {
      constraints: action.constraints,
      edits: action.edits,
      result: action.result,
    };
    const result = await adapters[action.author].transaction(scope);
    const expected = action.result === "abort" ? "aborted" : "committed";
    assert.equal(result.outcome, expected,
      "Seeded transaction reported another outcome");
    assert.equal(result.callback.outcome, expected,
      "Seeded transaction callback reported another outcome");
    assert.equal(result.outboundCount, action.result === "abort" ? 0 : 1,
      "Seeded transaction queued another outbound operation count");
    state.transactions.push({
      author: action.author,
      constraints: action.constraints,
      requestedResult: action.result,
      outcome: result.outcome,
      editsApplied: result.callback.editsApplied,
      nestedScopes: result.callback.nested.length,
      commitRevision: result.commitRevision,
      outboundCount: result.outboundCount,
      events: result.events,
    });
    if (action.result !== "abort") state.quiescent = false;
  } else if (action.type === "retain") {
    const result = await adapters[action.author]
      .retainLastLocalCommit(action.name);
    state.undoRedo.push({
      type: "retain",
      author: action.author,
      name: action.name,
      lifecycle: action.lifecycle,
      result,
    });
  } else if (action.type === "revert") {
    const result = await adapters[action.author]
      .revert(action.name, action.dispose);
    state.undoRedo.push({
      type: action.lifecycle,
      lifecycle: action.lifecycle,
      author: action.author,
      name: action.name,
      dispose: action.dispose,
      result,
    });
    state.quiescent = false;
  } else if (action.type === "dispose") {
    const result = await adapters[action.author]
      .disposeRevertible(action.name);
    state.undoRedo.push({
      type: "dispose",
      lifecycle: action.lifecycle,
      author: action.author,
      name: action.name,
      result,
    });
  } else if (action.type === "hold-inbound") {
    await adapters[action.author].holdInbound();
    state.held[action.author].inbound = true;
  } else if (action.type === "hold-outbound") {
    await adapters[action.author].holdOutbound();
    state.held[action.author].outbound = true;
  } else if (action.type === "release") {
    const options = {
      order: action.order,
      duplicate: action.duplicate,
    };
    if (action.direction === "inbound") {
      const sequenceNumbers = state.deliveries
        .filter(({ direction }) => direction === "outbound")
        .flatMap(({ acceptedSequenceNumbers }) => acceptedSequenceNumbers);
      assert(sequenceNumbers.length > 0, "Inbound release lacks accepted tree submissions");
      const held = await adapters[action.author].awaitInbound(sequenceNumbers);
      const delivered = await adapters[action.author].releaseInbound(options);
      state.deliveries.push({
        author: action.author, direction: "inbound", order: action.order,
        ...held, ...delivered,
      });
    } else {
      const historyBefore = await serverHistory(state.creator);
      const afterSequence = historyBefore.at(-1)?.sequenceNumber ?? 0;
      const pending = state.checkpoints.at(-1).observations.find(
        ({ implementation }) => implementation === action.author,
      ).pendingTreeCount;
      assert(pending > 0, "Outbound release lacks a measured pending tree commit");
      await adapters[action.author].releaseOutbound(options);
      const accepted = await waitForAuthorSubmission(
        state.creator, adapters, action.author, afterSequence, pending,
      );
      const history = await serverHistory(state.creator, accepted.outerSequenceNumber);
      const submissions = decodeTreeSubmissions(history).filter((outer) =>
        outer.outerSequenceNumber > afterSequence
        && outer.outerSequenceNumber <= accepted.outerSequenceNumber
        && adapters[action.author].clientIds.has(outer.clientId)
        && outer.commits.length > 0);
      const acceptedCommitCount = submissions.reduce((count, { commits }) => count + commits.length, 0);
      assert.equal(acceptedCommitCount, pending, "Outbound release accepted another commit count");
      state.deliveries.push({
        author: action.author, direction: "outbound", order: action.order,
        afterSequence, pendingTreeCount: pending, acceptedCommitCount,
        acceptedSequenceNumbers: submissions.map(({ outerSequenceNumber }) => outerSequenceNumber),
      });
    }
    state.held[action.author][action.direction] = false;
    state.quiescent = false;
  } else if (action.type === "checkpoint") {
    const checkpoint = action.stage === "quiescent"
      ? await settle(adapters)
      : await captureCheckpoint(action.label, action.stage, adapters);
    checkpoint.label = action.label;
    state.checkpoints.push(checkpoint);
    state.quiescent = action.stage === "quiescent";
  } else if (action.type === "disconnect") {
    await adapters[action.author].disconnect();
    state.connected[action.author] = false;
    state.quiescent = false;
  } else if (action.type === "reconnect") {
    await adapters[action.author].reconnect();
    state.connected[action.author] = true;
    state.quiescent = false;
  } else if (action.type === "summarize") {
    const result = action.author === "upstream"
      ? await publishUpstreamSummary(
        config,
        state.containers,
        state.documentId,
        `Task 6 seeded ${schedule.index}`,
        schedule.profile === "map"
          ? { store: mapServiceStore }
          : schedule.profile === "schema"
            ? { store: schemaEvolutionServiceStore }
            : schedule.profile === "array"
              ? { store: arrayServiceStore }
              : schedule.profile === "identifier"
                ? { store: identifierServiceStore }
              : undefined,
      )
      : await adapters[action.author].summarize();
    state.summaries.push({
      author: action.author,
      result,
    });
    state.quiescent = true;
  } else if (action.type === "reload") {
    assert(state.summaries.length > 0, "Reload requires a published summary");
    const barrier = state.checkpoints.findLast(({ stage }) => stage === "quiescent");
    assert(barrier, "Reload requires a quiescent checkpoint");
    state.reloads.push(await freshReload(
      config,
      context,
      state.documentId,
      action.author,
      state.token,
      barrier.observations[0].wholeTree,
      { profile: schedule.profile, view: action.view },
    ));
    state.quiescent = true;
  } else {
    assert.fail(`Unknown seeded action: ${action.type}`);
  }
}

export async function runSeededSchedule(config, context, schedule) {
  validateRunnerContext("runSeededSchedule", context);
  validateSchedule(schedule);
  if (schedule.profile === "map") {
    assert(typeof context.mapViewSchema === "string"
      && context.mapViewSchema.length > 0,
    "runSeededSchedule context requires mapViewSchema");
  }
  if (schedule.profile === "schema") {
    assert(context.schemaViews && typeof context.schemaViews.v1 === "string"
      && typeof context.schemaViews.optional === "string",
    "runSeededSchedule context requires schemaViews");
  }
  if (schedule.profile === "array") {
    assert(typeof context.arrayViewSchema === "string"
      && context.arrayViewSchema.length > 0,
    "runSeededSchedule context requires arrayViewSchema");
  }
  if (schedule.profile === "identifier") {
    assert(typeof context.identifierViewSchema === "string"
      && context.identifierViewSchema.length > 0,
    "runSeededSchedule context requires identifierViewSchema");
  }
  const state = {
    adapters: undefined,
    checkpoints: [],
    currentAction: null,
    deliveries: [],
    connected: Object.fromEntries(implementations.map((implementation) =>
      [implementation, true])),
    containers: [],
    creator: undefined,
    documentId: undefined,
    natives: [],
    held: Object.fromEntries(implementations.map((implementation) => [
      implementation,
      { inbound: false, outbound: false },
    ])),
    quiescent: false,
    reloads: [],
    summaries: [],
    schemaTransitions: [],
    transactions: [],
    undoRedo: [],
    token: undefined,
  };
  let scheduleError;
  try {
    const store = schedule.profile === "map"
      ? mapServiceStore
      : schedule.profile === "schema"
        ? schemaEvolutionServiceStore
        : schedule.profile === "array"
          ? arrayServiceStore
          : schedule.profile === "identifier"
            ? identifierServiceStore
          : undefined;
    state.creator = await openSession(
      config,
      state.containers,
      undefined,
      false,
      store ? { store } : undefined,
    );
    state.documentId = state.creator.container.resolvedUrl.id;
    await publishUpstreamSummary(
      config,
      state.containers,
      state.documentId,
      `Task 6 seeded ${schedule.index} bootstrap`,
      store ? { store } : undefined,
    );
    const upstream = upstreamAdapter(await openSession(
      config,
      state.containers,
      state.documentId,
      false,
      store ? { store } : undefined,
    ), schedule.profile === "schema" ? schemaEvolutionConfigurations : undefined);
    const { jwt } = await tokenProvider(config)
      .fetchOrdererToken(config.tenantId, state.documentId);
    state.token = jwt;
    for (const target of nativeTargets) {
      state.natives.push(await nativeAdapter(target, config, {
        runId: context.runId,
        documentId: state.documentId,
        tenant: config.tenantId,
        viewSchema: schedule.profile === "map"
          ? context.mapViewSchema
          : schedule.profile === "schema"
            ? context.schemaViews.v1
            : schedule.profile === "array"
              ? context.arrayViewSchema
              : schedule.profile === "identifier"
                ? context.identifierViewSchema
              : context.viewSchema,
        ...(schedule.profile === "schema"
          ? { viewSchemas: context.schemaViews }
          : {}),
      }, jwt));
    }
    state.adapters = {
      upstream,
      javascript: state.natives[0],
      erlang: state.natives[1],
    };
    await Promise.all(nativeTargets.map((target) =>
      state.adapters[target].awaitSynced()));
    for (const [index, action] of schedule.actions.entries()) {
      state.currentAction = { index, ...structuredClone(action) };
      await executeScheduleAction(config, context, schedule, action, state);
    }
    const finalHistory = await serverHistory(state.creator);
    const decoded = decodedEvidence(finalHistory, state.adapters, implementations);
    const mapping = identityMapping(state.adapters, decoded.decoded);
    for (const implementation of implementations) {
      assert(mapping[implementation].originatorIds.length > 0,
        `${implementation} lacks an accepted non-noop submission`);
    }
    const intermediate = state.checkpoints.filter(({ stage }) => stage === "intermediate");
    for (const implementation of implementations) {
      assert(intermediate.some(({ observations }) => observations.some(
        ({ implementation: author, pendingTreeCount, inflightSubmissionCount }) =>
          author === implementation
          && (pendingTreeCount > 0 || inflightSubmissionCount > 0),
      )), `${implementation} lacks a measured pending checkpoint`);
    }
    const item = {
      index: schedule.index,
      seed: schedule.seed,
      subSeed: schedule.subSeed,
      template: schedule.template,
      profile: schedule.profile,
      roles: schedule.roles,
      actions: schedule.actions,
      runId: context.runId,
      profileDigest: context.profileDigest,
      documentId: state.documentId,
      instanceIds: Object.fromEntries(implementations.map((implementation) =>
        [implementation, state.adapters[implementation].instanceId])),
      authorCoverage: [...new Set(decoded.submissions.map(({ author }) => author))],
      checkpoints: state.checkpoints,
      identityMapping: mapping,
      summaries: state.summaries,
      reloads: state.reloads,
      schemaTransitions: state.schemaTransitions,
      transactions: state.transactions,
      undoRedo: state.undoRedo,
      evidence: {
        submissions: decoded.submissions,
        rawSequencedOperationCount: finalHistory.length,
        releases: state.deliveries,
      },
      artifacts: [],
      passed: true,
      skipped: false,
    };
    item.artifacts = [await writeSeededArtifact(context, item, {
      sequencedOperations: finalHistory,
      decoded: decoded.decoded,
      checkpoints: item.checkpoints,
      lifecycle: item.undoRedo,
      sequencedHistory: checkpointSequencedRevisions(item.checkpoints),
      acceptedOperationPayloads: finalHistory,
      acceptedOperations: acceptedTreeOperations(finalHistory),
      gates: Object.fromEntries(nativeTargets.map((target) =>
        [target, state.adapters[target].evidence()])),
    })];
    return item;
  } catch (error) {
    scheduleError = error;
    if (error.checkpoint) {
      error.checkpoint.label = state.currentAction?.label ?? error.checkpoint.label;
      state.checkpoints.push(error.checkpoint);
    }
    if (state.adapters) {
      const drained = await captureFailureCheckpoint(
        "seeded-failure-drain",
        "intermediate",
        state.adapters,
      );
      preserveFailureCheckpoints(error, drained.checkpoint);
      state.checkpoints.push(drained.checkpoint);
      state.drainErrors = [
        ...(state.drainErrors ?? []),
        ...drained.errors.map(replayError),
      ];
    }
    try {
      error.failurePath = await writeSeededFailure(context, schedule, state, error);
    } catch (captureError) {
      error.artifactCaptureError = captureError;
    }
    throw error;
  } finally {
    const cleanupErrors = [];
    for (const native of state.natives.toReversed()) {
      try {
        await native.close();
      } catch (error) {
        cleanupErrors.push(error);
      }
    }
    for (const container of state.containers.toReversed()) {
      try {
        if (!container.closed) container.dispose();
      } catch (error) {
        cleanupErrors.push(error);
      }
    }
    if (cleanupErrors.length > 0) {
      if (scheduleError) {
        scheduleError.cleanupErrors = [
          ...(scheduleError.cleanupErrors ?? []),
          ...cleanupErrors,
        ];
      }
      else throw new AggregateError(
        cleanupErrors,
        `Cleanup failed for seeded schedule ${schedule.index}`,
      );
    }
  }
}

export async function runSeededSchedules(config, context, schedules) {
  assert(Array.isArray(schedules), "Seeded producer must return an array");
  const results = [];
  for (const schedule of schedules) {
    results.push(await runSeededSchedule(config, context, schedule));
  }
  return {
    results,
    accounting: {
      requested: schedules.length,
      generated: schedules.length,
      executed: results.length,
      seed: schedules[0]?.seed,
      profiles: Object.fromEntries(
        ["object", "map", "schema", "array", "identifier"].map((profile) => [
        profile,
        results.filter((result) => result.profile === profile).length,
        ]),
      ),
    },
  };
}

export async function loadReplayArtifact(path, expected) {
  let artifact;
  try {
    artifact = JSON.parse(await readFile(path, "utf8"));
  } catch (error) {
    throw new Error(`Cannot read replay artifact: ${path}`, { cause: error });
  }
  return validateReplayArtifact(artifact, expected);
}

export function sameReplayFailure(original, replayed) {
  const observations = (artifact) => artifact.failedCheckpoint?.observations.map(
    ({ implementation, wholeTree, pendingTreeCount, inflightSubmissionCount }) =>
      ({ implementation, wholeTree, pendingTreeCount, inflightSubmissionCount }),
  );
  const actionFailure = original.failedCheckpoint === null
    && original.failedAction
    && original.failedAction?.type !== "checkpoint";
  return original.firstDifferencePath === replayed.firstDifferencePath
    && JSON.stringify(original.failedAction) === JSON.stringify(replayed.failedAction)
    && JSON.stringify(observations(original)) === JSON.stringify(observations(replayed))
    && original.error.name === replayed.error.name
    && original.error.code === replayed.error.code
    && original.error.message === replayed.error.message
    && (!actionFailure
      || original.error.cause === undefined
      || JSON.stringify(original.error.cause) === JSON.stringify(replayed.error.cause));
}

export async function replayFailure(
  config,
  context,
  artifact,
  { runSchedule = runSeededSchedule } = {},
) {
  validateRunnerContext("replayFailure", context);
  validateReplayArtifact(artifact, { profileDigest: context.profileDigest });
  try {
    const result = await runSchedule(config, context, artifact.schedule);
    return {
      mode: "replay",
      accepted: false,
      reproduced: false,
      originalRunId: artifact.runId,
      originalDocumentId: artifact.originalDocumentId,
      originalIdentityMapping: artifact.identityMapping,
      replayIdentityMapping: result.identityMapping,
      result,
    };
  } catch (error) {
    if (!error.failurePath) throw error;
    let replayArtifact;
    try {
      replayArtifact = await loadReplayArtifact(error.failurePath, {
        profileDigest: context.profileDigest,
      });
    } catch (artifactError) {
      return {
        mode: "replay",
        accepted: false,
        reproduced: false,
        originalRunId: artifact.runId,
        originalDocumentId: artifact.originalDocumentId,
        originalIdentityMapping: artifact.identityMapping,
        replayIdentityMapping: undefined,
        diagnostic: replayError(error),
        artifactDiagnostic: replayError(artifactError),
        failurePath: error.failurePath,
      };
    }
    return {
      mode: "replay",
      accepted: false,
      reproduced: sameReplayFailure(artifact, replayArtifact),
      originalRunId: artifact.runId,
      originalDocumentId: artifact.originalDocumentId,
      originalIdentityMapping: artifact.identityMapping,
      replayIdentityMapping: replayArtifact.identityMapping,
      diagnostic: replayError(error),
      failurePath: error.failurePath,
    };
  }
}

function validateRunnerContext(name, context) {
  assert(typeof context?.runId === "string" && context.runId.length > 0,
    `${name} context requires runId`);
  assert(typeof context.profileDigest === "string" && context.profileDigest.length > 0,
    `${name} context requires profileDigest`);
  assert(typeof context.viewSchema === "string" && context.viewSchema.length > 0,
    `${name} context requires viewSchema`);
  assert(typeof context.artifactDirectory === "string"
    && context.artifactDirectory.length > 0,
  `${name} context requires artifactDirectory`);
}

function localCommand(caseId) {
  switch (caseId) {
    case "clear-required-title":
      return { command: "clear", path: ["title"] };
    case "numeric-title":
      return {
        command: "set",
        path: ["title"],
        value: { kind: "number", value: 7 },
      };
    case "null-optional-note":
      return {
        command: "set",
        path: ["note"],
        value: { kind: "null" },
      };
    case "unknown-field":
      return {
        command: "set",
        path: ["notAField"],
        value: { kind: "string", value: "invalid" },
      };
    case "wrong-schema-id":
      return {
        command: "set",
        path: ["point"],
        value: {
          kind: "object",
          schemaId: "org.watershed.shared-tree.m1.NotPoint",
          fields: [
            ["x", { kind: "number", value: 1 }],
            ["y", { kind: "number", value: 2 }],
          ],
        },
      };
    default:
      assert.fail(`Unknown local refusal: ${caseId}`);
  }
}

function structuredStartupError(error) {
  let current = error;
  while (current) {
    if (current.kind === "startup-error"
      && typeof current.code === "string"
      && typeof current.operation === "string"
      && typeof current.message === "string") {
      return current;
    }
    current = current.cause;
  }
  return undefined;
}

function sequencedMessage(payload) {
  const pending = [payload];
  while (pending.length > 0) {
    const current = pending.pop();
    if (Array.isArray(current)) {
      pending.push(...current.toReversed());
    } else if (current && typeof current === "object") {
      if (Number.isSafeInteger(current.sequenceNumber)
        && current.type === "op"
        && current.contents !== undefined) {
        return current;
      }
      pending.push(...Object.values(current).toReversed());
    }
  }
  return undefined;
}

function encodedLike(original, value) {
  return typeof original === "string" ? JSON.stringify(value) : value;
}

function treeMessage(value) {
  const pending = [value];
  while (pending.length > 0) {
    const current = pending.pop();
    if (Array.isArray(current)) {
      pending.push(...current.toReversed());
    } else if (current && typeof current === "object") {
      if (Number.isSafeInteger(current.revision)
        && typeof current.originatorId === "string"
        && Array.isArray(current.changeset)
        && Number.isSafeInteger(current.version)) {
        return current;
      }
      pending.push(...Object.values(current).toReversed());
    }
  }
  return undefined;
}

function collectSequenceFields(value, fields = []) {
  if (Array.isArray(value)) {
    for (const item of value) collectSequenceFields(item, fields);
  } else if (value && typeof value === "object") {
    if (value.fieldKind === "Sequence" && Object.hasOwn(value, "change")) {
      fields.push(value);
    }
    for (const item of Object.values(value)) collectSequenceFields(item, fields);
  }
  return fields;
}

function corruptSequenceChange(caseId, data) {
  const fields = collectSequenceFields(data.changes);
  assert(fields.length > 0, `${caseId} injection found no Sequence V3 field`);
  const first = fields[0];
  switch (caseId) {
    case "malformed-sequence-payload":
      first.change = "not-an-array";
      break;
    case "malformed-range-count":
      first.change[0].count = 0;
      break;
    case "missing-range-endpoint": {
      const mark = fields.flatMap(({ change }) => change)
        .find(({ effect }) => effect?.moveIn);
      assert(mark, `${caseId} injection found no move-in endpoint`);
      mark.effect.moveIn.finalEndpoint = [];
      break;
    }
    case "bad-child-ownership": {
      const field = fields.find(({ change }) =>
        change.some(({ effect }) => effect?.moveOut));
      const index = field?.change.findIndex(({ effect }) => effect?.moveOut);
      assert(field && index >= 0, `${caseId} injection found no owned range`);
      field.change.splice(index + 1, 0, structuredClone(field.change[index]));
      break;
    }
    case "invalid-sequence-content":
      first.change[0].changes = { content: { kind: "unknown" } };
      break;
    default:
      assert.fail(`Unknown sequence injection: ${caseId}`);
  }
}

function mutateIdentifierFieldBatch(value, replacement) {
  if (!value || typeof value !== "object") return false;
  if (Array.isArray(value.shapes) && Array.isArray(value.data)) {
    const identifierShapes = new Set(value.shapes.flatMap((shape, index) =>
      shape?.c?.value === 0 ? [index] : []));
    const identifierFields = new Map(value.shapes.flatMap((shape, index) => {
      const fields = shape?.c?.fields;
      if (!Array.isArray(fields)) return [];
      const positions = fields.flatMap(([name, fieldShape], position) =>
        name === "id" && identifierShapes.has(fieldShape) ? [position + 1] : []);
      return positions.length > 0 ? [[index, positions]] : [];
    }));
    const pending = [value.data];
    while (pending.length > 0) {
      const current = pending.pop();
      if (!Array.isArray(current)) continue;
      if (identifierShapes.has(current[0])
        && (typeof current[1] === "string" || Number.isSafeInteger(current[1]))) {
        current[1] = replacement;
        return true;
      }
      for (const position of identifierFields.get(current[0]) ?? []) {
        if (typeof current[position] === "string"
          || Number.isSafeInteger(current[position])) {
          current[position] = replacement;
          return true;
        }
      }
      pending.push(...current);
    }
  }
  for (const child of Object.values(value)) {
    if (mutateIdentifierFieldBatch(child, replacement)) return true;
  }
  return false;
}

export function operationTransform(caseId, invalidProfile) {
  const mutations = invalidProfile.input.mutations;
  return (payload) => {
    const message = sequencedMessage(payload);
    assert(message, `${caseId} injection found no sequenced operation`);
    if (caseId === "unsupported-message-version") {
      const source = mutations.find(({ mutation }) => mutation === "message-version");
      const contents = parsed(message.contents);
      const inner = treeMessage(contents);
      assert(inner, `${caseId} injection found no SharedTree message`);
      inner.version = source.message.contents.version;
      message.contents = encodedLike(message.contents, contents);
    } else if (caseId === "unknown-runtime-message") {
      const source = mutations.find(
        ({ mutation }) => mutation === "unknown-required-change");
      const contents = parsed(message.contents);
      const inner = treeMessage(contents);
      assert(inner, `${caseId} injection found no SharedTree message`);
      inner.changeset = structuredClone(source.message.contents.changeset);
      message.contents = encodedLike(message.contents, contents);
    } else if (sequenceRefusalCases.has(caseId)) {
      const contents = parsed(message.contents);
      const inner = treeMessage(contents);
      assert(inner, `${caseId} injection found no SharedTree message`);
      const dataChange = inner.changeset.find(
        (change) => change && typeof change === "object" && !Array.isArray(change)
          && change.data && typeof change.data === "object"
          && !Array.isArray(change.data),
      );
      assert(dataChange, `${caseId} injection found no ModularChange payload`);
      corruptSequenceChange(caseId, dataChange.data);
      message.contents = encodedLike(message.contents, contents);
    } else if (caseId === "malformed-allocation-range") {
      const source = mutations.find(({ operation }) => operation === "finalizeCreationRange");
      const original = parsed(message.contents);
      const grouped = {
        type: "groupedBatch",
        contents: [
          {
            contents: {
              type: "idAllocation",
              contents: source.range,
            },
          },
          ...(original?.type === "groupedBatch" ? original.contents : [{
            contents: original,
          }]),
        ],
      };
      message.contents = encodedLike(message.contents, grouped);
    } else if (identifierOperationRefusalCases.has(caseId)) {
      const contents = parsed(message.contents);
      assert.equal(contents?.type, "groupedBatch",
        `${caseId} injection found no grouped Identifier operation`);
      if (caseId === "missing-allocation") {
        contents.contents = contents.contents.filter(
          (item) => item.contents?.type !== "idAllocation",
        );
        assert.equal(contents.contents.length, 1,
          `${caseId} injection found another grouped operation`);
        delete message.metadata?.groupedOpCount;
        delete message.metadata?.batchId;
        message.contents = encodedLike(
          message.contents,
          contents.contents[0].contents,
        );
        return payload;
      } else {
        const inner = treeMessage(contents);
        assert(inner, `${caseId} injection found no SharedTree message`);
        if (caseId === "wrong-originator") {
          inner.originatorId = "50000000-0000-4000-8000-000000000005";
        } else {
          assert(mutateIdentifierFieldBatch(inner, 1.5),
            `${caseId} injection found no numeric Identifier: ${
              JSON.stringify(inner).slice(0, 4000)
            }`);
        }
      }
      message.contents = encodedLike(message.contents, contents);
    } else {
      assert.fail(`Unknown operation injection: ${caseId}`);
    }
    return payload;
  };
}

function decodedStorageBody(bytes) {
  try {
    return JSON.parse(bytes.toString("utf8"));
  } catch {
    return undefined;
  }
}

export function storageTransform(caseId) {
  return (payload) => {
    const body = decodedStorageBody(payload.bytes);
    if (body === undefined) return undefined;
    if (caseId === "unsupported-summary-version") {
      if (typeof body?.content !== "string") return undefined;
      let decoded;
      try {
        const text = Buffer.from(body.content, body.encoding ?? "base64").toString("utf8");
        decoded = JSON.parse(text);
      } catch {
        return undefined;
      }
      if (!Number.isSafeInteger(decoded?.version)) return undefined;
      decoded.version = 999;
      body.content = Buffer.from(JSON.stringify(decoded)).toString("base64");
      body.encoding = "base64";
      return { ...payload, bytes: Buffer.from(JSON.stringify(body)) };
    }
    if (caseId === "missing-summary-blob") {
      if (typeof body?.content !== "string") return undefined;
      let decoded;
      try {
        decoded = JSON.parse(
          Buffer.from(body.content, body.encoding ?? "base64").toString("utf8"),
        );
      } catch {
        return undefined;
      }
      if (!Array.isArray(decoded?.keys) || decoded?.fields === undefined) {
        return undefined;
      }
      return {
        ...payload,
        status: 404,
        bytes: Buffer.from(JSON.stringify({ error: "missing forest blob" })),
      };
    }
    if (caseId === "corrupt-retained-summary") {
      if (typeof body?.content !== "string") return undefined;
      let decoded;
      try {
        decoded = JSON.parse(
          Buffer.from(body.content, body.encoding ?? "base64").toString("utf8"),
        );
      } catch {
        return undefined;
      }
      if (decoded?.version !== 2
        || !Array.isArray(decoded.data)
        || !Number.isSafeInteger(decoded.maxId)) return undefined;
      decoded.corruptSequenceRetainedState = {
        field: "DetachedFieldIndex",
        range: [2, 1],
      };
      body.content = Buffer.from(JSON.stringify(decoded)).toString("base64");
      body.encoding = "base64";
      return { ...payload, bytes: Buffer.from(JSON.stringify(body)) };
    }
    if (caseId === "negative-originatorless-summary") {
      if (typeof body?.content !== "string") return undefined;
      let decoded;
      try {
        decoded = JSON.parse(
          Buffer.from(body.content, body.encoding ?? "base64").toString("utf8"),
        );
      } catch {
        return undefined;
      }
      if (!mutateIdentifierFieldBatch(decoded, -1)) return undefined;
      body.content = Buffer.from(JSON.stringify(decoded)).toString("base64");
      body.encoding = "base64";
      return { ...payload, bytes: Buffer.from(JSON.stringify(body)) };
    }
    assert.fail(`Unknown storage injection: ${caseId}`);
  };
}

async function writeFailureArtifact(context, item, raw) {
  const relative = `failure/${safeName(item.id)}.json`;
  const path = join(context.artifactDirectory, relative);
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, `${JSON.stringify({
    formatVersion: 1,
    runId: context.runId,
    profileDigest: context.profileDigest,
    kind: "failure",
    subject: item.id,
    documentId: item.documentId,
    result: Object.fromEntries(Object.entries(item)
      .filter(([name]) => name !== "artifacts")),
    raw,
  })}\n`, { mode: 0o600 });
  return relative;
}

async function openControl(config, context, target) {
  const containers = [];
  let native;
  const close = async () => {
    const errors = [];
    try {
      if (native) await native.close();
    } catch (error) {
      errors.push(error);
    }
    for (const container of containers.toReversed()) {
      try {
        if (!container.closed) container.dispose();
      } catch (error) {
        errors.push(error);
      }
    }
    if (errors.length > 0) throw new AggregateError(errors, `${target} control cleanup failed`);
  };
  try {
    const creator = await openSession(config, containers);
    const documentId = creator.container.resolvedUrl.id;
    await publishUpstreamSummary(config, containers, documentId, `Task 5 ${target} control`);
    const observer = await openSession(config, containers, documentId);
    const { jwt } = await tokenProvider(config).fetchOrdererToken(config.tenantId, documentId);
    native = await nativeAdapter(target, config, {
      runId: context.runId,
      documentId,
      tenant: config.tenantId,
      viewSchema: context.viewSchema,
    }, jwt);
    await native.awaitSynced();
    return {
      async verify(label) {
        const title = `control-${safeName(label)}-${randomUUID()}`;
        await native.set(["title"], title);
        await native.awaitSynced();
        await until(() => observer.data.view.root.title === title,
          `${target} unrelated control observation`);
        return true;
      },
      close,
    };
  } catch (error) {
    try {
      await close();
    } catch (cleanupError) {
      error.cleanupErrors = [...(error.cleanupErrors ?? []), cleanupError];
    }
    throw error;
  }
}

export function interceptedTreeMessageCount(evidence) {
  return new Set([
    ...evidence.held.filter(({ direction, kind }) => direction === "outbound" && kind === "op"),
    ...evidence.outboundTreeMessages,
  ].map(({ id }) => id)).size;
}

async function runLocalFailure(config, context, cell, control) {
  const containers = [];
  let native;
  let failure;
  try {
    const creator = await openSession(config, containers);
    const documentId = creator.container.resolvedUrl.id;
    await publishUpstreamSummary(config, containers, documentId, `Task 5 ${cell.id}`);
    const observer = await openSession(config, containers, documentId);
    const { jwt } = await tokenProvider(config).fetchOrdererToken(
      config.tenantId,
      documentId,
    );
    native = await nativeAdapter(cell.target, config, {
      runId: context.runId,
      documentId,
      tenant: config.tenantId,
      viewSchema: context.viewSchema,
    }, jwt);
    await native.awaitSynced();
    await native.checkpoint();
    native.client.gate.hold("outbound", "op");
    const before = await native.checkpoint();
    const outboundBefore = interceptedTreeMessageCount(native.evidence());
    const reply = await native.client.request(localCommand(cell.caseId));
    assert.equal(reply.ok, false, `${cell.id} unexpectedly accepted the invalid edit`);
    const after = await native.checkpoint();
    const outboundTreeMessages =
      interceptedTreeMessageCount(native.evidence()) - outboundBefore;
    assert.deepEqual(after.wholeTree, before.wholeTree,
      `${cell.id} changed the whole tree`);
    assert.equal(after.pendingTreeCount, before.pendingTreeCount,
      `${cell.id} changed pending state`);
    assert.deepEqual(after.events, [], `${cell.id} emitted a visible-change event`);
    assert.equal(outboundTreeMessages, 0, `${cell.id} emitted tree traffic`);
    const continuedTitle = `continued-${randomUUID()}`;
    await native.set(["title"], continuedTitle);
    await until(() => interceptedTreeMessageCount(native.evidence()) > outboundBefore,
      `${cell.id} intercepted continuation submission`);
    assert.equal(interceptedTreeMessageCount(native.evidence()) - outboundBefore, 1,
      `${cell.id} emitted traffic before the valid continuation`);
    await native.releaseOutbound();
    await native.awaitSynced();
    await until(() => observer.data.view.root.title === continuedTitle,
      `${cell.id} continuation peer observation`);
    const accepted = decodeTreeSubmissions(await serverHistory(creator))
      .filter(({ outerSequenceNumber, clientId }) =>
        outerSequenceNumber > before.sequenceNumber && native.clientIds.has(clientId))
      .flatMap(({ commits }) => commits);
    assert.equal(accepted.length, 1,
      `${cell.id} sequenced an invalid edit in addition to the valid continuation`);
    const item = {
      ...cell,
      runId: context.runId,
      profileDigest: context.profileDigest,
      documentId,
      outcome: "refused",
      stage: cell.expectedStage,
      typedError: reply.error,
      clientState: "ready-local",
      partialMutationObserved: false,
      unrelatedDocumentPassed: await control.verify(cell.id),
      writableTreeExposedAfterRefusal: true,
      before: {
        root: before.wholeTree,
        pendingTreeCount: before.pendingTreeCount,
      },
      after: {
        root: after.wholeTree,
        pendingTreeCount: after.pendingTreeCount,
        events: after.events,
      },
      outboundTreeMessages,
      continuationPeerObserved: true,
      artifacts: [],
    };
    item.artifacts = [await writeFailureArtifact(context, item, {
      gate: native.evidence(),
      reply,
    })];
    return item;
  } catch (error) {
    failure = error;
    throw error;
  } finally {
    const cleanup = [];
    if (native) {
      try {
        await native.close();
      } catch (error) {
        cleanup.push(error);
      }
    }
    for (const container of containers.toReversed()) {
      try {
        if (!container.closed) container.dispose();
      } catch (error) {
        cleanup.push(error);
      }
    }
    if (cleanup.length > 0) {
      if (failure) failure.cleanupErrors = cleanup;
      else throw new AggregateError(cleanup, `Cleanup failed for ${cell.id}`);
    }
  }
}

async function expectedStartupFailure(
  config,
  context,
  cell,
  documentId,
  token,
  configureGate,
) {
  let client;
  let startupFailure;
  try {
    client = await startClient(cell.target, {
      runId: context.runId,
      documentId,
      tenant: config.tenantId,
      viewSchema: context.viewSchema,
    }, { socketUrl: config.socketUrl, token }, {
      gateFactory: async (host, port) => {
        const gate = await DeliveryGate.open(host, port, { documentId });
        if (configureGate) configureGate(gate);
        return gate;
      },
    });
    await client.request({ command: "subscribe" });
  } catch (error) {
    startupFailure = error;
  } finally {
    if (client) await client.close();
  }
  assert(startupFailure, `${cell.id} exposed a ready client`);
  const typed = structuredStartupError(startupFailure);
  assert(typed,
    `${cell.id} failed without a structured startup diagnostic: `
      + `${startupFailure.message}; cause=${JSON.stringify(startupFailure.cause)}`);
  return {
    typed,
    gateEvidence: client?.gate.evidence() ?? { injections: [] },
  };
}

async function runStoredSchemaFailure(config, context, cell, control) {
  const containers = [];
  const kind = "map";
  try {
    const store = excludedStores[kind];
    const creator = await openSession(config, containers, undefined, false, { store });
    const documentId = creator.container.resolvedUrl.id;
    await publishUpstreamSummary(
      config,
      containers,
      documentId,
      `Task 5 ${cell.id}`,
      { store },
    );
    const { jwt } = await tokenProvider(config).fetchOrdererToken(
      config.tenantId,
      documentId,
    );
    const refusal = await expectedStartupFailure(
      config,
      context,
      cell,
      documentId,
      jwt,
    );
    const item = {
      ...cell,
      runId: context.runId,
      profileDigest: context.profileDigest,
      documentId,
      outcome: "refused",
      stage: cell.expectedStage,
      typedError: refusal.typed,
      clientState: "never-ready",
      partialMutationObserved: false,
      unrelatedDocumentPassed: await control.verify(cell.id),
      writableTreeExposedAfterRefusal: false,
      artifacts: [],
    };
    item.artifacts = [await writeFailureArtifact(context, item, {
      storedSchema: kind,
      gate: refusal.gateEvidence,
    })];
    return item;
  } finally {
    for (const container of containers.toReversed()) {
      if (!container.closed) container.dispose();
    }
  }
}

async function runInjectedFailure(config, context, cell, control, invalidProfile) {
  const containers = [];
  let native;
  let rawClient;
  let failure;
  try {
    const sequenceRefusal = sequenceRefusalCases.has(cell.caseId);
    const identifierRefusal = identifierRefusalCases.has(cell.caseId);
    const sessionOptions = sequenceRefusal
      ? { store: arrayServiceStore }
      : identifierRefusal
        ? { store: identifierServiceStore }
        : undefined;
    const creator = await openSession(
      config,
      containers,
      undefined,
      false,
      sessionOptions,
    );
    const documentId = creator.container.resolvedUrl.id;
    if (sequenceRefusal) {
      const creatorAdapter = upstreamAdapter(creator);
      await creatorAdapter.arrayInsert(["left"], 0, [
        { kind: "string", value: "sequence-control" },
        { kind: "string", value: "sequence-control-tail" },
      ]);
      await creatorAdapter.arrayInsert(["right"], 0, [
        { kind: "string", value: "sequence-destination" },
      ]);
      await creatorAdapter.awaitSynced();
    } else if (identifierRefusal) {
      const creatorAdapter = upstreamAdapter(creator);
      await creatorAdapter.arrayInsert(["left"], 0, [
        identifierPoint(`failure-${cell.caseId}`),
      ]);
      await creatorAdapter.awaitSynced();
    }
    await publishUpstreamSummary(
      config,
      containers,
      documentId,
      `Task 5 ${cell.id}`,
      sessionOptions,
    );
    const upstreamSession = await openSession(
      config,
      containers,
      documentId,
      false,
      sessionOptions,
    );
    const upstream = upstreamAdapter(upstreamSession);
    const { jwt } = await tokenProvider(config).fetchOrdererToken(
      config.tenantId,
      documentId,
    );
    if (cell.clientState === "never-ready") {
      const refusal = await expectedStartupFailure(
        config,
        context,
        cell,
        documentId,
        jwt,
        (gate) => gate.inject({
          documentId,
          mutation: cell.caseId,
          expectedStage: cell.expectedStage,
          direction: "inbound",
          kind: "summary-load",
          transform: storageTransform(cell.caseId),
        }),
      );
      assert.equal(refusal.gateEvidence.injections.length, 1,
        `${cell.id} did not inject one storage response`);
      const item = {
        ...cell,
        runId: context.runId,
        profileDigest: context.profileDigest,
        documentId,
        outcome: "refused",
        stage: cell.expectedStage,
        typedError: refusal.typed,
        clientState: "never-ready",
        partialMutationObserved: false,
        unrelatedDocumentPassed: await control.verify(cell.id),
        writableTreeExposedAfterRefusal: false,
        injected: true,
        artifacts: [],
      };
      item.artifacts = [await writeFailureArtifact(context, item, {
        gate: refusal.gateEvidence,
      })];
      return item;
    }
    native = await nativeAdapter(cell.target, config, {
      runId: context.runId,
      documentId,
      tenant: config.tenantId,
      viewSchema: sequenceRefusal
        ? context.arrayViewSchema
        : identifierRefusal
          ? context.identifierViewSchema
          : context.viewSchema,
    }, jwt);
    await native.awaitSynced();
    const before = await native.checkpoint();
    native.client.gate.inject({
      documentId,
      mutation: cell.caseId,
      expectedStage: cell.expectedStage,
      direction: "inbound",
      kind: "op",
      transform: operationTransform(cell.caseId, invalidProfile),
    });
    if (sequenceRefusal) {
      await upstream.arrayMove(["left"], 0, 1, ["right"], 0);
    } else if (identifierRefusal) {
      const id = cell.caseId === "corrupt-numeric-identifier"
        ? creator.data.view.root.left[0].id
        : undefined;
      await upstream.arrayInsert(["right"], 0, [
        identifierPoint(`trigger-${cell.caseId}`, id),
      ]);
    } else {
      upstreamSession.data.view.root.title = `trigger-${randomUUID()}`;
    }
    await until(
      () => !upstreamSession.container.isDirty,
      `${cell.id} trigger sequencing`,
    );
    await until(
      () => native.evidence().injections.length === 1,
      `${cell.id} injected operation delivery`,
    );
    let typed;
    try {
      const reply = await native.client.request({
        command: "await-synced",
        minimumSequenceNumber: before.sequenceNumber + 1,
      });
      assert.equal(reply.ok, false, `${cell.id} remained writable after semantic failure`);
      typed = reply.error;
    } catch (error) {
      typed = structuredStartupError(error) ?? {
        code: "connection-failed",
        operation: "await-synced",
        message: error.message,
      };
    }
    let terminalCheckpoint;
    try {
      terminalCheckpoint = await native.client.request({ command: "checkpoint" });
    } catch (error) {
      assert.match(error.message, /exited|closed|failed|timed out/i,
        `${cell.id} checkpoint failed for an unrelated reason`);
    }
    if (terminalCheckpoint !== undefined) {
      const checkpoint = terminalCheckpoint;
      assert.equal(checkpoint.ok, false,
        `${cell.id} exposed a successful checkpoint after terminal failure`);
    }
    const item = {
      ...cell,
      runId: context.runId,
      profileDigest: context.profileDigest,
      documentId,
      outcome: "refused",
      stage: cell.expectedStage,
      typedError: typed,
      clientState: "stopped-after-ready",
      partialMutationObserved: false,
      unrelatedDocumentPassed: await control.verify(cell.id),
      writableTreeExposedAfterRefusal: false,
      injected: true,
      artifacts: [],
    };
    item.artifacts = [await writeFailureArtifact(context, item, {
      before,
      gate: native.evidence(),
    })];
    return item;
  } catch (error) {
    failure = error;
    throw error;
  } finally {
    const cleanup = [];
    for (const client of [native, rawClient].filter(Boolean).toReversed()) {
      try {
        await client.close();
      } catch (error) {
        cleanup.push(error);
      }
    }
    for (const container of containers.toReversed()) {
      try {
        if (!container.closed) container.dispose();
      } catch (error) {
        cleanup.push(error);
      }
    }
    if (cleanup.length > 0) {
      if (failure) failure.cleanupErrors = cleanup;
      else throw new AggregateError(cleanup, `Cleanup failed for ${cell.id}`);
    }
  }
}

export async function runFailureCases(config, context, { createControl = openControl } = {}) {
  validateRunnerContext("runFailureCases", context);
  const invalidProfile = JSON.parse(await readFile(invalidProfilePath, "utf8"));
  assert.equal(invalidProfile.id, "invalid-profile",
    "Task 5 requires the pinned invalid-profile corpus");
  const controls = {};
  const results = [];
  let failure;
  try {
    for (const target of nativeTargets) {
      controls[target] = await createControl(config, context, target);
    }
    for (const cell of requiredFailureCells()) {
      const control = controls[cell.target];
      try {
        if (cell.kind === "local-refusal") {
          results.push(await runLocalFailure(config, context, cell, control));
        } else if (cell.kind === "stored-schema-refusal") {
          results.push(await runStoredSchemaFailure(config, context, cell, control));
        } else {
          results.push(await runInjectedFailure(
            config,
            context,
            cell,
            control,
            invalidProfile,
          ));
        }
      } catch (error) {
        throw new Error(`Failure case ${cell.id} failed: ${error.message}`, {
          cause: error,
        });
      }
    }
    return results;
  } catch (error) {
    failure = error;
    throw error;
  } finally {
    const cleanup = [];
    for (const control of Object.values(controls).toReversed()) {
      try {
        await control.close();
      } catch (error) {
        cleanup.push(error);
      }
    }
    if (cleanup.length > 0) {
      if (failure) failure.cleanupErrors = cleanup;
      else throw new AggregateError(cleanup, "Task 5 control cleanup failed");
    }
  }
}
