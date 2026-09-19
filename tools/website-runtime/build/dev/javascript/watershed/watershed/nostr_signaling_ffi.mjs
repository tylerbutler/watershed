// The Nostr relay pool behind `watershed/nostr_signaling_js`.
//
// This file owns the sockets, the ephemeral signing key, the room-derived
// AES key, and the dedupe set. It moves opaque plaintext strings: what a
// frame means, who it is for, and what the roster is are decided in the
// Gleam module. The one protocol this file speaks is NIP-01's relay
// vocabulary — `REQ`/`EVENT` out, `EVENT`/`EOSE`/`CLOSED` in — which is
// transport, not policy.
//
// ## Privacy
//
// A public relay carries whatever it is handed, so nothing legible is
// handed to it. The room name never appears on the wire: the subscription
// topic is a hash of it, and every frame body is AES-GCM encrypted with a
// key HKDF-derived from it. The relay (and anyone browsing it) sees that
// *someone* is signaling under an opaque topic, and nothing else. The room
// name is the room's secret, exactly as it is for the reference signaling
// service — anyone who has it is a member.
//
// ## Signing
//
// Nostr events must be Schnorr-signed and relays verify the signature, so
// `nostr-tools` is an *optional peer dependency*, exactly as `phoenix` is
// for the sequenced transport: a guarded top-level-await dynamic import
// resolves it at module load in an app bundle and degrades to `undefined`
// where it is absent, in which case `openPool` fails with a message that
// names the missing package. Every pool signs with a throwaway key
// generated at `openPool`; identity lives in watershed peer ids, not in
// Nostr keys.
//
// `WebSocket` is read from `globalThis` at call time, as in `ws_ffi.mjs`:
// a browser global, or the `ws` shim the Node test suites install.

import { Ok as GleamOk, Error as GleamError } from "../gleam.mjs";

let nostr;
try {
  nostr = await import("nostr-tools/pure");
} catch {
  // nostr-tools not installed — fine unless a nostr pool is opened.
}

// Any kind in 20000–29999 is ephemeral by NIP-01: relays broadcast it and
// store nothing. The exact number only has to be shared by every peer.
export const KIND = 21212;

const encoder = new TextEncoder();
const decoder = new TextDecoder();

// The label every derivation is bound to. Bumping it is a new, disjoint
// signaling universe: old and new clients stop hearing each other.
const DERIVATION = "watershed-nostr-v1";

// One pool: the same subscription on every relay, events deduped by id
// across them, so N flaky public relays behave as one adequate service.
//
// `onFirstReady` fires once, when the first relay acknowledges the
// subscription (`EOSE`) — the earliest moment a census of the room can
// meaningfully start. `onAllFailed` fires once, when the last socket is
// gone; individual relay failures are absorbed while any other lives.
export function openPool(relayUrls, room, onPlaintext, onFirstReady, onAllFailed) {
  if (!nostr) {
    return new GleamError(
      "the nostr signaling adapter needs the `nostr-tools` package (an " +
        "optional peer dependency, as `phoenix` is for the sequenced " +
        "transport) and it is not installed",
    );
  }
  const Impl = globalThis.WebSocket;
  if (typeof Impl !== "function") {
    return new GleamError("this environment has no WebSocket");
  }
  if (!globalThis.crypto || !globalThis.crypto.subtle) {
    return new GleamError("this environment has no WebCrypto");
  }

  const secretKey = nostr.generateSecretKey();
  const pool = {
    closing: false, // close requested: no new work, no more deliveries
    closed: false, // queued publishes flushed, sockets closed
    ready: derive(room), // -> { topic, key }, shared by every send/receive
    readyFailed: false,
    anyReady: false,
    seen: new Set(), // event ids, across every relay
    txChain: Promise.resolve(), // publishes in call order
    rxChain: Promise.resolve(), // deliveries in arrival order
    entries: [],
    secretKey,
    onPlaintext,
    onFirstReady,
    onAllFailed,
  };

  // A key derivation that fails (no entropy, a broken subtle) fails every
  // send and every receive, so it is the pool's failure, reported once.
  pool.ready.catch((error) => {
    pool.readyFailed = true;
    failPool(pool, "room key derivation failed: " + describe(error));
  });

  let lastRefusal = "no relay urls were given";
  for (const url of relayUrls.toArray()) {
    let socket;
    try {
      socket = new Impl(url);
    } catch (error) {
      lastRefusal = describe(error);
      continue;
    }
    const entry = { socket, url, subscribed: false, dead: false, queue: [] };
    pool.entries.push(entry);

    socket.onopen = async () => {
      if (pool.closed || entry.dead || pool.readyFailed) return;
      const { topic } = await pool.ready.catch(() => ({}));
      if (pool.closed || entry.dead || !topic) return;
      // The subscription goes first; the relay processes frames in order,
      // so it is standing before any queued hello is broadcast back.
      socket.send(
        JSON.stringify([
          "REQ",
          "watershed",
          { kinds: [KIND], "#t": [topic], since: nowSeconds() - 60 },
        ]),
      );
      const queued = entry.queue;
      entry.queue = [];
      for (const frame of queued) {
        if (!entry.dead && !pool.closed) socket.send(frame);
      }
    };

    socket.onmessage = (event) => {
      if (pool.closing || entry.dead || typeof event.data !== "string") return;
      let message;
      try {
        message = JSON.parse(event.data);
      } catch {
        return; // not relay vocabulary; a public relay's noise is dropped
      }
      if (!Array.isArray(message)) return;
      if (message[0] === "EOSE") {
        entry.subscribed = true;
        if (!pool.anyReady) {
          pool.anyReady = true;
          onFirstReady();
        }
      } else if (message[0] === "EVENT") {
        receive(pool, message[2]);
      } else if (message[0] === "CLOSED") {
        // The relay refused the subscription: this relay is of no use.
        retire(pool, entry, "relay " + entry.url + " refused the subscription");
      }
      // OK and NOTICE carry nothing this pool acts on.
    };

    socket.onerror = () => retire(pool, entry, "relay " + entry.url + " errored");
    socket.onclose = () =>
      retire(pool, entry, "relay " + entry.url + " closed its socket");
  }

  if (pool.entries.length === 0) return new GleamError(lastRefusal);
  return new GleamOk(pool);
}

// Encrypt, sign, and send one frame to every relay, queueing it on relays
// still connecting. Publishes settle in call order.
export function publish(pool, plaintext) {
  if (pool.closing) return undefined;
  pool.txChain = pool.txChain
    .then(async () => {
      if (pool.closed || pool.readyFailed) return;
      const { topic, key } = await pool.ready;
      const event = nostr.finalizeEvent(
        {
          kind: KIND,
          created_at: nowSeconds(),
          tags: [["t", topic]],
          content: await encrypt(key, plaintext),
        },
        pool.secretKey,
      );
      const frame = JSON.stringify(["EVENT", event]);
      for (const entry of pool.entries) {
        if (entry.dead) continue;
        if (entry.socket.readyState === 1) {
          entry.socket.send(frame);
        } else {
          entry.queue.push(frame);
        }
      }
    })
    .catch(() => {
      // A failed derivation was already reported as the pool's failure; a
      // send on a socket that closed mid-frame is that socket's close.
    });
  return undefined;
}

// Close after the tx chain drains, so a `bye` written just before the
// close still reaches the relays instead of racing the socket teardown.
// New publishes and deliveries stop immediately.
export function closePool(pool) {
  if (pool.closing) return undefined;
  pool.closing = true;
  pool.txChain.then(() => {
    pool.closed = true;
    for (const entry of pool.entries) {
      entry.dead = true;
      entry.queue = [];
      try {
        entry.socket.close();
      } catch {
        // Already closing; asked for.
      }
    }
  });
  return undefined;
}

// ── receiving ───────────────────────────────────────────────────────────────

function receive(pool, event) {
  if (!event || typeof event.content !== "string" || typeof event.id !== "string") {
    return;
  }
  // Every relay echoes every event — our own included — so the id set is
  // what turns N relays into one stream. Duplicates are free by the
  // transport's contract, so a full set is simply cleared: the worst case
  // of forgetting is a redelivery, which is harmless, unlike growth.
  if (pool.seen.has(event.id)) return;
  if (pool.seen.size >= 8192) pool.seen.clear();
  pool.seen.add(event.id);

  pool.rxChain = pool.rxChain
    .then(async () => {
      if (pool.closing || pool.readyFailed) return;
      const { key } = await pool.ready;
      let plaintext;
      try {
        plaintext = await decrypt(key, event.content);
      } catch {
        return; // not this room's ciphertext: a stranger on the topic, dropped
      }
      if (!pool.closing) pool.onPlaintext(plaintext);
    })
    .catch(() => {});
}

// ── failure ─────────────────────────────────────────────────────────────────

function retire(pool, entry, detail) {
  if (entry.dead) return;
  entry.dead = true;
  entry.queue = [];
  try {
    entry.socket.close();
  } catch {
    // Already closing.
  }
  if (pool.entries.every((peer) => peer.dead)) failPool(pool, detail);
}

function failPool(pool, detail) {
  if (pool.closing) return;
  closePool(pool);
  pool.onAllFailed(detail);
}

// ── crypto ──────────────────────────────────────────────────────────────────

async function derive(room) {
  const subtle = globalThis.crypto.subtle;
  const topicBytes = await subtle.digest(
    "SHA-256",
    encoder.encode(DERIVATION + ":" + room),
  );
  const material = await subtle.importKey(
    "raw",
    encoder.encode(room),
    "HKDF",
    false,
    ["deriveKey"],
  );
  const key = await subtle.deriveKey(
    {
      name: "HKDF",
      hash: "SHA-256",
      salt: encoder.encode(DERIVATION),
      info: encoder.encode("frame-key"),
    },
    material,
    { name: "AES-GCM", length: 256 },
    false,
    ["encrypt", "decrypt"],
  );
  return { topic: hex(new Uint8Array(topicBytes)), key };
}

async function encrypt(key, plaintext) {
  const iv = globalThis.crypto.getRandomValues(new Uint8Array(12));
  const ciphertext = new Uint8Array(
    await globalThis.crypto.subtle.encrypt(
      { name: "AES-GCM", iv },
      key,
      encoder.encode(plaintext),
    ),
  );
  const packed = new Uint8Array(iv.length + ciphertext.length);
  packed.set(iv);
  packed.set(ciphertext, iv.length);
  return base64(packed);
}

async function decrypt(key, content) {
  const packed = unbase64(content);
  const plaintext = await globalThis.crypto.subtle.decrypt(
    { name: "AES-GCM", iv: packed.subarray(0, 12) },
    key,
    packed.subarray(12),
  );
  return decoder.decode(plaintext);
}

// ── small helpers ───────────────────────────────────────────────────────────

function nowSeconds() {
  return Math.floor(Date.now() / 1000);
}

function hex(bytes) {
  let out = "";
  for (const byte of bytes) out += byte.toString(16).padStart(2, "0");
  return out;
}

function base64(bytes) {
  let binary = "";
  for (let i = 0; i < bytes.length; i += 4096) {
    binary += String.fromCharCode(...bytes.subarray(i, i + 4096));
  }
  return btoa(binary);
}

function unbase64(text) {
  const binary = atob(text);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function describe(error) {
  if (error instanceof Error) return error.name + ": " + error.message;
  return String(error);
}
