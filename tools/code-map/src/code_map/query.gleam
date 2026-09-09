//// Pure queries and terminal rendering.

import code_map/codec
import code_map/config
import code_map/model
import gleam/dict
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/string

pub fn metadata(file: model.FileEntry) -> model.Metadata {
  model.Metadata(
    file.path,
    file.language,
    file.status,
    file.reason,
    list.length(file.symbols),
    list.length(file.diagnostics),
    list.length(file.skipped_regions),
  )
}

fn page(items: List(a), page: model.Page) -> List(a) {
  items |> list.drop(page.offset) |> list.take(page.limit)
}

pub fn run(
  index: model.Index,
  request: model.Request,
) -> Result(model.View, model.Error) {
  let diagnostics = list.flat_map(index.files, fn(f) { f.diagnostics })
  let counts =
    list.map(model.statuses, fn(status) {
      #(status, list.count(index.files, fn(f) { f.status == status }))
    })
  let skipped =
    list.fold(index.files, 0, fn(n, f) { n + list.length(f.skipped_regions) })
  use content <- result.try(content(index, request))
  Ok(model.View(
    model.request_command(request),
    index.complete,
    counts,
    list.length(diagnostics),
    skipped,
    list.take(diagnostics, 50),
    content,
  ))
}

fn filter_path(
  files: List(model.FileEntry),
  path: Option(String),
) -> List(model.FileEntry) {
  list.filter(files, fn(f) {
    case path {
      None -> True
      Some(path) -> config.beneath(f.path, path)
    }
  })
}

fn content(
  index: model.Index,
  request: model.Request,
) -> Result(model.Content, model.Error) {
  case request {
    model.Overview | model.Refresh -> {
      let groups =
        list.fold(index.files, dict.new(), fn(groups, file) {
          let path = case string.split(file.path, "/") {
            [first, _, ..] -> first
            _ -> "."
          }
          let prior =
            dict.get(groups, path) |> result.unwrap(model.Group(path, 0, 0))
          dict.insert(
            groups,
            path,
            model.Group(
              path,
              prior.files + 1,
              prior.symbols + list.length(file.symbols),
            ),
          )
        })
      let groups =
        dict.values(groups)
        |> list.sort(fn(a, b) { string.compare(a.path, b.path) })
      Ok(model.Summary(
        list.length(index.files),
        list.fold(index.files, 0, fn(n, f) { n + list.length(f.symbols) }),
        list.take(groups, 50),
        list.length(groups),
      ))
    }
    model.Files(path, pagination) -> {
      let files = filter_path(index.files, path)
      Ok(model.Inventory(
        list.map(page(files, pagination), metadata),
        list.length(files),
        pagination,
      ))
    }
    model.File(path, pagination) -> {
      use file <- result.try(
        list.find(index.files, fn(f) { f.path == path })
        |> result.map_error(fn(_) {
          model.RequestError("File not in current inventory: " <> path)
        }),
      )
      Ok(model.Declarations(
        list.map(page(file.symbols, pagination), fn(s) { #(file.path, s) }),
        list.length(file.symbols),
        pagination,
        Some(model.FileDetail(
          metadata(file),
          file.diagnostics,
          file.skipped_regions,
        )),
      ))
    }
    model.Find(needle, path, kind, pagination) -> {
      let needle = string.lowercase(needle)
      let items =
        filter_path(index.files, path)
        |> list.flat_map(fn(f) { list.map(f.symbols, fn(s) { #(f.path, s) }) })
        |> list.filter(fn(item) {
          let #(_, symbol) = item
          {
            case kind {
              None -> True
              Some(kind) -> symbol.declaration.kind == kind
            }
          }
          && string.contains(string.lowercase(symbol.qualified_name), needle)
        })
        |> list.sort(fn(a, b) { compare_matches(a, b, needle) })
      Ok(model.Declarations(
        page(items, pagination),
        list.length(items),
        pagination,
        None,
      ))
    }
  }
}

fn rank(symbol: model.Symbol, needle: String) -> Int {
  let name = string.lowercase(symbol.declaration.name)
  case name == needle, string.starts_with(name, needle) {
    True, _ -> 0
    _, True -> 1
    _, _ -> 2
  }
}

fn compare_matches(
  a: #(String, model.Symbol),
  b: #(String, model.Symbol),
  needle: String,
) -> order.Order {
  case int.compare(rank(a.1, needle), rank(b.1, needle)) {
    order.Eq ->
      case string.compare(a.0, b.0) {
        order.Eq ->
          case
            int.compare(
              a.1.declaration.range.start.byte,
              b.1.declaration.range.start.byte,
            )
          {
            order.Eq -> string.compare(a.1.id, b.1.id)
            order -> order
          }
        order -> order
      }
    order -> order
  }
}

fn quote(value: String) -> String {
  value |> json.string |> json.to_string
}

fn number(value: Int) -> String {
  int.to_string(value)
}

fn reason(value: Option(String)) -> String {
  case value {
    None -> ""
    Some(reason) -> " (" <> quote(reason) <> ")"
  }
}

fn pagination(count: Int, total: Int, page: model.Page) -> String {
  number(count)
  <> " of "
  <> number(total)
  <> " results (offset "
  <> number(page.offset)
  <> ")"
}

fn more(total: Int, page: model.Page) -> List(String) {
  case page.offset + page.limit < total {
    True -> [
      "More results: repeat with --offset " <> number(page.offset + page.limit),
    ]
    False -> []
  }
}

pub fn render(view: model.View) -> String {
  let lines = case view.content {
    model.Summary(files, symbols, groups, total) -> {
      let header = [
        number(files) <> " files, " <> number(symbols) <> " symbols",
      ]
      let lines =
        list.map(groups, fn(g) {
          quote(g.path)
          <> ": "
          <> number(g.files)
          <> " files, "
          <> number(g.symbols)
          <> " symbols"
        })
      list.append(
        header,
        list.append(lines, case total > 50 {
          True -> [
            number(total) <> " groups; use files --path <directory> to browse.",
          ]
          False -> []
        }),
      )
    }
    model.Inventory(items, total, page) -> {
      let lines =
        list.map(items, fn(item) {
          quote(item.path)
          <> ": "
          <> codec.status_name(item.status)
          <> ", "
          <> number(item.symbol_count)
          <> " symbols"
          <> reason(item.reason)
        })
      [
        pagination(list.length(items), total, page),
        ..list.append(lines, more(total, page))
      ]
    }
    model.Declarations(items, total, page, file) -> {
      let header = case file {
        None -> []
        Some(file) -> [
          quote(file.metadata.path)
          <> ": "
          <> codec.status_name(file.metadata.status)
          <> reason(file.metadata.reason),
        ]
      }
      let lines =
        list.map(items, fn(item) {
          let #(path, symbol) = item
          let raw = symbol.declaration
          quote(path)
          <> ":"
          <> number(raw.range.start.line)
          <> ":"
          <> number(raw.range.start.column)
          <> " "
          <> codec.kind_name(raw.kind)
          <> " "
          <> codec.visibility_name(raw.visibility)
          <> " "
          <> quote(raw.signature)
        })
      list.append(header, [
        pagination(list.length(items), total, page),
        ..list.append(lines, more(total, page))
      ])
    }
  }
  let coverage =
    "Coverage: "
    <> string.join(
      list.map(view.counts, fn(pair) {
        codec.status_name(pair.0) <> "=" <> number(pair.1)
      }),
      ", ",
    )
  let skipped = case view.skipped_count > 0 {
    True -> [
      number(view.skipped_count)
      <> " script regions excluded; see file --json for details.",
    ]
    False -> []
  }
  let incomplete = case view.complete {
    True -> []
    False -> [
      "INCOMPLETE: source errors; failed files have no current declarations.",
    ]
  }
  let diagnostics =
    list.map(view.diagnostics, fn(d) {
      quote(d.path) <> ": " <> quote(d.message)
    })
  let truncated = case view.diagnostic_count > 50 {
    True -> [
      number(view.diagnostic_count)
      <> " diagnostics; use files and file to inspect affected paths.",
    ]
    False -> []
  }
  [lines, [coverage], skipped, incomplete, diagnostics, truncated]
  |> list.flatten
  |> string.join("\n")
  |> string.append("\n")
}
