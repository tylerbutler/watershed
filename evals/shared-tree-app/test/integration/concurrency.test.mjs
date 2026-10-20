import assert from "node:assert/strict";
import test from "node:test";
import { buildShellFixture } from "../shell-fixture.mjs";
import { launchBrowser } from "../../lib/cdp.mjs";
import { startServices } from "../../lib/services.mjs";
import { wait } from "../../lib/conditions.mjs";
import { createBarrier } from "../../lib/barrier.mjs";

for (const sdk of ["watershed", "fluid"]) {
  test(`${sdk} real native clients submit concurrent edits before remote delivery`, async () => {
    const fixture = await buildShellFixture(sdk, { fake: false, solution: true });
    let services;
    let browser;
    let barrier;
    try {
      services = await startServices({ sdk, root: fixture.workspace, runId: "concurrency-validation" });
      browser = await launchBrowser();
      const a = await (await browser.context()).page();
      const b = await (await browser.context()).page();
      const snapshot = page => page.evaluate("globalThis.__incidentEval?.snapshot()");
      await a.goto(services.appUrl);
      await wait("first ready", () => snapshot(a), state => state?.phase === "ready");
      await a.click("[data-action=add-incident]");
      await wait("incident created", () => snapshot(a), state => state.board.incidents.length === 1);
      const url = await a.evaluate("location.href");
      await b.goto(url);
      await wait("second ready with incident", () => snapshot(b),
        state => state?.phase === "ready" && state.board.incidents.length === 1);
      const clients = services.transport.clients();
      assert.equal(clients.length, 2);
      barrier = createBarrier({ transport: services.transport, clients });
      barrier.hold();
      await a.fill("[data-field=title]", "Concurrent title");
      await b.fill("[data-field=assignee]", "Concurrent assignee");
      await barrier.waitForSubmissions();
      assert.equal((await snapshot(a)).board.incidents[0].assignee, undefined);
      assert.equal((await snapshot(b)).board.incidents[0].title, "");
      const evidence = barrier.evidence();
      assert.equal(evidence.submittedClients.length, 2);
      barrier.release();
      await wait("native convergence after held delivery", async () =>
        Promise.all([snapshot(a), snapshot(b)]), states =>
        states.every(state => state.board.incidents[0].title === "Concurrent title"
          && state.board.incidents[0].assignee === "Concurrent assignee"));
      assert.deepEqual(a.errors(), []);
      assert.deepEqual(b.errors(), []);
      assert.deepEqual(services.diagnostics().transportErrors, []);
    } finally {
      barrier?.close();
      if (browser) await browser.close();
      if (services) await services.close();
      await fixture.close();
    }
  });
}
