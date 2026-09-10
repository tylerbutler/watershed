import test from "node:test";
import assert from "node:assert/strict";
import puppeteer from "puppeteer-core";
import { findBrowser } from "../../smoke/cdp.mjs";

const base = process.env.WATERSHED_WEBSITE_URL ?? "http://127.0.0.1:4321";
const client = (id, selector) => `[data-client="${id}"] ${selector}`;
const row = (id, key, selector = "[data-ormap-members]") =>
  client(id, `[data-ormap-set-row="${key}"] ${selector}`);

async function settle(page, key, expected) {
  await page.waitForFunction((key, expected) => {
    const views = document.querySelectorAll(
      `[data-ormap-set-row="${key}"] [data-ormap-members], [data-ormap-set-row="${key}"] [data-ormap-confirmed]`,
    );
    return views.length === 6 && [...views].every((view) => view.textContent === expected)
      && document.querySelector("[data-status] .converged");
  }, { timeout: 20_000 }, key, expected);
}

async function edit(page, id, key, member, action = "add") {
  await page.select(client(id, "[data-ormap-key]"), key);
  await page.$eval(client(id, "[data-ormap-set-input]"), (input, value) => {
    input.value = value;
  }, member);
  await page.click(client(id, action === "key" ? "[data-ormap-remove-key]" : `[data-ormap-set-${action}]`));
}

async function setup(t, width = 1500, path = "/structures/maps") {
  const executablePath = findBrowser();
  assert.ok(executablePath, "Chromium is required; set WATERSHED_CHROME");
  const browser = await puppeteer.launch({ executablePath, headless: true });
  t.after(() => browser.close());
  const page = await browser.newPage();
  // Analytics availability is independent of the compiled demo under test.
  await page.setRequestInterception(true);
  page.on("request", (request) => {
    if (new URL(request.url()).hostname === "tinylytics.app") {
      void request.respond({ status: 204, body: "" });
    } else {
      void request.continue();
    }
  });
  await page.setViewport({ width, height: 1100 });
  await page.emulateMediaFeatures([{ name: "prefers-reduced-motion", value: "reduce" }]);
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  page.on("console", (message) => {
    if (message.type() === "error") errors.push(message.text());
  });
  t.after(() => assert.deepEqual(errors, []));
  assert.equal((await page.goto(new URL(path, base).href)).status(), 200);
  await page.waitForSelector("[data-race]:not([disabled])");
  if (path === "/structures/maps") {
    await page.focus("#ormap [data-structure-toggle]");
    await page.keyboard.press("Enter");
  }
  await page.$eval("[data-pace]", (input) => {
    input.value = input.max;
    input.dispatchEvent(new Event("input", { bubbles: true }));
  });
  return page;
}

test("homepage keeps its SharedMap-only proof and real sequenced edits", { timeout: 30_000 }, async (t) => {
  const page = await setup(t, 1500, "/");
  assert.equal(await page.$("[data-ormap-mode]"), null);
  assert.equal(await page.$eval("[data-demo-rig]", (rig) => rig.dataset.dds), "map");
  assert.equal(await page.$$eval(".ormap-set-panel", (panels) => panels.some((panel) => panel.checkVisibility())), false);
  await page.focus(client("a", '.dds-map tr[data-key="mill-race"] [data-step="1"]'));
  await page.keyboard.press("Enter");
  await page.waitForFunction(() =>
    [...document.querySelectorAll('.dds-map tr[data-key="mill-race"] [data-value]')]
      .every((el) => el.textContent === "25") && document.querySelector("[data-status] .converged"));
});

test("ORMap inline tally controls retain history, race, replay and reopen", { timeout: 60_000 }, async (t) => {
  const page = await setup(t);
  assert.equal(await page.$eval("[data-ormap-mode]", (select) => select.value), "tally");
  const tally = client("a", '.dds-ormap tr[data-key="spoil-north"]');
  await page.click(`${tally} [data-ormap-strike]`);
  await page.waitForFunction(() => document.querySelector("[data-status] .converged"));
  assert.equal(await page.$eval(`${tally} [data-ormap-value]`, (el) => el.textContent), "struck");
  await page.click(`${tally} [data-ormap-reopen]`);
  await page.waitForFunction(() => document.querySelector("[data-status] .converged"));
  assert.equal(await page.$eval(`${tally} [data-ormap-value]`, (el) => el.textContent), "+18");
  await page.click("[data-race]");
  await page.waitForFunction(() => document.querySelector("[data-status] .converged"));
  const values = await page.$$eval("[data-ormap-value]", (els) => els.map((el) => el.textContent));
  const sn = await page.$eval("[data-seq-counter]", (el) => el.textContent);
  await page.click("[data-replay]");
  await page.waitForFunction(() => document.querySelector("[data-status] .converged"));
  assert.deepEqual(await page.$$eval("[data-ormap-value]", (els) => els.map((el) => el.textContent)), values);
  assert.equal(await page.$eval("[data-seq-counter]", (el) => el.textContent), sn);
  await page.click("[data-reset]");
  await page.waitForFunction(() => document.querySelector("[data-status] .converged"));
  assert.equal(await page.$eval(`${tally} [data-ormap-value]`, (el) => el.textContent), "+18");
});

test("ORMap set races use sequenced operations and preserve observed removals", { timeout: 120_000 }, async (t) => {
  const page = await setup(t);
  assert.equal(await page.$$eval("[data-ormap-mode]", (els) => els.length), 1);
  await page.select("[data-ormap-mode]", "set");
  await settle(page, "inspection-brief", "missing");
  for (const [scenario, expected, count, logPatterns] of [
    ["union", '["draft","reviewed"]', 2, [/add member "draft"/, /add member "reviewed"/]],
    ["member", '["draft"]', 3, [/remove member "draft"/, /add member "draft"/]],
    ["key", '["reviewed"]', 3, [/remove key inspection-brief/, /add member "reviewed"/]],
    ["readd", '["handoff"]', 3, [/remove key inspection-brief/, /again add member "draft"/]],
    ["empty", "empty set", 4, [/remove member "draft"/, /remove member "absent"/]],
  ]) {
    const before = await page.$eval("[data-seq-counter]", (el) => Number(el.textContent.replace(/\D/g, "")));
    await page.select("[data-ormap-set-race]", scenario);
    await page.focus("[data-race]");
    await page.keyboard.press("Enter");
    await page.waitForFunction(() => document.querySelector("[data-ormap-race-status]").textContent.includes("Complete"));
    await settle(page, "inspection-brief", expected);
    await settle(page, "pump-watch", "missing");
    assert.equal(await page.$eval("[data-seq-counter]", (el) => Number(el.textContent.replace(/\D/g, ""))), before + count);
    const log = await page.$eval("[data-op-log]", (el) => el.textContent);
    for (const pattern of logPatterns) assert.match(log, pattern);
    assert.deepEqual(await page.$$eval("[data-pending-count]", (els) => els.map((el) => el.textContent)), ["0 pending", "0 pending", "0 pending"]);
  }
});

test("ORMap set local views, literal strings, independent keys and duplicate metadata", { timeout: 90_000 }, async (t) => {
  const page = await setup(t, 390);
  await page.select("[data-ormap-mode]", "set");
  await edit(page, "a", "inspection-brief", "draft");
  assert.equal(await page.$eval(row("a", "inspection-brief"), (el) => el.textContent), '["draft"]');
  assert.equal(await page.$eval(row("a", "inspection-brief", "[data-ormap-confirmed]"), (el) => el.textContent), "missing");
  assert.equal(await page.$eval(client("a", "[data-pending-count]"), (el) => el.textContent), "1 pending");
  await edit(page, "b", "spillway-plan", "reviewed");
  await settle(page, "inspection-brief", '["draft"]');
  await settle(page, "spillway-plan", '["reviewed"]');
  const sn = await page.$eval("[data-seq-counter]", (el) => Number(el.textContent.replace(/\D/g, "")));
  await edit(page, "a", "inspection-brief", "draft");
  await settle(page, "inspection-brief", '["draft"]');
  assert.equal(await page.$eval("[data-seq-counter]", (el) => Number(el.textContent.replace(/\D/g, ""))), sn + 1);
  await page.click("[data-replay]");
  await settle(page, "inspection-brief", '["draft"]');
  assert.equal(await page.$eval("[data-seq-counter]", (el) => Number(el.textContent.replace(/\D/g, ""))), sn + 1);
  for (const member of ["", "é", "😀", "<b>literal</b>"]) {
    await page.select(client("c", "[data-ormap-key]"), "pump-watch");
    await page.$eval(client("c", "[data-ormap-set-input]"), (input, value) => { input.value = value; }, member);
    await page.focus(client("c", "[data-ormap-set-input]"));
    await page.keyboard.press("Enter");
  }
  await settle(page, "pump-watch", '["","<b>literal</b>","é","😀"]');
  assert.equal(await page.$("[data-ormap-members] b"), null);
  assert.equal(await page.$("[data-op-log] b"), null);
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
  await edit(page, "c", "pump-watch", "", "remove");
  await settle(page, "pump-watch", '["<b>literal</b>","é","😀"]');
  await page.click("#mv-register [data-structure-toggle]");
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
});

test("ORMap scenarios follow their plate across moves and cancel at reset or mode boundaries", { timeout: 90_000 }, async (t) => {
  const page = await setup(t);
  const sn = await page.$eval("[data-seq-counter]", (el) => el.textContent);
  await page.click(client("a", '.dds-ormap tr[data-key="spoil-north"] [data-ormap-log="2"]'));
  await page.select("[data-ormap-mode]", "set");
  await settle(page, "inspection-brief", "missing");
  assert.equal(await page.$eval("[data-seq-counter]", (el) => el.textContent), sn);
  await page.select("[data-ormap-set-race]", "readd");
  await page.click("[data-race]");
  await page.click("#mv-register [data-structure-toggle]");
  await page.waitForFunction(() => document.querySelector("[data-ormap-race-status]").textContent.includes("Complete"));
  await page.click("#ormap [data-structure-toggle]");
  await settle(page, "inspection-brief", '["handoff"]');
  for (const boundary of ["reset", "mode"]) {
    await page.select("[data-ormap-set-race]", "key");
    await page.click("[data-race]");
    assert.equal(await page.$eval(client("a", "[data-ormap-set-add]"), (el) => el.disabled), true);
    if (boundary === "reset") {
      await page.click("[data-reset]");
    } else {
      await page.select("[data-ormap-mode]", "tally");
      await page.select("[data-ormap-mode]", "set");
    }
    await settle(page, "inspection-brief", "missing");
    assert.equal(await page.$eval("[data-ormap-race-status]", (el) => el.textContent.includes("Complete")), false);
    assert.equal(await page.$eval(client("a", "[data-ormap-set-add]"), (el) => el.disabled), false);
  }
  await page.focus(client("c", "[data-ormap-set-add]"));
  await page.keyboard.press("Space");
  await settle(page, "inspection-brief", '["handoff"]');
});

test("ORMap mode epochs discard held, delayed and replayed packets without resetting other plates", { timeout: 120_000 }, async (t) => {
  const page = await setup(t);
  await page.click("#mv-register [data-structure-toggle]");
  await page.$eval(client("a", "[data-mv-register-input]"), (input) => { input.value = "keep this revision"; });
  await page.click(client("a", "[data-mv-register-write]"));
  await page.waitForFunction(() => document.querySelector("[data-status] .converged"));
  await page.click("#ormap [data-structure-toggle]");
  await page.select("[data-ormap-mode]", "set");
  await page.click("[data-latency-variance]");
  await page.click("[data-field-notes]");
  await page.click("[data-cut-link]");
  await edit(page, "b", "inspection-brief", "draft");
  await edit(page, "a", "inspection-brief", "reviewed");
  await page.waitForFunction(() =>
    document.querySelector('[data-client="a"] [data-ormap-set-row="inspection-brief"] [data-ormap-confirmed]').textContent === '["reviewed"]');
  assert.match(await page.$eval("[data-status]", (el) => el.textContent), /1 to resubmit/);
  await page.click("[data-cut-link]");
  await settle(page, "inspection-brief", '["draft","reviewed"]');
  await page.click("#map [data-structure-toggle]");
  await page.click(client("a", '.dds-map tr[data-key="mill-race"] [data-step="1"]'));
  await page.waitForFunction(() => document.querySelector("[data-status] .converged"));
  await page.click("#ormap [data-structure-toggle]");
  await settle(page, "inspection-brief", '["draft","reviewed"]');
  await page.click("#ormap [data-structure-toggle]");
  await page.click("#ormap [data-structure-toggle]");
  await settle(page, "inspection-brief", '["draft","reviewed"]');

  for (const reset of ["mode", "reset"]) {
    await page.click("[data-cut-link]");
    await edit(page, "b", "pump-watch", "held old mode");
    await edit(page, "a", "pump-watch", "catch-up old mode");
    await page.waitForFunction(() =>
      document.querySelector('[data-client="a"] [data-ormap-set-row="pump-watch"] [data-ormap-confirmed]').textContent === '["catch-up old mode"]');
    await page.click("[data-replay]");
    await edit(page, "a", "spillway-plan", "delayed old mode");
    if (reset === "mode") {
      await page.select("[data-ormap-mode]", "tally");
      await page.select("[data-ormap-mode]", "set");
    } else {
      await page.click("[data-reset]");
    }
    await page.click("[data-cut-link]");
    await settle(page, "pump-watch", "missing");
    await settle(page, "spillway-plan", "missing");
    await edit(page, "c", "inspection-brief", "handoff");
    await settle(page, "inspection-brief", '["handoff"]');
  }
  await page.click("#map [data-structure-toggle]");
  assert.equal(await page.$eval(client("a", '.dds-map tr[data-key="mill-race"] [data-value]'), (el) => el.textContent), "25");
  await page.click("#mv-register [data-structure-toggle]");
  assert.equal(await page.$eval(client("a", "[data-mv-register-values]"), (el) => el.textContent), '["keep this revision"]');
  await page.click("#ormap [data-structure-toggle]");
  assert.equal(await page.$eval("[data-ormap-mode]", (select) => select.value), "set");
  await settle(page, "inspection-brief", '["handoff"]');
});
