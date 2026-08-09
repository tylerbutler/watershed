# Server-backed presence plan

**Date:** 2026-08-08
**Builds on:** `2026-07-06-typed-presence-plan.md` (the current ripple-backed
driver), Beryl's `beryl/presence` actor and Phoenix-compatible presence diffs,
and Floodgate's document channel connection lifecycle.
**Touches:** Floodgate, Watershed, `watershed_lustre`, and the browser examples.
Uses Beryl through its existing public API.

## Goal

Watershed should present one presence model with two implementations:

1. **Server presence** uses Beryl for connection membership, snapshots,
   joins, leaves, multiple sessions per user, and cross-node replication.
2. **Ripple presence** preserves the current heartbeat and TTL behavior when a
   compatible server does not offer presence.

Applications should use one typed Watershed API shaped after Beryl's public
types. Raw ripples remain public for cursor motion, reactions, focus changes,
and other signals that do not need membership semantics.

## Why change the current model

`watershed/presence_js` sends a typed payload every two seconds. Each browser
builds its own roster and removes a peer after 6.5 seconds without a heartbeat.
That implementation works without server presence support, but it has four
limits:

- A late joiner waits for each peer's next heartbeat.
- Background timer throttling can make a connected peer disappear.
- The roster stores one entry per user, so two tabs from the same user replace
  each other.
- Each browser computes liveness independently and can show a different roster.

Beryl already tracks a presence by topic, user key, session ID, and metadata.
It emits Phoenix-compatible `presence_diff` values, lists the current topic,
and merges presence state across Beryl nodes with `lattice_presence`.

Floodgate should use that public API directly. Watershed needs a browser-side
representation because Beryl's `Presence` handle and calls run on the BEAM and
cannot cross a socket. The client types should mirror Beryl rather than define
a second presence domain model.

Watershed cannot implement server presence by itself. Only Floodgate can bind
an authenticated user to a server-assigned session, observe socket closure,
call Beryl during connection lifecycle changes, and distribute a current
snapshot. Beryl owns the presence engine; Floodgate supplies those lifecycle
calls; Watershed consumes the resulting wire events.

## Decisions to confirm before SP1

1. **The server owns identity and session IDs.** Floodgate derives the presence
   key from the authenticated `user_id` and the session ID from the document
   connection's server-assigned client ID. A client can submit metadata, but
   it cannot claim another user or session.
2. **Presence stays opt-in per document connection.** Starting a Watershed
   presence handle sends `joinPresence`. Stopping it sends `leavePresence`.
   Floodgate also removes every presence owned by a socket when it closes.
3. **Version one supports one presence registration per document connection.**
   Applications put panel, cursor, selection, and activity fields inside one
   typed metadata value. Named presence spaces can come later if a real app
   needs independent rosters.
4. **The public state includes the local session.** Server snapshots and
   Phoenix diffs include it. Watershed provides a helper that filters by the
   local session ID for interfaces that only render peers.
5. **Watershed mirrors Beryl's public data model.** Its client
   `PresenceEntry(a)` has Beryl's `session_id`, `key`, and `meta` fields, with
   `meta: a` instead of `meta: Json`. Its opaque `Diff(a)` uses Beryl-style
   join and leave accessors. Watershed does not expose actor handles, PubSub
   values, CRDT state, or tracking refs.
6. **Capability negotiation selects the implementation.** `Auto` chooses
   server presence when Floodgate advertises `presence_v1`; otherwise it starts
   the ripple driver. `Server` returns an unsupported error instead of falling
   back. `Ripple` forces the heartbeat driver for tests and compatibility.
7. **Ripples keep their current contract.** Server presence does not replace
   `submit_ripple` or `subscribe_ripples`. Applications should send membership
   and low-frequency status through presence, then send high-frequency cursor
   motion through ripples.
8. **Server mode sends metadata only when it changes.** It has no browser
   heartbeat. Beryl and the channel connection own liveness.

## Client model

Mirror Beryl's public values at the network boundary:

```gleam
pub type PresenceEntry(a) {
  PresenceEntry(session_id: String, key: String, meta: a)
}

pub opaque type Diff(a)

pub fn diff_joins(diff: Diff(a)) -> List(PresenceEntry(a))
pub fn diff_leaves(diff: Diff(a)) -> List(PresenceEntry(a))

pub type Event(a) {
  State(entries: List(PresenceEntry(a)))
  Changed(diff: Diff(a), entries: List(PresenceEntry(a)))
}
```

This matches Beryl's transparent `PresenceEntry` and opaque `Diff`. The
document topic stays out of the client values because one Watershed document
connection already fixes the topic.

`session_id` identifies one tab, device, CLI process, or reconnect
incarnation. `key` groups sessions for one authenticated user. Applications
can group the flat entry list when they need a user-level view; Watershed
should not make that projection its core model.

The pure client state keeps the current entries plus the wire-only `phx_ref`
needed to apply Phoenix diffs. It:

- replaces its entries when `presence_state` arrives;
- applies joins and leaves by `phx_ref`;
- queues diffs received before the initial state;
- ignores duplicate states and diffs;
- sorts public entries by key and session ID.

Watershed strips `phx_ref` and other reserved fields before running the
application's metadata decoder.

## Public client API

Keep the pure state and codec code in `watershed/presence`. Put target drivers
in `watershed/presence_js` and, once needed, `watershed/presence_erlang`.

```gleam
pub type Mode {
  Auto
  Server
  Ripple
}

pub opaque type Config(a)

pub fn config(
  encode: fn(a) -> Json,
  decode: Decoder(a),
) -> Config(a)

pub fn with_mode(config: Config(a), mode: Mode) -> Config(a)

pub fn with_ripple_timing(
  config: Config(a),
  heartbeat_ms: Int,
  ttl_ms: Int,
) -> Config(a)

pub opaque type Handle(a)

pub fn start(
  document: Document(root),
  config: Config(a),
  initial: a,
  on_event: fn(Event(a)) -> Nil,
) -> Result(Handle(a), PresenceError)

pub fn update(handle: Handle(a), meta: a) -> Nil
pub fn stop(handle: Handle(a)) -> Nil
pub fn mode(handle: Handle(a)) -> Mode
```

The final `Document(root)` signature assumes the document root-tag plan lands
first. Use the current unparameterized `Document` if presence lands before it.

Pure helpers:

```gleam
pub fn by_key(
  entries: List(PresenceEntry(a)),
  key: String,
) -> List(PresenceEntry(a))
pub fn remote_entries(
  entries: List(PresenceEntry(a)),
  local_session: String,
) -> List(PresenceEntry(a))
```

`start` takes an initial metadata value so server mode can join once and ripple
mode can begin heartbeating without a separate race between `start` and
`announce`. Rename the current `announce` call sites to `update`.

## Client and server wire contract

Floodgate advertises support in `connect_document_success`:

```json
{
  "capabilities": {
    "presence_v1": true
  }
}
```

If the existing success payload already has a capability collection, extend
that collection instead of adding a second field.

### Client to server

`joinPresence`:

```json
{
  "meta": {
    "panel": "sudoku",
    "cell": "r2c4",
    "editing": true
  }
}
```

`updatePresence` uses the same payload. `leavePresence` carries an empty
object. Floodgate rejects join and update calls before document authentication
finishes.

The client never sends `key`, `session_id`, or `phx_ref`.

### Server to client

Initial `presence_state`:

```json
{
  "user:alice": {
    "metas": [
      {
        "phx_ref": "A1",
        "client_id": "client-17",
        "panel": "sudoku"
      }
    ]
  }
}
```

Incremental `presence_diff`:

```json
{
  "joins": {
    "user:bob": {
      "metas": [
        {
          "phx_ref": "B1",
          "client_id": "client-42",
          "panel": "text"
        }
      ]
    }
  },
  "leaves": {}
}
```

Floodgate injects `client_id` beside `phx_ref`. Watershed uses it as
`PresenceEntry.session_id`. The application metadata decoder does not see
either reserved field.

Floodgate should preserve Beryl's Phoenix wire shape. Phoenix clients can then
use their standard Presence helper against the same events.

## Beryl integration

Beryl already has the typed server API. This plan requires no Beryl changes.
Floodgate uses:

- `track` creates one topic, key, session, and metadata entry and returns its
  tracking ref.
- `untrack` removes one tracked entry.
- `untrack_all` cleans up a disconnected session.
- `list` returns the entries needed to construct `presence_state`.
- `with_on_diff`, `diff_topics`, `diff_joins`, and `diff_leaves` expose changes
  without exposing CRDT state.
- `with_pubsub` handles cross-node replication.
- `broadcast_presence_diff` sends Phoenix-compatible diffs through Beryl's
  channel broadcast path.

Floodgate groups `presence.list` results into the Phoenix
`{key: {metas: [...]}}` state shape because Floodgate owns the client
protocol. It passes Beryl `PresenceEntry` and `Diff` values through their
public accessors instead of reconstructing presence state.

Beryl has no public metadata-update call. Floodgate implements an update by
calling `untrack` with the stored ref, then `track` with the same topic, key,
and session ID plus the new metadata. Beryl emits a leave followed by a join
and returns a new ref, which Floodgate stores. Phoenix presence clients already
understand that sequence.

Floodgate serializes update and disconnect commands so an update cannot
recreate a presence after cleanup. A later Beryl `update` API could reduce the
sequence to one actor call and one combined diff, but version one does not
require it.

Beryl remains unchanged. Its typed API stays on the BEAM side of the socket.
Floodgate replaces caller-supplied `client_id` before calling `track`; Beryl
already replaces caller-supplied `phx_ref`.

## Floodgate work

Floodgate connects Beryl's server registry to the Fluid-compatible document
channel.

### Presence worker

Add an application-owned worker that calls Beryl outside Floodgate's shared
socket update path. Beryl documents this integration pattern because its
public mutation and read calls can wait up to five seconds.

The worker owns:

- the Beryl `Presence` handle;
- the mapping from document connection to Beryl tracking ref;
- serialized join, update, leave, and disconnect cleanup;
- the initial snapshot request;
- delivery of results back to the document channel process.

Floodgate may use an existing application worker if its runtime has one. This
plan does not require a new adapter framework or a second presence service.

The worker derives:

- `topic` from Floodgate's canonical document channel topic;
- `key` from the authenticated connect message's `user_id`;
- `session_id` from Floodgate's server-assigned client ID;
- `meta` from the client payload after replacing reserved fields.

### Join ordering

Use Phoenix's state-plus-diff synchronization model:

1. The Watershed client subscribes to presence events before sending
   `joinPresence`.
2. Floodgate asks the worker for the current topic snapshot.
3. Floodgate sends `presence_state` to that client.
4. The worker tracks the local session.
5. Beryl's `on_diff` callback broadcasts the join as `presence_diff`.

A remote diff can arrive before the snapshot. Watershed queues it until
`presence_state` arrives, then applies it. This removes the need to lock the
topic while taking a snapshot.

### Cleanup

- `leavePresence` removes the stored tracking ref.
- Closing the document channel calls `untrack_all(client_id)`.
- Rejoining after reconnect creates a new server client ID and session.
- Duplicate leave and cleanup commands act as no-ops.
- An update queued behind a disconnect must not recreate the presence.

### Distributed delivery

Start Beryl Presence with the same PubSub topology that Floodgate uses for
channel broadcasts. The Beryl `on_diff` callback iterates over changed
document topics and calls `beryl.broadcast_presence_diff`.

Floodgate sends `presence_state` directly to the joining socket. It broadcasts
`presence_diff` through Beryl so sockets on other Floodgate nodes receive the
same change.

## Ripple fallback

Refactor the current fallback around the same `PresenceEntry`, `Diff`, and
`Event` types.

The fallback envelope becomes:

```json
{
  "kind": "presence",
  "key": "user:alice",
  "meta": {
    "panel": "sudoku"
  }
}
```

The receiver uses the ripple's server-stamped `client_id` as `session_id`.
This fixes the current one-entry-per-user behavior and lets two tabs from the
same user coexist.

The fallback still:

- sends the current metadata every `heartbeat_ms`;
- expires each session after `ttl_ms`;
- starts with no snapshot;
- derives joins, metadata replacements, and TTL leaves from local observation;
- produces Beryl-shaped `PresenceEntry(a)` and `Diff(a)` values.

Do not hide the semantic difference. `mode(handle)` lets diagnostics and tests
report which implementation runs. The website should state that ripple mode
offers soft presence and server mode offers connection-backed presence.

## Watershed runtime work

Both runtime targets need a presence event lane beside operations and ripples:

- decode `presence_state`;
- decode `presence_diff`;
- register presence subscribers;
- store the negotiated `presence_v1` capability;
- send join, update, and leave commands;
- keep presence events out of operation sequencing, summaries, reconnect
  resubmission, and DDS kernels.

Presence commands use request acknowledgements for protocol errors, unlike
ripples. A rejected join or update must reach `on_event` as an error or stop the
handle with a surfaced error. Do not turn a failed server join into silent
ripple fallback after `Auto` has selected server mode.

On reconnect:

1. Mark the prior server session unavailable.
2. Wait for the new document handshake and capabilities.
3. Send a fresh `joinPresence` with the latest metadata.
4. Replace local state from the new `presence_state`.

The runtime should not replay stale presence diffs across reconnects.

## Lustre binding

Replace the current presence effect with one that carries the negotiated mode
and typed events:

```gleam
pub fn presence(
  document: Document(root),
  config: presence.Config(a),
  initial: a,
  on_event: fn(presence.Event(a)) -> msg,
) -> Effect(msg)

pub fn update_presence(handle: presence_js.Handle(a), meta: a) -> Effect(msg)
pub fn stop_presence(handle: presence_js.Handle(a)) -> Effect(msg)
```

The binding should keep callback deferral at the Lustre boundary, as it does
today, so presence callbacks cannot dispatch during `update`.

## Delivery rungs

- **SP1: Beryl-shaped client model.** Add generic `PresenceEntry`, opaque
  `Diff`, and `Event`; implement state and diff application; add reserved-field
  decoding. Keep the old driver working through a temporary compatibility
  layer. Gate: pure tests pass on Erlang and JavaScript targets.
- **SP2: Floodgate presence worker.** Start Beryl Presence under supervision,
  derive trusted identity fields, implement join/update/leave/cleanup, and
  group `presence.list` results into state payloads. Gate: two sockets on one
  node receive state and diffs; a disconnect emits one leave.
- **SP3: Cross-node Floodgate presence.** Connect Beryl to PubSub and test two
  sockets on separate Floodgate nodes. Gate: join, update, disconnect, and node
  restart converge without duplicate sessions.
- **SP4: Capability and wire lane.** Add `presence_v1`, event codecs, command
  acknowledgements, and runtime subscriber plumbing in both Watershed targets.
  Gate: wire fixture tests match Floodgate exactly.
- **SP5: Server driver.** Implement `Mode.Server` and `Mode.Auto`, including
  diff buffering before state and rejoin after reconnect. Gate: a late third
  client receives both existing sessions without waiting for a heartbeat.
- **SP6: Session-aware ripple fallback.** Port the heartbeat driver to the new
  entry and diff model and use `ripple_client_id` as the session ID. Gate: two
  tabs with the same user key remain separate and expire independently.
- **SP7: Lustre and examples.** Migrate `watershed_lustre`, sudoku, text, and
  the showcase plan's shared roster. Gate: examples build in server and forced
  ripple modes.
- **SP8: Documentation and observability.** Update the guide, runtime page,
  module docs, and ecosystem diagram. Add mode, roster size, join failures, and
  decode failures to existing telemetry hooks.
- **SP9: Remove the compatibility API.** Delete `announce`, the old
  `Peer(last_seen)` public shape, and direct heartbeat configuration from the
  default path after all in-repo callers migrate.

## Test matrix

| Case | Server mode | Ripple mode |
| --- | --- | --- |
| Initial local session | State plus own join diff | Local synthetic session |
| Late join | Immediate full state | Next peer heartbeat |
| Two tabs, one user | Two sessions under one member | Two ripple client IDs |
| Metadata update | Leave and join for one `phx_ref` | Local replacement event |
| Clean stop | Immediate leave | TTL expiry for remote peers |
| Socket loss | Disconnect cleanup | TTL expiry |
| Reconnect | New session and fresh state | New ripple client ID |
| Cross-node | Beryl CRDT and PubSub | Floodgate signal broadcast |
| Malformed metadata | Drop entry and report decode error | Drop heartbeat and report decode error |

Required focused tests:

- Apply diffs that arrive before the initial state.
- Remove one of two sessions under the same key.
- Reject a client-supplied key, client ID, or `phx_ref`.
- Process an update racing with disconnect without resurrecting a session.
- Reconnect while metadata changes and join with the latest value.
- Force `Server` against a server without `presence_v1` and return
  `UnsupportedPresence`.
- Select ripple mode under `Auto` only when the handshake lacks the capability.
- Keep raw ripple traffic independent from presence traffic.

## Migration

Current code:

```gleam
let handle =
  presence_js.start(
    document,
    user_id,
    presence.default_config,
    encode,
    decoder,
    on_change,
  )

presence_js.announce(handle, payload)
```

New code:

```gleam
let config =
  presence.config(encode, decoder)
  |> presence.with_mode(presence.Auto)

let assert Ok(handle) =
  presence_js.start(document, config, payload, on_event)

presence_js.update(handle, next_payload)
```

Applications that rendered `List(Peer(a))` should render
`presence.remote_entries(entries, local_session)`. Applications that want one
row per user can group entries by `key`.

## Non-goals

- Do not send cursor motion through Beryl on every pointer event.
- Do not expose Beryl actor handles, PubSub values, CRDT clocks, or tracking
  refs to Watershed clients.
- Do not invent a client domain model that diverges from Beryl's
  `PresenceEntry` and `Diff`.
- Do not persist presence in document summaries or operation history.
- Do not promise identical failure timing between server and ripple modes.
- Do not add named presence spaces until an application needs more than one
  roster per document.

## Exit criteria

The model is complete when:

1. A late browser receives the current roster in one state event.
2. Two sessions for one user survive independent updates and leaves.
3. A socket disconnect removes its Beryl presence without a browser heartbeat.
4. Two Floodgate nodes publish one converged roster through Beryl.
5. Watershed applications run unchanged against a server with
   `presence_v1` and a server that only supports ripples.
6. Raw ripples still carry high-frequency ephemeral activity without touching
   the presence registry.
