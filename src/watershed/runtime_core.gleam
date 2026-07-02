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
//// possibly-wrong state. Sequence gaps are *not* fatal: out-of-order ops are
//// buffered and the caller is told to `requestOps` to fill the gap, then the
//// buffer drains once the missing ops arrive.

import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
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
    /// Ops submitted but not yet sequenced, oldest first. Each entry carries
    /// the client_id it was authored under so acks match by the head's own
    /// identity — this unifies normal acks with reconnect reconciliation,
    /// where old-client-id ops are still in flight under a new connection.
    in_flight: List(InFlight),
    /// Sequenced messages that arrived past a gap, buffered ascending by SN
    /// (deduped) until the missing ops fill in and they can be drained.
    out_of_order: List(SequencedDocumentMessage),
  )
}

/// One op submitted but not yet sequenced.
pub type InFlight {
  InFlight(client_id: String, csn: Int, op: MapOp)
}

pub type CoreError {
  /// Our own sequenced op did not match the head of the in-flight queue.
  AckMismatch(detail: String)
  /// A sequenced `"op"` message carried contents we could not decode. With
  /// only map channels in v1 this signals corruption, not a foreign DDS.
  BadOpContents(sequence_number: Int)
  /// Bootstrap could not close the gap between its seed point and the
  /// earliest replayable op: a `resume_bootstrap` round made no progress, so
  /// the deltas endpoint itself is missing the range. The state we would
  /// build is missing its prefix, so we fail loudly rather than diverge
  /// silently.
  HistoryGap(detail: String)
}

/// Outcome of (a step of) bootstrapping.
///
/// `initialMessages` is served from the server's bounded in-memory history
/// window, so a document with more ops than the window arrives missing its
/// prefix. `MissingPrefix` asks the caller to fetch the sequenced ops in
/// `(from, to]` out of band (`GET /deltas/:tenant_id/:id?from=&to=` — `from`
/// exclusive, `to` inclusive, response capped server-side) and feed them to
/// `resume_bootstrap`, repeating until `Complete`.
pub type Bootstrapped {
  Complete(core: Core)
  MissingPrefix(core: Core, checkpoint: Int, from: Int, to: Int)
}

/// Outcome of ingesting a sequenced message: events to fan out to subscribers
/// plus, when a gap was just opened, the `from` argument for a `requestOps`
/// catch-up the runtime should send. `request_ops_from` is only `Some` on the
/// first op of a new gap, so the runtime never spams duplicate requests.
pub type Ingested {
  Ingested(events: List(MapEvent), request_ops_from: Option(Int))
}

/// A loaded summary: the confirmed map entries (insertion order) and the
/// sequence number they are current as of (from `summaryContext`). The runtime
/// fetches and decodes the summary blob out of band and passes this to
/// `bootstrap`.
pub type Summary {
  Summary(sequence_number: Int, entries: List(#(String, Json)))
}

// ─────────────────────────────────────────────────────────────────────────────
// Bootstrap
// ─────────────────────────────────────────────────────────────────────────────

/// Build the initial state from `connect_document_success`.
///
/// When `summary` is `Some`, seed the kernel from the summary's confirmed
/// entries and mark its `sequence_number` as already seen, then replay
/// `initialMessages` — which are the *post-summary* deltas — on top. When
/// `None`, replay `initialMessages` as a full history from SN 1.
///
/// `checkpointSequenceNumber` equals the SN of our own join message, which
/// arrives as a separate `op` push right after the success event and is not
/// in `initialMessages` — marking the checkpoint as already seen makes that
/// push dedupe cleanly without skipping anything that came before it.
pub fn bootstrap(
  connected: ConnectedMessage,
  address address: String,
  summary summary: Option(Summary),
) -> Result(Bootstrapped, CoreError) {
  let #(kernel, last_seen) = case summary {
    Some(Summary(sequence_number: sn, entries: entries)) -> #(
      map_kernel.from_sequenced(entries),
      sn,
    )
    None -> #(map_kernel.new(), 0)
  }
  let core =
    Core(
      client_id: connected.client_id,
      address: address,
      kernel: kernel,
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

/// Continue a bootstrap that came back `MissingPrefix`: replay the deltas the
/// caller fetched for `(from, to]` and re-check contiguity. The server caps
/// each deltas response, so a large gap closes over several rounds; a round
/// that advances nothing means the requested range is genuinely gone and the
/// state we would build is missing its prefix, so we fail loudly rather than
/// diverge silently.
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

/// Replay sequenced messages during bootstrap, discarding events (subscribers
/// only attach once the document is ready) and catch-up requests (bootstrap
/// gaps are filled via the deltas endpoint, not in-band `requestOps`).
fn replay(
  core: Core,
  messages: List(SequencedDocumentMessage),
) -> Result(Core, CoreError) {
  list.try_fold(messages, core, fn(core, msg) {
    handle_sequenced(core, msg)
    |> result.map(fn(outcome) { outcome.0 })
  })
}

/// A complete history replays contiguously from the seed point (SN 1 with no
/// snapshot, or the snapshot's sequence number), leaving nothing buffered —
/// then the checkpoint is marked seen and the core is ready. Anything still
/// in `out_of_order` means the earliest replayable op sits above a gap the
/// caller must fill from the deltas endpoint before the checkpoint (which is
/// past every buffered op) may be applied.
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

/// The confirmed (sequenced) map entries in insertion order — the state a
/// summary captures. Excludes pending un-acked local edits.
pub fn summary_entries(core: Core) -> List(#(String, Json)) {
  map_kernel.sequenced_entries(core.kernel)
}

/// Whether the client is caught up: every local edit has been acknowledged by
/// the server, so the confirmed state a summary captures is complete. v1
/// summaries require this — ops still in flight would fall in the uncovered gap
/// between the captured `last_seen_sn` and the summarize op's assigned SN.
pub fn is_synced(core: Core) -> Bool {
  core.in_flight == []
}

/// Stamp a `"summarize"` op referencing an already-uploaded snapshot tree,
/// consuming a client sequence number so subsequent map ops stay strictly
/// increasing. A summarize op carries no map mutation, so it neither changes
/// the kernel nor joins the in-flight queue (its ack is a `summaryAck` the
/// runtime treats as a system message).
pub fn build_summarize(
  core: Core,
  handle handle: String,
  message message: String,
  head head: String,
) -> #(Core, wire.OutboundOp) {
  let csn = core.next_csn
  let outbound =
    wire.outbound_summarize_op(
      client_sequence_number: csn,
      reference_sequence_number: core.last_seen_sn,
      handle: handle,
      message: message,
      parents: [],
      head: head,
    )
  #(Core(..core, next_csn: csn + 1), outbound)
}

// ─────────────────────────────────────────────────────────────────────────────
// Reconnect
// ─────────────────────────────────────────────────────────────────────────────

/// Adopt a fresh connection after a reconnect: swap in the new
/// server-assigned `client_id` while keeping the kernel, pending edits,
/// in-flight queue, `next_csn`, and `last_seen_sn` intact.
///
/// The client-side sequenced state stays valid across a reconnect — only the
/// socket dropped — so we do *not* replay history. Passing
/// `lastSeenSequenceNumber` in `connect_document` makes the server push just
/// the delta we missed, which arrives as ordinary `op` events (SN-deduped
/// against anything we already have). In-flight ops keep their *old*
/// client_id so old-client-id ops replayed by the catch-up stream ack their
/// heads (reconciliation); whatever remains is resubmitted with `resubmit`.
pub fn adopt_reconnect(core: Core, connected: ConnectedMessage) -> Core {
  Core(..core, client_id: connected.client_id)
}

/// Re-stamp every in-flight op with a fresh CSN under the current
/// `client_id` and return the outbound ops for the runtime to send. Called
/// once catch-up has reconciled the reconnect checkpoint, so only ops that
/// never landed remain. In-flight entries adopt the new client_id + CSN so
/// their eventual acks still match by the head's identity.
pub fn resubmit(core: Core) -> #(Core, List(wire.OutboundOp)) {
  let #(next_csn, new_in_flight, outbound) =
    list.fold(core.in_flight, #(core.next_csn, [], []), fn(acc, entry) {
      let #(csn, entries, outbounds) = acc
      let outbound =
        wire.outbound_map_op(
          address: core.address,
          client_sequence_number: csn,
          reference_sequence_number: core.last_seen_sn,
          op: entry.op,
        )
      #(
        csn + 1,
        [InFlight(client_id: core.client_id, csn: csn, op: entry.op), ..entries],
        [outbound, ..outbounds],
      )
    })
  #(
    Core(..core, next_csn: next_csn, in_flight: list.reverse(new_in_flight)),
    list.reverse(outbound),
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// Inbound
// ─────────────────────────────────────────────────────────────────────────────

/// Process one sequenced message from the server.
///
/// Already-seen SNs are dropped silently. Ops past the next expected SN are
/// buffered (ascending, deduped) and — on the first op of a new gap — the
/// returned `request_ops_from` tells the runtime to `requestOps` a catch-up.
/// Contiguous ops apply immediately and then drain any buffered successors.
/// System message types (join, leave, noop, summarize, ...) only advance
/// `last_seen_sn`.
pub fn handle_sequenced(
  core: Core,
  msg: SequencedDocumentMessage,
) -> Result(#(Core, Ingested), CoreError) {
  let next = core.last_seen_sn + 1
  case msg.sequence_number {
    sn if sn < next -> Ok(#(core, Ingested([], None)))
    sn if sn > next -> {
      // A new gap only if nothing was buffered yet; otherwise the runtime has
      // already been asked to catch up and we just extend the buffer.
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

/// Apply a contiguous message (its SN is exactly `last_seen_sn + 1`),
/// advancing `last_seen_sn` and routing by message type.
fn apply_one(
  core: Core,
  msg: SequencedDocumentMessage,
) -> Result(#(Core, List(MapEvent)), CoreError) {
  let core = Core(..core, last_seen_sn: msg.sequence_number)
  case msg.message_type {
    "op" -> handle_op(core, msg)
    _ -> Ok(#(core, []))
  }
}

/// Drain buffered ops that have become contiguous, accumulating their events.
fn drain_buffer(core: Core) -> Result(#(Core, List(MapEvent)), CoreError) {
  case core.out_of_order {
    [head, ..rest] if head.sequence_number <= core.last_seen_sn ->
      // A stale duplicate from an overlapping catch-up; drop and continue.
      drain_buffer(Core(..core, out_of_order: rest))
    [head, ..rest] if head.sequence_number == core.last_seen_sn + 1 -> {
      use #(core, events) <- result.try(apply_one(
        Core(..core, out_of_order: rest),
        head,
      ))
      use #(core, more) <- result.try(drain_buffer(core))
      Ok(#(core, list.append(events, more)))
    }
    // Head is still past the gap, or the buffer is empty.
    _ -> Ok(#(core, []))
  }
}

/// Insert a message into the buffer keeping ascending SN order, skipping any
/// SN already present.
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
) -> Result(#(Core, List(MapEvent)), CoreError) {
  case wire.decode_map_envelope(msg.contents) {
    Error(_) -> Error(BadOpContents(msg.sequence_number))
    Ok(#(address, op)) ->
      case address == core.address {
        False -> Ok(#(core, []))
        True ->
          case is_own_op(core, msg.client_id) {
            True -> ack_own(core, msg.client_id, msg.client_sequence_number, op)
            False -> {
              let #(kernel, events) = map_kernel.apply_remote(core.kernel, op)
              Ok(#(Core(..core, kernel: kernel), events))
            }
          }
      }
  }
}

/// An op is ours when it was authored by our current connection or by the
/// client_id of the current in-flight head (the latter covers reconnect
/// reconciliation, where old-client-id ops are still awaiting their acks).
fn is_own_op(core: Core, message_client_id: Option(String)) -> Bool {
  case message_client_id {
    None -> False
    Some(cid) ->
      cid == core.client_id
      || case core.in_flight {
        [head, ..] -> head.client_id == cid
        [] -> False
      }
  }
}

/// Commit the head in-flight op after the server sequenced it. The echoed
/// client_id and CSN must match the head exactly (submission order is FIFO);
/// the op shape is cross-checked too, though values are compared only by key
/// since JSON object key order does not survive the wire.
fn ack_own(
  core: Core,
  message_client_id: Option(String),
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
    [head, ..rest] ->
      case
        Some(head.client_id) == message_client_id
        && head.csn == csn
        && same_shape(head.op, echoed)
      {
        False ->
          Error(AckMismatch(
            "expected ack for csn "
            <> int.to_string(head.csn)
            <> ", got csn "
            <> int.to_string(csn),
          ))
        True ->
          case map_kernel.ack_local(core.kernel, head.op) {
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
      in_flight: list.append(core.in_flight, [
        InFlight(client_id: core.client_id, csn: csn, op: op),
      ]),
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
