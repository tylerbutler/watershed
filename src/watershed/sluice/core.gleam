//// The in-memory sluice's pure, target-agnostic core: a floodgate-shaped sequencer
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
import gleam/result
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
    /// Presence tracked per *connection*, keyed by client id. Version one
    /// supports one registration per document connection, so an app puts panel,
    /// cursor, and activity into one metadata value.
    presence: Dict(String, frames.PresenceMeta),
    /// Deterministic `phx_ref` source. Phoenix mints random refs; the sluice
    /// mints `ref-1`, `ref-2`, … for the same reason it mints
    /// `sluice-client-N` — a test asserts on frames, so frames must be
    /// reproducible.
    next_presence_ref: Int,
    /// Whether the handshake advertises `presence_v1`. Tests turn it off to
    /// drive the capability-absent paths: `Auto` falling back to ripples, and a
    /// forced `Server` failing loudly.
    presence_supported: Bool,
    /// Clients whose inbound frames are held (the `pause`/`resume` control).
    paused: Set(String),
    next_client_number: Int,
    now_ms: Int,
    /// Frames awaiting delivery, oldest first.
    outbox: List(Outbound),
  )
}

/// A fresh sluice for one document. `now_ms` starts at 0 and only moves via
/// `advance`, keeping protocol frame timestamps deterministic in tests.
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
    presence: dict.new(),
    next_presence_ref: 1,
    presence_supported: True,
    paused: set.new(),
    next_client_number: 1,
    now_ms: 0,
    outbox: [],
  )
}

/// Withhold `presence_v1` from the handshake, so a client under `Auto` picks the
/// ripple fallback and a client forcing `Server` fails. Call before `connect`.
pub fn set_presence_supported(sluice: Sluice, supported: Bool) -> Sluice {
  Sluice(..sluice, presence_supported: supported)
}

// ─────────────────────────────────────────────────────────────────────────────
// Clock
// ─────────────────────────────────────────────────────────────────────────────

/// The sluice's logical wall clock (ms). Only `advance` moves it.
pub fn now(sluice: Sluice) -> Int {
  sluice.now_ms
}

/// Advance the logical clock used for protocol frame timestamps.
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

/// Drop a client: sequence a `"leave"` for the remaining clients, remove it
/// from the sequencer's MSN calculation and from the paused set. Queued frames
/// it never received are discarded on `take`.
///
/// The leave is what settles per-client kernel state on every surviving replica
/// — re-released queue jobs, drained consensus signoffs — at one agreed
/// sequence point. A client that never completed `connect_document` is not in
/// the roster, so its disconnect sequences nothing.
pub fn disconnect(sluice: Sluice, client_id: String) -> Sluice {
  let known = dict.has_key(sluice.clients, client_id)
  let sluice =
    Sluice(
      ..sluice,
      seq: sequencing.client_leave(sluice.seq, client_id),
      clients: dict.delete(sluice.clients, client_id),
      paused: set.delete(sluice.paused, client_id),
    )
  // Drop the socket's presence with the socket. This is the property server
  // presence exists for: a browser that closed its tab or lost its network
  // stops being present without having to say so, and without anyone waiting
  // out a heartbeat TTL. Both the forced-reconnect drop and a real disconnect
  // route through here, so both clean up.
  let sluice = on_leave_presence(sluice, client_id)
  case known {
    False -> sluice
    True -> {
      let #(sluice, leave) =
        sequence_system(sluice, "leave", frames.system_leave_data(client_id))
      broadcast(sluice, "op", frames.encode_op_event([leave]))
    }
  }
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
    "joinPresence" -> on_join_presence(sluice, client_id, payload)
    "updatePresence" -> on_update_presence(sluice, client_id, payload)
    "leavePresence" -> on_leave_presence(sluice, client_id)
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
      // Join the sequencer at the current SN — the catch-up below brings the
      // client level with the document before any live op is delivered.
      let seq = sequencing.client_join(sluice.seq, client_id, current)

      // Sequence the join *before* the joiner is added to `clients`, so the
      // broadcast reaches the existing room only: the joiner receives its own
      // copy through `initial_messages` instead, which is how a real server
      // orders it.
      let #(sluice, join) =
        Sluice(..sluice, seq: seq)
        |> sequence_system("join", frames.system_join_data(client_id))
      let sluice = broadcast(sluice, "op", frames.encode_op_event([join]))

      let clients =
        dict.insert(
          sluice.clients,
          client_id,
          ClientEntry(client: request.client, scopes: request.client.scopes),
        )
      let sluice = Sluice(..sluice, clients: clients)
      let connected =
        frames.encode_connected(
          client_id: client_id,
          tenant_id: sluice.tenant_id,
          document_id: sluice.document_id,
          scopes: request.client.scopes,
          checkpoint_sequence_number: sequencing.current_sn(sluice.seq),
          initial_clients: connected_ids(sluice),
          // The whole retained log, *not* the slice after the request's
          // `lastSeenSequenceNumber`. Floodgate ignores that field entirely and
          // answers every connect — first or thousandth — with the same recent
          // history, so filtering here would model a server that does not
          // exist. It costs a reconnecting client nothing either way: its
          // `adopt_reconnect` never replays `initial_messages`.
          initial_messages: log_since(sluice.log, 0),
          timestamp: sluice.now_ms,
          presence_v1: sluice.presence_supported,
        )
      // The joiner's own join is *not* pushed back to it as a live op. Floodgate
      // broadcasts it with `broadcast_from(channels, cid, ...)`, which excludes
      // the joiner — its only copy is the one in `initial_messages`.
      //
      // The sluice used to send it anyway, and that single extra frame was
      // Essential: a reconnecting runtime ignores `initial_messages`, so the
      // push was the one thing carrying it up to the handshake's checkpoint and
      // out of its holding state. Against a real server nothing supplies it,
      // which is why every sluice reconnect test passed while the live path
      // stalled forever. The runtime now asks for the gap itself, with
      // `requestOps` on the handshake, so the crutch can go.
      enqueue(sluice, client_id, "connect_document_success", connected)
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
          data: None,
        )
      let event = frames.encode_op_event([sequenced])
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
      // Exclusive of `from`, matching floodgate's `session.since` (`o.0 > sn`)
      // and what the runtime means when it asks: `from` is the last SN it has,
      // not the first it wants. This used to be `from - 1`, one op generous —
      // harmless in itself, since the runtime drops the duplicate, but it meant
      // the sluice could never catch an off-by-one on the client side.
      let ops = log_since(sluice.log, from)
      case ops {
        [] -> sluice
        _ -> enqueue(sluice, client_id, "op", frames.encode_op_event(ops))
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
      // ripple), stripping the `type` tag the way floodgate does.
      connected_ids(sluice)
      |> list.filter(fn(id) { id != signal.client_id })
      |> list.fold(sluice, fn(sluice, id) {
        enqueue(sluice, id, "signal", frame)
      })
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Presence
// ─────────────────────────────────────────────────────────────────────────────

/// Register this connection's presence.
///
/// The ordering here is Phoenix's state-plus-diff synchronization, and it is
/// what lets a joiner converge without locking the topic: snapshot the roster,
/// send it to the joiner alone, *then* track and broadcast the join. The joiner
/// therefore learns of its own session from the diff, not the snapshot, and a
/// remote change racing the snapshot is simply a diff the client queues.
fn on_join_presence(
  sluice: Sluice,
  client_id: String,
  payload: Dynamic,
) -> Sluice {
  case authenticated_key(sluice, client_id) {
    Error(frame) -> enqueue(sluice, client_id, "presence_error", frame)
    Ok(key) ->
      case read_meta(payload) {
        Error(frame) -> enqueue(sluice, client_id, "presence_error", frame)
        Ok(fields) -> {
          // Snapshot *before* inserting, so the joiner's own session arrives
          // through the diff below.
          let snapshot =
            enqueue(
              sluice,
              client_id,
              "presence_state",
              frames.encode_presence_state(dict.to_list(sluice.presence)),
            )
          let #(snapshot, meta) = track(snapshot, key, fields)
          Sluice(
            ..snapshot,
            presence: dict.insert(snapshot.presence, client_id, meta),
          )
          |> broadcast_presence(joins: [#(client_id, meta)], leaves: [])
        }
      }
  }
}

/// Replace this connection's metadata.
///
/// Emitted as one diff carrying a leave of the old `phx_ref` and a join of the
/// new one — both what Phoenix emits and what an untrack-then-track on the
/// server produces, so a Phoenix client already understands the sequence.
fn on_update_presence(
  sluice: Sluice,
  client_id: String,
  payload: Dynamic,
) -> Sluice {
  case dict.get(sluice.presence, client_id) {
    Error(Nil) ->
      enqueue(
        sluice,
        client_id,
        "presence_error",
        frames.encode_presence_error(
          code: "not_joined",
          message: "this connection has no presence to update",
        ),
      )
    Ok(previous) ->
      case read_meta(payload) {
        Error(frame) -> enqueue(sluice, client_id, "presence_error", frame)
        Ok(fields) -> {
          let #(sluice, meta) = track(sluice, previous.key, fields)
          Sluice(
            ..sluice,
            presence: dict.insert(sluice.presence, client_id, meta),
          )
          |> broadcast_presence(joins: [#(client_id, meta)], leaves: [
            #(client_id, previous),
          ])
        }
      }
  }
}

/// Drop this connection's presence. A connection with none is a silent no-op:
/// a duplicate leave, or one racing the socket's own cleanup, must not error.
fn on_leave_presence(sluice: Sluice, client_id: String) -> Sluice {
  case dict.get(sluice.presence, client_id) {
    Error(Nil) -> sluice
    Ok(previous) ->
      Sluice(..sluice, presence: dict.delete(sluice.presence, client_id))
      |> broadcast_presence(joins: [], leaves: [#(client_id, previous)])
  }
}

/// Mint a `phx_ref` and pair it with the metadata it stamps.
fn track(
  sluice: Sluice,
  key: String,
  fields: List(#(String, Json)),
) -> #(Sluice, frames.PresenceMeta) {
  let phx_ref = "ref-" <> int.to_string(sluice.next_presence_ref)
  #(
    Sluice(..sluice, next_presence_ref: sluice.next_presence_ref + 1),
    frames.PresenceMeta(key: key, phx_ref: phx_ref, fields: fields),
  )
}

/// Broadcast a presence change to **every** connected client, the joiner
/// included. That is deliberately unlike `on_signal`, which excludes the
/// author: Phoenix presence is topic-wide, and a joiner that never heard its
/// own join would hold a roster missing itself.
fn broadcast_presence(
  sluice: Sluice,
  joins joins: List(#(String, frames.PresenceMeta)),
  leaves leaves: List(#(String, frames.PresenceMeta)),
) -> Sluice {
  broadcast(
    sluice,
    "presence_diff",
    frames.encode_presence_diff(joins: joins, leaves: leaves),
  )
}

/// The presence key for a connection: its authenticated user id.
///
/// A connection that has not completed `connect_document` is not in `clients`
/// and has no authenticated identity to derive a key from, so it is rejected —
/// presence must never be attributable to an unauthenticated socket.
fn authenticated_key(
  sluice: Sluice,
  client_id: String,
) -> Result(String, Json) {
  case dict.get(sluice.clients, client_id) {
    Ok(entry) -> Ok(entry.client.user.id)
    Error(Nil) ->
      Error(frames.encode_presence_error(
        code: "unauthenticated",
        message: "presence requires a completed document connection",
      ))
  }
}

/// Read a presence command's metadata, rejecting an attempt to claim a
/// server-owned field. Reserved keys nested *inside* `meta` are stripped rather
/// than rejected (see `frames.decode_presence_meta`); naming one at the top
/// level is an identity claim, and worth an explicit error.
fn read_meta(payload: Dynamic) -> Result(List(#(String, Json)), Json) {
  case frames.names_reserved_field(payload) {
    True ->
      Error(frames.encode_presence_error(
        code: "invalid_meta",
        message: "the server owns key, session, and ref; a client cannot set them",
      ))
    False ->
      frames.decode_presence_meta(payload)
      |> result.map_error(fn(_) {
        frames.encode_presence_error(
          code: "invalid_meta",
          message: "presence metadata must be a JSON object",
        )
      })
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

/// Stamp a system message (`"join"` / `"leave"`) with the next sequence number
/// and append it to the log, returning it for the caller to route.
///
/// System messages consume a sequence number like any op, so every replica
/// agrees on *where* in the stream membership changed — that ordering is the
/// whole point, since a consensus kernel settles its pending state at exactly
/// this sequence point. `client_id` is null and `contents` is null; the payload
/// rides in `data`.
fn sequence_system(
  sluice: Sluice,
  message_type: String,
  data: String,
) -> #(Sluice, Sequenced) {
  let sn = sequencing.current_sn(sluice.seq) + 1
  let seq = sequencing.SequenceState(..sluice.seq, sequence_number: sn)
  let message =
    Sequenced(
      client_id: None,
      sequence_number: sn,
      minimum_sequence_number: sequencing.current_msn(seq),
      client_sequence_number: -1,
      reference_sequence_number: sn - 1,
      op_type: message_type,
      contents: json.null(),
      metadata: None,
      timestamp: sluice.now_ms,
      data: Some(data),
    )
  #(Sluice(..sluice, seq: seq, log: [message, ..sluice.log]), message)
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
