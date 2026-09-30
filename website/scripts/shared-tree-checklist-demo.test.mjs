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

async function openChecklist(t) {
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
  return page;
}

async function replaceText(page, selector, text) {
  await page.click(selector);
  await page.keyboard.down("Control");
  await page.keyboard.press("A");
  await page.keyboard.up("Control");
  await page.keyboard.type(text);
}

test("SharedTree checklist converges after local work and a stepped race", { timeout: 120_000 }, async (t) => {
  const page = await openChecklist(t);

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

test("focused checklist text preserves only dirty local drafts", { timeout: 120_000 }, async (t) => {
  const page = await openChecklist(t);

  await page.evaluate(() => {
    document
      .querySelector(
        '[data-client="b"] [data-item-id="publish-survey"][type="text"]',
      )
      ?.focus();
    document.querySelector("[data-st-race]")?.click();
    document.querySelector("[data-st-settle]")?.click();
  });
  await page.waitForFunction(() => {
    const canonical = document.querySelector(
      '[data-client="b"] [data-canonical]',
    );
    return canonical?.textContent?.includes("publish revised survey");
  });

  assert.equal(
    await page.$eval(
      '[data-client="b"] [data-item-id="publish-survey"][type="text"]',
      (input) => input.value,
    ),
    "publish revised survey",
  );

  await page.evaluate(() => {
    const input = document.querySelector(
      '[data-client="b"] [data-item-id="publish-survey"][type="text"]',
    );
    if (input instanceof HTMLInputElement) input.blur();
  });
  assert.deepEqual(
    await page.$$eval("[data-pending-count]", (elements) =>
      elements.map((element) => element.textContent?.trim())
    ),
    ["0 pending", "0 pending"],
  );
  assert.equal(
    (await canonicals(page))[1].find((item) => item.id === "publish-survey")
      ?.text,
    "publish revised survey",
  );

  await page.click("[data-st-reset]");
  await replaceText(
    page,
    '[data-client="b"] [data-item-id="publish-survey"][type="text"]',
    "publish local draft",
  );
  await page.evaluate(() => {
    document.querySelector("[data-st-race]")?.click();
    document.querySelector("[data-st-settle]")?.click();
  });
  assert.equal(
    await page.$eval(
      '[data-client="b"] [data-item-id="publish-survey"][type="text"]',
      (input) => input.value,
    ),
    "publish local draft",
  );
  assert.equal(
    (await canonicals(page))[1].find((item) => item.id === "publish-survey")
      ?.text,
    "publish revised survey",
  );

  await page.evaluate(() => {
    const input = document.querySelector(
      '[data-client="b"] [data-item-id="publish-survey"][type="text"]',
    );
    if (input instanceof HTMLInputElement) input.blur();
    document.querySelector("[data-st-settle]")?.click();
  });
  assert.equal(
    (await canonicals(page))[1].find((item) => item.id === "publish-survey")
      ?.text,
    "publish local draft",
  );
});

test("dirty checklist edits coexist with move, toggle, and Tab focus", { timeout: 120_000 }, async (t) => {
  const page = await openChecklist(t);

  await replaceText(
    page,
    '[data-client="a"] [data-item-id="review-field-notes"][type="text"]',
    "review revised notes",
  );
  await page.click(
    '[data-client="a"] [data-item-id="review-field-notes"][data-move-direction="down"]',
  );
  await page.click("[data-st-settle]");
  let clientA = (await canonicals(page))[0];
  assert.deepEqual(
    clientA.map((item) => item.id),
    ["inspect-spillway", "publish-survey", "review-field-notes"],
  );
  assert.equal(
    clientA.find((item) => item.id === "review-field-notes")?.text,
    "review revised notes",
  );

  await page.click("[data-st-reset]");
  await replaceText(
    page,
    '[data-client="a"] [data-item-id="review-field-notes"][type="text"]',
    "review toggled notes",
  );
  await page.click(
    '[data-client="a"] [data-item-id="review-field-notes"][type="checkbox"]',
  );
  await page.click("[data-st-settle]");
  clientA = (await canonicals(page))[0];
  assert.equal(
    clientA.find((item) => item.id === "review-field-notes")?.text,
    "review toggled notes",
  );
  assert.equal(
    clientA.find((item) => item.id === "review-field-notes")?.completed,
    true,
  );

  await page.click("[data-st-reset]");
  await replaceText(
    page,
    '[data-client="a"] [data-item-id="review-field-notes"][type="text"]',
    "review tab notes",
  );
  await page.keyboard.press("Tab");
  assert.deepEqual(
    await page.evaluate(() => ({
      id: document.activeElement?.getAttribute("data-item-id"),
      direction: document.activeElement?.getAttribute("data-move-direction"),
    })),
    { id: "review-field-notes", direction: "up" },
  );
  await page.click("[data-st-settle]");
  assert.equal(
    (await canonicals(page))[0].find(
      (item) => item.id === "review-field-notes",
    )?.text,
    "review tab notes",
  );
});

test("leaving a checklist while Tab is held commits its deferred edit", { timeout: 120_000 }, async (t) => {
  const page = await openChecklist(t);

  await replaceText(
    page,
    '[data-client="a"] [data-item-id="publish-survey"][type="text"]',
    "publish held-tab draft",
  );
  await page.keyboard.down("Tab");
  await page.keyboard.down("Tab");
  await page.keyboard.up("Tab");
  assert.equal(
    await page.evaluate(() =>
      document.activeElement?.matches('[data-client="b"] [data-st-draft]')
    ),
    true,
  );

  await page.click("[data-st-settle]");
  const settled = await canonicals(page);
  assert.equal(
    settled[0].find((item) => item.id === "publish-survey")?.text,
    "publish held-tab draft",
  );
  assert.equal(
    settled[1].find((item) => item.id === "publish-survey")?.text,
    "publish held-tab draft",
  );
});

test("repeated and boundary checklist races settle without phantom pending state", { timeout: 120_000 }, async (t) => {
  const page = await openChecklist(t);

  for (let index = 0; index < 4; index += 1) {
    await page.click("[data-st-race]");
    await page.click("[data-st-settle]");
    assert.deepEqual(
      await page.$$eval("[data-pending-count]", (elements) =>
        elements.map((element) => element.textContent?.trim())
      ),
      ["0 pending", "0 pending"],
    );
  }

  await page.click("[data-st-reset]");
  for (let index = 0; index < 2; index += 1) {
    await page.click(
      '[data-client="b"] [data-item-id="inspect-spillway"][data-move-direction="down"]',
    );
    await page.click("[data-st-settle]");
  }
  assert.deepEqual(
    (await canonicals(page))[1].map((item) => item.id),
    ["review-field-notes", "publish-survey", "inspect-spillway"],
  );

  await page.click("[data-st-race]");
  await page.waitForFunction(
    () => document.querySelector("[data-st-status] .converged") !== null,
    { timeout: 5_000 },
  );
  assert.deepEqual(
    await page.$$eval("[data-pending-count]", (elements) =>
      elements.map((element) => element.textContent?.trim())
    ),
    ["0 pending", "0 pending"],
  );
});

test("Race keeps the current checklist and Reset names the baseline reset", { timeout: 120_000 }, async (t) => {
  const page = await openChecklist(t);

  const hint = await page.$eval(
    "#sharedtree-checklist-demo .demo-hint",
    (element) => element.textContent ?? "",
  );
  assert.equal(hint.includes("resets the seeded checklist"), false);
  assert.match(
    await page.$eval("[data-st-reset]", (element) =>
      element.getAttribute("aria-label") ?? ""
    ),
    /seeded checklist/i,
  );
});
