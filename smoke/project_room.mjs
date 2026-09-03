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

    for (const [name, pageEndpoint] of [
      ["first", first],
      ["second", second],
    ]) {
      await waitFor(
        pageEndpoint,
        `document.querySelectorAll("[data-presence-peer]").length === 1`,
        name + " tab to see the other tab's presence",
      );
    }

    const firstName = await evaluate(
      first,
      `document.querySelector("[data-presence-self]")
        ?.dataset.presenceSelf ?? null`,
    );
    const secondName = await evaluate(
      second,
      `document.querySelector("[data-presence-self]")
        ?.dataset.presenceSelf ?? null`,
    );
    if (!firstName) throw new Error("the first tab has no local presence name");
    if (!secondName) {
      throw new Error("the second tab has no local presence name");
    }
    await evaluate(
      first,
      `(() => {
        const editor = document.querySelector("[data-notes-editor]");
        editor.focus();
        editor.value = "Shared project note";
        editor.setSelectionRange(7, 7);
        editor.dispatchEvent(new Event("input", { bubbles: true }));
      })()`,
    );
    await waitFor(
      second,
      `document.querySelector("[data-notes-editor]")?.value
        === "Shared project note"`,
      "the shared note to converge in the second tab",
    );
    await waitFor(
      second,
      `Array.from(document.querySelectorAll(
        '[data-component="notes"] [aria-hidden="true"] span'
      )).some((label) =>
        label.textContent === ${JSON.stringify(firstName)}
        && Number.parseFloat(label.parentElement.style.left) > 0
      )`,
      "the second tab to draw the first tab's cursor",
    );

    await evaluate(
      first,
      `document.querySelector(
        '[data-action="select-task"][data-task-id="task-1"]'
      ).click()`,
    );
    await waitFor(
      first,
      `document.querySelector('[data-component="inspector"]')
        ?.dataset.selectedTask === "task-1"`,
      "the first tab to inspect task-1",
    );
    await assertValue(
      second,
      `document.querySelector('[data-component="inspector"]')
        ?.dataset.selectedTask ?? null`,
      "",
      "the first selection changed the second tab's Inspector",
    );
    await waitFor(
      second,
      `document.querySelector(
        '[data-presence-task="task-1"]'
      )?.dataset.taskPeer === ${JSON.stringify(firstName)}`,
      "the second tab to show the first tab on task-1",
    );

    await evaluate(
      second,
      `document.querySelector(
        '[data-action="select-task"][data-task-id="task-2"]'
      ).click()`,
    );
    await waitFor(
      second,
      `document.querySelector('[data-component="inspector"]')
        ?.dataset.selectedTask === "task-2"`,
      "the second tab to inspect task-2",
    );
    await assertValue(
      first,
      `document.querySelector('[data-component="inspector"]')
        ?.dataset.selectedTask ?? null`,
      "task-1",
      "the second selection changed the first tab's Inspector",
    );
    await waitFor(
      first,
      `document.querySelector(
        '[data-presence-task="task-2"]'
      )?.dataset.taskPeer === ${JSON.stringify(secondName)}`,
      "the first tab to show the second tab on task-2",
    );

    await evaluate(
      first,
      `document.querySelector(
        '[data-action="toggle-results"]'
      ).click()`,
    );
    await waitFor(
      first,
      `document.querySelector('[data-component="poll"]')
        ?.dataset.resultsVisible === "true"`,
      "the first tab to show poll results",
    );
    await assertValue(
      second,
      `document.querySelector('[data-component="poll"]')
        ?.dataset.resultsVisible ?? null`,
      "false",
      "showing poll results changed the second tab",
    );

    for (const pageEndpoint of [first, second]) {
      await evaluate(
        pageEndpoint,
        `document.querySelector(
          '[data-action="toggle-approval"][data-choice-id="customer-research"]'
        ).click()`,
      );
    }
    for (const [name, pageEndpoint] of [
      ["first", first],
      ["second", second],
    ]) {
      await waitFor(
        pageEndpoint,
        `document.querySelector(
          '[data-choice-id="customer-research"]'
        )?.dataset.thresholdReached === "true"`,
        name + " tab to see the poll threshold",
      );
      await waitFor(
        pageEndpoint,
        `document.querySelectorAll(
          '[data-entry-kind="poll-threshold"]' +
          '[data-choice-id="customer-research"]'
        ).length === 1`,
        name + " tab to show one poll activity entry",
      );
    }

    await evaluate(
      first,
      `document.querySelector(
        '[data-action="claim-slot"][data-slot-id="facilitator"]'
      ).click()`,
    );
    for (const [name, pageEndpoint] of [
      ["first", first],
      ["second", second],
    ]) {
      await waitFor(
        pageEndpoint,
        `document.querySelector(
          '[data-slot-id="facilitator"]'
        )?.dataset.ownerLabel === ${JSON.stringify(firstName)}`,
        name + " tab to see the first Facilitator owner",
      );
      await waitFor(
        pageEndpoint,
        `document.querySelectorAll(
          '[data-entry-kind="ownership-change"]' +
          '[data-slot-id="facilitator"]'
        ).length === 1`,
        name + " tab to show the accepted claim activity entry",
      );
    }

    await evaluate(
      first,
      `document.querySelector(
        '[data-action="toggle-owner-details"]'
      ).click()`,
    );
    await waitFor(
      first,
      `document.querySelector('[data-component="ownership"]')
        ?.dataset.ownerDetailsVisible === "true"`,
      "the first tab to reveal owner details",
    );
    await assertValue(
      second,
      `document.querySelector('[data-component="ownership"]')
        ?.dataset.ownerDetailsVisible ?? null`,
      "false",
      "revealing owner details changed the second tab",
    );
    const firstOwnerId = await evaluate(
      first,
      `document.querySelector(
        '[data-slot-id="facilitator"]'
      )?.dataset.ownerId ?? ""`,
    );
    if (!firstOwnerId) {
      throw new Error("the first tab did not reveal the durable owner ID");
    }

    await waitFor(
      first,
      `document.querySelector(
        '[data-action="handoff-slot"][data-slot-id="facilitator"]'
      ) !== null`,
      "the Facilitator handoff control",
    );
    await evaluate(
      first,
      `document.querySelector(
        '[data-action="handoff-slot"][data-slot-id="facilitator"]'
      ).click()`,
    );
    for (const [name, pageEndpoint] of [
      ["first", first],
      ["second", second],
    ]) {
      await waitFor(
        pageEndpoint,
        `document.querySelector(
          '[data-slot-id="facilitator"]'
        )?.dataset.ownerLabel === ${JSON.stringify(secondName)}`,
        name + " tab to see the Facilitator handoff",
      );
      await waitFor(
        pageEndpoint,
        `document.querySelectorAll(
          '[data-entry-kind="ownership-change"]' +
          '[data-slot-id="facilitator"]'
        ).length === 2`,
        name + " tab to show both accepted ownership changes",
      );
    }

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
          ?.dataset.entryCount === "4"`,
        name + " tab to show all four activity entries",
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
      `document.querySelector('[data-component="inspector"]')
        ?.dataset.selectedTask ?? null`,
      "task-2",
      "collaborative convergence changed the second tab's Inspector",
    );

    await evaluate(
      first,
      `(() => {
        const input = document.querySelector("[data-palette-title]");
        input.focus();
        input.value = "Sprint checklist";
        input.dispatchEvent(new Event("input", { bubbles: true }));
      })()`,
    );
    await evaluate(
      first,
      `document.querySelector(
        '[data-action="add-component"]' +
        '[data-component-kind="project-room/checklist"]'
      ).click()`,
    );
    await waitFor(
      first,
      `Array.from(document.querySelectorAll(
        '[data-component-kind="checklist"][data-instance-id]'
      )).some((panel) =>
        panel.querySelector("h2")?.textContent === "Sprint checklist"
      )`,
      "the first tab to start the runtime-created Checklist",
    );
    const checklistId = await evaluate(
      first,
      `Array.from(document.querySelectorAll(
        '[data-component-kind="checklist"][data-instance-id]'
      )).find((panel) =>
        panel.querySelector("h2")?.textContent === "Sprint checklist"
      )?.dataset.instanceId ?? null`,
    );
    if (!checklistId) {
      throw new Error("the runtime-created Checklist has no instance ID");
    }
    await waitFor(
      second,
      `document.querySelector(
        '[data-instance-id=${JSON.stringify(checklistId)}]'
      )?.querySelector("h2")?.textContent === "Sprint checklist"`,
      "the second tab to start the same runtime-created Checklist",
    );

    await evaluate(
      first,
      `(() => {
        const input = document.querySelector(
          '[data-instance-id=${JSON.stringify(checklistId)}] ' +
          '[data-checklist-draft]'
        );
        input.focus();
        input.value = "Verify both clients";
        input.dispatchEvent(new Event("input", { bubbles: true }));
      })()`,
    );
    await evaluate(
      first,
      `document.querySelector(
        '[data-instance-id=${JSON.stringify(checklistId)}] ' +
        '[data-action="add-checklist-item"]'
      ).click()`,
    );
    await waitFor(
      first,
      `document.querySelector(
        '[data-instance-id=${JSON.stringify(checklistId)}] ' +
        'li[data-item-id] input'
      )?.value === "Verify both clients"`,
      "the first tab to add the runtime Checklist item",
    );
    const itemId = await evaluate(
      first,
      `document.querySelector(
        '[data-instance-id=${JSON.stringify(checklistId)}] ' +
        'li[data-item-id]'
      )?.dataset.itemId ?? null`,
    );
    if (!itemId) {
      throw new Error("the runtime Checklist item has no item ID");
    }
    await waitFor(
      second,
      `document.querySelector(
        '[data-instance-id=${JSON.stringify(checklistId)}] ' +
        'li[data-item-id=${JSON.stringify(itemId)}] input'
      )?.value === "Verify both clients"`,
      "the second tab to show the runtime Checklist item",
    );
    await evaluate(
      second,
      `document.querySelector(
        '[data-instance-id=${JSON.stringify(checklistId)}] ' +
        '[data-action="complete-checklist-item"]' +
        '[data-item-id=${JSON.stringify(itemId)}]'
      ).click()`,
    );
    for (const [name, pageEndpoint] of [
      ["first", first],
      ["second", second],
    ]) {
      await waitFor(
        pageEndpoint,
        `document.querySelector(
          '[data-instance-id=${JSON.stringify(checklistId)}] ' +
          '[data-action="reopen-checklist-item"]' +
          '[data-item-id=${JSON.stringify(itemId)}]'
        ) !== null`,
        name + " tab to show the runtime Checklist item as complete",
      );
    }

    await evaluate(
      first,
      `document.querySelector(
        '[data-controls-for=${JSON.stringify(checklistId)}] ' +
        '[data-action="move-component-up"]'
      ).click()`,
    );
    const movedOrder = [
      "tasks",
      "inspector",
      "poll",
      "ownership",
      "notes",
      "activity",
      "checklist",
      checklistId,
      "tally",
    ].join(",");
    for (const [name, pageEndpoint] of [
      ["first", first],
      ["second", second],
    ]) {
      await waitFor(
        pageEndpoint,
        `Array.from(document.querySelector(".workspace").children)
          .map((panel) =>
            panel.dataset.instanceId
            ?? panel.dataset.component
            ?? panel.querySelector("[data-instance-id]")?.dataset.instanceId
            ?? ""
          )
          .join(",") === ${JSON.stringify(movedOrder)}`,
        name + " tab to show the moved runtime Checklist order",
      );
    }

    await evaluate(
      first,
      `document.querySelector(
        '[data-controls-for=${JSON.stringify(checklistId)}] ' +
        '[data-action="remove-component"]'
      ).click()`,
    );
    for (const [name, pageEndpoint] of [
      ["first", first],
      ["second", second],
    ]) {
      await waitFor(
        pageEndpoint,
        `document.querySelector(
          '[data-instance-id=${JSON.stringify(checklistId)}]'
        ) === null`,
        name + " tab to remove the runtime-created Checklist",
      );
      await assertNoRuntimeError(pageEndpoint, name);
    }

    console.log(
      "PASS: local views stayed independent while tasks, poll threshold, " +
        "ownership handoff, notes, activity, and a runtime-created Checklist " +
        "converged across two tabs.",
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

// Headless Chromium can pause background-tab animation frames. Foreground each
// target before a DOM probe so pending Lustre renders can finish.
function evaluate(pageEndpoint, expression) {
  return withPage(
    pageEndpoint,
    GATE_MS,
    "browser evaluation timed out",
    async (send) => {
      await send("Page.bringToFront");
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
      await send("Page.bringToFront");
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
