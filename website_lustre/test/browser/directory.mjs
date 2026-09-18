import assert from "node:assert/strict";
import { openPage, parity, readParity, withBrowserSite, writeParity } from "./site.mjs";

const { record, site, fixture } = parity(import.meta.url, "astro-directory-parity.json");
const selector = (id) => `[data-testid="${id}"]`;

async function annotateAstro(page) {
  await page.evaluate(() => {
    const nodes = {
      "directory-demo": "#dir-demo",
      "directory-rig": "[data-dir-rig]",
      "client-a": '[data-client="a"]',
      "client-b": '[data-client="b"]',
      "client-c": '[data-client="c"]',
      pace: "[data-dir-pace]",
      jitter: "[data-dir-latency-variance]",
      race: "[data-dir-race]",
      seed: "[data-dir-seed]",
      reset: "[data-dir-reset]",
      status: "[data-dir-status]",
      "operation-log": "[data-op-log]",
      "flow-layer": "[data-flow-layer]",
      sequence: "[data-seq-counter]",
      "directory-fallback": "[data-dir-fallback]",
    };
    for (const [id, query] of Object.entries(nodes)) {
      document.querySelector(query).dataset.testid = id;
    }
  });
}

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
      hero: [...document.querySelectorAll(".page-hero p")].map(text),
      heroLinks: links(".page-hero"),
      demoHeading: text(document.querySelector(".demo-head h2")),
      demoCopy: [...document.querySelectorAll(".demo-head p")].map(text),
      clients: [...document.querySelectorAll(".client")].map((client) => ({
        label: client.getAttribute("aria-label"),
        heading: text(client.querySelector("h3")),
        pending: text(client.querySelector(".pending-count")),
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
        client: style(".client", [
          "border",
          "background-color",
          "min-height",
        ]),
        tree: style(".tree", ["font-family", "font-size", "padding"]),
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
  assert.equal((await page.goto(`${origin}/directory/`)).status(), 200);
  await page.evaluate(() => document.fonts.ready);
  await page.waitForFunction(
    () =>
      document.querySelectorAll(".dir-node").length === 3 &&
      !document.querySelector('[data-testid="race"]')?.disabled,
  );
  if (record) await annotateAstro(page);
  const desktop = await snapshot(page);
  await page.setViewport({ width: 390, height: 844 });
  const mobile = await snapshot(page);
  if (record) {
    assert.deepEqual(errors, [], "baseline browser errors");
    await writeParity(fixture, { desktop, mobile });
    console.log("Recorded Astro Directory parity baseline.");
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
  assert.deepEqual(
    await page.$$eval('script[type="module"]', (nodes) =>
      nodes.map((node) => new URL(node.src).pathname),
    ),
    ["/directory.js", "/scripts/concept-index.js"],
  );

  await page.setViewport({ width: 1440, height: 1000 });
  await page.$eval(selector("pace"), (input) => {
    input.value = "2";
    input.dispatchEvent(new Event("input", { bubbles: true }));
  });
  await page.click(selector("add-folder-a-root"));
  await page.waitForFunction(
    () => document.querySelector('[data-testid="pending-a"]').textContent === "1 pending",
  );
  assert.equal(
    await page.$eval(selector("tree-a"), (tree) => tree.textContent.includes("surveys/")),
    true,
  );
  assert.equal(
    await page.$eval(selector("tree-b"), (tree) => tree.textContent.includes("surveys/")),
    false,
  );
  await page.waitForFunction(
    () => document.querySelector('[data-testid="status"]').textContent.includes("Converged"),
  );
  assert.equal(
    await page.$$eval(".tree", (trees) =>
      trees.every((tree) => tree.textContent.includes("surveys/")),
    ),
    true,
  );
  await page.click(selector("add-reading-b-root"));
  await page.waitForFunction(
    () => document.querySelector('[data-testid="pending-b"]').textContent === "1 pending",
  );
  await page.waitForFunction(
    () => document.querySelector('[data-testid="status"]').textContent.includes("Converged"),
  );
  assert.equal(
    await page.$$eval(".tree", (trees) =>
      trees.every((tree) => tree.textContent.includes("grade")),
    ),
    true,
  );

  await page.click(selector("reset"));
  await page.waitForFunction(
    () =>
      document.querySelectorAll(".dir-node").length === 3 &&
      !document.querySelector('[data-testid="race"]').disabled,
  );
  await page.click(selector("race"));
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
    await page.$$eval(".tree", (trees) =>
      trees.map(
        (tree) =>
          [...tree.querySelectorAll(".dir-name")].filter(
            (node) => node.textContent === "kettle-run/",
          ).length,
      ),
    ),
    [1, 1, 1],
  );

  await page.click(selector("reset"));
  await page.waitForFunction(
    () =>
      document.querySelectorAll(".dir-node").length === 3 &&
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
  assert.equal(
    await page.$$eval(".tree", (trees) =>
      trees.every(
        (tree) =>
          tree.textContent.includes("surveys/") &&
          tree.textContent.includes("BM-17") &&
          tree.textContent.includes("plans/") &&
          tree.textContent.includes("grade"),
      ),
    ),
    true,
  );
  await page.click(selector("add-folder-a-surveys"));
  await page.waitForFunction(
    () => document.querySelector('[data-testid="pending-a"]').textContent === "1 pending",
  );
  await page.waitForFunction(
    () => document.querySelector('[data-testid="status"]').textContent.includes("Converged"),
  );
  assert.equal(
    await page.$$eval(".tree", (trees) =>
      trees.every((tree) => tree.textContent.includes("logs/")),
    ),
    true,
  );
  await page.click(selector("add-reading-a-surveys"));
  await page.waitForFunction(
    () => document.querySelector('[data-testid="pending-a"]').textContent === "1 pending",
  );
  await page.waitForFunction(
    () => document.querySelector('[data-testid="status"]').textContent.includes("Converged"),
  );
  assert.equal(
    await page.$$eval(".tree", (trees) =>
      trees.every((tree) => tree.textContent.includes("silt")),
    ),
    true,
  );
  await page.click(selector("delete-a-surveys"));
  await page.waitForFunction(
    () => document.querySelector('[data-testid="pending-a"]').textContent === "1 pending",
  );
  await page.waitForFunction(
    () => document.querySelector('[data-testid="status"]').textContent.includes("Converged"),
  );
  assert.equal(
    await page.$$eval(".tree", (trees) =>
      trees.every((tree) => !tree.textContent.includes("surveys/")),
    ),
    true,
  );

  await page.click(selector("reset"));
  await page.waitForFunction(
    () =>
      document.querySelectorAll(".dir-node").length === 3 &&
      !document.querySelector('[data-testid="race"]').disabled,
  );
  await page.click(selector("jitter"));
  await page.click(selector("add-folder-b-root"));
  await page.waitForFunction(
    () => document.querySelector('[data-testid="pending-b"]').textContent === "1 pending",
  );
  await page.waitForFunction(
    () =>
      document.querySelector('[data-testid="tree-a"]').textContent.includes("plans/") &&
      !document.querySelector('[data-testid="tree-c"]').textContent.includes("plans/"),
  );
  assert.equal(
    await page.$eval(selector("status"), (node) =>
      node.textContent.includes("Revising"),
    ),
    true,
  );
  await page.waitForFunction(
    () => document.querySelector('[data-testid="status"]').textContent.includes("Converged"),
  );
  await page.click(selector("reset"));
  await page.waitForFunction(
    () =>
      document.querySelectorAll(".dir-node").length === 3 &&
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
    await page.$$eval(`${selector("flow-layer")} [data-flow-id]`, (nodes) =>
      nodes.every((node) =>
        node
          .getAnimations()
          .every((animation) => animation.effect.getTiming().duration === 0),
      ),
    ),
  );
  assert.equal(await page.$eval(selector("error"), (node) => node.textContent), "");

  const noJs = await browser.newPage();
  await noJs.setJavaScriptEnabled(false);
  await noJs.goto(`${origin}/directory/`);
  assert.equal(await noJs.$$eval(".dir-node", (nodes) => nodes.length), 0);
  assert.equal(
    await noJs.$eval(selector("noscript"), (node) => node.checkVisibility()),
    true,
  );
  assert.equal(
    await noJs.$eval(selector("directory-fallback"), (node) =>
      node.checkVisibility(),
    ),
    false,
  );
  await noJs.close();

  const blocked = await browser.newPage();
  await blocked.setRequestInterception(true);
  blocked.on("request", (request) => {
    const path = new URL(request.url()).pathname;
    if (path === "/directory.js") request.abort();
    else if (request.url().startsWith("https://tinylytics.app/")) {
      request.respond({ status: 200, contentType: "text/javascript", body: "" });
    } else request.continue();
  });
  await blocked.goto(`${origin}/directory/`);
  await blocked.waitForSelector(selector("directory-fallback"), {
    visible: true,
    timeout: 6000,
  });
  assert.equal(await blocked.$$eval(".dir-node", (nodes) => nodes.length), 0);
  assert.equal(await blocked.$eval(selector("race"), (node) => node.disabled), true);
  await blocked.close();

  assert.deepEqual(errors, [], "browser errors");
  console.log(
    "PASS: Directory Astro parity, edits, race, reset, no-JS, and failures.",
  );
});
