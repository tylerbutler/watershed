//// Pure per-connection state machine, driven by the runtime actor.
////
//// Owns the client half of spillway's sequencing discipline: CSN strictly
//// increasing per connection (stamped here), RSN = last seen sequence
//// number, dedupe by SN as a general invariant (`initialMessages` and
//// catch-up pushes overlap by design), and FIFO ack matching by
//// `(client_id, csn)` against the in-flight queue.
////
//// Every error variant is a divergence risk the caller must treat as fatal
//// (crash the actor, let the supervisor re-sync) rather than continue with
//// possibly-wrong state. Sequence gaps are also fatal for now; M4 replaces
//// that with buffering + `requestOps` catch-up.

import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, Some}
import gleam/result

import spillway/message.{type ConnectedMessage}
import spillway/types.{type SequencedDocumentMessage}

import watershed/map_kernel.{type MapEvent, type MapOp}
import watershed/wire

pub type Core {
  Core(
    /// Server-assigned identity for this connection.
    client_id: String,
    /// Channel address of the map this connection edits (v1: "root").
    address: String,
    kernel: map_kernel.MapState,
    /// Next client sequence number to stamp on an outbound op.
    next_csn: Int,
    /// Highest sequence number processed (or marked seen at bootstrap).
    last_seen_sn: Int,
    /// Ops submitted but not yet sequenced, oldest first.
    in_flight: List(#(Int, MapOp)),
  )
}

pub type CoreError {
  /// An op arrived beyond the next expected sequence number. M3 treats this
  /// as fatal; M4 adds buffering + requestOps.
  SequenceGap(expected: Int, got: Int)
  /// Our own sequenced op did not match the head of the in-flight queue.
  AckMismatch(detail: String)
  /// A sequenced `"op"` message carried contents we could not decode. With
  /// only map channels in v1 this signals corruption, not a foreign DDS.
  BadOpContents(sequence_number: Int)
}

// ─────────────────────────────────────────────────────────────────────────────
// Bootstrap
// ─────────────────────────────────────────────────────────────────────────────

/// Build the initial state from `connect_document_success`, replaying
/// `initialMessages` (full history, chronological).
///
/// `checkpointSequenceNumber` equals the SN of our own join message, which
/// arrives as a separate `op` push right after the success event and is not
/// in `initialMessages` — marking the checkpoint as already seen makes that
/// push dedupe cleanly without skipping anything that came before it.
pub fn bootstrap(
  connected: ConnectedMessage,
  address address: String,
) -> Result(Core, CoreError) {
  let core =
    Core(
      client_id: connected.client_id,
      address: address,
      kernel: map_kernel.new(),
      next_csn: 1,
      last_seen_sn: 0,
      in_flight: [],
    )
  use core <- result.try(
    list.try_fold(connected.initial_messages, core, fn(core, msg) {
      handle_sequenced(core, msg)
      |> result.map(fn(outcome) { outcome.0 })
    }),
  )
  let checkpoint =
    option.unwrap(connected.checkpoint_sequence_number, core.last_seen_sn)
  Ok(Core(..core, last_seen_sn: int.max(core.last_seen_sn, checkpoint)))
}

// ─────────────────────────────────────────────────────────────────────────────
// Inbound
// ─────────────────────────────────────────────────────────────────────────────

/// Process one sequenced message from the server, in arrival order.
///
/// Already-seen SNs are dropped silently; system message types (join, leave,
/// noop, summarize, ...) only advance `last_seen_sn`. Returned events are
/// ready for subscriber fan-out.
pub fn handle_sequenced(
  core: Core,
  msg: SequencedDocumentMessage,
) -> Result(#(Core, List(MapEvent)), CoreError) {
  let next = core.last_seen_sn + 1
  case msg.sequence_number {
    sn if sn < next -> Ok(#(core, []))
    sn if sn > next -> Error(SequenceGap(expected: next, got: sn))
    sn -> {
      let core = Core(..core, last_seen_sn: sn)
      case msg.message_type {
        "op" -> handle_op(core, msg)
        _ -> Ok(#(core, []))
      }
    }
  }
}

fn handle_op(
  core: Core,
  msg: SequencedDocumentMessage,
) -> Result(#(Core, List(MapEvent)), CoreError) {
  case wire.decode_map_envelope(msg.contents) {
    Error(_) -> Error(BadOpContents(msg.sequence_number))
    Ok(#(address, op)) ->
      case address == core.address {
        False -> Ok(#(core, []))
        True ->
          case msg.client_id == Some(core.client_id) {
            True -> ack_own(core, msg.client_sequence_number, op)
            False -> {
              let #(kernel, events) = map_kernel.apply_remote(core.kernel, op)
              Ok(#(Core(..core, kernel: kernel), events))
            }
          }
      }
  }
}

/// Commit the head in-flight op after the server sequenced it. The echoed
/// CSN must match the head exactly (submission order is FIFO); the op shape
/// is cross-checked too, though values are compared only by key since JSON
/// object key order does not survive the wire.
fn ack_own(
  core: Core,
  csn: Int,
  echoed: MapOp,
) -> Result(#(Core, List(MapEvent)), CoreError) {
  case core.in_flight {
    [] ->
      Error(AckMismatch(
        "own op sequenced with csn "
        <> int.to_string(csn)
        <> " but in-flight queue is empty",
      ))
    [#(head_csn, head_op), ..rest] ->
      case head_csn == csn && same_shape(head_op, echoed) {
        False ->
          Error(AckMismatch(
            "expected ack for csn "
            <> int.to_string(head_csn)
            <> ", got csn "
            <> int.to_string(csn),
          ))
        True ->
          case map_kernel.ack_local(core.kernel, head_op) {
            Ok(kernel) ->
              Ok(#(Core(..core, kernel: kernel, in_flight: rest), []))
            Error(map_kernel.UnexpectedAck(_, detail)) ->
              Error(AckMismatch(detail))
          }
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

// ─────────────────────────────────────────────────────────────────────────────
// Outbound
// ─────────────────────────────────────────────────────────────────────────────

pub fn set(
  core: Core,
  key: String,
  value: Json,
) -> #(Core, List(MapEvent), wire.OutboundOp) {
  let #(kernel, events, op) = map_kernel.set(core.kernel, key, value)
  stamp(core, kernel, events, op)
}

pub fn delete(
  core: Core,
  key: String,
) -> #(Core, List(MapEvent), wire.OutboundOp) {
  let #(kernel, events, op) = map_kernel.delete(core.kernel, key)
  stamp(core, kernel, events, op)
}

pub fn clear(core: Core) -> #(Core, List(MapEvent), wire.OutboundOp) {
  let #(kernel, events, op) = map_kernel.clear(core.kernel)
  stamp(core, kernel, events, op)
}

fn stamp(
  core: Core,
  kernel: map_kernel.MapState,
  events: List(MapEvent),
  op: MapOp,
) -> #(Core, List(MapEvent), wire.OutboundOp) {
  let csn = core.next_csn
  let outbound =
    wire.outbound_map_op(
      address: core.address,
      client_sequence_number: csn,
      reference_sequence_number: core.last_seen_sn,
      op: op,
    )
  let core =
    Core(
      ..core,
      kernel: kernel,
      next_csn: csn + 1,
      in_flight: list.append(core.in_flight, [#(csn, op)]),
    )
  #(core, events, outbound)
}

// ─────────────────────────────────────────────────────────────────────────────
// Reads (optimistic, delegated to the kernel)
// ─────────────────────────────────────────────────────────────────────────────

pub fn get(core: Core, key: String) -> Option(Json) {
  map_kernel.get(core.kernel, key)
}

pub fn has(core: Core, key: String) -> Bool {
  map_kernel.has(core.kernel, key)
}

pub fn size(core: Core) -> Int {
  map_kernel.size(core.kernel)
}

pub fn keys(core: Core) -> List(String) {
  map_kernel.keys(core.kernel)
}

pub fn entries(core: Core) -> List(#(String, Json)) {
  map_kernel.entries(core.kernel)
}
