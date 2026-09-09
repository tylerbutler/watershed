//// JavaScript API boundary. Core errors become JavaScript exceptions here.

import code_map
import code_map/cache
import code_map/cache_codec
import code_map/codec
import code_map/config
import code_map/model
import code_map/query
import code_map/query_codec
import code_map/symbols
import gleam/dynamic/decode
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/result

pub fn decode_config(value: decode.Dynamic) -> model.Config {
  codec.decode_config(value) |> for_javascript
}

pub fn normalize_config(value: decode.Dynamic) -> json.Json {
  decode_config(value) |> codec.encode_config
}

pub fn relative_path(value: decode.Dynamic) -> Bool {
  case decode.run(value, decode.string) {
    Ok(path) -> config.relative_path(path)
    Error(_) -> False
  }
}

pub fn inventory_paths(value: decode.Dynamic) -> json.Json {
  decode.run(value, decode.list(decode.string))
  |> result.map_error(fn(_) { model.RefreshError("invalid Git path listing") })
  |> result.try(config.inventory_paths)
  |> for_javascript
  |> json.array(json.string)
}

pub fn classify(
  configuration: model.Config,
  path: String,
  extension: String,
  regular: Bool,
  symlink: Bool,
) -> json.Json {
  let kind = case regular, symlink {
    True, _ -> config.Regular
    _, True -> config.Symlink
    _, _ -> config.Other
  }
  let #(language, status, reason) = case
    config.classify(configuration, path, extension, kind)
  {
    config.ReadSource(language) -> #(Some(language), "pending", None)
    config.Exclude(language, reason) -> #(language, "excluded", Some(reason))
    config.UnsupportedFormat(reason) -> #(None, "unsupported", Some(reason))
  }
  json.object([
    #(
      "language",
      json.nullable(language, fn(l) { json.string(codec.language_name(l)) }),
    ),
    #("status", json.string(status)),
    #("reason", json.nullable(reason, json.string)),
  ])
}

@external(javascript, "../code_map_ffi.mjs", "raise_error")
fn raise_error(message: String) -> a

fn for_javascript(value: Result(a, model.Error)) -> a {
  case value {
    Ok(value) -> value
    Error(error) -> raise_error(model.error_message(error))
  }
}

pub fn decode_index(value: decode.Dynamic) -> model.Index {
  codec.decode_index(value) |> for_javascript
}

pub fn encode_index(value: model.Index) -> json.Json {
  codec.encode_index(value)
}

pub fn normalize_parse(path: String, value: decode.Dynamic) -> json.Json {
  let #(raw, diagnostics, regions) =
    decode.run(value, codec.raw_parse())
    |> result.map_error(fn(_) { model.ParserError(path) })
    |> for_javascript
  symbols.normalize_parse(path, raw, diagnostics, regions)
  |> for_javascript
  |> codec.encode_parse
}

pub fn parse_gleam(path: String, source: String) -> json.Json {
  code_map.extract(path, source) |> for_javascript |> codec.encode_parse
}

pub fn query_index(
  index: decode.Dynamic,
  request: decode.Dynamic,
) -> json.Json {
  let request = query_codec.decode_request(request) |> for_javascript
  query.run(decode_index(index), request)
  |> for_javascript
  |> query_codec.encode_view
}

pub fn validate_request(value: decode.Dynamic) -> json.Json {
  query_codec.decode_request(value)
  |> for_javascript
  |> query_codec.encode_request
}

pub fn render_text(value: decode.Dynamic) -> String {
  query_codec.decode_view(value) |> for_javascript |> query.render
}

pub fn cli_request(
  values: decode.Dynamic,
  positionals: decode.Dynamic,
) -> json.Json {
  let invocation = query_codec.decode_cli(values, positionals) |> for_javascript
  json.object([
    #("request", query_codec.encode_request(invocation.request)),
    #("root", json.nullable(invocation.root, json.string)),
    #("json", json.bool(invocation.json)),
    #("rebuild", json.bool(invocation.rebuild)),
  ])
}

pub fn decode_previous(value: decode.Dynamic) -> Option(model.Index) {
  cache_codec.previous(value) |> for_javascript
}

pub fn prepare_refresh(
  previous: Option(model.Index),
  candidates: decode.Dynamic,
  tool_hash: String,
  config_hash: String,
) -> cache.RefreshPlan {
  cache.prepare(
    previous,
    cache_codec.candidates(candidates) |> for_javascript,
    tool_hash,
    config_hash,
  )
}

pub fn parse_jobs(plan: cache.RefreshPlan) -> json.Json {
  cache_codec.encode_jobs(plan)
}

pub fn finish_refresh(
  plan: cache.RefreshPlan,
  results: decode.Dynamic,
) -> json.Json {
  cache.finish(plan, cache_codec.results(results) |> for_javascript)
  |> for_javascript
  |> codec.encode_index
}

pub fn refresh_options(
  root: decode.Dynamic,
  options: decode.Dynamic,
) -> json.Json {
  let options = cache_codec.options(root, options) |> for_javascript
  json.object([
    #("root", json.string(options.root)),
    #("rebuild", json.bool(options.rebuild)),
    #("config", json.nullable(options.config, codec.encode_config)),
  ])
}
