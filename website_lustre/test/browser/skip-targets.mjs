import assert from "node:assert/strict";
import { readdir } from "node:fs/promises";
import { contract, openPage, withBrowserSite } from "./site.mjs";

const { site } = contract(import.meta.url);
const routes = (await readdir(site, { recursive: true }))
  .filter((path) => path === "index.html" || path.endsWith("/index.html"))
  .map((path) => `/${path.replace(/index\.html$/, "")}`)
  .sort();
assert.equal(routes.length, 42, "check every generated route");

await withBrowserSite(site, async (browser, origin) => {
  const { page, errors } = await openPage(browser);
  await page.setJavaScriptEnabled(false);
  const failures = [];
  for (const route of routes) {
    assert.equal((await page.goto(`${origin}${route}`)).status(), 200);
    const target = await page.evaluate(() => {
      const skip = document.querySelector(".skip-link");
      const href = skip?.getAttribute("href");
      const matches = href?.startsWith("#") ? document.querySelectorAll(href) : [];
      return {
        href,
        count: matches.length,
        main: matches[0]?.tagName === "MAIN",
        mains: document.querySelectorAll("main").length,
      };
    });
    if (target.count !== 1 || !target.main || target.mains !== 1) {
      failures.push({ route, ...target });
      continue;
    }
    await page.focus(".skip-link");
    await page.keyboard.press("Enter");
    await page.waitForFunction(() => document.querySelector("main:target") !== null);
  }
  assert.deepEqual(failures, [], "skip links resolve to one main landmark on every route");
  assert.deepEqual(errors, []);
  await page.close();
  console.log(`Skip-target browser gate passed (${routes.length} routes, no JavaScript).`);
});
