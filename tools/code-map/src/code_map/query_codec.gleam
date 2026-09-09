//// Wire formats for requests and bounded query views.

import code_map/codec
import code_map/config
import code_map/model
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

fn command() -> decode.Decoder(model.Command) {
  codec.choices(
    [
      #("overview", model.OverviewCommand),
      #("refresh", model.RefreshCommand),
      #("files", model.FilesCommand),
      #("file", model.FileCommand),
      #("find", model.FindCommand),
    ],
    model.OverviewCommand,
    "command",
  )
}

fn optional(inner: decode.Decoder(a)) -> decode.Decoder(Option(a)) {
  codec.undefined_default(decode.map(inner, Some), None)
}

fn digits() -> decode.Decoder(Int) {
  use value <- decode.then(codec.checked(
    decode.string,
    fn(s) {
      s != ""
      && list.all(string.to_graphemes(s), fn(c) {
        string.contains("0123456789", c)
      })
    },
    "integer",
  ))
  case int.parse(value) {
    Ok(value) -> decode.success(value)
    Error(_) -> decode.failure(0, "integer")
  }
}

fn page(cli: Bool) -> decode.Decoder(model.Page) {
  let number = case cli {
    True -> digits()
    False -> codec.safe_int()
  }
  use limit <- decode.optional_field("limit", None, decode.optional(number))
  use offset <- decode.optional_field("offset", None, decode.optional(number))
  let limit = option.unwrap(limit, 50)
  let offset = option.unwrap(offset, 0)
  case
    limit > 0
    && limit <= 9_007_199_254_740_991
    && offset >= 0
    && offset <= 9_007_199_254_740_991
  {
    True -> decode.success(model.Page(limit, offset))
    False ->
      decode.failure(
        model.Page(50, 0),
        "positive limit and nonnegative offset (safe integers)",
      )
  }
}

fn fields(
  command: model.Command,
  cli: Bool,
  argument: Option(String),
) -> decode.Decoder(model.Request) {
  let fields = case command {
    model.OverviewCommand | model.RefreshCommand -> []
    model.FilesCommand -> ["path", "limit", "offset"]
    model.FileCommand ->
      case cli {
        True -> ["limit", "offset"]
        False -> ["path", "limit", "offset"]
      }
    model.FindCommand ->
      case cli {
        True -> ["path", "kind", "limit", "offset"]
        False -> ["query", "path", "kind", "limit", "offset"]
      }
  }
  let fields =
    list.append(fields, case cli {
      True -> ["root", "json", "rebuild", "help"]
      False -> ["command"]
    })
  use _ <- decode.then(codec.known_fields(fields))
  case command {
    model.OverviewCommand -> decode.success(model.Overview)
    model.RefreshCommand -> decode.success(model.Refresh)
    model.FilesCommand -> {
      use path <- decode.optional_field("path", None, optional(codec.path()))
      use page <- decode.then(page(cli))
      decode.success(model.Files(path, page))
    }
    model.FileCommand -> {
      let path_decoder = case cli {
        False -> decode.at(["path"], codec.path())
        True ->
          case argument {
            Some(path) ->
              case config.relative_path(path) {
                True -> decode.success(path)
                False -> decode.failure("", "repository-relative path")
              }
            None -> decode.failure("", "file path")
          }
      }
      use path <- decode.then(path_decoder)
      use page <- decode.then(page(cli))
      decode.success(model.File(path, page))
    }
    model.FindCommand -> {
      let query_decoder = case cli {
        False -> decode.at(["query"], decode.string)
        True ->
          case argument {
            Some(query) -> decode.success(query)
            None -> decode.failure("", "find query")
          }
      }
      use query <- decode.then(codec.checked(
        query_decoder,
        fn(q) { q != "" },
        "nonempty query",
      ))
      use path <- decode.optional_field("path", None, optional(codec.path()))
      use kind <- decode.optional_field("kind", None, optional(codec.kind()))
      use page <- decode.then(page(cli))
      decode.success(model.Find(query, path, kind, page))
    }
  }
}

pub fn request() -> decode.Decoder(model.Request) {
  use command <- decode.optional_field(
    "command",
    model.OverviewCommand,
    codec.undefined_default(command(), model.OverviewCommand),
  )
  fields(command, False, None)
}

fn error(errors: List(decode.DecodeError)) -> model.Error {
  case errors {
    [first, ..] ->
      model.RequestError(
        "Invalid query request: "
        <> string.join(first.path, ".")
        <> " expected "
        <> first.expected,
      )
    [] -> model.RequestError("Invalid query request")
  }
}

pub fn decode_request(
  value: decode.Dynamic,
) -> Result(model.Request, model.Error) {
  decode.run(value, request()) |> result.map_error(error)
}

pub fn decode_cli(
  values: decode.Dynamic,
  positional: decode.Dynamic,
) -> Result(model.Invocation, model.Error) {
  use positionals <- result.try(
    decode.run(positional, decode.list(decode.string))
    |> result.map_error(error),
  )
  let #(name, argument, valid) = case positionals {
    [] -> #("overview", None, True)
    [name] -> #(name, None, True)
    [name, argument] -> #(
      name,
      Some(argument),
      name == "find" || name == "file",
    )
    _ -> #("", None, False)
  }
  use _ <- result.try(case valid {
    True -> Ok(Nil)
    False -> Error(model.RequestError("Unexpected positional argument"))
  })
  let selected = case name {
    "overview" -> Ok(model.OverviewCommand)
    "refresh" -> Ok(model.RefreshCommand)
    "files" -> Ok(model.FilesCommand)
    "file" -> Ok(model.FileCommand)
    "find" -> Ok(model.FindCommand)
    _ -> Error(model.RequestError("Unknown command: " <> name))
  }
  use selected <- result.try(selected)
  let decoder = {
    use root <- decode.optional_field("root", None, optional(decode.string))
    use json <- decode.optional_field("json", False, decode.bool)
    use rebuild <- decode.optional_field("rebuild", False, decode.bool)
    use request <- decode.then(fields(selected, True, argument))
    decode.success(model.Invocation(request, root, json, rebuild))
  }
  use invocation <- result.try(
    decode.run(values, decoder) |> result.map_error(error),
  )
  case invocation.rebuild && selected != model.RefreshCommand {
    True -> Error(model.RequestError("--rebuild is only valid for refresh"))
    False -> Ok(invocation)
  }
}

fn optional_field(
  key: String,
  value: Option(a),
  encode: fn(a) -> json.Json,
) -> List(#(String, json.Json)) {
  case value {
    None -> []
    Some(value) -> [#(key, encode(value))]
  }
}

fn page_fields(total: Int, page: model.Page) -> List(#(String, json.Json)) {
  [
    #("total", json.int(total)),
    #("limit", json.int(page.limit)),
    #("offset", json.int(page.offset)),
    #("hasMore", json.bool(page.offset + page.limit < total)),
  ]
}

pub fn encode_request(request: model.Request) -> json.Json {
  let fields = case request {
    model.Overview | model.Refresh -> []
    model.Files(path, page) ->
      list.append(optional_field("path", path, json.string), [
        #("limit", json.int(page.limit)),
        #("offset", json.int(page.offset)),
      ])
    model.File(path, page) -> [
      #("path", json.string(path)),
      #("limit", json.int(page.limit)),
      #("offset", json.int(page.offset)),
    ]
    model.Find(query, path, kind, page) -> {
      let fields = [#("query", json.string(query))]
      [
        fields,
        optional_field("path", path, json.string),
        optional_field("kind", kind, fn(k) { json.string(codec.kind_name(k)) }),
        [#("limit", json.int(page.limit)), #("offset", json.int(page.offset))],
      ]
      |> list.flatten
    }
  }
  json.object([#("command", json.string(model.command(request))), ..fields])
}

fn metadata_fields(meta: model.Metadata) -> List(#(String, json.Json)) {
  [
    #("path", json.string(meta.path)),
    #(
      "language",
      json.nullable(meta.language, fn(l) { json.string(codec.language_name(l)) }),
    ),
    #("status", json.string(codec.status_name(meta.status))),
    #("reason", json.nullable(meta.reason, json.string)),
    #("symbolCount", json.int(meta.symbol_count)),
    #("diagnosticCount", json.int(meta.diagnostic_count)),
    #("skippedRegionCount", json.int(meta.skipped_count)),
  ]
}

fn encode_detail(file: model.FileDetail) -> json.Json {
  json.object(
    list.append(metadata_fields(file.metadata), [
      #("diagnostics", json.array(file.diagnostics, codec.encode_diagnostic)),
      #("skippedRegions", json.array(file.skipped_regions, codec.encode_region)),
    ]),
  )
}

pub fn encode_view(view: model.View) -> json.Json {
  let common = [
    #("version", json.int(1)),
    #("command", json.string(model.command_name(view.command))),
    #("complete", json.bool(view.complete)),
    #(
      "coverage",
      json.object([
        #(
          "statuses",
          json.object(
            list.map(view.counts, fn(p) {
              #(codec.status_name(p.0), json.int(p.1))
            }),
          ),
        ),
        #("extensions", json.array(config.extensions, json.string)),
        #("limits", json.array(model.limits, json.string)),
        #("intrinsicExclusions", json.array([".code-map"], json.string)),
        #("diagnosticCount", json.int(view.diagnostic_count)),
        #("skippedRegionCount", json.int(view.skipped_count)),
      ]),
    ),
    #("diagnostics", json.array(view.diagnostics, codec.encode_diagnostic)),
    #("diagnosticsHasMore", json.bool(view.diagnostic_count > 50)),
  ]
  let content = case view.content {
    model.Summary(files, symbols, groups, total) -> [
      #(
        "totals",
        json.object([
          #("files", json.int(files)),
          #("symbols", json.int(symbols)),
        ]),
      ),
      #(
        "groups",
        json.array(groups, fn(g) {
          json.object([
            #("path", json.string(g.path)),
            #("files", json.int(g.files)),
            #("symbols", json.int(g.symbols)),
          ])
        }),
      ),
      #("groupsTotal", json.int(total)),
      #("groupsHasMore", json.bool(total > 50)),
    ]
    model.Inventory(items, total, page) -> [
      #(
        "items",
        json.array(items, fn(item) { json.object(metadata_fields(item)) }),
      ),
      ..page_fields(total, page)
    ]
    model.Declarations(items, total, page, file) ->
      list.append(optional_field("file", file, encode_detail), [
        #(
          "items",
          json.array(items, fn(item) {
            json.object([
              #("path", json.string(item.0)),
              ..codec.symbol_fields(item.1)
            ])
          }),
        ),
        ..page_fields(total, page)
      ])
  }
  json.object(list.append(common, content))
}

fn metadata() -> decode.Decoder(model.Metadata) {
  use path <- decode.field("path", codec.path())
  use language <- decode.field("language", decode.optional(codec.language()))
  use status <- decode.field("status", codec.status())
  use reason <- decode.field("reason", decode.optional(decode.string))
  use symbols <- decode.field("symbolCount", codec.safe_int())
  use diagnostics <- decode.field("diagnosticCount", codec.safe_int())
  use skipped <- decode.field("skippedRegionCount", codec.safe_int())
  decode.success(model.Metadata(
    path,
    language,
    status,
    reason,
    symbols,
    diagnostics,
    skipped,
  ))
}

fn detail() -> decode.Decoder(model.FileDetail) {
  use metadata <- decode.then(metadata())
  use diagnostics <- decode.field(
    "diagnostics",
    decode.list(codec.diagnostic()),
  )
  use regions <- decode.field("skippedRegions", decode.list(codec.region()))
  decode.success(model.FileDetail(metadata, diagnostics, regions))
}

fn group() -> decode.Decoder(model.Group) {
  use path <- decode.field("path", decode.string)
  use files <- decode.field("files", codec.safe_int())
  use symbols <- decode.field("symbols", codec.safe_int())
  decode.success(model.Group(path, files, symbols))
}

fn counts() -> decode.Decoder(List(#(model.FileStatus, Int))) {
  use indexed <- decode.field("indexed", codec.safe_int())
  use unsupported <- decode.field("unsupported", codec.safe_int())
  use excluded <- decode.field("excluded", codec.safe_int())
  use parse_error <- decode.field("parse-error", codec.safe_int())
  use unreadable <- decode.field("unreadable", codec.safe_int())
  decode.success([
    #(model.Indexed, indexed),
    #(model.Unsupported, unsupported),
    #(model.Excluded, excluded),
    #(model.ParseError, parse_error),
    #(model.Unreadable, unreadable),
  ])
}

fn view_content(command: model.Command) -> decode.Decoder(model.Content) {
  case command {
    model.OverviewCommand | model.RefreshCommand -> {
      use files <- decode.subfield(["totals", "files"], codec.safe_int())
      use symbols <- decode.subfield(["totals", "symbols"], codec.safe_int())
      use groups <- decode.field("groups", decode.list(group()))
      use total <- decode.field("groupsTotal", codec.safe_int())
      decode.success(model.Summary(files, symbols, groups, total))
    }
    model.FilesCommand -> {
      use items <- decode.field("items", decode.list(metadata()))
      use total <- decode.field("total", codec.safe_int())
      use page <- decode.then(page(False))
      decode.success(model.Inventory(items, total, page))
    }
    model.FileCommand | model.FindCommand -> {
      let item = {
        use path <- decode.field("path", codec.path())
        use symbol <- decode.then(codec.symbol(path))
        decode.success(#(path, symbol))
      }
      use items <- decode.field("items", decode.list(item))
      use total <- decode.field("total", codec.safe_int())
      use page <- decode.then(page(False))
      use file <- decode.optional_field("file", None, optional(detail()))
      decode.success(model.Declarations(items, total, page, file))
    }
  }
}

pub fn decode_view(value: decode.Dynamic) -> Result(model.View, model.Error) {
  let decoder = {
    use command <- decode.field("command", command())
    use complete <- decode.field("complete", decode.bool)
    use counts <- decode.subfield(["coverage", "statuses"], counts())
    use diagnostic_count <- decode.subfield(
      ["coverage", "diagnosticCount"],
      codec.safe_int(),
    )
    use skipped_count <- decode.subfield(
      ["coverage", "skippedRegionCount"],
      codec.safe_int(),
    )
    use diagnostics <- decode.field(
      "diagnostics",
      decode.list(codec.diagnostic()),
    )
    use content <- decode.then(view_content(command))
    decode.success(model.View(
      command,
      complete,
      counts,
      diagnostic_count,
      skipped_count,
      diagnostics,
      content,
    ))
  }
  decode.run(value, decoder) |> result.map_error(error)
}
