// JS transport for the watershed SharedMap client, built on the official
// Phoenix JS client. The Gleam `runtime_js` module drives the pure core
// (`runtime_core`/`wire`/`map_kernel`) over this shim — no OTP, no aquamarine.
//
// The `phoenix` package is resolved by the consuming app's bundler; watershed's
// own `gleam build --target javascript` only emits this file, it does not bundle
// it, so the bare import below is never executed at library-build time.
import { Socket } from "phoenix";

// Levee document-channel events the runtime cares about. Everything else
// (signals, summary acks, pongs) is ignored, matching the erlang runtime.
const CHANNEL_EVENTS = [
  "connect_document_success",
  "connect_document_error",
  "op",
  "nack",
];

// Open a socket, join the document topic, and wire the runtime callbacks.
//
// `onJoin` fires on every successful (re)join — Phoenix auto-rejoins after a
// socket reconnect, so this doubles as the re-handshake hook. `onEvent` gets
// (eventName, parsedPayload); the payload is a plain JS object, which Gleam's
// dynamic decoders consume directly. Returns the Channel (its `.socket` back
// reference is used by push/close).
export function connect(url, topic, joinPayloadJson, onEvent, onJoin, onClose) {
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

// ── Demo helpers ─────────────────────────────────────────────────────────────
export function randomInt(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

// Mint an HS256 dev JWT matching levee's JOSE verification, so the Lustre
// example works against `just server` with no backend token endpoint. Pure-JS
// HMAC-SHA256 keeps this synchronous (Web Crypto's subtle.sign is async).
export function mintDevToken(secret, tenant, document, userId) {
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
  const sig = hmacSha256(utf8(secret), utf8(signingInput));
  return signingInput + "." + b64url(sig);
}

function utf8(str) {
  return new TextEncoder().encode(str);
}

function b64url(bytes) {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

// ── Minimal, self-contained SHA-256 / HMAC (dev-token minting only) ──────────
function hmacSha256(keyBytes, msgBytes) {
  const blockSize = 64;
  let key = keyBytes;
  if (key.length > blockSize) key = sha256(key);
  const padded = new Uint8Array(blockSize);
  padded.set(key);
  const oKey = new Uint8Array(blockSize);
  const iKey = new Uint8Array(blockSize);
  for (let i = 0; i < blockSize; i++) {
    oKey[i] = padded[i] ^ 0x5c;
    iKey[i] = padded[i] ^ 0x36;
  }
  const inner = sha256(concat(iKey, msgBytes));
  return sha256(concat(oKey, inner));
}

function concat(a, b) {
  const out = new Uint8Array(a.length + b.length);
  out.set(a);
  out.set(b, a.length);
  return out;
}

function sha256(bytes) {
  const K = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
    0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
    0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
    0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
    0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
    0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];
  let h = [
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c,
    0x1f83d9ab, 0x5be0cd19,
  ];
  const l = bytes.length;
  const withOne = new Uint8Array(((l + 8) >> 6) * 64 + 64);
  withOne.set(bytes);
  withOne[l] = 0x80;
  const bitLen = l * 8;
  const dv = new DataView(withOne.buffer);
  dv.setUint32(withOne.length - 4, bitLen >>> 0);
  dv.setUint32(withOne.length - 8, Math.floor(bitLen / 0x100000000));

  const w = new Uint32Array(64);
  for (let off = 0; off < withOne.length; off += 64) {
    for (let i = 0; i < 16; i++) w[i] = dv.getUint32(off + i * 4);
    for (let i = 16; i < 64; i++) {
      const s0 =
        rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >>> 3);
      const s1 =
        rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >>> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) >>> 0;
    }
    let [a, b, c, d, e, f, g, hh] = h;
    for (let i = 0; i < 64; i++) {
      const S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
      const ch = (e & f) ^ (~e & g);
      const t1 = (hh + S1 + ch + K[i] + w[i]) >>> 0;
      const S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
      const maj = (a & b) ^ (a & c) ^ (b & c);
      const t2 = (S0 + maj) >>> 0;
      hh = g;
      g = f;
      f = e;
      e = (d + t1) >>> 0;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) >>> 0;
    }
    h = [
      (h[0] + a) >>> 0, (h[1] + b) >>> 0, (h[2] + c) >>> 0, (h[3] + d) >>> 0,
      (h[4] + e) >>> 0, (h[5] + f) >>> 0, (h[6] + g) >>> 0, (h[7] + hh) >>> 0,
    ];
  }
  const out = new Uint8Array(32);
  const odv = new DataView(out.buffer);
  for (let i = 0; i < 8; i++) odv.setUint32(i * 4, h[i]);
  return out;
}

function rotr(x, n) {
  return (x >>> n) | (x << (32 - n));
}
