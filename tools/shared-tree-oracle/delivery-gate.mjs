import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { once } from "node:events";
import { createServer, request as httpRequest } from "node:http";
import { createRequire } from "node:module";

const require = createRequire(new URL("../../package.json", import.meta.url));
const WebSocket = require("ws");
const WebSocketServer = WebSocket.WebSocketServer ?? WebSocket.Server;

const directions = new Set(["inbound", "outbound"]);
const kinds = new Set(["op", "summarize", "summary-load"]);
const maxMessageBytes = 1024 * 1024;
const maxHeldBytes = 8 * 1024 * 1024;
const maxHeldItems = 128;
const maxHoldMilliseconds = 30_000;

function digest(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function sanitizedPath(raw) {
  const url = new URL(raw, "http://gate");
  const selected = new URLSearchParams();
  for (const name of ["from", "to", "start", "end"]) {
    for (const value of url.searchParams.getAll(name)) selected.append(name, value);
  }
  const query = selected.toString();
  return `${url.pathname}${query ? `?${query}` : ""}`;
}

function summaryLoad(raw) {
  const path = new URL(raw, "http://gate").pathname;
  return path.includes("/repos/") || /\/git\/(?:commits|trees|blobs)(?:\/|$)/.test(path);
}

function inspectPayload(bytes) {
  let value;
  try {
    value = JSON.parse(bytes.toString("utf8"));
  } catch {
    return undefined;
  }
  if (!Array.isArray(value) || value.length < 5) return undefined;
  const topic = typeof value[2] === "string" ? value[2] : undefined;
  const event = typeof value[3] === "string" ? value[3] : undefined;
  if (event !== "op" && event !== "submitOp") return undefined;
  const sequenceNumbers = [];
  let summarize = false;
  const pending = [value[4]];
  const seenStrings = new Set();
  while (pending.length > 0) {
    const current = pending.pop();
    if (Array.isArray(current)) {
      pending.push(...current.toReversed());
    } else if (current && typeof current === "object") {
      if (Number.isSafeInteger(current.sequenceNumber)) {
        sequenceNumbers.push(current.sequenceNumber);
      }
      if (["summarize", "summaryAck", "summaryNack"].includes(current.type)) {
        summarize = true;
      }
      pending.push(...Object.values(current).toReversed());
    } else if (typeof current === "string" && current.length <= maxMessageBytes
      && !seenStrings.has(current) && /^[\[{]/.test(current.trim())) {
      seenStrings.add(current);
      try {
        pending.push(JSON.parse(current));
      } catch {
        // A string in an operation can look like JSON without being encoded data.
      }
    }
  }
  return {
    kind: summarize ? "summarize" : "op",
    topic,
    event,
    sequenceNumbers,
  };
}

function submittedPayloads(value) {
  const submissions = [];
  const pending = [value];
  const seen = new Set();
  while (pending.length > 0) {
    const current = pending.pop();
    if (typeof current === "string" && /^[\[{]/.test(current.trim())) {
      try {
        pending.push(JSON.parse(current));
      } catch {
        // Operation data can resemble JSON without containing an encoded payload.
      }
      continue;
    }
    if (!current || typeof current !== "object" || seen.has(current)) continue;
    seen.add(current);
    if (typeof current.clientId === "string"
      && Array.isArray(current.messageBatches)) {
      submissions.push(sanitizedPayload(current));
      continue;
    }
    pending.push(...Object.values(current));
  }
  return submissions;
}

function inspectHandshake(bytes) {
  let value;
  try {
    value = JSON.parse(bytes.toString("utf8"));
  } catch {
    return undefined;
  }
  if (!Array.isArray(value) || value[3] !== "connect_document_success") return undefined;
  const payload = value[4];
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) return undefined;
  const checkpointSequenceNumber = Number.isSafeInteger(payload.checkpointSequenceNumber)
    ? payload.checkpointSequenceNumber : undefined;
  const summarySequenceNumber = Number.isSafeInteger(payload.summaryContext?.sequenceNumber)
    ? payload.summaryContext.sequenceNumber : undefined;
  const initialMessageSequenceNumbers = Array.isArray(payload.initialMessages)
    ? payload.initialMessages
      .map(({ sequenceNumber } = {}) => sequenceNumber)
      .filter(Number.isSafeInteger)
    : [];
  if (checkpointSequenceNumber === undefined
    && summarySequenceNumber === undefined
    && initialMessageSequenceNumbers.length === 0) return undefined;
  return {
    checkpointSequenceNumber,
    summarySequenceNumber,
    initialMessageSequenceNumbers,
  };
}

function inspectRepairRequest(bytes) {
  let value;
  try {
    value = JSON.parse(bytes.toString("utf8"));
  } catch {
    return undefined;
  }
  if (!Array.isArray(value) || value[3] !== "requestOps") return undefined;
  const payload = value[4];
  if (!payload || typeof payload !== "object" || Array.isArray(payload)
    || !Number.isSafeInteger(payload.from) || payload.from < 0) return undefined;
  return {
    from: payload.from,
    topic: typeof value[2] === "string" ? value[2] : undefined,
    hash: digest(bytes),
  };
}

function forwardedHeaders(headers) {
  const omitted = new Set([
    "connection", "host", "sec-websocket-accept", "sec-websocket-extensions",
    "sec-websocket-key", "sec-websocket-protocol", "sec-websocket-version", "upgrade",
  ]);
  return Object.fromEntries(
    Object.entries(headers).filter(([name]) => !omitted.has(name.toLowerCase())),
  );
}

function sanitizedPayload(value) {
  if (Array.isArray(value)) return value.map(sanitizedPayload);
  if (!value || typeof value !== "object") {
    if (typeof value !== "string") return value;
    return value.replace(
      /([?&](?:access_)?token=)[^&\s]+/gi,
      "$1[redacted]",
    );
  }
  return Object.fromEntries(Object.entries(value).map(([name, item]) => [
    name,
    /authorization|cookie|password|secret|token/i.test(name)
      ? "[redacted]"
      : sanitizedPayload(item),
  ]));
}

function payloadEvidence(bytes) {
  try {
    return sanitizedPayload(JSON.parse(bytes.toString("utf8")));
  } catch {
    return { byteLength: bytes.length, hash: digest(bytes) };
  }
}

export function snapshotSequenceNumber(bytes) {
  try {
    const value = JSON.parse(bytes.toString("utf8"));
    const attributes = value && !Array.isArray(value)
      && typeof value.content === "string"
      && ["base64", "utf-8"].includes(value.encoding)
      ? JSON.parse(value.encoding === "base64"
        ? Buffer.from(value.content, "base64").toString("utf8")
        : value.content)
      : value;
    return attributes && !Array.isArray(attributes)
      && Number.isSafeInteger(attributes.sequenceNumber)
      && Number.isSafeInteger(attributes.minimumSequenceNumber)
      && attributes.minimumSequenceNumber >= 0
      && attributes.minimumSequenceNumber <= attributes.sequenceNumber
      ? attributes.sequenceNumber
      : undefined;
  } catch {
    return undefined;
  }
}

export function storageResponseIdentity(path, bytes) {
  const match = path.match(/\/git\/(commits|trees|blobs)\/([^/?]+)/);
  if (!match) return undefined;
  let value;
  try {
    value = JSON.parse(bytes.toString("utf8"));
  } catch {
    return undefined;
  }
  const requestedId = decodeURIComponent(match[2]);
  if (match[1] === "commits") {
    const treeId = value?.tree?.sha ?? value?.tree?.id;
    return typeof treeId === "string"
      ? { kind: "commit", requestedId, treeId }
      : undefined;
  }
  if (match[1] === "trees") {
    const entries = Array.isArray(value?.tree)
      ? value.tree.flatMap(({ path: entryPath, type, sha, id }) => {
        const entryId = sha ?? id;
        return typeof entryPath === "string"
          && ["tree", "blob"].includes(type)
          && typeof entryId === "string"
          ? [{ path: entryPath, type, id: entryId }]
          : [];
      })
      : [];
    return entries.length > 0
      ? { kind: "tree", requestedId, entries }
      : undefined;
  }
  const sequenceNumber = snapshotSequenceNumber(bytes);
  return sequenceNumber === undefined
    ? undefined
    : { kind: "blob", requestedId, snapshotSequenceNumber: sequenceNumber };
}

function documentTopic(topic, documentId) {
  return topic === `document:${documentId}`
    || (topic?.startsWith("document:") && topic.endsWith(`:${documentId}`));
}

export class DeliveryGate {
  #server;
  #webSockets;
  #host;
  #upstreamPort;
  #documentId;
  #injection;
  #closed = false;
  #disconnected = false;
  #sockets = new Set();
  #bridges = new Set();
  #holds = {
    inbound: new Set(),
    outbound: new Set(),
  };
  #queues = {
    inbound: [],
    outbound: [],
  };
  #heldBytes = {
    inbound: 0,
    outbound: 0,
  };
  #nextMessageId = 1;
  #nextConnectionId = 1;
  #nextHttpId = 1;
  #dropped = {
    inbound: false,
    outbound: false,
  };
  #evidence = {
    http: [],
    held: [],
    delivered: [],
    handshakes: [],
    repairRequests: [],
    connections: [],
    outboundOccurrences: [],
    outboundTreeMessages: [],
    injections: [],
    errors: [],
  };

  constructor(server, webSockets, host, port, documentId) {
    this.#server = server;
    this.#webSockets = webSockets;
    this.#host = host;
    this.#upstreamPort = port;
    this.#documentId = documentId;
  }

  static async open(host, port, { documentId } = {}) {
    assert(typeof host === "string" && host.length > 0, "Invalid upstream host");
    assert(Number.isInteger(port) && port > 0 && port <= 65_535, "Invalid upstream port");
    const webSockets = new WebSocketServer({
      noServer: true,
      perMessageDeflate: true,
      maxPayload: maxMessageBytes,
    });
    let gate;
    const server = createServer((request, response) => gate.#http(request, response));
    assert(documentId === undefined
      || (typeof documentId === "string" && documentId.length > 0),
    "Invalid delivery gate document ID");
    gate = new DeliveryGate(server, webSockets, host, port, documentId);
    server.on("connection", (socket) => {
      gate.#sockets.add(socket);
      socket.on("close", () => gate.#sockets.delete(socket));
      if (gate.#disconnected) socket.destroy();
    });
    server.on("upgrade", (request, socket, head) => gate.#upgrade(request, socket, head));
    server.listen(0, "127.0.0.1");
    await once(server, "listening");
    return gate;
  }

  get port() {
    return this.#server.address().port;
  }

  hold(direction, kind) {
    this.#validateDirection(direction);
    assert(kinds.has(kind), `Unknown delivery kind: ${kind}`);
    if (this.#closed) throw new Error("Delivery gate is closed");
    this.#holds[direction].add(kind);
  }

  inject({
    documentId,
    mutation,
    expectedStage,
    direction,
    kind,
    transform,
  }) {
    assert(!this.#injection, "Delivery gate already has an armed injection");
    assert(typeof documentId === "string" && documentId.length > 0,
      "Injection requires a document ID");
    assert(this.#documentId === documentId,
      "Injection document does not match the gate document");
    assert(typeof mutation === "string" && mutation.length > 0,
      "Injection requires a mutation name");
    assert(typeof expectedStage === "string" && expectedStage.length > 0,
      "Injection requires an expected failure stage");
    this.#validateDirection(direction);
    assert(kinds.has(kind), `Unknown delivery kind: ${kind}`);
    assert(typeof transform === "function", "Injection requires a transform");
    if (this.#closed) throw new Error("Delivery gate is closed");
    this.#injection = {
      documentId,
      mutation,
      expectedStage,
      direction,
      kind,
      transform,
    };
  }

  async release(direction, {
    order = "fifo",
    duplicate = false,
    beforeDuplicate,
  } = {}) {
    this.#validateDirection(direction);
    assert(["fifo", "reverse"].includes(order), `Unknown release order: ${order}`);
    assert(beforeDuplicate === undefined || typeof beforeDuplicate === "function",
      "beforeDuplicate must be a function");
    assert(beforeDuplicate === undefined || duplicate,
      "beforeDuplicate requires duplicate delivery");
    if (this.#closed) throw new Error("Delivery gate is closed");
    if (this.#dropped[direction]) {
      this.#dropped[direction] = false;
      throw new Error(`Held ${direction} deliveries were dropped while disconnected`);
    }
    this.#holds[direction].clear();
    const queued = this.#queues[direction];
    this.#queues[direction] = [];
    this.#heldBytes[direction] = 0;
    for (const item of queued) clearTimeout(item.timer);
    if (order === "reverse") queued.reverse();
    for (const item of queued) await this.#deliver(item, false);
    const lastApplication = queued.findLast(({ kind }) =>
      kind === "op" || kind === "summarize");
    if (duplicate && lastApplication) {
      if (beforeDuplicate) await beforeDuplicate();
      await this.#deliver(lastApplication, true);
    }
  }

  evidence() {
    return structuredClone(this.#evidence);
  }

  async disconnect() {
    if (this.#closed) return;
    this.#disconnected = true;
    for (const direction of directions) {
      if (this.#queues[direction].length > 0) this.#dropped[direction] = true;
      for (const item of this.#queues[direction]) clearTimeout(item.timer);
      this.#queues[direction] = [];
      this.#heldBytes[direction] = 0;
      this.#holds[direction].clear();
    }
    for (const bridge of this.#bridges) {
      bridge.client.terminate();
      bridge.upstream.terminate();
    }
    for (const socket of this.#sockets) socket.destroy();
    await new Promise((resolve) => setImmediate(resolve));
  }

  async reconnect() {
    if (this.#closed) throw new Error("Delivery gate is closed");
    this.#disconnected = false;
  }

  async close() {
    if (this.#closed) return;
    this.#closed = true;
    this.#disconnected = true;
    for (const direction of directions) {
      for (const item of this.#queues[direction]) clearTimeout(item.timer);
      this.#queues[direction] = [];
      this.#heldBytes[direction] = 0;
    }
    for (const bridge of this.#bridges) {
      bridge.client.terminate();
      bridge.upstream.terminate();
    }
    for (const socket of this.#sockets) socket.destroy();
    await new Promise((resolve, reject) => {
      this.#server.close((error) => error ? reject(error) : resolve());
    });
    this.#webSockets.close();
  }

  #validateDirection(direction) {
    assert(directions.has(direction), `Unknown delivery direction: ${direction}`);
  }

  #queue(item) {
    const { direction, bytes } = item;
    if (this.#queues[direction].length >= maxHeldItems
      || this.#heldBytes[direction] + bytes.length > maxHeldBytes) {
      const error = `Held ${direction} delivery exceeded the bounded queue`;
      this.#evidence.errors.push({ kind: "overflow", direction, message: error });
      throw new Error(error);
    }
    this.#queues[direction].push(item);
    this.#heldBytes[direction] += bytes.length;
    this.#evidence.held.push(item.identity);
    item.timer = setTimeout(() => {
      const index = this.#queues[direction].indexOf(item);
      if (index < 0) return;
      this.#queues[direction].splice(index, 1);
      this.#heldBytes[direction] -= bytes.length;
      const error = new Error(`Held ${direction} delivery exceeded its deadline`);
      this.#evidence.errors.push({
        kind: "deadline",
        direction,
        message: error.message,
      });
      item.drop?.(error);
    }, maxHoldMilliseconds);
    item.timer.unref();
  }

  async #deliver(item, duplicate) {
    await item.send();
    const identity = { ...item.identity, duplicate };
    this.#evidence.delivered.push(identity);
    if (item.direction === "outbound" && item.kind === "op") {
      this.#evidence.outboundTreeMessages.push(identity);
    }
  }

  #message(direction, bytes, binary, send, drop, connectionId) {
    let deliveryBytes = bytes;
    if (direction === "inbound") {
      const handshake = inspectHandshake(deliveryBytes);
      if (handshake) this.#evidence.handshakes.push(handshake);
    } else {
      const repair = inspectRepairRequest(deliveryBytes);
      if (repair) this.#evidence.repairRequests.push(repair);
    }
    let inspected = inspectPayload(deliveryBytes);
    if (!inspected) {
      void send(deliveryBytes).catch((error) => {
        this.#evidence.errors.push({
          kind: "delivery-error", direction, message: error.message,
        });
      });
      return;
    }
    const injection = this.#injection;
    if (injection
      && injection.direction === direction
      && injection.kind === inspected.kind
      && documentTopic(inspected.topic, injection.documentId)) {
      const originalPayload = JSON.parse(deliveryBytes.toString("utf8"));
      const mutatedPayload = injection.transform(structuredClone(originalPayload));
      assert(mutatedPayload !== undefined, "Injection transform returned no payload");
      deliveryBytes = Buffer.from(JSON.stringify(mutatedPayload));
      inspected = inspectPayload(deliveryBytes);
      assert(inspected?.kind === injection.kind,
        "Injection changed the delivery classification");
      this.#evidence.injections.push({
        documentId: injection.documentId,
        mutation: injection.mutation,
        expectedStage: injection.expectedStage,
        direction,
        kind: injection.kind,
        originalHash: digest(bytes),
        mutatedHash: digest(deliveryBytes),
        originalPayload: sanitizedPayload(originalPayload),
        mutatedPayload: sanitizedPayload(mutatedPayload),
      });
      this.#injection = undefined;
    }
    const id = this.#nextMessageId++;
    const identity = {
      id,
      connectionId,
      direction,
      kind: inspected.kind,
      hash: digest(deliveryBytes),
      byteLength: deliveryBytes.length,
      topic: inspected.topic,
      event: inspected.event,
      sequenceNumbers: inspected.sequenceNumbers,
    };
    if (direction === "outbound" && inspected.kind === "op") {
      identity.submissions = submittedPayloads(
        JSON.parse(deliveryBytes.toString("utf8")),
      );
      this.#evidence.outboundOccurrences.push(structuredClone(identity));
    }
    const item = {
      direction,
      kind: inspected.kind,
      bytes: deliveryBytes,
      binary,
      identity,
      send: () => send(deliveryBytes),
      drop,
    };
    if (this.#holds[direction].has(inspected.kind)) {
      try {
        this.#queue(item);
      } catch (error) {
        this.#evidence.errors.push({
          kind: "delivery-error", direction, message: error.message,
        });
      }
    } else {
      void this.#deliver(item, false).catch((error) => {
        this.#evidence.errors.push({
          kind: "delivery-error", direction, message: error.message,
        });
      });
    }
  }

  #upgrade(request, socket, head) {
    if (this.#closed || this.#disconnected) {
      socket.destroy();
      return;
    }
    this.#webSockets.handleUpgrade(request, socket, head, (client) => {
      const connectionId = `connection-${this.#nextConnectionId++}`;
      const epoch = this.#nextConnectionId - 1;
      const protocols = request.headers["sec-websocket-protocol"]
        ?.split(",").map((value) => value.trim()).filter(Boolean);
      const upstream = new WebSocket(
        `ws://${this.#host}:${this.#upstreamPort}${request.url}`,
        protocols?.length ? protocols : undefined,
        {
          headers: forwardedHeaders(request.headers),
          perMessageDeflate: true,
          maxPayload: maxMessageBytes,
        },
      );
      const bridge = { client, upstream, connectionId };
      this.#bridges.add(bridge);
      this.#evidence.connections.push({
        connectionId,
        epoch,
        state: "opened",
      });
      const pending = [];
      let pendingBytes = 0;
      const finish = (source, target, direction) => {
        source.on("error", (error) => {
          this.#evidence.errors.push({
            kind: "websocket-error",
            direction,
            message: error.message,
          });
          target.terminate();
        });
        source.on("close", () => target.terminate());
      };
      finish(client, upstream, "outbound");
      finish(upstream, client, "inbound");
      client.on("close", () => this.#bridges.delete(bridge));
      client.on("message", (payload, binary) => {
        const bytes = Buffer.from(payload);
        const send = (deliveryBytes = bytes) => new Promise((resolve, reject) => {
          const forward = () => upstream.send(deliveryBytes, { binary }, (error) =>
            error ? reject(error) : resolve());
          if (upstream.readyState === WebSocket.OPEN) {
            forward();
          } else if (upstream.readyState === WebSocket.CONNECTING) {
            if (pending.length >= maxHeldItems || pendingBytes + bytes.length > maxHeldBytes) {
              reject(new Error("WebSocket startup queue exceeded the bounded limit"));
              return;
            }
            pending.push(forward);
            pendingBytes += bytes.length;
          } else {
            reject(new Error("Upstream WebSocket is not open"));
          }
        });
        this.#message("outbound", bytes, binary, send, () => {
          client.terminate();
          upstream.terminate();
        }, connectionId);
      });
      upstream.on("open", () => {
        for (const forward of pending.splice(0)) forward();
        pendingBytes = 0;
      });
      upstream.on("message", (payload, binary) => {
        const bytes = Buffer.from(payload);
        const send = (deliveryBytes = bytes) => new Promise((resolve, reject) => {
          if (client.readyState !== WebSocket.OPEN) {
            reject(new Error("Client WebSocket is not open"));
            return;
          }
          client.send(deliveryBytes, { binary },
            (error) => error ? reject(error) : resolve());
        });
        this.#message("inbound", bytes, binary, send, () => {
          client.terminate();
          upstream.terminate();
        }, connectionId);
      });
    });
  }

  #http(clientRequest, clientResponse) {
    if (this.#closed || this.#disconnected) {
      clientResponse.writeHead(503).end();
      return;
    }
    const id = this.#nextHttpId++;
    const method = clientRequest.method ?? "GET";
    const path = sanitizedPath(clientRequest.url ?? "/");
    const captureStorage = method === "GET"
      && /\/git\/(?:commits|trees|blobs)\/[^/?]+/.test(path);
    const requestHash = createHash("sha256");
    const requestChunks = [];
    let requestBytes = 0;
    let finishRequest;
    const requestDone = new Promise((resolve) => { finishRequest = resolve; });
    const holdRequest = summaryLoad(clientRequest.url ?? "/")
      && this.#holds.outbound.has("summary-load");
    const start = () => {
      const upstreamRequest = httpRequest({
        host: this.#host,
        port: this.#upstreamPort,
        method,
        path: clientRequest.url,
        headers: { ...clientRequest.headers, host: `${this.#host}:${this.#upstreamPort}` },
      }, (upstreamResponse) => {
        const responseHash = createHash("sha256");
        const responseChunks = [];
        const identityChunks = [];
        let responseBytes = 0;
        let identityOverflow = false;
        const holdResponse = summaryLoad(clientRequest.url ?? "/")
          && this.#holds.inbound.has("summary-load");
        const injectResponse = summaryLoad(clientRequest.url ?? "/")
          && this.#injection?.direction === "inbound"
          && this.#injection.kind === "summary-load";
        const bufferResponse = holdResponse || injectResponse;
        if (!bufferResponse) {
          clientResponse.writeHead(
            upstreamResponse.statusCode,
            upstreamResponse.statusMessage,
            upstreamResponse.headers,
          );
        }
        upstreamResponse.on("data", (chunk) => {
          responseHash.update(chunk);
          responseBytes += chunk.length;
          if (captureStorage && responseBytes > maxHeldBytes) {
            upstreamResponse.destroy(new Error("Storage response exceeded the bounded evidence limit"));
            return;
          }
          if (!identityOverflow) {
            if (responseBytes <= (captureStorage ? maxHeldBytes : maxMessageBytes)) {
              identityChunks.push(chunk);
            } else {
              identityChunks.length = 0;
              identityOverflow = true;
            }
          }
          if (bufferResponse) {
            if (responseBytes > maxHeldBytes) {
              upstreamResponse.destroy(new Error("Held HTTP response exceeded the bounded limit"));
              return;
            }
            responseChunks.push(chunk);
          } else {
            clientResponse.write(chunk);
          }
        });
        upstreamResponse.on("end", async () => {
          await requestDone;
          const observation = {
            id,
            method,
            path,
            status: upstreamResponse.statusCode,
            requestHash: requestHash.digest("hex"),
            responseHash: responseHash.digest("hex"),
          };
          if (!bufferResponse) {
            const responseBytes = identityOverflow
              ? undefined
              : Buffer.concat(identityChunks);
            const sequenceNumber = identityOverflow
              ? undefined
              : snapshotSequenceNumber(responseBytes);
            if (sequenceNumber !== undefined) {
              observation.responseSnapshotSequenceNumber = sequenceNumber;
            }
            const storageResponse = responseBytes === undefined
              ? undefined
              : storageResponseIdentity(path, responseBytes);
            if (storageResponse !== undefined) {
              observation.storageResponse = storageResponse;
            }
            if (captureStorage || storageResponse !== undefined) {
              observation.responseBody = responseBytes.toString("base64");
            }
            this.#evidence.http.push(observation);
            clientResponse.end();
            return;
          }
          let bytes = Buffer.concat(responseChunks);
          let status = upstreamResponse.statusCode;
          let headers = upstreamResponse.headers;
          if (injectResponse) {
            const injection = this.#injection;
            const originalBytes = bytes;
            const mutated = injection.transform({
              path,
              status,
              bytes: Buffer.from(bytes),
            });
            if (mutated !== undefined) {
              assert(Buffer.isBuffer(mutated.bytes),
                "Summary-load injection must return response bytes");
              bytes = mutated.bytes;
              status = mutated.status ?? status;
              headers = {
                ...(mutated.headers ?? headers),
                "content-length": String(bytes.length),
              };
              delete headers["transfer-encoding"];
              this.#evidence.injections.push({
                documentId: injection.documentId,
                mutation: injection.mutation,
                expectedStage: injection.expectedStage,
                direction: "inbound",
                kind: "summary-load",
                path,
                originalHash: digest(originalBytes),
                mutatedHash: digest(bytes),
                originalPayload: payloadEvidence(originalBytes),
                mutatedPayload: payloadEvidence(bytes),
              });
              this.#injection = undefined;
            }
          }
          const sequenceNumber = snapshotSequenceNumber(bytes);
          observation.status = status;
          observation.responseHash = digest(bytes);
          if (sequenceNumber !== undefined) {
            observation.responseSnapshotSequenceNumber = sequenceNumber;
          }
          const storageResponse = storageResponseIdentity(path, bytes);
          if (storageResponse !== undefined) {
            observation.storageResponse = storageResponse;
          }
          if (captureStorage || storageResponse !== undefined) {
            observation.responseBody = bytes.toString("base64");
          }
          this.#evidence.http.push(observation);
          if (!holdResponse) {
            clientResponse.writeHead(status, upstreamResponse.statusMessage, headers);
            clientResponse.end(bytes);
            return;
          }
          const identity = {
            id: `http:${id}`,
            direction: "inbound",
            kind: "summary-load",
            hash: digest(bytes),
            byteLength: bytes.length,
            method,
            path,
            status,
          };
          const item = {
            direction: "inbound",
            kind: "summary-load",
            bytes,
            identity,
            send: async () => {
              clientResponse.writeHead(
                status,
                upstreamResponse.statusMessage,
                headers,
              );
              clientResponse.end(bytes);
            },
            drop: (error) => clientResponse.destroy(error),
          };
          try {
            this.#queue(item);
          } catch (error) {
            clientResponse.destroy(error);
          }
        });
        upstreamResponse.on("error", (error) => clientResponse.destroy(error));
      });
      upstreamRequest.on("error", (error) => clientResponse.destroy(error));
      if (holdRequest) {
        for (const chunk of requestChunks) upstreamRequest.write(chunk);
        upstreamRequest.end();
      } else {
        clientRequest.pipe(upstreamRequest);
      }
    };
    clientRequest.on("data", (chunk) => {
      requestHash.update(chunk);
      requestBytes += chunk.length;
      if (holdRequest) {
        if (requestBytes > maxHeldBytes) {
          clientRequest.destroy(new Error("Held HTTP request exceeded the bounded limit"));
          return;
        }
        requestChunks.push(chunk);
      }
    });
    clientRequest.on("end", () => {
      finishRequest();
      if (!holdRequest) return;
      const bytes = Buffer.concat(requestChunks);
      const identity = {
        id: `http:${id}`,
        direction: "outbound",
        kind: "summary-load",
        hash: digest(bytes),
        byteLength: bytes.length,
        method,
        path,
      };
      try {
        this.#queue({
          direction: "outbound",
          kind: "summary-load",
          bytes,
          identity,
          send: async () => start(),
          drop: (error) => clientResponse.destroy(error),
        });
      } catch (error) {
        clientResponse.destroy(error);
      }
    });
    clientRequest.on("error", (error) => {
      finishRequest();
      clientResponse.destroy(error);
    });
    clientRequest.on("close", finishRequest);
    if (!holdRequest) start();
  }
}
