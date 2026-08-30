// The reference `crdt_relay_v1` service for watershed's p2p mode.
//
// A relay is a durable fan-out point for CRDT documents. It is *not* a
// sequencer for them: it stamps a diagnostic order, keeps a log it can
// replay, broadcasts what it accepts, and answers a `stateRequest` from what
// it holds. It never merges, never decides which of two replicas is right,
// and never looks inside a kernel payload.
//
// This is a reference, not a deployment. Admission is the bounded example
// rule set the protocol module defines — a well-formed `hello`, a room name
// within limits, a session that is not already attached, and a per-room
// client cap — with no tokens, no tenants, and no clustering. Floodgate
// implements the same lane on its own terms; what it has to match is
// `src/watershed/crdt_relay.gleam`, which is the protocol both sides share,
// and `docs/crdt-relay-v1.md`, which writes it down. Nothing in this
// repository claims to have changed Floodgate.
//
// ## Why it cannot see a document
//
// Every decision about what a frame is, and where it may go, is made by
// `watershed/crdt_relay` — the same pure Gleam module the browser client
// speaks. That module reads an envelope's preamble (protocol version, room,
// sender, session, and the message's `type` tag) and nothing else: the
// message body is carried as an opaque string from the socket it arrived on
// to the sockets and the log line it leaves by, byte for byte. So this file
// never parses application data, never logs a payload's contents, and never
// holds a decoded one.
//
// ## Durability
//
// One append-only JSONL file per room, under a caller-supplied data
// directory. Every accepted state, channel announcement and delta is a line;
// a client's attested digest is a line. Compaction replaces the file with the
// attested checkpoint *and* every record the attesting client reported it
// could not read — written to a temporary file and renamed, so the old log is
// only unlinked once the new one is durable, and only after the append that
// carried that checkpoint has already been flushed. A checkpoint therefore
// never shortens a room's history: it replaces what the publisher merged with
// the merge, and carries everything else forward for a client that can read
// it.
//
// A restart reads every file back and replays it, which is what makes a
// relay outage a merge rather than a data loss. A crash during an append
// leaves a torn *trailing* fragment, and only that is repaired: an
// unreadable line anywhere else is corruption of a record this process
// already accepted and acknowledged, and it is surfaced — a refusal to
// start, or a quarantined file — rather than quietly dropped.
//
// ## Backpressure
//
// A socket that is not draining is bounded: if a frame would push its
// buffered bytes past `MAX_BUFFERED_BYTES` the connection is dropped as a
// slow consumer, during a replay burst as well as an ordinary broadcast.
// A relay that let one stalled reader queue a room's whole history in
// memory would be one client away from an outage.
//
// ## One writer per data directory
//
// A room's log is a file, and two processes writing it are two processes
// each compacting from a room state the other one has already moved on
// from — or two services started from the same systemd unit — are
// enough to lose records that both of them believe they wrote. So a
// *writing* store takes an exclusive lock on the data directory:
// `relay.lock`, created with `mkdir`, which is atomic on every
// filesystem worth running this on, holding an `owner.json` that names
// the pid, the host, when it was taken, and what for.
//
// The lock is released on an orderly close and on the CLI's signal
// handlers, and a lock left behind by a crash is recovered *only* when
// its owner is demonstrably dead: same host, and a pid that `kill(pid,
// 0)` reports as gone. Anything else — a live pid, a pid this user may
// not signal, another host, a missing or unreadable owner file, a lock
// being written right now — is ambiguous, and an ambiguous lock is never
// taken. A refused acquisition writes nothing at all.
//
// `--inspect` is the one thing that runs beside a live service, and it
// runs **read-only**: no lock, no torn-tail repair, no corrupt-file
// quarantine. It reports what is on disk and changes none of it.
//
// ## Running it
//
//     gleam build --target javascript
//     node tools/relay/server.mjs --port 4500 --data ./relay-data
//
// Operator inspection, which is read-only and safe beside a running
// service:
//
//     node tools/relay/server.mjs --data ./relay-data --inspect

import {
  appendFileSync,
  closeSync,
  existsSync,
  fsyncSync,
  mkdirSync,
  openSync,
  readdirSync,
  readFileSync,
  renameSync,
  rmdirSync,
  rmSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { hostname } from "node:os";
import { join } from "node:path";
import { parseArgs } from "node:util";

import { WebSocketServer } from "ws";

import { toList } from "../../build/dev/javascript/prelude.mjs";
import {
  capability as CAPABILITY,
  max_frame_bytes as maxFrameBytes,
  max_room_clients as MAX_ROOM_CLIENTS,
  new_relay as newRelay,
  connect as relayConnect,
  disconnect as relayDisconnect,
  serve,
  replay,
  render_sockets as renderSockets,
  render_storage as renderStorage,
  string_to_record as stringToRecord,
  attested_digest as attestedDigest,
  carried_orders as carriedOrders,
  checkpoint_order as checkpointOrder,
  clients as relayClients,
  log_size as logSize,
  max_room_records as MAX_ROOM_RECORDS,
  checkpoint_pressure_records as CHECKPOINT_PRESSURE_RECORDS,
  checkpoint_requests as checkpointRequests,
  checkpoints_pending as checkpointsPending,
  next_order as nextOrder,
  room_names as roomNames,
  sessions as roomSessions,
} from "../../build/dev/javascript/watershed/watershed/crdt_relay.mjs";

export const MAX_FRAME_BYTES = maxFrameBytes();
export {
  CAPABILITY,
  MAX_ROOM_CLIENTS,
  MAX_ROOM_RECORDS,
  CHECKPOINT_PRESSURE_RECORDS,
};

// How much a socket may have queued and not yet flushed before it is treated
// as a slow consumer. Sixteen frames: enough that an ordinary replay burst
// never trips it, small enough that one stalled reader cannot hold a room's
// history in this process's heap.
export const MAX_BUFFERED_BYTES = 16 * MAX_FRAME_BYTES;

// A log line that is neither complete nor the torn tail of a crashed append
// is corruption of a record this service already acknowledged. `fail` is the
// default because a relay that silently starts without it has quietly
// rewritten history; `quarantine` moves the file aside intact and starts the
// room empty, which is the operable choice when uptime matters more than the
// entries only that file still holds.
const CORRUPTION_POLICIES = ["fail", "quarantine"];

export class CorruptLogError extends Error {
  constructor(file, line, detail) {
    super(
      "watershed relay: " +
        file +
        " is corrupt at line " +
        line +
        " (" +
        detail +
        "). Move or repair the file, or start with --on-corrupt quarantine.",
    );
    this.name = "CorruptLogError";
    this.file = file;
    this.line = line;
  }
}

// A room name is client-supplied and bounded at 128 bytes, but it is still a
// string of anything; base64url makes it a filename without inventing an
// escaping rule of our own, and without two rooms sharing a file.
function roomFile(dataDir, room) {
  return join(
    dataDir,
    Buffer.from(room, "utf8").toString("base64url") + ".jsonl",
  );
}

function flushFile(file) {
  const handle = openSync(file, "r");
  try {
    fsyncSync(handle);
  } finally {
    closeSync(handle);
  }
}

function roomFromFile(name) {
  return Buffer.from(name.replace(/\.jsonl$/, ""), "base64url").toString(
    "utf8",
  );
}

// ── the data directory lock ─────────────────────────────────────────────────
//
// Exactly one process may *write* a data directory at a time. Two writers
// are two room states, each compacting a log from a version of the room the
// other has already moved past, and the loser's records are gone — which is
// the one failure this whole file exists to prevent.

const LOCK_DIR = "relay.lock";
const LOCK_OWNER = "owner.json";

export class RelayLockedError extends Error {
  constructor(dataDir, owner, why) {
    super(
      "watershed relay: " +
        dataDir +
        " is locked by another process (" +
        why +
        (owner
          ? "; owner pid " +
            owner.pid +
            " on " +
            owner.host +
            ", " +
            (owner.purpose ?? "unknown") +
            ", since " +
            (owner.startedAt ?? "unknown")
          : "") +
        "). Stop it, or run with --inspect, which is read-only.",
    );
    this.name = "RelayLockedError";
    this.dataDir = dataDir;
    this.owner = owner ?? null;
  }
}

function lockPath(dataDir) {
  return join(dataDir, LOCK_DIR);
}

// The owner of a lock, or `null` when it cannot be read as one.
//
// `null` is deliberately the answer for every ambiguity — no file, a
// half-written file, a file with no pid, a file from a future version — and
// an ambiguous lock is never recovered. A lock being written by a process
// that is one syscall from owning the directory looks exactly like a lock
// abandoned mid-write, and the safe reading of "I cannot tell" is "not mine".
function readLockOwner(dir) {
  try {
    const owner = JSON.parse(readFileSync(join(dir, LOCK_OWNER), "utf8"));
    if (!Number.isInteger(owner.pid) || owner.pid <= 0) return null;
    if (typeof owner.host !== "string" || owner.host === "") return null;
    return owner;
  } catch {
    return null;
  }
}

// Whether a pid is a process that still exists. `EPERM` is a process this
// user may not signal, which is very much alive; only `ESRCH` — no such
// process — is demonstrably dead.
function pidAlive(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return error.code !== "ESRCH";
  }
}

// Take the directory, or say who has it. Never both, and never neither.
//
// A lock whose owner is demonstrably dead — same host, and a pid that
// `kill(pid, 0)` reports as gone — is removed and the acquisition retried
// exactly once; a second `EEXIST` means somebody else took it in between,
// and they may keep it.
function acquireDataDirLock(dataDir, purpose, stats, retry = true) {
  const dir = lockPath(dataDir);
  try {
    mkdirSync(dir);
  } catch (error) {
    if (error.code !== "EEXIST") throw error;
    const owner = readLockOwner(dir);
    if (owner === null) {
      throw new RelayLockedError(
        dataDir,
        null,
        "its owner file is missing, unreadable, or still being written",
      );
    }
    if (owner.host !== hostname()) {
      throw new RelayLockedError(
        dataDir,
        owner,
        "it was taken on another host, where this process cannot check a pid",
      );
    }
    if (pidAlive(owner.pid)) {
      throw new RelayLockedError(dataDir, owner, "its owner is running");
    }
    if (!retry) {
      throw new RelayLockedError(
        dataDir,
        owner,
        "it could not be taken after recovering a stale one",
      );
    }
    rmSync(dir, { recursive: true, force: true });
    stats.staleLocksRecovered += 1;
    console.error(
      "watershed relay: recovered a stale lock on " +
        dataDir +
        " left by pid " +
        owner.pid +
        ", which is no longer running",
    );
    return acquireDataDirLock(dataDir, purpose, stats, false);
  }
  const owner = {
    pid: process.pid,
    host: hostname(),
    purpose,
    startedAt: new Date().toISOString(),
  };
  const file = join(dir, LOCK_OWNER);
  writeFileSync(file, JSON.stringify(owner) + "\n");
  flushFile(file);

  let released = false;
  // Unconditional removal is safe: a lock is only ever recovered from a
  // dead pid, so nobody can have taken this one while its owner is alive
  // to release it.
  const release = () => {
    if (released) return;
    released = true;
    process.removeListener("exit", release);
    try {
      unlinkSync(file);
    } catch {
      // already gone
    }
    try {
      rmdirSync(dir);
    } catch {
      // already gone, or something else is in it
    }
  };
  process.on("exit", release);
  return { dir, owner, release };
}

// The durable half of a relay, with no socket anywhere near it.
//
// A log per room, the recovery that reads them back, and the operator
// views over them. A relay service is this plus `ws`; `--inspect` is this
// *without* `ws`, which is the whole point of it being separable: an
// operator reading a data directory should not have to open a port to do
// it.
//
// **A writing store owns its data directory exclusively.** It takes
// `relay.lock` before it reads a single log, and it refuses to open at all
// if another live process holds it. `close()` gives it back.
//
// `readOnly: true` is the exception, and it earns it by touching nothing:
// no lock, no torn-tail repair, no corrupt-file quarantine, no storage
// actions. That is what `--inspect` uses, so an operator can look at a
// directory a service is serving without either of them changing what the
// other sees.
export function openRelayStore({
  dataDir,
  onCorruptLog = "fail",
  readOnly = false,
  purpose = readOnly ? "inspect" : "store",
} = {}) {
  if (!dataDir) throw new Error("openRelayStore needs a dataDir");
  if (!CORRUPTION_POLICIES.includes(onCorruptLog)) {
    throw new Error(
      "openRelayStore: onCorruptLog must be one of " +
        CORRUPTION_POLICIES.join(", "),
    );
  }

  let relay = newRelay();

  const stats = {
    socketsOpened: 0,
    socketsClosed: 0,
    framesByTag: Object.create(null),
    oversizeFrames: 0,
    nonTextFrames: 0,
    appends: 0,
    compactions: 0,
    roomsRecovered: 0,
    repairedLogs: 0,
    quarantinedLogs: 0,
    slowConsumers: 0,
    staleLocksRecovered: 0,
    // Lines a read-only inspection could not parse. It never repairs one:
    // saying so is the whole of what it may do about them.
    unreadableLines: 0,
  };

  // A writing store creates the directory it is going to own. A read-only
  // one does not: creating a directory is a write, and a store that promised
  // to touch nothing has to mean it.
  if (!readOnly) mkdirSync(dataDir, { recursive: true });
  const present = existsSync(dataDir);

  // Before anything is read, and long before anything is written.
  const lock = readOnly
    ? null
    : acquireDataDirLock(dataDir, purpose, stats);

  // Every complete, readable line of a log.
  //
  // A crash during an append leaves a fragment with no newline. Skipping it
  // is not enough on its own: the next append would be concatenated onto it,
  // which would make *two* records unreadable instead of one — and the
  // second of them is one this process is about to accept and acknowledge.
  // So a torn tail is truncated here, and that is the only thing that is.
  //
  // An unreadable line anywhere else is not a torn write. It is a record
  // that was complete when it was acknowledged, so dropping it would be this
  // service quietly deciding what a client's durable history says. Instead
  // the start fails, or — under `--on-corrupt quarantine` — the file is
  // moved aside whole and the room starts empty, which returns `null`.
  //
  // A read-only store does none of that. It holds no lock, so the file it is
  // reading may be being appended to right now: a torn tail is somebody
  // else's append in progress rather than a crash, and repairing it would be
  // this process truncating a log it does not own. It reads what parses,
  // counts what does not, and writes nothing.
  function healed(file, room) {
    const raw = readFileSync(file, "utf8");
    if (raw === "") return [];
    const rows = raw.split("\n");
    const tail = rows.pop();
    const torn = tail !== "";
    const whole = rows.filter((line) => line !== "");
    if (readOnly) {
      const readable = whole.filter((line) => stringToRecord(line).isOk());
      stats.unreadableLines += whole.length - readable.length;
      if (torn && stringToRecord(tail).isOk()) readable.push(tail);
      return readable;
    }
    for (const [index, line] of whole.entries()) {
      if (stringToRecord(line).isOk()) continue;
      if (onCorruptLog === "fail") {
        throw new CorruptLogError(file, index + 1, "unreadable record");
      }
      const aside = file + ".corrupt-" + Date.now();
      renameSync(file, aside);
      stats.quarantinedLogs += 1;
      console.error(
        "watershed relay: room " +
          JSON.stringify(room) +
          " has a corrupt log; moved to " +
          aside +
          " and started empty",
      );
      return null;
    }
    // A tail that happens to be complete is kept; one that is not is the
    // half-written frame the crash interrupted.
    if (torn && stringToRecord(tail).isOk()) whole.push(tail);
    if (torn) {
      const staging = file + ".tmp";
      writeFileSync(staging, whole.map((line) => line + "\n").join(""));
      flushFile(staging);
      renameSync(staging, file);
      stats.repairedLogs += 1;
    }
    return whole;
  }

  // Recover before anything else happens, so a client that connects
  // immediately after a restart is answered from the log rather than from an
  // empty room it would then be asked to fill.
  //
  // A recovery that refuses — a corrupt log under `--on-corrupt fail` — must
  // give the directory back on the way out. A store that threw while holding
  // the lock would leave a live pid owning a directory nothing is serving,
  // which is precisely the ambiguity a lock may never create.
  try {
    // A crash between `writeFileSync(staging)` and the rename that
    // publishes it leaves an `X.jsonl.tmp` behind forever; the log it was
    // going to replace is intact, so the staging file is garbage. Swept
    // before the replay loop, which may write staging files of its own.
    if (!readOnly && present) {
      for (const name of readdirSync(dataDir)) {
        if (name.endsWith(".tmp")) rmSync(join(dataDir, name), { force: true });
      }
    }
    for (const name of present ? readdirSync(dataDir) : []) {
      if (!name.endsWith(".jsonl")) continue;
      const room = roomFromFile(name);
      const lines = healed(join(dataDir, name), room);
      if (lines === null) continue;
      relay = replay(relay, room, toList(lines));
      stats.roomsRecovered += 1;
    }
  } catch (error) {
    if (lock !== null) lock.release();
    throw error;
  }

  function appendLines(room, rows) {
    const file = roomFile(dataDir, room);
    appendFileSync(file, rows.map((line) => line + "\n").join(""));
    flushFile(file);
    stats.appends += rows.length;
  }

  // Write the replacement beside the log and rename over it. The checkpoint
  // it keeps was already appended and flushed, so the older log is only ever
  // unlinked once a later canonical state is durable in two places — and the
  // rows it is handed already carry every record that checkpoint did not
  // subsume, so this can never be the step that loses one.
  function compact(room, rows) {
    const file = roomFile(dataDir, room);
    const staging = file + ".tmp";
    writeFileSync(staging, rows.map((line) => line + "\n").join(""));
    flushFile(staging);
    renameSync(staging, file);
    stats.compactions += 1;
  }

  function logLines(room) {
    const file = roomFile(dataDir, room);
    if (!existsSync(file)) return [];
    return readFileSync(file, "utf8")
      .split("\n")
      .filter((line) => line !== "");
  }

  // Perform the storage half of a protocol action list, in order.
  //
  // Order is the whole guarantee here: the append that carries a checkpoint
  // is always flushed before the compaction that keeps it, so a crash in
  // between leaves a record in two places rather than in none.
  function storage(actions) {
    if (readOnly) {
      throw new Error(
        "watershed relay: this store is read-only and owns no lock on " +
          dataDir +
          "; it cannot perform storage actions",
      );
    }
    for (const [room, mode, lines] of renderStorage(actions).toArray()) {
      const rows = lines.toArray();
      if (mode === "append") appendLines(room, rows);
      else compact(room, rows);
    }
  }

  return {
    dataDir,
    corruptionPolicy: onCorruptLog,
    capability: CAPABILITY,
    recordLimit: MAX_ROOM_RECORDS,
    checkpointPressure: CHECKPOINT_PRESSURE_RECORDS,
    readOnly,
    // Who owns the directory, as this process wrote it: `null` for a
    // read-only store, which owns nothing and locks nothing.
    owner: () => (lock === null ? null : { ...lock.owner }),
    read: () => relay,
    write: (next) => {
      relay = next;
    },
    storage,
    counters: stats,
    stats: () => ({
      ...stats,
      framesByTag: { ...stats.framesByTag },
      rooms: roomNames(relay).toArray().length,
      checkpointRequests: roomNames(relay)
        .toArray()
        .reduce((total, room) => total + checkpointRequests(relay, room), 0),
    }),
    rooms: () => roomNames(relay).toArray(),
    sessions: (room) => roomSessions(relay, room).toArray(),
    logSize: (room) => logSize(relay, room),
    nextOrder: (room) => nextOrder(relay, room),
    attested: (room) => attestedDigest(relay, room),
    checkpointOrder: (room) => checkpointOrder(relay, room),
    checkpointRequests: (room) => checkpointRequests(relay, room),
    checkpointsPending: (room) => checkpointsPending(relay, room).toArray(),
    // What the room is still replaying because a client said it could not
    // read it — and `null` when there is no client attached to say.
    //
    // Carriage is a fact about *live claims*, so a store with nobody
    // connected to it does not know one: reporting `[]` there would be this
    // process claiming a room carries nothing when what it means is that
    // nobody has told it anything. An offline inspection says `unknown`.
    carried: (room) =>
      relayClients(relay, room).toArray().length === 0
        ? null
        : carriedOrders(relay, room).toArray(),
    // The durable lines, read back off disk rather than out of memory: what a
    // restart would see, which is the only version worth asserting on.
    lines: logLines,
    // Give the directory back. Idempotent, and safe to call on a read-only
    // store, which never took it.
    close: () => {
      if (lock !== null) lock.release();
    },
  };
}

// Start a relay. Returns the bound port, a stats snapshot, a few durable-state
// views for tests, and a close that resolves when the port is free.
//
// `dataDir` is required and is created if missing: a relay with nowhere to
// write is a hub, and calling it a relay would be a lie a restart test would
// find out about the hard way.
export function startRelayServer({
  port = 0,
  host = "127.0.0.1",
  dataDir,
  maxBufferedBytes = MAX_BUFFERED_BYTES,
  onCorruptLog = "fail",
} = {}) {
  if (!dataDir) throw new Error("startRelayServer needs a dataDir");

  // Everything durable lives in the store, which knows nothing about sockets
  // and is what an operator uses on its own. This is only the socket half.
  //
  // The store takes the data directory's lock as it opens, so a service
  // started against a directory another process is writing throws here,
  // before a port is bound and before a byte is written.
  const store = openRelayStore({ dataDir, onCorruptLog, purpose: "serve" });
  const stats = store.counters;
  const sockets = new Map(); // connection id -> ws
  let nextConnection = 1;

  let server;
  try {
    server = new WebSocketServer({
      port,
      host,
      // The protocol's own frame cap, enforced by the socket layer as well as
      // by the decoder: an oversize frame is dropped before it is a string,
      // so a flood cannot be paid for in `JSON.parse`.
      maxPayload: MAX_FRAME_BYTES,
    });
  } catch (error) {
    // No sockets, no lock: a service that cannot listen owns nothing.
    store.close();
    throw error;
  }

  server.on("connection", (socket) => {
    const connection = nextConnection++;
    sockets.set(connection, socket);
    stats.socketsOpened += 1;

    // The relay speaks first: capability negotiation is finished before the
    // client has said anything at all.
    const [next, actions] = relayConnect(store.read(), connection);
    store.write(next);
    perform(actions);

    socket.on("message", (data, isBinary) => {
      if (isBinary) {
        stats.nonTextFrames += 1;
        writeRefusal(connection, "binaryFrame", "relay frames are text");
        return;
      }
      run(connection, data.toString());
    });

    socket.on("close", () => {
      sockets.delete(connection);
      stats.socketsClosed += 1;
      const [next, actions] = relayDisconnect(store.read(), connection);
      store.write(next);
      perform(actions);
    });

    // A socket-level error is not routed anywhere; the `close` that follows
    // does the bookkeeping. The one error worth counting is `ws` rejecting a
    // frame over `maxPayload` — it closes the socket with 1009 before the
    // payload is ever a string, and a test needs to tell that from a
    // malformed frame.
    socket.on("error", (error) => {
      if (error && error.code === "WS_ERR_UNSUPPORTED_MESSAGE_LENGTH") {
        stats.oversizeFrames += 1;
      }
    });
  });

  function run(connection, raw) {
    const [next, actions, tag] = serve(store.read(), connection, raw);
    store.write(next);
    stats.framesByTag[tag] = (stats.framesByTag[tag] ?? 0) + 1;
    perform(actions);
  }

  // Storage first, then sockets. A client that has been told its state is
  // durable must not be able to observe that before it is.
  function perform(actions) {
    store.storage(actions);
    for (const [connection, payload, closeReason] of renderSockets(
      actions,
    ).toArray()) {
      const socket = sockets.get(connection);
      if (!socket) continue;
      if (payload !== "" && socket.readyState === socket.OPEN) {
        if (!writable(connection, socket, payload)) continue;
        socket.send(payload);
      }
      if (closeReason !== "") {
        // 1008 "policy violation": the frame was well-formed WebSocket and
        // unacceptable relay traffic.
        socket.close(1008, closeReason.slice(0, 120));
      }
    }
  }

  // Whether this frame may be queued for this socket.
  //
  // A reader that has stopped draining is dropped rather than buffered: one
  // stalled client must not be able to hold a room's replay in this
  // process's memory, and the frames it has already been sent are exactly
  // the ones it can no longer attest to anyway. 1013 "try again later": the
  // traffic was legal and the connection was not keeping up.
  function writable(connection, socket, payload) {
    const queued = socket.bufferedAmount + Buffer.byteLength(payload, "utf8");
    if (queued <= maxBufferedBytes) return true;
    stats.slowConsumers += 1;
    sockets.delete(connection);
    const [next, actions] = relayDisconnect(store.read(), connection);
    store.write(next);
    socket.close(1013, "slowConsumer");
    perform(actions);
    return false;
  }

  function writeRefusal(connection, reason, detail) {
    const socket = sockets.get(connection);
    if (!socket) return;
    if (socket.readyState === socket.OPEN) {
      socket.send(JSON.stringify({ type: "error", reason, detail }));
    }
    socket.close(1008, reason);
  }

  const listening = new Promise((ready, failed) => {
    server.once("listening", () => ready(server.address().port));
    server.once("error", (error) => {
      // A port that could not be bound is a service that never ran, and it
      // must not go on owning the data directory.
      store.close();
      failed(error);
    });
  });

  return {
    listening,
    dataDir,
    port: () => server.address()?.port ?? null,
    capability: CAPABILITY,
    frameLimit: MAX_FRAME_BYTES,
    clientLimit: MAX_ROOM_CLIENTS,
    bufferLimit: maxBufferedBytes,
    recordLimit: MAX_ROOM_RECORDS,
    checkpointPressure: CHECKPOINT_PRESSURE_RECORDS,
    corruptionPolicy: onCorruptLog,
    owner: store.owner,
    stats: store.stats,
    rooms: store.rooms,
    sessions: store.sessions,
    logSize: store.logSize,
    nextOrder: store.nextOrder,
    attested: store.attested,
    checkpointOrder: store.checkpointOrder,
    checkpointRequests: store.checkpointRequests,
    checkpointsPending: store.checkpointsPending,
    // Operator inspection. `carried` is what the room is still replaying
    // because an attached client said it could not merge it, and is `null`
    // when no client is attached to claim anything.
    carried: store.carried,
    lines: store.lines,
    close: () =>
      new Promise((done) => {
        for (const socket of sockets.values()) socket.terminate();
        server.close(() => {
          // The port first, then the directory: a successor started the
          // moment this resolves finds neither taken.
          store.close();
          done();
        });
      }),
  };
}

// ── CLI ──────────────────────────────────────────────────────────────────────

const invokedDirectly =
  process.argv[1] && import.meta.url === new URL(process.argv[1], "file:").href;

if (invokedDirectly) {
  const { values: args } = parseArgs({
    args: process.argv.slice(2),
    options: {
      port: { type: "string", default: "4500" },
      host: { type: "string", default: "127.0.0.1" },
      data: { type: "string", default: "./relay-data" },
      "on-corrupt": { type: "string", default: "fail" },
      inspect: { type: "boolean", default: false },
    },
  });
  const port = Number(args.port);
  const host = args.host;
  const dataDir = args.data;
  const onCorruptLog = args["on-corrupt"];

  // The operator command. It binds no port and accepts no socket, and it is
  // **read-only**: it takes no lock, repairs nothing, and can be run beside
  // a live service.
  if (args.inspect) {
    const offline = openRelayStore({
      dataDir,
      onCorruptLog,
      readOnly: true,
      purpose: "inspect",
    });
    try {
      for (const room of offline.rooms()) {
        const carried = offline.carried(room);
        console.log(
          "watershed relay: " +
            JSON.stringify(room) +
            " log " +
            offline.logSize(room) +
            ", checkpoint " +
            (offline.checkpointOrder(room) || "none") +
            // Carriage is what *attached clients* have claimed they cannot
            // read, and an offline inspection has no attached clients. Saying
            // `[]` here would read as "this room carries nothing"; what is
            // true is that nobody is connected to say.
            ", carried " +
            (carried === null
              ? "unknown (no client is attached to claim one)"
              : JSON.stringify(carried)),
        );
      }
    } finally {
      offline.close();
    }
    process.exit(0);
  }

  let service;
  try {
    service = startRelayServer({ port, host, dataDir, onCorruptLog });
  } catch (error) {
    if (error instanceof RelayLockedError) {
      console.error(error.message);
      process.exit(2);
    }
    throw error;
  }
  const bound = await service.listening;
  console.log(
    "watershed relay: ws://" +
      host +
      ":" +
      bound +
      "  (" +
      CAPABILITY +
      ", rooms cap " +
      MAX_ROOM_CLIENTS +
      " clients, frames cap " +
      MAX_FRAME_BYTES +
      " bytes, socket buffer cap " +
      MAX_BUFFERED_BYTES +
      " bytes, room log cap " +
      MAX_ROOM_RECORDS +
      " records asking for a checkpoint at " +
      CHECKPOINT_PRESSURE_RECORDS +
      ", data " +
      dataDir +
      " (locked by pid " +
      process.pid +
      "), corrupt logs " +
      onCorruptLog +
      ")",
  );
  console.log(
    "watershed relay: this process fans out and persists opaque CRDT " +
      "envelopes — it merges nothing and decodes no kernel payload.",
  );

  // An orderly stop gives the data directory back, so the next process to
  // open it finds no lock rather than a stale one to reason about.
  for (const signal of ["SIGINT", "SIGTERM", "SIGHUP"]) {
    process.on(signal, async () => {
      console.log("watershed relay: " + JSON.stringify(service.stats()));
      await service.close();
      process.exit(0);
    });
  }
}
