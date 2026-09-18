import assert from "node:assert/strict";
import { readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { withBrowserSite } from "./site.mjs";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const record = process.argv.includes("--record-baseline");
const site = resolve(root, record ? "../website/dist" : "dist");
const fixture = resolve(root, "test/fixtures/astro-json-ot-parity.json");
const selector = (id) => `[data-testid="${id}"]`;

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
        document: text(client.querySelector(".doc")),
      })),
      controls: text(document.querySelector(".demo-controls")),
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
        doc: style(".doc", ["font-family", "font-size", "line-height", "padding"]),
        controls: style(".demo-controls", ["display", "gap", "margin-top"]),
      },
    };
  });
}

await withBrowserSite(site, async (browser, origin) => {
  const errors = [];
  const page = await browser.newPage();
  page.on("pageerror", (error) => errors.push(error.message));
  page.on("console", (message) => {
    if (message.type() === "error") errors.push(message.text());
  });
  await page.setRequestInterception(true);
  page.on("request", (request) => {
    if (request.url().startsWith("https://tinylytics.app/")) {
      request.respond({ status: 200, contentType: "text/javascript", body: "" });
    } else request.continue();
  });
  await page.setViewport({ width: 1440, height: 1000 });
  assert.equal((await page.goto(`${origin}/json-ot/`)).status(), 200);
  await page.evaluate(() => document.fonts.ready);
  await page.waitForFunction(
    () =>
      document.querySelectorAll(".crew .chip").length === 6 &&
      !document.querySelector("[data-jot-race]").disabled,
  );
  const desktop = await snapshot(page);
  await page.setViewport({ width: 390, height: 844 });
  const mobile = await snapshot(page);
  if (record) {
    assert.deepEqual(errors, [], "baseline browser errors");
    await writeFile(
      fixture,
      JSON.stringify({ desktop, mobile }, null, 2) + "\n",
    );
    console.log("Recorded Astro JSON OT parity baseline.");
    return;
  }

  assert.deepEqual(
    { desktop, mobile },
    JSON.parse(await readFile(fixture, "utf8")),
  );
  assert.equal(mobile.fitsViewport, true, "mobile overflow");
  assert.equal(
    await page.$("astro-island, script[src*='_astro'], script[src*='@vite']"),
    null,
  );
  assert.deepEqual(
    await page.$$eval('script[type="module"]', (nodes) =>
      nodes.map((node) => new URL(node.src).pathname),
    ),
    ["/json_ot.js"],
  );

  await page.setViewport({ width: 1440, height: 1000 });
  await page.$eval("[data-jot-pace]", (input) => {
    input.value = "2";
    input.dispatchEvent(new Event("input", { bubbles: true }));
  });
  await page.click('[data-client="a"] [data-stage-inc]');
  await page.waitForFunction(
    () =>
      document.querySelector('[data-client="a"] [data-field="gauge.stage"] [data-value]')
        .textContent === "25",
  );
  assert.equal(
    await page.$eval(
      '[data-client="a"] [data-field="gauge.stage"] [data-value]',
      (node) => node.classList.contains("pending"),
    ),
    true,
  );
  await page.waitForFunction(
    () => document.querySelector("[data-jot-status]").textContent.includes("Converged"),
  );
  assert.deepEqual(
    await page.$$eval('[data-field="gauge.stage"] [data-value]', (nodes) =>
      nodes.map((node) => node.textContent),
    ),
    ["25", "25", "25"],
  );

  await page.click('[data-client="b"] [data-site-cycle]');
  await page.waitForFunction(
    () =>
      document.querySelector('[data-client="b"] [data-field="site"] [data-value]')
        .textContent !== "Mill Race",
  );
  await page.waitForFunction(
    () => document.querySelector("[data-jot-status]").textContent.includes("Converged"),
  );
  assert.equal(
    new Set(
      await page.$$eval('[data-field="site"] [data-value]', (nodes) =>
        nodes.map((node) => node.textContent),
      ),
    ).size,
    1,
  );

  await page.click('[data-client="c"] [data-trend-cycle]');
  await page.waitForFunction(
    () =>
      document.querySelector('[data-client="c"] [data-field="gauge.trend"] [data-value]')
        .textContent === "rising",
  );
  await page.waitForFunction(
    () => document.querySelector("[data-jot-status]").textContent.includes("Converged"),
  );
  assert.deepEqual(
    await page.$$eval('[data-field="gauge.trend"] [data-value]', (nodes) =>
      nodes.map((node) => node.textContent),
    ),
    ["rising", "rising", "rising"],
  );

  await page.click('[data-client="c"] [data-crew-add]');
  await page.waitForFunction(
    () =>
      document.querySelector('[data-client="c"] .chip-name')?.textContent ===
      "Eli",
  );
  await page.waitForFunction(
    () => document.querySelector("[data-jot-status]").textContent.includes("Converged"),
  );
  await page.click(
    '[data-client="c"] .chip:nth-child(2) button[aria-label^="Move"]',
  );
  await page.waitForFunction(
    () =>
      [...document.querySelectorAll(".crew")].every(
        (crew) => crew.querySelector(".chip-name")?.textContent === "Ada",
      ) &&
      [...document.querySelectorAll("[data-pending-count]")].every(
        (node) => node.textContent === "0 pending",
      ),
  );
  await page.$eval('[data-client="c"] .crew', (crew) => {
    const chip = [...crew.querySelectorAll(".chip")].find(
      (node) => node.querySelector(".chip-name")?.textContent === "Eli",
    );
    chip.querySelector('button[aria-label^="Remove"]').click();
  });
  await page.waitForFunction(
    () =>
      [...document.querySelectorAll(".crew")].every(
        (crew) => crew.querySelectorAll(".chip").length === 2,
      ),
  );
  await page.waitForFunction(
    () => document.querySelector("[data-jot-status]").textContent.includes("Converged"),
  );

  await page.click("[data-jot-latency-variance]");
  await page.click("[data-jot-race]");
  await page.waitForFunction(
    () =>
      [...document.querySelectorAll("[data-pending-count]")].some(
        (node) => node.textContent !== "0 pending",
      ),
  );
  await page.waitForFunction(
    () => document.querySelector("[data-jot-status]").textContent.includes("Converged"),
  );
  assert.deepEqual(
    await page.$$eval(".crew", (crews) =>
      crews.map((crew) =>
        [...crew.querySelectorAll(".chip-name")].map((node) => node.textContent),
      ),
    ),
    Array(3).fill(["Cy", "Dot", "Ada", "Ben"]),
  );

  await page.click("[data-jot-reset]");
  await page.waitForFunction(
    () =>
      [...document.querySelectorAll(".crew")].every(
        (crew) => crew.querySelectorAll(".chip").length === 2,
      ),
  );
  await page.click('[data-client="a"] [data-crew-add]');
  await page.waitForFunction(
    () => document.querySelector("[data-jot-status]").textContent.includes("Converged"),
  );
  await page.click("[data-jot-race]");
  await page.waitForFunction(
    () =>
      [...document.querySelectorAll(".crew")].every(
        (crew) => crew.querySelectorAll(".chip").length === 5,
      ) &&
      [...document.querySelectorAll("[data-pending-count]")].every(
        (node) => node.textContent === "0 pending",
      ),
  );
  const alignedRace = await page.$$eval(".crew", (crews) =>
    crews.map((crew) =>
      [...crew.querySelectorAll(".chip-name")].map((node) => node.textContent),
    ),
  );
  assert.deepEqual(alignedRace[0], alignedRace[1]);
  assert.deepEqual(alignedRace[1], alignedRace[2]);
  assert.equal(
    new Set(alignedRace[0].slice(0, 2)).size,
    2,
    "race payloads stay distinct after prior additions",
  );

  const noJs = await browser.newPage();
  await noJs.setJavaScriptEnabled(false);
  await noJs.goto(`${origin}/json-ot/`);
  assert.equal(
    await noJs.$eval(selector("noscript"), (node) => node.checkVisibility()),
    true,
  );
  assert.equal(
    await noJs.$eval(selector("json-ot-fallback"), (node) =>
      node.checkVisibility(),
    ),
    false,
  );
  await noJs.close();

  const blocked = await browser.newPage();
  await blocked.setRequestInterception(true);
  blocked.on("request", (request) => {
    const path = new URL(request.url()).pathname;
    if (path === "/json_ot.js") request.abort();
    else if (request.url().startsWith("https://tinylytics.app/")) {
      request.respond({ status: 200, contentType: "text/javascript", body: "" });
    } else request.continue();
  });
  await blocked.goto(`${origin}/json-ot/`);
  await blocked.waitForSelector(selector("json-ot-fallback"), {
    visible: true,
    timeout: 6000,
  });
  await blocked.close();

  const touch = await browser.newPage();
  await touch.emulate({
    viewport: { width: 390, height: 844, isMobile: true, hasTouch: true },
    userAgent: await browser.userAgent(),
  });
  await touch.goto(`${origin}/json-ot/`);
  await touch.waitForFunction(
    () => document.querySelectorAll(".crew .chip").length === 6,
  );
  const touchTarget = await touch.$eval(".crew .chip-actions button", (node) => {
    const box = node.getBoundingClientRect();
    return { width: box.width, height: box.height, opacity: getComputedStyle(node.parentElement).opacity };
  });
  assert.ok(touchTarget.width >= 30);
  assert.ok(touchTarget.height >= 30);
  assert.equal(touchTarget.opacity, "1");
  await touch.close();

  assert.deepEqual(errors, [], "browser errors");
  console.log(
    "PASS: JSON OT Astro parity, transformed inserts, no-JS, and failures.",
  );
});
