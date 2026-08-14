// The native `RTCPeerConnection` backend for `watershed/p2p_transport_js`.
//
// This file owns every mutable browser object the transport touches: one
// `RTCPeerConnection` and at most one `RTCDataChannel` per remote peer, held
// in a `Map` keyed by peer ID inside a registry the Gleam side treats as
// opaque. Gleam holds peer IDs and its own negotiation bookkeeping; it never
// holds a connection, a channel, or a listener.
//
// There is no policy here. Which side offers, which side is polite, when a
// candidate may be applied, and what a failure means are all decided in
// `p2p_transport_js.gleam`. This module performs the operation it is asked
// for and reports the outcome through the hooks it was given at `open`.
//
// Every promise gets a `.catch` that calls `onFailure(peer, stage, detail)`.
// Nothing is thrown into the event loop, and nothing is dropped: a rejection
// that Gleam has no peer for is a peer that was already torn down, which is
// the one case where there is genuinely nothing to report.
//
// Every hook a promise continuation fires is guarded by `live`. A peer ID is
// not an identity: a peer can be closed and a new one created under the same
// ID before an outstanding `setLocalDescription`, `setRemoteDescription`, or
// `addIceCandidate` settles, and its continuation must not hand the new peer
// the old connection's SDP, remote-description event, or failure.

// The label of the one document data channel. It must match
// `p2p_transport_js.document_channel_label`; the pair is asserted by
// `p2p_transport_ffi_test.gleam`, which drives this module with the Gleam
// constant. An incoming channel with any other label is a peer speaking a
// protocol this transport does not have.
const documentChannelLabel = "watershed-crdt-v1";

// A fresh registry per transport, so two documents in one page never share
// connections. `generation` numbers the entries so a stale continuation is
// identifiable even in a debugger, where object identity is not printable.
export function newRtc() {
  return { peers: new Map(), generation: 0 };
}

// Whether `entry` is still *the* entry for `peerId`. `closePeer` deletes it,
// and any peer created for the same ID afterwards is a different object with
// a later generation, so this is false for every continuation that outlived
// its connection.
function live(rtc, peerId, entry) {
  return rtc.peers.get(peerId) === entry;
}

export function open(
  rtc,
  peerId,
  configurationJson,
  onNegotiationNeeded,
  onDescription,
  onRemoteDescription,
  onCandidate,
  onChannelOpen,
  onChannelClose,
  onMessage,
  onInvalidMessage,
  onIceState,
  onFailure,
) {
  // Idempotent: a duplicate join must not replace a live connection.
  if (rtc.peers.has(peerId)) return undefined;

  const hooks = {
    onNegotiationNeeded,
    onDescription,
    onRemoteDescription,
    onCandidate,
    onChannelOpen,
    onChannelClose,
    onMessage,
    onInvalidMessage,
    onIceState,
    onFailure,
  };

  let connection;
  try {
    connection = new RTCPeerConnection(JSON.parse(configurationJson));
  } catch (error) {
    // Construction fails on a malformed `RTCConfiguration` or in a context
    // with no WebRTC at all. Both are the caller's problem, and both have to
    // arrive as a typed error rather than as an exception thrown from a
    // signaling callback.
    onFailure(peerId, "open", describe(error));
    return undefined;
  }

  const entry = {
    connection,
    channel: null,
    hooks,
    generation: ++rtc.generation,
  };
  rtc.peers.set(peerId, entry);

  connection.onnegotiationneeded = () => hooks.onNegotiationNeeded(peerId);

  connection.onicecandidate = (event) => {
    // The null candidate is the end-of-gathering marker, not a candidate.
    if (event.candidate === null) return;
    hooks.onCandidate(peerId, JSON.stringify(event.candidate.toJSON()));
  };

  connection.oniceconnectionstatechange = () =>
    hooks.onIceState(peerId, connection.iceConnectionState);

  connection.onconnectionstatechange = () => {
    if (connection.connectionState === "failed") {
      hooks.onFailure(peerId, "connection", "peer connection failed");
    }
  };

  // Only the offering side calls `createDataChannel`; the answering side's
  // channel arrives here. That asymmetry is what guarantees exactly one
  // document channel per link.
  connection.ondatachannel = (event) => {
    if (event.channel.label !== documentChannelLabel) {
      // Not our protocol. Refuse it, and leave the document channel — if
      // one exists — untouched.
      hooks.onInvalidMessage(
        peerId,
        "unexpected data channel label: " + event.channel.label,
      );
      event.channel.close();
      return;
    }
    attachChannel(rtc, entry, peerId, event.channel);
  };

  return undefined;
}

export function openChannel(rtc, peerId, label, optionsJson) {
  const entry = rtc.peers.get(peerId);
  if (entry === undefined || entry.channel !== null) return undefined;
  try {
    const channel = entry.connection.createDataChannel(
      label,
      JSON.parse(optionsJson),
    );
    attachChannel(rtc, entry, peerId, channel);
  } catch (error) {
    entry.hooks.onFailure(peerId, "channel", describe(error));
  }
  return undefined;
}

// `setLocalDescription()` with no argument produces the offer or answer the
// current signaling state calls for, which is what perfect negotiation wants:
// the description type is read back off the connection rather than assumed.
export function offer(rtc, peerId) {
  const entry = rtc.peers.get(peerId);
  if (entry === undefined) return undefined;
  entry.connection
    .setLocalDescription()
    .then(() => {
      if (live(rtc, peerId, entry)) reportLocalDescription(entry, peerId);
    })
    .catch((error) => {
      if (live(rtc, peerId, entry)) {
        entry.hooks.onFailure(peerId, "offer", describe(error));
      }
    });
  return undefined;
}

// Applying a remote offer while a local offer is outstanding rolls the local
// one back implicitly — that is the whole of perfect negotiation's rollback,
// and it is why the polite peer needs no explicit rollback call.
export function acceptOffer(rtc, peerId, sdp) {
  const entry = rtc.peers.get(peerId);
  if (entry === undefined) return undefined;
  entry.connection
    .setRemoteDescription({ type: "offer", sdp })
    .then(() => {
      if (!live(rtc, peerId, entry)) return undefined;
      entry.hooks.onRemoteDescription(peerId);
      return entry.connection.setLocalDescription();
    })
    .then(() => {
      if (live(rtc, peerId, entry)) reportLocalDescription(entry, peerId);
    })
    .catch((error) => {
      if (live(rtc, peerId, entry)) {
        entry.hooks.onFailure(peerId, "answer", describe(error));
      }
    });
  return undefined;
}

export function acceptAnswer(rtc, peerId, sdp) {
  const entry = rtc.peers.get(peerId);
  if (entry === undefined) return undefined;
  entry.connection
    .setRemoteDescription({ type: "answer", sdp })
    .then(() => {
      if (live(rtc, peerId, entry)) entry.hooks.onRemoteDescription(peerId);
    })
    .catch((error) => {
      if (live(rtc, peerId, entry)) {
        entry.hooks.onFailure(peerId, "answer", describe(error));
      }
    });
  return undefined;
}

export function addCandidate(rtc, peerId, candidateJson) {
  const entry = rtc.peers.get(peerId);
  if (entry === undefined) return undefined;
  let candidate;
  try {
    candidate = JSON.parse(candidateJson);
  } catch (error) {
    entry.hooks.onFailure(peerId, "candidate", describe(error));
    return undefined;
  }
  entry.connection.addIceCandidate(candidate).catch((error) => {
    if (live(rtc, peerId, entry)) {
      entry.hooks.onFailure(peerId, "candidate", describe(error));
    }
  });
  return undefined;
}

export function signalingState(rtc, peerId) {
  const entry = rtc.peers.get(peerId);
  return entry === undefined ? "closed" : entry.connection.signalingState;
}

export function send(rtc, peerId, payload) {
  const entry = rtc.peers.get(peerId);
  if (entry === undefined || entry.channel === null) return false;
  if (entry.channel.readyState !== "open") return false;
  try {
    entry.channel.send(payload);
    return true;
  } catch (error) {
    // `send` throws when the outgoing buffer is full or the channel closed
    // between the readiness check and the write. The caller learns it did not
    // go out, and the reason reaches the typed error callback.
    entry.hooks.onFailure(peerId, "send", describe(error));
    return false;
  }
}

// Detach every listener *before* closing, so the teardown cannot re-enter
// Gleam through an `onclose` or a state change for a peer it has already
// forgotten.
export function closePeer(rtc, peerId) {
  const entry = rtc.peers.get(peerId);
  if (entry === undefined) return undefined;
  rtc.peers.delete(peerId);

  const connection = entry.connection;
  connection.onnegotiationneeded = null;
  connection.onicecandidate = null;
  connection.oniceconnectionstatechange = null;
  connection.onconnectionstatechange = null;
  connection.ondatachannel = null;

  if (entry.channel !== null) {
    const channel = entry.channel;
    channel.onopen = null;
    channel.onclose = null;
    channel.onerror = null;
    channel.onmessage = null;
    entry.channel = null;
    channel.close();
  }
  connection.close();
  return undefined;
}

// Channel and connection facts, for status reporting and for asserting in a
// real browser that the document channel is reliable and unordered:
// `maxRetransmits` and `maxPacketLifeTime` are both null exactly when it is.
export function diagnostics(rtc, peerId) {
  const entry = rtc.peers.get(peerId);
  if (entry === undefined) return JSON.stringify({ known: false });
  const channel = entry.channel;
  return JSON.stringify({
    known: true,
    signalingState: entry.connection.signalingState,
    connectionState: entry.connection.connectionState,
    iceConnectionState: entry.connection.iceConnectionState,
    channel:
      channel === null
        ? null
        : {
            label: channel.label,
            readyState: channel.readyState,
            ordered: channel.ordered,
            maxRetransmits: channel.maxRetransmits,
            maxPacketLifeTime: channel.maxPacketLifeTime,
          },
  });
}

function attachChannel(rtc, entry, peerId, channel) {
  if (entry.channel !== null) {
    // A second channel on one link means the peer is not speaking this
    // protocol. Report it and leave the first channel alone.
    entry.hooks.onInvalidMessage(
      peerId,
      "unexpected second data channel: " + channel.label,
    );
    channel.close();
    return;
  }
  entry.channel = channel;
  channel.onopen = () => {
    if (live(rtc, peerId, entry)) entry.hooks.onChannelOpen(peerId);
  };
  channel.onclose = () => {
    if (live(rtc, peerId, entry)) entry.hooks.onChannelClose(peerId);
  };
  channel.onerror = (event) => {
    if (live(rtc, peerId, entry)) {
      entry.hooks.onFailure(peerId, "channel", describe(event && event.error));
    }
  };
  channel.onmessage = (event) => {
    if (!live(rtc, peerId, entry)) return;
    if (typeof event.data === "string") {
      entry.hooks.onMessage(peerId, event.data);
    } else {
      entry.hooks.onInvalidMessage(
        peerId,
        "non-string data channel message: " + typeName(event.data),
      );
    }
  };
  // A channel created by `createDataChannel` on an already-connected peer
  // opens before a listener can be attached, so an open one is reported now
  // rather than waited for.
  if (channel.readyState === "open") entry.hooks.onChannelOpen(peerId);
}

function reportLocalDescription(entry, peerId) {
  const description = entry.connection.localDescription;
  if (description === null) {
    entry.hooks.onFailure(peerId, "offer", "no local description was produced");
    return;
  }
  entry.hooks.onDescription(peerId, description.type, description.sdp);
}

function describe(error) {
  if (error === undefined || error === null) return "unknown error";
  if (typeof error === "string") return error;
  if (error.message) return String(error.message);
  return String(error);
}

function typeName(value) {
  if (value === null) return "null";
  if (value instanceof ArrayBuffer) return "ArrayBuffer";
  if (typeof Blob !== "undefined" && value instanceof Blob) return "Blob";
  return typeof value;
}
