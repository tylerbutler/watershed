// The two-browser gate for watershed's p2p mode.
//
//     gleam test --target javascript   # builds the harness module
//     node smoke/p2p_clap.mjs
//
// or `just p2p-clap`, which does both.
//
// What it proves is the plan's P2P5 gate, end to end and with nothing faked:
//
//   - two *real* browser pages, each with its own `RTCPeerConnection`s, its
//     own `WebSocket`, and its own `crdt_js` document;
//   - the page that joined second — the late one — is told it is ready only
//     *after* it has merged the room's state, never before;
//   - a real reference signaling process (`tools/signaling/server.mjs`),
//     talking the real protocol over real sockets;
//   - no sequencer, no document server, and no relay of any kind;
//   - both pages clap concurrently and converge on the same total *and* the
//     same canonical digest;
//   - the signaling process received only `join`, `signal`, and `leave`
//     frames — asserted from its own instrumentation, on the other side of
//     the wire from the pages.
//
// The browser plumbing — Chromium discovery, the static server for the
// compiled Gleam output, the DevTools Protocol pump — lives in
// `smoke/cdp.mjs`, shared with `smoke/p2p_browser.mjs`; see its header for
// why there is deliberately no browser-automation dependency.
//
// Exit codes: 0 when the gate passed *or* the environment has no launchable
// browser (reported as an explicit skip), 1 when it failed or the browser
// could not be driven.

import { spawn } from "node:child_process";
import { existsSync, mkdirSync, rmSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import WebSocket from "ws";

import { startSignalingServer } from "../tools/signaling/server.mjs";
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
const harness = join(
  webRoot,
  "watershed",
  "watershed",
  "crdt_js_browser_smoke.mjs",
);
const profile = join(repo, "build", "p2p-clap-profile");

const GATE_MS = 120_000;
const CLAPS = 12;

main().then(
  (code) => process.exit(code),
  (error) => {
    console.error("clap gate: " + (error && error.stack ? error.stack : error));
    process.exit(1);
  },
);

async function main() {
  if (!existsSync(harness)) {
    console.error(
      "clap gate: " +
        harness +
        " is missing.\n" +
        "Build the test modules first: gleam test --target javascript",
    );
    return 1;
  }

  const browser = findBrowser();
  if (browser === null) {
    console.log(
      "clap gate: SKIPPED — no launchable Chromium-based browser found.\n" +
        "  Set WATERSHED_CHROME to one, or install Chrome/Chromium.\n" +
        "  The deterministic facade tests in the JavaScript suite and the\n" +
        "  signaling service tests cover everything but the real browsers.",
    );
    return 0;
  }
  console.log("clap gate: browser " + browser);

  const signaling = startSignalingServer({ port: 0 });
  const signalingPort = await signaling.listening;
  const signalingUrl = "ws://127.0.0.1:" + signalingPort + "/";
  console.log("clap gate: signaling " + signalingUrl);

  const server = await startServer(webRoot, page);
  const url = "http://127.0.0.1:" + server.port + "/";
  console.log("clap gate: serving " + webRoot + " at " + url);

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
      // Host candidates are enough for two peers on one machine, but Chrome
      // hides them behind mDNS names by default. Resolving those is reliable
      // on a desktop and flaky in a headless container, so the gate asks for
      // the plain addresses rather than adding a STUN server the library
      // deliberately does not ship.
      "--disable-features=WebRtcHideLocalIpsWithMdns",
      url + "?tab=1",
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
    console.log("clap gate: devtools " + endpoint);
    // Headless Chrome refuses more than one URL on its command line, so the
    // second tab is opened over the protocol instead. Two tabs, one browser
    // process — which is exactly the shape a user reproduces by hand.
    await openTab(endpoint, url + "?tab=2");
    const pages = await pageTargets(endpoint, url, 2);
    console.log("clap gate: " + pages.length + " pages");

    const room = "clap-gate-" + Date.now();
    // Both pages run at once: the claps have to race for the gate to mean
    // anything.
    const reports = await Promise.all(
      pages.map((target) => runPage(target, room, signalingUrl, CLAPS)),
    );

    const stats = signaling.stats();
    const problems = check(reports, stats);
    console.log("─".repeat(72));
    for (const [index, report] of reports.entries()) {
      console.log(
        "tab " +
          (index + 1) +
          ": value=" +
          report.value +
          " peers=" +
          report.peers +
          " digest=" +
          String(report.digest).slice(0, 16) +
          " roster=" +
          report.rosterPeers +
          " mergesAtReady=" +
          report.mergesAtReady +
          " replica=" +
          report.replica,
      );
      for (const problem of report.problems) {
        console.log("  problem: " + problem);
      }
    }
    console.log("signaling: " + JSON.stringify(stats));
    console.log("─".repeat(72));
    if (problems.length === 0) {
      console.log(
        "PASS: two browser peers merged " +
          CLAPS * 2 +
          " claps with no sequencer, the late peer was ready only after its" +
          " state merge, and signaling carried no document data.",
      );
      exitCode = 0;
    } else {
      console.log("FAIL:");
      for (const problem of problems) console.log("  " + problem);
      for (const [index, report] of reports.entries()) {
        console.log("tab " + (index + 1) + " statuses:");
        for (const status of report.statuses) console.log("    " + status);
      }
      exitCode = 1;
    }
  } finally {
    await stopBrowser(chrome);
    server.close();
    await signaling.close();
    rmSync(profile, { recursive: true, force: true });
  }
  return exitCode;
}

// ── the gate's assertions ───────────────────────────────────────────────────

function check(reports, stats) {
  const problems = [];
  const expected = CLAPS * reports.length;

  for (const [index, report] of reports.entries()) {
    const tab = "tab " + (index + 1);
    if (!report.ready) problems.push(tab + " never became ready");
    if (report.value !== expected) {
      problems.push(
        tab + " holds " + report.value + " claps, expected " + expected,
      );
    }
    if (report.peers !== reports.length - 1) {
      problems.push(
        tab + " sees " + report.peers + " peers, expected " + (reports.length - 1),
      );
    }
    for (const problem of report.problems) problems.push(tab + ": " + problem);
  }

  // Late-join readiness. The service admits joins one at a time, so exactly
  // one page sees a non-empty roster, and that page is the late joiner: its
  // `on_ready` must come after the state merge, not merely converge later.
  const late = reports.filter((report) => report.rosterPeers > 0);
  const alone = reports.filter((report) => report.rosterPeers === 0);
  if (late.length !== 1 || alone.length !== reports.length - 1) {
    problems.push(
      "expected exactly one late joiner, saw rosters " +
        JSON.stringify(reports.map((report) => report.rosterPeers)),
    );
  }
  for (const report of late) {
    if (report.mergesAtReady < 1) {
      problems.push(
        "the late peer became ready before merging state (merges at ready: " +
          report.mergesAtReady +
          ")",
      );
    }
    const order = report.statuses.map((status) => status.split(" ")[0]);
    if (order.indexOf("stateMerged") === -1) {
      problems.push("the late peer never merged a state transfer");
    } else if (order.indexOf("ready") < order.indexOf("stateMerged")) {
      problems.push("the late peer reported ready before stateMerged");
    }
  }
  for (const report of alone) {
    if (report.mergesAtReady !== 0) {
      problems.push(
        "the first peer waited for a state transfer it was never owed",
      );
    }
  }

  const digests = new Set(reports.map((report) => report.digest));
  if (digests.size !== 1) {
    problems.push("the pages disagree about the digest: " + [...digests]);
  }
  const replicas = new Set(reports.map((report) => report.replica));
  if (replicas.size !== reports.length) {
    problems.push("two writers shared one author identity: " + [...replicas]);
  }

  // The point of the whole exercise: the signaling process saw signaling and
  // nothing else.
  const tags = stats.framesByTag;
  for (const tag of Object.keys(tags)) {
    if (tag.startsWith("rejected:")) {
      problems.push(
        "signaling refused " + tags[tag] + " frame(s) as " + tag.slice(9),
      );
    } else if (tag.startsWith("dropped:")) {
      // A signal to a peer that had just left. Not a fault, and not a
      // rejection — but worth printing, which the stats line already does.
    } else if (!["join", "signal", "leave"].includes(tag)) {
      problems.push("signaling received an unexpected frame kind: " + tag);
    }
  }
  if ((tags.join ?? 0) !== reports.length) {
    problems.push(
      "signaling saw " + (tags.join ?? 0) + " joins, expected " + reports.length,
    );
  }
  if ((tags.signal ?? 0) === 0) {
    problems.push("signaling carried no offers or candidates at all");
  }
  if (stats.oversizeFrames !== 0 || stats.nonTextFrames !== 0) {
    problems.push("signaling saw oversize or binary frames");
  }
  return problems;
}

// ── the pages ───────────────────────────────────────────────────────────────

const page = `<!doctype html>
<html><head><meta charset="utf-8"><title>watershed clap gate</title></head>
<body><pre id="out">waiting…</pre>
<script type="module">
  import { run } from "/watershed/watershed/crdt_js_browser_smoke.mjs";
  window.__watershedClapPeer = (room, url, claps) => run(room, url, claps);
  window.__watershedReady = true;
</script>
<script>
  window.addEventListener("error", (e) => {
    window.__watershedLoadError = String(e.message || e.error);
  });
</script>
</body></html>`;

// Ask the browser for one more page target. Resolves when it exists.
function openTab(browserEndpoint, url) {
  return new Promise((done, failed) => {
    const socket = new WebSocket(browserEndpoint);
    const timer = setTimeout(() => {
      socket.close();
      failed(new Error("the browser did not open a second tab"));
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
      else done(message.result.targetId);
    });
    socket.on("open", () => {
      socket.send(
        JSON.stringify({ id: 1, method: "Target.createTarget", params: { url } }),
      );
    });
  });
}

async function pageTargets(browserEndpoint, url, count) {
  const origin = new URL(browserEndpoint);
  const listUrl = "http://" + origin.host + "/json/list";
  const deadline = Date.now() + BROWSER_START_MS;
  while (Date.now() < deadline) {
    const response = await fetch(listUrl);
    const targets = await response.json();
    const matches = targets.filter(
      (target) =>
        target.type === "page" &&
        target.url.startsWith(url) &&
        target.webSocketDebuggerUrl,
    );
    if (matches.length >= count) {
      return matches.slice(0, count).map((match) => match.webSocketDebuggerUrl);
    }
    await sleep(100);
  }
  throw new Error("fewer than " + count + " page targets for " + url + " appeared");
}

function runPage(pageEndpoint, room, signalingUrl, claps) {
  return withPage(
    pageEndpoint,
    GATE_MS,
    "a page did not finish within " + GATE_MS + "ms",
    async (send) => {
      await send("Runtime.enable");
      await waitForPage(send, "__watershedClapPeer");
      const expression =
        "window.__watershedClapPeer(" +
        JSON.stringify(room) +
        "," +
        JSON.stringify(signalingUrl) +
        "," +
        claps +
        ")";
      const result = await send("Runtime.evaluate", {
        expression,
        awaitPromise: true,
        returnByValue: true,
      });
      if (result.exceptionDetails) {
        throw new Error(
          "a page threw: " + JSON.stringify(result.exceptionDetails),
        );
      }
      return JSON.parse(String(result.result.value));
    },
  );
}
