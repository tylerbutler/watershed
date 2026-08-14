// The reference WebSocket signaling service for watershed's p2p mode.
//
// It introduces peers to each other and carries three kinds of opaque WebRTC
// blob between them. That is the whole of it. It is a *reference*: it has no
// authentication beyond a room name and a peer id, no persistence, and no
// clustering, and it is here so the p2p example has something to point at,
// not so it can be deployed.
//
// ## Why it cannot see a document
//
// Every decision about what a frame is, and where it may go, is made by
// `watershed/crdt_signaling` — the same pure Gleam module the browser adapter
// speaks. Its client vocabulary has exactly three constructors (`join`,
// `signal`, `leave`) and the only payload it admits is the transport's own
// closed signal sum: an offer, an answer, or an ICE candidate. There is no
// frame shape that can carry a `crdt_wire` envelope, so this process cannot
// route a document delta however it is driven. A peer that sends one gets a
// `rejected` frame and a closed socket.
//
// This file therefore never parses application data, never logs a payload,
// and never holds one: `serve` hands back an already-encoded string and the
// connection to write it to, and that string is passed through untouched.
//
// ## Instrumentation
//
// `stats()` counts frames by the tag `serve` classified them as — `join`,
// `signal`, `leave`, `rejected:<reason>`, or `dropped:<reason>` — plus
// sockets opened and closed. The tags come from the frame's *type*, never
// its contents. A deployment that wants to prove no document data reached it
// asserts that every rejected counter is zero. `dropped:` is separate on
// purpose: the one refusal that leaves a connection open is a signal
// addressed to a peer that had just left, which is a race, not a fault.
//
// ## Running it
//
//     gleam build --target javascript      # builds the protocol module
//     node tools/signaling/server.mjs --port 4400
//
// or import `startSignalingServer` and drive it from a test.

import { WebSocketServer } from "ws";

import {
  max_frame_bytes as MAX_FRAME_BYTES,
  new_rooms as newRooms,
  disconnect,
  members,
  room_limit as roomLimit,
  room_names as roomNames,
  render_actions as renderActions,
  serve,
} from "../../build/dev/javascript/watershed/watershed/crdt_signaling.mjs";

export { MAX_FRAME_BYTES };

// Start a service. Returns the bound port, a stats snapshot function, a
// membership view for tests, and a close that resolves when the port is free.
export function startSignalingServer({ port = 0, host = "127.0.0.1" } = {}) {
  let rooms = newRooms();
  const sockets = new Map(); // connection id -> ws
  let nextConnection = 1;

  const stats = {
    socketsOpened: 0,
    socketsClosed: 0,
    framesByTag: Object.create(null),
    oversizeFrames: 0,
    nonTextFrames: 0,
  };

  const server = new WebSocketServer({
    port,
    host,
    // The protocol's own frame cap, enforced by the socket layer as well as
    // by the decoder: an oversize frame is dropped before it is a string,
    // so a flood cannot be paid for in `JSON.parse`.
    maxPayload: MAX_FRAME_BYTES,
  });

  server.on("connection", (socket) => {
    const connection = nextConnection++;
    sockets.set(connection, socket);
    stats.socketsOpened += 1;

    socket.on("message", (data, isBinary) => {
      if (isBinary) {
        stats.nonTextFrames += 1;
        writeRejection(connection, "binaryFrame", "signaling frames are text");
        return;
      }
      run(connection, data.toString());
    });

    socket.on("close", () => {
      sockets.delete(connection);
      stats.socketsClosed += 1;
      const [next, actions] = disconnect(rooms, connection);
      rooms = next;
      perform(renderActions(actions).toArray());
    });

    // A socket-level error is not routed anywhere; the `close` that follows
    // it does the bookkeeping. The one error worth counting is `ws`
    // rejecting a frame over `maxPayload` — it closes the socket with 1009
    // before the payload is ever a string, and a test needs to tell that
    // from a malformed frame.
    socket.on("error", (error) => {
      if (error && error.code === "WS_ERR_UNSUPPORTED_MESSAGE_LENGTH") {
        stats.oversizeFrames += 1;
      }
    });
  });

  function run(connection, raw) {
    const [next, actions, tag] = serve(rooms, connection, raw);
    rooms = next;
    stats.framesByTag[tag] = (stats.framesByTag[tag] ?? 0) + 1;
    perform(actions.toArray());
  }

  // Each action is `[connection, payload, closeReason]`. A payload is an
  // already-encoded signaling frame; nothing here inspects it.
  function perform(actions) {
    for (const [connection, payload, closeReason] of actions) {
      const socket = sockets.get(connection);
      if (!socket) continue;
      if (payload !== "") {
        if (socket.readyState === socket.OPEN) socket.send(payload);
      }
      if (closeReason !== "") {
        // 1008 "policy violation": the frame was well-formed WebSocket and
        // unacceptable signaling.
        socket.close(1008, closeReason.slice(0, 120));
      }
    }
  }

  function writeRejection(connection, reason, detail) {
    const socket = sockets.get(connection);
    if (!socket) return;
    if (socket.readyState === socket.OPEN) {
      socket.send(JSON.stringify({ t: "error", reason, detail }));
    }
    socket.close(1008, reason);
  }

  const listening = new Promise((ready, failed) => {
    server.once("listening", () => ready(server.address().port));
    server.once("error", failed);
  });

  return {
    listening,
    port: () => server.address()?.port ?? null,
    limit: roomLimit(),
    stats: () => ({
      ...stats,
      framesByTag: { ...stats.framesByTag },
      rooms: roomNames(rooms).toArray().length,
    }),
    members: (room) => members(rooms, room).toArray(),
    roomNames: () => roomNames(rooms).toArray(),
    close: () =>
      new Promise((done) => {
        for (const socket of sockets.values()) socket.terminate();
        server.close(() => done());
      }),
  };
}

// ── CLI ──────────────────────────────────────────────────────────────────────

const invokedDirectly =
  process.argv[1] && import.meta.url === new URL(process.argv[1], "file:").href;

if (invokedDirectly) {
  const portIndex = process.argv.indexOf("--port");
  const port = portIndex === -1 ? 4400 : Number(process.argv[portIndex + 1]);
  const hostIndex = process.argv.indexOf("--host");
  const host = hostIndex === -1 ? "127.0.0.1" : process.argv[hostIndex + 1];

  const service = startSignalingServer({ port, host });
  const bound = await service.listening;
  console.log(
    "watershed signaling: ws://" +
      host +
      ":" +
      bound +
      "  (rooms cap " +
      service.limit +
      " peers, frames cap " +
      MAX_FRAME_BYTES +
      " bytes)",
  );
  console.log(
    "watershed signaling: this process carries offers, answers and ICE " +
      "candidates only — it cannot route document data.",
  );

  for (const signal of ["SIGINT", "SIGTERM"]) {
    process.on(signal, async () => {
      console.log("watershed signaling: " + JSON.stringify(service.stats()));
      await service.close();
      process.exit(0);
    });
  }
}
