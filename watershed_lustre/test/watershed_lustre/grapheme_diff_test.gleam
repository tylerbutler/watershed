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

// ── Shifting an edit onto a moved target ─────────────────────────────────────
//
// An IME session is diffed against the text as it stood when composition
// opened, but commits against the text as it stands now. `shift` carries the
// edit across that gap by however far a peer moved the site.

pub fn shifting_by_zero_changes_nothing_test() {
  assert grapheme_diff.shift(Insert(index: 3, value: "拼"), by: 0)
    == Insert(index: 3, value: "拼")
  assert grapheme_diff.shift(Delete(start: 1, end: 4), by: 0)
    == Delete(start: 1, end: 4)
}

pub fn nothing_shifts_to_nothing_test() {
  assert grapheme_diff.shift(NoChange, by: 7) == NoChange
  assert grapheme_diff.shift(NoChange, by: -7) == NoChange
}

pub fn a_remote_insert_before_the_site_pushes_the_edit_later_test() {
  assert grapheme_diff.shift(Insert(index: 3, value: "拼音"), by: 5)
    == Insert(index: 8, value: "拼音")
  assert grapheme_diff.shift(Delete(start: 3, end: 6), by: 5)
    == Delete(start: 8, end: 11)
  assert grapheme_diff.shift(Replace(start: 3, end: 6, value: "音"), by: 5)
    == Replace(start: 8, end: 11, value: "音")
}

pub fn a_remote_delete_before_the_site_pulls_the_edit_earlier_test() {
  assert grapheme_diff.shift(Insert(index: 9, value: "x"), by: -4)
    == Insert(index: 5, value: "x")
  assert grapheme_diff.shift(Replace(start: 9, end: 12, value: "x"), by: -4)
    == Replace(start: 5, end: 8, value: "x")
}

pub fn the_inserted_text_is_never_touched_test() {
  // Only addresses move. A shift that would reach past the end stays out of
  // range on purpose: the runtime rejects it and the banner says so, which is
  // more honest than silently landing the composition somewhere else.
  assert grapheme_diff.shift(Insert(index: 2, value: "🌊é"), by: 900)
    == Insert(index: 902, value: "🌊é")
}

pub fn a_shift_past_the_start_clamps_to_zero_test() {
  // A peer deleted more before the site than the site was offset by. Index 0 is
  // a position that exists; a negative one is not.
  assert grapheme_diff.shift(Insert(index: 2, value: "x"), by: -9)
    == Insert(index: 0, value: "x")
}

pub fn clamping_preserves_range_order_test() {
  // Both ends move by the same amount, so `start <= end` survives the clamp
  // even when only one end would have gone negative.
  assert grapheme_diff.shift(Delete(start: 1, end: 3), by: -2)
    == Delete(start: 0, end: 1)
  assert grapheme_diff.shift(Replace(start: 1, end: 3, value: "y"), by: -5)
    == Replace(start: 0, end: 0, value: "y")
}
