// Tests for the reference signaling service (`server.mjs`).
//
// These drive the real `ws` server over real sockets, because the parts worth
// testing here are the ones the pure protocol module cannot cover on its own:
// that a room's membership is announced in both directions over the wire,
// that the ninth peer is refused, that a target in another room cannot be
// named, that oversize and malformed frames close the socket — and, the point
// of the whole exercise, that a document envelope is rejected rather than
// routed.
//
// The browser adapter (`watershed/crdt_signaling_js`) is tested here too, for
// the same reason: it is a `WebSocket` client, and the things worth pinning
// down about it — that admission produces exactly one complete `Roster`, that
// a service which never answers ends the wait instead of hanging, that a
// socket failure reaches the transport as a `Failed` signal rather than only
// the application — need a real socket on the other end. `ws` is installed as
// the `WebSocket` global Node lacks, exactly as `smoke/run.mjs` does.
//
// The protocol's own rules (frame vocabulary, room registry transitions,
// rejection reasons) are tested in Gleam, in
// `test/watershed/crdt_signaling_test.gleam`. This file is the service.
//
//     gleam build --target javascript
//     node tools/signaling/test.mjs

import { WebSocketServer } from "ws";
import WebSocket from "ws";

globalThis.WebSocket = globalThis.WebSocket ?? WebSocket;

import { startSignalingServer, MAX_FRAME_BYTES } from "./server.mjs";
import {
  websocket_signaling as websocketSignaling,
  websocket_signaling_with_timeout as websocketSignalingWithTimeout,
} from "../../build/dev/javascript/watershed/watershed/crdt_signaling_js.mjs";

const failures = [];
let checks = 0;

main().then(
  (code) => process.exit(code),
  (error) => {
    console.error(error && error.stack ? error.stack : error);
    process.exit(1);
  },
);

async function main() {
  await test("a lone peer is admitted with an empty roster", async (service) => {
    const peer = await join(service, "room-a", "alpha");
    const joined = await peer.next("joined");
    is(joined.room, "room-a", "joined names the room");
    is(joined.peer, "alpha", "joined names the peer");
    deep(joined.peers, [], "the first peer sees an empty roster");
    deep(service.members("room-a"), ["alpha"], "the room holds one member");
    peer.close();
  });

  await test("both sides of a join are announced", async (service) => {
    const alpha = await join(service, "room-b", "alpha");
    await alpha.next("joined");
    const beta = await join(service, "room-b", "beta");

    const roster = await beta.next("joined");
    deep(roster.peers, ["alpha"], "the newcomer learns the existing member");
    const notice = await alpha.next("peerJoined");
    is(notice.peer, "beta", "the existing member learns the newcomer");

    alpha.close();
    beta.close();
  });

  await test("offers, answers and candidates route to one named peer", async (service) => {
    const alpha = await join(service, "room-c", "alpha");
    await alpha.next("joined");
    const beta = await join(service, "room-c", "beta");
    await beta.next("joined");
    await alpha.next("peerJoined");
    const gamma = await join(service, "room-c", "gamma");
    await gamma.next("joined");
    await alpha.next("peerJoined");
    await beta.next("peerJoined");

    alpha.send({
      t: "signal",
      to: "beta",
      payload: { t: "offer", sdp: "v=0 alpha" },
    });
    const forwarded = await beta.next("signal");
    is(forwarded.from, "alpha", "the payload names its sender");
    is(forwarded.payload.sdp, "v=0 alpha", "the payload is carried verbatim");

    beta.send({
      t: "signal",
      to: "alpha",
      payload: { t: "answer", sdp: "v=0 beta" },
    });
    is((await alpha.next("signal")).payload.t, "answer", "answers route");

    alpha.send({
      t: "signal",
      to: "beta",
      payload: { t: "candidate", candidate: "{\"candidate\":\"host\"}" },
    });
    is((await beta.next("signal")).payload.t, "candidate", "candidates route");

    is(
      gamma.frames.filter((frame) => frame.t === "signal").length,
      0,
      "an unaddressed peer received no payload",
    );

    alpha.close();
    beta.close();
    gamma.close();
  });

  await test("a room is capped at eight peers", async (service) => {
    const admitted = [];
    for (let index = 0; index < service.limit; index++) {
      const peer = await join(service, "room-d", "peer-" + index);
      await peer.next("joined");
      admitted.push(peer);
    }
    is(
      service.members("room-d").length,
      service.limit,
      "the room filled to its cap",
    );

    const ninth = await join(service, "room-d", "peer-8");
    const refusal = await ninth.next("error");
    is(refusal.reason, "roomFull", "the ninth peer is refused");
    is(refusal.detail, String(service.limit), "the refusal names the cap");
    is(await ninth.closed(), 1008, "the refused socket is closed");
    is(
      service.members("room-d").length,
      service.limit,
      "a refused join changes no membership",
    );

    for (const peer of admitted) peer.close();
  });

  await test("a duplicate peer id is refused", async (service) => {
    const alpha = await join(service, "room-e", "alpha");
    await alpha.next("joined");
    const impostor = await join(service, "room-e", "alpha");
    is((await impostor.next("error")).reason, "duplicatePeerId", "refused");
    is(await impostor.closed(), 1008, "the impostor's socket is closed");
    deep(service.members("room-e"), ["alpha"], "the real peer is untouched");
    alpha.close();
  });

  await test("a target in another room cannot be named", async (service) => {
    const alpha = await join(service, "room-f", "alpha");
    await alpha.next("joined");
    const outsider = await join(service, "room-g", "beta");
    await outsider.next("joined");

    outsider.send({
      t: "signal",
      to: "alpha",
      payload: { t: "offer", sdp: "v=0 cross-room" },
    });
    is((await outsider.next("error")).reason, "crossRoomTarget", "refused");
    is(await outsider.closed(), 1008, "the socket is closed");
    is(
      alpha.frames.filter((frame) => frame.t === "signal").length,
      0,
      "the cross-room target received nothing",
    );
    alpha.close();
  });

  await test("a signal to a peer that just left is dropped, not fatal", async (service) => {
    const alpha = await join(service, "room-l", "alpha");
    await alpha.next("joined");
    const beta = await join(service, "room-l", "beta");
    await beta.next("joined");
    await alpha.next("peerJoined");

    // The race every mesh runs: beta leaves while alpha's last candidate is
    // already on the wire.
    beta.send({ t: "leave" });
    await alpha.next("peerLeft");
    alpha.send({
      t: "signal",
      to: "beta",
      payload: { t: "candidate", candidate: "{\"candidate\":\"host\"}" },
    });

    const dropped = await alpha.next("dropped");
    is(dropped.reason, "unknownTarget", "the sender is told the frame went nowhere");
    is(alpha.closeCode, null, "the sender's socket stays open");
    deep(service.members("room-l"), ["alpha"], "and it is still in the room");

    // And it can still route to a peer that is there.
    const gamma = await join(service, "room-l", "gamma");
    await gamma.next("joined");
    await alpha.next("peerJoined");
    alpha.send({ t: "signal", to: "gamma", payload: { t: "offer", sdp: "v=0" } });
    is((await gamma.next("signal")).from, "alpha", "later signals still route");

    const counts = service.stats().framesByTag;
    is(counts["dropped:unknownTarget"], 1, "the drop is counted apart");
    is(
      Object.keys(counts).filter((tag) => tag.startsWith("rejected:")).length,
      0,
      "and it is not a rejection",
    );

    alpha.close();
    gamma.close();
  });

  await test("signalling before joining is refused", async (service) => {
    const stranger = await connect(service);
    stranger.send({
      t: "signal",
      to: "alpha",
      payload: { t: "offer", sdp: "v=0" },
    });
    is((await stranger.next("error")).reason, "notJoined", "refused");
    is(await stranger.closed(), 1008, "the socket is closed");
  });

  await test("a document envelope is rejected, not routed", async (service) => {
    const alpha = await join(service, "room-h", "alpha");
    await alpha.next("joined");
    const beta = await join(service, "room-h", "beta");
    await beta.next("joined");
    await alpha.next("peerJoined");

    // Exactly what a peer speaks on its data channel: a `crdt_wire` v1
    // envelope carrying a delta. There is no signaling frame shape that can
    // hold it, and the service must not invent one.
    const envelope = {
      v: 1,
      room: "room-h",
      from: "beta",
      session: "session-beta",
      message: {
        type: "delta",
        id: { replica: "beta", counter: 1 },
        address: "root",
        channelType: "pn_counter",
        op: { type: "pn_counter", amount: 1 },
      },
    };
    beta.sendRaw(JSON.stringify(envelope));
    is((await beta.next("error")).reason, "malformed", "the envelope is refused");
    is(await beta.closed(), 1008, "the sender's socket is closed");
    is(
      alpha.frames.filter((frame) => frame.t === "signal").length,
      0,
      "no peer received the envelope",
    );

    // And the same delta smuggled into a well-formed frame's payload slot.
    const gamma = await join(service, "room-h", "gamma");
    await gamma.next("joined");
    await alpha.next("peerJoined");
    gamma.send({ t: "signal", to: "alpha", payload: envelope.message });
    is((await gamma.next("error")).reason, "malformed", "a smuggled delta is refused");
    is(
      alpha.frames.filter((frame) => frame.t === "signal").length,
      0,
      "a smuggled delta reached nobody either",
    );

    const counts = service.stats().framesByTag;
    is(counts["rejected:malformed"], 2, "both attempts counted as rejections");
    is(counts["signal"] ?? 0, 0, "nothing was routed");
    alpha.close();
  });

  await test("an oversize frame is refused", async (service) => {
    const peer = await join(service, "room-i", "alpha");
    await peer.next("joined");
    peer.sendRaw("x".repeat(MAX_FRAME_BYTES + 1));
    is(await peer.closed(), 1009, "the socket is closed with 1009");
    deep(service.members("room-i"), [], "the room emptied with the socket");
  });

  await test("malformed JSON and unknown tags are refused", async (service) => {
    const broken = await connect(service);
    broken.sendRaw("{not json");
    is((await broken.next("error")).reason, "malformed", "bad JSON is refused");

    const unknown = await connect(service);
    unknown.send({ t: "relay", payload: "anything" });
    is((await unknown.next("error")).reason, "malformed", "unknown tags are refused");
  });

  await test("leaving and disconnecting are announced once", async (service) => {
    const alpha = await join(service, "room-j", "alpha");
    await alpha.next("joined");
    const beta = await join(service, "room-j", "beta");
    await beta.next("joined");
    await alpha.next("peerJoined");

    beta.send({ t: "leave" });
    is((await alpha.next("peerLeft")).peer, "beta", "a leave is announced");
    deep(service.members("room-j"), ["alpha"], "the leaver is gone");

    // The socket close that follows the leave must not announce it twice.
    beta.close();
    await sleep(120);
    is(
      alpha.frames.filter((frame) => frame.t === "peerLeft").length,
      1,
      "leave then disconnect announces once",
    );

    alpha.close();
    await sleep(120);
    deep(service.roomNames(), [], "an emptied room is deleted");
  });

  await test("only signaling frames are ever counted", async (service) => {
    const alpha = await join(service, "room-k", "alpha");
    await alpha.next("joined");
    const beta = await join(service, "room-k", "beta");
    await beta.next("joined");
    await alpha.next("peerJoined");
    beta.send({ t: "signal", to: "alpha", payload: { t: "offer", sdp: "v=0" } });
    await alpha.next("signal");
    beta.send({ t: "leave" });
    await alpha.next("peerLeft");

    const counts = service.stats().framesByTag;
    is(counts["join"], 2, "two joins");
    is(counts["signal"], 1, "one signal");
    is(counts["leave"], 1, "one leave");
    const rejections = Object.keys(counts).filter((tag) =>
      tag.startsWith("rejected:"),
    );
    deep(rejections, [], "no frame was rejected");
    alpha.close();
  });

  // ── the browser adapter, over the same real sockets ──────────────────────

  await test("the adapter reports one complete roster per join", async (service) => {
    const first = adapter(service, "room-m", "alpha");
    is(await first.roster(), "", "the first peer's roster is empty");

    const second = adapter(service, "room-m", "beta");
    is(await second.roster(), "alpha", "the second peer's roster names the first");
    is(
      first.signals.filter((signal) => signal.kind === "roster").length,
      1,
      "and the first peer's roster is not repeated when someone joins",
    );
    is(
      (await first.next("peerJoined")).peer,
      "beta",
      "the running announcement is a join, not a second roster",
    );

    first.leave();
    second.leave();
  });

  await test("a service that never admits ends the wait", async () => {
    // A socket that opens and then says nothing: the shape of a service that
    // is up, accepting connections, and broken.
    const silent = new WebSocketServer({ port: 0, host: "127.0.0.1" });
    await new Promise((ready) => silent.once("listening", ready));
    const url = "ws://127.0.0.1:" + silent.address().port + "/";

    const peer = adapterAt(url, "room-n", "alpha", 150);
    const failure = await peer.failure();
    is(
      failure.includes("did not admit this peer"),
      true,
      "the roster deadline is reported: " + failure,
    );
    is(peer.failures.length, 1, "the application is told once");
    is(
      peer.signals.filter((signal) => signal.kind === "failed").length,
      1,
      "and the transport is told once, so a waiting document is answered",
    );

    peer.leave();
    await new Promise((done) => silent.close(done));
  });

  await test("a service that goes away is reported to the transport", async (service) => {
    const peer = adapter(service, "room-o", "alpha");
    await peer.roster();
    await service.close();

    const failure = await peer.failure();
    is(failure.length > 0, true, "the socket close is described: " + failure);
    is(
      peer.signals.filter((signal) => signal.kind === "failed").length,
      1,
      "reported to the transport exactly once",
    );
    peer.leave();
  });

  await test("an unreachable service is reported after join returns", async () => {
    // Port 1 on loopback: nothing listens there. The `WebSocket` is
    // constructed, so `join` succeeds; the connection fails a moment later,
    // which is exactly the case a synchronous `join` cannot report.
    const peer = adapterAt("ws://127.0.0.1:1/", "room-p", "alpha", 5_000);
    is(peer.joined, true, "join returned a session");
    const failure = await peer.failure();
    is(failure.length > 0, true, "the failure is described: " + failure);
    is(
      peer.signals.filter((signal) => signal.kind === "failed").length,
      1,
      "and the transport is told, so a waiting document is answered",
    );
    peer.leave();
  });

  console.log("");
  if (failures.length === 0) {
    console.log("signaling service: PASS — " + checks + " checks");
    return 0;
  }
  console.log("signaling service: FAIL");
  for (const failure of failures) console.log("  " + failure);
  return 1;
}

// ── harness ─────────────────────────────────────────────────────────────────

// One `crdt_signaling_js` adapter, joined, with every signal it handed the
// transport recorded. The adapter is a Gleam record of three closures; this
// calls them exactly as `p2p_transport_js.start` does.
function adapter(service, room, id, timeoutMs = 5_000) {
  return adapterAt("ws://127.0.0.1:" + service.port() + "/", room, id, timeoutMs);
}

function adapterAt(url, room, id, timeoutMs) {
  const peer = { signals: [], failures: [], joined: false, session: null };
  const signaling = websocketSignalingWithTimeout(
    url,
    (detail) => peer.failures.push(detail),
    timeoutMs,
  );
  const result = signaling.join(room, id, (signal) =>
    peer.signals.push(readSignal(signal)),
  );
  peer.joined = result.isOk();
  peer.session = peer.joined ? result[0] : null;
  peer.leave = () => {
    if (peer.session) signaling.leave(peer.session);
  };
  // The roster's peers, comma-joined, so an assertion reads as one string.
  peer.roster = async () => (await waitForSignal(peer, "roster")).peers.join(",");
  peer.next = (kind) => waitForSignal(peer, kind);
  peer.failure = async () => {
    const deadline = Date.now() + 3_000;
    while (Date.now() < deadline) {
      if (peer.failures.length > 0) return peer.failures[0];
      await sleep(10);
    }
    throw new Error("no failure was reported");
  };
  return peer;
}

// A `p2p_transport_js.Signal` as plain data. Its constructor name is the
// variant, which is all these tests need to tell them apart.
function readSignal(signal) {
  const kind = signal.constructor.name;
  if (kind === "Roster") return { kind: "roster", peers: signal.peers.toArray() };
  if (kind === "PeerJoined") return { kind: "peerJoined", peer: signal.peer_id };
  if (kind === "PeerLeft") return { kind: "peerLeft", peer: signal.peer_id };
  if (kind === "Failed") return { kind: "failed", detail: signal.detail };
  return { kind: "message", from: signal.from };
}

async function waitForSignal(peer, kind) {
  peer.consumedSignals = peer.consumedSignals ?? new Set();
  const deadline = Date.now() + 3_000;
  while (Date.now() < deadline) {
    for (let index = 0; index < peer.signals.length; index++) {
      if (peer.signals[index].kind === kind && !peer.consumedSignals.has(index)) {
        peer.consumedSignals.add(index);
        return peer.signals[index];
      }
    }
    await sleep(10);
  }
  throw new Error(
    "no `" + kind + "` signal arrived; saw " + JSON.stringify(peer.signals),
  );
}

// One service per test, so a counter assertion is about that test alone.
async function test(name, body) {
  const service = startSignalingServer({ port: 0 });
  await service.listening;
  const before = failures.length;
  try {
    await body(service);
  } catch (error) {
    failures.push(name + ": threw " + (error && error.message ? error.message : error));
  } finally {
    await service.close();
  }
  console.log((failures.length === before ? "  ok   " : "  FAIL ") + name);
}

function connect(service) {
  const socket = new WebSocket("ws://127.0.0.1:" + service.port() + "/");
  const peer = {
    frames: [],
    closeCode: null,
    send: (frame) => socket.send(JSON.stringify(frame)),
    sendRaw: (raw) => socket.send(raw),
    close: () => socket.close(),
    next: (tag) => waitFor(peer, tag),
    closed: () => waitForClose(peer),
  };
  socket.on("message", (data) => peer.frames.push(JSON.parse(data.toString())));
  socket.on("close", (code) => {
    peer.closeCode = code;
  });
  socket.on("error", () => {});
  return new Promise((ready, failed) => {
    socket.once("open", () => ready(peer));
    socket.once("error", failed);
  });
}

async function join(service, room, id) {
  const peer = await connect(service);
  peer.send({ t: "join", room, peer: id });
  return peer;
}

// The next unconsumed frame with this tag. Frames are consumed in order, so a
// test that waits for `peerJoined` twice gets two different announcements.
async function waitFor(peer, tag) {
  peer.consumed = peer.consumed ?? new Set();
  const deadline = Date.now() + 3_000;
  while (Date.now() < deadline) {
    for (let index = 0; index < peer.frames.length; index++) {
      if (peer.frames[index].t === tag && !peer.consumed.has(index)) {
        peer.consumed.add(index);
        return peer.frames[index];
      }
    }
    await sleep(10);
  }
  throw new Error(
    "no `" + tag + "` frame arrived; saw " + JSON.stringify(peer.frames),
  );
}

async function waitForClose(peer) {
  const deadline = Date.now() + 3_000;
  while (Date.now() < deadline) {
    if (peer.closeCode !== null) return peer.closeCode;
    await sleep(10);
  }
  throw new Error("the socket never closed");
}

function sleep(ms) {
  return new Promise((done) => setTimeout(done, ms));
}

function is(actual, expected, what) {
  checks += 1;
  if (actual !== expected) {
    failures.push(what + ": expected " + JSON.stringify(expected) + ", got " + JSON.stringify(actual));
  }
}

function deep(actual, expected, what) {
  checks += 1;
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    failures.push(what + ": expected " + JSON.stringify(expected) + ", got " + JSON.stringify(actual));
  }
}
