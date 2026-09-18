import assert from "node:assert/strict";
import { openPage, parity, readParity, withBrowserSite, writeParity } from "./site.mjs";

const { record, site, fixture } = parity(import.meta.url, "astro-rich-text-parity.json");

async function snapshot(page) {
  return page.evaluate(() => {
    const text = (node) =>
      (node.innerText ?? node.textContent).replace(/\s+/g, " ").trim();
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
      hero: text(document.querySelector(".page-hero")),
      demoHeading: text(document.querySelector(".demo-head h2")),
      demoCopy: [...document.querySelectorAll(".demo-head p")].map(text),
      clients: [...document.querySelectorAll(".client")].map((client) => ({
        label: client.getAttribute("aria-label"),
        heading: text(client.querySelector("h3")),
        editor: text(client.querySelector(".ql-editor")),
        canonical: text(client.querySelector("[data-canonical]")),
      })),
      controls: text(document.querySelector(".demo-controls")),
      scenarios: text(document.querySelector(".scenario-row")),
      viewportWidth: innerWidth,
      scrollWidth: document.documentElement.scrollWidth,
      fitsViewport: document.documentElement.scrollWidth <= innerWidth,
      styles: {
        hero: style(".page-hero", ["padding", "border-bottom-width"]),
        demo: style(".demo", ["padding", "border-bottom-width"]),
        rig: style(".rig", [
          "display",
          "grid-template-areas",
          "grid-template-columns",
          "gap",
        ]),
        client: style(".client", ["border", "background-color"]),
        editor: style(".ql-editor", ["min-height", "font-size", "line-height"]),
        controls: style(".demo-controls", ["display", "gap", "margin-top"]),
      },
    };
  });
}

const canonical = (page) =>
  page.$$eval("[data-canonical]", (nodes) =>
    nodes.map((node) => node.textContent),
  );

async function waitForConvergence(page) {
  await page.waitForFunction(
    () =>
      document.querySelector("[data-rt-status]").textContent.includes("Converged") &&
      [...document.querySelectorAll("[data-pending-count]")].every(
        (node) => node.textContent === "synced",
      ),
  );
  const values = await canonical(page);
  assert.equal(new Set(values).size, 1);
  return values[0];
}

async function startScenario(page, selector) {
  await page.click(selector);
  await page.waitForFunction(
    () =>
      !document.querySelector("[data-rt-status]").textContent.includes("Converged") ||
      [...document.querySelectorAll("[data-pending-count]")].some(
        (node) => node.textContent !== "synced",
      ),
  );
}

await withBrowserSite(site, async (browser, origin) => {
  const { page, errors } = await openPage(browser);
  await page.setViewport({ width: 1440, height: 1000 });
  assert.equal((await page.goto(`${origin}/rich-text/`)).status(), 200);
  await page.evaluate(() => document.fonts.ready);
  await page.waitForFunction(
    () =>
      document.querySelectorAll(".ql-editor").length === 3 &&
      !document.querySelector("[data-rt-race-type]").disabled,
  );
  assert.deepEqual(errors, [], "startup browser errors");
  const desktop = await snapshot(page);
  await page.setViewport({ width: 390, height: 844 });
  const mobile = await snapshot(page);
  if (record) {
    await writeParity(fixture, { desktop, mobile });
    console.log("Recorded Astro rich text parity baseline.");
    return;
  }

  assert.deepEqual(
    { desktop, mobile },
    await readParity(fixture),
  );
  assert.equal(mobile.fitsViewport, true, "mobile overflow");
  assert.equal(
    await page.$("astro-island, script[src*='_astro'], script[src*='@vite']"),
    null,
  );

  await page.setViewport({ width: 1440, height: 1000 });
  await page.$eval("[data-rt-pace]", (input) => {
    input.value = "2";
    input.dispatchEvent(new Event("input", { bubbles: true }));
  });
  const baseline = await waitForConvergence(page);
  await startScenario(page, "[data-rt-race-type]");
  const flowLabel = await page.$eval(".flow-dot-label", (node) => {
    const box = node.getBoundingClientRect();
    return {
      height: box.height,
      whiteSpace: getComputedStyle(node).whiteSpace,
    };
  });
  assert.ok(flowLabel.height <= 20);
  assert.equal(flowLabel.whiteSpace, "nowrap");
  const typed = await waitForConvergence(page);
  assert.notEqual(typed, baseline);
  assert.ok(typed.includes("⟨A⟩"));
  assert.ok(typed.includes("⟨B⟩"));

  await startScenario(page, "[data-rt-race-format]");
  const formatted = await waitForConvergence(page);
  assert.deepEqual(
    await page.$$eval(".ql-editor", (editors) =>
      editors.map(
        (editor) =>
          editor.querySelector("strong") !== null &&
          editor.querySelector('[style*="color"]') !== null,
      ),
    ),
    [true, true, true],
  );

  await startScenario(page, "[data-rt-race-delete]");
  assert.notEqual(await waitForConvergence(page), formatted);
  await startScenario(page, "[data-rt-embed]");
  await waitForConvergence(page);
  assert.equal(await page.$$(".ql-editor img").then((nodes) => nodes.length), 3);

  await page.click("[data-rt-reset]");
  assert.equal(await waitForConvergence(page), baseline);

  const noJs = await browser.newPage();
  await noJs.setJavaScriptEnabled(false);
  await noJs.goto(`${origin}/rich-text/`);
  assert.equal(
    await noJs.$eval('[data-testid="noscript"]', (node) =>
      node.checkVisibility(),
    ),
    true,
  );
  await noJs.close();

  const blocked = await browser.newPage();
  await blocked.setRequestInterception(true);
  blocked.on("request", (request) => {
    const path = new URL(request.url()).pathname;
    if (path === "/rich_text.js") request.abort();
    else if (request.url().startsWith("https://tinylytics.app/")) {
      request.respond({ status: 200, contentType: "text/javascript", body: "" });
    } else request.continue();
  });
  await blocked.goto(`${origin}/rich-text/`);
  await blocked.waitForSelector('[data-testid="rich-text-fallback"]', {
    visible: true,
    timeout: 6000,
  });
  await blocked.close();

  assert.deepEqual(errors, [], "browser errors");
  console.log(
    "PASS: rich text parity, OT scenarios, reset, no-JS, and failure fallback.",
  );
});
