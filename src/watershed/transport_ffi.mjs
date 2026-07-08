// JS transport for the watershed SharedMap client, built on the official
// Phoenix JS client. The Gleam `runtime_js` module drives the pure core
// (`runtime_core`/`wire`/`map_kernel`) over this shim — no OTP, no aquamarine.
//
// `phoenix` is an *optional peer dependency*: only the real (browser) transport
// needs it. The in-memory `sluice` test driver injects its own transport and
// never calls `connect`, so watershed's own test suite must be able to load
// this module without `phoenix` installed. A guarded top-level-await dynamic
// import gives us that: it resolves `Socket` at module-load in an app bundle
// (esbuild inlines the dynamic import, so it settles before `connect` is ever
// called, keeping `connect` synchronous), and degrades to `undefined` in a
// server-free test run where `phoenix` is absent.
let Socket;
try {
  ({ Socket } = await import("phoenix"));
} catch {
  // phoenix not installed — fine unless the real transport's connect() is used.
}

// Levee document-channel events the runtime cares about. Everything else
// (summary acks, pongs) is ignored, matching the erlang runtime. `signal`
// carries ephemeral, non-sequenced presence-style messages.
const CHANNEL_EVENTS = [
  "connect_document_success",
  "connect_document_error",
  "op",
  "nack",
  "signal",
];

// Open a socket, join the document topic, and wire the runtime callbacks.
//
// `onJoin` fires on every successful (re)join — Phoenix auto-rejoins after a
// socket reconnect, so this doubles as the re-handshake hook. `onEvent` gets
// (eventName, parsedPayload); the payload is a plain JS object, which Gleam's
// dynamic decoders consume directly. Returns the Channel (its `.socket` back
// reference is used by push/close).
export function connect(url, topic, joinPayloadJson, onEvent, onJoin, onClose) {
  if (Socket === undefined) {
    throw new Error(
      "watershed: the real transport requires the 'phoenix' package. " +
        "Install it, or use the in-memory sluice test driver instead.",
    );
  }
  const socket = new Socket(url, {});
  socket.connect();

  const channel = socket.channel(topic, JSON.parse(joinPayloadJson));

  for (const event of CHANNEL_EVENTS) {
    channel.on(event, (payload) => onEvent(event, payload));
  }

  channel.onClose(() => onClose());
  channel.onError(() => onClose());

  // recHooks persist across Phoenix's automatic rejoins, so this fires on the
  // initial handshake and on every reconnect.
  channel.join().receive("ok", () => onJoin());

  return channel;
}

// Push a channel event. `payloadJson` is a JSON string produced by the wire
// encoders; Phoenix wants a plain object.
export function push(channel, event, payloadJson) {
  channel.push(event, JSON.parse(payloadJson));
  return undefined;
}

// Force the socket down to exercise the reconnect path. Phoenix reconnects and
// rejoins automatically, driving `onJoin` again.
export function dropSocket(channel) {
  // Disconnect with a normal-closure code; the default reconnect timer rejoins.
  channel.socket.disconnect(() => {}, 1000, "watershed force reconnect");
  channel.socket.connect();
  return undefined;
}

export function close(channel) {
  channel.socket.disconnect();
  return undefined;
}

// ── Mutable state cell (the runtime keeps its state machine here) ────────────
export function newCell(value) {
  return { value };
}
export function getCell(cell) {
  return cell.value;
}
export function setCell(cell, value) {
  cell.value = value;
  return undefined;
}

export function nowMs() {
  return Date.now();
}

// Cancellable timers for the presence heartbeat/prune loop (returns a handle).
export function setTimer(action, ms) {
  return setTimeout(action, ms);
}

export function clearTimer(id) {
  clearTimeout(id);
  return undefined;
}

// Mint an HS256 dev JWT matching levee's JOSE verification, so the Lustre
// example works against `just server` with no backend token endpoint. Web
// Crypto's subtle.sign is async, so this returns a Promise<string>.
export async function mintDevToken(secret, tenant, document, userId) {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "HS256", typ: "JWT" };
  const payload = {
    documentId: document,
    tenantId: tenant,
    scopes: ["doc:read", "doc:write", "summary:write"],
    user: { id: userId },
    iat: now,
    exp: now + 3600,
    ver: "1.0",
  };
  const signingInput =
    b64url(utf8(JSON.stringify(header))) +
    "." +
    b64url(utf8(JSON.stringify(payload)));
  const key = await crypto.subtle.importKey(
    "raw",
    utf8(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, utf8(signingInput));
  return signingInput + "." + b64url(new Uint8Array(sig));
}

function utf8(str) {
  return new TextEncoder().encode(str);
}

function b64url(bytes) {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
