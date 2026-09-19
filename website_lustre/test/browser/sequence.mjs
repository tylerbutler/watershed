import assert from "node:assert/strict";
import { openPage, contract, readContract, withBrowserSite, writeContract } from "./site.mjs";

const { record, site, fixture } = contract(import.meta.url, "site-sequence-contract.json");

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
  assert.equal(
    await page.$$eval("svg.route-river path", (nodes) => nodes.length),
    3,
    "each route renders its river",
  );
  assert.deepEqual(errors, [], "startup browser errors");
  const desktop = await snapshot(page);
  await page.setViewport({ width: 390, height: 844 });
  const mobile = await snapshot(page);
  if (record) {
    await writeContract(fixture, { desktop, mobile });
    console.log("Recorded site Sequence contract baseline.");
    return;
  }

  assert.deepEqual(
    { desktop, mobile },
    await readContract(fixture),
  );
  assert.equal(mobile.fitsViewport, true, "mobile overflow");
  assert.equal(
    await page.$("script[src*='@vite']"),
    null,
  );

  await page.setViewport({ width: 1440, height: 1000 });
  await page.$eval("[data-route-pace]", (input) => {
    input.value = "2";
    input.dispatchEvent(new Event("input", { bubbles: true }));
  });
  const baseline = await converge(page);
  const movingName = await page.$eval(
    '[data-client="a"] .station:nth-of-type(2) .station-name',
    (node) => node.textContent,
  );
  const movingStation = await page.evaluateHandle(
    (name) =>
      [...document.querySelectorAll('[data-client="a"] .station')].find(
        (node) => node.querySelector(".station-name").textContent === name,
      ),
    movingName,
  );
  await page.click(
    `[data-client="a"] .station-name[aria-label^="Select ${movingName}"]`,
  );
  await page.click('[data-client="a"] [data-act="down"]');
  await waitForRevision(page);
  await converge(page);
  assert.equal(
    await page.evaluate(
      (before, name) =>
        before ===
        [...document.querySelectorAll('[data-client="a"] .station')].find(
          (node) => node.querySelector(".station-name").textContent === name,
        ),
      movingStation,
      movingName,
    ),
    true,
    "a moved station keeps its DOM identity",
  );
  await movingStation.dispose();
  await page.click("[data-route-reset]");
  await converge(page);

  await page.click("[data-route-notes]");
  await page.waitForSelector("[data-route-note]");
  assert.match(
    await page.$eval("[data-route-note]", (node) => node.textContent),
    /flash magenta.*then ink.*newest log line boxes/,
  );
  await page.click('[data-client="a"] .gap');
  await page.waitForSelector('[data-client="a"] .station.note-local');
  await page.waitForSelector(".station.note-sequenced");
  await page.waitForSelector(".op-log li.note-newest");
  await converge(page);
  const firstAnnotatedLog = await page.$(".op-log li.note-newest");
  await page.click('[data-client="b"] .gap');
  await page.waitForFunction(
    (previous) => {
      const newest = document.querySelector(".op-log li.note-newest");
      return newest && newest !== previous && newest.getAnimations().length === 1;
    },
    {},
    firstAnnotatedLog,
  );
  await firstAnnotatedLog.dispose();
  await converge(page);

  await page.emulateMediaFeatures([
    { name: "prefers-reduced-motion", value: "reduce" },
  ]);
  await page.click('[data-client="c"] .gap');
  await page.waitForSelector('[data-client="c"] .station.note-local');
  await page.waitForSelector(".station.note-sequenced");
  await page.waitForSelector(".op-log li.note-newest");
  await new Promise((resolve) => setTimeout(resolve, 100));
  const reducedAnnotations = await page.evaluate(() => {
    const local = document.querySelector('[data-client="c"] .station.note-local');
    const sequenced = document.querySelector(".station.note-sequenced");
    const log = document.querySelector(".op-log li.note-newest");
    return {
      localOpacity: getComputedStyle(local, "::after").opacity,
      sequencedOpacity: getComputedStyle(sequenced, "::after").opacity,
      logOutline: getComputedStyle(log).outlineColor,
    };
  });
  assert.deepEqual(
    {
      localOpacity: reducedAnnotations.localOpacity,
      sequencedOpacity: reducedAnnotations.sequencedOpacity,
    },
    { localOpacity: "1", sequencedOpacity: "1" },
    "reduced-motion station annotations stay visible for their model lifetime",
  );
  assert.notEqual(
    reducedAnnotations.logOutline,
    "rgba(0, 0, 0, 0)",
    "the reduced-motion log annotation stays visible for its model lifetime",
  );
  await converge(page);
  await page.emulateMediaFeatures([
    { name: "prefers-reduced-motion", value: "no-preference" },
  ]);
  await page.click("[data-route-reset]");
  await converge(page);

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

  for (let remaining = baseline.length; remaining > 1; remaining--) {
    const stations = await page.$$('[data-client="a"] .station-name');
    await stations.at(-1).click();
    await Promise.all(stations.map((station) => station.dispose()));
    await page.click('[data-client="a"] [data-act="delete"]');
    await waitForRevision(page);
    assert.equal((await converge(page)).length, remaining - 1);
  }
  await page.click("[data-route-race-move]");
  await page.waitForFunction(() =>
    document.querySelector('[data-testid="error"]').textContent
      .includes("No waypoint can move in both directions."),
  );
  assert.equal(await page.$eval("[data-route-reset]", (button) => button.disabled), false);
  assert.equal(await page.$eval('[data-client="b"] .gap', (button) => button.disabled), false);
  await page.click('[data-client="b"] .gap');
  await waitForRevision(page);
  assert.equal((await converge(page)).length, 2);
  assert.equal(await page.$eval('[data-testid="error"]', (node) => node.textContent), "");
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
  console.log("PASS: Sequence contract, races, edit, reset, and fallbacks.");
});
