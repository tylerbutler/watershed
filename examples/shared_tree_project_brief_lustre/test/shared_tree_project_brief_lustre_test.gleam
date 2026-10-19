import gleam/list
import gleam/option.{None, Some}
import gleeunit
import shared_tree_project_brief_lustre/brief
import shared_tree_project_brief_lustre/schema
import watershed/tree/schema_builder as builder
import watershed/tree/types

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn nested_brief_round_trip_test() {
  let initial = brief.initial("first", "second")
  let assert Ok(compiled) = builder.compile(schema.configuration())
  let assert Ok(encoded) = builder.encode_new(compiled, initial)
  let assert Ok(decoded) = builder.decode(compiled, encoded)
  let assert True = decoded == initial
  let assert 2 = list.length(decoded.schedule.milestones)
  let assert None = decoded.review
  let assert brief.ProjectBrief(
    "Release brief",
    brief.Owner("Alex", "alex@example.test"),
    brief.Schedule(
      "2026-11-02",
      "2026-11-16",
      [
        brief.Milestone("first", "Agree scope", False),
        brief.Milestone("second", "Ship preview", False),
      ],
    ),
    None,
  ) = decoded
}

pub fn present_empty_review_and_incomplete_text_round_trip_test() {
  let initial =
    brief.ProjectBrief(
      "",
      brief.Owner("", "alex@"),
      brief.Schedule("2026-", "", [brief.Milestone("first", "", False)]),
      Some(brief.Review("", False)),
    )
  let assert Ok(compiled) = builder.compile(schema.configuration())
  let assert Ok(encoded) = builder.encode_new(compiled, initial)
  let assert Ok(decoded) = builder.decode(compiled, encoded)
  let assert True = decoded == initial
  let assert Some(brief.Review("", False)) = decoded.review
}

pub fn snapshot_decoder_rejects_duplicate_milestone_ids_test() {
  let initial = brief.initial("same", "same")
  let assert Ok(compiled) = builder.compile(schema.configuration())
  let assert Ok(encoded) = builder.encode(compiled, initial)
  let assert Error(types.InvalidEdit(_, _)) = builder.decode(compiled, encoded)
  let assert Error(_) = brief.validate_unique_ids(initial.schedule.milestones)
}

pub fn milestone_id_validation_accepts_empty_and_distinct_lists_test() {
  let assert Ok(Nil) = brief.validate_unique_ids([])
  let initial = brief.initial("first", "second")
  let assert Ok(Nil) = brief.validate_unique_ids(initial.schedule.milestones)
  let assert Error(_) =
    brief.validate_unique_ids([
      brief.Milestone("first", "", False),
      brief.Milestone("second", "", False),
      brief.Milestone("first", "", True),
    ])
}
