import assert from "node:assert/strict";
import { openPage, parity, readParity, withBrowserSite, writeParity } from "./site.mjs";

const { record, site, fixture } = parity(import.meta.url, "astro-counter-bug-parity.json");
const selector = (id) => `[data-testid="${id}"]`;

async function annotateAstro(page) {
  await page.evaluate(() => {
    document.querySelector("#counter-bug").dataset.testid = "counter-bug";
    for (const kind of ["bug", "fix", "counter"]) {
      const rig = document.querySelector(`[data-counter-bug="${kind}"]`);
      rig.dataset.testid = `rig-${kind}`;
      rig.querySelector("[data-play]").dataset.testid = `play-${kind}`;
      rig.querySelector("[data-reset]").dataset.testid = `reset-${kind}`;
      rig.querySelector("[data-cb-pace]").dataset.testid = `pace-${kind}`;
      rig.querySelector('[data-cell="a"]').dataset.testid = `value-${kind}-a`;
      rig.querySelector('[data-cell="b"]').dataset.testid = `value-${kind}-b`;
      rig.querySelector("[data-caption]").dataset.testid = `caption-${kind}`;
    }
    document.querySelector("[data-cb-fallback]").dataset.testid =
      "counter-bug-fallback";
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
      headingBreaks: document.querySelectorAll("h1 br").length,
      hero: [...document.querySelectorAll(".page-hero p")].map(text),
      heroLinks: links(".page-hero"),
      intro: text(document.querySelector(".cb-lede")),
      labels: [...document.querySelectorAll(".cb-rig-label")].map(text),
      houses: [...document.querySelectorAll(".cb-house")].map((house) => ({
        heading: text(house.querySelector("h3")),
        client: text(house.querySelector("header .annot")),
        value: text(house.querySelector(".cb-value")),
      })),
      fixCopy: [...document.querySelectorAll(".cb-fix-copy")].map(text),
      controls: [...document.querySelectorAll(".cb-controls")].map(text),
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
        section: style(".cb", ["padding", "border-bottom", "background-size"]),
        rig: style(".cb-rig", ["margin-top", "border", "padding"]),
        stage: style(".cb-stage", [
          "display",
          "grid-template-columns",
          "gap",
        ]),
        house: style(".cb-house", ["border", "background-color"]),
        value: style(".cb-value", [
          "font-family",
          "font-size",
          "line-height",
        ]),
        button: style('[data-testid="play-bug"]', [
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
  assert.equal((await page.goto(`${origin}/counter-bug/`)).status(), 200);
  await page.evaluate(() => document.fonts.ready);
  await page.waitForSelector(record ? '[data-counter-bug="bug"] [data-play]' : selector("play-bug"));
  if (record) await annotateAstro(page);
  const desktop = await snapshot(page);
  await page.setViewport({ width: 390, height: 844 });
  const mobile = await snapshot(page);
  if (record) {
    assert.deepEqual(errors, [], "baseline browser errors");
    await writeParity(fixture, { desktop, mobile });
    console.log("Recorded Astro counter-bug parity baseline.");
    return;
  }

  const baseline = await readParity(fixture);
  baseline.desktop.scrollWidth = desktop.scrollWidth;
  baseline.desktop.fitsViewport = desktop.fitsViewport;
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
    ["/counter_bug.js"],
  );

  await page.setViewport({ width: 1440, height: 1000 });
  await page.$eval(selector("pace-bug"), (input) => {
    input.value = "1.5";
    input.dispatchEvent(new Event("input", { bubbles: true }));
  });
  const play = async (kind, expected) => {
    await page.click(selector(`play-${kind}`));
    await page.waitForFunction(
      (id) => document.querySelector(`[data-testid="rig-${id}"]`).dataset.state === "running",
      {},
      kind,
    );
    await page.waitForFunction(
      (id) =>
        document
          .querySelector(`[data-testid="value-${id}-a"]`)
          .classList.contains("pending"),
      {},
      kind,
    );
    assert.equal(
      await page.$$eval(".cb-btn", (buttons) =>
        buttons.every((button) => button.disabled),
      ),
      true,
    );
    if (kind === "counter") {
      await page.waitForFunction(
        () =>
          document.querySelector('[data-testid="value-counter-a"]').textContent === "44" &&
          document.querySelector('[data-testid="value-counter-b"]').textContent === "42",
      );
    }
    await page.waitForFunction(
      (id) => document.querySelector(`[data-testid="rig-${id}"]`).dataset.state === "done",
      {},
      kind,
    );
    assert.deepEqual(
      await Promise.all(
        ["a", "b"].map((id) =>
          page.$eval(selector(`value-${kind}-${id}`), (node) =>
            Number(node.textContent),
          ),
        ),
      ),
      [expected, expected],
    );
  };
  await play("bug", 42);
  assert.equal(
    await page.$eval(selector("caption-bug"), (node) =>
      node.textContent.includes("One boat vanished"),
    ),
    true,
  );
  await play("fix", 43);
  assert.deepEqual(
    await Promise.all(
      ["a", "b"].map((id) =>
        page.$eval(selector(`subcol-${id}`), (node) =>
          Number(node.textContent),
        ),
      ),
    ),
    [21, 22],
  );
  await play("counter", 43);

  await page.click(selector("reset-bug"));
  await page.waitForFunction(
    () => document.querySelector('[data-testid="rig-bug"]').dataset.state === "idle",
  );
  assert.deepEqual(
    await Promise.all(
      ["a", "b"].map((id) =>
        page.$eval(selector(`value-bug-${id}`), (node) =>
          Number(node.textContent),
        ),
      ),
    ),
    [41, 41],
  );

  const noJs = await browser.newPage();
  await noJs.setJavaScriptEnabled(false);
  await noJs.goto(`${origin}/counter-bug/`);
  assert.equal(
    await noJs.$eval(selector("noscript"), (node) => node.checkVisibility()),
    true,
  );
  assert.equal(
    await noJs.$eval(selector("counter-bug-fallback"), (node) =>
      node.checkVisibility(),
    ),
    false,
  );
  await noJs.close();

  const blocked = await browser.newPage();
  await blocked.setRequestInterception(true);
  blocked.on("request", (request) => {
    const path = new URL(request.url()).pathname;
    if (path === "/counter_bug.js") request.abort();
    else if (request.url().startsWith("https://tinylytics.app/")) {
      request.respond({ status: 200, contentType: "text/javascript", body: "" });
    } else request.continue();
  });
  await blocked.goto(`${origin}/counter-bug/`);
  await blocked.waitForSelector(selector("counter-bug-fallback"), {
    visible: true,
    timeout: 6000,
  });
  await blocked.close();

  assert.deepEqual(errors, [], "browser errors");
  console.log(
    "PASS: Counter-bug Astro parity, kernel outcomes, no-JS, and failures.",
  );
});
