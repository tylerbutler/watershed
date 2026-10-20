import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { buildShellFixture } from "../shell-fixture.mjs";
import { startServices } from "../../lib/services.mjs";
import { launchBrowser } from "../../lib/cdp.mjs";
import { runScenarios } from "../../graders/scenarios.mjs";
import { fileURLToPath } from "node:url";

const contract = JSON.parse(await readFile(new URL("../../contract.json", import.meta.url), "utf8"));
for (const sdk of ["watershed", "fluid"]) {
  test(`${sdk} reference passes every shared behavioral check`, async () => {
    const fixture = await buildShellFixture(sdk, { fake: false, solution: true, grader: true });
    let services;
    let browser;
    try {
      services = await startServices({ sdk, root: fixture.workspace, runId: "shared-grading" });
      browser = await launchBrowser();
      const checks = [];
      await runScenarios({ sdk, services, browser, record: check => checks.push(check) });
      assert.deepEqual(checks.filter(check => !check.passed), []);
      assert.deepEqual(checks.map(check => check.id).sort(),
        contract.checks.filter(check => check.group !== "integrity").map(check => check.id).sort());
      assert.deepEqual(services.diagnostics().transportErrors, []);
    } finally {
      if (browser) await browser.close();
      if (services) await services.close();
      await fixture.close();
    }

  });
}

for (const [defect, checkId] of [
  ["retry-create", "lifecycle.errors"],
  ["late-resource-leak", "lifecycle.late-callback"],
]) {
  test(`shared grading rejects ${defect} for its lifecycle behavior`, async () => {
    const fixture = await buildShellFixture("fluid", {
      fake: false, solution: true, grader: true,
      modelFixture: fileURLToPath(new URL(`../../validation/fixtures/fluid-${defect}.ts`, import.meta.url)),
    });
    let services;
    let browser;
    try {
      services = await startServices({ sdk: "fluid", root: fixture.workspace, runId: "lifecycle-mutant" });
      browser = await launchBrowser();
      const checks = [];
      await assert.rejects(runScenarios({ sdk: "fluid", services, browser,
        record: check => checks.push(check) }), /lifecycle/);
      assert.ok(checks.some(check => check.id === checkId && !check.passed));
      assert.ok(checks.some(check => check.id === "concurrency.same-field" && check.passed),
        "The mutant must reach lifecycle grading, not fail during setup or native checks");
    } finally {
      if (browser) await browser.close();
      if (services) await services.close();
      await fixture.close();
    }
  });
}
