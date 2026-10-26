import assert from "node:assert/strict";
import test from "node:test";
import { buildShellFixture } from "../shell-fixture.mjs";
import { launchBrowser } from "../../lib/cdp.mjs";
import { startServices } from "../../lib/services.mjs";
import { runTransferScenarios } from "../../graders/transfers.mjs";
import { getBenchmark } from "../../generate.mjs";
import { applyTransferMutation, transferMutations } from "../../validation/transfer-mutations.mjs";
import { cp, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { createIntegrityManifest } from "../../lib/staging.mjs";
import { grade } from "../../graders/main.mjs";
import { verdict } from "../../lib/report.mjs";

const benchmark = fileURLToPath(new URL("../../", import.meta.url));

for (const sdk of ["watershed", "fluid"]) {
  test(`${sdk} trusted transfer grading persists all core and transfer checks from an unfinished baseline`, async () => {
    const fixture = await buildShellFixture(sdk, { fake: false, track: "transfers" });
    const gradingRoot = await mkdtemp(join(tmpdir(), `transfer-grade-${sdk}-`));
    try {
      const contract = getBenchmark("transfers").contract;
      const integrity = await createIntegrityManifest({ workspace: fixture.workspace, sdk });
      await cp(fixture.workspace, join(gradingRoot, "workspace"), {
        recursive: true, verbatimSymlinks: true,
      });
      await cp(join(benchmark, "graders"), join(gradingRoot, "graders"), { recursive: true });
      for (const [name, value] of Object.entries({
        integrity, sdk: { version: 1, sdk, track: "transfers" }, contract,
      })) await writeFile(join(gradingRoot, `${name}.json`), JSON.stringify(value));
      for (const name of ["model", "schema"]) {
        const file = `${name}.${sdk === "fluid" ? "ts" : "gleam"}`;
        await cp(join(benchmark, "validation/solutions/transfers", sdk, file),
          join(fixture.workspace, sdk === "fluid" ? "src" : "src/incident_eval", file));
      }
      const output = join(gradingRoot, "report.json");
      const report = await grade({ sdk, workspace: fixture.workspace, gradingRoot,
        runId: `trusted-transfers-${sdk}`, output });
      assert.equal(verdict(report, contract), "passed",
        JSON.stringify(report.checks.filter(check => !check.passed), null, 2));
      assert.deepEqual(JSON.parse(await readFile(output, "utf8")), report);
      assert.equal(report.checks.length, contract.checks.length);
    } finally {
      await rm(gradingRoot, { recursive: true, force: true });
      await fixture.close();
    }
  });
  for (const [defect, expected] of Object.entries(transferMutations)) {
    test(`${sdk} transfer grading rejects ${defect} after successful native compilation`, async () => {
      const fixture = await buildShellFixture(sdk, {
        fake: false, solution: true, grader: true, track: "transfers",
        mutate: workspace => applyTransferMutation({ sdk, defect, workspace }),
      });
      let services;
      let browser;
      const checks = [];
      try {
        services = await startServices({ sdk, root: fixture.workspace, runId: `${defect}-${sdk}` });
        browser = await launchBrowser();
        await assert.rejects(runTransferScenarios({ services, browser, record: value => checks.push(value) }));
        assert.equal(checks.find(value => value.id === expected.failed)?.passed, false,
          JSON.stringify(checks, null, 2));
        if (expected.after) assert.equal(checks.find(value => value.id === expected.after)?.passed, true);
      } finally {
        if (browser) await browser.close();
        if (services) await services.close();
        await fixture.close();
      }
    });
  }
}
