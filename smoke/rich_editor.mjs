import { spawn } from "node:child_process";
import { existsSync, mkdirSync, rmSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import {
  BROWSER_START_MS,
  devtoolsEndpoint,
  findBrowser,
  sleep,
  startServer,
  stopBrowser,
  waitForPage,
  withPage,
} from "./cdp.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const repo = resolve(here, "..");
const example = join(repo, "examples", "project_room_lustre");
const bundle = join(example, "build", "rich-editor-browser-test.mjs");
const profile = join(repo, "build", "rich-editor-smoke-profile");

async function main() {
  if (!existsSync(bundle)) {
    console.error("rich editor smoke: browser bundle is missing");
    return 1;
  }

  const browser = findBrowser();
  if (browser === null) {
    console.log(
      "rich editor smoke: SKIPPED — no launchable Chromium-based browser found.",
    );
    return 0;
  }

  const server = await startServer(example, page);
  const url = "http://127.0.0.1:" + server.port + "/";
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
      url,
    ],
    { stdio: ["ignore", "pipe", "pipe"] },
  );
  chrome.stdout.resume();

  let exitCode = 1;
  try {
    const endpoint = await devtoolsEndpoint(chrome);
    const target = await pageTarget(endpoint, url);
    const report = await withPage(
      target,
      BROWSER_START_MS,
      "rich editor browser test timed out",
      async (send) => {
        await send("Runtime.enable");
        await waitForPage(send, "__watershedRichEditorSmoke");
        const result = await send("Runtime.evaluate", {
          expression: "window.__watershedRichEditorSmoke()",
          awaitPromise: true,
          returnByValue: true,
        });
        if (result.exceptionDetails) {
          throw new Error(JSON.stringify(result.exceptionDetails));
        }
        return String(result.result.value);
      },
    );
    console.log(report);
    exitCode = report.startsWith("PASS") ? 0 : 1;
  } finally {
    await stopBrowser(chrome);
    server.close();
    rmSync(profile, { recursive: true, force: true });
  }
  return exitCode;
}

const page = `<!doctype html>
<html><head><meta charset="utf-8"><title>rich editor smoke</title></head>
<body><div id="app"></div>
<script type="module">
  import { run } from "/build/rich-editor-browser-test.mjs";
  window.__watershedRichEditorSmoke = run;
</script>
<script>
  window.addEventListener("error", (event) => {
    window.__watershedLoadError = String(event.message || event.error);
  });
</script>
</body></html>`;

main().then(
  (code) => process.exit(code),
  (error) => {
    console.error(
      "rich editor smoke: " + (error && error.stack ? error.stack : error),
    );
    process.exit(1);
  },
);

async function pageTarget(browserEndpoint, url) {
  const origin = new URL(browserEndpoint);
  const deadline = Date.now() + BROWSER_START_MS;
  while (Date.now() < deadline) {
    const response = await fetch("http://" + origin.host + "/json/list");
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
  throw new Error("rich editor page target did not appear");
}
