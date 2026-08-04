import watershed_lustre/grapheme_diff.{Delete, Insert, NoChange, Replace}

// ── Degenerate cases ─────────────────────────────────────────────────────────

pub fn identical_strings_are_no_change_test() {
  assert grapheme_diff.diff(old: "", new: "") == NoChange
  assert grapheme_diff.diff(old: "hello", new: "hello") == NoChange
}

pub fn empty_to_text_is_an_insert_at_zero_test() {
  assert grapheme_diff.diff(old: "", new: "hello")
    == Insert(index: 0, value: "hello")
}

pub fn text_to_empty_is_a_full_delete_test() {
  assert grapheme_diff.diff(old: "hello", new: "") == Delete(start: 0, end: 5)
}

// ── Single-keystroke edits ───────────────────────────────────────────────────

pub fn typing_at_the_end_is_an_insert_test() {
  assert grapheme_diff.diff(old: "hell", new: "hello")
    == Insert(index: 4, value: "o")
}

pub fn typing_at_the_start_is_an_insert_test() {
  assert grapheme_diff.diff(old: "ello", new: "hello")
    == Insert(index: 0, value: "h")
}

pub fn typing_mid_document_is_an_insert_test() {
  assert grapheme_diff.diff(old: "helo", new: "hello")
    == Insert(index: 3, value: "l")
}

pub fn backspace_is_a_one_grapheme_delete_test() {
  assert grapheme_diff.diff(old: "hello", new: "hell")
    == Delete(start: 4, end: 5)
}

pub fn deleting_the_first_grapheme_test() {
  assert grapheme_diff.diff(old: "ab", new: "b") == Delete(start: 0, end: 1)
}

pub fn typing_over_a_selection_is_a_replace_test() {
  assert grapheme_diff.diff(old: "hello world", new: "hello there")
    == Replace(start: 6, end: 11, value: "there")
}

pub fn pasting_a_run_is_one_insert_test() {
  assert grapheme_diff.diff(old: "ab", new: "a-------b")
    == Insert(index: 1, value: "-------")
}

// ── Prefix/suffix overlap ────────────────────────────────────────────────────
//
// Repeated graphemes make the prefix and suffix scans want to claim the same
// characters. The suffix is clamped to what the prefix left behind, so the edit
// stays minimal and its indices stay in bounds.

pub fn repeated_graphemes_do_not_double_count_test() {
  assert grapheme_diff.diff(old: "aa", new: "aaa")
    == Insert(index: 2, value: "a")
  assert grapheme_diff.diff(old: "aaa", new: "aa") == Delete(start: 2, end: 3)
}

pub fn whole_old_string_is_a_prefix_of_the_new_one_test() {
  assert grapheme_diff.diff(old: "ab", new: "abab")
    == Insert(index: 2, value: "ab")
}

pub fn whole_old_string_is_a_suffix_of_the_new_one_test() {
  assert grapheme_diff.diff(old: "b", new: "ab") == Insert(index: 0, value: "a")
}

// ── Unicode: the reason this is grapheme-based ───────────────────────────────
//
// Every index below would be wrong by one or more if the diff counted UTF-16
// code units instead of extended grapheme clusters.

pub fn an_emoji_is_one_grapheme_test() {
  assert grapheme_diff.diff(old: "a🌊b", new: "ab") == Delete(start: 1, end: 2)
  assert grapheme_diff.diff(old: "ab", new: "a🌊b")
    == Insert(index: 1, value: "🌊")
}

pub fn typing_after_an_emoji_indexes_past_one_grapheme_test() {
  assert grapheme_diff.diff(old: "🌊", new: "🌊!") == Insert(index: 1, value: "!")
}

pub fn a_combining_mark_joins_its_base_grapheme_test() {
  // "e" + COMBINING ACUTE ACCENT is one cluster: deleting it is one op.
  assert grapheme_diff.diff(old: "ae\u{0301}b", new: "ab")
    == Delete(start: 1, end: 2)
}

pub fn adding_a_combining_mark_replaces_its_base_test() {
  // The cluster changes as a whole — "e" becomes "é" — so the minimal edit is a
  // replace of that one grapheme, not an insert between code units.
  assert grapheme_diff.diff(old: "aeb", new: "ae\u{0301}b")
    == Replace(start: 1, end: 2, value: "e\u{0301}")
}

pub fn a_zwj_sequence_is_one_grapheme_test() {
  // Family emoji: multiple codepoints joined by ZWJ, one cluster.
  let family = "👩\u{200D}👩\u{200D}👧"
  assert grapheme_diff.diff(old: "a" <> family <> "b", new: "ab")
    == Delete(start: 1, end: 2)
}
