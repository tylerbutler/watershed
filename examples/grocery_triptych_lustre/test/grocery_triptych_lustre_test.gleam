import gleeunit
import gleeunit/should

import grocery_triptych_lustre
import grocery_triptych_lustre/pantry_snapshot

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn snapshots_are_sorted_for_stable_rendering_test() -> Nil {
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

pub fn rows_cover_the_union_without_dropping_absent_panels_test() -> Nil {
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
    ),
    pantry_snapshot.Row(
      item: "bread",
      grow_only: False,
      two_phase: True,
      observed: False,
    ),
    pantry_snapshot.Row(
      item: "cereal",
      grow_only: False,
      two_phase: False,
      observed: True,
    ),
    pantry_snapshot.Row(
      item: "eggs",
      grow_only: True,
      two_phase: True,
      observed: True,
    ),
  ])
}

pub fn diff_counts_track_divergent_rows_for_each_panel_test() -> Nil {
  let rows =
    pantry_snapshot.from_values(grow_only: ["milk"], two_phase: [], observed: [
      "milk",
    ])
    |> pantry_snapshot.rows

  pantry_snapshot.diff_counts(rows)
  |> should.equal(pantry_snapshot.DiffCounts(
    grow_only: 1,
    two_phase: 1,
    observed: 1,
  ))
}

pub fn remove_action_requires_a_removable_copy_test() -> Nil {
  let rows =
    pantry_snapshot.from_values(
      grow_only: ["milk", "eggs"],
      two_phase: ["eggs"],
      observed: ["eggs"],
    )
    |> pantry_snapshot.rows

  let assert [eggs, milk] = rows

  pantry_snapshot.row_has_removable_copy(eggs)
  |> should.equal(True)

  pantry_snapshot.row_has_removable_copy(milk)
  |> should.equal(False)
}

pub fn divergence_is_derived_from_row_presence_test() -> Nil {
  pantry_snapshot.Row(
    item: "eggs",
    grow_only: True,
    two_phase: True,
    observed: True,
  )
  |> pantry_snapshot.diverges
  |> should.equal(False)

  pantry_snapshot.Row(
    item: "milk",
    grow_only: True,
    two_phase: False,
    observed: True,
  )
  |> pantry_snapshot.diverges
  |> should.equal(True)
}

pub fn concurrent_peer_go_timeout_covers_ack_window_test() -> Nil {
  grocery_triptych_lustre.concurrent_peer_go_timeout_covers_ack_window()
  |> should.equal(True)
}
