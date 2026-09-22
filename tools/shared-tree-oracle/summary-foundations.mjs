import { createHash } from "node:crypto";
import { access } from "node:fs/promises";
import { fileURLToPath, pathToFileURL } from "node:url";
import { reference } from "./source.mjs";

const identity = {
  package: "@fluidframework/tree",
  version: reference.version,
  commit: reference.commit,
};

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

function scenarioInput() {
  return [
    {
      label: "emitted-entries",
      summary: [
        { name: "binary", kind: "blob", bytes: "AP+A" },
        { name: "empty", kind: "blob", bytes: "" },
        {
          name: "text",
          kind: "blob",
          bytes: Buffer.from("héllo", "utf8").toString("base64"),
          text: "héllo",
        },
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
      summary: [{
        name: "copy",
        kind: "handle",
        handleKind: "blob",
        path: `${previousPath()}/SchemaString`,
      }],
    },
    {
      label: "missing-path",
      summary: [{
        name: "copy",
        kind: "handle",
        handleKind: "blob",
        path: `${previousPath()}/Missing`,
      }],
    },
    {
      label: "wrong-kind",
      summary: [{
        name: "copy",
        kind: "handle",
        handleKind: "tree",
        path: `${previousPath()}/SchemaString`,
      }],
    },
    {
      label: "malformed-percent-encoding",
      summary: [{
        name: "copy",
        kind: "handle",
        handleKind: "blob",
        path: "/bad%ZZ",
      }],
    },
  ];
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
    async () => scenario.label === "missing-parent" ? undefined : previousSnapshot,
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
        refused: error instanceof Error ? error.message : String(error),
      },
      raw: {
        label: scenario.label,
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
  const emittedRaw = recordingManager();
  const manager = new SummaryTreeUploadManager(
    emittedRaw.manager,
    new Map(),
    async () => previousSnapshot.tree,
  );
  const rootId = await manager.writeSummaryTree(
    toSummaryTree(scenarios[0].summary, SummaryType),
    "previous",
    "channel",
  );

  const refused = [];
  for (const scenario of scenarios.slice(1)) {
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
      previousSnapshot,
      scenarios,
    },
    expected: {
      observations: [
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
