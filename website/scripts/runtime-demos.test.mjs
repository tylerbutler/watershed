import assert from "node:assert/strict";
import test from "node:test";
import puppeteer from "puppeteer-core";
import { findBrowser } from "../../smoke/cdp.mjs";

const base = process.env.WATERSHED_WEBSITE_URL ?? "http://127.0.0.1:4321";
const demos = [
  ["/sudoku", "[data-sudoku-race]", "[data-sudoku-status]"],
  ["/directory", "[data-dir-race]", "[data-dir-status]"],
  ["/sequence", "[data-route-race-move]", "[data-route-status]"],
  ["/text", "[data-text-race-insert]", "[data-text-status]"],
  ["/rich-text", "[data-rt-race-type]", "[data-rt-status]", "[data-rt-settle]"],
  ["/json-ot", "[data-jot-race]", "[data-jot-status]"],
  ["/guide/race", "[data-guide-race-add]", "[data-guide-race-status]"],
];

test("dedicated demos execute compiled Gleam and converge", { timeout: 120_000 }, async (t) => {
  const executablePath = findBrowser();
  assert.ok(executablePath, "Chromium is required; set WATERSHED_CHROME");
  const browser = await puppeteer.launch({
    executablePath,
    headless: true,
    args: ["--no-sandbox", "--disable-dev-shm-usage"],
  });
  t.after(() => browser.close());

  for (const [path, action, status, settle] of demos) {
    await t.test(path, async () => {
      const page = await browser.newPage();
      const errors = [];
      page.on("pageerror", (error) => errors.push(error.message));
      try {
        const response = await page.goto(new URL(path, base).href);
        assert.equal(response?.status(), 200);
        await page.waitForSelector(`${action}:not([disabled])`);
        await page.click(action);
        if (settle) {
          await page.waitForSelector(`${settle}:not([disabled])`);
          await page.click(settle);
        }
        await page.waitForFunction(
          (selector) =>
            document.querySelector(selector)?.textContent?.includes("Converged"),
          { timeout: 30_000 },
          status,
        );
        assert.equal(
          await page.$$eval("[data-pending-count]", (elements) =>
            elements.every((element) =>
              ["0 pending", "synced"].includes(element.textContent?.trim() ?? "")
            ),
          ),
          true,
        );
        const canonical = await page.$$eval("[data-canonical]", (elements) =>
          elements.map((element) => element.textContent?.trim() ?? "")
        );
        if (canonical.length > 0) {
          assert.ok(canonical[0]);
          assert.ok(canonical.every((value) => value === canonical[0]));
        }
        assert.deepEqual(errors, []);
      } finally {
        await page.close();
      }
    });
  }

  const page = await browser.newPage();
  try {
    await page.goto(new URL("/text", base).href);
    await page.waitForFunction(
      () => customElements.get("watershed-textarea") !== undefined,
    );
    assert.equal(await page.$$eval("watershed-textarea", (elements) => elements.length), 2);
  } finally {
    await page.close();
  }
});
