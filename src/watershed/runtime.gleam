//// Runtime actor: one per document connection.
////
//// Owns the kernel-bearing `runtime_core` state and the subscriber list.
//// The aquamarine channel is owned by a dedicated receiver process (the
//// transport only delivers to the process that opened it); the receiver
//// forwards every inbound frame to this actor, while pushes are safe from
//// the actor itself.
////
//// Resilience (M4):
////
//// - **Gaps** — out-of-order ops are buffered by `runtime_core`, which asks
////   us to `requestOps` an in-band catch-up; the buffer drains as it fills.
//// - **Reconnect** — a mid-session channel close (or a retryable nack)
////   rejoins and re-handshakes with a fresh client_id, passing
////   `lastSeenSequenceNumber` so the server pushes just the delta. Old ops
////   still in flight are reconciled against the catch-up stream and the
////   remainder resubmitted with fresh CSNs once we reach the reconnect
////   checkpoint. Edits made while (re)connecting are applied optimistically
////   and their push is deferred to that resubmit.
//// - **Nacks** — fatal ones (bad scope, size, hard limit) crash the actor;
////   everything else reconnects and reconciles.
//// - **Heartbeat** — a periodic `noop` advances the server's MSN while idle.

import gleam/dynamic/decode
import gleam/erlang/process.{type Subject}
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/string

import aquamarine
import aquamarine/channel.{type Channel}
import aquamarine/codec.{type Incoming}
import aquamarine/phoenix

import spillway/message.{type ConnectMessage}
import spillway/nack.{type Nack}
import spillway/types.{type SequencedDocumentMessage}

import watershed/map_kernel.{type MapEvent}
import watershed/runtime_core
import watershed/wire

const connect_timeout_ms = 10_000

const heartbeat_interval_ms = 30_000

const address = "root"

/// Server nacks submissions above 100 ops; chunk resubmits to stay under it.
const max_ops_per_submission = 100

pub type Msg {
  // Actor bootstrap: learn our own subject so we can schedule heartbeats.
  Register(self: Subject(Msg))
  Heartbeat
  // Receiver-process lifecycle
  ChannelReady(Channel)
  ChannelFailed(String)
  Inbound(Incoming)
  ChannelClosed(String)
  // Local edits
  Put(key: String, value: Json)
  Remove(key: String)
  RemoveAll
  // Reads
  GetValue(key: String, reply: Subject(Option(Json)))
  GetEntries(reply: Subject(List(#(String, Json))))
  GetKeys(reply: Subject(List(String)))
  GetSize(reply: Subject(Int))
  // Lifecycle
  Subscribe(Subject(MapEvent))
  AwaitReady(reply: Subject(Result(Nil, String)))
  /// Fault-injection hook (tests): drop the live channel to force the
  /// runtime through its reconnect/reconcile path.
  DropChannel
  Shutdown
}

type Phase {
  Connecting(waiters: List(Subject(Result(Nil, String))))
  /// Socket down and re-handshaking; holds the pre-reconnect core so its
  /// kernel/pending/in-flight survive the round trip.
  Reconnecting(core: runtime_core.Core)
  /// Connected. `resubmit_at` is `Some(checkpoint)` while a reconnect is
  /// still catching up to the point where un-acked ops can be resubmitted,
  /// and `None` once fully synced.
  Ready(core: runtime_core.Core, resubmit_at: Option(Int))
  Failed(reason: String)
}

type State {
  State(
    host: String,
    port: Int,
    path: String,
    topic: String,
    join_payload: Json,
    connect_message: ConnectMessage,
    channel: Option(Channel),
    phase: Phase,
    subscribers: List(Subject(MapEvent)),
    self: Option(Subject(Msg)),
  )
}

/// Start a document runtime: spawns the actor and the channel receiver
/// process, then returns the actor subject. Callers should `AwaitReady`
/// (via `process.call`) before editing.
pub fn start(
  host host: String,
  port port: Int,
  path path: String,
  tenant tenant: String,
  document document: String,
  connect_message connect_message: ConnectMessage,
) -> Result(Subject(Msg), actor.StartError) {
  let topic = "document:" <> tenant <> ":" <> document
  let join_payload = case connect_message.token {
    Some(token) -> json.object([#("token", json.string(token))])
    None -> json.object([])
  }
  let state =
    State(
      host: host,
      port: port,
      path: path,
      topic: topic,
      join_payload: join_payload,
      connect_message: connect_message,
      channel: None,
      phase: Connecting([]),
      subscribers: [],
      self: None,
    )
  case actor.new(state) |> actor.on_message(handle) |> actor.start {
    Error(err) -> Error(err)
    Ok(started) -> {
      let runtime = started.data
      process.send(runtime, Register(runtime))
      spawn_receiver(state, runtime)
      Ok(runtime)
    }
  }
}

/// Block until the handshake completes (or fails).
pub fn await_ready(runtime: Subject(Msg)) -> Result(Nil, String) {
  process.call(runtime, waiting: connect_timeout_ms, sending: AwaitReady)
}

// ─────────────────────────────────────────────────────────────────────────────
// Receiver process
// ─────────────────────────────────────────────────────────────────────────────

fn spawn_receiver(state: State, runtime: Subject(Msg)) -> Nil {
  let _ =
    process.spawn_unlinked(fn() {
      receiver_main(
        state.host,
        state.port,
        state.path,
        state.topic,
        state.join_payload,
        runtime,
      )
    })
  Nil
}

fn receiver_main(
  host: String,
  port: Int,
  path: String,
  topic: String,
  join_payload: Json,
  runtime: Subject(Msg),
) -> Nil {
  case
    aquamarine.connect(
      host: host,
      port: port,
      path: path,
      topic: topic,
      payload: join_payload,
      codec: phoenix.codec(),
    )
  {
    Error(err) -> process.send(runtime, ChannelFailed(string.inspect(err)))
    Ok(channel) -> {
      process.send(runtime, ChannelReady(channel))
      receive_loop(channel, runtime)
    }
  }
}

fn receive_loop(channel: Channel, runtime: Subject(Msg)) -> Nil {
  case aquamarine.receive(channel) {
    Ok(incoming) -> {
      process.send(runtime, Inbound(incoming))
      receive_loop(channel, runtime)
    }
    Error(err) -> process.send(runtime, ChannelClosed(string.inspect(err)))
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Actor
// ─────────────────────────────────────────────────────────────────────────────

fn handle(state: State, msg: Msg) -> actor.Next(State, Msg) {
  case msg {
    Register(self) -> {
      let _ = process.send_after(self, heartbeat_interval_ms, Heartbeat)
      actor.continue(State(..state, self: Some(self)))
    }

    Heartbeat -> {
      case state.self {
        Some(self) -> {
          let _ = process.send_after(self, heartbeat_interval_ms, Heartbeat)
          Nil
        }
        None -> Nil
      }
      case state.phase, state.channel {
        Ready(core, None), Some(channel) ->
          push(
            channel,
            "noop",
            wire.encode_noop(
              core.client_id,
              reference_sequence_number: core.last_seen_sn,
            ),
          )
        _, _ -> Nil
      }
      actor.continue(state)
    }

    ChannelReady(channel) -> {
      let last_seen = case state.phase {
        Reconnecting(core) -> Some(core.last_seen_sn)
        _ -> None
      }
      push(
        channel,
        "connect_document",
        wire.encode_connect_document(state.connect_message, last_seen),
      )
      actor.continue(State(..state, channel: Some(channel)))
    }

    ChannelFailed(reason) ->
      actor.continue(fail(state, "channel connect failed: " <> reason))

    ChannelClosed(reason) ->
      case state.phase {
        Ready(core, _) -> actor.continue(begin_reconnect(state, core))
        Reconnecting(core) -> actor.continue(begin_reconnect(state, core))
        _ -> actor.continue(fail(state, "channel closed: " <> reason))
      }

    Inbound(incoming) -> handle_inbound(state, incoming)

    Put(key, value) ->
      edit(state, fn(core) { runtime_core.set(core, key, value) })
    Remove(key) -> edit(state, fn(core) { runtime_core.delete(core, key) })
    RemoveAll -> edit(state, runtime_core.clear)

    GetValue(key, reply) -> {
      process.send(reply, read(state, None, runtime_core.get(_, key)))
      actor.continue(state)
    }
    GetEntries(reply) -> {
      process.send(reply, read(state, [], runtime_core.entries))
      actor.continue(state)
    }
    GetKeys(reply) -> {
      process.send(reply, read(state, [], runtime_core.keys))
      actor.continue(state)
    }
    GetSize(reply) -> {
      process.send(reply, read(state, 0, runtime_core.size))
      actor.continue(state)
    }

    Subscribe(subscriber) ->
      actor.continue(
        State(..state, subscribers: [subscriber, ..state.subscribers]),
      )

    AwaitReady(reply) ->
      case state.phase {
        Ready(_, _) -> {
          process.send(reply, Ok(Nil))
          actor.continue(state)
        }
        Failed(reason) -> {
          process.send(reply, Error(reason))
          actor.continue(state)
        }
        Connecting(waiters) ->
          actor.continue(State(..state, phase: Connecting([reply, ..waiters])))
        // A reconnect can only start after we were Ready, i.e. after
        // await_ready already returned; treat as ready.
        Reconnecting(_) -> {
          process.send(reply, Ok(Nil))
          actor.continue(state)
        }
      }

    DropChannel ->
      case state.phase {
        // Reuse the retryable-nack path: close the channel and enter the
        // reconnecting phase; the receiver's ChannelClosed drives the rejoin.
        Ready(core, _) -> actor.continue(reconnect_after_nack(state, core))
        _ -> actor.continue(state)
      }

    Shutdown -> {
      case state.channel {
        Some(channel) -> {
          let _ = aquamarine.close(channel)
          Nil
        }
        None -> Nil
      }
      actor.stop()
    }
  }
}

fn handle_inbound(state: State, incoming: Incoming) -> actor.Next(State, Msg) {
  case incoming.event {
    "connect_document_success" -> {
      let connected =
        require(
          decode.run(incoming.payload, wire.connected_message_decoder()),
          "connect_document_success payload",
        )
      case state.phase {
        Connecting(_) ->
          case runtime_core.bootstrap(connected, address: address) {
            Ok(core) -> {
              notify_waiters(state.phase, Ok(Nil))
              actor.continue(State(..state, phase: Ready(core, None)))
            }
            Error(core_error) ->
              panic as { "bootstrap failed: " <> string.inspect(core_error) }
          }
        Reconnecting(core) -> {
          let core = runtime_core.adopt_reconnect(core, connected)
          let checkpoint =
            option.unwrap(
              connected.checkpoint_sequence_number,
              core.last_seen_sn,
            )
          settle_reconnect(state, core, checkpoint)
        }
        // A late duplicate success; nothing to do.
        _ -> actor.continue(state)
      }
    }

    "connect_document_error" -> {
      let connect_error =
        require(
          decode.run(incoming.payload, wire.connect_error_decoder()),
          "connect_document_error payload",
        )
      actor.continue(fail(state, connect_error.message))
    }

    "op" ->
      case state.phase {
        Ready(core, resubmit_at) -> {
          let #(core, events, request_from) =
            apply_ops(core, op_message(incoming))
          fan_out(state.subscribers, events)
          maybe_request_ops(state.channel, request_from)
          case resubmit_at {
            Some(checkpoint) -> settle_reconnect(state, core, checkpoint)
            None -> actor.continue(State(..state, phase: Ready(core, None)))
          }
        }
        // Ops before/without a connected session (or while reconnecting)
        // carry no state we can trust; ignore them.
        _ -> actor.continue(state)
      }

    "nack" -> {
      let nacks =
        require(
          decode.run(incoming.payload, wire.nacks_decoder()),
          "nack payload",
        )
      case list.any(nacks, nack_is_fatal) {
        True ->
          panic as {
            "fatal nack from server: " <> string.inspect(incoming.payload)
          }
        False ->
          case state.phase {
            Ready(core, _) -> actor.continue(reconnect_after_nack(state, core))
            // Already tearing the channel down; the pending reconnect covers it.
            _ -> actor.continue(state)
          }
      }
    }

    // Signals, summary events, pongs: not part of the v1 surface.
    _ -> actor.continue(state)
  }
}

/// Resubmit un-acked ops once catch-up has reached the reconnect checkpoint;
/// otherwise stay in the catching-up state until more ops arrive.
fn settle_reconnect(
  state: State,
  core: runtime_core.Core,
  checkpoint: Int,
) -> actor.Next(State, Msg) {
  case core.last_seen_sn >= checkpoint {
    True -> {
      let #(core, outbound) = runtime_core.resubmit(core)
      send_outbound(state.channel, core.client_id, outbound)
      actor.continue(State(..state, phase: Ready(core, None)))
    }
    False ->
      actor.continue(State(..state, phase: Ready(core, Some(checkpoint))))
  }
}

fn op_message(incoming: Incoming) -> List(SequencedDocumentMessage) {
  let message =
    require(
      decode.run(incoming.payload, wire.op_message_decoder()),
      "op payload",
    )
  message.ops
}

fn apply_ops(
  core: runtime_core.Core,
  ops: List(SequencedDocumentMessage),
) -> #(runtime_core.Core, List(MapEvent), Option(Int)) {
  do_apply_ops(core, ops, [], None)
}

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
        Error(core_error) ->
          panic as {
            "sequenced op processing failed: " <> string.inspect(core_error)
          }
      }
  }
}

fn edit(
  state: State,
  operate: fn(runtime_core.Core) ->
    #(runtime_core.Core, List(MapEvent), wire.OutboundOp),
) -> actor.Next(State, Msg) {
  case state.phase {
    Ready(core, resubmit_at) -> {
      let #(core, events, outbound) = operate(core)
      // Push immediately only when fully synced with a live channel;
      // otherwise the op stays in-flight and `resubmit` sends it once, so a
      // reconnect can't drop or duplicate it.
      case resubmit_at, state.channel {
        None, Some(channel) ->
          push(
            channel,
            "submitOp",
            wire.encode_submit_op(core.client_id, [[outbound]]),
          )
        _, _ -> Nil
      }
      fan_out(state.subscribers, events)
      actor.continue(State(..state, phase: Ready(core, resubmit_at)))
    }
    Reconnecting(core) -> {
      let #(core, events, _outbound) = operate(core)
      fan_out(state.subscribers, events)
      actor.continue(State(..state, phase: Reconnecting(core)))
    }
    // Edits are only reachable through handles returned after await_ready,
    // so this is either a race with a failure or API misuse.
    _ -> panic as "edit before the document connection is ready"
  }
}

fn read(state: State, default: t, extract: fn(runtime_core.Core) -> t) -> t {
  case state.phase {
    Ready(core, _) -> extract(core)
    Reconnecting(core) -> extract(core)
    _ -> default
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reconnect helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Enter the reconnecting phase after a channel close: drop the dead channel
/// and spawn a fresh receiver, which will re-handshake with our last-seen SN.
fn begin_reconnect(state: State, core: runtime_core.Core) -> State {
  case state.self {
    Some(self) -> spawn_receiver(state, self)
    None -> Nil
  }
  State(..state, channel: None, phase: Reconnecting(core))
}

/// Retryable nack: close the channel and enter the reconnecting phase. The
/// receiver's resulting `ChannelClosed` drives the actual reconnect, so we
/// don't spawn a second receiver here.
fn reconnect_after_nack(state: State, core: runtime_core.Core) -> State {
  case state.channel {
    Some(channel) -> {
      let _ = aquamarine.close(channel)
      Nil
    }
    None -> Nil
  }
  State(..state, channel: None, phase: Reconnecting(core))
}

fn nack_is_fatal(item: Nack) -> Bool {
  case item.content.error_type {
    nack.InvalidScopeError -> True
    nack.LimitExceededError -> True
    _ -> item.content.code == 413
  }
}

fn maybe_request_ops(
  channel: Option(Channel),
  request_from: Option(Int),
) -> Nil {
  case channel, request_from {
    Some(channel), Some(from) ->
      push(channel, "requestOps", wire.encode_request_ops(from: from))
    _, _ -> Nil
  }
}

fn send_outbound(
  channel: Option(Channel),
  client_id: String,
  outbound: List(wire.OutboundOp),
) -> Nil {
  case channel, outbound {
    _, [] -> Nil
    Some(channel), _ ->
      list.each(list.sized_chunk(outbound, max_ops_per_submission), fn(chunk) {
        push(channel, "submitOp", wire.encode_submit_op(client_id, [chunk]))
      })
    None, _ -> Nil
  }
}

fn push(channel: Channel, event: String, payload: Json) -> Nil {
  case aquamarine.push(channel, event, payload) {
    Ok(Nil) -> Nil
    Error(err) -> panic as { "channel push failed: " <> string.inspect(err) }
  }
}

fn fan_out(
  subscribers: List(Subject(MapEvent)),
  events: List(MapEvent),
) -> Nil {
  list.each(events, fn(event) { list.each(subscribers, process.send(_, event)) })
}

fn fail(state: State, reason: String) -> State {
  notify_waiters(state.phase, Error(reason))
  State(..state, phase: Failed(reason))
}

fn notify_waiters(phase: Phase, result: Result(Nil, String)) -> Nil {
  case phase {
    Connecting(waiters) -> list.each(waiters, process.send(_, result))
    _ -> Nil
  }
}

fn require(result: Result(t, e), context: String) -> t {
  case result {
    Ok(value) -> value
    Error(err) ->
      panic as { "failed to decode " <> context <> ": " <> string.inspect(err) }
  }
}
