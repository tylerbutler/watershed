// Integration tests for the reference `crdt_relay_v1` service.
//
// These drive the real relay over real sockets, with a real signaling
// service alongside it and real `crdt_js` documents on top, because the parts
// worth testing here are the ones the pure protocol cannot cover on its own:
// that state survives a process restart on disk, that an outage's edits merge
// back rather than being lost, that a late client sees everything, and that
// the relay's diagnostic order never reaches a document.
//
// The whole gate is one scenario, run once:
//
//   1. create and edit a room with the relay process absent;
//   2. start the relay; those same replicas attach, merge, become primary,
//      and checkpoint — the edits made while it was gone included;
//   3. stop the relay;
//   4. keep editing, concurrently, over the peer mesh;
//   5. restart the relay from its own data directory;
//   6. recover, merge, and become primary again;
//   7. attach a late client and find every copy equal;
//   8. prove the relay's order never entered a snapshot or a digest;
//   9. prove signaling carried no document frame.
//
// Every relay in here writes to a fresh directory under the system temp
// directory, and every one of them is removed at the end — a log left over
// from a previous run is indistinguishable from the one the test just wrote.
//
// `RTCPeerConnection` is the one thing Node has none of, so peer connections
// come from the deterministic fake the transport tests use. Signaling is the
// real service over a real socket, which is what makes the last assertion a
// claim about the shipped service. The real browser mesh has its own gate:
// `just p2p-clap`.
//
//     gleam test --target javascript
//     node tools/relay/test.mjs

import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { execFileSync, spawn } from "node:child_process";
import { hostname, tmpdir } from "node:os";
import { join } from "node:path";

import WebSocket from "ws";

globalThis.WebSocket = globalThis.WebSocket ?? WebSocket;

import {
  openRelayStore,
  startRelayServer,
  CAPABILITY,
  MAX_BUFFERED_BYTES,
  MAX_FRAME_BYTES,
} from "./server.mjs";
import { startSignalingServer } from "../signaling/server.mjs";
import * as harness from "../../build/dev/javascript/watershed/watershed/relay_integration.mjs";

const failures = [];
let checks = 0;
const scratch = [];

main().then(
  (code) => {
    cleanup();
    process.exit(code);
  },
  (error) => {
    cleanup();
    console.error(error && error.stack ? error.stack : error);
    process.exit(1);
  },
);

async function main() {
  await lifecycle();
  await socketLayer();
  await tornLogs();
  await corruptLogs();
  await slowConsumers();
  await poisonedLogs();
  await dataDirLocks();
  await noSequencedLane();

  console.log("");
  if (failures.length === 0) {
    console.log("relay service: PASS — " + checks + " checks");
    return 0;
  }
  console.log("relay service: FAIL");
  for (const failure of failures) console.log("  " + failure);
  return 1;
}

// ── the gate ────────────────────────────────────────────────────────────────

async function lifecycle() {
  const room = "trip-planning";
  const dataDir = tempDir();
  const signaling = startSignalingServer({});
  await signaling.listening;
  const signalingUrl = "ws://127.0.0.1:" + signaling.port() + "/";

  const world = harness.new_harness();
  const pump = pumping(world);

  // 1. The relay process is absent — configured, and not there. Two
  //    replicas find each other over the mesh, keep trying the relay in the
  //    background, and edit a document no sequencer has ever seen.
  const relayPort = await freePort();
  const relayUrl = "ws://127.0.0.1:" + relayPort + "/";
  const alpha = harness.start(world, "auto", room, "alpha", signalingUrl,
    relayUrl);
  const beta = harness.start(world, "auto", room, "beta", signalingUrl,
    relayUrl);
  await until(() => harness.readiness(alpha).toArray().length === 1,
    "readiness resolved with the relay absent");
  deep(harness.readiness(alpha).toArray(), ["ok"],
    "and it never waited for the relay to resolve it");
  await until(() => harness.peer_count(alpha) === 1, "the mesh formed");
  harness.clap(alpha, 2);
  harness.clap(beta, 3);
  await until(() => harness.value(alpha) === 5 && harness.value(beta) === 5,
    "the replicas converged with the relay process absent");
  is(harness.path(alpha), "p2p", "with no relay answering, the path is the mesh");
  await until(() => harness.saw(alpha, "relayRetry"),
    "and the absent relay was retried rather than given up on");
  const seen = (client, predicate) =>
    harness.statuses(client).toArray().filter(predicate).length;
  await until(
    () => seen(alpha, (entry) => entry === "relayConnecting") >= 2,
    "every attempt reported itself, not only the first",
  );
  const attempts = seen(alpha, (entry) => entry === "relayConnecting");
  const retries = seen(alpha, (entry) => entry.startsWith("relayRetry"));
  is(attempts <= retries + 1 && attempts >= retries, true,
    "one connecting per retry, plus the first: " + attempts + " vs " + retries);

  // 2. The relay starts, on the port they were already pointed at. These
  //    same two replicas — the ones holding edits no sequencer has seen —
  //    reconnect on their own backoff, merge what the relay gives them,
  //    publish the join, and become primary. Nothing is restarted to make
  //    the attachment work.
  let relay = startRelayServer({ dataDir, port: relayPort });
  await relay.listening;

  await until(() => harness.is_primary(alpha) && harness.is_primary(beta),
    "both replicas made the relay primary", 20_000);
  is(harness.path(alpha), "relay", "durable traffic goes to the relay");
  is(harness.path(beta), "relay", "on both replicas");
  is(harness.value(alpha), 5, "the edits made while it was absent are still here");

  // The checkpoint is on disk, and it is the digest the replicas hold.
  await until(() => relay.attested(room) === harness.digest(alpha),
    "the relay's attested digest is the document's own");
  is(relay.logSize(room), 1, "an attested checkpoint collapses the log");
  is(relay.lines(room).length > 0, true, "and the log is on disk");
  is(relay.stats().compactions > 0, true, "compaction ran");

  harness.clap(alpha, 5);
  await until(() => harness.value(beta) === 10, "and a new edit reaches the other");

  const one = alpha;
  const two = beta;
  const replicaOne = harness.replica(one);

  // 3 and 4. The relay dies. Both replicas keep editing, over the mesh,
  //    without pausing and without losing anything.
  await relay.close();
  await until(() => harness.path(one) === "p2p" && harness.path(two) === "p2p",
    "the path fell back to the mesh");
  is(harness.saw(one, "relayFallback"), true, "and the fallback was reported");

  harness.clap(one, 4);
  harness.clap(two, 6);
  await until(() => harness.value(one) === 20 && harness.value(two) === 20,
    "the outage's edits converged over WebRTC");
  is(harness.is_closed(one), false, "the document is still live");
  is(harness.replica(one), replicaOne, "and its replica identity is unchanged");

  // 5 and 6. The relay comes back on the same data directory, replays its
  //    log, merges the outage, and is primary again.
  relay = startRelayServer({ dataDir, port: relayPort });
  await relay.listening;
  is(relay.stats().roomsRecovered, 1, "the relay recovered its room from disk");

  await until(() => harness.is_primary(one) && harness.is_primary(two),
    "the relay became primary again", 20_000);
  is(harness.saw(one, "relayRecovering"), true,
    "and the second attachment reported itself as a recovery");
  await until(() => relay.attested(room) === harness.digest(one),
    "the recovered relay holds exactly what the replicas hold");
  is(harness.value(one), 20, "no edit was lost across the outage");

  // 7. A late client, with no peer at all: everything it knows, it learns
  //    from the relay.
  const late = harness.start(world, "sequencedOnly", room, "late", signalingUrl, relayUrl);
  await until(() => harness.readiness(late).toArray().length === 1,
    "the sequenced-only client resolved readiness");
  deep(harness.readiness(late).toArray(), ["ok"],
    "and it resolved on the relay alone");
  await until(() => harness.value(late) === 20, "the late client has every clap");
  is(harness.peer_count(late), 0, "with no peer connection whatsoever");
  await until(() => harness.digest(late) === harness.digest(one),
    "every copy is equal");
  is(harness.digest(late), harness.digest(two), "every copy is equal");

  // 8. The relay's order never reached a document.
  const snapshot = harness.snapshot(late);
  is(snapshot.includes("\"order\""), false,
    "no relay order appears in an exported snapshot");
  is(snapshot.includes("\"upTo\""), false,
    "and no attestation metadata either");
  is(relay.nextOrder(room) > 1, true, "even though the relay stamped plenty");
  // Two replicas that took different routes to the same state agree on the
  // digest, which they could not if an order had entered it.
  is(harness.digest(late) === harness.digest(one), true,
    "the digest is route-independent");
  // Every durable line carries its order *outside* the envelope it wraps.
  for (const line of relay.lines(room)) {
    const record = JSON.parse(line);
    if (record.e === undefined) continue;
    is(JSON.parse(record.e).message.order, undefined,
      "a logged envelope carries no order");
  }

  // 9. Signaling carried membership and WebRTC blobs, and nothing else.
  const tags = signaling.stats().framesByTag;
  is(Object.keys(tags).every((tag) => ["join", "leave", "signal"].includes(tag)),
    true,
    "signaling saw only join, signal, and leave: " +
      Object.keys(tags).sort().join(","));
  is(Object.keys(tags).some((tag) => tag.startsWith("rejected:")), false,
    "no frame was ever rejected, so no document frame was ever offered");

  harness.close(one);
  harness.close(two);
  harness.close(late);
  await until(() => (signaling.stats().framesByTag.leave ?? 0) >= 1,
    "and a leave when a replica went away");
  pump.stop();
  await relay.close();
  await signaling.close();
}

// ── the socket layer ────────────────────────────────────────────────────────

// Only what a real socket can prove. The protocol's own refusals — admission,
// identity, isolation, the hard bounds and checkpoint pressure — are pinned
// scenario-for-scenario by test/watershed/crdt_relay_test.gleam.
async function socketLayer() {
  const relay = startRelayServer({ dataDir: tempDir() });
  await relay.listening;

  await raw(relay, async (socket) => {
    const greeting = await socket.next();
    is(greeting.type, "connected", "the relay speaks first");
    is(greeting.capabilities[CAPABILITY], true, "advertising its lane");
    is(greeting.limits.envelopeBytes, MAX_FRAME_BYTES,
      "and the frame limit it will enforce");
  });

  // `ws` drops an oversize frame before it is ever a string.
  await raw(relay, async (socket) => {
    await socket.next();
    socket.send("x".repeat(MAX_FRAME_BYTES + 1));
    const code = await socket.closed();
    is(code === 1009 || code === 1008, true,
      "an oversize frame closes the socket: " + code);
    is(relay.stats().oversizeFrames >= 1, true,
      "and is counted before it is a string");
  });

  // A binary frame never reaches the protocol at all.
  await raw(relay, async (socket) => {
    await socket.next();
    socket.send(Buffer.from([1, 2, 3]));
    const refusal = await socket.next();
    is(refusal.reason, "binaryFrame", "a binary frame is refused");
    is(await socket.closed(), 1008, "and the socket is closed");
    is(relay.stats().nonTextFrames >= 1, true, "and counted");
  });

  await relay.close();
}

// ── the legacy lane ─────────────────────────────────────────────────────────

// The relay lane must not be the sequenced DDS lane wearing a hat. This is a
// structural check on the shipped modules: neither the relay protocol, nor
// its client, nor the facade may reach the sequenced runtime, its
// acknowledgement path, its summaries, or its membership.
// A crash during an append leaves a fragment with no newline. Recovery must
// skip it *and* truncate it, or the next record written lands on top of it and
// two records become unreadable instead of one.
async function tornLogs() {
  const dataDir = tempDir();
  const room = "torn-room";
  const file = logFile(dataDir, room);
  const whole = JSON.stringify({ o: 1, k: "traffic", s: "sb", e: "FIRST" });
  const torn = JSON.stringify({ o: 2, k: "traffic", s: "sb", e: "SECOND" });
  writeFileSync(file, whole + "\n" + torn.slice(0, torn.length - 12));
  // A crash between a compaction's staging write and its rename leaves a
  // `.tmp` behind; the log it was going to replace is intact, so a writing
  // store removes the garbage on open.
  writeFileSync(file + ".tmp", "half a compaction");

  let relay = startRelayServer({ dataDir });
  await relay.listening;
  is(existsSync(file + ".tmp"), false, "a stale staging file is removed");
  is(relay.logSize(room), 1, "the torn line is skipped");
  is(relay.stats().repairedLogs, 1, "and the log is repaired rather than left");
  deep(relay.lines(room), [whole], "the file now holds only whole records");

  await raw(relay, async (socket) => {
    await socket.next();
    socket.send(helloFrame(room, "carol", "sc"));
    socket.send(deltaFrame(room, "carol", "sc"));
    await sleep(50);
  });
  is(relay.logSize(room), 2, "a new record is accepted");
  await relay.close();

  const reopened = startRelayServer({ dataDir });
  await reopened.listening;
  is(reopened.logSize(room), 2,
    "and survives the next restart instead of being swallowed by the fragment");
  await reopened.close();
}

// A line that is neither complete nor a torn tail is corruption of a record
// this service already acknowledged. Dropping it silently would be the relay
// deciding what a client's durable history says, so it either refuses to
// start or quarantines the file whole.
async function corruptLogs() {
  const dataDir = tempDir();
  const room = "corrupt-room";
  const file = logFile(dataDir, room);
  const first = JSON.stringify({ o: 1, k: "traffic", s: "sb", e: "FIRST" });
  const third = JSON.stringify({ o: 3, k: "traffic", s: "sb", e: "THIRD" });
  const raw = first + "\n" + "{ this was never a record }" + "\n" + third + "\n";
  writeFileSync(file, raw);

  let refused = null;
  try {
    startRelayServer({ dataDir });
  } catch (error) {
    refused = error;
  }
  is(refused?.name, "CorruptLogError",
    "a mid-file corrupt record refuses to start");
  is(String(refused?.message).includes("line 2"), true, "and names the line");
  is(readFileSync(file, "utf8"), raw,
    "and leaves the file exactly as it found it");

  const quarantined = startRelayServer({ dataDir, onCorruptLog: "quarantine" });
  await quarantined.listening;
  is(quarantined.stats().quarantinedLogs, 1, "quarantine moves it aside");
  is(quarantined.logSize(room), 0, "and starts the room empty");
  is(existsSync(file), false, "the log is no longer in place");
  const aside = readdirSync(dataDir).filter((name) =>
    name.includes(".corrupt-"),
  );
  is(aside.length, 1, "the corrupt file is kept for an operator");
  is(readFileSync(join(dataDir, aside[0]), "utf8"), raw,
    "with every byte it had");
  await quarantined.close();
}

// One reader that has stopped draining must not be able to hold a room's
// replay in this process's memory.
async function slowConsumers() {
  const relay = startRelayServer({ dataDir: tempDir(), maxBufferedBytes: 1 });
  await relay.listening;
  is(relay.bufferLimit, 1, "the buffer bound is configurable");
  is(MAX_BUFFERED_BYTES, 16 * MAX_FRAME_BYTES,
    "and its default is sixteen frames");

  await raw(relay, async (socket) => {
    const code = await socket.closed();
    is(code, 1013, "a socket that cannot keep up is dropped: " + code);
  });
  is(relay.stats().slowConsumers >= 1, true, "and counted");
  is(relay.rooms().length, 0, "with the room left exactly as it was");
  await relay.close();
}

// A durable entry no client can merge — a delta whose body means nothing to
// any kernel — must not freeze the room. The client reports the exact order
// it refused, the relay lets its checkpoint land beside the entry, and the
// log compacts around it. Without that, the log never collapses, no relay is
// ever primary, and a `sequencedOnly` replica never becomes ready at all —
// and if the checkpoint *deleted* the entry instead, one client's inability
// to read a record would be enough to erase it for everybody.
async function poisonedLogs() {
  const dataDir = tempDir();
  const room = "poisoned-room";
  const poisoned = poison(room, "mallory", 1);
  writeFileSync(
    logFile(dataDir, room),
    JSON.stringify({ o: 1, k: "traffic", s: "mallory-session", e: poisoned }) +
      "\n",
  );

  let relay = startRelayServer({ dataDir });
  await relay.listening;
  const relayUrl = "ws://127.0.0.1:" + relay.port() + "/";
  is(relay.logSize(room), 1, "the poisoned entry replayed off disk");

  const world = harness.new_harness();
  const pump = pumping(world);
  // `sequencedOnly`: no peers, no mesh, nothing but the relay to be ready on.
  const late = harness.start(world, "sequencedOnly", room, "late",
    "ws://127.0.0.1:1/", relayUrl);
  await until(() => harness.readiness(late).toArray().length === 1,
    "the client resolved readiness despite the poisoned entry");
  deep(harness.readiness(late).toArray(), ["ok"], "and resolved successfully");
  is(harness.is_primary(late), true, "the relay became primary");
  is(harness.saw(late, "relayRejected"), true, "the entry was reported");
  is(relay.stats().framesByTag["skip"] >= 1, true,
    "and skipped by order rather than in silence");
  is(relay.logSize(room), 2, "the log collapsed to the checkpoint");
  is(relay.attested(room), harness.digest(late),
    "which is the digest the client holds");
  is(relay.lines(room).some((line) => line.includes("nonsense")), true,
    "and the entry nobody could read is still on disk beside it");

  harness.clap(late, 6);
  await until(() => harness.value(late) === 6, "and the document works");
  await until(() => relay.logSize(room) === 3,
    "with the new delta durable beside the checkpoint");

  // A restart replays the compacted log, and the client re-attaches to it.
  harness.close(late);
  await relay.close();
  relay = startRelayServer({ dataDir });
  await relay.listening;
  is(relay.stats().roomsRecovered, 1, "the room recovered from the checkpoint");
  is(relay.logSize(room), 3,
    "as the carried entry, the checkpoint, and the delta after it");
  is(relay.lines(room).some((line) => line.includes("nonsense")), true,
    "with the unreadable record still carried rather than quietly dropped");

  const after = harness.start(world, "sequencedOnly", room, "after",
    "ws://127.0.0.1:1/", "ws://127.0.0.1:" + relay.port() + "/");
  await until(() => harness.is_primary(after),
    "a later client attaches to the recovered room");
  is(harness.value(after), 6, "and sees everything the checkpoint held");
  harness.close(after);
  pump.stop();
  await relay.close();
}

// One writer per data directory, proved across real processes.
//
// Two processes writing one directory are two room states, each compacting a
// log from a version the other has already moved past. So a writing store
// takes `relay.lock`, a live lock is never taken from its owner, an ambiguous
// one is never taken at all, and a lock whose owner is demonstrably dead is
// recovered — those are four different rules, and this proves each of them
// with a separate process.
async function dataDirLocks() {
  const dataDir = tempDir();
  const room = "locked-room";

  // Seed the directory with a real room, so a refusal has something to be
  // asserted about on disk.
  const seed = startRelayServer({ dataDir });
  await seed.listening;
  await raw(seed, async (socket) => {
    await socket.next();
    socket.send(helloFrame(room, "carol", "carol-session"));
    socket.send(deltaFrame(room, "carol", "carol-session"));
    await until(() => seed.logSize(room) === 1, "a room is seeded");
  });
  await seed.close();
  is(existsSync(join(dataDir, "relay.lock")), false,
    "an orderly close gives the directory back");
  const seeded = readFileSync(logFile(dataDir, room), "utf8");

  // A real second process, holding the directory.
  const child = spawn("node",
    ["tools/relay/server.mjs", "--data", dataDir, "--port", "0"],
    { stdio: ["ignore", "pipe", "pipe"] });
  const banner = await new Promise((ready, failed) => {
    let output = "";
    child.stdout.on("data", (chunk) => {
      output += chunk.toString();
      if (output.includes("ws://")) ready(output);
    });
    child.once("error", failed);
    setTimeout(() => failed(new Error("the relay child never started")), 10_000);
  });
  is(banner.includes("locked by pid " + child.pid), true,
    "a serving process says it owns the directory");
  const owner = JSON.parse(
    readFileSync(join(dataDir, "relay.lock", "owner.json"), "utf8"),
  );
  is(owner.pid, child.pid, "and the lock names its pid");
  is(owner.purpose, "serve", "and what it took the directory for");

  // A service in this process refuses, by name, and writes nothing.
  let refused = null;
  try {
    startRelayServer({ dataDir });
  } catch (error) {
    refused = error;
  }
  is(refused?.name, "RelayLockedError", "a second service refuses to start");
  is(refused?.owner?.pid, child.pid, "naming the process that has it");
  is(String(refused?.message).includes("--inspect"), true,
    "and what to do instead");
  is(refused?.owner?.host, owner.host, "on the host that took it");

  // So does a writing store, opened in-process.
  let refusedStore = null;
  try {
    openRelayStore({ dataDir });
  } catch (error) {
    refusedStore = error;
  }
  is(refusedStore?.name, "RelayLockedError", "so does a writing store");

  // Nothing a refusal touched moved: not the log, not the lock itself.
  is(readFileSync(logFile(dataDir, room), "utf8"), seeded,
    "a refused operation leaves the log byte for byte as it was");
  deep(
    JSON.parse(readFileSync(join(dataDir, "relay.lock", "owner.json"), "utf8")),
    owner,
    "and leaves the owner's lock exactly as it found it",
  );

  // `--inspect` is the one thing that runs beside a live service, because
  // it is read-only: no lock, no repair.
  const inspected = await runCli(["--data", dataDir, "--inspect"]);
  is(inspected.code, 0, "an inspection runs beside a running service");
  is(inspected.stdout.includes(JSON.stringify(room)), true,
    "and reports the room");
  is(inspected.stdout.includes("ws://"), false, "without listening");
  is(readFileSync(logFile(dataDir, room), "utf8"), seeded,
    "and changes nothing on disk");
  deep(
    JSON.parse(readFileSync(join(dataDir, "relay.lock", "owner.json"), "utf8")),
    owner,
    "and does not disturb the lock it did not take",
  );

  // An orderly stop hands the directory back.
  child.kill("SIGTERM");
  await new Promise((done) => child.once("exit", done));
  is(existsSync(join(dataDir, "relay.lock")), false,
    "a signalled service releases the lock on its way out");
  const successor = startRelayServer({ dataDir });
  await successor.listening;
  is(successor.owner().pid, process.pid, "and the next process can take it");
  is(successor.logSize(room), 1, "with the room it left behind");
  await successor.close();
  is(existsSync(join(dataDir, "relay.lock")), false, "and give it back again");

  // A lock left by a crash — a pid that is demonstrably gone — is recovered.
  const deadPid = Number(
    execFileSync("node", ["-e", "process.stdout.write(String(process.pid))"], {
      encoding: "utf8",
    }),
  );
  writeLock(dataDir, {
    pid: deadPid,
    host: hostname(),
    token: "stale-token",
    purpose: "serve",
    startedAt: new Date().toISOString(),
  });
  const recovered = startRelayServer({ dataDir });
  await recovered.listening;
  is(recovered.stats().staleLocksRecovered, 1,
    "a lock whose owner is gone is recovered, once");
  is(recovered.owner().pid, process.pid, "and taken by the live process");
  is(recovered.logSize(room), 1, "with the room intact");
  is(readdirSync(dataDir).some((name) => name.includes(".stale-")), false,
    "and no stale lock left lying about");
  await recovered.close();

  // Everything else is ambiguous, and an ambiguous lock is never taken.
  const ambiguous = [
    ["an owner file that is not there", () => {
      mkdirSync(join(dataDir, "relay.lock"), { recursive: true });
    }],
    ["an owner file that cannot be read", () => {
      mkdirSync(join(dataDir, "relay.lock"), { recursive: true });
      writeFileSync(join(dataDir, "relay.lock", "owner.json"), "{ not json");
    }],
    ["an owner file with no pid in it", () => {
      writeLock(dataDir, { host: hostname(), token: "x" });
    }],
    ["an owner on another host", () => {
      writeLock(dataDir, {
        pid: deadPid,
        host: "some-other-host",
        token: "x",
        purpose: "serve",
      });
    }],
    ["an owner that is still running", () => {
      writeLock(dataDir, {
        pid: process.pid,
        host: hostname(),
        token: "x",
        purpose: "serve",
      });
    }],
  ];
  for (const [what, arrange] of ambiguous) {
    rmSync(join(dataDir, "relay.lock"), { recursive: true, force: true });
    arrange();
    const before = readdirSync(join(dataDir, "relay.lock")).sort();
    let denied = null;
    try {
      startRelayServer({ dataDir });
    } catch (error) {
      denied = error;
    }
    is(denied?.name, "RelayLockedError", "never taken: " + what);
    deep(readdirSync(join(dataDir, "relay.lock")).sort(), before,
      "and left alone: " + what);
    is(readFileSync(logFile(dataDir, room), "utf8"), seeded,
      "with the log untouched: " + what);
  }
  rmSync(join(dataDir, "relay.lock"), { recursive: true, force: true });
}

function writeLock(dataDir, owner) {
  const dir = join(dataDir, "relay.lock");
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, "owner.json"), JSON.stringify(owner) + "\n");
}

// The CLI as a real process, with its exit code and both streams.
function runCli(args) {
  return new Promise((done, failed) => {
    const child = spawn("node", ["tools/relay/server.mjs", ...args], {
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => (stdout += chunk.toString()));
    child.stderr.on("data", (chunk) => (stderr += chunk.toString()));
    child.once("error", failed);
    child.once("exit", (code) => done({ code, stdout, stderr }));
  });
}

function logFile(dataDir, room) {
  return join(dataDir, Buffer.from(room, "utf8").toString("base64url") + ".jsonl");
}

// A delta that passes every check a relay can make without merging — a
// well-formed message id, an address that names its own creator, a declared
// channel type — and that no kernel in any build can read. This is what a
// poisoned record actually looks like now that the cheap structural checks
// are in: the relay cannot tell it from a delta for a kernel some other
// replica has, because telling them apart would take a merge.
function poison(room, from, index) {
  return envelope(room, from, from + "-session", {
    type: "delta",
    id: [from, index],
    address: from + ":" + index,
    channelType: "nobodysKernel",
    contents: { nonsense: [1, 2, 3] },
  });
}

async function noSequencedLane() {
  const forbiddenModules = [
    "runtime_core",
    "runtime",
    "summary_policy",
    "presence",
    "presence_js",
    "watershed",
    "sluice",
  ];
  const forbiddenSymbols = ["handle_sequenced", "ack_local", "summary"];
  const modules = [
    "crdt_relay.mjs",
    "crdt_sequencer_js.mjs",
    "crdt_js.mjs",
    "crdt_core.mjs",
    "crdt_wire.mjs",
  ];
  for (const name of modules) {
    const source = readFileSync(
      join("build/dev/javascript/watershed/watershed", name),
      "utf8",
    );
    // Imports, from the emitted module graph rather than from prose: a doc
    // comment may name the sequenced lane, and several deliberately do.
    const imports = [...source.matchAll(/from\s+"([^"]+)"/g)].map(
      (match) => match[1],
    );
    for (const specifier of imports) {
      const module = specifier.split("/").pop().replace(/\.mjs$/, "");
      is(forbiddenModules.includes(module), false,
        name + " does not import " + specifier);
    }
    const code = stripComments(source);
    for (const symbol of forbiddenSymbols) {
      is(code.includes(symbol), false, name + " never calls " + symbol);
    }
  }
}

// Comments only; the point is to assert about code, and this file's own
// prose is allowed to name the lane it is proving is absent.
function stripComments(source) {
  return source
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .split("\n")
    .map((line) => line.replace(/^\s*\/\/.*$/, ""))
    .join("\n");
}

// ── harness ─────────────────────────────────────────────────────────────────

function tempDir() {
  const dir = mkdtempSync(join(tmpdir(), "watershed-relay-"));
  scratch.push(dir);
  return dir;
}

function cleanup() {
  for (const dir of scratch) {
    try {
      rmSync(dir, { recursive: true, force: true });
    } catch {
      // A directory that is already gone needs no removing, and a test run
      // must not fail on its own tidying up.
    }
  }
}

// A port nothing is listening on: bound, reported, and released. Used for
// the one thing a caller-supplied URL cannot fake — a relay that is
// configured and genuinely absent.
async function freePort() {
  const probe = startRelayServer({ dataDir: tempDir() });
  const port = await probe.listening;
  await probe.close();
  return port;
}

// The fake mesh is an effect queue: a signal that arrived over a real socket
// has to be stepped before the transport sees it. A 2 ms pump is the Node
// equivalent of a browser's event loop turning.
function pumping(world) {
  const timer = setInterval(() => harness.settle(world), 2);
  return { stop: () => clearInterval(timer) };
}

async function until(predicate, what, timeoutMs = 10_000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (predicate()) {
      checks += 1;
      return;
    }
    await sleep(5);
  }
  checks += 1;
  failures.push(what + ": timed out after " + timeoutMs + "ms");
}

function envelope(room, from, session, message) {
  return JSON.stringify({ v: 1, room, from, session, message });
}

// A `hello` and a `delta` with the structure the lane now insists on: the
// relay checks the fields that *name* a message — a delta's id, address and
// declared channel type, a hello's compatibility tag and root — and never the
// payload underneath them. A raw socket has to look like a client to get in.
function helloFrame(room, from, session) {
  return envelope(room, from, session, {
    type: "hello",
    compatibility: "relay-test/v1",
    root: "pnCounter",
    features: [],
  });
}

function deltaFrame(room, from, session, index = 1) {
  return envelope(room, from, session, {
    type: "delta",
    id: [from, index],
    address: from + ":" + index,
    channelType: "pnCounter",
    contents: { op: "noop" },
  });
}

// One raw socket, with every frame it received parsed and queued.
async function raw(service, body) {
  const socket = new WebSocket("ws://127.0.0.1:" + service.port() + "/");
  const state = { frames: [], closeCode: null };
  socket.on("message", (data) => {
    try {
      state.frames.push(JSON.parse(data.toString()));
    } catch {
      state.frames.push({ type: "unparseable", raw: data.toString() });
    }
  });
  socket.on("close", (code) => {
    state.closeCode = code;
  });
  socket.on("error", () => {});
  await new Promise((ready, failed) => {
    socket.once("open", ready);
    socket.once("error", failed);
  });

  // A flood keeps writing after the relay has hung up on it, and `ws`
  // reports that through the callback rather than by throwing. Swallowing it
  // here is what lets a test send 100 000 frames at a socket that closed
  // after the first thousand.
  state.send = (payload) => socket.send(payload, () => {});
  state.isClosed = () => state.closeCode !== null;
  state.next = async () => {
    const deadline = Date.now() + 3_000;
    while (Date.now() < deadline) {
      if (state.frames.length > 0) return state.frames.shift();
      await sleep(5);
    }
    throw new Error("no frame arrived");
  };
  state.closed = async () => {
    const deadline = Date.now() + 3_000;
    while (Date.now() < deadline) {
      if (state.closeCode !== null) return state.closeCode;
      await sleep(5);
    }
    throw new Error("the socket never closed");
  };

  try {
    await body(state);
  } finally {
    socket.close();
  }
}

function sleep(ms) {
  return new Promise((done) => setTimeout(done, ms));
}

function is(actual, expected, what) {
  checks += 1;
  if (actual !== expected) {
    failures.push(
      what + ": expected " + JSON.stringify(expected) + ", got " + JSON.stringify(actual),
    );
  }
}

function deep(actual, expected, what) {
  checks += 1;
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    failures.push(
      what + ": expected " + JSON.stringify(expected) + ", got " + JSON.stringify(actual),
    );
  }
}
