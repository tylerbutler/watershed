import assert from "node:assert/strict";
import { existsSync } from "node:fs";
import { readFile, stat, writeFile } from "node:fs/promises";
import { createServer } from "node:http";
import { dirname, extname, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import puppeteer from "puppeteer";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const record = process.argv.includes("--record-baseline");
const site = resolve(root, record ? "../website/dist" : "dist");
const fixture = resolve(root, "test/fixtures/astro-race-parity.json");
const browserPath = process.env.WATERSHED_CHROME || await puppeteer.executablePath();
if (!existsSync(browserPath)) {
  if (process.env.CI) throw new Error(`Chromium is required in CI: ${browserPath}`);
  console.log(`SKIP: Chromium is unavailable: ${browserPath}`);
  process.exit(0);
}
assert.ok(existsSync(resolve(site, "guide/race/index.html")), `Build the site first: ${site}`);
const mime = { ".html": "text/html", ".css": "text/css", ".js": "text/javascript", ".mjs": "text/javascript", ".svg": "image/svg+xml", ".png": "image/png", ".woff2": "font/woff2" };
const server = createServer(async (request, response) => {
  const pathname = new URL(request.url, "http://localhost").pathname;
  let path = resolve(site, "." + decodeURIComponent(pathname));
  if (!path.startsWith(site + sep) && path !== site) {
    response.writeHead(403).end();
    return;
  }
  try {
    if ((await stat(path)).isDirectory()) path = resolve(path, "index.html");
    const body = await readFile(path);
    response.writeHead(200, { "content-type": mime[extname(path)] || "application/octet-stream" }).end(body);
  } catch (error) {
    if (error.code !== "ENOENT" && error.code !== "ENOTDIR") {
      response.writeHead(500).end();
      throw error;
    }
    response.writeHead(404).end("Not found");
  }
});
await new Promise((resolve, reject) => {
  server.once("error", reject);
  server.listen(0, "127.0.0.1", resolve);
});
let browser;
const errors = [];
const selector = (id) => `[data-testid="${id}"]`;
const pause = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
try {
  browser = await puppeteer.launch({
    executablePath: browserPath,
    headless: true,
    args: process.env.CI ? ["--no-sandbox"] : [],
  });
  const url = `http://127.0.0.1:${server.address().port}/guide/race/`;
  const page = await browser.newPage();
  page.on("pageerror", (error) => errors.push(error.message));
  page.on("console", (message) => {
    if (message.type() === "error") errors.push(message.text());
  });
  await page.setRequestInterception(true);
  page.on("request", (request) => {
    if (request.url().startsWith("https://tinylytics.app/")) {
      request.respond({ status: 200, contentType: "text/javascript", body: "" });
    } else {
      request.continue();
    }
  });
  await page.setViewport({ width: 1440, height: 1000 });
  if (!record) await page.setJavaScriptEnabled(false);
  assert.equal((await page.goto(url)).status(), 200);
  await page.evaluate(() => document.fonts.ready);
  const content = await page.evaluate(() => {
    const links = (selector) => [...document.querySelectorAll(`${selector} a`)].map((node) => ({
      text: node.textContent.replace(/\s+/g, " ").trim(),
      href: node.getAttribute("href"),
      current: node.getAttribute("aria-current"),
    }));
    return {
      title: document.title,
      metadata: [...document.head.querySelectorAll("meta[name], meta[property]")].map((node) => [
        node.getAttribute("name") || node.getAttribute("property"), node.content,
      ]),
      heading: document.querySelector("h1").textContent,
      prose: [...document.querySelector("main").children].slice(0, 2).map((node) => node.innerText.replace(/\s+/g, " ").trim()),
      primary: links('nav[aria-label="Sheet index"]'),
      guide: links('nav[aria-label="Guide steps"]'),
      adjoining: links('nav[aria-labelledby="adjoining-title"]'),
      canonical: document.querySelector('link[rel="canonical"]')?.href || null,
    };
  });
  if (!record) {
    const baseline = JSON.parse(await readFile(fixture, "utf8"));
    assert.deepEqual(content, baseline.content);
    assert.equal(await page.$$eval(selector("race-demo"), (nodes) => nodes.length), 1);
    for (const id of ["alpha", "beta", "noscript"]) {
      assert.equal(await page.$eval(selector(id), (node) => node.checkVisibility()), true, id);
    }
    for (const id of ["alpha-notes", "beta-notes"]) {
      assert.match(await page.$eval(selector(id), (node) => node.innerText), /ship week went smoothly/);
    }
    assert.equal(await page.$eval(selector("race-fallback"), (node) => node.checkVisibility()), false);
    assert.deepEqual(await page.$$eval('script[type="module"]', (nodes) => nodes.map((node) => new URL(node.src).pathname)), ["/guide_race.js"]);
    assert.equal(await page.$("astro-island, script[src*='_astro'], script[src*='@vite']"), null);
    await page.setJavaScriptEnabled(true);
    await page.reload();
    await page.waitForFunction(() => document.querySelector('[data-testid="race-demo"]')?.dataset.phase === "ready");
  } else {
    await page.waitForFunction(() => !document.querySelector("[data-guide-race-add]").disabled);
    // Annotate the existing Astro DOM only while recording the baseline.
    await page.evaluate(() => {
      const nodes = {
        "race-demo": "#guide-race-demo",
        "race-rig": "[data-guide-race-rig]",
        alpha: '[data-client="a"]',
        beta: '[data-client="b"]',
        "starter-note": '[data-client="a"] [data-board] li',
        "race-add": "[data-guide-race-add]",
      };
      for (const [id, selector] of Object.entries(nodes)) document.querySelector(selector).dataset.testid = id;
    });
  }
  await page.evaluate(() => document.fonts.ready);
  const collectStyles = async () => page.evaluate((record) => {
    const style = (selector, properties) => {
      const computed = getComputedStyle(document.querySelector(selector));
      return Object.fromEntries(properties.map((key) => [key, computed.getPropertyValue(key)]));
    };
    return {
      body: style("body", ["font-family", "font-size", "line-height"]),
      section: style('[data-testid="race-demo"]', ["padding-top", "padding-left", "border-bottom-width", "border-bottom-color"]),
      rig: style('[data-testid="race-rig"]', ["display", "grid-template-areas", "grid-template-columns", "gap"]),
      replica: style('[data-testid="alpha"]', ["grid-area", "border-width", "border-color"]),
      note: style(record ? '[data-testid="starter-note"]' : '[data-testid="alpha-note-survey-900-1"]', ["border-width", "border-color", "padding", "font-size"]),
      button: style('[data-testid="race-add"]', ["padding", "font-size", "border-width", "font-weight"]),
    };
  }, record);
  const desktop = await collectStyles();
  if (record) {
    await page.focus(selector("race-add"));
  } else {
    await page.focus(selector("latency"));
    await page.keyboard.press("Tab");
    assert.equal(await page.evaluate(() => document.activeElement.dataset.testid), "race-add");
    await page.keyboard.press("Tab");
    assert.equal(await page.evaluate(() => document.activeElement.dataset.testid), "race-reset");
    await page.keyboard.down("Shift");
    await page.keyboard.press("Tab");
    await page.keyboard.up("Shift");
  }
  const focus = await page.$eval(selector("race-add"), (node) => {
    const style = getComputedStyle(node);
    return { outline: style.outline, offset: style.outlineOffset };
  });
  await page.setViewport({ width: 390, height: 844 });
  const mobile = await collectStyles();
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true, "mobile overflow");
  if (record) {
    await writeFile(fixture, JSON.stringify({ content, desktop, mobile, focus }, null, 2) + "\n");
    console.log("Recorded Astro race parity baseline.");
  } else {
    const baseline = JSON.parse(await readFile(fixture, "utf8"));
    assert.deepEqual(desktop, baseline.desktop, "desktop styles");
    assert.deepEqual(mobile, baseline.mobile, "mobile styles");
    assert.deepEqual(focus, baseline.focus, "keyboard focus");
    await page.setViewport({ width: 1440, height: 1000 });
    const notes = () => page.evaluate(() => ["alpha", "beta"].map((id) =>
      document.querySelector(`[data-testid="${id}-notes"]`).innerText));
    const initial = await notes();
    assert.equal(initial[0], initial[1]);
    await page.$eval(selector("latency"), (input) => {
      input.value = "1500";
      input.dispatchEvent(new Event("input", { bubbles: true }));
    });
    const start = Date.now();
    await page.focus(selector("race-add"));
    await page.keyboard.press("Space");
    await page.waitForFunction(() => document.querySelector('[data-testid="alpha-pending"]').textContent === "1 pending");
    const pending = await notes();
    assert.match(pending[0], /deploys got faster/);
    assert.doesNotMatch(pending[0], /standup stayed short/);
    assert.match(pending[1], /standup stayed short/);
    assert.doesNotMatch(pending[1], /deploys got faster/);
    assert.equal(await page.$eval(selector("race-add"), (node) => node.disabled), true);
    assert.equal(await page.$eval(selector("race-reset"), (node) => node.disabled), false);
    assert.equal(await page.$eval(selector("latency"), (node) => node.disabled), false);
    assert.equal(await page.$$eval(`${selector("flow-layer")} [data-from="alpha"][data-to="seq"]`, (nodes) => nodes.length), 1);
    const firstPosition = await page.$eval(`${selector("flow-layer")} [data-from="alpha"]`, (node) => node.getBoundingClientRect().x);
    await pause(150);
    const secondPosition = await page.$eval(`${selector("flow-layer")} [data-from="alpha"]`, (node) => node.getBoundingClientRect().x);
    assert.notEqual(firstPosition, secondPosition, "outbound flow moves");
    await page.waitForFunction(() => document.querySelector('[data-testid="operation-log"]').children.length >= 2);
    assert.ok(Date.now() - start >= 1200, "delivery respects latency");
    assert.ok(await page.$$eval(`${selector("flow-layer")} [data-from="seq"]`, (nodes) => nodes.length) >= 2);
    await page.evaluate(() => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve))));
    const inbound = await page.$eval(selector("flow-layer"), (layer) => {
      const bounds = layer.getBoundingClientRect();
      const source = document.querySelector('[data-flow-node="seq"]').getBoundingClientRect();
      const start = [source.left + source.width / 2 - bounds.left - 5, source.top + source.height / 2 - bounds.top - 5];
      return [...layer.querySelectorAll('[data-from="seq"]')].map((node) => ({
        start,
        actual: node.getAnimations().map((animation) => {
          const transform = new DOMMatrix(animation.effect.getKeyframes()[0].transform);
          return [transform.m41, transform.m42];
        }),
      }));
    });
    for (const marker of inbound) {
      assert.equal(marker.actual.length, 1, "each inbound marker has one animation");
      assert.ok(marker.actual[0].every((value, index) => Math.abs(value - marker.start[index]) < 0.01),
        `inbound marker starts at the sequencer: ${JSON.stringify(marker)}`);
    }
    await page.waitForFunction(() => document.querySelector('[data-testid="race-status"]').textContent.includes("Converged"));
    const converged = await notes();
    assert.equal(converged[0], converged[1]);
    assert.match(converged[0], /deploys got faster/);
    assert.match(converged[0], /standup stayed short/);
    assert.equal(await page.$eval(selector("operation-log"), (node) => node.children.length), 4);
    assert.match(await page.$eval(selector("operation-log"), (node) => node.innerText), /SN \d+.*→.*op/s);
    assert.equal(await page.$eval(selector("race-add"), (node) => node.disabled), true);
    await page.click(selector("race-reset"));
    await page.waitForFunction(() =>
      document.querySelector('[data-testid="race-demo"]').dataset.phase === "ready"
      && document.querySelector('[data-testid="alpha-notes"]').children.length === 1
      && !document.querySelector('[data-testid="race-add"]').disabled);
    assert.deepEqual(await notes(), initial);
    assert.equal(await page.$eval(selector("operation-log"), (node) => node.children.length), 0);
    await page.click(selector("race-add"));
    await page.waitForFunction(() => document.querySelector('[data-testid="alpha-pending"]').textContent === "1 pending");
    await page.click(selector("race-reset"));
    await pause(1800);
    assert.deepEqual(await notes(), initial, "old timers cannot mutate a reset board");
    await page.emulateMediaFeatures([{ name: "prefers-reduced-motion", value: "reduce" }]);
    await page.click(selector("race-add"));
    await page.waitForFunction(() => document.querySelector('[data-testid="alpha-pending"]').textContent === "1 pending");
    assert.ok(await page.$$eval(`${selector("flow-layer")} [data-flow-id]`, (nodes) =>
      nodes.every((node) => node.getAnimations().every((animation) => animation.effect.getTiming().duration === 0))));
    assert.equal(await page.$$eval('[id="guide-race-demo"]', (nodes) => nodes.length), 1);
    assert.equal(await page.$eval(selector("race-error"), (node) => node.textContent), "");
    await page.click(selector("race-reset"));
    await page.waitForFunction(() => !document.querySelector('[data-testid="race-add"]').disabled);
    await page.evaluate(() => {
      document.querySelector('[data-flow-node="seq"]').removeAttribute("data-flow-node");
      window.endpointQueries = 0;
      const query = Element.prototype.querySelector;
      Element.prototype.querySelector = function (selector) {
        if (selector === '[data-flow-node="seq"]') window.endpointQueries++;
        return query.call(this, selector);
      };
    });
    await page.click(selector("race-add"));
    await page.waitForFunction(() => document.querySelector('[data-testid="race-demo"]').dataset.phase === "failed");
    assert.match(await page.$eval(selector("race-error"), (node) => node.textContent), /Cannot find a flow endpoint/);
    await pause(250);
    assert.equal(await page.evaluate(() => window.endpointQueries), 1, "animation failure does not restart itself");

    const blocked = await browser.newPage();
    await blocked.setRequestInterception(true);
    blocked.on("request", (request) => {
      if (new URL(request.url()).pathname === "/guide_race.js") request.abort();
      else if (request.url().startsWith("https://tinylytics.app/")) {
        request.respond({ status: 200, contentType: "text/javascript", body: "" });
      } else request.continue();
    });
    await blocked.goto(url);
    await blocked.waitForSelector(selector("race-fallback"), { visible: true, timeout: 6000 });
    assert.match(await blocked.$eval(selector("race-fallback"), (node) => node.textContent), /The live race couldn't start/);
    assert.match(await blocked.$eval(selector("alpha-notes"), (node) => node.innerText), /ship week went smoothly/);
    assert.equal(await blocked.$eval(selector("race-add"), (node) => node.disabled), true);
    await blocked.close();
    console.log("PASS: static content, Astro parity, race, flow, reset, reduced motion, and failures.");
  }
  assert.deepEqual(errors, [], "browser errors");
} finally {
  if (browser) await browser.close();
  await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
}
