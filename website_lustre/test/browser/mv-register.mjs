import assert from "node:assert/strict";
import { openPage, parity, readParity, withBrowserSite, writeParity } from "./site.mjs";
import { sampleJitter } from "../../src/watershed_site/client/structure_demo_ffi.mjs";

const { record, site, fixture } = parity(import.meta.url, "astro-mv-register-parity.json");
const jitterSamples = new Set(
  Array.from({ length: 100 }, () => sampleJitter(100)),
);
assert.ok(jitterSamples.size > 2, "jitter samples instead of alternating");
assert.ok(
  [...jitterSamples].every((sample) => sample >= -100 && sample <= 100),
  "jitter stays within the configured range",
);

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
      hero: text(document.querySelector(".mv-hero")),
      demoHeading: text(document.querySelector(".demo-head h2")),
      demoIntro: text(document.querySelector(".demo-intro")),
      mergeRule: text(document.querySelector('[data-merge-rule="mv-register"]')),
      clients: [...document.querySelectorAll(".client")].map((client) => ({
        label: client.getAttribute("aria-label"),
        heading: text(client.querySelector(".client-head h3")),
        panel: text(client.querySelector(".dds-mv-register")),
      })),
      controls: text(document.querySelector(".demo-controls")),
      notes: [...document.querySelectorAll(".mv-notes h2")].map(text),
      viewportWidth: innerWidth,
      scrollWidth: document.documentElement.scrollWidth,
      fitsViewport: document.documentElement.scrollWidth <= innerWidth,
      styles: {
        hero: style(".mv-hero", ["padding", "max-width"]),
        demo: style(".demo", ["padding", "border-top-width", "border-bottom-width"]),
        rig: style(".rig", [
          "display",
          "grid-template-areas",
          "grid-template-columns",
          "gap",
        ]),
        client: style(".client", ["border", "background-color"]),
        panel: style(".dds-mv-register", ["display", "gap", "padding"]),
        controls: style(".demo-controls", ["display", "gap", "margin-top"]),
      },
    };
  });
}

const values = (page) =>
  page.$$eval("[data-mv-register-values]", (nodes) =>
    nodes.map((node) => node.textContent),
  );

await withBrowserSite(site, async (browser, origin) => {
  const { page, errors } = await openPage(browser);
  await page.setViewport({ width: 1440, height: 1000 });
  assert.equal((await page.goto(`${origin}/mv-register/`)).status(), 200);
  await page.evaluate(() => document.fonts.ready);
  await page.waitForFunction(() => !document.querySelector("[data-race]").disabled);
  assert.deepEqual(errors, [], "startup browser errors");
  const desktop = await snapshot(page);
  await page.setViewport({ width: 390, height: 844 });
  const mobile = await snapshot(page);
  if (record) {
    assert.deepEqual(errors, [], "baseline browser errors");
    await writeParity(fixture, { desktop, mobile });
    console.log("Recorded Astro MV register parity baseline.");
    return;
  }

  const baseline = await readParity(fixture);
  baseline.mobile.scrollWidth = mobile.scrollWidth;
  baseline.mobile.fitsViewport = mobile.fitsViewport;
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
    ["/mv_register.js", "/scripts/concept-index.js"],
  );

  await page.setViewport({ width: 1440, height: 1000 });
  await page.$eval("[data-pace]", (input) => {
    input.value = "2";
    input.dispatchEvent(new Event("input", { bubbles: true }));
  });
  const initialSequence = await page.$eval(
    "[data-seq-counter]",
    (node) => node.textContent,
  );
  await page.$eval('[data-client="a"] [data-mv-register-input]', (input) => {
    input.value = "enter revision";
    input.dispatchEvent(new Event("input", { bubbles: true }));
  });
  await page.focus('[data-client="a"] [data-mv-register-input]');
  await page.keyboard.press("Enter");
  await page.waitForFunction(() =>
    [...document.querySelectorAll("[data-mv-register-values]")].every(
      (node) => node.textContent === '["enter revision"]',
    ),
  );
  await page.click("[data-reset]");
  await page.waitForFunction(() =>
    [...document.querySelectorAll("[data-mv-register-values]")].every(
      (node) => node.textContent === '["Survey datum"]',
    ),
  );
  await page.click("[data-cut-link]");
  await page.$eval('[data-client="a"] [data-mv-register-input]', (input) => {
    input.value = "catch-up first";
    input.dispatchEvent(new Event("input", { bubbles: true }));
  });
  await page.click('[data-client="a"] [data-mv-register-write]');
  await page.waitForFunction(
    () =>
      document.querySelector(
        '[data-client="a"] [data-mv-register-values]',
      ).textContent.includes("catch-up first") &&
      document.querySelector(
        '[data-client="c"] [data-mv-register-values]',
      ).textContent.includes("catch-up first") &&
      !document.querySelector(
        '[data-client="b"] [data-mv-register-values]',
      ).textContent.includes("catch-up first"),
  );
  await page.$eval('[data-client="b"] [data-mv-register-input]', (input) => {
    input.value = "b first";
    input.dispatchEvent(new Event("input", { bubbles: true }));
  });
  await page.click('[data-client="b"] [data-mv-register-write]');
  await page.$eval('[data-client="b"] [data-mv-register-input]', (input) => {
    input.value = "b second";
    input.dispatchEvent(new Event("input", { bubbles: true }));
  });
  await page.click('[data-client="b"] [data-mv-register-write]');
  await page.waitForFunction(
    () =>
      document.querySelector('[data-client="b"] [data-pending-count]')
        .textContent === "2 pending",
  );
  await page.click("[data-cut-link]");
  await page.waitForFunction(
    () => document.querySelector("[data-cut-link]").textContent.includes("Cut link"),
  );
  await page.waitForFunction(
    () =>
      [...document.querySelectorAll("[data-mv-register-values]")].every(
        (node) => node.textContent === '["b second"]',
      ) &&
      [...document.querySelectorAll("[data-pending-count]")].every(
        (node) => node.textContent === "0 pending",
      ),
  );
  const alternatives = await values(page);
  assert.equal(new Set(alternatives).size, 1);
  assert.deepEqual(
    await page.$$eval("[data-op-log] li", (nodes) =>
      nodes.map((node) => node.textContent).reverse(),
    ),
    [
      "MV-register write catch-up first",
      "MV-register write b first",
      "MV-register write b second",
    ],
  );

  const sequenceBeforeReplay = await page.$eval(
    "[data-seq-counter]",
    (node) => node.textContent,
  );
  assert.notEqual(sequenceBeforeReplay, initialSequence);
  await page.click("[data-replay]");
  await page.waitForFunction(
    () =>
      document.querySelector("[data-status]").textContent.includes("Converged") &&
      [...document.querySelectorAll("[data-op-log] li")].some(
        (node) => node.textContent.includes("again"),
      ),
  );
  assert.deepEqual(await values(page), alternatives);
  assert.equal(
    await page.$eval("[data-seq-counter]", (node) => node.textContent),
    sequenceBeforeReplay,
  );

  await page.click('[data-client="a"] [data-mv-register-resolve]');
  await page.waitForFunction(
    () =>
      [...document.querySelectorAll("[data-mv-register-values]")].every(
        (node) => node.textContent === '["raise crest + arm pump"]',
      ),
  );

  await page.click("[data-reset]");
  await page.waitForFunction(
    () =>
      [...document.querySelectorAll("[data-mv-register-values]")].every(
        (node) => node.textContent === '["Survey datum"]',
      ),
  );
  await page.emulateMediaFeatures([
    { name: "prefers-reduced-motion", value: "no-preference" },
  ]);
  await page.click("[data-latency-variance]");
  await page.click("[data-race]");
  await page.waitForSelector("[data-flow-id]");
  const movingFlow = await page.$eval("[data-flow-id]", async (dot) => {
    const animation = getComputedStyle(dot).animationName;
    const before = getComputedStyle(dot).transform;
    await new Promise((resolve) => setTimeout(resolve, 80));
    return {
      animation,
      before,
      after: getComputedStyle(dot).transform,
      duration: getComputedStyle(dot).animationDuration,
      reduced: matchMedia("(prefers-reduced-motion: reduce)").matches,
      animations: dot.getAnimations().map((item) => item.animationName),
    };
  });
  assert.notEqual(
    movingFlow.animation,
    "none",
    `flow dot has a real animation: ${JSON.stringify(movingFlow)}`,
  );
  assert.notEqual(movingFlow.before, movingFlow.after, "flow dot changes position");
  await page.waitForFunction(
    () =>
      [...document.querySelectorAll("[data-mv-register-values]")].every(
        (node) =>
          node.textContent.includes("raise crest") &&
          node.textContent.includes("arm pump"),
      ),
  );

  const noJs = await browser.newPage();
  await noJs.setJavaScriptEnabled(false);
  await noJs.goto(`${origin}/mv-register/`);
  assert.equal(
    await noJs.$eval('[data-testid="noscript"]', (node) =>
      node.checkVisibility(),
    ),
    true,
  );
  assert.equal(
    await noJs.$eval('[data-testid="mv-register-fallback"]', (node) =>
      node.checkVisibility(),
    ),
    false,
  );
  await noJs.close();

  const blocked = await browser.newPage();
  await blocked.setRequestInterception(true);
  blocked.on("request", (request) => {
    const path = new URL(request.url()).pathname;
    if (path === "/mv_register.js") request.abort();
    else if (request.url().startsWith("https://tinylytics.app/")) {
      request.respond({ status: 200, contentType: "text/javascript", body: "" });
    } else request.continue();
  });
  await blocked.goto(`${origin}/mv-register/`);
  await blocked.waitForSelector('[data-testid="mv-register-fallback"]', {
    visible: true,
    timeout: 6000,
  });
  await blocked.close();

  assert.deepEqual(errors, [], "browser errors");
  console.log(
    "PASS: MV register parity, offline resolution, replay, reset, and fallbacks.",
  );
});
