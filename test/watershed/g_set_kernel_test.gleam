import gleam/json
import startest/expect
import watershed/g_set_kernel.{ElementAdded}

fn expect_coherent(state: g_set_kernel.GSetState) -> Nil {
  case g_set_kernel.check_cache_coherence(state) {
    Ok(Nil) -> Nil
    Error(detail) -> panic as detail
  }
}

fn ack(
  state: g_set_kernel.GSetState,
  op: g_set_kernel.GSetOp,
) -> g_set_kernel.GSetState {
  let assert Ok(state) = g_set_kernel.ack_local(state, op)
  state
}

pub fn add_is_optimistically_visible_test() {
  let #(state, events, op, message_id) =
    g_set_kernel.add(g_set_kernel.new(), "BM-17")

  g_set_kernel.values(state) |> expect.to_equal(["BM-17"])
  g_set_kernel.sequenced_values(state) |> expect.to_equal([])
  events |> expect.to_equal([ElementAdded("BM-17")])
  message_id |> expect.to_equal(0)
  let assert g_set_kernel.Add("BM-17", _) = op
  expect_coherent(state)
}

pub fn concurrent_adds_converge_by_union_test() {
  let #(_, _, add_a, _) = g_set_kernel.add(g_set_kernel.new(), "BM-17")
  let #(_, _, add_b, _) = g_set_kernel.add(g_set_kernel.new(), "BM-22")

  let #(observer, events_a) =
    g_set_kernel.apply_remote(g_set_kernel.new(), add_a)
  let #(observer, events_b) = g_set_kernel.apply_remote(observer, add_b)

  g_set_kernel.values(observer) |> expect.to_equal(["BM-17", "BM-22"])
  events_a |> expect.to_equal([ElementAdded("BM-17")])
  events_b |> expect.to_equal([ElementAdded("BM-22")])
  expect_coherent(observer)
}

pub fn remote_add_is_idempotent_test() {
  let #(_, _, op, _) = g_set_kernel.add(g_set_kernel.new(), "BM-17")
  let #(state, first_events) = g_set_kernel.apply_remote(g_set_kernel.new(), op)
  let #(state, second_events) = g_set_kernel.apply_remote(state, op)

  g_set_kernel.values(state) |> expect.to_equal(["BM-17"])
  first_events |> expect.to_equal([ElementAdded("BM-17")])
  second_events |> expect.to_equal([])
  expect_coherent(state)
}

pub fn duplicate_local_add_is_idempotent_but_still_ackable_test() {
  let #(state, first_events, op1, _) =
    g_set_kernel.add(g_set_kernel.new(), "BM-17")
  let #(state, second_events, op2, _) = g_set_kernel.add(state, "BM-17")

  g_set_kernel.values(state) |> expect.to_equal(["BM-17"])
  first_events |> expect.to_equal([ElementAdded("BM-17")])
  second_events |> expect.to_equal([])
  let state = ack(state, op1)
  let state = ack(state, op2)
  g_set_kernel.sequenced_values(state) |> expect.to_equal(["BM-17"])
  expect_coherent(state)
}

pub fn rollback_removes_newest_unacked_add_test() {
  let #(state, _, op1, _) = g_set_kernel.add(g_set_kernel.new(), "BM-17")
  let #(state, _, op2, message_id2) = g_set_kernel.add(state, "BM-22")
  let assert Ok(#(state, events)) =
    g_set_kernel.rollback(state, op2, message_id2)

  g_set_kernel.values(state) |> expect.to_equal(["BM-17"])
  events |> expect.to_equal([])
  let state = ack(state, op1)
  g_set_kernel.sequenced_values(state) |> expect.to_equal(["BM-17"])
  expect_coherent(state)
}

pub fn summary_round_trips_test() {
  let #(state, _, op, _) = g_set_kernel.add(g_set_kernel.new(), "BM-17")
  let state = ack(state, op)

  let raw = json.to_string(g_set_kernel.summary(state))
  let assert Ok(loaded) = g_set_kernel.from_summary(raw)

  g_set_kernel.values(loaded) |> expect.to_equal(["BM-17"])
  loaded.pending |> expect.to_equal([])
}
