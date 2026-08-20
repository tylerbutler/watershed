// The real-browser durability gate for markdown_notes_lustre.
//
//     pnpm run build
//     node smoke/browser.mjs
//
// It reuses the repository's CDP/Chromium helpers and the reference signaling
// service to prove the durable-offline benchmark against a real browser:
//
//   - visit the built app online and warm its service-worker shell;
//   - create and save a note;
//   - take network and signaling away, reload, and reopen the note from
//     IndexedDB;
//   - edit offline, save again, reload, and reopen the newer note from
//     IndexedDB;
//   - bring signaling back, reopen the old page online, join the same document
//     from a fresh browser context with no local snapshot, and prove both pages
//     hold the full converged note;
//   - corrupt the old page's IndexedDB snapshot, prove the app gates editing
//     while a live peer still renders the note, then explicitly replace the
//     broken snapshot and prove offline editing resumes.
//
// Exit codes: 0 when the gate passed *or* Chromium is unavailable (explicit
// skip, matching the repository convention), 1 on failure.

import { spawn } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, rmSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import WebSocket from "ws";

import { startSignalingServer } from "../../../tools/signaling/server.mjs";
import {
  BROWSER_START_MS,
  devtoolsEndpoint,
  findBrowser,
  sleep,
  startServer,
  stopBrowser,
  withPage,
} from "../../../smoke/cdp.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const appRoot = resolve(here, "..");
const bundle = join(appRoot, "dist", "markdown_notes_lustre.mjs");
const serviceWorker = join(appRoot, "sw.js");
const page = readFileSync(join(appRoot, "index.html"), "utf8");
const profile = join(appRoot, "build", "browser-smoke-profile");

const NOTE_NAME = "field notes";
const ONLINE_TEXT = "# field notes\nfirst online line\n";
const OFFLINE_TEXT = "# field notes\nfirst online line\noffline reload line\n";
const RECOVERED_TEXT =
  "# field notes\nfirst online line\noffline reload line\nrecovered after repair\n";

const OLD_PAGE_MS = 240_000;
const FRESH_PAGE_MS = 90_000;
const STEP_MS = 20_000;

main().then(
  (code) => process.exit(code),
  (error) => {
    console.error(
      "markdown notes smoke: " +
        (error && error.stack ? error.stack : String(error)),
    );
    process.exit(1);
  },
);

async function main() {
  if (!existsSync(bundle) || !existsSync(serviceWorker)) {
    console.error(
      "markdown notes smoke: the built app is missing.\n" +
        "Run `pnpm run build` in examples/markdown_notes_lustre first.",
    );
    return 1;
  }

  const browser = findBrowser();
  if (browser === null) {
    console.log(
      "markdown notes smoke: SKIPPED — no launchable Chromium-based browser found.\n" +
        "  Set WATERSHED_CHROME to one, or install Chrome/Chromium.\n" +
        "  The deterministic convergence smoke still covers the attach/save\n" +
        "  story; only the real IndexedDB/service-worker gate is skipped.",
    );
    return 0;
  }
  console.log("markdown notes smoke: browser " + browser);

  let signaling = null;
  let signalingPort = 0;
  let server = null;
  let chrome = null;
  let browserEndpoint = null;
  let freshContextId = null;

  try {
    signaling = startSignalingServer({ port: 0 });
    signalingPort = await signaling.listening;
    console.log(
      "markdown notes smoke: signaling ws://127.0.0.1:" + signalingPort + "/",
    );

    server = await startServer(appRoot, page);
    const origin = "http://127.0.0.1:" + server.port + "/";
    const launchUrl =
      origin + "?signaling=" + encodeURIComponent(signalingUrl(signalingPort));
    console.log("markdown notes smoke: serving " + appRoot + " at " + origin);

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
        "--disable-features=WebRtcHideLocalIpsWithMdns",
        launchUrl,
      ],
      { stdio: ["ignore", "pipe", "pipe"] },
    );
    chrome.stdout.resume();

    browserEndpoint = await devtoolsEndpoint(chrome);
    console.log("markdown notes smoke: devtools " + browserEndpoint);
    const oldTarget = await firstPageTarget(browserEndpoint, origin);

    const report = await withPage(
      oldTarget.webSocketDebuggerUrl,
      OLD_PAGE_MS,
      "the persisted page did not finish within " + OLD_PAGE_MS + "ms",
      async (send) => {
        await send("Runtime.enable");
        await send("Page.enable");
        await send("Network.enable");

        await waitForNotesApp(send);
        await ensureServiceWorkerControl(send);

        console.log("markdown notes smoke: online visit");
        let state = await waitForSnapshot(
          send,
          "the shared channels to open online",
          (snapshot) =>
            snapshot.phase === "ready" &&
            snapshot.shared === "ready" &&
            snapshot.save !== "waiting",
        );
        const documentUrl = state.url;

        await createNote(send, NOTE_NAME);
        state = await waitForSnapshot(
          send,
          "the created note to open",
          (snapshot) =>
            snapshot.noteNames.includes(NOTE_NAME) &&
            snapshot.openNote === NOTE_NAME &&
            snapshot.editorValue !== null,
        );

        const initialSavedDigest = state.savedDigest;
        await setEditorText(send, ONLINE_TEXT);
        state = await waitForSavedDigest(send, initialSavedDigest, ONLINE_TEXT);

        console.log("markdown notes smoke: stopping signaling and going offline");
        await signaling.close();
        signaling = null;
        await setOffline(send, true);
        await reload(send);

        await waitForNotesApp(send);
        state = await waitForSnapshot(
          send,
          "the offline reload to reopen from IndexedDB",
          (snapshot) =>
            snapshot.phase === "ready" &&
            snapshot.storage === "loaded" &&
            snapshot.noteNames.includes(NOTE_NAME),
        );
        await openNote(send, NOTE_NAME);
        state = await waitForSnapshot(
          send,
          "the saved note to reopen offline",
          (snapshot) =>
            snapshot.openNote === NOTE_NAME &&
            snapshot.editorValue === ONLINE_TEXT,
        );

        console.log(
          "markdown notes smoke: editing offline, saving, and reloading again",
        );
        const durableDigest = state.savedDigest;
        await setEditorText(send, OFFLINE_TEXT);
        state = await waitForSavedDigest(send, durableDigest, OFFLINE_TEXT);
        await reload(send);

        await waitForNotesApp(send);
        state = await waitForSnapshot(
          send,
          "the pagehide reload to reopen from IndexedDB",
          (snapshot) =>
            snapshot.phase === "ready" &&
            snapshot.storage === "loaded" &&
            snapshot.noteNames.includes(NOTE_NAME),
        );
        await openNote(send, NOTE_NAME);
        state = await waitForSnapshot(
          send,
          "the pagehide-saved note to reopen offline",
          (snapshot) =>
            snapshot.openNote === NOTE_NAME &&
            snapshot.editorValue === OFFLINE_TEXT,
        );

        console.log("markdown notes smoke: restoring networking");
        signaling = startSignalingServer({ port: signalingPort });
        await signaling.listening;
        await setOffline(send, false);
        await reload(send);

        await waitForNotesApp(send);
        state = await waitForSnapshot(
          send,
          "the old page to reopen online",
          (snapshot) =>
            snapshot.phase === "ready" &&
            snapshot.storage === "loaded" &&
            snapshot.noteNames.includes(NOTE_NAME),
        );
        await openNote(send, NOTE_NAME);
        state = await waitForSnapshot(
          send,
          "the old page to show the durable note online",
          (snapshot) =>
            snapshot.openNote === NOTE_NAME &&
            snapshot.editorValue === OFFLINE_TEXT,
        );

        console.log("markdown notes smoke: opening a fresh peer");
        freshContextId = await createBrowserContext(browserEndpoint);
        const freshTargetId = await createTarget(
          browserEndpoint,
          documentUrl,
          freshContextId,
        );
        const freshEndpoint = await targetEndpoint(browserEndpoint, freshTargetId);

        const converged = await withPage(
          freshEndpoint,
          FRESH_PAGE_MS,
          "the fresh peer did not converge within " + FRESH_PAGE_MS + "ms",
          async (freshSend) => {
            await freshSend("Runtime.enable");
            await freshSend("Page.enable");
            await freshSend("Network.enable");

            await waitForNotesApp(freshSend);
            let fresh = await waitForSnapshot(
              freshSend,
              "the fresh peer to merge the old page",
              (snapshot) =>
                snapshot.phase === "ready" &&
                snapshot.storage === "none" &&
                snapshot.noteNames.includes(NOTE_NAME),
            );
            await openNote(freshSend, NOTE_NAME);
            fresh = await waitForSnapshot(
              freshSend,
              "the fresh peer to open the converged note",
              (snapshot) =>
                snapshot.openNote === NOTE_NAME &&
                snapshot.editorValue === OFFLINE_TEXT &&
                snapshot.peers >= 1,
            );
            const old = await waitForSnapshot(
              send,
              "the old page to see the fresh peer",
              (snapshot) =>
                snapshot.openNote === NOTE_NAME &&
                snapshot.editorValue === OFFLINE_TEXT &&
                snapshot.peers >= 1,
            );
            return { old, fresh };
          },
        );

        state = converged.old;

        console.log("markdown notes smoke: corrupting the old local snapshot");
        await corruptLocalSnapshot(send);
        await reload(send);

        await waitForNotesApp(send);
        state = await waitForSnapshot(
          send,
          "the old page to gate on the corrupt snapshot",
          (snapshot) =>
            snapshot.phase === "ready" &&
            snapshot.recovery === "required" &&
            snapshot.noteNames.includes(NOTE_NAME) &&
            snapshot.createInputDisabled &&
            snapshot.recoveryButtonDisabled === false,
        );
        await openNote(send, NOTE_NAME);
        state = await waitForSnapshot(
          send,
          "the gated page to keep rendering the converged note read-only",
          (snapshot) =>
            snapshot.openNote === NOTE_NAME &&
            snapshot.editorValue === OFFLINE_TEXT &&
            snapshot.recovery === "required" &&
            snapshot.editorReadOnly &&
            snapshot.createInputDisabled &&
            snapshot.deleteDisabled &&
            snapshot.tagInputDisabled &&
            snapshot.toolbarDisabled,
        );

        console.log("markdown notes smoke: explicitly recovering the snapshot");
        await clickRecovery(send);
        state = await waitForSnapshot(
          send,
          "the old page to clear recovery after replace",
          (snapshot) =>
            snapshot.recovery === "none" &&
            snapshot.save === "saved" &&
            snapshot.editorReadOnly === false &&
            snapshot.createInputDisabled === false &&
            snapshot.deleteDisabled === false &&
            snapshot.tagInputDisabled === false &&
            snapshot.toolbarDisabled === false,
        );
        const repairedDigest = state.savedDigest;

        console.log("markdown notes smoke: reloading the repaired snapshot offline");
        await setOffline(send, true);
        await reload(send);

        await waitForNotesApp(send);
        state = await waitForSnapshot(
          send,
          "the repaired snapshot to reopen offline",
          (snapshot) =>
            snapshot.phase === "ready" &&
            snapshot.storage === "loaded" &&
            snapshot.recovery === "none" &&
            snapshot.noteNames.includes(NOTE_NAME),
        );
        await openNote(send, NOTE_NAME);
        state = await waitForSnapshot(
          send,
          "the repaired note to stay editable offline",
          (snapshot) =>
            snapshot.openNote === NOTE_NAME &&
            snapshot.editorValue === OFFLINE_TEXT &&
            snapshot.editorReadOnly === false,
        );

        console.log("markdown notes smoke: editing again after recovery");
        await setEditorText(send, RECOVERED_TEXT);
        state = await waitForSavedDigest(send, repairedDigest, RECOVERED_TEXT);
        await reload(send);

        await waitForNotesApp(send);
        state = await waitForSnapshot(
          send,
          "the post-recovery save to reopen offline",
          (snapshot) =>
            snapshot.phase === "ready" &&
            snapshot.storage === "loaded" &&
            snapshot.recovery === "none" &&
            snapshot.noteNames.includes(NOTE_NAME),
        );
        await openNote(send, NOTE_NAME);
        state = await waitForSnapshot(
          send,
          "the post-recovery note to persist offline",
          (snapshot) =>
            snapshot.openNote === NOTE_NAME &&
            snapshot.editorValue === RECOVERED_TEXT &&
            snapshot.editorReadOnly === false,
        );

        return {
          documentUrl,
          old: summary(state),
          fresh: summary(converged.fresh),
        };
      },
    );

    console.log("─".repeat(72));
    console.log(JSON.stringify(report, null, 2));
    console.log("─".repeat(72));
    console.log(
      "PASS: offline reload reopened from IndexedDB, a second offline save\n" +
        "survived another reload, a fresh peer converged, and a corrupt local\n" +
        "snapshot forced a visible recovery gate until an explicit replace\n" +
        "restored offline durability and editing.",
    );
    return 0;
  } finally {
    if (freshContextId !== null && browserEndpoint !== null) {
      try {
        await disposeBrowserContext(browserEndpoint, freshContextId);
      } catch {
        // The browser is already dying; nothing left to clean here.
      }
    }
    if (chrome) {
      await stopBrowser(chrome);
    }
    if (server) {
      server.close();
    }
    if (signaling) {
      await signaling.close();
    }
    rmSync(profile, { recursive: true, force: true });
  }
}

function signalingUrl(port) {
  return "ws://127.0.0.1:" + port + "/";
}

async function waitForNotesApp(send) {
  const deadline = Date.now() + BROWSER_START_MS;
  let lastError = "";
  while (Date.now() < deadline) {
    try {
      const probe = await evaluate(
        send,
        `(() => ({
          ready: typeof window.__watershedMarkdownNotesLoaded === "function",
          error: window.__watershedLoadError || "",
        }))()`,
      );
      if (probe.ready) {
        return;
      }
      if (probe.error) {
        throw new Error("the app failed to load: " + probe.error);
      }
    } catch (error) {
      lastError = String(error);
    }
    await sleep(100);
  }
  throw new Error(
    "the markdown notes app never loaded" +
      (lastError ? " (" + lastError + ")" : ""),
  );
}

async function ensureServiceWorkerControl(send) {
  const controlled = await evaluate(
    send,
    `(async () => {
      if (!("serviceWorker" in navigator)) {
        return { ok: false, detail: "serviceWorker unavailable" };
      }
      await navigator.serviceWorker.ready;
      if (navigator.serviceWorker.controller) {
        return { ok: true };
      }
      await new Promise((resolve) => {
        const timer = setTimeout(resolve, 5000);
        navigator.serviceWorker.addEventListener(
          "controllerchange",
          () => {
            clearTimeout(timer);
            resolve(undefined);
          },
          { once: true },
        );
      });
      return {
        ok: !!navigator.serviceWorker.controller,
        detail: navigator.serviceWorker.controller
          ? ""
          : "the service worker never took control",
      };
    })()`,
    true,
  );
  if (!controlled.ok) {
    throw new Error("the app shell never became controllable: " + controlled.detail);
  }
}

async function waitForSnapshot(send, label, predicate, timeoutMs = STEP_MS) {
  const deadline = Date.now() + timeoutMs;
  let last = null;
  while (Date.now() < deadline) {
    await waitForNotesApp(send);
    last = await snapshot(send);
    if (last.loadError) {
      throw new Error("the app reported a load error: " + last.loadError);
    }
    if (predicate(last)) {
      return last;
    }
    await sleep(100);
  }
  throw new Error(label + " timed out:\n" + JSON.stringify(last, null, 2));
}

function summary(snapshot) {
  return {
    url: snapshot.url,
    phase: snapshot.phase,
    shared: snapshot.shared,
    storage: snapshot.storage,
    save: snapshot.save,
    recovery: snapshot.recovery,
    peers: snapshot.peers,
    noteNames: snapshot.noteNames,
    openNote: snapshot.openNote,
    editorValue: snapshot.editorValue,
  };
}

function snapshot(send) {
  return evaluate(
    send,
    `(() => {
      const app = document.querySelector(".app");
      const editor = document.querySelector('textarea[data-smoke="editor"]');
      const readText = (selector) =>
        document.querySelector(selector)?.textContent?.trim() ?? "";
      return {
        loadError: window.__watershedLoadError || "",
        url: location.href,
        phase: app?.dataset.smokePhase ?? "",
        shared: app?.dataset.smokeShared ?? "",
        storage: app?.dataset.smokeStorage ?? "",
        save: app?.dataset.smokeSave ?? "",
        recovery: app?.dataset.smokeRecovery ?? "",
        savedDigest: app?.dataset.smokeSavedDigest ?? "",
        peers: Number(app?.dataset.smokePeers ?? "0"),
        noteCount: Number(app?.dataset.smokeNoteCount ?? "0"),
        openNote: app?.dataset.smokeOpenNote ?? "",
        noteNames: Array.from(
          document.querySelectorAll('[data-smoke="note-open"]'),
          (button) => button.dataset.noteName ?? button.textContent ?? "",
        ),
        editorValue: editor ? editor.value : null,
        editorReadOnly: !!editor?.readOnly,
        createInputDisabled:
          document.querySelector('[data-smoke="create-note-input"]')?.disabled ??
          false,
        deleteDisabled: (() => {
          const buttons = Array.from(
            document.querySelectorAll('[data-smoke="note-delete"]'),
          );
          return buttons.length > 0 && buttons.every((button) => button.disabled);
        })(),
        tagInputDisabled:
          document.querySelector('[data-smoke="tag-input"]')?.disabled ?? false,
        tagAddDisabled:
          document.querySelector('[data-smoke="add-tag"]')?.disabled ?? false,
        toolbarDisabled: (() => {
          const buttons = Array.from(
            document.querySelectorAll('[data-smoke="format-button"]'),
          );
          return buttons.length > 0 && buttons.every((button) => button.disabled);
        })(),
        recoveryButtonDisabled:
          document.querySelector('[data-smoke="recovery-replace"]')?.disabled ??
          true,
        networkText: readText('[data-smoke="network-status"]'),
        storageText: readText('[data-smoke="storage-status"]'),
        saveText: readText('[data-smoke="save-status"]'),
        recoveryText: readText('[data-smoke="recovery-status"]'),
      };
    })()`,
  );
}

async function waitForSavedDigest(send, previousDigest, expectedText) {
  return waitForSnapshot(
    send,
    "the local snapshot to save",
    (snapshot) =>
      snapshot.openNote === NOTE_NAME &&
      snapshot.editorValue === expectedText &&
      snapshot.save === "saved" &&
      snapshot.savedDigest !== previousDigest,
    STEP_MS,
  );
}

async function createNote(send, name) {
  const result = await call(
    send,
    async function (noteName) {
      const input = document.querySelector('[data-smoke="create-note-input"]');
      if (!input) {
        return { ok: false, detail: "create controls are missing" };
      }
      input.focus();
      input.value = noteName;
      input.dispatchEvent(new Event("input", { bubbles: true }));
      await new Promise((resolve) => requestAnimationFrame(() => resolve()));
      const button = document.querySelector('[data-smoke="create-note"]');
      if (!button || button.disabled) {
        return { ok: false, detail: "create button never became enabled" };
      }
      button.click();
      return { ok: true };
    },
    [name],
    true,
  );
  if (!result.ok) {
    throw new Error(result.detail);
  }
}

async function openNote(send, name) {
  const result = await call(
    send,
    function (noteName) {
      const selector =
        '[data-smoke="note-open"][data-note-name="' +
        CSS.escape(noteName) +
        '"]';
      const button = document.querySelector(selector);
      if (!button) {
        return { ok: false, detail: "no note named " + noteName };
      }
      button.click();
      return { ok: true };
    },
    [name],
  );
  if (!result.ok) {
    throw new Error(result.detail);
  }
}

async function clickRecovery(send) {
  const result = await call(
    send,
    function () {
      const button = document.querySelector('[data-smoke="recovery-replace"]');
      if (!button) {
        return { ok: false, detail: "the recovery button is missing" };
      }
      if (button.disabled) {
        return { ok: false, detail: "the recovery button is disabled" };
      }
      button.click();
      return { ok: true };
    },
    [],
  );
  if (!result.ok) {
    throw new Error(result.detail);
  }
}

async function corruptLocalSnapshot(send) {
  const result = await call(
    send,
    async function () {
      const room = new URL(location.href).searchParams.get("document");
      if (!room) {
        return { ok: false, detail: "no ?document room id to corrupt" };
      }

      let database;
      try {
        database = await new Promise((resolve, reject) => {
          const request = indexedDB.open("watershed", 1);
          request.onerror = () =>
            reject(request.error ?? new Error("IndexedDB open failed"));
          request.onsuccess = () => resolve(request.result);
        });

        await new Promise((resolve, reject) => {
          const transaction = database.transaction("snapshots", "readwrite");
          transaction.oncomplete = () => resolve(undefined);
          transaction.onerror = () =>
            reject(
              transaction.error ?? new Error("IndexedDB write transaction failed"),
            );
          transaction.onabort = () =>
            reject(
              transaction.error ??
                new Error("IndexedDB write transaction aborted"),
            );
          transaction
            .objectStore("snapshots")
            .put("not valid json", JSON.stringify([room, "markdown-notes/v2"]));
        });

        return { ok: true };
      } catch (error) {
        return {
          ok: false,
          detail: error && error.message ? error.message : String(error),
        };
      } finally {
        database?.close();
      }
    },
    [],
    true,
  );
  if (!result.ok) {
    throw new Error(result.detail);
  }
}

async function setEditorText(send, text) {
  const result = await call(
    send,
    function (value) {
      const editor = document.querySelector('textarea[data-smoke="editor"]');
      if (!editor) {
        return { ok: false, detail: "the editor is missing" };
      }
      editor.focus();
      editor.value = value;
      editor.selectionStart = value.length;
      editor.selectionEnd = value.length;
      editor.dispatchEvent(new Event("input", { bubbles: true }));
      return { ok: true };
    },
    [text],
  );
  if (!result.ok) {
    throw new Error(result.detail);
  }
}

async function reload(send) {
  await evaluate(
    send,
    `(() => {
      setTimeout(() => location.reload(), 0);
      return true;
    })()`,
  );
}

async function setOffline(send, offline) {
  await send("Network.emulateNetworkConditions", {
    offline,
    latency: 0,
    downloadThroughput: offline ? 0 : 50 * 1024 * 1024,
    uploadThroughput: offline ? 0 : 20 * 1024 * 1024,
    connectionType: offline ? "none" : "wifi",
  });
}

async function evaluate(send, expression, awaitPromise = false) {
  const result = await send("Runtime.evaluate", {
    expression,
    awaitPromise,
    returnByValue: true,
  });
  if (result.exceptionDetails) {
    throw new Error("evaluation failed: " + JSON.stringify(result.exceptionDetails));
  }
  return result.result.value;
}

function call(send, fn, args, awaitPromise = false) {
  return evaluate(send, `(${fn.toString()})(...${JSON.stringify(args)})`, awaitPromise);
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

    socket.on("error", (error) => {
      clearTimeout(timer);
      rejectCommand(error);
    });

    socket.on("message", (raw) => {
      const message = JSON.parse(raw.toString());
      if (message.id !== 1) {
        return;
      }
      clearTimeout(timer);
      socket.close();
      if (message.error) {
        rejectCommand(new Error(JSON.stringify(message.error)));
      } else {
        resolveCommand(message.result);
      }
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
    if (match) {
      return match;
    }
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
    if (match) {
      return match.webSocketDebuggerUrl;
    }
    await sleep(100);
  }
  throw new Error("no debugger target for " + targetId + " appeared");
}

async function listPageTargets(browserEndpoint) {
  const origin = new URL(browserEndpoint);
  const response = await fetch("http://" + origin.host + "/json/list");
  return response.json();
}
