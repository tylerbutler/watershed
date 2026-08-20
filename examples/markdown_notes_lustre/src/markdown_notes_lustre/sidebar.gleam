//// Pure render rules for the sidebar: tag pairs and (from MN8) the
//// order-reconciling display rule. No channel in sight, so every rule gets a
//// plain test.
////
//// Tags are one document-wide OR-set of `"<note>\t<tag>"` pairs — one
//// channel, no per-note handle plumbing. Note names and tags therefore must
//// not contain a tab, enforced at input. Deleting a note leaves its pairs
//// behind as harmless orphans; these renderers only show pairs whose note
//// exists.

import gleam/list
import gleam/string

/// The wire encoding of one tagging: `"<note>\t<tag>"`.
pub fn pair(note: String, tag: String) -> String {
  note <> "\t" <> tag
}

/// The tags on one note, sorted.
pub fn tags_of(pairs: List(String), note: String) -> List(String) {
  pairs
  |> list.filter_map(fn(entry) {
    case string.split_once(entry, "\t") {
      Ok(#(n, tag)) if n == note -> Ok(tag)
      _ -> Error(Nil)
    }
  })
  |> list.sort(string.compare)
}

/// The notes carrying a tag.
pub fn notes_with_tag(pairs: List(String), tag: String) -> List(String) {
  pairs
  |> list.filter_map(fn(entry) {
    case string.split_once(entry, "\t") {
      Ok(#(note, t)) if t == tag -> Ok(note)
      _ -> Error(Nil)
    }
  })
}

/// Every tag in use by a note that exists, sorted and deduplicated — orphaned
/// pairs from deleted notes are not shown.
pub fn all_tags(pairs: List(String), notes: List(String)) -> List(String) {
  pairs
  |> list.filter_map(fn(entry) {
    case string.split_once(entry, "\t") {
      Ok(#(note, tag)) ->
        case list.contains(notes, note) {
          True -> Ok(tag)
          False -> Error(Nil)
        }
      _ -> Error(Nil)
    }
  })
  |> list.unique
  |> list.sort(string.compare)
}
