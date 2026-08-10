import gleam/option.{Some}
import gleeunit
import gleeunit/should

import pantry_snapshot
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

fn expected_snapshots() -> pantry_snapshot.Snapshots {
  pantry_snapshot.Snapshots(
    grow_only: [scenario_state.concurrent_item],
    two_phase: [],
    observed: [scenario_state.concurrent_item],
  )
}

fn unexpected_snapshots() -> pantry_snapshot.Snapshots {
  pantry_snapshot.Snapshots(
    grow_only: [scenario_state.concurrent_item],
    two_phase: [scenario_state.concurrent_item],
    observed: [],
  )
}
