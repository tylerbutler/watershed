import test from "node:test";
import assert from "node:assert/strict";
import puppeteer from "puppeteer-core";
import { findBrowser } from "../../smoke/cdp.mjs";

const base = process.env.WATERSHED_WEBSITE_URL ?? "http://127.0.0.1:4321";
const client = (id, selector) => `[data-client="${id}"] ${selector}`;

async function settled(page, expected) {
  await page.waitForFunction((want) => {
    const views = [...document.querySelectorAll("[data-mv-register-values], [data-mv-register-confirmed]")];
    return views.length === 6
      && views.every((view) => view.textContent === JSON.stringify(want))
      && document.querySelector("[data-status] .converged");
  }, { timeout: 15_000 }, expected);
}

async function write(page, id, text) {
  await page.$eval(client(id, "[data-mv-register-input]"), (input, value) => {
    input.value = value;
  }, text);
  await page.click(client(id, "[data-mv-register-write]"));
}

for (const path of ["/structures/maps", "/mv-register"]) {
  test(`MV register race, resolution, replay and reset on ${path}`, { timeout: 90_000 }, async () => {
    const executablePath = findBrowser();
    assert.ok(executablePath, "Chromium is required; set WATERSHED_CHROME");
    const browser = await puppeteer.launch({
      executablePath, headless: true, args: ["--no-sandbox", "--disable-dev-shm-usage"],
    });
    try {
      const page = await browser.newPage();
      await page.setViewport({ width: 1500, height: 1100 });
      await page.emulateMediaFeatures([{ name: "prefers-reduced-motion", value: "reduce" }]);
      const errors = [];
      page.on("pageerror", (error) => errors.push(error.message));
      const response = await page.goto(new URL(path, base).href);
      assert.equal(response.status(), 200);
      await page.waitForSelector('[data-mv-register-write]:not([disabled])', { timeout: 10_000 });
      if (path === "/structures/maps") {
        await page.focus('[data-dds-pick][value="mv-register"]');
        await page.keyboard.press("Space");
      }
      await page.$eval("[data-pace]", (input) => {
        input.value = input.max;
        input.dispatchEvent(new Event("input", { bubbles: true }));
      });
      await settled(page, ["Survey datum"]);
      await page.focus("[data-race]");
      await page.keyboard.press("Enter");
      await page.waitForFunction(() =>
        document.querySelector('[data-client="a"] [data-mv-register-values]').textContent === '["raise crest"]'
        && document.querySelector('[data-client="a"] [data-mv-register-confirmed]').textContent === '["Survey datum"]',
      );
      await settled(page, ["arm pump", "raise crest"]);
      assert.match(await page.$eval("[data-status]", (el) => el.textContent), /2 alternatives/);
      if (path === "/structures/maps") {
        await page.click('[data-dds-pick][value="ormap"]');
        await page.click('[data-dds-pick][value="mv-register"]');
        await settled(page, ["arm pump", "raise crest"]);
      }
      await page.click(client("a", "[data-mv-register-resolve]"));
      await settled(page, ["raise crest + arm pump"]);
      await page.click("[data-replay]");
      await settled(page, ["raise crest + arm pump"]);
      await page.click("[data-cut-link]");
      await write(page, "b", "offline note");
      await write(page, "a", "online note");
      await page.waitForFunction(() =>
        document.querySelector('[data-client="a"] [data-mv-register-confirmed]').textContent === '["online note"]',
      );
      await page.click("[data-cut-link]");
      await settled(page, ["offline note", "online note"]);
      await page.click("[data-cut-link]");
      await write(page, "b", "discard held");
      await write(page, "a", "discard catch-up");
      await page.waitForFunction(() =>
        document.querySelector('[data-client="a"] [data-mv-register-confirmed]').textContent === '["discard catch-up"]',
      );
      await write(page, "a", "discard delayed");
      await page.click("[data-reset]");
      await page.click("[data-cut-link]");
      await settled(page, ["Survey datum"]);
      await page.focus(client("c", "[data-mv-register-input]"));
      await page.keyboard.down("Control");
      await page.keyboard.press("KeyA");
      await page.keyboard.up("Control");
      await page.keyboard.type("<b>literal text</b>");
      await page.keyboard.press("Enter");
      await settled(page, ["<b>literal text</b>"]);
      assert.equal(await page.$(client("c", "[data-mv-register-values] b")), null);
      assert.deepEqual(errors, []);
    } finally {
      await browser.close();
    }
  });
}
