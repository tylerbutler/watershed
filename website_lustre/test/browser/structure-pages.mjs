import assert from "node:assert/strict";
import { resolve } from "node:path";
import { openPage, parity, readParity, withBrowserSite, writeParity } from "./site.mjs";

const { root, record, site } = parity(import.meta.url);
const slugs = [
  "counters",
  "sets",
  "registers",
  "maps",
  "sequences",
  "coordination",
  "transforms",
];

async function snapshot(page) {
  return page.evaluate(() => {
    const text = (node) => (node.innerText ?? node.textContent).replace(/\s+/g, " ").trim();
    const links = (selector) => [...document.querySelectorAll(`${selector} a`)]
      .filter((node) => node.checkVisibility())
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
      hero: [...document.querySelectorAll(".cat-hero p, .cat-index")].map(text),
      jump: links(".jump"),
      plates: [...document.querySelectorAll(".plate")].map((plate) => ({
        id: plate.id,
        number: text(plate.querySelector(".plate-mark")),
        title: text(plate.querySelector("h2")),
        kind: text(plate.querySelector(".stamp")),
        module: text(plate.querySelector(".plate-module")),
        tagline: text(plate.querySelector(".plate-tagline")),
        prose: [...plate.querySelectorAll(".plate-prose > p")].map(text),
        uses: [...plate.querySelectorAll(".uses li")].map(text),
        spec: [...plate.querySelectorAll(".spec > div")].map((row) => [
          text(row.querySelector("dt")),
          text(row.querySelector("dd")),
        ]),
        links: links(`#${plate.id}`),
      })),
      notes: [...document.querySelectorAll(".rfn-list > li")].map((node) => ({
        title: text(node.querySelector("a")),
        href: node.querySelector("a").getAttribute("href"),
        rule: text(node.querySelector("p")),
        example: text(node.querySelector(".annot")),
      })),
      pager: links('nav[aria-label="More on data structures"]'),
      primary: links('nav[aria-label="Sheet index"]'),
      adjoining: links('nav[aria-labelledby="adjoining-title"]'),
      fitsViewport: document.documentElement.scrollWidth <= innerWidth,
      styles: {
        hero: style(".cat-hero", ["padding", "border-bottom", "background-image"]),
        heading: style("h1", ["font-size", "font-weight", "font-stretch", "line-height"]),
        jump: style(".jump a", ["display", "padding", "border"]),
        plate: style(".plate", ["padding", "border", "background-color"]),
        body: style(".plate-body", ["display", "grid-template-columns", "gap"]),
        spec: style(".spec", ["border", "background-color"]),
        pager: style(".cat-nav", ["display", "grid-template-columns", "gap"]),
      },
    };
  });
}

await withBrowserSite(site, async (browser, origin) => {
  for (const slug of slugs) {
    const { page, errors } = await openPage(browser);
    await page.setJavaScriptEnabled(false);
    await page.setViewport({ width: 1440, height: 1000 });
    assert.equal((await page.goto(`${origin}/structures/${slug}/`)).status(), 200);
    await page.evaluate(() => document.fonts.ready);
    const desktop = await snapshot(page);
    await page.setViewport({ width: 390, height: 844 });
    const mobile = await snapshot(page);
    const fixture = resolve(root, `test/fixtures/astro-structures-${slug}-parity.json`);
    if (record) {
      assert.deepEqual(errors, [], `${slug} baseline browser errors`);
      await writeParity(fixture, { desktop, mobile });
      await page.close();
      continue;
    }
    const baseline = await readParity(fixture);
    assert.deepEqual({ desktop, mobile }, baseline);
    assert.equal(mobile.fitsViewport, true, `${slug} fits the mobile viewport`);
    assert.equal(await page.$("astro-island, script[src*='_astro'], script[src*='@vite']"), null);
    assert.deepEqual(
      await page.$$eval('script[type="module"]', (nodes) => nodes.map((node) => new URL(node.src).pathname)),
      ["/structure_sheet.js"],
    );
    assert.deepEqual(await page.$$eval("[aria-labelledby]", (nodes) =>
      nodes.flatMap((node) => node.getAttribute("aria-labelledby").split(/\s+/))
        .filter((id) => !document.getElementById(id))), []);
    await page.focus(".jump a");
    assert.notEqual(
      await page.evaluate(() => getComputedStyle(document.activeElement).outlineStyle),
      "none",
    );
    assert.deepEqual(errors, [], `${slug} browser errors`);
    await page.close();
  }

  const { page, errors } = await openPage(browser);
  await page.goto(`${origin}/structures/counters/`);
  await page.waitForSelector('[data-structure-toggle="counter"]', {
    visible: true,
  });
  await page.click('[data-structure-toggle="counter"]');
  await page.waitForSelector('#counter-demo #demo', { visible: true });
  assert.equal(
    await page.$eval('#counter-demo [data-step]', (button) => button.disabled),
    false,
  );
  assert.deepEqual(
    await page.$$eval(
      '#counter-demo [data-client="a"] > :is(table, .counter-panel, .mv-register-panel)',
      (nodes) => nodes.filter((node) => node.checkVisibility()).map((node) => node.className),
    ),
    ["counter-panel dds-counter"],
  );
  assert.deepEqual(errors, [], "counter demo browser errors");
  await page.close();

  const { page: mapsPage, errors: mapsErrors } = await openPage(browser);
  await mapsPage.goto(`${origin}/structures/maps/`);
  await mapsPage.waitForSelector('[data-structure-toggle="ormap"]', {
    visible: true,
  });
  await mapsPage.click('[data-structure-toggle="ormap"]');
  await mapsPage.waitForSelector('#ormap-demo [data-ormap-view]', {
    visible: true,
  });
  assert.equal(
    await mapsPage.$eval('#ormap-demo [data-ormap-view]', (select) => select.disabled),
    false,
  );
  await mapsPage.select('#ormap-demo [data-ormap-mode]', "set");
  await mapsPage.waitForSelector(
    '#ormap-demo [data-client="a"] .ormap-set-panel',
    { visible: true },
  );
  await mapsPage.select(
    '#ormap-demo [data-ormap-view]',
    "or-map-mv-register",
  );
  await mapsPage.waitForSelector(
    '#ormap-demo [data-client="a"] .dds-or-map-mv-register',
    { visible: true },
  );
  await mapsPage.select('#ormap-demo [data-ormap-view]', "ormap");
  assert.equal(
    await mapsPage.$eval('#ormap-demo [data-ormap-mode]', (select) => select.value),
    "set",
  );
  await mapsPage.waitForSelector(
    '#ormap-demo [data-client="a"] .ormap-set-panel',
    { visible: true },
  );
  assert.deepEqual(mapsErrors, [], "OR-map instance switch browser errors");
  await mapsPage.close();

  console.log(`PASS: ${slugs.join(", ")} structure page static parity.`);
});
