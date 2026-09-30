import assert from "node:assert/strict";
import test from "node:test";
import { openBrowserTest } from "./browser-test-harness.mjs";

const base = process.env.WATERSHED_WEBSITE_URL ?? "http://127.0.0.1:4321";
const baselineIds = [
  "inspect-spillway",
  "review-field-notes",
  "publish-survey",
];

async function canonicals(page) {
  return page.$$eval("[data-canonical]", (elements) =>
    elements.map((element) => JSON.parse(element.textContent ?? "[]"))
  );
}

test("SharedTree checklist converges after local work and a stepped race", { timeout: 120_000 }, async (t) => {
  const { page, errors } = await openBrowserTest(t);
  await page.setRequestInterception(true);
  page.on("request", (request) => {
    if (new URL(request.url()).hostname === "tinylytics.app") {
      void request.respond({ status: 204, body: "" });
    } else {
      void request.continue();
    }
  });
  t.after(() => assert.deepEqual(errors, []));

  const response = await page.goto(new URL("/sharedtree/checklist", base).href);
  assert.equal(response?.status(), 200);
  await page.waitForSelector("[data-st-race]:not([disabled])");

  const initial = await canonicals(page);
  assert.equal(initial.length, 2);
  assert.deepEqual(initial[0], initial[1]);

  await page.$eval('[data-client="a"] [data-st-draft]', (input) => {
    input.value = "mark low ford";
  });
  await page.click('[data-client="a"] [data-st-add]');
  await page.click("[data-st-settle]");
  await page.waitForFunction(() =>
    [...document.querySelectorAll("[data-canonical]")].every((element) =>
      element.textContent?.includes("mark low ford")
    )
  );

  const afterAdd = await canonicals(page);
  assert.deepEqual(afterAdd[0], afterAdd[1]);
  const added = afterAdd[0].find((item) => item.text === "mark low ford");
  assert.ok(added);

  await page.click("[data-st-race]");
  await page.click("[data-st-step]");
  assert.equal(await page.$("[data-st-status] .converged"), null);

  await page.click("[data-st-settle]");
  await page.waitForFunction(() =>
    document.querySelector("[data-st-status] .converged") !== null
  );

  const final = await canonicals(page);
  assert.deepEqual(final[0], final[1]);
  assert.deepEqual(
    final[0].map((item) => item.id),
    [
      "review-field-notes",
      "inspect-spillway",
      "publish-survey",
      added.id,
    ],
  );
  assert.equal(
    final[0].find((item) => item.id === "publish-survey")?.text,
    "publish revised survey",
  );
  assert.deepEqual(
    await page.$$eval("[data-pending-count]", (elements) =>
      elements.map((element) => element.textContent?.trim())
    ),
    ["0 pending", "0 pending"],
  );

  await page.click("[data-st-reset]");
  await page.waitForFunction((ids) => {
    const values = [...document.querySelectorAll("[data-canonical]")].map(
      (element) => JSON.parse(element.textContent ?? "[]"),
    );
    return values.length === 2
      && values.every((items) =>
        JSON.stringify(items.map((item) => item.id)) === JSON.stringify(ids)
      );
  }, {}, baselineIds);
  assert.deepEqual(await canonicals(page), initial);
});
