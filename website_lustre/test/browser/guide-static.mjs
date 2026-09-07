import assert from "node:assert/strict";
import { readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { withBrowserSite } from "./site.mjs";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const record = process.argv.includes("--record-baseline");
const site = resolve(root, record ? "../website/dist" : "dist");
const routes = [
  { slug: "connect", anchor: "ffi-surface" },
  { slug: "notes", anchor: "authoritative-channel" },
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
      headings: [...document.querySelectorAll("main h2, main h3")].map(text),
      prose: [...document.querySelectorAll("main .g-block > p, main > .fnr, main .g-note > p, main > .g-out > p")]
        .map(text)
        .filter(Boolean),
      links: links("main"),
      guide: links('nav[aria-label="Guide steps"]'),
      labels: [...document.querySelectorAll("main .g-file")].map(text),
      captions: [...document.querySelectorAll("main figcaption")].map(text),
      code: [...document.querySelectorAll("main pre code")]
        .map((node) => node.textContent.replace(/\n$/, "")),
      notes: [...document.querySelectorAll("details.fn-note")].map((node) => ({
        id: node.id,
        summary: text(node.querySelector("summary")),
        body: text(node.querySelector(".fn-body")),
      })),
      fitsViewport: document.documentElement.scrollWidth <= innerWidth,
      styles: {
        hero: style(".g-hero", ["padding", "border-bottom"]),
        prose: style(".doc-body p", ["font-size", "line-height", "color"]),
        code: style(".g-code pre", ["padding", "border", "font-size", "line-height"]),
        reference: style(".fnr", ["display", "padding", "border-left", "background-color"]),
        note: style(".fn-note", ["border-top", "scroll-margin-top"]),
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
    await page.setViewport({ width: 1440, height: 1000 });
    assert.equal((await page.goto(`${origin}/guide/${route.slug}/`)).status(), 200);
    await page.evaluate(() => document.fonts.ready);
    const desktop = await snapshot(page);
    await page.setViewport({ width: 390, height: 844 });
    const mobile = await snapshot(page);
    const fixture = resolve(root, `test/fixtures/astro-guide-${route.slug}-parity.json`);
    if (record) {
      await writeFile(fixture, JSON.stringify({ desktop, mobile }, null, 2) + "\n");
      await page.close();
      continue;
    }
    const baseline = JSON.parse(await readFile(fixture, "utf8"));
    assert.deepEqual({ desktop, mobile }, baseline);
    assert.equal(await page.$("astro-island, script[src*='_astro'], script[src*='@vite']"), null);
    assert.deepEqual(
      await page.$$eval('script[type="module"]', (nodes) => nodes.map((node) => new URL(node.src).pathname)),
      ["/scripts/field-notes.js"],
    );
    await page.setViewport({ width: 1440, height: 1000 });
    await page.goto(`${origin}/guide/${route.slug}/#${route.anchor}`);
    assert.equal(await page.$eval(`#${route.anchor}`, (node) => node.open), true);
    assert.deepEqual(errors, []);
    await page.close();
  }
  console.log(`PASS: ${routes.map(({ slug }) => slug).join(", ")} guide parity and field-note fragments.`);
});
