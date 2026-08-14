// The browser plumbing shared by `smoke/p2p_browser.mjs` and
// `smoke/p2p_clap.mjs`: find a Chromium, serve the compiled Gleam output,
// learn the DevTools endpoint, pump the protocol, wait for a page's harness
// module, and tear the browser down.
//
// There is no browser-automation dependency here on purpose. The library has
// no npm dependencies, the root `package.json` carries only `phoenix` and `ws`
// for the live JavaScript suite, and a WebRTC smoke test is not a reason to
// add a third. So this drives Chromium over the DevTools Protocol directly:
// `ws` is already installed, a WebSocket and `Runtime.evaluate` are the whole
// of what is needed, and the browser is whichever one the machine already has.

import { createReadStream, existsSync, readdirSync } from "node:fs";
import { stat } from "node:fs/promises";
import { createServer } from "node:http";
import { homedir } from "node:os";
import { isAbsolute, join, relative, resolve } from "node:path";
import WebSocket from "ws";

/** How long the browser gets to start, announce devtools, and load a page. */
export const BROWSER_START_MS = 30_000;

// ── browser discovery ───────────────────────────────────────────────────────

/**
 * A launchable Chromium-based browser, or `null`. `WATERSHED_CHROME` wins
 * outright; otherwise the well-known install paths, then the browsers a
 * developer machine already has from Playwright or Puppeteer — read, never
 * installed: this adds no dependency and downloads nothing. Scanned by hand
 * rather than with `fs.globSync`, which only exists from Node 22.
 */
export function findBrowser() {
  const explicit = process.env.WATERSHED_CHROME;
  if (explicit) return existsSync(explicit) ? explicit : null;

  const fixed = [
    "/usr/bin/google-chrome-stable",
    "/usr/bin/google-chrome",
    "/usr/bin/chromium",
    "/usr/bin/chromium-browser",
    "/snap/bin/chromium",
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  ];
  for (const candidate of fixed) if (existsSync(candidate)) return candidate;

  const versioned = [
    [join(homedir(), ".cache/ms-playwright"), "chromium-", "chrome-linux/chrome"],
    [
      join(homedir(), ".cache/ms-playwright"),
      "chromium_headless_shell-",
      "chrome-linux/headless_shell",
    ],
    [join(homedir(), ".cache/puppeteer/chrome"), "", "chrome-linux64/chrome"],
  ];
  for (const [base, prefix, tail] of versioned) {
    const found = newestUnder(base, prefix, tail);
    if (found !== null) return found;
  }
  return null;
}

// The newest `<base>/<prefix>*/<tail>` that exists, by directory name.
function newestUnder(base, prefix, tail) {
  let entries;
  try {
    entries = readdirSync(base, { withFileTypes: true });
  } catch {
    return null;
  }
  const candidates = entries
    .filter((entry) => entry.isDirectory() && entry.name.startsWith(prefix))
    .map((entry) => join(base, entry.name, tail))
    .filter((candidate) => existsSync(candidate))
    .sort();
  return candidates.length > 0 ? candidates[candidates.length - 1] : null;
}

// ── static server ───────────────────────────────────────────────────────────

/**
 * Serve `page` at `/` and everything under `webRoot` as-is. The built Gleam
 * output is served rather than bundled: Gleam emits relative ES module imports
 * (`../../gleam_stdlib/gleam/dict.mjs`), so serving `build/dev/javascript` as
 * the document root resolves every one of them, and the page runs exactly the
 * modules the suite compiled. Resolves to `{ port, close }`.
 */
export function startServer(webRoot, page) {
  const types = {
    ".mjs": "text/javascript; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".json": "application/json; charset=utf-8",
    ".map": "application/json; charset=utf-8",
  };
  const server = createServer(async (request, response) => {
    const path = decodeURIComponent(new URL(request.url, "http://x").pathname);
    if (path === "/" || path === "/index.html") {
      response.writeHead(200, { "content-type": "text/html; charset=utf-8" });
      response.end(page);
      return;
    }
    // Contain every request inside the build output. A prefix compare
    // would also admit a sibling directory whose name merely starts with
    // the root's, so this asks whether the resolved path is genuinely
    // *under* the root.
    const target = resolve(webRoot, "." + path);
    const inside = relative(webRoot, target);
    if (inside.startsWith("..") || isAbsolute(inside)) {
      response.writeHead(403).end("forbidden");
      return;
    }
    try {
      const info = await stat(target);
      if (!info.isFile()) throw new Error("not a file");
    } catch {
      response.writeHead(404).end("not found");
      return;
    }
    const extension = target.slice(target.lastIndexOf("."));
    response.writeHead(200, {
      "content-type": types[extension] ?? "application/octet-stream",
    });
    createReadStream(target).pipe(response);
  });
  return new Promise((resolveServer, rejectServer) => {
    server.once("error", rejectServer);
    server.listen(0, "127.0.0.1", () =>
      resolveServer({
        port: server.address().port,
        close: () => server.close(),
      }),
    );
  });
}

// ── devtools protocol ───────────────────────────────────────────────────────

// Chrome prints `DevTools listening on ws://127.0.0.1:PORT/devtools/browser/…`
// once it is up. `--remote-debugging-port=0` means that line is the only way
// to learn the port.
export function devtoolsEndpoint(chrome) {
  return new Promise((resolveEndpoint, rejectEndpoint) => {
    let buffered = "";
    const timer = setTimeout(() => {
      rejectEndpoint(
        new Error(
          "the browser did not report a devtools endpoint within " +
            BROWSER_START_MS +
            "ms:\n" +
            buffered,
        ),
      );
    }, BROWSER_START_MS);

    chrome.stderr.on("data", (chunk) => {
      buffered += chunk.toString();
      const match = buffered.match(/ws:\/\/[^\s]+/);
      if (match) {
        clearTimeout(timer);
        resolveEndpoint(match[0]);
      }
    });
    chrome.on("exit", (code) => {
      clearTimeout(timer);
      rejectEndpoint(
        new Error("the browser exited with code " + code + ":\n" + buffered),
      );
    });
  });
}

/**
 * The CDP message pump. Opens a socket to `pageEndpoint`, gives `body` a
 * `send(method, params)` that resolves with each command's result, echoes the
 * page's console output and exceptions (so a module that failed to load is
 * diagnosable rather than a bare timeout), and settles with whatever `body`
 * returns — or rejects with `timeoutMessage` after `timeoutMs`.
 */
export function withPage(pageEndpoint, timeoutMs, timeoutMessage, body) {
  return new Promise((resolveRun, rejectRun) => {
    const socket = new WebSocket(pageEndpoint);
    const pending = new Map();
    let nextId = 1;
    const timer = setTimeout(() => {
      socket.close();
      rejectRun(new Error(timeoutMessage));
    }, timeoutMs);

    const send = (method, params) => {
      const id = nextId++;
      return new Promise((ok, fail) => {
        pending.set(id, { ok, fail });
        socket.send(JSON.stringify({ id, method, params: params ?? {} }));
      });
    };

    socket.on("message", (raw) => {
      const message = JSON.parse(raw.toString());
      if (message.id !== undefined) {
        const waiting = pending.get(message.id);
        pending.delete(message.id);
        if (!waiting) return;
        if (message.error) waiting.fail(new Error(JSON.stringify(message.error)));
        else waiting.ok(message.result);
        return;
      }
      if (message.method === "Runtime.consoleAPICalled") {
        const text = (message.params.args ?? [])
          .map((argument) => argument.value ?? argument.description ?? "")
          .join(" ");
        console.log("  page> " + text);
      }
      if (message.method === "Runtime.exceptionThrown") {
        const details = message.params.exceptionDetails;
        console.log("  page! " + (details.text ?? "") + " " + (details.url ?? ""));
      }
    });

    socket.on("error", (error) => {
      clearTimeout(timer);
      rejectRun(error);
    });

    socket.on("open", async () => {
      try {
        const result = await body(send);
        clearTimeout(timer);
        socket.close();
        resolveRun(result);
      } catch (error) {
        clearTimeout(timer);
        socket.close();
        rejectRun(error);
      }
    });
  });
}

/**
 * Poll until `window.<readyGlobal>` is a function — the page's harness module
 * has loaded — surfacing `window.__watershedLoadError` if it never does.
 */
export async function waitForPage(send, readyGlobal) {
  const deadline = Date.now() + BROWSER_START_MS;
  while (Date.now() < deadline) {
    const probe = await send("Runtime.evaluate", {
      expression:
        "typeof window." +
        readyGlobal +
        " === 'function' ? 'ready' :" +
        " (window.__watershedLoadError || 'waiting')",
      returnByValue: true,
    });
    const value = probe.result.value;
    if (value === "ready") return;
    if (value !== "waiting") {
      throw new Error("the harness module failed to load: " + value);
    }
    await sleep(100);
  }
  throw new Error("the harness module never loaded");
}

// ── teardown ────────────────────────────────────────────────────────────────

/**
 * Kill the browser and wait for it to actually go — a killed Chrome keeps
 * writing to its profile for a moment, and deleting the directory out from
 * under it leaves half of it behind.
 */
export function stopBrowser(chrome) {
  if (chrome.exitCode !== null || chrome.signalCode !== null) {
    return Promise.resolve();
  }
  return new Promise((done) => {
    const give_up = setTimeout(done, 5_000);
    chrome.once("exit", () => {
      clearTimeout(give_up);
      done();
    });
    chrome.kill("SIGKILL");
  });
}

export function sleep(ms) {
  return new Promise((ok) => setTimeout(ok, ms));
}
