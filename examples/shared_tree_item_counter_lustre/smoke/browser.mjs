import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { existsSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  devtoolsEndpoint,
  findBrowser,
  sleep,
  stopBrowser,
  withPage,
} from "../../../smoke/cdp.mjs";
import { startChecklistServer } from "../../shared_tree_checklist_lustre/serve.mjs";

const appRoot = new URL("../", import.meta.url);
const bundle = new URL("dist/shared_tree_item_counter_lustre.mjs", appRoot);
const snapshot = `({
  status: document.querySelector("[data-runtime-status]")?.dataset.runtimeStatus,
  id: document.querySelector("[data-document-id]")?.dataset.documentId,
  count: Number(document.querySelector("[data-count]")?.dataset.count ?? -1),
  errors: [...document.querySelectorAll("[data-error]")].map(el => el.textContent),
  browserErrors: globalThis.__itemCounterErrors ?? [],
  generation: globalThis.__itemCounterGeneration,
  disabled: [...document.querySelectorAll("button")].every(el => el.disabled),
  url: location.href
})`;

async function evaluate(send, expression) {
  const result = await send("Runtime.evaluate", {
    expression,
    returnByValue: true,
    awaitPromise: true,
  });
  assert.equal(result.exceptionDetails, undefined, JSON.stringify(result));
  return result.result.value;
}

async function waitFor(send, predicate, description) {
  const deadline = Date.now() + 20_000;
  let value;
  while (Date.now() < deadline) {
    value = await evaluate(send, snapshot);
    assert.deepEqual(value.errors, [], JSON.stringify(value));
    assert.deepEqual(value.browserErrors, [], JSON.stringify(value));
    if (predicate(value)) return value;
    await sleep(50);
  }
  throw new Error("Timed out waiting for " + description + ": " + JSON.stringify(value));
}

async function click(send, action) {
  const clicked = await evaluate(send, `(() => {
    const button = document.querySelector('[data-action="${action}"]');
    if (!button || button.disabled) return false;
    button.click();
    return true;
  })()`);
  assert.equal(clicked, true, action + " must be available");
}

async function navigate(send, url, holdRequests = false) {
  await send("Page.enable");
  await send("Runtime.enable");
  await send("Page.addScriptToEvaluateOnNewDocument", {
    source: `globalThis.__itemCounterGeneration = crypto.randomUUID();
      globalThis.__itemCounterErrors = [];
      addEventListener("error", event => __itemCounterErrors.push(event.message));
      addEventListener("unhandledrejection", event =>
        __itemCounterErrors.push(String(event.reason)));
      if (${holdRequests}) {
        const nativeFetch = globalThis.fetch.bind(globalThis);
        const gate = new Promise(resolve => { globalThis.__releaseRequests = resolve; });
        globalThis.fetch = (...args) => gate.then(() => nativeFetch(...args));
      }`,
  });
  await send("Page.navigate", { url });
}

async function main() {
  assert.ok(existsSync(bundle), "Build the item-counter bundle before the smoke gate");
  const browser = findBrowser();
  assert.ok(browser, "Chromium is required; set WATERSHED_CHROME");
  const service = await fetch("http://127.0.0.1:4000");
  assert.ok(service.status < 500, "Start Floodgate with just integration-up");
  const profile = mkdtempSync(join(tmpdir(), "watershed-item-counter-"));
  let server;
  let chrome;
  try {
    server = await startChecklistServer({ appRoot, port: 0 });
    const origin = "http://127.0.0.1:" + server.port;
    assert.equal((await fetch(origin)).status, 200);
    chrome = spawn(browser, [
      "--headless=new",
      "--no-sandbox",
      "--disable-gpu",
      "--no-first-run",
      "--no-default-browser-check",
      "--remote-debugging-port=0",
      "--user-data-dir=" + profile,
      "about:blank",
    ], { stdio: ["ignore", "pipe", "pipe"] });
    chrome.stdout.resume();
    const endpoint = await devtoolsEndpoint(chrome);
    await withPage(endpoint, 120_000, "Item-counter smoke timed out", async (control) => {
      const targets = async () => (await control("Target.getTargets")).targetInfos;
      const open = async () => {
        const { browserContextId } = await control("Target.createBrowserContext");
        const { targetId } = await control("Target.createTarget", {
          url: "about:blank", browserContextId,
        });
        const target = (await targets()).find(target => target.targetId === targetId);
        assert.ok(target, "new browser target exists");
        return endpoint.replace(/\/devtools\/browser\/.*/, "/devtools/page/" + targetId);
      };
      const first = await open();
      await withPage(first, 100_000, "First client timed out", async (a) => {
        await navigate(a, origin, true);
        await waitFor(a, value => value.status === "creating", "creation in progress");
        assert.equal(await evaluate(a,
          'document.querySelector(\'[data-action="close"]\').disabled'), true,
        "Close must not discard an in-flight creation response");
        await evaluate(a, "globalThis.__releaseRequests()");
        const initial = await waitFor(a, value => value.status === "ready", "creation");
        assert.equal(initial.count, 0);
        assert.ok(initial.id);
        const second = await open();
        await withPage(second, 90_000, "Second client timed out", async (b) => {
          await navigate(b, initial.url);
          const loaded = await waitFor(b, value => value.status === "ready", "second client");
          assert.equal(loaded.id, initial.id);
          assert.equal(loaded.count, 0);
          const both = async count => {
            for (const send of [a, b]) {
              await waitFor(send, value => value.count === count, "count " + count);
            }
          };
          await click(a, "remove");
          await both(0);
          await click(a, "insert");
          await both(1);
          await click(b, "insert");
          await both(2);
          await click(a, "remove");
          await both(1);
          await Promise.all([click(a, "insert"), click(b, "insert")]);
          await both(3);
          const beforeReload = await evaluate(b, snapshot);
          await b("Page.reload");
          const reopened = await waitFor(b,
            value => value.generation
              && value.generation !== beforeReload.generation
              && value.status === "ready"
              && value.count === 3,
            "persisted reload");
          assert.equal(reopened.id, initial.id);
          await click(a, "close");
          await waitFor(a, value => value.status === "closed" && value.disabled, "close");
          await click(b, "insert");
          await waitFor(b, value => value.count === 4, "remaining client edit");
          await click(b, "close");
        });
      });
    });
    console.log("ok  SharedTree item counter: create, open, empty remove, both writers, reload, close");
  } finally {
    if (chrome) await stopBrowser(chrome);
    if (server) server.close();
    rmSync(profile, { recursive: true, force: true });
  }
}

main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
