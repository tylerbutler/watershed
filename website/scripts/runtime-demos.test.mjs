import assert from "node:assert/strict";
import test from "node:test";
import { launchBrowserTest } from "./browser-test-harness.mjs";

const base = process.env.WATERSHED_WEBSITE_URL ?? "http://127.0.0.1:4321";
const demos = [
  ["/sudoku", "[data-sudoku-race]", "[data-sudoku-status]"],
  ["/directory", "[data-dir-race]", "[data-dir-status]"],
  ["/sequence", "[data-route-race-move]", "[data-route-status]"],
  ["/text", "[data-text-race-insert]", "[data-text-status]"],
  ["/rich-text", "[data-rt-race-type]", "[data-rt-status]", "[data-rt-settle]"],
  ["/json-ot", "[data-jot-race]", "[data-jot-status]"],
  ["/guide/race", "[data-guide-race-add]", "[data-guide-race-status]"],
  [
    "/sharedtree/checklist",
    "[data-st-race]",
    "[data-st-status]",
    "[data-st-settle]",
  ],
];

test("dedicated demos execute compiled Gleam and converge", { timeout: 120_000 }, async (t) => {
  const browser = await launchBrowserTest(t);

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

test("SharedTree checklist restores keyboard focus after list replacement", { timeout: 120_000 }, async (t) => {
  const browser = await launchBrowserTest(t);
  const page = await browser.newPage();
  try {
    const response = await page.goto(
      new URL("/sharedtree/checklist", base).href,
    );
    assert.equal(response?.status(), 200);
    await page.waitForSelector(
      '[data-client="a"] input[aria-label="Client A item inspect spillway, not completed"]',
    );

    const toggle =
      '[data-client="a"] input[aria-label="Client A item inspect spillway, not completed"]';
    await page.focus(toggle);
    await page.keyboard.press("Space");
    assert.equal(
      await page.evaluate(
        () => document.activeElement?.getAttribute("aria-label"),
      ),
      "Client A item inspect spillway, completed",
    );

    const moveDown =
      '[data-client="a"] button[aria-label="Move Client A item inspect spillway down"]';
    await page.focus(moveDown);
    await page.keyboard.press("Enter");
    assert.equal(
      await page.evaluate(
        () => document.activeElement?.getAttribute("aria-label"),
      ),
      "Move Client A item inspect spillway down",
    );

    await page.keyboard.press("Enter");
    assert.equal(
      await page.evaluate(
        () => document.activeElement?.getAttribute("aria-label"),
      ),
      "Move Client A item inspect spillway up",
    );
  } finally {
    await page.close();
  }
});
