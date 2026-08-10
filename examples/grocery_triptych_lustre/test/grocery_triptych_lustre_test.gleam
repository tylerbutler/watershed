import gleeunit
import gleeunit/should

import pantry_snapshot

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn snapshots_are_sorted_for_stable_rendering_test() {
  pantry_snapshot.from_values(
    grow_only: ["pear", "apple", "banana"],
    two_phase: ["milk", "bread"],
    observed: ["zucchini", "carrot", "beet"],
  )
  |> should.equal(
    pantry_snapshot.Snapshots(
      grow_only: ["apple", "banana", "pear"],
      two_phase: ["bread", "milk"],
      observed: ["beet", "carrot", "zucchini"],
    ),
  )
}

pub fn rows_cover_the_union_without_dropping_absent_panels_test() {
  pantry_snapshot.from_values(
    grow_only: ["eggs", "apples"],
    two_phase: ["bread", "eggs"],
    observed: ["apples", "cereal", "eggs"],
  )
  |> pantry_snapshot.rows
  |> should.equal([
    pantry_snapshot.Row(
      item: "apples",
      grow_only: True,
      two_phase: False,
      observed: True,
      diverges: True,
    ),
    pantry_snapshot.Row(
      item: "bread",
      grow_only: False,
      two_phase: True,
      observed: False,
      diverges: True,
    ),
    pantry_snapshot.Row(
      item: "cereal",
      grow_only: False,
      two_phase: False,
      observed: True,
      diverges: True,
    ),
    pantry_snapshot.Row(
      item: "eggs",
      grow_only: True,
      two_phase: True,
      observed: True,
      diverges: False,
    ),
  ])
}

pub fn diff_counts_track_the_odd_panel_out_test() {
  let rows =
    pantry_snapshot.from_values(
      grow_only: ["milk", "rice"],
      two_phase: ["rice"],
      observed: ["milk"],
    )
    |> pantry_snapshot.rows

  pantry_snapshot.diff_counts(rows)
  |> should.equal(pantry_snapshot.DiffCounts(
    grow_only: 0,
    two_phase: 1,
    observed: 1,
  ))
}
