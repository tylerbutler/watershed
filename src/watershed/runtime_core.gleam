//// Pure per-connection state machine, driven by the runtime actor.
////
//// Owns the client half of spillway's sequencing discipline: CSN strictly
//// increasing per connection, RSN = last seen sequence number, dedupe by SN,
//// FIFO ack matching, and optimistic local state for attached and detached
//// channels. Kernel state, ops, and events (map/counter/OR-map/registers/
//// claims) flow through the closed sums in `watershed/channel`; the
//// sequencing discipline itself is kernel-agnostic.

import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/string

import spillway/message.{type ConnectedMessage}
import spillway/types.{type SequencedDocumentMessage}

import watershed/channel.{
  type ChannelEvent, type ChannelState, type Resolution, type Snapshot,
  SequencedMeta,
}
import watershed/claims_kernel
import watershed/client_id
import watershed/counter_kernel
import watershed/directory_kernel
import watershed/g_set_kernel
import watershed/handle
import watershed/json_ot
import watershed/json_ot_kernel
import watershed/map_kernel
import watershed/or_map_kernel
import watershed/or_set_kernel
import watershed/pact_map_kernel
import watershed/pn_counter_kernel
import watershed/register_collection_kernel
import watershed/task_manager_kernel
import watershed/two_p_set_kernel
import watershed/wire
import watershed/wire/ops

const root_address = "root"

pub type Core {
  Core(
    client_id: String,
    channels: Dict(String, ChannelState),
    channel_order: List(String),
    detached: Dict(String, ChannelState),
    next_csn: Int,
    last_seen_sn: Int,
    in_flight: List(InFlight),
    out_of_order: List(SequencedDocumentMessage),
    /// Per-channel buffer of *owed* follow-up ops a kernel released while
    /// applying a sequenced op (e.g. a consensus `Accept` reacting to a peer's
    /// `Set`). Drained after each sequenced batch by `collect_released_ops`,
    /// which stamps each with a fresh CSN + in-flight entry and hands it to the
    /// actor loop to submit. Generic across kernels — any `channel.apply_remote`
    /// arm can enqueue by returning owed ops.
    owed: Dict(String, List(channel.ChannelOp)),
  )
}

pub type InFlight {
  InFlightOp(
    client_id: String,
    csn: Int,
    address: String,
    op: channel.ChannelOp,
    meta: channel.LocalOpMeta,
  )
  InFlightAttach(
    client_id: String,
    csn: Int,
    address: String,
    snapshot: Snapshot,
  )
}

pub type CoreError {
  AckMismatch(detail: String)
  BadOpContents(sequence_number: Int)
  HistoryGap(detail: String)
  UnknownChannel(address: String, sequence_number: Int)
  DuplicateAttach(address: String, sequence_number: Int)
  /// A local edit used a verb for one channel type on a channel of another
  /// (e.g. `set` on a counter). Retryable API misuse, not document corruption.
  WrongChannelType(
    address: String,
    expected: channel.ChannelType,
    actual: channel.ChannelType,
  )
  OrMapModeMismatch(address: String, detail: String)
  TaskNotAssigned(address: String, task_id: String)
  /// A directory edit was rejected by the kernel (unknown path, invalid
  /// subdirectory name). Retryable API misuse, not document corruption.
  DirectoryOpFailed(address: String, detail: String)
}

pub type Bootstrapped {
  Complete(core: Core)
  MissingPrefix(core: Core, checkpoint: Int, from: Int, to: Int)
}

pub type Ingested {
  Ingested(
    events: List(#(String, ChannelEvent)),
    resolutions: List(#(String, Resolution)),
    request_ops_from: Option(Int),
    /// Ops a single-in-flight kernel (json0) released onto the wire while its
    /// own op was being acked. The actor loop must submit these.
    outbound: List(wire.OutboundOp),
  )
}

pub type Summary {
  Summary(sequence_number: Int, channels: List(#(String, Snapshot)))
}

// ─────────────────────────────────────────────────────────────────────────────
// Bootstrap
// ─────────────────────────────────────────────────────────────────────────────

pub fn bootstrap(
  connected: ConnectedMessage,
  summary summary: Option(Summary),
) -> Result(Bootstrapped, CoreError) {
  let Summary(sequence_number: last_seen, channels: seeded) =
    option.unwrap(summary, Summary(sequence_number: 0, channels: []))
  let #(channels, channel_order) = seed_channels(seeded, connected.client_id)

  let core =
    Core(
      client_id: connected.client_id,
      channels: channels,
      channel_order: channel_order,
      detached: dict.new(),
      next_csn: 1,
      last_seen_sn: last_seen,
      in_flight: [],
      out_of_order: [],
      owed: dict.new(),
    )

  use core <- result.try(replay(core, connected.initial_messages))
  let checkpoint =
    option.unwrap(connected.checkpoint_sequence_number, core.last_seen_sn)
  Ok(settle_bootstrap(core, checkpoint))
}

pub fn resume_bootstrap(
  core: Core,
  checkpoint checkpoint: Int,
  deltas deltas: List(SequencedDocumentMessage),
) -> Result(Bootstrapped, CoreError) {
  let before = core.last_seen_sn
  use core <- result.try(replay(core, deltas))
  case core.out_of_order != [] && core.last_seen_sn == before {
    True ->
      Error(HistoryGap(
        "history catch-up made no progress past sequence number "
        <> int.to_string(before)
        <> " (server storage is missing the range)",
      ))
    False -> Ok(settle_bootstrap(core, checkpoint))
  }
}

fn replay(
  core: Core,
  messages: List(SequencedDocumentMessage),
) -> Result(Core, CoreError) {
  list.try_fold(messages, core, fn(core, msg) {
    handle_sequenced(core, msg)
    |> result.map(fn(outcome) { outcome.0 })
  })
}

fn settle_bootstrap(core: Core, checkpoint: Int) -> Bootstrapped {
  case core.out_of_order {
    [] ->
      Complete(
        Core(..core, last_seen_sn: int.max(core.last_seen_sn, checkpoint)),
      )
    [head, ..] ->
      MissingPrefix(
        core: core,
        checkpoint: checkpoint,
        from: core.last_seen_sn,
        to: head.sequence_number - 1,
      )
  }
}

pub fn summary_channels(core: Core) -> List(#(String, Snapshot)) {
  list.filter_map(core.channel_order, fn(address) {
    case dict.get(core.channels, address) {
      Ok(state) -> Ok(#(address, channel.snapshot(state)))
      Error(_) -> Error(Nil)
    }
  })
}

pub fn is_synced(core: Core) -> Bool {
  core.in_flight == []
}

pub fn build_summarize(
  core: Core,
  handle handle: String,
  message message: String,
  head head: String,
) -> #(Core, wire.OutboundOp) {
  let csn = core.next_csn
  let outbound =
    ops.outbound_summarize_op(
      client_sequence_number: csn,
      reference_sequence_number: core.last_seen_sn,
      handle: handle,
      message: message,
      parents: [],
      head: head,
    )
  #(Core(..core, next_csn: csn + 1), outbound)
}

fn seed_channels(
  seeded: List(#(String, Snapshot)),
  replica replica: String,
) -> #(Dict(String, ChannelState), List(String)) {
  let #(channels, channel_order) =
    list.fold(seeded, #(dict.new(), []), fn(acc, entry) {
      let #(channels, channel_order) = acc
      let #(address, snapshot) = entry
      #(
        dict.insert(
          channels,
          address,
          channel.from_snapshot(snapshot, replica: replica),
        ),
        list.unique(list.append(channel_order, [address])),
      )
    })

  case dict.has_key(channels, root_address) {
    True -> #(channels, channel_order)
    False -> #(
      dict.insert(
        channels,
        root_address,
        channel.new(channel.InitMap, replica: replica),
      ),
      [root_address, ..channel_order],
    )
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reconnect
// ─────────────────────────────────────────────────────────────────────────────

pub fn adopt_reconnect(core: Core, connected: ConnectedMessage) -> Core {
  Core(..core, client_id: connected.client_id)
}

pub fn resubmit(core: Core) -> #(Core, List(wire.OutboundOp)) {
  let #(core, next_csn, new_in_flight, outbound) =
    list.fold(core.in_flight, #(core, core.next_csn, [], []), fn(acc, entry) {
      let #(core, csn, entries, outbounds) = acc
      let #(core, next_csn, restamped, outbound) =
        restamp_in_flight(core, entry, csn)
      #(
        core,
        next_csn,
        list.append(entries, restamped),
        list.append(outbounds, outbound),
      )
    })

  #(Core(..core, next_csn: next_csn, in_flight: new_in_flight), outbound)
}

fn restamp_in_flight(
  core: Core,
  entry: InFlight,
  csn: Int,
) -> #(Core, Int, List(InFlight), List(wire.OutboundOp)) {
  case entry {
    InFlightOp(address: address, op: channel.TaskManagerOp(op), meta: meta, ..) ->
      restamp_task_manager(core, address, op, meta, csn)
    InFlightOp(address: address, op: channel.DirectoryOp(op, message_id), ..) ->
      restamp_directory(core, address, op, message_id, csn)
    InFlightOp(address: address, op: op, meta: meta, ..) -> #(
      core,
      csn + 1,
      [
        InFlightOp(
          client_id: core.client_id,
          csn: csn,
          address: address,
          op: op,
          meta: meta,
        ),
      ],
      [
        ops.outbound_channel_op(
          address: address,
          client_sequence_number: csn,
          reference_sequence_number: core.last_seen_sn,
          op: op,
        ),
      ],
    )
    InFlightAttach(address: address, snapshot: snapshot, ..) -> #(
      core,
      csn + 1,
      [
        InFlightAttach(
          client_id: core.client_id,
          csn: csn,
          address: address,
          snapshot: snapshot,
        ),
      ],
      [
        ops.outbound_attach_op(
          address: address,
          client_sequence_number: csn,
          reference_sequence_number: core.last_seen_sn,
          snapshot: snapshot,
        ),
      ],
    )
  }
}

fn restamp_task_manager(
  core: Core,
  address: String,
  op: task_manager_kernel.TaskManagerOp,
  meta: channel.LocalOpMeta,
  csn: Int,
) -> #(Core, Int, List(InFlight), List(wire.OutboundOp)) {
  case meta, dict.get(core.channels, address) {
    channel.TaskManagerMeta(message_id), Ok(channel.TaskManagerState(kernel)) -> {
      case task_manager_kernel.resubmit(kernel, op, message_id, csn) {
        Ok(#(kernel, Some(next_op), Some(pending))) -> {
          let next_channel_op = channel.TaskManagerOp(next_op)
          let next_meta = channel.TaskManagerMeta(pending.message_id)
          let core =
            put_attached_channel(
              core,
              address,
              channel.TaskManagerState(kernel),
            )
          #(
            core,
            csn + 1,
            [
              InFlightOp(
                client_id: core.client_id,
                csn: csn,
                address: address,
                op: next_channel_op,
                meta: next_meta,
              ),
            ],
            [
              ops.outbound_channel_op(
                address: address,
                client_sequence_number: csn,
                reference_sequence_number: core.last_seen_sn,
                op: next_channel_op,
              ),
            ],
          )
        }
        Ok(#(kernel, None, None)) -> {
          let core =
            put_attached_channel(
              core,
              address,
              channel.TaskManagerState(kernel),
            )
          #(core, csn, [], [])
        }
        Ok(#(_, _, _)) ->
          panic as "task-manager resubmit returned inconsistent op metadata"
        Error(err) ->
          panic as { "task-manager resubmit failed: " <> string.inspect(err) }
      }
    }
    _, _ -> panic as "task-manager resubmit missing channel state or metadata"
  }
}

/// Re-stamp a directory op on reconnect. `directory_kernel.resubmit` filters
/// the op against the current live instance of its target path: a `Some` op is
/// re-sent (possibly rewritten — a create resubmit re-adds this client's
/// creator id), a `None` means the target instance no longer exists and the op
/// is dropped, with the kernel stripping its now-orphaned pending entry.
fn restamp_directory(
  core: Core,
  address: String,
  op: directory_kernel.DirectoryOp,
  message_id: Int,
  csn: Int,
) -> #(Core, Int, List(InFlight), List(wire.OutboundOp)) {
  case dict.get(core.channels, address) {
    Ok(channel.DirectoryState(kernel)) -> {
      let self = client_id_to_int(core.client_id)
      let #(kernel, maybe_op) =
        directory_kernel.resubmit(kernel, op, message_id, self)
      let core =
        put_attached_channel(core, address, channel.DirectoryState(kernel))
      case maybe_op {
        Some(next_op) -> {
          let next_channel_op = channel.DirectoryOp(next_op, message_id)
          #(
            core,
            csn + 1,
            [
              InFlightOp(
                client_id: core.client_id,
                csn: csn,
                address: address,
                op: next_channel_op,
                meta: channel.DirectoryMeta(message_id),
              ),
            ],
            [
              ops.outbound_channel_op(
                address: address,
                client_sequence_number: csn,
                reference_sequence_number: core.last_seen_sn,
                op: next_channel_op,
              ),
            ],
          )
        }
        None -> #(core, csn, [], [])
      }
    }
    _ -> panic as "directory resubmit missing channel state"
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Inbound
// ─────────────────────────────────────────────────────────────────────────────

pub fn handle_sequenced(
  core: Core,
  msg: SequencedDocumentMessage,
) -> Result(#(Core, Ingested), CoreError) {
  let next = core.last_seen_sn + 1
  case msg.sequence_number {
    sn if sn < next -> Ok(#(core, Ingested([], [], None, [])))
    sn if sn > next -> {
      let request = case core.out_of_order {
        [] -> Some(core.last_seen_sn)
        _ -> None
      }
      let core =
        Core(..core, out_of_order: buffer_insert(core.out_of_order, msg))
      Ok(#(core, Ingested([], [], request, [])))
    }
    _ -> {
      use #(core, events, resolutions) <- result.try(apply_one(core, msg))
      use #(core, drained, drained_resolutions) <- result.try(drain_buffer(core))
      // A single-in-flight kernel (json0) may have promoted a buffered op to
      // the wire while acking its own op; collect and stamp those now, after
      // every op in this batch has been applied and rebased.
      let #(core, outbound) = collect_released_ops(core)
      Ok(#(
        core,
        Ingested(
          events: list.append(events, drained),
          resolutions: list.append(resolutions, drained_resolutions),
          request_ops_from: None,
          outbound: outbound,
        ),
      ))
    }
  }
}

/// After a sequenced batch, drain every follow-up op a channel released for the
/// actor loop to auto-submit, stamping each with a fresh CSN + in-flight entry
/// so the ordinary ack path reclaims it. Two producers feed this:
///
///   1. the generic per-channel `owed` buffer (any `channel.apply_remote` arm
///      that returned owed ops — e.g. a consensus `Accept`), and
///   2. json0's single-in-flight kernel buffer promotion, drained via
///      `channel.take_outbound`.
///
/// Returns the stamped outbound ops in channel order (owed before kernel-buffer
/// within each channel).
fn collect_released_ops(core: Core) -> #(Core, List(wire.OutboundOp)) {
  list.fold(core.channel_order, #(core, []), fn(acc, address) {
    let #(core, outs) = acc
    let #(core, owed_outs) = drain_owed(core, address)
    let #(core, kernel_outs) = drain_kernel_outbound(core, address)
    #(core, list.append(outs, list.append(owed_outs, kernel_outs)))
  })
}

/// Drain the generic `owed` buffer for one channel, stamping each op.
fn drain_owed(core: Core, address: String) -> #(Core, List(wire.OutboundOp)) {
  case dict.get(core.owed, address) {
    Ok([_, ..] as ops) -> {
      let core = Core(..core, owed: dict.delete(core.owed, address))
      list.fold(ops, #(core, []), fn(acc, op) {
        let #(core, outs) = acc
        let #(core, out) = stamp_outbound(core, address, op)
        #(core, list.append(outs, [out]))
      })
    }
    _ -> #(core, [])
  }
}

/// Drain a json0 kernel's promoted buffer for one channel, stamping the op.
fn drain_kernel_outbound(
  core: Core,
  address: String,
) -> #(Core, List(wire.OutboundOp)) {
  case dict.get(core.channels, address) {
    Error(_) -> #(core, [])
    Ok(state) ->
      case channel.take_outbound(state) {
        #(_, None) -> #(core, [])
        #(state, Some(op)) -> {
          let core =
            Core(..core, channels: dict.insert(core.channels, address, state))
          let #(core, out) = stamp_outbound(core, address, op)
          #(core, [out])
        }
      }
  }
}

/// Stamp a released op with a fresh CSN, record an in-flight entry so the
/// ordinary ack path reclaims it, and build its outbound wire op.
fn stamp_outbound(
  core: Core,
  address: String,
  op: channel.ChannelOp,
) -> #(Core, wire.OutboundOp) {
  let csn = core.next_csn
  let outbound =
    ops.outbound_channel_op(
      address: address,
      client_sequence_number: csn,
      reference_sequence_number: core.last_seen_sn,
      op: op,
    )
  let core =
    Core(
      ..core,
      next_csn: csn + 1,
      in_flight: list.append(core.in_flight, [
        InFlightOp(
          client_id: core.client_id,
          csn: csn,
          address: address,
          op: op,
          meta: channel.NoMeta,
        ),
      ]),
    )
  #(core, outbound)
}

fn apply_one(
  core: Core,
  msg: SequencedDocumentMessage,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(#(String, Resolution))),
  CoreError,
) {
  let core = Core(..core, last_seen_sn: msg.sequence_number)
  case msg.message_type {
    "op" -> handle_op(core, msg)
    _ -> Ok(#(core, [], []))
  }
}

fn drain_buffer(
  core: Core,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(#(String, Resolution))),
  CoreError,
) {
  case core.out_of_order {
    [head, ..rest] if head.sequence_number <= core.last_seen_sn ->
      drain_buffer(Core(..core, out_of_order: rest))
    [head, ..rest] if head.sequence_number == core.last_seen_sn + 1 -> {
      use #(core, events, resolutions) <- result.try(apply_one(
        Core(..core, out_of_order: rest),
        head,
      ))
      use #(core, more, more_resolutions) <- result.try(drain_buffer(core))
      Ok(#(
        core,
        list.append(events, more),
        list.append(resolutions, more_resolutions),
      ))
    }
    _ -> Ok(#(core, [], []))
  }
}

fn buffer_insert(
  buffer: List(SequencedDocumentMessage),
  msg: SequencedDocumentMessage,
) -> List(SequencedDocumentMessage) {
  case buffer {
    [] -> [msg]
    [head, ..rest] ->
      case int.compare(msg.sequence_number, head.sequence_number) {
        order.Lt -> [msg, ..buffer]
        order.Eq -> buffer
        order.Gt -> [head, ..buffer_insert(rest, msg)]
      }
  }
}

fn handle_op(
  core: Core,
  msg: SequencedDocumentMessage,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(#(String, Resolution))),
  CoreError,
) {
  case ops.decode_op_contents(msg.contents) {
    Error(_) -> Error(BadOpContents(msg.sequence_number))
    Ok(ops.AttachOp(address, snapshot)) ->
      case is_own_op(core, msg.client_id) {
        True ->
          ack_own_attach(
            core,
            msg.client_id,
            msg.client_sequence_number,
            address,
            snapshot,
          )
        False -> remote_attach(core, msg.sequence_number, address, snapshot)
      }
    Ok(ops.ChannelOp(address, raw_contents)) ->
      // The op envelope carries no channel type; the registry is the
      // authoritative source, so decode against the addressed channel's own
      // grammar. Channels are always attached before their ops arrive.
      case dict.get(core.channels, address) {
        Error(_) -> Error(UnknownChannel(address, msg.sequence_number))
        Ok(state) ->
          case
            decode.run(
              raw_contents,
              ops.channel_op_decoder(channel.channel_type(state)),
            )
          {
            Error(_) -> Error(BadOpContents(msg.sequence_number))
            Ok(op) ->
              case is_own_op(core, msg.client_id) {
                True ->
                  ack_own_op(
                    core,
                    msg.client_id,
                    msg.client_sequence_number,
                    address,
                    state,
                    op,
                    msg.sequence_number,
                    msg.minimum_sequence_number,
                  )
                False ->
                  apply_remote_channel(
                    core,
                    msg.client_id,
                    msg.sequence_number,
                    msg.minimum_sequence_number,
                    msg.reference_sequence_number,
                    address,
                    state,
                    op,
                  )
              }
          }
      }
  }
}

fn is_own_op(core: Core, message_client_id: Option(String)) -> Bool {
  case message_client_id {
    None -> False
    Some(cid) ->
      cid == core.client_id
      || case core.in_flight {
        [head, ..] -> in_flight_client_id(head) == cid
        [] -> False
      }
  }
}

fn in_flight_client_id(entry: InFlight) -> String {
  case entry {
    InFlightOp(client_id: client_id, ..) -> client_id
    InFlightAttach(client_id: client_id, ..) -> client_id
  }
}

fn remote_attach(
  core: Core,
  sequence_number: Int,
  address: String,
  snapshot: Snapshot,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(#(String, Resolution))),
  CoreError,
) {
  case has_channel(core, address) {
    True -> Error(DuplicateAttach(address, sequence_number))
    False ->
      Ok(
        #(
          add_attached_channel(
            core,
            address,
            channel.from_snapshot(snapshot, replica: core.client_id),
          ),
          [],
          [],
        ),
      )
  }
}

fn apply_remote_channel(
  core: Core,
  message_client_id: Option(String),
  sequence_number: Int,
  minimum_sequence_number: Int,
  reference_sequence_number: Int,
  address: String,
  state: ChannelState,
  op: channel.ChannelOp,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(#(String, Resolution))),
  CoreError,
) {
  let meta =
    SequencedMeta(
      seq: sequence_number,
      last_seen_sn: core.last_seen_sn,
      min_seq: minimum_sequence_number,
      author: option.map(message_client_id, client_id_to_int)
        |> option.unwrap(0),
      self: client_id_to_int(core.client_id),
      quorum: [
        client_id_to_int(core.client_id),
        option.map(message_client_id, client_id_to_int) |> option.unwrap(0),
      ],
      reference_sequence_number: reference_sequence_number,
    )
  case channel.apply_remote(state, op, meta) {
    Ok(#(state, events, owed)) ->
      Ok(
        #(
          enqueue_owed(
            put_attached_channel(core, address, state),
            address,
            owed,
          ),
          tag_events(address, events),
          [],
        ),
      )
    Error(channel.UnexpectedAck(detail))
    | Error(channel.WrongChannelType(detail))
    | Error(channel.CorruptRemoteOp(detail)) -> Error(AckMismatch(detail))
  }
}

/// Enqueue owed follow-up ops a kernel released while applying a sequenced op,
/// keyed by channel address, for `collect_released_ops` to stamp and submit
/// after the current batch. Exposed so tests can drive the generic buffer
/// without a producing kernel.
pub fn enqueue_owed(
  core: Core,
  address: String,
  owed: List(channel.ChannelOp),
) -> Core {
  case owed {
    [] -> core
    _ -> {
      let existing = dict.get(core.owed, address) |> result.unwrap([])
      Core(
        ..core,
        owed: dict.insert(core.owed, address, list.append(existing, owed)),
      )
    }
  }
}

fn ack_own_attach(
  core: Core,
  message_client_id: Option(String),
  csn: Int,
  address: String,
  echoed: Snapshot,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(#(String, Resolution))),
  CoreError,
) {
  case core.in_flight {
    [] ->
      Error(AckMismatch(
        "own attach sequenced with csn "
        <> int.to_string(csn)
        <> " but in-flight queue is empty",
      ))
    [head, ..rest] ->
      case head {
        InFlightAttach(
          client_id: client_id,
          csn: head_csn,
          address: head_address,
          snapshot: snapshot,
        ) ->
          case
            Some(client_id) == message_client_id
            && head_csn == csn
            && head_address == address
            && channel.same_snapshot(snapshot, echoed)
          {
            True -> Ok(#(Core(..core, in_flight: rest), [], []))
            False ->
              Error(AckMismatch(
                "expected attach ack for csn "
                <> int.to_string(head_csn)
                <> ", got csn "
                <> int.to_string(csn),
              ))
          }
        InFlightOp(csn: head_csn, ..) ->
          Error(AckMismatch(
            "expected channel op ack for csn "
            <> int.to_string(head_csn)
            <> ", got attach ack for csn "
            <> int.to_string(csn),
          ))
      }
  }
}

fn ack_own_op(
  core: Core,
  message_client_id: Option(String),
  csn: Int,
  address: String,
  state: ChannelState,
  echoed: channel.ChannelOp,
  sequence_number: Int,
  minimum_sequence_number: Int,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(#(String, Resolution))),
  CoreError,
) {
  case core.in_flight {
    [] ->
      Error(AckMismatch(
        "own op sequenced with csn "
        <> int.to_string(csn)
        <> " but in-flight queue is empty",
      ))
    [head, ..rest] ->
      case head {
        InFlightOp(
          client_id: client_id,
          csn: head_csn,
          address: head_address,
          op: op,
          meta: meta,
        ) ->
          case
            Some(client_id) == message_client_id
            && head_csn == csn
            && head_address == address
            && channel.same_shape(op, echoed)
          {
            False ->
              Error(AckMismatch(
                "expected ack for csn "
                <> int.to_string(head_csn)
                <> ", got csn "
                <> int.to_string(csn),
              ))
            True -> {
              let sequenced_meta =
                SequencedMeta(
                  seq: sequence_number,
                  last_seen_sn: core.last_seen_sn,
                  min_seq: minimum_sequence_number,
                  author: client_id_to_int(core.client_id),
                  self: client_id_to_int(core.client_id),
                  quorum: [client_id_to_int(core.client_id)],
                  reference_sequence_number: core.last_seen_sn,
                )
              case channel.applies_own_on_sequence(state) {
                // Consensus kernels (PactMap) take effect only on sequencing,
                // regardless of author. Reclaim the in-flight entry here, then
                // apply the op through the same `apply_remote` path a remote
                // client would, capturing any owed follow-up (e.g. an Accept).
                True ->
                  case channel.apply_remote(state, op, sequenced_meta) {
                    Ok(#(state, events, owed)) ->
                      Ok(
                        #(
                          enqueue_owed(
                            Core(
                              ..core,
                              channels: dict.insert(
                                core.channels,
                                address,
                                state,
                              ),
                              in_flight: rest,
                            ),
                            address,
                            owed,
                          ),
                          tag_events(address, events),
                          [],
                        ),
                      )
                    Error(channel.UnexpectedAck(detail))
                    | Error(channel.WrongChannelType(detail))
                    | Error(channel.CorruptRemoteOp(detail)) ->
                      Error(AckMismatch(detail))
                  }
                False ->
                  case channel.ack_local(state, op, meta, sequenced_meta) {
                    Ok(#(state, events, resolution)) ->
                      Ok(#(
                        Core(
                          ..core,
                          channels: dict.insert(core.channels, address, state),
                          in_flight: rest,
                        ),
                        tag_events(address, events),
                        tag_resolution(address, resolution),
                      ))
                    Error(channel.UnexpectedAck(detail))
                    | Error(channel.WrongChannelType(detail))
                    | Error(channel.CorruptRemoteOp(detail)) ->
                      Error(AckMismatch(detail))
                  }
              }
            }
          }
        InFlightAttach(csn: head_csn, ..) ->
          Error(AckMismatch(
            "expected attach ack for csn "
            <> int.to_string(head_csn)
            <> ", got channel op ack for csn "
            <> int.to_string(csn),
          ))
      }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Outbound
// ─────────────────────────────────────────────────────────────────────────────

pub fn create_detached(
  core: Core,
  address: String,
  init: channel.ChannelInit,
) -> Core {
  case address == root_address || has_channel(core, address) {
    True -> core
    False ->
      Core(
        ..core,
        detached: dict.insert(
          core.detached,
          address,
          channel.new(init, replica: core.client_id),
        ),
      )
  }
}

pub fn has_channel(core: Core, address: String) -> Bool {
  dict.has_key(core.channels, address) || dict.has_key(core.detached, address)
}

pub fn set(
  core: Core,
  address: String,
  key: String,
  value: Json,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOp)),
  CoreError,
) {
  case locate_map(core, address) {
    Error(core_error) -> Error(core_error)
    Ok(Detached(kernel)) -> {
      let #(kernel, events, _op) = map_kernel.set(kernel, key, value)
      Ok(
        #(
          put_detached_channel(core, address, channel.MapState(kernel)),
          tag_map_events(address, events),
          [],
        ),
      )
    }
    Ok(Attached(_)) -> {
      // Attaching dependencies first can reshape `core.channels`, so re-read
      // the kernel afterwards (its own type cannot change underneath us).
      let #(core, attach_outbound) = attach_dependencies(core, value)
      let assert Ok(channel.MapState(kernel)) = dict.get(core.channels, address)
      let #(kernel, events, op) = map_kernel.set(kernel, key, value)
      let #(core, events, outbound) =
        stamp_attached(
          core,
          address,
          channel.MapState(kernel),
          tag_map_events(address, events),
          channel.MapOp(op),
          channel.NoMeta,
        )
      Ok(#(core, events, list.append(attach_outbound, outbound)))
    }
  }
}

pub fn delete(
  core: Core,
  address: String,
  key: String,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOp)),
  CoreError,
) {
  case locate_map(core, address) {
    Error(core_error) -> Error(core_error)
    Ok(Detached(kernel)) -> {
      let #(kernel, events, _op) = map_kernel.delete(kernel, key)
      Ok(
        #(
          put_detached_channel(core, address, channel.MapState(kernel)),
          tag_map_events(address, events),
          [],
        ),
      )
    }
    Ok(Attached(kernel)) -> {
      let #(kernel, events, op) = map_kernel.delete(kernel, key)
      Ok(stamp_attached(
        core,
        address,
        channel.MapState(kernel),
        tag_map_events(address, events),
        channel.MapOp(op),
        channel.NoMeta,
      ))
    }
  }
}

pub fn clear(
  core: Core,
  address: String,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOp)),
  CoreError,
) {
  case locate_map(core, address) {
    Error(core_error) -> Error(core_error)
    Ok(Detached(kernel)) -> {
      let #(kernel, events, _op) = map_kernel.clear(kernel)
      Ok(
        #(
          put_detached_channel(core, address, channel.MapState(kernel)),
          tag_map_events(address, events),
          [],
        ),
      )
    }
    Ok(Attached(kernel)) -> {
      let #(kernel, events, op) = map_kernel.clear(kernel)
      Ok(stamp_attached(
        core,
        address,
        channel.MapState(kernel),
        tag_map_events(address, events),
        channel.MapOp(op),
        channel.NoMeta,
      ))
    }
  }
}

pub fn increment(
  core: Core,
  address: String,
  amount: Int,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOp)),
  CoreError,
) {
  case locate_counter(core, address) {
    Error(core_error) -> Error(core_error)
    Ok(Detached(kernel)) -> {
      let #(kernel, events, _op, _message_id) =
        counter_kernel.increment(kernel, amount)
      Ok(
        #(
          put_detached_channel(core, address, channel.CounterState(kernel)),
          tag_counter_events(address, events),
          [],
        ),
      )
    }
    Ok(Attached(kernel)) -> {
      let #(kernel, events, op, message_id) =
        counter_kernel.increment(kernel, amount)
      Ok(stamp_attached(
        core,
        address,
        channel.CounterState(kernel),
        tag_counter_events(address, events),
        channel.CounterOp(op),
        channel.CounterMeta(message_id),
      ))
    }
  }
}

/// Optimistically apply a signed update (increment or decrement) to the
/// PN-counter at `address`. Same optimistic lifecycle as `increment`.
pub fn pn_counter_update(
  core: Core,
  address: String,
  amount: Int,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOp)),
  CoreError,
) {
  case locate_pn_counter(core, address) {
    Error(core_error) -> Error(core_error)
    Ok(Detached(kernel)) -> {
      let #(kernel, events, _op, _message_id) =
        pn_counter_kernel.update(kernel, amount)
      Ok(
        #(
          put_detached_channel(core, address, channel.PnCounterState(kernel)),
          tag_pn_counter_events(address, events),
          [],
        ),
      )
    }
    Ok(Attached(kernel)) -> {
      let #(kernel, events, op, message_id) =
        pn_counter_kernel.update(kernel, amount)
      Ok(stamp_attached(
        core,
        address,
        channel.PnCounterState(kernel),
        tag_pn_counter_events(address, events),
        channel.PnCounterOp(op),
        channel.PnCounterMeta(message_id),
      ))
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PactMap edits
// ─────────────────────────────────────────────────────────────────────────────

/// Propose `value` (a JSON payload, or `None` to delete) for `key` in the
/// PactMap at `address`. Unlike optimistic kernels, a consensus PactMap does
/// **not** apply locally: the kernel only yields an `Option(PactMapOp)` to
/// submit (`None` when a value is already pending for the key, i.e. a no-op).
/// The value takes effect when the `Set` sequences; the setter's own `Accept`
/// follow-up is emitted automatically by the released-ops loop.
pub fn pact_map_set(
  core: Core,
  address: String,
  key: String,
  value: Json,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOp)),
  CoreError,
) {
  pact_map_submit(core, address, fn(kernel) {
    pact_map_kernel.set(kernel, key, Some(value), core.last_seen_sn)
  })
}

/// Propose a delete (tombstone) for `key` in the PactMap at `address`. Like
/// `pact_map_set`, this only submits an op; the delete takes effect on
/// sequencing. `None` from the kernel (already pending, absent, or already a
/// tombstone) is a no-op.
pub fn pact_map_delete(
  core: Core,
  address: String,
  key: String,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOp)),
  CoreError,
) {
  pact_map_submit(core, address, fn(kernel) {
    pact_map_kernel.delete(kernel, key, core.last_seen_sn)
  })
}

fn pact_map_submit(
  core: Core,
  address: String,
  produce: fn(pact_map_kernel.PactMapState) -> Option(pact_map_kernel.PactMapOp),
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOp)),
  CoreError,
) {
  case locate_pact_map(core, address) {
    Error(core_error) -> Error(core_error)
    // A detached PactMap has no sequencer to settle a pending value, so a set
    // cannot be submitted yet; it is a no-op until the channel is attached.
    Ok(Detached(_)) -> Ok(#(core, [], []))
    Ok(Attached(kernel)) ->
      case produce(kernel) {
        None -> Ok(#(core, [], []))
        Some(op) ->
          Ok(stamp_attached(
            core,
            address,
            channel.PactMapState(kernel),
            [],
            channel.PactMapOp(op),
            channel.NoMeta,
          ))
      }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SharedDirectory edits
// ─────────────────────────────────────────────────────────────────────────────

/// Set `key` to `value` in the directory at `path`. Optimistic: the local
/// value shows immediately; the op is sequenced and acked like any other.
pub fn directory_set(
  core: Core,
  address: String,
  path: String,
  key: String,
  value: Json,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOp)),
  CoreError,
) {
  directory_storage_edit(core, address, fn(kernel) {
    directory_kernel.set(kernel, path, key, value)
  })
}

pub fn directory_delete(
  core: Core,
  address: String,
  path: String,
  key: String,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOp)),
  CoreError,
) {
  directory_storage_edit(core, address, fn(kernel) {
    directory_kernel.delete(kernel, path, key)
  })
}

pub fn directory_clear(
  core: Core,
  address: String,
  path: String,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOp)),
  CoreError,
) {
  directory_storage_edit(core, address, fn(kernel) {
    directory_kernel.clear(kernel, path)
  })
}

pub fn directory_create_subdirectory(
  core: Core,
  address: String,
  path: String,
  name: String,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOp)),
  CoreError,
) {
  let self = client_id_to_int(core.client_id)
  directory_subdir_edit(core, address, fn(kernel) {
    directory_kernel.create_subdirectory(kernel, path, name, self)
  })
}

pub fn directory_delete_subdirectory(
  core: Core,
  address: String,
  path: String,
  name: String,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOp)),
  CoreError,
) {
  directory_subdir_edit(core, address, fn(kernel) {
    directory_kernel.delete_subdirectory(kernel, path, name)
  })
}

/// Storage ops (`set`/`delete`/`clear`) always produce an outbound op when
/// attached; the kernel returns state, events, op, and the message id.
fn directory_storage_edit(
  core: Core,
  address: String,
  run: fn(directory_kernel.DirectoryState) ->
    Result(
      #(
        directory_kernel.DirectoryState,
        List(directory_kernel.DirectoryEvent),
        directory_kernel.DirectoryOp,
        Int,
      ),
      directory_kernel.KernelError,
    ),
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOp)),
  CoreError,
) {
  case locate_directory(core, address) {
    Error(core_error) -> Error(core_error)
    Ok(Detached(kernel)) ->
      case run(kernel) {
        Ok(#(kernel, events, _op, _message_id)) ->
          Ok(
            #(
              put_detached_channel(
                core,
                address,
                channel.DirectoryState(kernel),
              ),
              tag_directory_events(address, events),
              [],
            ),
          )
        Error(err) -> Error(DirectoryOpFailed(address, directory_detail(err)))
      }
    Ok(Attached(kernel)) ->
      case run(kernel) {
        Ok(#(kernel, events, op, message_id)) ->
          Ok(stamp_attached(
            core,
            address,
            channel.DirectoryState(kernel),
            tag_directory_events(address, events),
            channel.DirectoryOp(op, message_id),
            channel.DirectoryMeta(message_id),
          ))
        Error(err) -> Error(DirectoryOpFailed(address, directory_detail(err)))
      }
  }
}

/// Subdirectory ops (`create`/`delete`) may produce no outbound op — a
/// duplicate create or a delete of an optimistically-absent child updates
/// local state and events but sends nothing.
fn directory_subdir_edit(
  core: Core,
  address: String,
  run: fn(directory_kernel.DirectoryState) ->
    Result(
      #(
        directory_kernel.DirectoryState,
        List(directory_kernel.DirectoryEvent),
        Option(directory_kernel.DirectoryOp),
        Int,
      ),
      directory_kernel.KernelError,
    ),
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOp)),
  CoreError,
) {
  case locate_directory(core, address) {
    Error(core_error) -> Error(core_error)
    Ok(Detached(kernel)) ->
      case run(kernel) {
        Ok(#(kernel, events, _op, _message_id)) ->
          Ok(
            #(
              put_detached_channel(
                core,
                address,
                channel.DirectoryState(kernel),
              ),
              tag_directory_events(address, events),
              [],
            ),
          )
        Error(err) -> Error(DirectoryOpFailed(address, directory_detail(err)))
      }
    Ok(Attached(kernel)) ->
      case run(kernel) {
        Ok(#(kernel, events, Some(op), message_id)) ->
          Ok(stamp_attached(
            core,
            address,
            channel.DirectoryState(kernel),
            tag_directory_events(address, events),
            channel.DirectoryOp(op, message_id),
            channel.DirectoryMeta(message_id),
          ))
        Ok(#(kernel, events, None, _message_id)) ->
          Ok(
            #(
              put_attached_channel(
                core,
                address,
                channel.DirectoryState(kernel),
              ),
              tag_directory_events(address, events),
              [],
            ),
          )
        Error(err) -> Error(DirectoryOpFailed(address, directory_detail(err)))
      }
  }
}

fn directory_detail(err: directory_kernel.KernelError) -> String {
  case err {
    directory_kernel.PathNotFound(path) -> "path not found: " <> path
    directory_kernel.InvalidName(name) -> "invalid subdirectory name: " <> name
    directory_kernel.UnexpectedAck(_, detail) -> detail
    directory_kernel.UnexpectedRollback(_, detail) -> detail
    directory_kernel.InvariantViolation(detail) -> detail
  }
}

/// Submit a json0 op authored against the channel's current optimistic view.
/// The single-in-flight kernel sends the op immediately when nothing is in
/// flight, otherwise it is composed into the buffer and released on the next
/// ack (`collect_released_ops`), so at most one op is on the wire at a time.
pub fn submit_json_ot(
  core: Core,
  address: String,
  components: json_ot.Op,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOp)),
  CoreError,
) {
  case locate_json_ot(core, address) {
    Error(core_error) -> Error(core_error)
    Ok(Detached(kernel)) ->
      case json_ot_kernel.submit(kernel, components, core.last_seen_sn) {
        Ok(#(kernel, _wire, events)) ->
          Ok(
            #(
              put_detached_channel(core, address, channel.JsonOtState(kernel)),
              tag_json_ot_events(address, events),
              [],
            ),
          )
        Error(err) -> Error(AckMismatch(json_ot_kernel_error_detail(err)))
      }
    Ok(Attached(kernel)) ->
      case json_ot_kernel.submit(kernel, components, core.last_seen_sn) {
        Ok(#(kernel, Some(wire), events)) ->
          Ok(stamp_attached(
            core,
            address,
            channel.JsonOtState(kernel),
            tag_json_ot_events(address, events),
            channel.JsonOtOp(wire),
            channel.NoMeta,
          ))
        Ok(#(kernel, None, events)) ->
          Ok(
            #(
              put_attached_channel(core, address, channel.JsonOtState(kernel)),
              tag_json_ot_events(address, events),
              [],
            ),
          )
        Error(err) -> Error(AckMismatch(json_ot_kernel_error_detail(err)))
      }
  }
}

/// The channel's current optimistic json0 document, or `None` if the address is
/// not a json0 channel or its view cannot be computed.
pub fn json_ot_view(core: Core, address: String) -> Option(json_ot.JsonValue) {
  case find_channel(core, address) {
    Some(channel.JsonOtState(kernel)) ->
      option.from_result(json_ot_kernel.view(kernel))
    _ -> None
  }
}

fn json_ot_kernel_error_detail(err: json_ot_kernel.KernelError) -> String {
  case err {
    json_ot_kernel.UnexpectedAck(detail) -> detail
    json_ot_kernel.OtFailure(ot) ->
      case ot {
        json_ot.BadPath(detail) -> "json0 bad path: " <> detail
        json_ot.BadValue(detail) -> "json0 bad value: " <> detail
        json_ot.UnknownSubtype(name) -> "json0 unknown subtype: " <> name
      }
  }
}

pub fn or_map_increment(
  core: Core,
  address: String,
  key: String,
  amount: Int,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOp)),
  CoreError,
) {
  case locate_or_map(core, address) {
    Error(core_error) -> Error(core_error)
    Ok(Detached(kernel)) ->
      case or_map_kernel.increment(kernel, key, amount) {
        Ok(#(kernel, events, _op, _message_id)) ->
          Ok(
            #(
              put_detached_channel(core, address, channel.OrMapState(kernel)),
              tag_or_map_events(address, events),
              [],
            ),
          )
        Error(or_map_kernel.ModeMismatch(detail)) ->
          Error(OrMapModeMismatch(address, detail))
        Error(or_map_kernel.UnexpectedAck(detail))
        | Error(or_map_kernel.UnexpectedRollback(detail))
        | Error(or_map_kernel.CorruptDelta(detail)) ->
          Error(AckMismatch(detail))
      }
    Ok(Attached(kernel)) ->
      case or_map_kernel.increment(kernel, key, amount) {
        Ok(#(kernel, events, op, message_id)) ->
          Ok(stamp_attached(
            core,
            address,
            channel.OrMapState(kernel),
            tag_or_map_events(address, events),
            channel.OrMapOp(op),
            channel.OrMapMeta(message_id),
          ))
        Error(or_map_kernel.ModeMismatch(detail)) ->
          Error(OrMapModeMismatch(address, detail))
        Error(or_map_kernel.UnexpectedAck(detail))
        | Error(or_map_kernel.UnexpectedRollback(detail))
        | Error(or_map_kernel.CorruptDelta(detail)) ->
          Error(AckMismatch(detail))
      }
  }
}

pub fn or_map_set(
  core: Core,
  address: String,
  key: String,
  value: String,
  timestamp: Int,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOp)),
  CoreError,
) {
  case locate_or_map(core, address) {
    Error(core_error) -> Error(core_error)
    Ok(Detached(kernel)) ->
      case or_map_kernel.set_register(kernel, key, value, timestamp) {
        Ok(#(kernel, events, _op, _message_id)) ->
          Ok(
            #(
              put_detached_channel(core, address, channel.OrMapState(kernel)),
              tag_or_map_events(address, events),
              [],
            ),
          )
        Error(or_map_kernel.ModeMismatch(detail)) ->
          Error(OrMapModeMismatch(address, detail))
        Error(or_map_kernel.UnexpectedAck(detail))
        | Error(or_map_kernel.UnexpectedRollback(detail))
        | Error(or_map_kernel.CorruptDelta(detail)) ->
          Error(AckMismatch(detail))
      }
    Ok(Attached(_)) -> {
      let #(core, attach_outbound) =
        attach_dependencies_from_register_string(core, value)
      let assert Ok(channel.OrMapState(kernel)) =
        dict.get(core.channels, address)
      case or_map_kernel.set_register(kernel, key, value, timestamp) {
        Ok(#(kernel, events, op, message_id)) -> {
          let #(core, events, outbound) =
            stamp_attached(
              core,
              address,
              channel.OrMapState(kernel),
              tag_or_map_events(address, events),
              channel.OrMapOp(op),
              channel.OrMapMeta(message_id),
            )
          Ok(#(core, events, list.append(attach_outbound, outbound)))
        }
        Error(or_map_kernel.ModeMismatch(detail)) ->
          Error(OrMapModeMismatch(address, detail))
        Error(or_map_kernel.UnexpectedAck(detail))
        | Error(or_map_kernel.UnexpectedRollback(detail))
        | Error(or_map_kernel.CorruptDelta(detail)) ->
          Error(AckMismatch(detail))
      }
    }
  }
}

pub fn or_map_remove(
  core: Core,
  address: String,
  key: String,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOp)),
  CoreError,
) {
  case locate_or_map(core, address) {
    Error(core_error) -> Error(core_error)
    Ok(Detached(kernel)) -> {
      let #(kernel, events, _op, _message_id) =
        or_map_kernel.remove(kernel, key)
      Ok(
        #(
          put_detached_channel(core, address, channel.OrMapState(kernel)),
          tag_or_map_events(address, events),
          [],
        ),
      )
    }

    Ok(Attached(kernel)) -> {
      let #(kernel, events, op, message_id) = or_map_kernel.remove(kernel, key)
      Ok(stamp_attached(
        core,
        address,
        channel.OrMapState(kernel),
        tag_or_map_events(address, events),
        channel.OrMapOp(op),
        channel.OrMapMeta(message_id),
      ))
    }
  }
}

pub fn or_set_add(
  core: Core,
  address: String,
  element: String,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOp)),
  CoreError,
) {
  case locate_or_set(core, address) {
    Error(core_error) -> Error(core_error)
    Ok(Detached(kernel)) -> {
      let #(kernel, events, _op, _message_id) =
        or_set_kernel.add(kernel, element)
      Ok(
        #(
          put_detached_channel(core, address, channel.OrSetState(kernel)),
          tag_or_set_events(address, events),
          [],
        ),
      )
    }
    Ok(Attached(kernel)) -> {
      let #(kernel, events, op, message_id) = or_set_kernel.add(kernel, element)
      Ok(stamp_attached(
        core,
        address,
        channel.OrSetState(kernel),
        tag_or_set_events(address, events),
        channel.OrSetOp(op),
        channel.OrSetMeta(message_id),
      ))
    }
  }
}

pub fn or_set_remove(
  core: Core,
  address: String,
  element: String,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOp)),
  CoreError,
) {
  case locate_or_set(core, address) {
    Error(core_error) -> Error(core_error)
    Ok(Detached(kernel)) -> {
      let #(kernel, events, _op, _message_id) =
        or_set_kernel.remove(kernel, element)
      Ok(
        #(
          put_detached_channel(core, address, channel.OrSetState(kernel)),
          tag_or_set_events(address, events),
          [],
        ),
      )
    }
    Ok(Attached(kernel)) -> {
      let #(kernel, events, op, message_id) =
        or_set_kernel.remove(kernel, element)
      Ok(stamp_attached(
        core,
        address,
        channel.OrSetState(kernel),
        tag_or_set_events(address, events),
        channel.OrSetOp(op),
        channel.OrSetMeta(message_id),
      ))
    }
  }
}

pub fn g_set_add(
  core: Core,
  address: String,
  element: String,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOp)),
  CoreError,
) {
  case locate_g_set(core, address) {
    Error(core_error) -> Error(core_error)
    Ok(Detached(kernel)) -> {
      let #(kernel, events, _op, _message_id) =
        g_set_kernel.add(kernel, element)
      Ok(
        #(
          put_detached_channel(core, address, channel.GSetState(kernel)),
          tag_g_set_events(address, events),
          [],
        ),
      )
    }
    Ok(Attached(kernel)) -> {
      let #(kernel, events, op, message_id) = g_set_kernel.add(kernel, element)
      Ok(stamp_attached(
        core,
        address,
        channel.GSetState(kernel),
        tag_g_set_events(address, events),
        channel.GSetOp(op),
        channel.GSetMeta(message_id),
      ))
    }
  }
}

pub fn two_p_set_add(
  core: Core,
  address: String,
  element: String,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOp)),
  CoreError,
) {
  case locate_two_p_set(core, address) {
    Error(core_error) -> Error(core_error)
    Ok(Detached(kernel)) -> {
      let #(kernel, events, _op, _message_id) =
        two_p_set_kernel.add(kernel, element)
      Ok(
        #(
          put_detached_channel(core, address, channel.TwoPSetState(kernel)),
          tag_two_p_set_events(address, events),
          [],
        ),
      )
    }
    Ok(Attached(kernel)) -> {
      let #(kernel, events, op, message_id) =
        two_p_set_kernel.add(kernel, element)
      Ok(stamp_attached(
        core,
        address,
        channel.TwoPSetState(kernel),
        tag_two_p_set_events(address, events),
        channel.TwoPSetOp(op),
        channel.TwoPSetMeta(message_id),
      ))
    }
  }
}

pub fn two_p_set_remove(
  core: Core,
  address: String,
  element: String,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOp)),
  CoreError,
) {
  case locate_two_p_set(core, address) {
    Error(core_error) -> Error(core_error)
    Ok(Detached(kernel)) -> {
      let #(kernel, events, _op, _message_id) =
        two_p_set_kernel.remove(kernel, element)
      Ok(
        #(
          put_detached_channel(core, address, channel.TwoPSetState(kernel)),
          tag_two_p_set_events(address, events),
          [],
        ),
      )
    }
    Ok(Attached(kernel)) -> {
      let #(kernel, events, op, message_id) =
        two_p_set_kernel.remove(kernel, element)
      Ok(stamp_attached(
        core,
        address,
        channel.TwoPSetState(kernel),
        tag_two_p_set_events(address, events),
        channel.TwoPSetOp(op),
        channel.TwoPSetMeta(message_id),
      ))
    }
  }
}

pub fn register_write(
  core: Core,
  address: String,
  key: String,
  value: Json,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOp)),
  CoreError,
) {
  case locate_register_collection(core, address) {
    Error(core_error) -> Error(core_error)
    Ok(Detached(kernel)) -> {
      let #(kernel, events) =
        register_collection_kernel.write_detached(kernel, key, value)
      Ok(
        #(
          put_detached_channel(
            core,
            address,
            channel.RegisterCollectionState(kernel),
          ),
          tag_register_collection_events(address, events),
          [],
        ),
      )
    }
    Ok(Attached(_)) -> {
      let #(core, attach_outbound) = attach_dependencies(core, value)
      let assert Ok(channel.RegisterCollectionState(kernel)) =
        dict.get(core.channels, address)
      let op =
        register_collection_kernel.write(kernel, key, value, core.last_seen_sn)
      let #(core, events, outbound) =
        stamp_attached(
          core,
          address,
          channel.RegisterCollectionState(kernel),
          [],
          channel.RegisterCollectionOp(op),
          channel.NoMeta,
        )
      Ok(#(core, events, list.append(attach_outbound, outbound)))
    }
  }
}

pub type ClaimSubmitResult {
  ClaimPending(
    core: Core,
    outbound: List(wire.OutboundOp),
    immediate_outcome: Option(claims_kernel.ClaimOutcome),
  )
  ClaimAlreadyClaimed(current_value: Json)
  ClaimAlreadyPendingLocally
}

pub fn try_set_claim(
  core: Core,
  address: String,
  key: String,
  value: Json,
) -> Result(ClaimSubmitResult, CoreError) {
  case locate_claims(core, address) {
    Error(core_error) -> Error(core_error)
    Ok(Detached(kernel)) ->
      case claims_kernel.get(kernel, key) {
        Some(current_value) -> Ok(ClaimAlreadyClaimed(current_value))
        None -> {
          let kernel = claims_kernel.set_detached(kernel, key, value)
          let core =
            put_detached_channel(core, address, channel.ClaimsState(kernel))
          Ok(ClaimPending(
            core: core,
            outbound: [],
            immediate_outcome: Some(claims_kernel.Accepted(value)),
          ))
        }
      }
    Ok(Attached(kernel)) ->
      case claims_kernel.try_set_claim(kernel, key, value, core.last_seen_sn) {
        Ok(claims_kernel.AlreadyClaimed(current_value)) ->
          Ok(ClaimAlreadyClaimed(current_value))
        Ok(claims_kernel.Submitted(kernel, op)) -> {
          let #(core, attach_outbound) = attach_dependencies(core, value)
          let #(core, _events, outbound) =
            stamp_attached(
              core,
              address,
              channel.ClaimsState(kernel),
              [],
              channel.ClaimsOp(op),
              channel.NoMeta,
            )
          Ok(ClaimPending(
            core: core,
            outbound: list.append(attach_outbound, outbound),
            immediate_outcome: None,
          ))
        }
        Error(claims_kernel.AlreadyPendingLocally(_)) ->
          Ok(ClaimAlreadyPendingLocally)
        Error(claims_kernel.UnexpectedAck(_, detail))
        | Error(claims_kernel.UnexpectedRollback(_, detail)) ->
          Error(AckMismatch(detail))
      }
  }
}

pub fn compare_and_set_claim(
  core: Core,
  address: String,
  key: String,
  value: Json,
) -> Result(ClaimSubmitResult, CoreError) {
  case locate_claims(core, address) {
    Error(core_error) -> Error(core_error)
    Ok(Detached(kernel)) -> {
      let kernel = claims_kernel.set_detached(kernel, key, value)
      let core =
        put_detached_channel(core, address, channel.ClaimsState(kernel))
      Ok(ClaimPending(
        core: core,
        outbound: [],
        immediate_outcome: Some(claims_kernel.Accepted(value)),
      ))
    }
    Ok(Attached(kernel)) ->
      case
        claims_kernel.compare_and_set_claim(
          kernel,
          key,
          value,
          core.last_seen_sn,
        )
      {
        Ok(claims_kernel.Submitted(kernel, op)) -> {
          let #(core, attach_outbound) = attach_dependencies(core, value)
          let #(core, _events, outbound) =
            stamp_attached(
              core,
              address,
              channel.ClaimsState(kernel),
              [],
              channel.ClaimsOp(op),
              channel.NoMeta,
            )
          Ok(ClaimPending(
            core: core,
            outbound: list.append(attach_outbound, outbound),
            immediate_outcome: None,
          ))
        }
        Ok(claims_kernel.AlreadyClaimed(current_value)) ->
          Ok(ClaimAlreadyClaimed(current_value))
        Error(claims_kernel.AlreadyPendingLocally(_)) ->
          Ok(ClaimAlreadyPendingLocally)
        Error(claims_kernel.UnexpectedAck(_, detail))
        | Error(claims_kernel.UnexpectedRollback(_, detail)) ->
          Error(AckMismatch(detail))
      }
  }
}

pub fn task_manager_volunteer(
  core: Core,
  address: String,
  task_id: String,
) -> Result(
  #(
    Core,
    List(#(String, ChannelEvent)),
    List(wire.OutboundOp),
    task_manager_kernel.VolunteerOutcome,
  ),
  CoreError,
) {
  case locate_task_manager(core, address) {
    Error(core_error) -> Error(core_error)
    Ok(Detached(kernel)) -> {
      let #(kernel, events, outcome) =
        task_manager_kernel.volunteer_detached(
          kernel,
          task_id,
          client_id_to_int(core.client_id),
        )
      Ok(#(
        put_detached_channel(core, address, channel.TaskManagerState(kernel)),
        tag_task_manager_events(address, events),
        [],
        outcome,
      ))
    }
    Ok(Attached(kernel)) -> {
      let message_id = core.next_csn
      let #(kernel, op, outcome) =
        task_manager_kernel.volunteer(
          kernel,
          task_id,
          client_id_to_int(core.client_id),
          message_id,
        )
      case op {
        None ->
          Ok(#(
            put_attached_channel(
              core,
              address,
              channel.TaskManagerState(kernel),
            ),
            [],
            [],
            outcome,
          ))
        Some(op) -> {
          let #(core, events, outbound) =
            stamp_attached(
              core,
              address,
              channel.TaskManagerState(kernel),
              [],
              channel.TaskManagerOp(op),
              channel.TaskManagerMeta(message_id),
            )
          Ok(#(core, events, outbound, outcome))
        }
      }
    }
  }
}

pub fn task_manager_abandon(
  core: Core,
  address: String,
  task_id: String,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOp)),
  CoreError,
) {
  case locate_task_manager(core, address) {
    Error(core_error) -> Error(core_error)
    Ok(Detached(kernel)) -> {
      let #(kernel, events) =
        task_manager_kernel.abandon_detached(
          kernel,
          task_id,
          client_id_to_int(core.client_id),
        )
      Ok(
        #(
          put_detached_channel(core, address, channel.TaskManagerState(kernel)),
          tag_task_manager_events(address, events),
          [],
        ),
      )
    }
    Ok(Attached(kernel)) -> {
      let message_id = core.next_csn
      let #(kernel, op, events) =
        task_manager_kernel.abandon(
          kernel,
          task_id,
          client_id_to_int(core.client_id),
          message_id,
        )
      case op {
        None ->
          Ok(
            #(
              put_attached_channel(
                core,
                address,
                channel.TaskManagerState(kernel),
              ),
              tag_task_manager_events(address, events),
              [],
            ),
          )
        Some(op) ->
          Ok(stamp_attached(
            core,
            address,
            channel.TaskManagerState(kernel),
            tag_task_manager_events(address, events),
            channel.TaskManagerOp(op),
            channel.TaskManagerMeta(message_id),
          ))
      }
    }
  }
}

pub fn task_manager_complete(
  core: Core,
  address: String,
  task_id: String,
) -> Result(
  #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOp)),
  CoreError,
) {
  case locate_task_manager(core, address) {
    Error(core_error) -> Error(core_error)
    Ok(Detached(kernel)) -> {
      case
        task_manager_kernel.assigned(
          kernel,
          task_id,
          client_id_to_int(core.client_id),
          True,
        )
      {
        False -> Error(TaskNotAssigned(address, task_id))
        True -> {
          let #(kernel, events) =
            task_manager_kernel.complete_detached(kernel, task_id)
          Ok(
            #(
              put_detached_channel(
                core,
                address,
                channel.TaskManagerState(kernel),
              ),
              tag_task_manager_events(address, events),
              [],
            ),
          )
        }
      }
    }
    Ok(Attached(kernel)) -> {
      let message_id = core.next_csn
      case
        task_manager_kernel.complete(
          kernel,
          task_id,
          client_id_to_int(core.client_id),
          message_id,
        )
      {
        Ok(#(kernel, op)) ->
          Ok(stamp_attached(
            core,
            address,
            channel.TaskManagerState(kernel),
            [],
            channel.TaskManagerOp(op),
            channel.TaskManagerMeta(message_id),
          ))
        Error(task_manager_kernel.NotAssigned(_)) ->
          Error(TaskNotAssigned(address, task_id))
        Error(task_manager_kernel.UnexpectedAck(_, detail))
        | Error(task_manager_kernel.UnexpectedRollback(_, detail))
        | Error(task_manager_kernel.UnexpectedResubmit(_, detail)) ->
          Error(AckMismatch(detail))
      }
    }
  }
}

/// Where an edit's target channel lives, holding the type-checked kernel.
type Located(kernel) {
  Detached(kernel)
  Attached(kernel)
}

fn locate_map(
  core: Core,
  address: String,
) -> Result(Located(map_kernel.MapState), CoreError) {
  use located <- result.try(locate_channel(core, address))
  case located {
    Detached(channel.MapState(kernel)) -> Ok(Detached(kernel))
    Attached(channel.MapState(kernel)) -> Ok(Attached(kernel))
    Detached(other) | Attached(other) ->
      Error(WrongChannelType(
        address,
        expected: channel.MapChannel,
        actual: channel.channel_type(other),
      ))
  }
}

fn locate_counter(
  core: Core,
  address: String,
) -> Result(Located(counter_kernel.CounterState), CoreError) {
  use located <- result.try(locate_channel(core, address))
  case located {
    Detached(channel.CounterState(kernel)) -> Ok(Detached(kernel))
    Attached(channel.CounterState(kernel)) -> Ok(Attached(kernel))
    Detached(other) | Attached(other) ->
      Error(WrongChannelType(
        address,
        expected: channel.CounterChannel,
        actual: channel.channel_type(other),
      ))
  }
}

fn locate_pn_counter(
  core: Core,
  address: String,
) -> Result(Located(pn_counter_kernel.PnCounterState), CoreError) {
  use located <- result.try(locate_channel(core, address))
  case located {
    Detached(channel.PnCounterState(kernel)) -> Ok(Detached(kernel))
    Attached(channel.PnCounterState(kernel)) -> Ok(Attached(kernel))
    Detached(other) | Attached(other) ->
      Error(WrongChannelType(
        address,
        expected: channel.PnCounterChannel,
        actual: channel.channel_type(other),
      ))
  }
}

fn locate_pact_map(
  core: Core,
  address: String,
) -> Result(Located(pact_map_kernel.PactMapState), CoreError) {
  use located <- result.try(locate_channel(core, address))
  case located {
    Detached(channel.PactMapState(kernel)) -> Ok(Detached(kernel))
    Attached(channel.PactMapState(kernel)) -> Ok(Attached(kernel))
    Detached(other) | Attached(other) ->
      Error(WrongChannelType(
        address,
        expected: channel.PactMapChannel,
        actual: channel.channel_type(other),
      ))
  }
}

fn locate_or_map(
  core: Core,
  address: String,
) -> Result(Located(or_map_kernel.OrMapState), CoreError) {
  use located <- result.try(locate_channel(core, address))
  case located {
    Detached(channel.OrMapState(kernel)) -> Ok(Detached(kernel))
    Attached(channel.OrMapState(kernel)) -> Ok(Attached(kernel))
    Detached(other) | Attached(other) ->
      Error(WrongChannelType(
        address,
        expected: channel.OrMapChannel,
        actual: channel.channel_type(other),
      ))
  }
}

fn locate_or_set(
  core: Core,
  address: String,
) -> Result(Located(or_set_kernel.OrSetState), CoreError) {
  use located <- result.try(locate_channel(core, address))
  case located {
    Detached(channel.OrSetState(kernel)) -> Ok(Detached(kernel))
    Attached(channel.OrSetState(kernel)) -> Ok(Attached(kernel))
    Detached(other) | Attached(other) ->
      Error(WrongChannelType(
        address,
        expected: channel.OrSetChannel,
        actual: channel.channel_type(other),
      ))
  }
}

fn locate_g_set(
  core: Core,
  address: String,
) -> Result(Located(g_set_kernel.GSetState), CoreError) {
  use located <- result.try(locate_channel(core, address))
  case located {
    Detached(channel.GSetState(kernel)) -> Ok(Detached(kernel))
    Attached(channel.GSetState(kernel)) -> Ok(Attached(kernel))
    Detached(other) | Attached(other) ->
      Error(WrongChannelType(
        address,
        expected: channel.GSetChannel,
        actual: channel.channel_type(other),
      ))
  }
}

fn locate_two_p_set(
  core: Core,
  address: String,
) -> Result(Located(two_p_set_kernel.TwoPSetState), CoreError) {
  use located <- result.try(locate_channel(core, address))
  case located {
    Detached(channel.TwoPSetState(kernel)) -> Ok(Detached(kernel))
    Attached(channel.TwoPSetState(kernel)) -> Ok(Attached(kernel))
    Detached(other) | Attached(other) ->
      Error(WrongChannelType(
        address,
        expected: channel.TwoPSetChannel,
        actual: channel.channel_type(other),
      ))
  }
}

fn locate_register_collection(
  core: Core,
  address: String,
) -> Result(Located(register_collection_kernel.RegisterState), CoreError) {
  use located <- result.try(locate_channel(core, address))
  case located {
    Detached(channel.RegisterCollectionState(kernel)) -> Ok(Detached(kernel))
    Attached(channel.RegisterCollectionState(kernel)) -> Ok(Attached(kernel))
    Detached(other) | Attached(other) ->
      Error(WrongChannelType(
        address,
        expected: channel.RegisterCollectionChannel,
        actual: channel.channel_type(other),
      ))
  }
}

fn locate_claims(
  core: Core,
  address: String,
) -> Result(Located(claims_kernel.ClaimsState), CoreError) {
  use located <- result.try(locate_channel(core, address))
  case located {
    Detached(channel.ClaimsState(kernel)) -> Ok(Detached(kernel))
    Attached(channel.ClaimsState(kernel)) -> Ok(Attached(kernel))
    Detached(other) | Attached(other) ->
      Error(WrongChannelType(
        address,
        expected: channel.ClaimsChannel,
        actual: channel.channel_type(other),
      ))
  }
}

fn locate_task_manager(
  core: Core,
  address: String,
) -> Result(Located(task_manager_kernel.TaskManagerState), CoreError) {
  use located <- result.try(locate_channel(core, address))
  case located {
    Detached(channel.TaskManagerState(kernel)) -> Ok(Detached(kernel))
    Attached(channel.TaskManagerState(kernel)) -> Ok(Attached(kernel))
    Detached(other) | Attached(other) ->
      Error(WrongChannelType(
        address,
        expected: channel.TaskManagerChannel,
        actual: channel.channel_type(other),
      ))
  }
}

fn locate_json_ot(
  core: Core,
  address: String,
) -> Result(Located(json_ot_kernel.JsonOtState), CoreError) {
  use located <- result.try(locate_channel(core, address))
  case located {
    Detached(channel.JsonOtState(kernel)) -> Ok(Detached(kernel))
    Attached(channel.JsonOtState(kernel)) -> Ok(Attached(kernel))
    Detached(other) | Attached(other) ->
      Error(WrongChannelType(
        address,
        expected: channel.JsonOtChannel,
        actual: channel.channel_type(other),
      ))
  }
}

fn locate_directory(
  core: Core,
  address: String,
) -> Result(Located(directory_kernel.DirectoryState), CoreError) {
  use located <- result.try(locate_channel(core, address))
  case located {
    Detached(channel.DirectoryState(kernel)) -> Ok(Detached(kernel))
    Attached(channel.DirectoryState(kernel)) -> Ok(Attached(kernel))
    Detached(other) | Attached(other) ->
      Error(WrongChannelType(
        address,
        expected: channel.DirectoryChannel,
        actual: channel.channel_type(other),
      ))
  }
}

fn locate_channel(
  core: Core,
  address: String,
) -> Result(Located(ChannelState), CoreError) {
  case dict.get(core.detached, address) {
    Ok(state) -> Ok(Detached(state))
    Error(_) ->
      case dict.get(core.channels, address) {
        Ok(state) -> Ok(Attached(state))
        Error(_) -> Error(UnknownChannel(address, core.last_seen_sn))
      }
  }
}

fn attach_dependencies(
  core: Core,
  value: Json,
) -> #(Core, List(wire.OutboundOp)) {
  let #(order, _) =
    collect_attach_order(core, handle.collect_handle_addresses(value), [])
  submit_attaches(core, order)
}

fn attach_dependencies_from_register_string(
  core: Core,
  value: String,
) -> #(Core, List(wire.OutboundOp)) {
  case json.parse(value, wire.json_value_decoder()) {
    Ok(json_value) -> attach_dependencies(core, json_value)
    Error(_) -> #(core, [])
  }
}

fn collect_attach_order(
  core: Core,
  addresses: List(String),
  visited: List(String),
) -> #(List(String), List(String)) {
  list.fold(addresses, #([], visited), fn(acc, address) {
    let #(order, visited) = acc
    let #(next, visited) = collect_attach_for(core, address, visited)
    #(list.append(order, next), visited)
  })
}

fn collect_attach_for(
  core: Core,
  address: String,
  visited: List(String),
) -> #(List(String), List(String)) {
  case list.any(visited, fn(seen) { seen == address }) {
    True -> #([], visited)
    False -> {
      let visited = [address, ..visited]
      case dict.get(core.detached, address) {
        Error(_) -> #([], visited)
        Ok(state) -> {
          let deps = channel.handle_addresses(state)
          let #(order, visited) = collect_attach_order(core, deps, visited)
          #(list.append(order, [address]), visited)
        }
      }
    }
  }
}

fn submit_attaches(
  core: Core,
  addresses: List(String),
) -> #(Core, List(wire.OutboundOp)) {
  list.fold(addresses, #(core, []), fn(acc, address) {
    let #(core, outbound) = acc
    case dict.get(core.detached, address) {
      Error(_) -> #(core, outbound)
      Ok(state) -> {
        let snapshot = channel.attach_snapshot(state)
        let csn = core.next_csn
        let outbound_op =
          ops.outbound_attach_op(
            address: address,
            client_sequence_number: csn,
            reference_sequence_number: core.last_seen_sn,
            snapshot: snapshot,
          )
        let core =
          Core(
            ..core,
            channels: dict.insert(
              core.channels,
              address,
              channel.attach_state(state, replica: core.client_id),
            ),
            channel_order: list.unique(
              list.append(core.channel_order, [address]),
            ),
            detached: dict.delete(core.detached, address),
            next_csn: csn + 1,
            in_flight: list.append(core.in_flight, [
              InFlightAttach(
                client_id: core.client_id,
                csn: csn,
                address: address,
                snapshot: snapshot,
              ),
            ]),
          )
        #(core, list.append(outbound, [outbound_op]))
      }
    }
  })
}

fn stamp_attached(
  core: Core,
  address: String,
  state: ChannelState,
  events: List(#(String, ChannelEvent)),
  op: channel.ChannelOp,
  meta: channel.LocalOpMeta,
) -> #(Core, List(#(String, ChannelEvent)), List(wire.OutboundOp)) {
  let csn = core.next_csn
  let outbound =
    ops.outbound_channel_op(
      address: address,
      client_sequence_number: csn,
      reference_sequence_number: core.last_seen_sn,
      op: op,
    )
  let core =
    Core(
      ..core,
      channels: dict.insert(core.channels, address, state),
      next_csn: csn + 1,
      in_flight: list.append(core.in_flight, [
        InFlightOp(
          client_id: core.client_id,
          csn: csn,
          address: address,
          op: op,
          meta: meta,
        ),
      ]),
    )
  #(core, events, [outbound])
}

fn tag_events(
  address: String,
  events: List(ChannelEvent),
) -> List(#(String, ChannelEvent)) {
  list.map(events, fn(event) { #(address, event) })
}

fn tag_resolution(
  address: String,
  resolution: Option(Resolution),
) -> List(#(String, Resolution)) {
  case resolution {
    Some(resolution) -> [#(address, resolution)]
    None -> []
  }
}

fn tag_map_events(
  address: String,
  events: List(map_kernel.MapEvent),
) -> List(#(String, ChannelEvent)) {
  list.map(events, fn(event) { #(address, channel.MapEvent(event)) })
}

fn tag_counter_events(
  address: String,
  events: List(counter_kernel.CounterEvent),
) -> List(#(String, ChannelEvent)) {
  list.map(events, fn(event) { #(address, channel.CounterEvent(event)) })
}

fn tag_pn_counter_events(
  address: String,
  events: List(pn_counter_kernel.PnCounterEvent),
) -> List(#(String, ChannelEvent)) {
  list.map(events, fn(event) { #(address, channel.PnCounterEvent(event)) })
}

fn tag_json_ot_events(
  address: String,
  events: List(json_ot_kernel.JsonOtEvent),
) -> List(#(String, ChannelEvent)) {
  list.map(events, fn(event) { #(address, channel.JsonOtEvent(event)) })
}

fn tag_directory_events(
  address: String,
  events: List(directory_kernel.DirectoryEvent),
) -> List(#(String, ChannelEvent)) {
  list.map(events, fn(event) { #(address, channel.DirectoryEvent(event)) })
}

fn tag_or_map_events(
  address: String,
  events: List(or_map_kernel.OrMapEvent),
) -> List(#(String, ChannelEvent)) {
  list.map(events, fn(event) { #(address, channel.OrMapEvent(event)) })
}

fn tag_or_set_events(
  address: String,
  events: List(or_set_kernel.OrSetEvent),
) -> List(#(String, ChannelEvent)) {
  list.map(events, fn(event) { #(address, channel.OrSetEvent(event)) })
}

fn tag_g_set_events(
  address: String,
  events: List(g_set_kernel.GSetEvent),
) -> List(#(String, ChannelEvent)) {
  list.map(events, fn(event) { #(address, channel.GSetEvent(event)) })
}

fn tag_two_p_set_events(
  address: String,
  events: List(two_p_set_kernel.TwoPSetEvent),
) -> List(#(String, ChannelEvent)) {
  list.map(events, fn(event) { #(address, channel.TwoPSetEvent(event)) })
}

fn tag_register_collection_events(
  address: String,
  events: List(register_collection_kernel.RegisterEvent),
) -> List(#(String, ChannelEvent)) {
  list.map(events, fn(event) {
    #(address, channel.RegisterCollectionEvent(event))
  })
}

fn tag_task_manager_events(
  address: String,
  events: List(task_manager_kernel.TaskManagerEvent),
) -> List(#(String, ChannelEvent)) {
  list.map(events, fn(event) { #(address, channel.TaskManagerEvent(event)) })
}

// ─────────────────────────────────────────────────────────────────────────────
// Reads
// ─────────────────────────────────────────────────────────────────────────────

pub fn get(core: Core, address: String, key: String) -> Option(Json) {
  case find_channel(core, address) {
    Some(channel.MapState(kernel)) -> map_kernel.get(kernel, key)
    _ -> None
  }
}

pub fn has(core: Core, address: String, key: String) -> Bool {
  get(core, address, key) != None
}

pub fn size(core: Core, address: String) -> Int {
  case find_channel(core, address) {
    Some(channel.MapState(kernel)) -> map_kernel.size(kernel)
    _ -> 0
  }
}

pub fn keys(core: Core, address: String) -> List(String) {
  case find_channel(core, address) {
    Some(channel.MapState(kernel)) -> map_kernel.keys(kernel)
    _ -> []
  }
}

pub fn entries(core: Core, address: String) -> List(#(String, Json)) {
  case find_channel(core, address) {
    Some(channel.MapState(kernel)) -> map_kernel.entries(kernel)
    _ -> []
  }
}

/// The counter's current optimistic value, `None` when the address is
/// missing or not a counter channel.
pub fn counter_value(core: Core, address: String) -> Option(Int) {
  case find_channel(core, address) {
    Some(channel.CounterState(kernel)) -> Some(kernel.value)
    _ -> None
  }
}

/// The PN-counter's current optimistic value, `None` when the address is
/// missing or not a pn-counter channel.
pub fn pn_counter_value(core: Core, address: String) -> Option(Int) {
  case find_channel(core, address) {
    Some(channel.PnCounterState(kernel)) ->
      Some(pn_counter_kernel.value(kernel))
    _ -> None
  }
}

/// The accepted value for `key` in the PactMap at `address`, `None` when the
/// key has no accepted value (still pending or absent) or the address is not a
/// PactMap channel.
pub fn pact_map_get(core: Core, address: String, key: String) -> Option(Json) {
  case find_channel(core, address) {
    Some(channel.PactMapState(kernel)) -> pact_map_kernel.get(kernel, key)
    _ -> None
  }
}

/// The accepted entry (value + sequence number) for `key`, `None` when absent.
pub fn pact_map_get_with_details(
  core: Core,
  address: String,
  key: String,
) -> Option(pact_map_kernel.Accepted) {
  case find_channel(core, address) {
    Some(channel.PactMapState(kernel)) ->
      pact_map_kernel.get_with_details(kernel, key)
    _ -> None
  }
}

/// Whether `key` currently has a pending (proposed but not-yet-accepted) value.
pub fn pact_map_is_pending(core: Core, address: String, key: String) -> Bool {
  case find_channel(core, address) {
    Some(channel.PactMapState(kernel)) ->
      pact_map_kernel.is_pending(kernel, key)
    _ -> False
  }
}

/// All keys with an accepted or pending pact, sorted.
pub fn pact_map_keys(core: Core, address: String) -> List(String) {
  case find_channel(core, address) {
    Some(channel.PactMapState(kernel)) -> pact_map_kernel.keys(kernel)
    _ -> []
  }
}

pub fn or_map_value(
  core: Core,
  address: String,
  key: String,
) -> Option(or_map_kernel.OrMapValue) {
  case find_channel(core, address) {
    Some(channel.OrMapState(kernel)) -> or_map_kernel.get(kernel, key)
    _ -> None
  }
}

pub fn or_map_keys(core: Core, address: String) -> List(String) {
  case find_channel(core, address) {
    Some(channel.OrMapState(kernel)) -> or_map_kernel.keys(kernel)
    _ -> []
  }
}

pub fn or_map_entries(
  core: Core,
  address: String,
) -> List(#(String, or_map_kernel.OrMapValue)) {
  case find_channel(core, address) {
    Some(channel.OrMapState(kernel)) -> or_map_kernel.entries(kernel)
    _ -> []
  }
}

pub fn or_set_contains(core: Core, address: String, element: String) -> Bool {
  case find_channel(core, address) {
    Some(channel.OrSetState(kernel)) -> or_set_kernel.contains(kernel, element)
    _ -> False
  }
}

pub fn or_set_values(core: Core, address: String) -> List(String) {
  case find_channel(core, address) {
    Some(channel.OrSetState(kernel)) -> or_set_kernel.values(kernel)
    _ -> []
  }
}

pub fn g_set_contains(core: Core, address: String, element: String) -> Bool {
  case find_channel(core, address) {
    Some(channel.GSetState(kernel)) -> g_set_kernel.contains(kernel, element)
    _ -> False
  }
}

pub fn g_set_values(core: Core, address: String) -> List(String) {
  case find_channel(core, address) {
    Some(channel.GSetState(kernel)) -> g_set_kernel.values(kernel)
    _ -> []
  }
}

pub fn two_p_set_contains(
  core: Core,
  address: String,
  element: String,
) -> Bool {
  case find_channel(core, address) {
    Some(channel.TwoPSetState(kernel)) ->
      two_p_set_kernel.contains(kernel, element)
    _ -> False
  }
}

pub fn two_p_set_values(core: Core, address: String) -> List(String) {
  case find_channel(core, address) {
    Some(channel.TwoPSetState(kernel)) -> two_p_set_kernel.values(kernel)
    _ -> []
  }
}

/// Optimistic read of a directory key at `path` (pending edits applied).
pub fn directory_get(
  core: Core,
  address: String,
  path: String,
  key: String,
) -> Option(Json) {
  case find_channel(core, address) {
    Some(channel.DirectoryState(kernel)) ->
      directory_kernel.get(kernel, path, key)
    _ -> None
  }
}

/// Ordered optimistic `#(key, value)` entries of the directory at `path`.
pub fn directory_entries(
  core: Core,
  address: String,
  path: String,
) -> List(#(String, Json)) {
  case find_channel(core, address) {
    Some(channel.DirectoryState(kernel)) ->
      directory_kernel.entries(kernel, path)
    _ -> []
  }
}

/// Ordered optimistic child directory names of the directory at `path`.
pub fn directory_subdirectories(
  core: Core,
  address: String,
  path: String,
) -> List(String) {
  case find_channel(core, address) {
    Some(channel.DirectoryState(kernel)) ->
      directory_kernel.subdirectories(kernel, path)
    _ -> []
  }
}

pub fn directory_has_subdirectory(
  core: Core,
  address: String,
  path: String,
  name: String,
) -> Bool {
  case find_channel(core, address) {
    Some(channel.DirectoryState(kernel)) ->
      directory_kernel.has_subdirectory(kernel, path, name)
    _ -> False
  }
}

pub fn register_read(
  core: Core,
  address: String,
  key: String,
  policy: register_collection_kernel.ReadPolicy,
) -> Option(Json) {
  case find_channel(core, address) {
    Some(channel.RegisterCollectionState(kernel)) ->
      register_collection_kernel.read(kernel, key, policy)
    _ -> None
  }
}

pub fn register_versions(
  core: Core,
  address: String,
  key: String,
) -> Option(List(Json)) {
  case find_channel(core, address) {
    Some(channel.RegisterCollectionState(kernel)) ->
      register_collection_kernel.read_versions(kernel, key)
    _ -> None
  }
}

pub fn register_keys(core: Core, address: String) -> List(String) {
  case find_channel(core, address) {
    Some(channel.RegisterCollectionState(kernel)) ->
      register_collection_kernel.keys(kernel)
    _ -> []
  }
}

pub fn get_claim(core: Core, address: String, key: String) -> Option(Json) {
  case find_channel(core, address) {
    Some(channel.ClaimsState(kernel)) -> claims_kernel.get(kernel, key)
    _ -> None
  }
}

pub fn has_claim(core: Core, address: String, key: String) -> Bool {
  case find_channel(core, address) {
    Some(channel.ClaimsState(kernel)) -> claims_kernel.has(kernel, key)
    _ -> False
  }
}

pub fn task_manager_assigned(
  core: Core,
  address: String,
  task_id: String,
) -> Bool {
  case find_channel(core, address) {
    Some(channel.TaskManagerState(kernel)) ->
      task_manager_kernel.assigned(
        kernel,
        task_id,
        client_id_to_int(core.client_id),
        True,
      )
    _ -> False
  }
}

pub fn task_manager_queued(
  core: Core,
  address: String,
  task_id: String,
) -> Bool {
  case find_channel(core, address) {
    Some(channel.TaskManagerState(kernel)) ->
      task_manager_kernel.queued(
        kernel,
        task_id,
        client_id_to_int(core.client_id),
        True,
      )
    _ -> False
  }
}

pub fn task_manager_queues(
  core: Core,
  address: String,
) -> List(#(String, List(Int))) {
  case find_channel(core, address) {
    Some(channel.TaskManagerState(kernel)) ->
      task_manager_kernel.summary_queues(kernel)
    _ -> []
  }
}

fn find_channel(core: Core, address: String) -> Option(ChannelState) {
  case dict.get(core.channels, address) {
    Ok(state) -> Some(state)
    Error(_) ->
      case dict.get(core.detached, address) {
        Ok(state) -> Some(state)
        Error(_) -> None
      }
  }
}

fn put_attached_channel(
  core: Core,
  address: String,
  state: ChannelState,
) -> Core {
  Core(..core, channels: dict.insert(core.channels, address, state))
}

fn put_detached_channel(
  core: Core,
  address: String,
  state: ChannelState,
) -> Core {
  Core(..core, detached: dict.insert(core.detached, address, state))
}

fn add_attached_channel(
  core: Core,
  address: String,
  state: ChannelState,
) -> Core {
  Core(
    ..core,
    channels: dict.insert(core.channels, address, state),
    channel_order: list.unique(list.append(core.channel_order, [address])),
  )
}

fn client_id_to_int(client_id: String) -> Int {
  client_id.to_int(client_id)
}
