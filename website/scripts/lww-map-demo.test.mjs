import test from "node:test";
import assert from "node:assert/strict";
import puppeteer from "puppeteer-core";
import { findBrowser } from "../../smoke/cdp.mjs";

const base = process.env.WATERSHED_WEBSITE_URL ?? "http://127.0.0.1:4321";
const client = (id, selector) => `[data-client="${id}"] ${selector}`;
const baseline = [["gate-mode", "surveyed"]];

async function settled(page, entries) {
  await page.waitForFunction((expected) => {
    const views = [...document.querySelectorAll(
      "[data-lww-map-entries], [data-lww-map-confirmed]",
    )];
    return views.length === 6
      && views.every((view) => view.textContent === JSON.stringify(expected))
      && document.querySelector("[data-status] .converged");
  }, { timeout: 15_000 }, entries);
}

async function idle(page) {
  await page.waitForSelector("[data-status] .converged", { timeout: 15_000 });
}

async function write(page, id, key, value, keyboard = false) {
  await page.$eval(client(id, "[data-lww-map-key]"), (el, text) => { el.value = text; }, key);
  await page.$eval(client(id, "[data-lww-map-input]"), (el, text) => { el.value = text; }, value);
  if (keyboard) {
    await page.focus(client(id, "[data-lww-map-input]"));
    await page.keyboard.press("Enter");
  } else {
    await page.click(client(id, "[data-lww-map-write]"));
  }
}

async function metadata(page, id = "a") {
  return page.$eval(client(id, "[data-lww-map-metadata]"), (el) => JSON.parse(el.textContent));
}

async function logRows(page) {
  return page.$$eval("[data-op-log] li", (rows) => rows.map((row) => row.textContent));
}

async function race(page, choice, expected) {
  await page.select("select[data-lww-map-race]", choice);
  const before = await logRows(page);
  await page.focus("[data-race]");
  await page.keyboard.press("Enter");
  await page.waitForFunction(() =>
    document.querySelector('[data-client="a"] [data-pending-count]').textContent !== "0 pending",
  );
  assert.equal(
    await page.$eval(client("a", "[data-lww-map-confirmed]"), (el) => el.textContent),
    JSON.stringify(baseline),
  );
  await settled(page, expected);
  const rows = (await logRows(page)).filter((row) => !before.includes(row));
  const a = rows.find((row) => row.endsWith("from A"));
  const b = rows.find((row) => row.endsWith("from B"));
  assert.ok(a && b, JSON.stringify(rows));
  const sn = (row) => Number(row.match(/^#(\d+)/)[1]);
  const time = (row) => Number(row.match(/\(t (\d+)\)/)[1]);
  assert.ok(sn(a) < sn(b), `A must sequence before B: ${a}; ${b}`);
  assert.equal(time(a), time(b) + (choice === "timestamp" ? 1 : 0));
  assert.ok(time(b) > 100);
  assert.match(a, choice === "remove-tie" ? /remove "gate-mode"/ : /"open"/);
  assert.match(b, choice === "remove-tie" ? /"open"/ : /"closed"/);
  return time(a);
}

test("LWWMap races, tombstones, string edits and shared-rig lifecycle", { timeout: 120_000 }, async () => {
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
    await page.waitForSelector('[data-dds-pick]:not([disabled])');
    assert.ok(await page.$('[data-dds-pick][value="lww-map"]'), "LWWMap must join the maps picker");
    await page.focus('#lww-map [data-structure-toggle]');
    await page.keyboard.press("Enter");
    await page.$eval("[data-pace]", (input) => {
      input.value = input.max;
      input.dispatchEvent(new Event("input", { bubbles: true }));
    });
    assert.equal(await page.$eval("[data-latency-variance]", (el) => el.checked), false);
    await settled(page, baseline);
    for (const choice of ["timestamp", "writer-tie", "remove-tie"]) {
      await page.click("[data-reset]");
      await settled(page, baseline);
      const expected = choice === "remove-tie"
        ? []
        : [["gate-mode", choice === "writer-tie" ? "closed" : "open"]];
      const removedAt = await race(page, choice, expected);
      if (choice === "remove-tie") {
        const removed = (await metadata(page))[0];
        assert.deepEqual(
          { key: removed.key, value: removed.value, timestamp: removed.timestamp },
          { key: "gate-mode", value: null, timestamp: removedAt },
        );
        assert.match(removed.provenance.writer, /^client-a-lww-map-/);
        await page.click("[data-replay]");
        await settled(page, []);
        assert.deepEqual((await metadata(page))[0], removed);
        assert.match((await logRows(page))[0], /again set "gate-mode" = "open"/);
        await write(page, "c", "gate-mode", "restored", true);
        await settled(page, [["gate-mode", "restored"]]);
        assert.ok((await metadata(page))[0].timestamp > removedAt);
      }
    }

    await write(page, "a", "z-key", "");
    await write(page, "b", "a-key", "<b>text</b>", true);
    const strings = [["a-key", "<b>text</b>"], ["gate-mode", "restored"], ["z-key", ""]];
    await settled(page, strings);
    assert.equal(await page.$("[data-lww-map-entries] b"), null);
    await write(page, "c", "", "");
    await settled(page, [["", ""], ...strings]);
    await page.click(client("c", "[data-lww-map-remove]"));
    await settled(page, strings);

    // Other views remain usable and retain their own state across LWWMap reset.
    for (const view of ["map", "ormap"]) {
      await page.click(`#${view} [data-structure-toggle]`);
      const before = await logRows(page);
      await page.click("[data-race]");
      await page.waitForFunction((oldRows) =>
        [...document.querySelectorAll("[data-op-log] li")]
          .filter((row) => !oldRows.includes(row.textContent)).length >= 2,
      {}, before);
      await idle(page);
    }
    assert.deepEqual(
      await page.$$eval('.dds-ormap tr[data-key="spoil-north"] [data-ormap-value]', (els) => els.map((el) => el.textContent)),
      ["+24", "+24", "+24"],
    );
    const otherViews = await page.$$eval(".dds-map [data-value], .dds-ormap [data-ormap-value]", (els) => els.map((el) => el.textContent));
    await page.click('#lww-map [data-structure-toggle]');
    await settled(page, strings);
    await page.click("[data-latency-variance]");
    await page.click("[data-cut-link]");
    await write(page, "b", "offline", "held");
    await write(page, "a", "online", "delivered");
    await page.waitForFunction(() => document.querySelector('[data-client="a"] [data-lww-map-confirmed]').textContent.includes("delivered"));
    await page.click("[data-cut-link]");
    await settled(page, [...strings.slice(0, 2), ["offline", "held"], ["online", "delivered"], strings[2]]);
    for (const id of ["a", "b", "c"]) {
      assert.equal(await page.$eval(client(id, "[data-pending-count]"), (el) => el.textContent), "0 pending");
    }

    await page.click("[data-cut-link]");
    await write(page, "b", "held", "discard");
    await write(page, "a", "catch-up", "discard");
    await page.waitForFunction(() => document.querySelector('[data-client="a"] [data-lww-map-confirmed]').textContent.includes("catch-up"));
    await page.click("[data-replay]");
    await write(page, "a", "delayed", "discard");
    await page.click("[data-reset]");
    await page.click("[data-cut-link]");
    await settled(page, baseline);
    const resetEntry = (await metadata(page))[0];
    assert.deepEqual(
      { key: resetEntry.key, value: resetEntry.value, timestamp: resetEntry.timestamp },
      { key: "gate-mode", value: "surveyed", timestamp: 100 },
    );
    assert.equal(resetEntry.provenance.writer, "survey-lww-map");
    assert.equal(await page.$eval("[data-replay]", (el) => el.disabled), true);
    assert.deepEqual(
      await page.$$eval(".dds-map [data-value], .dds-ormap [data-ormap-value]", (els) => els.map((el) => el.textContent)),
      otherViews,
    );

    // A future timestamp on C must bound both race writers, even before ack.
    // Advancing only another key must not advance gate-mode's logical clock.
    await page.click("[data-latency-variance]");
    for (const edit of ["write", "remove"]) {
      await page.click("[data-reset]");
      await settled(page, baseline);
      await page.select("[data-lww-map-race]", "writer-tie");
      await page.evaluate((action) => {
        const now = Date.now;
        try {
          const c = document.querySelector('[data-client="c"]');
          c.querySelector("[data-lww-map-key]").value = "gate-mode";
          c.querySelector("[data-lww-map-input]").value = "future";
          Date.now = () => 5_000_000_000_000;
          c.querySelector(`[data-lww-map-${action}]`).click();
          c.querySelector("[data-lww-map-key]").value = "independent";
          Date.now = () => 200;
          c.querySelector("[data-lww-map-write]").click();
          document.querySelector("[data-race]").click();
        } finally {
          Date.now = now;
        }
      }, edit);
      await settled(page, [["gate-mode", "closed"], ["independent", "future"]]);
      const entries = await metadata(page);
      assert.equal(entries.find((entry) => entry.key === "gate-mode").timestamp, 5_000_000_000_001);
      assert.equal(entries.find((entry) => entry.key === "independent").timestamp, 200);
      const rows = await logRows(page);
      for (const id of ["A", "B"]) {
        assert.match(rows.find((row) => row.endsWith(`from ${id}`)), /\(t 5000000000001\)/);
      }
    }
    assert.equal((await page.goto(new URL("/", base).href)).status(), 200);
    await page.waitForSelector("[data-race]:not([disabled])");
    assert.ok(await page.$$eval('a[href="/structures/maps"]', (links) =>
      links.some((link) => link.textContent.includes("LWWMap"))));
    assert.equal(await page.$eval("[data-demo-rig]", (el) => el.dataset.views), "map");
    assert.equal(await page.$('[data-dds-pick][value="lww-map"]'), null);
    assert.deepEqual(errors, []);
  } finally {
    await browser.close();
  }
});
