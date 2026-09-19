import assert from "node:assert/strict";
import { openPage, contract, readContract, withBrowserSite, writeContract } from "./site.mjs";

const { record, site, fixture } = contract(import.meta.url, "site-home-contract.json");

async function snapshot(page) {
  return page.evaluate(() => {
    const text = (selector) =>
      document.querySelector(selector)?.innerText.replace(/\s+/g, " ").trim();
    const style = (selector, properties) => {
      const computed = getComputedStyle(document.querySelector(selector));
      return Object.fromEntries(properties.map((name) => [
        name,
        computed.getPropertyValue(name),
      ]));
    };
    return {
      title: document.title,
      description: document.querySelector('meta[name="description"]')?.content,
      hero: text(".hero"),
      headings: [...document.querySelectorAll("main h2")].map((node) =>
        node.textContent.replace(/\s+/g, " ").trim(),
      ),
      demoHeading: text("#demo-title"),
      featuredSheets: document.querySelectorAll(".field-sheet").length,
      flowSteps: document.querySelectorAll(".flow-steps li").length,
      strata: document.querySelectorAll(".stratum").length,
      ledgerRows: document.querySelectorAll(".ledger tbody tr").length,
      hasSourceSnippet: Boolean(document.querySelector(".code-figure pre code")),
      links: [...document.querySelectorAll("main a")].map((node) =>
        node.innerText.replace(/\s+/g, " ").trim(),
      ).filter(Boolean).sort(),
      fitsViewport: document.documentElement.scrollWidth <= innerWidth,
      styles: {
        hero: style(".hero", ["padding", "border-bottom-width", "overflow"]),
        rig: style("[data-demo-rig]", ["display", "grid-template-areas", "gap"]),
      },
    };
  });
}

await withBrowserSite(site, async (browser, origin) => {
  const { page, errors } = await openPage(browser);
  await page.setViewport({ width: 1440, height: 1000 });
  assert.equal((await page.goto(`${origin}/`)).status(), 200);
  await page.waitForFunction(
    (lustre) =>
      (!lustre || document.querySelector("#demo")?.hasAttribute("data-mounted")) &&
      [...document.querySelectorAll(".dds-map [data-step]")].some(
        (node) => !node.disabled,
      ),
    !record,
  );
  const desktop = await snapshot(page);
  await page.setViewport({ width: 390, height: 844 });
  const mobile = await snapshot(page);
  if (record) {
    await writeContract(fixture, { desktop, mobile });
    console.log("Recorded site homepage contract baseline.");
    return;
  }
  assert.equal(
    await page.$$eval("#home-demo-mount", (nodes) => nodes.length),
    1,
  );
  assert.deepEqual(
    { desktop, mobile },
    await readContract(fixture),
  );
  assert.deepEqual(errors, []);
  assert.equal(await page.$("script[src*='@vite']"), null);
  const before = await page.$eval(
    '[data-client="a"] .dds-map tr[data-key="mill-race"] [data-value]',
    (node) => node.textContent,
  );
  await page.click(
    '[data-client="a"] .dds-map tr[data-key="mill-race"] [data-step="1"]',
  );
  await page.waitForFunction(
    (value) =>
      [...document.querySelectorAll('.dds-map tr[data-key="mill-race"] [data-value]')]
        .every((node) => node.textContent !== value),
    {},
    before,
  );
  const values = await page.$$eval(
    '.dds-map tr[data-key="mill-race"] [data-value]',
    (nodes) => nodes.map((node) => node.textContent),
  );
  assert.equal(new Set(values).size, 1);
  assert.deepEqual(
    await page.$eval('[data-strip-client="a"] [data-strip-key="mill-race"]', (node) =>
      node.textContent,
    ),
    values[0],
  );
  assert.equal(
    await page.$eval("[data-strip-race]", (button) => button.disabled),
    false,
  );
  await page.setViewport({ width: 1440, height: 1000 });
  const contour = "[data-contour-field] #contour-0";
  await page.$eval(contour, (path) => path.scrollIntoView());
  const initialContour = await page.$eval(contour, (path) => path.getAttribute("d"));
  await page.waitForFunction(
    (selector, path) =>
      document.querySelector(selector)?.getAttribute("d") !== path,
    {},
    contour,
    initialContour,
  );
  await page.emulateMediaFeatures([
    { name: "prefers-reduced-motion", value: "reduce" },
  ]);
  await new Promise((resolve) => setTimeout(resolve, 200));
  const reducedContour = await page.$eval(contour, (path) => path.getAttribute("d"));
  await new Promise((resolve) => setTimeout(resolve, 200));
  assert.equal(
    await page.$eval(contour, (path) => path.getAttribute("d")),
    reducedContour,
  );
  await page.emulateMediaFeatures([
    { name: "prefers-reduced-motion", value: "no-preference" },
  ]);
  await page.waitForFunction(
    (selector, path) =>
      document.querySelector(selector)?.getAttribute("d") !== path,
    {},
    contour,
    reducedContour,
  );
  await page.click("[data-cut-link]");
  const cutValue = await page.$eval(
    '[data-client="a"] .dds-map tr[data-key="mill-race"] [data-value]',
    (node) => node.textContent,
  );
  await page.click(
    '[data-client="a"] .dds-map tr[data-key="mill-race"] [data-step="1"]',
  );
  await page.waitForFunction(
    (value) =>
      document.querySelector(
        '[data-client="a"] .dds-map tr[data-key="mill-race"] [data-value]',
      ).textContent !== value &&
      document.querySelector(
        '[data-client="c"] .dds-map tr[data-key="mill-race"] [data-value]',
      ).textContent !== value,
    {},
    cutValue,
  );
  assert.equal(
    await page.$eval(
      '[data-client="b"] .dds-map tr[data-key="mill-race"] [data-value]',
      (node) => node.textContent,
    ),
    cutValue,
  );
  assert.deepEqual(
    await page.$eval("[data-cut-link]", (button) => [
      button.textContent.trim(),
      button.getAttribute("aria-pressed"),
    ]),
    ["Restore link", "true"],
  );
  await page.click("[data-cut-link]");
  assert.notEqual(await page.$("#after-demo"), null);

  const reduced = await browser.newPage();
  await reduced.emulateMediaFeatures([
    { name: "prefers-reduced-motion", value: "reduce" },
  ]);
  await reduced.goto(`${origin}/`);
  assert.equal(
    await reduced.$$eval("[data-contour-field] path", (nodes) =>
      new Set(nodes.map((node) => node.getAttribute("d"))).size,
    ),
    13,
  );
  await reduced.close();

  const noJs = await browser.newPage();
  await noJs.setJavaScriptEnabled(false);
  await noJs.goto(`${origin}/`);
  assert.equal(
    await noJs.$eval('[data-testid="noscript"]', (node) => node.checkVisibility()),
    true,
  );
  await noJs.close();

  const blocked = await browser.newPage();
  await blocked.setRequestInterception(true);
  blocked.on("request", (request) => {
    if (new URL(request.url()).pathname === "/home.js") request.abort();
    else request.continue();
  });
  await blocked.goto(`${origin}/`);
  await blocked.waitForSelector('[data-testid="home-fallback"]', {
    visible: true,
    timeout: 6000,
  });
  await blocked.close();
  await page.setViewport({ width: 390, height: 844, hasTouch: true, isMobile: true });
  assert.equal(
    await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth),
    true,
  );
  console.log("PASS: Homepage SharedMap demo converges with the native runtime.");
});
