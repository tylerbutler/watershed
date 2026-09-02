//// Line-based marker extractor for Gleam source files.
////
//// Scans source text for `// docs:snippet-start <id>` and
//// `// docs:snippet-end <id>` directives. Returns the dedented content
//// between the markers, with directive lines excluded.

import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string

/// A successfully extracted marker range.
pub type MarkerRange {
  MarkerRange(name: String, code: String)
}

/// A marker extraction error.
pub type MarkerError {
  /// No start directive found for the marker.
  MissingStart(path: String, marker: String)
  /// No end directive found for the marker.
  MissingEnd(path: String, marker: String)
  /// More than one start directive found for the marker.
  DuplicateStart(path: String, marker: String)
  /// More than one end directive found for the marker.
  DuplicateEnd(path: String, marker: String)
  /// End directive appears before start directive.
  Reversed(path: String, marker: String)
  /// Another marker opens inside this range.
  Nested(path: String, outer: String, inner: String)
  /// A different marker ends inside this range.
  MismatchedEnd(path: String, outer: String, inner: String)
  /// No non-blank lines between start and end.
  Empty(path: String, marker: String)
}

const start_prefix = "// docs:snippet-start "

const end_prefix = "// docs:snippet-end "

type Directive {
  Start(name: String)
  End(name: String)
}

fn parse_directive(line: String) -> option.Option(Directive) {
  let trimmed = string.trim_start(line)
  case string.starts_with(trimmed, start_prefix) {
    True -> {
      let name =
        trimmed
        |> string.drop_start(string.length(start_prefix))
        |> string.trim
      Some(Start(name))
    }
    False ->
      case string.starts_with(trimmed, end_prefix) {
        True -> {
          let name =
            trimmed
            |> string.drop_start(string.length(end_prefix))
            |> string.trim
          Some(End(name))
        }
        False -> None
      }
  }
}

/// Returns the names of all start markers found in the source.
pub fn marker_names(source: String) -> List(String) {
  source
  |> string.split("\n")
  |> list.filter_map(fn(line) {
    case parse_directive(line) {
      Some(Start(name)) -> Ok(name)
      _ -> Error(Nil)
    }
  })
}

/// Returns the source without its marker directive lines.
///
/// A directive line is punctuation for this tool, not code. A whole-file
/// snippet must not show one to the reader. The Gleam formatter puts a blank
/// line on each side of a directive line that stands between two items.
/// Removal of that directive line alone leaves two blank lines, so this
/// function also removes one of the two. All other bytes stay the same,
/// including the last newline of the file.
pub fn without_directives(source: String) -> String {
  source
  |> string.split("\n")
  |> drop_directives(False, [])
  |> string.join("\n")
}

fn drop_directives(
  lines: List(String),
  previous_is_blank: Bool,
  acc: List(String),
) -> List(String) {
  case lines {
    [] -> list.reverse(acc)
    [line, ..rest] ->
      case parse_directive(line) {
        Some(_) -> {
          let rest = case previous_is_blank {
            True -> drop_one_blank(rest)
            False -> rest
          }
          drop_directives(rest, previous_is_blank, acc)
        }
        None -> drop_directives(rest, is_blank(line), [line, ..acc])
      }
  }
}

fn drop_one_blank(lines: List(String)) -> List(String) {
  case lines {
    [line, ..rest] ->
      case is_blank(line) {
        True -> rest
        False -> lines
      }
    [] -> lines
  }
}

fn is_blank(line: String) -> Bool {
  string.trim(line) == ""
}

/// Extracts the named marker range from source.
///
/// Returns `Ok(MarkerRange)` when the marker pair is found and valid.
/// Returns `Error(MarkerError)` for structural problems such as missing,
/// duplicate, reversed, nested, or empty ranges.
pub fn extract(
  source: String,
  source_path: String,
  marker: String,
) -> Result(MarkerRange, MarkerError) {
  let lines = string.split(source, "\n")
  let indexed = list.index_map(lines, fn(line, idx) { #(idx, line) })

  let start_positions =
    list.filter_map(indexed, fn(pair) {
      let #(idx, line) = pair
      case parse_directive(line) {
        Some(Start(name)) if name == marker -> Ok(idx)
        _ -> Error(Nil)
      }
    })

  let end_positions =
    list.filter_map(indexed, fn(pair) {
      let #(idx, line) = pair
      case parse_directive(line) {
        Some(End(name)) if name == marker -> Ok(idx)
        _ -> Error(Nil)
      }
    })

  case start_positions, end_positions {
    [], _ -> Error(MissingStart(source_path, marker))
    [_, _, ..], _ -> Error(DuplicateStart(source_path, marker))
    [_], [] -> Error(MissingEnd(source_path, marker))
    [_], [_, _, ..] -> Error(DuplicateEnd(source_path, marker))
    [start_idx], [end_idx] ->
      case end_idx < start_idx {
        True -> Error(Reversed(source_path, marker))
        False -> {
          let content_lines =
            list.filter_map(indexed, fn(pair) {
              let #(idx, line) = pair
              case idx > start_idx && idx < end_idx {
                True -> Ok(line)
                False -> Error(Nil)
              }
            })
          check_and_build(content_lines, source_path, marker)
        }
      }
  }
}

fn check_and_build(
  lines: List(String),
  path: String,
  marker: String,
) -> Result(MarkerRange, MarkerError) {
  case check_range(lines, path, marker) {
    Error(e) -> Error(e)
    Ok(Nil) -> {
      let trimmed = list.map(lines, string.trim_end)
      // Drop trailing blank lines while preserving internal blank lines.
      let stripped =
        trimmed
        |> list.reverse
        |> list.drop_while(fn(l) { l == "" })
        |> list.reverse
      let non_blank = list.filter(stripped, fn(l) { l != "" })
      case non_blank {
        [] -> Error(Empty(path, marker))
        _ -> Ok(MarkerRange(name: marker, code: dedent(stripped)))
      }
    }
  }
}

fn check_range(
  lines: List(String),
  path: String,
  outer: String,
) -> Result(Nil, MarkerError) {
  list.fold_until(lines, Ok(Nil), fn(acc, line) {
    case parse_directive(line) {
      Some(Start(inner)) -> list.Stop(Error(Nested(path, outer, inner)))
      Some(End(inner)) -> list.Stop(Error(MismatchedEnd(path, outer, inner)))
      _ -> list.Continue(acc)
    }
  })
}

fn count_leading_spaces(s: String) -> Int {
  do_count_leading_spaces(string.to_graphemes(s), 0)
}

fn do_count_leading_spaces(chars: List(String), count: Int) -> Int {
  case chars {
    [" ", ..rest] -> do_count_leading_spaces(rest, count + 1)
    _ -> count
  }
}

fn dedent(lines: List(String)) -> String {
  let non_blank = list.filter(lines, fn(l) { l != "" })
  let indent = case non_blank {
    [] -> 0
    _ -> {
      let indents = list.map(non_blank, count_leading_spaces)
      case indents {
        [] -> 0
        [first, ..rest] -> list.fold(rest, first, int.min)
      }
    }
  }
  let dedented =
    list.map(lines, fn(line) {
      case indent > 0 && string.length(line) >= indent {
        True -> string.drop_start(line, indent)
        False -> line
      }
    })
  string.join(dedented, "\n")
}
