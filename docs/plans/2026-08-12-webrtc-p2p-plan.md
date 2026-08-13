# WebRTC peer-to-peer mode plan

**Date:** 2026-08-12
**Builds on:** the lattice-backed PN counter, OR-map, OR-set, G-set, 2P-set,
sequence, and text kernels; the JavaScript runtime transport seam; summary
snapshots; and the deterministic sluice test pattern.
**Scope:** browser collaboration over CRDT semantics with WebRTC available from
startup and an optional sequencer used when reachable. A signaling service
introduces peers but does not sequence, store, inspect, or relay document
operations.

## Goal

Add a JavaScript CRDT runtime that can start and run without a sequencer.
Browsers discover one another through signaling, exchange state over WebRTC,
edit while disconnected, reconnect in any order, and converge once they
exchange state.

When a compatible sequencer becomes available, the same document attaches to
it for relay, history, authentication, and durable checkpoints. Losing that
connection returns the document to WebRTC without changing its state or public
handles. The sequencer's order is useful transport metadata, not part of CRDT
correctness.

This mode supports CRDT channels whose merge functions establish convergence.
It rejects DDS, OT, and coordination channels that read sequence numbers,
reference sequence numbers, room membership, or server acknowledgements.

## Decisions to confirm before P2P1

1. **Version one targets browsers.** WebRTC support belongs in a new
   `watershed/crdt_js` facade; the BEAM facade keeps its server-backed runtime.
   A future BEAM transport can implement the same CRDT protocol without
   blocking this work.
2. **Signaling is independent from sequencing.** Peers use an
   application-supplied signaling adapter to exchange offers, answers, and ICE
   candidates. The signaling service routes opaque session messages and may
   authenticate room admission. It never assigns operation order or stores
   document state. A dead or absent sequencer cannot prevent room creation,
   peer discovery, or WebRTC bootstrap.
3. **The first topology is a small full mesh.** Every peer opens one data
   channel to every other peer. Set a default room limit of eight peers and
   return `RoomFull` before creating another connection. Larger rooms need an
   SFU, relay, or gossip design and belong in another plan.
4. **Applications supply ICE configuration.** `Config` accepts STUN and TURN
   servers using the browser's `RTCConfiguration` model. Watershed must not
   ship service credentials or imply that STUN alone connects every NAT pair.
5. **One CRDT document changes transports without changing semantics.** A
   `CrdtDocument(root)` supports `Auto`, `SequencedOnly`, and `P2pOnly`
   policies. `Auto` starts through WebRTC and attempts the sequencer in
   parallel. It prefers a compatible sequencer while healthy and returns to
   WebRTC when the connection drops. The document never converts into the
   existing DDS runtime and cannot be passed to server-order-dependent APIs.
6. **The root is an explicit CRDT kind.** The current `root()` is a
   `SharedMap`, whose last-writer-wins rule depends on server order. P2p connect
   therefore takes a supported root initializer and returns the matching
   handle. The typed SharedMap schema layer is unavailable in p2p mode until a
   JSON-valued CRDT map exists.
7. **Applications declare a compatibility tag.** Matching root kinds do not
   prove that two app versions assign the same meaning to channel addresses or
   values. Every connection supplies an application-defined tag such as
   `"retro-board/v1"`. Peers reject a mismatch before exchanging state.
8. **Peers do not trust remote envelopes.** The runtime validates room ID,
   protocol version, channel address, declared channel type, payload size, and
   codec success before touching a kernel. DTLS protects transport links, while
   room admission and peer identity remain signaling-service concerns.
9. **Durability depends on the transports that joined.** A document with no
   sequencer keeps state in connected replicas. A compatible sequencer may
   retain history and checkpoints after it attaches. Applications can export
   and import a CRDT snapshot in either case. IndexedDB persistence and
   background sync remain separate features.

## Eligible channels

Add one source of truth in `watershed/channel.gleam`:

```gleam
pub fn supports_p2p(channel_type: ChannelType) -> Bool
```

Version one returns `True` for:

| Public structure | Channel type | Why it is eligible |
| --- | --- | --- |
| PN Counter | `PnCounterChannel` | merges per-replica positive and negative tallies |
| OR-Map | `OrMapChannel` | merges causal entry deltas in both current value modes |
| OR-Set | `OrSetChannel` | merges add dots and observed removals |
| G-Set | `GSetChannel` | merges by union |
| 2P-Set | `TwoPSetChannel` | merges add and tombstone sets by union |
| SharedSequence | `SequenceChannel` | merges identity-based sequence deltas |
| SharedText | `TextChannel` | merges identity-based text deltas |

Reject these channel types:

- `MapChannel`, `CounterChannel`, and `DirectoryChannel` use server order or
  server deduplication.
- `RegisterCollectionChannel` and `ClaimsChannel` persist sequence numbers.
- `TaskManagerChannel`, `PactMapChannel`, and `OrderedCollectionChannel` depend
  on ordered membership and acknowledgements.
- `JsonOtChannel` and `RichTextChannel` transform against sequenced history.

The website describes a G-Counter, but Watershed does not expose a G-counter
channel in the closed channel sums. Do not add it as part of this work. Once a
public G-counter channel exists, `supports_p2p` can admit it.

Creation, root initialization, handle resolution, snapshot import, and remote
channel announcements must all call `supports_p2p`. A remote peer cannot smuggle
an unsupported snapshot into an otherwise valid p2p document.

## Public API

Keep the hybrid CRDT types in a new `watershed/crdt_js` module. Do not add them
to `WatershedConfig`; existing callers expect its server URL to be mandatory
and its document to use sequenced DDS semantics.

```gleam
pub opaque type CrdtDocument(root)
pub opaque type Signaling
pub opaque type Config(root)
pub opaque type Handle(kind)

pub type TransportPolicy {
  Auto
  SequencedOnly
  P2pOnly
}

pub type Root(kind) {
  Root(
    kind: CrdtKind(kind),
    address: String,
  )
}

pub fn config(
  room_id: String,
  replica_id: String,
  compatibility_tag: String,
  root: CrdtKind(root),
  signaling: Signaling,
) -> Config(root)

pub fn with_ice_servers(
  config: Config(root),
  servers: List(IceServer),
) -> Config(root)

pub fn with_transport_policy(
  config: Config(root),
  policy: TransportPolicy,
) -> Config(root)

pub fn with_sequencer(
  config: Config(root),
  sequencer: SequencerConfig,
) -> Config(root)

pub fn connect(
  config: Config(root),
  on_ready: fn(Result(CrdtDocument(root), P2pError)) -> Nil,
  on_status: fn(Status) -> Nil,
) -> CrdtConnection

pub fn root(document: CrdtDocument(root)) -> Handle(root)
pub fn close(connection: CrdtConnection) -> Nil
pub fn export_snapshot(document: CrdtDocument(root)) -> Json
pub fn import_snapshot(config: Config(root), snapshot: Json)
  -> Result(CrdtDocument(root), P2pError)
```

`CrdtKind(kind)` is a closed, typed set of supported initializers. Constructors
such as `pn_counter_root`, `or_set_root`, `sequence_root`, and `text_root`
preserve the handle type without casts.

Expose CRDT mutation, read, create, resolve, and subscribe functions for the
eligible handles. Match existing facade names where the semantics match, but
keep them in `crdt_js` so a caller cannot pass a hybrid handle to
`watershed_js.set` or another server-backed function.

`Auto` is the default. The first peer becomes ready with an empty root after
joining signaling, even when no sequencer and no other peer exist. A sequencer
connection attempt must never delay `on_ready` in `Auto` or `P2pOnly`.
`SequencedOnly` is the one policy that waits for a sequencer and fails if it
cannot connect.

### Signaling adapter

Define signaling as callbacks rather than a WebSocket dependency:

```gleam
pub type Signaling {
  Signaling(
    join: fn(String, String, fn(Signal) -> Nil)
      -> Result(SignalingSession, String),
    send: fn(SignalingSession, String, SignalPayload) -> Nil,
    leave: fn(SignalingSession) -> Nil,
  )
}

pub type Signal {
  PeerJoined(peer_id: String)
  PeerLeft(peer_id: String)
  Message(from: String, payload: SignalPayload)
}
```

Ship one WebSocket signaling adapter for examples and integration tests if the
repository's server stack has a suitable endpoint by P2P5. Keep the core API
adapter-based so an application can use Phoenix, a hosted signaling product,
or manual invitation exchange.

## Runtime architecture

Do not run CRDT messages through `runtime_core.handle_sequenced`, including
when a sequencer relays them. That core owns client sequence numbers, server
sequence numbers, FIFO ack matching, replay watermarks, summaries, and
membership. Supplying invented values would conceal sequencer dependencies and
make unsupported kernels appear safe.

Add:

- `watershed/crdt_core.gleam`: pure document state, channel registry, local
  edits, remote merges, snapshots, and protocol validation.
- `watershed/crdt_wire.gleam`: protocol envelopes and codecs shared by WebRTC
  and sequencer relay.
- `watershed/crdt_js.gleam`: public typed facade, transport policy, and
  connection lifecycle.
- `watershed/crdt_sequencer_js.gleam`: optional sequencer relay adapter.
- `watershed/p2p_transport_js.gleam` plus
  `watershed/p2p_transport_ffi.mjs`: `RTCPeerConnection`, data channels, and ICE
  exchange.

Reuse channel snapshots and CRDT op codecs where their formats contain no
sequencer metadata. Keep the CRDT envelope separate from legacy Fluid DDS
operation envelopes.

### Transport policy

`Auto` follows this lifecycle:

1. Generate a collision-resistant CRDT replica identity in the browser.
2. Join independent signaling and establish available WebRTC connections.
3. Bootstrap from a peer, or create an empty root when the room has no peers.
4. Fire `on_ready` without waiting for a sequencer.
5. Attempt the configured sequencer connection in parallel and keep retrying
   with bounded backoff.
6. When the sequencer advertises `crdt_relay_v1`, merge its state with the
   local document, publish the local state back through the relay, and verify a
   digest.
7. Use the sequencer as the primary durable delta path while keeping WebRTC
   connections open for presence, ripples, digests, and failover.
8. When the sequencer drops, exchange state with a peer, route new deltas over
   WebRTC, and keep local edits available throughout the transition.
9. When the sequencer returns, merge both sides again before marking it
   primary.

Transport changes do not create a new replica identity, reset channel state,
clear subscribers, or turn local edits into pending acknowledgements. Deltas
may arrive from WebRTC and the sequencer during a transition. Their stable
message IDs aid diagnostics, while CRDT idempotence makes duplicate delivery
safe.

`P2pOnly` skips sequencer connection attempts. `SequencedOnly` skips WebRTC data
bootstrap but still uses the same CRDT core and envelope, so exported snapshots
and later policy changes do not alter document semantics.

### Sequencer relay contract

Floodgate needs a capability separate from its existing Fluid document lane:

```json
{
  "capabilities": {
    "crdt_relay_v1": true
  }
}
```

The relay accepts the same `hello`, `channel`, `delta`, `state`, `stateRequest`,
and `digest` messages used over WebRTC. It may stamp and persist a total order,
but clients do not pass those sequence numbers into kernels. A new or returning
client merges the relay's latest state and any later deltas.

When a room starts without the sequencer, the first attaching replica sends a
full `state` message. Concurrent attachments may send different states; the
relay broadcasts both and every client merges them. The relay can checkpoint a
canonical state after receiving one, but it must not pick a winning replica or
reject a state because another snapshot arrived first.

`Auto` treats a server without `crdt_relay_v1` as unavailable for this
document, reports that status, and continues over WebRTC. It must not send CRDT
envelopes through the legacy sequenced DDS lane.

### Kernel lifecycle without acknowledgements

The eligible kernels currently keep `sequenced`, `optimistic`, and `pending`
state because a local delta waits for its server echo. The hybrid CRDT runtime
does not wait for an echo, even while using the sequencer relay.

Add explicit channel dispatch functions:

```gleam
pub fn apply_p2p_local(
  state: ChannelState,
  edit: P2pEdit,
) -> Result(#(ChannelState, List(ChannelEvent), ChannelOp), ChannelError)

pub fn apply_p2p_remote(
  state: ChannelState,
  op: ChannelOp,
) -> Result(#(ChannelState, List(ChannelEvent)), ChannelError)
```

Each eligible kernel should implement a local path that:

1. authors a CRDT delta with the local replica identity;
2. merges that delta into confirmed and visible state in one transition;
3. returns the delta for broadcast;
4. leaves no pending entry and expects no acknowledgement.

The remote path merges the delta without sequence metadata. Do not implement
this by calling `ack_local` with zero or synthetic sequence numbers.

Server-backed kernel functions and state transitions must remain unchanged.
Shared pure helpers may extract delta construction and merge logic where both
runtimes need it.

## CRDT protocol

Use a versioned JSON envelope first. WebRTC data channels can carry strings,
and JSON lets the existing Gleam codecs validate payloads. A binary codec can
follow measured size or CPU pressure.

```json
{
  "v": 1,
  "room": "trip-planning",
  "from": "replica-a",
  "session": "4e65...",
  "message": {
    "type": "delta",
    "id": ["replica-a", 17],
    "address": "root",
    "channelType": "or-set",
    "contents": {}
  }
}
```

Message types:

| Type | Purpose |
| --- | --- |
| `hello` | protocol version, compatibility tag, root kind, session ID, limits, and feature flags |
| `channel` | announce an immutable channel address, kind, and initial snapshot |
| `delta` | merge one channel delta |
| `stateRequest` | request current registry and channel snapshots |
| `state` | send a complete mergeable document snapshot |
| `digest` | compare registry and per-channel state hashes |
| `error` | report protocol rejection before closing a bad peer |

Every local message gets an ID of `(replica_id, local_counter)`. Keep a bounded
recent-ID set for diagnostics and cheap duplicate suppression, but correctness
must come from idempotent CRDT merge. A state transfer may contain effects whose
delta messages arrive before or after it.

Open a reliable data channel with ordering disabled. Reliability avoids
inventing retransmission in version one; disabled ordering proves the protocol
does not depend on one connection's delivery order. State exchange repairs any
gap caused by a peer closing before queued messages flush.

Set protocol limits for envelope bytes, snapshot bytes, channels per document,
and buffered messages during bootstrap. Close a peer that exceeds a limit or
repeats malformed payloads.

## Channel registry and handles

The server currently establishes a global order for attach operations. P2p mode
needs a mergeable registry.

Use collision-free channel addresses:

```text
<replica-id>:<local-channel-counter>
```

The `root` address is reserved and every peer derives it from `Config`.
Other channel descriptors are immutable facts:

```gleam
pub type ChannelDescriptor {
  ChannelDescriptor(
    address: String,
    channel_type: ChannelType,
    created_by: String,
  )
}
```

Store descriptors in a grow-only registry keyed by address. If two descriptors
name the same address with different kinds, mark the peer invalid and close its
connection. Since addresses contain the creator replica ID, a conflict signals
a forged or corrupt message rather than a normal race.

A `channel` message carries the descriptor and initial CRDT snapshot. Later
`state` messages carry the current snapshot. Handle-bearing values may refer to
an address before its descriptor arrives; keep those handles unresolved and
notify subscribers once the registry learns the channel. Bound this unresolved
set.

## Join, merge, failover, and reconnect

### Initial join

1. Join the signaling room and discover current peers.
2. Establish one WebRTC connection per peer. Break simultaneous-offer ties by
   letting the lexicographically smaller peer ID create the offer.
3. Exchange `hello`. Reject protocol, room, or root-kind mismatches.
4. The joining peer sends `stateRequest` to one connected peer.
5. That peer captures its registry and channel snapshots, then sends `state`.
6. The joiner merges the snapshot. It can receive and merge live deltas before,
   during, or after this transfer.
7. The joiner sends `digest` to every peer. A mismatch triggers another state
   exchange with that peer.
8. Fire `on_ready` after one valid state response, or at once if the room had no
   peers. Do not wait for a sequencer.

No peer acts as leader after bootstrap. Any peer can answer `stateRequest`.

### Sequencer attachment and failover

A document may attach to the sequencer before or after WebRTC bootstrap. In
both cases it merges relay state rather than replacing local state. The runtime
marks the sequencer primary after relay and local digests match.

Keep WebRTC connections established while the sequencer is primary. A
sequencer outage may also take down a colocated signaling endpoint, so existing
peer connections must not depend on receiving another signaling event before
they can carry deltas. Deployments that need peer discovery during a sequencer
outage must host signaling on an independent failure domain or use another
signaling adapter.

On failover, pause no local mutations. Merge peer state, then send new deltas
through WebRTC. On recovery, merge relay state, peer state, and edits made
during the outage before returning to the sequencer path.

### Ongoing repair

Send a digest after:

- a new data channel opens;
- a data channel reconnects;
- a local import merges a snapshot;
- a configurable interval while the document is active.

Hash canonical encoded snapshots. A mismatch requests full state in version
one. Per-channel requests or Merkle trees can reduce large repairs after data
shows that full snapshots cost too much.

### Partitions

Both partitions accept edits. Peers exchange state when any connection between
the partitions returns, and the mesh fans merged state to the remaining peers.
If every replica in one partition disappears before reconnecting or exporting a
snapshot, its edits are lost. The status API must report peer count, bootstrap
state, partition repairs, and the last successful digest match.

Replica IDs must not be reused by two active writers. Generate a random
installation ID and add a random session suffix for each p2p connection. An
application-supplied stable ID may label status events, but CRDT authorship uses
the collision-resistant session identity.

## Presence, ripples, and summaries

- Derive p2p presence from open peer connections. Expose peer joined and peer
  left status events; do not write them into document state.
- Add an unreliable, unordered WebRTC data channel for optional ripples after
  the document channel works. Cursor and pointer traffic must not block CRDT
  state delivery.
- Server presence and `presence_v1` do not define CRDT membership. A compatible
  sequencer may expose connection status, but WebRTC presence remains available
  during failover.
- Legacy Floodgate summary upload and auto-summarization do not apply. The CRDT
  relay checkpoints the same mergeable state container that peers exchange,
  with room ID, compatibility tag, root descriptor, registry, and replica
  metadata.

## Error model

Add typed errors:

```gleam
pub type P2pError {
  UnsupportedChannel(ChannelType)
  RootMismatch(expected: ChannelType, received: ChannelType)
  CompatibilityMismatch(expected: String, received: String)
  ProtocolMismatch(expected: Int, received: Int)
  RoomMismatch
  RoomFull(limit: Int)
  SignalingFailed(String)
  SequencerUnavailable(String)
  SequencerUnsupported
  PeerConnectionFailed(peer_id: String, detail: String)
  InvalidEnvelope(peer_id: String, detail: String)
  SnapshotTooLarge(bytes: Int, limit: Int)
  ReplicaCollision(replica_id: String)
}
```

An invalid remote delta does not become a successful no-op. Report the error,
close that peer, and keep the valid local document available. A signaling
failure before first state prevents readiness. Losing one peer after readiness
changes status but does not fail the document while another local replica still
exists.

## Existing examples to use

No current example can run unchanged in p2p mode. Every example starts with the
sequencer-backed `SharedMap` root, even when all nested application state uses
eligible CRDT channels.

Several examples can test p2p with small root and bootstrap changes:

| Example | Collaborative state | Required adaptation | Test value |
| --- | --- | --- | --- |
| `clap_counter_lustre` | PN Counter | Make the PN Counter the p2p root instead of storing its handle in SharedMap | Smallest end-to-end transport and merge test |
| `grocery_triptych_lustre` | G-Set, 2P-Set, OR-Set | Replace the SharedMap handle index with the p2p channel registry | Multi-channel creation, resolution, and merge |
| `pixel_canvas_lustre` | OR-Map in register mode | Make the pixels OR-Map the root; keep the display title local | High operation volume and same-key write races |
| `playlist_lustre` | SharedSequence | Make the sequence the root; keep the display title local | Concurrent insert, move, delete, and reorder |
| `text_lustre` | SharedText | Make the text channel the root; keep the display title local | Dense concurrent edits and identity-based merge |
| `retro_board_lustre` | OR-Maps and SharedSequences | Replace the SharedMap title and handle index with local metadata plus the p2p registry | Mixed CRDT kinds and nested handles |

Use `clap_counter_lustre` for the first WebRTC proof because it needs one root
channel and one mutation. Use `grocery_triptych_lustre` next because its three
set channels exercise the registry without introducing sequence or text
editing.

Do not use these as p2p acceptance examples:

- `drum_machine_lustre` uses `PactMap` for tempo.
- `work_queue_lustre` uses `OrderedCollection` and `TaskManager`.
- `tournament_bracket_lustre` uses `RegisterCollection`.
- `sudoku_lustre` uses SharedMap, Claims, and SharedCounter.
- `dice_lustre`, `dice_cli`, `scoreboard_cli`, and `flowboard_lustre` depend on
  SharedMap or SharedCounter semantics.

## Delivery rungs

- **P2P1: Eligibility boundary.** Add `supports_p2p`, typed p2p kinds, errors,
  and tests that every channel type has an explicit supported or rejected
  result. Gate: all unsupported root, create, resolve, and import paths return
  `UnsupportedChannel`.
- **P2P2: Ack-free CRDT lifecycle.** Add local commit and remote merge paths for
  PN counter, OR-map, OR-set, G-set, 2P-set, sequence, and text. Gate: pure
  permutation tests deliver each delta in every tested order, with duplicates,
  and all replicas converge with empty pending queues.
- **P2P3: Pure CRDT core and wire protocol.** Add the registry, envelopes,
  snapshots, digests, limits, and a deterministic mesh simulator. Gate:
  three-peer tests cover concurrent channel creation, delta-before-channel,
  duplicate state, partition, reconnect, and malformed peers.
- **P2P4: WebRTC transport.** Add the browser FFI, perfect-negotiation
  collision handling, ICE forwarding, reliable unordered document channels,
  and connection status. Gate: the first browser creates an empty room without
  a sequencer; a second browser joins through a fake signaling adapter and both
  converge.
- **P2P5: Public facade and signaling example.** Add `watershed/crdt_js`, typed
  root constructors, eligible handle APIs, snapshot import/export, and a small
  signaling service or adapter. Migrate `clap_counter_lustre` as the first p2p
  example. Gate: two browsers merge claps and the signaling process receives no
  document delta.
- **P2P6: Optional sequencer relay.** Add `Auto`, `SequencedOnly`, and
  `P2pOnly`, the Floodgate `crdt_relay_v1` capability, initial state publication,
  late attachment, primary-path selection, failover, and recovery. Gate: create
  and edit a room with Floodgate absent, start Floodgate, attach and checkpoint,
  stop it, continue editing over WebRTC, restart it, and converge all copies.
- **P2P7: Anti-entropy and partitions.** Add canonical digests, state repair,
  reconnect, bounded bootstrap buffers, and the p2p registry path needed by
  `grocery_triptych_lustre`. Gate: split a three-peer mesh, edit both sides,
  reconnect one edge, and verify all peers reach equal snapshots across its
  three set channels.
- **P2P8: Lustre bindings and documentation.** Add CRDT connect, transport
  policy, status,
  subscriptions, and eligible mutations to `watershed_lustre`; document room
  limits, TURN requirements, sequencer-independent startup, durability by
  active transport, and unsupported structures.

## Test matrix

| Case | Expected result |
| --- | --- |
| First peer, no sequencer | Creates the configured CRDT root and becomes ready |
| Late peer | Merges one state response, then verifies digests with all peers |
| Sequencer available at startup | Uses relay after state and digest agreement |
| Sequencer appears later | Publishes and merges state without resetting handles |
| Sequencer disconnects | Keeps editing and switches deltas to WebRTC |
| Sequencer returns | Merges outage edits before marking relay primary |
| Sequencer lacks `crdt_relay_v1` | `Auto` reports status and stays on WebRTC |
| Concurrent deltas | All delivery orders and duplicates converge |
| Concurrent channel creation | Both collision-free descriptors survive |
| Delta before descriptor | Buffers within limits, then applies after announce |
| Partition and reconnect | Both partitions merge without choosing a winner |
| Peer disappears during state transfer | Joiner requests state from another peer |
| Root kind differs | Peers reject the connection with `RootMismatch` |
| Compatibility tag differs | Peers reject the connection before state exchange |
| Unsupported handle arrives | Receiver closes the bad peer and keeps local state |
| Snapshot exceeds limit | Import or peer transfer returns `SnapshotTooLarge` |
| Same replica identity appears twice | Reject the second session |
| All peers leave | Room state disappears unless a peer exported it |
| TURN-only network | Connects when the application supplies valid TURN config |

Required property tests:

- Shuffle and duplicate deltas for every eligible kernel.
- Interleave a full snapshot with deltas already represented in that snapshot.
- Merge snapshots in both directions and assert equal canonical snapshots.
- Generate channel registries in different orders and assert equal registries.
- Verify no CRDT kernel path calls `handle_sequenced`, `ack_local`, legacy
  summary upload, or membership callbacks, including through the relay.
- Deliver one delta through WebRTC and the relay in both orders and assert one
  state change.
- Switch transports during local mutation bursts and assert no lost delta,
  duplicate event, handle replacement, or pending acknowledgement.

## Follow-up capabilities

The first release should leave extension points for these features without
including them in its exit criteria.

### Highest priority

- **IndexedDB persistence.** Save the latest p2p snapshot and local replica
  identity, restore them after refresh, and merge restored state with connected
  peers. Specify transaction boundaries, quota errors, schema migration, and
  whether closing a room deletes local state. This changes the promise that a
  room disappears when its last peer leaves, so ship it as an explicit storage
  policy rather than a silent default.
- **Snapshot invitations.** Encode an exported snapshot in a file or invitation
  payload so a new room can start from known state without a persistent peer.
  Keep signaling credentials outside the snapshot and authenticate imported
  application tags before merge.
- **Sync observability.** Expose peer count, ICE state, selected candidate type,
  bootstrap progress, last digest match, repair count, bytes sent, and bytes
  received. Add these to status events before adding a telemetry backend.
- **Reference signaling service.** Provide authenticated room admission,
  bounded room membership, and opaque offer, answer, and ICE routing. Pin an
  integration test that proves document envelopes never enter the signaling
  process.

P2p presence, ripples, capability negotiation, compatibility tags, and the
deterministic mesh simulator already belong to the main delivery rungs. Do not
track them as follow-up work.

### Later

- **Application-level end-to-end encryption.** Encrypt document envelopes above
  WebRTC DTLS when peers should not trust TURN termination, browser extensions,
  or captured snapshot files. Define room-key distribution and rotation before
  choosing a cipher envelope.
- **Selective synchronization.** Let peers subscribe to chosen channels and
  request dependencies when a received handle crosses that boundary. This
  requires per-channel anti-entropy and clear semantics for partial snapshots.
- **Compact anti-entropy.** Replace full-state repair with per-channel requests,
  version vectors, or Merkle trees after measurements show snapshot transfer is
  the bottleneck.
- **Replica retirement and compaction.** Reclaim tombstones and causal metadata
  after proving that a retired replica cannot return with unseen state. This
  needs a durable membership or epoch protocol; a timeout is not sufficient.
- **Offline invitation exchange.** Support manual offer and answer bundles,
  copy-and-paste codes, or QR exchange for rooms that cannot use a signaling
  service. ICE candidates and credentials expire, so invitation UX must expose
  that lifetime.
- **Encrypted snapshot archive.** Let an optional service store opaque snapshots
  for rooms that do not configure a sequencer. Keep archival storage separate
  from peer discovery and document ordering.
- **Larger-room topology.** Add relay, SFU-assisted data routing, or gossip after
  full-mesh connection count or bandwidth becomes a measured limit. Preserve
  the same unordered merge protocol across topology changes.

## Non-goals

- Running DDS, OT, claims, queues, locks, quorum agreement, or last-writer-wins
  SharedMap in p2p mode.
- Replacing Floodgate or changing its legacy Fluid-compatible DDS protocol. The
  separate `crdt_relay_v1` capability is in scope.
- Hiding TURN or signaling infrastructure behind a claim of serverless
  connectivity.
- Supporting large rooms through a full mesh.
- Durable hosting after all peers leave when no sequencer or snapshot archive
  was configured.
- Electing a leader or assigning a total operation order.
- Making the existing typed SharedMap schema API work over an incompatible
  root.

## Exit criteria

The capability is complete when:

1. A browser creates and edits a room when no sequencer exists.
2. Two browser peers edit every eligible public structure and converge over
   WebRTC.
3. A sequencer attaches to that running room, merges its state, and becomes the
   primary durable relay without replacing the document or its handles.
4. The room keeps accepting edits during a sequencer outage and merges them
   when the sequencer returns.
5. Three peers converge after duplicate, reordered, relay-duplicated, and
   snapshot-interleaved delivery.
6. Two partitions accept offline edits and merge after one WebRTC edge returns.
7. Every unsupported channel fails at the API boundary and at both wire
   boundaries.
8. A late peer reconstructs the current registry and state without operation
   history.
9. The example documents its room-size, signaling, TURN, trust, transport, and
   durability constraints.
