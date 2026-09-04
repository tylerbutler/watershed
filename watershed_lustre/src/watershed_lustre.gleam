//// Lustre effect bindings for [watershed](https://github.com/tylerbutler/watershed).
////
//// The JavaScript facade of watershed, which is the `watershed` module, uses
//// callbacks. `connect` takes an `on_ready` function, `subscribe` takes a
//// handler, and the timers are FFI that the caller writes. A Lustre
//// application must bridge each of those into `dispatch`. watershed delivers
//// its events synchronously, and sometimes from inside a running `update`
//// call, so a nested `dispatch` call is lost. Every application finds that
//// fault and fixes it with a microtask. This package owns that bridge.
////
//// Every effect here takes a `fn(...) -> msg` constructor from the caller, the
//// same as a `lustre/event` handler. The package owns the *scheduling*, and
//// the application owns its message vocabulary. Every inbound callback goes to
//// a microtask, always. The dispatch fault inside `update` is thus removed by
//// design, and not only documented. Every binding behaves in the same way.
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
//// // after GotHandle(document): subscribe to the root map
//// watershed_lustre.subscribe(watershed.root(document), fn(_) { MapChanged })
//// ```
////
//// The edits and the reads stay on `watershed`, which has `set`, `get`,
//// `entries`, and the other functions. This package wraps the callback-shaped
//// surface only. JavaScript target only.

import gleam/javascript/promise
import gleam/json.{type Json}

import lustre/effect.{type Effect}

import watershed/presence
import watershed/presence_js
import watershed/summary_policy

import watershed.{
  type Claims, type Document, type GSet, type JsonOt, type OrMap, type OrSet,
  type OrderedCollection, type PactMap, type PnCounter, type RegisterCollection,
  type Ripple, type SharedCounter, type SharedDirectory, type SharedMap,
  type SharedRichText, type SharedSequence, type SharedText, type TaskManager,
  type TwoPSet, type TypedMap, type WatershedConfig, WatershedConfig,
}
import watershed/claim_outcome_js
import watershed/claims_kernel
import watershed/counter_kernel
import watershed/directory_kernel
import watershed/g_set_kernel
import watershed/json_ot_kernel
import watershed/map_kernel
import watershed/or_map_kernel.{type OrMapMode}
import watershed/or_set_kernel
import watershed/ordered_collection_kernel
import watershed/pact_map_kernel
import watershed/pn_counter_kernel
import watershed/register_collection_kernel
import watershed/rich_text_kernel
import watershed/runtime
import watershed/schema.{
  type ChannelField, type ChildField, type Field, type FieldChange,
}
import watershed/sequence_kernel
import watershed/task_manager_kernel
import watershed/text_kernel
import watershed/two_p_set_kernel
import watershed_lustre/crdt as crdt_effect

/// Run an operation when Lustre performs the effect.
///
/// The effect sends the outcome on a microtask.
pub fn perform(
  operation operation: fn() -> a,
  outcome outcome: fn(a) -> msg,
) -> Effect(msg) {
  crdt_effect.perform(operation:, outcome:)
}

@external(javascript, "./watershed_lustre_ffi.mjs", "queue_microtask")
fn queue_microtask(action: fn() -> Nil) -> Nil

@external(javascript, "./watershed_lustre_ffi.mjs", "set_timeout")
fn set_timeout(action: fn() -> Nil, milliseconds: Int) -> Nil

// ── Connect ────────────────────────────────────────────────────────────────

// docs:snippet-start watershed-lustre-connect
/// Connect to a document. `got_document` runs with the handle immediately. You
/// can start a root subscription and an optimistic edit at that point. To
/// create a nested channel, wait for `connected`. That callback runs with
/// `Ok(Nil)` after the handshake and the history replay complete, or with
/// `Error(reason)` when the server refuses the connection. This effect owns the
/// microtask for both callbacks.
pub fn connect(
  config: WatershedConfig,
  got_document got_document: fn(Document(root)) -> msg,
  connected connected: fn(Result(Nil, String)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let document =
    watershed.connect(config, on_ready: fn(result) {
      queue_microtask(fn() { dispatch(connected(result)) })
    })
  queue_microtask(fn() { dispatch(got_document(document)) })
}

// docs:snippet-end watershed-lustre-connect

/// The development form of `connect`. It creates the HS256 development token
/// from the tenant secret before it connects. That step is asynchronous,
/// through Web Crypto, and this effect handles the promise. Do not use this
/// function in production. The tenant secret must never reach the browser
/// there. Issue the tokens from a backend, and call `connect` instead.
pub fn connect_dev(
  url url: String,
  tenant tenant: String,
  secret secret: String,
  document document_id: String,
  user_id user_id: String,
  got_document got_document: fn(Document(root)) -> msg,
  connected connected: fn(Result(Nil, String)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let _ = {
    use token <- promise.map(watershed.dev_token(
      secret: secret,
      tenant: tenant,
      document: document_id,
      user_id: user_id,
    ))
    let config =
      WatershedConfig(
        url: url,
        tenant: tenant,
        document: document_id,
        token: token,
        user_id: user_id,
      )
    let document =
      watershed.connect(config, on_ready: fn(result) {
        queue_microtask(fn() { dispatch(connected(result)) })
      })
    queue_microtask(fn() { dispatch(got_document(document)) })
  }
  Nil
}

// ── Subscriptions ────────────────────────────────────────────────────────────
//
// One per channel kind, mirroring `watershed`'s narrowed `subscribe_*`. Each
// delivers the kind's own event type (never the 14-variant union), deferred to a
// microtask before dispatch.

/// Subscribe to a map channel. `to_msg` receives every local and remote
/// `map_kernel.MapEvent` value.
pub fn subscribe(
  map: SharedMap,
  to_msg to_msg: fn(map_kernel.MapEvent) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let _ =
    watershed.subscribe(map, fn(event) {
      queue_microtask(fn() { dispatch(to_msg(event)) })
    })
  Nil
}

/// Subscribe to a directory channel. Every event carries the `path` of the
/// subdirectory that it happened in, so one subscription covers the whole
/// tree: the value writes, the clears, and the creation and deletion of a
/// subdirectory.
pub fn subscribe_directory(
  directory: SharedDirectory,
  to_msg to_msg: fn(directory_kernel.DirectoryEvent) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let _ =
    watershed.subscribe_directory(directory, fn(event) {
      queue_microtask(fn() { dispatch(to_msg(event)) })
    })
  Nil
}

/// Subscribe to a counter channel.
pub fn subscribe_counter(
  counter: SharedCounter,
  to_msg to_msg: fn(counter_kernel.CounterEvent) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let _ =
    watershed.subscribe_counter(counter, fn(event) {
      queue_microtask(fn() { dispatch(to_msg(event)) })
    })
  Nil
}

/// Subscribe to an OR-map channel.
pub fn subscribe_or_map(
  or_map: OrMap,
  to_msg to_msg: fn(or_map_kernel.OrMapEvent) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let _ =
    watershed.subscribe_or_map(or_map, fn(event) {
      queue_microtask(fn() { dispatch(to_msg(event)) })
    })
  Nil
}

/// Subscribe to an OR-set channel.
pub fn subscribe_or_set(
  or_set: OrSet,
  to_msg to_msg: fn(or_set_kernel.OrSetEvent) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let _ =
    watershed.subscribe_or_set(or_set, fn(event) {
      queue_microtask(fn() { dispatch(to_msg(event)) })
    })
  Nil
}

/// Subscribe to a grow-only set. `ElementAdded` is the only event that this
/// channel produces, because a G-set has no remove operation.
pub fn subscribe_g_set(
  g_set: GSet,
  to_msg to_msg: fn(g_set_kernel.GSetEvent) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let _ =
    watershed.subscribe_g_set(g_set, fn(event) {
      queue_microtask(fn() { dispatch(to_msg(event)) })
    })
  Nil
}

/// Subscribe to a two-phase set, which produces `ElementAdded` and
/// `ElementRemoved`. A removal is permanent. You cannot add an element again
/// after you remove it.
pub fn subscribe_two_p_set(
  two_p_set: TwoPSet,
  to_msg to_msg: fn(two_p_set_kernel.TwoPSetEvent) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let _ =
    watershed.subscribe_two_p_set(two_p_set, fn(event) {
      queue_microtask(fn() { dispatch(to_msg(event)) })
    })
  Nil
}

/// Subscribe to a PN-counter channel.
pub fn subscribe_pn_counter(
  pn_counter: PnCounter,
  to_msg to_msg: fn(pn_counter_kernel.PnCounterEvent) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let _ =
    watershed.subscribe_pn_counter(pn_counter, fn(event) {
      queue_microtask(fn() { dispatch(to_msg(event)) })
    })
  Nil
}

/// Subscribe to the consensus transitions of a PactMap, which are `WentPending`
/// and `WentAccepted`.
pub fn subscribe_pact_map(
  pact_map: PactMap,
  to_msg to_msg: fn(pact_map_kernel.PactMapEvent) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let _ =
    watershed.subscribe_pact_map(pact_map, fn(event) {
      queue_microtask(fn() { dispatch(to_msg(event)) })
    })
  Nil
}

/// Subscribe to the queue events of an ordered collection.
pub fn subscribe_ordered_collection(
  collection: OrderedCollection,
  to_msg to_msg: fn(ordered_collection_kernel.OrderedEvent) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let _ =
    watershed.subscribe_ordered_collection(collection, fn(event) {
      queue_microtask(fn() { dispatch(to_msg(event)) })
    })
  Nil
}

/// Acquire the head of an ordered collection, and deliver the consensus outcome
/// as a message.
///
/// The outcome is `AcquiredItem` when this client won the head. That message
/// carries the acquire id for the later complete or release. The outcome is
/// `QueueEmpty` when the queue became empty before the operation sequenced. An
/// acquire that loses emits no event, so `QueueEmpty` is the only signal that a
/// loser receives. The outcome is `Aborted` when the document closes while the
/// acquire is still in flight.
///
/// The queue is not optimistic. Nothing changes until the operation sequences,
/// so render the interval as pending.
pub fn ordered_acquire(
  collection: OrderedCollection,
  to_msg to_msg: fn(ordered_collection_kernel.AcquireOutcome) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let _acquire_id =
    watershed.ordered_acquire_with_outcome(collection, fn(outcome) {
      queue_microtask(fn() { dispatch(to_msg(outcome)) })
    })
  Nil
}

/// Subscribe to a register collection channel.
pub fn subscribe_register_collection(
  collection: RegisterCollection,
  to_msg to_msg: fn(register_collection_kernel.RegisterEvent) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let _ =
    watershed.subscribe_register_collection(collection, fn(event) {
      queue_microtask(fn() { dispatch(to_msg(event)) })
    })
  Nil
}

/// Subscribe to a claims channel.
pub fn subscribe_claims(
  claims: Claims,
  to_msg to_msg: fn(claims_kernel.ClaimEvent) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let _ =
    watershed.subscribe_claims(claims, fn(event) {
      queue_microtask(fn() { dispatch(to_msg(event)) })
    })
  Nil
}

/// Attempt a first-writer-wins claim on `key`, and deliver the outcome as a
/// message. A claims read is not optimistic. Nothing in the view that this
/// client has of `key` changes until the outcome arrives. Render the interval
/// between this call and its message as pending.
///
/// `to_msg` receives exactly one `claims_kernel.ClaimOutcome` value. It is
/// `Accepted` when the value of this client won. It is `Lost` when another
/// client already claimed the key, either synchronously, because a committed
/// claim existed at the time of this call, or after the operation sequences,
/// because a concurrent attempt won the race. It is `Aborted` when the client
/// could not submit the claim at all, because it is still connecting or it
/// failed permanently. A caller must not treat `Aborted` as "nothing happened".
/// Report it, the same as any other connection failure.
pub fn claim_once(
  claims: Claims,
  key: String,
  value: Json,
  to_msg to_msg: fn(claims_kernel.ClaimOutcome) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  deliver_claim_outcome(watershed.claim_once(claims, key, value), fn(outcome) {
    dispatch(to_msg(outcome))
  })
}

/// A compare-and-set claim on `key`. It takes the key from the client that
/// holds it now, if no write has sequenced after the committed entry that this
/// call reads its `reference_sequence_number` from. It delivers its outcome in
/// the same way as `claim_once`. Here `Lost` means that a concurrent attempt to
/// take the key won the race. It does not mean that another client already
/// claimed the key.
pub fn compare_and_set_claim(
  claims: Claims,
  key: String,
  value: Json,
  to_msg to_msg: fn(claims_kernel.ClaimOutcome) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  deliver_claim_outcome(
    watershed.compare_and_set_claim(claims, key, value),
    fn(outcome) { dispatch(to_msg(outcome)) },
  )
}

/// The shared code of `claim_once` and `compare_and_set_claim`.
///
/// Two synchronous replies never reach the wire: `AlreadyClaimed` and
/// `AlreadyPendingLocally`. Each one resolves to an immediate outcome. The
/// asynchronous reply, which is `Pending`, resolves when its promise settles.
/// Both paths use the same microtask as every other binding in this module.
///
/// `WrongChannelType` covers two different runtime replies. In the first, the
/// address does not name a claims channel. A typed `ClaimsChannel` field always
/// resolves a real channel, so that reply is unreachable through one. In the
/// second, the runtime is neither `Ready` nor `Reconnecting`, because it is
/// still connecting or it is permanently `Failed`. That reply *is* reachable,
/// for example when a click on a claim races a disconnect.
///
/// Both replies become `Aborted`. A fifth outcome would add nothing, because a
/// caller would act on the two in the same way: something prevented this
/// attempt from reaching the wire.
fn deliver_claim_outcome(
  reply: runtime.ClaimSubmitReply,
  resolve: fn(claims_kernel.ClaimOutcome) -> Nil,
) -> Nil {
  claim_outcome_js.observe(reply, fn(outcome) {
    queue_microtask(fn() { resolve(outcome) })
  })
}

/// Subscribe to a task manager channel.
pub fn subscribe_task_manager(
  manager: TaskManager,
  to_msg to_msg: fn(task_manager_kernel.TaskManagerEvent) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let _ =
    watershed.subscribe_task_manager(manager, fn(event) {
      queue_microtask(fn() { dispatch(to_msg(event)) })
    })
  Nil
}

/// Subscribe to a sequence channel. `to_msg` receives every local and remote
/// `sequence_kernel.SequenceEvent` value, which carries the full list of values
/// after the edit. An insert, a delete, a move, and a replace all arrive in the
/// same form.
pub fn subscribe_sequence(
  sequence: SharedSequence,
  to_msg to_msg: fn(sequence_kernel.SequenceEvent) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let _ =
    watershed.subscribe_sequence(sequence, fn(event) {
      queue_microtask(fn() { dispatch(to_msg(event)) })
    })
  Nil
}

/// Subscribe to a text channel. `to_msg` receives every local and remote
/// `text_kernel.TextEvent` value, which is a `TextChanged` event that carries
/// the full optimistic string after the edit. An insert, a delete, a replace,
/// and an append all arrive in the same form, and none of them carries a stale
/// author index. Read the channel again on that event, to render the committed
/// optimistic state.
pub fn subscribe_text(
  text: SharedText,
  to_msg to_msg: fn(text_kernel.TextEvent) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let _ =
    watershed.subscribe_text(text, fn(event) {
      queue_microtask(fn() { dispatch(to_msg(event)) })
    })
  Nil
}

/// Subscribe to a text channel and return its cancellation token in a message.
///
/// Use this form when a nested component can bind to a different text channel
/// during its lifetime. Call `watershed.unsubscribe` with the token before the
/// component releases the old binding.
pub fn subscribe_text_cancellable(
  text: SharedText,
  to_msg to_msg: fn(text_kernel.TextEvent) -> msg,
  subscribed subscribed: fn(watershed.SubscriptionToken) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let token =
    watershed.subscribe_text(text, fn(event) {
      queue_microtask(fn() { dispatch(to_msg(event)) })
    })
  queue_microtask(fn() { dispatch(subscribed(token)) })
}

/// Subscribe to a rich text channel. `to_msg` receives every local and remote
/// `rich_text_kernel.RichTextChanged` value, which carries the `Delta` that the
/// kernel applied. Read the channel again with `watershed.rich_text_view` to
/// render it.
pub fn subscribe_rich_text(
  rich_text: SharedRichText,
  to_msg to_msg: fn(rich_text_kernel.RichTextEvent) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let _ =
    watershed.subscribe_rich_text(rich_text, fn(event) {
      queue_microtask(fn() { dispatch(to_msg(event)) })
    })
  Nil
}

/// Subscribe to a JSON-OT document. `DocumentChanged` carries the path that
/// changed, and not the new value, so read the channel again to render it.
pub fn subscribe_json_ot(
  json_ot: JsonOt,
  to_msg to_msg: fn(json_ot_kernel.JsonOtEvent) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let _ =
    watershed.subscribe_json_ot(json_ot, fn(event) {
      queue_microtask(fn() { dispatch(to_msg(event)) })
    })
  Nil
}

/// Subscribe to the inbound ephemeral ripples of the document. Those are the
/// transient messages of presence: a cursor, a selection, and a typing
/// indicator.
pub fn subscribe_ripples(
  document: Document(root),
  to_msg to_msg: fn(Ripple) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  watershed.subscribe_ripples(document, fn(ripple) {
    queue_microtask(fn() { dispatch(to_msg(ripple)) })
  })
}

// ── Typed subscriptions ──────────────────────────────────────────────────────

/// Subscribe to one typed field. Every local or remote write to the key of that
/// field dispatches a `FieldChange` value. It carries the new value and the
/// previous value, both decoded at the boundary. Each one is `Error(Invalid)`
/// when a peer wrote a value that does not match the field type.
pub fn subscribe_field(
  typed_map: TypedMap(s),
  field: Field(s, a),
  to_msg to_msg: fn(FieldChange(a)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let _ =
    watershed.subscribe_field(typed_map, field, fn(change) {
      queue_microtask(fn() { dispatch(to_msg(change)) })
    })
  Nil
}

/// Subscribe to the whole-map events of a typed map, and stay in the typed API.
/// Use `subscribe_field` to watch one field instead.
pub fn subscribe_typed(
  typed_map: TypedMap(s),
  to_msg to_msg: fn(map_kernel.MapEvent) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let _ =
    watershed.subscribe_typed(typed_map, fn(event) {
      queue_microtask(fn() { dispatch(to_msg(event)) })
    })
  Nil
}

// ── Declarative bootstrap (ensure_*) ─────────────────────────────────────────
//
// Each `ensure_*` gives a typed slot a guaranteed channel — adopting the
// sequenced winner or seeding a candidate and waiting for sync — and dispatches
// the resolved channel (or an error) once it settles. Batched in `init`, they
// make a document's nested structure declarative.

/// Make sure that a nested (untyped) map exists under `field`.
pub fn ensure_map(
  document: Document(root),
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.MapChannel),
  to_msg to_msg: fn(Result(SharedMap, String)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  watershed.ensure_map(document, typed_map, field, fn(result) {
    queue_microtask(fn() { dispatch(to_msg(result)) })
  })
}

/// Make sure that a directory exists under `field`. If none exists, the effect
/// creates one with an empty root.
pub fn ensure_directory(
  document: Document(root),
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.DirectoryChannel),
  to_msg to_msg: fn(Result(SharedDirectory, String)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  watershed.ensure_directory(document, typed_map, field, fn(result) {
    queue_microtask(fn() { dispatch(to_msg(result)) })
  })
}

/// Make sure that a counter exists under `field`. If the slot is empty, the
/// effect creates one.
pub fn ensure_counter(
  document: Document(root),
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.CounterChannel),
  to_msg to_msg: fn(Result(SharedCounter, String)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  watershed.ensure_counter(document, typed_map, field, fn(result) {
    queue_microtask(fn() { dispatch(to_msg(result)) })
  })
}

/// Make sure that an OR-map exists under `field`. If none exists, the effect
/// creates one in `mode`.
pub fn ensure_or_map(
  document: Document(root),
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.OrMapChannel),
  mode: OrMapMode,
  to_msg to_msg: fn(Result(OrMap, String)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  watershed.ensure_or_map(document, typed_map, field, mode, fn(result) {
    queue_microtask(fn() { dispatch(to_msg(result)) })
  })
}

/// Make sure that an OR-set exists under `field`.
pub fn ensure_or_set(
  document: Document(root),
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.OrSetChannel),
  to_msg to_msg: fn(Result(OrSet, String)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  watershed.ensure_or_set(document, typed_map, field, fn(result) {
    queue_microtask(fn() { dispatch(to_msg(result)) })
  })
}

/// Make sure that a grow-only set exists under `field`.
pub fn ensure_g_set(
  document: Document(root),
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.GSetChannel),
  to_msg to_msg: fn(Result(GSet, String)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  watershed.ensure_g_set(document, typed_map, field, fn(result) {
    queue_microtask(fn() { dispatch(to_msg(result)) })
  })
}

/// Make sure that a two-phase set exists under `field`.
pub fn ensure_two_p_set(
  document: Document(root),
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.TwoPSetChannel),
  to_msg to_msg: fn(Result(TwoPSet, String)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  watershed.ensure_two_p_set(document, typed_map, field, fn(result) {
    queue_microtask(fn() { dispatch(to_msg(result)) })
  })
}

/// Make sure that a register collection exists under `field`.
pub fn ensure_register_collection(
  document: Document(root),
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.RegisterCollectionChannel),
  to_msg to_msg: fn(Result(RegisterCollection, String)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  watershed.ensure_register_collection(document, typed_map, field, fn(result) {
    queue_microtask(fn() { dispatch(to_msg(result)) })
  })
}

/// Make sure that a claims channel exists under `field`.
pub fn ensure_claims(
  document: Document(root),
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.ClaimsChannel),
  to_msg to_msg: fn(Result(Claims, String)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  watershed.ensure_claims(document, typed_map, field, fn(result) {
    queue_microtask(fn() { dispatch(to_msg(result)) })
  })
}

/// Make sure that a task manager exists under `field`.
pub fn ensure_task_manager(
  document: Document(root),
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.TaskManagerChannel),
  to_msg to_msg: fn(Result(TaskManager, String)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  watershed.ensure_task_manager(document, typed_map, field, fn(result) {
    queue_microtask(fn() { dispatch(to_msg(result)) })
  })
}

/// Make sure that a PN-counter exists under `field`. If the slot is empty, the
/// effect creates one.
pub fn ensure_pn_counter(
  document: Document(root),
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.PnCounterChannel),
  to_msg to_msg: fn(Result(PnCounter, String)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  watershed.ensure_pn_counter(document, typed_map, field, fn(result) {
    queue_microtask(fn() { dispatch(to_msg(result)) })
  })
}

/// Make sure that a PactMap exists under `field`.
pub fn ensure_pact_map(
  document: Document(root),
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.PactMapChannel),
  to_msg to_msg: fn(Result(PactMap, String)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  watershed.ensure_pact_map(document, typed_map, field, fn(result) {
    queue_microtask(fn() { dispatch(to_msg(result)) })
  })
}

/// Make sure that an ordered collection exists under `field`.
pub fn ensure_ordered_collection(
  document: Document(root),
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.OrderedCollectionChannel),
  to_msg to_msg: fn(Result(OrderedCollection, String)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  watershed.ensure_ordered_collection(document, typed_map, field, fn(result) {
    queue_microtask(fn() { dispatch(to_msg(result)) })
  })
}

/// Make sure that a sequence exists under `field`. If none exists, the effect
/// creates an empty one.
pub fn ensure_sequence(
  document: Document(root),
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.SequenceChannel),
  to_msg to_msg: fn(Result(SharedSequence, String)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  watershed.ensure_sequence(document, typed_map, field, fn(result) {
    queue_microtask(fn() { dispatch(to_msg(result)) })
  })
}

/// Make sure that a text channel exists under `field`. If none exists, the
/// effect creates an empty one.
pub fn ensure_text(
  document: Document(root),
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.TextChannel),
  to_msg to_msg: fn(Result(SharedText, String)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  watershed.ensure_text(document, typed_map, field, fn(result) {
    queue_microtask(fn() { dispatch(to_msg(result)) })
  })
}

/// Make sure that a rich text channel exists under `field`. If none exists, the
/// effect creates one with an empty document.
pub fn ensure_rich_text(
  document: Document(root),
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.RichTextChannel),
  to_msg to_msg: fn(Result(SharedRichText, String)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  watershed.ensure_rich_text(document, typed_map, field, fn(result) {
    queue_microtask(fn() { dispatch(to_msg(result)) })
  })
}

/// Make sure that a JSON-OT document exists under `field`.
pub fn ensure_json_ot(
  document: Document(root),
  typed_map: TypedMap(s),
  field: ChannelField(s, schema.JsonOtChannel),
  to_msg to_msg: fn(Result(JsonOt, String)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  watershed.ensure_json_ot(document, typed_map, field, fn(result) {
    queue_microtask(fn() { dispatch(to_msg(result)) })
  })
}

/// Make sure that a nested *typed* child map exists under a child field.
pub fn ensure_child(
  document: Document(root),
  typed_map: TypedMap(s),
  field: ChildField(s, c),
  to_msg to_msg: fn(Result(TypedMap(c), String)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  watershed.ensure_child(document, typed_map, field, fn(result) {
    queue_microtask(fn() { dispatch(to_msg(result)) })
  })
}

/// Set a plain typed field to `default`, and only when its key is absent now.
/// The write is synchronous and dispatches no message. Put it in a batch with
/// the channel effects above, to make the bootstrap declarative in `init`.
pub fn ensure_field(
  typed_map: TypedMap(s),
  field: Field(s, a),
  default: a,
) -> Effect(msg) {
  use _dispatch <- effect.from
  watershed.ensure_field(typed_map, field, default)
}

// ── Timers & misc effects ──────────────────────────────────────────────────

/// Dispatch `msg` after `ms` milliseconds. This is the timer effect that an
/// application uses for a heartbeat, a debounce, and a retry, and the
/// application thus writes no `setTimeout` FFI. The timer runs outside every
/// `update` call, so this effect needs no microtask.
pub fn after(milliseconds: Int, msg: msg) -> Effect(msg) {
  use dispatch <- effect.from
  set_timeout(fn() { dispatch(msg) }, milliseconds)
}

/// Broadcast an ephemeral ripple to every other connected client. The effect
/// dispatches no message back.
pub fn submit_ripple(
  document: Document(root),
  ripple_type ripple_type: String,
  content content: Json,
) -> Effect(msg) {
  use _dispatch <- effect.from
  watershed.submit_ripple(document, ripple_type: ripple_type, content: content)
}

/// A hook that injects a fault, for a test or a demo. It closes the socket, so
/// that the client runs the reconnect and reconcile path. The pending edits and
/// the in-flight edits all stay.
pub fn force_reconnect(document: Document(root)) -> Effect(msg) {
  use _dispatch <- effect.from
  watershed.force_reconnect(document)
}

/// Go offline and stay offline. A read and an edit both continue to work. The
/// edits queue, and they go out when `go_online` reconnects. The effect does
/// nothing unless the document is connected.
///
/// Bind this function and `go_online` directly to a toggle:
///
/// ```gleam
/// ToggledOffline(offline) -> #(
///   Model(..model, offline:),
///   case offline {
///     True -> watershed_lustre.go_offline(document)
///     False -> watershed_lustre.go_online(document)
///   },
/// )
/// ```
pub fn go_offline(document: Document(root)) -> Effect(msg) {
  use _dispatch <- effect.from
  watershed.go_offline(document)
}

/// Return from `go_offline`. The client replays the interval and sends the
/// edits from it. The effect does nothing unless the document is offline now.
pub fn go_online(document: Document(root)) -> Effect(msg) {
  use _dispatch <- effect.from
  watershed.go_online(document)
}

// ── Presence ─────────────────────────────────────────────────────────────────
//
// The library's presence driver as effects. The driver owns the whole
// lifecycle — negotiating server or ripple mode, joining, rejoining after a
// reconnect, and expiring silent peers in ripple mode. This package adds the
// same microtask deferral every other binding has, so a presence callback can
// never dispatch during `update`, and hands the `Handle` back so
// `update_presence` and `stop_presence` can be effects too.

/// Start to track presence on `document`, with `initial` as the metadata of
/// this client.
///
/// `started` runs with the `Handle` value of the driver. Keep that value in
/// your model, so that you can update it later. `on_event` runs with every
/// `presence.Event` value. A `State` event replaces the whole roster. A
/// `Changed` event carries a change and the roster that results. A `Failed`
/// event reports a failure. Render on whichever event suits your application.
/// The roster in a `Changed` event is always complete.
pub fn presence(
  document document: Document(root),
  config config: presence.Config(a),
  initial initial: a,
  started started: fn(presence_js.Handle(a)) -> msg,
  on_event on_event: fn(presence.Event(a)) -> msg,
) -> Effect(msg) {
  use dispatch <- effect.from
  let handle =
    presence_js.start(
      document: document,
      config: config,
      initial: initial,
      on_event: fn(event) {
        queue_microtask(fn() { dispatch(on_event(event)) })
      },
    )
  queue_microtask(fn() { dispatch(started(handle)) })
}

/// Replace the presence metadata of this client. The effect dispatches no
/// message back.
pub fn update_presence(
  handle: presence_js.Handle(a),
  metadata: a,
) -> Effect(msg) {
  use _dispatch <- effect.from
  presence_js.update(handle, metadata)
}

/// Stop the presence tracking. In server mode the peers see the departure
/// immediately. In ripple mode they see it when the TTL expires.
pub fn stop_presence(handle: presence_js.Handle(a)) -> Effect(msg) {
  use _dispatch <- effect.from
  presence_js.stop(handle)
}

// ─────────────────────────────────────────────────────────────────────────────
// Summaries
// ─────────────────────────────────────────────────────────────────────────────

/// Let this client summarize the document without a request, under `policy`.
///
/// Without this effect nothing summarizes, and every client that joins replays
/// the whole log. The effect dispatches no message back, and the policy applies
/// from the next sequenced operation. Put it in a batch beside `connect_dev`,
/// in the effect that receives the `Document` value.
pub fn auto_summarize(
  document document: Document(root),
  policy policy: summary_policy.Policy,
) -> Effect(msg) {
  use _dispatch <- effect.from
  watershed.auto_summarize(document, policy)
}

/// Stop the automatic summaries.
pub fn stop_auto_summarize(document document: Document(root)) -> Effect(msg) {
  use _dispatch <- effect.from
  watershed.stop_auto_summarize(document)
}
