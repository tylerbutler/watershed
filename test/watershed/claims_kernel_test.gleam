//// Unit suite for `claims_kernel`, ported describe-by-describe from
//// FluidFramework's `packages/dds/claims/src/test/claims.spec.ts`. The mock
//// container runtime is replaced by explicit `apply_remote`/`ack_local` calls
//// with hand-assigned sequence numbers: "process all messages" becomes
//// "sequence the ops in submission order and deliver them to each client".

import gleam/json.{type Json}
import gleam/list
import gleam/option.{Some}
import startest/expect
import watershed/claims_kernel.{
  type ClaimEvent, type ClaimOperation, type ClaimOutcome, type ClaimsState,
  type KernelError, type SubmitResult, Aborted, Accepted, AlreadyClaimed,
  AlreadyPendingLocally, Claim, Claimed, Lost, Submitted, UnexpectedAck,
  UnexpectedRollback,
}

// ─────────────────────────────────────────────────────────────────────────────
// Case-based helpers (startest's rescue wraps `let assert` in Ok(), which
// breaks error-variant destructuring — see map_kernel_test).
// ─────────────────────────────────────────────────────────────────────────────

fn submitted(
  result: Result(SubmitResult, KernelError),
) -> #(ClaimsState, ClaimOperation) {
  case result {
    Ok(Submitted(state, operation)) -> #(state, operation)
    Ok(AlreadyClaimed(_)) | Error(_) -> panic as "expected Submitted"
  }
}

fn expect_already_claimed(result: Result(SubmitResult, KernelError)) -> Json {
  case result {
    Ok(AlreadyClaimed(value)) -> value
    Ok(Submitted(..)) | Error(_) -> panic as "expected AlreadyClaimed"
  }
}

fn expect_already_pending(
  result: Result(SubmitResult, KernelError),
  key: String,
) -> Nil {
  case result {
    Error(AlreadyPendingLocally(pending_key)) ->
      expect.to_equal(pending_key, key)
    Ok(_) | Error(UnexpectedAck(..)) | Error(UnexpectedRollback(..)) ->
      panic as "expected AlreadyPendingLocally"
  }
}

fn ack(
  state: ClaimsState,
  operation: ClaimOperation,
  sequence_number: Int,
) -> #(ClaimsState, List(ClaimEvent), ClaimOutcome) {
  case claims_kernel.ack_local(state, operation, sequence_number) {
    Ok(triple) -> triple
    Error(_) -> panic as "expected ack_local to succeed"
  }
}

fn roll_back(
  state: ClaimsState,
  operation: ClaimOperation,
) -> #(ClaimsState, ClaimOutcome) {
  case claims_kernel.rollback(state, operation) {
    Ok(pair) -> pair
    Error(_) -> panic as "expected rollback to succeed"
  }
}

fn expect_unexpected_rollback(
  result: Result(#(ClaimsState, ClaimOutcome), KernelError),
) -> Nil {
  case result {
    Error(UnexpectedRollback(_, _)) -> Nil
    Ok(_) | Error(AlreadyPendingLocally(_)) | Error(UnexpectedAck(..)) ->
      panic as "expected UnexpectedRollback"
  }
}

fn stashed(
  result: Result(#(ClaimsState, ClaimOperation), KernelError),
) -> #(ClaimsState, ClaimOperation) {
  case result {
    Ok(pair) -> pair
    Error(_) -> panic as "expected apply_stashed_op to succeed"
  }
}

fn string_value(value: String) -> Json {
  json.string(value)
}

// ─────────────────────────────────────────────────────────────────────────────
// Local (detached) state
// ─────────────────────────────────────────────────────────────────────────────

pub fn new_state_reads_are_empty_test() -> Nil {
  let state = claims_kernel.new()
  claims_kernel.get(state, "foo") |> expect.to_equal(Error(Nil))
  claims_kernel.has(state, "foo") |> expect.to_be_false()
}

pub fn set_detached_is_visible_immediately_test() -> Nil {
  let state =
    claims_kernel.set_detached(
      claims_kernel.new(),
      "key",
      string_value("value"),
    )
  claims_kernel.get(state, "key") |> expect.to_equal(Ok(string_value("value")))
  claims_kernel.has(state, "key") |> expect.to_be_true()
}

pub fn set_detached_summary_persists_sequence_number_zero_test() -> Nil {
  let state =
    claims_kernel.set_detached(
      claims_kernel.new(),
      "key",
      string_value("value"),
    )
  claims_kernel.summary_entries(state)
  |> expect.to_equal([#("key", string_value("value"), 0)])
}

pub fn summary_round_trip_preserves_committed_reads_test() -> Nil {
  let state =
    claims_kernel.set_detached(
      claims_kernel.new(),
      "key",
      string_value("value"),
    )
  let loaded = claims_kernel.from_summary(claims_kernel.summary_entries(state))
  claims_kernel.get(loaded, "key") |> expect.to_equal(Ok(string_value("value")))
  claims_kernel.get(loaded, "missing") |> expect.to_equal(Error(Nil))
}

pub fn cas_against_loaded_sequence_number_zero_entry_succeeds_test() -> Nil {
  // A loaded entry carries sequence_number 0; CAS captures
  // reference_sequence_number = 0, and the equality acceptance path accepts it
  // against that sequence_number-0 entry.
  let loaded = claims_kernel.from_summary([#("key", string_value("v0"), 0)])
  let #(state, operation) =
    submitted(claims_kernel.compare_and_set_claim(
      loaded,
      "key",
      string_value("v1"),
      7,
    ))
  // reference_sequence_number is the entry's sequence_number (0), not
  // last_seen_sequence_number (7).
  operation |> expect.to_equal(Claim("key", string_value("v1"), 0))
  let #(state, _events, outcome) = ack(state, operation, 1)
  outcome |> expect.to_equal(Accepted(string_value("v1")))
  claims_kernel.get(state, "key") |> expect.to_equal(Ok(string_value("v1")))
}

// ─────────────────────────────────────────────────────────────────────────────
// Connected state, single client
// ─────────────────────────────────────────────────────────────────────────────

pub fn submit_is_not_optimistically_visible_test() -> Nil {
  // The map-style-port trap: a pending claim must NOT be visible to reads.
  let #(state, operation) =
    submitted(claims_kernel.claim_once(
      claims_kernel.new(),
      "k",
      string_value("v"),
      0,
    ))
  operation |> expect.to_equal(Claim("k", string_value("v"), 0))
  claims_kernel.get(state, "k") |> expect.to_equal(Error(Nil))
  claims_kernel.has(state, "k") |> expect.to_be_false()
}

pub fn ack_commits_and_emits_local_claimed_test() -> Nil {
  let #(state, operation) =
    submitted(claims_kernel.claim_once(
      claims_kernel.new(),
      "k",
      string_value("v"),
      0,
    ))
  let #(state, events, outcome) = ack(state, operation, 1)
  outcome |> expect.to_equal(Accepted(string_value("v")))
  events |> expect.to_equal([Claimed("k", True)])
  claims_kernel.get(state, "k") |> expect.to_equal(Ok(string_value("v")))
}

pub fn try_set_on_committed_key_returns_already_claimed_test() -> Nil {
  let #(state, operation) =
    submitted(claims_kernel.claim_once(
      claims_kernel.new(),
      "k",
      string_value("first"),
      0,
    ))
  let #(state, _events, _outcome) = ack(state, operation, 1)
  // Second attempt sees the committed value and sends nothing.
  claims_kernel.claim_once(state, "k", string_value("second"), 1)
  |> expect_already_claimed
  |> expect.to_equal(string_value("first"))
}

pub fn duplicate_pending_claim_errors_test() -> Nil {
  let #(state, _operation) =
    submitted(claims_kernel.claim_once(
      claims_kernel.new(),
      "dup",
      string_value("a"),
      0,
    ))
  claims_kernel.claim_once(state, "dup", string_value("b"), 0)
  |> expect_already_pending("dup")
}

// ─────────────────────────────────────────────────────────────────────────────
// Connected state, multiple clients — first-writer-wins
// ─────────────────────────────────────────────────────────────────────────────

pub fn first_sequenced_operation_wins_on_every_client_test() -> Nil {
  // Client A and B race key "k". A is sequenced first (sequence_number 1), B
  // second (sequence_number 2).
  let #(state_a, operation_a) =
    submitted(claims_kernel.claim_once(
      claims_kernel.new(),
      "k",
      string_value("A"),
      0,
    ))
  let #(state_b, operation_b) =
    submitted(claims_kernel.claim_once(
      claims_kernel.new(),
      "k",
      string_value("B"),
      0,
    ))

  // Client A: acks its own winning operation, then rejects B's remote
  // operation.
  let #(state_a, _e1, outcome_a) = ack(state_a, operation_a, 1)
  outcome_a |> expect.to_equal(Accepted(string_value("A")))
  let #(state_a, events_a2) =
    claims_kernel.apply_remote(state_a, operation_b, 2)
  events_a2 |> expect.to_equal([])
  claims_kernel.get(state_a, "k") |> expect.to_equal(Ok(string_value("A")))

  // Client B: applies A's remote win, then its own operation loses at ack.
  let #(state_b, events_b1) =
    claims_kernel.apply_remote(state_b, operation_a, 1)
  events_b1 |> expect.to_equal([Claimed("k", False)])
  let #(state_b, events_b2, outcome_b) = ack(state_b, operation_b, 2)
  outcome_b |> expect.to_equal(Lost(Some(string_value("A"))))
  events_b2 |> expect.to_equal([])
  claims_kernel.get(state_b, "k") |> expect.to_equal(Ok(string_value("A")))
}

pub fn rejected_remote_operation_leaves_state_unchanged_test() -> Nil {
  // Commit "k"="A" at sequence_number 1, then a stale operation with a
  // non-matching reference_sequence_number.
  let #(state, operation_a) =
    submitted(claims_kernel.claim_once(
      claims_kernel.new(),
      "k",
      string_value("A"),
      0,
    ))
  let #(state, _e, _o) = ack(state, operation_a, 1)
  let stale = Claim("k", string_value("B"), 0)
  let #(after, events) = claims_kernel.apply_remote(state, stale, 2)
  events |> expect.to_equal([])
  after |> expect.to_equal(state)
}

pub fn independent_keys_do_not_conflict_test() -> Nil {
  let #(state, op1) =
    submitted(claims_kernel.claim_once(
      claims_kernel.new(),
      "k1",
      string_value("v1"),
      0,
    ))
  let #(state, _e, _o) = ack(state, op1, 1)
  let #(state, op2) =
    submitted(claims_kernel.claim_once(state, "k2", string_value("v2"), 1))
  let #(state, _e, outcome) = ack(state, op2, 2)
  outcome |> expect.to_equal(Accepted(string_value("v2")))
  claims_kernel.get(state, "k1") |> expect.to_equal(Ok(string_value("v1")))
  claims_kernel.get(state, "k2") |> expect.to_equal(Ok(string_value("v2")))
}

pub fn remote_win_does_not_disturb_local_pending_test() -> Nil {
  // S10: client B has a pending claim on "k". A remote operation wins "k"
  // first; B's pending entry survives and only resolves (as a loss) when B's
  // operation sequences.
  let #(state_b, operation_b) =
    submitted(claims_kernel.claim_once(
      claims_kernel.new(),
      "k",
      string_value("B"),
      0,
    ))
  let remote_a = Claim("k", string_value("A"), 0)
  let #(state_b, events) = claims_kernel.apply_remote(state_b, remote_a, 1)
  events |> expect.to_equal([Claimed("k", False)])
  // The pending entry is untouched by the remote apply: ack still resolves it
  // (as a loss) rather than erroring on a missing pending entry.
  let #(state_b, _e, outcome) = ack(state_b, operation_b, 2)
  outcome |> expect.to_equal(Lost(Some(string_value("A"))))
  claims_kernel.get(state_b, "k") |> expect.to_equal(Ok(string_value("A")))
}

// ─────────────────────────────────────────────────────────────────────────────
// Compare-and-swap (CAS)
// ─────────────────────────────────────────────────────────────────────────────

pub fn cas_succeeds_on_unclaimed_key_test() -> Nil {
  // No entry: reference_sequence_number falls back to
  // last_seen_sequence_number.
  let #(state, operation) =
    submitted(claims_kernel.compare_and_set_claim(
      claims_kernel.new(),
      "k",
      string_value("v"),
      5,
    ))
  operation |> expect.to_equal(Claim("k", string_value("v"), 5))
  let #(_state, _e, outcome) = ack(state, operation, 6)
  outcome |> expect.to_equal(Accepted(string_value("v")))
}

pub fn cas_succeeds_when_unchallenged_test() -> Nil {
  let #(state, op1) =
    submitted(claims_kernel.claim_once(
      claims_kernel.new(),
      "k",
      string_value("v1"),
      0,
    ))
  let #(state, _e, _o) = ack(state, op1, 1)
  // Entry sequence_number is 1, so CAS captures reference_sequence_number = 1
  // (ignoring last_seen_sequence_number = 9).
  let #(state, op2) =
    submitted(claims_kernel.compare_and_set_claim(
      state,
      "k",
      string_value("v2"),
      9,
    ))
  op2 |> expect.to_equal(Claim("k", string_value("v2"), 1))
  let #(state, _e, outcome) = ack(state, op2, 2)
  outcome |> expect.to_equal(Accepted(string_value("v2")))
  claims_kernel.get(state, "k") |> expect.to_equal(Ok(string_value("v2")))
}

pub fn concurrent_cas_first_writer_wins_test() -> Nil {
  // Both clients start from committed "k"="v0" at sequence_number 1.
  let base = claims_kernel.from_summary([#("k", string_value("v0"), 1)])
  let #(state1, cas1) =
    submitted(claims_kernel.compare_and_set_claim(
      base,
      "k",
      string_value("v1"),
      1,
    ))
  let #(state2, cas2) =
    submitted(claims_kernel.compare_and_set_claim(
      base,
      "k",
      string_value("v2"),
      1,
    ))
  cas1 |> expect.to_equal(Claim("k", string_value("v1"), 1))
  cas2 |> expect.to_equal(Claim("k", string_value("v2"), 1))

  // cas1 sequenced first (sequence_number 2), cas2 second (sequence_number 3).
  let #(state1, _e, outcome1) = ack(state1, cas1, 2)
  outcome1 |> expect.to_equal(Accepted(string_value("v1")))
  let #(state1, ev) = claims_kernel.apply_remote(state1, cas2, 3)
  ev |> expect.to_equal([])

  let #(state2, _e) = claims_kernel.apply_remote(state2, cas1, 2)
  let #(state2, _e2, outcome2) = ack(state2, cas2, 3)
  outcome2 |> expect.to_equal(Lost(Some(string_value("v1"))))
  claims_kernel.get(state1, "k") |> expect.to_equal(Ok(string_value("v1")))
  claims_kernel.get(state2, "k") |> expect.to_equal(Ok(string_value("v1")))
}

pub fn cas_uses_exact_equality_not_greater_or_equal_test() -> Nil {
  // Ported from claims.spec.ts:420 ("CAS rejects when refSeq is greater than
  // entry sequenceNumber"). Two CAS operations both capture
  // reference_sequence_number = 2; the first sequenced advances the entry to
  // sequence_number 3, so the second — reference_sequence_number 2 against
  // entry sequence_number 3 — must be rejected.
  let #(state, op0) =
    submitted(claims_kernel.claim_once(
      claims_kernel.new(),
      "k",
      string_value("initial"),
      0,
    ))
  let #(state, _e, _o) = ack(state, op0, 1)

  // Client 1's first CAS wins normally (entry sequence_number 1 -> 2).
  let #(state, cas1) =
    submitted(claims_kernel.compare_and_set_claim(
      state,
      "k",
      string_value("value1"),
      0,
    ))
  cas1 |> expect.to_equal(Claim("k", string_value("value1"), 1))
  let #(state, _e, _o) = ack(state, cas1, 2)

  // Now two competing CAS operations, both observing entry sequence_number 2 ->
  // reference_sequence_number 2.
  let #(state_c1, cas2) =
    submitted(claims_kernel.compare_and_set_claim(
      state,
      "k",
      string_value("value1again"),
      0,
    ))
  // Client 2 built from the same committed view (entry sequence_number 2).
  let base2 = claims_kernel.from_summary([#("k", string_value("value1"), 2)])
  let #(state_c2, cas3) =
    submitted(claims_kernel.compare_and_set_claim(
      base2,
      "k",
      string_value("value2"),
      0,
    ))
  cas2 |> expect.to_equal(Claim("k", string_value("value1again"), 2))
  cas3 |> expect.to_equal(Claim("k", string_value("value2"), 2))

  // cas2 sequenced first (sequence_number 3) advances the entry; cas3
  // (sequence_number 4) then loses.
  let #(state_c1, _e, outcome2) = ack(state_c1, cas2, 3)
  outcome2 |> expect.to_equal(Accepted(string_value("value1again")))
  let #(state_c2, _e) = claims_kernel.apply_remote(state_c2, cas2, 3)
  let #(state_c2, _e2, outcome3) = ack(state_c2, cas3, 4)
  outcome3 |> expect.to_equal(Lost(Some(string_value("value1again"))))
  claims_kernel.get(state_c1, "k")
  |> expect.to_equal(Ok(string_value("value1again")))
  claims_kernel.get(state_c2, "k")
  |> expect.to_equal(Ok(string_value("value1again")))
}

pub fn write_once_operation_with_stale_high_reference_sequence_number_is_rejected_test() -> Nil {
  // The operation that actually discriminates `==` from `>=` (the port above
  // asserts the right spec outcomes but passes under both rules). A write-once
  // claim captures `reference_sequence_number` from the container-wide last
  // sequence number, which can exceed a key's own older committed SN — e.g. a
  // client whose container advanced on other channels while it never saw an
  // early, low-SN claim on this key. Such an operation MUST be rejected
  // (write-once holds); `==` rejects it, `>=` would wrongly accept and
  // overwrite the committed claim.
  let state = claims_kernel.from_summary([#("k", string_value("A"), 2)])
  let stale = Claim("k", string_value("B"), 5)
  let #(after, events) = claims_kernel.apply_remote(state, stale, 6)
  events |> expect.to_equal([])
  claims_kernel.get(after, "k") |> expect.to_equal(Ok(string_value("A")))
}

pub fn cas_on_key_with_pending_claim_errors_test() -> Nil {
  let #(state, _operation) =
    submitted(claims_kernel.compare_and_set_claim(
      claims_kernel.new(),
      "k",
      string_value("a"),
      0,
    ))
  claims_kernel.compare_and_set_claim(state, "k", string_value("b"), 0)
  |> expect_already_pending("k")
}

pub fn try_set_on_committed_key_beats_pending_cas_guard_test() -> Nil {
  // S7 ordering: try_set checks committed state *before* the pending guard, so
  // it returns AlreadyClaimed even while a CAS for that key is pending.
  let #(state, operation) =
    submitted(claims_kernel.claim_once(
      claims_kernel.new(),
      "k",
      string_value("committed"),
      0,
    ))
  let #(state, _e, _o) = ack(state, operation, 1)
  // A CAS on the committed key is now pending.
  let #(state, _cas) =
    submitted(claims_kernel.compare_and_set_claim(
      state,
      "k",
      string_value("cas"),
      0,
    ))
  // try_set still short-circuits to AlreadyClaimed rather than erroring.
  claims_kernel.claim_once(state, "k", string_value("try"), 1)
  |> expect_already_claimed
  |> expect.to_equal(string_value("committed"))
}

// ─────────────────────────────────────────────────────────────────────────────
// Rollback / stash / abort
// ─────────────────────────────────────────────────────────────────────────────

pub fn rollback_removes_pending_and_aborts_test() -> Nil {
  let #(state, operation) =
    submitted(claims_kernel.claim_once(
      claims_kernel.new(),
      "k",
      string_value("v"),
      0,
    ))
  let #(state, outcome) = roll_back(state, operation)
  outcome |> expect.to_equal(Aborted)
  claims_kernel.pending_values(state) |> expect.to_equal([])
  claims_kernel.get(state, "k") |> expect.to_equal(Error(Nil))
  // The key is free again after rollback.
  let #(_state, op2) =
    submitted(claims_kernel.claim_once(state, "k", string_value("v2"), 1))
  op2 |> expect.to_equal(Claim("k", string_value("v2"), 1))
}

pub fn rollback_with_no_pending_errors_test() -> Nil {
  claims_kernel.rollback(claims_kernel.new(), Claim("k", string_value("v"), 0))
  |> expect_unexpected_rollback
}

pub fn stashed_operation_reregisters_pending_and_returns_operation_verbatim_test() -> Nil {
  // The original reference_sequence_number (3) must be preserved for
  // resubmission.
  let operation = Claim("k", string_value("v"), 3)
  let #(state, resubmit) =
    stashed(claims_kernel.apply_stashed_operation(
      claims_kernel.new(),
      operation,
    ))
  resubmit |> expect.to_equal(operation)
  // The key is now guarded against a duplicate local submit.
  claims_kernel.claim_once(state, "k", string_value("other"), 9)
  |> expect_already_pending("k")
  // Still invisible to reads until it sequences.
  claims_kernel.get(state, "k") |> expect.to_equal(Error(Nil))
}

pub fn stashed_operation_on_pending_key_errors_test() -> Nil {
  let operation = Claim("k", string_value("v"), 0)
  let #(state, _resubmit) =
    stashed(claims_kernel.apply_stashed_operation(
      claims_kernel.new(),
      operation,
    ))
  case
    claims_kernel.apply_stashed_operation(
      state,
      Claim("k", string_value("w"), 0),
    )
  {
    Error(AlreadyPendingLocally(pending_key)) ->
      expect.to_equal(pending_key, "k")
    Ok(_) | Error(UnexpectedAck(..)) | Error(UnexpectedRollback(..)) ->
      panic as "expected AlreadyPendingLocally"
  }
}

pub fn abort_all_returns_sorted_keys_and_clears_pending_test() -> Nil {
  let #(state, _operation) =
    submitted(claims_kernel.claim_once(
      claims_kernel.new(),
      "k2",
      string_value("b"),
      0,
    ))
  let #(state, _operation) =
    submitted(claims_kernel.compare_and_set_claim(
      state,
      "k1",
      string_value("a"),
      0,
    ))
  let #(state, keys) = claims_kernel.abort_all(state)
  keys |> expect.to_equal(["k1", "k2"])
  claims_kernel.pending_values(state) |> expect.to_equal([])
}

pub fn pending_values_exposes_a_single_pending_value_test() -> Nil {
  let #(state, _operation) =
    submitted(claims_kernel.claim_once(
      claims_kernel.new(),
      "k",
      string_value("v"),
      0,
    ))
  claims_kernel.pending_values(state) |> expect.to_equal([string_value("v")])
}

pub fn pending_values_exposes_every_pending_value_test() -> Nil {
  let #(state, _operation) =
    submitted(claims_kernel.claim_once(
      claims_kernel.new(),
      "k1",
      string_value("a"),
      0,
    ))
  let #(state, _operation) =
    submitted(claims_kernel.claim_once(state, "k2", string_value("b"), 0))
  let values = claims_kernel.pending_values(state)
  list.length(values) |> expect.to_equal(2)
  list.contains(values, string_value("a")) |> expect.to_be_true()
  list.contains(values, string_value("b")) |> expect.to_be_true()
}

// ─────────────────────────────────────────────────────────────────────────────
// Summary round-trip
// ─────────────────────────────────────────────────────────────────────────────

pub fn summary_round_trips_values_and_sequence_numbers_test() -> Nil {
  let #(state, operation) =
    submitted(claims_kernel.claim_once(
      claims_kernel.new(),
      "a",
      string_value("v1"),
      0,
    ))
  // Committed at server sequence number 5 — the SN must survive the round trip.
  let #(state, _e, _o) = ack(state, operation, 5)
  let entries = claims_kernel.summary_entries(state)
  entries |> expect.to_equal([#("a", string_value("v1"), 5)])
  let loaded = claims_kernel.from_summary(entries)
  claims_kernel.summary_entries(loaded) |> expect.to_equal(entries)
}

pub fn cas_after_load_uses_persisted_sequence_number_test() -> Nil {
  // Loaded entry carries sequence_number 5; CAS captures
  // reference_sequence_number = 5 (not last_seen 99), and the equality path
  // accepts against sequence_number 5.
  let loaded = claims_kernel.from_summary([#("k", string_value("v0"), 5)])
  let #(state, operation) =
    submitted(claims_kernel.compare_and_set_claim(
      loaded,
      "k",
      string_value("v1"),
      99,
    ))
  operation |> expect.to_equal(Claim("k", string_value("v1"), 5))
  let #(state, _e, outcome) = ack(state, operation, 6)
  outcome |> expect.to_equal(Accepted(string_value("v1")))
  claims_kernel.get(state, "k") |> expect.to_equal(Ok(string_value("v1")))
}

pub fn null_value_round_trips_with_has_true_test() -> Nil {
  // JSON null is a legitimate claimed value; `has` distinguishes it from
  // "never set", and it survives a summary round trip.
  let #(state, operation) =
    submitted(claims_kernel.claim_once(claims_kernel.new(), "k", json.null(), 0))
  let #(state, _e, outcome) = ack(state, operation, 1)
  outcome |> expect.to_equal(Accepted(json.null()))
  claims_kernel.get(state, "k") |> expect.to_equal(Ok(json.null()))
  claims_kernel.has(state, "k") |> expect.to_be_true()
  let loaded = claims_kernel.from_summary(claims_kernel.summary_entries(state))
  claims_kernel.get(loaded, "k") |> expect.to_equal(Ok(json.null()))
  claims_kernel.has(loaded, "k") |> expect.to_be_true()
}
