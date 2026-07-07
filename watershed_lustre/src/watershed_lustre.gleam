//// Lustre effect bindings for [watershed](https://github.com/tylerbutler/watershed).
////
//// watershed's JS facade (`watershed_js`) is callback-shaped: `connect` takes
//// an `on_ready`, `subscribe` takes a handler, timers are hand-rolled FFI. A
//// Lustre app has to bridge each of those into `dispatch`, and — because
//// watershed delivers events synchronously, sometimes from inside a running
//// `update` — every app independently rediscovers that a nested `dispatch` is
//// clobbered and patches it with a microtask. This package owns that bridging.
////
//// Every effect here takes a caller-supplied `fn(...) -> msg` constructor, the
//// way `lustre/event` handlers do: the package owns *scheduling*, the app owns
//// its message vocabulary. Every inbound callback is unconditionally deferred
//// to a microtask, so the mid-`update` dispatch bug is designed out rather than
//// documented — the semantics of every binding are identical.
////
//// ```gleam
//// fn init(_) {
////   #(initial, watershed_lustre.connect_dev(
////     url: url, tenant: tenant, secret: secret,
////     document: "dice", user_id: user_id,
////     got_document: GotHandle, connected: Connected,
////   ))
//// }
////
//// // after GotHandle(doc): subscribe to the root map
//// watershed_lustre.subscribe(watershed_js.root(doc), fn(_) { MapChanged })
//// ```
////
//// Edits and reads stay on `watershed_js` (`set`, `get`, `entries`, …); this
//// package only wraps the callback-shaped surface. JavaScript target only.

import gleam/dynamic/decode.{type Decoder}
import gleam/javascript/promise
import gleam/json.{type Json}

import lustre/effect.{type Effect}

import watershed/presence.{type Config, type Peer}
import watershed/presence_js.{type Handle}

import watershed/claims_kernel
import watershed/counter_kernel
import watershed/map_kernel
import watershed/or_map_kernel.{type OrMapMode}
import watershed/or_set_kernel
import watershed/register_collection_kernel
import watershed/schema.{
  type ChannelField, type ChildField, type Field, type FieldChange,
}
import watershed/task_manager_kernel
import watershed_js.{
  type Claims, type Document, type OrMap, type OrSet, type OrderedCollection,
  type PactMap, type PnCounter, type RegisterCollection, type Ripple,
  type SharedCounter, type SharedMap, type TaskManager, type TypedMap,
  type WatershedConfig, WatershedConfig,
}

@external(javascript, "./watershed_lustre_ffi.mjs", "queue_microtask")
fn queue_microtask(action: fn() -> Nil) -> Nil

@external(javascript, "./watershed_lustre_ffi.mjs", "set_timeout")
fn set_timeout(action: fn() -> Nil, ms: Int) -> Nil

// ── Connect ────────────────────────────────────────────────────────────────

/// Connect to a document. `got_document` fires with the handle immediately (so
/// the app can start issuing edits against the optimistic state); `connected`
/// fires once the handshake and history replay complete (`Ok(Nil)`) or the
/// connection is rejected (`Error(reason)`). Owns the deferral of both.
pub fn connect(
  config: WatershedConfig,
  got_document got_document: fn(Document) -> msg,
  connected connected: fn(Result(Nil, String)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let doc =
    watershed_js.connect(config, on_ready: fn(result) {
      queue_microtask(fn() { dispatch(connected(result)) })
    })
  queue_microtask(fn() { dispatch(got_document(doc)) })
}

/// Dev-mode variant of `connect`: mints the HS256 dev token (async, via Web
/// Crypto) from the tenant secret before connecting, absorbing the promise
/// dance. Do not use in production — the tenant secret must never reach the
/// browser there; issue tokens from a backend and call `connect` instead.
pub fn connect_dev(
  url url: String,
  tenant tenant: String,
  secret secret: String,
  document document: String,
  user_id user_id: String,
  got_document got_document: fn(Document) -> msg,
  connected connected: fn(Result(Nil, String)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let _ = {
    use token <- promise.map(watershed_js.dev_token(
      secret: secret,
      tenant: tenant,
      document: document,
      user_id: user_id,
    ))
    let config =
      WatershedConfig(
        url: url,
        tenant: tenant,
        document: document,
        token: token,
        user_id: user_id,
      )
    let doc =
      watershed_js.connect(config, on_ready: fn(result) {
        queue_microtask(fn() { dispatch(connected(result)) })
      })
    queue_microtask(fn() { dispatch(got_document(doc)) })
  }
  Nil
}

// ── Subscriptions ────────────────────────────────────────────────────────────
//
// One per channel kind, mirroring `watershed_js`'s narrowed `subscribe_*`. Each
// delivers the kind's own event type (never the 14-variant union), deferred to a
// microtask before dispatch.

/// Subscribe to a map channel. `to_msg` receives each local and remote
/// `map_kernel.MapEvent`.
pub fn subscribe(
  map: SharedMap,
  to_msg to_msg: fn(map_kernel.MapEvent) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  watershed_js.subscribe(map, fn(event) {
    queue_microtask(fn() { dispatch(to_msg(event)) })
  })
}

/// Subscribe to a counter channel.
pub fn subscribe_counter(
  counter: SharedCounter,
  to_msg to_msg: fn(counter_kernel.CounterEvent) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  watershed_js.subscribe_counter(counter, fn(event) {
    queue_microtask(fn() { dispatch(to_msg(event)) })
  })
}

/// Subscribe to an OR-map channel.
pub fn subscribe_or_map(
  or_map: OrMap,
  to_msg to_msg: fn(or_map_kernel.OrMapEvent) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  watershed_js.subscribe_or_map(or_map, fn(event) {
    queue_microtask(fn() { dispatch(to_msg(event)) })
  })
}

/// Subscribe to an OR-set channel.
pub fn subscribe_or_set(
  or_set: OrSet,
  to_msg to_msg: fn(or_set_kernel.OrSetEvent) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  watershed_js.subscribe_or_set(or_set, fn(event) {
    queue_microtask(fn() { dispatch(to_msg(event)) })
  })
}

/// Subscribe to a register collection channel.
pub fn subscribe_register_collection(
  collection: RegisterCollection,
  to_msg to_msg: fn(register_collection_kernel.RegisterEvent) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  watershed_js.subscribe_register_collection(collection, fn(event) {
    queue_microtask(fn() { dispatch(to_msg(event)) })
  })
}

/// Subscribe to a claims channel.
pub fn subscribe_claims(
  claims: Claims,
  to_msg to_msg: fn(claims_kernel.ClaimEvent) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  watershed_js.subscribe_claims(claims, fn(event) {
    queue_microtask(fn() { dispatch(to_msg(event)) })
  })
}

/// Subscribe to a task manager channel.
pub fn subscribe_task_manager(
  manager: TaskManager,
  to_msg to_msg: fn(task_manager_kernel.TaskManagerEvent) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  watershed_js.subscribe_task_manager(manager, fn(event) {
    queue_microtask(fn() { dispatch(to_msg(event)) })
  })
}

/// Subscribe to the document's inbound ephemeral ripples (presence-style
/// transient messages — cursors, selection, typing indicators).
pub fn subscribe_ripples(
  document: Document,
  to_msg to_msg: fn(Ripple) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  watershed_js.subscribe_ripples(document, fn(ripple) {
    queue_microtask(fn() { dispatch(to_msg(ripple)) })
  })
}

// ── Typed subscriptions ──────────────────────────────────────────────────────

/// Subscribe to a single typed field: each local or remote write to the field's
/// key dispatches a `FieldChange` with the new and previous values decoded at
/// the boundary (`Error(Invalid)` when a peer wrote a mismatching value).
pub fn subscribe_field(
  typed_map: TypedMap(s),
  field: Field(s, a),
  to_msg to_msg: fn(FieldChange(a)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  watershed_js.subscribe_field(typed_map, field, fn(change) {
    queue_microtask(fn() { dispatch(to_msg(change)) })
  })
}

/// Subscribe to a typed map's whole-map events without dropping to the untyped
/// API. Use `subscribe_field` to watch a single field instead.
pub fn subscribe_typed(
  typed_map: TypedMap(s),
  to_msg to_msg: fn(map_kernel.MapEvent) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  watershed_js.subscribe_typed(typed_map, fn(event) {
    queue_microtask(fn() { dispatch(to_msg(event)) })
  })
}

// ── Declarative bootstrap (ensure_*) ─────────────────────────────────────────
//
// Each `ensure_*` gives a typed slot a guaranteed channel — adopting the
// sequenced winner or seeding a candidate and waiting for sync — and dispatches
// the resolved channel (or an error) once it settles. Batched in `init`, they
// make a document's nested structure declarative.

/// Ensure a nested (untyped) map exists under `field`.
pub fn ensure_map(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.MapChannel),
  to_msg to_msg: fn(Result(SharedMap, String)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  watershed_js.ensure_map(document, typed_map, field, fn(result) {
    queue_microtask(fn() { dispatch(to_msg(result)) })
  })
}

/// Ensure a counter exists under `field`, seeding one if the slot is empty.
pub fn ensure_counter(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.CounterChannel),
  to_msg to_msg: fn(Result(SharedCounter, String)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  watershed_js.ensure_counter(document, typed_map, field, fn(result) {
    queue_microtask(fn() { dispatch(to_msg(result)) })
  })
}

/// Ensure an OR-map exists under `field`, seeding one in `mode` if absent.
pub fn ensure_or_map(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.OrMapChannel),
  mode: OrMapMode,
  to_msg to_msg: fn(Result(OrMap, String)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  watershed_js.ensure_or_map(document, typed_map, field, mode, fn(result) {
    queue_microtask(fn() { dispatch(to_msg(result)) })
  })
}

/// Ensure an OR-set exists under `field`.
pub fn ensure_or_set(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.OrSetChannel),
  to_msg to_msg: fn(Result(OrSet, String)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  watershed_js.ensure_or_set(document, typed_map, field, fn(result) {
    queue_microtask(fn() { dispatch(to_msg(result)) })
  })
}

/// Ensure a register collection exists under `field`.
pub fn ensure_register_collection(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.RegisterCollectionChannel),
  to_msg to_msg: fn(Result(RegisterCollection, String)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  watershed_js.ensure_register_collection(
    document,
    typed_map,
    field,
    fn(result) { queue_microtask(fn() { dispatch(to_msg(result)) }) },
  )
}

/// Ensure a claims channel exists under `field`.
pub fn ensure_claims(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.ClaimsChannel),
  to_msg to_msg: fn(Result(Claims, String)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  watershed_js.ensure_claims(document, typed_map, field, fn(result) {
    queue_microtask(fn() { dispatch(to_msg(result)) })
  })
}

/// Ensure a task manager exists under `field`.
pub fn ensure_task_manager(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.TaskManagerChannel),
  to_msg to_msg: fn(Result(TaskManager, String)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  watershed_js.ensure_task_manager(document, typed_map, field, fn(result) {
    queue_microtask(fn() { dispatch(to_msg(result)) })
  })
}

/// Ensure a PN-counter exists under `field`, seeding one if the slot is empty.
pub fn ensure_pn_counter(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.PnCounterChannel),
  to_msg to_msg: fn(Result(PnCounter, String)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  watershed_js.ensure_pn_counter(document, typed_map, field, fn(result) {
    queue_microtask(fn() { dispatch(to_msg(result)) })
  })
}

/// Ensure a PactMap exists under `field`.
pub fn ensure_pact_map(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.PactMapChannel),
  to_msg to_msg: fn(Result(PactMap, String)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  watershed_js.ensure_pact_map(document, typed_map, field, fn(result) {
    queue_microtask(fn() { dispatch(to_msg(result)) })
  })
}

/// Ensure an ordered collection exists under `field`.
pub fn ensure_ordered_collection(
  document: Document,
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.OrderedCollectionChannel),
  to_msg to_msg: fn(Result(OrderedCollection, String)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  watershed_js.ensure_ordered_collection(document, typed_map, field, fn(result) {
    queue_microtask(fn() { dispatch(to_msg(result)) })
  })
}

/// Ensure a nested *typed* child map exists under a child field.
pub fn ensure_child(
  document: Document,
  typed_map: TypedMap(s),
  field: ChildField(s, c),
  to_msg to_msg: fn(Result(TypedMap(c), String)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  watershed_js.ensure_child(document, typed_map, field, fn(result) {
    queue_microtask(fn() { dispatch(to_msg(result)) })
  })
}

/// Set a plain typed field to `default` only if its key is currently absent.
/// Synchronous seed (no dispatch) — batch it alongside the channel ensures to
/// make bootstrap declarative in `init`.
pub fn ensure_field(
  typed_map: TypedMap(s),
  field: Field(s, a),
  default: a,
) -> Effect(msg) {
  use _dispatch <- effect.from
  watershed_js.ensure_field(typed_map, field, default)
}

// ── Timers & misc effects ──────────────────────────────────────────────────

/// Dispatch `msg` after `ms` milliseconds — the timer effect apps reach for to
/// drive heartbeats, debounces, and retries without hand-rolling `setTimeout`
/// FFI. The timer fires outside any `update`, so no deferral is needed.
pub fn after(ms: Int, msg: msg) -> Effect(msg) {
  use dispatch <- effect.from
  set_timeout(fn() { dispatch(msg) }, ms)
}

/// Broadcast an ephemeral ripple to every other connected client. Fire-and-
/// forget: no message is dispatched back.
pub fn submit_ripple(
  document: Document,
  ripple_type ripple_type: String,
  content content: Json,
) -> Effect(msg) {
  use _dispatch <- effect.from
  watershed_js.submit_ripple(
    document,
    ripple_type: ripple_type,
    content: content,
  )
}

/// Fault-injection hook (tests/demos): drop the socket to force the
/// reconnect/reconcile path. Pending and in-flight edits are preserved.
pub fn force_reconnect(document: Document) -> Effect(msg) {
  use _dispatch <- effect.from
  watershed_js.force_reconnect(document)
}

// ── Presence ─────────────────────────────────────────────────────────────────
//
// The library's heartbeat presence driver as effects. The driver owns the
// heartbeat/TTL lifecycle over ephemeral ripples; this package adds the same
// microtask deferral every other binding has (the deferral PS2 deliberately
// left out) and hands the `Handle` back so `announce` can be an effect too.

/// Start tracking presence on `document`. `started` fires with the driver
/// `Handle` (keep it in your model to `announce` later); `on_peers` fires with
/// the sorted roster whenever the visible peer set changes — re-render
/// unconditionally on it. The driver owns heartbeat + TTL expiry.
pub fn presence(
  document document: Document,
  user_id user_id: String,
  config config: Config,
  encode encode: fn(a) -> Json,
  decode decode: Decoder(a),
  started started: fn(Handle(a)) -> msg,
  on_peers on_peers: fn(List(Peer(a))) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let handle =
    presence_js.start(
      document: document,
      user_id: user_id,
      config: config,
      encode: encode,
      decode: decode,
      on_change: fn(peers) {
        queue_microtask(fn() { dispatch(on_peers(peers)) })
      },
    )
  queue_microtask(fn() { dispatch(started(handle)) })
}

/// Announce this client's current payload through the driver: broadcasts now
/// and keeps the heartbeat alive. Fire-and-forget — no message is dispatched
/// back.
pub fn announce(handle: Handle(a), payload: a) -> Effect(msg) {
  use _dispatch <- effect.from
  presence_js.announce(handle, payload)
}
