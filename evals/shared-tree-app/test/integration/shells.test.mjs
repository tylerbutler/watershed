import assert from "node:assert/strict";
import test from "node:test";
import { launchBrowser } from "../../lib/cdp.mjs";
import { buildShellFixture } from "../shell-fixture.mjs";
import { smoke } from "../../public/smoke.mjs";

for (const sdk of ["watershed", "fluid"]) {
  test(`${sdk} unfinished model builds but displays an error instead of readiness`, async () => {
    const fixture = await buildShellFixture(sdk, { fake: false });
    let browser;
    try {
      browser = await launchBrowser({});
      const context = await browser.context();
      const page = await context.page();
      await page.goto(fixture.url);
      await page.waitFor('[data-state="error"]');
      assert.equal(await page.evaluate('document.querySelector("[role=alert]").textContent'), "Not implemented");
      assert.equal(await page.evaluate('document.querySelector("[data-action=add-incident]").disabled'), true);
      assert.equal(await page.evaluate('document.querySelector("[data-state=ready]") !== null'), false);
      assert.equal(await page.evaluate('document.querySelector("[data-empty=incidents]").textContent'), "No incidents");
      assert.deepEqual(page.errors(), []);
      await assert.rejects(smoke(fixture.url), /Native model error: Not implemented/);
    } finally {
      if (browser) await browser.close();
      await fixture.close();
    }
  });

  test(`${sdk} shell renders nested state and forwards ID-based actions`, async () => {
    const fixture = await buildShellFixture(sdk);
    let browser;
    try {
      browser = await launchBrowser({});
      const context = await browser.context();
      const page = await context.page();
      await page.goto(fixture.url);
      await page.waitFor('[data-state="ready"]');
      assert.equal(await page.evaluate('document.querySelectorAll("[data-incident-id]").length'), 2);
      assert.equal(await page.evaluate('document.querySelectorAll("[data-step-id]").length'), 2);
      assert.equal(await page.evaluate("globalThis.__incidentEval.snapshot().board.incidents[0].title"), "First");
      assert.deepEqual(await page.evaluate(`(() => {
        const incident = document.querySelector('[data-incident-id="incident-a"]');
        const step = document.querySelector('[data-step-id="step-a"]');
        return {
          status: incident.querySelector('[data-field="status"]').value,
          assignee: incident.querySelector('[data-field="assignee"]').value,
          assigned: incident.querySelector('[data-assignee-present]').getAttribute('data-assignee-present'),
          unassigned: document.querySelector('[data-incident-id="incident-b"] [data-assignee-present]')
            .getAttribute('data-assignee-present'),
          label: step.querySelector('[data-field="step-label"]').value,
          done: step.querySelector('[data-field="step-done"]').checked,
          actions: Array.from(document.querySelectorAll('[data-action]'), el => el.getAttribute('data-action'))
            .filter((action, index, values) => values.indexOf(action) === index).sort(),
        };
      })()`), {
        status: "open", assignee: "Alex", assigned: "true", unassigned: "false", label: "One", done: false,
        actions: ["add-incident", "add-step", "assignee-remove", "close", "incident-down", "incident-up",
          "remove-incident", "remove-step", "step-down", "step-up"],
      });
      await page.fill('[data-incident-id="incident-b"] [data-field="title"]', "Updated");
      assert.deepEqual(await page.evaluate("globalThis.__actions.at(-1)"), {
        type: "title", id: "incident-b", value: "Updated",
      });
      assert.equal(await page.evaluate("globalThis.__incidentEval.snapshot().board.incidents[1].title"), "Updated");
      await page.evaluate('globalThis.__incidentEval.apply({type:"title",id:"incident-a",value:"Direct action"})');
      assert.deepEqual(await page.evaluate("globalThis.__actions.at(-1)"), {
        type: "title", id: "incident-a", value: "Direct action",
      });
      await page.click('[data-incident-id="incident-b"] [data-action="incident-up"]');
      assert.deepEqual(await page.evaluate("globalThis.__actions.at(-1)"), {
        type: "move-incident", id: "incident-b", before: "incident-a",
      });
      await page.click('[data-incident-id="incident-a"] [data-action="assignee-remove"]');
      assert.deepEqual(await page.evaluate("globalThis.__actions.at(-1)"), {
        type: "assignee", id: "incident-a", value: null,
      });
      await page.click('[data-step-id="step-b"] [data-action="step-up"]');
      assert.deepEqual(await page.evaluate("globalThis.__actions.at(-1)"), {
        type: "move-step", incident: "incident-a", id: "step-b", before: "step-a",
      });
      await page.click('[data-action="close"]');
      await page.waitFor('[data-state="closed"]');
      assert.equal(await page.evaluate(
        'Array.from(document.querySelectorAll("input,select,button")).every(el => el.disabled)',
      ), true);
      assert.equal(await page.evaluate(`(() => {
        const count = globalThis.__actions.length;
        globalThis.__incidentEval.apply({ type: "title", id: "incident-a", value: "After close" });
        return globalThis.__actions.length === count;
      })()`), true);
      assert.deepEqual(page.errors(), []);
    } finally {
      if (browser) await browser.close();
      await fixture.close();
    }
  });

  test(`${sdk} public smoke creates and reads an SDK-free shell fixture`, async () => {
    const fixture = await buildShellFixture(sdk);
    try {
      await smoke(`${fixture.url}?empty=1`);
      await assert.rejects(smoke(`${fixture.url}?empty=1&fail-edit=1`), /Service rejected the edit/);
    } finally {
      await fixture.close();
    }
  });
}
