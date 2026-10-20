import assert from "node:assert/strict";
import test from "node:test";
import { launchBrowser } from "../../lib/cdp.mjs";

test("browser click waits for a scrollable control rather than clicking outside the viewport", async () => {
  const browser = await launchBrowser();
  try {
    const page = await (await browser.context()).page();
    await page.goto("about:blank");
    await page.evaluate(`(() => {
      document.documentElement.style.scrollBehavior = "smooth";
      document.body.innerHTML = '<div style="height:3000px"></div><button id="target">Target</button>';
      globalThis.clickCount = 0;
      document.querySelector("#target").onclick = () => globalThis.clickCount++;
    })()`);
    await page.click("#target");
    assert.equal(await page.evaluate("globalThis.clickCount"), 1);
  } finally { await browser.close(); }
});

test("browser clicks remain actionable across isolated client contexts", async () => {
  const browser = await launchBrowser();
  try {
    const a = await (await browser.context()).page();
    await a.goto("about:blank");
    await a.evaluate(`document.body.innerHTML = '<button id="a">A</button>';
      globalThis.count = 0; document.querySelector("button").onclick = () => globalThis.count++;`);
    const b = await (await browser.context()).page();
    await b.goto("about:blank");
    await b.evaluate(`document.body.innerHTML = '<button id="b">B</button>';
      globalThis.count = 0; document.querySelector("button").onclick = () => globalThis.count++;`);
    for (let i = 0; i < 3; i++) {
      await a.click("#a");
      await b.click("#b");
    }
    assert.equal(await a.evaluate("globalThis.count"), 3);
    assert.equal(await b.evaluate("globalThis.count"), 3);
  } finally { await browser.close(); }
});

test("browser click activates an idle background client before waiting for animation frames", async () => {
  const browser = await launchBrowser();
  try {
    const pages = [];
    for (let i = 0; i < 4; i++) {
      const page = await (await browser.context()).page();
      await page.goto("about:blank");
      await page.evaluate(`document.body.innerHTML = '<button id="target">Target</button>';
        globalThis.count = 0; document.querySelector("button").onclick = () => globalThis.count++;`);
      pages.push(page);
    }
    await pages[3].evaluate("new Promise(resolve => setTimeout(resolve, 1200))");
    await pages[3].click("#target");
    assert.equal(await pages[3].evaluate("globalThis.count"), 1);
  } finally { await browser.close(); }
});
