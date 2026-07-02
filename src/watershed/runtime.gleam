//// Runtime actor: one per document connection.
////
//// Owns the kernel-bearing `runtime_core` state and the subscriber list.
//// The aquamarine channel is owned by a dedicated receiver process (the
//// transport only delivers to the process that opened it); the receiver
//// forwards every inbound frame to this actor, while pushes are safe from
//// the actor itself.
////
//// Failure policy (M3): any protocol divergence — nack, sequence gap, ack
//// mismatch, undecodable frame — crashes the actor loudly rather than
//// continuing with possibly-divergent state. M4 replaces the crash paths
//// with the reconnect/reconcile state machine.

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
import spillway/types.{type SequencedDocumentMessage}

import watershed/map_kernel.{type MapEvent}
import watershed/runtime_core
import watershed/wire

const connect_timeout_ms = 10_000

pub type Msg {
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
  Shutdown
}

type Phase {
  Connecting(waiters: List(Subject(Result(Nil, String))))
  Ready(core: runtime_core.Core)
  Failed(reason: String)
}

type State {
  State(
    channel: Option(Channel),
    connect_payload: Json,
    phase: Phase,
    subscribers: List(Subject(MapEvent)),
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
  let connect_payload = wire.encode_connect_document(connect_message, None)
  let state =
    State(
      channel: None,
      connect_payload: connect_payload,
      phase: Connecting([]),
      subscribers: [],
    )
  case actor.new(state) |> actor.on_message(handle) |> actor.start {
    Error(err) -> Error(err)
    Ok(started) -> {
      let runtime = started.data
      let topic = "document:" <> tenant <> ":" <> document
      let join_payload = case connect_message.token {
        Some(token) -> json.object([#("token", json.string(token))])
        None -> json.object([])
      }
      process.spawn_unlinked(fn() {
        receiver_main(host, port, path, topic, join_payload, runtime)
      })
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
    ChannelReady(channel) -> {
      push(channel, "connect_document", state.connect_payload)
      actor.continue(State(..state, channel: Some(channel)))
    }

    ChannelFailed(reason) ->
      actor.continue(fail(state, "channel connect failed: " <> reason))

    ChannelClosed(reason) ->
      case state.phase {
        // M4 adds reconnect; for now a mid-session close is fatal.
        Ready(_) -> panic as { "channel closed while connected: " <> reason }
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
        Ready(_) -> {
          process.send(reply, Ok(Nil))
          actor.continue(state)
        }
        Failed(reason) -> {
          process.send(reply, Error(reason))
          actor.continue(state)
        }
        Connecting(waiters) ->
          actor.continue(State(..state, phase: Connecting([reply, ..waiters])))
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
      case runtime_core.bootstrap(connected, address: "root") {
        Ok(core) -> {
          notify_waiters(state.phase, Ok(Nil))
          actor.continue(State(..state, phase: Ready(core)))
        }
        Error(core_error) ->
          panic as { "bootstrap failed: " <> string.inspect(core_error) }
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

    "op" -> {
      let op_message =
        require(
          decode.run(incoming.payload, wire.op_message_decoder()),
          "op payload",
        )
      case state.phase {
        Ready(core) -> {
          let #(core, events) = apply_ops(core, op_message.ops, [])
          fan_out(state.subscribers, events)
          actor.continue(State(..state, phase: Ready(core)))
        }
        // Ops can only arrive after connect_document_success on this
        // channel; anything earlier is a protocol violation.
        _ -> panic as "op event before connect_document_success"
      }
    }

    "nack" ->
      // M3 policy: nacks are fatal (v1 reconnect+reconcile lands in M4).
      panic as { "op nacked by server: " <> string.inspect(incoming.payload) }

    // Signals, summary events, pongs: not part of the v1 surface.
    _ -> actor.continue(state)
  }
}

fn apply_ops(
  core: runtime_core.Core,
  ops: List(SequencedDocumentMessage),
  events: List(List(MapEvent)),
) -> #(runtime_core.Core, List(MapEvent)) {
  case ops {
    [] -> #(core, list.reverse(events) |> list.flatten)
    [op, ..rest] ->
      case runtime_core.handle_sequenced(core, op) {
        Ok(#(core, new_events)) -> apply_ops(core, rest, [new_events, ..events])
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
  case state.phase, state.channel {
    Ready(core), Some(channel) -> {
      let #(core, events, outbound) = operate(core)
      push(
        channel,
        "submitOp",
        wire.encode_submit_op(core.client_id, [[outbound]]),
      )
      fan_out(state.subscribers, events)
      actor.continue(State(..state, phase: Ready(core)))
    }
    // Edits are only reachable through handles returned after await_ready,
    // so this is either a race with a failure or API misuse.
    _, _ -> panic as "edit before the document connection is ready"
  }
}

fn read(state: State, default: t, extract: fn(runtime_core.Core) -> t) -> t {
  case state.phase {
    Ready(core) -> extract(core)
    _ -> default
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
