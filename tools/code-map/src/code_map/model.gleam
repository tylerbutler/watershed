//// Typed values shared by the code map core.

import gleam/json
import gleam/list
import gleam/option.{type Option}
import gleam/string

pub type SymbolKind {
  Function
  Method
  Class
  Type
  Constant
}

pub type Visibility {
  Public
  Protected
  Private
  Local
  Unknown
}

pub type Target {
  ErlangTarget
  JavaScriptTarget
}

pub type Language {
  Gleam
  JavaScript
  TypeScript
  Astro
}

pub type FileStatus {
  Indexed
  Unsupported
  Excluded
  ParseError
  Unreadable
}

pub type Position {
  Position(line: Int, column: Int, byte: Int)
}

pub type Range {
  Range(start: Position, end: Position)
}

pub type Diagnostic {
  Diagnostic(path: String, message: String, range: Option(Range))
}

pub type SkippedRegion {
  SkippedRegion(reason: String, range: Range)
}

pub type RawSymbol {
  RawSymbol(
    name: String,
    container: List(String),
    kind: SymbolKind,
    visibility: Visibility,
    exported: Bool,
    signature: String,
    range: Range,
    target: Option(Target),
  )
}

pub type Symbol {
  Symbol(id: String, qualified_name: String, declaration: RawSymbol)
}

pub type ParseResult {
  ParseResult(
    symbols: List(Symbol),
    diagnostics: List(Diagnostic),
    skipped_regions: List(SkippedRegion),
  )
}

pub type FileEntry {
  FileEntry(
    path: String,
    language: Option(Language),
    status: FileStatus,
    reason: Option(String),
    hash: Option(String),
    symbols: List(Symbol),
    diagnostics: List(Diagnostic),
    skipped_regions: List(SkippedRegion),
  )
}

pub type Index {
  Index(
    tool_hash: String,
    config_hash: String,
    complete: Bool,
    files: List(FileEntry),
  )
}

pub type Config {
  Config(exclude_dirs: List(String), exclude_paths: List(String))
}

pub type Error {
  ConfigError(String)
  RequestError(String)
  CacheError
  ParserError(String)
  RefreshError(String)
}

pub fn error_message(error: Error) -> String {
  case error {
    ConfigError(message) -> "Invalid code-map config: " <> message
    RequestError(message) -> message
    CacheError -> "Invalid code-map cache schema. Run refresh --rebuild."
    ParserError(message) -> "Invalid parser result: " <> message
    RefreshError(message) -> "Invalid refresh: " <> message
  }
}

pub fn qualified_name(path: String, raw: RawSymbol) -> String {
  path <> "::" <> string.join(list.append(raw.container, [raw.name]), ".")
}

pub fn symbol_id(path: String, raw: RawSymbol) -> String {
  json.preprocessed_array([
    json.string(path),
    json.array(raw.container, json.string),
    json.string(raw.name),
    json.int(raw.range.start.byte),
    json.int(raw.range.end.byte),
  ])
  |> json.to_string
}

pub fn failed(status: FileStatus) -> Bool {
  case status {
    ParseError | Unreadable -> True
    Indexed | Unsupported | Excluded -> False
  }
}
