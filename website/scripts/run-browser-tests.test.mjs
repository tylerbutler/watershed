import assert from "node:assert/strict";
import test from "node:test";
import {
  findBrowserIn,
  resolveStaticPath,
} from "./run-browser-tests.mjs";

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
