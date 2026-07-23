//// JavaScript runtime for the SharedMap client — the browser counterpart of
//// the erlang `watershed/runtime` OTP actor.
////
//// Same responsibilities (handshake, CSN/RSN stamping, inbound ordering,
//// gap catch-up, reconnect/reconcile, event fan-out) driving the *same* pure
//// core (`runtime_core`/`wire`/`map_kernel`), but with no OTP: state lives in
//// a mutable cell and the Phoenix transport delivers events via callbacks.
////
//// JavaScript target only (gated with `@target(javascript)`).

@target(javascript)
import gleam/dict.{type Dict}
@target(javascript)
import gleam/dynamic.{type Dynamic}
@target(javascript)
import gleam/dynamic/decode
@target(javascript)
import gleam/int
@target(javascript)
import gleam/javascript/promise.{type Promise}
@target(javascript)
import gleam/json.{type Json}
@target(javascript)
import gleam/list
@target(javascript)
import gleam/option.{type Option, None, Some}
@target(javascript)
import gleam/string
@target(javascript)
import gleam/uri

@target(javascript)
import spillway/message.{
  type ConnectMessage, type ConnectedMessage, type SignalMessage,
  type SummaryContext,
}
@target(javascript)
import spillway/nack.{type Nack}
@target(javascript)
import spillway/types.{type SequencedDocumentMessage}

@target(javascript)
import watershed/channel.{type ChannelEvent, type Resolution, ClaimResolved}
@target(javascript)
import watershed/claims_kernel
@target(javascript)
import watershed/git_storage
@target(javascript)
import watershed/ids
@target(javascript)
import watershed/json_ot
@target(javascript)
import watershed/or_map_kernel.{type OrMapMode, type OrMapValue}
@target(javascript)
import watershed/register_collection_kernel.{type ReadPolicy}
@target(javascript)
import watershed/rich_text
@target(javascript)
import watershed/runtime_core
@target(javascript)
import watershed/task_manager_kernel
@target(javascript)
import watershed/text_kernel
@target(javascript)
import watershed/transport_js.{type Cell}
@target(javascript)
import watershed/wire
@target(javascript)
import watershed/wire/socket
@target(javascript)
import watershed/wire/summary_blob

@target(javascript)
/// Server nacks submissions above 100 ops; chunk resubmits to stay under it.
const max_ops_per_submission = 100

// ─────────────────────────────────────────────────────────────────────────────
// Transport seam
//
// The runtime talks to levee through an injectable `Transport` rather than
// calling `transport_js` directly, so the in-memory hub (see `watershed/hub`)
// can supply an alternate transport for deterministic app tests. The concrete
// link (a phoenix `Channel`, a hub cell) is captured inside the closures of a
// `TransportHandle`, so no connection-specific type leaks into `State`.
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// A live connection's outbound operations. `push` carries the wire event and
/// its JSON payload; `close` tears the connection down; `drop` forces the
/// reconnect path (for phoenix, a socket drop that auto-rejoins).
pub type TransportHandle {
  TransportHandle(
    push: fn(String, Json) -> Nil,
    close: fn() -> Nil,
    drop: fn() -> Nil,
  )
}

@target(javascript)
/// How a transport reports inbound frames and (re)join/close lifecycle back to
/// the runtime. Phoenix drives these from its socket; the hub drives them on
/// explicit delivery.
pub type TransportCallbacks {
  TransportCallbacks(
    on_event: fn(String, Dynamic) -> Nil,
    /// Fires on every successful (re)join — also the re-handshake hook.
    on_join: fn() -> Nil,
    on_close: fn() -> Nil,
  )
}

@target(javascript)
/// A pluggable connection to a levee-shaped server. `connect` opens the link,
/// wires the callbacks, and returns the handle used for outbound frames.
pub type Transport {
  Transport(connect: fn(TransportCallbacks) -> TransportHandle)
}

@target(javascript)
pub type ClaimSubmitReply {
  Pending(outcome: Promise(claims_kernel.ClaimOutcome))
  AlreadyClaimed(current_value: Json)
  AlreadyPendingLocally
  WrongChannelType
}

@target(javascript)
type Phase {
  Connecting
  /// Socket down and re-handshaking; holds the pre-reconnect core.
  Reconnecting(core: runtime_core.Core)
  /// Connected. `resubmit_at` is `Some(checkpoint)` while a reconnect is still
  /// catching up to where un-acked ops can be resubmitted, `None` once synced.
  Ready(core: runtime_core.Core, resubmit_at: Option(Int))
  Failed(reason: String)
}

@target(javascript)
type State {
  State(
    connect_message: ConnectMessage,
    /// HTTP(S) base URL for git-storage (summary) calls, derived from the
    /// Phoenix socket URL. levee serves both the socket and REST from one
    /// origin.
    http_base_url: String,
    channel: Option(TransportHandle),
    phase: Phase,
    subscribers: List(#(String, fn(ChannelEvent) -> Nil)),
    /// Ephemeral-ripple subscribers. Ripples are document-scoped and
    /// non-sequenced, so they fan out independently of the op event stream.
    ripple_subscribers: List(fn(SignalMessage) -> Nil),
    claim_waiters: Dict(
      #(String, String),
      fn(claims_kernel.ClaimOutcome) -> Nil,
    ),
    on_ready: fn(Result(Nil, String)) -> Nil,
    ready_fired: Bool,
  )
}

@target(javascript)
/// Opaque handle to a running document runtime.
pub opaque type Runtime {
  Runtime(cell: Cell(State))
}

@target(javascript)
/// Read-only runtime state intended for diagnostics and example tooling.
pub type Diagnostics {
  Diagnostics(
    phase: String,
    client_id: Option(String),
    last_seen_sequence_number: Option(Int),
    next_client_sequence_number: Option(Int),
    in_flight_count: Int,
    buffered_out_of_order_count: Int,
    resubmit_checkpoint: Option(Int),
    synced: Bool,
  )
}

@target(javascript)
/// Start a runtime: open the Phoenix socket, join the topic, and begin the
/// handshake. `on_ready` fires once with `Ok(Nil)` when the document has
/// bootstrapped, or `Error(reason)` if the connection is rejected.
pub fn start(
  url url: String,
  topic topic: String,
  connect_message connect_message: ConnectMessage,
  on_ready on_ready: fn(Result(Nil, String)) -> Nil,
) -> Runtime {
  let join_payload = case connect_message.token {
    Some(token) -> json.object([#("token", json.string(token))])
    None -> json.object([])
  }
  start_with_transport(
    http_base_url: http_base_from_socket_url(url),
    connect_message: connect_message,
    transport: phoenix_transport(url, topic, join_payload),
    on_ready: on_ready,
  )
}

@target(javascript)
/// Start a runtime against an arbitrary transport. Used by the live `start`
/// (phoenix) and by the in-memory hub test driver. `http_base_url` only feeds
/// the REST summary API and may be a placeholder for transports without one.
pub fn start_with_transport(
  http_base_url http_base_url: String,
  connect_message connect_message: ConnectMessage,
  transport transport: Transport,
  on_ready on_ready: fn(Result(Nil, String)) -> Nil,
) -> Runtime {
  let cell =
    transport_js.new_cell(State(
      connect_message: connect_message,
      http_base_url: http_base_url,
      channel: None,
      phase: Connecting,
      subscribers: [],
      ripple_subscribers: [],
      claim_waiters: dict.new(),
      on_ready: on_ready,
      ready_fired: False,
    ))

  let handle =
    transport.connect(
      TransportCallbacks(
        on_event: fn(event, payload) { on_event(cell, event, payload) },
        on_join: fn() { on_join(cell) },
        on_close: fn() { on_close(cell) },
      ),
    )

  cell_set(cell, State(..cell_get(cell), channel: Some(handle)))
  Runtime(cell: cell)
}

@target(javascript)
/// The default transport: a phoenix socket over `transport_js`. Phoenix
/// auto-rejoins after a socket drop, re-firing `on_join`, so the runtime never
/// re-invokes `connect`.
fn phoenix_transport(
  url: String,
  topic: String,
  join_payload: Json,
) -> Transport {
  Transport(connect: fn(callbacks: TransportCallbacks) -> TransportHandle {
    let channel =
      transport_js.connect(
        url: url,
        topic: topic,
        join_payload: json.to_string(join_payload),
        on_event: callbacks.on_event,
        on_join: callbacks.on_join,
        on_close: callbacks.on_close,
      )
    TransportHandle(
      push: fn(event, payload) {
        transport_js.push(channel, event, json.to_string(payload))
      },
      close: fn() { transport_js.close(channel) },
      drop: fn() { transport_js.drop_socket(channel) },
    )
  })
}

// ─────────────────────────────────────────────────────────────────────────────
// Public edits / reads / events
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
pub fn set(runtime: Runtime, address: String, key: String, value: Json) -> Nil {
  edit(runtime.cell, fn(core) { runtime_core.set(core, address, key, value) })
}

@target(javascript)
pub fn delete(runtime: Runtime, address: String, key: String) -> Nil {
  edit(runtime.cell, fn(core) { runtime_core.delete(core, address, key) })
}

@target(javascript)
pub fn clear(runtime: Runtime, address: String) -> Nil {
  edit(runtime.cell, fn(core) { runtime_core.clear(core, address) })
}

@target(javascript)
pub fn get(runtime: Runtime, address: String, key: String) -> Option(Json) {
  read(runtime.cell, None, runtime_core.get(_, address, key))
}

@target(javascript)
pub fn entries(runtime: Runtime, address: String) -> List(#(String, Json)) {
  read(runtime.cell, [], runtime_core.entries(_, address))
}

@target(javascript)
pub fn keys(runtime: Runtime, address: String) -> List(String) {
  read(runtime.cell, [], runtime_core.keys(_, address))
}

@target(javascript)
pub fn size(runtime: Runtime, address: String) -> Int {
  read(runtime.cell, 0, runtime_core.size(_, address))
}

@target(javascript)
pub fn has(runtime: Runtime, address: String, key: String) -> Bool {
  get(runtime, address, key) != None
}

@target(javascript)
/// Optimistically increment the counter at `address` (negative amounts
/// decrement).
pub fn increment(runtime: Runtime, address: String, amount: Int) -> Nil {
  edit(runtime.cell, fn(core) { runtime_core.increment(core, address, amount) })
}

@target(javascript)
/// The counter's optimistic value, `None` when the address is missing or
/// not a counter channel.
pub fn counter_value(runtime: Runtime, address: String) -> Option(Int) {
  read(runtime.cell, None, runtime_core.counter_value(_, address))
}

@target(javascript)
/// Optimistically apply a signed update to the PN-counter at `address`
/// (negative amounts decrement).
pub fn pn_counter_update(
  runtime: Runtime,
  address: String,
  amount: Int,
) -> Nil {
  edit(runtime.cell, fn(core) {
    runtime_core.pn_counter_update(core, address, amount)
  })
}

@target(javascript)
/// The PN-counter's optimistic value, `None` when the address is missing or
/// not a pn-counter channel.
pub fn pn_counter_value(runtime: Runtime, address: String) -> Option(Int) {
  read(runtime.cell, None, runtime_core.pn_counter_value(_, address))
}

@target(javascript)
/// Propose `value` for `key` in the PactMap at `address`. Consensus, not
/// optimistic: the value takes effect only once the `Set` sequences (and its
/// automatic `Accept` follow-up settles the quorum).
pub fn pact_map_set(
  runtime: Runtime,
  address: String,
  key: String,
  value: Json,
) -> Nil {
  edit(runtime.cell, fn(core) {
    runtime_core.pact_map_set(core, address, key, value)
  })
}

@target(javascript)
/// Propose a delete (tombstone) for `key` in the PactMap at `address`.
pub fn pact_map_delete(runtime: Runtime, address: String, key: String) -> Nil {
  edit(runtime.cell, fn(core) {
    runtime_core.pact_map_delete(core, address, key)
  })
}

@target(javascript)
/// The PactMap's accepted value for `key`, `None` when pending, absent, or not
/// a PactMap channel.
pub fn pact_map_get(
  runtime: Runtime,
  address: String,
  key: String,
) -> Option(Json) {
  read(runtime.cell, None, runtime_core.pact_map_get(_, address, key))
}

@target(javascript)
/// All keys with an accepted or pending pact in the PactMap at `address`.
pub fn pact_map_keys(runtime: Runtime, address: String) -> List(String) {
  read(runtime.cell, [], runtime_core.pact_map_keys(_, address))
}

@target(javascript)
/// Whether `key` has a pending (proposed but not-yet-accepted) value.
pub fn pact_map_is_pending(
  runtime: Runtime,
  address: String,
  key: String,
) -> Bool {
  read(runtime.cell, False, runtime_core.pact_map_is_pending(_, address, key))
}

@target(javascript)
/// Append `value` to the ordered collection at `address`. Non-optimistic when
/// attached (takes effect on sequencing); a detached channel adds immediately.
pub fn ordered_add(runtime: Runtime, address: String, value: Json) -> Nil {
  edit(runtime.cell, fn(core) { runtime_core.ordered_add(core, address, value) })
}

@target(javascript)
/// Acquire the head of the ordered collection at `address`, returning the minted
/// acquire id for the later `ordered_complete`/`ordered_release`. The acquired
/// item arrives via the `Acquired` event (the queue is non-optimistic).
pub fn ordered_acquire(runtime: Runtime, address: String) -> String {
  let acquire_id = ids.uuid_v4()
  edit(runtime.cell, fn(core) {
    runtime_core.ordered_acquire(core, address, acquire_id)
  })
  acquire_id
}

@target(javascript)
/// Complete the held job `acquire_id` in the ordered collection at `address`.
pub fn ordered_complete(
  runtime: Runtime,
  address: String,
  acquire_id: String,
) -> Nil {
  edit(runtime.cell, fn(core) {
    runtime_core.ordered_complete(core, address, acquire_id)
  })
}

@target(javascript)
/// Release the held job `acquire_id` back to the ordered collection at `address`.
pub fn ordered_release(
  runtime: Runtime,
  address: String,
  acquire_id: String,
) -> Nil {
  edit(runtime.cell, fn(core) {
    runtime_core.ordered_release(core, address, acquire_id)
  })
}

@target(javascript)
/// The number of queued (not-yet-acquired) items at `address`, `None` when
/// missing or not an ordered-collection channel.
pub fn ordered_size(runtime: Runtime, address: String) -> Option(Int) {
  read(runtime.cell, None, runtime_core.ordered_size(_, address))
}

@target(javascript)
/// Optimistically submit a json0 op to the channel at `address`.
pub fn submit_json_ot(
  runtime: Runtime,
  address: String,
  components: json_ot.Op,
) -> Nil {
  edit(runtime.cell, fn(core) {
    runtime_core.submit_json_ot(core, address, components)
  })
}

@target(javascript)
/// The json0 channel's optimistic document, `None` when the address is missing
/// or not a json0 channel.
pub fn json_ot_view(
  runtime: Runtime,
  address: String,
) -> Option(json_ot.JsonValue) {
  read(runtime.cell, None, runtime_core.json_ot_view(_, address))
}

@target(javascript)
/// Optimistically submit a rich-text delta to the channel at `address`.
pub fn submit_rich_text(
  runtime: Runtime,
  address: String,
  delta: rich_text.Delta,
) -> Nil {
  edit(runtime.cell, fn(core) {
    runtime_core.submit_rich_text(core, address, delta)
  })
}

@target(javascript)
/// The rich-text channel's optimistic document, `None` when the address is
/// missing or not a rich-text channel.
pub fn rich_text_view(
  runtime: Runtime,
  address: String,
) -> Option(rich_text.Document) {
  read(runtime.cell, None, runtime_core.rich_text_view(_, address))
}

@target(javascript)
pub fn or_map_increment(
  runtime: Runtime,
  address: String,
  key: String,
  amount: Int,
) -> Nil {
  edit(runtime.cell, fn(core) {
    runtime_core.or_map_increment(core, address, key, amount)
  })
}

@target(javascript)
pub fn or_map_set(
  runtime: Runtime,
  address: String,
  key: String,
  value: String,
) -> Nil {
  edit(runtime.cell, fn(core) {
    runtime_core.or_map_set(core, address, key, value, transport_js.now_ms())
  })
}

@target(javascript)
pub fn or_map_remove(runtime: Runtime, address: String, key: String) -> Nil {
  edit(runtime.cell, fn(core) { runtime_core.or_map_remove(core, address, key) })
}

@target(javascript)
pub fn or_map_value(
  runtime: Runtime,
  address: String,
  key: String,
) -> Option(OrMapValue) {
  read(runtime.cell, None, runtime_core.or_map_value(_, address, key))
}

@target(javascript)
pub fn or_map_entries(
  runtime: Runtime,
  address: String,
) -> List(#(String, OrMapValue)) {
  read(runtime.cell, [], runtime_core.or_map_entries(_, address))
}

@target(javascript)
pub fn or_map_keys(runtime: Runtime, address: String) -> List(String) {
  read(runtime.cell, [], runtime_core.or_map_keys(_, address))
}

@target(javascript)
pub fn or_set_add(runtime: Runtime, address: String, element: String) -> Nil {
  edit(runtime.cell, fn(core) {
    runtime_core.or_set_add(core, address, element)
  })
}

@target(javascript)
pub fn or_set_remove(
  runtime: Runtime,
  address: String,
  element: String,
) -> Nil {
  edit(runtime.cell, fn(core) {
    runtime_core.or_set_remove(core, address, element)
  })
}

@target(javascript)
pub fn or_set_contains(
  runtime: Runtime,
  address: String,
  element: String,
) -> Bool {
  read(runtime.cell, False, runtime_core.or_set_contains(_, address, element))
}

@target(javascript)
pub fn or_set_values(runtime: Runtime, address: String) -> List(String) {
  read(runtime.cell, [], runtime_core.or_set_values(_, address))
}

@target(javascript)
pub fn g_set_add(runtime: Runtime, address: String, element: String) -> Nil {
  edit(runtime.cell, fn(core) { runtime_core.g_set_add(core, address, element) })
}

@target(javascript)
pub fn g_set_contains(
  runtime: Runtime,
  address: String,
  element: String,
) -> Bool {
  read(runtime.cell, False, runtime_core.g_set_contains(_, address, element))
}

@target(javascript)
pub fn g_set_values(runtime: Runtime, address: String) -> List(String) {
  read(runtime.cell, [], runtime_core.g_set_values(_, address))
}

@target(javascript)
pub fn sequence_insert(
  runtime: Runtime,
  address: String,
  index: Int,
  value: Json,
) -> Result(Nil, String) {
  edit_sequence_with_result(runtime.cell, fn(core) {
    runtime_core.sequence_insert(core, address, index, value)
  })
}

@target(javascript)
pub fn sequence_delete(
  runtime: Runtime,
  address: String,
  index: Int,
) -> Result(Nil, String) {
  edit_sequence_with_result(runtime.cell, fn(core) {
    runtime_core.sequence_delete(core, address, index)
  })
}

@target(javascript)
pub fn sequence_move(
  runtime: Runtime,
  address: String,
  from_index: Int,
  to_index: Int,
) -> Result(Nil, String) {
  edit_sequence_with_result(runtime.cell, fn(core) {
    runtime_core.sequence_move(core, address, from_index, to_index)
  })
}

@target(javascript)
pub fn sequence_replace(
  runtime: Runtime,
  address: String,
  index: Int,
  value: Json,
) -> Result(Nil, String) {
  edit_sequence_with_result(runtime.cell, fn(core) {
    runtime_core.sequence_replace(core, address, index, value)
  })
}

@target(javascript)
pub fn sequence_values(runtime: Runtime, address: String) -> List(Json) {
  read(runtime.cell, [], runtime_core.sequence_values(_, address))
}

@target(javascript)
pub fn sequence_length(runtime: Runtime, address: String) -> Int {
  read(runtime.cell, 0, runtime_core.sequence_length(_, address))
}

// ── SharedText ───────────────────────────────────────────────────────────────

@target(javascript)
/// Insert `value` at the optimistic grapheme `index`. An empty `value` at a
/// valid index is a no-op: `Ok(Nil)` with no outbound effect (see
/// `text_kernel` module docs).
pub fn text_insert(
  runtime: Runtime,
  address: String,
  index: Int,
  value: String,
) -> Result(Nil, String) {
  edit_text_with_result(runtime.cell, fn(core) {
    runtime_core.text_insert(core, address, index, value)
  })
}

@target(javascript)
/// Delete the graphemes in `[start, end)`. An empty range at valid bounds is
/// a no-op.
pub fn text_delete_range(
  runtime: Runtime,
  address: String,
  start: Int,
  end: Int,
) -> Result(Nil, String) {
  edit_text_with_result(runtime.cell, fn(core) {
    runtime_core.text_delete_range(core, address, start, end)
  })
}

@target(javascript)
/// Replace the graphemes in `[start, end)` with `value`. Only an empty range
/// replaced with `""` is a no-op.
pub fn text_replace_range(
  runtime: Runtime,
  address: String,
  start: Int,
  end: Int,
  value: String,
) -> Result(Nil, String) {
  edit_text_with_result(runtime.cell, fn(core) {
    runtime_core.text_replace_range(core, address, start, end, value)
  })
}

@target(javascript)
/// Insert `value` at the end of the text. An empty `value` is a no-op.
pub fn text_append(
  runtime: Runtime,
  address: String,
  value: String,
) -> Result(Nil, String) {
  edit_text_with_result(runtime.cell, fn(core) {
    runtime_core.text_append(core, address, value)
  })
}

@target(javascript)
/// The text channel's current optimistic visible string, `""` when the
/// address is missing or not a text channel.
pub fn text_value(runtime: Runtime, address: String) -> String {
  read(runtime.cell, "", runtime_core.text_value(_, address))
}

@target(javascript)
/// The text channel's current optimistic grapheme count, `0` when the
/// address is missing or not a text channel.
pub fn text_length(runtime: Runtime, address: String) -> Int {
  read(runtime.cell, 0, runtime_core.text_length(_, address))
}

@target(javascript)
/// The graphemes in `[start, end)` of the text channel's optimistic string.
pub fn text_substring(
  runtime: Runtime,
  address: String,
  start: Int,
  end: Int,
) -> Result(String, String) {
  read(
    runtime.cell,
    Error("text_substring requires a ready document connection"),
    runtime_core.text_substring(_, address, start, end),
  )
}

@target(javascript)
/// Create a stable anchor at the gap at `index`; `bias` selects which
/// adjacent grapheme the anchor binds to (`Before` binds to the following
/// grapheme, `After` to the preceding one).
pub fn text_anchor_at(
  runtime: Runtime,
  address: String,
  index: Int,
  bias: text_kernel.Bias,
) -> Result(text_kernel.TextAnchor, String) {
  read(
    runtime.cell,
    Error("text_anchor_at requires a ready document connection"),
    runtime_core.text_anchor_at(_, address, index, bias),
  )
}

@target(javascript)
/// Resolve an anchor to a current optimistic grapheme index.
pub fn text_resolve_anchor(
  runtime: Runtime,
  address: String,
  anchor: text_kernel.TextAnchor,
) -> Result(Int, String) {
  read(
    runtime.cell,
    Error("text_resolve_anchor requires a ready document connection"),
    runtime_core.text_resolve_anchor(_, address, anchor),
  )
}

@target(javascript)
/// An anchor at the start of the text. Always resolves to 0. Pure — doesn't
/// need a `Runtime`/address since it carries no document state.
pub fn text_start_anchor() -> text_kernel.TextAnchor {
  runtime_core.text_start_anchor()
}

@target(javascript)
/// An anchor at the end of the text. Always resolves to the current
/// grapheme length, tracking growth. Pure, like `text_start_anchor`.
pub fn text_end_anchor() -> text_kernel.TextAnchor {
  runtime_core.text_end_anchor()
}

@target(javascript)
/// Encode an anchor as a self-describing JSON value, for example to travel
/// through presence for shared cursors.
pub fn text_anchor_to_json(anchor: text_kernel.TextAnchor) -> Json {
  runtime_core.text_anchor_to_json(anchor)
}

@target(javascript)
/// Decode an anchor from a JSON string produced by `text_anchor_to_json`.
pub fn text_anchor_from_json(
  json_string: String,
) -> Result(text_kernel.TextAnchor, String) {
  runtime_core.text_anchor_from_json(json_string)
}

// ── SharedDirectory ─────────────────────────────────────────────────────────

@target(javascript)
pub fn create_directory(runtime: Runtime) -> Result(String, String) {
  create_channel(runtime, channel.InitDirectory, "create_directory")
}

@target(javascript)
pub fn directory_set(
  runtime: Runtime,
  address: String,
  path: String,
  key: String,
  value: Json,
) -> Nil {
  edit(runtime.cell, fn(core) {
    runtime_core.directory_set(core, address, path, key, value)
  })
}

@target(javascript)
pub fn directory_delete(
  runtime: Runtime,
  address: String,
  path: String,
  key: String,
) -> Nil {
  edit(runtime.cell, fn(core) {
    runtime_core.directory_delete(core, address, path, key)
  })
}

@target(javascript)
pub fn directory_clear(runtime: Runtime, address: String, path: String) -> Nil {
  edit(runtime.cell, fn(core) {
    runtime_core.directory_clear(core, address, path)
  })
}

@target(javascript)
pub fn directory_create_subdirectory(
  runtime: Runtime,
  address: String,
  path: String,
  name: String,
) -> Nil {
  edit(runtime.cell, fn(core) {
    runtime_core.directory_create_subdirectory(core, address, path, name)
  })
}

@target(javascript)
pub fn directory_delete_subdirectory(
  runtime: Runtime,
  address: String,
  path: String,
  name: String,
) -> Nil {
  edit(runtime.cell, fn(core) {
    runtime_core.directory_delete_subdirectory(core, address, path, name)
  })
}

@target(javascript)
pub fn directory_get(
  runtime: Runtime,
  address: String,
  path: String,
  key: String,
) -> Option(Json) {
  read(runtime.cell, None, runtime_core.directory_get(_, address, path, key))
}

@target(javascript)
pub fn directory_entries(
  runtime: Runtime,
  address: String,
  path: String,
) -> List(#(String, Json)) {
  read(runtime.cell, [], runtime_core.directory_entries(_, address, path))
}

@target(javascript)
pub fn directory_subdirectories(
  runtime: Runtime,
  address: String,
  path: String,
) -> List(String) {
  read(runtime.cell, [], runtime_core.directory_subdirectories(_, address, path))
}

@target(javascript)
pub fn directory_has_subdirectory(
  runtime: Runtime,
  address: String,
  path: String,
  name: String,
) -> Bool {
  read(runtime.cell, False, runtime_core.directory_has_subdirectory(
    _,
    address,
    path,
    name,
  ))
}

@target(javascript)
pub fn two_p_set_add(
  runtime: Runtime,
  address: String,
  element: String,
) -> Nil {
  edit(runtime.cell, fn(core) {
    runtime_core.two_p_set_add(core, address, element)
  })
}

@target(javascript)
pub fn two_p_set_remove(
  runtime: Runtime,
  address: String,
  element: String,
) -> Nil {
  edit(runtime.cell, fn(core) {
    runtime_core.two_p_set_remove(core, address, element)
  })
}

@target(javascript)
pub fn two_p_set_contains(
  runtime: Runtime,
  address: String,
  element: String,
) -> Bool {
  read(runtime.cell, False, runtime_core.two_p_set_contains(_, address, element))
}

@target(javascript)
pub fn two_p_set_values(runtime: Runtime, address: String) -> List(String) {
  read(runtime.cell, [], runtime_core.two_p_set_values(_, address))
}

@target(javascript)
pub fn register_write(
  runtime: Runtime,
  address: String,
  key: String,
  value: Json,
) -> Nil {
  edit(runtime.cell, fn(core) {
    runtime_core.register_write(core, address, key, value)
  })
}

@target(javascript)
pub fn register_read(
  runtime: Runtime,
  address: String,
  key: String,
  policy: ReadPolicy,
) -> Option(Json) {
  read(runtime.cell, None, runtime_core.register_read(_, address, key, policy))
}

@target(javascript)
pub fn register_versions(
  runtime: Runtime,
  address: String,
  key: String,
) -> Option(List(Json)) {
  read(runtime.cell, None, runtime_core.register_versions(_, address, key))
}

@target(javascript)
pub fn register_keys(runtime: Runtime, address: String) -> List(String) {
  read(runtime.cell, [], runtime_core.register_keys(_, address))
}

@target(javascript)
pub fn get_claim(
  runtime: Runtime,
  address: String,
  key: String,
) -> Option(Json) {
  read(runtime.cell, None, runtime_core.get_claim(_, address, key))
}

@target(javascript)
pub fn has_claim(runtime: Runtime, address: String, key: String) -> Bool {
  read(runtime.cell, False, runtime_core.has_claim(_, address, key))
}

@target(javascript)
pub fn try_set_claim(
  runtime: Runtime,
  address: String,
  key: String,
  value: Json,
) -> ClaimSubmitReply {
  claim_submit(runtime.cell, address, key, fn(core) {
    runtime_core.try_set_claim(core, address, key, value)
  })
}

@target(javascript)
pub fn compare_and_set_claim(
  runtime: Runtime,
  address: String,
  key: String,
  value: Json,
) -> ClaimSubmitReply {
  claim_submit(runtime.cell, address, key, fn(core) {
    runtime_core.compare_and_set_claim(core, address, key, value)
  })
}

@target(javascript)
pub fn task_manager_volunteer(
  runtime: Runtime,
  address: String,
  task_id: String,
) -> task_manager_kernel.VolunteerOutcome {
  let state = cell_get(runtime.cell)
  case state.phase {
    Ready(core, resubmit_at) ->
      case runtime_core.task_manager_volunteer(core, address, task_id) {
        Error(core_error) ->
          panic as { "task volunteer failed: " <> string.inspect(core_error) }
        Ok(#(core, events, outbound, outcome)) -> {
          cell_set(
            runtime.cell,
            State(..state, phase: Ready(core, resubmit_at)),
          )
          case resubmit_at {
            None -> send_outbound(state.channel, core.client_id, outbound)
            _ -> Nil
          }
          fan_out(state.subscribers, events)
          outcome
        }
      }
    Reconnecting(core) ->
      case runtime_core.task_manager_volunteer(core, address, task_id) {
        Error(core_error) ->
          panic as { "task volunteer failed: " <> string.inspect(core_error) }
        Ok(#(core, events, _outbound, outcome)) -> {
          cell_set(runtime.cell, State(..state, phase: Reconnecting(core)))
          fan_out(state.subscribers, events)
          outcome
        }
      }
    _ -> task_manager_kernel.DisconnectedBeforeAssignment
  }
}

@target(javascript)
pub fn task_manager_abandon(
  runtime: Runtime,
  address: String,
  task_id: String,
) -> Nil {
  edit(runtime.cell, fn(core) {
    runtime_core.task_manager_abandon(core, address, task_id)
  })
}

@target(javascript)
pub fn task_manager_complete(
  runtime: Runtime,
  address: String,
  task_id: String,
) -> Result(Nil, String) {
  let state = cell_get(runtime.cell)
  case state.phase {
    Ready(core, resubmit_at) ->
      case runtime_core.task_manager_complete(core, address, task_id) {
        Error(runtime_core.TaskNotAssigned(_, task_id)) ->
          Error("task is not assigned: " <> task_id)
        Error(core_error) ->
          panic as { "complete_task failed: " <> string.inspect(core_error) }
        Ok(#(core, events, outbound)) -> {
          cell_set(
            runtime.cell,
            State(..state, phase: Ready(core, resubmit_at)),
          )
          case resubmit_at {
            None -> send_outbound(state.channel, core.client_id, outbound)
            _ -> Nil
          }
          fan_out(state.subscribers, events)
          Ok(Nil)
        }
      }
    Reconnecting(core) ->
      case runtime_core.task_manager_complete(core, address, task_id) {
        Error(runtime_core.TaskNotAssigned(_, task_id)) ->
          Error("task is not assigned: " <> task_id)
        Error(core_error) ->
          panic as { "complete_task failed: " <> string.inspect(core_error) }
        Ok(#(core, events, _outbound)) -> {
          cell_set(runtime.cell, State(..state, phase: Reconnecting(core)))
          fan_out(state.subscribers, events)
          Ok(Nil)
        }
      }
    _ -> Error("complete_task requires a ready document connection")
  }
}

@target(javascript)
pub fn task_manager_assigned(
  runtime: Runtime,
  address: String,
  task_id: String,
) -> Bool {
  read(runtime.cell, False, runtime_core.task_manager_assigned(
    _,
    address,
    task_id,
  ))
}

@target(javascript)
pub fn task_manager_queued(
  runtime: Runtime,
  address: String,
  task_id: String,
) -> Bool {
  read(runtime.cell, False, runtime_core.task_manager_queued(
    _,
    address,
    task_id,
  ))
}

@target(javascript)
pub fn task_manager_queues(
  runtime: Runtime,
  address: String,
) -> List(#(String, List(Int))) {
  read(runtime.cell, [], runtime_core.task_manager_queues(_, address))
}

@target(javascript)
/// Create a new detached map channel: local-only until its handle is first
/// stored into an attached map. Returns the generated address.
pub fn create_map(runtime: Runtime) -> Result(String, String) {
  create_channel(runtime, channel.InitMap, "create_map")
}

@target(javascript)
/// Create a new detached counter channel, same lifecycle as `create_map`.
pub fn create_counter(runtime: Runtime) -> Result(String, String) {
  create_channel(runtime, channel.InitCounter, "create_counter")
}

@target(javascript)
/// Create a new detached PN-counter channel, same lifecycle as `create_map`.
pub fn create_pn_counter(runtime: Runtime) -> Result(String, String) {
  create_channel(runtime, channel.InitPnCounter, "create_pn_counter")
}

@target(javascript)
/// Create a new detached PactMap (consensus map) channel, same lifecycle as
/// `create_map`.
pub fn create_pact_map(runtime: Runtime) -> Result(String, String) {
  create_channel(runtime, channel.InitPactMap, "create_pact_map")
}

@target(javascript)
/// Create a new detached ConsensusOrderedCollection channel, same lifecycle as
/// `create_map`.
pub fn create_ordered_collection(runtime: Runtime) -> Result(String, String) {
  create_channel(
    runtime,
    channel.InitOrderedCollection,
    "create_ordered_collection",
  )
}

@target(javascript)
pub fn create_or_map(
  runtime: Runtime,
  mode: OrMapMode,
) -> Result(String, String) {
  create_channel(runtime, channel.InitOrMap(mode), "create_or_map")
}

@target(javascript)
pub fn create_or_set(runtime: Runtime) -> Result(String, String) {
  create_channel(runtime, channel.InitOrSet, "create_or_set")
}

@target(javascript)
pub fn create_g_set(runtime: Runtime) -> Result(String, String) {
  create_channel(runtime, channel.InitGSet, "create_g_set")
}

@target(javascript)
pub fn create_sequence(runtime: Runtime) -> Result(String, String) {
  create_channel(runtime, channel.InitSequence, "create_sequence")
}

@target(javascript)
/// Create a new detached text channel, same lifecycle as `create_map`.
pub fn create_text(runtime: Runtime) -> Result(String, String) {
  create_channel(runtime, channel.InitText, "create_text")
}

@target(javascript)
pub fn create_two_p_set(runtime: Runtime) -> Result(String, String) {
  create_channel(runtime, channel.InitTwoPSet, "create_two_p_set")
}

@target(javascript)
pub fn create_register_collection(runtime: Runtime) -> Result(String, String) {
  create_channel(
    runtime,
    channel.InitRegisterCollection,
    "create_register_collection",
  )
}

@target(javascript)
pub fn create_claims(runtime: Runtime) -> Result(String, String) {
  create_channel(runtime, channel.InitClaims, "create_claims")
}

@target(javascript)
/// Create a new detached json0 channel, same lifecycle as `create_map`.
pub fn create_json_ot(runtime: Runtime) -> Result(String, String) {
  create_channel(runtime, channel.InitJsonOt, "create_json_ot")
}

@target(javascript)
/// Create a new detached rich-text channel, same lifecycle as `create_map`.
pub fn create_rich_text(runtime: Runtime) -> Result(String, String) {
  create_channel(runtime, channel.InitRichText, "create_rich_text")
}

@target(javascript)
pub fn create_task_manager(runtime: Runtime) -> Result(String, String) {
  create_channel(runtime, channel.InitTaskManager, "create_task_manager")
}

@target(javascript)
fn claim_submit(
  cell: Cell(State),
  address: String,
  key: String,
  operate: fn(runtime_core.Core) ->
    Result(runtime_core.ClaimSubmitResult, runtime_core.CoreError),
) -> ClaimSubmitReply {
  let state = cell_get(cell)
  case state.phase {
    Ready(core, resubmit_at) ->
      case operate(core) {
        Error(runtime_core.WrongChannelType(..)) -> WrongChannelType
        Error(core_error) ->
          panic as { "claim submit failed: " <> string.inspect(core_error) }
        Ok(runtime_core.ClaimAlreadyClaimed(current_value)) ->
          AlreadyClaimed(current_value)
        Ok(runtime_core.ClaimAlreadyPendingLocally) -> AlreadyPendingLocally
        Ok(runtime_core.ClaimPending(core, outbound, immediate_outcome)) -> {
          let #(promise_outcome, resolve_outcome) = promise.start()
          let state =
            register_claim_waiter(
              state,
              address,
              key,
              resolve_outcome,
              immediate_outcome,
            )
          cell_set(cell, State(..state, phase: Ready(core, resubmit_at)))
          case resubmit_at {
            None -> send_outbound(state.channel, core.client_id, outbound)
            Some(_) -> Nil
          }
          Pending(promise_outcome)
        }
      }
    Reconnecting(core) ->
      case operate(core) {
        Error(runtime_core.WrongChannelType(..)) -> WrongChannelType
        Error(core_error) ->
          panic as { "claim submit failed: " <> string.inspect(core_error) }
        Ok(runtime_core.ClaimAlreadyClaimed(current_value)) ->
          AlreadyClaimed(current_value)
        Ok(runtime_core.ClaimAlreadyPendingLocally) -> AlreadyPendingLocally
        Ok(runtime_core.ClaimPending(core, _outbound, immediate_outcome)) -> {
          let #(promise_outcome, resolve_outcome) = promise.start()
          let state =
            register_claim_waiter(
              state,
              address,
              key,
              resolve_outcome,
              immediate_outcome,
            )
          cell_set(cell, State(..state, phase: Reconnecting(core)))
          Pending(promise_outcome)
        }
      }
    _ -> WrongChannelType
  }
}

@target(javascript)
fn create_channel(
  runtime: Runtime,
  init: channel.ChannelInit,
  verb: String,
) -> Result(String, String) {
  let state = cell_get(runtime.cell)
  case state.phase {
    Ready(core, resubmit_at) -> {
      let address = ids.uuid_v4()
      let core = runtime_core.create_detached(core, address, init)
      cell_set(runtime.cell, State(..state, phase: Ready(core, resubmit_at)))
      Ok(address)
    }
    Reconnecting(core) -> {
      let address = ids.uuid_v4()
      let core = runtime_core.create_detached(core, address, init)
      cell_set(runtime.cell, State(..state, phase: Reconnecting(core)))
      Ok(address)
    }
    _ -> Error(verb <> " requires a ready document connection")
  }
}

@target(javascript)
/// Whether a channel exists at `address` (attached or detached). Errors are
/// retryable — a foreign attach may still be in flight.
pub fn resolve_address(
  runtime: Runtime,
  address: String,
) -> Result(Nil, String) {
  case read(runtime.cell, False, runtime_core.has_channel(_, address)) {
    True -> Ok(Nil)
    False ->
      Error(
        "unresolved handle: no channel at address "
        <> address
        <> " (a foreign attach may still be in flight; retry)",
      )
  }
}

@target(javascript)
pub fn resolve_sequence(
  runtime: Runtime,
  address: String,
) -> Result(Nil, String) {
  let state = cell_get(runtime.cell)
  case state.phase {
    Ready(core, _) | Reconnecting(core) ->
      case
        runtime_core.require_channel_type(
          core,
          address,
          channel.SequenceChannel,
        )
      {
        Ok(Nil) -> Ok(Nil)
        Error(error) -> Error(string.inspect(error))
      }
    _ -> Error("resolve_sequence requires a ready document connection")
  }
}

@target(javascript)
pub fn resolve_text(runtime: Runtime, address: String) -> Result(Nil, String) {
  let state = cell_get(runtime.cell)
  case state.phase {
    Ready(core, _) | Reconnecting(core) ->
      case
        runtime_core.require_channel_type(core, address, channel.TextChannel)
      {
        Ok(Nil) -> Ok(Nil)
        Error(error) -> Error(string.inspect(error))
      }
    _ -> Error("resolve_text requires a ready document connection")
  }
}

@target(javascript)
/// Register a callback invoked for every local and remote event on the
/// channel at `address`.
pub fn subscribe(
  runtime: Runtime,
  address: String,
  handler: fn(ChannelEvent) -> Nil,
) -> Nil {
  let state = cell_get(runtime.cell)
  cell_set(
    runtime.cell,
    State(..state, subscribers: [#(address, handler), ..state.subscribers]),
  )
}

@target(javascript)
/// Broadcast an ephemeral, document-scoped ripple (`type` + arbitrary JSON
/// `content`). Ripples are non-sequenced and non-persisted — fire-and-forget,
/// with no ack, resubmit, or catch-up. A no-op until the client has a
/// server-assigned client id (i.e. before the first handshake completes).
pub fn send_ripple(
  runtime: Runtime,
  ripple_type: String,
  content: Json,
) -> Nil {
  let state = cell_get(runtime.cell)
  let client_id = case state.phase {
    Ready(core, _) -> Some(core.client_id)
    Reconnecting(core) -> Some(core.client_id)
    _ -> None
  }
  case state.channel, client_id {
    Some(channel), Some(client_id) ->
      push_json(
        channel,
        "submitSignal",
        socket.encode_submit_ripple(
          client_id: client_id,
          ripple_type: ripple_type,
          content: content,
        ),
      )
    _, _ -> Nil
  }
}

@target(javascript)
/// Register a callback invoked for every inbound ephemeral ripple on the
/// document. Content is left as `Dynamic` for the caller to decode.
pub fn subscribe_ripples(
  runtime: Runtime,
  handler: fn(SignalMessage) -> Nil,
) -> Nil {
  let state = cell_get(runtime.cell)
  cell_set(
    runtime.cell,
    State(..state, ripple_subscribers: [handler, ..state.ripple_subscribers]),
  )
}

@target(javascript)
/// Fault-injection hook: drop the socket to force the reconnect/reconcile path.
pub fn force_reconnect(runtime: Runtime) -> Nil {
  let state = cell_get(runtime.cell)
  case state.phase, state.channel {
    Ready(core, _), Some(channel) -> {
      cell_set(runtime.cell, State(..state, phase: Reconnecting(core)))
      channel.drop()
    }
    _, _ -> Nil
  }
}

@target(javascript)
pub fn close(runtime: Runtime) -> Nil {
  let state = abort_claim_waiters(cell_get(runtime.cell))
  cell_set(runtime.cell, State(..state, phase: Failed("runtime closed")))
  case state.channel {
    Some(channel) -> channel.close()
    None -> Nil
  }
}

@target(javascript)
/// Whether the document is fully caught up: every local edit has been
/// acknowledged by the server, so the confirmed state is complete and stable.
pub fn is_synced(runtime: Runtime) -> Bool {
  case cell_get(runtime.cell).phase {
    Ready(core, None) -> runtime_core.is_synced(core)
    _ -> False
  }
}

@target(javascript)
/// Snapshot connection and sequencing state for diagnostics. This does not
/// mutate the runtime and is safe to poll from a debug UI.
pub fn diagnostics(runtime: Runtime) -> Diagnostics {
  case cell_get(runtime.cell).phase {
    Connecting ->
      Diagnostics(
        phase: "connecting",
        client_id: None,
        last_seen_sequence_number: None,
        next_client_sequence_number: None,
        in_flight_count: 0,
        buffered_out_of_order_count: 0,
        resubmit_checkpoint: None,
        synced: False,
      )
    Reconnecting(core) ->
      diagnostics_from_core(core, "reconnecting", None, False)
    Ready(core, Some(checkpoint)) ->
      diagnostics_from_core(core, "catching-up", Some(checkpoint), False)
    Ready(core, None) ->
      diagnostics_from_core(core, "ready", None, runtime_core.is_synced(core))
    Failed(reason) ->
      Diagnostics(
        phase: "failed: " <> reason,
        client_id: None,
        last_seen_sequence_number: None,
        next_client_sequence_number: None,
        in_flight_count: 0,
        buffered_out_of_order_count: 0,
        resubmit_checkpoint: None,
        synced: False,
      )
  }
}

@target(javascript)
fn diagnostics_from_core(
  core: runtime_core.Core,
  phase: String,
  checkpoint: Option(Int),
  synced: Bool,
) -> Diagnostics {
  Diagnostics(
    phase: phase,
    client_id: Some(core.client_id),
    last_seen_sequence_number: Some(core.last_seen_sn),
    next_client_sequence_number: Some(core.next_csn),
    in_flight_count: list.length(core.in_flight),
    buffered_out_of_order_count: list.length(core.out_of_order),
    resubmit_checkpoint: checkpoint,
    synced: synced,
  )
}

@target(javascript)
/// Summarize the document's current confirmed state to levee storage so future
/// clients can bootstrap from the snapshot instead of replaying the full op
/// history. Resolves with the summary handle (git tree SHA). Requires the
/// connection to be fully synced and the token to carry `summary:write`.
///
/// Uploading is asynchronous, so the returned Promise settles once the blob is
/// stored and the summarize op has been pushed. The summarize op's sequence
/// number is drawn from the live core at push time (not at upload start) so a
/// concurrent local edit can't collide with it.
pub fn summarize(runtime: Runtime) -> Promise(Result(String, String)) {
  let cell = runtime.cell
  let state = cell_get(cell)
  case state.phase, state.channel {
    Ready(core, None), Some(_) ->
      case state.connect_message.token {
        None -> promise.resolve(Error("summarize requires an auth token"))
        Some(token) ->
          case runtime_core.is_synced(core) {
            False ->
              promise.resolve(Error(
                "summarize requires the client to be caught up; retry once "
                <> "in-flight edits have been acknowledged",
              ))
            True ->
              git_storage.upload_summary(
                base_url: state.http_base_url,
                tenant: state.connect_message.tenant_id,
                token: token,
                sequence_number: core.last_seen_sn,
                channels: runtime_core.summary_channels(core),
              )
              |> promise.map(fn(result) {
                case result {
                  Error(reason) -> Error(reason)
                  Ok(tree_sha) -> finish_summarize(cell, tree_sha)
                }
              })
          }
      }
    _, _ ->
      promise.resolve(Error(
        "summarize is only available once the connection is fully synced",
      ))
  }
}

@target(javascript)
/// List the document's stored summary versions, newest first (the client half
/// of Fluid's `getVersions`). Requires the token to carry `doc:read`.
pub fn get_versions(
  runtime: Runtime,
  count: Int,
) -> Promise(Result(List(git_storage.SummaryVersion), String)) {
  let state = cell_get(runtime.cell)
  case state.connect_message.token {
    None -> promise.resolve(Error("listing versions requires an auth token"))
    Some(token) ->
      git_storage.fetch_versions(
        base_url: state.http_base_url,
        tenant: state.connect_message.tenant_id,
        token: token,
        document: state.connect_message.document_id,
        count: count,
      )
  }
}

@target(javascript)
/// Read the historical snapshot a summary version captured, by its handle
/// (from `get_versions` or a `summarize` resolution). The live document is
/// unaffected — this is a point-in-time read of the stored blob.
pub fn load_version(
  runtime: Runtime,
  handle: String,
) -> Promise(Result(summary_blob.SummaryBlob, String)) {
  let state = cell_get(runtime.cell)
  case state.connect_message.token {
    None -> promise.resolve(Error("loading a version requires an auth token"))
    Some(token) ->
      git_storage.fetch_summary(
        base_url: state.http_base_url,
        tenant: state.connect_message.tenant_id,
        token: token,
        handle: handle,
      )
  }
}

@target(javascript)
/// Stamp the summarize op referencing the uploaded snapshot tree and push it.
/// Re-reads the live state so the op is built from the current core, keeping
/// its client sequence number strictly increasing past any edits that landed
/// during the async upload.
fn finish_summarize(
  cell: Cell(State),
  tree_sha: String,
) -> Result(String, String) {
  let state = cell_get(cell)
  case state.phase, state.channel {
    Ready(core, None), Some(channel) -> {
      let #(core, outbound) =
        runtime_core.build_summarize(
          core,
          handle: tree_sha,
          message: "watershed summary",
          head: tree_sha,
        )
      push_json(
        channel,
        "submitOp",
        socket.encode_submit_op(core.client_id, [[outbound]]),
      )
      cell_set(cell, State(..state, phase: Ready(core, None)))
      Ok(tree_sha)
    }
    _, _ -> Error("connection changed during summarize; retry")
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Transport callbacks
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// (Re)join succeeded: (re)send `connect_document`. On the initial join this
/// starts the handshake; on a Phoenix auto-rejoin it re-handshakes with our
/// last-seen SN so the server pushes just the delta.
fn on_join(cell: Cell(State)) -> Nil {
  let state = cell_get(cell)
  case state.channel {
    None -> Nil
    Some(channel) ->
      case state.phase {
        Connecting -> push_connect(channel, state.connect_message, None)
        Reconnecting(core) ->
          push_connect(channel, state.connect_message, Some(core.last_seen_sn))
        Ready(core, _) -> {
          // Rejoin without an intervening close event; treat as reconnect.
          cell_set(cell, State(..state, phase: Reconnecting(core)))
          push_connect(channel, state.connect_message, Some(core.last_seen_sn))
        }
        Failed(_) -> Nil
      }
  }
}

@target(javascript)
fn on_close(cell: Cell(State)) -> Nil {
  let state = cell_get(cell)
  case state.phase {
    // Preserve the core so kernel/pending/in-flight survive the reconnect.
    Ready(core, _) | Reconnecting(core) ->
      cell_set(cell, State(..state, phase: Reconnecting(core)))
    // Not yet connected: Phoenix will retry the join, which re-fires on_join.
    _ -> Nil
  }
}

@target(javascript)
fn on_event(cell: Cell(State), event: String, payload: Dynamic) -> Nil {
  case event {
    "connect_document_success" -> on_connect_success(cell, payload)
    "connect_document_error" -> on_connect_error(cell, payload)
    "op" -> on_op(cell, payload)
    "nack" -> on_nack(cell, payload)
    "signal" -> on_ripple(cell, payload)
    _ -> Nil
  }
}

@target(javascript)
fn on_connect_success(cell: Cell(State), payload: Dynamic) -> Nil {
  case decode.run(payload, socket.connected_message_decoder()) {
    Error(_) -> fail(cell, "malformed connect_document_success payload")
    Ok(connected) -> {
      let state = cell_get(cell)
      case state.phase {
        Connecting ->
          // A never-summarized document bootstraps synchronously from
          // `initialMessages`. A summarized document first fetches its summary
          // blob over HTTP (async), then bootstraps seeded from that state.
          case connected.summary_context {
            None -> finish_bootstrap(cell, connected, None)
            Some(ctx) ->
              load_summary_then_bootstrap(cell, state, connected, ctx)
          }
        Reconnecting(core) -> {
          let core = runtime_core.adopt_reconnect(core, connected)
          let checkpoint =
            option.unwrap(
              connected.checkpoint_sequence_number,
              core.last_seen_sn,
            )
          settle_reconnect(cell, core, checkpoint)
        }
        _ -> Nil
      }
    }
  }
}

@target(javascript)
/// Fetch the summary blob referenced by `ctx`, then bootstrap the core seeded
/// from it. Real-time ops that arrive during the async fetch are dropped while
/// still `Connecting`, but the gap they create is self-healing: the first op
/// after bootstrap that is non-contiguous triggers a `requestOps` catch-up.
fn load_summary_then_bootstrap(
  cell: Cell(State),
  state: State,
  connected: ConnectedMessage,
  ctx: SummaryContext,
) -> Nil {
  case state.connect_message.token {
    None -> fail(cell, "loading a summarized document requires an auth token")
    Some(token) -> {
      let _ =
        git_storage.fetch_summary(
          base_url: state.http_base_url,
          tenant: state.connect_message.tenant_id,
          token: token,
          handle: ctx.handle,
        )
        |> promise.map(fn(result) {
          case result {
            Error(reason) -> fail(cell, "summary load failed: " <> reason)
            Ok(blob) ->
              finish_bootstrap(
                cell,
                connected,
                // The blob records the SN it was captured at, but the
                // authoritative load point is the server's summaryContext.
                Some(runtime_core.Summary(
                  sequence_number: ctx.sequence_number,
                  channels: list.map(blob.channels, fn(ch) {
                    #(ch.address, ch.snapshot)
                  }),
                )),
              )
          }
        })
      Nil
    }
  }
}

@target(javascript)
/// Bootstrap the core (optionally seeded from a summary) and fire `on_ready`.
fn finish_bootstrap(
  cell: Cell(State),
  connected: ConnectedMessage,
  summary: Option(runtime_core.Summary),
) -> Nil {
  case runtime_core.bootstrap(connected, summary: summary) {
    Ok(bootstrapped) -> continue_bootstrap(cell, bootstrapped)
    Error(err) -> fail(cell, "bootstrap failed: " <> string.inspect(err))
  }
}

@target(javascript)
/// Complete a bootstrap step: ready the document, or page the missing history
/// prefix from the deltas REST endpoint (async, possibly several rounds) and
/// resume. Bootstrap must not complete on a gapped history, so any failure
/// here drives the cell to `Failed`.
fn continue_bootstrap(
  cell: Cell(State),
  bootstrapped: runtime_core.Bootstrapped,
) -> Nil {
  case bootstrapped {
    runtime_core.Complete(core) -> {
      cell_set(cell, State(..cell_get(cell), phase: Ready(core, None)))
      fire_ready(cell, Ok(Nil))
    }
    runtime_core.MissingPrefix(core, checkpoint, from, to) -> {
      let state = cell_get(cell)
      case state.connect_message.token {
        None -> fail(cell, "history catch-up requires an auth token")
        Some(token) -> {
          let _ =
            git_storage.fetch_deltas(
              base_url: state.http_base_url,
              tenant: state.connect_message.tenant_id,
              token: token,
              document: state.connect_message.document_id,
              from: from,
              to: to,
            )
            |> promise.map(fn(result) {
              case result {
                Error(reason) ->
                  fail(cell, "history catch-up failed: " <> reason)
                Ok(deltas) ->
                  case
                    runtime_core.resume_bootstrap(
                      core,
                      checkpoint: checkpoint,
                      deltas: deltas,
                    )
                  {
                    Ok(next) -> continue_bootstrap(cell, next)
                    Error(err) ->
                      fail(cell, "bootstrap failed: " <> string.inspect(err))
                  }
              }
            })
          Nil
        }
      }
    }
  }
}

@target(javascript)
fn on_connect_error(cell: Cell(State), payload: Dynamic) -> Nil {
  case decode.run(payload, socket.connect_error_decoder()) {
    Ok(err) -> fail(cell, err.message)
    Error(_) -> fail(cell, "connect_document_error")
  }
}

@target(javascript)
fn on_op(cell: Cell(State), payload: Dynamic) -> Nil {
  let state = cell_get(cell)
  case state.phase {
    Ready(core, resubmit_at) ->
      case decode.run(payload, socket.op_message_decoder()) {
        Error(_) -> fail(cell, "malformed op payload")
        Ok(message) ->
          case apply_ops(core, message.ops) {
            Ok(#(core, events, resolutions, request_from, released)) -> {
              let state = resolve_claim_waiters(state, resolutions)
              // Commit the new core before fan-out (see fan_out's contract).
              case resubmit_at {
                Some(checkpoint) -> {
                  cell_set(cell, state)
                  settle_reconnect(cell, core, checkpoint)
                }
                None -> cell_set(cell, State(..state, phase: Ready(core, None)))
              }
              fan_out(state.subscribers, events)
              maybe_request_ops(state.channel, request_from)
              send_outbound(state.channel, core.client_id, released)
            }
            Error(core_error) ->
              fail(
                cell,
                "sequenced op processing failed: " <> string.inspect(core_error),
              )
          }
      }
    // Ops before a connected session (or while reconnecting) carry no state
    // we can trust; ignore them.
    _ -> Nil
  }
}

@target(javascript)
fn on_nack(cell: Cell(State), payload: Dynamic) -> Nil {
  case decode.run(payload, socket.nacks_decoder()) {
    Error(_) -> fail(cell, "malformed nack payload")
    Ok(nacks) ->
      case list.any(nacks, nack_is_fatal) {
        True -> fail(cell, "fatal nack from server")
        False -> {
          let state = cell_get(cell)
          case state.phase, state.channel {
            Ready(core, _), Some(channel) -> {
              cell_set(cell, State(..state, phase: Reconnecting(core)))
              channel.drop()
            }
            _, _ -> Nil
          }
        }
      }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// State machine helpers (ported from the erlang runtime)
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
fn settle_reconnect(
  cell: Cell(State),
  core: runtime_core.Core,
  checkpoint: Int,
) -> Nil {
  let state = cell_get(cell)
  case core.last_seen_sn >= checkpoint {
    True -> {
      let #(core, outbound) = runtime_core.resubmit(core)
      send_outbound(state.channel, core.client_id, outbound)
      cell_set(cell, State(..state, phase: Ready(core, None)))
    }
    False ->
      cell_set(cell, State(..state, phase: Ready(core, Some(checkpoint))))
  }
}

@target(javascript)
fn apply_ops(
  core: runtime_core.Core,
  ops: List(SequencedDocumentMessage),
) -> Result(
  #(
    runtime_core.Core,
    List(#(String, ChannelEvent)),
    List(#(String, Resolution)),
    Option(Int),
    List(wire.OutboundOp),
  ),
  runtime_core.CoreError,
) {
  do_apply_ops(core, ops, [], [], None, [])
}

@target(javascript)
fn do_apply_ops(
  core: runtime_core.Core,
  ops: List(SequencedDocumentMessage),
  events: List(List(#(String, ChannelEvent))),
  resolutions: List(List(#(String, Resolution))),
  request_from: Option(Int),
  released: List(wire.OutboundOp),
) -> Result(
  #(
    runtime_core.Core,
    List(#(String, ChannelEvent)),
    List(#(String, Resolution)),
    Option(Int),
    List(wire.OutboundOp),
  ),
  runtime_core.CoreError,
) {
  case ops {
    [] ->
      Ok(#(
        core,
        list.reverse(events) |> list.flatten,
        list.reverse(resolutions) |> list.flatten,
        request_from,
        released,
      ))
    [op, ..rest] ->
      case runtime_core.handle_sequenced(core, op) {
        Ok(#(core, ingested)) ->
          do_apply_ops(
            core,
            rest,
            [ingested.events, ..events],
            [ingested.resolutions, ..resolutions],
            option.or(request_from, ingested.request_ops_from),
            list.append(released, ingested.outbound),
          )
        Error(core_error) -> Error(core_error)
      }
  }
}

@target(javascript)
fn register_claim_waiter(
  state: State,
  address: String,
  key: String,
  resolve_outcome: fn(claims_kernel.ClaimOutcome) -> Nil,
  immediate_outcome: Option(claims_kernel.ClaimOutcome),
) -> State {
  case immediate_outcome {
    Some(outcome) -> {
      resolve_outcome(outcome)
      state
    }
    None ->
      State(
        ..state,
        claim_waiters: dict.insert(
          state.claim_waiters,
          #(address, key),
          resolve_outcome,
        ),
      )
  }
}

@target(javascript)
fn resolve_claim_waiters(
  state: State,
  resolutions: List(#(String, Resolution)),
) -> State {
  let claim_waiters =
    list.fold(resolutions, state.claim_waiters, fn(acc, item) {
      let #(address, resolution) = item
      case resolution {
        ClaimResolved(key, outcome) ->
          case dict.get(acc, #(address, key)) {
            Ok(resolve_outcome) -> {
              resolve_outcome(outcome)
              dict.delete(acc, #(address, key))
            }
            Error(_) -> acc
          }
      }
    })
  State(..state, claim_waiters: claim_waiters)
}

@target(javascript)
fn abort_claim_waiters(state: State) -> State {
  dict.values(state.claim_waiters)
  |> list.each(fn(resolve_outcome) { resolve_outcome(claims_kernel.Aborted) })
  State(..state, claim_waiters: dict.new())
}

@target(javascript)
fn edit(
  cell: Cell(State),
  operate: fn(runtime_core.Core) ->
    Result(
      #(runtime_core.Core, List(#(String, ChannelEvent)), List(wire.OutboundOp)),
      runtime_core.CoreError,
    ),
) -> Nil {
  let state = cell_get(cell)
  case state.phase {
    Ready(core, resubmit_at) -> {
      case operate(core) {
        Error(core_error) ->
          panic as { "local edit failed: " <> string.inspect(core_error) }
        Ok(#(core, events, outbound)) -> {
          // Commit the new core before fan-out (see fan_out's contract).
          cell_set(cell, State(..state, phase: Ready(core, resubmit_at)))
          // Push immediately only when fully synced with a live channel;
          // otherwise the op stays in-flight and `resubmit` sends it once, so a
          // reconnect can't drop or duplicate it.
          case resubmit_at {
            None -> send_outbound(state.channel, core.client_id, outbound)
            _ -> Nil
          }
          fan_out(state.subscribers, events)
        }
      }
    }
    Reconnecting(core) -> {
      case operate(core) {
        Error(core_error) ->
          panic as { "local edit failed: " <> string.inspect(core_error) }
        Ok(#(core, events, _outbound)) -> {
          cell_set(cell, State(..state, phase: Reconnecting(core)))
          fan_out(state.subscribers, events)
        }
      }
    }
    // Edits before ready are dropped (the demo gates edits behind on_ready).
    _ -> Nil
  }
}

@target(javascript)
fn edit_sequence_with_result(
  cell: Cell(State),
  operate: fn(runtime_core.Core) ->
    Result(
      #(runtime_core.Core, List(#(String, ChannelEvent)), List(wire.OutboundOp)),
      runtime_core.CoreError,
    ),
) -> Result(Nil, String) {
  let state = cell_get(cell)
  case state.phase {
    Ready(core, resubmit_at) ->
      case operate(core) {
        Ok(#(core, events, outbound)) -> {
          cell_set(cell, State(..state, phase: Ready(core, resubmit_at)))
          case resubmit_at {
            None -> send_outbound(state.channel, core.client_id, outbound)
            Some(_) -> Nil
          }
          fan_out(state.subscribers, events)
          Ok(Nil)
        }
        Error(runtime_core.SequenceOpFailed(_, detail)) -> Error(detail)
        Error(error) -> Error(string.inspect(error))
      }
    Reconnecting(core) ->
      case operate(core) {
        Ok(#(core, events, _outbound)) -> {
          cell_set(cell, State(..state, phase: Reconnecting(core)))
          fan_out(state.subscribers, events)
          Ok(Nil)
        }
        Error(runtime_core.SequenceOpFailed(_, detail)) -> Error(detail)
        Error(error) -> Error(string.inspect(error))
      }
    _ -> Error("sequence edit before the document connection is ready")
  }
}

@target(javascript)
fn edit_text_with_result(
  cell: Cell(State),
  operate: fn(runtime_core.Core) ->
    Result(
      #(runtime_core.Core, List(#(String, ChannelEvent)), List(wire.OutboundOp)),
      runtime_core.CoreError,
    ),
) -> Result(Nil, String) {
  let state = cell_get(cell)
  case state.phase {
    Ready(core, resubmit_at) ->
      case operate(core) {
        Ok(#(core, events, outbound)) -> {
          cell_set(cell, State(..state, phase: Ready(core, resubmit_at)))
          case resubmit_at {
            None -> send_outbound(state.channel, core.client_id, outbound)
            Some(_) -> Nil
          }
          fan_out(state.subscribers, events)
          Ok(Nil)
        }
        Error(runtime_core.TextOpFailed(_, detail)) -> Error(detail)
        Error(error) -> Error(string.inspect(error))
      }
    Reconnecting(core) ->
      case operate(core) {
        Ok(#(core, events, _outbound)) -> {
          cell_set(cell, State(..state, phase: Reconnecting(core)))
          fan_out(state.subscribers, events)
          Ok(Nil)
        }
        Error(runtime_core.TextOpFailed(_, detail)) -> Error(detail)
        Error(error) -> Error(string.inspect(error))
      }
    _ -> Error("text edit before the document connection is ready")
  }
}

@target(javascript)
fn read(
  cell: Cell(State),
  default: t,
  extract: fn(runtime_core.Core) -> t,
) -> t {
  case cell_get(cell).phase {
    Ready(core, _) -> extract(core)
    Reconnecting(core) -> extract(core)
    _ -> default
  }
}

@target(javascript)
fn nack_is_fatal(item: Nack) -> Bool {
  case item.content.error_type {
    nack.InvalidScopeError -> True
    nack.LimitExceededError -> True
    _ -> item.content.code == 413
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// IO helpers
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
fn push_connect(
  channel: TransportHandle,
  connect_message: ConnectMessage,
  last_seen: Option(Int),
) -> Nil {
  push_json(
    channel,
    "connect_document",
    socket.encode_connect_document(connect_message, last_seen),
  )
}

@target(javascript)
fn maybe_request_ops(
  channel: Option(TransportHandle),
  request_from: Option(Int),
) -> Nil {
  case channel, request_from {
    Some(channel), Some(from) ->
      push_json(channel, "requestOps", socket.encode_request_ops(from: from))
    _, _ -> Nil
  }
}

@target(javascript)
fn send_outbound(
  channel: Option(TransportHandle),
  client_id: String,
  outbound: List(wire.OutboundOp),
) -> Nil {
  case channel, outbound {
    _, [] -> Nil
    Some(channel), _ ->
      list.each(list.sized_chunk(outbound, max_ops_per_submission), fn(chunk) {
        push_json(
          channel,
          "submitOp",
          socket.encode_submit_op(client_id, [chunk]),
        )
      })
    None, _ -> Nil
  }
}

@target(javascript)
fn push_json(channel: TransportHandle, event: String, payload: Json) -> Nil {
  channel.push(event, payload)
}

@target(javascript)
/// Derive the HTTP(S) base URL for git-storage calls from the Phoenix socket
/// URL, e.g. `ws://localhost:4000/socket/websocket?vsn=2.0.0` →
/// `http://localhost:4000`. `wss` maps to `https`; everything else to `http`.
fn http_base_from_socket_url(url: String) -> String {
  case uri.parse(url) {
    Ok(parsed) -> {
      let scheme = case parsed.scheme {
        Some("wss") | Some("https") -> "https"
        _ -> "http"
      }
      let host = option.unwrap(parsed.host, "localhost")
      let port = case parsed.port {
        Some(p) -> ":" <> int.to_string(p)
        None -> ""
      }
      scheme <> "://" <> host <> port
    }
    Error(_) -> url
  }
}

@target(javascript)
/// Route each address-tagged event to the subscribers registered for that
/// channel address.
///
/// Contract: callers must commit the updated core to the cell before fanning
/// out, so a handler that reads the map during the event observes the
/// just-applied state (local edits, remote ops, and reconnects alike).
fn fan_out(
  subscribers: List(#(String, fn(ChannelEvent) -> Nil)),
  events: List(#(String, ChannelEvent)),
) -> Nil {
  list.each(events, fn(event) {
    let #(address, event) = event
    list.each(subscribers, fn(subscriber) {
      case subscriber.0 == address {
        True -> subscriber.1(event)
        False -> Nil
      }
    })
  })
}

@target(javascript)
/// Fan an inbound ephemeral `signal` broadcast out to ripple subscribers.
/// (The wire event is Fluid's `"signal"`; we surface it as a *ripple*.)
/// Malformed payloads are dropped silently — ripples are best-effort.
fn on_ripple(cell: Cell(State), payload: Dynamic) -> Nil {
  case decode.run(payload, socket.ripple_message_decoder()) {
    Error(_) -> Nil
    Ok(ripple) -> {
      let state = cell_get(cell)
      list.each(state.ripple_subscribers, fn(handler) { handler(ripple) })
    }
  }
}

@target(javascript)
fn fail(cell: Cell(State), reason: String) -> Nil {
  let state = abort_claim_waiters(cell_get(cell))
  fire_ready(cell, Error(reason))
  cell_set(cell, State(..state, phase: Failed(reason)))
}

@target(javascript)
/// Fire the one-shot `on_ready` callback exactly once.
fn fire_ready(cell: Cell(State), result: Result(Nil, String)) -> Nil {
  let state = cell_get(cell)
  case state.ready_fired {
    True -> Nil
    False -> {
      cell_set(cell, State(..state, ready_fired: True))
      state.on_ready(result)
    }
  }
}

@target(javascript)
fn cell_get(cell: Cell(State)) -> State {
  transport_js.get_cell(cell)
}

@target(javascript)
fn cell_set(cell: Cell(State), state: State) -> Nil {
  transport_js.set_cell(cell, state)
}
