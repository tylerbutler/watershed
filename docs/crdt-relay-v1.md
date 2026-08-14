# `crdt_relay_v1` — the optional sequencer relay lane

This is the contract a sequencer must implement for watershed's peer-to-peer
CRDT documents to use it as a durable delta path. The **normative
specification is the module docstring of `src/watershed/crdt_relay.gleam`**,
the pure protocol module both sides share; the tests in
`test/watershed/crdt_relay_test.gleam` are its executable form. This page is
the wire-format reference and the operator's guide. The client half ships in
this repository (`src/watershed/crdt_sequencer_js.gleam`) and the server half
does not: **Floodgate is an external repository and nothing in this one
modifies it.** `tools/relay/server.mjs` is a reference service that
implements the contract end to end.

A relay is optional. A p2p document works with no sequencer at all, `Auto`
never waits for one to become ready, and `P2pOnly` never opens a socket to
one.

## What a relay is, and is not

A relay is a **durable fan-out point**. It stamps a diagnostic order, keeps a
log it can replay, broadcasts what it accepts, and answers a `stateRequest`
from what it holds. It never merges, never decides which of two replicas is
right, and never decodes a kernel payload — an envelope reaches it as an
opaque string and leaves as the same string, byte for byte. The order it
stamps is diagnostic: it lives outside the envelope and no client passes it
to a kernel, a message id, a digest, or an event.

It is also **not the legacy sequenced DDS lane**. This is a separate endpoint
or subprotocol with its own capability negotiation; CRDT envelopes are never
tunnelled through the Fluid document lane.

## The lane

One WebSocket per document. Text frames only. The frame limit in both
directions is `crdt_wire`'s `Limits.envelope_bytes` — 262 144 bytes in v1 —
enforced at the socket layer as well as in the decoder.

### The greeting

The relay speaks first, before the client has said anything:

```json
{
  "type": "connected",
  "capabilities": { "crdt_relay_v1": true },
  "limits": { "envelopeBytes": 262144 }
}
```

A client that does not see `crdt_relay_v1` set to `true` treats the endpoint
as a sequencer without this lane; that is the whole of capability
negotiation. Under `Auto` it is a reported status and the document carries on
over WebRTC; under `SequencedOnly` it is a readiness failure. Anything other
than the greeting, before the greeting, is a handshake violation: the client
reports it and drops the socket.

### Client → relay

**Encoded `crdt_wire.Envelope` strings, unchanged** — exactly the strings a
WebRTC data channel would carry:

| type | what the relay does |
| --- | --- |
| `hello` | admits the connection, then broadcasts |
| `channel` | logs, then broadcasts |
| `delta` | logs, then broadcasts |
| `stateRequest` | answers from its own log; does **not** broadcast |
| `state` | logs, then broadcasts |
| `digest` | broadcasts; not durable content |

`error` is not on the list: a relay is not a peer and has nobody to be
rejected by, so an `error` envelope is refused as `unsupportedMessage`.

**And three control frames:**

```json
{ "type": "attest", "digest": "<the client's own digest>", "upTo": 12 }
{ "type": "skip", "order": 7 }
{ "type": "supports", "checkpointRequests": true }
```

- `attest` follows a published `state`: `upTo` is the highest `order` the
  client has *accounted for* on this socket — merged into the state it just
  published, or reported as skipped. Reset on every reconnect.
- `skip` names the exact order of a relayed entry this client could not
  merge, the moment it refuses one.
- `supports` opts in to being *asked* for a checkpoint, sent once after the
  admitting `hello`. A relay never sends `checkpointRequest` to a connection
  that has not said this, so a client written against an earlier version of
  this lane is never sent a frame it would treat as a violation. It also
  gates the one capacity exemption: at the room's hard bound, only a
  supports-declaring connection may publish a `state`.

### Relay → client

```json
{ "type": "frame",    "order": 12, "envelope": "<the sender's exact string>" }
{ "type": "synced",   "order": 12 }
{ "type": "attested", "order": 13, "digest": "<echo, or empty>" }
{ "type": "checkpointRequest" }
{ "type": "error",    "reason": "malformed", "detail": "…" }
```

- `frame` carries one relayed envelope; `order` is outside it.
- `synced` ends the burst a `stateRequest` produced.
- `attested` answers an `attest`: the digest echoed back when the relay's
  content is exactly the published state plus what that client reported
  skipped, and `""` otherwise.
- `checkpointRequest` asks a client to publish its merged state and attest
  it. It carries **nothing at all** — a client answers out of its own
  state. Sent only to a connection that declared `supports`.
- `error` is terminal: the socket is closed after it.

A relay that stamps nothing may send a bare envelope string instead of a
`frame` wrapper; the client accepts that and reports its order as `0`.

## Admission — the trust boundary

**Admission and authentication are this lane's trust boundary**, and in
particular the checkpoint's: a relay never merges, so it takes an admitted
client's word for what its published state contains. The reference service's
rules are bounded examples, not a security model — a deployment substitutes
its own authentication, and defence against a malicious *admitted* client
belongs to that deployment. What must be kept is that admission is decided
from the envelope's *preamble* and never from a payload.

Refusals, each of which writes an `error` frame, closes that connection, and
leaves the room exactly as it was:

| reason | when |
| --- | --- |
| `notAdmitted` | any frame before the admitting `hello` |
| `identityChanged` | a frame naming a different room, sender, or session |
| `duplicateSession` | a session already attached to the room |
| `invalidRoom` | empty, or over 128 UTF-8 bytes |
| `roomFull` | more than 32 clients (reference value) |
| `frameTooLarge` | over the envelope byte limit |
| `malformed` | unparseable, or failing a structural check |
| `unsupportedMessage` | a message type not in the table above |
| `tooManySkips` | more than 1 024 outstanding live skips |
| `roomAtCapacity` | a durable frame that would take the live log past `max_room_records`, checked *before* the append |

### Structural checks

A relay checks the *shape* of a message using only the fields that name or
address it — `contents` and `snapshot` stay opaque — and every check is a
strict subset of `crdt_wire`'s decoder, so a relay can never refuse an
envelope a document would have accepted:

| type | checked |
| --- | --- |
| `hello` | `compatibility` and `root` are strings |
| `channel` | `descriptor.address` is a valid address, `descriptor.createdBy` is the creator that address names, `descriptor.channelType` is a non-empty string |
| `delta` | `id` is `[replica, counter]` with a valid replica and `counter >= 0`, `address` is a valid address, `channelType` is a non-empty string |
| `state` | `channels` is a list (its elements are never inspected) |
| `digest` | `digest` is a string |
| `stateRequest` | nothing to check |

## Attestation, skips, and the hard bound

The module docstring is normative here; in brief:

- **Attachment**: `hello`, `stateRequest`, merge every replayed `frame`, on
  `synced` publish the whole merged state, `attest` its digest, and become
  primary only on a matching echo. An empty echo means the relay holds
  something unaccounted for: merge and try again.
- **A checkpoint never shortens a room's history.** An honoured `attest`
  retires what the published state claims to contain, keeps every record the
  publisher reported as skipped beside the checkpoint, and leaves the log
  untouched if anything is outstanding. `upTo` is clamped to what this
  connection was actually sent.
- **A skip is a fact about delivery, not content.** It is honoured only for
  an order this connection was sent that still names a live log entry;
  duplicates, unseen and future orders are ignored. A skipped entry keeps
  being replayed to everyone else, is carried past that client's
  checkpoints, and is retired only by a client that merged it.
- **The live log is bounded** at `max_room_records` (1 024), checked before
  the append. Past `checkpoint_pressure_records` (768) the relay sends
  `checkpointRequest` to supports-declaring clients, re-asking only after
  `checkpoint_request_interval` (64) records of further growth; at the bound
  the sender of the crossing frame is refused with `roomAtCapacity`. The one
  exemption: **a `state` from a supports-declaring connection is always
  admitted at the bound**, because it is the one frame that can compact a
  full room — this is also how a room recovered already-full drains, since
  no append can ever run to ask. A client that publishes past the bound and
  never attests earns nothing further: its next ordinary append is refused
  like any other. `max_client_skips` (1 024) ≥ `max_room_records`, so a
  client refusing every record in a full room is never closed for it.

## Durability

The reference service keeps one append-only JSONL file per room in a
caller-supplied data directory:

```json
{"o":3,"k":"state","s":"<session>","e":"<envelope>"}
{"o":4,"k":"traffic","s":"<session>","e":"<envelope>"}
{"o":5,"k":"digest","d":"<attested digest>","c":3}
```

The `digest` line is the room's **checkpoint marker**. `d` is the digest a
client attested; `c` names the order of the canonical `state` record — the
one a fresh attachment rebuilds from. `c` is optional for a reader: a log
written without it replays with the newest `state` record as canonical. A
marker's `d` counts only while the marker is the newest record in the file;
a marker rewritten by a later compaction carries `""` while still naming the
entry.

Rules a durable relay must keep:

- append before acknowledging;
- **compact only after a later canonical state has been durably written**:
  write the replacement beside the log and rename over it, and only after
  the append that carried the checkpoint was flushed;
- **never compact away a record the attesting client reported as skipped** —
  the replacement holds them in ascending order beside the checkpoint;
- **keep the checkpoint marker across every compaction**;
- **never rewind a room's order**: on replay, the next order is
  `max(what it had reached, highest order read + 1)`;
- **own the data directory exclusively while writing it** — see below;
- **bound the live log before appending**, asking for a checkpoint first;
- replay every line on start, before the first socket is accepted, removing
  any stale `*.tmp` staging file a crashed compaction left behind;
- **repair a torn trailing line, and only that.** An unreadable line
  anywhere else is a record that was complete when acknowledged: the
  reference refuses to start (`CorruptLogError`) or, under
  `--on-corrupt quarantine`, moves the whole file aside byte for byte and
  starts that room empty.

## One writer per data directory

Two processes writing one directory are two room states, each compacting
from a version the other has already moved past. So a **writing** store
takes an exclusive lock before it reads a single log:

```
relay-data/relay.lock/owner.json
{"pid":4242,"host":"gannet","purpose":"serve","startedAt":"…"}
```

- the lock is a **directory**, created with `mkdir`, which is atomic;
- it is released on an orderly `close()` and on the CLI's signal handlers,
  and by a store that throws while opening;
- a lock left by a crash is recovered **only when its owner is demonstrably
  dead**: same host, and a pid `kill(pid, 0)` reports as gone (`ESRCH`) —
  removed, and the acquisition retried once;
- **an ambiguous lock is never taken.** A live pid, `EPERM`, another host, a
  missing or unreadable owner file — all refuse, naming the owner where
  there is one. A refused acquisition writes nothing at all.

## The operator workflow

```
# what does each room hold, and where is its checkpoint?
node tools/relay/server.mjs --data ./relay-data --inspect
```

`--inspect` prints each room's live log size, the record its checkpoint
marker names, and what attached clients have reported they cannot read. It
is **read-only** — no lock, no torn-tail repair, no writes — so it is safe
beside a running service, and it binds no port. Carriage is a fact about
live claims, so an offline inspection reports it as **unknown** rather than
empty: with nobody attached, nobody has said what they cannot read.

The serving flags are `--port`, `--host`, `--data`, and
`--on-corrupt fail|quarantine`.

## Backpressure

A relay writes bursts: a `stateRequest` replays a whole room. The reference
bounds each socket's buffered bytes and drops a connection whose next frame
would exceed it — close code `1013`, counted as a slow consumer, room left
exactly as it was. The bound is sixteen frames (4 MiB), configurable per
service.

## Client behaviour a relay can rely on

- **Readiness never waits for a relay** under `Auto`; the mesh decides.
- **Reconnect backoff** is 250 ms, 500 ms, 1 s, 2 s, then 5 s, reset after a
  healthy session. `SequencedOnly` retries under a readiness deadline
  (default 10 s), then fails once and closes.
- **Failover pauses nothing**: the client marks WebRTC as the delta path
  before reporting the fallback, pushes the digest it owed the mesh, asks
  its peers for state, and carries on — a transport changed, not a session.
- **The mesh stays informed**: while the relay is primary, peers get
  coalesced digests (one per 250 ms anti-entropy interval), and a peer merge
  that moves this replica's state is republished to the relay on the same
  interval.
- **Duplicates are free**: a delta arriving over both paths is one state
  change, because CRDT merge is idempotent and message ids are stable.
- **Refusals are reported**: a `skip` for the exact refused order, at once.
- **A checkpoint request is answered, not negotiated**: the same `state` +
  `attest` the client publishes at attachment.
- **A write that fails is a lane that failed**: every send is checked, and a
  write that did not reach an open socket retires the socket and arms the
  reconnect.
- **The relay's order is never quoted back into a document.** It appears in
  exactly two client-authored places, both control frames: an `attest`'s
  `upTo` and a `skip`'s `order`, both reset per socket.

## Implementing it

The protocol is a pure Gleam module with no I/O:
`src/watershed/crdt_relay.gleam`. `serve/3` takes a registry, a connection
id and a raw frame, and hands back the new registry, the socket and storage
writes to perform, and a diagnostic tag. `tools/relay/server.mjs` is a few
hundred lines of `ws` and `node:fs` on top of it, and `tools/relay/test.mjs`
runs the whole lifecycle against it — absent, attach, checkpoint, outage
edits, restart, converge — in a temporary directory.

A service in another language reimplements the same decisions. The pure
module's docstring is the specification; the tests in
`test/watershed/crdt_relay_test.gleam` are the executable form of it.
