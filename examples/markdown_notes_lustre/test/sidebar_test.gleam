//// The sidebar's pure rules, fed edge cases with no channel involved.

import gleeunit/should
import markdown_notes_lustre/sidebar

pub fn tags_of_filters_and_sorts_test() {
  sidebar.tags_of(
    ["a\turgent", "b\tlater", "a\tdraft", "not-a-pair"],
    "a",
  )
  |> should.equal(["draft", "urgent"])
}

pub fn notes_with_tag_test() {
  sidebar.notes_with_tag(["a\turgent", "b\turgent", "c\tlater"], "urgent")
  |> should.equal(["a", "b"])
}

pub fn all_tags_hides_orphaned_pairs_test() {
  // "ghost" was deleted; its pair stays in the set but is not shown.
  sidebar.all_tags(
    ["a\turgent", "ghost\tlost", "b\tlater", "a\tlater"],
    ["a", "b"],
  )
  |> should.equal(["later", "urgent"])
}
