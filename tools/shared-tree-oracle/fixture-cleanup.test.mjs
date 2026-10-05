import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtemp, readdir, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

const fixtureTest = "a complete current-run report satisfies";
const failureMessage = "intentional fixture cleanup regression failure";

for (const { name, pattern, file = "interop.test.mjs", preload, count = 1 } of [
  {
    name: "interop fixtures are removed after successful tests",
    count: 7,
    pattern: [
      fixtureTest,
      "failed status publication",
      "completion reconnect failure retains",
      "seeded failure artifacts retain",
      "artifact evidence is nonempty",
      "the committed profile is hashed",
    ].join("|"),
  },
  {
    name: "interop fixtures are removed after an assertion failure",
    pattern: fixtureTest,
    preload: `
      import assert from "node:assert/strict";
      assert.equal = () => { throw new Error(${JSON.stringify(failureMessage)}); };
    `,
  },
  {
    name: "interop fixtures are removed when fixture setup fails",
    pattern: fixtureTest,
    preload: `
      import fs from "node:fs";
      import { syncBuiltinESMExports } from "node:module";
      fs.promises.mkdir = async () => {
        throw new Error(${JSON.stringify(failureMessage)});
      };
      syncBuiltinESMExports();
    `,
  },
  {
    name: "replay fixtures are removed when the second allocation fails",
    file: "interop-scenarios.test.mjs",
    pattern: "replay classifies native array-move failures",
    preload: `
      import fs from "node:fs";
      import { syncBuiltinESMExports } from "node:module";
      const mkdtemp = fs.promises.mkdtemp;
      fs.promises.mkdtemp = (prefix, ...args) => {
        if (prefix.endsWith("watershed-array-move-replay-")) {
          throw new Error(${JSON.stringify(failureMessage)});
        }
        return mkdtemp(prefix, ...args);
      };
      syncBuiltinESMExports();
    `,
  },
]) {
  test(name, async (t) => {
    const directory = await mkdtemp(join(tmpdir(), "watershed-fixture-cleanup-"));
    t.after(() => rm(directory, { recursive: true, force: true }));
    const env = {
      ...process.env,
      TMPDIR: directory,
      TMP: directory,
      TEMP: directory,
      NODE_DISABLE_COMPILE_CACHE: "1",
    };
    // The child must start a runner, not inherit the parent test worker.
    delete env.NODE_TEST_CONTEXT;
    const result = spawnSync(process.execPath, [
      "--test",
      "--test-reporter=tap",
      `--test-name-pattern=${pattern}`,
      ...(preload ? [`--import=data:text/javascript,${encodeURIComponent(preload)}`] : []),
      join(import.meta.dirname, file),
    ], {
      env,
      encoding: "utf8",
      timeout: 60_000,
    });
    assert.ifError(result.error);
    const output = result.stdout + result.stderr;
    assert.equal(result.status, preload ? 1 : 0, output);
    assert.match(output, new RegExp(`^# tests ${count}$`, "m"));
    if (preload) assert(output.includes(failureMessage), output);
    assert.deepEqual(await readdir(directory), [], "test fixtures leaked");
  });
}
