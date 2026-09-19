import assert from "node:assert/strict";
import { openPage, parity, readParity, withBrowserSite, writeParity } from "./site.mjs";

const { record, site, fixture } = parity(import.meta.url, "astro-text-parity.json");

async function snapshot(page) {
  return page.evaluate(() => ({
    title: document.title,
    description: document.querySelector('meta[name="description"]')?.content,
    hero: document.querySelector(".page-hero")?.innerText.replace(/\s+/g, " ").trim(),
    headings: [...document.querySelectorAll("main h2")].map((node) =>
      node.textContent.trim(),
    ),
    clients: [...document.querySelectorAll("[data-text-rig] .client")].map(
      (node) => node.getAttribute("aria-label"),
    ),
    panes: [...document.querySelectorAll("[data-pane]")].map((node) =>
      node.getAttribute("aria-label"),
    ),
    fitsViewport: document.documentElement.scrollWidth <= innerWidth,
  }));
}

async function waitForRevision(page) {
  await page.waitForFunction(
    () =>
      document.querySelector("[data-text-status]").textContent.includes("Revising") ||
      [...document.querySelectorAll("[data-pending-count]")].some(
        (node) => node.textContent !== "0 pending",
      ),
  );
}

async function converge(page) {
  await page.waitForFunction(
    () =>
      document.querySelector("[data-text-status]").textContent.includes("Converged") &&
      [...document.querySelectorAll("[data-pending-count]")].every(
        (node) => node.textContent === "0 pending",
      ),
  );
  const values = await page.$$eval("[data-text-editor]", (nodes) =>
    nodes.map((node) => node.value),
  );
  assert.equal(new Set(values).size, 1, JSON.stringify(values));
  return values[0];
}

await withBrowserSite(site, async (browser, origin) => {
  const { page, errors } = await openPage(browser);
  await page.setViewport({ width: 1440, height: 1000 });
  assert.equal((await page.goto(`${origin}/text/`)).status(), 200);
  await page.waitForFunction(
    (lustre) =>
      (!lustre ||
        (document.querySelector("#text-demo")?.hasAttribute("data-mounted") &&
          document.querySelector("#text-element-demo")?.hasAttribute("data-mounted"))) &&
      [...document.querySelectorAll("[data-text-editor]")].every(
        (node) => !node.disabled,
      ) &&
      customElements.get("watershed-textarea"),
    !record,
  );
  const desktop = await snapshot(page);
  await page.setViewport({ width: 390, height: 844 });
  const mobile = await snapshot(page);
  if (record) {
    await writeParity(fixture, { desktop, mobile });
    console.log("Recorded Astro Text parity baseline.");
    return;
  }
  assert.deepEqual(
    { desktop, mobile },
    await readParity(fixture),
  );
  assert.equal(mobile.fitsViewport, true);
  const mainText = await page.$eval("main", (node) =>
    node.innerText.replace(/\s+/g, " ").trim(),
  );
  for (const phrase of [
    "Every keystroke is diffed into one minimal grapheme edit",
    "The seed text is grapheme-rich on purpose",
    "The component owns what the naïve bridge gets wrong",
    "Cursors here hop panes through a property assignment",
  ]) assert.match(mainText, new RegExp(phrase));
  assert.equal(await page.$("astro-island, script[src*='_astro'], script[src*='@vite']"), null);

  await page.setViewport({ width: 1440, height: 1000 });
  const editor = await page.$('[data-client="a"] [data-text-editor]');
  await editor.focus();
  await editor.type(" upstream");
  await waitForRevision(page);
  assert.match(await converge(page), /upstream/);
  await page.click("[data-text-race-insert]");
  await waitForRevision(page);
  await converge(page);
  await page.click("[data-text-race-overlap]");
  await waitForRevision(page);
  await converge(page);
  assert.ok(
    await page.$$eval("[data-op-log] li", (nodes) => nodes.length >= 4),
    "both text races should log both replica operations",
  );
  assert.match(
    await page.$eval("[data-seq-counter]", (node) => node.textContent),
    /^SN \d+$/,
  );
  await page.$eval("[data-text-pace]", (input) => {
    input.value = "2";
    input.dispatchEvent(new Event("input", { bubbles: true }));
  });
  await page.waitForFunction(
    () => document.querySelector("[data-text-pace-out]")?.textContent === "2×",
  );
  assert.equal(
    await page.$eval("[data-text-pace-out]", (node) => node.textContent),
    "2×",
  );
  await page.click("[data-text-latency-variance]");
  assert.equal(
    await page.$eval("[data-text-latency-variance]", (node) => node.checked),
    true,
  );

  const anchorEditor = await page.$('[data-client="a"] [data-text-editor]');
  await anchorEditor.focus();
  await page.$eval('[data-client="a"] [data-text-editor]', (node) => {
    node.setSelectionRange(4, 4);
    node.dispatchEvent(new Event("select", { bubbles: true }));
  });
  await page.click('[data-client="a"] [data-anchor-pin]');
  await page.waitForFunction(
    () =>
      document.querySelector('[data-client="a"] [data-anchor-readout]')
        ?.textContent.includes("anchor pinned @"),
  );
  assert.match(
    await page.$eval('[data-client="a"] [data-anchor-readout]', (node) => node.textContent),
    /anchor pinned @/,
  );
  await page.click('[data-client="a"] [data-anchor-clear]');
  await page.waitForFunction(
    () =>
      document.querySelector('[data-client="a"] [data-anchor-readout]')
        ?.textContent === "no anchor pinned",
  );
  assert.equal(
    await page.$eval('[data-client="a"] [data-anchor-readout]', (node) => node.textContent),
    "no anchor pinned",
  );

  const imeBase = await page.$eval(
    '[data-client="b"] [data-text-editor]',
    (node) => node.value,
  );
  await page.$eval('[data-client="b"] [data-text-editor]', (node) => {
    node.focus();
    node.setSelectionRange(node.value.length, node.value.length);
    node.dispatchEvent(new CompositionEvent("compositionstart", { bubbles: true }));
  });
  await page.waitForFunction(
    () =>
      document.querySelector('[data-client="b"] [data-text-editor]')
        ?.dataset.composing === "true",
  );
  await page.$eval('[data-client="c"] [data-text-editor]', (node) => {
    node.value = `remote ${node.value}`;
    node.dispatchEvent(new InputEvent("input", {
      bubbles: true,
      inputType: "insertText",
      data: "remote ",
    }));
  });
  await page.waitForFunction(
    (base) =>
      document.querySelector('[data-client="a"] [data-text-editor]').value.startsWith("remote ") &&
      document.querySelector('[data-client="b"] [data-text-editor]').value === base,
    {},
    imeBase,
  );
  await page.$eval('[data-client="b"] [data-text-editor]', (node) => {
    node.value += " 水";
    node.setSelectionRange(node.value.length, node.value.length);
    node.dispatchEvent(new CompositionEvent("compositionend", { bubbles: true }));
    node.dispatchEvent(new InputEvent("input", {
      bubbles: true,
      inputType: "insertCompositionText",
      data: " 水",
    }));
  });
  await waitForRevision(page);
  assert.match(await converge(page), /^remote .* 水$/);
  await page.click("[data-text-reset]");
  await converge(page);

  let elementValues = await page.$$eval("watershed-textarea", (nodes) =>
    nodes.map((node) => node.shadowRoot?.querySelector("textarea")?.value),
  );
  assert.equal(elementValues.length, 2);
  assert.ok(elementValues.every((value) => value?.length > 20));
  assert.equal(new Set(elementValues).size, 1);
  await page.$eval('[data-pane="a"] watershed-textarea', (node) => {
    const textarea = node.shadowRoot.querySelector("textarea");
    textarea.value += " shared";
    textarea.dispatchEvent(new InputEvent("input", {
      bubbles: true,
      inputType: "insertText",
      data: " shared",
    }));
  });
  await page.waitForFunction(() => {
    const values = [...document.querySelectorAll("watershed-textarea")].map(
      (node) => node.shadowRoot?.querySelector("textarea")?.value,
    );
    return values.length === 2 && values[0]?.endsWith(" shared") && values[0] === values[1];
  });
  const cursorPayload = JSON.stringify({
    start: { kind: "start" },
    end: { kind: "end" },
  });
  await page.$eval(
    '[data-pane="a"] watershed-textarea',
    (node, payload) => {
      node.dispatchEvent(new CustomEvent("cursor", {
        bubbles: true,
        detail: JSON.parse(payload),
      }));
    },
    cursorPayload,
  );
  await page.waitForFunction(() => {
    const a = document.querySelector('[data-pane="a"] watershed-textarea');
    const b = document.querySelector('[data-pane="b"] watershed-textarea');
    return a.peers.length === 0 && b.peers.length === 1 && b.peers[0].id === "a";
  });

  const noJs = await browser.newPage();
  await noJs.setJavaScriptEnabled(false);
  await noJs.goto(`${origin}/text/`);
  assert.equal(await noJs.$$eval('[data-testid="noscript"]', (nodes) =>
    nodes.every((node) => node.checkVisibility())), true);
  await noJs.close();

  const blocked = await browser.newPage();
  await blocked.setRequestInterception(true);
  blocked.on("request", (request) => {
    if (new URL(request.url()).pathname === "/text.js") request.abort();
    else request.continue();
  });
  await blocked.goto(`${origin}/text/`);
  await blocked.waitForSelector('[data-testid="text-fallback"]', {
    visible: true,
    timeout: 6000,
  });
  await blocked.close();
  assert.deepEqual(errors, []);
  console.log("PASS: Text parity, edits, races, custom elements, and fallbacks.");
});
