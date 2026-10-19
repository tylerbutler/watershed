import assert from "node:assert/strict";
import test from "node:test";
import { setTimeout } from "node:timers/promises";
import { openBrowserTest } from "./browser-test-harness.mjs";

const base = process.env.WATERSHED_WEBSITE_URL ?? "http://127.0.0.1:4321";
const example = "https://github.com/tylerbutler/watershed/blob/main/examples/shared_tree_project_brief_lustre/";

test("project brief pairs local source, responsive layout, and keyboard code access without JavaScript", {
  timeout: 60_000,
}, async (t) => {
  const { page, errors } = await openBrowserTest(t);
  await page.setJavaScriptEnabled(false);
  const response = await page.goto(new URL("/sharedtree/project-brief/", base).href, {
    waitUntil: "networkidle0",
  });
  assert.equal(response?.status(), 200);
  assert.equal((await page.$$("main h1, header h1")).length, 1);
  for (const width of [1440, 390]) {
    await page.setViewport({ width, height: 1000 });
    const rows = await page.$$eval("[data-comparison-row]", sections =>
      sections.map(section => {
        const rect = element => {
          const box = element.getBoundingClientRect();
          return { x: box.x, y: box.y, right: box.right, bottom: box.bottom };
        };
        return {
          id: section.dataset.comparisonRow,
          columns: [...section.querySelectorAll("[data-comparison-column]")].map(column => ({
            side: column.dataset.comparisonColumn,
            box: rect(column),
            heading: column.querySelector("h3").textContent,
            code: [...column.querySelectorAll("pre")].map(node => node.textContent.trim()),
            links: [...column.querySelectorAll("a.g-file")].map(node => node.href),
          })),
        };
      }));
    assert.deepEqual(rows.map(row => row.id), [
      "schema", "lifecycle", "observe", "edits", "milestones", "presence",
    ]);
    for (const row of rows) {
      assert.deepEqual(row.columns.map(column => column.side), ["fluid", "watershed"]);
      assert.deepEqual(row.columns.map(column => column.heading), ["Fluid · TypeScript", "watershed · Gleam"]);
      for (const column of row.columns) {
        assert.ok(column.code.length > 0 && column.code.every(Boolean));
        assert.equal(column.links.length, column.code.length);
        assert.ok(column.links.every(link => link.startsWith(example)));
        assert.ok(column.links.every(link => column.side === "fluid"
          ? link.startsWith(`${example}fluid/src/`)
          : link.startsWith(`${example}src/`)));
      }
      const [fluid, watershed] = row.columns.map(column => column.box);
      if (width === 1440) {
        assert.ok(fluid.right <= watershed.x + 1, JSON.stringify(row));
      } else {
        assert.ok(fluid.bottom <= watershed.y + 1, JSON.stringify(row));
      }
    }
    assert.ok(await page.evaluate(() =>
      document.documentElement.scrollWidth <= window.innerWidth),
    `document overflow at ${width}px`);
    // Check keyboard reachability at both sizes, without injecting focus.
    await page.goto(new URL("/sharedtree/project-brief/", base).href, { waitUntil: "networkidle0" });
    let codeFocused = false;
    for (let step = 0; step < 60; step++) {
      await page.keyboard.press("Tab");
      codeFocused = await page.evaluate(() =>
        document.activeElement.matches("[data-comparison-row] pre"));
      if (codeFocused) break;
    }
    assert.ok(codeFocused, `keyboard must reach code at ${width}px`);
    assert.ok(await page.evaluate(() => {
      const style = getComputedStyle(document.activeElement);
      return style.outlineStyle !== "none" && Number.parseFloat(style.outlineWidth) >= 2;
    }), "source code must have visible focus");
    if (width === 390) {
      const before = await page.evaluate(() => document.activeElement.scrollLeft);
      await page.keyboard.press("ArrowRight");
      let scrolled = false;
      for (let step = 0; step < 20; step++) {
        scrolled = await page.evaluate(value => document.activeElement.scrollLeft > value, before);
        if (scrolled) break;
        await setTimeout(50);
      }
      assert.ok(scrolled, "focused code must scroll with arrow keys");
    }
    console.log(`project brief no-JS ${width}px: six local-source pairs, no overflow, visible keyboard focus`);
  }
  const links = await page.$$eval("a", nodes => nodes.map(node => node.getAttribute("href")));
  assert.ok(links.includes("/sharedtree"));
  assert.ok(links.includes("/sharedtree/item-counter"));
  assert.ok(links.includes(example.replace("/blob/", "/tree/").slice(0, -1)));
  assert.ok(links.includes(example.replace("/blob/", "/tree/") + "fluid"));
  for (const path of ["/sharedtree/", "/sharedtree/item-counter/"]) {
    const response = await page.goto(new URL(path, base).href, { waitUntil: "networkidle0" });
    assert.equal(response?.status(), 200);
    assert.ok(await page.$('a[href="/sharedtree/project-brief"]'), `${path} links to the comparison`);
  }
  assert.deepEqual(errors, []);
});
