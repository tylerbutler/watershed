//// The pure, target-agnostic core of the in-memory sluice: a floodgate-shaped
//// sequencer over parsed wire frame.
////
//// It uses the *real* `sequencing` module of spillway, which is the same SN,
//// MSN, and CSN logic that the production server runs. It also uses the
//// inverse codecs in `sluice/frame`. A runtime under test thus runs
//// byte-identical client code paths against an accurate server. Everything
//// here is a pure function of the state. There is no actor, no clock, and no
//// input or output. The Erlang driver (`watershed/sluice`) and the JavaScript
//// driver (`watershed/sluice_js`) add a mailbox and the delivery controls.
////
//// Every delivery is explicit, which is plan decision 3. An op sequences in
//// `handle`, but it goes into the `outbox`, and the core delivers it only when
//// a driver calls `take`. That behaviour makes a race scriptable. "Client A
//// and client B both claim the cell, deliver B first" is a sequence of `take`
//// calls, and not an accident of timing.

import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/set.{type Set}
import gleam/string

import spillway/sequencing.{type SequenceState}
import spillway/types.{type Client}

import watershed/sluice/frame.{type Sequenced, Sequenced}

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────

/// A frame that the sluice owes to one client, which waits for an explicit
/// `take`.
pub type Outbound {
  Outbound(client_id: String, event: String, payload: Json)
}

type ClientEntry {
  ClientEntry(client: Client, scopes: List(String))
}

/// The sluice state for one document. The type is pure, and a driver owns the
/// mutable cell.
pub opaque type Sluice {
  Sluice(
    document_id: String,
    tenant_id: String,
    seq: SequenceState,
    /// The full op history, in ascending order of sequence number. A late
    /// joiner and a reconnect both replay from this list. Plan decision 5 says
    /// that version 1 has no summary store.
    log: List(Sequenced),
    clients: Dict(String, ClientEntry),
    /// The presence of each *connection*, keyed by client id. Version 1
    /// supports one registration for each document connection, so an
    /// application puts its panel, cursor, and activity into one metadata
    /// value.
    presence: Dict(String, frame.PresenceMeta),
    /// A deterministic source of `phx_ref` values. Phoenix creates a random
    /// ref. The sluice creates `ref-1`, `ref-2`, and so on, for the same
    /// reason that it creates `sluice-client-N`. A test asserts on the frames,
    /// so the frames must be reproducible.
    next_presence_ref: Int,
    /// Whether the handshake announces `presence_v1`. A test sets this field
    /// to false to run the paths for an absent capability: `Auto` mode changes
    /// to ripples, and a forced `Server` mode fails with a report.
    presence_supported: Bool,
    /// The clients whose inbound frames the core holds. `pause` and `resume`
    /// control this set.
    paused: Set(String),
    next_client_number: Int,
    now_ms: Int,
    /// The frames that wait for delivery, oldest first.
    outbox: List(Outbound),
  )
}

/// A new sluice for one document. `now_ms` starts at 0, and only `advance`
/// moves it. The timestamps on the protocol frames thus stay deterministic in
/// a test.
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

/// Remove `presence_v1` from the handshake. A client in `Auto` mode thus
/// selects the ripple fallback, and a client that forces `Server` mode fails.
/// Call this function before `connect`.
pub fn set_presence_supported(sluice: Sluice, supported: Bool) -> Sluice {
  Sluice(..sluice, presence_supported: supported)
}

// ─────────────────────────────────────────────────────────────────────────────
// Clock
// ─────────────────────────────────────────────────────────────────────────────

/// The logical wall clock of the sluice, in milliseconds. Only `advance` moves
/// it.
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

/// Reserve a client id for a connection that just opened. The sequencer learns
/// about the client only when its `connect_document` message arrives, in
/// `handle`. This function thus creates the id that the driver uses as the key
/// of the link, and it does nothing else.
pub fn register(sluice: Sluice) -> #(Sluice, String) {
  let client_id = "sluice-client-" <> int.to_string(sluice.next_client_number)
  #(
    Sluice(..sluice, next_client_number: sluice.next_client_number + 1),
    client_id,
  )
}

/// Remove a client. The function sequences a `"leave"` message for the clients
/// that remain, and it removes the client from the MSN calculation of the
/// sequencer and from the paused set. `take` discards each queued frame that
/// the client did not receive.
///
/// The leave settles the per-client kernel state on every replica that
/// remains, at one agreed sequence point. It releases the queue jobs of that
/// client and removes it from the consensus signoffs. A client that did not
/// complete `connect_document` is not in the roster, so its disconnect
/// sequences nothing.
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
        sequence_system(sluice, "leave", frame.system_leave_data(client_id))
      broadcast(sluice, "op", frame.encode_op_event([leave]))
    }
  }
}

/// Hold the inbound frames of a client. They stay in the queue until a
/// `resume` call. A test can thus deliver the op of one peer before the op of
/// another peer.
pub fn pause(sluice: Sluice, client_id: String) -> Sluice {
  Sluice(..sluice, paused: set.insert(sluice.paused, client_id))
}

/// Return the held frames of a paused client to the deliverable queue.
pub fn resume(sluice: Sluice, client_id: String) -> Sluice {
  Sluice(..sluice, paused: set.delete(sluice.paused, client_id))
}

// ─────────────────────────────────────────────────────────────────────────────
// Inbound frame handling
// ─────────────────────────────────────────────────────────────────────────────

/// Process one push from a client to the server, keyed by the client id that
/// the connection received. The function sequences the ops, appends them to
/// the log, and queues the frames that result. It ignores a malformed frame
/// and a frame that the protocol does not permit, because a correct runtime
/// never sends one.
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
  case frame.decode_connect_document(payload) {
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
        |> sequence_system("join", frame.system_join_data(client_id))
      let sluice = broadcast(sluice, "op", frame.encode_op_event([join]))

      let clients =
        dict.insert(
          sluice.clients,
          client_id,
          ClientEntry(client: request.client, scopes: request.client.scopes),
        )
      let sluice = Sluice(..sluice, clients: clients)
      let connected =
        frame.encode_connected(
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
  case frame.decode_submit_op(payload) {
    Error(_) -> sluice
    Ok(submit) ->
      list.flatten(submit.batches)
      |> list.fold(sluice, fn(sluice, op) {
        sequence_op(sluice, submit.client_id, op)
      })
  }
}

/// Give a sequence number to one op and broadcast that op to every connected
/// client. The broadcast includes the author, because that echo is the ack
/// that the kernel of the author waits for.
fn sequence_op(
  sluice: Sluice,
  client_id: String,
  op: frame.SubmittedOp,
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
      let event = frame.encode_op_event([sequenced])
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
  case frame.decode_request_ops(payload) {
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
        _ -> enqueue(sluice, client_id, "op", frame.encode_op_event(ops))
      }
    }
  }
}

fn on_noop(sluice: Sluice, payload: Dynamic) -> Sluice {
  case frame.decode_noop(payload) {
    Error(_) -> sluice
    Ok(#(client_id, rsn)) ->
      case sequencing.update_client_rsn(sluice.seq, client_id, rsn) {
        Ok(seq) -> Sluice(..sluice, seq: seq)
        Error(_) -> sluice
      }
  }
}

fn on_signal(sluice: Sluice, payload: Dynamic) -> Sluice {
  case frame.decode_submit_signal(payload) {
    Error(_) -> sluice
    Ok(signal) -> {
      let frame = frame.encode_signal(signal.client_id, signal.content)
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

/// Register the presence of this connection.
///
/// The order here is the state-plus-diff synchronization of Phoenix, and it
/// lets a joiner converge without a lock on the topic. Take a snapshot of the
/// roster, send that snapshot to the joiner alone, and *then* track the join
/// and broadcast it. The joiner thus learns about its own session from the
/// diff, and not from the snapshot. A remote change that races the snapshot is
/// a diff that the client queues.
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
              frame.encode_presence_state(dict.to_list(sluice.presence)),
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

/// Replace the metadata of this connection.
///
/// The core emits one diff, which carries a leave of the old `phx_ref` and a
/// join of the new one. Phoenix emits the same pair, and an untrack followed
/// by a track on the server produces it too. A Phoenix client thus already
/// understands the sequence.
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
        frame.encode_presence_error(
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

/// Remove the presence of this connection. If the connection has no presence,
/// the function does nothing and reports nothing. A duplicate leave, or a
/// leave that races the cleanup of the socket, must not give an error.
fn on_leave_presence(sluice: Sluice, client_id: String) -> Sluice {
  case dict.get(sluice.presence, client_id) {
    Error(Nil) -> sluice
    Ok(previous) ->
      Sluice(..sluice, presence: dict.delete(sluice.presence, client_id))
      |> broadcast_presence(joins: [], leaves: [#(client_id, previous)])
  }
}

/// Create a `phx_ref` value and pair it with the metadata that it stamps.
fn track(
  sluice: Sluice,
  key: String,
  fields: List(#(String, Json)),
) -> #(Sluice, frame.PresenceMeta) {
  let phx_ref = "ref-" <> int.to_string(sluice.next_presence_ref)
  #(
    Sluice(..sluice, next_presence_ref: sluice.next_presence_ref + 1),
    frame.PresenceMeta(key: key, phx_ref: phx_ref, fields: fields),
  )
}

/// Broadcast a presence change to **every** connected client, and to the
/// joiner too. This differs from `on_signal`, which excludes the author, and
/// the difference is deliberate. Phoenix presence covers the whole topic, and
/// a joiner that never received its own join would hold a roster without
/// itself in it.
fn broadcast_presence(
  sluice: Sluice,
  joins joins: List(#(String, frame.PresenceMeta)),
  leaves leaves: List(#(String, frame.PresenceMeta)),
) -> Sluice {
  broadcast(
    sluice,
    "presence_diff",
    frame.encode_presence_diff(joins: joins, leaves: leaves),
  )
}

/// The presence key of a connection, which is its authenticated user id.
///
/// A connection that did not complete `connect_document` is not in `clients`,
/// and it has no authenticated identity to derive a key from. The function
/// thus refuses it. A presence must never come from a socket that no server
/// authenticated.
fn authenticated_key(
  sluice: Sluice,
  client_id: String,
) -> Result(String, Json) {
  case dict.get(sluice.clients, client_id) {
    Ok(entry) -> Ok(entry.client.user.id)
    Error(Nil) ->
      Error(frame.encode_presence_error(
        code: "unauthenticated",
        message: "presence requires a completed document connection",
      ))
  }
}

/// Read the metadata of a presence command, and refuse an attempt to claim a
/// field that the server owns. The function removes a reserved key *inside*
/// `meta`, and it does not refuse the command. See
/// `frame.decode_presence_meta`. A reserved key at the top level is a claim
/// of identity, and it deserves an explicit error.
fn read_meta(payload: Dynamic) -> Result(List(#(String, Json)), Json) {
  case frame.names_reserved_field(payload) {
    True ->
      Error(frame.encode_presence_error(
        code: "invalid_meta",
        message: "the server owns key, session, and ref; a client cannot set them",
      ))
    False ->
      frame.decode_presence_meta(payload)
      |> result.map_error(fn(_) {
        frame.encode_presence_error(
          code: "invalid_meta",
          message: "presence metadata must be a JSON object",
        )
      })
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Delivery
// ─────────────────────────────────────────────────────────────────────────────

/// Deliver the oldest frame that the core owes to a client that is not paused,
/// and remove that frame from the queue. The result is `Error(Nil)` when the
/// core can deliver no frame, which occurs when the queue is empty and when
/// every pending frame belongs to a paused client.
pub fn take(sluice: Sluice) -> #(Sluice, Result(Outbound, Nil)) {
  case pop_deliverable(sluice.outbox, sluice.paused, []) {
    Error(Nil) -> #(sluice, Error(Nil))
    Ok(#(frame, rest)) -> #(Sluice(..sluice, outbox: rest), Ok(frame))
  }
}

/// The next frame that `take` would deliver, without a removal. The result is
/// `Error(Nil)` when the core can deliver no frame. A caller can thus collect
/// a whole broadcast group, which is the set of frames that share the sequence
/// number of one op, before it delivers that group.
pub fn peek(sluice: Sluice) -> Result(Outbound, Nil) {
  case pop_deliverable(sluice.outbox, sluice.paused, []) {
    Error(Nil) -> Error(Nil)
    Ok(#(frame, _rest)) -> Ok(frame)
  }
}

/// Whether the core can deliver a frame now, which is true when it owes a
/// frame to a client that is not paused.
pub fn has_pending(sluice: Sluice) -> Bool {
  list.any(sluice.outbox, fn(frame) {
    !set.contains(sluice.paused, frame.client_id)
  })
}

/// Every frame in the queue now, oldest first, for a paused client and for a
/// client that is not paused. Use this function for assertions and for
/// diagnostics.
pub fn outbox(sluice: Sluice) -> List(Outbound) {
  sluice.outbox
}

/// The connected clients, in a stable order, sorted by id.
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

/// Queue one frame for every connected client. The op echoes and the
/// broadcasts use this function.
fn broadcast(sluice: Sluice, event: String, payload: Json) -> Sluice {
  connected_ids(sluice)
  |> list.fold(sluice, fn(sluice, id) { enqueue(sluice, id, event, payload) })
}

/// Give the next sequence number to a system message, which is a `"join"` or a
/// `"leave"`, and append that message to the log. The function returns the
/// message, for the caller to route.
///
/// A system message uses a sequence number, the same as an op. Every replica
/// thus agrees on the position in the stream at which the membership changed.
/// That order is the purpose of the message, because a consensus kernel
/// settles its pending state at exactly that sequence point. `client_id` is
/// null and `contents` is null. The payload is in `data`.
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

/// The ops whose sequence number is more than `after`, in ascending order.
fn log_since(log: List(Sequenced), after: Int) -> List(Sequenced) {
  log
  |> list.reverse()
  |> list.filter(fn(op) { op.sequence_number > after })
}

/// Take the first frame whose client is not paused, and keep the queue order of
/// the frames that remain. `skipped` collects the frames of the paused clients
/// that the function passed over, so that the caller can put them back before
/// `rest`.
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
