//// The markdown toolbar as pure selection surgery.
////
//// Markdown formatting is characters in the document, so every action is a
//// list of plain inserts against the current text and selection — no channel
//// in sight, which is what makes these testable with no harness. The app
//// applies each `#(index, text)` with `text_insert`, in order.
////
//// Indices are grapheme indices throughout: `textarea.selection` hands out a
//// half-open grapheme range, which is exactly the unit `text_insert` takes,
//// so no offset conversion exists anywhere in this app.
////
//// Buttons apply formatting; they do not toggle it. Pressing bold on
//// already-bold text nests delimiters, same as typing them.

import gleam/list
import gleam/string

pub type Action {
  Bold
  Italic
  Code
  H1
  H2
  Bullet
}

/// The insert operations for one action, in application order. Inline wraps
/// emit the end insert first so the start index stays valid; a collapsed caret
/// gets the delimiters inserted around it.
pub fn edits(
  action: Action,
  text: String,
  selection: #(Int, Int),
) -> List(#(Int, String)) {
  case action {
    Bold -> wrap(selection, "**")
    Italic -> wrap(selection, "*")
    Code -> wrap(selection, "`")
    H1 -> line_prefix(text, selection, "# ")
    H2 -> line_prefix(text, selection, "## ")
    Bullet -> line_prefix(text, selection, "- ")
  }
}

/// Wrap the selection in `delimiter`: one insert at the end index, one at the
/// start index — end first, so the start index stays valid.
pub fn wrap(selection: #(Int, Int), delimiter: String) -> List(#(Int, String)) {
  let #(start, end) = selection
  [#(end, delimiter), #(start, delimiter)]
}

/// Prefix the line containing the selection start.
pub fn line_prefix(
  text: String,
  selection: #(Int, Int),
  prefix: String,
) -> List(#(Int, String)) {
  let #(start, _end) = selection
  [#(line_start(text, start), prefix)]
}

/// The grapheme index of the start of the line containing `index`: one past
/// the last newline before it, or zero.
pub fn line_start(text: String, index: Int) -> Int {
  string.to_graphemes(text)
  |> list.take(index)
  |> list.index_fold(0, fn(start, grapheme, position) {
    case grapheme {
      "\n" -> position + 1
      _ -> start
    }
  })
}

pub fn label(action: Action) -> String {
  case action {
    Bold -> "Bold"
    Italic -> "Italic"
    Code -> "Code"
    H1 -> "H1"
    H2 -> "H2"
    Bullet -> "List"
  }
}

/// The keyboard chord, for the button's tooltip. Empty where there is none —
/// inventing a shortcut the app does not listen for is worse than silence.
pub fn shortcut(action: Action) -> String {
  case action {
    Bold -> "Ctrl/Cmd+B"
    Italic -> "Ctrl/Cmd+I"
    Code -> "Ctrl/Cmd+E"
    H1 | H2 | Bullet -> ""
  }
}

pub fn describe(action: Action) -> String {
  case action {
    Bold -> "bold"
    Italic -> "italic"
    Code -> "inline code"
    H1 -> "heading 1"
    H2 -> "heading 2"
    Bullet -> "bullet line"
  }
}

pub fn all() -> List(Action) {
  [Bold, Italic, Code, H1, H2, Bullet]
}
