import gleam/list
import gleam/option.{type Option, None, Some}

import pantry_snapshot.{type Snapshots}

pub const tombstone_item = "milk"

pub const concurrent_item = "eggs"

pub type VerificationOutcome {
  Verified
  Retry(attempts_remaining: Int)
  TimedOut
}

pub fn tombstone_locked_message() -> String {
  "Tombstone already ran in this room. Use a fresh room URL to rerun because TwoPSet cannot reset."
}

pub fn invitation_timeout_message() -> String {
  "Concurrent add/remove timed out waiting for a second ready tab. Retry is available because the remove phase never started."
}

pub fn expected_concurrent_summary() -> String {
  "expected GSet present, TwoPSet absent, OrSet present"
}

pub fn tombstone_button_reason(
  ready ready: Bool,
  busy busy: Bool,
  completed completed: Bool,
) -> Option(String) {
  case ready {
    False ->
      Some(
        "Tombstone is disabled until the document handle and pantry bootstrap finish.",
      )

    True ->
      case busy {
        True -> Some("Tombstone is disabled while another scenario is running.")
        False ->
          case completed {
            True -> Some(tombstone_locked_message())
            False -> None
          }
      }
  }
}

pub fn concurrent_matches_expected(snapshots: Snapshots) -> Bool {
  list.contains(snapshots.grow_only, concurrent_item)
  && !list.contains(snapshots.two_phase, concurrent_item)
  && list.contains(snapshots.observed, concurrent_item)
}

pub fn concurrent_summary(snapshots: Snapshots) -> String {
  "GSet "
  <> presence(list.contains(snapshots.grow_only, concurrent_item))
  <> ", TwoPSet "
  <> presence(list.contains(snapshots.two_phase, concurrent_item))
  <> ", OrSet "
  <> presence(list.contains(snapshots.observed, concurrent_item))
}

pub fn advance_verification(
  snapshots: Snapshots,
  attempts_remaining: Int,
) -> VerificationOutcome {
  case concurrent_matches_expected(snapshots) {
    True -> Verified
    False ->
      case attempts_remaining > 0 {
        True -> Retry(attempts_remaining - 1)
        False -> TimedOut
      }
  }
}

fn presence(present: Bool) -> String {
  case present {
    True -> "present"
    False -> "absent"
  }
}
