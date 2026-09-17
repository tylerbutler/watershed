import assert from "node:assert/strict";
import { readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { withBrowserSite } from "./site.mjs";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const record = process.argv.includes("--record-baseline");
const site = resolve(root, record ? "../website/dist" : "dist");
const fixture = resolve(root, "test/fixtures/astro-sharedtree-parity.json");

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
      hero: [...document.querySelectorAll(".st-hero p")].map(text),
      blocks: [...document.querySelectorAll(".doc-body > .g-block")].map((block) => ({
        heading: text(block.querySelector("h2")),
        text: text(block),
        links: [...block.querySelectorAll("a")].map((node) => [text(node), node.getAttribute("href")]),
      })),
      snippets: [...document.querySelectorAll(".doc-body .g-code")].map((figure) => ({
        source: text(figure.previousElementSibling),
        caption: text(figure.querySelector("figcaption")),
        code: figure.querySelector("code").textContent.trim(),
      })),
      table: [...document.querySelectorAll(".st-table tr")].map((row) =>
        [...row.children].map(text)),
      guide: text(document.querySelector(".st-guide")),
      guideLinks: links(".st-guide"),
      primary: links('nav[aria-label="Sheet index"]'),
      adjoining: links('nav[aria-labelledby="adjoining-title"]'),
      viewportWidth: innerWidth,
      scrollWidth: document.documentElement.scrollWidth,
      fitsViewport: document.documentElement.scrollWidth <= innerWidth,
      styles: {
        hero: style(".st-hero", ["padding", "border-bottom"]),
        heading: style("h1", ["font-size", "font-weight", "font-stretch", "line-height"]),
        body: style(".doc-body", ["max-width", "padding"]),
        pair: style(".st-pair", ["display", "grid-template-columns", "gap", "width"]),
        code: style(".st-pair .g-code pre", ["font-size", "overflow-x"]),
        table: style(".st-table-scroll", ["overflow-x", "border"]),
        guide: style(".st-guide", ["padding", "border-top", "background-image"]),
      },
    };
  });
}

await withBrowserSite(site, async (browser, origin) => {
  const errors = [];
  const page = await browser.newPage();
  page.on("pageerror", (error) => errors.push(error.message));
  page.on("console", (message) => {
    if (message.type() === "error") errors.push(message.text());
  });
  await page.setRequestInterception(true);
  page.on("request", (request) => {
    if (request.url().startsWith("https://tinylytics.app/")) {
      request.respond({ status: 200, contentType: "text/javascript", body: "" });
    } else request.continue();
  });
  await page.setJavaScriptEnabled(false);
  await page.setViewport({ width: 1440, height: 1000 });
  assert.equal((await page.goto(`${origin}/sharedtree/`)).status(), 200);
  await page.evaluate(() => document.fonts.ready);
  const desktop = await snapshot(page);
  await page.setViewport({ width: 390, height: 844 });
  const mobile = await snapshot(page);
  if (record) {
    assert.deepEqual(errors, [], "baseline browser errors");
    await writeFile(fixture, JSON.stringify({ desktop, mobile }, null, 2) + "\n");
    console.log("Recorded Astro SharedTree parity baseline.");
    return;
  }
  const baseline = JSON.parse(await readFile(fixture, "utf8"));
  assert.deepEqual({ desktop, mobile }, baseline);
  assert.equal(mobile.fitsViewport, true, "mobile overflow");
  assert.equal(await page.$("astro-island, script[src*='_astro'], script[src*='@vite']"), null);
  assert.deepEqual(await page.$$eval('script[type="module"]', (nodes) =>
    nodes.map((node) => new URL(node.src).pathname)), ["/scripts/concept-index.js"]);
  await page.focus(".st-table-scroll");
  assert.notEqual(
    await page.evaluate(() => getComputedStyle(document.activeElement).outlineStyle),
    "none",
  );
  assert.deepEqual(errors, [], "browser errors");
  console.log("PASS: SharedTree Astro parity, mobile layout, and keyboard focus.");
});
