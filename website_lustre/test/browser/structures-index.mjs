import assert from "node:assert/strict";
import { openPage, parity, readParity, withBrowserSite, writeParity } from "./site.mjs";

const { record, site, fixture } = parity(import.meta.url, "astro-structures-index-parity.json");

async function snapshot(page) {
  return page.evaluate(() => {
    const text = (node) => node.textContent.replace(/\s+/g, " ").trim();
    const links = (selector) => [...document.querySelectorAll(`${selector} a`)]
      .map((node) => ({
        text: text(node),
        href: node.getAttribute("href"),
        current: node.getAttribute("aria-current"),
      }));
    const style = (selector, properties) => {
      const computed = getComputedStyle(document.querySelector(selector));
      return Object.fromEntries(properties.map((key) => [key, computed.getPropertyValue(key)]));
    };
    return {
      title: document.title,
      metadata: [...document.head.querySelectorAll("meta[name], meta[property]")]
        .map((node) => [node.getAttribute("name") || node.getAttribute("property"), node.content]),
      heading: text(document.querySelector("h1")),
      headingBreaks: document.querySelectorAll("h1 br").length,
      prose: [...document.querySelectorAll(".hub-hero p")].map(text),
      ctas: links(".cta-row"),
      families: [...document.querySelectorAll(".family")].map((link) => ({
        href: link.getAttribute("href"),
        index: text(link.querySelector(".family-index")),
        name: text(link.querySelector("h2")),
        tagline: text(link.querySelector(".family-tagline")),
        entries: [...link.querySelectorAll("li")].map((item) => ({
          name: text(item.querySelector("code")),
          kind: text(item.querySelector(".kind")),
        })),
      })),
      primary: links('nav[aria-label="Sheet index"]'),
      adjoining: links('nav[aria-labelledby="adjoining-title"]'),
      canonical: document.querySelector('link[rel="canonical"]')?.href || null,
      fitsViewport: document.documentElement.scrollWidth <= innerWidth,
      styles: {
        hero: style(".hub-hero", ["padding", "border-bottom"]),
        heading: style("h1", ["font-size", "font-weight", "font-stretch", "line-height", "letter-spacing"]),
        lede: style(".hub-hero .lede", ["font-size", "line-height", "max-width", "margin-top"]),
        families: style(".families", ["display", "grid-template-columns", "gap", "padding"]),
        family: style(".family", ["display", "padding", "border", "background-color"]),
        familyHeading: style(".family h2", ["font-size", "font-weight", "font-stretch"]),
      },
    };
  });
}

await withBrowserSite(site, async (browser, origin) => {
  const { page, errors } = await openPage(browser);
  await page.setJavaScriptEnabled(false);
  await page.setViewport({ width: 1440, height: 1000 });
  assert.equal((await page.goto(`${origin}/structures/`)).status(), 200);
  await page.evaluate(() => document.fonts.ready);
  const desktop = await snapshot(page);
  await page.setViewport({ width: 390, height: 844 });
  const mobile = await snapshot(page);
  if (record) {
    assert.deepEqual(errors, [], "baseline browser errors");
    await writeParity(fixture, { desktop, mobile });
    console.log("Recorded Astro structures index parity baseline.");
    return;
  }
  const baseline = await readParity(fixture);
  assert.deepEqual({ desktop, mobile }, baseline);
  assert.equal(mobile.fitsViewport, true, "mobile overflow");
  assert.equal(await page.$("astro-island, script[src*='_astro'], script[src*='@vite']"), null);
  assert.deepEqual(
    await page.$$eval('script[type="module"]', (nodes) => nodes.map((node) => new URL(node.src).pathname)),
    ["/scripts/concept-index.js"],
  );
  assert.equal(
    await page.$$eval(".family", (nodes) =>
      nodes.length === 7 && nodes.every((node) => node.checkVisibility())),
    true,
    "all families work without JavaScript",
  );
  await page.focus(".family");
  assert.notEqual(
    await page.evaluate(() => getComputedStyle(document.activeElement).outlineStyle),
    "none",
  );
  await page.setJavaScriptEnabled(true);
  await page.setViewport({ width: 1440, height: 1000 });
  await page.emulateMediaFeatures([{ name: "prefers-reduced-motion", value: "no-preference" }]);
  await page.reload();
  await page.waitForFunction(() =>
    document.querySelector(".family")?.dataset.revealIndex === "0");
  await page.emulateMediaFeatures([{ name: "prefers-reduced-motion", value: "reduce" }]);
  await page.reload();
  assert.equal(await page.$$eval("[data-reveal-index]", (nodes) => nodes.length), 0);
  assert.equal(
    await page.$$eval(".family", (nodes) => nodes.every((node) => node.checkVisibility())),
    true,
  );
  assert.deepEqual(errors, [], "browser errors");
  console.log("PASS: structures index Astro parity, focus, no-JS, and reveal motion.");
});
