//// Unit suite for `claims_kernel`, ported describe-by-describe from
//// FluidFramework's `packages/dds/claims/src/test/claims.spec.ts`. The mock
//// container runtime is replaced by explicit `apply_remote`/`ack_local` calls
//// with hand-assigned sequence numbers: "process all messages" becomes
//// "sequence the ops in submission order and deliver them to each client".

import gleam/json.{type Json}
import gleam/list
import gleam/option.{None, Some}
import startest/expect
import watershed/claims_kernel.{
  type ClaimEvent, type ClaimOp, type ClaimOutcome, type ClaimsState,
  type KernelError, type SubmitResult, Aborted, Accepted, AlreadyClaimed,
  AlreadyPendingLocally, Claim, Claimed, Lost, Submitted, UnexpectedRollback,
}

// ─────────────────────────────────────────────────────────────────────────────
// Case-based helpers (startest's rescue wraps `let assert` in Ok(), which
// breaks error-variant destructuring — see map_kernel_test).
// ─────────────────────────────────────────────────────────────────────────────

fn submitted(
  result: Result(SubmitResult, KernelError),
) -> #(ClaimsState, ClaimOp) {
  case result {
    Ok(Submitted(state, op)) -> #(state, op)
    _ -> panic as "expected Submitted"
  }
}

fn expect_already_claimed(result: Result(SubmitResult, KernelError)) -> Json {
  case result {
    Ok(AlreadyClaimed(value)) -> value
    _ -> panic as "expected AlreadyClaimed"
  }
}

fn expect_already_pending(
  result: Result(SubmitResult, KernelError),
  key: String,
) -> Nil {
  case result {
    Error(AlreadyPendingLocally(k)) -> expect.to_equal(k, key)
    _ -> panic as "expected AlreadyPendingLocally"
  }
}

fn ack(
  state: ClaimsState,
  op: ClaimOp,
  seq: Int,
) -> #(ClaimsState, List(ClaimEvent), ClaimOutcome) {
  case claims_kernel.ack_local(state, op, seq) {
    Ok(triple) -> triple
    Error(_) -> panic as "expected ack_local to succeed"
  }
}

fn roll_back(state: ClaimsState, op: ClaimOp) -> #(ClaimsState, ClaimOutcome) {
  case claims_kernel.rollback(state, op) {
    Ok(pair) -> pair
    Error(_) -> panic as "expected rollback to succeed"
  }
}

fn expect_unexpected_rollback(
  result: Result(#(ClaimsState, ClaimOutcome), KernelError),
) -> Nil {
  case result {
    Error(UnexpectedRollback(_, _)) -> Nil
    _ -> panic as "expected UnexpectedRollback"
  }
}

fn stashed(
  result: Result(#(ClaimsState, ClaimOp), KernelError),
) -> #(ClaimsState, ClaimOp) {
  case result {
    Ok(pair) -> pair
    _ -> panic as "expected apply_stashed_op to succeed"
  }
}

fn s(value: String) -> Json {
  json.string(value)
}

// ─────────────────────────────────────────────────────────────────────────────
// Local (detached) state
// ─────────────────────────────────────────────────────────────────────────────

pub fn new_state_reads_are_empty_test() {
  let state = claims_kernel.new()
  claims_kernel.get(state, "foo") |> expect.to_equal(None)
  claims_kernel.has(state, "foo") |> expect.to_be_false()
}

pub fn set_detached_is_visible_immediately_test() {
  let state = claims_kernel.set_detached(claims_kernel.new(), "key", s("value"))
  claims_kernel.get(state, "key") |> expect.to_equal(Some(s("value")))
  claims_kernel.has(state, "key") |> expect.to_be_true()
}

pub fn set_detached_summary_persists_seq_zero_test() {
  let state = claims_kernel.set_detached(claims_kernel.new(), "key", s("value"))
  claims_kernel.summary_entries(state)
  |> expect.to_equal([#("key", s("value"), 0)])
}

pub fn summary_round_trip_preserves_committed_reads_test() {
  let state = claims_kernel.set_detached(claims_kernel.new(), "key", s("value"))
  let loaded = claims_kernel.from_summary(claims_kernel.summary_entries(state))
  claims_kernel.get(loaded, "key") |> expect.to_equal(Some(s("value")))
  claims_kernel.get(loaded, "missing") |> expect.to_equal(None)
}

pub fn cas_against_loaded_seq_zero_entry_succeeds_test() {
  // A loaded entry carries seq 0; CAS captures ref_seq = 0, and the equality
  // acceptance path accepts it against that seq-0 entry.
  let loaded = claims_kernel.from_summary([#("key", s("v0"), 0)])
  let #(state, op) =
    submitted(claims_kernel.compare_and_set_claim(loaded, "key", s("v1"), 7))
  // ref_seq is the entry's seq (0), not last_seen_seq (7).
  op |> expect.to_equal(Claim("key", s("v1"), 0))
  let #(state, _events, outcome) = ack(state, op, 1)
  outcome |> expect.to_equal(Accepted(s("v1")))
  claims_kernel.get(state, "key") |> expect.to_equal(Some(s("v1")))
}

// ─────────────────────────────────────────────────────────────────────────────
// Connected state, single client
// ─────────────────────────────────────────────────────────────────────────────

pub fn submit_is_not_optimistically_visible_test() {
  // The map-style-port trap: a pending claim must NOT be visible to reads.
  let #(state, op) =
    submitted(claims_kernel.try_set_claim(claims_kernel.new(), "k", s("v"), 0))
  op |> expect.to_equal(Claim("k", s("v"), 0))
  claims_kernel.get(state, "k") |> expect.to_equal(None)
  claims_kernel.has(state, "k") |> expect.to_be_false()
}

pub fn ack_commits_and_emits_local_claimed_test() {
  let #(state, op) =
    submitted(claims_kernel.try_set_claim(claims_kernel.new(), "k", s("v"), 0))
  let #(state, events, outcome) = ack(state, op, 1)
  outcome |> expect.to_equal(Accepted(s("v")))
  events |> expect.to_equal([Claimed("k", True)])
  claims_kernel.get(state, "k") |> expect.to_equal(Some(s("v")))
}

pub fn try_set_on_committed_key_returns_already_claimed_test() {
  let #(state, op) =
    submitted(claims_kernel.try_set_claim(
      claims_kernel.new(),
      "k",
      s("first"),
      0,
    ))
  let #(state, _events, _outcome) = ack(state, op, 1)
  // Second attempt sees the committed value and sends nothing.
  claims_kernel.try_set_claim(state, "k", s("second"), 1)
  |> expect_already_claimed
  |> expect.to_equal(s("first"))
}

pub fn duplicate_pending_claim_errors_test() {
  let #(state, _op) =
    submitted(claims_kernel.try_set_claim(claims_kernel.new(), "dup", s("a"), 0))
  claims_kernel.try_set_claim(state, "dup", s("b"), 0)
  |> expect_already_pending("dup")
}

// ─────────────────────────────────────────────────────────────────────────────
// Connected state, multiple clients — first-writer-wins
// ─────────────────────────────────────────────────────────────────────────────

pub fn first_sequenced_op_wins_on_every_client_test() {
  // Client A and B race key "k". A is sequenced first (seq 1), B second (seq 2).
  let #(state_a, op_a) =
    submitted(claims_kernel.try_set_claim(claims_kernel.new(), "k", s("A"), 0))
  let #(state_b, op_b) =
    submitted(claims_kernel.try_set_claim(claims_kernel.new(), "k", s("B"), 0))

  // Client A: acks its own winning op, then rejects B's remote op.
  let #(state_a, _e1, outcome_a) = ack(state_a, op_a, 1)
  outcome_a |> expect.to_equal(Accepted(s("A")))
  let #(state_a, events_a2) = claims_kernel.apply_remote(state_a, op_b, 2)
  events_a2 |> expect.to_equal([])
  claims_kernel.get(state_a, "k") |> expect.to_equal(Some(s("A")))

  // Client B: applies A's remote win, then its own op loses at ack.
  let #(state_b, events_b1) = claims_kernel.apply_remote(state_b, op_a, 1)
  events_b1 |> expect.to_equal([Claimed("k", False)])
  let #(state_b, events_b2, outcome_b) = ack(state_b, op_b, 2)
  outcome_b |> expect.to_equal(Lost(Some(s("A"))))
  events_b2 |> expect.to_equal([])
  claims_kernel.get(state_b, "k") |> expect.to_equal(Some(s("A")))
}

pub fn rejected_remote_op_leaves_state_unchanged_test() {
  // Commit "k"="A" at seq 1, then a stale op with a non-matching ref_seq.
  let #(state, op_a) =
    submitted(claims_kernel.try_set_claim(claims_kernel.new(), "k", s("A"), 0))
  let #(state, _e, _o) = ack(state, op_a, 1)
  let stale = Claim("k", s("B"), 0)
  let #(after, events) = claims_kernel.apply_remote(state, stale, 2)
  events |> expect.to_equal([])
  after |> expect.to_equal(state)
}

pub fn independent_keys_do_not_conflict_test() {
  let #(state, op1) =
    submitted(claims_kernel.try_set_claim(claims_kernel.new(), "k1", s("v1"), 0))
  let #(state, _e, _o) = ack(state, op1, 1)
  let #(state, op2) =
    submitted(claims_kernel.try_set_claim(state, "k2", s("v2"), 1))
  let #(state, _e, outcome) = ack(state, op2, 2)
  outcome |> expect.to_equal(Accepted(s("v2")))
  claims_kernel.get(state, "k1") |> expect.to_equal(Some(s("v1")))
  claims_kernel.get(state, "k2") |> expect.to_equal(Some(s("v2")))
}

pub fn remote_win_does_not_disturb_local_pending_test() {
  // S10: client B has a pending claim on "k". A remote op wins "k" first; B's
  // pending entry survives and only resolves (as a loss) when B's op sequences.
  let #(state_b, op_b) =
    submitted(claims_kernel.try_set_claim(claims_kernel.new(), "k", s("B"), 0))
  let remote_a = Claim("k", s("A"), 0)
  let #(state_b, events) = claims_kernel.apply_remote(state_b, remote_a, 1)
  events |> expect.to_equal([Claimed("k", False)])
  // The pending entry is untouched by the remote apply: ack still resolves it
  // (as a loss) rather than erroring on a missing pending entry.
  let #(state_b, _e, outcome) = ack(state_b, op_b, 2)
  outcome |> expect.to_equal(Lost(Some(s("A"))))
  claims_kernel.get(state_b, "k") |> expect.to_equal(Some(s("A")))
}

// ─────────────────────────────────────────────────────────────────────────────
// Compare-and-swap (CAS)
// ─────────────────────────────────────────────────────────────────────────────

pub fn cas_succeeds_on_unclaimed_key_test() {
  // No entry: ref_seq falls back to last_seen_seq.
  let #(state, op) =
    submitted(claims_kernel.compare_and_set_claim(
      claims_kernel.new(),
      "k",
      s("v"),
      5,
    ))
  op |> expect.to_equal(Claim("k", s("v"), 5))
  let #(_state, _e, outcome) = ack(state, op, 6)
  outcome |> expect.to_equal(Accepted(s("v")))
}

pub fn cas_succeeds_when_unchallenged_test() {
  let #(state, op1) =
    submitted(claims_kernel.try_set_claim(claims_kernel.new(), "k", s("v1"), 0))
  let #(state, _e, _o) = ack(state, op1, 1)
  // Entry seq is 1, so CAS captures ref_seq = 1 (ignoring last_seen_seq = 9).
  let #(state, op2) =
    submitted(claims_kernel.compare_and_set_claim(state, "k", s("v2"), 9))
  op2 |> expect.to_equal(Claim("k", s("v2"), 1))
  let #(state, _e, outcome) = ack(state, op2, 2)
  outcome |> expect.to_equal(Accepted(s("v2")))
  claims_kernel.get(state, "k") |> expect.to_equal(Some(s("v2")))
}

pub fn concurrent_cas_first_writer_wins_test() {
  // Both clients start from committed "k"="v0" at seq 1.
  let base = claims_kernel.from_summary([#("k", s("v0"), 1)])
  let #(state1, cas1) =
    submitted(claims_kernel.compare_and_set_claim(base, "k", s("v1"), 1))
  let #(state2, cas2) =
    submitted(claims_kernel.compare_and_set_claim(base, "k", s("v2"), 1))
  cas1 |> expect.to_equal(Claim("k", s("v1"), 1))
  cas2 |> expect.to_equal(Claim("k", s("v2"), 1))

  // cas1 sequenced first (seq 2), cas2 second (seq 3).
  let #(state1, _e, outcome1) = ack(state1, cas1, 2)
  outcome1 |> expect.to_equal(Accepted(s("v1")))
  let #(state1, ev) = claims_kernel.apply_remote(state1, cas2, 3)
  ev |> expect.to_equal([])

  let #(state2, _e) = claims_kernel.apply_remote(state2, cas1, 2)
  let #(state2, _e2, outcome2) = ack(state2, cas2, 3)
  outcome2 |> expect.to_equal(Lost(Some(s("v1"))))
  claims_kernel.get(state1, "k") |> expect.to_equal(Some(s("v1")))
  claims_kernel.get(state2, "k") |> expect.to_equal(Some(s("v1")))
}

pub fn cas_uses_exact_equality_not_greater_or_equal_test() {
  // Ported from claims.spec.ts:420 ("CAS rejects when refSeq is greater than
  // entry sequenceNumber"). Two CAS ops both capture ref_seq = 2; the first
  // sequenced advances the entry to seq 3, so the second — ref_seq 2 against
  // entry seq 3 — must be rejected.
  let #(state, op0) =
    submitted(claims_kernel.try_set_claim(
      claims_kernel.new(),
      "k",
      s("initial"),
      0,
    ))
  let #(state, _e, _o) = ack(state, op0, 1)

  // Client 1's first CAS wins normally (entry seq 1 -> 2).
  let #(state, cas1) =
    submitted(claims_kernel.compare_and_set_claim(state, "k", s("value1"), 0))
  cas1 |> expect.to_equal(Claim("k", s("value1"), 1))
  let #(state, _e, _o) = ack(state, cas1, 2)

  // Now two competing CAS ops, both observing entry seq 2 -> ref_seq 2.
  let #(state_c1, cas2) =
    submitted(claims_kernel.compare_and_set_claim(
      state,
      "k",
      s("value1again"),
      0,
    ))
  // Client 2 built from the same committed view (entry seq 2).
  let base2 = claims_kernel.from_summary([#("k", s("value1"), 2)])
  let #(state_c2, cas3) =
    submitted(claims_kernel.compare_and_set_claim(base2, "k", s("value2"), 0))
  cas2 |> expect.to_equal(Claim("k", s("value1again"), 2))
  cas3 |> expect.to_equal(Claim("k", s("value2"), 2))

  // cas2 sequenced first (seq 3) advances the entry; cas3 (seq 4) then loses.
  let #(state_c1, _e, outcome2) = ack(state_c1, cas2, 3)
  outcome2 |> expect.to_equal(Accepted(s("value1again")))
  let #(state_c2, _e) = claims_kernel.apply_remote(state_c2, cas2, 3)
  let #(state_c2, _e2, outcome3) = ack(state_c2, cas3, 4)
  outcome3 |> expect.to_equal(Lost(Some(s("value1again"))))
  claims_kernel.get(state_c1, "k") |> expect.to_equal(Some(s("value1again")))
  claims_kernel.get(state_c2, "k") |> expect.to_equal(Some(s("value1again")))
}

pub fn write_once_op_with_stale_high_ref_seq_is_rejected_test() {
  // The op that actually discriminates `==` from `>=` (the port above asserts
  // the right spec outcomes but passes under both rules). A write-once claim
  // captures `ref_seq` from the container-wide last sequence number, which can
  // exceed a key's own older committed SN — e.g. a client whose container
  // advanced on other channels while it never saw an early, low-SN claim on
  // this key. Such an op MUST be rejected (write-once holds); `==` rejects it,
  // `>=` would wrongly accept and overwrite the committed claim.
  let state = claims_kernel.from_summary([#("k", s("A"), 2)])
  let stale = Claim("k", s("B"), 5)
  let #(after, events) = claims_kernel.apply_remote(state, stale, 6)
  events |> expect.to_equal([])
  claims_kernel.get(after, "k") |> expect.to_equal(Some(s("A")))
}

pub fn cas_on_key_with_pending_claim_errors_test() {
  let #(state, _op) =
    submitted(claims_kernel.compare_and_set_claim(
      claims_kernel.new(),
      "k",
      s("a"),
      0,
    ))
  claims_kernel.compare_and_set_claim(state, "k", s("b"), 0)
  |> expect_already_pending("k")
}

pub fn try_set_on_committed_key_beats_pending_cas_guard_test() {
  // S7 ordering: try_set checks committed state *before* the pending guard, so
  // it returns AlreadyClaimed even while a CAS for that key is pending.
  let #(state, op) =
    submitted(claims_kernel.try_set_claim(
      claims_kernel.new(),
      "k",
      s("committed"),
      0,
    ))
  let #(state, _e, _o) = ack(state, op, 1)
  // A CAS on the committed key is now pending.
  let #(state, _cas) =
    submitted(claims_kernel.compare_and_set_claim(state, "k", s("cas"), 0))
  // try_set still short-circuits to AlreadyClaimed rather than erroring.
  claims_kernel.try_set_claim(state, "k", s("try"), 1)
  |> expect_already_claimed
  |> expect.to_equal(s("committed"))
}

// ─────────────────────────────────────────────────────────────────────────────
// Rollback / stash / abort
// ─────────────────────────────────────────────────────────────────────────────

pub fn rollback_removes_pending_and_aborts_test() {
  let #(state, op) =
    submitted(claims_kernel.try_set_claim(claims_kernel.new(), "k", s("v"), 0))
  let #(state, outcome) = roll_back(state, op)
  outcome |> expect.to_equal(Aborted)
  claims_kernel.pending_values(state) |> expect.to_equal([])
  claims_kernel.get(state, "k") |> expect.to_equal(None)
  // The key is free again after rollback.
  let #(_state, op2) =
    submitted(claims_kernel.try_set_claim(state, "k", s("v2"), 1))
  op2 |> expect.to_equal(Claim("k", s("v2"), 1))
}

pub fn rollback_with_no_pending_errors_test() {
  claims_kernel.rollback(claims_kernel.new(), Claim("k", s("v"), 0))
  |> expect_unexpected_rollback
}

pub fn stashed_op_reregisters_pending_and_returns_op_verbatim_test() {
  // The original ref_seq (3) must be preserved for resubmission.
  let op = Claim("k", s("v"), 3)
  let #(state, resubmit) =
    stashed(claims_kernel.apply_stashed_op(claims_kernel.new(), op))
  resubmit |> expect.to_equal(op)
  // The key is now guarded against a duplicate local submit.
  claims_kernel.try_set_claim(state, "k", s("other"), 9)
  |> expect_already_pending("k")
  // Still invisible to reads until it sequences.
  claims_kernel.get(state, "k") |> expect.to_equal(None)
}

pub fn stashed_op_on_pending_key_errors_test() {
  let op = Claim("k", s("v"), 0)
  let #(state, _resubmit) =
    stashed(claims_kernel.apply_stashed_op(claims_kernel.new(), op))
  case claims_kernel.apply_stashed_op(state, Claim("k", s("w"), 0)) {
    Error(AlreadyPendingLocally(k)) -> expect.to_equal(k, "k")
    _ -> panic as "expected AlreadyPendingLocally"
  }
}

pub fn abort_all_returns_sorted_keys_and_clears_pending_test() {
  let #(state, _op) =
    submitted(claims_kernel.try_set_claim(claims_kernel.new(), "k2", s("b"), 0))
  let #(state, _op) =
    submitted(claims_kernel.compare_and_set_claim(state, "k1", s("a"), 0))
  let #(state, keys) = claims_kernel.abort_all(state)
  keys |> expect.to_equal(["k1", "k2"])
  claims_kernel.pending_values(state) |> expect.to_equal([])
}

pub fn pending_values_exposes_a_single_pending_value_test() {
  let #(state, _op) =
    submitted(claims_kernel.try_set_claim(claims_kernel.new(), "k", s("v"), 0))
  claims_kernel.pending_values(state) |> expect.to_equal([s("v")])
}

pub fn pending_values_exposes_every_pending_value_test() {
  let #(state, _op) =
    submitted(claims_kernel.try_set_claim(claims_kernel.new(), "k1", s("a"), 0))
  let #(state, _op) =
    submitted(claims_kernel.try_set_claim(state, "k2", s("b"), 0))
  let values = claims_kernel.pending_values(state)
  list.length(values) |> expect.to_equal(2)
  list.contains(values, s("a")) |> expect.to_be_true()
  list.contains(values, s("b")) |> expect.to_be_true()
}

// ─────────────────────────────────────────────────────────────────────────────
// Summary round-trip
// ─────────────────────────────────────────────────────────────────────────────

pub fn summary_round_trips_values_and_sequence_numbers_test() {
  let #(state, op) =
    submitted(claims_kernel.try_set_claim(claims_kernel.new(), "a", s("v1"), 0))
  // Committed at server sequence number 5 — the SN must survive the round trip.
  let #(state, _e, _o) = ack(state, op, 5)
  let entries = claims_kernel.summary_entries(state)
  entries |> expect.to_equal([#("a", s("v1"), 5)])
  let loaded = claims_kernel.from_summary(entries)
  claims_kernel.summary_entries(loaded) |> expect.to_equal(entries)
}

pub fn cas_after_load_uses_persisted_sequence_number_test() {
  // Loaded entry carries seq 5; CAS captures ref_seq = 5 (not last_seen 99),
  // and the equality path accepts against seq 5.
  let loaded = claims_kernel.from_summary([#("k", s("v0"), 5)])
  let #(state, op) =
    submitted(claims_kernel.compare_and_set_claim(loaded, "k", s("v1"), 99))
  op |> expect.to_equal(Claim("k", s("v1"), 5))
  let #(state, _e, outcome) = ack(state, op, 6)
  outcome |> expect.to_equal(Accepted(s("v1")))
  claims_kernel.get(state, "k") |> expect.to_equal(Some(s("v1")))
}

pub fn null_value_round_trips_with_has_true_test() {
  // JSON null is a legitimate claimed value; `has` distinguishes it from
  // "never set", and it survives a summary round trip.
  let #(state, op) =
    submitted(claims_kernel.try_set_claim(
      claims_kernel.new(),
      "k",
      json.null(),
      0,
    ))
  let #(state, _e, outcome) = ack(state, op, 1)
  outcome |> expect.to_equal(Accepted(json.null()))
  claims_kernel.get(state, "k") |> expect.to_equal(Some(json.null()))
  claims_kernel.has(state, "k") |> expect.to_be_true()
  let loaded = claims_kernel.from_summary(claims_kernel.summary_entries(state))
  claims_kernel.get(loaded, "k") |> expect.to_equal(Some(json.null()))
  claims_kernel.has(loaded, "k") |> expect.to_be_true()
}
