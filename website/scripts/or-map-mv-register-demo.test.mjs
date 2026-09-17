import test from "node:test";
import assert from "node:assert/strict";
import puppeteer from "puppeteer-core";
import { findBrowser } from "../../smoke/cdp.mjs";

const base = process.env.WATERSHED_WEBSITE_URL ?? "http://127.0.0.1:4321";
const view = "or-map-mv-register";
const client = (id, part) => `[data-client="${id}"] [data-${view}-${part}]`;
const baseline = [["gate-mode", ["surveyed"]]];

async function settled(page, expected) {
  await page.waitForFunction((want) => {
    const outputs = [...document.querySelectorAll(
      "[data-or-map-mv-register-entries], [data-or-map-mv-register-confirmed]",
    )];
    return outputs.length === 6
      && outputs.every((output) => output.textContent === JSON.stringify(want))
      && document.querySelector("[data-status] .converged");
  }, { timeout: 15_000 }, expected);
  const summaries = await page.$$eval(
    "[data-or-map-mv-register-canonical-summary]",
    (els) => els.map((el) => el.getAttribute("data-or-map-mv-register-canonical-summary")),
  );
  assert.equal(summaries.length, 3);
  assert.ok(summaries.every((summary) => summary === summaries[0]), summaries.join("\n"));
  assert.deepEqual(await page.$$eval("[data-pending-count]", (els) =>
    els.map((el) => el.textContent)), ["0 pending", "0 pending", "0 pending"]);
}

async function write(page, id, key, value, keyboard = false) {
  await page.$eval(client(id, "key"), (el, text) => {
    el.value = text;
    el.dispatchEvent(new Event("input", { bubbles: true }));
  }, key);
  await page.$eval(client(id, "input"), (el, text) => { el.value = text; }, value);
  if (keyboard) {
    await page.focus(client(id, "input"));
    await page.keyboard.press("Enter");
  } else {
    await page.click(client(id, "write"));
  }
}

async function reset(page) {
  await page.click("[data-reset]");
  await settled(page, baseline);
}

test("OR-map MV registers share the maps rig without replacing stockpiles", { timeout: 120_000 }, async (t) => {
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
    page.on("pageerror", (error) => errors.push(error.stack));
    assert.equal((await page.goto(new URL("/structures/maps", base).href)).status(), 200);
    await page.waitForSelector("[data-dds-pick]:not([disabled])");
    assert.ok(await page.$(`[data-dds-pick][value="${view}"]`),
      "OR-map / MV registers must join the existing maps picker");
    await page.focus("#ormap [data-structure-toggle]");
    await page.keyboard.press("Enter");
    await page.select("[data-ormap-view]", view);
    await page.$eval("[data-pace]", (input) => {
      input.value = input.max;
      input.dispatchEvent(new Event("input", { bubbles: true }));
    });
    await settled(page, baseline);
    const liveLabels = await page.$$eval(
      "[data-or-map-mv-register-confirmed], [data-or-map-mv-register-entries]",
      (els) => els.map((el) => el.getAttribute("aria-label")),
    );
    assert.equal(liveLabels.length, 6);
    assert.ok(liveLabels.every(Boolean));
    assert.equal(new Set(liveLabels).size, liveLabels.length);
    assert.equal(await page.$eval(client("a", "resolve"), (el) => el.disabled), true);
    assert.deepEqual(await page.$$eval('[data-client="a"] > :is(table, .counter-panel, .mv-register-panel)',
      (els) => els.filter((el) => getComputedStyle(el).display !== "none").map((el) => el.className)),
    ["mv-register-panel dds-or-map-mv-register"]);

    await t.test("concurrent revisions stay sorted while confirmed state waits for delivery", async () => {
      await page.focus("[data-race]");
      await page.keyboard.press("Enter");
      await page.waitForFunction(() =>
        document.querySelector('[data-client="a"] [data-or-map-mv-register-entries]').textContent
          === '[["gate-mode",["raise crest"]]]'
        && document.querySelector('[data-client="a"] [data-or-map-mv-register-confirmed]').textContent
          === '[["gate-mode",["surveyed"]]]'
        && document.querySelector('[data-client="a"] [data-pending-count]').textContent === "1 pending");
      assert.equal(await page.$eval(client("a", "entries"), (el) => el.classList.contains("k-pending")), true);
      await settled(page, [["gate-mode", ["arm pump", "raise crest"]]]);
    });

    let stockpiles;
    await t.test("picker switching preserves both modes and resolution defeats early replay", async () => {
      await page.select("[data-ormap-view]", "ormap");
      await page.click("[data-race]");
      await page.waitForFunction(() =>
        [...document.querySelectorAll('.dds-ormap tr[data-key="spoil-north"] [data-ormap-value]')].length === 3
        && [...document.querySelectorAll('.dds-ormap tr[data-key="spoil-north"] [data-ormap-value]')]
          .every((el) => el.textContent === "+24")
        && document.querySelector("[data-status] .converged"));
      stockpiles = await page.$$eval(".dds-ormap [data-ormap-value]", (els) => els.map((el) => el.textContent));
      assert.equal(stockpiles.length, 9);
      await page.select("[data-ormap-view]", view);
      await settled(page, [["gate-mode", ["arm pump", "raise crest"]]]);
      await page.click(client("a", "resolve"));
      await settled(page, [["gate-mode", ["raise crest + arm pump"]]]);
      await page.click("[data-replay]");
      await settled(page, [["gate-mode", ["raise crest + arm pump"]]]);
      assert.match(await page.$eval("[data-op-log] li", (el) => el.textContent),
        /again revise "gate-mode" = "raise crest"/);
    });

    await t.test("a concurrent write survives removal, but an observed removal hides the key", async () => {
      await reset(page);
      const pending = await page.evaluate(() => {
        document.querySelector('[data-client="a"] [data-or-map-mv-register-remove]').click();
        const b = document.querySelector('[data-client="b"]');
        b.querySelector("[data-or-map-mv-register-input]").value = "keep pumping";
        b.querySelector("[data-or-map-mv-register-write]").click();
        return document.querySelector('[data-client="a"] [data-or-map-mv-register-entries]').textContent;
      });
      assert.equal(pending, "[]");
      await settled(page, [["gate-mode", ["keep pumping"]]]);
      await page.click(client("c", "remove"));
      await settled(page, []);
      await page.click("[data-replay]");
      await settled(page, []);
      await write(page, "c", "gate-mode", "restored");
      await settled(page, [["gate-mode", ["restored"]]]);
    });

    await t.test("resolve reads the selected key and cannot retire an unseen offline revision", async () => {
      await reset(page);
      await page.click("[data-latency-variance]");
      await page.evaluate(() => {
        for (const [id, value] of [["a", "alpha"], ["b", "beta"]]) {
          const el = document.querySelector(`[data-client="${id}"]`);
          el.querySelector("[data-or-map-mv-register-key]").value = "pump-plan";
          el.querySelector("[data-or-map-mv-register-input]").value = value;
          el.querySelector("[data-or-map-mv-register-write]").click();
        }
      });
      await settled(page, [...baseline, ["pump-plan", ["alpha", "beta"]]]);
      await page.$eval(client("a", "key"), (el) => {
        el.value = "missing";
        el.dispatchEvent(new Event("input", { bubbles: true }));
      });
      assert.equal(await page.$eval(client("a", "resolve"), (el) => el.disabled), true);
      await page.$eval(client("a", "key"), (el) => {
        el.value = "pump-plan";
        el.dispatchEvent(new Event("input", { bubbles: true }));
      });
      assert.equal(await page.$eval(client("a", "resolve"), (el) => el.disabled), false);
      await page.click("[data-cut-link]");
      await write(page, "b", "pump-plan", "unseen");
      await page.click(client("a", "resolve"));
      await page.waitForFunction(() =>
        document.querySelector('[data-client="a"] [data-or-map-mv-register-confirmed]').textContent
          === '[["gate-mode",["surveyed"]],["pump-plan",["beta + alpha"]]]');
      await page.click("[data-cut-link]");
      await settled(page, [...baseline, ["pump-plan", ["beta + alpha", "unseen"]]]);
    });

    await t.test("string keys and alternatives render literally, including empty and duplicate values", async () => {
      await reset(page);
      await write(page, "a", "z-key", "");
      await write(page, "c", "<b>key</b>", "<b>literal text</b>", true);
      await page.evaluate(() => {
        for (const id of ["a", "b"]) {
          const el = document.querySelector(`[data-client="${id}"]`);
          el.querySelector("[data-or-map-mv-register-key]").value = "same";
          el.querySelector("[data-or-map-mv-register-input]").value = "duplicate";
          el.querySelector("[data-or-map-mv-register-write]").click();
        }
      });
      await settled(page, [
        ["<b>key</b>", ["<b>literal text</b>"]], ...baseline,
        ["same", ["duplicate", "duplicate"]], ["z-key", [""]],
      ]);
      assert.equal(await page.$("[data-or-map-mv-register-entries] b, [data-or-map-mv-register-confirmed] b, [data-op-log] b"), null);
    });

    await t.test("reset invalidates offline submits, catch-up hops, delayed writes and replay", async () => {
      await page.click("[data-cut-link]");
      await write(page, "b", "held", "discard");
      await write(page, "a", "catch-up", "discard");
      await page.waitForFunction(() =>
        document.querySelector('[data-client="a"] [data-or-map-mv-register-confirmed]').textContent.includes("catch-up")
        && /[1-9]\d* to catch up/.test(document.querySelector("[data-status]").textContent));
      await page.click("[data-replay]");
      await write(page, "a", "delayed", "discard");
      await page.click("[data-reset]");
      await page.click("[data-cut-link]");
      await settled(page, baseline);
      assert.equal(await page.$eval("[data-replay]", (el) => el.disabled), true);
      const resetStockpiles = await page.$$eval(".dds-ormap [data-ormap-value]", (els) =>
        els.map((el) => el.textContent));
      assert.equal(resetStockpiles.length, 9);
      assert.deepEqual(resetStockpiles, stockpiles);
      await write(page, "a", "gate-mode", "fresh epoch");
      await settled(page, [["gate-mode", ["fresh epoch"]]]);
    });

    await t.test("MV registers and string sets keep separate state across plate moves", async () => {
      await page.select("[data-ormap-view]", "ormap");
      await page.select("[data-ormap-mode]", "set");
      await page.click('[data-client="a"] [data-ormap-set-add]');
      await page.waitForFunction(() =>
        [...document.querySelectorAll('[data-ormap-set-row="inspection-brief"] [data-ormap-confirmed]')]
          .every((el) => el.textContent === '["draft"]')
        && document.querySelector("[data-status] .converged"));
      await page.select("[data-ormap-view]", view);
      await settled(page, [["gate-mode", ["fresh epoch"]]]);
      await page.click("#lww-map [data-structure-toggle]");
      await page.click("#ormap [data-structure-toggle]");
      assert.equal(await page.$eval("[data-ormap-mode]", (el) => el.value), "set");
      assert.equal(await page.$eval(
        '[data-client="a"] [data-ormap-set-row="inspection-brief"] [data-ormap-members]',
        (el) => el.textContent), '["draft"]');
      await page.select("[data-ormap-view]", view);
      await settled(page, [["gate-mode", ["fresh epoch"]]]);
    });

    await t.test("the homepage keeps its single SharedMap view and one OrMap card", async () => {
      assert.equal((await page.goto(new URL("/", base).href)).status(), 200);
      await page.waitForSelector("[data-race]:not([disabled])");
      assert.equal(await page.$eval("[data-demo-rig]", (el) => el.dataset.views), "map");
      assert.equal(await page.$(`[data-dds-pick][value="${view}"]`), null);
      assert.equal(await page.$$eval('a[href="/structures/maps"]', (links) =>
        links.filter((link) => /\bOrMap\b/.test(link.textContent)).length), 1);
    });
    assert.deepEqual(errors, []);
  } finally {
    await browser.close();
  }
});
