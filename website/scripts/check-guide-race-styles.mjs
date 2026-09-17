// Regression check for GuideRaceDemo's dynamically created note/vote markup.
//
// GuideRaceDemo.astro is a scoped Astro component, but `guide-race-demo.ts`
// builds its board with document.createElement(...) at runtime. Astro only
// stamps its `data-astro-cid-*` scope attribute onto elements present in the
// component's own template — nodes created later in the browser never get it,
// so any style written as a bare `.gr-note { ... }` silently stops matching
// (see task-3 → task-7 final-review fix wave). This script boots the built
// site, drives one real race on /guide/race/, and asserts the *computed* style
// of a dynamically-created pending card and a dynamically-created sequenced
// card actually differ — which only happens if the scoped selectors are still
// reaching the JS-created nodes.
//
// Usage: node scripts/check-guide-race-styles.mjs
// Requires `pnpm build` to have already produced dist/.
// Needs a local Chrome; set GUIDE_RACE_CHROME to override the executable path.
import { createReadStream, existsSync } from "node:fs";
import { stat } from "node:fs/promises";
import { createServer } from "node:http";
import { extname, join } from "node:path";
import { fileURLToPath } from "node:url";
import puppeteer from "puppeteer-core";

const root = fileURLToPath(new URL("..", import.meta.url));
const distDir = join(root, "dist");

// Snap-confined chromium is listed first: on this project's sandboxed
// dev hosts, google-chrome-stable silently fails to reach 127.0.0.1 (its
// navigations time out with net::ERR_ABORTED) while /snap/bin/chromium
// reaches localhost fine, so it is the more portable default here.
const chrome =
  process.env.GUIDE_RACE_CHROME ??
  process.env.OG_CHROME ??
  ["/snap/bin/chromium", "/usr/bin/google-chrome-stable", "/usr/bin/google-chrome"].find(
    existsSync,
  );
if (!chrome) {
  console.error("No Chrome found; set GUIDE_RACE_CHROME to a browser executable.");
  process.exit(1);
}
if (!existsSync(distDir)) {
  console.error("dist/ is missing; run `pnpm build` before this check.");
  process.exit(1);
}

const MIME = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".svg": "image/svg+xml",
};

function serveDist() {
  return new Promise((resolve) => {
    const server = createServer(async (req, res) => {
      let reqPath = decodeURIComponent(new URL(req.url, "http://localhost").pathname);
      if (reqPath.endsWith("/")) reqPath += "index.html";
      let filePath = join(distDir, reqPath);
      try {
        const info = await stat(filePath);
        if (info.isDirectory()) filePath = join(filePath, "index.html");
      } catch {
        res.writeHead(404).end("not found");
        return;
      }
      res.writeHead(200, { "content-type": MIME[extname(filePath)] ?? "application/octet-stream" });
      createReadStream(filePath).pipe(res);
    });
    server.listen(0, "127.0.0.1", () => resolve(server));
  });
}

async function checkPage(browser, base, path) {
  const page = await browser.newPage();
  page.setDefaultTimeout(15000);
  await page.goto(`${base}${path}`, { waitUntil: "networkidle0" });
  await page.$eval("[data-guide-race-add]", (el) => el.scrollIntoView());
  await page.waitForSelector("[data-guide-race-add]:not([disabled])");

  // The starter note renders sequenced (never pending) as soon as the demo
  // boots, so it is available as the "already sequenced" reference card.
  const sequencedStyle = await page.$eval(
    '[data-client="a"] .gr-note.is-sequenced',
    (el) => {
      const cs = getComputedStyle(el);
      return { border: cs.borderStyle, background: cs.backgroundColor, color: cs.color };
    },
  );
  if (sequencedStyle.border !== "solid") {
    throw new Error(
      `${path}: sequenced note has no border (got border-style: ${sequencedStyle.border}); .gr-note is not reaching JS-created nodes`,
    );
  }

  // Slow playback so the add race leaves a card visibly pending long enough
  // to read its computed style.
  await page.$eval("[data-guide-race-pace]", (el) => {
    el.value = "0.25";
    el.dispatchEvent(new Event("input", { bubbles: true }));
  });
  await page.evaluate(() => {
    Math.random = () => 1;
  });
  await page.click("[data-guide-race-latency-variance]");
  await page.click("[data-guide-race-add]");
  await page.waitForSelector("[data-flow-layer] .flow-dot-label");
  const flowLabel = await page.$eval(
    "[data-flow-layer] .flow-dot-label",
    (el) => el.textContent,
  );
  if (!/\b1100 ms\b/.test(flowLabel ?? "")) {
    throw new Error(
      `${path}: request marker does not show the expected 1000 + 100 ms jitter sample`,
    );
  }
  await page.waitForSelector('[data-client="a"] .gr-note.is-note-pending');
  const pendingStyle = await page.$eval(
    '[data-client="a"] .gr-note.is-note-pending',
    (el) => {
      const cs = getComputedStyle(el);
      return { border: cs.borderStyle, background: cs.backgroundColor, color: cs.color };
    },
  );

  if (pendingStyle.border !== "solid") {
    throw new Error(`${path}: pending note has no border (got border-style: ${pendingStyle.border})`);
  }
  if (pendingStyle.background === sequencedStyle.background) {
    throw new Error(
      `${path}: pending note background (${pendingStyle.background}) does not differ from sequenced note background (${sequencedStyle.background}); .gr-note.is-note-pending is not matching`,
    );
  }
  if (pendingStyle.color === sequencedStyle.color) {
    throw new Error(
      `${path}: pending note color (${pendingStyle.color}) does not differ from sequenced note color (${sequencedStyle.color}); .gr-note.is-note-pending is not matching`,
    );
  }

  // Wait for convergence so the page can close cleanly; also confirms the
  // race itself still finishes once delivery catches up.
  await page.waitForFunction(
    () => document.querySelector("[data-guide-race-status]")?.textContent?.includes("Converged"),
    { timeout: 15000 },
  );

  await page.close();
  console.log(`ok  ${path} — dynamic .gr-note styles reach JS-created nodes`);
}

const server = await serveDist();
const { port } = server.address();
const base = `http://127.0.0.1:${port}`;

const browser = await puppeteer.launch({
  executablePath: chrome,
  headless: "new",
  args: ["--no-sandbox", "--disable-dev-shm-usage"],
});

try {
  await checkPage(browser, base, "/guide/race/");
} finally {
  await browser.close();
  server.close();
}
