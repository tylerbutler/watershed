//// The in-memory sluice's pure, target-agnostic core: a levee-shaped sequencer
//// over parsed wire frames.
////
//// It reuses spillway's *real* `sequencing` module (the same SN/MSN/CSN logic
//// the production server runs) and the inverse codecs in `sluice/frames`, so a
//// runtime under test exercises byte-identical client code paths against a
//// faithful server. Everything here is a pure function of state — no actors,
//// no clock, no I/O. The erlang and JavaScript drivers (`watershed/sluice`,
//// `watershed/sluice_js`) wrap this with a mailbox and delivery controls.
////
//// Delivery is explicit (plan decision 3): ops sequence on `handle` but land
//// in the `outbox`, delivered only when a driver calls `take`. That is what
//// makes races scriptable — "A and B both claim the cell, deliver B first" is
//// a sequence of `take` calls, not a timing accident.

import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/set.{type Set}
import gleam/string

import spillway/sequencing.{type SequenceState}
import spillway/types.{type Client}

import watershed/sluice/frames.{type Sequenced, Sequenced}

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────

/// A frame the sluice owes one client, awaiting an explicit `take`.
pub type Outbound {
  Outbound(client_id: String, event: String, payload: Json)
}

type ClientEntry {
  ClientEntry(client: Client, scopes: List(String))
}

/// One document's worth of sluice state. Pure; a driver owns the mutable cell.
pub opaque type Sluice {
  Sluice(
    document_id: String,
    tenant_id: String,
    seq: SequenceState,
    /// Full op history in ascending sequence-number order. Late joiners and
    /// reconnects replay from here (plan decision 5: no summary store in v1).
    log: List(Sequenced),
    clients: Dict(String, ClientEntry),
    /// Clients whose inbound frames are held (the `pause`/`resume` control).
    paused: Set(String),
    next_client_number: Int,
    now_ms: Int,
    /// Frames awaiting delivery, oldest first.
    outbox: List(Outbound),
  )
}

/// A fresh sluice for one document. `now_ms` starts at 0 and only moves via
/// `advance`, so TTL logic (presence prune) is testable without sleeping.
pub fn new(
  tenant_id tenant_id: String,
  document_id document_id: String,
) -> Sluice {
  Sluice(
    document_id: document_id,
    tenant_id: tenant_id,
    seq: sequencing.new(),
    log: [],
    clients: dict.new(),
    paused: set.new(),
    next_client_number: 1,
    now_ms: 0,
    outbox: [],
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// Clock
// ─────────────────────────────────────────────────────────────────────────────

/// The sluice's logical wall clock (ms). Only `advance` moves it.
pub fn now(sluice: Sluice) -> Int {
  sluice.now_ms
}

/// Advance the logical clock, so time-dependent behavior (presence TTL) can be
/// driven deterministically.
pub fn advance(sluice: Sluice, ms: Int) -> Sluice {
  Sluice(..sluice, now_ms: sluice.now_ms + ms)
}

// ─────────────────────────────────────────────────────────────────────────────
// Connection lifecycle
// ─────────────────────────────────────────────────────────────────────────────

/// Reserve a client id for a newly opened connection. The client only becomes
/// known to the sequencer once its `connect_document` arrives (`handle`), so
/// this just mints the id the driver keys the link by.
pub fn register(sluice: Sluice) -> #(Sluice, String) {
  let client_id = "sluice-client-" <> int.to_string(sluice.next_client_number)
  #(
    Sluice(..sluice, next_client_number: sluice.next_client_number + 1),
    client_id,
  )
}

/// Drop a client: remove it from the sequencer's MSN calculation and from the
/// paused set. Queued frames it never received are discarded on `take`.
pub fn disconnect(sluice: Sluice, client_id: String) -> Sluice {
  Sluice(
    ..sluice,
    seq: sequencing.client_leave(sluice.seq, client_id),
    clients: dict.delete(sluice.clients, client_id),
    paused: set.delete(sluice.paused, client_id),
  )
}

/// Hold a client's inbound frames (they stay queued until `resume`). Lets a
/// test deliver one peer's op before another's.
pub fn pause(sluice: Sluice, client_id: String) -> Sluice {
  Sluice(..sluice, paused: set.insert(sluice.paused, client_id))
}

/// Release a paused client's held frames back into the deliverable queue.
pub fn resume(sluice: Sluice, client_id: String) -> Sluice {
  Sluice(..sluice, paused: set.delete(sluice.paused, client_id))
}

// ─────────────────────────────────────────────────────────────────────────────
// Inbound frame handling
// ─────────────────────────────────────────────────────────────────────────────

/// Process one client→server push, keyed by the connection's assigned client
/// id. Sequences ops, appends to the log, and enqueues resulting frames.
/// Malformed or out-of-protocol frames are ignored (a well-behaved runtime
/// never sends them).
pub fn handle(
  sluice: Sluice,
  client_id: String,
  event: String,
  payload: Dynamic,
) -> Sluice {
  case event {
    "connect_document" -> on_connect_document(sluice, client_id, payload)
    "submitOp" -> on_submit_op(sluice, payload)
    "requestOps" -> on_request_ops(sluice, client_id, payload)
    "noop" -> on_noop(sluice, payload)
    "submitSignal" -> on_signal(sluice, payload)
    _ -> sluice
  }
}

fn on_connect_document(
  sluice: Sluice,
  client_id: String,
  payload: Dynamic,
) -> Sluice {
  case frames.decode_connect_document(payload) {
    Error(_) -> sluice
    Ok(request) -> {
      let current = sequencing.current_sn(sluice.seq)
      let last_seen = option.unwrap(request.last_seen_sequence_number, 0)
      // Join the sequencer at the current SN — the catch-up below brings the
      // client level with the document before any live op is delivered.
      let seq = sequencing.client_join(sluice.seq, client_id, current)
      let clients =
        dict.insert(
          sluice.clients,
          client_id,
          ClientEntry(client: request.client, scopes: request.client.scopes),
        )
      let catch_up = log_since(sluice.log, last_seen)
      let connected =
        frames.encode_connected(
          client_id: client_id,
          tenant_id: sluice.tenant_id,
          document_id: sluice.document_id,
          scopes: request.client.scopes,
          checkpoint_sequence_number: current,
          initial_messages: catch_up,
          timestamp: sluice.now_ms,
        )
      Sluice(..sluice, seq: seq, clients: clients)
      |> enqueue(client_id, "connect_document_success", connected)
    }
  }
}

fn on_submit_op(sluice: Sluice, payload: Dynamic) -> Sluice {
  case frames.decode_submit_op(payload) {
    Error(_) -> sluice
    Ok(submit) ->
      list.flatten(submit.batches)
      |> list.fold(sluice, fn(sluice, op) {
        sequence_op(sluice, submit.client_id, op)
      })
  }
}

/// Assign a sequence number to one op and broadcast it to every connected
/// client — including the author, whose echo is the ack its kernel awaits.
fn sequence_op(
  sluice: Sluice,
  client_id: String,
  op: frames.SubmittedOp,
) -> Sluice {
  case
    sequencing.assign_sequence_number(
      sluice.seq,
      client_id,
      op.client_sequence_number,
      op.reference_sequence_number,
    )
  {
    sequencing.SequenceError(_) -> sluice
    sequencing.SequenceOk(state: seq, assigned_sn: sn, msn: msn) -> {
      let sequenced =
        Sequenced(
          client_id: Some(client_id),
          sequence_number: sn,
          minimum_sequence_number: msn,
          client_sequence_number: op.client_sequence_number,
          reference_sequence_number: op.reference_sequence_number,
          op_type: op.op_type,
          contents: op.contents,
          metadata: op.metadata,
          timestamp: sluice.now_ms,
        )
      let event = frames.encode_op_event(sluice.document_id, [sequenced])
      Sluice(..sluice, seq: seq, log: [sequenced, ..sluice.log])
      |> broadcast("op", event)
    }
  }
}

fn on_request_ops(
  sluice: Sluice,
  client_id: String,
  payload: Dynamic,
) -> Sluice {
  case frames.decode_request_ops(payload) {
    Error(_) -> sluice
    Ok(from) -> {
      let ops = log_since(sluice.log, from - 1)
      case ops {
        [] -> sluice
        _ ->
          enqueue(
            sluice,
            client_id,
            "op",
            frames.encode_op_event(sluice.document_id, ops),
          )
      }
    }
  }
}

fn on_noop(sluice: Sluice, payload: Dynamic) -> Sluice {
  case frames.decode_noop(payload) {
    Error(_) -> sluice
    Ok(#(client_id, rsn)) ->
      case sequencing.update_client_rsn(sluice.seq, client_id, rsn) {
        Ok(seq) -> Sluice(..sluice, seq: seq)
        Error(_) -> sluice
      }
  }
}

fn on_signal(sluice: Sluice, payload: Dynamic) -> Sluice {
  case frames.decode_submit_signal(payload) {
    Error(_) -> sluice
    Ok(signal) -> {
      let frame = frames.encode_signal(signal.client_id, signal.content)
      // Fan out to everyone *except* the author (a client never hears its own
      // ripple), stripping the `type` tag the way levee does.
      connected_ids(sluice)
      |> list.filter(fn(id) { id != signal.client_id })
      |> list.fold(sluice, fn(sluice, id) {
        enqueue(sluice, id, "signal", frame)
      })
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Delivery
// ─────────────────────────────────────────────────────────────────────────────

/// Deliver the oldest frame owed to a non-paused client, removing it from the
/// queue. Returns `None` when nothing is deliverable (empty, or every pending
/// frame belongs to a paused client).
pub fn take(sluice: Sluice) -> #(Sluice, Option(Outbound)) {
  case pop_deliverable(sluice.outbox, sluice.paused, []) {
    Error(Nil) -> #(sluice, None)
    Ok(#(frame, rest)) -> #(Sluice(..sluice, outbox: rest), Some(frame))
  }
}

/// The next frame `take` would deliver, without removing it. `None` when
/// nothing is deliverable. Lets a caller group a whole broadcast wave (frames
/// sharing an op's sequence number) before committing to deliver it.
pub fn peek(sluice: Sluice) -> Option(Outbound) {
  case pop_deliverable(sluice.outbox, sluice.paused, []) {
    Error(Nil) -> None
    Ok(#(frame, _rest)) -> Some(frame)
  }
}

/// Whether any frame is deliverable right now (a non-paused client is owed one).
pub fn has_pending(sluice: Sluice) -> Bool {
  list.any(sluice.outbox, fn(frame) {
    !set.contains(sluice.paused, frame.client_id)
  })
}

/// Every frame currently queued, oldest first (paused or not). For assertions
/// and diagnostics.
pub fn outbox(sluice: Sluice) -> List(Outbound) {
  sluice.outbox
}

/// The connected clients, in a stable (sorted) order.
pub fn connected_ids(sluice: Sluice) -> List(String) {
  sluice.clients |> dict.keys() |> list.sort(string.compare)
}

/// The current server sequence number.
pub fn sequence_number(sluice: Sluice) -> Int {
  sequencing.current_sn(sluice.seq)
}

// ─────────────────────────────────────────────────────────────────────────────
// Internals
// ─────────────────────────────────────────────────────────────────────────────

fn enqueue(
  sluice: Sluice,
  client_id: String,
  event: String,
  payload: Json,
) -> Sluice {
  Sluice(
    ..sluice,
    outbox: list.append(sluice.outbox, [Outbound(client_id, event, payload)]),
  )
}

/// Enqueue one frame to every connected client (used for op echoes/broadcasts).
fn broadcast(sluice: Sluice, event: String, payload: Json) -> Sluice {
  connected_ids(sluice)
  |> list.fold(sluice, fn(sluice, id) { enqueue(sluice, id, event, payload) })
}

/// Ops with sequence number strictly greater than `after`, ascending.
fn log_since(log: List(Sequenced), after: Int) -> List(Sequenced) {
  log
  |> list.reverse()
  |> list.filter(fn(op) { op.sequence_number > after })
}

/// Pop the first frame whose client is not paused, preserving queue order
/// among the frames left behind. `skipped` accumulates the paused frames we
/// stepped over so they can be spliced back ahead of `rest`.
fn pop_deliverable(
  remaining: List(Outbound),
  paused: Set(String),
  skipped: List(Outbound),
) -> Result(#(Outbound, List(Outbound)), Nil) {
  case remaining {
    [] -> Error(Nil)
    [frame, ..rest] ->
      case set.contains(paused, frame.client_id) {
        True -> pop_deliverable(rest, paused, [frame, ..skipped])
        False -> Ok(#(frame, list.append(list.reverse(skipped), rest)))
      }
  }
}
