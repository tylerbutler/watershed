import assert from "node:assert/strict";
import test from "node:test";
import { openBrowserTest } from "./browser-test-harness.mjs";

const base = process.env.WATERSHED_WEBSITE_URL ?? "http://127.0.0.1:4321";

test("guide race styles reach dynamically created notes", { timeout: 30_000 }, async (t) => {
  const { page, errors } = await openBrowserTest(t, { reducedMotion: false });
  await page.setRequestInterception(true);
  page.on("request", (request) => {
    if (new URL(request.url()).hostname === "tinylytics.app") {
      void request.respond({ status: 204, body: "" });
    } else {
      void request.continue();
    }
  });
  page.setDefaultTimeout(15_000);

  const response = await page.goto(new URL("/guide/race/", base).href, {
    waitUntil: "networkidle0",
  });
  assert.equal(response?.status(), 200);
  await page.$eval("[data-guide-race-add]", (el) => el.scrollIntoView());
  await page.waitForSelector("[data-guide-race-add]:not([disabled])");

  const sequencedStyle = await page.$eval(
    '[data-client="a"] .gr-note.is-sequenced',
    (el) => {
      const style = getComputedStyle(el);
      return {
        border: style.borderStyle,
        background: style.backgroundColor,
        color: style.color,
      };
    },
  );
  assert.equal(
    sequencedStyle.border,
    "solid",
    `sequenced note has no border (got border-style: ${sequencedStyle.border}); .gr-note is not reaching JS-created nodes`,
  );

  await page.$eval("[data-guide-race-pace]", (el) => {
    el.value = "0.25";
    el.dispatchEvent(new Event("input", { bubbles: true }));
  });
  await page.evaluate(() => {
    Math.random = () => 1;
  });
  await page.$eval("[data-guide-race-latency-variance]", (el) => {
    el.checked = true;
    el.dispatchEvent(new Event("change", { bubbles: true }));
  });
  assert.equal(
    await page.$eval("[data-guide-race-latency-variance]", (el) => el.checked),
    true,
    "latency variance must be enabled before sampling jitter",
  );
  await page.click("[data-guide-race-add]");
  await page.waitForSelector("[data-flow-layer] .flow-dot-label");
  const flowLabel = await page.$eval(
    "[data-flow-layer] .flow-dot-label",
    (el) => el.textContent,
  );
  assert.match(
    flowLabel ?? "",
    /\b1100 ms\b/,
    "request marker does not show the expected 1000 + 100 ms jitter sample",
  );

  await page.waitForSelector('[data-client="a"] .gr-note.is-note-pending');
  const pendingStyle = await page.$eval(
    '[data-client="a"] .gr-note.is-note-pending',
    (el) => {
      const style = getComputedStyle(el);
      return {
        border: style.borderStyle,
        background: style.backgroundColor,
        color: style.color,
      };
    },
  );
  assert.equal(
    pendingStyle.border,
    "solid",
    `pending note has no border (got border-style: ${pendingStyle.border})`,
  );
  assert.notEqual(
    pendingStyle.background,
    sequencedStyle.background,
    `pending note background (${pendingStyle.background}) does not differ from sequenced note background (${sequencedStyle.background}); .gr-note.is-note-pending is not matching`,
  );
  assert.notEqual(
    pendingStyle.color,
    sequencedStyle.color,
    `pending note color (${pendingStyle.color}) does not differ from sequenced note color (${sequencedStyle.color}); .gr-note.is-note-pending is not matching`,
  );

  await page.waitForFunction(
    () => document.querySelector("[data-guide-race-status]")?.textContent?.includes("Converged"),
    { timeout: 15_000 },
  );
  assert.deepEqual(errors, []);
});
