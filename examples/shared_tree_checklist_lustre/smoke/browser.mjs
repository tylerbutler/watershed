import { spawn } from "node:child_process";
import { existsSync, mkdirSync, rmSync } from "node:fs";
import { connect } from "node:net";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import WebSocket from "ws";
import {
  BROWSER_START_MS,
  devtoolsEndpoint,
  findBrowser,
  sleep,
  stopBrowser,
  withPage,
} from "../../../smoke/cdp.mjs";
import { startChecklistServer } from "../serve.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const appRoot = resolve(here, "..");
const bundle = join(appRoot, "dist", "shared_tree_checklist_lustre.mjs");
const profile = join(appRoot, "build", "browser-smoke-profile");

const PAGE_MS = 120_000;
const STEP_MS = 20_000;

const snapshotExpression = `(() => ({
  status: document.querySelector("[data-runtime-status]")?.dataset.runtimeStatus,
  document: document.querySelector("[data-document-id]")?.dataset.documentId,
  pending: Number(document.querySelector("[data-pending]")?.dataset.pending ?? -1),
  undo: Number(document.querySelector("[data-undo-count]")?.dataset.undoCount ?? -1),
  redo: Number(document.querySelector("[data-redo-count]")?.dataset.redoCount ?? -1),
  items: Array.from(document.querySelectorAll("[data-item-id]")).map((row) => ({
    id: row.dataset.itemId,
    text: row.querySelector('[data-action="edit"]').value,
    completed: row.querySelector('[data-action="toggle"]').checked,
  })),
  errors: Array.from(document.querySelectorAll("[data-error]")).map((node) =>
    node.textContent
  ),
  controls: {
    addInput: document.querySelector("[data-new-item]")?.disabled ?? null,
    add: document.querySelector('[data-action="add"]')?.disabled ?? null,
    global: Object.fromEntries(
      ["undo", "redo", "complete-all", "clear-history", "close"].map((action) => [
        action,
        document.querySelector('[data-action="' + action + '"]')?.disabled ?? null,
      ]),
    ),
    items: Array.from(document.querySelectorAll("[data-item-id]")).map((row) => ({
      id: row.dataset.itemId,
      edit: row.querySelector('[data-action="edit"]')?.disabled ?? null,
      toggle: row.querySelector('[data-action="toggle"]')?.disabled ?? null,
      delete: row.querySelector('[data-action="delete"]')?.disabled ?? null,
      moveUp: row.querySelector('[data-action="move-up"]')?.disabled ?? null,
      moveDown: row.querySelector('[data-action="move-down"]')?.disabled ?? null,
    })),
  },
  url: location.href,
}))()`;

main().then(
  (code) => process.exit(code),
  (error) => {
    console.error(
      "SharedTree checklist smoke: " +
        (error && error.stack ? error.stack : String(error)),
    );
    process.exit(1);
  },
);

async function main() {
  if (!existsSync(bundle)) {
    console.error(
      "SharedTree checklist smoke: the browser bundle is missing.\n" +
        "Run `pnpm run build` in examples/shared_tree_checklist_lustre first.",
    );
    return 1;
  }

  if (!(await portIsOpen(4000))) {
    console.error(
      "SharedTree checklist smoke: Floodgate is not available on port 4000.\n" +
        "Start it with: just integration-up",
    );
    return 1;
  }

  const browser = findBrowser();
  if (browser === null) {
    console.log(
      "SharedTree checklist smoke: SKIPPED - no launchable Chromium-based " +
        "browser found.\n  Set WATERSHED_CHROME or install Chrome/Chromium.",
    );
    return 0;
  }

  let server = null;
  let chrome = null;
  let browserEndpoint = null;
  let secondContext = null;

  try {
    server = await startChecklistServer({ appRoot, port: 0 });
    const origin = "http://127.0.0.1:" + server.port + "/";

    rmSync(profile, { recursive: true, force: true });
    mkdirSync(profile, { recursive: true });
    chrome = spawn(
      browser,
      [
        "--headless=new",
        "--no-sandbox",
        "--disable-gpu",
        "--disable-dev-shm-usage",
        "--no-first-run",
        "--no-default-browser-check",
        "--remote-debugging-port=0",
        "--user-data-dir=" + profile,
        origin,
      ],
      { stdio: ["ignore", "pipe", "pipe"] },
    );
    chrome.stdout.resume();

    browserEndpoint = await devtoolsEndpoint(chrome);
    const firstTarget = await firstPageTarget(browserEndpoint, origin);
    const report = await withPage(
      firstTarget.webSocketDebuggerUrl,
      PAGE_MS,
      "the first checklist page did not finish",
      async (firstSend) => {
        await firstSend("Runtime.enable");
        const firstReady = await waitForSnapshot(
          firstSend,
          "the first page to create and open a document",
          ready,
        );

        secondContext = await createBrowserContext(browserEndpoint);
        const secondTargetId = await createTarget(
          browserEndpoint,
          firstReady.url,
          secondContext,
        );
        const secondEndpoint = await targetEndpoint(
          browserEndpoint,
          secondTargetId,
        );

        return withPage(
          secondEndpoint,
          PAGE_MS,
          "the second checklist page did not finish",
          async (secondSend) => {
            await secondSend("Runtime.enable");
            const secondReady = await waitForSnapshot(
              secondSend,
              "the second page to open the created document",
              (value) =>
                ready(value) && value.document === firstReady.document,
            );
            assertClean(firstReady);
            assertClean(secondReady);

            await addItem(firstSend, "write plan");
            let pair = await waitForPair(
              firstSend,
              secondSend,
              "the added item to converge",
              (value) =>
                value.items.length === 1 &&
                value.items[0].text === "write plan",
            );
            const planId = pair.first.items[0].id;

            await editItem(secondSend, planId, "review plan");
            await clickAction(secondSend, planId, "toggle");
            pair = await waitForPair(
              firstSend,
              secondSend,
              "the edit and completion state to converge",
              (value) =>
                value.items.length === 1 &&
                value.items[0].id === planId &&
                value.items[0].text === "review plan" &&
                value.items[0].completed,
            );

            await addItem(firstSend, "ship demo");
            await addItem(firstSend, "watch convergence");
            pair = await waitForPair(
              firstSend,
              secondSend,
              "three items to converge",
              (value) => value.items.length === 3,
            );
            const shipId = pair.first.items.find(
              (item) => item.text === "ship demo",
            ).id;
            await clickAction(secondSend, shipId, "delete");
            pair = await waitForPair(
              firstSend,
              secondSend,
              "the deletion to converge",
              (value) =>
                value.items.length === 2 &&
                value.items.every((item) => item.id !== shipId),
            );

            await addItem(firstSend, "race anchor");
            pair = await waitForPair(
              firstSend,
              secondSend,
              "the race fixture to converge",
              (value) => value.items.length === 3,
            );
            const originalIds = pair.first.items.map((item) => item.id);
            const firstId = originalIds[0];
            const editedId = originalIds[2];

            await Promise.all([
              clickAction(firstSend, firstId, "move-down"),
              editItem(secondSend, editedId, "edited during reorder"),
            ]);
            pair = await waitForPair(
              firstSend,
              secondSend,
              "the edit and reorder race to converge",
              (value) =>
                value.items.length === 3 &&
                value.items[0].id === originalIds[1] &&
                value.items[1].id === originalIds[0] &&
                value.items.find((item) => item.id === editedId)?.text ===
                  "edited during reorder" &&
                sameMembers(
                  value.items.map((item) => item.id),
                  originalIds,
                ),
            );

            await clickAction(firstSend, firstId, "move-up");
            pair = await waitForPair(
              firstSend,
              secondSend,
              "move-up to restore the original order",
              (value) =>
                value.items.map((item) => item.id).join(",") ===
                  originalIds.join(",") &&
                value.items.find((item) => item.id === editedId)?.text ===
                  "edited during reorder",
            );

            const beforeClear = pair.first.items;
            await clickGlobalAction(firstSend, "clear-history");
            const cleared = await waitForSnapshot(
              firstSend,
              "clear history without changing checklist data",
              (value) =>
                ready(value) &&
                value.undo === 0 &&
                value.redo === 0 &&
                JSON.stringify(value.items) === JSON.stringify(beforeClear),
            );
            assertClean(cleared);

            const pending = await clickGlobalActionAndSnapshot(
              firstSend,
              "complete-all",
            );
            if (pending.pending < 1 || !allControlsDisabled(pending.controls)) {
              throw new Error(
                "local pending work did not disable every editing control:\n" +
                  JSON.stringify(pending, null, 2),
              );
            }
            pair = await waitForPair(
              firstSend,
              secondSend,
              "complete all to converge as one local history step",
              (value) =>
                value.items.length === 3 &&
                value.items.every((item) => item.completed),
            );
            await waitForSnapshot(
              firstSend,
              "complete all to create one undo step",
              (value) => ready(value) && value.undo === 1 && value.redo === 0,
            );

            const peerEditedId = originalIds[1];
            await editItem(secondSend, peerEditedId, "peer text survives undo");
            pair = await waitForPair(
              firstSend,
              secondSend,
              "the peer edit before local undo",
              (value) =>
                value.items.find((item) => item.id === peerEditedId)?.text ===
                "peer text survives undo",
            );

            await clickGlobalAction(firstSend, "undo");
            pair = await waitForPair(
              firstSend,
              secondSend,
              "one undo to restore both incomplete items and preserve peer text",
              (value) =>
                value.items.find((item) => item.id === planId)?.completed ===
                  true &&
                value.items.find((item) => item.id === peerEditedId)
                  ?.completed === false &&
                value.items.find((item) => item.id === editedId)?.completed ===
                  false &&
                value.items.find((item) => item.id === peerEditedId)?.text ===
                  "peer text survives undo",
            );
            await waitForSnapshot(
              firstSend,
              "undo to leave exactly one redo step",
              (value) => ready(value) && value.undo === 0 && value.redo === 1,
            );

            await clickGlobalAction(firstSend, "redo");
            pair = await waitForPair(
              firstSend,
              secondSend,
              "one redo to complete both items again",
              (value) => value.items.every((item) => item.completed),
            );
            await waitForSnapshot(
              firstSend,
              "redo to restore exactly one undo step",
              (value) => ready(value) && value.undo === 1 && value.redo === 0,
            );

            await clickGlobalAction(firstSend, "undo");
            await waitForSnapshot(
              firstSend,
              "the second undo to restore the redo entry",
              (value) => ready(value) && value.undo === 0 && value.redo === 1,
            );
            await editItem(firstSend, editedId, "new local edit clears redo");
            pair = await waitForPair(
              firstSend,
              secondSend,
              "a new local edit to invalidate redo",
              (value) =>
                value.items.find((item) => item.id === editedId)?.text ===
                "new local edit clears redo",
            );
            await waitForSnapshot(
              firstSend,
              "redo invalidation after the new local edit",
              (value) => ready(value) && value.undo === 1 && value.redo === 0,
            );

            const beforeFinalClear = pair.first.items;
            await clickGlobalAction(firstSend, "clear-history");
            await waitForSnapshot(
              firstSend,
              "the final clear history to preserve data",
              (value) =>
                ready(value) &&
                value.undo === 0 &&
                value.redo === 0 &&
                JSON.stringify(value.items) ===
                  JSON.stringify(beforeFinalClear),
            );

            await editItem(firstSend, editedId, "retained handle closes cleanly");
            pair = await waitForPair(
              firstSend,
              secondSend,
              "the retained close-history fixture to converge",
              (value) =>
                value.items.find((item) => item.id === editedId)?.text ===
                "retained handle closes cleanly",
            );
            await waitForSnapshot(
              firstSend,
              "close to begin with one retained undo handle",
              (value) => ready(value) && value.undo === 1 && value.redo === 0,
            );

            await captureItemControl(firstSend, editedId, "edit");
            await clickAction(secondSend, editedId, "move-up");
            pair = await waitForPair(
              firstSend,
              secondSend,
              "the peer reorder of the captured target",
              (value) =>
                value.items.length === 3 &&
                value.items[1].id === editedId,
            );
            await triggerCapturedEdit(
              firstSend,
              "captured target follows peer reorder",
            );
            pair = await waitForPair(
              firstSend,
              secondSend,
              "the captured edit to follow physical identity",
              (value) =>
                value.items.find((item) => item.id === editedId)?.text ===
                "captured target follows peer reorder",
            );

            await captureItemControl(firstSend, planId, "toggle");
            const beforeRefusal = pair.first.items.filter(
              (item) => item.id !== planId,
            );
            await triggerCapturedAction(firstSend);
            await clickAction(secondSend, planId, "delete");
            const refused = await waitForSnapshot(
              firstSend,
              "the removed captured target to report a visible refusal",
              (value) =>
                value.status === "ready" &&
                value.pending === 0 &&
                value.errors.length === 1 &&
                JSON.stringify(value.items) === JSON.stringify(beforeRefusal),
            );
            const peerAfterRefusal = await waitForSnapshot(
              secondSend,
              "the peer removal to remain visible after refusal",
              (value) =>
                ready(value) &&
                JSON.stringify(value.items) === JSON.stringify(beforeRefusal),
            );
            assertClean(peerAfterRefusal);
            if (
              JSON.stringify(peerAfterRefusal.items) !==
              JSON.stringify(beforeRefusal)
            ) {
              throw new Error(
                "the removed captured action retargeted visible data:\n" +
                  JSON.stringify({ refused, peerAfterRefusal }, null, 2),
              );
            }
            const beforeClose = refused.items;

            await clickGlobalAction(firstSend, "close");
            const closed = await waitForSnapshot(
              firstSend,
              "close to drain cleanup and disable the app",
              (value) =>
                value.status === "closed" &&
                value.pending === 0 &&
                value.undo === 0 &&
                value.redo === 0 &&
                value.errors.length === 1 &&
                allControlsDisabled(value.controls),
            );

            await firstSend("Page.enable");
            await firstSend("Page.reload", { ignoreCache: true });
            const reloaded = await waitForSnapshot(
              firstSend,
              "reload to recover data with empty local history",
              (value) =>
                ready(value) &&
                value.document === firstReady.document &&
                value.undo === 0 &&
                value.redo === 0 &&
                JSON.stringify(value.items) ===
                  JSON.stringify(beforeClose),
            );
            const peer = await snapshot(secondSend);
            assertClean(reloaded);
            assertClean(peer);
            if (JSON.stringify(reloaded.items) !== JSON.stringify(peer.items)) {
              throw new Error(
                "reload did not recover the peer checklist:\n" +
                  JSON.stringify({ reloaded, peer }, null, 2),
              );
            }

            return { first: reloaded, second: peer, closed };
          },
        );
      },
    );

    console.log(
      "PASS: two browser contexts created one native SharedTree document and " +
        "proved CRUD, captured-target reorder and removal refusal, grouped " +
        "completion, undo/redo, peer-edit preservation, redo invalidation, " +
        "clear, close, and reload.",
    );
    console.log(JSON.stringify(report.first, null, 2));
    return 0;
  } finally {
    if (secondContext !== null && browserEndpoint !== null) {
      try {
        await disposeBrowserContext(browserEndpoint, secondContext);
      } catch {
        // The browser is already stopping.
      }
    }
    if (chrome !== null) {
      await stopBrowser(chrome);
    }
    server?.close();
    rmSync(profile, { recursive: true, force: true });
  }
}

function ready(value) {
  return (
    value.status === "ready" &&
    value.document &&
    value.pending === 0 &&
    value.errors.length === 0
  );
}

function assertClean(value) {
  if (!ready(value)) {
    throw new Error("the page is not ready:\n" + JSON.stringify(value, null, 2));
  }
}

async function waitForPair(firstSend, secondSend, label, predicate) {
  const deadline = Date.now() + STEP_MS;
  let first = null;
  let second = null;
  while (Date.now() < deadline) {
    [first, second] = await Promise.all([
      snapshot(firstSend),
      snapshot(secondSend),
    ]);
    if (
      predicate(first) &&
      predicate(second) &&
      JSON.stringify(first.items) === JSON.stringify(second.items) &&
      first.pending === 0 &&
      second.pending === 0 &&
      first.errors.length === 0 &&
      second.errors.length === 0
    ) {
      return { first, second };
    }
    await sleep(100);
  }
  throw new Error(
    label +
      " timed out:\n" +
      JSON.stringify({ first, second }, null, 2),
  );
}

async function waitForSnapshot(send, label, predicate) {
  const deadline = Date.now() + STEP_MS;
  let value = null;
  while (Date.now() < deadline) {
    value = await snapshot(send);
    if (predicate(value)) return value;
    await sleep(100);
  }
  throw new Error(label + " timed out:\n" + JSON.stringify(value, null, 2));
}

function snapshot(send) {
  return evaluate(send, snapshotExpression);
}

async function addItem(send, text) {
  const result = await call(
    send,
    function (value) {
      const input = document.querySelector("[data-new-item]");
      if (!input) return { ok: false, detail: "the add input is missing" };
      input.value = value;
      input.dispatchEvent(new Event("input", { bubbles: true }));
      const form = input.closest("form");
      if (!form) return { ok: false, detail: "the add form is missing" };
      form.requestSubmit();
      return { ok: true };
    },
    [text],
  );
  if (!result.ok) throw new Error(result.detail);
}

async function editItem(send, id, text) {
  const result = await call(
    send,
    function (itemId, value) {
      const row = Array.from(document.querySelectorAll("[data-item-id]")).find(
        (candidate) => candidate.dataset.itemId === itemId,
      );
      const input = row?.querySelector('[data-action="edit"]');
      if (!input) return { ok: false, detail: "the edit input is missing" };
      input.value = value;
      input.dispatchEvent(new Event("input", { bubbles: true }));
      input.dispatchEvent(new Event("change", { bubbles: true }));
      return { ok: true };
    },
    [id, text],
  );
  if (!result.ok) throw new Error(result.detail);
}

async function captureItemControl(send, id, action) {
  const result = await call(
    send,
    function (itemId, actionName) {
      const row = Array.from(document.querySelectorAll("[data-item-id]")).find(
        (candidate) => candidate.dataset.itemId === itemId,
      );
      const control = row?.querySelector(
        '[data-action="' + actionName + '"]',
      );
      if (!control) return { ok: false, detail: actionName + " is missing" };
      window.__capturedChecklistControl = control;
      return { ok: true };
    },
    [id, action],
  );
  if (!result.ok) throw new Error(result.detail);
}

async function triggerCapturedEdit(send, text) {
  const result = await call(
    send,
    function (value) {
      const input = window.__capturedChecklistControl;
      if (!input) return { ok: false, detail: "no item control was captured" };
      input.value = value;
      input.dispatchEvent(new Event("input", { bubbles: true }));
      input.dispatchEvent(new Event("change", { bubbles: true }));
      return { ok: true };
    },
    [text],
  );
  if (!result.ok) throw new Error(result.detail);
}

async function triggerCapturedAction(send) {
  const result = await call(
    send,
    function () {
      const control = window.__capturedChecklistControl;
      if (!control) return { ok: false, detail: "no item control was captured" };
      control.click();
      return { ok: true };
    },
    [],
  );
  if (!result.ok) throw new Error(result.detail);
}

async function clickAction(send, id, action) {
  const result = await call(
    send,
    function (itemId, actionName) {
      const row = Array.from(document.querySelectorAll("[data-item-id]")).find(
        (candidate) => candidate.dataset.itemId === itemId,
      );
      const button = row?.querySelector(
        '[data-action="' + actionName + '"]',
      );
      if (!button) return { ok: false, detail: actionName + " is missing" };
      if (button.disabled) {
        return { ok: false, detail: actionName + " is disabled" };
      }
      button.click();
      return { ok: true };
    },
    [id, action],
  );
  if (!result.ok) throw new Error(result.detail);
}

async function clickGlobalAction(send, action) {
  const result = await call(
    send,
    function (actionName) {
      const button = document.querySelector(
        '[data-action="' + actionName + '"]',
      );
      if (!button) return { ok: false, detail: actionName + " is missing" };
      if (button.disabled) {
        return { ok: false, detail: actionName + " is disabled" };
      }
      button.click();
      return { ok: true };
    },
    [action],
  );
  if (!result.ok) throw new Error(result.detail);
}

async function clickGlobalActionAndSnapshot(send, action) {
  const result = await call(
    send,
    function (actionName) {
      const button = document.querySelector(
        '[data-action="' + actionName + '"]',
      );
      if (!button) return { ok: false, detail: actionName + " is missing" };
      if (button.disabled) {
        return { ok: false, detail: actionName + " is disabled" };
      }
      button.click();
      return new Promise((resolveSnapshot) => {
        requestAnimationFrame(() => {
          const items = Array.from(
            document.querySelectorAll("[data-item-id]"),
          ).map((row) => ({
            id: row.dataset.itemId,
            edit: row.querySelector('[data-action="edit"]')?.disabled ?? null,
            toggle:
              row.querySelector('[data-action="toggle"]')?.disabled ?? null,
            delete:
              row.querySelector('[data-action="delete"]')?.disabled ?? null,
            moveUp:
              row.querySelector('[data-action="move-up"]')?.disabled ?? null,
            moveDown:
              row.querySelector('[data-action="move-down"]')?.disabled ?? null,
          }));
          resolveSnapshot({
            ok: true,
            pending: Number(
              document.querySelector("[data-pending]")?.dataset.pending ?? -1,
            ),
            controls: {
              addInput:
                document.querySelector("[data-new-item]")?.disabled ?? null,
              add:
                document.querySelector('[data-action="add"]')?.disabled ?? null,
              global: Object.fromEntries(
                ["undo", "redo", "complete-all", "clear-history", "close"].map(
                  (name) => [
                    name,
                    document.querySelector(
                      '[data-action="' + name + '"]',
                    )?.disabled ?? null,
                  ],
                ),
              ),
              items,
            },
          });
        });
      });
    },
    [action],
  );
  if (!result.ok) throw new Error(result.detail);
  return result;
}

function allControlsDisabled(controls) {
  return (
    controls.addInput === true &&
    controls.add === true &&
    Object.values(controls.global).every((disabled) => disabled === true) &&
    controls.items.length > 0 &&
    controls.items.every(({ id, ...item }) => {
      void id;
      return Object.values(item).every((disabled) => disabled === true);
    })
  );
}

function sameMembers(actual, expected) {
  return (
    actual.length === expected.length &&
    new Set(actual).size === actual.length &&
    expected.every((id) => actual.includes(id))
  );
}

function portIsOpen(port) {
  return new Promise((resolveOpen) => {
    const socket = connect({ host: "127.0.0.1", port });
    socket.setTimeout(500);
    socket.once("connect", () => {
      socket.destroy();
      resolveOpen(true);
    });
    socket.once("timeout", () => {
      socket.destroy();
      resolveOpen(false);
    });
    socket.once("error", () => resolveOpen(false));
  });
}

async function evaluate(send, expression) {
  const result = await send("Runtime.evaluate", {
    expression,
    returnByValue: true,
    awaitPromise: true,
  });
  if (result.exceptionDetails) {
    throw new Error("evaluation failed: " + JSON.stringify(result.exceptionDetails));
  }
  return result.result.value;
}

function call(send, fn, args) {
  return evaluate(send, `(${fn.toString()})(...${JSON.stringify(args)})`);
}

async function browserCommand(browserEndpoint, method, params = {}) {
  return new Promise((resolveCommand, rejectCommand) => {
    const socket = new WebSocket(browserEndpoint);
    const timer = setTimeout(() => {
      socket.close();
      rejectCommand(
        new Error(method + " did not finish within " + BROWSER_START_MS + "ms"),
      );
    }, BROWSER_START_MS);
    socket.on("error", rejectCommand);
    socket.on("message", (raw) => {
      const message = JSON.parse(raw.toString());
      if (message.id !== 1) return;
      clearTimeout(timer);
      socket.close();
      if (message.error) rejectCommand(new Error(JSON.stringify(message.error)));
      else resolveCommand(message.result);
    });
    socket.on("open", () => {
      socket.send(JSON.stringify({ id: 1, method, params }));
    });
  });
}

function createBrowserContext(browserEndpoint) {
  return browserCommand(browserEndpoint, "Target.createBrowserContext").then(
    (result) => result.browserContextId,
  );
}

function disposeBrowserContext(browserEndpoint, browserContextId) {
  return browserCommand(browserEndpoint, "Target.disposeBrowserContext", {
    browserContextId,
  });
}

function createTarget(browserEndpoint, url, browserContextId) {
  return browserCommand(browserEndpoint, "Target.createTarget", {
    url,
    browserContextId,
  }).then((result) => result.targetId);
}

async function firstPageTarget(browserEndpoint, origin) {
  const deadline = Date.now() + BROWSER_START_MS;
  while (Date.now() < deadline) {
    const targets = await listPageTargets(browserEndpoint);
    const match = targets.find(
      (target) =>
        target.type === "page" &&
        target.url.startsWith(origin) &&
        target.webSocketDebuggerUrl,
    );
    if (match) return match;
    await sleep(100);
  }
  throw new Error("no page target for " + origin + " appeared");
}

async function targetEndpoint(browserEndpoint, targetId) {
  const deadline = Date.now() + BROWSER_START_MS;
  while (Date.now() < deadline) {
    const targets = await listPageTargets(browserEndpoint);
    const match = targets.find(
      (target) =>
        (target.id === targetId || target.targetId === targetId) &&
        target.webSocketDebuggerUrl,
    );
    if (match) return match.webSocketDebuggerUrl;
    await sleep(100);
  }
  throw new Error("no debugger target for " + targetId + " appeared");
}

async function listPageTargets(browserEndpoint) {
  const origin = new URL(browserEndpoint);
  const response = await fetch("http://" + origin.host + "/json/list");
  return response.json();
}
