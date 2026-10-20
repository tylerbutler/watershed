import { spawn, execFile } from "node:child_process";
import { once } from "node:events";
import { readFile, writeFile, mkdir, mkdtemp, rm } from "node:fs/promises";
import { createServer } from "node:http";
import { join, resolve } from "node:path";
import { promisify } from "node:util";
import { fileURLToPath } from "node:url";
import { randomUUID } from "node:crypto";
import { parse } from "yaml";
import { bounded, wait } from "./conditions.mjs";

const exec = promisify(execFile);
const packageRoot = fileURLToPath(new URL("../", import.meta.url));
const composeFile = join(packageRoot, "docker/compose.yaml");

async function freePort() {
  const server = createServer();
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });
  const port = server.address().port;
  await new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
  return port;
}

async function reachable(url) {
  try {
    const response = await fetch(url, { signal: AbortSignal.timeout(3000) });
    await response.body?.cancel();
    return response.status < 500;
  } catch (error) {
    if (error.cause?.code === "ECONNREFUSED") return false;
    throw error;
  }
}

export async function startServices({ sdk, root, runId }) {
  if (!["watershed", "fluid"].includes(sdk)) throw new TypeError("Unknown service SDK");
  if (typeof runId !== "string" || !/^[a-z0-9][a-z0-9-]*$/.test(runId)) {
    throw new TypeError("Service runId must contain lowercase letters, digits, and hyphens");
  }
  const dataRoot = await mkdtemp(join(resolve(root), ".service-"));
  const project = `incident-${runId}-${randomUUID().slice(0, 8)}`;
  const output = [];
  let endpoint;
  let child;
  let composeStarted = false;
  let imageId;
  let serviceRevision;
  let closing;
  const server = createServer(async (request, response) => {
    const url = new URL(request.url, "http://app");
    try {
      if (url.pathname.startsWith("/api/")) {
        if (!endpoint) throw new Error("Service is not ready");
        const target = endpoint + url.pathname.slice(4) + url.search;
        const chunks = [];
        for await (const chunk of request) chunks.push(chunk);
        const headers = { ...request.headers };
        delete headers.host;
        delete headers.connection;
        delete headers["content-length"];
        const result = await fetch(target, {
          method: request.method,
          headers,
          ...(["GET", "HEAD"].includes(request.method) ? {} : { body: Buffer.concat(chunks) }),
          signal: AbortSignal.timeout(10_000),
        });
        const body = Buffer.from(await result.arrayBuffer());
        response.writeHead(result.status, { "content-type": result.headers.get("content-type") ?? "application/octet-stream" });
        response.end(body);
        return;
      }
      const file = url.pathname === "/" ? "index.html" : url.pathname.slice(1);
      if (!["index.html", "app.js"].includes(file)) { response.writeHead(404).end(); return; }
      const content = await readFile(join(root, "dist", file));
      response.writeHead(200, { "content-type": file.endsWith(".js") ? "text/javascript" : "text/html" });
      response.end(content);
    } catch (error) {
      output.push(`HTTP ${request.url}: ${error.message}`);
      if (response.headersSent) response.destroy(error);
      else response.writeHead(502).end(error.message);
    }
  });
  let origin;
  const compose = async args => {
    const result = await exec("podman", ["compose", "-f", composeFile, "-p", project, ...args], {
      env: {
        ...process.env,
        DOCKER_CONFIG: join(dataRoot, "docker-client"),
        APP_PUBLIC_URL: `${origin}/api`,
      },
      timeout: 600_000,
      maxBuffer: 4 * 1024 * 1024,
    });
    output.push(result.stdout, result.stderr);
    return result.stdout.trim();
  };
  const close = () => closing ??= (async () => {
    try {
      if (child && child.exitCode === null && child.signalCode === null) {
        const exited = once(child, "exit");
        child.kill("SIGTERM");
        const timer = setTimeout(() => child.kill("SIGKILL"), 5000);
        try { await bounded("Fluid service shutdown", () => exited, 10_000); }
        finally { clearTimeout(timer); }
      }
      if (composeStarted) await compose(["down", "--volumes", "--remove-orphans"]);
    } finally {
      if (server.listening) {
        const stopped = new Promise((resolve, reject) =>
          server.close(error => error ? reject(error) : resolve()));
        server.closeAllConnections();
        await stopped;
      }
      await rm(dataRoot, { recursive: true, force: true });
    }
  })();
  try {
    await mkdir(join(dataRoot, "docker-client"));
    await writeFile(join(dataRoot, "docker-client/config.json"), "{}\n");
    await new Promise((resolve, reject) => {
      server.once("error", reject);
      server.listen(0, "127.0.0.1", resolve);
    });
    origin = `http://127.0.0.1:${server.address().port}`;
    if (sdk === "fluid") {
      const port = await freePort();
      endpoint = `http://localhost:${port}`;
      await mkdir(join(dataRoot, "storage"));
      child = spawn(process.execPath, [
        join(root, "node_modules/@fluidframework/azure-local-service/index.js"),
      ], {
        cwd: dataRoot,
        env: {
          ...process.env, PORT: String(port),
          storage: join(dataRoot, "storage"),
          db__path: join(dataRoot, "db"),
        },
        stdio: ["ignore", "pipe", "pipe"],
      });
      child.stdout.on("data", chunk => output.push(chunk.toString()));
      child.stderr.on("data", chunk => output.push(chunk.toString()));
      await Promise.race([
        wait("Fluid service ready", () => reachable(endpoint), Boolean, 30_000),
        once(child, "exit").then(([code]) => {
          throw new Error(`Fluid service exited (${code}): ${output.join("")}`);
        }),
      ]);
    } else {
      composeStarted = true;
      await compose(["--profile", "watershed", "up", "-d", "--build", "--wait"]);
      const definition = parse(await readFile(composeFile, "utf8")).services.floodgate;
      serviceRevision = definition.build.context.split("#")[1];
      if (!/^[0-9a-f]{40}$/.test(serviceRevision)) throw new Error("Floodgate source must use a full revision");
      const image = await exec("podman", ["image", "inspect", definition.image], { timeout: 10_000 });
      const id = JSON.parse(image.stdout)[0].Id.replace(/^sha256:/, "");
      if (!/^[0-9a-f]{64}$/.test(id)) throw new Error("Floodgate image has no content-addressed identity");
      imageId = `sha256:${id}`;
      const address = await compose(["port", "floodgate", "3000"]);
      if (!/^127\.0\.0\.1:\d+$/.test(address)) throw new Error(`Unexpected Floodgate address: ${address}`);
      endpoint = `http://${address}`;
      await wait("Floodgate ready", () => reachable(`${endpoint}/health`), Boolean);
    }
    const url = new URL(origin);
    if (sdk === "fluid") url.searchParams.set("endpoint", endpoint);
    else {
      url.searchParams.set("base", `${origin}/api`);
      url.searchParams.set("socket", endpoint.replace("http:", "ws:") + "/socket/websocket?vsn=2.0.0");
    }
    return {
      appUrl: url.href,
      health: () => reachable(sdk === "fluid" ? endpoint : `${endpoint}/health`),
      diagnostics: () => ({ sdk, endpoint, project, dataRoot, imageId, serviceRevision, output: [...output] }),
      close,
    };
  } catch (error) {
    try {
      await close();
    } catch (cleanupError) {
      throw new AggregateError([error, cleanupError], `${sdk} service setup and cleanup failed`);
    }
    throw new Error(`${sdk} service setup failed: ${error.message}; ${output.join("")}`, { cause: error });
  }
}
