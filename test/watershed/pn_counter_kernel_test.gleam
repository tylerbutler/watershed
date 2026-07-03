import gleam/dict
import gleam/dynamic/decode
import gleam/json
import lattice_core/replica_id
import startest/expect
import watershed/pn_counter_kernel.{Update, Updated}

fn rid(name: String) -> replica_id.ReplicaId {
  replica_id.new(name)
}

fn new_a() -> pn_counter_kernel.PnCounterState {
  pn_counter_kernel.new(rid("a"))
}

fn new_b() -> pn_counter_kernel.PnCounterState {
  pn_counter_kernel.new(rid("b"))
}

fn expect_coherent(state: pn_counter_kernel.PnCounterState) -> Nil {
  case pn_counter_kernel.check_cache_coherence(state) {
    Ok(Nil) -> Nil
    Error(detail) -> panic as detail
  }
}

fn ack(
  state: pn_counter_kernel.PnCounterState,
  op: pn_counter_kernel.PnCounterOp,
) -> pn_counter_kernel.PnCounterState {
  case pn_counter_kernel.ack_local(state, op) {
    Ok(state) -> state
    Error(_) -> panic as "expected ack to succeed"
  }
}

fn rollback(
  state: pn_counter_kernel.PnCounterState,
  op: pn_counter_kernel.PnCounterOp,
  message_id: Int,
) -> #(pn_counter_kernel.PnCounterState, List(pn_counter_kernel.PnCounterEvent)) {
  case pn_counter_kernel.rollback(state, op, message_id) {
    Ok(result) -> result
    Error(_) -> panic as "expected rollback to succeed"
  }
}

fn expect_unexpected_ack(
  result: Result(
    pn_counter_kernel.PnCounterState,
    pn_counter_kernel.KernelError,
  ),
) {
  case result {
    Error(pn_counter_kernel.UnexpectedAck(_, _)) -> Nil
    _ -> panic as "expected UnexpectedAck error"
  }
}

fn expect_unexpected_rollback(
  result: Result(
    #(pn_counter_kernel.PnCounterState, List(pn_counter_kernel.PnCounterEvent)),
    pn_counter_kernel.KernelError,
  ),
) {
  case result {
    Error(pn_counter_kernel.UnexpectedRollback(_, _)) -> Nil
    _ -> panic as "expected UnexpectedRollback error"
  }
}

/// The per-replica counts of one half of a summary's CRDT state, keyed by
/// replica id string — the structural view the re-branding tests assert on.
fn summary_counts(
  state: pn_counter_kernel.PnCounterState,
  half: String,
) -> dict.Dict(String, Int) {
  let assert Ok(counts) =
    json.parse(
      json.to_string(pn_counter_kernel.summary(state)),
      decode.at(
        ["state", half, "counts"],
        decode.dict(decode.string, decode.int),
      ),
    )
  counts
}

// ─────────────────────────────────────────────────────────────────────────────
// Counter parity: new / update / apply_remote / convergence
// ─────────────────────────────────────────────────────────────────────────────

pub fn new_state_is_zero_test() {
  let state = new_a()
  pn_counter_kernel.value(state) |> expect.to_equal(0)
  pn_counter_kernel.sequenced_value(state) |> expect.to_equal(0)
  state.pending |> expect.to_equal([])
}

pub fn update_is_optimistically_visible_test() {
  let #(state, events, op, message_id) = pn_counter_kernel.update(new_a(), 10)
  pn_counter_kernel.value(state) |> expect.to_equal(10)
  pn_counter_kernel.sequenced_value(state) |> expect.to_equal(0)
  message_id |> expect.to_equal(0)
  events |> expect.to_equal([Updated(10, 10)])
  let Update(amount, _delta) = op
  amount |> expect.to_equal(10)
  expect_coherent(state)
}

pub fn update_accepts_negative_and_zero_amounts_test() {
  let #(state, _, _, _) = pn_counter_kernel.update(new_a(), -3)
  pn_counter_kernel.value(state) |> expect.to_equal(-3)
  let #(state, events, _, _) = pn_counter_kernel.update(state, 0)
  pn_counter_kernel.value(state) |> expect.to_equal(-3)
  // Counter parity (CP6): local zero-amount updates still emit.
  events |> expect.to_equal([Updated(0, -3)])
  expect_coherent(state)
}

pub fn update_message_ids_increment_test() {
  let #(state, _, _, id0) = pn_counter_kernel.update(new_a(), 1)
  let #(state, _, _, id1) = pn_counter_kernel.update(state, 2)
  id0 |> expect.to_equal(0)
  id1 |> expect.to_equal(1)
  state.next_pending_message_id |> expect.to_equal(2)
}

pub fn apply_remote_applies_delta_and_emits_diff_test() {
  let #(_, _, op, _) = pn_counter_kernel.update(new_a(), 7)
  let #(state, events) = pn_counter_kernel.apply_remote(new_b(), op)
  pn_counter_kernel.value(state) |> expect.to_equal(7)
  pn_counter_kernel.sequenced_value(state) |> expect.to_equal(7)
  state.pending |> expect.to_equal([])
  events |> expect.to_equal([Updated(7, 7)])
  expect_coherent(state)
}

pub fn concurrent_updates_converge_in_both_orders_test() {
  let #(_, _, op_a, _) = pn_counter_kernel.update(new_a(), 10)
  let #(_, _, op_b, _) = pn_counter_kernel.update(new_b(), 20)

  // Two fresh observers receive the ops in opposite orders.
  let #(observer_c, _) =
    pn_counter_kernel.apply_remote(pn_counter_kernel.new(rid("c")), op_a)
  let #(observer_c, _) = pn_counter_kernel.apply_remote(observer_c, op_b)
  let #(observer_d, _) =
    pn_counter_kernel.apply_remote(pn_counter_kernel.new(rid("d")), op_b)
  let #(observer_d, _) = pn_counter_kernel.apply_remote(observer_d, op_a)

  pn_counter_kernel.value(observer_c) |> expect.to_equal(30)
  pn_counter_kernel.value(observer_d) |> expect.to_equal(30)
}

pub fn concurrent_mixed_sign_updates_converge_test() {
  let #(_, _, op_a, _) = pn_counter_kernel.update(new_a(), 10)
  let #(_, _, op_b, _) = pn_counter_kernel.update(new_b(), -4)

  let #(observer, _) =
    pn_counter_kernel.apply_remote(pn_counter_kernel.new(rid("c")), op_a)
  let #(observer, _) = pn_counter_kernel.apply_remote(observer, op_b)
  pn_counter_kernel.value(observer) |> expect.to_equal(6)
}

// ─────────────────────────────────────────────────────────────────────────────
// CRDT-specific: idempotence, cumulative subsumption, sign routing
// ─────────────────────────────────────────────────────────────────────────────

pub fn duplicate_remote_delta_is_idempotent_and_silent_test() {
  let #(_, _, op, _) = pn_counter_kernel.update(new_a(), 3)
  let #(state, first_events) = pn_counter_kernel.apply_remote(new_b(), op)
  first_events |> expect.to_equal([Updated(3, 3)])

  // Re-merging the same delta changes nothing and emits nothing.
  let #(state, second_events) = pn_counter_kernel.apply_remote(state, op)
  pn_counter_kernel.value(state) |> expect.to_equal(3)
  second_events |> expect.to_equal([])
  expect_coherent(state)
}

/// PN3: a replica's later delta carries its cumulative count, so merging it
/// without the earlier delta still yields the replica's full contribution —
/// the contract the fuzz oracle's sum-of-amounts argument relies on.
pub fn later_delta_subsumes_earlier_ones_test() {
  let #(state_a, _, op1, _) = pn_counter_kernel.update(new_a(), 3)
  let #(_, _, op2, _) = pn_counter_kernel.update(state_a, 2)

  // op2 alone carries A's full +5.
  let #(observer, _) = pn_counter_kernel.apply_remote(new_b(), op2)
  pn_counter_kernel.value(observer) |> expect.to_equal(5)

  // The earlier delta arriving afterwards is subsumed: no change, no event.
  let #(observer, events) = pn_counter_kernel.apply_remote(observer, op1)
  pn_counter_kernel.value(observer) |> expect.to_equal(5)
  events |> expect.to_equal([])
}

// ─────────────────────────────────────────────────────────────────────────────
// Counter parity: FIFO ack / LIFO rollback
// ─────────────────────────────────────────────────────────────────────────────

pub fn ack_local_retires_pending_without_value_change_test() {
  let #(state, _, op, _) = pn_counter_kernel.update(new_a(), 5)
  let state = ack(state, op)
  pn_counter_kernel.value(state) |> expect.to_equal(5)
  pn_counter_kernel.sequenced_value(state) |> expect.to_equal(5)
  state.pending |> expect.to_equal([])
  expect_coherent(state)
}

pub fn ack_local_is_fifo_test() {
  let #(state, _, op1, _) = pn_counter_kernel.update(new_a(), 1)
  let #(state, _, op2, _) = pn_counter_kernel.update(state, 2)
  expect_unexpected_ack(pn_counter_kernel.ack_local(state, op2))

  let state = ack(state, op1)
  pn_counter_kernel.sequenced_value(state) |> expect.to_equal(1)
  let state = ack(state, op2)
  state.pending |> expect.to_equal([])
  pn_counter_kernel.value(state) |> expect.to_equal(3)
  pn_counter_kernel.sequenced_value(state) |> expect.to_equal(3)
  expect_coherent(state)
}

pub fn ack_local_with_message_id_validates_metadata_test() {
  let #(state, _, op, message_id) = pn_counter_kernel.update(new_a(), 4)
  expect_unexpected_ack(pn_counter_kernel.ack_local_with_message_id(
    state,
    op,
    message_id + 1,
  ))

  let assert Ok(state) =
    pn_counter_kernel.ack_local_with_message_id(state, op, message_id)
  state.pending |> expect.to_equal([])
}

pub fn ack_without_pending_is_an_error_test() {
  let #(_, _, op, _) = pn_counter_kernel.update(new_a(), 1)
  expect_unexpected_ack(pn_counter_kernel.ack_local(new_a(), op))
}

pub fn rollback_undoes_newest_pending_update_test() {
  let #(state, _, _, _) = pn_counter_kernel.update(new_a(), 10)
  let #(state, _, op2, message_id2) = pn_counter_kernel.update(state, -3)

  let #(state, events) = rollback(state, op2, message_id2)
  pn_counter_kernel.value(state) |> expect.to_equal(10)
  events |> expect.to_equal([Updated(3, 10)])
  expect_coherent(state)
}

pub fn rollback_validates_newest_pending_metadata_test() {
  let #(state, _, op1, message_id1) = pn_counter_kernel.update(new_a(), 1)
  let #(state, _, op2, message_id2) = pn_counter_kernel.update(state, 2)

  // op1 is not the newest pending entry; wrong message id also rejects.
  expect_unexpected_rollback(pn_counter_kernel.rollback(state, op1, message_id1))
  expect_unexpected_rollback(pn_counter_kernel.rollback(
    state,
    op2,
    message_id2 + 1,
  ))

  let #(state, _) = rollback(state, op2, message_id2)
  pn_counter_kernel.value(state) |> expect.to_equal(1)
}

/// The `optimistic` recompute test: merge is not invertible, so rollback
/// rebuilds the cache from `sequenced` plus the remaining pending deltas —
/// a remote contribution that arrived mid-flight must survive.
pub fn rollback_across_remote_ops_preserves_remote_delta_test() {
  let #(state, _, op, message_id) = pn_counter_kernel.update(new_a(), 10)
  let #(_, _, remote_op, _) = pn_counter_kernel.update(new_b(), 20)
  let #(state, _) = pn_counter_kernel.apply_remote(state, remote_op)

  let #(state, events) = rollback(state, op, message_id)
  pn_counter_kernel.value(state) |> expect.to_equal(20)
  state.pending |> expect.to_equal([])
  events |> expect.to_equal([Updated(-10, 20)])
  expect_coherent(state)
}

pub fn rollback_without_pending_is_an_error_test() {
  let #(_, _, op, _) = pn_counter_kernel.update(new_a(), 1)
  expect_unexpected_rollback(pn_counter_kernel.rollback(new_a(), op, 0))
}

// ─────────────────────────────────────────────────────────────────────────────
// CRDT-specific: stash idempotence, summaries, cache coherence
// ─────────────────────────────────────────────────────────────────────────────

/// The headline safety property: re-applying a stashed op whose delta was
/// already sequenced (the client reloaded from a summary that contains it)
/// changes nothing — where counter's re-increment path would double-count.
/// The op still re-pends and is returned unchanged for routing.
pub fn apply_stashed_op_is_idempotent_under_duplication_test() {
  let #(state, _, op, _) = pn_counter_kernel.update(new_a(), 5)
  let state = ack(state, op)
  pn_counter_kernel.value(state) |> expect.to_equal(5)

  let #(state, events, routed, message_id) =
    pn_counter_kernel.apply_stashed_op(state, op)
  pn_counter_kernel.value(state) |> expect.to_equal(5)
  events |> expect.to_equal([])
  routed |> expect.to_equal(op)
  case state.pending {
    [pn_counter_kernel.PendingDelta(_, amount, id)] -> {
      amount |> expect.to_equal(5)
      id |> expect.to_equal(message_id)
    }
    _ -> panic as "expected the stashed op to re-pend"
  }
  expect_coherent(state)

  // Acking the replayed op still works and leaves the value untouched.
  let state = ack(state, op)
  pn_counter_kernel.value(state) |> expect.to_equal(5)
  expect_coherent(state)
}

pub fn apply_stashed_op_applies_a_genuinely_new_delta_test() {
  let #(_, _, op, _) = pn_counter_kernel.update(new_a(), 5)
  // A state that never saw the op (fresh reload from an empty summary).
  let #(state, events, routed, _) =
    pn_counter_kernel.apply_stashed_op(new_a(), op)
  pn_counter_kernel.value(state) |> expect.to_equal(5)
  events |> expect.to_equal([Updated(5, 5)])
  routed |> expect.to_equal(op)
  expect_coherent(state)
}

/// PN5/PN6/CP5: summary round trip preserving per-replica structure. The
/// loaded client's own updates must land under its replica key, not the
/// summarizer's — pins lattice's keep-`a`'s-id merge re-branding idiom.
pub fn from_summary_rebrands_under_the_loader_identity_test() {
  let #(state, _, op_a, _) = pn_counter_kernel.update(new_a(), 3)
  let state = ack(state, op_a)
  let #(_, _, op_b, _) = pn_counter_kernel.update(new_b(), 4)
  let #(state, _) = pn_counter_kernel.apply_remote(state, op_b)

  let summary_json = json.to_string(pn_counter_kernel.summary(state))
  let assert Ok(loaded) = pn_counter_kernel.from_summary(summary_json, rid("c"))
  pn_counter_kernel.value(loaded) |> expect.to_equal(7)
  pn_counter_kernel.sequenced_value(loaded) |> expect.to_equal(7)
  loaded.pending |> expect.to_equal([])
  expect_coherent(loaded)

  // c's subsequent update lands under "c", alongside a's and b's counts.
  let #(loaded, _, op_c, _) = pn_counter_kernel.update(loaded, 1)
  let loaded = ack(loaded, op_c)
  summary_counts(loaded, "positive")
  |> expect.to_equal(dict.from_list([#("a", 3), #("b", 4), #("c", 1)]))
}

pub fn from_summary_rejects_invalid_json_test() {
  case pn_counter_kernel.from_summary("not json", rid("c")) {
    Error(_) -> Nil
    Ok(_) -> panic as "expected from_summary to reject invalid JSON"
  }
}

/// PN4 (structural): sign routing keeps per-replica cumulative counts on
/// separate halves of the summary.
pub fn summary_reflects_both_halves_test() {
  let #(state, _, op1, _) = pn_counter_kernel.update(new_a(), 5)
  let #(state, _, op2, _) = pn_counter_kernel.update(state, -3)
  let state = ack(state, op1)
  let state = ack(state, op2)
  summary_counts(state, "positive")
  |> expect.to_equal(dict.from_list([#("a", 5)]))
  summary_counts(state, "negative")
  |> expect.to_equal(dict.from_list([#("a", 3)]))
}

/// Mergeable-summary property: an un-acked local delta is absent from the
/// summary, and a client loaded from that summary converges when the same
/// delta later arrives sequenced.
pub fn summary_excludes_pending_and_still_converges_test() {
  let #(state, _, op, _) = pn_counter_kernel.update(new_a(), 9)
  pn_counter_kernel.value(state) |> expect.to_equal(9)
  summary_counts(state, "positive") |> expect.to_equal(dict.new())

  let summary_json = json.to_string(pn_counter_kernel.summary(state))
  let assert Ok(loaded) = pn_counter_kernel.from_summary(summary_json, rid("c"))
  pn_counter_kernel.value(loaded) |> expect.to_equal(0)

  let #(loaded, _) = pn_counter_kernel.apply_remote(loaded, op)
  pn_counter_kernel.value(loaded) |> expect.to_equal(9)
  expect_coherent(loaded)
}

pub fn cache_coherence_holds_across_a_scripted_sequence_test() {
  let #(state, _, op1, _) = pn_counter_kernel.update(new_a(), 5)
  expect_coherent(state)
  let #(_, _, remote_op, _) = pn_counter_kernel.update(new_b(), -2)
  let #(state, _) = pn_counter_kernel.apply_remote(state, remote_op)
  expect_coherent(state)
  let #(state, _, op2, message_id2) = pn_counter_kernel.update(state, 4)
  expect_coherent(state)
  let state = ack(state, op1)
  expect_coherent(state)
  let #(state, _) = rollback(state, op2, message_id2)
  expect_coherent(state)
  pn_counter_kernel.value(state) |> expect.to_equal(3)
}

/// PN4: sign is routed inside the kernel — negative amounts land on the
/// negative half, and each half's cumulative count is independent, so a
/// later positive delta does not subsume an earlier negative one.
pub fn sign_routing_keeps_halves_independent_test() {
  let #(state, _, _, _) = pn_counter_kernel.update(new_a(), 5)
  let #(state, _, op_negative, _) = pn_counter_kernel.update(state, -3)
  let #(state, _, op_positive, _) = pn_counter_kernel.update(state, 2)
  pn_counter_kernel.value(state) |> expect.to_equal(4)
  expect_coherent(state)

  // op_positive carries A's cumulative positive (+7) but none of the
  // negative half; op_negative carries the cumulative negative (−3).
  let #(observer, _) = pn_counter_kernel.apply_remote(new_b(), op_positive)
  pn_counter_kernel.value(observer) |> expect.to_equal(7)
  let #(observer, _) = pn_counter_kernel.apply_remote(observer, op_negative)
  pn_counter_kernel.value(observer) |> expect.to_equal(4)
}
