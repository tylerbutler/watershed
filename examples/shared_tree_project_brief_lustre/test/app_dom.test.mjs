import assert from "node:assert/strict";
import { test } from "node:test";
import { spawn } from "node:child_process";
import { mkdirSync, rmSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { build } from "esbuild";
import { devtoolsEndpoint, findBrowser, startServer, stopBrowser, withPage } from "../../../smoke/cdp.mjs";

const root = fileURLToPath(new URL("..", import.meta.url));

test("actual Lustre DOM replaces review controls between captures, isolating native composition", async () => {
  const browser = findBrowser();
  assert(browser, "Chromium required");
  const directory = resolve(root, `build/final-dom-${process.pid}`);
  mkdirSync(directory, { recursive: true });
  let server, chrome;
  try {
    await build({ entryPoints: [resolve(root, "test/dom_fixture.mjs")],
      bundle: true, format: "esm", outfile: resolve(directory, "fixture.mjs"), logLevel: "silent" });
    await build({ entryPoints: [resolve(root, "fluid/test/input_fixture.tsx")],
      bundle: true, format: "esm", jsx: "automatic", outfile: resolve(directory, "fluid.mjs"), logLevel: "silent" });
    server = await startServer(directory, '<div id="app"></div><script type="module">import(location.search ? "/fluid.mjs" : "/fixture.mjs")</script>');
    chrome = spawn(browser, ["--headless=new", "--no-sandbox", "--disable-gpu",
      "--no-first-run", "--remote-debugging-port=0", "--user-data-dir=" + resolve(directory, "profile"),
      "about:blank"], { stdio: ["ignore", "pipe", "pipe"] });
    chrome.stdout.resume();
    const endpoint = await devtoolsEndpoint(chrome);
    const targets = await (await fetch(`http://${new URL(endpoint).host}/json/list`)).json();
    await withPage(targets.find(t => t.type === "page").webSocketDebuggerUrl, 20_000,
      "review DOM regression timeout", async send => {
        async function run(expression) {
          const result = await send("Runtime.evaluate", { expression, awaitPromise: true, returnByValue: true });
          assert(!result.exceptionDetails, JSON.stringify(result.exceptionDetails));
          return result.result.value;
        }
        await send("Page.enable");
        await send("Page.navigate", { url: `http://127.0.0.1:${server.port}/` });
        await run(`new Promise(resolve => {
          const poll = () => window.fixture ? resolve() : setTimeout(poll, 10); poll();
        })`);
        await run(`(() => {
          window.oldInput = document.querySelector('[data-field="review.reviewer"]');
          oldInput.focus();
          oldInput.dispatchEvent(new CompositionEvent("compositionstart", {bubbles:true}));
          oldInput.value = "OLD COMPOSITION";
          oldInput.dispatchEvent(new InputEvent("input", {bubbles:true, isComposing:true}));
          fixture.replace();
        })()`);
        await run("new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)))");
        assert.equal(await run("oldInput.isConnected"), false, "old native control must be removed");
        assert.equal(await run("document.activeElement === oldInput"), false);
        assert.equal(await run('document.activeElement?.dataset.field === "review.reviewer"'), false);
        await run(`oldInput.dispatchEvent(new CompositionEvent("compositionend", {bubbles:true, data:"OLD COMPOSITION"}))`);
        await run("fixture.capture()");
        await run("new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)))");
        assert.equal(await run("fixture.reviewer"), "New");
        assert.deepEqual(await run("fixture.errors"), []);
        await run(`(() => {
          const input = document.querySelector('[data-field="review.reviewer"]');
          window.replacement = input;
          input.focus(); input.value = "Fresh";
          input.dispatchEvent(new InputEvent("input", {bubbles:true}));
        })()`);
        await run("new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)))");
        await run("fixture.capture()");
        await run("new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)))");
        assert.equal(await run("fixture.reviewer"), "Fresh");
        assert.equal(await run('replacement === document.querySelector(\'[data-field="review.reviewer"]\')'), true,
          "ordinary content edits must not remount controls");

        await send("Page.navigate", { url: `http://127.0.0.1:${server.port}/?fluid` });
        await run(`new Promise(resolve => {
          const poll = () => window.fixture ? resolve() : setTimeout(poll, 10); poll();
        })`);
        await run(`(() => {
          const input = document.querySelector("input");
          input.focus();
          input.dispatchEvent(new CompositionEvent("compositionstart", {bubbles:true}));
          input.value = "OLD COMPOSITION";
          fixture.replace();
          input.dispatchEvent(new CompositionEvent("compositionend", {bubbles:true}));
          input.dispatchEvent(new InputEvent("input", {bubbles:true}));
        })()`);
        assert.equal(await run("fixture.reviewer"), "New", "React identity transition cancels the old composition");
        assert.equal(await run('document.activeElement?.tagName === "INPUT"'), false);
        await run(`(() => {
          const input = document.querySelector("input");
          input.focus();
          input.dispatchEvent(new CompositionEvent("compositionstart", {bubbles:true}));
          fixture.disconnect();
          fixture.reconnect();
          input.value = "LATE CANCELED";
          input.dispatchEvent(new CompositionEvent("compositionend", {bubbles:true}));
          input.dispatchEvent(new InputEvent("input", {bubbles:true}));
        })()`);
        assert.equal(await run("fixture.reviewer"), "New", "React reconnect cannot publish the late end or final input");
        assert.equal(await run('document.querySelector("input").value'), "New",
          "React must restore the resolved native value after rejecting late composition");
        await run(`(() => {
          const input = document.querySelector("input");
          input.dispatchEvent(new KeyboardEvent("keydown", {bubbles:true, key:"x"}));
          input.value = "Fresh key";
          input.dispatchEvent(new InputEvent("input", {bubbles:true}));
        })()`);
        assert.equal(await run("fixture.reviewer"), "Fresh key", "fresh keyboard interaction releases cancellation");
      });
  } finally {
    if (chrome) await stopBrowser(chrome);
    if (server) server.close();
    rmSync(directory, { recursive: true, force: true });
  }
});
