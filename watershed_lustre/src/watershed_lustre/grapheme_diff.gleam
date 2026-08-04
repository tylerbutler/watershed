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
//// `watershed_js.text_insert` / `text_delete_range` / `text_replace_range`
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
