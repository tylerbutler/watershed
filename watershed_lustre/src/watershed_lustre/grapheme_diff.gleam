//// A minimal grapheme-level diff between two strings.
////
//// The `input` event of a `<textarea>` gives you the whole new value only. If
//// you write that value back to a CRDT as one replace-the-document op, the
//// result is correct for one client. Under collaboration it is very bad. It
//// overwrites every concurrent remote edit, and it makes the sequence do the
//// maximum amount of work for a one-keystroke change. It also makes you want
//// to address the CRDT by the UTF-16 code-unit offsets of the browser, such as
//// `selectionStart`. Those offsets are *not* grapheme indices. An emoji or a
//// combining mark makes the two disagree, and the op then applies at the wrong
//// position.
////
//// This module derives the one minimal edit that a keystroke implies, from the
//// two strings only. The unit is the Unicode extended grapheme cluster, from
//// `string.to_graphemes` of Gleam. The unit is never a code unit. The module
//// finds the longest common grapheme prefix and the longest common grapheme
//// suffix. The graphemes between them on each side are the removed range and
//// the inserted text:
////
//// - an insertion only → `Insert(index, value)`
//// - a removal only    → `Delete(start, end)`
//// - both              → `Replace(start, end, value)`
//// - no difference     → `NoChange`
////
//// Every index is a grapheme index into the *old* string, which is what
//// `watershed.text_insert`, `text_delete_range`, and `text_replace_range`
//// need. The result is deterministic. It is never a whole-document replace
//// when a smaller op is possible.

import gleam/list
import gleam/string

/// The one minimal edit that changes one string into another, in grapheme
/// indices into the *old* string.
pub type Edit {
  /// The two strings are the same. Emit no CRDT op.
  NoChange
  /// Insert `value` at the grapheme `index`, in the range `0..old_length`.
  Insert(index: Int, value: String)
  /// Delete the graphemes in `[start, end)`.
  Delete(start: Int, end: Int)
  /// Replace the graphemes in `[start, end)` with `value`.
  Replace(start: Int, end: Int, value: String)
}

/// Derive the minimal `Edit` value from `old` to `new`. The function segments
/// both strings into extended grapheme clusters. It is pure and total. It uses
/// no CRDT and no browser offset.
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

/// Re-address an edit, so that it applies to text that moved below it. Every
/// index moves by `by`, and the inserted content does not change.
///
/// An input method editor (IME) composition needs this function. The component
/// recovers the edit of a composition against the value that the element held
/// when the session opened. The edit thus arrives in the coordinates of a
/// string that can be several remote keystrokes out of date. A `TextAnchor` on
/// the composition site gives the distance that the site moved, and this
/// function moves the edit by that distance.
///
/// One distance describes the move only while the composed-over region stayed
/// complete. The component thus prefers [`replacement`](#replacement) and
/// [`splice`](#splice), because a resolved span says where *both* ends moved.
/// The component uses this function only when it cannot read the session as one
/// region that changed.
///
/// An index clamps at zero. A peer can delete more text before the site than
/// the offset of the site, and index 0 is a position that exists, where a
/// negative index is not. The two ends of a range move together, so
/// `start <= end` stays true. Nothing clamps at the upper end. An index after
/// the end of the text is a rejection that the runtime must report. It is not a
/// rejection to move quietly.
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

/// Recover the text that replaced a known region of `old`.
///
/// [`diff`](#diff) *infers* the extent of an edit from two strings, which is
/// all that a keystroke gives you. An IME session gives more. It knows the
/// region that it opened over, which is the selection that the user composes
/// across. The extent is thus known, and only the content is in question.
///
/// That difference is important. Inference cannot separate "the user replaced
/// these five graphemes" from "the user replaced the three of them that
/// changed". Only the first statement can be re-addressed against a document
/// that a peer edited in the same interval.
///
/// `region` is a half-open grapheme range into `old`. The result is the
/// graphemes of `new` that are now between the same surrounding text.
///
/// The result is `Error(Nil)` when `new` is not `old` with that region
/// replaced. That occurs when the region is out of bounds or inverted, when
/// `new` is too short to hold the surrounding text, or when the text outside
/// the region moved. This function cannot answer those conditions. The caller
/// must then infer the edit with `diff`.
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
/// with the most specific constructor that gives the same result.
///
/// This function is the counterpart of [`replacement`](#replacement). After a
/// caller knows the region and its new content, the op needs no inference. A
/// caller that has two strings only must use [`diff`](#diff) instead. This
/// function emits an op that is wider than the change when you ask it to. That
/// result is correct when the *user* selected that extent, and incorrect when a
/// diff only failed to make the extent smaller.
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
