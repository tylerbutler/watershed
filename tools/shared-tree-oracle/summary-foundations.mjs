import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { access } from "node:fs/promises";
import { fileURLToPath, pathToFileURL } from "node:url";
import { reference } from "./source.mjs";

const identity = {
  package: "@fluidframework/tree",
  version: reference.version,
  commit: reference.commit,
};

function object(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function exactKeys(value, keys, label) {
  assert(object(value), `${label}: object`);
  assert.deepEqual(Object.keys(value).sort(), [...keys].sort(), `${label}: keys`);
}

function nonemptyString(value, label) {
  assert(typeof value === "string" && value.length > 0, label);
}

function validateSnapshot(snapshot) {
  exactKeys(
    snapshot,
    ["version", "tree", "blobs", "blobEncoding"],
    "summary-foundations snapshot",
  );
  exactKeys(snapshot.version, ["id", "treeId"], "summary-foundations snapshot version");
  nonemptyString(snapshot.version.id, "summary-foundations snapshot version id");
  nonemptyString(snapshot.version.treeId, "summary-foundations snapshot tree id");
  assert.equal(snapshot.blobEncoding, "base64", "summary-foundations snapshot encoding");
  assert(object(snapshot.blobs), "summary-foundations snapshot blobs");

  function visit(tree) {
    assert(object(tree), "summary-foundations snapshot tree");
    assert.deepEqual(
      Object.keys(tree).sort(),
      (Object.hasOwn(tree, "commits")
        ? ["id", "blobs", "trees", "commits"]
        : ["id", "blobs", "trees"]).sort(),
      "summary-foundations snapshot tree keys",
    );
    nonemptyString(tree.id, "summary-foundations snapshot storage id");
    assert(object(tree.blobs), "summary-foundations snapshot tree blobs");
    assert(object(tree.trees), "summary-foundations snapshot child trees");
    if (Object.hasOwn(tree, "commits")) {
      assert(object(tree.commits), "summary-foundations snapshot commits");
      assert.equal(Object.keys(tree.commits).length, 0, "summary-foundations snapshot commits");
    }
    for (const blobId of Object.values(tree.blobs)) {
      nonemptyString(blobId, "summary-foundations snapshot blob id");
      nonemptyString(snapshot.blobs[blobId], "summary-foundations snapshot blob bytes");
    }
    for (const child of Object.values(tree.trees)) visit(child);
  }

  visit(snapshot.tree);
  assert.equal(snapshot.version.treeId, snapshot.tree.id, "summary-foundations snapshot root");
}

function validateRawBlob(blob, label) {
  exactKeys(blob, ["content", "encoding", "bytes", "sha"], label);
  assert(blob.encoding === "base64" || blob.encoding === "utf-8", `${label}: encoding`);
  assert(typeof blob.content === "string", `${label}: content`);
  assert(typeof blob.bytes === "string", `${label}: blob bytes`);
  nonemptyString(blob.sha, `${label}: sha`);
  const bytes = Buffer.from(blob.content, blob.encoding === "base64" ? "base64" : "utf8");
  if (blob.encoding === "base64") {
    assert.equal(bytes.toString("base64"), blob.content, `${label}: base64 content`);
  }
  assert.equal(bytes.toString("base64"), blob.bytes, `${label}: blob bytes`);
  assert.equal(gitBlobHash(bytes), blob.sha, `${label}: sha`);
}

function validateRawTree(tree, label) {
  exactKeys(tree, ["sha", "entries"], label);
  nonemptyString(tree.sha, `${label}: sha`);
  assert(Array.isArray(tree.entries), `${label}: entries`);
  for (const [index, entry] of tree.entries.entries()) {
    const entryLabel = `${label} entry ${index}`;
    exactKeys(entry, ["mode", "path", "sha", "type"], entryLabel);
    nonemptyString(entry.path, `${entryLabel}: path`);
    nonemptyString(entry.sha, `${entryLabel}: sha`);
    assert(entry.type === "blob" || entry.type === "tree", `${entryLabel}: type`);
    assert.equal(entry.mode, entry.type === "blob" ? "100644" : "040000", `${entryLabel}: mode`);
    assert.doesNotThrow(() => decodeURIComponent(entry.path), `${entryLabel}: path encoding`);
  }
}

async function oracleModules() {
  const candidates = [
    new URL("./node_modules/", import.meta.url),
    new URL("../../../../tools/shared-tree-oracle/node_modules/", import.meta.url),
  ];
  let modules;
  for (const candidate of candidates) {
    try {
      await access(fileURLToPath(candidate));
      modules = candidate;
      break;
    } catch {
      // Try the main checkout when this module runs from an isolated worktree.
    }
  }
  if (modules === undefined) {
    throw new Error("SharedTree oracle dependencies are not installed");
  }
  const load = (path) => import(pathToFileURL(fileURLToPath(new URL(path, modules))));
  const [{ SummaryTreeUploadManager }, { SummaryType }] = await Promise.all([
    load("@fluidframework/routerlicious-driver/lib/summaryTreeUploadManager.js"),
    load("@fluidframework/driver-definitions/lib/index.js"),
  ]);
  return { SummaryTreeUploadManager, SummaryType };
}

function gitBlobHash(bytes) {
  return createHash("sha1")
    .update(`blob ${bytes.length}\0`)
    .update(bytes)
    .digest("hex");
}

function recordingManager() {
  const blobs = [];
  const trees = [];
  return {
    blobs,
    trees,
    manager: {
      async createBlob(content, encoding) {
        const bytes = Buffer.from(content, encoding === "base64" ? "base64" : "utf8");
        const sha = gitBlobHash(bytes);
        blobs.push({
          content,
          encoding,
          bytes: bytes.toString("base64"),
          sha,
        });
        return { content: { sha } };
      },
      async createGitTree(body) {
        const sha = `created-tree-${trees.length + 1}`;
        trees.push({ sha, entries: structuredClone(body.tree) });
        return { content: { sha } };
      },
    },
  };
}

function findCase(existingCases, id) {
  const value = existingCases.find((item) => item?.id === id);
  if (value === undefined) throw new Error(`Missing existing case: ${id}`);
  return value;
}

function previousPath() {
  return "/.channels/A/.channels/_C/indexes/Schema";
}

function summaryShape(entries, parent = []) {
  return entries.flatMap((entry) => {
    const components = [...parent, entry.name];
    const kind = entry.kind === "handle" ? entry.handleKind : entry.kind;
    return [
      { components, kind },
      ...(entry.kind === "tree" ? summaryShape(entry.entries, components) : []),
    ];
  });
}

function uploadedCounts(entries) {
  return entries.reduce((counts, entry) => {
    if (entry.kind === "blob") counts.blobs += 1;
    if (entry.kind === "tree") {
      counts.trees += 1;
      const children = uploadedCounts(entry.entries);
      counts.blobs += children.blobs;
      counts.trees += children.trees;
    }
    return counts;
  }, { blobs: 0, trees: 0 });
}

function scenarioInput() {
  return [
    { label: "snapshot-entries", operation: "snapshot" },
    {
      label: "emitted-entries",
      operation: "emit",
      previous: "snapshot",
      summary: [
        { name: "binary", kind: "blob", bytes: "AP+A" },
        { name: "empty", kind: "blob", bytes: "" },
        {
          name: "text",
          kind: "blob",
          bytes: Buffer.from("héllo", "utf8").toString("base64"),
          text: "héllo",
        },
        { name: "plus+cash$", kind: "blob", bytes: "Kw==" },
        {
          name: "slash/name",
          kind: "tree",
          entries: [{ name: "nested", kind: "blob", bytes: "bmVzdGVk" }],
        },
        {
          name: "schema-copy",
          kind: "handle",
          handleKind: "tree",
          path: previousPath(),
        },
        {
          name: "schema-string-copy",
          kind: "handle",
          handleKind: "blob",
          path: `${previousPath()}/SchemaString`,
        },
        {
          name: "schema-string-copy-again",
          kind: "handle",
          handleKind: "blob",
          path: `${previousPath()}/SchemaString`,
        },
        { name: "root-copy", kind: "handle", handleKind: "tree", path: "" },
      ],
    },
    {
      label: "missing-parent",
      operation: "refuse",
      previous: "missing",
      summary: [{
        name: "copy",
        kind: "handle",
        handleKind: "blob",
        path: `${previousPath()}/SchemaString`,
      }],
    },
    {
      label: "missing-path",
      operation: "refuse",
      previous: "snapshot",
      summary: [{
        name: "copy",
        kind: "handle",
        handleKind: "blob",
        path: `${previousPath()}/Missing`,
      }],
    },
    {
      label: "wrong-kind",
      operation: "refuse",
      previous: "snapshot",
      summary: [{
        name: "copy",
        kind: "handle",
        handleKind: "tree",
        path: `${previousPath()}/SchemaString`,
      }],
    },
    {
      label: "malformed-percent-encoding",
      operation: "refuse",
      previous: "snapshot",
      summary: [{
        name: "copy",
        kind: "handle",
        handleKind: "blob",
        path: "/bad%ZZ",
      }],
    },
  ];
}

function snapshotObservation(snapshot) {
  const entries = [];
  function visit(tree, components) {
    entries.push({
      components,
      kind: "tree",
      storageId: tree.id,
    });
    const children = [
      ...Object.entries(tree.blobs).map(([name, id]) => ({
        name,
        id,
        kind: "blob",
      })),
      ...Object.entries(tree.trees).map(([name, value]) => ({
        name,
        value,
        kind: "tree",
      })),
    ].sort((left, right) => left.name < right.name ? -1 : left.name > right.name ? 1 : 0);
    for (const child of children) {
      const path = [...components, child.name];
      if (child.kind === "blob") {
        entries.push({
          components: path,
          kind: "blob",
          storageId: child.id,
          bytes: snapshot.blobs[child.id],
        });
      } else {
        visit(child.value, path);
      }
    }
  }
  visit(snapshot.tree, []);
  return { label: "snapshot-entries", entries };
}

function toSummaryTree(entries, SummaryType) {
  return {
    type: SummaryType.Tree,
    tree: Object.fromEntries(entries.map((entry) => [
      entry.name,
      toSummaryObject(entry, SummaryType),
    ])),
  };
}

function toSummaryObject(entry, SummaryType) {
  switch (entry.kind) {
    case "blob":
      return {
        type: SummaryType.Blob,
        content: entry.text ?? Uint8Array.from(Buffer.from(entry.bytes, "base64")),
      };
    case "tree":
      return toSummaryTree(entry.entries, SummaryType);
    case "handle":
      return {
        type: SummaryType.Handle,
        handleType:
          entry.handleKind === "tree" ? SummaryType.Tree : SummaryType.Blob,
        handle: entry.path,
      };
    default:
      throw new Error(`Unsupported summary input kind: ${entry.kind}`);
  }
}

function snapshotIds(tree, output = new Map()) {
  output.set(tree.id, { kind: "tree" });
  for (const [name, id] of Object.entries(tree.blobs)) {
    output.set(id, { kind: "blob", name });
  }
  for (const child of Object.values(tree.trees)) snapshotIds(child, output);
  return output;
}

function emittedObservation(rootId, raw, snapshot) {
  const createdTrees = new Map(raw.trees.map((tree) => [tree.sha, tree.entries]));
  const uploadedBlobs = new Map(raw.blobs.map((blob) => [blob.sha, blob.bytes]));
  const previousIds = snapshotIds(snapshot.tree);
  const entries = [];

  function visit(treeId, components) {
    const tree = createdTrees.get(treeId);
    if (tree === undefined) return;
    for (const entry of tree) {
      const name = decodeURIComponent(entry.path);
      const childComponents = [...components, name];
      const previous = previousIds.get(entry.sha);
      const kind = entry.type === "tree" ? "tree" : "blob";
      const observation = {
        components: childComponents,
        encodedName: entry.path,
        kind,
        mode: entry.mode,
        storageId: entry.sha,
        source: previous === undefined ? "uploaded" : "previous",
      };
      if (kind === "blob") {
        observation.bytes =
          uploadedBlobs.get(entry.sha) ?? snapshot.blobs[entry.sha];
      }
      entries.push(observation);
      if (kind === "tree" && previous === undefined) {
        visit(entry.sha, childComponents);
      }
    }
  }

  visit(rootId, []);
  return { label: "emitted-entries", entries };
}

async function refusedObservation(
  scenario,
  SummaryTreeUploadManager,
  SummaryType,
  previousSnapshot,
) {
  const raw = recordingManager();
  const manager = new SummaryTreeUploadManager(
    raw.manager,
    new Map(),
    async () => scenario.previous === "missing" ? undefined : previousSnapshot,
  );
  const logged = [];
  const originalLog = console.log;
  const originalError = console.error;
  console.log = (...values) => logged.push(values.map(String).join(" "));
  console.error = (...values) => logged.push(values.map(String).join(" "));
  try {
    await manager.writeSummaryTree(
      toSummaryTree(scenario.summary, SummaryType),
      "previous",
      "channel",
    );
  } catch (error) {
    return {
      observation: {
        label: scenario.label,
        refused: true,
      },
      raw: {
        label: scenario.label,
        error: error instanceof Error ? error.message : String(error),
        blobs: raw.blobs,
        trees: raw.trees,
        logged,
      },
    };
  } finally {
    console.log = originalLog;
    console.error = originalError;
  }
  throw new Error(`Upstream accepted refused summary scenario: ${scenario.label}`);
}

export async function captureSummaryFoundations(existingCases) {
  findCase(existingCases, "bootstrap-map-handles");
  const summaryTail = findCase(existingCases, "summary-tail");
  const previousSnapshot = summaryTail.input?.replayInput?.snapshotAtS;
  if (previousSnapshot?.tree === undefined || previousSnapshot?.blobs === undefined) {
    throw new Error("summary-tail has no replay snapshot");
  }

  const { SummaryTreeUploadManager, SummaryType } = await oracleModules();
  const scenarios = scenarioInput();
  const emittedScenario = scenarios.find(({ operation }) => operation === "emit");
  const emittedRaw = recordingManager();
  const manager = new SummaryTreeUploadManager(
    emittedRaw.manager,
    new Map(),
    async () => previousSnapshot.tree,
  );
  const rootId = await manager.writeSummaryTree(
    toSummaryTree(emittedScenario.summary, SummaryType),
    "previous",
    "channel",
  );

  const refused = [];
  for (const scenario of scenarios.filter(({ operation }) =>
    operation === "refuse")) {
    refused.push(await refusedObservation(
      scenario,
      SummaryTreeUploadManager,
      SummaryType,
      previousSnapshot.tree,
    ));
  }

  return {
    formatVersion: 1,
    reference: identity,
    id: "summary-foundations",
    domain: "summary",
    input: {
      service: "SummaryTreeUploadManager",
      previousSnapshot,
      scenarios,
    },
    expected: {
      observations: [
        snapshotObservation(previousSnapshot),
        emittedObservation(rootId, emittedRaw, previousSnapshot),
        ...refused.map(({ observation }) => observation),
      ],
    },
    raw: {
      rootId,
      blobs: emittedRaw.blobs,
      trees: emittedRaw.trees,
      refusals: refused.map((item) => item.raw),
    },
  };
}

export function validateSummaryFoundationsCase(value) {
  exactKeys(
    value,
    ["formatVersion", "reference", "id", "domain", "input", "expected", "raw"],
    "summary-foundations",
  );
  assert.equal(value.formatVersion, 1, "summary-foundations: formatVersion");
  assert.deepEqual(value.reference, identity, "summary-foundations: reference");
  assert.equal(value.id, "summary-foundations", "summary-foundations: id");
  assert.equal(value.domain, "summary", "summary-foundations: domain");

  exactKeys(
    value.input,
    ["service", "previousSnapshot", "scenarios"],
    "summary-foundations input",
  );
  assert.equal(
    value.input.service,
    "SummaryTreeUploadManager",
    "summary-foundations: service",
  );
  validateSnapshot(value.input.previousSnapshot);
  assert.deepEqual(
    value.input.scenarios,
    scenarioInput(),
    "summary-foundations: scenarios",
  );

  exactKeys(value.expected, ["observations"], "summary-foundations expected");
  assert(Array.isArray(value.expected.observations), "summary-foundations: observations");
  const labels = value.input.scenarios.map(({ label }) => label);
  assert.deepEqual(
    value.expected.observations.map(({ label }) => label),
    labels,
    "summary-foundations: observations",
  );
  assert.deepEqual(
    value.expected.observations[0],
    snapshotObservation(value.input.previousSnapshot),
    "summary-foundations: snapshot observation",
  );

  exactKeys(
    value.raw,
    ["rootId", "blobs", "trees", "refusals"],
    "summary-foundations raw",
  );
  nonemptyString(value.raw.rootId, "summary-foundations: raw rootId");
  assert(Array.isArray(value.raw.blobs), "summary-foundations: raw blobs");
  assert(Array.isArray(value.raw.trees) && value.raw.trees.length > 0,
    "summary-foundations: raw trees");
  assert(Array.isArray(value.raw.refusals), "summary-foundations: refusals");
  const counts = uploadedCounts(value.input.scenarios[1].summary);
  assert.equal(value.raw.blobs.length, counts.blobs, "summary-foundations: raw blobs");
  assert.equal(value.raw.trees.length, counts.trees + 1, "summary-foundations: raw trees");
  value.raw.blobs.forEach((blob, index) =>
    validateRawBlob(blob, `summary-foundations raw blob ${index}`));
  value.raw.trees.forEach((tree, index) =>
    validateRawTree(tree, `summary-foundations raw tree ${index}`));
  const previousIds = snapshotIds(value.input.previousSnapshot.tree);
  const blobIds = new Set(value.raw.blobs.map(({ sha }) => sha));
  const treeIds = new Set(value.raw.trees.map(({ sha }) => sha));
  assert.equal(blobIds.size, value.raw.blobs.length, "summary-foundations: raw blob ids");
  assert.equal(treeIds.size, value.raw.trees.length, "summary-foundations: raw tree ids");
  const referenced = new Set();
  for (const tree of value.raw.trees) {
    for (const entry of tree.entries) {
      referenced.add(entry.sha);
      const previous = previousIds.get(entry.sha);
      const known = entry.type === "blob"
        ? blobIds.has(entry.sha) || previous?.kind === "blob"
        : treeIds.has(entry.sha) || previous?.kind === "tree";
      assert(known, `summary-foundations: object reference ${entry.sha}`);
    }
  }
  for (const blobId of blobIds) {
    assert(referenced.has(blobId), `summary-foundations: object reference ${blobId}`);
  }
  for (const treeId of treeIds) {
    assert(treeId === value.raw.rootId || referenced.has(treeId),
      `summary-foundations: object reference ${treeId}`);
  }
  assert(
    value.raw.trees.some(({ sha }) => sha === value.raw.rootId),
    "summary-foundations: raw trees root",
  );
  assert.deepEqual(
    value.expected.observations[1],
    emittedObservation(
      value.raw.rootId,
      value.raw,
      value.input.previousSnapshot,
    ),
    "summary-foundations: emitted observation",
  );
  assert.deepEqual(
    value.expected.observations[1].entries.map(({ components, kind }) => ({
      components,
      kind,
    })),
    summaryShape(value.input.scenarios[1].summary),
    "summary-foundations: emitted entries",
  );

  const refusalLabels = labels.slice(2);
  assert.deepEqual(
    value.raw.refusals.map(({ label }) => label),
    refusalLabels,
    "summary-foundations: refusals",
  );
  assert.deepEqual(
    value.expected.observations.slice(2).map(({ label }) => label),
    refusalLabels,
    "summary-foundations: refusal observations",
  );
  for (const [index, refusal] of value.raw.refusals.entries()) {
    exactKeys(refusal, ["label", "error", "blobs", "trees", "logged"],
      `summary-foundations refusal ${index}`);
    nonemptyString(refusal.error, `summary-foundations refusal ${index}: error`);
    assert(Array.isArray(refusal.blobs), `summary-foundations refusal ${index}: blobs`);
    assert(Array.isArray(refusal.trees), `summary-foundations refusal ${index}: trees`);
    assert(Array.isArray(refusal.logged), `summary-foundations refusal ${index}: logged`);
    assert.equal(refusal.blobs.length, 0, "summary-foundations: refusal writes");
    assert.equal(refusal.trees.length, 0, "summary-foundations: refusal writes");
    refusal.blobs.forEach((blob, blobIndex) =>
      validateRawBlob(blob, `summary-foundations refusal ${index} blob ${blobIndex}`));
    refusal.trees.forEach((tree, treeIndex) =>
      validateRawTree(tree, `summary-foundations refusal ${index} tree ${treeIndex}`));
    const observation = value.expected.observations[index + 2];
    exactKeys(observation, ["label", "refused"],
      `summary-foundations refusal observation ${index}`);
    assert.equal(observation.refused, true,
      "summary-foundations: refusal observations");
  }
}
