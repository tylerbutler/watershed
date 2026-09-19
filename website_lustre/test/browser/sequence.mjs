import assert from "node:assert/strict";
import { openPage, parity, readParity, withBrowserSite, writeParity } from "./site.mjs";

const { record, site, fixture } = parity(import.meta.url, "astro-sequence-parity.json");

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
      metadata: [...document.head.querySelectorAll("meta[name], meta[property]")].map(
        (node) => [
          node.getAttribute("name") || node.getAttribute("property"),
          node.content,
        ],
      ),
      hero: text(document.querySelector(".page-hero")),
      demoHeading: text(document.querySelector(".demo-head h2")),
      demoCopy: [...document.querySelectorAll(".demo-head p")].map(text),
      clients: [...document.querySelectorAll(".client")].map((client) => ({
        label: client.getAttribute("aria-label"),
        heading: text(client.querySelector("h3")),
        route: [...client.querySelectorAll(".station-name")].map(text),
      })),
      controls: text(document.querySelector(".demo-controls")),
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
        controls: style(".demo-controls", ["display", "gap", "margin-top"]),
      },
    };
  });
}

const routes = (page) =>
  page.$$eval("[data-route]", (nodes) =>
    nodes.map((node) =>
      [...node.querySelectorAll(".station")]
        .sort(
          (left, right) =>
            Number(left.querySelector("[data-station-no]").textContent) -
            Number(right.querySelector("[data-station-no]").textContent),
        )
        .map((station) => station.querySelector(".station-name").textContent),
    ),
  );

async function converge(page) {
  await page.waitForFunction(
    () =>
      document.querySelector("[data-route-status]").textContent.includes("Converged") &&
      [...document.querySelectorAll("[data-pending-count]")].every(
        (node) => node.textContent === "0 pending",
      ),
  );
  const values = await routes(page);
  assert.deepEqual(values[0], values[1]);
  assert.deepEqual(values[1], values[2]);
  return values[0];
}

async function waitForRevision(page) {
  await page.waitForFunction(
    () =>
      document.querySelector("[data-route-status]").textContent.includes("Revising") ||
      [...document.querySelectorAll("[data-pending-count]")].some(
        (node) => node.textContent !== "0 pending",
      ),
  );
}

await withBrowserSite(site, async (browser, origin) => {
  const { page, errors } = await openPage(browser);
  await page.setViewport({ width: 1440, height: 1000 });
  assert.equal((await page.goto(`${origin}/sequence/`)).status(), 200);
  await page.evaluate(() => document.fonts.ready);
  await page.waitForFunction(
    () =>
      document.querySelectorAll(".station-name").length === 15 &&
      !document.querySelector("[data-route-race-move]").disabled,
  );
  assert.deepEqual(errors, [], "startup browser errors");
  const desktop = await snapshot(page);
  await page.setViewport({ width: 390, height: 844 });
  const mobile = await snapshot(page);
  if (record) {
    await writeParity(fixture, { desktop, mobile });
    console.log("Recorded Astro Sequence parity baseline.");
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
  await page.$eval("[data-route-pace]", (input) => {
    input.value = "2";
    input.dispatchEvent(new Event("input", { bubbles: true }));
  });
  const baseline = await converge(page);
  await page.click("[data-route-race-move]");
  await waitForRevision(page);
  await converge(page);
  await page.click("[data-route-race-insert]");
  await waitForRevision(page);
  const crowded = await converge(page);
  assert.equal(crowded.length, baseline.length + 2);
  await page.click('[data-client="a"] .station-name');
  await page.waitForFunction(() =>
    document
      .querySelector('[data-client="a"] .station')
      .classList.contains("selected"),
  );
  assert.equal(
    await page.$eval('[data-client="a"] .station', (node) =>
      node.classList.contains("selected"),
    ),
    true,
  );
  await page.click('[data-client="a"] [data-act="rename"]');
  await waitForRevision(page);
  assert.equal((await converge(page)).length, crowded.length);
  await page.click("[data-route-reset]");
  assert.deepEqual(await converge(page), baseline);

  const noJs = await browser.newPage();
  await noJs.setJavaScriptEnabled(false);
  await noJs.goto(`${origin}/sequence/`);
  assert.equal(
    await noJs.$eval('[data-testid="noscript"]', (node) => node.checkVisibility()),
    true,
  );
  await new Promise((resolve) => setTimeout(resolve, 3500));
  assert.equal(
    await noJs.$eval('[data-testid="sequence-fallback"]', (node) =>
      node.checkVisibility(),
    ),
    false,
  );
  await noJs.close();

  const touch = await browser.newPage();
  await touch.setViewport({
    width: 390,
    height: 844,
    hasTouch: true,
    isMobile: true,
  });
  await touch.goto(`${origin}/sequence/`);
  await touch.waitForFunction(
    () =>
      document.querySelector("#route-demo").hasAttribute("data-mounted") &&
      document.querySelectorAll(".station-name").length === 15,
  );
  const firstStation = await touch.$('[data-client="a"] .station-name');
  await firstStation.click();
  await touch.waitForFunction(() =>
    document
      .querySelector('[data-client="a"] .station')
      .classList.contains("selected"),
  );
  assert.equal(
    await touch.$eval('[data-client="a"] .station', (node) =>
      node.classList.contains("selected"),
    ),
    true,
  );
  assert.equal((await routes(touch))[0].length, baseline.length);
  await touch.close();

  const blocked = await browser.newPage();
  await blocked.setRequestInterception(true);
  blocked.on("request", (request) => {
    const path = new URL(request.url()).pathname;
    if (path === "/sequence.js") request.abort();
    else if (request.url().startsWith("https://tinylytics.app/")) {
      request.respond({ status: 200, contentType: "text/javascript", body: "" });
    } else request.continue();
  });
  await blocked.goto(`${origin}/sequence/`);
  await blocked.waitForSelector('[data-testid="sequence-fallback"]', {
    visible: true,
    timeout: 6000,
  });
  await blocked.close();
  assert.deepEqual(errors, [], "browser errors");
  console.log("PASS: Sequence parity, races, edit, reset, and fallbacks.");
});
