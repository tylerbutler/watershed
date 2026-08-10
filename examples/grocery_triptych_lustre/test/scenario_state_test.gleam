import gleam/option.{Some}
import gleeunit
import gleeunit/should

import pantry_snapshot
import scenario_protocol
import scenario_state

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn completed_tombstone_blocks_the_button_test() {
  scenario_state.tombstone_button_reason(
    ready: True,
    busy: False,
    completed: True,
  )
  |> should.equal(Some(scenario_state.tombstone_locked_message()))
}

pub fn tombstone_completion_is_detected_when_or_set_still_contains_milk_test() {
  scenario_state.tombstone_matches_expected(completed_tombstone_snapshots())
  |> should.equal(True)
}

pub fn tombstone_completion_is_detected_when_or_set_no_longer_contains_milk_test() {
  scenario_state.tombstone_matches_expected(
    completed_without_or_set_snapshots(),
  )
  |> should.equal(True)
}

pub fn tombstone_completion_waits_for_two_phase_removal_evidence_test() {
  scenario_state.tombstone_matches_expected(
    before_two_phase_removal_snapshots(),
  )
  |> should.equal(False)
}

pub fn tombstone_preflight_refuses_live_rooms_that_are_already_tombstoned_test() {
  [
    scenario_state.tombstone_preflight_outcome(
      before_two_phase_removal_snapshots(),
    ),
    scenario_state.tombstone_preflight_outcome(completed_tombstone_snapshots()),
    scenario_state.tombstone_preflight_outcome(
      completed_without_or_set_snapshots(),
    ),
  ]
  |> should.equal([
    scenario_state.TombstonePreflightRetryable,
    scenario_state.TombstonePreflightComplete(
      scenario_state.tombstone_complete_status(),
    ),
    scenario_state.TombstonePreflightComplete(
      scenario_state.tombstone_complete_status(),
    ),
  ])
}

pub fn tombstone_add_step_continues_only_when_two_phase_recovers_live_presence_test() {
  [
    scenario_state.tombstone_add_step_outcome(True),
    scenario_state.tombstone_add_step_outcome(False),
  ]
  |> should.equal([
    scenario_state.TombstoneAddStepContinue,
    scenario_state.TombstoneAddStepComplete(
      scenario_state.tombstone_add_step_locked_status(),
    ),
  ])
}

pub fn concurrent_room_starts_retryable_when_eggs_have_never_crossed_the_remove_phase_test() {
  scenario_state.concurrent_durable_state(initial_snapshots())
  |> should.equal(scenario_state.DurableRetryable)
}

pub fn concurrent_room_stays_retryable_while_eggs_are_still_present_in_all_sets_test() {
  scenario_state.concurrent_durable_state(prepared_snapshots())
  |> should.equal(scenario_state.DurableRetryable)
}

pub fn concurrent_room_derives_complete_after_the_remove_phase_when_or_set_keeps_eggs_test() {
  scenario_state.concurrent_durable_state(expected_snapshots())
  |> should.equal(durable_complete_state())
}

pub fn concurrent_room_derives_locked_after_the_remove_phase_when_or_set_loses_eggs_test() {
  scenario_state.concurrent_durable_state(consumed_incomplete_snapshots())
  |> should.equal(durable_locked_state())
}

pub fn or_set_churn_never_makes_a_consumed_room_retryable_again_test() {
  [
    scenario_state.concurrent_durable_state(expected_snapshots()),
    scenario_state.concurrent_durable_state(consumed_incomplete_snapshots()),
    scenario_state.concurrent_durable_state(expected_snapshots()),
  ]
  |> should.equal([
    durable_complete_state(),
    durable_locked_state(),
    durable_complete_state(),
  ])
}

pub fn concurrent_preflight_allows_retry_only_while_live_room_is_unconsumed_test() {
  [
    scenario_state.concurrent_preflight_outcome(initial_snapshots()),
    scenario_state.concurrent_preflight_outcome(prepared_snapshots()),
    scenario_state.concurrent_preflight_outcome(expected_snapshots()),
    scenario_state.concurrent_preflight_outcome(consumed_incomplete_snapshots()),
  ]
  |> should.equal([
    scenario_state.PreflightRetryable,
    scenario_state.PreflightRetryable,
    scenario_state.PreflightComplete(
      "Concurrent add/remove is complete for this room; settled snapshots show expected GSet present, TwoPSet absent, OrSet present.",
      scenario_state.concurrent_locked_message(),
    ),
    scenario_state.PreflightLocked(
      "Concurrent add/remove already consumed this room; settled snapshots show GSet present, TwoPSet absent, OrSet absent instead of expected GSet present, TwoPSet absent, OrSet present.",
      scenario_state.concurrent_locked_message(),
    ),
  ])
}

pub fn peer_go_timeout_applies_live_durable_evidence_before_returning_idle_test() {
  [
    scenario_state.concurrent_peer_go_timeout_outcome(
      "run-7",
      initial_snapshots(),
    ),
    scenario_state.concurrent_peer_go_timeout_outcome(
      "run-7",
      prepared_snapshots(),
    ),
    scenario_state.concurrent_peer_go_timeout_outcome(
      "run-7",
      expected_snapshots(),
    ),
    scenario_state.concurrent_peer_go_timeout_outcome(
      "run-7",
      consumed_incomplete_snapshots(),
    ),
  ]
  |> should.equal([
    scenario_state.PeerGoRetryable(
      "Concurrent add/remove: no go arrived for run run-7, so this tab stayed waiting until timeout, did not mutate anything, and returned to idle ready to retry.",
    ),
    scenario_state.PeerGoRetryable(
      "Concurrent add/remove: no go arrived for run run-7, so this tab stayed waiting until timeout, did not mutate anything, and returned to idle ready to retry.",
    ),
    scenario_state.PeerGoComplete(
      "Concurrent add/remove is complete for this room; settled snapshots show expected GSet present, TwoPSet absent, OrSet present.",
      scenario_state.concurrent_locked_message(),
    ),
    scenario_state.PeerGoLocked(
      "Concurrent add/remove already consumed this room; settled snapshots show GSet present, TwoPSet absent, OrSet absent instead of expected GSet present, TwoPSet absent, OrSet present.",
      scenario_state.concurrent_locked_message(),
    ),
  ])
}

pub fn verification_succeeds_on_expected_snapshots_test() {
  scenario_state.advance_verification(expected_snapshots(), 2)
  |> should.equal(scenario_state.Verified)
}

pub fn verification_retries_before_timing_out_test() {
  scenario_state.advance_verification(unexpected_snapshots(), 2)
  |> should.equal(scenario_state.Retry(1))
}

pub fn verification_times_out_honestly_when_retries_are_exhausted_test() {
  scenario_state.advance_verification(unexpected_snapshots(), 0)
  |> should.equal(scenario_state.TimedOut)
}

pub fn invitation_timeout_copy_stays_truthful_about_seeded_eggs_test() {
  scenario_state.invitation_timeout_message()
  |> should.equal(
    "Concurrent add/remove timed out waiting for a second ready tab. No remove phase began, and the seeded \"eggs\" can be reused for retry.",
  )
}

pub fn pre_remove_phase_timeouts_stay_retryable_test() {
  scenario_state.concurrent_timeout_state(
    remove_phase_began: False,
    status: scenario_state.invitation_timeout_message(),
  )
  |> should.equal(
    scenario_state.RetryableTimeout(scenario_state.invitation_timeout_message()),
  )
}

pub fn post_remove_phase_timeouts_lock_the_room_test() {
  scenario_state.concurrent_timeout_state(
    remove_phase_began: True,
    status: "verification timed out",
  )
  |> should.equal(scenario_state.LockedTimeout(
    "verification timed out",
    scenario_state.concurrent_locked_message(),
  ))
}

pub fn concurrent_summary_reports_the_current_triptych_state_test() {
  scenario_state.concurrent_summary(unexpected_snapshots())
  |> should.equal("GSet present, TwoPSet present, OrSet absent")
}

pub fn lost_go_peers_ignore_final_status_ripples_test() {
  scenario_state.observe_peer_status(
    participating: False,
    status: scenario_protocol.VerifiedExpectedOutcome,
  )
  |> should.equal(scenario_state.IgnoreWhileAwaitingGo)
}

pub fn participating_peers_keep_verifying_after_status_ripples_test() {
  scenario_state.observe_peer_status(
    participating: True,
    status: scenario_protocol.VerifiedExpectedOutcome,
  )
  |> should.equal(scenario_state.KeepVerifying(
    "Concurrent add/remove: the initiator reported the expected eventual outcome while this tab keeps validating its own snapshots.",
  ))
}

pub fn participating_peers_keep_verifying_after_timeout_status_ripples_test() {
  scenario_state.observe_peer_status(
    participating: True,
    status: scenario_protocol.VerificationTimedOut,
  )
  |> should.equal(scenario_state.KeepVerifying(
    "Concurrent add/remove: the initiator timed out while waiting for the expected eventual outcome. This status is advisory only; this tab keeps validating its own snapshots until its local bound decides complete or locked.",
  ))

  scenario_state.advance_verification(expected_snapshots(), 2)
  |> should.equal(scenario_state.Verified)
}

pub fn run_history_remembers_seen_run_ids_without_duplicates_test() {
  let seen =
    []
    |> scenario_state.remember_run_id("run-1")
    |> scenario_state.remember_run_id("run-2")
    |> scenario_state.remember_run_id("run-1")

  seen
  |> should.equal(["run-2", "run-1"])

  scenario_state.has_seen_run_id(seen, "run-1")
  |> should.equal(True)

  scenario_state.has_seen_run_id(seen, "run-3")
  |> should.equal(False)
}

fn initial_snapshots() -> pantry_snapshot.Snapshots {
  pantry_snapshot.Snapshots(grow_only: [], two_phase: [], observed: [])
}

fn prepared_snapshots() -> pantry_snapshot.Snapshots {
  pantry_snapshot.Snapshots(
    grow_only: [scenario_state.concurrent_item],
    two_phase: [scenario_state.concurrent_item],
    observed: [scenario_state.concurrent_item],
  )
}

fn expected_snapshots() -> pantry_snapshot.Snapshots {
  pantry_snapshot.Snapshots(
    grow_only: [scenario_state.concurrent_item],
    two_phase: [],
    observed: [scenario_state.concurrent_item],
  )
}

fn consumed_incomplete_snapshots() -> pantry_snapshot.Snapshots {
  pantry_snapshot.Snapshots(
    grow_only: [scenario_state.concurrent_item],
    two_phase: [],
    observed: [],
  )
}

fn completed_tombstone_snapshots() -> pantry_snapshot.Snapshots {
  pantry_snapshot.Snapshots(
    grow_only: [scenario_state.tombstone_item],
    two_phase: [],
    observed: [scenario_state.tombstone_item],
  )
}

fn completed_without_or_set_snapshots() -> pantry_snapshot.Snapshots {
  pantry_snapshot.Snapshots(
    grow_only: [scenario_state.tombstone_item],
    two_phase: [],
    observed: [],
  )
}

fn before_two_phase_removal_snapshots() -> pantry_snapshot.Snapshots {
  pantry_snapshot.Snapshots(
    grow_only: [scenario_state.tombstone_item],
    two_phase: [scenario_state.tombstone_item],
    observed: [scenario_state.tombstone_item],
  )
}

fn unexpected_snapshots() -> pantry_snapshot.Snapshots {
  pantry_snapshot.Snapshots(
    grow_only: [scenario_state.concurrent_item],
    two_phase: [scenario_state.concurrent_item],
    observed: [],
  )
}

fn durable_complete_state() -> scenario_state.ConcurrentDurableState {
  scenario_state.DurableComplete(
    "Concurrent add/remove is complete for this room; settled snapshots show expected GSet present, TwoPSet absent, OrSet present.",
    scenario_state.concurrent_locked_message(),
  )
}

fn durable_locked_state() -> scenario_state.ConcurrentDurableState {
  scenario_state.DurableLocked(
    "Concurrent add/remove already consumed this room; settled snapshots show GSet present, TwoPSet absent, OrSet absent instead of expected GSet present, TwoPSet absent, OrSet present.",
    scenario_state.concurrent_locked_message(),
  )
}
