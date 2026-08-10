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

pub fn tombstone_completion_is_detected_from_durable_snapshots_test() {
  scenario_state.tombstone_matches_expected(completed_tombstone_snapshots())
  |> should.equal(True)
}

pub fn incomplete_tombstone_snapshots_do_not_lock_the_room_test() {
  scenario_state.tombstone_matches_expected(incomplete_tombstone_snapshots())
  |> should.equal(False)
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

fn expected_snapshots() -> pantry_snapshot.Snapshots {
  pantry_snapshot.Snapshots(
    grow_only: [scenario_state.concurrent_item],
    two_phase: [],
    observed: [scenario_state.concurrent_item],
  )
}

fn completed_tombstone_snapshots() -> pantry_snapshot.Snapshots {
  pantry_snapshot.Snapshots(
    grow_only: [scenario_state.tombstone_item],
    two_phase: [],
    observed: [scenario_state.tombstone_item],
  )
}

fn incomplete_tombstone_snapshots() -> pantry_snapshot.Snapshots {
  pantry_snapshot.Snapshots(
    grow_only: [scenario_state.tombstone_item],
    two_phase: [],
    observed: [],
  )
}

fn unexpected_snapshots() -> pantry_snapshot.Snapshots {
  pantry_snapshot.Snapshots(
    grow_only: [scenario_state.concurrent_item],
    two_phase: [scenario_state.concurrent_item],
    observed: [],
  )
}
