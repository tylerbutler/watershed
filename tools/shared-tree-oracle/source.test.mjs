import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdir, mkdtemp, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import test from "node:test";
import {
  forestInjectedTestPath,
  historyInjectedTestPath,
  injectedTestPath,
  modularInjectedTestPath,
  publishCapture,
  reference,
  validateCapture,
  verifyCheckout,
  verifyPackages,
} from "./source.mjs";

async function temporaryDirectory(t) {
  const directory = await mkdtemp(join(tmpdir(), "watershed-tree-oracle-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  return directory;
}

async function writeJson(path, value) {
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, `${JSON.stringify(value)}\n`);
}

async function packageFixture(t) {
  const directory = await temporaryDirectory(t);
  for (const name of reference.packages) {
    await writeJson(join(directory, "node_modules", name, "package.json"), {
      name,
      version: reference.version,
    });
  }
  return directory;
}

function git(directory, ...args) {
  return execFileSync("git", ["-C", directory, ...args], {
    encoding: "utf8",
  }).trim();
}

async function checkoutFixture(t) {
  const directory = await temporaryDirectory(t);
  git(directory, "init", "--quiet");
  await writeJson(join(directory, "packages/dds/tree/package.json"), {
    name: "@fluidframework/tree",
    version: reference.version,
  });
  git(directory, "add", ".");
  git(directory, "-c", "user.name=Oracle Test", "-c",
    "user.email=oracle@example.invalid", "-c", "commit.gpgsign=false",
    "commit", "--quiet", "-m", "fixture");
  return { directory, commit: git(directory, "rev-parse", "HEAD") };
}

test("package verification accepts the installed pinned oracle", async () => {
  const versions = await verifyPackages();
  assert.equal(versions["@fluidframework/tree"], "3.1.0");
  assert.equal(versions["fluid-framework"], "3.1.0");
  assert.equal(versions["@fluidframework/local-driver"], "3.1.0");
});

test("package verification refuses a mismatched dependency", async (t) => {
  const directory = await packageFixture(t);
  await writeJson(join(directory, "node_modules/@fluidframework/tree/package.json"), {
    name: "@fluidframework/tree",
    version: "3.0.0",
  });
  await assert.rejects(verifyPackages(directory), /@fluidframework\/tree.*3\.0\.0/);
});

test("package verification refuses a missing dependency", async (t) => {
  const directory = await temporaryDirectory(t);
  await assert.rejects(verifyPackages(directory), /ENOENT/);
});

test("source verification refuses an unexpected commit", async (t) => {
  const { directory } = await checkoutFixture(t);
  await assert.rejects(verifyCheckout(directory), /commit/);
});

test("source verification refuses changed tracked source", async (t) => {
  const { directory, commit } = await checkoutFixture(t);
  await writeJson(join(directory, "packages/dds/tree/package.json"), {
    name: "@fluidframework/tree",
    version: "3.0.0",
  });
  await assert.rejects(verifyCheckout(directory, commit), /tracked/);
});

test("source verification refuses unrelated untracked files", async (t) => {
  const { directory, commit } = await checkoutFixture(t);
  await writeFile(join(directory, "unrelated.ts"), "export {};\n");
  await assert.rejects(verifyCheckout(directory, commit), /unrelated\.ts/);
});

test("source verification accepts only the matching owned injection", async (t) => {
  const { directory, commit } = await checkoutFixture(t);
  const target = join(directory, injectedTestPath);
  const contents = await readFile(new URL("./upstream-oracle.spec.ts", import.meta.url));
  await mkdir(dirname(target), { recursive: true });
  await writeFile(target, contents);
  await verifyCheckout(directory, commit);
  await writeFile(target, "// changed by someone else\n");
  await assert.rejects(verifyCheckout(directory, commit), /injected/);
});

test("source verification byte-checks the owned forest injection", async (t) => {
  const { directory, commit } = await checkoutFixture(t);
  const target = join(directory, forestInjectedTestPath);
  const contents = await readFile(new URL("./upstream-forest.spec.ts", import.meta.url));
  await mkdir(dirname(target), { recursive: true });
  await writeFile(target, contents);
  await verifyCheckout(directory, commit);
  await writeFile(target, "// changed by someone else\n");
  await assert.rejects(verifyCheckout(directory, commit), /injected/);
});

test("source verification byte-checks the owned modular injection", async (t) => {
  const { directory, commit } = await checkoutFixture(t);
  const target = join(directory, modularInjectedTestPath);
  const contents = await readFile(new URL("./upstream-modular.spec.ts", import.meta.url));
  await mkdir(dirname(target), { recursive: true });
  await writeFile(target, contents);
  await verifyCheckout(directory, commit);
  await writeFile(target, "// changed by someone else\n");
  await assert.rejects(verifyCheckout(directory, commit), /injected/);
});

test("source verification byte-checks the owned history injection", async (t) => {
  const { directory, commit } = await checkoutFixture(t);
  const target = join(directory, historyInjectedTestPath);
  const contents = await readFile(new URL("./upstream-history.spec.ts", import.meta.url));
  await mkdir(dirname(target), { recursive: true });
  await writeFile(target, contents);
  await verifyCheckout(directory, commit);
  await writeFile(target, "// changed by someone else\n");
  await assert.rejects(verifyCheckout(directory, commit), /injected/);
});

test("source verification does not mistake a parent repository for its checkout", async (t) => {
  const { directory, commit } = await checkoutFixture(t);
  const nested = join(directory, "nested");
  await mkdir(nested);
  await assert.rejects(verifyCheckout(nested, commit), /root/);
});

function captureFixture() {
  return {
    formatVersion: 1,
    reference: {
      version: "3.1.0",
      commit: "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960",
    },
    kind: "source-smoke",
    minVersionForCollab: "2.117.0",
    codecTree: { name: "test-format", formatVersion: 1 },
    messages: [{ contents: { version: 7 } }],
    observations: { pending: [1, 2], settled: [2, 2] },
    compressor: { version: 1 },
    compressorFormat: { version: 2, byteOrder: "LE" },
    summary: { type: 1, tree: {} },
  };
}

test("capture validation refuses missing source output and empty message data", () => {
  assert.throws(() => validateCapture(undefined), /capture/);
  assert.throws(() => validateCapture({ ...captureFixture(), messages: [] }), /messages/);
});

test("capture validation refuses another source revision", () => {
  const capture = captureFixture();
  capture.reference.commit = "other";
  assert.throws(() => validateCapture(capture), /reference/);
});

test("capture validation requires codecs, compressor, summary, and observations", () => {
  for (const field of ["codecTree", "compressor", "compressorFormat", "summary", "observations"]) {
    const capture = captureFixture();
    delete capture[field];
    assert.throws(() => validateCapture(capture), new RegExp(field));
  }
  assert.doesNotThrow(() => validateCapture(captureFixture()));
});

test("capture publication propagates a failed producer without replacing prior output", async (t) => {
  const directory = await temporaryDirectory(t);
  const prior = "previous capture\n";
  await writeFile(join(directory, "source-smoke.json"), prior);
  await assert.rejects(publishCapture(directory, () => {
    execFileSync(process.execPath, ["-e", "process.exit(19)"], { stdio: "pipe" });
  }), (error) => error.status === 19);
  assert.equal(await readFile(join(directory, "source-smoke.json"), "utf8"), prior);
  assert.deepEqual(await readdir(directory), ["source-smoke.json"]);
});

test("capture publication rejects absent output and removes its temporary directory", async (t) => {
  const directory = await temporaryDirectory(t);
  await assert.rejects(publishCapture(directory, async () => {}), /ENOENT/);
  assert.deepEqual(await readdir(directory), []);
});

test("capture publication rejects empty cases rather than publishing them", async (t) => {
  const directory = await temporaryDirectory(t);
  await assert.rejects(publishCapture(directory, async (output) => {
    await writeJson(join(output, "source-smoke.json"), { ...captureFixture(), messages: [] });
  }), /messages/);
  assert.deepEqual(await readdir(directory), []);
});

test("capture publication publishes only a complete validated result", async (t) => {
  const directory = await temporaryDirectory(t);
  const capture = captureFixture();
  await publishCapture(directory, (output) => writeJson(join(output, "source-smoke.json"), capture));
  assert.deepEqual(JSON.parse(await readFile(join(directory, "source-smoke.json"), "utf8")), capture);
  assert.deepEqual(await readdir(directory), ["source-smoke.json"]);
});
