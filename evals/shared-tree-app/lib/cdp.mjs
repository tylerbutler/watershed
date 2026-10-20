import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { mkdtemp, readdir, rm } from "node:fs/promises";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import { once } from "node:events";
import WebSocket from "ws";
import { bounded, wait } from "./conditions.mjs";

async function findBrowser() {
  if (process.env.WATERSHED_CHROME) {
    if (!existsSync(process.env.WATERSHED_CHROME)) throw new Error("WATERSHED_CHROME does not exist");
    return process.env.WATERSHED_CHROME;
  }
  for (const path of [
    "/usr/bin/chromium", "/usr/bin/google-chrome", "/usr/bin/chromium-browser",
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  ]) {
    if (existsSync(path)) return path;
  }
  const cache = join(homedir(), "Library/Caches/ms-playwright");
  if (existsSync(cache)) {
    const entries = (await readdir(cache)).filter(name => name.startsWith("chromium-")).sort().reverse();
    for (const name of entries) {
      const path = join(cache, name, "chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing");
      if (existsSync(path)) return path;
    }
  }
  throw new Error("Chromium is required; set WATERSHED_CHROME to an installed executable");
}

export async function launchBrowser({ executable } = {}) {
  const browserPath = executable ?? await findBrowser();
  const profile = await mkdtemp(join(tmpdir(), "shared-tree-eval-chrome-"));
  const child = spawn(browserPath, [
    "--headless=new", "--no-first-run", "--no-default-browser-check",
    "--remote-debugging-port=0", `--user-data-dir=${profile}`, "about:blank",
  ], { stdio: ["ignore", "ignore", "pipe"] });
  let socket;
  let closed = false;
  try {
    const endpoint = await bounded("Chromium startup", () => new Promise((resolve, reject) => {
      let output = "";
      child.stderr.on("data", chunk => {
        output = (output + chunk.toString()).slice(-16_384);
        const match = output.match(/DevTools listening on (ws:\/\/[^\s]+)/);
        if (match) resolve(match[1]);
      });
      child.once("error", reject);
      child.once("exit", code => reject(new Error(`Chromium exited (${code}): ${output}`)));
    }), 30_000);
    socket = new WebSocket(endpoint);
    await bounded("CDP connect", () => once(socket, "open"));
    let next = 1;
    const pending = new Map();
    const errors = new Map();
    const traffic = new Map();
    const requests = new Map();
    socket.on("message", data => {
      const message = JSON.parse(data.toString());
      if (message.id !== undefined) {
        const request = pending.get(message.id);
        if (!request) return;
        pending.delete(message.id);
        clearTimeout(request.timer);
        if (message.error) request.reject(new Error(JSON.stringify(message.error)));
        else request.resolve(message.result);
      } else if (message.method === "Runtime.exceptionThrown") {
        const details = message.params.exceptionDetails;
        errors.get(message.sessionId)?.push(details.exception?.description ?? details.text);
      } else if (message.method === "Network.requestWillBeSent") {
        requests.set(`${message.sessionId}:${message.params.requestId}`, message.params.request.url);
      } else if (message.method === "Network.loadingFailed") {
        traffic.get(message.sessionId)?.push({
          url: requests.get(`${message.sessionId}:${message.params.requestId}`),
          error: message.params.errorText,
        });
      }
    });
    const failPending = error => {
      for (const request of pending.values()) {
        clearTimeout(request.timer);
        request.reject(error);
      }
      pending.clear();
    };
    socket.on("error", failPending);
    socket.on("close", () => failPending(new Error("CDP connection closed")));
    const send = (method, params = {}, sessionId) => new Promise((resolve, reject) => {
      const id = next++;
      const timer = setTimeout(() => {
        pending.delete(id);
        reject(new Error(`CDP ${method} timed out`));
      }, 5000);
      pending.set(id, { resolve, reject, timer });
      socket.send(JSON.stringify({ id, method, params, ...(sessionId ? { sessionId } : {}) }));
    });
    return {
      async context() {
        const { browserContextId } = await send("Target.createBrowserContext");
        return {
          async page() {
            const { targetId } = await send("Target.createTarget", { url: "about:blank", browserContextId });
            const { sessionId } = await send("Target.attachToTarget", { targetId, flatten: true });
            errors.set(sessionId, []);
            traffic.set(sessionId, []);
            const command = (method, params) => send(method, params, sessionId);
            await command("Page.enable");
            await command("Runtime.enable");
            await command("Network.enable");
            const evaluate = async expression => {
              const value = await command("Runtime.evaluate", {
                expression, returnByValue: true, awaitPromise: true,
              });
              if (value.exceptionDetails) {
                throw new Error(value.exceptionDetails.exception?.description ?? value.exceptionDetails.text);
              }
              return value.result.value;
            };
            return {
              evaluate,
              command,
              errors: () => [...errors.get(sessionId)],
              networkErrors: () => [...traffic.get(sessionId)],
              async goto(url) {
                const target = new URL(url);
                const result = await command("Page.navigate", { url });
                if (result.errorText) throw new Error(result.errorText);
                await wait("page load", () => evaluate(
                  `location.origin === ${JSON.stringify(target.origin)}
                    && location.pathname === ${JSON.stringify(target.pathname)}
                    && document.readyState === "complete"`,
                ), Boolean);
              },
              async waitFor(selector) {
                await wait(selector, () => evaluate(
                  `document.querySelector(${JSON.stringify(selector)}) !== null`,
                ), Boolean);
              },
              async click(selector) {
                const rect = await evaluate(`(() => {
                  const el = document.querySelector(${JSON.stringify(selector)});
                  if (!el) throw new Error("Missing control");
                  el.scrollIntoView();
                  const r = el.getBoundingClientRect();
                  return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
                })()`);
                await command("Input.dispatchMouseEvent", { type: "mousePressed", button: "left", clickCount: 1, ...rect });
                await command("Input.dispatchMouseEvent", { type: "mouseReleased", button: "left", clickCount: 1, ...rect });
              },
              async fill(selector, text) {
                await evaluate(`(() => {
                  const el = document.querySelector(${JSON.stringify(selector)});
                  if (!el) throw new Error("Missing input");
                  el.focus(); el.select();
                })()`);
                await command("Input.insertText", { text });
              },
              async close() {
                await send("Target.closeTarget", { targetId });
                errors.delete(sessionId);
                traffic.delete(sessionId);
              },
            };
          },
          async close() { await send("Target.disposeBrowserContext", { browserContextId }); },
        };
      },
      async close() {
        if (closed) return;
        closed = true;
        socket.close();
        if (child.exitCode === null && child.signalCode === null) {
          const exited = once(child, "exit");
          child.kill("SIGKILL");
          await bounded("Chromium shutdown", () => exited);
        }
        await rm(profile, { recursive: true, force: true });
      },
    };
  } catch (error) {
    socket?.close();
    if (child.exitCode === null && child.signalCode === null) {
      const exited = once(child, "exit");
      child.kill("SIGKILL");
      await bounded("Failed Chromium shutdown", () => exited);
    }
    await rm(profile, { recursive: true, force: true });
    throw error;
  }
}
