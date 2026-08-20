//// The toolbar helpers are pure functions from (text, selection) to insert
//// ops, so line-start math, collapsed-caret wrapping, and end-before-start
//// ordering get plain tests with no channel at all.

import gleeunit/should
import markdown_notes_lustre/toolbar

pub fn wrap_emits_end_insert_first_test() {
  toolbar.wrap(#(4, 9), "**")
  |> should.equal([#(9, "**"), #(4, "**")])
}

pub fn wrap_collapsed_caret_inserts_delimiters_around_it_test() {
  toolbar.wrap(#(7, 7), "*")
  |> should.equal([#(7, "*"), #(7, "*")])
}

pub fn line_start_of_first_line_is_zero_test() {
  toolbar.line_start("no newline here", 8)
  |> should.equal(0)
}

pub fn line_start_after_newline_test() {
  // "# one\n" is 6 graphemes; index 8 sits in "two".
  toolbar.line_start("# one\ntwo\n", 8)
  |> should.equal(6)
}

pub fn line_start_at_start_of_line_is_that_line_test() {
  // Index 6 is the first grapheme of the second line, not part of line one.
  toolbar.line_start("# one\ntwo\n", 6)
  |> should.equal(6)
}

pub fn line_start_counts_graphemes_not_code_units_test() {
  // The emoji is one grapheme, so "b" on line two sits at index 5.
  toolbar.line_start("🌊a\nb", 4)
  |> should.equal(3)
}

pub fn line_prefix_targets_line_of_selection_start_test() {
  // Selection spans lines two and three; only line two gets the prefix.
  toolbar.line_prefix("one\ntwo\nthree\n", #(5, 10), "- ")
  |> should.equal([#(4, "- ")])
}

pub fn heading_edits_prefix_current_line_test() {
  toolbar.edits(toolbar.H2, "one\ntwo", #(5, 5))
  |> should.equal([#(4, "## ")])
}

pub fn bold_edits_wrap_selection_test() {
  toolbar.edits(toolbar.Bold, "meet the deadline", #(9, 17))
  |> should.equal([#(17, "**"), #(9, "**")])
}
