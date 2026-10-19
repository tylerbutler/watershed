import fixture
import gleam/option.{None, Some}
import shared_tree_project_brief_lustre/brief
import shared_tree_project_brief_lustre/edits
import shared_tree_project_brief_lustre/schema
import watershed
import watershed/tree
import watershed/tree/error

pub fn captured_milestone_survives_neighbor_removal_test() {
  let fixture = fixture.new(brief.initial("first", "second"))
  let assert Ok(before) = edits.capture(fixture.tree)
  let assert [#("first", first), #("second", second)] = before.milestone_nodes
  let assert Ok(Nil) = edits.remove(before.milestones, first)
  let assert Ok(Nil) =
    tree.set(second, schema.milestone_title(), "Still second")
  let assert Ok(after) = tree.read_root(fixture.tree)
  let assert [brief.Milestone("second", "Still second", False)] =
    after.schedule.milestones
  let assert Ok(captured) = edits.capture(fixture.tree)
  let assert [#("second", surviving)] = captured.milestone_nodes
  let assert Ok(brief.Milestone("second", "Still second", False)) =
    tree.read(surviving)
  watershed.close(fixture.document)
}

pub fn removed_review_cannot_edit_replacement_test() {
  let initial = brief.initial("first", "second")
  let initial =
    brief.ProjectBrief(..initial, review: Some(brief.Review("Old", True)))
  let fixture = fixture.new(initial)
  let assert Ok(before) = edits.capture(fixture.tree)
  let assert Some(old) = before.review
  let assert Ok(Nil) = tree.set(before.root, schema.review(), None)
  let assert Ok(absent) = edits.capture(fixture.tree)
  let assert None = absent.review
  let assert Ok(Nil) =
    tree.set(before.root, schema.review(), Some(brief.Review("", False)))
  let assert Error(error.InvalidReference(_)) =
    tree.set(old, schema.review_reviewer(), "Stale edit")
  let assert Ok(after) = edits.capture(fixture.tree)
  let assert Some(replacement) = after.review
  let assert Ok(brief.Review("", False)) = tree.read(replacement)
  let assert Some(brief.Review("", False)) = after.value.review
  watershed.close(fixture.document)
}

pub fn removed_milestone_cannot_edit_or_remove_replacement_test() {
  let fixture = fixture.new(brief.initial("first", "second"))
  let assert Ok(before) = edits.capture(fixture.tree)
  let assert [#(_, old), #(_, _)] = before.milestone_nodes
  let assert Ok(Nil) = edits.remove(before.milestones, old)
  let assert Ok(Nil) = edits.append(before.schedule, "fresh")
  let assert Error(error.InvalidReference(_)) =
    tree.set(old, schema.milestone_title(), "Stale edit")
  let assert Error(error.InvalidReference(_)) =
    edits.remove(before.milestones, old)
  let assert Ok(after) = edits.capture(fixture.tree)
  let assert [
    brief.Milestone("second", "Ship preview", False),
    brief.Milestone("fresh", "", False),
  ] = after.value.schedule.milestones
  let assert [#("second", _), #("fresh", replacement)] = after.milestone_nodes
  let assert Ok(brief.Milestone("fresh", "", False)) = tree.read(replacement)
  watershed.close(fixture.document)
}

pub fn owner_leaf_edit_preserves_other_fields_test() {
  let initial = brief.initial("first", "second")
  let initial =
    brief.ProjectBrief(..initial, review: Some(brief.Review("Sam", True)))
  let fixture = fixture.new(initial)
  let assert Ok(before) = edits.capture(fixture.tree)
  let assert Ok(Nil) = tree.set(before.owner, schema.owner_name(), "Morgan")
  let assert Ok(after) = edits.capture(fixture.tree)
  let assert True =
    after.value
    == brief.ProjectBrief(
      ..initial,
      owner: brief.Owner("Morgan", "alex@example.test"),
    )
  let assert Ok(brief.Owner("Morgan", "alex@example.test")) =
    tree.read(before.owner)
  watershed.close(fixture.document)
}

pub fn append_uses_current_length_of_captured_schedule_test() {
  let fixture = fixture.new(brief.initial("first", "second"))
  let assert Ok(before) = edits.capture(fixture.tree)
  let assert [#(_, first), #(_, _)] = before.milestone_nodes
  let assert Ok(Nil) = edits.remove(before.milestones, first)
  let assert Ok(Nil) = edits.append(before.schedule, "third")
  let assert Ok(Nil) = edits.append(before.schedule, "fourth")
  let assert Ok(after) = tree.read_root(fixture.tree)
  let assert [
    brief.Milestone("second", "Ship preview", False),
    brief.Milestone("third", "", False),
    brief.Milestone("fourth", "", False),
  ] = after.schedule.milestones
  watershed.close(fixture.document)
}

pub fn capture_empty_milestones_and_absent_review_test() {
  let initial = brief.initial("first", "second")
  let initial =
    brief.ProjectBrief(
      ..initial,
      schedule: brief.Schedule("2026-11-02", "2026-11-16", []),
    )
  let fixture = fixture.new(initial)
  let assert Ok(before) = edits.capture(fixture.tree)
  let assert True = before.value == initial
  let assert [] = before.milestone_nodes
  let assert None = before.review
  let assert Ok(Nil) = edits.append(before.schedule, "fresh")
  let assert Ok(after) = edits.capture(fixture.tree)
  let assert [#("fresh", node)] = after.milestone_nodes
  let assert Ok(brief.Milestone("fresh", "", False)) = tree.read(node)
  watershed.close(fixture.document)
}

pub fn closed_tree_errors_are_propagated_test() {
  let fixture = fixture.new(brief.initial("first", "second"))
  let assert Ok(before) = edits.capture(fixture.tree)
  let assert [#(_, first), #(_, _)] = before.milestone_nodes
  let assert Ok(Nil) = tree.dispose(fixture.tree)
  let assert Error(error.ClosedTree) = edits.capture(fixture.tree)
  let assert Error(error.ClosedTree) = edits.append(before.schedule, "third")
  let assert Error(error.ClosedTree) = edits.remove(before.milestones, first)
  watershed.close(fixture.document)
}
