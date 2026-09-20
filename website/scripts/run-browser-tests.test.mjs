import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import test from "node:test";
import { attachBrowserErrorCapture } from "./browser-test-harness.mjs";
import {
  browserTestFiles,
  findBrowserIn,
  requireBrowser,
  resolveStaticPath,
} from "./run-browser-tests.mjs";
import { browserTestFiles as sharedBrowserTestFiles } from "./test-files.mjs";

test("uses the shared browser test manifest", () => {
  assert.strictEqual(browserTestFiles, sharedBrowserTestFiles);
  assert.deepEqual(browserTestFiles, [
    "scripts/guide-race-styles.test.mjs",
    "scripts/structure-demos.test.mjs",
    "scripts/mv-register-demo.test.mjs",
    "scripts/ormap-demo.test.mjs",
    "scripts/lww-map-demo.test.mjs",
    "scripts/or-map-mv-register-demo.test.mjs",
    "scripts/runtime-demos.test.mjs",
    "scripts/structure-runtime-contract.test.mjs",
  ]);
});

test("maps route paths to Astro index files", () => {
  assert.equal(
    resolveStaticPath("/tmp/site", "/structures/maps"),
    "/tmp/site/structures/maps/index.html",
  );
  assert.equal(
    resolveStaticPath("/tmp/site", "/assets/app.js"),
    "/tmp/site/assets/app.js",
  );
});

test("rejects paths outside the static root", () => {
  assert.equal(resolveStaticPath("/tmp/site", "/../secret"), null);
});

test("finds a Playwright Chromium headless shell", () => {
  const home = "/home/tester";
  const executable =
    `${home}/.cache/ms-playwright/` +
    "chromium_headless_shell-1234/chrome-linux/headless_shell";
  assert.equal(
    findBrowserIn({
      env: {},
      home,
      exists: (candidate) => candidate === executable,
      readDirectory: (directory) =>
        directory === `${home}/.cache/ms-playwright`
          ? [
              {
                isDirectory: () => true,
                name: "chromium_headless_shell-1234",
              },
            ]
          : [],
    }),
    executable,
  );
});

test("requires Chromium only when strict browser integration is enabled", () => {
  assert.equal(requireBrowser(null, false), null);
  assert.throws(
    () => requireBrowser(null, true),
    /Chromium is required for website browser integration/,
  );
  assert.equal(requireBrowser("/usr/bin/chrome", true), "/usr/bin/chrome");
});

test("browser error capture records page and console failures", () => {
  const page = new EventEmitter();
  const errors = [];
  attachBrowserErrorCapture(page, errors);
  page.emit("pageerror", new Error("page failed"));
  page.emit("console", { type: () => "error", text: () => "console failed" });
  assert.deepEqual(errors, ["page failed", "console failed"]);
});
