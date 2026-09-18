import assert from "node:assert/strict";
import { openPage, parity, readParity, withBrowserSite, writeParity } from "./site.mjs";

const { record, site, fixture } = parity(import.meta.url, "astro-home-parity.json");

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
    await writeParity(fixture, { desktop, mobile });
    console.log("Recorded Astro homepage parity baseline.");
    return;
  }
  assert.deepEqual(
    { desktop, mobile },
    await readParity(fixture),
  );
  assert.deepEqual(errors, []);
  assert.equal(await page.$("astro-island, script[src*='_astro'], script[src*='@vite']"), null);
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
  assert.equal(
    await page.$eval('[data-strip-client="a"] [data-strip-key="mill-race"]', (node) =>
      node.textContent,
    ),
    values[0],
  );
  assert.equal(
    await page.$eval("[data-strip-race]", (button) => button.disabled),
    false,
  );
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
  console.log("PASS: Homepage SharedMap demo converges without Astro runtime.");
});
