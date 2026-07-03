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
  type ConnectMessage, type ConnectedMessage, type SummaryContext,
}
@target(javascript)
import spillway/nack.{type Nack}
@target(javascript)
import spillway/types.{type SequencedDocumentMessage}

@target(javascript)
import watershed/channel.{type ChannelEvent}
@target(javascript)
import watershed/git_storage
@target(javascript)
import watershed/ids
@target(javascript)
import watershed/runtime_core
@target(javascript)
import watershed/transport_js.{type Cell, type Channel}
@target(javascript)
import watershed/wire
@target(javascript)
import watershed/wire/socket
@target(javascript)
import watershed/wire/summary_blob

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
    /// HTTP(S) base URL for git-storage (summary) calls, derived from the
    /// Phoenix socket URL. levee serves both the socket and REST from one
    /// origin.
    http_base_url: String,
    channel: Option(Channel),
    phase: Phase,
    subscribers: List(#(String, fn(ChannelEvent) -> Nil)),
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
      http_base_url: http_base_from_socket_url(url),
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
/// Create a new detached map channel: local-only until its handle is first
/// stored into an attached map. Returns the generated address.
pub fn create_map(runtime: Runtime) -> Result(String, String) {
  let state = cell_get(runtime.cell)
  case state.phase {
    Ready(core, resubmit_at) -> {
      let address = ids.uuid_v4()
      let core = runtime_core.create_detached(core, address, channel.MapChannel)
      cell_set(runtime.cell, State(..state, phase: Ready(core, resubmit_at)))
      Ok(address)
    }
    Reconnecting(core) -> {
      let address = ids.uuid_v4()
      let core = runtime_core.create_detached(core, address, channel.MapChannel)
      cell_set(runtime.cell, State(..state, phase: Reconnecting(core)))
      Ok(address)
    }
    _ -> Error("create_map requires a ready document connection")
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

@target(javascript)
/// Whether the document is fully caught up: every local edit has been
/// acknowledged by the server, so the confirmed state is complete and stable.
pub fn is_synced(runtime: Runtime) -> Bool {
  read(runtime.cell, False, runtime_core.is_synced)
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
            Ok(#(core, events, request_from)) -> {
              // Commit the new core before fan-out (see fan_out's contract).
              case resubmit_at {
                Some(checkpoint) -> settle_reconnect(cell, core, checkpoint)
                None -> cell_set(cell, State(..state, phase: Ready(core, None)))
              }
              fan_out(state.subscribers, events)
              maybe_request_ops(state.channel, request_from)
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
) -> Result(
  #(runtime_core.Core, List(#(String, ChannelEvent)), Option(Int)),
  runtime_core.CoreError,
) {
  do_apply_ops(core, ops, [], None)
}

@target(javascript)
fn do_apply_ops(
  core: runtime_core.Core,
  ops: List(SequencedDocumentMessage),
  events: List(List(#(String, ChannelEvent))),
  request_from: Option(Int),
) -> Result(
  #(runtime_core.Core, List(#(String, ChannelEvent)), Option(Int)),
  runtime_core.CoreError,
) {
  case ops {
    [] -> Ok(#(core, list.reverse(events) |> list.flatten, request_from))
    [op, ..rest] ->
      case runtime_core.handle_sequenced(core, op) {
        Ok(#(core, ingested)) ->
          do_apply_ops(
            core,
            rest,
            [ingested.events, ..events],
            option.or(request_from, ingested.request_ops_from),
          )
        Error(core_error) -> Error(core_error)
      }
  }
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
    socket.encode_connect_document(connect_message, last_seen),
  )
}

@target(javascript)
fn maybe_request_ops(
  channel: Option(Channel),
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
          socket.encode_submit_op(client_id, [chunk]),
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
