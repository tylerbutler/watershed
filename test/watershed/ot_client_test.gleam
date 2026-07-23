//// Focused unit tests for the generic `ot_client` helpers extracted from
//// `json_ot_kernel`. These use toy op/error types (not json0's `Op`) to prove
//// the mechanics are genuinely algebra-agnostic: any future kernel supplying
//// its own transform/compose callbacks gets the same guarantees.

import gleam/option.{None, Some}
import startest/expect
import watershed/ot_client.{LogEntry}

// ─────────────────────────────────────────────────────────────────────────────
// Deterministic author precedence
// ─────────────────────────────────────────────────────────────────────────────

pub fn author_precedes_smaller_id_wins_test() {
  ot_client.author_precedes(1, 2) |> expect.to_equal(True)
  ot_client.author_precedes(2, 1) |> expect.to_equal(False)
  ot_client.author_precedes(5, 5) |> expect.to_equal(False)
}

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

pub fn to_head_context_folds_window_in_seq_order_test() {
  // Log entries deliberately out of order; the window (ref_seq=1, seq=5)
  // should only include seq 2, 3, 4, folded oldest-first.
  let log = [
    LogEntry(seq: 3, author: 9, op: []),
    LogEntry(seq: 1, author: 9, op: []),
    LogEntry(seq: 4, author: 9, op: []),
    LogEntry(seq: 2, author: 9, op: []),
    LogEntry(seq: 5, author: 9, op: []),
  ]
  ot_client.to_head_context(log, 1, 5, [], record_seq)
  |> expect.to_equal(Ok([4, 3, 2]))
}

pub fn to_head_context_excludes_boundary_entries_test() {
  // Entries at exactly ref_seq or seq are excluded (strict window).
  let log = [
    LogEntry(seq: 1, author: 0, op: []),
    LogEntry(seq: 2, author: 0, op: []),
    LogEntry(seq: 3, author: 0, op: []),
  ]
  ot_client.to_head_context(log, 1, 3, [], record_seq)
  |> expect.to_equal(Ok([2]))
}

pub fn to_head_context_empty_window_returns_op_unchanged_test() {
  ot_client.to_head_context([], 0, 1, [42], record_seq)
  |> expect.to_equal(Ok([42]))
}

pub fn to_head_context_propagates_transform_error_test() {
  let log = [LogEntry(seq: 2, author: 0, op: [])]
  let fail = fn(_current: List(Int), _entry: ot_client.LogEntry(List(Int))) {
    Error(Nil)
  }
  ot_client.to_head_context(log, 1, 3, [], fail)
  |> expect.to_equal(Error(Nil))
}

// ─────────────────────────────────────────────────────────────────────────────
// Pending-op rebase (rebase_pending)
// ─────────────────────────────────────────────────────────────────────────────

pub fn rebase_pending_returns_rebased_local_and_advanced_remote_test() {
  // Toy algebra: rebasing local past remote adds them; advancing remote past
  // local subtracts, so the two results are independently observable.
  let rebase_local = fn(local: Int, remote: Int) { Ok(local + remote) }
  let advance_remote = fn(remote: Int, local: Int) { Ok(remote - local) }
  ot_client.rebase_pending(Some(10), 3, rebase_local, advance_remote)
  |> expect.to_equal(Ok(#(Some(13), -7)))
}

pub fn rebase_pending_with_no_local_op_returns_remote_unchanged_test() {
  let rebase_local = fn(local: Int, remote: Int) { Ok(local + remote) }
  let advance_remote = fn(remote: Int, local: Int) { Ok(remote - local) }
  ot_client.rebase_pending(None, 7, rebase_local, advance_remote)
  |> expect.to_equal(Ok(#(None, 7)))
}

pub fn rebase_pending_propagates_rebase_error_test() {
  let rebase_local = fn(_local: Int, _remote: Int) { Error("bad rebase") }
  let advance_remote = fn(remote: Int, local: Int) { Ok(remote - local) }
  ot_client.rebase_pending(Some(1), 2, rebase_local, advance_remote)
  |> expect.to_equal(Error("bad rebase"))
}

pub fn rebase_pending_propagates_advance_error_test() {
  let rebase_local = fn(local: Int, remote: Int) { Ok(local + remote) }
  let advance_remote = fn(_remote: Int, _local: Int) { Error("bad advance") }
  ot_client.rebase_pending(Some(1), 2, rebase_local, advance_remote)
  |> expect.to_equal(Error("bad advance"))
}

// ─────────────────────────────────────────────────────────────────────────────
// Concurrency-log GC (gc_log)
// ─────────────────────────────────────────────────────────────────────────────

pub fn gc_log_retains_only_entries_above_msn_test() {
  let log = [
    LogEntry(seq: 1, author: 0, op: Nil),
    LogEntry(seq: 2, author: 0, op: Nil),
    LogEntry(seq: 3, author: 0, op: Nil),
  ]
  ot_client.gc_log(log, 2)
  |> expect.to_equal([LogEntry(seq: 3, author: 0, op: Nil)])
}

pub fn gc_log_keeps_everything_when_msn_is_zero_test() {
  let log = [LogEntry(seq: 1, author: 0, op: Nil)]
  ot_client.gc_log(log, 0) |> expect.to_equal(log)
}

// ─────────────────────────────────────────────────────────────────────────────
// Single-inflight / buffer promotion
// ─────────────────────────────────────────────────────────────────────────────

type Wire {
  Wire(ref_seq: Int, op: String)
}

pub fn promote_buffer_stamps_ref_seq_to_ack_seq_test() {
  ot_client.promote_buffer(Some("buffered-op"), 42, Wire)
  |> expect.to_equal(#(Some("buffered-op"), Some(Wire(42, "buffered-op"))))
}

pub fn promote_buffer_with_no_buffer_returns_nothing_test() {
  ot_client.promote_buffer(None, 42, Wire)
  |> expect.to_equal(#(None, None))
}

pub fn take_pending_is_idempotent_after_drain_test() {
  let #(cleared, taken) = ot_client.take_pending(Some("op"))
  taken |> expect.to_equal(Some("op"))
  cleared |> expect.to_equal(None)

  // Draining again on the cleared slot yields nothing.
  ot_client.take_pending(cleared) |> expect.to_equal(#(None, None))
}
