//// Focused unit tests for the generic `ot_client` helpers extracted from
//// `json_ot_kernel`. These use toy op/error types (not json0's `Op`) to prove
//// the mechanics are genuinely algebra-agnostic: any future kernel supplying
//// its own transform/compose callbacks gets the same guarantees.

import gleam/option.{None, Some}
import startest/expect
import watershed/ot_client.{Idle, InFlight, InFlightAndBuffered, LogEntry}

// ─────────────────────────────────────────────────────────────────────────────
// Concurrency-window transform (to_head_context)
// ─────────────────────────────────────────────────────────────────────────────

/// A toy "op" is just the trace of entry seqs it was folded against, so the
/// order `to_head_context` visits entries is directly observable.
fn record_seq(
  current: List(Int),
  entry: ot_client.LogEntry(List(Int)),
) -> Result(List(Int), Nil) {
  Ok([entry.seq, ..current])
}

pub fn to_head_context_folds_window_in_seq_order_test() -> Nil {
  // Log entries deliberately out of order; the window (ref_seq=1, seq=5)
  // should only include seq 2, 3, 4, folded oldest-first.
  let log = [
    LogEntry(seq: 3, op: []),
    LogEntry(seq: 1, op: []),
    LogEntry(seq: 4, op: []),
    LogEntry(seq: 2, op: []),
    LogEntry(seq: 5, op: []),
  ]
  ot_client.to_head_context(log, 1, 5, [], record_seq)
  |> expect.to_equal(Ok([4, 3, 2]))
}

pub fn to_head_context_excludes_boundary_entries_test() -> Nil {
  // Entries at exactly ref_seq or seq are excluded (strict window).
  let log = [
    LogEntry(seq: 1, op: []),
    LogEntry(seq: 2, op: []),
    LogEntry(seq: 3, op: []),
  ]
  ot_client.to_head_context(log, 1, 3, [], record_seq)
  |> expect.to_equal(Ok([2]))
}

pub fn to_head_context_empty_window_returns_op_unchanged_test() -> Nil {
  ot_client.to_head_context([], 0, 1, [42], record_seq)
  |> expect.to_equal(Ok([42]))
}

pub fn to_head_context_propagates_transform_error_test() -> Nil {
  let log = [LogEntry(seq: 2, op: [])]
  let fail = fn(_current: List(Int), _entry: ot_client.LogEntry(List(Int))) {
    Error(Nil)
  }
  ot_client.to_head_context(log, 1, 3, [], fail)
  |> expect.to_equal(Error(Nil))
}

// ─────────────────────────────────────────────────────────────────────────────
// Pending-op rebase (rebase_pending)
// ─────────────────────────────────────────────────────────────────────────────

pub fn rebase_pending_returns_rebased_local_and_advanced_remote_test() -> Nil {
  // Toy algebra: rebasing local past remote adds them; advancing remote past
  // local subtracts, so the two results are independently observable.
  let rebase_local = fn(local: Int, remote: Int) { Ok(local + remote) }
  let advance_remote = fn(remote: Int, local: Int) { Ok(remote - local) }
  ot_client.rebase_pending(InFlight(10), 3, rebase_local, advance_remote)
  |> expect.to_equal(Ok(#(InFlight(13), -7)))
}

/// The buffer rebases against the remote op that the wire layer already
/// advanced, so the two layers do not see the same remote value.
pub fn rebase_pending_rebases_the_buffer_one_layer_deeper_test() -> Nil {
  let rebase_local = fn(local: Int, remote: Int) { Ok(local + remote) }
  let advance_remote = fn(remote: Int, local: Int) { Ok(remote - local) }
  ot_client.rebase_pending(
    InFlightAndBuffered(10, 100),
    3,
    rebase_local,
    advance_remote,
  )
  |> expect.to_equal(Ok(#(InFlightAndBuffered(13, 93), -107)))
}

pub fn rebase_pending_with_no_local_op_returns_remote_unchanged_test() -> Nil {
  let rebase_local = fn(local: Int, remote: Int) { Ok(local + remote) }
  let advance_remote = fn(remote: Int, local: Int) { Ok(remote - local) }
  ot_client.rebase_pending(Idle, 7, rebase_local, advance_remote)
  |> expect.to_equal(Ok(#(Idle, 7)))
}

pub fn rebase_pending_propagates_rebase_error_test() -> Nil {
  let rebase_local = fn(_local: Int, _remote: Int) { Error("bad rebase") }
  let advance_remote = fn(remote: Int, local: Int) { Ok(remote - local) }
  ot_client.rebase_pending(InFlight(1), 2, rebase_local, advance_remote)
  |> expect.to_equal(Error("bad rebase"))
}

pub fn rebase_pending_propagates_advance_error_test() -> Nil {
  let rebase_local = fn(local: Int, remote: Int) { Ok(local + remote) }
  let advance_remote = fn(_remote: Int, _local: Int) { Error("bad advance") }
  ot_client.rebase_pending(InFlight(1), 2, rebase_local, advance_remote)
  |> expect.to_equal(Error("bad advance"))
}

// ─────────────────────────────────────────────────────────────────────────────
// Unacknowledged local edits (Pending)
// ─────────────────────────────────────────────────────────────────────────────

/// The first edit goes on the wire. Every later edit joins the buffer, and the
/// caller gets nothing to send.
pub fn hold_local_sends_the_first_edit_and_buffers_the_rest_test() -> Nil {
  let compose = fn(buffered: String, edit: String) { Ok(buffered <> edit) }
  ot_client.hold_local(Idle, "a", compose)
  |> expect.to_equal(Ok(#(InFlight("a"), Some("a"))))
  ot_client.hold_local(InFlight("a"), "b", compose)
  |> expect.to_equal(Ok(#(InFlightAndBuffered("a", "b"), None)))
  ot_client.hold_local(InFlightAndBuffered("a", "b"), "c", compose)
  |> expect.to_equal(Ok(#(InFlightAndBuffered("a", "bc"), None)))
}

pub fn hold_local_propagates_a_compose_error_test() -> Nil {
  let compose = fn(_buffered: String, _edit: String) { Error("bad compose") }
  ot_client.hold_local(InFlightAndBuffered("a", "b"), "c", compose)
  |> expect.to_equal(Error("bad compose"))
}

pub fn pending_reads_report_each_layer_test() -> Nil {
  ot_client.in_flight(Idle) |> expect.to_equal(Error(Nil))
  ot_client.buffered(Idle) |> expect.to_equal(Error(Nil))
  ot_client.in_flight(InFlight("a")) |> expect.to_equal(Ok("a"))
  ot_client.buffered(InFlight("a")) |> expect.to_equal(Error(Nil))
  ot_client.in_flight(InFlightAndBuffered("a", "b")) |> expect.to_equal(Ok("a"))
  ot_client.buffered(InFlightAndBuffered("a", "b")) |> expect.to_equal(Ok("b"))
}

// ─────────────────────────────────────────────────────────────────────────────
// Concurrency-log GC (gc_log)
// ─────────────────────────────────────────────────────────────────────────────

pub fn gc_log_retains_only_entries_above_msn_test() -> Nil {
  let log = [
    LogEntry(seq: 1, op: Nil),
    LogEntry(seq: 2, op: Nil),
    LogEntry(seq: 3, op: Nil),
  ]
  ot_client.gc_log(log, 2)
  |> expect.to_equal([LogEntry(seq: 3, op: Nil)])
}

pub fn gc_log_keeps_everything_when_msn_is_zero_test() -> Nil {
  let log = [LogEntry(seq: 1, op: Nil)]
  ot_client.gc_log(log, 0) |> expect.to_equal(log)
}

// ─────────────────────────────────────────────────────────────────────────────
// Single-inflight / buffer promotion
// ─────────────────────────────────────────────────────────────────────────────

type Wire {
  Wire(ref_seq: Int, op: String)
}

pub fn promote_buffer_stamps_ref_seq_to_ack_seq_test() -> Nil {
  ot_client.promote_buffer(
    InFlightAndBuffered("acked", "buffered-op"),
    42,
    Wire,
  )
  |> expect.to_equal(#(InFlight("buffered-op"), Some(Wire(42, "buffered-op"))))
}

pub fn promote_buffer_with_no_buffer_returns_nothing_test() -> Nil {
  ot_client.promote_buffer(InFlight("acked"), 42, Wire)
  |> expect.to_equal(#(Idle, None))
  ot_client.promote_buffer(Idle, 42, Wire)
  |> expect.to_equal(#(Idle, None))
}

pub fn take_pending_is_idempotent_after_drain_test() -> Nil {
  let #(cleared, taken) = ot_client.take_pending(Some("op"))
  taken |> expect.to_equal(Some("op"))
  cleared |> expect.to_equal(None)

  // Draining again on the cleared slot yields nothing.
  ot_client.take_pending(cleared) |> expect.to_equal(#(None, None))
}
