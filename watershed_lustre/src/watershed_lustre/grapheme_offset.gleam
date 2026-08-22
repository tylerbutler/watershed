//// Convert between the UTF-16 code-unit offsets of the browser and the
//// grapheme indices of the CRDT.
////
//// A `<textarea>` reports `selectionStart` and `selectionEnd` as counts of
//// UTF-16 code units. `SharedText` addresses every edit by extended grapheme
//// cluster. The two counts agree only for text that contains BMP scalars and
//// no combining marks. The first emoji, accent, or flag ends that agreement.
//// If you read a caret position on one side and use it on the other side, the
//// bridge puts an op at the wrong position. This is the most frequent error in
//// a collaborative text bridge.
////
//// Both directions clamp, and neither one fails. An offset after the end gives
//// the end. A negative offset gives zero. An offset inside a cluster, for
//// example between the two surrogate halves of an emoji, moves back to the
//// start of that cluster. A caret one grapheme too early is better than an
//// index that the CRDT cannot name.

import gleam/list
import gleam/string

import watershed/rich_text/utf16

/// The UTF-16 offset of the grapheme at `index`. This is where the browser
/// must put a caret that the CRDT calls `index`.
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

/// The grapheme index that contains the UTF-16 `offset`. This is the name that
/// the CRDT must use for a caret that the browser reported at `offset`.
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
