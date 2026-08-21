// Tests for the Nostr signaling adapter (`watershed/nostr_signaling_js`).
//
// These drive the real adapter over real sockets against an in-process
// NIP-01 relay stub, because the parts worth testing are the ones the pure
// frame codec cannot cover: that a census produces exactly one roster and
// both sides of a pair discover each other, that signals route to their
// addressee and nowhere else, that two relays carrying the same event
// deliver it once, that a relay which accepts a socket and says nothing
// ends the wait, and — the point of the encrypted lane — that the relay
// never holds a legible byte: no room name, no peer id, no SDP.
//
// The stub speaks just enough NIP-01 for the adapter: `REQ` answered with
// `EOSE`, `EVENT` acknowledged with `OK` and broadcast to every matching
// subscription (the sender's included, as real relays do). It verifies no
// signatures — signing is `nostr-tools`' contract with real relays, not
// this suite's.
//
//     gleam build --target javascript
//     node tools/nostr/test.mjs

import { WebSocketServer } from "ws";
import WebSocket from "ws";

globalThis.WebSocket = globalThis.WebSocket ?? WebSocket;

import {
  nostr_signaling_with_timing as nostrSignalingWithTiming,
} from "../../build/dev/javascript/watershed/watershed/nostr_signaling_js.mjs";
import {
  Offer,
  Answer,
  Candidate,
} from "../../build/dev/javascript/watershed/watershed/p2p_transport_js.mjs";
import { toList } from "../../build/dev/javascript/prelude.mjs";

const failures = [];
let checks = 0;

main().then(
  (code) => process.exit(code),
  (error) => {
    console.error(error);
    process.exit(1);
  },
);

async function main() {
  await test("a census yields one roster and both sides discover each other", async (relay) => {
    const alpha = adapter([relay.url], "room-a", "alpha");
    is(await alpha.roster(), "", "the first peer's census is empty");

    const beta = adapter([relay.url], "room-a", "beta");
    is(await beta.roster(), "alpha", "the second peer's census names the first");
    is((await alpha.next("peerJoined")).peer, "beta", "the hello announces the newcomer");
    is(
      alpha.signals.filter((signal) => signal.kind === "roster").length,
      1,
      "the first peer's roster is not repeated when someone joins",
    );

    alpha.leave();
    beta.leave();
  });

  await test("signals route to their addressee and nowhere else", async (relay) => {
    const alpha = adapter([relay.url], "room-b", "alpha");
    await alpha.roster();
    const beta = adapter([relay.url], "room-b", "beta");
    await beta.roster();
    const outsider = adapter([relay.url], "room-c", "gamma");
    await outsider.roster();

    alpha.send("beta", new Offer("v=0 alpha"));
    const offer = await beta.next("message");
    is(offer.from, "alpha", "the payload names its sender");
    is(offer.payload, "offer:v=0 alpha", "the offer is carried verbatim");

    beta.send("alpha", new Answer("v=0 beta"));
    is((await alpha.next("message")).payload, "answer:v=0 beta", "answers route");

    alpha.send("beta", new Candidate('{"candidate":"host"}'));
    is(
      (await beta.next("message")).payload,
      'candidate:{"candidate":"host"}',
      "candidates route",
    );

    await settle(150);
    is(
      outsider.signals.filter((signal) => signal.kind !== "roster").length,
      0,
      "another room on the same relay heard nothing",
    );

    // The privacy assertion: everything the relay held, end to end.
    const held = JSON.stringify(relay.events);
    for (const secret of ["sdp", "hello", "alpha", "beta", "room-b", "v=0"]) {
      is(held.includes(secret), false, "the relay never held `" + secret + "`");
    }

    alpha.leave();
    beta.leave();
    outsider.leave();
  });

  await test("a bye is a departure, census included", async (relay) => {
    const alpha = adapter([relay.url], "room-d", "alpha");
    await alpha.roster();
    const beta = adapter([relay.url], "room-d", "beta");
    await beta.roster();
    await alpha.next("peerJoined");

    beta.leave();
    is((await alpha.next("peerLeft")).peer, "beta", "the bye reaches the room");

    // Join and leave inside a third peer's census window: the census must
    // not resurrect the departed member.
    const late = adapter([relay.url], "room-d", "delta", { windowMs: 400 });
    const ghost = adapter([relay.url], "room-d", "ghost");
    await settle(100);
    ghost.leave();
    is(
      (await late.roster()).includes("ghost"),
      false,
      "a peer that left during the census is not in the roster",
    );

    alpha.leave();
    late.leave();
  });

  await test("two relays carrying the same event deliver it once", async (relay) => {
    const second = await startRelayStub();
    const urls = [relay.url, second.url];

    const alpha = adapter(urls, "room-e", "alpha");
    await alpha.roster();
    const beta = adapter(urls, "room-e", "beta");
    await beta.roster();

    alpha.send("beta", new Offer("v=0 dedupe"));
    await beta.next("message");
    await settle(150);
    is(
      alpha.signals.filter((signal) => signal.kind === "peerJoined").length,
      1,
      "one hello over two relays is one announcement",
    );
    is(
      beta.signals.filter((signal) => signal.kind === "message").length,
      1,
      "one offer over two relays is one message",
    );

    alpha.leave();
    beta.leave();
    await second.close();
  });

  await test("a relay that goes away is reported once, after join returned", async () => {
    // Port 1 on loopback: nothing listens there. The socket constructs, so
    // `join` succeeds; the connection fails a moment later, which is
    // exactly the case a synchronous `join` cannot report.
    const peer = adapter(["ws://127.0.0.1:1/"], "room-f", "alpha");
    is(peer.joined, true, "join returned a session");
    const failure = await peer.failure();
    is(failure.length > 0, true, "the failure is described: " + failure);
    is(
      peer.signals.filter((signal) => signal.kind === "failed").length,
      1,
      "the transport is told once, so a waiting document is answered",
    );
    is(peer.failures.length, 1, "and the application once");
    peer.leave();
  });

  await test("a relay that accepts a socket and says nothing ends the wait", async () => {
    const silent = await startRelayStub({ silent: true });
    const peer = adapter([silent.url], "room-g", "alpha", {
      windowMs: 300,
      timeoutMs: 200,
    });
    const failure = await peer.failure();
    is(
      failure.includes("no relay acknowledged"),
      true,
      "the backstop is reported: " + failure,
    );
    is(
      peer.signals.filter((signal) => signal.kind === "roster").length,
      0,
      "no census was taken on an unacknowledged subscription",
    );
    peer.leave();
    await silent.close();
  });

  console.log("");
  if (failures.length === 0) {
    console.log("nostr signaling adapter: PASS — " + checks + " checks");
    return 0;
  }
  console.log("nostr signaling adapter: FAIL");
  for (const failure of failures) console.log("  " + failure);
  return 1;
}

// ── the relay stub ──────────────────────────────────────────────────────────

// Just enough NIP-01: subscriptions filtered by `#t`, events broadcast to
// every matching subscription including the sender's, every event recorded
// for the privacy assertions. `silent` accepts sockets and answers nothing.
async function startRelayStub({ silent = false } = {}) {
  const server = new WebSocketServer({ port: 0, host: "127.0.0.1" });
  await new Promise((ready) => server.once("listening", ready));
  const clients = new Set();
  const events = [];

  server.on("connection", (socket) => {
    const client = { socket, subscriptions: new Map() };
    clients.add(client);
    socket.on("message", (data) => {
      if (silent) return;
      let message;
      try {
        message = JSON.parse(String(data));
      } catch {
        return;
      }
      if (!Array.isArray(message)) return;
      if (message[0] === "REQ") {
        client.subscriptions.set(message[1], message[2]?.["#t"] ?? []);
        socket.send(JSON.stringify(["EOSE", message[1]]));
      } else if (message[0] === "EVENT") {
        const event = message[1];
        events.push(event);
        socket.send(JSON.stringify(["OK", event.id, true, ""]));
        const topic = (event.tags.find((tag) => tag[0] === "t") ?? [])[1];
        for (const receiver of clients) {
          for (const [id, topics] of receiver.subscriptions) {
            if (topics.includes(topic)) {
              receiver.socket.send(JSON.stringify(["EVENT", id, event]));
            }
          }
        }
      } else if (message[0] === "CLOSE") {
        client.subscriptions.delete(message[1]);
      }
    });
    socket.on("close", () => clients.delete(client));
  });

  return {
    url: "ws://127.0.0.1:" + server.address().port + "/",
    events,
    // Terminate stragglers: a test that failed before its adapters left
    // must not hang the suite on `server.close` waiting for them.
    close: () =>
      new Promise((done) => {
        for (const client of clients) client.socket.terminate();
        server.close(done);
      }),
  };
}

// ── harness ─────────────────────────────────────────────────────────────────

// One adapter, joined, with every signal it handed the transport recorded.
// The adapter is a Gleam record of three closures; this calls them exactly
// as `p2p_transport_js.start` does.
function adapter(urls, room, id, { windowMs = 300, timeoutMs = 2_000 } = {}) {
  const peer = { signals: [], failures: [], joined: false, session: null };
  const signaling = nostrSignalingWithTiming(
    toList(urls),
    (detail) => peer.failures.push(detail),
    windowMs,
    timeoutMs,
  );
  const result = signaling.join(room, id, (signal) =>
    peer.signals.push(readSignal(signal)),
  );
  peer.joined = result.isOk();
  peer.session = peer.joined ? result[0] : null;
  peer.send = (to, payload) => signaling.send(peer.session, to, payload);
  peer.leave = () => {
    if (peer.session) signaling.leave(peer.session);
  };
  peer.roster = async () =>
    (await waitForSignal(peer, "roster")).peers.sort().join(",");
  peer.next = (kind) => waitForSignal(peer, kind);
  peer.failure = async () => {
    const deadline = Date.now() + 3_000;
    while (Date.now() < deadline) {
      if (peer.failures.length > 0) return peer.failures[0];
      await settle(10);
    }
    throw new Error("no failure was reported");
  };
  return peer;
}

// A `p2p_transport_js.Signal` as plain data; the payload flattened to one
// comparable string.
function readSignal(signal) {
  const kind = signal.constructor.name;
  if (kind === "Roster") return { kind: "roster", peers: signal.peers.toArray() };
  if (kind === "PeerJoined") return { kind: "peerJoined", peer: signal.peer_id };
  if (kind === "PeerLeft") return { kind: "peerLeft", peer: signal.peer_id };
  if (kind === "Failed") return { kind: "failed", detail: signal.detail };
  const payload = signal.payload;
  const tag = payload.constructor.name.toLowerCase();
  return {
    kind: "message",
    from: signal.from,
    payload: tag + ":" + (tag === "candidate" ? payload.candidate : payload.sdp),
  };
}

async function waitForSignal(peer, kind) {
  peer.consumed = peer.consumed ?? new Set();
  const deadline = Date.now() + 3_000;
  while (Date.now() < deadline) {
    for (let index = 0; index < peer.signals.length; index++) {
      if (peer.signals[index].kind === kind && !peer.consumed.has(index)) {
        peer.consumed.add(index);
        return peer.signals[index];
      }
    }
    await settle(10);
  }
  throw new Error(
    "no `" + kind + "` signal arrived; saw " + JSON.stringify(peer.signals),
  );
}

// One relay stub per test, so its recorded events are that test's alone.
async function test(name, body) {
  const relay = await startRelayStub();
  const before = failures.length;
  try {
    await body(relay);
  } catch (error) {
    failures.push(name + ": threw " + (error && error.message ? error.message : error));
  } finally {
    await relay.close();
  }
  console.log((failures.length === before ? "  ok  " : "  FAIL") + " " + name);
}

function settle(ms) {
  return new Promise((done) => setTimeout(done, ms));
}

function is(actual, expected, what) {
  checks += 1;
  if (actual !== expected) {
    failures.push(what + ": expected " + expected + ", got " + actual);
  }
}
