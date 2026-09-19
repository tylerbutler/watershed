import assert from "node:assert/strict";
import { resolve } from "node:path";
import { openPage, contract, readContract, withBrowserSite, writeContract } from "./site.mjs";

const { root, record, site } = contract(import.meta.url);
const routes = ["optimistic", "reconnect", "redelivery", "presence", "p2p"];

async function snapshot(page) {
  return page.evaluate(() => {
    const text = (node) => (node.innerText ?? node.textContent).replace(/\s+/g, " ").trim();
    const links = (selector) => [...document.querySelectorAll(`${selector} a`)]
      .map((node) => [text(node), node.getAttribute("href")]);
    const style = (selector, properties) => {
      const node = document.querySelector(selector);
      if (!node) return null;
      const computed = getComputedStyle(node);
      return Object.fromEntries(properties.map((key) => [key, computed.getPropertyValue(key)]));
    };
    return {
      title: document.title,
      metadata: [...document.head.querySelectorAll("meta[name], meta[property]")]
        .map((node) => [node.getAttribute("name") || node.getAttribute("property"), node.content]),
      heading: text(document.querySelector("h1")),
      hero: [...document.querySelectorAll(".r-hero p, .r-hero span")].map(text),
      headings: [...document.querySelectorAll("main h2, main h3")].map(text),
      prose: [...document.querySelectorAll("main .g-block > p, main .g-note > p, main > .g-out > p")]
        .map(text)
        .filter(Boolean),
      links: links("main"),
      pager: links('nav[aria-label="Runtime sheets"]'),
      labels: [...document.querySelectorAll("main .g-file")].map(text),
      captions: [...document.querySelectorAll("main figcaption")].map(text),
      code: [...document.querySelectorAll("main pre code")]
        .map((node) => node.textContent.replace(/\n$/, "")),
      ...(document.querySelector("main .g-block > p strong > code") ? {
        inlineCode: [...document.querySelectorAll("main .g-block > p strong > code")]
          .map((node) => {
            const computed = getComputedStyle(node);
            return {
              text: text(node),
              style: Object.fromEntries(
                ["font-family", "font-size", "font-weight", "color"]
                  .map((key) => [key, computed.getPropertyValue(key)]),
              ),
            };
          }),
      } : {}),
      ...(document.querySelector(".oplog") ? {
        oplog: {
          label: document.querySelector(".oplog").getAttribute("aria-label"),
          lines: [...document.querySelectorAll(".oplog-line")].map(text),
          style: style(".oplog", ["border", "background-color", "font-family", "font-size"]),
          duplicate: style(".oplog-dupe .oplog-op", ["color", "font-style"]),
        },
      } : {}),
      fitsViewport: document.documentElement.scrollWidth <= innerWidth,
      styles: {
        hero: style(".r-hero", ["padding", "border-bottom"]),
        heading: style(".r-hero h1", ["font-size", "font-weight", "font-stretch", "line-height"]),
        prose: style(".doc-body p", ["font-size", "line-height", "color"]),
        code: style(".g-code pre", ["padding", "border", "font-size", "line-height"]),
        pager: style(".r-pager", ["display", "grid-template-columns", "gap", "padding"]),
      },
    };
  });
}

await withBrowserSite(site, async (browser, origin) => {
  for (const slug of routes) {
    const { page, errors } = await openPage(browser);
    await page.setJavaScriptEnabled(false);
    await page.setViewport({ width: 1440, height: 1000 });
    assert.equal((await page.goto(`${origin}/runtime/${slug}/`)).status(), 200);
    await page.evaluate(() => document.fonts.ready);
    const desktop = await snapshot(page);
    await page.setViewport({ width: 390, height: 844 });
    const mobile = await snapshot(page);
    const fixture = resolve(root, `test/fixtures/site-runtime-${slug}-contract.json`);
    if (record) {
      assert.deepEqual(errors, [], `${slug} baseline browser errors`);
      await writeContract(fixture, { desktop, mobile });
      await page.close();
      continue;
    }
    const baseline = await readContract(fixture);
    assert.deepEqual({ desktop, mobile }, baseline);
    assert.equal(mobile.fitsViewport, true, `${slug} fits the mobile viewport`);
    assert.equal(await page.$("script[src*='@vite']"), null);
    assert.deepEqual(
      await page.$$eval('script[type="module"]', (nodes) => nodes.map((node) => new URL(node.src).pathname)),
      [],
    );
    assert.deepEqual(await page.$$eval("[aria-labelledby]", (nodes) =>
      nodes.flatMap((node) => node.getAttribute("aria-labelledby").split(/\s+/))
        .filter((id) => !document.getElementById(id))), []);
    await page.focus('nav[aria-label="Runtime sheets"] a');
    assert.notEqual(await page.evaluate(() => getComputedStyle(document.activeElement).outlineStyle), "none");
    assert.deepEqual(errors, [], `${slug} browser errors`);
    await page.close();
  }
  console.log(`PASS: ${routes.join(", ")} runtime page contract.`);
});
