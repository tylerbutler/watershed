import assert from "node:assert/strict";
import { openPage, contract, readContract, withBrowserSite, writeContract } from "./site.mjs";

const { record, site, fixture } = contract(import.meta.url, "site-foundations-index-contract.json");
const selector = (id) => `[data-testid="${id}"]`;

await withBrowserSite(site, async (browser, origin) => {
  const { page, errors } = await openPage(browser);
  await page.setJavaScriptEnabled(false);
  await page.setViewport({ width: 1440, height: 1000 });
  assert.equal((await page.goto(`${origin}/foundations/`)).status(), 200);
  await page.evaluate(() => document.fonts.ready);
  const content = await page.evaluate(() => {
    const text = (node) => node.textContent.replace(/\s+/g, " ").trim();
    const links = (nodeSelector) => [...document.querySelectorAll(`${nodeSelector} a`)].map((node) => ({
      text: text(node),
      href: node.getAttribute("href"),
      current: node.getAttribute("aria-current"),
    }));
    return {
      title: document.title,
      metadata: [...document.head.querySelectorAll("meta[name], meta[property]")].map((node) => [
        node.getAttribute("name") || node.getAttribute("property"),
        node.content,
      ]),
      heading: text(document.querySelector("h1")),
      headingBreaks: document.querySelectorAll("h1 br").length,
      headings: [...document.querySelectorAll("main h2")].map(text),
      prose: [...document.querySelectorAll('[data-testid="foundations-intro"] p, main p')].map(text),
      entries: [...document.querySelectorAll('[data-testid="foundations-list"] > li > a')].map((link) => ({
        href: link.getAttribute("href"),
        number: text(link.children[0]),
        fields: [...link.children[1].children].map(text),
      })),
      primary: links('nav[aria-label="Sheet index"]'),
      adjoining: links('nav[aria-labelledby="adjoining-title"]'),
      canonical: document.querySelector('link[rel="canonical"]')?.href || null,
    };
  });
  const collectStyles = () => page.evaluate(() => {
    const style = (nodeSelector, properties) => {
      const computed = getComputedStyle(document.querySelector(nodeSelector));
      return Object.fromEntries(properties.map((key) => [key, computed.getPropertyValue(key)]));
    };
    return {
      hero: style('[data-testid="foundations-intro"]', ["padding", "border-bottom"]),
      heading: style("h1", ["font-size", "font-weight", "font-stretch", "line-height", "letter-spacing"]),
      lede: style('[data-testid="foundations-intro"] .lede', ["font-size", "line-height", "max-width", "margin-top"]),
      ledger: style('[data-testid="foundations-ledger"]', ["padding", "max-width"]),
      item: style('[data-testid="foundations-list"] > li > a', ["display", "grid-template-columns", "gap", "padding"]),
      concept: style('[data-testid="foundations-list"] > li > a > span:nth-child(2) > span:last-child', ["display", "font-size", "color"]),
      aside: style(".fh-aside", ["margin-top", "padding-top", "border-top", "max-width"]),
    };
  });
  const desktop = await collectStyles();
  await page.focus(`${selector("foundations-list")} a`);
  const focus = await page.$eval(`${selector("foundations-list")} a`, (node) => {
    const style = getComputedStyle(node);
    return { outline: style.outline, offset: style.outlineOffset };
  });
  await page.setViewport({ width: 390, height: 844 });
  const mobile = await collectStyles();
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true, "mobile overflow");
  if (record) {
    assert.deepEqual(errors, [], "baseline browser errors");
    await writeContract(fixture, { content, desktop, mobile, focus });
    console.log("Recorded site foundations index contract baseline.");
    return;
  }
  const baseline = await readContract(fixture);
  assert.deepEqual(content, baseline.content, "static copy, metadata, catalog, and navigation");
  assert.deepEqual(desktop, baseline.desktop, "desktop styles");
  assert.deepEqual(mobile, baseline.mobile, "mobile styles");
  assert.deepEqual(focus, baseline.focus, "keyboard focus");
  assert.equal(await page.$("script[src*='@vite']"), null);
  assert.deepEqual(await page.$$eval('script[type="module"]', (nodes) => nodes.map((node) => new URL(node.src).pathname)), ["/scripts/concept-index.js"]);
  assert.equal(await page.$$eval(`${selector("foundations-list")} > li`, (nodes) =>
    nodes.length === 3 && nodes.every((node) => node.checkVisibility())), true, "all entries work without JavaScript");
  assert.deepEqual(await page.$$eval("[aria-labelledby]", (nodes) =>
    nodes.flatMap((node) => node.getAttribute("aria-labelledby").split(/\s+/)).filter((id) => !document.getElementById(id))), [], "accessible headings resolve");
  await page.focus(`${selector("foundations-list")} a`);
  await page.keyboard.press("Tab");
  assert.equal(await page.evaluate(() => document.activeElement.getAttribute("href")), "/foundations/topology");
  await page.setJavaScriptEnabled(true);
  await page.setViewport({ width: 1440, height: 1000 });
  await page.emulateMediaFeatures([{ name: "prefers-reduced-motion", value: "no-preference" }]);
  await page.reload();
  await page.waitForFunction(() =>
    document.querySelector('[data-testid="foundations-list"] > li')?.dataset.revealIndex === "0");
  await page.evaluate(() => {
    window.revealCount = 0;
    const animate = Element.prototype.animate;
    Element.prototype.animate = function (...args) {
      if (this.hasAttribute("data-reveal")) window.revealCount++;
      return animate.apply(this, args);
    };
    document.querySelector('[data-testid="foundations-list"]').scrollIntoView({ behavior: "instant" });
  });
  await page.waitForFunction(() => window.revealCount > 0);
  await page.emulateMediaFeatures([{ name: "prefers-reduced-motion", value: "reduce" }]);
  await page.reload();
  assert.equal(await page.$$eval("[data-reveal-index]", (nodes) => nodes.length), 0, "reduced motion does not arm reveals");
  assert.equal(await page.$$eval(`${selector("foundations-list")} > li`, (nodes) =>
    nodes.every((node) => node.checkVisibility())), true);
  assert.deepEqual(errors, [], "browser errors");
  console.log("PASS: foundations index site contract, navigation, focus, and reveal motion.");
});
