import assert from "node:assert/strict";
import { openPage, parity, readParity, withBrowserSite, writeParity } from "./site.mjs";

const { record, site, fixture } = parity(import.meta.url, "astro-sudoku-parity.json");
const selector = (id) => `[data-testid="${id}"]`;
const pause = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function snapshot(page) {
  return page.evaluate(() => {
    const text = (node) =>
      (node.innerText ?? node.textContent).replace(/\s+/g, " ").trim();
    const links = (query) =>
      [...document.querySelectorAll(`${query} a`)].map((node) => [
        text(node),
        node.getAttribute("href"),
      ]);
    const style = (query, properties) => {
      const computed = getComputedStyle(document.querySelector(query));
      return Object.fromEntries(
        properties.map((key) => [key, computed.getPropertyValue(key)]),
      );
    };
    return {
      title: document.title,
      metadata: [
        ...document.head.querySelectorAll("meta[name], meta[property]"),
      ].map((node) => [
        node.getAttribute("name") || node.getAttribute("property"),
        node.content,
      ]),
      heading: text(document.querySelector("h1")),
      headingBreaks: document.querySelectorAll("h1 br").length,
      hero: [...document.querySelectorAll(".page-hero p")].map(text),
      heroLinks: links(".page-hero"),
      demoHeading: text(document.querySelector(".demo-head h2")),
      demoCopy: [...document.querySelectorAll(".demo-head p")].map(text),
      clients: [...document.querySelectorAll(".client")].map((client) => ({
        label: client.getAttribute("aria-label"),
        heading: text(client.querySelector("h3")),
        note: text(client.querySelector(".board-note")),
        cells: client.querySelectorAll(".sudoku-cell").length,
      })),
      controls: text(document.querySelector(".demo-controls")),
      primary: links('nav[aria-label="Sheet index"]'),
      adjoining: links('nav[aria-labelledby="adjoining-title"]'),
      viewportWidth: innerWidth,
      scrollWidth: document.documentElement.scrollWidth,
      fitsViewport: document.documentElement.scrollWidth <= innerWidth,
      styles: {
        hero: style(".page-hero", ["padding", "border-bottom"]),
        heading: style("h1", [
          "font-size",
          "font-weight",
          "font-stretch",
          "line-height",
          "max-width",
        ]),
        demo: style(".demo", ["padding", "border-bottom"]),
        rig: style(".rig", [
          "display",
          "grid-template-areas",
          "grid-template-columns",
          "gap",
        ]),
        client: style(".client", ["border", "background-color"]),
        board: style(".board", ["display", "width", "border", "font-family"]),
        cell: style(".sudoku-cell", [
          "font-size",
          "font-weight",
          "border-right-width",
          "border-bottom-width",
        ]),
        controls: style(".demo-controls", ["display", "gap", "margin-top"]),
        race: style('[data-testid="race"]', [
          "padding",
          "border",
          "font-weight",
        ]),
      },
    };
  });
}

await withBrowserSite(site, async (browser, origin) => {
  const { page, errors } = await openPage(browser);
  await page.setViewport({ width: 1440, height: 1000 });
  assert.equal((await page.goto(`${origin}/sudoku/`)).status(), 200);
  await page.evaluate(() => document.fonts.ready);
  await page.waitForFunction(
    () => document.querySelectorAll(".sudoku-cell").length === 243,
  );
  const desktop = await snapshot(page);
  await page.setViewport({ width: 390, height: 844 });
  const mobile = await snapshot(page);
  if (record) {
    assert.deepEqual(errors, [], "baseline browser errors");
    await writeParity(fixture, { desktop, mobile });
    console.log("Recorded Astro Sudoku parity baseline.");
    return;
  }

  const baseline = await readParity(fixture);
  assert.deepEqual({ desktop, mobile }, baseline);
  assert.equal(mobile.fitsViewport, true, "mobile overflow");
  assert.equal(
    await page.$("astro-island, script[src*='_astro'], script[src*='@vite']"),
    null,
  );
  assert.deepEqual(
    await page.$$eval('script[type="module"]', (nodes) =>
      nodes.map((node) => new URL(node.src).pathname),
    ),
    ["/sudoku.js", "/scripts/concept-index.js"],
  );

  await page.setViewport({ width: 1440, height: 1000 });
  await page.$eval(selector("pace"), (input) => {
    input.value = "2";
    input.dispatchEvent(new Event("input", { bubbles: true }));
  });
  const value = (id) =>
    page.$eval(selector(id), (cell) => cell.textContent.trim());
  await page.click(selector("cell-a-0-0"));
  await page.waitForFunction(
    () => document.querySelector('[data-testid="pending-a"]').textContent === "1 pending",
  );
  assert.equal(await value("cell-a-0-0"), "1");
  assert.equal(await value("cell-b-0-0"), "·");
  await page.waitForFunction(
    () => document.querySelector('[data-testid="status"]').textContent.includes("Converged"),
  );
  assert.deepEqual(
    await Promise.all(
      ["a", "b", "c"].map((id) => value(`cell-${id}-0-0`)),
    ),
    ["1", "1", "1"],
  );
  await page.focus(selector("pace"));
  await page.$eval(selector("pace"), (input) => {
    input.value = "1";
    input.dispatchEvent(new Event("input", { bubbles: true }));
  });
  await pause(10);
  assert.equal(
    await page.evaluate(() => document.activeElement.dataset.testid),
    "pace",
  );

  await page.focus(selector("cell-a-0-0"));
  await page.keyboard.press("ArrowRight");
  await page.waitForFunction(
    () => document.activeElement.dataset.testid === "cell-a-0-1",
  );
  assert.equal(
    await page.evaluate(() => document.activeElement.dataset.testid),
    "cell-a-0-1",
  );
  await page.keyboard.press("7");
  await page.waitForFunction(
    () => document.querySelector('[data-testid="pending-a"]').textContent === "1 pending",
  );
  await page.waitForFunction(
    () => document.querySelector('[data-testid="status"]').textContent.includes("Converged"),
  );
  assert.deepEqual(
    await Promise.all(
      ["a", "b", "c"].map((id) => value(`cell-${id}-0-1`)),
    ),
    ["7", "7", "7"],
  );
  await page.keyboard.down("Shift");
  await page.click(selector("cell-a-0-1"));
  await page.keyboard.up("Shift");
  await page.waitForFunction(
    () => document.querySelector('[data-testid="pending-a"]').textContent === "1 pending",
  );
  await page.waitForFunction(
    () => document.querySelector('[data-testid="status"]').textContent.includes("Converged"),
  );
  assert.deepEqual(
    await Promise.all(
      ["a", "b", "c"].map((id) => value(`cell-${id}-0-1`)),
    ),
    ["·", "·", "·"],
  );

  await page.click(selector("reset"));
  await page.waitForFunction(
    () =>
      document.querySelectorAll(".sudoku-cell").length === 243 &&
      !document.querySelector('[data-testid="race"]').disabled,
  );
  await page.click(selector("race"));
  await page.waitForFunction(
    () =>
      ["1", "5", "9"].every(
        (digit, index) =>
          document.querySelector(
            `[data-testid="cell-${["a", "b", "c"][index]}-4-4"]`,
          ).textContent.trim() === digit,
      ),
  );
  await page.waitForFunction(
    () => document.querySelector('[data-testid="status"]').textContent.includes("Converged"),
  );
  assert.deepEqual(
    await Promise.all(
      ["a", "b", "c"].map((id) => value(`cell-${id}-4-4`)),
    ),
    ["9", "9", "9"],
  );
  assert.equal(
    await page.$eval(selector("operation-log"), (node) => node.children.length),
    3,
  );

  await page.click(selector("reset"));
  await page.waitForFunction(
    () =>
      document.querySelectorAll(".sudoku-cell").length === 243 &&
      !document.querySelector('[data-testid="seed"]').disabled,
  );
  await page.click(selector("seed"));
  await page.waitForFunction(
    () =>
      [...document.querySelectorAll('[data-testid^="pending-"]')].some(
        (node) => node.textContent !== "0 pending",
      ),
  );
  await page.waitForFunction(
    () => document.querySelector('[data-testid="status"]').textContent.includes("Converged"),
  );
  assert.deepEqual(
    await Promise.all(
      ["a", "b", "c"].map((id) => value(`cell-${id}-0-0`)),
    ),
    ["5", "5", "5"],
  );
  assert.deepEqual(
    await Promise.all(
      ["a", "b", "c"].map((id) => value(`cell-${id}-8-8`)),
    ),
    ["2", "2", "2"],
  );

  await page.click(selector("reset"));
  await page.waitForFunction(
    () =>
      document.querySelectorAll(".sudoku-cell").length === 243 &&
      !document.querySelector('[data-testid="race"]').disabled,
  );
  await page.emulateMediaFeatures([
    { name: "prefers-reduced-motion", value: "reduce" },
  ]);
  await page.click(selector("race"));
  await page.waitForFunction(
    () => document.querySelectorAll('[data-testid="flow-layer"] [data-flow-id]').length > 0,
  );
  assert.ok(
    await page.$$eval(
      `${selector("flow-layer")} [data-flow-id]`,
      (nodes) =>
        nodes.every((node) =>
          node
            .getAnimations()
            .every(
              (animation) => animation.effect.getTiming().duration === 0,
            ),
        ),
    ),
  );
  assert.equal(await page.$eval(selector("error"), (node) => node.textContent), "");

  const noJs = await browser.newPage();
  await noJs.setJavaScriptEnabled(false);
  await noJs.goto(`${origin}/sudoku/`);
  assert.equal(await noJs.$$eval(".sudoku-cell", (nodes) => nodes.length), 0);
  assert.equal(
    await noJs.$eval(selector("noscript"), (node) => node.checkVisibility()),
    true,
  );
  assert.equal(
    await noJs.$eval(selector("sudoku-fallback"), (node) => node.checkVisibility()),
    false,
  );
  await noJs.close();

  const blocked = await browser.newPage();
  await blocked.setRequestInterception(true);
  blocked.on("request", (request) => {
    const path = new URL(request.url()).pathname;
    if (path === "/sudoku.js") request.abort();
    else if (request.url().startsWith("https://tinylytics.app/")) {
      request.respond({ status: 200, contentType: "text/javascript", body: "" });
    } else request.continue();
  });
  await blocked.goto(`${origin}/sudoku/`);
  await blocked.waitForSelector(selector("sudoku-fallback"), {
    visible: true,
    timeout: 6000,
  });
  assert.equal(await blocked.$$eval(".sudoku-cell", (nodes) => nodes.length), 0);
  assert.equal(await blocked.$eval(selector("race"), (node) => node.disabled), true);
  await blocked.close();

  await pause(10);
  assert.deepEqual(errors, [], "browser errors");
  console.log(
    "PASS: Sudoku Astro parity, cell edits, race, reset, no-JS, and failures.",
  );
});
