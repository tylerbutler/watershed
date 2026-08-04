//// Convert between the browser's UTF-16 code-unit offsets and the CRDT's
//// grapheme indices.
////
//// A `<textarea>` reports `selectionStart`/`selectionEnd` as counts of UTF-16
//// code units; `SharedText` addresses every edit by extended grapheme cluster.
//// The two agree only for text that is entirely BMP scalars with no combining
//// marks — that is, until the first emoji, accent, or flag. Reading a caret
//// position on one side and using it on the other is the single most common way
//// a collaborative text bridge lands an op in the wrong place.
////
//// Both directions clamp rather than fail: an offset past the end resolves to
//// the end, a negative one to zero. An offset that lands *inside* a cluster —
//// between the surrogate halves of an emoji, say — snaps backwards to that
//// cluster's start, because a caret is better placed one grapheme early than at
//// an index the CRDT cannot name.

import gleam/list
import gleam/string

import watershed/rich_text/utf16

/// The UTF-16 offset of grapheme `index` — where the browser should put a caret
/// that the CRDT calls `index`.
pub fn to_utf16(text: String, index: Int) -> Int {
  case index <= 0 {
    True -> 0
    False ->
      text
      |> string.to_graphemes
      |> list.take(index)
      |> string.join("")
      |> utf16.length
  }
}

/// The grapheme index containing UTF-16 `offset` — what the CRDT should call a
/// caret the browser reported at `offset`.
pub fn from_utf16(text: String, offset: Int) -> Int {
  case offset <= 0 {
    True -> 0
    False -> walk(string.to_graphemes(text), offset, 0, 0)
  }
}

fn walk(
  graphemes: List(String),
  offset: Int,
  consumed: Int,
  index: Int,
) -> Int {
  case graphemes {
    [] -> index
    [grapheme, ..rest] -> {
      let next = consumed + utf16.length(grapheme)
      // Only advance past a cluster the offset fully covers; a partial cluster
      // leaves the index where it is, which is the backwards snap.
      case next <= offset {
        True -> walk(rest, offset, next, index + 1)
        False -> index
      }
    }
  }
}
