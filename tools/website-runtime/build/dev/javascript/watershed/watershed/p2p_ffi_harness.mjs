// A deterministic browser for `src/watershed/p2p_transport_ffi.mjs`.
//
// The fake `RTCPeerConnection` in `p2p_fake.gleam` stands in for the whole
// `Rtc` seam, which is the right level for negotiation policy but leaves the
// FFI itself — the code that actually holds the browser's promises —
// untested.
// This harness drives that module directly, with an `RTCPeerConnection` whose
// promises never settle until the test says so.
//
// The promises are synchronous. A real promise resolves in a microtask, which
// no Gleam test can wait for without becoming asynchronous; `Deferred` below
// is a promise-shaped object whose continuations run inside `resolve`, so a
// test can close a peer, create a new one under the same ID, and *then* settle
// the operation the old one started — all in one synchronous call. That is
// the exact interleaving a browser produces when a peer leaves and rejoins
// while a `setLocalDescription` is in flight, and it is the one that must not
// deliver the old connection's SDP, remote-description event, or failure to
// the new peer.
//
// Every scenario returns its hook log as a string, so the assertions live in
// Gleam rather than here.

import * as ffi from "./p2p_transport_ffi.mjs";

// ── a synchronous promise ───────────────────────────────────────────────────

class Deferred {
  constructor() {
    this.state = "pending";
    this.value = undefined;
    this.handlers = [];
  }

  then(onOk, onErr) {
    const next = new Deferred();
    this.handlers.push({ onOk, onErr, next });
    if (this.state !== "pending") this.flush();
    return next;
  }

  catch(onErr) {
    return this.then(undefined, onErr);
  }

  resolve(value) {
    this.settle("fulfilled", value);
  }

  reject(reason) {
    this.settle("rejected", reason);
  }

  settle(state, value) {
    if (this.state !== "pending") return;
    // Adopt a thenable, so a continuation that returns another operation's
    // promise chains the way the FFI's `acceptOffer` expects.
    if (state === "fulfilled" && value && typeof value.then === "function") {
      value.then(
        (inner) => this.settle("fulfilled", inner),
        (error) => this.settle("rejected", error),
      );
      return;
    }
    this.state = state;
    this.value = value;
    this.flush();
  }

  flush() {
    const handlers = this.handlers;
    this.handlers = [];
    for (const handler of handlers) {
      const callback =
        this.state === "fulfilled" ? handler.onOk : handler.onErr;
      if (typeof callback !== "function") {
        handler.next.settle(this.state, this.value);
        continue;
      }
      try {
        handler.next.settle("fulfilled", callback(this.value));
      } catch (error) {
        handler.next.settle("rejected", error);
      }
    }
  }
}

// ── the fake browser ────────────────────────────────────────────────────────

let constructed = [];

class FakeChannel {
  constructor(label, options) {
    this.label = label;
    this.options = options || {};
    this.ordered = this.options.ordered !== false;
    this.maxRetransmits = null;
    this.maxPacketLifeTime = null;
    this.readyState = "connecting";
    this.closes = 0;
    this.sent = [];
    this.onopen = null;
    this.onclose = null;
    this.onerror = null;
    this.onmessage = null;
  }

  send(payload) {
    this.sent.push(payload);
  }

  close() {
    this.closes += 1;
    this.readyState = "closed";
  }
}

class FakeConnection {
  constructor(configuration) {
    this.configuration = configuration;
    this.signalingState = "stable";
    this.connectionState = "new";
    this.iceConnectionState = "new";
    this.localDescription = null;
    this.remoteDescription = null;
    this.candidates = [];
    this.channels = [];
    this.pending = [];
    this.closes = 0;
    this.onnegotiationneeded = null;
    this.onicecandidate = null;
    this.oniceconnectionstatechange = null;
    this.onconnectionstatechange = null;
    this.ondatachannel = null;
    constructed.push(this);
  }

  setLocalDescription() {
    return this.defer("setLocalDescription");
  }

  setRemoteDescription(description) {
    this.remoteDescription = description;
    return this.defer("setRemoteDescription");
  }

  addIceCandidate(candidate) {
    this.candidates.push(candidate);
    return this.defer("addIceCandidate");
  }

  createDataChannel(label, options) {
    const channel = new FakeChannel(label, options);
    this.channels.push(channel);
    return channel;
  }

  close() {
    this.closes += 1;
    this.signalingState = "closed";
  }

  defer(kind) {
    const deferred = new Deferred();
    this.pending.push({ kind, deferred });
    return deferred;
  }

  // The oldest outstanding operation of this kind, removed from the queue.
  take(kind) {
    const index = this.pending.findIndex((entry) => entry.kind === kind);
    if (index === -1) throw new Error("nothing pending for " + kind);
    return this.pending.splice(index, 1)[0].deferred;
  }
}

function withFakeBrowser(scenario) {
  const previous = globalThis.RTCPeerConnection;
  globalThis.RTCPeerConnection = FakeConnection;
  constructed = [];
  try {
    return scenario();
  } finally {
    if (previous === undefined) delete globalThis.RTCPeerConnection;
    else globalThis.RTCPeerConnection = previous;
  }
}

// Wire one peer with hooks that write `tag`-prefixed lines into `log`.
function openPeer(rtc, peerId, tag, log) {
  const note = (line) => log.push(tag + " " + line);
  ffi.open(
    rtc,
    peerId,
    "{}",
    () => note("negotiation-needed"),
    (_peer, kind, sdp) => note("description " + kind + " " + sdp),
    () => note("remote-description"),
    (_peer, candidate) => note("candidate " + candidate),
    () => note("channel-open"),
    () => note("channel-close"),
    (_peer, data) => note("message " + data),
    (_peer, detail) => note("invalid " + detail),
    (_peer, state) => note("ice " + state),
    (_peer, stage, detail) => note("failure " + stage + " " + detail),
  );
  return constructed[constructed.length - 1];
}

// ── scenarios ───────────────────────────────────────────────────────────────

const PEER = "peer-z";

// Start the deferred operation `stage` names, and return how to settle it.
function beginStage(rtc, stage) {
  switch (stage) {
    case "offer":
    case "offer-failure":
    case "offer-no-description":
      ffi.offer(rtc, PEER);
      return "setLocalDescription";
    case "accept-offer":
    case "accept-offer-failure":
      ffi.acceptOffer(rtc, PEER, "sdp:their-offer");
      return "setRemoteDescription";
    case "accept-answer":
    case "accept-answer-failure":
      ffi.acceptAnswer(rtc, PEER, "sdp:their-answer");
      return "setRemoteDescription";
    case "candidate":
      ffi.addCandidate(rtc, PEER, '{"candidate":"c1"}');
      return "addIceCandidate";
    default:
      throw new Error("unknown stage " + stage);
  }
}

function settleStage(connection, stage, kind) {
  const deferred = connection.take(kind);
  switch (stage) {
    case "offer":
      connection.localDescription = { type: "offer", sdp: "sdp-1" };
      deferred.resolve(undefined);
      return;
    case "offer-no-description":
      // `setLocalDescription` resolved but produced nothing, which the FFI
      // reports as an `offer` failure of its own making.
      deferred.resolve(undefined);
      return;
    case "accept-offer":
    case "accept-answer":
      deferred.resolve(undefined);
      return;
    default:
      deferred.reject(new Error("boom"));
  }
}

/// Settle a continuation while its peer is still the one the registry
/// holds: the control that proves the guard is not simply silencing
/// everything.
export function liveContinuation(stage) {
  return withFakeBrowser(() => {
    const log = [];
    const rtc = ffi.newRtc();
    const connection = openPeer(rtc, PEER, "gen1", log);
    const kind = beginStage(rtc, stage);
    settleStage(connection, stage, kind);
    return log.join(",");
  });
}

/// Close the peer and create a new one under the same ID *before* the
/// operation the first one started settles. Nothing the old connection
/// produces may reach either generation's hooks.
export function staleContinuation(stage) {
  return withFakeBrowser(() => {
    const log = [];
    const rtc = ffi.newRtc();
    const connection = openPeer(rtc, PEER, "gen1", log);
    const kind = beginStage(rtc, stage);

    ffi.closePeer(rtc, PEER);
    openPeer(rtc, PEER, "gen2", log);

    settleStage(connection, stage, kind);
    return log.join(",");
  });
}

/// The same, for a peer that was closed and not recreated.
export function closedContinuation(stage) {
  return withFakeBrowser(() => {
    const log = [];
    const rtc = ffi.newRtc();
    const connection = openPeer(rtc, PEER, "gen1", log);
    const kind = beginStage(rtc, stage);
    ffi.closePeer(rtc, PEER);
    settleStage(connection, stage, kind);
    return log.join(",");
  });
}

/// Hand the peer connection an inbound data channel with `label` and report
/// what the FFI did with it. Called with the Gleam-side
/// `document_channel_label`, so the two constants cannot drift apart
/// unnoticed.
export function incomingChannel(label) {
  return withFakeBrowser(() => {
    const log = [];
    const rtc = ffi.newRtc();
    const connection = openPeer(rtc, PEER, "gen1", log);

    const channel = new FakeChannel(label, { ordered: false });
    connection.ondatachannel({ channel });

    // Whatever survived attachment is exercised: an accepted channel opens
    // and delivers, a refused one has no listeners to fire.
    if (channel.onopen !== null) {
      channel.readyState = "open";
      channel.onopen();
    }
    if (channel.onmessage !== null) channel.onmessage({ data: "hello" });
    if (channel.closes > 0) log.push("channel closed");
    return log.join(",");
  });
}

/// A second inbound channel on one link, whatever its label.
export function secondChannel() {
  return withFakeBrowser(() => {
    const log = [];
    const rtc = ffi.newRtc();
    const connection = openPeer(rtc, PEER, "gen1", log);
    const first = new FakeChannel("watershed-crdt-v1", {});
    connection.ondatachannel({ channel: first });
    const second = new FakeChannel("watershed-crdt-v1", {});
    connection.ondatachannel({ channel: second });
    if (second.closes > 0) log.push("channel closed");
    return log.join(",");
  });
}
