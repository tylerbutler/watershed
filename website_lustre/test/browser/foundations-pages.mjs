import assert from "node:assert/strict";
import { readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { withBrowserSite } from "./site.mjs";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const record = process.argv.includes("--record-baseline");
const site = resolve(root, record ? "../website/dist" : "dist");
const routes = [
  { slug: "schema", anchor: "stamp-schema" },
  { slug: "topology", anchor: "typedmap-panels" },
  { slug: "lifecycle", anchor: "ffi-surface" },
];

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
      hero: [...document.querySelectorAll(".fd-hero p, .fd-hero span")].map(text),
      headings: [...document.querySelectorAll("main h2, main h3")].map(text),
      prose: [...document.querySelectorAll("main .g-block > p, main .g-note > p, main > .g-out > p")]
        .map(text)
        .filter(Boolean),
      links: links("main"),
      pager: links('nav[aria-label="Foundations sheets"]'),
      labels: [...document.querySelectorAll("main .g-file")].map(text),
      captions: [...document.querySelectorAll("main figcaption")].map(text),
      code: [...document.querySelectorAll("main pre code")]
        .map((node) => node.textContent.replace(/\n$/, "")),
      notes: [...document.querySelectorAll(".rfn-list > li")].map((node) => ({
        title: text(node.querySelector("a")),
        href: node.querySelector("a").getAttribute("href"),
        rule: text(node.querySelector("p")),
        example: text(node.querySelector(".annot")),
      })),
      fitsViewport: document.documentElement.scrollWidth <= innerWidth,
      styles: {
        hero: style(".fd-hero", ["padding", "border-bottom"]),
        heading: style(".fd-hero h1", ["font-size", "font-weight", "font-stretch", "line-height"]),
        scope: style(".fd-scope", ["display", "padding", "border", "color"]),
        prose: style(".doc-body p", ["font-size", "line-height", "color"]),
        code: style(".g-code pre", ["padding", "border", "font-size", "line-height"]),
        pager: style(".fd-pager", ["display", "grid-template-columns", "gap", "padding"]),
        related: style(".rfn", ["border-top", "background-color"]),
      },
    };
  });
}

await withBrowserSite(site, async (browser, origin) => {
  for (const route of routes) {
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
    assert.equal((await page.goto(`${origin}/foundations/${route.slug}/`)).status(), 200);
    await page.evaluate(() => document.fonts.ready);
    const desktop = await snapshot(page);
    await page.setViewport({ width: 390, height: 844 });
    const mobile = await snapshot(page);
    const fixture = resolve(root, `test/fixtures/astro-foundations-${route.slug}-parity.json`);
    if (record) {
      await writeFile(fixture, JSON.stringify({ desktop, mobile }, null, 2) + "\n");
      await page.close();
      continue;
    }
    const baseline = JSON.parse(await readFile(fixture, "utf8"));
    assert.deepEqual({ desktop, mobile }, baseline);
    assert.equal(mobile.fitsViewport, true, `${route.slug} fits the mobile viewport`);
    assert.equal(await page.$("astro-island, script[src*='_astro'], script[src*='@vite']"), null);
    assert.deepEqual(
      await page.$$eval('script[type="module"]', (nodes) => nodes.map((node) => new URL(node.src).pathname)),
      [],
    );
    assert.deepEqual(await page.$$eval("[aria-labelledby]", (nodes) =>
      nodes.flatMap((node) => node.getAttribute("aria-labelledby").split(/\s+/))
        .filter((id) => !document.getElementById(id))), []);
    await page.focus('nav[aria-label="Foundations sheets"] a');
    assert.notEqual(await page.evaluate(() => getComputedStyle(document.activeElement).outlineStyle), "none");
    await page.setJavaScriptEnabled(true);
    await page.goto(`${origin}/guide/${route.anchor === "stamp-schema" ? "notes" : "connect"}/#${route.anchor}`);
    assert.equal(
      await page.$eval(`#${route.anchor}`, (node) => node.open),
      true,
      `${route.slug} related field note opens from its fragment`,
    );
    assert.deepEqual(errors, []);
    await page.close();
  }
  console.log(`PASS: ${routes.map(({ slug }) => slug).join(", ")} foundations page parity.`);
});
