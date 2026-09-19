import assert from "node:assert/strict";
import { openPage, contract, readContract, withBrowserSite, writeContract } from "./site.mjs";

const { record, site, fixture } = contract(import.meta.url, "site-examples-contract.json");

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
      hero: [...document.querySelectorAll(".e-hero p")].map(text),
      actions: links(".e-actions"),
      groups: [...document.querySelectorAll(".e-group")].map((group) => ({
        id: group.querySelector("h2").id,
        title: text(group.querySelector("h2")),
        description: text(group.querySelector(".e-group-head p")),
        entries: [...group.querySelectorAll(".e-entry")].map((entry) => ({
          id: entry.id,
          name: text(entry.querySelector("h3")),
          summary: text(entry.querySelector(".e-entry-head p")),
          source: links(`#${entry.id} .e-entry-head`),
          facts: [...entry.querySelectorAll(".e-facts > div")].map((fact) => ({
            label: text(fact.querySelector("dt")),
            value: text(fact.querySelector("dd")),
            links: links(`#${entry.id} dd`),
          })),
        })),
      })),
      next: text(document.querySelector(".e-next")),
      nextLinks: links(".e-next"),
      primary: links('nav[aria-label="Sheet index"]'),
      adjoining: links('nav[aria-labelledby="adjoining-title"]'),
      viewportWidth: innerWidth,
      scrollWidth: document.documentElement.scrollWidth,
      fitsViewport: document.documentElement.scrollWidth <= innerWidth,
      styles: {
        hero: style(".e-hero", ["padding", "border-bottom"]),
        heading: style("h1", ["font-size", "font-weight", "font-stretch", "line-height"]),
        main: style(".e-main", ["padding", "max-width"]),
        groupHead: style(".e-group-head", ["display", "grid-template-columns", "gap"]),
        entryHead: style(".e-entry-head", ["display", "grid-template-columns", "gap"]),
        facts: style(".e-facts", ["display", "grid-template-columns", "gap"]),
        next: style(".e-next", ["padding", "border-top", "background-color"]),
      },
    };
  });
}

await withBrowserSite(site, async (browser, origin) => {
  const { page, errors } = await openPage(browser);
  await page.setJavaScriptEnabled(false);
  await page.setViewport({ width: 1440, height: 1000 });
  assert.equal((await page.goto(`${origin}/examples/`)).status(), 200);
  await page.evaluate(() => document.fonts.ready);
  const desktop = await snapshot(page);
  await page.setViewport({ width: 390, height: 844 });
  const mobile = await snapshot(page);
  if (record) {
    assert.deepEqual(errors, [], "baseline browser errors");
    await writeContract(fixture, { desktop, mobile });
    console.log("Recorded site examples contract baseline.");
    return;
  }
  const baseline = await readContract(fixture);
  assert.deepEqual({ desktop, mobile }, baseline);
  assert.equal(mobile.fitsViewport, true, "mobile overflow");
  assert.equal(await page.$("script[src*='@vite']"), null);
  assert.deepEqual(await page.$$eval('script[type="module"]', (nodes) =>
    nodes.map((node) => new URL(node.src).pathname)), []);
  await page.focus(".e-source");
  assert.notEqual(
    await page.evaluate(() => getComputedStyle(document.activeElement).outlineStyle),
    "none",
  );
  assert.deepEqual(errors, [], "browser errors");
  console.log("PASS: examples site contract, mobile layout, and keyboard focus.");
});
