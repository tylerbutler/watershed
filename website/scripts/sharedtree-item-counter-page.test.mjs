import assert from "node:assert/strict";
import test from "node:test";
import { setTimeout } from "node:timers/promises";
import { openBrowserTest } from "./browser-test-harness.mjs";

const base = process.env.WATERSHED_WEBSITE_URL ?? "http://127.0.0.1:4321";

test("native SharedTree comparison pairs attributed source without requiring JavaScript", {
  timeout: 60_000,
}, async (t) => {
  const { page, errors } = await openBrowserTest(t);
  await page.setJavaScriptEnabled(false);
  const response = await page.goto(new URL("/sharedtree/item-counter/", base).href, {
    waitUntil: "networkidle0",
  });
  assert.equal(response?.status(), 200);
  assert.equal((await page.$$("main h1, header h1")).length, 1);
  assert.equal((await page.$$("[data-comparison-row]")).length, 4);
  for (const width of [1440, 390]) {
    await page.setViewport({ width, height: 1000 });
    const rows = await page.$$eval("[data-comparison-row]", sections =>
      sections.map(section => {
        const fluid = section.querySelector('[data-comparison-column="fluid"]');
        const watershed = section.querySelector('[data-comparison-column="watershed"]');
        const rect = element => {
          const box = element.getBoundingClientRect();
          return { x: box.x, y: box.y, right: box.right, bottom: box.bottom };
        };
        return {
          id: section.dataset.comparisonRow,
          fluid: rect(fluid),
          watershed: rect(watershed),
          headings: [...section.querySelectorAll("h3")].map(node => node.textContent),
          code: [...section.querySelectorAll("pre")].every(node => node.textContent.trim()),
        };
      }));
    assert.deepEqual(rows.map(row => row.id), ["schema", "lifecycle", "observe", "edits"]);
    for (const row of rows) {
      assert.ok(row.code);
      assert.deepEqual(row.headings, ["Fluid · TypeScript", "watershed · Gleam"]);
      if (width === 1440) {
        assert.ok(row.fluid.right <= row.watershed.x + 1, JSON.stringify(row));
      } else {
        assert.ok(row.fluid.bottom <= row.watershed.y + 1, JSON.stringify(row));
      }
    }
    assert.ok(await page.evaluate(() =>
      document.documentElement.scrollWidth <= window.innerWidth),
    "code must not overflow the page at " + width);
  }
  const links = await page.$$eval("a", nodes => nodes.map(node => node.getAttribute("href")));
  assert.ok(links.includes("/sharedtree"));
  assert.ok(links.includes("/sharedtree/checklist"));
  assert.ok(links.some(link =>
    link?.includes("/watershed/tree/main/examples/shared_tree_item_counter_lustre")));
  assert.ok(links.some(link =>
    link?.includes("/FluidExamples/blob/396454d692950f29c9965cf1190678cc6a227d23/item-counter/")));
  assert.equal(await page.$eval("main", node => node.textContent.includes("detached")), true);
  await page.keyboard.press("Tab");
  assert.equal(await page.evaluate(() => document.activeElement.tagName), "A");
  let codeFocused = false;
  for (let step = 0; step < 40; step++) {
    await page.keyboard.press("Tab");
    codeFocused = await page.evaluate(() =>
      document.activeElement.matches("[data-comparison-row] pre"));
    if (codeFocused) break;
  }
  assert.ok(codeFocused, "keyboard navigation must reach source code");
  assert.ok(await page.evaluate(() => {
    const style = getComputedStyle(document.activeElement);
    return style.outlineStyle !== "none" && Number.parseFloat(style.outlineWidth) > 0;
  }), "focused source code must have a visible outline");
  const beforeScroll = await page.evaluate(() => document.activeElement.scrollLeft);
  await page.keyboard.press("ArrowRight");
  let scrolled = false;
  for (let step = 0; step < 20; step++) {
    scrolled = await page.evaluate(before =>
      document.activeElement.scrollLeft > before, beforeScroll);
    if (scrolled) break;
    await setTimeout(50);
  }
  assert.ok(scrolled, "focused source code must scroll with arrow keys");
  assert.deepEqual(errors, []);
});
