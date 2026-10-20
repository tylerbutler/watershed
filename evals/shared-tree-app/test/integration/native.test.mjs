import assert from "node:assert/strict";
import test from "node:test";
import { buildShellFixture } from "../shell-fixture.mjs";
import { launchBrowser } from "../../lib/cdp.mjs";
import { startServices } from "../../lib/services.mjs";
import { wait } from "../../lib/conditions.mjs";
import { fileURLToPath } from "node:url";

for (const sdk of ["watershed", "fluid"]) {
  test(`${sdk} private reference model uses real nested SharedTree nodes`, async () => {
    const fixture = await buildShellFixture(sdk, { fake: false, solution: true, grader: true });
    let services;
    let browser;
    try {
      services = await startServices({ sdk, root: fixture.workspace, runId: "native-validation" });
      browser = await launchBrowser();
      const context = await browser.context();
      const page = await context.page();
      await page.goto(services.appUrl);
      try {
        await wait("native reference ready", () => page.evaluate(`(() => {
        const errors = [...document.querySelectorAll("[role=alert]")].map(el => el.textContent);
        if (errors.length) throw new Error(errors.join("; "));
        return globalThis.__incidentEval?.snapshot();
      })()`), state => state?.phase === "ready");
      } catch (error) {
        throw new Error(`${error.message}; network=${JSON.stringify(page.networkErrors())}`);
      }

      const result = await page.evaluate("globalThis.__nativeEval.inspect()");
      assert.equal(result.schema, true);
      assert.equal(result.native, true);
      assert.deepEqual(result.board, { incidents: [] });
      const snapshot = () => page.evaluate("globalThis.__incidentEval.snapshot()");
      const native = () => page.evaluate("globalThis.__nativeEval.inspect()");
      const apply = async (action, expected) => {
        await page.evaluate(`globalThis.__incidentEval.apply(${JSON.stringify(action)})`);
        await wait(action.type, snapshot, state => expected(state.board));
        assert.deepEqual((await native()).board, (await snapshot()).board);
      };
      await apply({ type: "add-incident", id: "incident-first", title: "First" },
        board => board.incidents.length === 1);
      await apply({ type: "add-incident", id: "incident-second", title: "Second" },
        board => board.incidents.length === 2);
      await apply({ type: "add-step", incident: "incident-first", id: "step-first", label: "One" },
        board => board.incidents[0].steps.length === 1);
      await apply({ type: "add-step", incident: "incident-first", id: "step-second", label: "Two" },
        board => board.incidents[0].steps.length === 2);
      await page.evaluate("globalThis.__nativeEval.capture()");
      await apply({ type: "assignee", id: "incident-first", value: "" },
        board => board.incidents[0].assignee === "");
      await apply({ type: "assignee", id: "incident-first", value: null },
        board => !Object.hasOwn(board.incidents[0], "assignee"));
      await apply({ type: "move-incident", id: "incident-first", before: null },
        board => board.incidents.at(-1).id === "incident-first");
      await apply({ type: "move-incident", id: "incident-first", before: "incident-second" },
        board => board.incidents[0].id === "incident-first");
      await apply({ type: "move-step", incident: "incident-first", id: "step-first", before: null },
        board => board.incidents[0].steps.at(-1).id === "step-first");
      await apply({ type: "move-step", incident: "incident-first", id: "step-first", before: "step-second" },
        board => board.incidents[0].steps[0].id === "step-first");
      await apply({ type: "title", id: "incident-first", value: "Changed" },
        board => board.incidents[0].title === "Changed");
      await apply({ type: "step-label", incident: "incident-first", id: "step-first", value: "Changed step" },
        board => board.incidents[0].steps[0].label === "Changed step");
      assert.equal((await page.evaluate(
        'globalThis.__nativeEval.capturedState("incident:incident-first")')).value.title, "Changed");
      assert.equal((await page.evaluate(
        'globalThis.__nativeEval.capturedState("step:step-first")')).value.label, "Changed step");
      await page.evaluate('globalThis.__nativeEval.setCaptured("incident:incident-first", "title", "Native reference")');
      await wait("captured native edit renders", snapshot,
        state => state.board.incidents[0].title === "Native reference");
      await apply({ type: "remove-step", incident: "incident-first", id: "step-first" },
        board => board.incidents[0].steps.length === 1);
      assert.equal((await page.evaluate(
        'globalThis.__nativeEval.capturedState("step:step-first")')).attached, false);
      await apply({ type: "step-label", incident: "incident-first", id: "step-first", value: "Removed" },
        board => board.incidents[0].steps[0].label === "Two");
      await apply({ type: "remove-incident", id: "incident-first" },
        board => board.incidents.length === 1);
      assert.equal((await page.evaluate(
        'globalThis.__nativeEval.capturedState("incident:incident-first")')).attached, false);
      await apply({ type: "title", id: "incident-first", value: "Removed" },
        board => board.incidents[0].title === "Second");
      await page.evaluate(`(() => {
        globalThis.__nativeEval.setCaptured("incident:incident-second", "title", "Queued before close");
        globalThis.__incidentEval.close();
      })()`);
      await wait("native session closed", snapshot, state => state.phase === "closed");
      await page.evaluate("new Promise(requestAnimationFrame)");
      assert.equal((await snapshot()).phase, "closed");
      assert.deepEqual(await page.evaluate("globalThis.__nativeEval.closed()"), {
        viewClosed: true, documentClosed: true,
      });
      const closed = await snapshot();
      await page.evaluate('globalThis.__incidentEval.apply({type:"title",id:"incident-second",value:"After close"})');
      assert.deepEqual(await snapshot(), closed);

      for (const failure of ["create", "open"]) {
        const bad = new URL(services.appUrl);
        if (failure === "open") bad.searchParams.set("document", "missing-document");
        else services.rejectHttpWrites(true);
        const failed = await context.page();
        await failed.goto(bad.href);
        await wait(`visible ${failure} failure`, () => failed.evaluate(
          'document.querySelector("[role=alert]")?.textContent'), Boolean, 30_000);
        assert.equal(await failed.evaluate('document.querySelector("[data-state=ready]") !== null'), false);
        await failed.close();
        services.rejectHttpWrites(false);
        if (failure === "create") assert.equal(services.diagnostics().rejectedRequests.length, 1);
      }
      await wait("original native connections closed", async () => services.diagnostics().openSockets,
        count => count === 0);
      const before = services.diagnostics().completedWrites;
      services.holdHttpWrites(true);
      const early = await context.page();
      await early.goto(services.appUrl);
      await wait("creation held before native initialization completes",
        async () => services.diagnostics().pendingWrites, count => count === 1);
      assert.equal(await early.evaluate('document.querySelector("[data-action=close]").disabled'), false,
        "Close must be available while opening");
      await early.click("[data-action=close]");
      await early.waitFor('[data-state="closed"]');
      services.holdHttpWrites(false);
      await wait("late creation response completed", async () => services.diagnostics().completedWrites,
        count => count > before);
      if (sdk === "fluid") {
        await wait("late native session was closed", () => early.evaluate(
          "globalThis.__incidentEval.native() !== undefined"), Boolean);
        assert.deepEqual(await early.evaluate("globalThis.__nativeEval.closed()"), {
          viewClosed: true, documentClosed: true,
        });
      }
      await early.evaluate("new Promise(requestAnimationFrame)");
      assert.equal(await early.evaluate("globalThis.__incidentEval.snapshot().phase"), "closed");
      await wait("no late native transport survives Close", async () => services.diagnostics().openSockets,
        count => count === 0);
      assert.deepEqual(early.errors(), []);
      await early.close();
      assert.deepEqual(page.errors(), []);
    } finally {
      if (browser) await browser.close();
      if (services) await services.close();
      await fixture.close();
    }
  });
}

test("Fluid native schema rejects a local-only assignee even with empty arrays", async () => {
  const fixture = await buildShellFixture("fluid", {
    fake: false, solution: true, grader: true,
    schemaFixture: fileURLToPath(new URL("../../validation/fixtures/fluid-local-assignee.ts", import.meta.url)),
  });
  let services;
  let browser;
  try {
    services = await startServices({ sdk: "fluid", root: fixture.workspace, runId: "schema-rejection" });
    browser = await launchBrowser();
    const context = await browser.context();
    const page = await context.page();
    await page.goto(services.appUrl);
    await wait("schema mutant ready", () => page.evaluate("globalThis.__incidentEval?.snapshot().phase"),
      phase => phase === "ready");
    await assert.rejects(page.evaluate("globalThis.__nativeEval.inspect()"), /assignee|optional/i);
  } finally {
    if (browser) await browser.close();
    if (services) await services.close();
    await fixture.close();
  }
});
