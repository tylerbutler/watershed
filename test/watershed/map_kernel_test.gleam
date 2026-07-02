import gleam/json
import gleam/option.{None, Some}
import watershed/map_kernel.{
  Cleared, Delete, PendingClear, PendingDelete, PendingLifetime, Set,
  ValueChanged,
}
import startest/expect

// Case-based helpers instead of `let assert`: startest's rescue mechanism
// wraps `let assert` values in `Ok()`, breaking error-variant destructuring.

fn ack(state: map_kernel.MapState, op: map_kernel.MapOp) -> map_kernel.MapState {
  case map_kernel.ack_local(state, op) {
    Ok(state) -> state
    Error(_) -> panic as "expected ack to succeed"
  }
}

fn expect_unexpected_ack(
  result: Result(map_kernel.MapState, map_kernel.KernelError),
) {
  case result {
    Error(map_kernel.UnexpectedAck(_, _)) -> Nil
    _ -> panic as "expected UnexpectedAck error"
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Basic reads and local operations
// ─────────────────────────────────────────────────────────────────────────────

pub fn new_map_is_empty_test() {
  let state = map_kernel.new()
  map_kernel.entries(state) |> expect.to_equal([])
  map_kernel.size(state) |> expect.to_equal(0)
  map_kernel.get(state, "missing") |> expect.to_equal(None)
  map_kernel.has(state, "missing") |> expect.to_be_false()
}

pub fn set_is_optimistically_visible_test() {
  let #(state, events, op) = map_kernel.set(map_kernel.new(), "k", json.int(1))
  map_kernel.get(state, "k") |> expect.to_equal(Some(json.int(1)))
  op |> expect.to_equal(Set("k", json.int(1)))
  events |> expect.to_equal([ValueChanged("k", None, True)])
}

pub fn set_event_carries_previous_optimistic_value_test() {
  let #(state, _, _) = map_kernel.set(map_kernel.new(), "k", json.int(1))
  let #(_, events, _) = map_kernel.set(state, "k", json.int(2))
  events |> expect.to_equal([ValueChanged("k", Some(json.int(1)), True)])
}

pub fn consecutive_sets_aggregate_into_one_lifetime_test() {
  let #(state, _, _) = map_kernel.set(map_kernel.new(), "k", json.int(1))
  let #(state, _, _) = map_kernel.set(state, "k", json.int(2))
  state.pending
  |> expect.to_equal([PendingLifetime("k", [json.int(1), json.int(2)])])
  map_kernel.get(state, "k") |> expect.to_equal(Some(json.int(2)))
}

pub fn delete_after_set_terminates_lifetime_test() {
  let #(state, _, _) = map_kernel.set(map_kernel.new(), "k", json.int(1))
  let #(state, events, op) = map_kernel.delete(state, "k")
  op |> expect.to_equal(Delete("k"))
  events |> expect.to_equal([ValueChanged("k", Some(json.int(1)), True)])
  map_kernel.get(state, "k") |> expect.to_equal(None)
  // A set after the delete starts a fresh lifetime.
  let #(state, _, _) = map_kernel.set(state, "k", json.int(3))
  state.pending
  |> expect.to_equal([
    PendingLifetime("k", [json.int(1)]),
    PendingDelete("k"),
    PendingLifetime("k", [json.int(3)]),
  ])
}

pub fn delete_of_missing_key_sends_op_without_event_test() {
  let #(state, events, op) = map_kernel.delete(map_kernel.new(), "ghost")
  op |> expect.to_equal(Delete("ghost"))
  events |> expect.to_equal([])
  state.pending |> expect.to_equal([PendingDelete("ghost")])
}

pub fn clear_emits_cleared_then_value_changed_per_visible_key_test() {
  let #(state, _) =
    map_kernel.apply_remote(map_kernel.new(), Set("a", json.int(1)))
  let #(state, _, _) = map_kernel.set(state, "b", json.int(2))
  let #(state, events, op) = map_kernel.clear(state)
  op |> expect.to_equal(map_kernel.Clear)
  events
  |> expect.to_equal([
    Cleared(True),
    ValueChanged("a", Some(json.int(1)), True),
    ValueChanged("b", Some(json.int(2)), True),
  ])
  map_kernel.entries(state) |> expect.to_equal([])
  // A set after the clear is visible again.
  let #(state, _, _) = map_kernel.set(state, "c", json.int(3))
  map_kernel.entries(state) |> expect.to_equal([#("c", json.int(3))])
}

// ─────────────────────────────────────────────────────────────────────────────
// Remote operations and event suppression
// ─────────────────────────────────────────────────────────────────────────────

pub fn apply_remote_set_emits_event_test() {
  let #(state, events) =
    map_kernel.apply_remote(map_kernel.new(), Set("k", json.int(7)))
  events |> expect.to_equal([ValueChanged("k", None, False)])
  map_kernel.get(state, "k") |> expect.to_equal(Some(json.int(7)))
}

pub fn remote_set_masked_by_local_pending_set_test() {
  let #(state, _, _) = map_kernel.set(map_kernel.new(), "k", json.int(1))
  let #(state, events) = map_kernel.apply_remote(state, Set("k", json.int(9)))
  // Sequenced data updates, but the local pending value wins optimistically
  // and no event is emitted.
  events |> expect.to_equal([])
  map_kernel.get(state, "k") |> expect.to_equal(Some(json.int(1)))
}

pub fn remote_delete_masked_by_local_pending_set_test() {
  let #(state, _) =
    map_kernel.apply_remote(map_kernel.new(), Set("k", json.int(1)))
  let #(state, _, _) = map_kernel.set(state, "k", json.int(2))
  let #(state, events) = map_kernel.apply_remote(state, Delete("k"))
  events |> expect.to_equal([])
  map_kernel.get(state, "k") |> expect.to_equal(Some(json.int(2)))
}

pub fn remote_delete_emits_event_even_for_missing_key_test() {
  // Mirrors the TS kernel: remote deletes emit unconditionally when not
  // masked, even if the key was absent.
  let #(_, events) = map_kernel.apply_remote(map_kernel.new(), Delete("ghost"))
  events |> expect.to_equal([ValueChanged("ghost", None, False)])
}

pub fn remote_clear_spares_events_for_locally_pending_keys_test() {
  let #(state, _) =
    map_kernel.apply_remote(map_kernel.new(), Set("a", json.int(1)))
  let #(state, _) = map_kernel.apply_remote(state, Set("b", json.int(2)))
  let #(state, _, _) = map_kernel.set(state, "b", json.int(20))
  let #(state, events) = map_kernel.apply_remote(state, map_kernel.Clear)
  // "b" stays optimistically visible via its pending lifetime, so only "a"
  // gets a valueChanged.
  events
  |> expect.to_equal([
    Cleared(False),
    ValueChanged("a", Some(json.int(1)), False),
  ])
  map_kernel.entries(state) |> expect.to_equal([#("b", json.int(20))])
}

pub fn remote_clear_masked_by_local_pending_clear_test() {
  let #(state, _) =
    map_kernel.apply_remote(map_kernel.new(), Set("a", json.int(1)))
  let #(state, _, _) = map_kernel.clear(state)
  let #(state, events) = map_kernel.apply_remote(state, map_kernel.Clear)
  events |> expect.to_equal([])
  map_kernel.entries(state) |> expect.to_equal([])
}

pub fn set_racing_remote_clear_survives_test() {
  let #(state, _, _) = map_kernel.set(map_kernel.new(), "k", json.int(1))
  let #(state, _) = map_kernel.apply_remote(state, map_kernel.Clear)
  map_kernel.get(state, "k") |> expect.to_equal(Some(json.int(1)))
  // Our set sequences after the clear, so it wins on all clients.
  let state = ack(state, Set("k", json.int(1)))
  map_kernel.entries(state) |> expect.to_equal([#("k", json.int(1))])
}

pub fn delete_vs_remote_set_converges_test() {
  let #(state, _) =
    map_kernel.apply_remote(map_kernel.new(), Set("k", json.int(1)))
  let #(state, _, _) = map_kernel.delete(state, "k")
  // A remote set sequences before our delete: masked, and our delete wins.
  let #(state, events) = map_kernel.apply_remote(state, Set("k", json.int(9)))
  events |> expect.to_equal([])
  map_kernel.get(state, "k") |> expect.to_equal(None)
  let state = ack(state, Delete("k"))
  map_kernel.entries(state) |> expect.to_equal([])
}

// ─────────────────────────────────────────────────────────────────────────────
// Acks
// ─────────────────────────────────────────────────────────────────────────────

pub fn ack_set_commits_pending_to_sequenced_test() {
  let #(state, _, op) = map_kernel.set(map_kernel.new(), "k", json.int(1))
  let state = ack(state, op)
  state.pending |> expect.to_equal([])
  map_kernel.get(state, "k") |> expect.to_equal(Some(json.int(1)))
  map_kernel.entries(state) |> expect.to_equal([#("k", json.int(1))])
}

pub fn ack_multi_set_lifetime_commits_fifo_test() {
  let #(state, _, op1) = map_kernel.set(map_kernel.new(), "k", json.int(1))
  let #(state, _, op2) = map_kernel.set(state, "k", json.int(2))
  let state = ack(state, op1)
  // Oldest set committed; newest still pending and still wins optimistically.
  state.pending |> expect.to_equal([PendingLifetime("k", [json.int(2)])])
  map_kernel.get(state, "k") |> expect.to_equal(Some(json.int(2)))
  let state = ack(state, op2)
  state.pending |> expect.to_equal([])
  map_kernel.get(state, "k") |> expect.to_equal(Some(json.int(2)))
}

pub fn ack_clear_requires_queue_head_test() {
  let #(state, _, _) = map_kernel.set(map_kernel.new(), "k", json.int(1))
  let #(state, _, _) = map_kernel.clear(state)
  // Acking the clear before the set is an ordering violation.
  expect_unexpected_ack(map_kernel.ack_local(state, map_kernel.Clear))
  // In order it works: set first, then clear.
  let state = ack(state, Set("k", json.int(1)))
  let state = ack(state, map_kernel.Clear)
  state.pending |> expect.to_equal([])
  map_kernel.entries(state) |> expect.to_equal([])
}

pub fn ack_without_pending_is_an_error_test() {
  expect_unexpected_ack(map_kernel.ack_local(
    map_kernel.new(),
    Set("k", json.int(1)),
  ))
  expect_unexpected_ack(map_kernel.ack_local(map_kernel.new(), Delete("k")))
  expect_unexpected_ack(map_kernel.ack_local(map_kernel.new(), map_kernel.Clear))
}

pub fn ack_delete_expecting_lifetime_is_an_error_test() {
  let #(state, _, _) = map_kernel.set(map_kernel.new(), "k", json.int(1))
  expect_unexpected_ack(map_kernel.ack_local(state, Delete("k")))
}

pub fn ack_set_delete_set_sequence_test() {
  let #(state, _, op1) = map_kernel.set(map_kernel.new(), "k", json.int(1))
  let #(state, _, op2) = map_kernel.delete(state, "k")
  let #(state, _, op3) = map_kernel.set(state, "k", json.int(3))
  let state = ack(state, op1)
  let state = ack(state, op2)
  let state = ack(state, op3)
  state.pending |> expect.to_equal([])
  map_kernel.entries(state) |> expect.to_equal([#("k", json.int(3))])
}

pub fn pending_clear_acks_only_after_earlier_ops_test() {
  let #(state, _, set_op) = map_kernel.set(map_kernel.new(), "a", json.int(1))
  let #(state, _, clear_op) = map_kernel.clear(state)
  let #(state, _, set_op2) = map_kernel.set(state, "a", json.int(2))
  state.pending
  |> expect.to_equal([
    PendingLifetime("a", [json.int(1)]),
    PendingClear,
    PendingLifetime("a", [json.int(2)]),
  ])
  let state = ack(state, set_op)
  let state = ack(state, clear_op)
  let state = ack(state, set_op2)
  map_kernel.entries(state) |> expect.to_equal([#("a", json.int(2))])
}

// ─────────────────────────────────────────────────────────────────────────────
// Iteration order
// ─────────────────────────────────────────────────────────────────────────────

pub fn iteration_follows_insertion_order_test() {
  let #(state, _) =
    map_kernel.apply_remote(map_kernel.new(), Set("a", json.int(1)))
  let #(state, _) = map_kernel.apply_remote(state, Set("b", json.int(2)))
  let #(state, _) = map_kernel.apply_remote(state, Set("a", json.int(3)))
  // Re-setting an existing key keeps its original position (JS Map contract).
  map_kernel.keys(state) |> expect.to_equal(["a", "b"])
}

pub fn remote_delete_then_set_moves_key_to_end_test() {
  let #(state, _) =
    map_kernel.apply_remote(map_kernel.new(), Set("a", json.int(1)))
  let #(state, _) = map_kernel.apply_remote(state, Set("b", json.int(2)))
  let #(state, _) = map_kernel.apply_remote(state, Delete("a"))
  let #(state, _) = map_kernel.apply_remote(state, Set("a", json.int(3)))
  map_kernel.keys(state) |> expect.to_equal(["b", "a"])
}

pub fn pending_keys_iterate_after_sequenced_keys_test() {
  let #(state, _) =
    map_kernel.apply_remote(map_kernel.new(), Set("a", json.int(1)))
  let #(state, _, _) = map_kernel.set(state, "b", json.int(2))
  map_kernel.entries(state)
  |> expect.to_equal([#("a", json.int(1)), #("b", json.int(2))])
}

pub fn pending_set_on_sequenced_key_keeps_position_test() {
  let #(state, _) =
    map_kernel.apply_remote(map_kernel.new(), Set("a", json.int(1)))
  let #(state, _) = map_kernel.apply_remote(state, Set("b", json.int(2)))
  let #(state, _, _) = map_kernel.set(state, "a", json.int(10))
  map_kernel.entries(state)
  |> expect.to_equal([#("a", json.int(10)), #("b", json.int(2))])
}

pub fn local_delete_then_set_repositions_key_test() {
  let #(state, _) =
    map_kernel.apply_remote(map_kernel.new(), Set("a", json.int(1)))
  let #(state, _) = map_kernel.apply_remote(state, Set("b", json.int(2)))
  let #(state, _, _) = map_kernel.delete(state, "a")
  let #(state, _, _) = map_kernel.set(state, "a", json.int(3))
  // The delete terminated a's sequenced position; the new lifetime iterates
  // at the end.
  map_kernel.entries(state)
  |> expect.to_equal([#("b", json.int(2)), #("a", json.int(3))])
}

pub fn lifetime_before_pending_clear_is_not_iterated_test() {
  let #(state, _, _) = map_kernel.set(map_kernel.new(), "a", json.int(1))
  let #(state, _, _) = map_kernel.clear(state)
  let #(state, _, _) = map_kernel.set(state, "b", json.int(2))
  map_kernel.entries(state) |> expect.to_equal([#("b", json.int(2))])
}
