//// Pure per-connection state machine, driven by the runtime actor.
////
//// Owns the client half of spillway's sequencing discipline: CSN strictly
//// increasing per connection, RSN = last seen sequence number, dedupe by SN,
//// FIFO ack matching, and optimistic local state for attached and detached
//// channels. Kernel state, ops, and events flow through the closed sums in
//// `watershed/channel`; the sequencing discipline itself is kernel-agnostic.

import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result

import spillway/message.{type ConnectedMessage}
import spillway/types.{type SequencedDocumentMessage}

import watershed/channel.{
  type ChannelEvent, type ChannelState, type Snapshot, SequencedMeta,
}
import watershed/counter_kernel
import watershed/handle
import watershed/map_kernel
import watershed/or_map_kernel
import watershed/register_collection_kernel
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
}

pub type Bootstrapped {
  Complete(core: Core)
  MissingPrefix(core: Core, checkpoint: Int, from: Int, to: Int)
}

pub type Ingested {
  Ingested(events: List(#(String, ChannelEvent)), request_ops_from: Option(Int))
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
  let #(next_csn, new_in_flight, outbound) =
    list.fold(core.in_flight, #(core.next_csn, [], []), fn(acc, entry) {
      let #(csn, entries, outbounds) = acc
      let #(restamped, outbound) = restamp_in_flight(core, entry, csn)
      #(
        csn + 1,
        list.append(entries, [restamped]),
        list.append(outbounds, [outbound]),
      )
    })

  #(Core(..core, next_csn: next_csn, in_flight: new_in_flight), outbound)
}

fn restamp_in_flight(
  core: Core,
  entry: InFlight,
  csn: Int,
) -> #(InFlight, wire.OutboundOp) {
  case entry {
    InFlightOp(address: address, op: op, meta: meta, ..) -> #(
      InFlightOp(
        client_id: core.client_id,
        csn: csn,
        address: address,
        op: op,
        meta: meta,
      ),
      ops.outbound_channel_op(
        address: address,
        client_sequence_number: csn,
        reference_sequence_number: core.last_seen_sn,
        op: op,
      ),
    )
    InFlightAttach(address: address, snapshot: snapshot, ..) -> #(
      InFlightAttach(
        client_id: core.client_id,
        csn: csn,
        address: address,
        snapshot: snapshot,
      ),
      ops.outbound_attach_op(
        address: address,
        client_sequence_number: csn,
        reference_sequence_number: core.last_seen_sn,
        snapshot: snapshot,
      ),
    )
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
    sn if sn < next -> Ok(#(core, Ingested([], None)))
    sn if sn > next -> {
      let request = case core.out_of_order {
        [] -> Some(core.last_seen_sn)
        _ -> None
      }
      let core =
        Core(..core, out_of_order: buffer_insert(core.out_of_order, msg))
      Ok(#(core, Ingested([], request)))
    }
    _ -> {
      use #(core, events) <- result.try(apply_one(core, msg))
      use #(core, drained) <- result.try(drain_buffer(core))
      Ok(#(core, Ingested(list.append(events, drained), None)))
    }
  }
}

fn apply_one(
  core: Core,
  msg: SequencedDocumentMessage,
) -> Result(#(Core, List(#(String, ChannelEvent))), CoreError) {
  let core = Core(..core, last_seen_sn: msg.sequence_number)
  case msg.message_type {
    "op" -> handle_op(core, msg)
    _ -> Ok(#(core, []))
  }
}

fn drain_buffer(
  core: Core,
) -> Result(#(Core, List(#(String, ChannelEvent))), CoreError) {
  case core.out_of_order {
    [head, ..rest] if head.sequence_number <= core.last_seen_sn ->
      drain_buffer(Core(..core, out_of_order: rest))
    [head, ..rest] if head.sequence_number == core.last_seen_sn + 1 -> {
      use #(core, events) <- result.try(apply_one(
        Core(..core, out_of_order: rest),
        head,
      ))
      use #(core, more) <- result.try(drain_buffer(core))
      Ok(#(core, list.append(events, more)))
    }
    _ -> Ok(#(core, []))
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
) -> Result(#(Core, List(#(String, ChannelEvent))), CoreError) {
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
                  )
                False ->
                  apply_remote_channel(
                    core,
                    msg.sequence_number,
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
) -> Result(#(Core, List(#(String, ChannelEvent))), CoreError) {
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
        ),
      )
  }
}

fn apply_remote_channel(
  core: Core,
  sequence_number: Int,
  address: String,
  state: ChannelState,
  op: channel.ChannelOp,
) -> Result(#(Core, List(#(String, ChannelEvent))), CoreError) {
  let meta =
    SequencedMeta(seq: sequence_number, last_seen_sn: core.last_seen_sn)
  case channel.apply_remote(state, op, meta) {
    Ok(#(state, events)) ->
      Ok(#(
        put_attached_channel(core, address, state),
        tag_events(address, events),
      ))
    Error(channel.UnexpectedAck(detail))
    | Error(channel.WrongChannelType(detail))
    | Error(channel.CorruptRemoteOp(detail)) -> Error(AckMismatch(detail))
  }
}

fn ack_own_attach(
  core: Core,
  message_client_id: Option(String),
  csn: Int,
  address: String,
  echoed: Snapshot,
) -> Result(#(Core, List(#(String, ChannelEvent))), CoreError) {
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
            True -> Ok(#(Core(..core, in_flight: rest), []))
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
) -> Result(#(Core, List(#(String, ChannelEvent))), CoreError) {
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
                )
              case channel.ack_local(state, op, meta, sequenced_meta) {
                Ok(#(state, events)) ->
                  Ok(#(
                    Core(
                      ..core,
                      channels: dict.insert(core.channels, address, state),
                      in_flight: rest,
                    ),
                    tag_events(address, events),
                  ))
                Error(channel.UnexpectedAck(detail))
                | Error(channel.WrongChannelType(detail))
                | Error(channel.CorruptRemoteOp(detail)) ->
                  Error(AckMismatch(detail))
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

fn tag_or_map_events(
  address: String,
  events: List(or_map_kernel.OrMapEvent),
) -> List(#(String, ChannelEvent)) {
  list.map(events, fn(event) { #(address, channel.OrMapEvent(event)) })
}

fn tag_register_collection_events(
  address: String,
  events: List(register_collection_kernel.RegisterEvent),
) -> List(#(String, ChannelEvent)) {
  list.map(events, fn(event) {
    #(address, channel.RegisterCollectionEvent(event))
  })
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
