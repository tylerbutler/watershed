//// Minimal grapheme-level diff between two strings.
////
//// A `<textarea>`'s `input` event only ever hands you the *whole* new value.
//// Writing that straight back to a CRDT as one giant replace-the-document op is
//// correct in isolation but catastrophic under collaboration: it clobbers every
//// concurrent remote edit and makes the sequence do maximum work for a
//// single-keystroke change. It also tempts you to address the CRDT by the
//// browser's UTF-16 code-unit offsets (`selectionStart`), which are *not*
//// grapheme indices — an emoji or a combining mark and the two disagree, so the
//// op lands in the wrong place.
////
//// This module derives the one minimal edit a keystroke implies, entirely from
//// the before/after strings, using Gleam's `string.to_graphemes` (Unicode
//// extended grapheme clusters) as the unit — never code units. It finds the
//// longest common grapheme prefix and suffix, and the graphemes between them on
//// each side are the removed range and the inserted text:
////
//// - only insertion  → `Insert(index, value)`
//// - only removal     → `Delete(start, end)`
//// - both             → `Replace(start, end, value)`
//// - identical        → `NoChange`
////
//// All indices are grapheme indices into the *old* string, exactly what
//// `watershed.text_insert` / `text_delete_range` / `text_replace_range`
//// expect. The result is deterministic and never a whole-document replace when a
//// narrower op exists.

import gleam/list
import gleam/string

/// The single minimal edit that turns one string into another, expressed in
/// grapheme indices into the *old* string.
pub type Edit {
  /// The strings are identical: emit no CRDT op.
  NoChange
  /// Insert `value` at grapheme `index` (`0..old_length`).
  Insert(index: Int, value: String)
  /// Delete the graphemes in `[start, end)`.
  Delete(start: Int, end: Int)
  /// Replace the graphemes in `[start, end)` with `value`.
  Replace(start: Int, end: Int, value: String)
}

/// Derive the minimal `Edit` from `old` to `new`, both segmented into extended
/// grapheme clusters. Pure and total — no CRDT, no browser offsets involved.
pub fn diff(old old: String, new new: String) -> Edit {
  case old == new {
    True -> NoChange
    False -> {
      let old_graphemes = string.to_graphemes(old)
      let new_graphemes = string.to_graphemes(new)
      let old_len = list.length(old_graphemes)
      let new_len = list.length(new_graphemes)

      // Longest common grapheme prefix.
      let prefix = common_prefix_length(old_graphemes, new_graphemes, 0)

      // Longest common grapheme suffix, computed on the reversed remainders so
      // it never overlaps the prefix already consumed on either side.
      let max_suffix = int_min(old_len - prefix, new_len - prefix)
      let suffix =
        common_prefix_length(
          list.reverse(old_graphemes),
          list.reverse(new_graphemes),
          0,
        )
        |> int_min(max_suffix)

      let removed_start = prefix
      let removed_end = old_len - suffix
      let inserted =
        new_graphemes
        |> list.drop(prefix)
        |> list.take(new_len - suffix - prefix)
        |> string.join("")

      case removed_start == removed_end, inserted {
        // Nothing removed, nothing inserted: identical (shouldn't happen given
        // the outer guard, but total is total).
        True, "" -> NoChange
        // Pure insertion at the divergence point.
        True, value -> Insert(index: removed_start, value: value)
        // Pure deletion.
        False, "" -> Delete(start: removed_start, end: removed_end)
        // Substitution of one span for another.
        False, value ->
          Replace(start: removed_start, end: removed_end, value: value)
      }
    }
  }
}

/// Re-address an edit so it applies to text that has moved under it: every
/// index shifts by `by`, and the inserted content is untouched.
///
/// An IME composition is what needs this. Its edit is recovered against the
/// value the element held when the session opened, so it arrives in the
/// coordinates of a string that may be several remote keystrokes out of date;
/// a `TextAnchor` on the composition site gives the distance it travelled and
/// this carries the edit that far. One distance describes the move only while
/// the composed-over region stayed intact, which is why the component prefers
/// [`replacement`](#replacement) and [`splice`](#splice) — a resolved span says
/// where *both* ends went — and falls back here when the session cannot be read
/// as one region changing.
///
/// Indices clamp at zero — a peer can delete more before the site than the site
/// was offset by, and index 0 is a position that exists where a negative one is
/// not. Both ends of a range move together, so `start <= end` survives. Nothing
/// clamps at the upper end: an index past the end of the text is a rejection the
/// runtime should report, not one to quietly relocate.
pub fn shift(edit: Edit, by amount: Int) -> Edit {
  case edit {
    NoChange -> NoChange
    Insert(index:, value:) -> Insert(index: nudge(index, amount), value:)
    Delete(start:, end:) ->
      Delete(start: nudge(start, amount), end: nudge(end, amount))
    Replace(start:, end:, value:) ->
      Replace(start: nudge(start, amount), end: nudge(end, amount), value:)
  }
}

/// Recover the text that took the place of a known region of `old`.
///
/// [`diff`](#diff) *infers* an edit's extent from two strings, which is all a
/// keystroke gives you. An IME session has more than that: it knows the region
/// it opened over — the selection the user is composing across — so the extent
/// is not in question and only its content is. That distinction matters,
/// because inference cannot tell "the user replaced these five graphemes" from
/// "the user replaced the three of them that changed", and only the first is
/// a claim that can be re-addressed against a document a peer has edited
/// meanwhile.
///
/// `region` is a half-open grapheme range into `old`. The answer is the
/// graphemes of `new` that now sit between the same surroundings.
///
/// `Error(Nil)` when `new` is not `old` with that region swapped out — the
/// region is out of bounds or inverted, `new` is too short to hold the
/// surroundings, or the text outside the region moved. Nothing here can honour
/// those cases; the caller should fall back to inferring the edit with `diff`.
pub fn replacement(
  old old: String,
  new new: String,
  region region: #(Int, Int),
) -> Result(String, Nil) {
  let #(start, end) = region
  let old_graphemes = string.to_graphemes(old)
  let new_graphemes = string.to_graphemes(new)
  let old_length = list.length(old_graphemes)
  let new_length = list.length(new_graphemes)
  // How much of `old` follows the region — the part `new` has to still end with.
  let tail = old_length - end

  case start < 0 || end < start || tail < 0 || new_length - tail < start {
    True -> Error(Nil)
    False ->
      case
        list.take(old_graphemes, start) == list.take(new_graphemes, start),
        list.drop(old_graphemes, end)
        == list.drop(new_graphemes, { new_length - tail })
      {
        True, True ->
          Ok(
            new_graphemes
            |> list.drop(start)
            |> list.take(new_length - tail - start)
            |> string.join(""),
          )
        _, _ -> Error(Nil)
      }
  }
}

/// The edit that puts `value` in place of the graphemes in `[start, end)`,
/// named by the narrowest constructor that says the same thing.
///
/// The counterpart to [`replacement`](#replacement): once a caller knows the
/// region and its new content, the op needs no inferring at all. Callers with
/// only two strings want [`diff`](#diff) instead — this will happily emit a
/// wider op than the change requires, which is right when the *user* chose that
/// extent and wrong when a diff merely failed to narrow it.
pub fn splice(start start: Int, end end: Int, value value: String) -> Edit {
  case start >= end, value {
    True, "" -> NoChange
    True, _ -> Insert(index: start, value:)
    False, "" -> Delete(start:, end:)
    False, _ -> Replace(start:, end:, value:)
  }
}

fn nudge(index: Int, amount: Int) -> Int {
  case index + amount < 0 {
    True -> 0
    False -> index + amount
  }
}

fn common_prefix_length(a: List(String), b: List(String), acc: Int) -> Int {
  case a, b {
    [x, ..xs], [y, ..ys] if x == y -> common_prefix_length(xs, ys, acc + 1)
    _, _ -> acc
  }
}

fn int_min(a: Int, b: Int) -> Int {
  case a < b {
    True -> a
    False -> b
  }
}
