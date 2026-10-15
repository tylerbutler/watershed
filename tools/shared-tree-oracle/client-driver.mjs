import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import { once } from "node:events";
import { existsSync } from "node:fs";
import { mkdir, mkdtemp, readdir, rm, writeFile } from "node:fs/promises";
import { createConnection, createServer } from "node:net";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { constants, inflateRawSync } from "node:zlib";

const repository = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const nativeReplyLineLimit = 32 * 1024 * 1024;

export class JsonLinesChannel {
  #child;
  #pending = new Map();
  #completed = new Set();
  #nextId = 1;
  #buffer = "";
  #failure;
  #timeout;
  #stderr = "";
  #stderrLimit = 64 * 1024;

  constructor(child, timeout = 60_000) {
    this.#child = child;
    this.#timeout = timeout;
    child.stdout.setEncoding("utf8");
    child.stdout.on("data", (chunk) => this.#receive(chunk));
    if (child.stderr) {
      child.stderr.setEncoding("utf8");
      child.stderr.on("data", (chunk) => {
        this.#stderr = (this.#stderr + chunk).slice(-this.#stderrLimit);
      });
    }
    child.on("error", (error) => this.#abort(error));
    child.on("close", (code, signal) => {
      const cause = this.#startupCause();
      const diagnostics = this.#stderr.trim();
      this.#abort(new Error(
        `Native client exited (${code ?? signal})`
          + (diagnostics ? `\n${diagnostics}` : ""),
        cause ? { cause } : {},
      ));
    });
  }

  get failure() { return this.#failure; }

  #startupCause() {
    for (const line of this.#stderr.trimEnd().split("\n").reverse()) {
      try {
        const value = JSON.parse(line);
        if (value?.kind === "startup-error"
          && typeof value.code === "string"
          && typeof value.operation === "string"
          && typeof value.message === "string") {
          return {
            kind: value.kind,
            code: value.code,
            operation: value.operation,
            message: value.message,
          };
        }
      } catch {
        // Native runtimes can write diagnostics around the structured record.
      }
    }
    return undefined;
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
    let end;
    while ((end = this.#buffer.indexOf("\n")) >= 0) {
      if (end > nativeReplyLineLimit) {
        this.#abort(new Error("Native client reply exceeds the line limit"));
        return;
      }
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
    if (this.#buffer.length > nativeReplyLineLimit) {
      this.#abort(new Error("Native client reply exceeds the line limit"));
    }
  }

  async #result(command) {
    const reply = await this.request(command);
    if (!reply.ok) {
      throw new Error(`Native ${command.command ?? command.op} failed`, {
        cause: reply.error,
      });
    }
    return reply.result;
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

  read(path, tree) {
    return this.#result({
      command: "read",
      ...(tree === undefined ? {} : { tree }),
      path,
    });
  }

  createDataStore(name) {
    return this.#result({ command: "create-data-store", name });
  }

  trySetAlias(store, alias) {
    return this.#result({ command: "try-set-alias", store, alias });
  }

  rootMap(name) {
    return this.#result({ command: "root-map", name });
  }

  dataStoreRoot(store, name) {
    return this.#result({ command: "data-store-root", store, name });
  }

  createMap(name, store) {
    return this.#result({
      command: "create-map",
      ...(store === undefined ? {} : { store }),
      name,
    });
  }

  openMap(name, handle) {
    return this.#result({ command: "open-map", name, handle });
  }

  sharedMapGet(name, key) {
    return this.#result({ command: "shared-map-get", name, key });
  }

  sharedMapSet(name, key, value) {
    return this.#result({ command: "shared-map-set", name, key, value });
  }

  sharedMapDelete(name, key) {
    return this.#result({ command: "shared-map-delete", name, key });
  }

  sharedMapEntries(name) {
    return this.#result({ command: "shared-map-entries", name });
  }

  createTree({ name, store, schema, initialRoot, view }) {
    return this.#result({
      command: "create-tree",
      ...(store === undefined ? {} : { store }),
      name,
      schema,
      initialRoot,
      view,
    });
  }

  openTree(name, handle, view) {
    return this.#result({ command: "open-tree", name, handle, view });
  }

  mapGet(path, key, tree) {
    return this.#result({ command: "map-get", ...(tree === undefined ? {} : { tree }), path, key });
  }

  mapSet(path, key, value, tree) {
    return this.#result({
      command: "map-set", ...(tree === undefined ? {} : { tree }), path, key, value,
    });
  }

  mapDelete(path, key, tree) {
    return this.#result({
      command: "map-delete", ...(tree === undefined ? {} : { tree }), path, key,
    });
  }

  mapKeys(path, tree) {
    return this.#result({ command: "map-keys", ...(tree === undefined ? {} : { tree }), path });
  }

  mapEntries(path, tree) {
    return this.#result({
      command: "map-entries", ...(tree === undefined ? {} : { tree }), path,
    });
  }

  schemaCompatibility(view, tree) {
    return this.#result({
      command: "schema-compatibility", ...(tree === undefined ? {} : { tree }), view,
    });
  }

  schemaUpgrade(view, tree) {
    return this.#result({
      command: "schema-upgrade", ...(tree === undefined ? {} : { tree }), view,
    });
  }

  openView(view, tree) {
    return this.#result({ command: "open-view", ...(tree === undefined ? {} : { tree }), view });
  }

  subscribe(tree) {
    return this.#result({ command: "subscribe", ...(tree === undefined ? {} : { tree }) });
  }

  unsubscribe(tree) {
    return this.#result({ command: "unsubscribe", ...(tree === undefined ? {} : { tree }) });
  }

  checkpoint(tree) {
    return this.#result({ command: "checkpoint", ...(tree === undefined ? {} : { tree }) });
  }

  arrayGet(path, index, tree) {
    return this.#result({
      command: "array-get", ...(tree === undefined ? {} : { tree }), path, index,
    });
  }

  arrayValues(path, tree) {
    return this.#result({
      command: "array-values", ...(tree === undefined ? {} : { tree }), path,
    });
  }

  arrayInsert(path, index, values, tree) {
    return this.#result({
      command: "array-insert", ...(tree === undefined ? {} : { tree }), path, index, values,
    });
  }

  arrayRemove(path, start, end, tree) {
    return this.#result({
      command: "array-remove", ...(tree === undefined ? {} : { tree }), path, start, end,
    });
  }

  arrayMove(sourcePath, sourceStart, sourceEnd, destinationPath, destinationGap, tree) {
    return this.#result({
      command: "array-move",
      ...(tree === undefined ? {} : { tree }),
      sourcePath,
      sourceStart,
      sourceEnd,
      destinationPath,
      destinationGap,
    });
  }

  constrainedArrayRemove(targetPath, path, start, end, tree) {
    return this.#result({
      command: "constrained-array-remove",
      ...(tree === undefined ? {} : { tree }),
      targetPath,
      path,
      start,
      end,
    });
  }

  transaction({ constraints, edits, result, tree }) {
    return this.#result({
      command: "transaction", ...(tree === undefined ? {} : { tree }), constraints, edits, result,
    });
  }

  fork(source, name, tree) {
    return this.#result({ op: "fork", ...(tree === undefined ? {} : { tree }), source, name });
  }

  branchEdit(branch, edit, tree) {
    return this.#result({
      op: "branchEdit", ...(tree === undefined ? {} : { tree }), branch, edit,
    });
  }

  rebaseBranch(source, target, tree) {
    return this.#result({
      op: "rebaseBranch", ...(tree === undefined ? {} : { tree }), source, target,
    });
  }

  mergeBranch(target, source, dispose, tree) {
    return this.#result({
      op: "mergeBranch", ...(tree === undefined ? {} : { tree }), target, source, dispose,
    });
  }

  disposeBranch(name, tree) {
    return this.#result({
      op: "disposeBranch", ...(tree === undefined ? {} : { tree }), name,
    });
  }

  retainLastLocalCommit(name, branch, tree) {
    return this.#result({
      op: "retainLastLocalCommit",
      ...(tree === undefined ? {} : { tree }),
      name,
      ...(branch === undefined ? {} : { branch }),
    });
  }

  revertibleStatus(name, tree) {
    return this.#result({
      op: "revertibleStatus", ...(tree === undefined ? {} : { tree }), name,
    });
  }

  disposeRevertible(name, tree) {
    return this.#result({
      op: "disposeRevertible", ...(tree === undefined ? {} : { tree }), name,
    });
  }

  revert(name, dispose, tree) {
    return this.#result({
      op: "revert", ...(tree === undefined ? {} : { tree }), name, dispose,
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
  #pauseAfterConnectSuccess = false;
  #connectSuccesses = 0;
  #withheldBytes = [];

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
  get connections() { return this.#pairs.size; }
  get connectSuccesses() { return this.#connectSuccesses; }

  #accept(client) {
    client.on("error", () => client.destroy());
    if (this.#withheld) this.#waiting.add(client);
    else this.#forward(client);
    client.on("close", () => this.#waiting.delete(client));
  }

  #forward(client) {
    if (client.destroyed) return;
    const upstream = createConnection(this.#port, this.#host);
    const pair = {
      client, upstream, buffer: Buffer.alloc(0),
      dictionary: Buffer.alloc(0), upgrading: true,
    };
    this.#pairs.add(pair);
    upstream.on("error", () => client.destroy());
    client.on("close", () => { upstream.destroy(); this.#pairs.delete(pair); });
    upstream.on("close", () => { client.destroy(); this.#pairs.delete(pair); });
    pair.capture = (chunk) => {
      this.#withheldBytes.push(chunk);
      if (this.#withheldBytes.reduce((total, bytes) => total + bytes.length, 0)
        > 1024 * 1024) {
        client.destroy(new Error("Withheld outbound exceeded byte limit"));
      }
    };
    if (this.#outbound) client.on("data", pair.capture);
    else client.pipe(upstream);
    if (this.#pauseAfterConnectSuccess) {
      pair.inspect = (chunk) => {
        pair.buffer = Buffer.concat([pair.buffer, chunk]);
        if (pair.buffer.length > 1024 * 1024) {
          client.destroy(new Error("Reconnect handshake exceeded byte limit"));
          return;
        }
        if (pair.upgrading) {
          const end = pair.buffer.indexOf("\r\n\r\n");
          if (end < 0) return;
          const header = pair.buffer.subarray(0, end + 4);
          pair.buffer = pair.buffer.subarray(end + 4);
          client.write(header);
          pair.upgrading = false;
          if (!header.toString("ascii").startsWith("HTTP/1.1 101")) {
            this.#release(pair);
            return;
          }
        }
        while (pair.buffer.length >= 2) {
          const marker = pair.buffer[1] & 0x7f;
          const headerSize = marker === 126 ? 4 : marker === 127 ? 10 : 2;
          if (pair.buffer.length < headerSize) return;
          const length = marker === 126
            ? pair.buffer.readUInt16BE(2)
            : marker === 127
              ? Number(pair.buffer.readBigUInt64BE(2))
              : marker;
          if (!Number.isSafeInteger(length) || length > 1024 * 1024) {
            client.destroy(new Error("Reconnect frame exceeded byte limit"));
            return;
          }
          if (pair.buffer.length < headerSize + length) return;
          const frame = pair.buffer.subarray(0, headerSize + length);
          pair.buffer = pair.buffer.subarray(headerSize + length);
          client.write(frame);
          let payload = frame.subarray(headerSize);
          if (frame[0] & 0x40) {
            try {
              payload = inflateRawSync(Buffer.concat([
                payload, Buffer.from([0, 0, 0xff, 0xff]),
              ]), {
                dictionary: pair.dictionary,
                finishFlush: constants.Z_SYNC_FLUSH,
              });
              pair.dictionary = Buffer.concat([pair.dictionary, payload]).subarray(-32768);
            } catch (error) {
              client.destroy(new Error("Cannot inspect compressed reconnect frame", { cause: error }));
              return;
            }
          }
          if (payload.includes('"connect_document_success"')) {
            this.#connectSuccesses++;
            this.#inbound = true;
            upstream.pause();
            return;
          }
        }
      };
      upstream.on("data", pair.inspect);
    } else {
      upstream.pipe(client);
    }
    if (this.#inbound) upstream.pause();
  }

  pauseInbound() {
    this.#inbound = true;
    for (const { upstream } of this.#pairs) upstream.pause();
  }

  #release(pair) {
    if (pair.inspect) {
      pair.upstream.off("data", pair.inspect);
      pair.inspect = undefined;
      if (pair.buffer.length) pair.client.write(pair.buffer);
      pair.buffer = Buffer.alloc(0);
      pair.upstream.pipe(pair.client);
    }
    pair.upstream.resume();
  }

  resumeInbound() {
    this.#inbound = false;
    for (const pair of this.#pairs) this.#release(pair);
  }

  pauseOutbound() {
    this.#outbound = true;
    for (const pair of this.#pairs) {
      pair.client.unpipe(pair.upstream);
      pair.client.on("data", pair.capture);
      pair.client.resume();
    }
  }

  withheldOutboundPayloads({ allowIncomplete = false } = {}) {
    const bytes = Buffer.concat(this.#withheldBytes);
    const payloads = [];
    let dictionary = Buffer.alloc(0);
    for (let at = 0; at < bytes.length;) {
      if (allowIncomplete && at + 2 > bytes.length) return payloads;
      assert(at + 2 <= bytes.length, "Incomplete withheld WebSocket frame");
      const masked = (bytes[at + 1] & 0x80) !== 0;
      const marker = bytes[at + 1] & 0x7f;
      const header = marker === 126 ? 4 : marker === 127 ? 10 : 2;
      if (allowIncomplete && at + header + (masked ? 4 : 0) > bytes.length) {
        return payloads;
      }
      assert(at + header + (masked ? 4 : 0) <= bytes.length,
        "Incomplete withheld frame header");
      const length = marker === 126 ? bytes.readUInt16BE(at + 2)
        : marker === 127 ? Number(bytes.readBigUInt64BE(at + 2)) : marker;
      assert(Number.isSafeInteger(length) && length <= 1024 * 1024,
        "Invalid withheld frame length");
      const start = at + header + (masked ? 4 : 0);
      if (allowIncomplete && start + length > bytes.length) return payloads;
      assert(start + length <= bytes.length, "Incomplete withheld frame payload");
      let payload = Buffer.from(bytes.subarray(start, start + length));
      if (masked) {
        for (let i = 0; i < length; i++) {
          payload[i] ^= bytes[at + header + i % 4];
        }
      }
      if (bytes[at] & 0x40) {
        payload = inflateRawSync(Buffer.concat([
          payload, Buffer.from([0, 0, 0xff, 0xff]),
        ]), { dictionary, finishFlush: constants.Z_SYNC_FLUSH });
        dictionary = Buffer.concat([dictionary, payload]).subarray(-32768);
      }
      if ((bytes[at] & 0x0f) === 1) payloads.push(payload.toString("utf8"));
      at = start + length;
    }
    return payloads;
  }

  async disconnect() {
    this.#withheld = true;
    for (const { client, upstream } of this.#pairs) {
      client.destroy();
      upstream.destroy();
    }
    this.#pairs.clear();
  }

  async reconnect({ pauseInbound = false, pauseAfterConnectSuccess = false } = {}) {
    this.#withheld = false;
    this.#inbound = pauseInbound;
    this.#pauseAfterConnectSuccess = pauseAfterConnectSuccess;
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

export async function startClient(target, descriptor, environment, options = {}) {
  assert(["javascript", "erlang"].includes(target), "Unsupported native target");
  const upstream = new URL(environment.socketUrl);
  assert.equal(upstream.protocol, "http:", "Native gate requires the local HTTP profile");
  const gateFactory = options.gateFactory ?? ((host, port) => TcpGate.open(host, port));
  const gate = await gateFactory(upstream.hostname, Number(upstream.port || 80));
  const instanceId = randomUUID();
  let directory;
  try {
    const output = join(repository, "tools/shared-tree-oracle/.output");
    await mkdir(output, { recursive: true });
    directory = await mkdtemp(join(output, "native-client-"));
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
      cwd: repository, env, stdio: ["pipe", "pipe", "pipe"],
    });
    const channel = new JsonLinesChannel(child);
    return {
      instanceId,
      gate,
      request: (command) => channel.request(command),
      read: (path, tree) => channel.read(path, tree),
      createDataStore: (name) => channel.createDataStore(name),
      trySetAlias: (store, alias) => channel.trySetAlias(store, alias),
      rootMap: (name) => channel.rootMap(name),
      dataStoreRoot: (store, name) => channel.dataStoreRoot(store, name),
      createMap: (name, store) => channel.createMap(name, store),
      openMap: (name, handle) => channel.openMap(name, handle),
      sharedMapGet: (name, key) => channel.sharedMapGet(name, key),
      sharedMapSet: (name, key, value) => channel.sharedMapSet(name, key, value),
      sharedMapDelete: (name, key) => channel.sharedMapDelete(name, key),
      sharedMapEntries: (name) => channel.sharedMapEntries(name),
      createTree: (options) => channel.createTree(options),
      openTree: (name, handle, view) => channel.openTree(name, handle, view),
      mapGet: (path, key, tree) => channel.mapGet(path, key, tree),
      mapSet: (path, key, value, tree) => channel.mapSet(path, key, value, tree),
      mapDelete: (path, key, tree) => channel.mapDelete(path, key, tree),
      mapKeys: (path, tree) => channel.mapKeys(path, tree),
      mapEntries: (path, tree) => channel.mapEntries(path, tree),
      schemaCompatibility: (view, tree) => channel.schemaCompatibility(view, tree),
      schemaUpgrade: (view, tree) => channel.schemaUpgrade(view, tree),
      openView: (view, tree) => channel.openView(view, tree),
      subscribe: (tree) => channel.subscribe(tree),
      unsubscribe: (tree) => channel.unsubscribe(tree),
      checkpoint: (tree) => channel.checkpoint(tree),
      arrayGet: (path, index, tree) => channel.arrayGet(path, index, tree),
      arrayValues: (path, tree) => channel.arrayValues(path, tree),
      arrayInsert: (path, index, values, tree) =>
        channel.arrayInsert(path, index, values, tree),
      arrayRemove: (path, start, end, tree) =>
        channel.arrayRemove(path, start, end, tree),
      arrayMove: (sourcePath, sourceStart, sourceEnd, destinationPath, destinationGap, tree) =>
        channel.arrayMove(
          sourcePath,
          sourceStart,
          sourceEnd,
          destinationPath,
          destinationGap,
          tree,
        ),
      constrainedArrayRemove: (targetPath, path, start, end, tree) =>
        channel.constrainedArrayRemove(targetPath, path, start, end, tree),
      transaction: (scope) => channel.transaction(scope),
      fork: (source, name, tree) => channel.fork(source, name, tree),
      branchEdit: (branch, edit, tree) => channel.branchEdit(branch, edit, tree),
      rebaseBranch: (source, target, tree) =>
        channel.rebaseBranch(source, target, tree),
      mergeBranch: (target, source, dispose, tree) =>
        channel.mergeBranch(target, source, dispose, tree),
      disposeBranch: (name, tree) => channel.disposeBranch(name, tree),
      retainLastLocalCommit: (name, branch, tree) =>
        channel.retainLastLocalCommit(name, branch, tree),
      revertibleStatus: (name, tree) => channel.revertibleStatus(name, tree),
      disposeRevertible: (name, tree) => channel.disposeRevertible(name, tree),
      revert: (name, dispose, tree) => channel.revert(name, dispose, tree),
      async crash() {
        if (child.exitCode === null && child.signalCode === null) {
          const exited = once(child, "exit");
          child.kill("SIGKILL");
          await exited;
        }
      },
      async close() {
        const cleanupErrors = [];
        try {
          if (child.exitCode === null && !child.killed && !channel.failure) {
            await channel.request({ command: "close" });
            channel.end();
            if (child.exitCode === null) {
              let timer;
              try {
                await Promise.race([
                  once(child, "exit"),
                  new Promise((_resolve, reject) => {
                    timer = setTimeout(
                      () => reject(new Error("Native client did not exit")), 5000);
                  }),
                ]);
              } finally {
                clearTimeout(timer);
              }
            }
          }
        } catch (error) {
          cleanupErrors.push(error);
        } finally {
          if (child.exitCode === null && child.signalCode === null) {
            child.kill();
            try {
              await once(child, "close");
            } catch (error) {
              cleanupErrors.push(error);
            }
          }
          try {
            await gate.close();
          } catch (error) {
            cleanupErrors.push(error);
          }
          try {
            await rm(directory, { recursive: true, force: true });
          } catch (error) {
            cleanupErrors.push(error);
          }
        }
        if (cleanupErrors.length === 1) throw cleanupErrors[0];
        if (cleanupErrors.length > 1) {
          throw new AggregateError(cleanupErrors, "Native client cleanup failed");
        }
      },
    };
  } catch (error) {
    const cleanupErrors = [];
    try {
      await gate.close();
    } catch (cleanupError) {
      cleanupErrors.push(cleanupError);
    }
    if (directory) {
      try {
        await rm(directory, { recursive: true, force: true });
      } catch (cleanupError) {
        cleanupErrors.push(cleanupError);
      }
    }
    if (cleanupErrors.length > 0) error.cleanupErrors = cleanupErrors;
    throw error;
  }
}
