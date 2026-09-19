import assert from "node:assert/strict";
import { openPage, contract, readContract, withBrowserSite, writeContract } from "./site.mjs";

const { record, site, fixture } = contract(import.meta.url, "site-patterns-contract.json");

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
      hero: [...document.querySelectorAll(".p-hero p")].map(text),
      actions: links(".p-actions"),
      sections: [...document.querySelectorAll(".p-step")].map((section) => ({
        heading: text(section.querySelector("h2")),
        intro: [...section.querySelectorAll(".p-step-head p")].map(text),
        rules: [...section.querySelectorAll(".p-rules li")].map((item) => ({
          title: text(item.querySelector(".p-rule-link")),
          href: item.querySelector(".p-rule-link").getAttribute("href"),
          rule: text(item.querySelector(".p-rule")),
          source: text(item.querySelector(".p-rule-src")),
        })),
      })),
      boundary: text(document.querySelector(".p-boundary")),
      boundaryLinks: links(".p-boundary"),
      primary: links('nav[aria-label="Sheet index"]'),
      adjoining: links('nav[aria-labelledby="adjoining-title"]'),
      viewportWidth: innerWidth,
      scrollWidth: document.documentElement.scrollWidth,
      fitsViewport: document.documentElement.scrollWidth <= innerWidth,
      styles: {
        hero: style(".p-hero", ["padding", "border-bottom"]),
        heading: style("h1", ["font-size", "font-weight", "font-stretch", "line-height"]),
        main: style(".p-main", ["padding", "max-width"]),
        section: style(".p-step", ["display", "grid-template-columns", "gap", "border-top"]),
        rule: style(".p-rule", ["margin-top", "max-width", "color", "line-height"]),
        boundary: style(".p-boundary", ["padding", "border-top", "background-image"]),
      },
    };
  });
}

await withBrowserSite(site, async (browser, origin) => {
  const { page, errors } = await openPage(browser);
  await page.setJavaScriptEnabled(false);
  await page.setViewport({ width: 1440, height: 1000 });
  assert.equal((await page.goto(`${origin}/patterns/`)).status(), 200);
  await page.evaluate(() => document.fonts.ready);
  const desktop = await snapshot(page);
  await page.setViewport({ width: 390, height: 844 });
  const mobile = await snapshot(page);
  if (record) {
    assert.deepEqual(errors, [], "baseline browser errors");
    await writeContract(fixture, { desktop, mobile });
    console.log("Recorded site patterns contract baseline.");
    return;
  }
  const baseline = await readContract(fixture);
  assert.deepEqual({ desktop, mobile }, baseline);
  assert.equal(mobile.fitsViewport, true, "mobile overflow");
  assert.equal(await page.$("script[src*='@vite']"), null);
  assert.deepEqual(await page.$$eval('script[type="module"]', (nodes) =>
    nodes.map((node) => new URL(node.src).pathname)), []);
  await page.focus(".p-rule-link");
  assert.notEqual(
    await page.evaluate(() => getComputedStyle(document.activeElement).outlineStyle),
    "none",
  );
  assert.deepEqual(errors, [], "browser errors");
  console.log("PASS: patterns site contract, mobile layout, and keyboard focus.");
});
