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
const liveControls = {
  counters: {
    counter: '[data-inc="1"]',
    gcounter: '[data-gcounter-inc="1"]',
    pn: '[data-pn-inc="2"]',
  },
  sets: {
    gset: "[data-gset-add]",
    twopset: "[data-twopset-remove]",
    orset: "[data-orset-remove]",
  },
  registers: {
    "lww-register": "[data-lww-register-write]",
    registers: "[data-register-write]",
  },
  maps: {
    map: '[data-step="1"]',
    "lww-map": "[data-lww-map-write]",
    ormap: '[data-ormap-log="2"]',
  },
  coordination: {
    claims: "[data-claim]",
    ordered: "[data-ordered-add]",
    tasks: '[data-key="pump-watch"] [data-task-volunteer]',
    pact: "[data-pact-set]",
  },
};

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
    assert.ok(
      await page.$$eval('link[rel="stylesheet"]', (nodes) =>
        nodes.some((node) => new URL(node.href).pathname === "/styles/home.css")),
      `${slug} loads demo styles`,
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

  for (const [slug, structures] of Object.entries(liveControls)) {
    const { page, errors } = await openPage(browser);
    await page.goto(`${origin}/structures/${slug}/`);
    for (const [id, control] of Object.entries(structures)) {
      await page.click(`[data-structure-toggle="${id}"]`);
      await page.waitForSelector(`#${id}-demo #demo`, { visible: true });
      assert.deepEqual(
        await page.$$eval(`#${id}-demo button`, (buttons) =>
          buttons.filter((button) => button.checkVisibility() && button.disabled)
            .map((button) => button.outerHTML),
        ),
        [],
        `${id} exposes live controls`,
      );
      await page.$eval(`#${id}-demo [data-pace]`, (input) => {
        input.value = "2";
        input.dispatchEvent(new Event("input", { bubbles: true }));
      });
      const before = await page.$eval(
        `#${id}-demo [data-seq-counter]`,
        (node) => node.textContent,
      );
      const commandIsVisible = await page.$$eval(
        `#${id}-demo ${control}`,
        (buttons) => buttons.some((button) => button.checkVisibility()),
      );
      assert.equal(
        commandIsVisible,
        true,
        `${id} command is visible`,
      );
      await page.$$eval(`#${id}-demo ${control}`, (buttons) =>
        buttons.find((candidate) => candidate.checkVisibility()).click(),
      );
      await page.waitForFunction(
        (selector, value) =>
          document.querySelector(selector).textContent !== value,
        {},
        `#${id}-demo [data-seq-counter]`,
        before,
      );
      await page.click(`[data-structure-toggle="${id}"]`);
    }
    assert.deepEqual(errors, [], `${slug} live-control browser errors`);
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
    await page.$eval('#counter-demo [data-inc]', (button) => button.disabled),
    false,
  );
  const counterBefore = await page.$eval(
    '#counter-demo [data-client="a"] [data-counter-value]',
    (node) => node.textContent,
  );
  await page.click('#counter-demo [data-client="a"] [data-inc="1"]');
  await page.waitForFunction(
    (value) =>
      document.querySelector(
        '#counter-demo [data-client="a"] [data-counter-value]',
      ).textContent !== value,
    {},
    counterBefore,
  );
  assert.notEqual(await page.$("#counter-after-demo"), null);
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
  await mapsPage.$eval(
    '#ormap-demo [data-client="a"] [data-ormap-set-input]',
    (input) => {
      input.value = "retained";
      input.dispatchEvent(new Event("input", { bubbles: true }));
    },
  );
  await mapsPage.click(
    '#ormap-demo [data-client="a"] [data-ormap-set-add]',
  );
  await mapsPage.waitForFunction(() =>
    document.querySelector(
      '#ormap-demo [data-client="a"] [data-ormap-members]',
    ).textContent.includes("retained"),
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
  assert.ok(
    await mapsPage.$eval(
      '#ormap-demo [data-client="a"] [data-ormap-members]',
      (node) => node.textContent.includes("retained"),
    ),
    "OR-map set edits survive view switching",
  );
  assert.equal(
    await mapsPage.$eval("#ormap-demo .demo-skip", (link) => link.hash),
    "#ormap-after-demo",
    "OR-map subviews keep the plate skip target",
  );
  assert.deepEqual(mapsErrors, [], "OR-map instance switch browser errors");
  await mapsPage.close();

  const { page: registerPage, errors: registerErrors } = await openPage(browser);
  await registerPage.goto(`${origin}/structures/maps/`);
  await registerPage.click('[data-structure-toggle="lww-map"]');
  await registerPage.waitForSelector(
    '#lww-map-demo [data-client="a"] [data-lww-map-input]',
    { visible: true },
  );
  await registerPage.$eval(
    '#lww-map-demo [data-client="a"] [data-lww-map-key]',
    (input) => {
      input.value = "typed-key";
      input.dispatchEvent(new Event("input", { bubbles: true }));
    },
  );
  await registerPage.$eval(
    '#lww-map-demo [data-client="a"] [data-lww-map-input]',
    (input) => {
      input.value = "typed-value";
      input.dispatchEvent(new Event("input", { bubbles: true }));
    },
  );
  await registerPage.click(
    '#lww-map-demo [data-client="a"] [data-lww-map-write]',
  );
  await registerPage.waitForFunction(() =>
    document.querySelector(
      '#lww-map-demo [data-client="a"] [data-lww-map-entries]',
    ).textContent.includes("typed-key") &&
    document.querySelector(
      '#lww-map-demo [data-client="a"] [data-lww-map-entries]',
    ).textContent.includes("typed-value"),
  );
  assert.deepEqual(registerErrors, [], "typed family input browser errors");
  await registerPage.close();

  console.log(`PASS: ${slugs.join(", ")} structure page static parity.`);
});
