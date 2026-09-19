import assert from "node:assert/strict";
import { resolve } from "node:path";
import { openPage, contract, readContract, withBrowserSite, writeContract } from "./site.mjs";

const { root, record, site } = contract(import.meta.url);
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
    const fontResponses = [];
    page.on("response", (response) => {
      if (new URL(response.url()).pathname.startsWith("/fonts/")) {
        fontResponses.push([new URL(response.url()).pathname, response.status()]);
      }
    });
    await page.setJavaScriptEnabled(false);
    await page.setViewport({ width: 1280, height: 800 });
    assert.equal((await page.goto(`${origin}/structures/${slug}/`)).status(), 200);
    await page.evaluate(() => document.fonts.ready);
    assert.equal(
      await page.evaluate(() => document.documentElement.scrollWidth),
      1280,
      `${slug} fits the 1280px viewport`,
    );
    if (slug === "maps") {
      assert.ok(fontResponses.length > 0, "maps loads local font assets");
      assert.deepEqual(
        fontResponses.filter(([, status]) => status !== 200),
        [],
        "every maps font response succeeds",
      );
    }
    await page.setViewport({ width: 1440, height: 1000 });
    const desktop = await snapshot(page);
    await page.setViewport({ width: 390, height: 844 });
    const mobile = await snapshot(page);
    const fixture = resolve(root, `test/fixtures/site-structures-${slug}-contract.json`);
    if (record) {
      assert.deepEqual(errors, [], `${slug} baseline browser errors`);
      await writeContract(fixture, { desktop, mobile });
      await page.close();
      continue;
    }
    const baseline = await readContract(fixture);
    assert.equal(
      desktop.styles.pager["grid-template-columns"].split(/\s+/).length,
      3,
      `${slug} uses three desktop pager columns`,
    );
    assert.equal(
      mobile.styles.pager["grid-template-columns"].split(/\s+/).length,
      1,
      `${slug} uses one mobile pager column`,
    );
    desktop.styles.pager["grid-template-columns"] =
      baseline.desktop.styles.pager["grid-template-columns"];
    mobile.styles.pager["grid-template-columns"] =
      baseline.mobile.styles.pager["grid-template-columns"];
    assert.deepEqual({ desktop, mobile }, baseline);
    assert.equal(
      await page.evaluate(() => document.documentElement.scrollWidth),
      390,
      `${slug} fits the 390px viewport`,
    );
    if (slug === "maps") {
      assert.ok(
        Number.parseFloat(mobile.styles.heading["font-size"]) >= 36,
        "Maps heading stays at least 36px wide on mobile",
      );
    }
    assert.deepEqual(
      await page.$$eval("pre", (nodes) =>
        nodes
          .filter((node) => node.scrollWidth > node.clientWidth)
          .map((node) => node.getAttribute("tabindex")),
      ),
      await page.$$eval("pre", (nodes) =>
        nodes
          .filter((node) => node.scrollWidth > node.clientWidth)
          .map(() => "0"),
      ),
      `${slug} scrollable code is keyboard focusable`,
    );
    assert.equal(await page.$("script[src*='@vite']"), null);
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
    await page.setViewport({
      width: 390,
      height: 844,
      hasTouch: true,
      isMobile: true,
    });
    await page.goto(`${origin}/structures/${slug}/`);
    for (const [id, control] of Object.entries(structures)) {
      await page.click(`[data-structure-toggle="${id}"]`);
      await page.waitForSelector(`#${id}-demo #demo`, { visible: true });
      assert.deepEqual(
        await page.$$eval(`#${id}-demo button`, (buttons) =>
          buttons
            .filter((button) => button.checkVisibility())
            .filter((button) => {
              const rect = button.getBoundingClientRect();
              return rect.width < 44 || rect.height < 44;
            })
            .map((button) => button.outerHTML),
        ),
        [],
        `${id} visible controls have 44px touch targets`,
      );
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
      const raceBefore = await page.$eval(
        `#${id}-demo [data-seq-counter]`,
        (node) => node.textContent,
      );
      await page.click(`#${id}-demo [data-race]`);
      await page.waitForFunction(
        (selector, value) =>
          document.querySelector(selector).textContent !== value,
        {},
        `#${id}-demo [data-seq-counter]`,
        raceBefore,
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

  for (const [slug, id] of [["counters", "counter"], ["coordination", "pact"]]) {
    const { page: offline, errors: offlineErrors } = await openPage(browser);
    await offline.goto(`${origin}/structures/${slug}/`);
    await offline.waitForSelector("#structure-sheet-mount[data-lustre-mounted]");
    await offline.click(`[data-structure-toggle="${id}"]`);
    const root = `#${id}-demo`;
    await offline.waitForSelector(`${root} #demo[data-mounted]`);
    await offline.click(`${root} [data-cut-link]`);
    await offline.waitForSelector(`${root} [data-cut-link][aria-pressed="true"]`);
    if (id === "counter") {
      await offline.click(`${root} [data-client="b"] [data-inc="5"]`);
      await offline.waitForFunction(() =>
        document.querySelector('#counter-demo [data-client="b"] [data-counter-value]').textContent === "125",
      );
      assert.deepEqual(await offline.$$eval(`${root} [data-counter-value]`, (nodes) =>
        nodes.map((node) => node.textContent)), ["120", "125", "120"]);
      await offline.click(`${root} [data-client="a"] [data-inc="1"]`);
      await offline.waitForFunction(() =>
        document.querySelector('#counter-demo [data-client="c"] [data-counter-value]').textContent === "121",
      );
      assert.deepEqual(await offline.$$eval(`${root} [data-counter-value]`, (nodes) =>
        nodes.map((node) => node.textContent)), ["121", "125", "121"]);
    } else {
      await offline.click(`${root} [data-client="b"] [data-key="gate-policy"] [data-pact-set]`);
      await offline.click(`${root} [data-client="a"] [data-key="gate-policy"] [data-pact-set]`);
      await offline.waitForFunction(() =>
        document.querySelector('#pact-demo [data-error]') ||
        document.querySelector('#pact-demo [data-client="a"] [data-key="gate-policy"] [data-pact-signoffs]')
          .textContent === "awaiting B",
      );
      assert.equal(await offline.$(`${root} [data-error]`), null);
      assert.deepEqual(await offline.$$eval(`${root} [data-key="gate-policy"] [data-pact-pending]`, (nodes) =>
        nodes.map((node) => node.textContent)), ["Survey", "—", "Survey"]);
      assert.deepEqual(await offline.$$eval(`${root} [data-key="gate-policy"] [data-pact-accepted]`, (nodes) =>
        nodes.map((node) => node.textContent)), ["—", "—", "—"]);
    }
    await offline.click(`${root} [data-cut-link]`);
    await offline.waitForFunction((id) => {
      const selector = id === "counter"
        ? "[data-counter-value]" : '[data-key="gate-policy"] [data-pact-accepted]';
      const expected = id === "counter" ? "126" : "Survey";
      return [...document.querySelectorAll(`#${id}-demo ${selector}`)]
        .every((node) => node.textContent === expected);
    }, {}, id);
    if (id === "pact") {
      assert.deepEqual(await offline.$$eval(`${root} [data-key="gate-policy"] [data-pact-signoffs]`, (nodes) =>
        nodes.map((node) => node.textContent)), ["", "", ""]);
    }
    assert.equal(await offline.$(`${root} [data-error]`), null);
    assert.deepEqual(offlineErrors, [], `${id} disconnected browser errors`);
    await offline.close();
  }

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
  await mapsPage.click('#ormap-demo [data-race]');
  await mapsPage.waitForFunction(() =>
    [...document.querySelectorAll(
      '#ormap-demo [data-ormap-set-row="inspection-brief"] [data-ormap-members]',
    )].every((node) => node.textContent === '["draft", "reviewed"]') &&
    [...document.querySelectorAll('#ormap-demo [data-pending-count]')]
      .every((node) => node.textContent === "0 pending"),
  );
  assert.equal(
    await mapsPage.$eval('#ormap-demo [data-seq-counter]', (node) => node.textContent),
    "SN 2",
    "string-set race sequences two additions",
  );
  assert.equal(await mapsPage.$('#ormap-demo .demo-error'), null);
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

  console.log(`PASS: ${slugs.join(", ")} structure page static contract.`);
});
