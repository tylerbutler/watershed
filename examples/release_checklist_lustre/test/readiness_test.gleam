import gleam/option.{None, Some}
import gleeunit/should

import release_checklist_lustre/release_readiness

pub fn is_captain_none_test() -> Nil {
  release_readiness.is_captain(None, "web-1234")
  |> should.be_false
}

pub fn is_captain_self_test() -> Nil {
  release_readiness.is_captain(Some("web-1234"), "web-1234")
  |> should.be_true
}

pub fn is_captain_someone_else_test() -> Nil {
  release_readiness.is_captain(Some("web-9999"), "web-1234")
  |> should.be_false
}

pub fn all_checks_complete_empty_required_test() -> Nil {
  release_readiness.all_checks_complete([], [])
  |> should.be_true
}

pub fn all_checks_complete_missing_one_test() -> Nil {
  release_readiness.all_checks_complete(["tests_passing"], [
    "tests_passing", "changelog_updated",
  ])
  |> should.be_false
}

pub fn all_checks_complete_all_present_test() -> Nil {
  release_readiness.all_checks_complete(
    ["changelog_updated", "tests_passing", "docs_updated"],
    ["tests_passing", "changelog_updated", "docs_updated"],
  )
  |> should.be_true
}

pub fn all_checks_complete_ignores_extras_test() -> Nil {
  // Extra completed ids beyond the fixed set — from a future version of the
  // app, say — do not block readiness; only the required set matters.
  release_readiness.all_checks_complete(
    ["tests_passing", "changelog_updated", "docs_updated", "mystery_gate"],
    ["tests_passing", "changelog_updated", "docs_updated"],
  )
  |> should.be_true
}

pub fn can_propose_requires_captain_test() -> Nil {
  release_readiness.can_propose(False, True, "v1.2.3", False, False)
  |> should.be_false
}

pub fn can_propose_requires_all_checks_test() -> Nil {
  release_readiness.can_propose(True, False, "v1.2.3", False, False)
  |> should.be_false
}

pub fn can_propose_requires_nonblank_target_test() -> Nil {
  release_readiness.can_propose(True, True, "", False, False)
  |> should.be_false
}

pub fn can_propose_requires_nonblank_target_whitespace_test() -> Nil {
  release_readiness.can_propose(True, True, "   ", False, False)
  |> should.be_false
}

pub fn can_propose_blocked_while_pending_test() -> Nil {
  release_readiness.can_propose(True, True, "v1.2.3", True, False)
  |> should.be_false
}

pub fn can_propose_blocked_in_submit_gap_test() -> Nil {
  release_readiness.can_propose(True, True, "v1.2.3", False, True)
  |> should.be_false
}

pub fn can_propose_true_when_everything_lines_up_test() -> Nil {
  release_readiness.can_propose(True, True, "v1.2.3", False, False)
  |> should.be_true
}
