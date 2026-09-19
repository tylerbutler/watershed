import assert from "node:assert/strict";
import { openPage, contract, readContract, withBrowserSite, writeContract } from "./site.mjs";

const { record, site, fixture } = contract(import.meta.url, "site-models-contract.json");

async function snapshot(page) {
  return page.evaluate(() => {
    const text = (node) => (node.innerText ?? node.textContent).replace(/\s+/g, " ").trim();
    const links = (selector) => [...document.querySelectorAll(`${selector} a`)]
      .map((node) => [text(node), node.getAttribute("href")]);
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
      hero: [...document.querySelectorAll(".mod-hero p")].map(text),
      cards: [...document.querySelectorAll(".mod-card")].map((card) => ({
        kind: text(card.querySelector(".stamp")),
        title: text(card.querySelector("h2")),
        gloss: text(card.querySelector(".mod-gloss")),
        body: [...card.querySelectorAll(".mod-card-body p")].map(text),
        memberText: [...card.querySelectorAll(".mod-members a")].map(text),
        memberHrefs: [...card.querySelectorAll(".mod-members a")].map((node) => node.getAttribute("href")),
      })),
      table: [...document.querySelectorAll(".mod-table tr")].map((row) =>
        [...row.children].map(text)),
      guide: [...document.querySelectorAll(".mod-guide-list li")].map(text),
      guideLinks: links(".mod-guide"),
      primary: links('nav[aria-label="Sheet index"]'),
      adjoining: links('nav[aria-labelledby="adjoining-title"]'),
      fitsViewport: document.documentElement.scrollWidth <= innerWidth,
      styles: {
        hero: style(".mod-hero", ["padding", "border-bottom"]),
        heading: style("h1", ["font-size", "font-weight", "font-stretch", "line-height"]),
        cards: style(".mod-cards", ["display", "grid-template-columns", "gap", "padding"]),
        card: style(".mod-card", ["display", "padding", "border"]),
        table: style(".mod-table-scroll", ["overflow-x", "border"]),
        guide: style(".mod-guide", ["padding", "border-top", "background-image"]),
      },
    };
  });
}

await withBrowserSite(site, async (browser, origin) => {
  const { page, errors } = await openPage(browser);
  await page.setJavaScriptEnabled(false);
  await page.setViewport({ width: 1440, height: 1000 });
  assert.equal((await page.goto(`${origin}/models/`)).status(), 200);
  await page.evaluate(() => document.fonts.ready);
  const desktop = await snapshot(page);
  await page.setViewport({ width: 390, height: 844 });
  const mobile = await snapshot(page);
  if (record) {
    assert.deepEqual(errors, [], "baseline browser errors");
    await writeContract(fixture, { desktop, mobile });
    console.log("Recorded site models contract baseline.");
    return;
  }
  const baseline = await readContract(fixture);
  assert.deepEqual({ desktop, mobile }, baseline);
  assert.equal(mobile.fitsViewport, true, "mobile overflow");
  assert.equal(await page.$("script[src*='@vite']"), null);
  assert.deepEqual(
    await page.$$eval('script[type="module"]', (nodes) => nodes.map((node) => new URL(node.src).pathname)),
    ["/scripts/concept-index.js"],
  );
  await page.focus(".mod-table-scroll");
  assert.notEqual(
    await page.evaluate(() => getComputedStyle(document.activeElement).outlineStyle),
    "none",
  );
  assert.deepEqual(errors, [], "browser errors");
  console.log("PASS: models site contract, mobile layout, and keyboard focus.");
});
