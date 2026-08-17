//// Pure captain/readiness rules for the release checklist, kept out of
//// `release_checklist_lustre` so the gating logic — who may claim the
//// captain seat, when every gate is satisfied, and when a release target may
//// be drafted — can be exercised directly without any watershed channel or
//// Lustre effect in the loop.

import gleam/list
import gleam/option.{type Option, Some}
import gleam/string

/// Whether `user_id` is the currently committed captain. `committed` is
/// whatever `watershed_js.get_claim` on the `"captain"` key decoded to —
/// `None` until someone claims the seat.
///
/// This is a UI convenience, not an authorization boundary: nothing in
/// watershed stops another client from calling `pact_map_set` on the release
/// target directly. The app enforces "only the captain publishes" the same
/// way it enforces every other rule here — by not offering the control to
/// anyone else — and says so in the UI copy.
pub fn is_captain(committed: Option(String), user_id: String) -> Bool {
  committed == Some(user_id)
}

/// Whether every required gate id is present among the completed ones. Order
/// and duplicates in `completed` do not matter — it is read straight off an
/// OR-set, which has neither.
pub fn all_checks_complete(
  completed: List(String),
  required: List(String),
) -> Bool {
  list.all(required, fn(id) { list.contains(completed, id) })
}

/// Whether the captain may draft/propose a release target right now.
///
/// All five conditions are required: only the captain proposes; every fixed
/// gate must be complete; the target text must be non-blank; and there must
/// be no proposal already pending or in the submit-to-pending gap — a second
/// `pact_map_set` while one of ours is already in flight would either be
/// rejected outright or race its own proposal.
pub fn can_propose(
  is_captain: Bool,
  all_checks_complete: Bool,
  target: String,
  proposal_pending: Bool,
  submitting: Bool,
) -> Bool {
  is_captain
  && all_checks_complete
  && string.trim(target) != ""
  && !proposal_pending
  && !submitting
}
