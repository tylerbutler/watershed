//// Unit suite for `pact_map_kernel`, covering PactMap's pending/accepted
//// quorum protocol as a pure kernel.

import gleam/json.{type Json}
import gleam/option.{None, Some}
import startest/expect
import watershed/pact_map_kernel.{
  type PactMapState, Accept, Accepted, NoReaction, OweAccept, Pact, Pending, Set,
  UnexpectedAccept, WentAccepted, WentPending,
}

fn s(value: String) -> Json {
  json.string(value)
}

fn apply_set(
  state: PactMapState,
  op: pact_map_kernel.PactMapOp,
  seq: Int,
  connected: List(Int),
  self_id: Int,
) {
  pact_map_kernel.apply_set(state, op, seq, connected, self_id)
}

pub fn detached_set_accepts_immediately_test() {
  let state = pact_map_kernel.new()
  let assert Some(op) = pact_map_kernel.set(state, "k", Some(s("A")), 0)
  let #(state, events, reaction) = apply_set(state, op, 0, [], 1)

  events |> expect.to_equal([WentAccepted("k")])
  reaction |> expect.to_equal(NoReaction)
  pact_map_kernel.get(state, "k") |> expect.to_equal(Some(s("A")))
  pact_map_kernel.get_with_details(state, "k")
  |> expect.to_equal(Some(Accepted(Some(s("A")), 0)))
  pact_map_kernel.is_pending(state, "k") |> expect.to_be_false()
  pact_map_kernel.get_pending(state, "k") |> expect.to_equal(None)
}

pub fn single_client_set_requires_accept_then_get_returns_value_test() {
  let state = pact_map_kernel.new()
  let assert Some(op) = pact_map_kernel.set(state, "k", Some(s("A")), 0)
  let #(state, events, reaction) = apply_set(state, op, 1, [1], 1)

  events |> expect.to_equal([WentPending("k")])
  reaction |> expect.to_equal(OweAccept(Accept("k")))
  pact_map_kernel.get(state, "k") |> expect.to_equal(None)
  pact_map_kernel.get_pending(state, "k")
  |> expect.to_equal(Some(Some(s("A"))))

  let assert Ok(#(state, events)) =
    pact_map_kernel.apply_accept(state, "k", 1, 2)
  events |> expect.to_equal([WentAccepted("k")])
  pact_map_kernel.get(state, "k") |> expect.to_equal(Some(s("A")))
  pact_map_kernel.get_with_details(state, "k")
  |> expect.to_equal(Some(Accepted(Some(s("A")), 2)))
}

pub fn two_client_acceptance_waits_for_every_signer_test() {
  let state = pact_map_kernel.new()
  let #(state, _, _) = apply_set(state, Set("k", Some(s("A")), 0), 1, [1, 2], 1)
  let assert Ok(#(state, events)) =
    pact_map_kernel.apply_accept(state, "k", 1, 2)
  events |> expect.to_equal([])
  pact_map_kernel.is_pending(state, "k") |> expect.to_be_true()
  pact_map_kernel.get(state, "k") |> expect.to_equal(None)

  let assert Ok(#(state, events)) =
    pact_map_kernel.apply_accept(state, "k", 2, 3)
  events |> expect.to_equal([WentAccepted("k")])
  pact_map_kernel.get_with_details(state, "k")
  |> expect.to_equal(Some(Accepted(Some(s("A")), 3)))
}

pub fn frozen_signoffs_do_not_include_late_joiner_test() {
  let state = pact_map_kernel.new()
  let #(state, _, _) = apply_set(state, Set("k", Some(s("A")), 0), 1, [1, 2], 3)
  pact_map_kernel.summary_entries(state)
  |> expect.to_equal([
    #("k", Pact(None, Some(Pending(Some(s("A")), [1, 2])))),
  ])

  case pact_map_kernel.apply_accept(state, "k", 3, 2) {
    Error(UnexpectedAccept("k", 3, _)) -> Nil
    _ -> panic as "expected late joiner's accept to be rejected"
  }
}

pub fn competing_set_while_pending_is_not_submitted_test() {
  let state = pact_map_kernel.new()
  let #(state, _, _) = apply_set(state, Set("k", Some(s("A")), 0), 1, [1], 1)
  pact_map_kernel.set(state, "k", Some(s("B")), 1)
  |> expect.to_equal(None)
}

pub fn stale_set_is_dropped_but_current_set_goes_pending_test() {
  let state =
    pact_map_kernel.from_summary([
      #("k", Pact(Some(Accepted(Some(s("A")), 5)), None)),
    ])

  let #(state, events, reaction) =
    apply_set(state, Set("k", Some(s("B")), 4), 6, [1], 1)
  events |> expect.to_equal([])
  reaction |> expect.to_equal(NoReaction)
  pact_map_kernel.get(state, "k") |> expect.to_equal(Some(s("A")))

  let #(state, events, reaction) =
    apply_set(state, Set("k", Some(s("B")), 5), 7, [1], 1)
  events |> expect.to_equal([WentPending("k")])
  reaction |> expect.to_equal(OweAccept(Accept("k")))
  pact_map_kernel.get_pending(state, "k")
  |> expect.to_equal(Some(Some(s("B"))))
}

pub fn leave_driven_acceptance_settles_at_leave_sequence_test() {
  let state = pact_map_kernel.new()
  let #(state, _, _) = apply_set(state, Set("k", Some(s("A")), 0), 1, [1, 2], 1)
  let #(state, events) = pact_map_kernel.remove_member(state, 1, 2)
  events |> expect.to_equal([])
  pact_map_kernel.is_pending(state, "k") |> expect.to_be_true()

  let #(state, events) = pact_map_kernel.remove_member(state, 2, 3)
  events |> expect.to_equal([WentAccepted("k")])
  pact_map_kernel.get_with_details(state, "k")
  |> expect.to_equal(Some(Accepted(Some(s("A")), 3)))
}

pub fn accept_plus_leave_can_settle_test() {
  let state = pact_map_kernel.new()
  let #(state, _, _) = apply_set(state, Set("k", Some(s("A")), 0), 1, [1, 2], 1)
  let assert Ok(#(state, [])) = pact_map_kernel.apply_accept(state, "k", 1, 2)
  let #(state, events) = pact_map_kernel.remove_member(state, 2, 3)

  events |> expect.to_equal([WentAccepted("k")])
  pact_map_kernel.get_with_details(state, "k")
  |> expect.to_equal(Some(Accepted(Some(s("A")), 3)))
}

pub fn late_accept_after_settlement_is_noop_test() {
  let state =
    pact_map_kernel.from_summary([
      #("k", Pact(Some(Accepted(Some(s("A")), 2)), None)),
    ])
  let assert Ok(#(after, events)) =
    pact_map_kernel.apply_accept(state, "k", 1, 3)

  events |> expect.to_equal([])
  after |> expect.to_equal(state)
}

pub fn delete_proposes_none_and_accepts_to_deleted_value_test() {
  let state =
    pact_map_kernel.from_summary([
      #("k", Pact(Some(Accepted(Some(s("A")), 1)), None)),
    ])
  let assert Some(op) = pact_map_kernel.delete(state, "k", 1)
  op |> expect.to_equal(Set("k", None, 1))
  let #(state, _, reaction) = apply_set(state, op, 2, [1], 1)
  reaction |> expect.to_equal(OweAccept(Accept("k")))
  pact_map_kernel.get_pending(state, "k") |> expect.to_equal(Some(None))
  pact_map_kernel.is_pending(state, "k") |> expect.to_be_true()

  let assert Ok(#(state, _)) = pact_map_kernel.apply_accept(state, "k", 1, 3)
  pact_map_kernel.get(state, "k") |> expect.to_equal(None)
  pact_map_kernel.get_with_details(state, "k")
  |> expect.to_equal(Some(Accepted(None, 3)))
  pact_map_kernel.is_pending(state, "k") |> expect.to_be_false()
  pact_map_kernel.delete(state, "k", 3) |> expect.to_equal(None)
}

pub fn delete_guards_absent_and_pending_keys_test() {
  let state = pact_map_kernel.new()
  pact_map_kernel.delete(state, "missing", 0) |> expect.to_equal(None)
  let #(state, _, _) = apply_set(state, Set("k", Some(s("A")), 0), 1, [1], 1)
  pact_map_kernel.delete(state, "k", 1) |> expect.to_equal(None)
}

pub fn summary_round_trip_preserves_accepted_and_pending_test() {
  let original = [
    #("a", Pact(Some(Accepted(Some(s("A")), 1)), None)),
    #("b", Pact(None, Some(Pending(None, [1, 2])))),
  ]
  let state = pact_map_kernel.from_summary(original)
  pact_map_kernel.summary_entries(state) |> expect.to_equal(original)
  let loaded =
    pact_map_kernel.from_summary(pact_map_kernel.summary_entries(state))
  pact_map_kernel.summary_entries(loaded) |> expect.to_equal(original)
}

pub fn loaded_pending_can_be_settled_by_accept_or_leave_test() {
  let state =
    pact_map_kernel.from_summary([
      #("k", Pact(None, Some(Pending(Some(s("A")), [1, 2])))),
    ])
  let assert Ok(#(state, [])) = pact_map_kernel.apply_accept(state, "k", 1, 5)
  let #(state, events) = pact_map_kernel.remove_member(state, 2, 6)

  events |> expect.to_equal([WentAccepted("k")])
  pact_map_kernel.get_with_details(state, "k")
  |> expect.to_equal(Some(Accepted(Some(s("A")), 6)))
}

pub fn remove_member_for_unlisted_client_is_noop_test() {
  let state =
    pact_map_kernel.from_summary([
      #("k", Pact(None, Some(Pending(Some(s("A")), [1, 2])))),
    ])
  let #(after, events) = pact_map_kernel.remove_member(state, 3, 4)

  events |> expect.to_equal([])
  after |> expect.to_equal(state)
}
