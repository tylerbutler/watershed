import assert from "node:assert/strict";
import { readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { withBrowserSite } from "./site.mjs";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const record = process.argv.includes("--record-baseline");
const site = resolve(root, record ? "../website/dist" : "dist");
const fixture = resolve(root, "test/fixtures/astro-guide-index-parity.json");
const selector = (id) => `[data-testid="${id}"]`;

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
    } else {
      request.continue();
    }
  });
  await page.setJavaScriptEnabled(false);
  await page.setViewport({ width: 1440, height: 1000 });
  assert.equal((await page.goto(`${origin}/guide/`)).status(), 200);
  await page.evaluate(() => document.fonts.ready);
  if (record) {
    await page.evaluate(() => {
      const nodes = {
        "guide-intro": ".gi-hero",
        "guide-lede": ".lede",
        "guide-start": ".cta-primary",
        "guide-build": ".gi-build",
        "guide-build-grid": ".gi-build-inner",
        "guide-document": ".gi-doc",
        "guide-procedure": ".gi-ledger",
        "guide-steps": ".gi-steps",
        "guide-companion": ".gi-companion",
      };
      for (const [id, selector] of Object.entries(nodes)) {
        document.querySelector(selector).dataset.testid = id;
      }
    });
  }
  const content = await page.evaluate(() => {
    const text = (node) => node.textContent.replace(/\s+/g, " ").trim();
    const links = (selector) => [...document.querySelectorAll(`${selector} a`)].map((node) => ({
      text: text(node), href: node.getAttribute("href"), current: node.getAttribute("aria-current"),
    }));
    return {
      title: document.title,
      metadata: [...document.head.querySelectorAll("meta[name], meta[property]")].map((node) => [
        node.getAttribute("name") || node.getAttribute("property"), node.content,
      ]),
      heading: document.querySelector("h1").innerText.replace(/\s+/g, " ").trim(),
      headingBreaks: document.querySelectorAll("h1 br").length,
      headings: [...document.querySelectorAll("main h2")].map(text),
      prose: [...document.querySelectorAll('[data-testid="guide-intro"] p, main p')].map(text),
      diagram: [...document.querySelectorAll('[data-testid="guide-document"] span')].map(text),
      steps: [...document.querySelectorAll('[data-testid="guide-steps"] > li > a')].map((link) => ({
        href: link.getAttribute("href"),
        number: text(link.children[0]),
        fields: [...link.children[1].children].map(text),
      })),
      actions: links('[data-testid="guide-intro"]'),
      bodyLinks: links("main"),
      primary: links('nav[aria-label="Sheet index"]'),
      adjoining: links('nav[aria-labelledby="adjoining-title"]'),
      canonical: document.querySelector('link[rel="canonical"]')?.href || null,
    };
  });
  const collectStyles = () => page.evaluate(() => {
    const style = (selector, properties) => {
      const computed = getComputedStyle(document.querySelector(selector));
      return Object.fromEntries(properties.map((key) => [key, computed.getPropertyValue(key)]));
    };
    return {
      hero: style('[data-testid="guide-intro"]', ["padding", "border-bottom"]),
      heading: style("h1", ["font-size", "font-weight", "font-stretch", "line-height", "letter-spacing"]),
      lede: style('[data-testid="guide-lede"]', ["font-size", "line-height", "max-width", "margin-top"]),
      start: style('[data-testid="guide-start"]', ["padding", "background-color", "color", "font-weight"]),
      grid: style('[data-testid="guide-build-grid"]', ["display", "grid-template-columns", "gap"]),
      diagram: style('[data-testid="guide-document"]', ["border", "background-color"]),
      ledger: style('[data-testid="guide-procedure"]', ["padding", "max-width"]),
      step: style('[data-testid="guide-steps"] > li > a', ["display", "grid-template-columns", "gap", "padding"]),
      surface: style('[data-testid="guide-steps"] > li > a > span:nth-child(2) > span:last-child', ["display", "font-size", "color"]),
      companion: style('[data-testid="guide-companion"]', ["padding", "background-color"]),
    };
  });
  const desktop = await collectStyles();
  await page.focus(`${selector("guide-steps")} a`);
  const focus = await page.$eval(`${selector("guide-steps")} a`, (node) => {
    const style = getComputedStyle(node);
    return { outline: style.outline, offset: style.outlineOffset };
  });
  await page.setViewport({ width: 390, height: 844 });
  const mobile = await collectStyles();
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true, "mobile overflow");
  if (record) {
    assert.deepEqual(errors, [], "baseline browser errors");
    await writeFile(fixture, JSON.stringify({ content, desktop, mobile, focus }, null, 2) + "\n");
    console.log("Recorded Astro guide index parity baseline.");
    return;
  }
  const baseline = JSON.parse(await readFile(fixture, "utf8"));
  assert.deepEqual(content, baseline.content, "static copy, metadata, diagram, and navigation");
  assert.deepEqual(desktop, baseline.desktop, "desktop styles");
  assert.deepEqual(mobile, baseline.mobile, "mobile styles");
  assert.deepEqual(focus, baseline.focus, "keyboard focus");
  assert.equal(await page.$("astro-island, script[src*='_astro'], script[src*='@vite']"), null);
  assert.deepEqual(await page.$$eval('script[type="module"]', (nodes) => nodes.map((node) => new URL(node.src).pathname)), ["/scripts/guide-index.js"]);
  assert.equal(await page.$$eval(`${selector("guide-steps")} > li`, (nodes) =>
    nodes.length === 6 && nodes.every((node) => node.checkVisibility())), true, "all steps work without JavaScript");
  assert.deepEqual(await page.$$eval("[aria-labelledby]", (nodes) =>
    nodes.flatMap((node) => node.getAttribute("aria-labelledby").split(/\s+/)).filter((id) => !document.getElementById(id))), [], "accessible headings resolve");
  await page.focus(`${selector("guide-steps")} a[href="/guide/notes"]`);
  await page.keyboard.press("Tab");
  assert.equal(await page.evaluate(() => document.activeElement.getAttribute("href")), "/guide/race");
  await page.keyboard.press("Enter");
  await page.waitForSelector(selector("race-demo"));
  assert.equal(new URL(page.url()).pathname, "/guide/race");
  await page.click('a[href="/guide"]');
  await page.waitForSelector(selector("guide-steps"));
  await page.setJavaScriptEnabled(true);
  await page.setViewport({ width: 1440, height: 1000 });
  await page.emulateMediaFeatures([{ name: "prefers-reduced-motion", value: "no-preference" }]);
  await page.reload();
  await page.waitForFunction(() =>
    document.querySelector('[data-testid="guide-steps"] > li')?.dataset.revealIndex === "0");
  await page.evaluate(() => {
    window.revealCount = 0;
    const animate = Element.prototype.animate;
    Element.prototype.animate = function (...args) {
      if (this.hasAttribute("data-reveal")) window.revealCount++;
      return animate.apply(this, args);
    };
    document.querySelector('[data-testid="guide-steps"]').scrollIntoView({ behavior: "instant" });
  });
  await page.waitForFunction(() => window.revealCount > 0);
  await page.emulateMediaFeatures([{ name: "prefers-reduced-motion", value: "reduce" }]);
  await page.reload();
  assert.equal(await page.$$eval("[data-reveal-index]", (nodes) => nodes.length), 0, "reduced motion does not arm reveals");
  assert.equal(await page.$$eval(`${selector("guide-steps")} > li`, (nodes) =>
    nodes.every((node) => node.checkVisibility())), true);
  assert.deepEqual(errors, [], "browser errors");
  console.log("PASS: guide index static content, Astro parity, navigation, focus, and reveal motion.");
});
