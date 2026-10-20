import assert from "node:assert/strict";
import { mkdir, mkdtemp, readdir, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import test from "node:test";
import { buildShellFixture } from "../shell-fixture.mjs";

test("fresh Watershed fixtures reuse compiler fingerprints instead of resolving Hex versions again", async () => {
  await mkdir(new URL("../../.work", import.meta.url), { recursive: true });
  const cache = await mkdtemp(new URL("../../.work/dependency-cache-test-", import.meta.url));
  try {
    const first = await buildShellFixture("watershed", { dependencyCache: cache });
    await first.close();
    const second = await buildShellFixture("watershed", { dependencyCache: cache });
    try {
      assert.doesNotMatch(second.compilation, /Resolving versions/);
    } finally { await second.close(); }
  } finally { await rm(cache, { recursive: true, force: true }); }
});

test("a failed fixture install releases its cold-cache lock", async () => {
  await mkdir(new URL("../../.work", import.meta.url), { recursive: true });
  const root = await mkdtemp(new URL("../../.work/failed-install-", import.meta.url));
  const cache = join(root, "cache");
  const tools = join(root, "tools");
  const originalPath = process.env.PATH;
  try {
    await mkdir(tools);
    await writeFile(join(tools, "pnpm"), "#!/bin/sh\nprintf 'Injected install failure' >&2\nexit 19\n", { mode: 0o755 });
    process.env.PATH = `${tools}:${originalPath}`;
    await assert.rejects(buildShellFixture("watershed", { dependencyCache: cache }), /Injected install failure/);
    assert.deepEqual(await readdir(cache), []);
  } finally {
    process.env.PATH = originalPath;
    await rm(root, { recursive: true, force: true });
  }
});
