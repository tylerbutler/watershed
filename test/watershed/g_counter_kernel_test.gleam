import gleam/json
import lattice_core/replica_id
import lattice_counters/g_counter
import startest/expect
import watershed/g_counter_kernel as kernel

fn replica(name: String) -> replica_id.ReplicaId {
  replica_id.new(name)
}

fn new_a() -> kernel.GCounterState {
  kernel.new(replica("a"))
}

fn new_b() -> kernel.GCounterState {
  kernel.new(replica("b"))
}

fn increment(
  state: kernel.GCounterState,
  amount: Int,
) -> #(
  kernel.GCounterState,
  List(kernel.GCounterEvent),
  kernel.GCounterOperation,
  Int,
) {
  case kernel.increment(state, amount) {
    Ok(result) -> result
    Error(_) -> panic as "expected increment to succeed"
  }
}

fn ack(
  state: kernel.GCounterState,
  operation: kernel.GCounterOperation,
) -> kernel.GCounterState {
  case kernel.ack_local(state, operation) {
    Ok(state) -> state
    Error(_) -> panic as "expected ack to succeed"
  }
}

fn expect_coherent(state: kernel.GCounterState) -> Nil {
  case kernel.check_cache_coherence(state) {
    Ok(Nil) -> Nil
    Error(detail) -> panic as detail
  }
}

pub fn negative_increment_is_rejected_test() -> Nil {
  kernel.increment(kernel.new(replica_id.new("a")), -1)
  |> expect.to_equal(Error(kernel.NegativeIncrement(-1)))
}

pub fn independent_increments_merge_once_test() -> Nil {
  let assert Ok(#(a, _, _, _)) =
    kernel.increment(kernel.new(replica_id.new("a")), 2)
  let assert Ok(#(_, _, operation, _)) =
    kernel.increment(kernel.new(replica_id.new("b")), 3)
  let #(a, _) = kernel.apply_remote(a, operation)
  let #(a, events) = kernel.apply_remote(a, operation)
  kernel.value(a) |> expect.to_equal(5)
  kernel.sequenced_value(a) |> expect.to_equal(3)
  events |> expect.to_equal([])
  kernel.check_cache_coherence(a) |> expect.to_equal(Ok(Nil))
}

pub fn new_counter_starts_at_zero_test() -> Nil {
  let state = new_a()
  kernel.value(state) |> expect.to_equal(0)
  kernel.sequenced_value(state) |> expect.to_equal(0)
  expect_coherent(state)
}

pub fn local_increment_is_optimistic_test() -> Nil {
  let #(state, events, operation, message_id) = increment(new_a(), 4)
  kernel.value(state) |> expect.to_equal(4)
  kernel.sequenced_value(state) |> expect.to_equal(0)
  events |> expect.to_equal([kernel.Updated(4, 4)])
  message_id |> expect.to_equal(0)
  expect_coherent(state)

  let state = ack(state, operation)
  kernel.value(state) |> expect.to_equal(4)
  kernel.sequenced_value(state) |> expect.to_equal(4)
  expect_coherent(state)
}

pub fn zero_increment_emits_no_event_test() -> Nil {
  let #(state, events, _operation, _) = increment(new_a(), 0)
  events |> expect.to_equal([])
  kernel.value(state) |> expect.to_equal(0)
  expect_coherent(state)
}

pub fn negative_increment_leaves_state_untouched_test() -> Nil {
  let #(state, _, _, _) = increment(new_a(), 3)
  kernel.increment(state, -2)
  |> expect.to_equal(Error(kernel.NegativeIncrement(-2)))
  kernel.value(state) |> expect.to_equal(3)
}

pub fn negative_p2p_increment_is_rejected_test() -> Nil {
  kernel.p2p_increment(new_a(), -5)
  |> expect.to_equal(Error(kernel.NegativeIncrement(-5)))
}

pub fn acks_retire_pending_operations_in_order_test() -> Nil {
  let #(state, _, first, first_id) = increment(new_a(), 2)
  let #(state, _, second, second_id) = increment(state, 3)
  kernel.value(state) |> expect.to_equal(5)
  kernel.sequenced_value(state) |> expect.to_equal(0)

  let assert Ok(state) =
    kernel.ack_local_with_message_id(state, first, first_id)
  kernel.value(state) |> expect.to_equal(5)
  kernel.sequenced_value(state) |> expect.to_equal(2)
  expect_coherent(state)

  let assert Ok(state) =
    kernel.ack_local_with_message_id(state, second, second_id)
  kernel.sequenced_value(state) |> expect.to_equal(5)
  expect_coherent(state)
}

pub fn ack_rejects_the_wrong_message_id_test() -> Nil {
  let #(state, _, operation, message_id) = increment(new_a(), 2)
  let assert Error(kernel.UnexpectedAck(_, _)) =
    kernel.ack_local_with_message_id(state, operation, message_id + 1)
  Nil
}

pub fn ack_rejects_the_wrong_amount_test() -> Nil {
  let #(state, _, operation, _) = increment(new_a(), 2)
  let kernel.Increment(_, delta) = operation
  let assert Error(kernel.UnexpectedAck(_, _)) =
    kernel.ack_local(state, kernel.Increment(9, delta))
  Nil
}

pub fn ack_rejects_the_wrong_fragment_test() -> Nil {
  let #(state, _, operation, _) = increment(new_a(), 2)
  let kernel.Increment(amount, _) = operation
  let foreign = g_counter.increment(g_counter.new(replica("z")), 2)
  let assert Error(kernel.UnexpectedAck(_, _)) =
    kernel.ack_local(state, kernel.Increment(amount, foreign))
  Nil
}

pub fn ack_rejects_an_empty_queue_test() -> Nil {
  let #(state, _, operation, _) = increment(new_a(), 2)
  let state = ack(state, operation)
  let assert Error(kernel.UnexpectedAck(_, _)) =
    kernel.ack_local(state, operation)
  Nil
}

pub fn rollback_removes_the_newest_pending_increment_test() -> Nil {
  let #(state, _, first, _) = increment(new_a(), 2)
  let #(state, _, second, second_id) = increment(state, 3)
  let assert Ok(#(state, events)) = kernel.rollback(state, second, second_id)
  events |> expect.to_equal([kernel.Updated(-3, 2)])
  kernel.value(state) |> expect.to_equal(2)
  kernel.sequenced_value(state) |> expect.to_equal(0)
  expect_coherent(state)

  let state = ack(state, first)
  kernel.sequenced_value(state) |> expect.to_equal(2)
  expect_coherent(state)
}

pub fn rollback_rejects_the_wrong_entry_test() -> Nil {
  let #(state, _, first, first_id) = increment(new_a(), 2)
  let #(state, _, _second, _) = increment(state, 3)
  let assert Error(kernel.UnexpectedRollback(_, _)) =
    kernel.rollback(state, first, first_id)
  Nil
}

pub fn rollback_rejects_an_empty_queue_test() -> Nil {
  let #(state, _, operation, message_id) = increment(new_a(), 2)
  let state = ack(state, operation)
  let assert Error(kernel.UnexpectedRollback(_, _)) =
    kernel.rollback(state, operation, message_id)
  Nil
}

pub fn remote_increments_add_to_both_states_test() -> Nil {
  let #(local, _, _, _) = increment(new_a(), 2)
  let #(_, _, remote_operation, _) = increment(new_b(), 3)
  let #(local, events) = kernel.apply_remote(local, remote_operation)
  events |> expect.to_equal([kernel.Updated(3, 5)])
  kernel.value(local) |> expect.to_equal(5)
  kernel.sequenced_value(local) |> expect.to_equal(3)
  expect_coherent(local)
}

pub fn stash_replay_reuses_the_original_fragment_test() -> Nil {
  let #(state, _, operation, _) = increment(new_a(), 4)
  let reconnected = kernel.new(replica("a"))
  let #(replayed, events, returned, message_id) =
    kernel.apply_stashed_operation(reconnected, operation)
  returned |> expect.to_equal(operation)
  events |> expect.to_equal([kernel.Updated(4, 4)])
  message_id |> expect.to_equal(0)
  kernel.value(replayed) |> expect.to_equal(4)
  expect_coherent(replayed)

  let #(again, events, _, _) =
    kernel.apply_stashed_operation(replayed, operation)
  events |> expect.to_equal([])
  kernel.value(again) |> expect.to_equal(4)
  kernel.value(state) |> expect.to_equal(4)
}

pub fn summary_excludes_pending_increments_test() -> Nil {
  let #(state, _, operation, _) = increment(new_a(), 2)
  let state = ack(state, operation)
  let #(state, _, _pending, _) = increment(state, 5)

  let assert Ok(loaded) =
    kernel.from_summary(json.to_string(kernel.summary(state)), replica("b"))
  kernel.value(loaded) |> expect.to_equal(2)
  kernel.sequenced_value(loaded) |> expect.to_equal(2)
  expect_coherent(loaded)
}

pub fn summary_reload_keeps_the_local_replica_identity_test() -> Nil {
  let #(writer, _, operation, _) = increment(new_a(), 2)
  let writer = ack(writer, operation)

  let assert Ok(loaded) =
    kernel.from_summary(json.to_string(kernel.summary(writer)), replica("b"))
  let #(loaded, _, _, _) = increment(loaded, 3)
  kernel.value(loaded) |> expect.to_equal(5)
  expect_coherent(loaded)
}

pub fn from_sequenced_rebrands_the_loaded_state_test() -> Nil {
  let #(writer, _, operation, _) = increment(new_a(), 7)
  let writer = ack(writer, operation)

  let loaded = kernel.from_sequenced(writer.sequenced, replica("b"))
  let #(loaded, _, _, _) = increment(loaded, 1)
  kernel.value(loaded) |> expect.to_equal(8)
  expect_coherent(loaded)
}

pub fn malformed_summary_is_rejected_test() -> Nil {
  let assert Error(_) = kernel.from_summary("{\"nope\":true}", replica("a"))
  Nil
}

pub fn p2p_increment_commits_to_both_states_test() -> Nil {
  let assert Ok(#(state, events, operation)) = kernel.p2p_increment(new_a(), 3)
  events |> expect.to_equal([kernel.Updated(3, 3)])
  kernel.value(state) |> expect.to_equal(3)
  kernel.sequenced_value(state) |> expect.to_equal(3)
  expect_coherent(state)

  let kernel.Increment(amount, _) = operation
  amount |> expect.to_equal(3)
}

pub fn p2p_merge_absorbs_a_peer_state_test() -> Nil {
  let assert Ok(#(a, _, _)) = kernel.p2p_increment(new_a(), 2)
  let assert Ok(#(b, _, _)) = kernel.p2p_increment(new_b(), 3)

  let #(a, events) = kernel.p2p_merge(a, b.sequenced)
  events |> expect.to_equal([kernel.Updated(3, 5)])
  kernel.value(a) |> expect.to_equal(5)

  let #(a, events) = kernel.p2p_merge(a, b.sequenced)
  events |> expect.to_equal([])
  kernel.value(a) |> expect.to_equal(5)
  expect_coherent(a)
}

pub fn confirmed_state_stays_grow_only_after_rollback_test() -> Nil {
  let #(state, _, operation, message_id) = increment(new_a(), 5)
  let assert Ok(#(state, _)) = kernel.rollback(state, operation, message_id)
  kernel.value(state) |> expect.to_equal(0)
  kernel.sequenced_value(state) |> expect.to_equal(0)

  let #(state, _, next, _) = increment(state, 2)
  let state = ack(state, next)
  kernel.sequenced_value(state) |> expect.to_equal(2)
  expect_coherent(state)
}
