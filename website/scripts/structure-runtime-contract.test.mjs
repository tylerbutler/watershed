import assert from "node:assert/strict";
import test from "node:test";
import { openBrowserTest } from "./browser-test-harness.mjs";

const base = process.env.WATERSHED_WEBSITE_URL ?? "http://127.0.0.1:4321";
const families = [
  ["counters", ["counter", "gcounter", "pn"]],
  ["sets", ["gset", "twopset", "orset"]],
  ["maps", ["map", "lww-map", "ormap"]],
  ["registers", ["lww-register", "mv-register", "registers"]],
  ["coordination", ["claims", "ordered", "tasks", "pact"]],
];

test("every structure mode sequences compiled Gleam and converges", { timeout: 180_000 }, async (t) => {
  const { page, errors } = await openBrowserTest(t, {
    width: 1440,
    height: 1000,
  });
  await page.setRequestInterception(true);
  page.on("request", (request) => {
    if (new URL(request.url()).hostname === "tinylytics.app") {
      void request.respond({ status: 204, body: "" });
    } else {
      void request.continue();
    }
  });

  for (const [family, ids] of families) {
    const response = await page.goto(new URL(`/structures/${family}`, base).href);
    assert.equal(response?.status(), 200);
    await page.waitForSelector("[data-race]:not([disabled])");

    for (const id of ids) {
      await page.click(`#${id} [data-structure-toggle]`);
      assert.equal(
        await page.$eval("[data-demo-rig]", (rig) => rig.dataset.dds),
        id,
      );
      assert.equal(
        await page.$eval("[data-demo-rig]", (rig) => rig.dataset.transport),
        "sluice",
      );
      const before = await page.$$eval("[data-op-log] li", (rows) => rows.length);
      await page.click("[data-race]");
      await page.waitForFunction(
        (count) =>
          document.querySelectorAll("[data-op-log] li").length > count &&
          document.querySelector("[data-status] .converged") !== null &&
          [...document.querySelectorAll("[data-pending-count]")].every(
            (element) => element.textContent?.trim() === "0 pending",
          ),
        { timeout: 20_000 },
        before,
      );
    }
  }

  assert.deepEqual(errors, []);
});
