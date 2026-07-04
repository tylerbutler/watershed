import gleam/json
import lattice_core/replica_id
import startest/expect
import watershed/or_set_kernel.{ElementAdded, ElementRemoved}

fn rid(name: String) -> replica_id.ReplicaId {
  replica_id.new(name)
}

fn new_a() -> or_set_kernel.OrSetState {
  or_set_kernel.new(rid("a"))
}

fn new_b() -> or_set_kernel.OrSetState {
  or_set_kernel.new(rid("b"))
}

fn expect_coherent(state: or_set_kernel.OrSetState) -> Nil {
  case or_set_kernel.check_cache_coherence(state) {
    Ok(Nil) -> Nil
    Error(detail) -> panic as detail
  }
}

fn ack(
  state: or_set_kernel.OrSetState,
  op: or_set_kernel.OrSetOp,
) -> or_set_kernel.OrSetState {
  let assert Ok(state) = or_set_kernel.ack_local(state, op)
  state
}

pub fn add_is_optimistically_visible_test() {
  let #(state, events, op, message_id) = or_set_kernel.add(new_a(), "alice")

  or_set_kernel.values(state) |> expect.to_equal(["alice"])
  or_set_kernel.sequenced_values(state) |> expect.to_equal([])
  events |> expect.to_equal([ElementAdded("alice")])
  message_id |> expect.to_equal(0)
  let assert or_set_kernel.Add("alice", _) = op
  expect_coherent(state)
}

pub fn remote_add_is_idempotent_test() {
  let #(_, _, op, _) = or_set_kernel.add(new_a(), "alice")
  let #(state, first_events) = or_set_kernel.apply_remote(new_b(), op)
  let #(state, second_events) = or_set_kernel.apply_remote(state, op)

  or_set_kernel.values(state) |> expect.to_equal(["alice"])
  first_events |> expect.to_equal([ElementAdded("alice")])
  second_events |> expect.to_equal([])
  expect_coherent(state)
}

pub fn concurrent_add_survives_observed_remove_test() {
  let #(state_a, _, add_a, _) = or_set_kernel.add(new_a(), "alice")
  let state_a = ack(state_a, add_a)
  let #(state_b, _) = or_set_kernel.apply_remote(new_b(), add_a)

  let #(_, _, remove_a, _) = or_set_kernel.remove(state_a, "alice")
  let #(_, _, add_b, _) = or_set_kernel.add(state_b, "alice")

  let #(observer, _) = or_set_kernel.apply_remote(new_a(), remove_a)
  let #(observer, events) = or_set_kernel.apply_remote(observer, add_b)

  or_set_kernel.values(observer) |> expect.to_equal(["alice"])
  events |> expect.to_equal([ElementAdded("alice")])
  expect_coherent(observer)
}

pub fn rollback_recomputes_optimistic_from_remaining_pending_test() {
  let #(state, _, op1, _) = or_set_kernel.add(new_a(), "alice")
  let #(state, _, op2, message_id2) = or_set_kernel.add(state, "bob")
  let assert Ok(#(state, events)) =
    or_set_kernel.rollback(state, op2, message_id2)

  or_set_kernel.values(state) |> expect.to_equal(["alice"])
  events |> expect.to_equal([ElementRemoved("bob")])
  let state = ack(state, op1)
  or_set_kernel.sequenced_values(state) |> expect.to_equal(["alice"])
  expect_coherent(state)
}

pub fn summary_round_trips_and_rebrands_test() {
  let #(state, _, op, _) = or_set_kernel.add(new_a(), "alice")
  let state = ack(state, op)

  let raw = json.to_string(or_set_kernel.summary(state))
  let assert Ok(loaded) = or_set_kernel.from_summary(raw, rid("c"))

  or_set_kernel.values(loaded) |> expect.to_equal(["alice"])
  loaded.pending |> expect.to_equal([])
  let #(loaded, _, op_c, _) = or_set_kernel.add(loaded, "carol")
  let loaded = ack(loaded, op_c)
  or_set_kernel.sequenced_values(loaded)
  |> expect.to_equal(["alice", "carol"])
}
