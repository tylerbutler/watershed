import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { cp, mkdir, mkdtemp, readFile, readdir, rm } from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
import test from "node:test";
import { prepare } from "../../prepare.mjs";
import { grade } from "../../graders/main.mjs";
import { verdict } from "../../lib/report.mjs";
import { applyMutation, mutations } from "../../validation/mutations.mjs";
import { buildShellFixture } from "../shell-fixture.mjs";
import { startServices } from "../../lib/services.mjs";
import { launchBrowser } from "../../lib/cdp.mjs";
import { runScenarios } from "../../graders/scenarios.mjs";
import { wait } from "../../lib/conditions.mjs";
import { interruptServiceDuringGrade } from "../../validation/fixtures/interrupted-service.mjs";

const exec = promisify(execFile);
const benchmark = fileURLToPath(new URL("../../", import.meta.url));
const repository = fileURLToPath(new URL("../../../../", import.meta.url));
const contract = JSON.parse(await readFile(join(benchmark, "contract.json"), "utf8"));
const check = (report, id) => {
  const result = report.checks.find(value => value.id === id);
  assert.ok(result, `Missing check ${id}`);
  return result;
};

for (const sdk of ["watershed", "fluid"]) {
  test(`${sdk} trusted grading rejects behavioral mutations of a compiling native reference`, async t => {
    await mkdir(join(benchmark, ".work"), { recursive: true });
    const work = await mkdtemp(join(benchmark, `.work/validation-${sdk}-`));
    try {
      const source = sdk === "watershed" ? repository : process.env.SHARED_TREE_FLUID_SOURCE ??
        join(repository, "tools/shared-tree-oracle/.reference/FluidFramework");
      const revision = sdk === "watershed"
        ? (await exec("git", ["rev-parse", "HEAD"], { cwd: source })).stdout.trim()
        : "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960";
      const prepared = await prepare({ sdk, source, revision, out: join(work, "prepared") });
      const baseline = join(prepared.gradingRoot, "workspace");
      const files = await readdir(baseline, { recursive: true });
      assert.equal(files.some(path => /(^|\/)(validation|mutation[^/]*)(\/|$)/.test(path)), false,
        "Agent and trusted starter baselines must not include private mutation fixtures");
      if (sdk === "watershed") {
        const seed = await buildShellFixture(sdk, { fake: false });
        try {
          await mkdir(join(baseline, "build/packages"), { recursive: true });
          for (const name of ["watershed.config_fingerprint", "watershed_lustre.config_fingerprint"]) {
            await cp(join(seed.workspace, "build/packages", name), join(baseline, "build/packages", name));
          }
        } finally { await seed.close(); }
      }
      await exec("pnpm", ["install", "--frozen-lockfile"], {
        cwd: baseline, timeout: 300_000, maxBuffer: 4 * 1024 * 1024,
      });
      const validateMutant = async (defect, classification = "agent") => {
        const workspace = join(work, defect);
        await cp(prepared.agentRoot, workspace, { recursive: true });
        if (defect !== "starter") {
          const extension = sdk === "fluid" ? "ts" : "gleam";
          const directory = join(workspace, sdk === "fluid" ? "src" : "src/incident_eval");
          for (const name of ["model", "schema"]) await cp(
            join(benchmark, "validation/solutions", sdk, `${name}.${extension}`),
            join(directory, `${name}.${extension}`));
        }
        if (Object.hasOwn(mutations, defect)) await applyMutation({ sdk, defect, workspace });
        const report = await grade({ sdk, workspace, gradingRoot: prepared.gradingRoot,
          runId: `validation-${sdk}-${defect}`, output: join(work, `${defect}.json`) });
        assert.equal(report.classification, classification,
          JSON.stringify(report.checks.filter(value => !value.passed), null, 2));
        return report;
      };
      await t.test("unfinished starter compiles but cannot pass native acceptance", async () => {
        const report = await validateMutant("starter");
        assert.equal(check(report, "integrity.build").passed, true);
        assert.equal(check(report, "native.schema").passed, false);
        assert.equal(verdict(report, contract), "failed");
      });
      await t.test("unmodified private reference passes the complete trusted path", async () => {
        const report = await validateMutant("reference");
        assert.equal(verdict(report, contract), "passed",
          JSON.stringify(report.checks.filter(value => !value.passed), null, 2));
      });
      for (const [defect, expected] of Object.entries(mutations)) {
        await t.test(`rejects ${defect} for its intended behavior`, async () => {
          const report = await validateMutant(defect);
          assert.equal(verdict(report, contract), "failed");
          if (defect !== "edit-shell") assert.equal(check(report, "integrity.build").passed, true,
            check(report, "integrity.build").evidence);
          assert.equal(check(report, expected.after).passed, true, `Must reach ${expected.after}`);
          for (const id of expected.failed) {
            const result = check(report, id);
            assert.equal(result.passed, false, `${defect} must fail ${id}`);
            assert.doesNotMatch(result.evidence, /^Not reached:/, `${id} must actually execute`);
            t.diagnostic(`${sdk}/${defect}: ${id}: ${result.evidence.split("\n")[0]}`);
          }
        });
      }
      await t.test("missing Chromium is explicitly infrastructure-invalid", async () => {
        const previous = process.env.WATERSHED_CHROME;
        try {
          process.env.WATERSHED_CHROME = join(work, "absent-chromium");
          const report = await validateMutant("missing-chromium", "infrastructure");
          assert.equal(verdict(report, contract), "invalid");
          assert.match(report.checks.map(value => value.evidence).join("\n"),
            /WATERSHED_CHROME does not exist/);
        } finally {
          if (previous === undefined) delete process.env.WATERSHED_CHROME;
          else process.env.WATERSHED_CHROME = previous;
        }
      });
      await t.test("independently interrupted native service is infrastructure-invalid after a successful build", async () => {
        const report = await interruptServiceDuringGrade({ sdk, baseline, work,
          grade: () => validateMutant("interrupted-service", "infrastructure") });
        assert.equal(check(report, "integrity.build").passed, true,
          check(report, "integrity.build").evidence);
        assert.equal(verdict(report, contract), "invalid");
        assert.match(report.checks.map(value => value.evidence).join("\n"),
          /Independent native service health probe failed/);
      });
    } finally { await rm(work, { recursive: true, force: true }); }
  });

  test(`${sdk} native probes reject the unfinished starter and real grading rejects sequential delivery`, async t => {
    const starter = await buildShellFixture(sdk, { fake: false, grader: true });
    let browser;
    let services;
    try {
      services = await startServices({ sdk, root: starter.workspace, runId: "validation-starter" });
      browser = await launchBrowser();
      const page = await (await browser.context()).page();
      await page.goto(services.appUrl);
      await wait("unfinished starter exposes inspection", () => page.evaluate(
        "typeof globalThis.__nativeEval?.inspect"), value => value === "function");
      await assert.rejects(page.evaluate("globalThis.__nativeEval.inspect()"),
        /native|handle|session|absent|implement/i);
    } finally {
      if (browser) await browser.close();
      if (services) await services.close();
      await starter.close();
    }
    const fixture = await buildShellFixture(sdk, { fake: false, solution: true, grader: true });
    services = undefined;
    browser = undefined;
    try {
      services = await startServices({ sdk, root: fixture.workspace, runId: "validation-sequential" });
      browser = await launchBrowser();
      // Bypass only holding. All submissions and delivery evidence still come from real SDK frames.
      services.transport.hold = () => {};
      const checks = [];
      await assert.rejects(runScenarios({ sdk, services, browser, record: value => checks.push(value) }),
        /Operation delivery escaped the active hold/);
      const report = { checks };
      assert.equal(check(report, "identity.removed").passed, true);
      assert.equal(check(report, "concurrency.distinct-fields").passed, false);
      assert.match(check(report, "concurrency.distinct-fields").evidence,
        /Operation delivery escaped the active hold/);
      t.diagnostic(`${sdk}/sequential-delivery: concurrency.distinct-fields: real remote delivery escaped hold`);
    } finally {
      if (browser) await browser.close();
      if (services) await services.close();
      await fixture.close();
    }
  });
}
