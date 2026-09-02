//// Versioned JSON configuration decoder for source-snippet generation.
////
//// Decodes and validates the version-1 schema from a JSON string.
//// Returns descriptive errors for malformed, missing, or invalid fields.

import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option
import gleam/set
import gleam/string

/// A decoded and validated snippet configuration.
pub type Config {
  Config(
    version: Int,
    source_root: String,
    marker_roots: List(String),
    extensions: List(String),
    snippets: List(SnippetSpec),
  )
}

/// A single output snippet specification.
pub type SnippetSpec {
  SnippetSpec(
    id: String,
    source_path: String,
    language: String,
    selection: Selection,
  )
}

/// How a snippet selects code from its source file.
///
/// A snippet selects marker ranges or the whole file. It cannot do both,
/// and it cannot do neither.
pub type Selection {
  /// The named marker ranges, in order, joined by the separator.
  MarkerSelection(markers: List(String), separator: String)
  /// The complete file, without its marker directive lines.
  WholeFileSelection
}

/// Configuration decode and validation errors.
pub type ConfigError {
  /// JSON syntax error.
  JsonSyntax(message: String)
  /// A required field is missing or has wrong type.
  FieldError(field: String, message: String)
  /// Unsupported configuration version.
  UnsupportedVersion(version: Int)
  /// A snippet id is empty.
  EmptyId(index: Int)
  /// Duplicate snippet ids.
  DuplicateId(id: String)
  /// Empty source path in a snippet.
  EmptyPath(id: String)
  /// Empty language in a snippet.
  EmptyLanguage(id: String)
  /// Empty marker list in a snippet.
  EmptyMarkers(id: String)
  /// A snippet names neither `markers` nor `wholeFile`.
  MissingSelection(id: String)
  /// A snippet names both `markers` and `wholeFile`.
  ConflictingSelection(id: String)
  /// A snippet sets `wholeFile` to a value other than `true`.
  WholeFileNotTrue(id: String)
  /// A whole-file snippet declares a separator, which it cannot use.
  SeparatorWithWholeFile(id: String)
  /// Repeated marker within a single snippet.
  RepeatedMarker(id: String, marker: String)
  /// Empty marker root entry.
  EmptyRoot
  /// Unsupported file extension.
  UnsupportedExtension(extension: String)
  /// Empty source root.
  EmptySourceRoot
  /// Empty extensions list.
  EmptyExtensions
}

/// Decodes a JSON string into a validated `Config`.
pub fn decode_config(input: String) -> Result(Config, ConfigError) {
  case json.parse(input, raw_decoder()) {
    Ok(raw) -> validate(raw)
    Error(json.UnableToDecode(decode_errors)) ->
      Error(map_decode_errors(decode_errors))
    Error(_) -> Error(JsonSyntax("invalid JSON"))
  }
}

// ---------------------------------------------------------------------------
// Decode error mapping
// ---------------------------------------------------------------------------

/// Converts raw decode errors into a descriptive FieldError.
///
/// The field path uses dot-separated segments with array indices in brackets.
/// Examples: "version", "sourceRoot", "snippets[0].id".
fn map_decode_errors(errors: List(decode.DecodeError)) -> ConfigError {
  case errors {
    [first, ..] -> {
      let field = format_field_path(first.path)
      let message = case first.found {
        "Nothing" -> "missing required field"
        found -> "expected " <> first.expected <> ", got " <> found
      }
      FieldError(field, message)
    }
    [] -> JsonSyntax("invalid JSON")
  }
}

fn format_field_path(path: List(String)) -> String {
  case path {
    [] -> "<root>"
    segments -> format_path_segments(segments, "")
  }
}

fn format_path_segments(segments: List(String), acc: String) -> String {
  case segments {
    [] -> acc
    [segment, ..rest] -> {
      let part = case is_array_index(segment) {
        True -> "[" <> segment <> "]"
        False ->
          case acc {
            "" -> segment
            _ -> "." <> segment
          }
      }
      format_path_segments(rest, acc <> part)
    }
  }
}

fn is_array_index(s: String) -> Bool {
  case string.to_graphemes(s) {
    [] -> False
    graphemes -> list.all(graphemes, fn(g) { is_digit(g) })
  }
}

fn is_digit(g: String) -> Bool {
  case g {
    "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
    _ -> False
  }
}

// ---------------------------------------------------------------------------
// Internal raw decoding
// ---------------------------------------------------------------------------

type RawConfig {
  RawConfig(
    version: Int,
    source_root: String,
    marker_roots: List(String),
    extensions: List(String),
    snippets: List(RawSnippet),
  )
}

type RawSnippet {
  RawSnippet(
    id: String,
    source_path: String,
    language: String,
    markers: option.Option(List(String)),
    whole_file: option.Option(Bool),
    separator: option.Option(String),
  )
}

fn raw_decoder() -> decode.Decoder(RawConfig) {
  use version <- decode.field("version", decode.int)
  use source_root <- decode.field("sourceRoot", decode.string)
  use marker_roots <- decode.field("markerRoots", decode.list(decode.string))
  use extensions <- decode.field("extensions", decode.list(decode.string))
  use snippets <- decode.field("snippets", decode.list(raw_snippet_decoder()))
  decode.success(RawConfig(
    version:,
    source_root:,
    marker_roots:,
    extensions:,
    snippets:,
  ))
}

fn raw_snippet_decoder() -> decode.Decoder(RawSnippet) {
  use id <- decode.field("id", decode.string)
  use source_path <- decode.field("sourcePath", decode.string)
  use language <- decode.field("language", decode.string)
  use markers <- decode.optional_field(
    "markers",
    option.None,
    decode.optional(decode.list(decode.string)),
  )
  use whole_file <- decode.optional_field(
    "wholeFile",
    option.None,
    decode.optional(decode.bool),
  )
  use separator <- decode.optional_field(
    "separator",
    option.None,
    decode.optional(decode.string),
  )
  decode.success(RawSnippet(
    id:,
    source_path:,
    language:,
    markers:,
    whole_file:,
    separator:,
  ))
}

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

fn validate(raw: RawConfig) -> Result(Config, ConfigError) {
  use _ <- result_try(validate_version(raw.version))
  use _ <- result_try(validate_source_root(raw.source_root))
  use _ <- result_try(validate_roots(raw.marker_roots))
  use _ <- result_try(validate_extensions(raw.extensions))
  use snippets <- result_try(validate_snippets(raw.snippets))
  Ok(Config(
    version: raw.version,
    source_root: raw.source_root,
    marker_roots: raw.marker_roots,
    extensions: raw.extensions,
    snippets:,
  ))
}

fn result_try(
  result: Result(a, e),
  next: fn(a) -> Result(b, e),
) -> Result(b, e) {
  case result {
    Ok(value) -> next(value)
    Error(err) -> Error(err)
  }
}

fn validate_version(version: Int) -> Result(Nil, ConfigError) {
  case version {
    1 -> Ok(Nil)
    other -> Error(UnsupportedVersion(other))
  }
}

fn validate_source_root(root: String) -> Result(Nil, ConfigError) {
  case string.trim(root) {
    "" -> Error(EmptySourceRoot)
    _ -> Ok(Nil)
  }
}

fn validate_roots(roots: List(String)) -> Result(Nil, ConfigError) {
  list.try_each(roots, fn(r) {
    case string.trim(r) {
      "" -> Error(EmptyRoot)
      _ -> Ok(Nil)
    }
  })
}

fn validate_extensions(extensions: List(String)) -> Result(Nil, ConfigError) {
  case extensions {
    [] -> Error(EmptyExtensions)
    _ ->
      list.try_each(extensions, fn(ext) {
        case ext {
          ".gleam" | ".mjs" | ".ts" | ".js" -> Ok(Nil)
          other -> Error(UnsupportedExtension(other))
        }
      })
  }
}

fn validate_snippets(
  raw_snippets: List(RawSnippet),
) -> Result(List(SnippetSpec), ConfigError) {
  use specs <- result_try(validate_each_snippet(raw_snippets, 0, []))
  use _ <- result_try(check_duplicate_ids(specs))
  Ok(specs)
}

fn validate_each_snippet(
  remaining: List(RawSnippet),
  index: Int,
  acc: List(SnippetSpec),
) -> Result(List(SnippetSpec), ConfigError) {
  case remaining {
    [] -> Ok(list.reverse(acc))
    [raw, ..rest] -> {
      use spec <- result_try(validate_one_snippet(raw, index))
      validate_each_snippet(rest, index + 1, [spec, ..acc])
    }
  }
}

fn validate_one_snippet(
  raw: RawSnippet,
  index: Int,
) -> Result(SnippetSpec, ConfigError) {
  use _ <- result_try(case string.trim(raw.id) {
    "" -> Error(EmptyId(index))
    _ -> Ok(Nil)
  })
  use _ <- result_try(case string.trim(raw.source_path) {
    "" -> Error(EmptyPath(raw.id))
    _ -> Ok(Nil)
  })
  use _ <- result_try(case string.trim(raw.language) {
    "" -> Error(EmptyLanguage(raw.id))
    _ -> Ok(Nil)
  })
  use selection <- result_try(validate_selection(raw))
  Ok(SnippetSpec(
    id: raw.id,
    source_path: raw.source_path,
    language: raw.language,
    selection:,
  ))
}

/// Reads the selector of one snippet.
///
/// The snippet declares `markers` or `wholeFile`. Two selectors are a
/// conflict, and no selector is an omission. `wholeFile` accepts only
/// `true`, and a whole-file snippet has no use for a separator.
fn validate_selection(raw: RawSnippet) -> Result(Selection, ConfigError) {
  case raw.markers, raw.whole_file {
    option.Some(_), option.Some(_) -> Error(ConflictingSelection(raw.id))
    option.None, option.None -> Error(MissingSelection(raw.id))
    option.None, option.Some(False) -> Error(WholeFileNotTrue(raw.id))
    option.None, option.Some(True) ->
      case raw.separator {
        option.Some(_) -> Error(SeparatorWithWholeFile(raw.id))
        option.None -> Ok(WholeFileSelection)
      }
    option.Some(markers), option.None -> {
      use _ <- result_try(case markers {
        [] -> Error(EmptyMarkers(raw.id))
        _ -> Ok(Nil)
      })
      use _ <- result_try(check_repeated_markers(raw.id, markers))
      Ok(MarkerSelection(
        markers:,
        separator: option.unwrap(raw.separator, "\n\n"),
      ))
    }
  }
}

fn check_repeated_markers(
  id: String,
  markers: List(String),
) -> Result(Nil, ConfigError) {
  check_repeated_markers_loop(id, markers, set.new())
}

fn check_repeated_markers_loop(
  id: String,
  markers: List(String),
  seen: set.Set(String),
) -> Result(Nil, ConfigError) {
  case markers {
    [] -> Ok(Nil)
    [m, ..rest] ->
      case set.contains(seen, m) {
        True -> Error(RepeatedMarker(id, m))
        False -> check_repeated_markers_loop(id, rest, set.insert(seen, m))
      }
  }
}

fn check_duplicate_ids(specs: List(SnippetSpec)) -> Result(Nil, ConfigError) {
  check_duplicate_ids_loop(specs, dict.new())
}

fn check_duplicate_ids_loop(
  specs: List(SnippetSpec),
  seen: dict.Dict(String, Nil),
) -> Result(Nil, ConfigError) {
  case specs {
    [] -> Ok(Nil)
    [spec, ..rest] ->
      case dict.has_key(seen, spec.id) {
        True -> Error(DuplicateId(spec.id))
        False -> check_duplicate_ids_loop(rest, dict.insert(seen, spec.id, Nil))
      }
  }
}
