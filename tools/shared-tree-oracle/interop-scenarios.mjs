import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import {
  SchemaFactory,
  TreeViewConfiguration,
} from "fluid-framework/alpha";
import { SharedMap } from "@fluidframework/map/internal";
import {
  defineDataStore,
  sharedObjectRegistryFromIterable,
} from "@fluidframework/shared-object-base/internal";
import { SharedTree } from "@fluidframework/tree/internal";
import { Tree } from "@fluidframework/tree/internal";
import { startClient } from "./client-driver.mjs";
import { DeliveryGate } from "./delivery-gate.mjs";
import { mapServiceStore, openSession, tokenProvider } from "./service.mjs";
import { DynamicMap, MapPoint } from "./schema.mjs";

const implementations = ["upstream", "javascript", "erlang"];
const nativeTargets = ["javascript", "erlang"];
const seededTemplates = [
  "multiple-pending",
  "optional-conflict",
  "parent-child-conflict",
  "nested-conflict",
];
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
const invalidProfilePath = join(
  import.meta.dirname,
  "../../test/fixtures/shared_tree/cases/invalid-profile.json",
);

const excludedFactory = new SchemaFactory("org.watershed.shared-tree.m1");
const ExcludedArray = excludedFactory.array("ExcludedArray", [excludedFactory.number]);
const ExcludedMap = excludedFactory.map("ExcludedMap", [excludedFactory.number]);

function excludedStore(kind) {
  const schema = kind === "array" ? ExcludedArray : ExcludedMap;
  const config = new TreeViewConfiguration({ schema });
  return defineDataStore({
    type: `org.watershed.shared-tree.m1.excluded-${kind}`,
    registry: sharedObjectRegistryFromIterable([SharedMap, SharedTree]),
    async instantiateFirstTime(rootCreator, creator) {
      const bootstrap = await rootCreator.createSharedObject(SharedMap);
      const tree = await creator.createSharedObject(SharedTree);
      const view = tree.viewWith(config);
      view.initialize(kind === "array"
        ? new ExcludedArray([1, 2])
        : new ExcludedMap([["key", 1]]));
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

const excludedStores = {
  array: excludedStore("array"),
  map: excludedStore("map"),
};

function parsed(value) {
  return typeof value === "string" ? JSON.parse(value) : value;
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
    if (outer?.type !== "groupedBatch" || !Array.isArray(outer.contents)) return [];
    const allocations = outer.contents.flatMap((item) => {
      if (item.contents?.type !== "idAllocation") return [];
      const decoded = allocation(item.contents.contents);
      return decoded ? [decoded] : [];
    });
    const batchId = outer.contents
      .map(({ metadata }) => metadata?.batchId)
      .find((value) => typeof value === "string" && value.length > 0);
    const commits = outer.contents.flatMap((item, innerIndex) => {
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
];

const localRefusals = [
  ["clear-required-title", "clear", ["title", "required field"]],
  ["numeric-title", "set", ["title", "leaf.number"]],
  ["null-optional-note", "set", ["note", "leaf.null"]],
  ["unknown-field", "set", ["notAField", "unknown field"]],
  ["wrong-schema-id", "set", ["NotPoint", "node type"]],
];
const injectedRefusals = [
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
  ...["array", "map"].flatMap((kind) =>
    nativeTargets.map((target) => ({
      id: `unsupported-${kind}-schema:${target}`,
      caseId: `unsupported-${kind}-schema`,
      target,
      kind: "stored-schema-refusal",
      expectedStage: "resolve-view",
      errorCode: kind === "array"
        ? "bootstrap-failed"
        : "view-resolution-failed",
      errorOperation: kind === "array" ? "connect" : "resolve-view",
      diagnosticTerms: kind === "array"
        ? ["ExcludedArray", "unsupported field kind Sequence"]
        : ["root", "incompatible field schema"],
      clientState: "never-ready",
    }))),
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
      pathType: pathTypes[path[0]],
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

export function generateSchedules({ seed, iterations }) {
  assert(Number.isSafeInteger(seed) && seed >= 0 && seed <= 0xffff_ffff,
    "Schedule seed must be an unsigned 32-bit integer");
  assert(Number.isSafeInteger(iterations) && iterations >= 0,
    "Schedule iterations must be a nonnegative integer");
  return Array.from({ length: iterations }, (_, index) => {
    const subSeed = scheduleSubSeed(seed, index);
    let state = subSeed;
    const random = () => {
      state ^= state << 13;
      state ^= state >>> 17;
      state ^= state << 5;
      return state >>>= 0;
    };
    const template = seededTemplates[random() % seededTemplates.length];
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
    return {
      formatVersion: 1,
      index,
      seed,
      subSeed,
      template,
      authors: [...implementations],
      roles,
      actions: generatedActions(seed, index, template, roles, random),
    };
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
  const expected = generateSchedules({
    seed: schedule.seed,
    iterations: schedule.index + 1,
  })[schedule.index];
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
  assert(Array.isArray(artifact.checkpoints),
    "Replay artifact lacks checkpoints");
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

function setUpstream(root, path, value) {
  assert(path.length > 0, "Upstream path must not be empty");
  let parent = root;
  for (const segment of path.slice(0, -1)) {
    parent = parent instanceof DynamicMap ? parent.get(segment) : parent[segment];
    assert(parent !== undefined, `Missing upstream path segment: ${segment}`);
  }
  const field = path.at(-1);
  if (parent instanceof DynamicMap) parent.set(field, value);
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

function mapTreeValue(value) {
  if (value === null) return { kind: "null" };
  if (typeof value === "string") return { kind: "string", value };
  if (typeof value === "number") return { kind: "number", value };
  if (typeof value === "boolean") return { kind: "boolean", value };
  if (value instanceof MapPoint) {
    return {
      kind: "object",
      schemaId: "org.watershed.shared-tree.m2.Point",
      fields: [
        ["x", mapTreeValue(value.x)],
        ["y", mapTreeValue(value.y)],
      ],
    };
  }
  if (value instanceof DynamicMap) {
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
    node instanceof DynamicMap ? node.get(segment) : node[segment], root);
  assert(value instanceof DynamicMap, `Path is not a dynamic map: ${path.join(".")}`);
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

export function upstreamAdapter(session) {
  const instanceId = randomUUID();
  const events = [];
  const connectionEvents = [];
  session.container.deltaManager.on("disconnect", (reason, error) => {
    connectionEvents.push({ reason, ...(error ? { error: replayError(error) } : {}) });
  });
  let connected = session.container.connected;
  Tree.on(session.data.view.root, "treeChanged", () => events.push({ kind: "treeChanged" }));
  const clientIds = new Set();
  if (session.container.clientId) clientIds.add(session.container.clientId);
  return {
    implementation: "upstream",
    instanceId,
    session,
    clientIds,
    connectionEvents,
    async set(path, value) {
      setUpstream(session.data.view.root, path, value);
    },
    async clear(path) {
      assert.deepEqual(path, ["note"], "Only the optional note can be cleared");
      delete session.data.view.root.note;
    },
    async mapGet(path, key) {
      const map = mapAt(session.data.view.root, path);
      return map.has(key)
        ? { present: true, value: canonicalValue(mapTreeValue(map.get(key))) }
        : { present: false };
    },
    async mapSet(path, key, value) {
      mapAt(session.data.view.root, path).set(key, upstreamMapValue(value));
    },
    async mapDelete(path, key) {
      mapAt(session.data.view.root, path).delete(key);
    },
    async mapKeys(path) {
      return canonicalMapKeys(mapAt(session.data.view.root, path).keys());
    },
    async mapEntries(path) {
      return canonicalMapEntries(
        [...mapAt(session.data.view.root, path).entries()]
          .map(([key, value]) => [key, mapTreeValue(value)]),
      );
    },
    async checkpoint() {
      if (session.container.clientId) clientIds.add(session.container.clientId);
      const captured = events.splice(0);
      return {
        implementation: "upstream",
        instanceId,
        sequenceNumber: session.container.deltaManager.lastSequenceNumber,
        pendingTreeCount: pendingTreeCommits(session),
        inflightSubmissionCount: session.container.deltaManager.outbound.length,
        wholeTree: canonicalValue(session.data.view.root.items instanceof DynamicMap
          ? mapRootValue(session.data.view.root)
          : rootValue(session.data.view.root)),
        events: captured,
        clientId: session.container.clientId,
        connectionEvents: [...connectionEvents],
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
    async checkpoint() {
      const reply = success(await client.request({ command: "checkpoint" }),
        `${target} checkpoint`);
      if (reply.observation.clientId) clientIds.add(reply.observation.clientId);
      return {
        implementation: target,
        instanceId: client.instanceId,
        sequenceNumber: reply.sequenceNumber,
        pendingTreeCount: reply.observation.pendingTreeCount,
        inflightSubmissionCount: reply.observation.inFlightCount,
        wholeTree: canonicalValue(reply.result.root),
        events: reply.result.events,
        clientId: reply.observation.clientId,
        reconnectRetries: structuredClone(reconnectRetries),
      };
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
    async summarize() {
      return success(await client.request({ command: "summarize" }),
        `${target} summarize`).result;
    },
    evidence() {
      return {
        ...client.gate.evidence(),
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
  return acknowledged.data;
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

async function captureCheckpoint(label, stage, adapters) {
  const observations = await Promise.all(implementations.map((implementation) =>
    adapters[implementation].checkpoint()));
  return { label, stage, observations };
}

export async function settle(adapters) {
  let observations;
  const events = Object.fromEntries(implementations.map((implementation) => [implementation, []]));
  const observe = async () => {
    const captured = await Promise.all(implementations.map((implementation) =>
      adapters[implementation].checkpoint()));
    observations = captured.map((observation) => {
      events[observation.implementation].push(...observation.events);
      return { ...observation, events: [...events[observation.implementation]] };
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
    error.checkpoint = { label: "settled", stage: "failed", observations: observations ?? [] };
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
  const baseline = await Promise.all(cell.authors.map((author) =>
    adapters[author].checkpoint()));
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
        viewSchema: context.viewSchema,
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
            ...await Promise.all(nativeTargets.map((implementation) =>
              adapters[implementation].checkpoint())),
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
      const baseline = await Promise.all(implementations.map((implementation) =>
        adapters[implementation].checkpoint()));
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
      const beforeReconnect = await Promise.all(implementations.map((implementation) =>
        adapters[implementation].checkpoint()));
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

export async function runDeterministicCases(
  config,
  context,
  { runObject = runCell, runMap = runMapCell } = {},
) {
  assert(typeof context?.runId === "string" && context.runId.length > 0,
    "runDeterministicCases context requires runId");
  assert(typeof context.profileDigest === "string" && context.profileDigest.length > 0,
    "runDeterministicCases context requires profileDigest");
  assert(typeof context.viewSchema === "string" && context.viewSchema.length > 0,
    "runDeterministicCases context requires viewSchema");
  assert(typeof context.mapViewSchema === "string" && context.mapViewSchema.length > 0,
    "runDeterministicCases context requires mapViewSchema");
  assert(typeof context.artifactDirectory === "string"
    && context.artifactDirectory.length > 0,
  "runDeterministicCases context requires artifactDirectory");
  const results = [];
  for (const cell of requiredScenarioCells()) {
    results.push(await (cell.profile === "map" ? runMap : runObject)(
      config,
      context,
      cell,
    ));
  }
  return results;
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

function replayError(error) {
  return {
    name: error?.name ?? "Error",
    message: error?.message ?? String(error),
    ...(error?.code === undefined ? {} : { code: error.code }),
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
    schedule,
    originalDocumentId: state.documentId ?? null,
    identityMapping: mapping,
    checkpoints: state.checkpoints,
    rawSequencedOperations: history,
    summaries: state.summaries,
    captureErrors,
    failedAction: state.currentAction ?? null,
    failedCheckpoint: error.checkpoint ?? null,
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
  { createNative = nativeAdapter, createSession = openSession } = {},
) {
  if (author === "upstream") {
    const containers = [];
    let failure;
    try {
      const session = await createSession(config, containers, documentId, false, {
        cache: false,
        observeStorage: true,
      });
      const adapter = upstreamAdapter(session);
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
    viewSchema: context.viewSchema,
  }, token);
  let failure;
  try {
    await adapter.awaitSynced();
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
    ));
    state.quiescent = true;
  } else {
    assert.fail(`Unknown seeded action: ${action.type}`);
  }
}

export async function runSeededSchedule(config, context, schedule) {
  validateRunnerContext("runSeededSchedule", context);
  validateSchedule(schedule);
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
    token: undefined,
  };
  let scheduleError;
  try {
    state.creator = await openSession(config, state.containers);
    state.documentId = state.creator.container.resolvedUrl.id;
    await publishUpstreamSummary(
      config,
      state.containers,
      state.documentId,
      `Task 6 seeded ${schedule.index} bootstrap`,
    );
    const upstream = upstreamAdapter(await openSession(
      config, state.containers, state.documentId,
    ));
    const { jwt } = await tokenProvider(config)
      .fetchOrdererToken(config.tenantId, state.documentId);
    state.token = jwt;
    for (const target of nativeTargets) {
      state.natives.push(await nativeAdapter(target, config, {
        runId: context.runId,
        documentId: state.documentId,
        tenant: config.tenantId,
        viewSchema: context.viewSchema,
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
      state.currentAction = { index, type: action.type, label: action.label ?? null };
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
      if (scheduleError) scheduleError.cleanupErrors = cleanupErrors;
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
  return original.firstDifferencePath === replayed.firstDifferencePath
    && JSON.stringify(original.failedAction) === JSON.stringify(replayed.failedAction)
    && JSON.stringify(observations(original)) === JSON.stringify(observations(replayed))
    && original.error.name === replayed.error.name
    && original.error.code === replayed.error.code
    && original.error.message === replayed.error.message;
}

export async function replayFailure(config, context, artifact) {
  validateRunnerContext("replayFailure", context);
  validateReplayArtifact(artifact, { profileDigest: context.profileDigest });
  try {
    const result = await runSeededSchedule(config, context, artifact.schedule);
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
    const replayArtifact = await loadReplayArtifact(error.failurePath, {
      profileDigest: context.profileDigest,
    });
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

function operationTransform(caseId, invalidProfile) {
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

function storageTransform(caseId) {
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
  const kind = cell.caseId === "unsupported-array-schema" ? "array" : "map";
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
    const creator = await openSession(config, containers);
    const documentId = creator.container.resolvedUrl.id;
    await publishUpstreamSummary(config, containers, documentId, `Task 5 ${cell.id}`);
    const upstream = await openSession(config, containers, documentId);
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
      viewSchema: context.viewSchema,
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
    upstream.data.view.root.title = `trigger-${randomUUID()}`;
    await until(() => !upstream.container.isDirty, `${cell.id} trigger sequencing`);
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
