//// Pure per-connection state machine, driven by the runtime actor.
////
//// Owns the client half of spillway's sequencing discipline: CSN strictly
//// increasing per connection, RSN = last seen sequence number, dedupe by SN,
//// FIFO ack matching, and optimistic local state for attached and detached
//// map channels.

import gleam/dict.{type Dict}
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result

import spillway/message.{type ConnectedMessage}
import spillway/types.{type SequencedDocumentMessage}

import watershed/handle
import watershed/map_kernel.{type MapEvent, type MapOp}
import watershed/wire
import watershed/wire/ops

const root_address = "root"

pub type Core {
  Core(
    client_id: String,
    channels: Dict(String, map_kernel.MapState),
    channel_order: List(String),
    detached: Dict(String, map_kernel.MapState),
    next_csn: Int,
    last_seen_sn: Int,
    in_flight: List(InFlight),
    out_of_order: List(SequencedDocumentMessage),
  )
}

pub type InFlight {
  InFlightOp(client_id: String, csn: Int, address: String, op: MapOp)
  InFlightAttach(
    client_id: String,
    csn: Int,
    address: String,
    snapshot: List(#(String, Json)),
  )
}

pub type CoreError {
  AckMismatch(detail: String)
  BadOpContents(sequence_number: Int)
  HistoryGap(detail: String)
  UnknownChannel(address: String, sequence_number: Int)
  DuplicateAttach(address: String, sequence_number: Int)
}

pub type Bootstrapped {
  Complete(core: Core)
  MissingPrefix(core: Core, checkpoint: Int, from: Int, to: Int)
}

pub type Ingested {
  Ingested(events: List(#(String, MapEvent)), request_ops_from: Option(Int))
}

pub type Summary {
  Summary(
    sequence_number: Int,
    channels: List(#(String, List(#(String, Json)))),
  )
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
  let #(channels, channel_order) = seed_channels(seeded)

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

pub fn summary_channels(core: Core) -> List(#(String, List(#(String, Json)))) {
  list.filter_map(core.channel_order, fn(address) {
    case dict.get(core.channels, address) {
      Ok(kernel) -> Ok(#(address, map_kernel.sequenced_entries(kernel)))
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
  seeded: List(#(String, List(#(String, Json)))),
) -> #(Dict(String, map_kernel.MapState), List(String)) {
  let #(channels, channel_order) =
    list.fold(seeded, #(dict.new(), []), fn(acc, entry) {
      let #(channels, channel_order) = acc
      let #(address, entries) = entry
      #(
        dict.insert(channels, address, map_kernel.from_sequenced(entries)),
        list.unique(list.append(channel_order, [address])),
      )
    })

  case dict.has_key(channels, root_address) {
    True -> #(channels, channel_order)
    False -> #(dict.insert(channels, root_address, map_kernel.new()), [
      root_address,
      ..channel_order
    ])
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
    InFlightOp(address: address, op: op, ..) -> #(
      InFlightOp(client_id: core.client_id, csn: csn, address: address, op: op),
      ops.outbound_map_op(
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
) -> Result(#(Core, List(#(String, MapEvent))), CoreError) {
  let core = Core(..core, last_seen_sn: msg.sequence_number)
  case msg.message_type {
    "op" -> handle_op(core, msg)
    _ -> Ok(#(core, []))
  }
}

fn drain_buffer(
  core: Core,
) -> Result(#(Core, List(#(String, MapEvent))), CoreError) {
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
) -> Result(#(Core, List(#(String, MapEvent))), CoreError) {
  case ops.decode_op_contents(msg.contents) {
    Error(_) -> Error(BadOpContents(msg.sequence_number))
    Ok(ops.AttachOp(address, channel_type, snapshot)) -> {
      case channel_type == wire.channel_type_map {
        False -> Error(BadOpContents(msg.sequence_number))
        True ->
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
      }
    }
    Ok(ops.ChannelOp(address, op)) ->
      case is_own_op(core, msg.client_id) {
        True ->
          ack_own_op(
            core,
            msg.client_id,
            msg.client_sequence_number,
            address,
            op,
          )
        False -> apply_remote_channel(core, msg.sequence_number, address, op)
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
  snapshot: List(#(String, Json)),
) -> Result(#(Core, List(#(String, MapEvent))), CoreError) {
  case has_channel(core, address) {
    True -> Error(DuplicateAttach(address, sequence_number))
    False ->
      Ok(
        #(
          add_attached_channel(
            core,
            address,
            map_kernel.from_sequenced(snapshot),
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
  op: MapOp,
) -> Result(#(Core, List(#(String, MapEvent))), CoreError) {
  case dict.get(core.channels, address) {
    Error(_) -> Error(UnknownChannel(address, sequence_number))
    Ok(kernel) -> {
      let #(kernel, events) = map_kernel.apply_remote(kernel, op)
      Ok(#(
        put_attached_channel(core, address, kernel),
        tag_events(address, events),
      ))
    }
  }
}

fn ack_own_attach(
  core: Core,
  message_client_id: Option(String),
  csn: Int,
  address: String,
  echoed: List(#(String, Json)),
) -> Result(#(Core, List(#(String, MapEvent))), CoreError) {
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
            && same_attach_shape(snapshot, echoed)
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
  echoed: MapOp,
) -> Result(#(Core, List(#(String, MapEvent))), CoreError) {
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
        ) ->
          case
            Some(client_id) == message_client_id
            && head_csn == csn
            && head_address == address
            && same_shape(op, echoed)
          {
            False ->
              Error(AckMismatch(
                "expected ack for csn "
                <> int.to_string(head_csn)
                <> ", got csn "
                <> int.to_string(csn),
              ))
            True ->
              case dict.get(core.channels, address) {
                Error(_) -> Error(UnknownChannel(address, core.last_seen_sn))
                Ok(kernel) ->
                  case map_kernel.ack_local(kernel, op) {
                    Ok(kernel) ->
                      Ok(
                        #(
                          Core(
                            ..core,
                            channels: dict.insert(
                              core.channels,
                              address,
                              kernel,
                            ),
                            in_flight: rest,
                          ),
                          [],
                        ),
                      )
                    Error(map_kernel.UnexpectedAck(_, detail)) ->
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

fn same_shape(ours: MapOp, echoed: MapOp) -> Bool {
  case ours, echoed {
    map_kernel.Set(our_key, _), map_kernel.Set(echoed_key, _) ->
      our_key == echoed_key
    map_kernel.Delete(our_key), map_kernel.Delete(echoed_key) ->
      our_key == echoed_key
    map_kernel.Clear, map_kernel.Clear -> True
    _, _ -> False
  }
}

fn same_attach_shape(
  ours: List(#(String, Json)),
  echoed: List(#(String, Json)),
) -> Bool {
  case ours, echoed {
    [], [] -> True
    [our, ..our_rest], [echoed, ..echoed_rest] ->
      our.0 == echoed.0
      && same_json_value(our.1, echoed.1)
      && same_attach_shape(our_rest, echoed_rest)
    _, _ -> False
  }
}

fn same_json_value(ours: Json, echoed: Json) -> Bool {
  case json.parse(json.to_string(ours), wire.json_value_decoder()) {
    Ok(normalized_ours) ->
      case json.parse(json.to_string(echoed), wire.json_value_decoder()) {
        Ok(normalized_echoed) -> normalized_ours == normalized_echoed
        Error(_) -> False
      }
    Error(_) -> False
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Outbound
// ─────────────────────────────────────────────────────────────────────────────

pub fn create_detached(core: Core, address: String) -> Core {
  case address == root_address || has_channel(core, address) {
    True -> core
    False ->
      Core(
        ..core,
        detached: dict.insert(core.detached, address, map_kernel.new()),
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
  #(Core, List(#(String, MapEvent)), List(wire.OutboundOp)),
  CoreError,
) {
  case dict.get(core.detached, address) {
    Ok(kernel) -> {
      let #(kernel, events, _op) = map_kernel.set(kernel, key, value)
      Ok(
        #(
          Core(..core, detached: dict.insert(core.detached, address, kernel)),
          tag_events(address, events),
          [],
        ),
      )
    }
    Error(_) ->
      case dict.get(core.channels, address) {
        Error(_) -> Error(UnknownChannel(address, core.last_seen_sn))
        Ok(_kernel) -> {
          let #(core, attach_outbound) = attach_dependencies(core, value)
          let assert Ok(kernel) = dict.get(core.channels, address)
          let #(kernel, events, op) = map_kernel.set(kernel, key, value)
          let #(core, events, outbound) =
            stamp_attached(core, address, kernel, events, op)
          Ok(#(core, events, list.append(attach_outbound, outbound)))
        }
      }
  }
}

pub fn delete(
  core: Core,
  address: String,
  key: String,
) -> Result(
  #(Core, List(#(String, MapEvent)), List(wire.OutboundOp)),
  CoreError,
) {
  case dict.get(core.detached, address) {
    Ok(kernel) -> {
      let #(kernel, events, _op) = map_kernel.delete(kernel, key)
      Ok(
        #(
          Core(..core, detached: dict.insert(core.detached, address, kernel)),
          tag_events(address, events),
          [],
        ),
      )
    }
    Error(_) ->
      case dict.get(core.channels, address) {
        Error(_) -> Error(UnknownChannel(address, core.last_seen_sn))
        Ok(kernel) -> {
          let #(kernel, events, op) = map_kernel.delete(kernel, key)
          Ok(stamp_attached(core, address, kernel, events, op))
        }
      }
  }
}

pub fn clear(
  core: Core,
  address: String,
) -> Result(
  #(Core, List(#(String, MapEvent)), List(wire.OutboundOp)),
  CoreError,
) {
  case dict.get(core.detached, address) {
    Ok(kernel) -> {
      let #(kernel, events, _op) = map_kernel.clear(kernel)
      Ok(
        #(
          Core(..core, detached: dict.insert(core.detached, address, kernel)),
          tag_events(address, events),
          [],
        ),
      )
    }
    Error(_) ->
      case dict.get(core.channels, address) {
        Error(_) -> Error(UnknownChannel(address, core.last_seen_sn))
        Ok(kernel) -> {
          let #(kernel, events, op) = map_kernel.clear(kernel)
          Ok(stamp_attached(core, address, kernel, events, op))
        }
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
        Ok(kernel) -> {
          let deps = detached_handle_dependencies(kernel)
          let #(order, visited) = collect_attach_order(core, deps, visited)
          #(list.append(order, [address]), visited)
        }
      }
    }
  }
}

fn detached_handle_dependencies(kernel: map_kernel.MapState) -> List(String) {
  list.flat_map(map_kernel.entries(kernel), fn(entry) {
    handle.collect_handle_addresses(entry.1)
  })
  |> list.unique
}

fn submit_attaches(
  core: Core,
  addresses: List(String),
) -> #(Core, List(wire.OutboundOp)) {
  list.fold(addresses, #(core, []), fn(acc, address) {
    let #(core, outbound) = acc
    case dict.get(core.detached, address) {
      Error(_) -> #(core, outbound)
      Ok(kernel) -> {
        let snapshot = map_kernel.entries(kernel)
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
              map_kernel.from_sequenced(snapshot),
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
  kernel: map_kernel.MapState,
  events: List(MapEvent),
  op: MapOp,
) -> #(Core, List(#(String, MapEvent)), List(wire.OutboundOp)) {
  let csn = core.next_csn
  let outbound =
    ops.outbound_map_op(
      address: address,
      client_sequence_number: csn,
      reference_sequence_number: core.last_seen_sn,
      op: op,
    )
  let core =
    Core(
      ..core,
      channels: dict.insert(core.channels, address, kernel),
      next_csn: csn + 1,
      in_flight: list.append(core.in_flight, [
        InFlightOp(
          client_id: core.client_id,
          csn: csn,
          address: address,
          op: op,
        ),
      ]),
    )
  #(core, tag_events(address, events), [outbound])
}

fn tag_events(
  address: String,
  events: List(MapEvent),
) -> List(#(String, MapEvent)) {
  list.map(events, fn(event) { #(address, event) })
}

// ─────────────────────────────────────────────────────────────────────────────
// Reads
// ─────────────────────────────────────────────────────────────────────────────

pub fn get(core: Core, address: String, key: String) -> Option(Json) {
  case find_channel(core, address) {
    Some(kernel) -> map_kernel.get(kernel, key)
    None -> None
  }
}

pub fn has(core: Core, address: String, key: String) -> Bool {
  get(core, address, key) != None
}

pub fn size(core: Core, address: String) -> Int {
  case find_channel(core, address) {
    Some(kernel) -> map_kernel.size(kernel)
    None -> 0
  }
}

pub fn keys(core: Core, address: String) -> List(String) {
  case find_channel(core, address) {
    Some(kernel) -> map_kernel.keys(kernel)
    None -> []
  }
}

pub fn entries(core: Core, address: String) -> List(#(String, Json)) {
  case find_channel(core, address) {
    Some(kernel) -> map_kernel.entries(kernel)
    None -> []
  }
}

fn find_channel(core: Core, address: String) -> Option(map_kernel.MapState) {
  case dict.get(core.channels, address) {
    Ok(kernel) -> Some(kernel)
    Error(_) ->
      case dict.get(core.detached, address) {
        Ok(kernel) -> Some(kernel)
        Error(_) -> None
      }
  }
}

fn put_attached_channel(
  core: Core,
  address: String,
  kernel: map_kernel.MapState,
) -> Core {
  Core(..core, channels: dict.insert(core.channels, address, kernel))
}

fn add_attached_channel(
  core: Core,
  address: String,
  kernel: map_kernel.MapState,
) -> Core {
  Core(
    ..core,
    channels: dict.insert(core.channels, address, kernel),
    channel_order: list.unique(list.append(core.channel_order, [address])),
  )
}
