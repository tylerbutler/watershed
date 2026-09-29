import { createReadStream } from "node:fs";
import { stat } from "node:fs/promises";
import { createServer, request as httpRequest } from "node:http";
import { isAbsolute, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

export function startChecklistServer({
  appRoot = new URL(".", import.meta.url),
  upstream = "http://127.0.0.1:4000",
  port = 8080,
} = {}) {
  const root =
    appRoot instanceof URL ? fileURLToPath(appRoot) : resolve(appRoot);
  const server = createServer(async (request, response) => {
    const url = new URL(request.url, "http://local");
    const pathname =
      url.pathname === "/" ? "/index.html" : decodeURIComponent(url.pathname);
    const target = resolve(root, "." + pathname);
    const inside = relative(root, target);
    if (inside.startsWith("..") || isAbsolute(inside)) {
      response.writeHead(403).end("forbidden");
      return;
    }
    try {
      const info = await stat(target);
      if (!info.isFile()) throw new Error("not a file");
    } catch {
      proxy(request, response, upstream);
      return;
    }
    response.writeHead(200, {
      "content-type": contentType(target),
    });
    createReadStream(target).pipe(response);
  });

  return new Promise((resolveServer, rejectServer) => {
    server.once("error", rejectServer);
    server.listen(port, "127.0.0.1", () => {
      resolveServer({
        port: server.address().port,
        close: () => server.close(),
      });
    });
  });
}

function proxy(incoming, response, upstream) {
  const target = new URL(incoming.url, upstream);
  const outgoing = httpRequest(
    target,
    {
      method: incoming.method,
      headers: incoming.headers,
    },
    (upstreamResponse) => {
      response.writeHead(
        upstreamResponse.statusCode ?? 502,
        upstreamResponse.headers,
      );
      upstreamResponse.pipe(response);
    },
  );
  outgoing.on("error", (error) => {
    response.writeHead(502, { "content-type": "text/plain; charset=utf-8" });
    response.end("Floodgate request failed: " + error.message);
  });
  incoming.pipe(outgoing);
}

function contentType(path) {
  if (path.endsWith(".html")) return "text/html; charset=utf-8";
  if (path.endsWith(".mjs") || path.endsWith(".js")) {
    return "text/javascript; charset=utf-8";
  }
  if (path.endsWith(".json")) return "application/json; charset=utf-8";
  return "application/octet-stream";
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const server = await startChecklistServer();
  console.log("SharedTree checklist: http://127.0.0.1:" + server.port);
}
