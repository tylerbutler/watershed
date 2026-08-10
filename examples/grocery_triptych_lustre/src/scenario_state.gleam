import gleam/list
import gleam/option.{type Option, None, Some}

import pantry_snapshot.{type Snapshots}
import scenario_protocol

pub const tombstone_item = "milk"

pub const concurrent_item = "eggs"

pub type VerificationOutcome {
  Verified
  Retry(attempts_remaining: Int)
  TimedOut
}

pub type PeerStatusUpdate {
  IgnoreWhileAwaitingGo
  KeepVerifying(note: String)
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

pub fn tombstone_matches_expected(snapshots: Snapshots) -> Bool {
  list.contains(snapshots.grow_only, tombstone_item)
  && !list.contains(snapshots.two_phase, tombstone_item)
}

pub fn concurrent_matches_expected(snapshots: Snapshots) -> Bool {
  list.contains(snapshots.grow_only, concurrent_item)
  && !list.contains(snapshots.two_phase, concurrent_item)
  && list.contains(snapshots.observed, concurrent_item)
}

pub fn observe_peer_status(
  participating participating: Bool,
  status status: scenario_protocol.Status,
) -> PeerStatusUpdate {
  case participating {
    False -> IgnoreWhileAwaitingGo
    True -> KeepVerifying(peer_status_note(status))
  }
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

pub fn has_seen_run_id(seen_run_ids: List(String), run_id: String) -> Bool {
  list.contains(seen_run_ids, run_id)
}

pub fn remember_run_id(
  seen_run_ids: List(String),
  run_id: String,
) -> List(String) {
  case has_seen_run_id(seen_run_ids, run_id) {
    True -> seen_run_ids
    False -> [run_id, ..seen_run_ids]
  }
}

fn peer_status_note(status: scenario_protocol.Status) -> String {
  case status {
    scenario_protocol.VerifiedExpectedOutcome ->
      "Concurrent add/remove: the initiator reported the expected eventual outcome while this tab keeps validating its own snapshots."
    scenario_protocol.VerificationTimedOut ->
      "Concurrent add/remove: the initiator timed out while waiting for the expected eventual outcome; this tab will report its own verified state honestly too."
    scenario_protocol.PeerAppliedAdd ->
      "Concurrent add/remove: ignored an unexpected peer-applied status on the peer side."
  }
}

fn presence(present: Bool) -> String {
  case present {
    True -> "present"
    False -> "absent"
  }
}
