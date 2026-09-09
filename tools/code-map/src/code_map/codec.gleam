//// Decodes foreign values and encodes the versioned wire format.

import code_map/config
import code_map/model
import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None}
import gleam/result
import gleam/set
import gleam/string

@external(javascript, "../code_map_ffi.mjs", "is_undefined")
fn is_undefined(value: decode.Dynamic) -> Bool

pub fn undefined_default(
  inner: decode.Decoder(a),
  default: a,
) -> decode.Decoder(a) {
  use data <- decode.then(decode.dynamic)
  case is_undefined(data) {
    True -> decode.success(default)
    False -> inner
  }
}

pub fn known_fields(fields: List(String)) -> decode.Decoder(Nil) {
  use object <- decode.then(decode.dict(decode.string, decode.dynamic))
  case list.all(dict.keys(object), fn(key) { list.contains(fields, key) }) {
    True -> decode.success(Nil)
    False -> decode.failure(Nil, "known fields")
  }
}

pub fn config() -> decode.Decoder(model.Config) {
  use _ <- decode.then(known_fields(["version", "excludeDirs", "excludePaths"]))
  use _ <- decode.field(
    "version",
    checked(decode.int, fn(v) { v == 1 }, "version 1"),
  )
  use dirs <- decode.optional_field(
    "excludeDirs",
    [],
    undefined_default(decode.list(decode.string), []),
  )
  use paths <- decode.optional_field(
    "excludePaths",
    [],
    undefined_default(decode.list(decode.string), []),
  )
  decode.success(model.Config(dirs, paths))
}

pub fn decode_config(
  value: decode.Dynamic,
) -> Result(model.Config, model.Error) {
  use config <- result.try(
    decode.run(value, config())
    |> result.map_error(fn(_) {
      model.ConfigError("expected version 1 and valid exclusion fields")
    }),
  )
  config.validate(config)
}

pub fn encode_config(config: model.Config) -> json.Json {
  json.object([
    #("version", json.int(1)),
    #("excludeDirs", json.array(config.exclude_dirs, json.string)),
    #("excludePaths", json.array(config.exclude_paths, json.string)),
  ])
}

pub fn checked(
  decoder: decode.Decoder(a),
  valid: fn(a) -> Bool,
  expected: String,
) -> decode.Decoder(a) {
  use value <- decode.then(decoder)
  case valid(value) {
    True -> decode.success(value)
    False -> decode.failure(value, expected)
  }
}

pub fn safe_int() -> decode.Decoder(Int) {
  checked(
    decode.int,
    fn(n) { n >= -9_007_199_254_740_991 && n <= 9_007_199_254_740_991 },
    "safe integer",
  )
}

pub fn choices(
  entries: List(#(String, a)),
  fallback: a,
  label: String,
) -> decode.Decoder(a) {
  use value <- decode.then(decode.string)
  case list.key_find(entries, value) {
    Ok(value) -> decode.success(value)
    Error(_) -> decode.failure(fallback, label)
  }
}

pub fn kind() -> decode.Decoder(model.SymbolKind) {
  choices(
    [
      #("function", model.Function),
      #("method", model.Method),
      #("class", model.Class),
      #("type", model.Type),
      #("constant", model.Constant),
    ],
    model.Function,
    "symbol kind",
  )
}

pub fn kind_name(value: model.SymbolKind) -> String {
  case value {
    model.Function -> "function"
    model.Method -> "method"
    model.Class -> "class"
    model.Type -> "type"
    model.Constant -> "constant"
  }
}

fn visibility() -> decode.Decoder(model.Visibility) {
  choices(
    [
      #("public", model.Public),
      #("protected", model.Protected),
      #("private", model.Private),
      #("local", model.Local),
      #("unknown", model.Unknown),
    ],
    model.Unknown,
    "visibility",
  )
}

pub fn visibility_name(value: model.Visibility) -> String {
  case value {
    model.Public -> "public"
    model.Protected -> "protected"
    model.Private -> "private"
    model.Local -> "local"
    model.Unknown -> "unknown"
  }
}

fn target() -> decode.Decoder(model.Target) {
  choices(
    [#("erlang", model.ErlangTarget), #("javascript", model.JavaScriptTarget)],
    model.ErlangTarget,
    "target",
  )
}

pub fn target_name(value: model.Target) -> String {
  case value {
    model.ErlangTarget -> "erlang"
    model.JavaScriptTarget -> "javascript"
  }
}

pub fn language() -> decode.Decoder(model.Language) {
  choices(
    [
      #("gleam", model.Gleam),
      #("javascript", model.JavaScript),
      #("typescript", model.TypeScript),
      #("astro", model.Astro),
    ],
    model.Gleam,
    "language",
  )
}

pub fn language_name(value: model.Language) -> String {
  case value {
    model.Gleam -> "gleam"
    model.JavaScript -> "javascript"
    model.TypeScript -> "typescript"
    model.Astro -> "astro"
  }
}

pub fn status() -> decode.Decoder(model.FileStatus) {
  choices(
    [
      #("indexed", model.Indexed),
      #("unsupported", model.Unsupported),
      #("excluded", model.Excluded),
      #("parse-error", model.ParseError),
      #("unreadable", model.Unreadable),
    ],
    model.Indexed,
    "file status",
  )
}

pub fn status_name(value: model.FileStatus) -> String {
  case value {
    model.Indexed -> "indexed"
    model.Unsupported -> "unsupported"
    model.Excluded -> "excluded"
    model.ParseError -> "parse-error"
    model.Unreadable -> "unreadable"
  }
}

pub fn hash() -> decode.Decoder(String) {
  checked(
    decode.string,
    fn(value) {
      string.length(value) == 64
      && list.all(string.to_graphemes(value), fn(c) {
        string.contains("0123456789abcdef", c)
      })
    },
    "SHA-256",
  )
}

pub fn path() -> decode.Decoder(String) {
  checked(decode.string, config.relative_path, "repository-relative path")
}

pub fn position() -> decode.Decoder(model.Position) {
  use line <- decode.field(
    "line",
    checked(safe_int(), fn(n) { n > 0 }, "positive line"),
  )
  use column <- decode.field(
    "column",
    checked(safe_int(), fn(n) { n > 0 }, "positive column"),
  )
  use byte <- decode.field(
    "byte",
    checked(safe_int(), fn(n) { n >= 0 }, "nonnegative byte"),
  )
  decode.success(model.Position(line, column, byte))
}

pub fn range() -> decode.Decoder(model.Range) {
  let decoder = {
    use start <- decode.field("start", position())
    use end <- decode.field("end", position())
    decode.success(model.Range(start, end))
  }
  checked(
    decoder,
    fn(r) { r.start.byte <= r.end.byte && r.start.line <= r.end.line },
    "ordered range",
  )
}

pub fn diagnostic() -> decode.Decoder(model.Diagnostic) {
  use path <- decode.field("path", path())
  use message <- decode.field("message", decode.string)
  use range <- decode.field("range", decode.optional(range()))
  decode.success(model.Diagnostic(path, message, range))
}

pub fn region() -> decode.Decoder(model.SkippedRegion) {
  use reason <- decode.field("reason", decode.string)
  use range <- decode.field("range", range())
  decode.success(model.SkippedRegion(reason, range))
}

pub fn raw_symbol() -> decode.Decoder(model.RawSymbol) {
  use name <- decode.field(
    "name",
    checked(decode.string, fn(n) { n != "" }, "nonempty name"),
  )
  use container <- decode.field("container", decode.list(decode.string))
  use kind <- decode.field("kind", kind())
  use visibility <- decode.field("visibility", visibility())
  use exported <- decode.field("exported", decode.bool)
  use signature <- decode.field("signature", decode.string)
  use range <- decode.field("range", range())
  use target <- decode.field("target", decode.optional(target()))
  decode.success(model.RawSymbol(
    name,
    container,
    kind,
    visibility,
    exported,
    signature,
    range,
    target,
  ))
}

pub fn symbol(path: String) -> decode.Decoder(model.Symbol) {
  let decoder = {
    use id <- decode.field("id", decode.string)
    use qualified_name <- decode.field("qualifiedName", decode.string)
    use raw <- decode.then(raw_symbol())
    decode.success(model.Symbol(id, qualified_name, raw))
  }
  checked(
    decoder,
    fn(s) {
      s.id == model.symbol_id(path, s.declaration)
      && s.qualified_name == model.qualified_name(path, s.declaration)
    },
    "consistent symbol identity",
  )
}

pub fn file() -> decode.Decoder(model.FileEntry) {
  let decoder = {
    use path <- decode.field("path", path())
    use language <- decode.field("language", decode.optional(language()))
    use status <- decode.field("status", status())
    use reason <- decode.field("reason", decode.optional(decode.string))
    use hash <- decode.field("hash", decode.optional(hash()))
    use symbols <- decode.field("symbols", decode.list(symbol(path)))
    use diagnostics <- decode.field("diagnostics", decode.list(diagnostic()))
    use skipped_regions <- decode.field("skippedRegions", decode.list(region()))
    decode.success(model.FileEntry(
      path,
      language,
      status,
      reason,
      hash,
      symbols,
      diagnostics,
      skipped_regions,
    ))
  }
  checked(
    decoder,
    fn(f) {
      list.all(f.diagnostics, fn(d) { d.path == f.path })
      && case f.status {
        model.Indexed ->
          f.hash != None && f.language != None && f.diagnostics == []
        _ -> f.symbols == []
      }
    },
    "consistent file entry",
  )
}

pub fn index() -> decode.Decoder(model.Index) {
  let decoder = {
    use _ <- decode.field(
      "version",
      checked(decode.int, fn(v) { v == 1 }, "version 1"),
    )
    use tool_hash <- decode.field("toolHash", hash())
    use config_hash <- decode.field("configHash", hash())
    use complete <- decode.field("complete", decode.bool)
    use files <- decode.field("files", decode.list(file()))
    decode.success(model.Index(tool_hash, config_hash, complete, files))
  }
  checked(
    decoder,
    fn(index) {
      set.size(set.from_list(list.map(index.files, fn(f) { f.path })))
      == list.length(index.files)
      && index.complete
      == !list.any(index.files, fn(f) { model.failed(f.status) })
    },
    "consistent index",
  )
}

pub fn decode_index(value: decode.Dynamic) -> Result(model.Index, model.Error) {
  decode.run(value, index()) |> result.map_error(fn(_) { model.CacheError })
}

pub fn encode_position(value: model.Position) -> json.Json {
  json.object([
    #("line", json.int(value.line)),
    #("column", json.int(value.column)),
    #("byte", json.int(value.byte)),
  ])
}

pub fn encode_range(value: model.Range) -> json.Json {
  json.object([
    #("start", encode_position(value.start)),
    #("end", encode_position(value.end)),
  ])
}

pub fn encode_diagnostic(value: model.Diagnostic) -> json.Json {
  json.object([
    #("path", json.string(value.path)),
    #("message", json.string(value.message)),
    #("range", json.nullable(value.range, encode_range)),
  ])
}

pub fn encode_region(value: model.SkippedRegion) -> json.Json {
  json.object([
    #("reason", json.string(value.reason)),
    #("range", encode_range(value.range)),
  ])
}

pub fn symbol_fields(value: model.Symbol) -> List(#(String, json.Json)) {
  let raw = value.declaration
  [
    #("id", json.string(value.id)),
    #("name", json.string(raw.name)),
    #("qualifiedName", json.string(value.qualified_name)),
    #("container", json.array(raw.container, json.string)),
    #("kind", json.string(kind_name(raw.kind))),
    #("visibility", json.string(visibility_name(raw.visibility))),
    #("exported", json.bool(raw.exported)),
    #("signature", json.string(raw.signature)),
    #("range", encode_range(raw.range)),
    #(
      "target",
      json.nullable(raw.target, fn(t) { json.string(target_name(t)) }),
    ),
  ]
}

pub fn encode_symbol(value: model.Symbol) -> json.Json {
  json.object(symbol_fields(value))
}

pub fn encode_file(value: model.FileEntry) -> json.Json {
  json.object([
    #("path", json.string(value.path)),
    #(
      "language",
      json.nullable(value.language, fn(l) { json.string(language_name(l)) }),
    ),
    #("status", json.string(status_name(value.status))),
    #("reason", json.nullable(value.reason, json.string)),
    #("hash", json.nullable(value.hash, json.string)),
    #("symbols", json.array(value.symbols, encode_symbol)),
    #("diagnostics", json.array(value.diagnostics, encode_diagnostic)),
    #("skippedRegions", json.array(value.skipped_regions, encode_region)),
  ])
}

pub fn encode_index(value: model.Index) -> json.Json {
  json.object([
    #("version", json.int(1)),
    #("toolHash", json.string(value.tool_hash)),
    #("configHash", json.string(value.config_hash)),
    #("complete", json.bool(value.complete)),
    #("files", json.array(value.files, encode_file)),
  ])
}
