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

pub const statuses = [Indexed, Unsupported, Excluded, ParseError, Unreadable]

pub type Page {
  Page(limit: Int, offset: Int)
}

pub type Request {
  Overview
  Refresh
  Files(path: Option(String), page: Page)
  File(path: String, page: Page)
  Find(
    query: String,
    path: Option(String),
    kind: Option(SymbolKind),
    page: Page,
  )
}

pub fn command(request: Request) -> String {
  request_command(request) |> command_name
}

pub type Command {
  OverviewCommand
  RefreshCommand
  FilesCommand
  FileCommand
  FindCommand
}

pub fn request_command(request: Request) -> Command {
  case request {
    Overview -> OverviewCommand
    Refresh -> RefreshCommand
    Files(..) -> FilesCommand
    File(..) -> FileCommand
    Find(..) -> FindCommand
  }
}

pub fn command_name(command: Command) -> String {
  case command {
    OverviewCommand -> "overview"
    RefreshCommand -> "refresh"
    FilesCommand -> "files"
    FileCommand -> "file"
    FindCommand -> "find"
  }
}

pub type Metadata {
  Metadata(
    path: String,
    language: Option(Language),
    status: FileStatus,
    reason: Option(String),
    symbol_count: Int,
    diagnostic_count: Int,
    skipped_count: Int,
  )
}

pub type FileDetail {
  FileDetail(
    metadata: Metadata,
    diagnostics: List(Diagnostic),
    skipped_regions: List(SkippedRegion),
  )
}

pub type Group {
  Group(path: String, files: Int, symbols: Int)
}

pub type Content {
  Summary(files: Int, symbols: Int, groups: List(Group), groups_total: Int)
  Inventory(items: List(Metadata), total: Int, page: Page)
  Declarations(
    items: List(#(String, Symbol)),
    total: Int,
    page: Page,
    file: Option(FileDetail),
  )
}

pub type View {
  View(
    command: Command,
    complete: Bool,
    counts: List(#(FileStatus, Int)),
    diagnostic_count: Int,
    skipped_count: Int,
    diagnostics: List(Diagnostic),
    content: Content,
  )
}

pub type Invocation {
  Invocation(request: Request, root: Option(String), json: Bool, rebuild: Bool)
}

pub const limits = [
  "Syntax only; no inferred types, references, call graph, or runtime-generated methods.",
  "Named declarations and callable bindings; not unbound anonymous callbacks.",
  "Gleam constructors are represented by their enclosing type.",
  "Astro frontmatter and executable scripts only; no template expressions, styles, event attributes, or external script contents.",
  "Other formats are inventoried but not parsed.",
]
