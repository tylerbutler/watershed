import { existsSync, readdirSync } from "node:fs";
import { readFile, stat } from "node:fs/promises";
import { createServer } from "node:http";
import { homedir } from "node:os";
import {
  dirname,
  extname,
  isAbsolute,
  join,
  relative,
  resolve,
} from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { spawn } from "node:child_process";

const __dirname = dirname(fileURLToPath(import.meta.url));
const websiteRoot = resolve(__dirname, "..");
const distRoot = resolve(websiteRoot, "dist");

const browserTests = [
  "scripts/structure-demos.test.mjs",
  "scripts/mv-register-demo.test.mjs",
  "scripts/ormap-demo.test.mjs",
  "scripts/lww-map-demo.test.mjs",
  "scripts/or-map-mv-register-demo.test.mjs",
  "scripts/runtime-demos.test.mjs",
  "scripts/structure-runtime-contract.test.mjs",
];

export function resolveStaticPath(root, pathname) {
  const decoded = decodeURIComponent(pathname);
  const relativePath =
    decoded === "/"
      ? "index.html"
      : extname(decoded)
        ? decoded.slice(1)
        : join(decoded.slice(1), "index.html");
  const target = resolve(root, relativePath);
  const inside = relative(root, target);
  return inside.startsWith("..") || isAbsolute(inside) ? null : target;
}

function newestUnder(base, prefix, tail, exists, readDirectory) {
  let entries;
  try {
    entries = readDirectory(base);
  } catch {
    return null;
  }
  const candidates = entries
    .filter((entry) => entry.isDirectory() && entry.name.startsWith(prefix))
    .map((entry) => join(base, entry.name, tail))
    .filter((candidate) => exists(candidate))
    .sort();
  return candidates.at(-1) ?? null;
}

export function findBrowserIn({
  env = process.env,
  home = homedir(),
  exists = existsSync,
  readDirectory = (base) => readdirSync(base, { withFileTypes: true }),
} = {}) {
  const explicit = env.WATERSHED_CHROME;
  if (explicit) return exists(explicit) ? explicit : null;
  for (const candidate of [
    "/usr/bin/google-chrome-stable",
    "/usr/bin/google-chrome",
    "/usr/bin/chromium",
    "/usr/bin/chromium-browser",
    "/snap/bin/chromium",
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  ]) {
    if (exists(candidate)) return candidate;
  }
  return (
    newestUnder(
      join(home, ".cache/ms-playwright"),
      "chromium-",
      "chrome-linux/chrome",
      exists,
      readDirectory,
    ) ??
    newestUnder(
      join(home, ".cache/ms-playwright"),
      "chromium_headless_shell-",
      "chrome-linux/headless_shell",
      exists,
      readDirectory,
    ) ??
    newestUnder(
      join(home, ".cache/puppeteer/chrome"),
      "",
      "chrome-linux64/chrome",
      exists,
      readDirectory,
    )
  );
}

function findBrowser() {
  return findBrowserIn();
}

export function requireBrowser(browser, required) {
  if (browser !== null) return browser;
  if (required) {
    throw new Error("Chromium is required for website browser integration");
  }
  return null;
}

function run(command, args, options = {}) {
  return new Promise((resolveRun, rejectRun) => {
    const child = spawn(command, args, { stdio: "inherit", ...options });
    child.once("error", rejectRun);
    child.once("exit", (code, signal) => {
      if (code === 0) resolveRun();
      else rejectRun(new Error(`${command} exited with ${code ?? signal}`));
    });
  });
}

async function startServer() {
  const contentTypes = {
    ".css": "text/css; charset=utf-8",
    ".html": "text/html; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".json": "application/json; charset=utf-8",
    ".mjs": "text/javascript; charset=utf-8",
    ".svg": "image/svg+xml",
    ".woff2": "font/woff2",
  };
  const server = createServer(async (request, response) => {
    const target = resolveStaticPath(
      distRoot,
      new URL(request.url ?? "/", "http://website").pathname,
    );
    if (target === null) {
      response.writeHead(403).end("forbidden");
      return;
    }
    try {
      if (!(await stat(target)).isFile()) throw new Error("not a file");
      response.writeHead(200, {
        "content-type": contentTypes[extname(target)] ?? "application/octet-stream",
      });
      response.end(await readFile(target));
    } catch {
      response.writeHead(404).end("not found");
    }
  });
  await new Promise((resolveListen, rejectListen) => {
    server.once("error", rejectListen);
    server.listen(0, "127.0.0.1", resolveListen);
  });
  const address = server.address();
  if (address === null || typeof address === "string") {
    throw new Error("website test server did not bind a TCP port");
  }
  return {
    url: `http://127.0.0.1:${address.port}`,
    close: () => new Promise((resolveClose) => server.close(resolveClose)),
  };
}

async function main() {
  const browser = requireBrowser(
    findBrowser(),
    process.env.WATERSHED_REQUIRE_BROWSER === "1",
  );
  if (browser === null) {
    console.log("SKIP website browser integration: Chromium is unavailable");
    return;
  }

  await run("pnpm", ["build"], { cwd: websiteRoot });
  const server = await startServer();
  try {
    await run(process.execPath, ["--test", ...browserTests], {
      cwd: websiteRoot,
      env: {
        ...process.env,
        WATERSHED_CHROME: browser,
        WATERSHED_WEBSITE_URL: server.url,
      },
    });
  } finally {
    await server.close();
  }
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
}
