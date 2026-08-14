// The native `WebSocket` backend shared by `watershed/crdt_signaling_js`
// and `watershed/crdt_sequencer_js`.
//
// This file owns the socket, its listeners, and — for the signaling
// variant — the queue of frames written before it opened. Gleam holds only
// the opaque handle `open*` returns, so there is no browser object on the
// Gleam side and no listener list to keep in step.
//
// There is no policy here. What a frame means, when a drop is worth
// retrying, and what a failure implies are decided in the Gleam modules.
// The two variants differ only in the small ways their protocols demand:
//
//   * signaling queues writes made before the socket opens and flushes
//     them in order — the `join` frame is written from inside `join`,
//     before any real socket can be open;
//   * the relay refuses such writes instead (`send` answers `false`): it
//     only writes after the capability handshake, and a queue flushed
//     after a reconnect would replay a document's history behind the
//     state that already superseded it.
//
// Both report exactly one close per socket, whatever mixture of `onerror`
// and `onclose` the environment delivers; `onerror` carries no detail by
// specification, so whichever arrives first names the reason.
//
// `WebSocket` is read from `globalThis` at call time rather than imported.
// In a browser it is a global; under Node, the live suites install one
// from `ws` (see `smoke/run.mjs`). A static import of `ws` here would
// break every browser bundle.

import { Ok as GleamOk, Error as GleamError } from "../gleam.mjs";

// One socket, wired up. `queue` is an array for the queueing variant and
// `null` for the refusing one; `onBinary` decides what a non-text frame
// does, since only text frames carry either protocol and decoding a
// binary one would be guessing.
function openSocket(url, label, queue, onMessage, onClose, onBinary) {
  const Impl = globalThis.WebSocket;
  if (typeof Impl !== "function") {
    return new GleamError("this environment has no WebSocket");
  }

  let socket;
  try {
    socket = new Impl(url);
  } catch (error) {
    // A malformed URL, a blocked scheme, or a context that refuses to
    // open sockets at all. All three are this attempt's failure rather
    // than an exception thrown out of the caller.
    return new GleamError(describe(error));
  }

  const entry = { socket, queue, closed: false };
  const finish = (detail) => {
    if (entry.closed) return;
    entry.closed = true;
    if (entry.queue) entry.queue = [];
    onClose(detail);
  };
  entry.finish = finish;

  socket.onopen = () => {
    if (entry.closed || !entry.queue) return;
    const queued = entry.queue;
    entry.queue = [];
    for (const payload of queued) {
      if (!entry.closed) socket.send(payload);
    }
  };

  socket.onmessage = (event) => {
    if (entry.closed) return;
    if (typeof event.data === "string") {
      onMessage(event.data);
    } else {
      onBinary(entry);
    }
  };

  socket.onerror = () => finish("the " + label + " socket errored");

  socket.onclose = (event) =>
    finish(
      "the " +
        label +
        " socket closed (" +
        (event && event.code !== undefined ? event.code : "no code") +
        (event && event.reason ? ": " + event.reason : "") +
        ")",
    );

  return new GleamOk(entry);
}

// ── the signaling variant: queue before open ────────────────────────────────

export function openSignaling(url, onMessage, onFailure) {
  return openSocket(url, "signaling", [], onMessage, onFailure, () =>
    onFailure("signaling sent a non-text frame"),
  );
}

export function sendSignaling(entry, payload) {
  if (entry.closed) return undefined;
  if (entry.socket.readyState === 1) {
    entry.socket.send(payload);
  } else {
    // Written before the socket opened. Flushed in order by `onopen`; a
    // socket that never opens closes instead, which clears the queue and
    // reports the failure.
    entry.queue.push(payload);
  }
  return undefined;
}

// ── the relay variant: refuse before open ───────────────────────────────────

export function openRelay(url, onMessage, onClose) {
  return openSocket(url, "relay", null, onMessage, onClose, (entry) => {
    entry.finish("the relay sent a non-text frame");
    try {
      entry.socket.close();
    } catch {
      // Already closing; the close reason above is the one that matters.
    }
  });
}

export function sendRelay(entry, payload) {
  // Nothing is queued, and nothing is claimed. A socket that has closed
  // underneath the caller answers `false` so the caller can take the
  // other path now rather than discover the loss later.
  if (entry.closed) return false;
  if (entry.socket.readyState !== 1) return false;
  try {
    entry.socket.send(payload);
  } catch {
    // `send` throws on a socket that closed between the readyState check
    // and the write. That is the same outcome as a closed socket, and the
    // caller is told so rather than told nothing.
    return false;
  }
  return true;
}

// ── shared ──────────────────────────────────────────────────────────────────

export function close(entry) {
  if (entry.closed) return undefined;
  entry.closed = true;
  if (entry.queue) entry.queue = [];
  try {
    entry.socket.close();
  } catch {
    // A socket already closing throws nothing worth reporting: the caller
    // asked for exactly this outcome.
  }
  return undefined;
}

// UTF-8 bytes, not code units: the envelope limit is a byte limit, and a
// string's `length` is neither.
const encoder = new TextEncoder();

export function byteSize(raw) {
  return encoder.encode(raw).length;
}

function describe(error) {
  if (error instanceof Error) {
    return error.name + ": " + error.message;
  }
  return String(error);
}
