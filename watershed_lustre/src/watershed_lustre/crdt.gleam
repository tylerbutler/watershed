//// Lustre effect bindings for watershed's peer-to-peer CRDT facade
//// (`watershed/crdt_js`).
////
//// This is the p2p counterpart of the sequenced bindings in
//// `watershed_lustre`. `crdt_js` is callback-shaped the same way `watershed_js`
//// is — `connect` takes an `on_ready` and an `on_status`, `subscribe` takes a
//// handler, mutations broadcast to peers and fan an event back to the same
//// document's subscribers synchronously, sometimes from inside a running
//// Lustre `update`. This module owns that bridging so an app never hand-writes
//// an `effect.from` around it.
////
//// Every effect takes caller-supplied `fn(...) -> msg` constructors, the way
//// `lustre/event` handlers do: the package owns *scheduling*, the app owns its
//// message vocabulary. Every inbound callback — readiness, status, a
//// subscription event, a mutation's `Result`, a delivered `CrdtConnection` or
//// `Subscription` — is unconditionally deferred to a microtask before dispatch,
//// exactly like the sequenced bindings, so a callback watershed fires
//// synchronously can never clobber the dispatch of the `update` it interrupted.
////
//// ## Naming
////
//// The names here mirror `watershed/crdt_js`, and the *module boundary* is what
//// keeps them from colliding with the sequenced `subscribe_*`/`ensure_*`
//// effects in `watershed_lustre`: `watershed_lustre.subscribe_pn_counter` binds
//// a server-sequenced `PnCounter`, `watershed_lustre/crdt.subscribe_pn_counter`
//// binds a peer-to-peer one. The two take different, non-interchangeable handle
//// types (`watershed_js.PnCounter` vs `crdt_js.Handle(PnCounterChannel)`), so a
//// qualified import (`import watershed_lustre/crdt`) reads unambiguously and the
//// compiler rejects a handle passed to the wrong stack.
////
//// ## What stays on `crdt_js`
////
//// This module wraps only the callback-shaped and effectful surface. Pure
//// configuration (`crdt_js.config`, `with_transport_policy`, `with_sequencer`,
//// `with_ice_servers`, `sequencer`), synchronous reads (`pn_counter_value`,
//// `or_set_values`, `text_value`, …), channel registration (`create_channel`,
//// `resolve_channel`, `root`, `address`), and diagnostics (`peer_count`,
//// `digest`, `readiness`, `policy`, `effective_path`, …) stay on `crdt_js` and
//// are called directly: they need no scheduling and wrapping them would only
//// duplicate a pure API. Mutations stay on `crdt_js` too — an app composes the
//// typed edit with `perform`, which owns the scheduling. Transport policy is
//// observed through the `status` stream that `connect` delivers and read back
//// with `crdt_js.effective_path`.
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
import watershed/pn_counter_kernel
import watershed/schema
import watershed/sequence_kernel
import watershed/text_kernel
import watershed/two_p_set_kernel

@external(javascript, "../watershed_lustre_ffi.mjs", "queue_microtask")
fn queue_microtask(action: fn() -> Nil) -> Nil

// ── Connect & lifecycle ──────────────────────────────────────────────────────

/// Join a room. Builds the document the `Config` describes and connects it —
/// `crdt_js.connect` is synchronous, so the document exists before this effect
/// returns, but its handle arrives through `ready`.
///
/// `connection` fires once with the `CrdtConnection` to retain in your model so
/// a later `close` (or a snapshot re-`attach`) has something to act on. `ready`
/// fires exactly once with `Ok(document)` when the room's state has merged (or
/// immediately when this replica is alone) or `Error(reason)` if the join
/// fails. `status` fires for the connection's whole lifetime. Every one of the
/// three is deferred to a microtask before dispatch, and `connection` always
/// arrives before `ready` — an app holds the handle `close` needs before it is
/// told the room is usable.
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

/// Bring an already-built document online — the one `import_snapshot` hands
/// back, or any `crdt_js.new_document`. Handles and subscriptions taken before
/// the attach stay valid. Delivers `connection`, `ready`, and `status` exactly
/// as `connect` does, each deferred, `connection` first.
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

/// `attach` against a substituted browser seam, so bootstrap ordering and merge
/// behaviour can be driven deterministically without a browser. The same seam
/// `crdt_js.attach_with_rtc` exposes, for the same reason; production code wants
/// `connect` or `attach`.
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

/// The one shape all three ways of coming online share: run the `crdt_js`
/// call, defer its callbacks, and deliver the returned `CrdtConnection`
/// through `connection` — before `ready`.
///
/// `ready` is deferred one microtask *deeper* than everything else. When
/// readiness resolves synchronously (a solo replica), `on_ready` fires inside
/// `run`, before the `connection` dispatch below can even be queued; the extra
/// hop moves `ready` behind it, so an app always retains the `CrdtConnection`
/// it is told to keep before it hears the room is usable. When readiness
/// resolves later the extra hop only delays `ready` by one drained microtask.
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

/// Leave signaling, close every peer, drop every subscription, and stop the
/// document. Idempotent. Fire-and-forget: any readiness still outstanding is
/// resolved through the `ready` callback the connection was opened with.
pub fn close(connection: CrdtConnection) -> Effect(msg) {
  use _dispatch <- effect.from
  crdt_js.close(connection)
}

// ── Subscriptions ────────────────────────────────────────────────────────────
//
// One per eligible CRDT kind, mirroring `crdt_js`'s narrowed `subscribe_*` —
// the per-kind names carry the event typing. Each delivers the kind's own
// event type — never the whole `ChannelEvent` union — deferred to a microtask,
// and hands back the `Subscription` through `subscribed` (also deferred) so an
// app can retain it for `unsubscribe`.

/// The one shape every `subscribe_*` shares: take the kind's narrowed
/// `crdt_js` subscribe (with its handler still unapplied), defer each event,
/// and deliver the `Subscription`, deferred, through `subscribed`.
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

/// Subscribe to a peer-to-peer PN counter. `event` receives each local and
/// remote `pn_counter_kernel.PnCounterEvent`.
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
/// it can produce — a G-set has no removal.
pub fn subscribe_g_set(
  handle: Handle(schema.GSetChannel),
  subscribed subscribed: fn(Subscription) -> msg,
  event event: fn(g_set_kernel.GSetEvent) -> msg,
) -> Effect(msg) {
  subscribe(crdt_js.subscribe_g_set(handle, _), subscribed, event)
}

/// Subscribe to a peer-to-peer two-phase set (`ElementAdded` / `ElementRemoved`).
/// A removal is final: an element removed once can never be re-added.
pub fn subscribe_two_p_set(
  handle: Handle(schema.TwoPSetChannel),
  subscribed subscribed: fn(Subscription) -> msg,
  event event: fn(two_p_set_kernel.TwoPSetEvent) -> msg,
) -> Effect(msg) {
  subscribe(crdt_js.subscribe_two_p_set(handle, _), subscribed, event)
}

/// Subscribe to a peer-to-peer sequence. `event` receives each
/// `sequence_kernel.SequenceEvent`, which carries the full post-edit value
/// list — insert, delete, move, and replace all surface the same way.
pub fn subscribe_sequence(
  handle: Handle(schema.SequenceChannel),
  subscribed subscribed: fn(Subscription) -> msg,
  event event: fn(sequence_kernel.SequenceEvent) -> msg,
) -> Effect(msg) {
  subscribe(crdt_js.subscribe_sequence(handle, _), subscribed, event)
}

/// Subscribe to a peer-to-peer text channel. `event` receives each
/// `text_kernel.TextEvent` — a `TextChanged` carrying the full post-edit
/// string, so insert, delete, replace, and append all surface the same way.
pub fn subscribe_text(
  handle: Handle(schema.TextChannel),
  subscribed subscribed: fn(Subscription) -> msg,
  event event: fn(text_kernel.TextEvent) -> msg,
) -> Effect(msg) {
  subscribe(crdt_js.subscribe_text(handle, _), subscribed, event)
}

/// Remove one subscription taken above. Idempotent. Cleanup for a single
/// channel while the document stays connected; `close` drops them all.
pub fn unsubscribe(subscription: Subscription) -> Effect(msg) {
  use _dispatch <- effect.from
  crdt_js.unsubscribe(subscription)
}

// ── Mutations ────────────────────────────────────────────────────────────────

/// Run one effectful `crdt_js` operation *when the effect is performed* —
/// never when it is built inside `update` — and defer the delivery of its
/// result through the caller's message constructor, so the outcome reaches
/// `dispatch` on a microtask like every other callback here. `operation` is a
/// thunk so the edit, broadcast, and subscriber fan-out happen in the effect
/// phase, not while `update` is still running.
///
/// This is the whole mutation surface: compose it with the typed `crdt_js`
/// edit directly rather than looking for a per-edit wrapper —
///
/// ```gleam
/// crdt.perform(fn() { crdt_js.pn_counter_update(counter, 1) }, Clapped)
/// crdt.perform(fn() { crdt_js.or_map_set(map, key: "k", value: "v") }, Wrote)
/// ```
///
/// The `Result` is passed through untouched: an unsupported or invalid edit
/// stays an `Error`, never a success-shaped `Ok`.
pub fn perform(
  operation operation: fn() -> a,
  outcome outcome: fn(a) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let result = operation()
  queue_microtask(fn() { dispatch(outcome(result)) })
}

// ── Snapshots ────────────────────────────────────────────────────────────────

/// Export the whole importable snapshot — every channel's full CRDT state, in
/// canonical order — and deliver it through `exported`, deferred. The moment of
/// capture is effectful (it reads live document state), so it is an effect
/// rather than a pure read: dispatch it when you mean to persist.
pub fn export_snapshot(
  document: CrdtDocument(root),
  exported exported: fn(Result(Json, P2pError)) -> msg,
) -> Effect(msg) {
  perform(fn() { crdt_js.export_snapshot(document) }, exported)
}

/// Rebuild a detached document from an exported snapshot and deliver it through
/// `imported`, deferred. Size, protocol, room, compatibility, root type, and
/// every channel's eligibility are checked before a channel is loaded; on `Ok`,
/// pass the document to `attach` to bring it online.
pub fn import_snapshot(
  config: Config(root),
  snapshot: Json,
  imported imported: fn(Result(CrdtDocument(root), P2pError)) -> msg,
) -> Effect(msg) {
  perform(fn() { crdt_js.import_snapshot(config, snapshot) }, imported)
}
