// Drives the project room through two real browser tabs and a live floodgate
// dev server. The deterministic package test covers the same flow with sluice.

import { spawn } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, rmSync } from "node:fs";
import { connect } from "node:net";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import WebSocket from "ws";

import {
  BROWSER_START_MS,
  devtoolsEndpoint,
  findBrowser,
  sleep,
  startServer,
  stopBrowser,
  withPage,
} from "./cdp.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const repo = resolve(here, "..");
const example = join(repo, "examples", "project_room_lustre");
const bundle = join(example, "dist", "project_room_lustre.mjs");
const profile = join(repo, "build", "project-room-smoke-profile");
const GATE_MS = 90_000;

main().then(
  (code) => process.exit(code),
  (error) => {
    console.error(
      "project room smoke: " + (error && error.stack ? error.stack : error),
    );
    process.exit(1);
  },
);

async function main() {
  if (!existsSync(bundle)) {
    console.error(
      "project room smoke: " +
        bundle +
        " is missing.\n" +
        "Build it first: pnpm --dir examples/project_room_lustre run build",
    );
    return 1;
  }

  const browser = findBrowser();
  if (browser === null) {
    console.log(
      "project room smoke: SKIPPED — no launchable Chromium-based browser found.\n" +
        "  Set WATERSHED_CHROME to one, or install Chrome/Chromium.\n" +
        "  The deterministic two-client sluice test still covers this flow.",
    );
    return 0;
  }

  try {
    await requireFloodgate();
  } catch (error) {
    console.error(
      "project room smoke: floodgate is not available at 127.0.0.1:4000.\n" +
        "  Start it with: just integration-up\n" +
        "  " +
        error.message,
    );
    return 1;
  }

  const page = readFileSync(join(example, "index.html"), "utf8");
  const server = await startServer(example, page);
  const document = "project-room-smoke-" + Date.now();
  const base = "http://127.0.0.1:" + server.port + "/";
  const firstUrl = base + "?document=" + document + "&tab=1";
  const secondUrl = base + "?document=" + document + "&tab=2";

  rmSync(profile, { recursive: true, force: true });
  mkdirSync(profile, { recursive: true });

  const chrome = spawn(
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
      firstUrl,
    ],
    { stdio: ["ignore", "pipe", "pipe"] },
  );
  chrome.stdout.resume();

  let exitCode = 1;
  try {
    const endpoint = await devtoolsEndpoint(chrome);
    const first = await pageTarget(endpoint, firstUrl);
    await waitFor(
      first,
      `document.querySelector('[data-runtime-status="ready"]') !== null`,
      "the first tab to become ready",
    );

    await openTab(endpoint, secondUrl);
    const second = await pageTarget(endpoint, secondUrl);
    await waitFor(
      second,
      `document.querySelector('[data-runtime-status="ready"]') !== null`,
      "the second tab to become ready",
    );

    await evaluate(
      first,
      `document.querySelector(
        '[data-action="select-task"][data-task-id="task-1"]'
      ).click()`,
    );
    await waitFor(
      first,
      `document.querySelector('[data-component="notes"]')
        ?.dataset.focusedTask === "task-1"`,
      "the first tab to focus task-1",
    );
    await assertValue(
      second,
      `document.querySelector('[data-component="notes"]')
        ?.dataset.focusedTask ?? null`,
      "",
      "selection leaked into the second tab",
    );

    await evaluate(
      first,
      `document.querySelector(
        '[data-action="complete-task"][data-task-id="task-1"]'
      ).click()`,
    );

    for (const [name, pageEndpoint] of [
      ["first", first],
      ["second", second],
    ]) {
      await waitFor(
        pageEndpoint,
        `document.querySelector(
          '[data-component="tasks"] [data-task-id="task-1"]'
        )?.dataset.completed === "true"`,
        name + " tab to show task-1 as complete",
      );
      await waitFor(
        pageEndpoint,
        `document.querySelector('[data-component="activity"]')
          ?.dataset.entryCount === "1"`,
        name + " tab to show one activity entry",
      );
      await assertValue(
        pageEndpoint,
        `document.querySelectorAll(
          '[data-component="activity"] li[data-task-id="task-1"]'
        ).length`,
        1,
        name + " tab did not show exactly one matching activity entry",
      );
      await assertNoRuntimeError(pageEndpoint, name);
    }
    await assertValue(
      second,
      `document.querySelector('[data-component="notes"]')
        ?.dataset.focusedTask ?? null`,
      "",
      "selection reached the second tab after collaborative convergence",
    );

    console.log(
      "PASS: selection stayed local while completion and one activity entry " +
        "converged across two browser tabs.",
    );
    exitCode = 0;
  } finally {
    await stopBrowser(chrome);
    server.close();
    rmSync(profile, { recursive: true, force: true });
  }
  return exitCode;
}

function requireFloodgate() {
  return new Promise((ok, failed) => {
    const socket = connect({ host: "127.0.0.1", port: 4000 });
    const timer = setTimeout(() => {
      socket.destroy();
      failed(new Error("connection timed out"));
    }, 2_000);
    socket.once("connect", () => {
      clearTimeout(timer);
      socket.destroy();
      ok();
    });
    socket.once("error", (error) => {
      clearTimeout(timer);
      failed(error);
    });
  });
}

function openTab(browserEndpoint, url) {
  return new Promise((ok, failed) => {
    const socket = new WebSocket(browserEndpoint);
    const timer = setTimeout(() => {
      socket.close();
      failed(new Error("the browser did not open the second tab"));
    }, BROWSER_START_MS);
    socket.on("error", (error) => {
      clearTimeout(timer);
      failed(error);
    });
    socket.on("message", (raw) => {
      const message = JSON.parse(raw.toString());
      if (message.id !== 1) return;
      clearTimeout(timer);
      socket.close();
      if (message.error) failed(new Error(JSON.stringify(message.error)));
      else ok(message.result.targetId);
    });
    socket.on("open", () => {
      socket.send(
        JSON.stringify({
          id: 1,
          method: "Target.createTarget",
          params: { url },
        }),
      );
    });
  });
}

async function pageTarget(browserEndpoint, url) {
  const origin = new URL(browserEndpoint);
  const listUrl = "http://" + origin.host + "/json/list";
  const deadline = Date.now() + BROWSER_START_MS;
  while (Date.now() < deadline) {
    const response = await fetch(listUrl);
    const targets = await response.json();
    const match = targets.find(
      (target) =>
        target.type === "page" &&
        target.url.startsWith(url) &&
        target.webSocketDebuggerUrl,
    );
    if (match) return match.webSocketDebuggerUrl;
    await sleep(100);
  }
  throw new Error("no page target for " + url + " appeared");
}

function evaluate(pageEndpoint, expression) {
  return withPage(
    pageEndpoint,
    GATE_MS,
    "browser evaluation timed out",
    async (send) => {
      await send("Runtime.enable");
      return evaluatedValue(await send("Runtime.evaluate", {
        expression,
        returnByValue: true,
      }));
    },
  );
}

function waitFor(pageEndpoint, expression, description) {
  return withPage(
    pageEndpoint,
    GATE_MS,
    "timed out waiting for " + description,
    async (send) => {
      await send("Runtime.enable");
      const deadline = Date.now() + GATE_MS;
      while (Date.now() < deadline) {
        const result = await send("Runtime.evaluate", {
          expression,
          returnByValue: true,
        });
        if (evaluatedValue(result) === true) return;

        const error = await send("Runtime.evaluate", {
          expression:
            `document.querySelector('[data-runtime-error="true"]')` +
            `?.textContent ?? null`,
          returnByValue: true,
        });
        const reason = evaluatedValue(error);
        if (reason !== null) throw new Error("page runtime failed: " + reason);
        await sleep(100);
      }
      throw new Error("timed out waiting for " + description);
    },
  );
}

async function assertValue(
  pageEndpoint,
  expression,
  expected,
  message,
) {
  const actual = await evaluate(pageEndpoint, expression);
  if (actual !== expected) {
    throw new Error(
      message + ": expected " + JSON.stringify(expected) +
        ", got " + JSON.stringify(actual),
    );
  }
}

async function assertNoRuntimeError(pageEndpoint, name) {
  const reason = await evaluate(
    pageEndpoint,
    `document.querySelector('[data-runtime-error="true"]')?.textContent ?? null`,
  );
  if (reason !== null) {
    throw new Error(name + " tab reported a runtime error: " + reason);
  }
}

function evaluatedValue(result) {
  if (result.exceptionDetails) {
    throw new Error(
      "browser evaluation failed: " + JSON.stringify(result.exceptionDetails),
    );
  }
  return result.result.value;
}
