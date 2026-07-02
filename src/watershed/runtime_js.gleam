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
import gleam/dynamic.{type Dynamic}
@target(javascript)
import gleam/dynamic/decode
@target(javascript)
import gleam/json.{type Json}
@target(javascript)
import gleam/list
@target(javascript)
import gleam/option.{type Option, None, Some}
@target(javascript)
import gleam/string

@target(javascript)
import spillway/message.{type ConnectMessage}
@target(javascript)
import spillway/nack.{type Nack}
@target(javascript)
import spillway/types.{type SequencedDocumentMessage}

@target(javascript)
import watershed/map_kernel.{type MapEvent}
@target(javascript)
import watershed/runtime_core
@target(javascript)
import watershed/transport_js.{type Cell, type Channel}
@target(javascript)
import watershed/wire

@target(javascript)
const address = "root"

@target(javascript)
/// Server nacks submissions above 100 ops; chunk resubmits to stay under it.
const max_ops_per_submission = 100

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
    channel: Option(Channel),
    phase: Phase,
    subscribers: List(fn(MapEvent) -> Nil),
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
/// Start a runtime: open the Phoenix socket, join the topic, and begin the
/// handshake. `on_ready` fires once with `Ok(Nil)` when the document has
/// bootstrapped, or `Error(reason)` if the connection is rejected.
pub fn start(
  url url: String,
  topic topic: String,
  connect_message connect_message: ConnectMessage,
  on_ready on_ready: fn(Result(Nil, String)) -> Nil,
) -> Runtime {
  let cell =
    transport_js.new_cell(State(
      connect_message: connect_message,
      channel: None,
      phase: Connecting,
      subscribers: [],
      on_ready: on_ready,
      ready_fired: False,
    ))

  let join_payload = case connect_message.token {
    Some(token) -> json.object([#("token", json.string(token))])
    None -> json.object([])
  }

  let channel =
    transport_js.connect(
      url: url,
      topic: topic,
      join_payload: json.to_string(join_payload),
      on_event: fn(event, payload) { on_event(cell, event, payload) },
      on_join: fn() { on_join(cell) },
      on_close: fn() { on_close(cell) },
    )

  cell_set(cell, State(..cell_get(cell), channel: Some(channel)))
  Runtime(cell: cell)
}

// ─────────────────────────────────────────────────────────────────────────────
// Public edits / reads / events
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
pub fn set(runtime: Runtime, key: String, value: Json) -> Nil {
  edit(runtime.cell, fn(core) { runtime_core.set(core, key, value) })
}

@target(javascript)
pub fn delete(runtime: Runtime, key: String) -> Nil {
  edit(runtime.cell, fn(core) { runtime_core.delete(core, key) })
}

@target(javascript)
pub fn clear(runtime: Runtime) -> Nil {
  edit(runtime.cell, runtime_core.clear)
}

@target(javascript)
pub fn get(runtime: Runtime, key: String) -> Option(Json) {
  read(runtime.cell, None, runtime_core.get(_, key))
}

@target(javascript)
pub fn entries(runtime: Runtime) -> List(#(String, Json)) {
  read(runtime.cell, [], runtime_core.entries)
}

@target(javascript)
pub fn keys(runtime: Runtime) -> List(String) {
  read(runtime.cell, [], runtime_core.keys)
}

@target(javascript)
pub fn size(runtime: Runtime) -> Int {
  read(runtime.cell, 0, runtime_core.size)
}

@target(javascript)
pub fn has(runtime: Runtime, key: String) -> Bool {
  get(runtime, key) != None
}

@target(javascript)
/// Register a callback invoked for every local and remote map event.
pub fn subscribe(runtime: Runtime, handler: fn(MapEvent) -> Nil) -> Nil {
  let state = cell_get(runtime.cell)
  cell_set(
    runtime.cell,
    State(..state, subscribers: [handler, ..state.subscribers]),
  )
}

@target(javascript)
/// Fault-injection hook: drop the socket to force the reconnect/reconcile path.
pub fn force_reconnect(runtime: Runtime) -> Nil {
  let state = cell_get(runtime.cell)
  case state.phase, state.channel {
    Ready(core, _), Some(channel) -> {
      cell_set(runtime.cell, State(..state, phase: Reconnecting(core)))
      transport_js.drop_socket(channel)
    }
    _, _ -> Nil
  }
}

@target(javascript)
pub fn close(runtime: Runtime) -> Nil {
  case cell_get(runtime.cell).channel {
    Some(channel) -> transport_js.close(channel)
    None -> Nil
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
    _ -> Nil
  }
}

@target(javascript)
fn on_connect_success(cell: Cell(State), payload: Dynamic) -> Nil {
  case decode.run(payload, wire.connected_message_decoder()) {
    Error(_) -> fail(cell, "malformed connect_document_success payload")
    Ok(connected) -> {
      let state = cell_get(cell)
      case state.phase {
        Connecting ->
          case runtime_core.bootstrap(connected, address: address) {
            Ok(core) -> {
              cell_set(cell, State(..state, phase: Ready(core, None)))
              fire_ready(cell, Ok(Nil))
            }
            Error(err) ->
              fail(cell, "bootstrap failed: " <> string.inspect(err))
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
fn on_connect_error(cell: Cell(State), payload: Dynamic) -> Nil {
  case decode.run(payload, wire.connect_error_decoder()) {
    Ok(err) -> fail(cell, err.message)
    Error(_) -> fail(cell, "connect_document_error")
  }
}

@target(javascript)
fn on_op(cell: Cell(State), payload: Dynamic) -> Nil {
  let state = cell_get(cell)
  case state.phase {
    Ready(core, resubmit_at) ->
      case decode.run(payload, wire.op_message_decoder()) {
        Error(_) -> fail(cell, "malformed op payload")
        Ok(message) -> {
          let #(core, events, request_from) = apply_ops(core, message.ops)
          fan_out(state.subscribers, events)
          maybe_request_ops(state.channel, request_from)
          case resubmit_at {
            Some(checkpoint) -> settle_reconnect(cell, core, checkpoint)
            None ->
              cell_set(cell, State(..cell_get(cell), phase: Ready(core, None)))
          }
        }
      }
    // Ops before a connected session (or while reconnecting) carry no state
    // we can trust; ignore them.
    _ -> Nil
  }
}

@target(javascript)
fn on_nack(cell: Cell(State), payload: Dynamic) -> Nil {
  case decode.run(payload, wire.nacks_decoder()) {
    Error(_) -> fail(cell, "malformed nack payload")
    Ok(nacks) ->
      case list.any(nacks, nack_is_fatal) {
        True -> fail(cell, "fatal nack from server")
        False -> {
          let state = cell_get(cell)
          case state.phase, state.channel {
            Ready(core, _), Some(channel) -> {
              cell_set(cell, State(..state, phase: Reconnecting(core)))
              transport_js.drop_socket(channel)
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
) -> #(runtime_core.Core, List(MapEvent), Option(Int)) {
  do_apply_ops(core, ops, [], None)
}

@target(javascript)
fn do_apply_ops(
  core: runtime_core.Core,
  ops: List(SequencedDocumentMessage),
  events: List(List(MapEvent)),
  request_from: Option(Int),
) -> #(runtime_core.Core, List(MapEvent), Option(Int)) {
  case ops {
    [] -> #(core, list.reverse(events) |> list.flatten, request_from)
    [op, ..rest] ->
      case runtime_core.handle_sequenced(core, op) {
        Ok(#(core, ingested)) ->
          do_apply_ops(
            core,
            rest,
            [ingested.events, ..events],
            option.or(request_from, ingested.request_ops_from),
          )
        // A decode/ack failure here means divergence; stop applying and keep
        // what we had rather than corrupting state silently.
        Error(_) -> #(core, list.reverse(events) |> list.flatten, request_from)
      }
  }
}

@target(javascript)
fn edit(
  cell: Cell(State),
  operate: fn(runtime_core.Core) ->
    #(runtime_core.Core, List(MapEvent), wire.OutboundOp),
) -> Nil {
  let state = cell_get(cell)
  case state.phase {
    Ready(core, resubmit_at) -> {
      let #(core, events, outbound) = operate(core)
      // Push immediately only when fully synced with a live channel; otherwise
      // the op stays in-flight and `resubmit` sends it once, so a reconnect
      // can't drop or duplicate it.
      case resubmit_at, state.channel {
        None, Some(channel) ->
          push_json(
            channel,
            "submitOp",
            wire.encode_submit_op(core.client_id, [[outbound]]),
          )
        _, _ -> Nil
      }
      fan_out(state.subscribers, events)
      cell_set(cell, State(..state, phase: Ready(core, resubmit_at)))
    }
    Reconnecting(core) -> {
      let #(core, events, _outbound) = operate(core)
      fan_out(state.subscribers, events)
      cell_set(cell, State(..state, phase: Reconnecting(core)))
    }
    // Edits before ready are dropped (the demo gates edits behind on_ready).
    _ -> Nil
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
  channel: Channel,
  connect_message: ConnectMessage,
  last_seen: Option(Int),
) -> Nil {
  push_json(
    channel,
    "connect_document",
    wire.encode_connect_document(connect_message, last_seen),
  )
}

@target(javascript)
fn maybe_request_ops(
  channel: Option(Channel),
  request_from: Option(Int),
) -> Nil {
  case channel, request_from {
    Some(channel), Some(from) ->
      push_json(channel, "requestOps", wire.encode_request_ops(from: from))
    _, _ -> Nil
  }
}

@target(javascript)
fn send_outbound(
  channel: Option(Channel),
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
          wire.encode_submit_op(client_id, [chunk]),
        )
      })
    None, _ -> Nil
  }
}

@target(javascript)
fn push_json(channel: Channel, event: String, payload: Json) -> Nil {
  transport_js.push(channel, event, json.to_string(payload))
}

@target(javascript)
fn fan_out(
  subscribers: List(fn(MapEvent) -> Nil),
  events: List(MapEvent),
) -> Nil {
  list.each(events, fn(event) {
    list.each(subscribers, fn(subscriber) { subscriber(event) })
  })
}

@target(javascript)
fn fail(cell: Cell(State), reason: String) -> Nil {
  fire_ready(cell, Error(reason))
  cell_set(cell, State(..cell_get(cell), phase: Failed(reason)))
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
