import { spawn, execFile } from "node:child_process";
import { once } from "node:events";
import { readFile, writeFile, mkdir, mkdtemp, rm } from "node:fs/promises";
import { createServer } from "node:http";
import { join, resolve } from "node:path";
import { promisify } from "node:util";
import { fileURLToPath } from "node:url";
import { randomInt, randomUUID } from "node:crypto";
import { parse } from "yaml";
import WebSocket, { WebSocketServer } from "ws";
import { bounded, wait } from "./conditions.mjs";
import { createTransport } from "./barrier.mjs";

const exec = promisify(execFile);
const packageRoot = fileURLToPath(new URL("../", import.meta.url));
const composeFile = join(packageRoot, "docker/compose.yaml");

async function freePort() {
  for (let attempt = 0; attempt < 20; attempt++) {
    const server = createServer();
    try {
      // Avoid outbound ephemeral ports being reused before the child service binds.
      await new Promise((resolve, reject) => {
        server.once("error", reject);
        server.listen(randomInt(10_000, 30_000), resolve);
      });
      const port = server.address().port;
      await new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
      return port;
    } catch (error) {
      if (error.code !== "EADDRINUSE") throw error;
    }
  }
  throw new Error("Could not allocate an unused native service port outside the ephemeral range");
}

async function reachable(url) {
  try {
    const response = await fetch(url, { signal: AbortSignal.timeout(3000) });
    await response.body?.cancel();
    return response.status < 500;
  } catch (error) {
    if (error.name === "TimeoutError" || [
      "ECONNREFUSED", "ECONNRESET", "EPIPE", "UND_ERR_SOCKET", "UND_ERR_CONNECT_TIMEOUT",
    ].includes(error.cause?.code)) return false;
    throw error;
  }
}

export async function startServices({
  sdk, root, runId,
  serviceEndpoint = process.env.SHARED_TREE_SERVICE_URL,
  appPort = process.env.SHARED_TREE_APP_PORT ?? 0,
  stateRoot = process.env.SHARED_TREE_SERVICE_STATE_ROOT ?? root,
}) {
  if (!["watershed", "fluid"].includes(sdk)) throw new TypeError("Unknown service SDK");
  if (typeof runId !== "string" || !/^[a-z0-9][a-z0-9-]*$/.test(runId)) {
    throw new TypeError("Service runId must contain lowercase letters, digits, and hyphens");
  }
  if (serviceEndpoint !== undefined) {
    const url = new URL(serviceEndpoint);
    if (!["http:", "https:"].includes(url.protocol) || url.username || url.password ||
        url.search || url.hash || url.pathname !== "/") {
      throw new TypeError("External service endpoint must be an HTTP origin without credentials");
    }
    serviceEndpoint = url.origin;
  }
  if ((typeof appPort === "string" && !/^\d+$/.test(appPort)) ||
      !Number.isInteger(Number(appPort)) || Number(appPort) < 0 || Number(appPort) > 65535) {
    throw new TypeError("App port must be an integer from 0 to 65535");
  }
  const dataRoot = await mkdtemp(join(resolve(stateRoot), ".service-"));
  const project = `incident-${runId}-${randomUUID().slice(0, 8)}`;
  const output = [];
  let endpoint;
  let child;
  let composeStarted = false;
  let imageId;
  let serviceRevision;
  let closing;
  let rejectWrites = false;
  let holdWrites = false;
  let failConnections = false;
  let completedWrites = 0;
  const waitingWrites = [];
  const rejectedRequests = [];
  const sockets = new Set();
  const transport = createTransport({ sdk });
  const transportErrors = [];
  const websocketServer = new WebSocketServer({ noServer: true });
  const server = createServer(async (request, response) => {
    const url = new URL(request.url, "http://app");
    try {
      if (url.pathname.startsWith("/api/") || /^\/(repos|documents|deltas|trees|socket\.io)\//.test(url.pathname)) {
        if (!endpoint) throw new Error("Service is not ready");
        if (rejectWrites && !["GET", "HEAD", "OPTIONS"].includes(request.method)) {
          request.resume();
          rejectedRequests.push({ method: request.method, path: url.pathname });
          response.writeHead(400, { "content-type": "application/json" })
            .end(JSON.stringify({ message: "Injected local service rejection" }));
          return;
        }
        if (holdWrites && !["GET", "HEAD", "OPTIONS"].includes(request.method)) {
          await new Promise(resolve => waitingWrites.push(resolve));
        }
        const target = endpoint + (url.pathname.startsWith("/api/") ? url.pathname.slice(4) : url.pathname) + url.search;
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
        if (!["GET", "HEAD", "OPTIONS"].includes(request.method)) completedWrites++;
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
  server.on("upgrade", (request, socket, head) => {
    if (failConnections) {
      socket.end("HTTP/1.1 503 Service Unavailable\r\nConnection: close\r\nContent-Length: 0\r\n\r\n");
      return;
    }
    if (!endpoint) { socket.destroy(new Error("Service is not ready")); return; }
    websocketServer.handleUpgrade(request, socket, head, client => {
      const clientId = transport.register();
      const target = new URL(request.url, endpoint.replace("http:", "ws:"));
      const upstream = new WebSocket(target);
      sockets.add(client);
      sockets.add(upstream);
      const queued = [];
      const stop = () => { client.terminate(); upstream.terminate(); };
      const failed = error => {
        output.push(`WebSocket proxy: ${error.message}`);
        stop();
      };
      client.on("error", failed);
      upstream.on("error", failed);
      client.on("close", () => { transport.unregister(clientId); sockets.delete(client); upstream.close(); });
      upstream.on("close", () => { sockets.delete(upstream); client.close(); });
      client.on("message", (data, isBinary) => {
        try {
          transport.forward(clientId, "submit", data, isBinary, () => {
            if (upstream.readyState === WebSocket.OPEN) upstream.send(data, { binary: isBinary });
            else if (upstream.readyState === WebSocket.CONNECTING) queued.push([data, isBinary]);
          });
        } catch (error) { transportErrors.push(error.message); failed(error); }
      });
      upstream.on("open", () => {
        for (const [data, binary] of queued) upstream.send(data, { binary });
        queued.length = 0;
      });
      upstream.on("message", (data, binary) => {
        if (client.readyState !== WebSocket.OPEN) return;
        try {
          transport.forward(clientId, "receive", data, binary, () => {
            if (client.readyState === WebSocket.OPEN) client.send(data, { binary });
          });
        } catch (error) { transportErrors.push(error.message); failed(error); }
      });
    });
  });
  let origin;
  const compose = async args => {
    const result = await exec("podman", ["compose", "-f", composeFile, "-p", project,
      "--profile", "watershed", ...args], {
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
      for (const resume of waitingWrites.splice(0)) resume();
      for (const socket of sockets) socket.terminate();
      await new Promise((resolve, reject) => websocketServer.close(error => error ? reject(error) : resolve()));
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
      server.listen(Number(appPort), "127.0.0.1", resolve);
    });
    origin = `http://127.0.0.1:${server.address().port}`;
    if (serviceEndpoint !== undefined) {
      endpoint = serviceEndpoint;
      await wait("External native service ready",
        () => reachable(sdk === "fluid" ? endpoint : `${endpoint}/health`), Boolean, 30_000);
    } else if (sdk === "fluid") {
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
      await wait("Fluid service ready", () => {
        if (child.exitCode !== null || child.signalCode !== null) {
          throw new Error(`Fluid service exited (${child.exitCode ?? child.signalCode}): ${output.join("")}`);
        }
        return reachable(endpoint);
      }, Boolean, 30_000);
    } else {
      composeStarted = true;
      await compose(["up", "-d", "--build", "--wait"]);
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
    if (sdk === "fluid") url.searchParams.set("endpoint", origin);
    else {
      url.searchParams.set("base", `${origin}/api`);
      url.searchParams.set("socket", origin.replace("http:", "ws:") + "/socket/websocket?vsn=2.0.0");
    }
    return {
      appUrl: url.href,
      health: () => reachable(sdk === "fluid" ? endpoint : `${endpoint}/health`),
      transport,
      failConnections(enabled) {
        if (typeof enabled !== "boolean") throw new TypeError("Connection failure requires a boolean");
        failConnections = enabled;
        if (enabled) for (const socket of sockets) socket.terminate();
      },
      rejectHttpWrites(enabled) {
        if (typeof enabled !== "boolean") throw new TypeError("Failure injection requires a boolean");
        rejectWrites = enabled;
      },
      holdHttpWrites(enabled) {
        if (typeof enabled !== "boolean") throw new TypeError("HTTP delivery control requires a boolean");
        holdWrites = enabled;
        if (!enabled) for (const resume of waitingWrites.splice(0)) resume();
      },
      diagnostics: () => ({ sdk, endpoint, project, dataRoot, imageId, serviceRevision,
        rejectedRequests: [...rejectedRequests], pendingWrites: waitingWrites.length,
        completedWrites, openSockets: sockets.size, transportErrors: [...transportErrors], output: [...output] }),
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
