import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { existsSync } from "node:fs";
import { mkdtemp, readdir, rm, writeFile } from "node:fs/promises";
import { createConnection, createServer } from "node:net";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const repository = resolve(dirname(fileURLToPath(import.meta.url)), "../..");

export class JsonLinesChannel {
  #child;
  #pending = new Map();
  #completed = new Set();
  #nextId = 1;
  #buffer = "";
  #failure;
  #timeout;

  constructor(child, timeout = 60_000) {
    this.#child = child;
    this.#timeout = timeout;
    child.stdout.setEncoding("utf8");
    child.stdout.on("data", (chunk) => this.#receive(chunk));
    child.on("error", (error) => this.#abort(error));
    child.on("exit", (code, signal) =>
      this.#abort(new Error(`Native client exited (${code ?? signal})`)));
    child.stdout.on("end", () => this.#abort(new Error("Native client closed stdout")));
  }

  #abort(error) {
    if (this.#failure) return;
    this.#failure = error;
    for (const { reject, timer } of this.#pending.values()) {
      clearTimeout(timer);
      reject(error);
    }
    this.#pending.clear();
  }

  #receive(chunk) {
    if (this.#failure) return;
    this.#buffer += chunk;
    if (this.#buffer.length > 1024 * 1024) {
      this.#abort(new Error("Native client reply exceeds the line limit"));
      return;
    }
    let end;
    while ((end = this.#buffer.indexOf("\n")) >= 0) {
      const line = this.#buffer.slice(0, end);
      this.#buffer = this.#buffer.slice(end + 1);
      let reply;
      try {
        reply = JSON.parse(line);
      } catch (error) {
        this.#abort(new Error(`Native client emitted invalid JSON: ${error.message}`));
        return;
      }
      const id = reply?.requestId;
      if (!Number.isSafeInteger(id) || this.#completed.has(id) || !this.#pending.has(id)
        || typeof reply.ok !== "boolean") {
        this.#abort(new Error(`Unmatched, duplicate, or invalid native reply: ${line}`));
        return;
      }
      const entry = this.#pending.get(id);
      clearTimeout(entry.timer);
      this.#pending.delete(id);
      this.#completed.add(id);
      entry.resolve(reply);
    }
  }

  request(command) {
    if (this.#failure) return Promise.reject(this.#failure);
    const requestId = this.#nextId++;
    assert(Number.isSafeInteger(requestId), "Command request ID exceeded the safe range");
    return new Promise((resolve, reject) => {
      const timer = setTimeout(
        () => this.#abort(new Error(`Native command ${requestId} timed out`)),
        this.#timeout,
      );
      this.#pending.set(requestId, { resolve, reject, timer });
      this.#child.stdin.write(`${JSON.stringify({ ...command, requestId })}\n`, (error) => {
        if (error) this.#abort(error);
      });
    });
  }

  end() {
    this.#child.stdin.end();
  }
}

export class TcpGate {
  #server;
  #host;
  #port;
  #pairs = new Set();
  #waiting = new Set();
  #withheld = false;
  #inbound = false;
  #outbound = false;

  constructor(server, host, port) {
    this.#server = server;
    this.#host = host;
    this.#port = port;
  }

  static async open(host, port) {
    const server = createServer();
    const gate = new TcpGate(server, host, port);
    server.on("connection", (socket) => gate.#accept(socket));
    server.listen(0, "127.0.0.1");
    await once(server, "listening");
    return gate;
  }

  get port() { return this.#server.address().port; }

  #accept(client) {
    client.on("error", () => client.destroy());
    if (this.#withheld) this.#waiting.add(client);
    else this.#forward(client);
    client.on("close", () => this.#waiting.delete(client));
  }

  #forward(client) {
    if (client.destroyed) return;
    const upstream = createConnection(this.#port, this.#host);
    const pair = { client, upstream };
    this.#pairs.add(pair);
    upstream.on("error", () => client.destroy());
    client.on("close", () => { upstream.destroy(); this.#pairs.delete(pair); });
    upstream.on("close", () => { client.destroy(); this.#pairs.delete(pair); });
    client.pipe(upstream);
    upstream.pipe(client);
    if (this.#outbound) client.pause();
    if (this.#inbound) upstream.pause();
  }

  pauseInbound() {
    this.#inbound = true;
    for (const { upstream } of this.#pairs) upstream.pause();
  }

  pauseOutbound() {
    this.#outbound = true;
    for (const { client } of this.#pairs) client.pause();
  }

  async disconnect() {
    this.#withheld = true;
    for (const { client, upstream } of this.#pairs) {
      client.destroy();
      upstream.destroy();
    }
    this.#pairs.clear();
  }

  async reconnect() {
    this.#withheld = false;
    this.#inbound = false;
    this.#outbound = false;
    for (const client of this.#waiting) {
      this.#waiting.delete(client);
      this.#forward(client);
    }
  }

  async close() {
    this.#withheld = true;
    const closed = new Promise((resolve, reject) =>
      this.#server.close((error) => error ? reject(error) : resolve()));
    for (const { client, upstream } of this.#pairs) {
      client.destroy();
      upstream.destroy();
    }
    for (const client of this.#waiting) client.destroy();
    this.#pairs.clear();
    this.#waiting.clear();
    await closed;
  }
}

export async function startClient(target, descriptor, environment) {
  assert(["javascript", "erlang"].includes(target), "Unsupported native target");
  const upstream = new URL(environment.socketUrl);
  assert.equal(upstream.protocol, "http:", "Native gate requires the local HTTP profile");
  const gate = await TcpGate.open(upstream.hostname, Number(upstream.port || 80));
  const directory = await mkdtemp(join(tmpdir(), "watershed-tree-client-"));
  const file = join(directory, "descriptor.json");
  const socketUrl = `ws://127.0.0.1:${gate.port}/socket/websocket?vsn=2.0.0`;
  await writeFile(file, JSON.stringify({
    protocolVersion: 1,
    ...descriptor,
    socketUrl,
    host: "127.0.0.1",
    port: gate.port,
  }), { mode: 0o600 });
  const env = {
    ...process.env,
    WATERSHED_DESCRIPTOR: file,
    WATERSHED_TOKEN: environment.token,
    ERL_CRASH_DUMP: join(directory, "erl-crash.dump"),
  };
  let command;
  let args;
  if (target === "javascript") {
    const entry = join(repository,
      "build/dev/javascript/watershed/watershed/tree/client_js.mjs");
    assert(existsSync(entry), `Missing native JavaScript client: ${entry}`);
    command = process.execPath;
    args = ["--input-type=module", "-e",
      `import(${JSON.stringify(pathToFileURL(entry).href)}).then((module) => module.main())`];
  } else {
    const erlang = join(repository, "build/dev/erlang");
    const libraries = (await readdir(erlang, { withFileTypes: true }))
      .filter((entry) => entry.isDirectory())
      .map((entry) => join(erlang, entry.name, "ebin"));
    assert(libraries.length > 0, "Missing BEAM build artifacts");
    command = "erl";
    args = ["-noshell", "-pa", ...libraries,
      "-eval", "ok = logger:remove_handler(default), ok = logger:add_handler(default, logger_std_h, #{config => #{type => standard_error}}), {ok, _} = application:ensure_all_started(watershed), 'watershed@tree@client_beam':main(), init:stop()."];
  }
  const child = spawn(command, args, {
    cwd: repository, env, stdio: ["pipe", "pipe", "inherit"],
  });
  const channel = new JsonLinesChannel(child);
  return {
    gate,
    request: (command) => channel.request(command),
    async close() {
      try {
        if (child.exitCode === null && !child.killed) {
          try {
            await channel.request({ command: "close" });
            channel.end();
            if (child.exitCode === null) {
              await Promise.race([
                once(child, "exit"),
                new Promise((_resolve, reject) =>
                  setTimeout(() => reject(new Error("Native client did not exit")), 5000)),
              ]);
            }
          } catch {
            child.kill();
          }
        }
      } finally {
        if (child.exitCode === null) child.kill();
        await gate.close();
        await rm(directory, { recursive: true, force: true });
      }
    },
  };
}
