import assert from "node:assert/strict";
import puppeteer from "puppeteer-core";
import { findBrowserIn } from "./run-browser-tests.mjs";

export function attachBrowserErrorCapture(
  page,
  errors,
  captureConsoleErrors = true,
) {
  page.on("pageerror", (error) => errors.push(error.message));
  if (captureConsoleErrors) {
    page.on("console", (message) => {
      if (message.type() === "error") errors.push(message.text());
    });
  }
}

export async function openBrowserTest(t, {
  width = 1440,
  height = 1000,
  reducedMotion = true,
  captureConsoleErrors = true,
  args = ["--no-sandbox", "--disable-dev-shm-usage"],
} = {}) {
  const browser = await launchBrowserTest(t, args);
  const page = await browser.newPage();
  await page.setViewport({ width, height });
  await page.emulateMediaFeatures([{
    name: "prefers-reduced-motion",
    value: reducedMotion ? "reduce" : "no-preference",
  }]);
  const errors = [];
  attachBrowserErrorCapture(page, errors, captureConsoleErrors);
  return { browser, page, errors };
}

export async function launchBrowserTest(
  t = null,
  args = ["--no-sandbox", "--disable-dev-shm-usage"],
) {
  const executablePath = findBrowserIn();
  assert.ok(executablePath, "Chromium is required; set WATERSHED_CHROME");
  const browser = await puppeteer.launch({ executablePath, headless: true, args });
  t?.after(() => browser.close());
  return browser;
}
