//// JavaScript runtime for the SharedMap client — the browser counterpart of
//// the Erlang `watershed/runtime_beam` OTP actor.
////
//// This module has the same responsibilities as that actor: the handshake, the
//// CSN and RSN stamps, the order of the inbound frames, the catch-up after a
//// gap, the reconnect and reconcile, and the event fan-out. It drives the
//// *same* pure core, which is `runtime_core`, `wire`, and `map_kernel`. It uses
//// no OTP. The state is in a mutable cell, and the Phoenix transport delivers
//// its events through callbacks.
////
//// JavaScript target only. `@target(javascript)` gates the module.

@target(javascript)
import gleam/dict.{type Dict}
@target(javascript)
import gleam/dynamic.{type Dynamic}
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
import gleam/result
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
import watershed/channel.{
  type ChannelEvent, type Resolution, AcquireResolved, ClaimResolved,
}
@target(javascript)
import watershed/claims_kernel
@target(javascript)
import watershed/git_storage
@target(javascript)
import watershed/id
@target(javascript)
import watershed/json_ot
@target(javascript)
import watershed/or_map_kernel.{type OrMapMode, type OrMapValue}
@target(javascript)
import watershed/ordered_collection_kernel
@target(javascript)
import watershed/pact_map_kernel
@target(javascript)
import watershed/register_collection_kernel.{type ReadPolicy}
@target(javascript)
import watershed/rich_text
@target(javascript)
import watershed/runtime_core
@target(javascript)
import watershed/summary_policy
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
/// The server nacks a submission of more than 100 operations. Split a resubmit
/// into chunks to stay below that limit.
const max_operations_per_submission = 100

// ─────────────────────────────────────────────────────────────────────────────
// Transport seam
//
// The runtime talks to floodgate through an injectable `Transport` rather than
// calling `transport_js` directly, so the in-memory hub (see `watershed/hub`)
// can supply an alternate transport for deterministic app tests. The concrete
// link (a phoenix `Channel`, a hub cell) is captured inside the closures of a
// `TransportHandle`, so no connection-specific type leaks into `State`.
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// The outbound operations of a live connection. `push` carries the wire event
/// and its JSON payload. `close` shuts the connection down. `drop` forces the
/// reconnect path, which for Phoenix is a socket drop that joins again by
/// itself.
///
/// `hold` and `resume` are `drop`, split into two steps. `drop` goes away and
/// comes back in one step. That shape is correct for a fault injection, and
/// incorrect for an offline mode, because there is no interval in the middle to
/// edit in. A held connection stays held until a `resume` call. The runtime
/// keeps its core in both forms, so an edit from that interval is still there,
/// and the rejoin sends it.
pub type TransportHandle {
  TransportHandle(
    push: fn(String, Json) -> Nil,
    close: fn() -> Nil,
    drop: fn() -> Nil,
    hold: fn() -> Nil,
    resume: fn() -> Nil,
  )
}

@target(javascript)
/// How a transport reports its inbound frames and its join and close lifecycle
/// back to the runtime. Phoenix calls these functions from its socket. The hub
/// calls them at an explicit delivery.
pub type TransportCallbacks {
  TransportCallbacks(
    on_event: fn(String, String) -> Nil,
    /// This callback runs after every successful join. It is also the hook for
    /// a new handshake.
    on_join: fn() -> Nil,
    on_close: fn() -> Nil,
  )
}

@target(javascript)
/// A replaceable connection to a floodgate-shaped server. `connect` opens the
/// link, connects the callbacks, and returns the handle for the outbound
/// frames.
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
/// One ordered inbox for the presence lane. It carries the data frames and the
/// connection lifecycle events that a presence driver must react to.
///
/// The two share one channel on purpose. A driver that learned about a lost
/// session from one source, and about the diffs from another source, could
/// apply a diff that belongs to a dead session. One stream cannot represent
/// that order.
pub type PresenceFrame {
  /// A `presence_state` snapshot, which the runtime does not decode. The
  /// runtime has no decoder for the metadata of the application, and the
  /// operation lane does have one. The payload is the raw event JSON, a typed
  /// boundary the typed driver decodes with its own `presence.config_decoder`.
  PresenceState(payload: String)
  PresenceDiff(payload: String)
  PresenceError(payload: String)
  /// A new document session settled. The frame carries a new client id from
  /// the server, and the features that this handshake negotiated. The runtime
  /// sends it after the first handshake and after every reconnect, and a
  /// driver rejoins on it.
  PresenceSession(client_id: String, presence_v1: Bool)
  /// The session ended. Every presence that the server held for it is gone.
  PresenceSessionLost
}

@target(javascript)
type Subscriber {
  Subscriber(id: String, address: String, handler: fn(ChannelEvent) -> Nil)
}

@target(javascript)
type Phase {
  Connecting
  /// The socket is closed and the runtime is doing the handshake again. This
  /// state holds the core from before the reconnect.
  Reconnecting(core: runtime_core.Core)
  /// The runtime is connected. `resubmit_at` is `Some(checkpoint)` while a
  /// reconnect still catches up to the point at which the runtime can resubmit
  /// the operations with no ack. It is `None` after the runtime is
  /// synchronized.
  Ready(core: runtime_core.Core, resubmit_at: Option(Int))
  Failed(reason: String)
}

@target(javascript)
type State {
  State(
    connect_message: ConnectMessage,
    /// The base HTTP or HTTPS URL for the git-storage calls, which the
    /// summaries use. It comes from the Phoenix socket URL. floodgate serves
    /// the socket and the REST API from one origin.
    http_base_url: String,
    channel: Option(TransportHandle),
    phase: Phase,
    subscribers: List(Subscriber),
    /// The subscribers for the ephemeral ripples. A ripple belongs to one
    /// document and does not sequence, so the fan-out is separate from the
    /// operation event stream.
    ripple_subscribers: List(fn(SignalMessage) -> Nil),
    /// The subscribers on the presence lane. Presence does not sequence and
    /// never touches the core, the same as a ripple.
    presence_subscribers: List(fn(PresenceFrame) -> Nil),
    /// What the handshake of the *current* connection announced. This field is
    /// on `State`, and not on the core, and that is deliberate. The core stays
    /// intact across a reconnect. A capability on the core would thus outlive
    /// the connection that negotiated it, and it could claim support on a
    /// server that does not have it.
    supported_features: Dict(String, Dynamic),
    claim_waiters: Dict(
      #(String, String),
      fn(claims_kernel.ClaimOutcome) -> Nil,
    ),
    /// The pending acquires on an ordered collection, which wait for their
    /// sequenced outcome, keyed by `#(address, acquire_id)`.
    acquire_waiters: Dict(
      #(String, String),
      fn(ordered_collection_kernel.AcquireOutcome) -> Nil,
    ),
    on_ready: fn(Result(Nil, String)) -> Nil,
    ready_fired: Bool,
    /// The automatic summarization policy. The value is `None` unless an
    /// application asked for one. This field is on `State`, and not on the
    /// core, because it is part of the configuration of this client, and not
    /// part of the document.
    auto_summary: Option(summary_policy.Policy),
    /// Whether a summarization wake-up is scheduled already. Without this flag,
    /// a busy document would arm a new timer for every sequenced operation.
    summary_armed: Bool,
    /// How the runtime schedules delayed work. In production it uses the real
    /// `setTimeout` function. The in-memory hub substitutes its logical clock,
    /// so `sluice_js.advance` drives the delay window of the policy, and not
    /// the elapsed time.
    scheduler: transport_js.Scheduler,
  )
}

@target(javascript)
/// An opaque handle to a running document runtime.
pub opaque type Runtime {
  Runtime(cell: Cell(State))
}

@target(javascript)
/// A token for one channel subscription, which a caller can remove.
pub opaque type SubscriptionToken {
  SubscriptionToken(runtime: Runtime, id: String)
}

@target(javascript)
/// Runtime state that you can read but not change, for diagnostics and for the
/// example tools.
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
    /// The operations that sequenced after the newest checkpoint that this
    /// client knows about. An automatic summarization policy compares this
    /// count with its threshold, and a client that joins replays these
    /// operations on top of that checkpoint.
    operations_since_summary: Int,
    /// Whether an automatic summarization attempt is scheduled and waits for
    /// its delay window. The value is always `False` without a policy.
    summary_pending: Bool,
  )
}

@target(javascript)
/// Start a runtime. The function opens the Phoenix socket, joins the topic, and
/// starts the handshake. `on_ready` runs one time. It gives `Ok(Nil)` after the
/// document bootstraps, or `Error(reason)` when the server refuses the
/// connection.
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
/// Start a runtime against any transport. The live `start` function, which uses
/// Phoenix, calls this function, and so does the in-memory hub test driver.
/// `http_base_url` supplies the REST summary API only. A transport that serves
/// no such API can pass any value.
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
      presence_subscribers: [],
      supported_features: dict.new(),
      claim_waiters: dict.new(),
      acquire_waiters: dict.new(),
      on_ready: on_ready,
      ready_fired: False,
      auto_summary: None,
      summary_armed: False,
      scheduler: transport_js.real_scheduler(),
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
/// The default transport: a Phoenix socket over `transport_js`. Phoenix joins
/// again by itself after a socket drop, and it runs `on_join` again. The runtime
/// thus never calls `connect` a second time.
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
      hold: fn() { transport_js.hold_socket(channel) },
      resume: fn() { transport_js.resume_socket(channel) },
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
pub fn get(
  runtime: Runtime,
  address: String,
  key: String,
) -> Result(Json, Nil) {
  read(runtime.cell, Error(Nil), runtime_core.get(_, address, key))
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
  result.is_ok(get(runtime, address, key))
}

@target(javascript)
/// Increment the counter at `address` optimistically. A negative amount
/// decrements it.
pub fn increment(runtime: Runtime, address: String, amount: Int) -> Nil {
  edit(runtime.cell, fn(core) { runtime_core.increment(core, address, amount) })
}

@target(javascript)
/// The optimistic value of the counter. The result is `Error(Nil)` when the address
/// does not exist, and when it does not name a counter channel.
pub fn counter_value(runtime: Runtime, address: String) -> Result(Int, Nil) {
  read(runtime.cell, Error(Nil), runtime_core.counter_value(_, address))
}

@target(javascript)
/// Apply a signed update to the PN-counter at `address` optimistically. A
/// negative amount decrements it.
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
/// The optimistic value of the PN-counter. The result is `Error(Nil)` when the
/// address does not exist, and when it does not name a PN-counter channel.
pub fn pn_counter_value(runtime: Runtime, address: String) -> Result(Int, Nil) {
  read(runtime.cell, Error(Nil), runtime_core.pn_counter_value(_, address))
}

@target(javascript)
/// Propose `value` for `key` in the PactMap at `address`. This write is a
/// consensus write, and it is not optimistic. The value takes effect only after
/// the `Set` operation sequences, and after the `Accept` operation that follows
/// it settles the quorum.
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
/// Propose a delete for `key` in the PactMap at `address`. A delete writes a
/// tombstone.
pub fn pact_map_delete(runtime: Runtime, address: String, key: String) -> Nil {
  edit(runtime.cell, fn(core) {
    runtime_core.pact_map_delete(core, address, key)
  })
}

@target(javascript)
/// The accepted value of the PactMap for `key`. The result is `Error(Nil)` when the
/// value is pending, when the key is absent, and when the address does not name
/// a PactMap channel.
pub fn pact_map_get(
  runtime: Runtime,
  address: String,
  key: String,
) -> Result(Json, Nil) {
  read(runtime.cell, Error(Nil), runtime_core.pact_map_get(_, address, key))
}

@target(javascript)
/// Every key with an accepted pact or a pending pact, in the PactMap at
/// `address`.
pub fn pact_map_keys(runtime: Runtime, address: String) -> List(String) {
  read(runtime.cell, [], runtime_core.pact_map_keys(_, address))
}

@target(javascript)
/// Whether `key` has a pending value, which a client proposed and no room has
/// accepted yet.
pub fn pact_map_is_pending(
  runtime: Runtime,
  address: String,
  key: String,
) -> Bool {
  read(runtime.cell, False, runtime_core.pact_map_is_pending(_, address, key))
}

@target(javascript)
/// The pending proposal for `key`, which is the value with the signoff list that
/// it waits on. The result is `Error(Nil)` when nothing is pending.
pub fn pact_map_pending(
  runtime: Runtime,
  address: String,
  key: String,
) -> Result(pact_map_kernel.Pending, Nil) {
  read(runtime.cell, Error(Nil), runtime_core.pact_map_pending(_, address, key))
}

@target(javascript)
/// The accepted entry for `key`, which is the value with its sequence number.
/// The result is `Error(Nil)` when the key has no accepted value.
pub fn pact_map_get_with_details(
  runtime: Runtime,
  address: String,
  key: String,
) -> Result(pact_map_kernel.Accepted, Nil) {
  read(runtime.cell, Error(Nil), runtime_core.pact_map_get_with_details(
    _,
    address,
    key,
  ))
}

@target(javascript)
/// Append `value` to the ordered collection at `address`. An attached channel
/// is not optimistic, and the value takes effect when the operation sequences.
/// A detached channel adds the value immediately.
pub fn ordered_add(runtime: Runtime, address: String, value: Json) -> Nil {
  edit(runtime.cell, fn(core) { runtime_core.ordered_add(core, address, value) })
}

@target(javascript)
/// Acquire the head of the ordered collection at `address`, and return the new
/// acquire id for a later `ordered_complete` or `ordered_release` call. The
/// acquired item arrives in the `Acquired` event, because the queue is not
/// optimistic.
pub fn ordered_acquire(runtime: Runtime, address: String) -> String {
  let acquire_id = id.uuid_v4()
  edit(runtime.cell, fn(core) {
    runtime_core.ordered_acquire(core, address, acquire_id)
  })
  acquire_id
}

@target(javascript)
/// The same as `ordered_acquire`, and the function also reports the consensus
/// outcome of the acquire.
///
/// `on_outcome` runs exactly one time. It gives `AcquiredItem` when this client
/// won the head. It gives `QueueEmpty` when the queue became empty before the
/// operation sequenced. An acquire that loses emits no event, so `QueueEmpty`
/// is the only signal that a loser receives. It gives `Aborted` when the
/// document closes while the acquire is still in flight. A detached channel
/// resolves immediately.
pub fn ordered_acquire_with_outcome(
  runtime: Runtime,
  address: String,
  on_outcome: fn(ordered_collection_kernel.AcquireOutcome) -> Nil,
) -> String {
  let acquire_id = id.uuid_v4()
  let state = cell_get(runtime.cell)
  case state.phase {
    Ready(core, resubmit_at) ->
      case runtime_core.ordered_acquire_submit(core, address, acquire_id) {
        // The core refused the acquire, for example because the address
        // names another kernel. The runtime resolves the waiter at once and
        // changes nothing, because a client library must not panic.
        Error(_) -> {
          on_outcome(ordered_collection_kernel.Aborted)
          acquire_id
        }
        Ok(#(core, events, outbound, immediate_outcome)) -> {
          let state =
            register_acquire_waiter(
              state,
              address,
              acquire_id,
              on_outcome,
              immediate_outcome,
            )
          cell_set(
            runtime.cell,
            State(..state, phase: Ready(core, resubmit_at)),
          )
          case resubmit_at {
            None -> send_outbound(state.channel, core.client_id, outbound)
            Some(_) -> Nil
          }
          fan_out(state.subscribers, events)
          acquire_id
        }
      }
    Reconnecting(core) ->
      case runtime_core.ordered_acquire_submit(core, address, acquire_id) {
        // The core refused the acquire, for example because the address
        // names another kernel. The runtime resolves the waiter at once and
        // changes nothing, because a client library must not panic.
        Error(_) -> {
          on_outcome(ordered_collection_kernel.Aborted)
          acquire_id
        }
        Ok(#(core, events, _outbound, immediate_outcome)) -> {
          let state =
            register_acquire_waiter(
              state,
              address,
              acquire_id,
              on_outcome,
              immediate_outcome,
            )
          cell_set(runtime.cell, State(..state, phase: Reconnecting(core)))
          fan_out(state.subscribers, events)
          acquire_id
        }
      }
    Connecting | Failed(_) -> {
      on_outcome(ordered_collection_kernel.Aborted)
      acquire_id
    }
  }
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
/// Release the held job `acquire_id` back to the ordered collection at
/// `address`.
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
/// The number of items in the queue at `address`, which are the items that no
/// client acquired yet. The result is `Error(Nil)` when the address does not exist,
/// and when it does not name an ordered-collection channel.
pub fn ordered_size(runtime: Runtime, address: String) -> Result(Int, Nil) {
  read(runtime.cell, Error(Nil), runtime_core.ordered_size(_, address))
}

@target(javascript)
/// The values in the queue at `address`, which no client acquired yet, front
/// first.
pub fn ordered_queue(runtime: Runtime, address: String) -> List(Json) {
  read(runtime.cell, [], runtime_core.ordered_queue(_, address))
}

@target(javascript)
/// The jobs that clients hold at `address` now, keyed by acquire id and sorted
/// by that id.
pub fn ordered_jobs(
  runtime: Runtime,
  address: String,
) -> List(#(String, ordered_collection_kernel.JobEntry)) {
  read(runtime.cell, [], runtime_core.ordered_jobs(_, address))
}

@target(javascript)
/// Submit a json0 operation to the channel at `address`, optimistically.
pub fn submit_json_ot(
  runtime: Runtime,
  address: String,
  components: json_ot.Operation,
) -> Nil {
  edit(runtime.cell, fn(core) {
    runtime_core.submit_json_ot(core, address, components)
  })
}

@target(javascript)
/// The optimistic document of the json0 channel. The result is `Error(Nil)` when the
/// address does not exist, and when it does not name a json0 channel.
pub fn json_ot_view(
  runtime: Runtime,
  address: String,
) -> Result(json_ot.JsonValue, Nil) {
  read(runtime.cell, Error(Nil), runtime_core.json_ot_view(_, address))
}

@target(javascript)
/// Submit a rich-text delta to the channel at `address`, optimistically.
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
/// The optimistic document of the rich-text channel. The result is `Error(Nil)` when
/// the address does not exist, and when it does not name a rich-text
/// channel.
pub fn rich_text_view(
  runtime: Runtime,
  address: String,
) -> Result(rich_text.Document, Nil) {
  read(runtime.cell, Error(Nil), runtime_core.rich_text_view(_, address))
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
    runtime_core.or_map_set(
      core,
      address,
      key,
      value,
      transport_js.now_milliseconds(),
    )
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
) -> Result(OrMapValue, Nil) {
  read(runtime.cell, Error(Nil), runtime_core.or_map_value(_, address, key))
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
/// valid index changes nothing. The result is `Ok(Nil)`, and the runtime sends
/// no operation. See the module docs of `text_kernel`.
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
/// Delete the graphemes in `[start, end)`. An empty range with valid bounds
/// changes nothing.
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
/// that you replace with `""` changes nothing.
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
/// Insert `value` at the end of the text. An empty `value` changes nothing.
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
/// The current visible optimistic string of the text channel. The result is
/// `""` when the address does not exist, and when it does not name a text
/// channel.
pub fn text_value(runtime: Runtime, address: String) -> String {
  read(runtime.cell, "", runtime_core.text_value(_, address))
}

@target(javascript)
/// The current optimistic grapheme count of the text channel. The result is `0`
/// when the address does not exist, and when it does not name a text
/// channel.
pub fn text_length(runtime: Runtime, address: String) -> Int {
  read(runtime.cell, 0, runtime_core.text_length(_, address))
}

@target(javascript)
/// The graphemes in `[start, end)` of the optimistic string of the text
/// channel.
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
/// Create a stable anchor at the gap at `index`. `bias` selects the adjacent
/// grapheme that the anchor binds to. `Before` binds it to the grapheme after
/// the gap, and `After` binds it to the grapheme before the gap.
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
/// An anchor at the start of the text. It always resolves to 0. The function is
/// pure. It needs no `Runtime` value and no address, because the anchor carries
/// no document state.
pub fn text_start_anchor() -> text_kernel.TextAnchor {
  runtime_core.text_start_anchor()
}

@target(javascript)
/// An anchor at the end of the text. It always resolves to the current grapheme
/// count, and it moves as the text becomes longer. The function is pure, the
/// same as `text_start_anchor`.
pub fn text_end_anchor() -> text_kernel.TextAnchor {
  runtime_core.text_end_anchor()
}

@target(javascript)
/// Encode an anchor as a self-describing JSON value, for example to send it
/// through presence for a shared cursor.
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
) -> Result(Json, Nil) {
  read(runtime.cell, Error(Nil), runtime_core.directory_get(
    _,
    address,
    path,
    key,
  ))
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
) -> Result(Json, Nil) {
  read(runtime.cell, Error(Nil), runtime_core.register_read(
    _,
    address,
    key,
    policy,
  ))
}

@target(javascript)
pub fn register_versions(
  runtime: Runtime,
  address: String,
  key: String,
) -> Result(List(Json), Nil) {
  read(runtime.cell, Error(Nil), runtime_core.register_versions(_, address, key))
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
) -> Result(Json, Nil) {
  read(runtime.cell, Error(Nil), runtime_core.get_claim(_, address, key))
}

@target(javascript)
pub fn has_claim(runtime: Runtime, address: String, key: String) -> Bool {
  read(runtime.cell, False, runtime_core.has_claim(_, address, key))
}

@target(javascript)
pub fn claim_once(
  runtime: Runtime,
  address: String,
  key: String,
  value: Json,
) -> ClaimSubmitReply {
  claim_submit(runtime.cell, address, key, fn(core) {
    runtime_core.claim_once(core, address, key, value)
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
        // The core refused the volunteer, for example because the address
        // names another kernel. The runtime reports no assignment and changes
        // nothing.
        Error(_) -> task_manager_kernel.DisconnectedBeforeAssignment
        Ok(#(core, events, outbound, outcome)) -> {
          cell_set(
            runtime.cell,
            State(..state, phase: Ready(core, resubmit_at)),
          )
          case resubmit_at {
            None -> send_outbound(state.channel, core.client_id, outbound)
            Some(_) -> Nil
          }
          fan_out(state.subscribers, events)
          outcome
        }
      }
    Reconnecting(core) ->
      case runtime_core.task_manager_volunteer(core, address, task_id) {
        // The core refused the volunteer, for example because the address
        // names another kernel. The runtime reports no assignment and changes
        // nothing.
        Error(_) -> task_manager_kernel.DisconnectedBeforeAssignment
        Ok(#(core, events, _outbound, outcome)) -> {
          cell_set(runtime.cell, State(..state, phase: Reconnecting(core)))
          fan_out(state.subscribers, events)
          outcome
        }
      }
    Connecting | Failed(_) -> task_manager_kernel.DisconnectedBeforeAssignment
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
          Error("complete_task failed: " <> string.inspect(core_error))
        Ok(#(core, events, outbound)) -> {
          cell_set(
            runtime.cell,
            State(..state, phase: Ready(core, resubmit_at)),
          )
          case resubmit_at {
            None -> send_outbound(state.channel, core.client_id, outbound)
            Some(_) -> Nil
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
          Error("complete_task failed: " <> string.inspect(core_error))
        Ok(#(core, events, _outbound)) -> {
          cell_set(runtime.cell, State(..state, phase: Reconnecting(core)))
          fan_out(state.subscribers, events)
          Ok(Nil)
        }
      }
    Connecting | Failed(_) ->
      Error("complete_task requires a ready document connection")
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
/// Create a new detached map channel. It is local only, until a caller stores
/// its handle into an attached map. The function returns the address that the
/// runtime generated.
pub fn create_map(runtime: Runtime) -> Result(String, String) {
  create_channel(runtime, channel.InitMap, "create_map")
}

@target(javascript)
/// Create a new detached counter channel. The lifecycle is the same as for
/// `create_map`.
pub fn create_counter(runtime: Runtime) -> Result(String, String) {
  create_channel(runtime, channel.InitCounter, "create_counter")
}

@target(javascript)
/// Create a new detached PN-counter channel. The lifecycle is the same as for
/// `create_map`.
pub fn create_pn_counter(runtime: Runtime) -> Result(String, String) {
  create_channel(runtime, channel.InitPnCounter, "create_pn_counter")
}

@target(javascript)
/// Create a new detached PactMap channel, which is a consensus map. The
/// lifecycle is the same as for `create_map`.
pub fn create_pact_map(runtime: Runtime) -> Result(String, String) {
  create_channel(runtime, channel.InitPactMap, "create_pact_map")
}

@target(javascript)
/// Create a new detached ConsensusOrderedCollection channel. The lifecycle is
/// the same as for `create_map`.
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
/// Create a new detached text channel. The lifecycle is the same as for
/// `create_map`.
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
/// Create a new detached json0 channel. The lifecycle is the same as for
/// `create_map`.
pub fn create_json_ot(runtime: Runtime) -> Result(String, String) {
  create_channel(runtime, channel.InitJsonOt, "create_json_ot")
}

@target(javascript)
/// Create a new detached rich-text channel. The lifecycle is the same as for
/// `create_map`.
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
        // The core refused the claim for a reason that is not a channel type
        // mismatch. The runtime reports the same refusal and changes nothing.
        Error(_) -> WrongChannelType
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
        // The core refused the claim for a reason that is not a channel type
        // mismatch. The runtime reports the same refusal and changes nothing.
        Error(_) -> WrongChannelType
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
    Connecting | Failed(_) -> WrongChannelType
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
      let address = id.uuid_v4()
      let core = runtime_core.create_detached(core, address, init)
      cell_set(runtime.cell, State(..state, phase: Ready(core, resubmit_at)))
      Ok(address)
    }
    Reconnecting(core) -> {
      let address = id.uuid_v4()
      let core = runtime_core.create_detached(core, address, init)
      cell_set(runtime.cell, State(..state, phase: Reconnecting(core)))
      Ok(address)
    }
    Connecting | Failed(_) ->
      Error(verb <> " requires a ready document connection")
  }
}

@target(javascript)
/// Whether a channel exists at `address`, attached or detached. A caller can
/// retry after an error, because an attach from another client can still be in
/// flight.
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
    Connecting | Failed(_) ->
      Error("resolve_sequence requires a ready document connection")
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
    Connecting | Failed(_) ->
      Error("resolve_text requires a ready document connection")
  }
}

@target(javascript)
/// Register a callback that the runtime calls for every local event and remote
/// event on the channel at `address`.
pub fn subscribe(
  runtime: Runtime,
  address: String,
  handler: fn(ChannelEvent) -> Nil,
) -> SubscriptionToken {
  let state = cell_get(runtime.cell)
  let token_id = id.uuid_v4()
  cell_set(
    runtime.cell,
    State(..state, subscribers: [
      Subscriber(id: token_id, address: address, handler: handler),
      ..state.subscribers
    ]),
  )
  SubscriptionToken(runtime: runtime, id: token_id)
}

@target(javascript)
/// Remove a channel subscription. A second call has no more effect.
pub fn unsubscribe(token: SubscriptionToken) -> Nil {
  let runtime = token.runtime
  let state = cell_get(runtime.cell)
  cell_set(
    runtime.cell,
    State(
      ..state,
      subscribers: list.filter(state.subscribers, fn(subscriber) {
        subscriber.id != token.id
      }),
    ),
  )
}

@target(javascript)
/// The client id that the server assigned to this connection. The result is
/// `None` before the first handshake completes.
///
/// A reconnect does not keep the value. There is always *a* current id, and
/// `adopt_reconnect` replaces it with the id that the new handshake assigns.
/// That id can differ from the previous one. A caller that holds the id across
/// a disconnect must read it again. It must not use a cached value.
pub fn client_id(runtime: Runtime) -> Option(String) {
  client_id_of(cell_get(runtime.cell))
}

@target(javascript)
fn client_id_of(state: State) -> Option(String) {
  case state.phase {
    Ready(core, _) -> Some(core.client_id)
    Reconnecting(core) -> Some(core.client_id)
    Connecting | Failed(_) -> None
  }
}

@target(javascript)
/// Broadcast an ephemeral ripple to this document, with a `type` field and any
/// JSON `content`. A ripple does not sequence and no server stores it. It
/// expects no reply, and it has no ack, no resubmit, and no catch-up. The
/// function does nothing until the server assigns a client id, which is until
/// the first handshake completes.
pub fn send_ripple(
  runtime: Runtime,
  ripple_type: String,
  content: Json,
) -> Nil {
  let state = cell_get(runtime.cell)
  case state.channel, client_id_of(state) {
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
/// Register a callback that the runtime calls for every inbound ephemeral
/// ripple on the document. The content stays a `Dynamic` value, for the caller
/// to decode.
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
/// Push a command on the presence lane, which is `joinPresence`,
/// `updatePresence`, or `leavePresence`. The function does nothing before the
/// channel exists.
///
/// Unlike `send_ripple`, this function does not wait for a client id. A
/// presence payload carries no identity at all, because the server derives the
/// key and the session from the authenticated connection.
pub fn send_presence(runtime: Runtime, event: String, payload: Json) -> Nil {
  case cell_get(runtime.cell).channel {
    Some(channel) -> push_json(channel, event, payload)
    None -> Nil
  }
}

@target(javascript)
/// Register a callback for every frame on the presence lane, both a data frame
/// and a lifecycle frame. Each data-frame payload stays the raw event JSON, as
/// a `String`, for the typed driver to decode with its own decoder.
pub fn subscribe_presence(
  runtime: Runtime,
  handler: fn(PresenceFrame) -> Nil,
) -> Nil {
  let state = cell_get(runtime.cell)
  cell_set(
    runtime.cell,
    State(..state, presence_subscribers: [handler, ..state.presence_subscribers]),
  )
}

@target(javascript)
/// Whether the handshake of the *current* connection announced `presence_v1`.
/// The result is `False` before the first handshake settles.
pub fn supports_presence(runtime: Runtime) -> Bool {
  socket.supports_feature(
    cell_get(runtime.cell).supported_features,
    socket.feature_presence_v1,
  )
}

@target(javascript)
/// The authenticated user id that this runtime connected with. Server presence
/// derives its presence key from the same value. Ripple mode reads that value
/// here, so the two implementations use the same key for their rosters.
pub fn user_id(runtime: Runtime) -> String {
  cell_get(runtime.cell).connect_message.client.user.id
}

@target(javascript)
/// A hook that injects a fault. It closes the socket, so that the runtime runs
/// its reconnect and reconcile path.
pub fn force_reconnect(runtime: Runtime) -> Nil {
  let state = cell_get(runtime.cell)
  case state.phase, state.channel {
    Ready(core, _), Some(channel) -> {
      cell_set(runtime.cell, State(..state, phase: Reconnecting(core)))
      notify_session_lost(runtime.cell, state.phase)
      channel.drop()
    }
    Ready(_, _), None | Connecting, _ | Reconnecting(_), _ | Failed(_), _ -> Nil
  }
}

@target(javascript)
/// Go offline and stay offline. The function holds the connection closed, and
/// the document continues to accept local edits. `go_online` opens the
/// connection again.
///
/// The phase stays at `Reconnecting`, which is a state that the runtime already
/// serves in full. A read and an edit both work, the edits collect as pending
/// entries, and the rejoin handshake carries `last_seen` and sends them. This
/// function adds no state machine. The one new behaviour is that the socket
/// does not open again by itself.
///
/// An offline toggle needs this function, and neither of the two similar hooks
/// gives it. `force_reconnect` goes away and comes back with no interval
/// between. `close` is terminal, and to reconnect after it means a new runtime,
/// whose empty core holds none of the edits from that interval.
pub fn go_offline(runtime: Runtime) -> Nil {
  let state = cell_get(runtime.cell)
  case state.phase, state.channel {
    Ready(core, _), Some(channel) -> {
      cell_set(runtime.cell, State(..state, phase: Reconnecting(core)))
      notify_session_lost(runtime.cell, state.phase)
      channel.hold()
    }
    Ready(_, _), None | Connecting, _ | Reconnecting(_), _ | Failed(_), _ -> Nil
  }
}

@target(javascript)
/// Return from `go_offline`. The function does nothing unless the connection is
/// held, so an interface can bind it to a toggle and does not have to track the
/// phase.
pub fn go_online(runtime: Runtime) -> Nil {
  let state = cell_get(runtime.cell)
  case state.phase, state.channel {
    Reconnecting(_), Some(channel) -> channel.resume()
    Reconnecting(_), None | Connecting, _ | Ready(_, _), _ | Failed(_), _ -> Nil
  }
}

@target(javascript)
pub fn close(runtime: Runtime) -> Nil {
  let state = abort_outcome_waiters(cell_get(runtime.cell))
  cell_set(runtime.cell, State(..state, phase: Failed("runtime closed")))
  notify_session_lost(runtime.cell, state.phase)
  case state.channel {
    Some(channel) -> channel.close()
    None -> Nil
  }
}

@target(javascript)
/// Whether the document is caught up, which is true when the server acked every
/// local edit. The confirmed state is then complete and stable.
pub fn is_synced(runtime: Runtime) -> Bool {
  case cell_get(runtime.cell).phase {
    Ready(core, None) -> runtime_core.is_synced(core)
    Ready(_, Some(_)) | Connecting | Reconnecting(_) | Failed(_) -> False
  }
}

@target(javascript)
/// Take a snapshot of the connection state and the sequencing state, for
/// diagnostics. The function does not change the runtime, and a debug interface
/// can call it repeatedly.
pub fn diagnostics(runtime: Runtime) -> Diagnostics {
  let state = cell_get(runtime.cell)
  case state.phase {
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
        operations_since_summary: 0,
        summary_pending: False,
      )
    Reconnecting(core) ->
      diagnostics_from_core(core, "reconnecting", None, False, state)
    Ready(core, Some(checkpoint)) ->
      diagnostics_from_core(core, "catching-up", Some(checkpoint), False, state)
    Ready(core, None) ->
      diagnostics_from_core(
        core,
        "ready",
        None,
        runtime_core.is_synced(core),
        state,
      )
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
        operations_since_summary: 0,
        summary_pending: False,
      )
  }
}

@target(javascript)
fn diagnostics_from_core(
  core: runtime_core.Core,
  phase: String,
  checkpoint: Option(Int),
  synced: Bool,
  state: State,
) -> Diagnostics {
  Diagnostics(
    phase: phase,
    client_id: Some(core.client_id),
    last_seen_sequence_number: Some(core.last_seen_sequence_number),
    next_client_sequence_number: Some(core.next_client_sequence_number),
    in_flight_count: list.length(core.in_flight),
    buffered_out_of_order_count: list.length(core.out_of_order),
    resubmit_checkpoint: checkpoint,
    synced: synced,
    operations_since_summary: runtime_core.operations_since_summary(core),
    summary_pending: state.summary_armed,
  )
}

@target(javascript)
/// Replace the scheduler of the runtime. This is a test seam for the in-memory
/// hub, which binds the delayed work to its logical clock. A production runtime
/// keeps the real `setTimeout` function that it started with. You can call this
/// function at any time before the first sequenced operation, which is the
/// earliest moment at which the runtime schedules anything.
pub fn set_scheduler(
  runtime: Runtime,
  scheduler: transport_js.Scheduler,
) -> Nil {
  cell_set(runtime.cell, State(..cell_get(runtime.cell), scheduler: scheduler))
}

@target(javascript)
/// Install the automatic summarization policy. A value of `None` clears it.
pub fn auto_summarize(
  runtime: Runtime,
  policy: Option(summary_policy.Policy),
) -> Nil {
  // Arming waits for the next sequenced operation rather than happening here:
  // the operation path is the one place that knows the phase has settled, and a
  // document already past the threshold is the common case on a busy room.
  cell_set(runtime.cell, State(..cell_get(runtime.cell), auto_summary: policy))
}

@target(javascript)
/// How far the document moved past the newest checkpoint that this client knows
/// about. The result is zero before the first handshake.
pub fn operations_since_summary(runtime: Runtime) -> Int {
  case cell_get(runtime.cell).phase {
    Ready(core, _) | Reconnecting(core) ->
      runtime_core.operations_since_summary(core)
    Connecting | Failed(_) -> 0
  }
}

@target(javascript)
/// Schedule an attempt to summarize, if the policy asks for one and no attempt
/// is pending.
///
/// The delay keeps the cost of a room low. Every client crosses the threshold
/// on the same operation. Each client then waits for a different interval,
/// which comes from its id. The first summary that sequences advances
/// `last_summary_sequence_number` on every client, and the rest of the room
/// checks again on its wake-up and stops. A lost race costs one unnecessary
/// upload, and nothing more.
fn arm_summary(cell: Cell(State), core: runtime_core.Core) -> Nil {
  let state = cell_get(cell)
  case state.auto_summary, state.summary_armed {
    Some(policy), False ->
      case runtime_core.wants_summary(core, policy) {
        False -> Nil
        True -> {
          cell_set(cell, State(..state, summary_armed: True))
          let _ =
            state.scheduler.schedule(
              fn() { attempt_summary(cell) },
              runtime_core.summary_jitter_milliseconds(core, policy),
            )
          Nil
        }
      }
    _, _ -> Nil
  }
}

@target(javascript)
/// The wake-up of the policy. The function makes the decision again against the
/// core as it is now, because a summary from a peer that arrives in the delay
/// window is the condition that this wake-up looks for.
fn attempt_summary(cell: Cell(State)) -> Nil {
  let state = cell_get(cell)
  cell_set(cell, State(..state, summary_armed: False))
  case state.phase, state.auto_summary {
    Ready(core, None), Some(policy) ->
      case runtime_core.wants_summary(core, policy) {
        False -> Nil
        True -> {
          // A summarize operation carries no ack, so there is nothing to
          // reconcile on failure: the checkpoint did not move, and the next
          // sequenced operation arms another attempt.
          let _ = summarize(Runtime(cell: cell))
          Nil
        }
      }
    Ready(_, None), None
    | Ready(_, Some(_)), _
    | Connecting, _
    | Reconnecting(_), _
    | Failed(_), _
    -> Nil
  }
}

@target(javascript)
/// Summarize the current confirmed state of the document to the storage of
/// floodgate. A later client can then start from that snapshot, and it does not
/// replay the full operation history. The promise resolves with the summary
/// handle, which is a git tree SHA. The connection must be synchronized, and
/// the token must carry the `summary:write` scope.
///
/// The upload is asynchronous, so the promise settles after the storage holds
/// the blob and the runtime pushes the summarize operation. The sequence number
/// of that operation comes from the live core at push time, and not at the
/// start of the upload, so a concurrent local edit cannot collide with it.
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
                sequence_number: core.last_seen_sequence_number,
                members: runtime_core.summary_members(core),
                channels: runtime_core.summary_channels(core),
              )
              |> promise.map(fn(result) {
                case result {
                  Error(error) -> Error(git_storage.error_to_string(error))
                  Ok(tree_sha) -> finish_summarize(cell, tree_sha)
                }
              })
          }
      }
    Ready(_, None), None
    | Ready(_, Some(_)), _
    | Connecting, _
    | Reconnecting(_), _
    | Failed(_), _
    ->
      promise.resolve(Error(
        "summarize is only available once the connection is fully synced",
      ))
  }
}

@target(javascript)
/// List the stored summary versions of the document, newest first. This is the
/// client half of the `getVersions` function of Fluid. The token must carry the
/// `doc:read` scope.
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
      |> promise.map(result.map_error(_, git_storage.error_to_string))
  }
}

@target(javascript)
/// Read the snapshot that a summary version captured, by the handle of that
/// version. `get_versions` and the resolution of `summarize` both give a
/// handle. The function does not change the live document. It reads the stored
/// blob at one point in time.
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
      |> promise.map(result.map_error(_, git_storage.error_to_string))
  }
}

@target(javascript)
/// Stamp the summarize operation that references the uploaded snapshot tree,
/// and push it. The function reads the live state again, so it builds the
/// operation from the current core. The client sequence number of that
/// operation thus stays above the number of every edit that arrived during the
/// asynchronous upload.
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
        socket.encode_submit_operation(core.client_id, [[outbound]]),
      )
      cell_set(cell, State(..state, phase: Ready(core, None)))
      Ok(tree_sha)
    }
    Ready(_, None), None
    | Ready(_, Some(_)), _
    | Connecting, _
    | Reconnecting(_), _
    | Failed(_), _
    -> Error("connection changed during summarize; retry")
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Transport callbacks
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// A join succeeded, so send `connect_document`. On the first join that message
/// starts the handshake. On a rejoin that Phoenix performed by itself, it
/// starts the handshake again, with the last sequence number that this client
/// saw, so the server pushes the delta only.
fn on_join(cell: Cell(State)) -> Nil {
  let state = cell_get(cell)
  case state.channel {
    None -> Nil
    Some(channel) ->
      case state.phase {
        Connecting -> push_connect(channel, state.connect_message, None)
        Reconnecting(core) ->
          push_connect(
            channel,
            state.connect_message,
            Some(core.last_seen_sequence_number),
          )
        Ready(core, _) -> {
          // Rejoin without an intervening close event; treat as reconnect.
          cell_set(cell, State(..state, phase: Reconnecting(core)))
          notify_session_lost(cell, state.phase)
          push_connect(
            channel,
            state.connect_message,
            Some(core.last_seen_sequence_number),
          )
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
    Ready(core, _) | Reconnecting(core) -> {
      cell_set(cell, State(..state, phase: Reconnecting(core)))
      notify_session_lost(cell, state.phase)
    }
    // Not yet connected: Phoenix will retry the join, which re-fires on_join.
    Connecting | Failed(_) -> Nil
  }
}

@target(javascript)
fn on_event(cell: Cell(State), event: String, payload: String) -> Nil {
  case event {
    "connect_document_success" -> on_connect_success(cell, payload)
    "connect_document_error" -> on_connect_error(cell, payload)
    "op" -> on_operation(cell, payload)
    "nack" -> on_nack(cell, payload)
    "signal" -> on_ripple(cell, payload)
    "presence_state" -> notify_presence(cell, PresenceState(payload))
    "presence_diff" -> notify_presence(cell, PresenceDiff(payload))
    "presence_error" -> notify_presence(cell, PresenceError(payload))
    _ -> Nil
  }
}

@target(javascript)
fn on_connect_success(cell: Cell(State), payload: String) -> Nil {
  case json.parse(payload, socket.connected_message_decoder()) {
    Error(_) -> fail(cell, "malformed connect_document_success payload")
    Ok(connected) -> {
      // Record what this connection negotiated before anything acts on it, and
      // on both paths — a reconnect may land on a different node with a
      // different answer.
      cell_set(
        cell,
        State(
          ..cell_get(cell),
          supported_features: connected.supported_features,
        ),
      )
      let state = cell_get(cell)
      case state.phase {
        Connecting ->
          // A never-summarized document bootstraps synchronously from
          // `initialMessages`. A summarized document first fetches its summary
          // blob over HTTP (async), then bootstraps seeded from that state.
          case connected.summary_context {
            None -> finish_bootstrap(cell, connected, None)
            Some(context) ->
              load_summary_then_bootstrap(cell, state, connected, context)
          }
        Reconnecting(core) -> {
          let core = runtime_core.adopt_reconnect(core, connected)
          let checkpoint =
            option.unwrap(
              connected.checkpoint_sequence_number,
              core.last_seen_sequence_number,
            )
          // Ask for the gap. Nothing else will: no server pushes it unprompted,
          // and the reactive `requestOps` in `on_operation` needs an operation
          // to react to. See `runtime_core.catch_up_from`.
          maybe_request_operations(
            state.channel,
            runtime_core.catch_up_from(core, checkpoint),
          )
          settle_reconnect(cell, core, checkpoint)
          // Presence is unsequenced, so it does not wait for the operation
          // catch-up `settle_reconnect` may still be pending — rejoining now is
          // both correct and the fastest way back to a roster.
          notify_presence_session(cell, core)
        }
        Ready(_, _) | Failed(_) -> Nil
      }
    }
  }
}

@target(javascript)
/// Fetch the summary blob that `context` references, and then bootstrap the core
/// from it. The runtime drops a real-time operation that arrives during the
/// asynchronous fetch, while the phase is still `Connecting`. The gap that those
/// drops create repairs itself: the first operation after the bootstrap that is
/// not contiguous starts a `requestOps` catch-up.
fn load_summary_then_bootstrap(
  cell: Cell(State),
  state: State,
  connected: ConnectedMessage,
  context: SummaryContext,
) -> Nil {
  case state.connect_message.token {
    None -> fail(cell, "loading a summarized document requires an auth token")
    Some(token) -> {
      let _ =
        git_storage.fetch_summary(
          base_url: state.http_base_url,
          tenant: state.connect_message.tenant_id,
          token: token,
          handle: context.handle,
        )
        |> promise.map(fn(result) {
          case result {
            Error(error) ->
              fail(
                cell,
                "summary load failed: " <> git_storage.error_to_string(error),
              )
            Ok(blob) ->
              // `context` locates the blob; the blob says what it holds and when
              // it was captured. See `runtime_core.summary_from_blob` for why
              // the context's sequence number is deliberately not the load
              // point.
              finish_bootstrap(
                cell,
                connected,
                Some(runtime_core.summary_from_blob(blob)),
              )
          }
        })
      Nil
    }
  }
}

@target(javascript)
/// Bootstrap the core, from a summary if one exists, and then run `on_ready`.
fn finish_bootstrap(
  cell: Cell(State),
  connected: ConnectedMessage,
  summary: Option(runtime_core.Summary),
) -> Nil {
  case runtime_core.bootstrap(connected, summary: summary) {
    Ok(bootstrapped) -> continue_bootstrap(cell, bootstrapped)
    Error(error) -> fail(cell, "bootstrap failed: " <> string.inspect(error))
  }
}

@target(javascript)
/// Complete one bootstrap step. The function makes the document ready, or it
/// reads the missing prefix of the history from the deltas REST endpoint and
/// continues. That read is asynchronous, and it can need several rounds. A
/// bootstrap must not complete on a history with a gap, so every failure here
/// moves the cell to `Failed`.
fn continue_bootstrap(
  cell: Cell(State),
  bootstrapped: runtime_core.Bootstrapped,
) -> Nil {
  case bootstrapped {
    runtime_core.Complete(core) -> {
      cell_set(cell, State(..cell_get(cell), phase: Ready(core, None)))
      fire_ready(cell, Ok(Nil))
      // The one completion point shared by the synchronous and
      // summary-fetching bootstrap paths.
      notify_presence_session(cell, core)
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
                Error(error) ->
                  fail(
                    cell,
                    "history catch-up failed: "
                      <> git_storage.error_to_string(error),
                  )
                Ok(deltas) ->
                  case
                    runtime_core.resume_bootstrap(
                      core,
                      checkpoint: checkpoint,
                      deltas: deltas,
                    )
                  {
                    Ok(next) -> continue_bootstrap(cell, next)
                    Error(error) ->
                      fail(cell, "bootstrap failed: " <> string.inspect(error))
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
fn on_connect_error(cell: Cell(State), payload: String) -> Nil {
  case json.parse(payload, socket.connect_error_decoder()) {
    Ok(error) -> fail(cell, error.message)
    Error(_) -> fail(cell, "connect_document_error")
  }
}

@target(javascript)
fn on_operation(cell: Cell(State), payload: String) -> Nil {
  let state = cell_get(cell)
  case state.phase {
    Ready(core, resubmit_at) ->
      case json.parse(payload, socket.operation_message_decoder()) {
        Error(_) -> fail(cell, "malformed op payload")
        Ok(message) ->
          case apply_operations(core, message.ops) {
            Ok(#(core, events, resolutions, request_from, released)) -> {
              let state = resolve_claim_waiters(state, resolutions)
              let state = resolve_acquire_waiters(state, resolutions)
              // Commit the new core before fan-out (see fan_out's contract).
              case resubmit_at {
                Some(checkpoint) -> {
                  cell_set(cell, state)
                  settle_reconnect(cell, core, checkpoint)
                }
                None -> cell_set(cell, State(..state, phase: Ready(core, None)))
              }
              fan_out(state.subscribers, events)
              maybe_request_operations(state.channel, request_from)
              case resubmit_at {
                // Mid-reconnect these are already in the in-flight queue, and
                // `settle_reconnect` restamps that whole queue with fresh
                // client sequence numbers and sends it. Sending them here as
                // well puts two copies of each on the wire; the server
                // sequences both and the stale ack fails the FIFO match.
                Some(_) -> Nil
                None -> send_outbound(state.channel, core.client_id, released)
              }
              case resubmit_at {
                Some(_) -> Nil
                None -> arm_summary(cell, core)
              }
            }
            Error(core_error) ->
              fail(
                cell,
                "sequenced op processing failed: " <> string.inspect(core_error),
              )
          }
      }
    // Operations before a connected session (or while reconnecting) carry no
    // state we can trust; ignore them.
    Connecting | Reconnecting(_) | Failed(_) -> Nil
  }
}

@target(javascript)
fn on_nack(cell: Cell(State), payload: String) -> Nil {
  case json.parse(payload, socket.nacks_decoder()) {
    Error(_) -> fail(cell, "malformed nack payload")
    Ok(nacks) ->
      case list.any(nacks, nack_is_fatal) {
        True -> fail(cell, "fatal nack from server")
        False -> {
          let state = cell_get(cell)
          case state.phase, state.channel {
            Ready(core, _), Some(channel) -> {
              cell_set(cell, State(..state, phase: Reconnecting(core)))
              notify_session_lost(cell, state.phase)
              channel.drop()
            }
            Ready(_, _), None
            | Connecting, _
            | Reconnecting(_), _
            | Failed(_), _
            -> Nil
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
  case core.last_seen_sequence_number >= checkpoint {
    True -> {
      let #(core, outbound) = runtime_core.resubmit(runtime_core.go_live(core))
      send_outbound(state.channel, core.client_id, outbound)
      cell_set(cell, State(..state, phase: Ready(core, None)))
    }
    False ->
      cell_set(cell, State(..state, phase: Ready(core, Some(checkpoint))))
  }
}

@target(javascript)
fn apply_operations(
  core: runtime_core.Core,
  operations: List(SequencedDocumentMessage),
) -> Result(
  #(
    runtime_core.Core,
    List(#(String, ChannelEvent)),
    List(#(String, Resolution)),
    Option(Int),
    List(wire.OutboundOperation),
  ),
  runtime_core.CoreError,
) {
  do_apply_operations(core, operations, [], [], None, [])
}

@target(javascript)
fn do_apply_operations(
  core: runtime_core.Core,
  operations: List(SequencedDocumentMessage),
  events: List(List(#(String, ChannelEvent))),
  resolutions: List(List(#(String, Resolution))),
  request_from: Option(Int),
  released: List(wire.OutboundOperation),
) -> Result(
  #(
    runtime_core.Core,
    List(#(String, ChannelEvent)),
    List(#(String, Resolution)),
    Option(Int),
    List(wire.OutboundOperation),
  ),
  runtime_core.CoreError,
) {
  case operations {
    [] ->
      Ok(#(
        core,
        list.reverse(events) |> list.flatten,
        list.reverse(resolutions) |> list.flatten,
        request_from,
        released,
      ))
    [operation, ..rest] ->
      case runtime_core.handle_sequenced(core, operation) {
        Ok(#(core, ingested)) ->
          do_apply_operations(
            core,
            rest,
            [ingested.events, ..events],
            [ingested.resolutions, ..resolutions],
            option.or(request_from, ingested.request_operations_from),
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
        AcquireResolved(_, _) -> acc
      }
    })
  State(..state, claim_waiters: claim_waiters)
}

@target(javascript)
fn abort_outcome_waiters(state: State) -> State {
  dict.values(state.claim_waiters)
  |> list.each(fn(resolve_outcome) { resolve_outcome(claims_kernel.Aborted) })
  dict.values(state.acquire_waiters)
  |> list.each(fn(resolve_outcome) {
    resolve_outcome(ordered_collection_kernel.Aborted)
  })
  State(..state, claim_waiters: dict.new(), acquire_waiters: dict.new())
}

@target(javascript)
fn register_acquire_waiter(
  state: State,
  address: String,
  acquire_id: String,
  resolve_outcome: fn(ordered_collection_kernel.AcquireOutcome) -> Nil,
  immediate_outcome: Option(ordered_collection_kernel.AcquireOutcome),
) -> State {
  case immediate_outcome {
    Some(outcome) -> {
      resolve_outcome(outcome)
      state
    }
    None ->
      State(
        ..state,
        acquire_waiters: dict.insert(
          state.acquire_waiters,
          #(address, acquire_id),
          resolve_outcome,
        ),
      )
  }
}

@target(javascript)
fn resolve_acquire_waiters(
  state: State,
  resolutions: List(#(String, Resolution)),
) -> State {
  let acquire_waiters =
    list.fold(resolutions, state.acquire_waiters, fn(acc, item) {
      let #(address, resolution) = item
      case resolution {
        AcquireResolved(acquire_id, outcome) ->
          case dict.get(acc, #(address, acquire_id)) {
            Ok(resolve_outcome) -> {
              resolve_outcome(outcome)
              dict.delete(acc, #(address, acquire_id))
            }
            Error(_) -> acc
          }
        ClaimResolved(_, _) -> acc
      }
    })
  State(..state, acquire_waiters: acquire_waiters)
}

@target(javascript)
fn edit(
  cell: Cell(State),
  operate: fn(runtime_core.Core) ->
    Result(
      #(
        runtime_core.Core,
        List(#(String, ChannelEvent)),
        List(wire.OutboundOperation),
      ),
      runtime_core.CoreError,
    ),
) -> Nil {
  let state = cell_get(cell)
  case state.phase {
    Ready(core, resubmit_at) -> {
      case operate(core) {
        // The core refused the edit, for example because the address names
        // another kernel, or because the edit is out of bounds. The runtime
        // drops the edit and changes nothing, because a client library must
        // not panic.
        Error(_) -> Nil
        Ok(#(core, events, outbound)) -> {
          // Commit the new core before fan-out (see fan_out's contract).
          cell_set(cell, State(..state, phase: Ready(core, resubmit_at)))
          // Push immediately only when fully synced with a live channel;
          // otherwise the operation stays in-flight and `resubmit` sends it
          // once, so a reconnect can't drop or duplicate it.
          case resubmit_at {
            None -> send_outbound(state.channel, core.client_id, outbound)
            Some(_) -> Nil
          }
          fan_out(state.subscribers, events)
        }
      }
    }
    Reconnecting(core) -> {
      case operate(core) {
        // The core refused the edit, for example because the address names
        // another kernel, or because the edit is out of bounds. The runtime
        // drops the edit and changes nothing, because a client library must
        // not panic.
        Error(_) -> Nil
        Ok(#(core, events, _outbound)) -> {
          cell_set(cell, State(..state, phase: Reconnecting(core)))
          fan_out(state.subscribers, events)
        }
      }
    }
    // Edits before ready are dropped (the demo gates edits behind on_ready).
    Connecting | Failed(_) -> Nil
  }
}

@target(javascript)
fn edit_sequence_with_result(
  cell: Cell(State),
  operate: fn(runtime_core.Core) ->
    Result(
      #(
        runtime_core.Core,
        List(#(String, ChannelEvent)),
        List(wire.OutboundOperation),
      ),
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
        Error(runtime_core.SequenceOperationFailed(_, detail)) -> Error(detail)
        Error(error) -> Error(string.inspect(error))
      }
    Reconnecting(core) ->
      case operate(core) {
        Ok(#(core, events, _outbound)) -> {
          cell_set(cell, State(..state, phase: Reconnecting(core)))
          fan_out(state.subscribers, events)
          Ok(Nil)
        }
        Error(runtime_core.SequenceOperationFailed(_, detail)) -> Error(detail)
        Error(error) -> Error(string.inspect(error))
      }
    Connecting | Failed(_) ->
      Error("sequence edit before the document connection is ready")
  }
}

@target(javascript)
fn edit_text_with_result(
  cell: Cell(State),
  operate: fn(runtime_core.Core) ->
    Result(
      #(
        runtime_core.Core,
        List(#(String, ChannelEvent)),
        List(wire.OutboundOperation),
      ),
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
        Error(runtime_core.TextOperationFailed(_, detail)) -> Error(detail)
        Error(error) -> Error(string.inspect(error))
      }
    Reconnecting(core) ->
      case operate(core) {
        Ok(#(core, events, _outbound)) -> {
          cell_set(cell, State(..state, phase: Reconnecting(core)))
          fan_out(state.subscribers, events)
          Ok(Nil)
        }
        Error(runtime_core.TextOperationFailed(_, detail)) -> Error(detail)
        Error(error) -> Error(string.inspect(error))
      }
    Connecting | Failed(_) ->
      Error("text edit before the document connection is ready")
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
    Connecting | Failed(_) -> default
  }
}

@target(javascript)
fn nack_is_fatal(item: Nack) -> Bool {
  case item.content.error_type {
    nack.InvalidScopeError -> True
    nack.LimitExceededError -> True
    nack.ThrottlingError | nack.BadRequestError -> item.content.code == 413
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
fn maybe_request_operations(
  channel: Option(TransportHandle),
  request_from: Option(Int),
) -> Nil {
  case channel, request_from {
    Some(channel), Some(from) ->
      push_json(
        channel,
        "requestOps",
        socket.encode_request_operations(from: from),
      )
    _, _ -> Nil
  }
}

@target(javascript)
fn send_outbound(
  channel: Option(TransportHandle),
  client_id: String,
  outbound: List(wire.OutboundOperation),
) -> Nil {
  case channel, outbound {
    _, [] -> Nil
    Some(channel), _ ->
      list.each(
        list.sized_chunk(outbound, max_operations_per_submission),
        fn(chunk) {
          push_json(
            channel,
            "submitOp",
            socket.encode_submit_operation(client_id, [chunk]),
          )
        },
      )
    None, _ -> Nil
  }
}

@target(javascript)
fn push_json(channel: TransportHandle, event: String, payload: Json) -> Nil {
  channel.push(event, payload)
}

@target(javascript)
/// Derive the base HTTP or HTTPS URL for the git-storage calls, from the
/// Phoenix socket URL. For example,
/// `ws://localhost:4000/socket/websocket?vsn=2.0.0` gives
/// `http://localhost:4000`. A `wss` scheme gives `https`, and every other
/// scheme gives `http`.
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
/// Route each event to the subscribers that registered for the channel address
/// on that event.
///
/// The contract for a caller: write the new core into the cell before this
/// fan-out. A handler that reads the map during the event thus sees the state
/// that the runtime applied. That rule holds for a local edit, a remote
/// operation, and a reconnect.
///
/// The `subscribers` argument is one snapshot. A callback can unsubscribe
/// itself, or another callback, during the fan-out. That change affects the
/// next fan-out only.
fn fan_out(
  subscribers: List(Subscriber),
  events: List(#(String, ChannelEvent)),
) -> Nil {
  list.each(events, fn(event) {
    let #(address, event) = event
    list.each(subscribers, fn(subscriber) {
      case subscriber.address == address {
        True -> subscriber.handler(event)
        False -> Nil
      }
    })
  })
}

@target(javascript)
/// Send an inbound ephemeral `signal` broadcast to the ripple subscribers. The
/// wire event is the `"signal"` event of Fluid, and watershed calls it a
/// *ripple*. The function drops a malformed payload and reports nothing,
/// because a ripple is best-effort.
fn on_ripple(cell: Cell(State), payload: String) -> Nil {
  case json.parse(payload, socket.ripple_message_decoder()) {
    Error(_) -> Nil
    Ok(ripple) -> {
      let state = cell_get(cell)
      list.each(state.ripple_subscribers, fn(handler) { handler(ripple) })
    }
  }
}

@target(javascript)
fn notify_presence(cell: Cell(State), frame: PresenceFrame) -> Nil {
  let state = cell_get(cell)
  list.each(state.presence_subscribers, fn(handler) { handler(frame) })
}

@target(javascript)
/// Announce a handshake that settled. The message carries the id and the
/// capability that a driver needs to join.
fn notify_presence_session(cell: Cell(State), core: runtime_core.Core) -> Nil {
  let state = cell_get(cell)
  notify_presence(
    cell,
    PresenceSession(
      client_id: core.client_id,
      presence_v1: socket.supports_feature(
        state.supported_features,
        socket.feature_presence_v1,
      ),
    ),
  )
}

@target(javascript)
/// Announce that a live session ended, and only when one was live. A socket
/// that never reached `Ready`, and a socket that the runtime already knows is
/// closed, both hold no presence. The runtime must not report a lost presence
/// two times.
fn notify_session_lost(cell: Cell(State), previous: Phase) -> Nil {
  case previous {
    Ready(_, _) -> notify_presence(cell, PresenceSessionLost)
    Connecting | Reconnecting(_) | Failed(_) -> Nil
  }
}

@target(javascript)
fn fail(cell: Cell(State), reason: String) -> Nil {
  let state = abort_outcome_waiters(cell_get(cell))
  fire_ready(cell, Error(reason))
  cell_set(cell, State(..state, phase: Failed(reason)))
  notify_session_lost(cell, state.phase)
}

@target(javascript)
/// Run the `on_ready` callback exactly one time.
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
