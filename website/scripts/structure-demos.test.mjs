import test from "node:test";
import assert from "node:assert/strict";
import puppeteer from "puppeteer-core";
import { findBrowser } from "../../smoke/cdp.mjs";

const base = process.env.WATERSHED_WEBSITE_URL ?? "http://127.0.0.1:4321";
const families = [
  ["counters", ["counter", "gcounter", "pn"]],
  ["sets", ["gset", "twopset", "orset"]],
  ["maps", ["map", "lww-map", "ormap"]],
  ["registers", ["lww-register", "mv-register", "registers"]],
  ["coordination", ["claims", "ordered", "tasks", "pact"]],
];

for (const width of [1440, 1100, 390]) {
  test(`structure demos replace descriptions in place at ${width}px`, { timeout: 90_000 }, async () => {
    const executablePath = findBrowser();
    assert.ok(executablePath, "Chromium is required; set WATERSHED_CHROME");
    const browser = await puppeteer.launch({ executablePath, headless: true });
    try {
      const page = await browser.newPage();
      await page.setViewport({ width, height: 1000 });
      await page.emulateMediaFeatures([{ name: "prefers-reduced-motion", value: "reduce" }]);
      const errors = [];
      page.on("pageerror", (error) => errors.push(error.message));

      for (const [family, ids] of families) {
        await page.goto(new URL(`/structures/${family}`, base).href);
        await page.waitForSelector("[data-race]:not([disabled])");
        assert.equal(await page.$eval("#demo", (demo) => demo.checkVisibility()), false);
        assert.equal(await page.$$eval(".plate-body", (bodies) => bodies.every((body) => body.checkVisibility())), true);

        for (const id of ids) {
          const toggle = `#${id} [data-structure-toggle]`;
          await page.focus(toggle);
          await page.keyboard.press("Enter");
          assert.equal(await page.$eval(toggle, (button) => button.getAttribute("aria-expanded")), "true");
          assert.equal(await page.$eval(".plate:has(#demo)", (plate) => plate.id), id);
          assert.equal(await page.$eval("[data-demo-rig]", (rig) => rig.dataset.dds), id);
          assert.equal(await page.$eval(`#${id} .plate-body`, (body) => body.checkVisibility()), false);
          assert.equal(await page.$$eval("[data-structure-demo]", (panels) => panels.filter((panel) => panel.checkVisibility()).length), 1);
          assert.equal(await page.$eval(toggle, (button) => button === document.activeElement), true);
          assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
        }

        await page.focus(".demo-skip");
        await page.keyboard.press("Enter");
        assert.equal(await page.evaluate(() => document.activeElement.id), `${ids.at(-1)}-after-demo`);
        const toggle = `#${ids.at(-1)} [data-structure-toggle]`;
        await page.focus(toggle);
        await page.keyboard.press("Space");
        assert.equal(await page.$eval("#demo", (demo) => demo.checkVisibility()), false);
        assert.equal(await page.$$eval(".plate-body", (bodies) => bodies.every((body) => body.checkVisibility())), true);
      }
      assert.deepEqual(errors, []);
    } finally {
      await browser.close();
    }
  });
}

test("descriptions and dedicated demo links work without JavaScript", async () => {
  const executablePath = findBrowser();
  assert.ok(executablePath, "Chromium is required; set WATERSHED_CHROME");
  const browser = await puppeteer.launch({ executablePath, headless: true });
  try {
    const page = await browser.newPage();
    await page.setJavaScriptEnabled(false);
    for (const family of ["counters", "maps", "registers", "sequences", "transforms"]) {
      await page.goto(new URL(`/structures/${family}`, base).href);
      assert.equal(await page.$$eval(".plate-body", (bodies) => bodies.every((body) => body.checkVisibility())), true);
      assert.equal(await page.$$eval("[data-structure-toggle]", (buttons) => buttons.some((button) => button.checkVisibility())), false);
      assert.equal(await page.$$eval("#demo", (demos) => demos.some((demo) => demo.checkVisibility())), false);
      if (family === "maps") {
        assert.equal(await page.$eval('#directory a[href="/directory"]', (link) => link.checkVisibility()), true);
      }
    }
  } finally {
    await browser.close();
  }
});
