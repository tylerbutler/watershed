//// Normalizes parser declarations into shared symbols.

import code_map/model
import gleam/int
import gleam/list
import gleam/option.{type Option}
import gleam/order
import gleam/result
import gleam/string

@external(javascript, "../code_map_ffi.mjs", "source_span")
fn source_span(
  source: String,
  start: Int,
  end: Int,
  signature_end: Int,
) -> #(String, #(Int, Int, Int), #(Int, Int, Int))

pub fn range_at(source: String, start: Int, end: Int) -> model.Range {
  let #(_, start, end) = source_span(source, start, end, start)
  model.Range(
    model.Position(start.0, start.1, start.2),
    model.Position(end.0, end.1, end.2),
  )
}

pub fn from_span(
  source: String,
  name: String,
  container: List(String),
  kind: model.SymbolKind,
  visibility: model.Visibility,
  exported: Bool,
  target: Option(model.Target),
  start: Int,
  end: Int,
  signature_end: Int,
) -> model.RawSymbol {
  let #(signature, start, end) = source_span(source, start, end, signature_end)
  model.RawSymbol(
    name,
    container,
    kind,
    visibility,
    exported,
    signature,
    model.Range(
      model.Position(start.0, start.1, start.2),
      model.Position(end.0, end.1, end.2),
    ),
    target,
  )
}

pub fn normalize(
  path: String,
  raw: model.RawSymbol,
) -> Result(model.Symbol, model.Error) {
  case raw.name != "" && raw.range.start.byte <= raw.range.end.byte {
    True ->
      Ok(model.Symbol(
        model.symbol_id(path, raw),
        model.qualified_name(path, raw),
        raw,
      ))
    False -> Error(model.ParserError("invalid declaration"))
  }
}

pub fn normalize_parse(
  path: String,
  raw_symbols: List(model.RawSymbol),
  diagnostics: List(model.Diagnostic),
  skipped_regions: List(model.SkippedRegion),
) -> Result(model.ParseResult, model.Error) {
  case list.all(diagnostics, fn(d) { d.path == path }) {
    False -> Error(model.ParserError("diagnostic path mismatch"))
    True -> {
      use symbols <- result.try(
        list.try_map(raw_symbols, fn(raw) { normalize(path, raw) }),
      )
      Ok(model.ParseResult(
        case diagnostics {
          [] -> list.sort(symbols, compare)
          _ -> []
        },
        diagnostics,
        skipped_regions,
      ))
    }
  }
}

pub fn compare(a: model.Symbol, b: model.Symbol) -> order.Order {
  case
    int.compare(a.declaration.range.start.byte, b.declaration.range.start.byte)
  {
    order.Eq ->
      case
        string.compare(
          kind_name(a.declaration.kind),
          kind_name(b.declaration.kind),
        )
      {
        order.Eq -> string.compare(a.declaration.name, b.declaration.name)
        order -> order
      }
    order -> order
  }
}

pub fn kind_name(kind: model.SymbolKind) -> String {
  case kind {
    model.Function -> "function"
    model.Method -> "method"
    model.Class -> "class"
    model.Type -> "type"
    model.Constant -> "constant"
  }
}
