import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { readFile } from "node:fs/promises";
import { createServer } from "node:http";
import { dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { promisify } from "node:util";

const execute = promisify(execFile);
const here = dirname(fileURLToPath(import.meta.url));
const repo = resolve(here, "..");
const tenant = "tenant";
const token = "storage-token";
const summaryTail = JSON.parse(await readFile(
  resolve(repo, "test/fixtures/shared_tree/cases/summary-tail.json"),
  "utf8",
));
const capturedSnapshot = summaryTail.input.replayInput.snapshotAtS;

function json(response, status, value) {
  response.writeHead(status, { "content-type": "application/json" });
  response.end(typeof value === "string" ? value : JSON.stringify(value));
}

function staticObjects() {
  return {
    trees: new Map([
      ["root-tree", [
        { path: "binary", sha: "binary-blob", type: "blob", mode: "100644" },
        { path: "empty", sha: "empty-blob", type: "blob", mode: "100644" },
        { path: "empty-tree", sha: "empty-tree", type: "tree", mode: "040000" },
        { path: "plus%2Bcash%24", sha: "plus-blob", type: "blob", mode: "100644" },
        { path: "repeat", sha: "binary-blob", type: "blob", mode: "100644" },
        { path: "slash%2Fname", sha: "child-tree", type: "tree", mode: "040000" },
      ]],
      ["child-tree", [
        { path: "%E6%B0%B4", sha: "text-blob", type: "blob", mode: "100644" },
      ]],
      ["empty-tree", []],
      ["invalid-encoding-tree", [
        {
          path: "bad-encoding",
          sha: "bad-encoding-blob",
          type: "blob",
          mode: "100644",
        },
      ]],
      ["malformed-blob-tree", [
        {
          path: "malformed-blob",
          sha: "malformed-blob",
          type: "blob",
          mode: "100644",
        },
      ]],
      ["invalid-base64-tree", [
        {
          path: "bad-base64",
          sha: "bad-base64-blob",
          type: "blob",
          mode: "100644",
        },
      ]],
      ["missing-descendant-tree", [
        { path: "missing", sha: "missing-blob", type: "blob", mode: "100644" },
      ]],
      ["cycle-tree", [
        { path: "loop", sha: "cycle-tree", type: "tree", mode: "040000" },
      ]],
    ]),
    blobs: new Map([
      ["binary-blob", { content: "AP+A", encoding: "base64" }],
      ["empty-blob", { content: "", encoding: "base64" }],
      ["plus-blob", { content: "Kw==", encoding: "base64" }],
      ["text-blob", { content: "héllo", encoding: "utf-8" }],
      ["bad-encoding-blob", { content: "value", encoding: "gzip" }],
      ["bad-base64-blob", { content: "%%%", encoding: "base64" }],
    ]),
  };
}

function capturedFixture(snapshot) {
  assert.equal(snapshot.blobEncoding, "base64");
  const trees = new Map();
  const blobs = new Map(
    Object.entries(snapshot.blobs).map(([id, content]) => [
      id,
      { content, encoding: "base64" },
    ]),
  );
  const entries = [{ components: [], kind: "tree" }];
  let blobPaths = 0;
  let treeNodes = 0;

  function visit(tree, components) {
    treeNodes += 1;
    const children = [
      ...Object.entries(tree.blobs).map(([name, sha]) => ({
        name,
        sha,
        type: "blob",
        mode: "100644",
      })),
      ...Object.entries(tree.trees).map(([name, value]) => ({
        name,
        sha: value.id,
        type: "tree",
        mode: "040000",
        value,
      })),
    ].sort((left, right) =>
      left.name < right.name ? -1 : left.name > right.name ? 1 : 0);
    trees.set(tree.id, children.map(({ name, sha, type, mode }) => ({
      path: encodeURIComponent(name),
      sha,
      type,
      mode,
    })));
    for (const child of children) {
      const path = [...components, child.name];
      if (child.type === "blob") {
        blobPaths += 1;
        entries.push({
          components: path,
          kind: "blob",
          bytes: snapshot.blobs[child.sha],
        });
      } else {
        entries.push({ components: path, kind: "tree" });
        visit(child.value, path);
      }
    }
  }

  visit(snapshot.tree, []);
  return {
    root: snapshot.tree.id,
    trees,
    blobs,
    entries,
    blobPaths,
    treeNodes,
  };
}

const captured = capturedFixture(capturedSnapshot);

function createState() {
  const controls = staticObjects();
  return {
    trees: new Map([...controls.trees, ...captured.trees]),
    blobs: new Map([...controls.blobs, ...captured.blobs]),
    blobCount: 0,
    treeCount: 0,
    stagedRoot: undefined,
    failurePhase: false,
    failedTree: false,
    requests: [],
  };
}

let state = createState();

function commitTree(commit) {
  switch (commit) {
    case "success-commit":
      return "root-tree";
    case "staged-commit":
      assert(state.stagedRoot, "staged commit requested before staging");
      return state.stagedRoot;
    case "malformed-tree-commit":
      return "malformed-tree";
    case "invalid-encoding-commit":
      return "invalid-encoding-tree";
    case "malformed-blob-commit":
      return "malformed-blob-tree";
    case "invalid-base64-commit":
      return "invalid-base64-tree";
    case "missing-descendant-commit":
      return "missing-descendant-tree";
    case "cycle-commit":
      return "cycle-tree";
    case "captured-commit":
      return captured.root;
    case "captured-staged-commit":
      assert(state.stagedRoot, "captured staged commit requested before staging");
      return state.stagedRoot;
    default:
      return undefined;
  }
}

async function body(request) {
  const chunks = [];
  for await (const chunk of request) chunks.push(chunk);
  return Buffer.concat(chunks).toString("utf8");
}

const server = createServer(async (request, response) => {
  try {
    assert.equal(request.headers.authorization, `Bearer ${token}`);
    const url = new URL(request.url, "http://127.0.0.1");
    state.requests.push({ method: request.method, path: url.pathname });
    const prefix = `/repos/${tenant}/git`;

    if (request.method === "GET" && url.pathname.startsWith(`${prefix}/commits/`)) {
      const commit = decodeURIComponent(url.pathname.slice(`${prefix}/commits/`.length));
      if (commit === "missing-commit") return json(response, 404, { error: "missing" });
      if (commit === "forbidden-commit") return json(response, 403, { error: "forbidden" });
      if (commit === "error-commit") return json(response, 500, { error: "failed" });
      if (commit === "malformed-commit") return json(response, 200, "{\"tree\":");
      const tree = commitTree(commit);
      assert(tree, `unexpected commit: ${commit}`);
      return json(response, 200, { tree: { sha: tree } });
    }

    if (request.method === "GET" && url.pathname.startsWith(`${prefix}/trees/`)) {
      const id = decodeURIComponent(url.pathname.slice(`${prefix}/trees/`.length));
      if (id === "malformed-tree") return json(response, 200, "{\"tree\":");
      const entries = state.trees.get(id);
      if (entries === undefined) return json(response, 404, { error: "missing tree" });
      if (id === "cycle-tree") state.failurePhase = true;
      return json(response, 200, { sha: id, tree: entries });
    }

    if (request.method === "GET" && url.pathname.startsWith(`${prefix}/blobs/`)) {
      const id = decodeURIComponent(url.pathname.slice(`${prefix}/blobs/`.length));
      if (id === "malformed-blob") return json(response, 200, "{\"content\":");
      const blob = state.blobs.get(id);
      if (blob === undefined) return json(response, 404, { error: "missing blob" });
      return json(response, 200, { sha: id, ...blob });
    }

    if (request.method === "POST" && url.pathname === `${prefix}/blobs`) {
      assert.equal(request.headers["content-type"], "application/json");
      const value = JSON.parse(await body(request));
      assert.deepEqual(Object.keys(value), ["content", "encoding"]);
      assert.equal(value.encoding, "base64");
      if (state.failurePhase && state.blobCount === 5) {
        assert.equal(value.content, "AQID", "invalid hierarchy wrote before validation");
      }
      const id = `uploaded-blob-${++state.blobCount}`;
      state.blobs.set(id, value);
      return json(response, 201, { sha: id });
    }

    if (request.method === "POST" && url.pathname === `${prefix}/trees`) {
      assert.equal(request.headers["content-type"], "application/json");
      const value = JSON.parse(await body(request));
      assert.deepEqual(Object.keys(value), ["tree"]);
      for (const entry of value.tree) {
        assert.deepEqual(Object.keys(entry), ["mode", "path", "sha", "type"]);
        assert.equal(
          entry.mode,
          entry.type === "blob" ? "100644" : "040000",
        );
        assert(!entry.path.includes("/"), `unencoded component: ${entry.path}`);
      }
      if (value.tree.some(({ path }) => path === "fail-after-upload")) {
        state.failedTree = true;
        return json(response, 500, { error: "injected tree failure" });
      }
      const id = `uploaded-tree-${++state.treeCount}`;
      state.trees.set(id, value.tree);
      state.stagedRoot = id;
      return json(response, 201, { sha: id });
    }

    assert.fail(`unexpected storage request: ${request.method} ${url.pathname}`);
  } catch (error) {
    response.writeHead(500, { "content-type": "text/plain" });
    response.end(error.stack ?? String(error));
  }
});

await new Promise((resolveListen) => server.listen(0, "127.0.0.1", resolveListen));
const address = server.address();
assert(address && typeof address === "object");
const baseUrl = `http://127.0.0.1:${address.port}`;
const environment = {
  ...process.env,
  WATERSHED_TREE_STORAGE_URL: baseUrl,
  WATERSHED_TREE_STORAGE_TENANT: tenant,
  WATERSHED_TREE_STORAGE_TOKEN: token,
};

function marker(stdout, prefix) {
  const line = stdout.split(/\r?\n/).find((value) =>
    value.startsWith(prefix));
  assert(line, `missing storage marker in:\n${stdout}`);
  return JSON.parse(line.slice(prefix.length));
}

function assertRun() {
  assert.equal(state.blobCount, 7 + captured.blobPaths);
  assert.equal(state.treeCount, 4 + captured.treeNodes);
  assert.equal(state.failedTree, true);
  for (const request of state.requests) {
    if (request.path.includes("/git/commits/")) {
      assert.equal(request.method, "GET", "probe sent a commit publication request");
    } else if (
      request.path.endsWith("/git/trees")
      || request.path.endsWith("/git/blobs")
    ) {
      assert.equal(request.method, "POST");
    } else if (
      request.path.includes("/git/trees/")
      || request.path.includes("/git/blobs/")
    ) {
      assert.equal(request.method, "GET");
    } else {
      assert.fail(`probe sent an unexpected request: ${request.method} ${request.path}`);
    }
  }
}

try {
  await execute("gleam", ["build", "--target", "javascript"], {
    cwd: repo,
    env: environment,
  });
  const moduleUrl = pathToFileURL(
    resolve(
      repo,
      "build/dev/javascript/watershed/watershed/shared_tree_storage_probe.mjs",
    ),
  ).href;
  const javascript = await execute(
    process.execPath,
    [
      "--input-type=module",
      "--eval",
      `const probe = await import(${JSON.stringify(moduleUrl)});
       await probe.main();`,
    ],
    { cwd: repo, env: environment },
  );
  const javascriptObservation = marker(
    javascript.stdout,
    "WATERSHED_TREE_STORAGE=",
  );
  const javascriptCaptured = marker(
    javascript.stdout,
    "WATERSHED_TREE_STORAGE_CAPTURED=",
  );
  assertRun();

  state = createState();
  const erlang = await execute(
    "gleam",
    ["run", "--target", "erlang", "-m", "watershed/shared_tree_storage_probe"],
    { cwd: repo, env: environment },
  );
  const erlangObservation = marker(erlang.stdout, "WATERSHED_TREE_STORAGE=");
  const erlangCaptured = marker(
    erlang.stdout,
    "WATERSHED_TREE_STORAGE_CAPTURED=",
  );
  assertRun();

  assert.deepEqual(erlangObservation, javascriptObservation);
  assert.deepEqual(erlangCaptured, javascriptCaptured);
  assert.deepEqual(javascriptObservation, {
    root: "uploaded-tree-3",
    entries: [
      { components: ["binary"], kind: "blob", bytes: "AP+A" },
      { components: ["empty"], kind: "blob", bytes: "" },
      { components: ["empty-tree"], kind: "tree" },
      { components: ["plus+cash$"], kind: "blob", bytes: "Kw==" },
      { components: ["repeat"], kind: "blob", bytes: "AP+A" },
      { components: ["slash/name"], kind: "tree" },
      {
        components: ["slash/name", "水"],
        kind: "blob",
        bytes: Buffer.from("héllo").toString("base64"),
      },
    ],
  });
  assert.deepEqual(javascriptCaptured, {
    root: `uploaded-tree-${4 + captured.treeNodes}`,
    entries: captured.entries,
  });
  console.log("shared tree storage smoke: ok");
} finally {
  await new Promise((resolveClose, rejectClose) =>
    server.close((error) => error ? rejectClose(error) : resolveClose()));
}
