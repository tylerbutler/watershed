import { existsSync } from "node:fs";
import { readFile, stat, writeFile } from "node:fs/promises";
import { createServer } from "node:http";
import { dirname, extname, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import puppeteer from "puppeteer";

export function parity(importMetaUrl, fixtureName) {
  const root = resolve(dirname(fileURLToPath(importMetaUrl)), "../..");
  const record = process.argv.includes("--record-baseline");
  return {
    root,
    record,
    site: resolve(root, "dist"),
    fixture: fixtureName
      ? resolve(root, "test/fixtures", fixtureName)
      : undefined,
  };
}

export async function readParity(path) {
  return JSON.parse(await readFile(path, "utf8"));
}

export async function writeParity(path, value) {
  await writeFile(path, JSON.stringify(value, null, 2) + "\n");
}

export async function openPage(browser) {
  const errors = [];
  const page = await browser.newPage();
  page.on("pageerror", (error) => errors.push(error.message));
  page.on("console", (message) => {
    if (message.type() === "error") errors.push(message.text());
  });
  await page.setRequestInterception(true);
  page.on("request", (request) => {
    if (request.url().startsWith("https://tinylytics.app/")) {
      request.respond({ status: 200, contentType: "text/javascript", body: "" });
    } else {
      request.continue();
    }
  });
  return { page, errors };
}

export async function withBrowserSite(site, run) {
  const browserPath = process.env.WATERSHED_CHROME || await puppeteer.executablePath();
  if (!existsSync(browserPath)) {
    if (process.env.CI) throw new Error(`Chromium is required in CI: ${browserPath}`);
    console.log(`SKIP: Chromium is unavailable: ${browserPath}`);
    return;
  }
  const mime = { ".html": "text/html", ".css": "text/css", ".js": "text/javascript", ".mjs": "text/javascript", ".svg": "image/svg+xml", ".png": "image/png", ".woff": "font/woff", ".woff2": "font/woff2" };
  const server = createServer(async (request, response) => {
    const pathname = new URL(request.url, "http://localhost").pathname;
    let path = resolve(site, "." + decodeURIComponent(pathname));
    if (!path.startsWith(site + sep) && path !== site) {
      response.writeHead(403).end();
      return;
    }
    try {
      if ((await stat(path)).isDirectory()) path = resolve(path, "index.html");
      const body = await readFile(path);
      response.writeHead(200, { "content-type": mime[extname(path)] || "application/octet-stream" }).end(body);
    } catch (error) {
      if (error.code !== "ENOENT" && error.code !== "ENOTDIR") {
        response.writeHead(500).end();
        throw error;
      }
      response.writeHead(404).end("Not found");
    }
  });
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });
  let browser;
  try {
    browser = await puppeteer.launch({
      executablePath: browserPath,
      headless: true,
      args: process.env.CI ? ["--no-sandbox"] : [],
    });
    await run(browser, `http://127.0.0.1:${server.address().port}`);
  } finally {
    if (browser) await browser.close();
    await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
  }
}
