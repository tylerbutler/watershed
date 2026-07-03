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

@target(erlang)
import gleam/dynamic/decode
@target(erlang)
import gleam/erlang/process.{type Subject}
@target(erlang)
import gleam/int
@target(erlang)
import gleam/json.{type Json}
@target(erlang)
import gleam/list
@target(erlang)
import gleam/option.{type Option, None, Some}
@target(erlang)
import gleam/otp/actor
@target(erlang)
import gleam/result
@target(erlang)
import gleam/string

@target(erlang)
import aquamarine
@target(erlang)
import aquamarine/channel.{type Channel}
@target(erlang)
import aquamarine/codec.{type Incoming}
@target(erlang)
import aquamarine/phoenix

@target(erlang)
import spillway/message.{type ConnectMessage, type SummaryContext}
@target(erlang)
import spillway/nack.{type Nack}
@target(erlang)
import spillway/types.{type SequencedDocumentMessage}

@target(erlang)
import watershed/git_storage
@target(erlang)
import watershed/ids
@target(erlang)
import watershed/map_kernel.{type MapEvent}
@target(erlang)
import watershed/runtime_core
@target(erlang)
import watershed/wire
@target(erlang)
import watershed/wire/socket
@target(erlang)
import watershed/wire/summary_blob

@target(erlang)
const connect_timeout_ms = 10_000

@target(erlang)
const heartbeat_interval_ms = 30_000

@target(erlang)
/// Server nacks submissions above 100 ops; chunk resubmits to stay under it.
const max_ops_per_submission = 100

@target(erlang)
pub type Msg {
  Heartbeat
  // Receiver-process lifecycle
  ChannelReady(Channel)
  ChannelFailed(String)
  Inbound(Incoming)
  ChannelClosed(String)
  // Local edits
  Put(address: String, key: String, value: Json)
  Remove(address: String, key: String)
  RemoveAll(address: String)
  /// Create a new detached map channel: local-only until its handle is first
  /// stored into an attached map. Replies with the generated address.
  CreateMap(reply: Subject(Result(String, String)))
  /// Whether a channel exists at `address` (attached or detached). Errors are
  /// retryable — a foreign attach may still be in flight.
  ResolveAddress(address: String, reply: Subject(Result(Nil, String)))
  /// Summarize the current confirmed state to levee storage, replying with the
  /// summary handle (git tree SHA) on success.
  Summarize(reply: Subject(Result(String, String)))
  /// List the document's stored summary versions, newest first.
  GetVersions(
    count: Int,
    reply: Subject(Result(List(git_storage.SummaryVersion), String)),
  )
  /// Read the historical snapshot a summary version captured, by its handle.
  LoadVersion(
    handle: String,
    reply: Subject(Result(summary_blob.SummaryBlob, String)),
  )
  // Reads
  GetValue(address: String, key: String, reply: Subject(Option(Json)))
  GetEntries(address: String, reply: Subject(List(#(String, Json))))
  GetKeys(address: String, reply: Subject(List(String)))
  GetSize(address: String, reply: Subject(Int))
  /// Whether every local edit has been acknowledged (in-flight queue empty),
  /// so the confirmed state is complete and stable.
  IsSynced(reply: Subject(Bool))
  // Lifecycle
  Subscribe(address: String, subscriber: Subject(MapEvent))
  AwaitReady(reply: Subject(Result(Nil, String)))
  /// Fault-injection hook (tests): drop the live channel to force the
  /// runtime through its reconnect/reconcile path.
  DropChannel
  Shutdown
}

@target(erlang)
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

@target(erlang)
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
    subscribers: List(#(String, Subject(MapEvent))),
    self: Subject(Msg),
  )
}

@target(erlang)
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
  actor.new_with_initialiser(1000, fn(self) {
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
        self: self,
      )
    let _ = process.send_after(self, heartbeat_interval_ms, Heartbeat)
    spawn_receiver(state, self)
    Ok(actor.initialised(state) |> actor.returning(self))
  })
  |> actor.on_message(handle)
  |> actor.start
  |> result.map(fn(started) { started.data })
}

@target(erlang)
/// Block until the handshake completes (or fails).
pub fn await_ready(runtime: Subject(Msg)) -> Result(Nil, String) {
  process.call(runtime, waiting: connect_timeout_ms, sending: AwaitReady)
}

@target(erlang)
/// Summarize the current confirmed state to levee storage. Returns the summary
/// handle (git tree SHA) on success. Requires the connection to be fully synced
/// and the token to carry the `summary:write` scope.
pub fn summarize(runtime: Subject(Msg)) -> Result(String, String) {
  process.call(runtime, waiting: connect_timeout_ms, sending: Summarize)
}

@target(erlang)
/// Whether the client is caught up: every local edit has been acknowledged by
/// the server, so the confirmed state is complete and stable.
pub fn is_synced(runtime: Subject(Msg)) -> Bool {
  process.call(runtime, waiting: connect_timeout_ms, sending: IsSynced)
}

@target(erlang)
/// List the document's stored summary versions, newest first (the client half
/// of Fluid's `getVersions`). Requires the token to carry `doc:read`.
pub fn get_versions(
  runtime: Subject(Msg),
  count: Int,
) -> Result(List(git_storage.SummaryVersion), String) {
  process.call(runtime, waiting: connect_timeout_ms, sending: fn(reply) {
    GetVersions(count, reply)
  })
}

@target(erlang)
/// Read the historical snapshot a summary version captured, by its handle
/// (from `get_versions` or a `summarize` return). The live document is
/// unaffected — this is a point-in-time read of the stored blob.
pub fn load_version(
  runtime: Subject(Msg),
  handle: String,
) -> Result(summary_blob.SummaryBlob, String) {
  process.call(runtime, waiting: connect_timeout_ms, sending: fn(reply) {
    LoadVersion(handle, reply)
  })
}

// ─────────────────────────────────────────────────────────────────────────────
// Receiver process
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
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

@target(erlang)
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

@target(erlang)
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

@target(erlang)
fn handle(state: State, msg: Msg) -> actor.Next(State, Msg) {
  case msg {
    Heartbeat -> {
      let _ = process.send_after(state.self, heartbeat_interval_ms, Heartbeat)
      case state.phase, state.channel {
        Ready(core, None), Some(channel) ->
          push(
            channel,
            "noop",
            socket.encode_noop(
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
        socket.encode_connect_document(state.connect_message, last_seen),
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

    Put(address, key, value) ->
      edit(state, fn(core) { runtime_core.set(core, address, key, value) })
    Remove(address, key) ->
      edit(state, fn(core) { runtime_core.delete(core, address, key) })
    RemoveAll(address) ->
      edit(state, fn(core) { runtime_core.clear(core, address) })

    CreateMap(reply) ->
      case state.phase {
        Ready(core, resubmit_at) -> {
          let address = ids.uuid_v4()
          let core = runtime_core.create_detached(core, address)
          process.send(reply, Ok(address))
          actor.continue(State(..state, phase: Ready(core, resubmit_at)))
        }
        Reconnecting(core) -> {
          let address = ids.uuid_v4()
          let core = runtime_core.create_detached(core, address)
          process.send(reply, Ok(address))
          actor.continue(State(..state, phase: Reconnecting(core)))
        }
        _ -> {
          process.send(
            reply,
            Error("create_map requires a ready document connection"),
          )
          actor.continue(state)
        }
      }

    ResolveAddress(address, reply) -> {
      let known = read(state, False, runtime_core.has_channel(_, address))
      let result = case known {
        True -> Ok(Nil)
        False ->
          Error(
            "unresolved handle: no channel at address "
            <> address
            <> " (a foreign attach may still be in flight; retry)",
          )
      }
      process.send(reply, result)
      actor.continue(state)
    }

    Summarize(reply) -> handle_summarize(state, reply)

    GetVersions(count, reply) -> {
      process.send(reply, fetch_document_versions(state, count))
      actor.continue(state)
    }
    LoadVersion(handle, reply) -> {
      process.send(reply, fetch_version_blob(state, handle))
      actor.continue(state)
    }

    GetValue(address, key, reply) -> {
      process.send(reply, read(state, None, runtime_core.get(_, address, key)))
      actor.continue(state)
    }
    GetEntries(address, reply) -> {
      process.send(reply, read(state, [], runtime_core.entries(_, address)))
      actor.continue(state)
    }
    GetKeys(address, reply) -> {
      process.send(reply, read(state, [], runtime_core.keys(_, address)))
      actor.continue(state)
    }
    GetSize(address, reply) -> {
      process.send(reply, read(state, 0, runtime_core.size(_, address)))
      actor.continue(state)
    }
    IsSynced(reply) -> {
      process.send(reply, read(state, False, runtime_core.is_synced))
      actor.continue(state)
    }

    Subscribe(address, subscriber) ->
      actor.continue(
        State(..state, subscribers: [
          #(address, subscriber),
          ..state.subscribers
        ]),
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

@target(erlang)
fn handle_inbound(state: State, incoming: Incoming) -> actor.Next(State, Msg) {
  case incoming.event {
    "connect_document_success" -> {
      let connected =
        require(
          decode.run(incoming.payload, socket.connected_message_decoder()),
          "connect_document_success payload",
        )
      case state.phase {
        Connecting(_) -> {
          let summary = case connected.summary_context {
            None -> None
            Some(ctx) ->
              case fetch_summary(state, ctx) {
                Ok(summary) -> Some(summary)
                Error(reason) -> panic as { "summary load failed: " <> reason }
              }
          }
          case runtime_core.bootstrap(connected, summary: summary) {
            Ok(bootstrapped) -> {
              let core = complete_bootstrap(state, bootstrapped)
              notify_waiters(state.phase, Ok(Nil))
              actor.continue(State(..state, phase: Ready(core, None)))
            }
            Error(core_error) ->
              panic as { "bootstrap failed: " <> string.inspect(core_error) }
          }
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
          decode.run(incoming.payload, socket.connect_error_decoder()),
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
          decode.run(incoming.payload, socket.nacks_decoder()),
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

@target(erlang)
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

@target(erlang)
fn op_message(incoming: Incoming) -> List(SequencedDocumentMessage) {
  let message =
    require(
      decode.run(incoming.payload, socket.op_message_decoder()),
      "op payload",
    )
  message.ops
}

@target(erlang)
fn apply_ops(
  core: runtime_core.Core,
  ops: List(SequencedDocumentMessage),
) -> #(runtime_core.Core, List(#(String, MapEvent)), Option(Int)) {
  do_apply_ops(core, ops, [], None)
}

@target(erlang)
fn do_apply_ops(
  core: runtime_core.Core,
  ops: List(SequencedDocumentMessage),
  events: List(List(#(String, MapEvent))),
  request_from: Option(Int),
) -> #(runtime_core.Core, List(#(String, MapEvent)), Option(Int)) {
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

@target(erlang)
fn edit(
  state: State,
  operate: fn(runtime_core.Core) ->
    Result(
      #(runtime_core.Core, List(#(String, MapEvent)), List(wire.OutboundOp)),
      runtime_core.CoreError,
    ),
) -> actor.Next(State, Msg) {
  case state.phase {
    Ready(core, resubmit_at) -> {
      case operate(core) {
        Error(core_error) ->
          panic as { "local edit failed: " <> string.inspect(core_error) }
        Ok(#(core, events, outbound)) -> {
          // Push immediately only when fully synced with a live channel;
          // otherwise the op stays in-flight and `resubmit` sends it once, so a
          // reconnect can't drop or duplicate it.
          case resubmit_at, state.channel {
            None, Some(channel) ->
              send_outbound(Some(channel), core.client_id, outbound)
            _, _ -> Nil
          }
          fan_out(state.subscribers, events)
          actor.continue(State(..state, phase: Ready(core, resubmit_at)))
        }
      }
    }
    Reconnecting(core) -> {
      case operate(core) {
        Error(core_error) ->
          panic as { "local edit failed: " <> string.inspect(core_error) }
        Ok(#(core, events, _outbound)) -> {
          fan_out(state.subscribers, events)
          actor.continue(State(..state, phase: Reconnecting(core)))
        }
      }
    }
    // Edits are only reachable through handles returned after await_ready,
    // so this is either a race with a failure or API misuse.
    _ -> panic as "edit before the document connection is ready"
  }
}

@target(erlang)
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

@target(erlang)
/// Enter the reconnecting phase after a channel close: drop the dead channel
/// and spawn a fresh receiver, which will re-handshake with our last-seen SN.
fn begin_reconnect(state: State, core: runtime_core.Core) -> State {
  spawn_receiver(state, state.self)
  State(..state, channel: None, phase: Reconnecting(core))
}

@target(erlang)
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

@target(erlang)
fn nack_is_fatal(item: Nack) -> Bool {
  case item.content.error_type {
    nack.InvalidScopeError -> True
    nack.LimitExceededError -> True
    _ -> item.content.code == 413
  }
}

@target(erlang)
fn maybe_request_ops(
  channel: Option(Channel),
  request_from: Option(Int),
) -> Nil {
  case channel, request_from {
    Some(channel), Some(from) ->
      push(channel, "requestOps", socket.encode_request_ops(from: from))
    _, _ -> Nil
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Summaries
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
fn handle_summarize(
  state: State,
  reply: Subject(Result(String, String)),
) -> actor.Next(State, Msg) {
  // Summarizing is only well-defined while fully synced with a live channel:
  // the confirmed state is stable and the summarize op can go out immediately.
  case state.phase, state.channel {
    Ready(core, None), Some(channel) ->
      case do_summarize(state, core, channel) {
        Ok(#(core, tree_sha)) -> {
          process.send(reply, Ok(tree_sha))
          actor.continue(State(..state, phase: Ready(core, None)))
        }
        Error(reason) -> {
          process.send(reply, Error(reason))
          actor.continue(state)
        }
      }
    _, _ -> {
      process.send(
        reply,
        Error("summarize is only available once the connection is fully synced"),
      )
      actor.continue(state)
    }
  }
}

@target(erlang)
/// Upload the confirmed state as a summary blob, then stamp and push the
/// summarize op referencing it. Returns the updated core and the tree SHA.
fn do_summarize(
  state: State,
  core: runtime_core.Core,
  channel: Channel,
) -> Result(#(runtime_core.Core, String), String) {
  use token <- result.try(option.to_result(
    state.connect_message.token,
    "summarize requires an auth token",
  ))
  use _ <- result.try(case runtime_core.is_synced(core) {
    True -> Ok(Nil)
    False ->
      Error(
        "summarize requires the client to be caught up; retry once "
        <> "in-flight edits have been acknowledged",
      )
  })
  use tree_sha <- result.try(git_storage.upload_summary(
    base_url: http_base_url(state),
    tenant: state.connect_message.tenant_id,
    token: token,
    sequence_number: core.last_seen_sn,
    channels: runtime_core.summary_channels(core),
  ))
  let #(core, outbound) =
    runtime_core.build_summarize(
      core,
      handle: tree_sha,
      message: "watershed summary",
      head: tree_sha,
    )
  push(
    channel,
    "submitOp",
    socket.encode_submit_op(core.client_id, [[outbound]]),
  )
  Ok(#(core, tree_sha))
}

@target(erlang)
/// Close any gap between the bootstrap seed point and the earliest op the
/// server pushed in-band by paging the missing prefix from the deltas REST
/// endpoint until the history is contiguous. Bootstrap must not complete on
/// a gapped history, so any failure here is fatal.
fn complete_bootstrap(
  state: State,
  bootstrapped: runtime_core.Bootstrapped,
) -> runtime_core.Core {
  case bootstrapped {
    runtime_core.Complete(core) -> core
    runtime_core.MissingPrefix(core, checkpoint, from, to) -> {
      let deltas = case fetch_missing_deltas(state, from, to) {
        Ok(deltas) -> deltas
        Error(reason) -> panic as { "history catch-up failed: " <> reason }
      }
      case
        runtime_core.resume_bootstrap(
          core,
          checkpoint: checkpoint,
          deltas: deltas,
        )
      {
        Ok(next) -> complete_bootstrap(state, next)
        Error(core_error) ->
          panic as { "bootstrap failed: " <> string.inspect(core_error) }
      }
    }
  }
}

@target(erlang)
fn fetch_missing_deltas(
  state: State,
  from: Int,
  to: Int,
) -> Result(List(SequencedDocumentMessage), String) {
  case state.connect_message.token {
    None -> Error("history catch-up requires an auth token")
    Some(token) ->
      git_storage.fetch_deltas(
        base_url: http_base_url(state),
        tenant: state.connect_message.tenant_id,
        token: token,
        document: state.connect_message.document_id,
        from: from,
        to: to,
      )
  }
}

@target(erlang)
fn fetch_document_versions(
  state: State,
  count: Int,
) -> Result(List(git_storage.SummaryVersion), String) {
  case state.connect_message.token {
    None -> Error("listing versions requires an auth token")
    Some(token) ->
      git_storage.fetch_versions(
        base_url: http_base_url(state),
        tenant: state.connect_message.tenant_id,
        token: token,
        document: state.connect_message.document_id,
        count: count,
      )
  }
}

@target(erlang)
fn fetch_version_blob(
  state: State,
  handle: String,
) -> Result(summary_blob.SummaryBlob, String) {
  case state.connect_message.token {
    None -> Error("loading a version requires an auth token")
    Some(token) ->
      git_storage.fetch_summary(
        base_url: http_base_url(state),
        tenant: state.connect_message.tenant_id,
        token: token,
        handle: handle,
      )
  }
}

@target(erlang)
fn fetch_summary(
  state: State,
  ctx: SummaryContext,
) -> Result(runtime_core.Summary, String) {
  case state.connect_message.token {
    None -> Error("loading a summarized document requires an auth token")
    Some(token) ->
      git_storage.fetch_summary(
        base_url: http_base_url(state),
        tenant: state.connect_message.tenant_id,
        token: token,
        handle: ctx.handle,
      )
      |> result.map(fn(blob) {
        // The summary blob records the SN it was captured at, but the
        // authoritative load point is the server's summaryContext.
        let channels =
          list.map(blob.channels, fn(ch) { #(ch.address, ch.entries) })
        runtime_core.Summary(
          sequence_number: ctx.sequence_number,
          channels: channels,
        )
      })
  }
}

@target(erlang)
/// The HTTP(S) base URL for git-storage calls, derived from the socket host
/// and port. levee serves both the Phoenix socket and the REST API from the
/// same origin.
fn http_base_url(state: State) -> String {
  "http://" <> state.host <> ":" <> int.to_string(state.port)
}

@target(erlang)
fn send_outbound(
  channel: Option(Channel),
  client_id: String,
  outbound: List(wire.OutboundOp),
) -> Nil {
  case channel, outbound {
    _, [] -> Nil
    Some(channel), _ ->
      list.each(list.sized_chunk(outbound, max_ops_per_submission), fn(chunk) {
        push(channel, "submitOp", socket.encode_submit_op(client_id, [chunk]))
      })
    None, _ -> Nil
  }
}

@target(erlang)
fn push(channel: Channel, event: String, payload: Json) -> Nil {
  case aquamarine.push(channel, event, payload) {
    Ok(Nil) -> Nil
    Error(err) -> panic as { "channel push failed: " <> string.inspect(err) }
  }
}

@target(erlang)
/// Route each address-tagged event to the subscribers registered for that
/// channel address.
fn fan_out(
  subscribers: List(#(String, Subject(MapEvent))),
  events: List(#(String, MapEvent)),
) -> Nil {
  list.each(events, fn(event) {
    let #(address, event) = event
    list.each(subscribers, fn(subscriber) {
      case subscriber.0 == address {
        True -> process.send(subscriber.1, event)
        False -> Nil
      }
    })
  })
}

@target(erlang)
fn fail(state: State, reason: String) -> State {
  notify_waiters(state.phase, Error(reason))
  State(..state, phase: Failed(reason))
}

@target(erlang)
fn notify_waiters(phase: Phase, result: Result(Nil, String)) -> Nil {
  case phase {
    Connecting(waiters) -> list.each(waiters, process.send(_, result))
    _ -> Nil
  }
}

@target(erlang)
fn require(result: Result(t, e), context: String) -> t {
  case result {
    Ok(value) -> value
    Error(err) ->
      panic as { "failed to decode " <> context <> ": " <> string.inspect(err) }
  }
}
