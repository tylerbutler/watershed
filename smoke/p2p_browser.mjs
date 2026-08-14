// Runs the real-browser WebRTC smoke harness
// (`test/watershed/p2p_browser_smoke.gleam`) in a headless Chromium.
//
//     gleam test --target javascript   # builds the test modules
//     node smoke/p2p_browser.mjs
//
// or `just p2p-smoke`, which does both.
//
// The browser plumbing — Chromium discovery, the static server for the
// compiled Gleam output, the DevTools Protocol pump — lives in
// `smoke/cdp.mjs`, shared with `smoke/p2p_clap.mjs`; see its header for why
// there is deliberately no browser-automation dependency.
//
// Exit codes: 0 when the harness passed *or* the environment has no launchable
// browser (reported as an explicit skip), 1 when the harness failed or the
// browser could not be driven.

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
const webRoot = join(repo, "build", "dev", "javascript");
const harness = join(webRoot, "watershed", "watershed", "p2p_browser_smoke.mjs");
const profile = join(repo, "build", "p2p-smoke-profile");

const HARNESS_MS = 120_000;

main().then(
  (code) => process.exit(code),
  (error) => {
    console.error("p2p smoke: " + (error && error.stack ? error.stack : error));
    process.exit(1);
  },
);

async function main() {
  if (!existsSync(harness)) {
    console.error(
      "p2p smoke: " +
        harness +
        " is missing.\n" +
        "Build the test modules first: gleam test --target javascript",
    );
    return 1;
  }

  const browser = findBrowser();
  if (browser === null) {
    console.log(
      "p2p smoke: SKIPPED — no launchable Chromium-based browser found.\n" +
        "  Set WATERSHED_CHROME to one, or install Chrome/Chromium.\n" +
        "  The deterministic fake-RTCPeerConnection tests in the JavaScript\n" +
        "  suite cover this transport either way; only the real-browser\n" +
        "  convergence check is skipped.",
    );
    return 0;
  }
  console.log("p2p smoke: browser " + browser);

  const server = await startServer(webRoot, page);
  const url = "http://127.0.0.1:" + server.port + "/";
  console.log("p2p smoke: serving " + webRoot + " at " + url);

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
      // Host candidates are enough for two peer connections in one page, but
      // Chrome hides them behind mDNS names by default. Resolving those is
      // reliable in a desktop browser and flaky in a headless container, so
      // the smoke test asks for the plain addresses instead of adding a STUN
      // server the library deliberately does not ship.
      "--disable-features=WebRtcHideLocalIpsWithMdns",
      url,
    ],
    { stdio: ["ignore", "pipe", "pipe"] },
  );
  // Chrome writes to stdout occasionally and nothing here reads it. An
  // unread pipe fills and then blocks the browser, so it is drained and
  // discarded; the devtools endpoint is announced on stderr, which is read.
  chrome.stdout.resume();

  let exitCode = 1;
  try {
    const endpoint = await devtoolsEndpoint(chrome);
    console.log("p2p smoke: devtools " + endpoint);
    const target = await pageTarget(endpoint, url);
    const report = await runHarness(target);
    console.log("─".repeat(72));
    console.log(report);
    console.log("─".repeat(72));
    exitCode = report.startsWith("PASS") ? 0 : 1;
  } finally {
    await stopBrowser(chrome);
    server.close();
    rmSync(profile, { recursive: true, force: true });
  }
  return exitCode;
}

const page = `<!doctype html>
<html><head><meta charset="utf-8"><title>watershed p2p smoke</title></head>
<body><pre id="out">running…</pre>
<script type="module">
  import { run } from "/watershed/watershed/p2p_browser_smoke.mjs";
  window.__watershedP2pSmoke = () => run();
  window.__watershedReady = true;
</script>
<script>
  window.addEventListener("error", (e) => {
    window.__watershedLoadError = String(e.message || e.error);
  });
</script>
</body></html>`;

async function pageTarget(browserEndpoint, url) {
  const origin = new URL(browserEndpoint);
  const listUrl = "http://" + origin.host + "/json/list";
  const deadline = Date.now() + BROWSER_START_MS;
  while (Date.now() < deadline) {
    const response = await fetch(listUrl);
    const targets = await response.json();
    const match = targets.find(
      (target) => target.type === "page" && target.url.startsWith(url),
    );
    if (match && match.webSocketDebuggerUrl) return match.webSocketDebuggerUrl;
    await sleep(100);
  }
  throw new Error("no page target for " + url + " appeared");
}

function runHarness(pageEndpoint) {
  return withPage(
    pageEndpoint,
    HARNESS_MS,
    "the harness did not finish within " + HARNESS_MS + "ms",
    async (send) => {
      await send("Runtime.enable");
      await waitForPage(send, "__watershedP2pSmoke");
      const result = await send("Runtime.evaluate", {
        expression: "window.__watershedP2pSmoke()",
        awaitPromise: true,
        returnByValue: true,
      });
      if (result.exceptionDetails) {
        throw new Error(
          "the harness threw: " + JSON.stringify(result.exceptionDetails),
        );
      }
      return String(result.result.value);
    },
  );
}
