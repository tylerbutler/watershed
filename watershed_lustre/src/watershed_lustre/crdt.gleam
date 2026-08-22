//// Lustre effect bindings for watershed's peer-to-peer CRDT facade
//// (`watershed/crdt_js`).
////
//// This module is the p2p equivalent of the sequenced bindings in
//// `watershed_lustre`. `crdt_js` uses callbacks in the same way as
//// `watershed`. `connect` takes an `on_ready` function and an `on_status`
//// function. `subscribe` takes a handler. A mutation broadcasts to the peers
//// and sends an event back to the subscribers of the same document
//// synchronously, and sometimes from inside a running Lustre `update` call.
//// This module owns that bridge, so an application never writes an
//// `effect.from` call around it.
////
//// Every effect takes `fn(...) -> msg` constructors from the caller, the same
//// as a `lustre/event` handler. The package owns the *scheduling*, and the
//// application owns its message vocabulary. Every inbound callback goes to a
//// microtask before the dispatch, always. That includes readiness, status, a
//// subscription event, the `Result` of a mutation, and a delivered
//// `CrdtConnection` or `Subscription` value. The sequenced bindings do the
//// same thing. A callback that watershed runs synchronously thus can never
//// overwrite the dispatch of the `update` call that it interrupted.
////
//// ## Naming
////
//// The names here are the same as in `watershed/crdt_js`. The *module
//// boundary* keeps them separate from the sequenced `subscribe_*` and
//// `ensure_*` effects in `watershed_lustre`.
//// `watershed_lustre.subscribe_pn_counter` binds a server-sequenced
//// `PnCounter` value. `watershed_lustre/crdt.subscribe_pn_counter` binds a
//// peer-to-peer one. The two take different handle types, which are
//// `watershed.PnCounter` and `crdt_js.Handle(PnCounterChannel)`, and you
//// cannot use one in place of the other. A qualified import
//// (`import watershed_lustre/crdt`) thus reads unambiguously, and the compiler
//// refuses a handle that you pass to the wrong stack.
////
//// ## What stays on `crdt_js`
////
//// This module wraps the callback-shaped and effectful surface only. Four
//// groups stay on `crdt_js`, and you call them directly. They are the pure
//// configuration (`crdt_js.config`, `with_transport_policy`, `with_sequencer`,
//// `with_ice_servers`, and `sequencer`), the synchronous reads
//// (`pn_counter_value`, `or_set_values`, `text_value`, and others), the
//// channel registration (`create_channel`, `resolve_channel`, `root`, and
//// `address`), and the diagnostics (`peer_count`, `digest`, `readiness`,
//// `policy`, `effective_path`, and others). None of them needs scheduling,
//// and a wrapper would only repeat a pure API.
////
//// The mutations also stay on `crdt_js`. An application composes the typed
//// edit with `perform`, which owns the scheduling. To observe the transport
//// policy, read the `status` stream that `connect` delivers, and then call
//// `crdt_js.effective_path`.
////
//// ```gleam
//// import watershed/crdt_js
//// import watershed/p2p
//// import watershed_lustre/crdt
////
//// // in init: join the room
//// crdt.connect(
////   config,
////   connection: Retained,
////   ready: Connected,
////   status: StatusChanged,
//// )
////
//// // after Connected(Ok(document)): watch the root counter
//// crdt.subscribe_pn_counter(crdt_js.root(document), Watching, Bumped)
////
//// // on a click: author an edit; the subscription reports the new total
//// crdt.perform(fn() { crdt_js.pn_counter_update(counter, 1) }, Clapped)
//// ```
////
//// JavaScript target only.

import gleam/json.{type Json}
import gleam/option.{None, Some}

import lustre/effect.{type Effect}

import watershed/crdt_js.{
  type Config, type CrdtConnection, type CrdtDocument, type Handle, type Status,
  type Subscription,
}
import watershed/g_set_kernel
import watershed/or_map_kernel
import watershed/or_set_kernel
import watershed/p2p.{type P2pError}
import watershed/p2p_transport_js.{type Rtc}
import watershed/persist_controller_js
import watershed/persist_js
import watershed/pn_counter_kernel
import watershed/schema
import watershed/sequence_kernel
import watershed/text_kernel
import watershed/two_p_set_kernel

@external(javascript, "../watershed_lustre_ffi.mjs", "queue_microtask")
fn queue_microtask(action: fn() -> Nil) -> Nil

// ── Connect & lifecycle ──────────────────────────────────────────────────────

/// What the disk-first open found before the module attempted the network.
pub type PersistenceStatus {
  NoLocalSnapshot
  LocalSnapshotReady
  PersistenceFailed(error: persist_js.PersistenceError)
}

/// Open from IndexedDB first, and then treat the network as an addition.
///
/// A valid local snapshot dispatches `ready` before the network can succeed or
/// fail, so a user can edit the application offline immediately. Without a
/// usable local value, this function behaves as the ordinary `connect`. The
/// function reports stored bytes that it cannot load, and it keeps them in
/// storage.
pub fn open(
  storage: persist_js.Storage,
  config: Config(root),
  connection connection: fn(CrdtConnection) -> msg,
  ready ready: fn(Result(CrdtDocument(root), P2pError)) -> msg,
  status status: fn(Status) -> msg,
  persistence persistence: fn(PersistenceStatus) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  persist_js.load(storage, config, fn(loaded) {
    case loaded {
      Ok(Some(document)) -> {
        let held =
          crdt_js.attach(
            document,
            on_ready: fn(_network_ready) { Nil },
            on_status: fn(update) {
              queue_microtask(fn() {
                queue_microtask(fn() { dispatch(status(update)) })
              })
            },
          )
        queue_microtask(fn() {
          dispatch(persistence(LocalSnapshotReady))
          dispatch(connection(held))
          queue_microtask(fn() { dispatch(ready(Ok(document))) })
        })
      }
      Ok(None) -> {
        queue_microtask(fn() { dispatch(persistence(NoLocalSnapshot)) })
        let held =
          crdt_js.connect(
            config,
            on_ready: fn(outcome) {
              queue_microtask(fn() {
                queue_microtask(fn() { dispatch(ready(outcome)) })
              })
            },
            on_status: fn(update) {
              queue_microtask(fn() { dispatch(status(update)) })
            },
          )
        queue_microtask(fn() { dispatch(connection(held)) })
      }
      Error(error) -> {
        queue_microtask(fn() { dispatch(persistence(PersistenceFailed(error))) })
        let held =
          crdt_js.connect(
            config,
            on_ready: fn(outcome) {
              queue_microtask(fn() {
                queue_microtask(fn() { dispatch(ready(outcome)) })
              })
            },
            on_status: fn(update) {
              queue_microtask(fn() { dispatch(status(update)) })
            },
          )
        queue_microtask(fn() { dispatch(connection(held)) })
      }
    }
  })
}

/// Join a room. The function builds the document that `Config` describes and
/// connects it. `crdt_js.connect` is synchronous, so the document exists
/// before this effect returns, but its handle arrives through `ready`.
///
/// `connection` runs one time, with the `CrdtConnection` value to keep in your
/// model. A later `close` call, or a re-`attach` of a snapshot, then has a
/// value to act on. `ready` runs exactly one time. It gives `Ok(document)`
/// when the state of the room merges, or immediately when this replica is
/// alone. It gives `Error(reason)` when the join fails. `status` runs for the
/// whole lifetime of the connection. All three go to a microtask before the
/// dispatch, and `connection` always arrives before `ready`. An application
/// thus holds the handle that `close` needs before it learns that the room is
/// usable.
pub fn connect(
  config: Config(root),
  connection connection: fn(CrdtConnection) -> msg,
  ready ready: fn(Result(CrdtDocument(root), P2pError)) -> msg,
  status status: fn(Status) -> msg,
) -> Effect(msg) {
  establish(
    fn(on_ready, on_status) { crdt_js.connect(config, on_ready, on_status) },
    connection,
    ready,
    status,
  )
}

/// Bring a document that already exists online. That document is the one that
/// `import_snapshot` returns, or any `crdt_js.new_document` value. A handle and
/// a subscription that you took before the attach stay valid. The function
/// delivers `connection`, `ready`, and `status` exactly as `connect` does. Each
/// one goes to a microtask, and `connection` arrives first.
pub fn attach(
  document: CrdtDocument(root),
  connection connection: fn(CrdtConnection) -> msg,
  ready ready: fn(Result(CrdtDocument(root), P2pError)) -> msg,
  status status: fn(Status) -> msg,
) -> Effect(msg) {
  establish(
    fn(on_ready, on_status) { crdt_js.attach(document, on_ready, on_status) },
    connection,
    ready,
    status,
  )
}

/// `attach` against a replacement browser seam. A test can thus drive the
/// bootstrap order and the merge behaviour deterministically, and it needs no
/// browser. This is the same seam that `crdt_js.attach_with_rtc` gives, for the
/// same reason. Production code must use `connect` or `attach`.
pub fn attach_with_rtc(
  document: CrdtDocument(root),
  connection connection: fn(CrdtConnection) -> msg,
  ready ready: fn(Result(CrdtDocument(root), P2pError)) -> msg,
  status status: fn(Status) -> msg,
  rtc rtc: Rtc,
) -> Effect(msg) {
  establish(
    fn(on_ready, on_status) {
      crdt_js.attach_with_rtc(document, on_ready, on_status, rtc)
    },
    connection,
    ready,
    status,
  )
}

/// The one shape that the three ways to come online share. Run the `crdt_js`
/// call, put its callbacks in a microtask, and deliver the `CrdtConnection`
/// value through `connection`, before `ready`.
///
/// `ready` goes one microtask *deeper* than everything else. When the readiness
/// resolves synchronously, which occurs for a replica that is alone,
/// `on_ready` runs inside `run`, before the code below can queue the
/// `connection` dispatch. The extra step moves `ready` after that dispatch, so
/// an application always keeps the `CrdtConnection` value before it learns
/// that the room is usable. When the readiness resolves later, the extra step
/// delays `ready` by one microtask only.
fn establish(
  run: fn(fn(Result(CrdtDocument(root), P2pError)) -> Nil, fn(Status) -> Nil) ->
    CrdtConnection,
  connection: fn(CrdtConnection) -> msg,
  ready: fn(Result(CrdtDocument(root), P2pError)) -> msg,
  status: fn(Status) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let held =
    run(
      fn(outcome) {
        queue_microtask(fn() {
          queue_microtask(fn() { dispatch(ready(outcome)) })
        })
      },
      fn(update) { queue_microtask(fn() { dispatch(status(update)) }) },
    )
  queue_microtask(fn() { dispatch(connection(held)) })
}

/// Leave the signaling, close every peer, remove every subscription, and stop
/// the document. A second call has no more effect. The effect returns nothing.
/// A readiness that is still open resolves through the `ready` callback that
/// opened the connection.
pub fn close(connection: CrdtConnection) -> Effect(msg) {
  use _dispatch <- effect.from
  crdt_js.close(connection)
}

/// Start the digest-gated local persistence for a document that is ready.
pub fn start_persistence(
  storage: persist_js.Storage,
  document: CrdtDocument(root),
  started: fn(persist_controller_js.Controller(root)) -> msg,
  status: fn(persist_controller_js.Status) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let controller =
    persist_controller_js.start(storage, document, fn(update) {
      queue_microtask(fn() { dispatch(status(update)) })
    })
  queue_microtask(fn() { dispatch(started(controller)) })
}

/// Tell the save controller that a local mutation can have occurred.
pub fn persistence_changed(
  controller: persist_controller_js.Controller(root),
) -> Effect(msg) {
  use _dispatch <- effect.from
  persist_controller_js.changed(controller)
}

/// Stop the local persistence timers and the page lifecycle handling.
pub fn stop_persistence(
  controller: persist_controller_js.Controller(root),
) -> Effect(msg) {
  use _dispatch <- effect.from
  persist_controller_js.stop(controller)
}

// ── Subscriptions ────────────────────────────────────────────────────────────
//
// One per eligible CRDT kind, mirroring `crdt_js`'s narrowed `subscribe_*` —
// the per-kind names carry the event typing. Each delivers the kind's own
// event type — never the whole `ChannelEvent` union — deferred to a microtask,
// and hands back the `Subscription` through `subscribed` (also deferred) so an
// app can retain it for `unsubscribe`.

/// The one shape that every `subscribe_*` function shares. Take the `crdt_js`
/// subscribe function of that kind, with its handler not applied yet, put each
/// event in a microtask, and deliver the `Subscription` value through
/// `subscribed`, also in a microtask.
fn subscribe(
  run: fn(fn(event) -> Nil) -> Subscription,
  subscribed: fn(Subscription) -> msg,
  event: fn(event) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let subscription =
    run(fn(inner) { queue_microtask(fn() { dispatch(event(inner)) }) })
  queue_microtask(fn() { dispatch(subscribed(subscription)) })
}

/// Subscribe to a peer-to-peer PN counter. `event` receives every local and
/// remote `pn_counter_kernel.PnCounterEvent` value.
pub fn subscribe_pn_counter(
  handle: Handle(schema.PnCounterChannel),
  subscribed subscribed: fn(Subscription) -> msg,
  event event: fn(pn_counter_kernel.PnCounterEvent) -> msg,
) -> Effect(msg) {
  subscribe(crdt_js.subscribe_pn_counter(handle, _), subscribed, event)
}

/// Subscribe to a peer-to-peer OR-map.
pub fn subscribe_or_map(
  handle: Handle(schema.OrMapChannel),
  subscribed subscribed: fn(Subscription) -> msg,
  event event: fn(or_map_kernel.OrMapEvent) -> msg,
) -> Effect(msg) {
  subscribe(crdt_js.subscribe_or_map(handle, _), subscribed, event)
}

/// Subscribe to a peer-to-peer OR-set.
pub fn subscribe_or_set(
  handle: Handle(schema.OrSetChannel),
  subscribed subscribed: fn(Subscription) -> msg,
  event event: fn(or_set_kernel.OrSetEvent) -> msg,
) -> Effect(msg) {
  subscribe(crdt_js.subscribe_or_set(handle, _), subscribed, event)
}

/// Subscribe to a peer-to-peer grow-only set. `ElementAdded` is the only event
/// that this channel produces, because a G-set has no remove operation.
pub fn subscribe_g_set(
  handle: Handle(schema.GSetChannel),
  subscribed subscribed: fn(Subscription) -> msg,
  event event: fn(g_set_kernel.GSetEvent) -> msg,
) -> Effect(msg) {
  subscribe(crdt_js.subscribe_g_set(handle, _), subscribed, event)
}

/// Subscribe to a peer-to-peer two-phase set, which produces `ElementAdded`
/// and `ElementRemoved`. A removal is permanent. You cannot add an element
/// again after you remove it.
pub fn subscribe_two_p_set(
  handle: Handle(schema.TwoPSetChannel),
  subscribed subscribed: fn(Subscription) -> msg,
  event event: fn(two_p_set_kernel.TwoPSetEvent) -> msg,
) -> Effect(msg) {
  subscribe(crdt_js.subscribe_two_p_set(handle, _), subscribed, event)
}

/// Subscribe to a peer-to-peer sequence. `event` receives every
/// `sequence_kernel.SequenceEvent` value, which carries the full list of
/// values after the edit. An insert, a delete, a move, and a replace all
/// arrive in the same form.
pub fn subscribe_sequence(
  handle: Handle(schema.SequenceChannel),
  subscribed subscribed: fn(Subscription) -> msg,
  event event: fn(sequence_kernel.SequenceEvent) -> msg,
) -> Effect(msg) {
  subscribe(crdt_js.subscribe_sequence(handle, _), subscribed, event)
}

/// Subscribe to a peer-to-peer text channel. `event` receives every
/// `text_kernel.TextEvent` value, which is a `TextChanged` event that carries
/// the full string after the edit. An insert, a delete, a replace, and an
/// append all arrive in the same form.
pub fn subscribe_text(
  handle: Handle(schema.TextChannel),
  subscribed subscribed: fn(Subscription) -> msg,
  event event: fn(text_kernel.TextEvent) -> msg,
) -> Effect(msg) {
  subscribe(crdt_js.subscribe_text(handle, _), subscribed, event)
}

/// Remove one subscription from the functions above. A second call has no more
/// effect. Use this function to clean up one channel while the document stays
/// connected. `close` removes every subscription.
pub fn unsubscribe(subscription: Subscription) -> Effect(msg) {
  use _dispatch <- effect.from
  crdt_js.unsubscribe(subscription)
}

// ── Mutations ────────────────────────────────────────────────────────────────

/// Run one effectful `crdt_js` operation *when Lustre performs the effect*,
/// and never when your code builds that effect inside `update`. The function
/// then delivers the result through the message constructor of the caller, in
/// a microtask. The outcome thus reaches `dispatch` in the same way as every
/// other callback here. `operation` is a thunk, so the edit, the broadcast,
/// and the fan-out to the subscribers all happen in the effect phase, and not
/// while `update` still runs.
///
/// This function is the whole mutation surface. Compose it with the typed
/// `crdt_js` edit directly. Do not look for a wrapper for each edit.
///
/// ```gleam
/// crdt.perform(fn() { crdt_js.pn_counter_update(counter, 1) }, Clapped)
/// crdt.perform(fn() { crdt_js.or_map_set(map, key: "k", value: "v") }, Wrote)
/// ```
///
/// The function passes the `Result` value through without a change. An edit
/// that the channel does not support, or that is invalid, stays an `Error`. It
/// never becomes an `Ok`.
pub fn perform(
  operation operation: fn() -> a,
  outcome outcome: fn(a) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let result = operation()
  queue_microtask(fn() { dispatch(outcome(result)) })
}

// ── Snapshots ────────────────────────────────────────────────────────────────

/// Export the whole snapshot that `import_snapshot` can read, which is the full
/// CRDT state of every channel in canonical order, and deliver it through
/// `exported`, in a microtask. The moment of the capture is effectful, because
/// it reads the live state of the document. This is thus an effect, and not a
/// pure read. Dispatch it when you intend to store the result.
pub fn export_snapshot(
  document: CrdtDocument(root),
  exported exported: fn(Result(Json, P2pError)) -> msg,
) -> Effect(msg) {
  perform(fn() { crdt_js.export_snapshot(document) }, exported)
}

/// Build a detached document again from an exported snapshot, and deliver it
/// through `imported`, in a microtask. The function checks the size, the
/// protocol, the room, the compatibility, the root type, and the eligibility of
/// every channel, before it loads a channel. On an `Ok` result, give the
/// document to `attach` to bring it online.
pub fn import_snapshot(
  config: Config(root),
  snapshot: Json,
  imported imported: fn(Result(CrdtDocument(root), P2pError)) -> msg,
) -> Effect(msg) {
  perform(fn() { crdt_js.import_snapshot(config, snapshot) }, imported)
}
