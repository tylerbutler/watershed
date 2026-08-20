//// The sidebar's pure rules, fed edge cases with no channel involved.

import gleeunit/should
import markdown_notes_lustre/sidebar

pub fn display_order_follows_the_sequence_test() {
  sidebar.display_order(["a", "b", "c"], ["c", "a", "b"])
  |> should.equal(["c", "a", "b"])
}

pub fn display_order_dedupes_first_occurrence_wins_test() {
  // A doubled concurrent create yields two sequence entries; render once.
  sidebar.display_order(["a", "b"], ["b", "a", "b"])
  |> should.equal(["b", "a"])
}

pub fn display_order_drops_sequence_only_names_test() {
  // "ghost" is in the sequence but was deleted from the map.
  sidebar.display_order(["a"], ["ghost", "a"])
  |> should.equal(["a"])
}

pub fn display_order_appends_map_only_names_alphabetically_test() {
  // "z" and "m" never made it into the sequence; they still render, sorted.
  sidebar.display_order(["z", "a", "m"], ["a"])
  |> should.equal(["a", "m", "z"])
}

pub fn tags_of_filters_and_sorts_test() {
  sidebar.tags_of(["a\turgent", "b\tlater", "a\tdraft", "not-a-pair"], "a")
  |> should.equal(["draft", "urgent"])
}

pub fn notes_with_tag_test() {
  sidebar.notes_with_tag(["a\turgent", "b\turgent", "c\tlater"], "urgent")
  |> should.equal(["a", "b"])
}

pub fn all_tags_hides_orphaned_pairs_test() {
  // "ghost" was deleted; its pair stays in the set but is not shown.
  sidebar.all_tags(["a\turgent", "ghost\tlost", "b\tlater", "a\tlater"], [
    "a",
    "b",
  ])
  |> should.equal(["later", "urgent"])
}
