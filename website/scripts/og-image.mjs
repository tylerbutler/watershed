// Renders public/og.png — the site's Open Graph card — as a 1200×630 survey
// sheet in the same visual system as the landing page. The contour field is
// generated from the shared hero generator so the card and the hero agree.
//
// Usage: node scripts/og-image.mjs
// Needs a local Chrome; set OG_CHROME to override the executable path.
import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import puppeteer from "puppeteer-core";
import { W, H, ROWS, contourPath } from "../src/scripts/contour-field.js";

const root = fileURLToPath(new URL("..", import.meta.url));
const font = (pkgPath) =>
  new URL(`../node_modules/${pkgPath}`, import.meta.url).href;

const chrome =
  process.env.OG_CHROME ??
  ["/usr/bin/google-chrome-stable", "/usr/bin/google-chrome", "/snap/bin/chromium"].find(
    existsSync,
  );
if (!chrome) {
  console.error("No Chrome found; set OG_CHROME to a browser executable.");
  process.exit(1);
}

const contours = Array.from({ length: ROWS }, (_, i) => ({
  d: contourPath(i),
  index: i % 4 === 1,
  sn: 1240 - i * 20,
}));

const contourSvg = contours
  .map(({ d, index, sn }, i) => {
    const path = `<path id="c${i}" d="${d}" fill="none" stroke="${
      index ? "var(--overprint)" : "var(--waterline-faint)"
    }" stroke-width="${index ? 1.4 : 1}"/>`;
    const label = index
      ? `<text class="sn" dy="-4"><textPath href="#c${i}" startOffset="${i >= 8 ? 90 : 93}%">SN ${sn}</textPath></text>`
      : "";
    return path + label;
  })
  .join("\n      ");

const html = `<!doctype html>
<html><head><meta charset="utf-8">
<style>
  @font-face {
    font-family: "Archivo Variable";
    font-style: normal;
    font-weight: 100 900;
    font-stretch: 62% 125%;
    src: url("${font("@fontsource-variable/archivo/files/archivo-latin-wdth-normal.woff2")}") format("woff2-variations");
  }
  @font-face {
    font-family: "JetBrains Mono";
    font-style: normal;
    font-weight: 400;
    src: url("${font("@fontsource/jetbrains-mono/files/jetbrains-mono-latin-400-normal.woff2")}") format("woff2");
  }

  :root {
    --bg: oklch(100% 0 0);
    --ink: oklch(25% 0.02 260);
    --muted: oklch(44% 0.015 260);
    --overprint: oklch(55% 0.21 340);
    --overprint-deep: oklch(44% 0.185 340);
    --waterline-faint: oklch(37% 0.095 240 / 0.35);
    --font-sans: "Archivo Variable", sans-serif;
    --font-mono: "JetBrains Mono", monospace;
  }

  * { margin: 0; box-sizing: border-box; }

  body {
    width: 1200px;
    height: 630px;
    background: var(--bg);
    color: var(--ink);
    font-family: var(--font-sans);
    display: flex;
    flex-direction: column;
    padding: 26px 34px;
  }

  .annot {
    font-family: var(--font-mono);
    font-size: 15px;
    letter-spacing: 0.07em;
    text-transform: uppercase;
    color: var(--muted);
  }

  .margin-row {
    display: flex;
    justify-content: space-between;
    align-items: baseline;
    padding: 0 2px;
    flex: none;
  }
  .margin-row.top { padding-bottom: 14px; }
  .margin-row.bottom { padding-top: 14px; }
  .margin-row .magenta { color: var(--overprint-deep); }

  .wordmark {
    font-family: var(--font-mono);
    font-size: 17px;
    color: var(--ink);
  }

  /* the sheet: neatline + registration crosses */
  .sheet {
    position: relative;
    flex: 1;
    border: 1.5px solid var(--ink);
    background: var(--bg);
  }

  /* clip the contour field without clipping the registration crosses */
  .field {
    position: absolute;
    inset: 0;
    overflow: hidden;
  }

  .reg {
    position: absolute;
    width: 25px;
    height: 25px;
    background:
      linear-gradient(var(--ink), var(--ink)) center / 1.5px 100% no-repeat,
      linear-gradient(var(--ink), var(--ink)) center / 100% 1.5px no-repeat;
    z-index: 2;
  }
  .reg.tl { top: -13.25px; left: -13.25px; }
  .reg.tr { top: -13.25px; right: -13.25px; }
  .reg.bl { bottom: -13.25px; left: -13.25px; }
  .reg.br { bottom: -13.25px; right: -13.25px; }

  .contours {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    mask-image: linear-gradient(
      100deg,
      transparent 40%,
      oklch(0 0 0 / 0.35) 64%,
      black 86%
    );
    -webkit-mask-image: linear-gradient(
      100deg,
      transparent 40%,
      oklch(0 0 0 / 0.35) 64%,
      black 86%
    );
  }

  .sn {
    font-family: var(--font-mono);
    font-size: 12px;
    letter-spacing: 0.08em;
    fill: var(--overprint-deep);
  }

  .inner {
    position: relative;
    height: 100%;
    display: flex;
    flex-direction: column;
    justify-content: center;
    padding: 0 64px;
  }

  h1 {
    font-size: 88px;
    font-weight: 640;
    font-stretch: 122%;
    line-height: 0.99;
    letter-spacing: -0.025em;
  }
  h1 em {
    font-style: normal;
    color: var(--overprint-deep);
  }

  .tagline {
    margin-top: 40px;
    font-family: var(--font-mono);
    font-size: 20px;
    letter-spacing: 0.07em;
    text-transform: uppercase;
    color: var(--muted);
  }
  .tagline .tick { color: var(--overprint); }
</style></head>
<body>
  <div class="margin-row top">
    <span class="wordmark">watershed</span>
    <span class="annot">Photorevised — state flows toward sequencing</span>
  </div>

  <div class="sheet">
    <span class="reg tl"></span><span class="reg tr"></span>
    <span class="reg bl"></span><span class="reg br"></span>
    <div class="field">
      <svg class="contours" viewBox="0 0 ${W} ${H}" preserveAspectRatio="xMaxYMid slice" aria-hidden="true">
        ${contourSvg}
      </svg>
    </div>
    <div class="inner">
      <h1>Edit upstream.<br>Converge <em>downstream.</em></h1>
      <p class="tagline"><span class="tick">▸</span> Collaborative data structures for Gleam</p>
    </div>
  </div>

  <div class="margin-row bottom">
    <span class="annot magenta">Magenta indicates revisions not yet field-checked</span>
    <span class="annot">watershed.tylerbutler.com</span>
  </div>
</body></html>`;

const browser = await puppeteer.launch({
  executablePath: chrome,
  args: ["--no-sandbox", "--force-color-profile=srgb"],
});
const page = await browser.newPage();
await page.setViewport({ width: 1200, height: 630, deviceScaleFactor: 2 });
await page.setContent(html, { waitUntil: "networkidle0" });
await page.evaluate(() => document.fonts.ready);
const out = new URL("../public/og.png", import.meta.url);
await page.screenshot({ path: fileURLToPath(out) });
await browser.close();
console.log(`wrote ${fileURLToPath(out).replace(root, "")}`);
