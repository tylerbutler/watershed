//// JavaScript API boundary. Core errors become JavaScript exceptions here.

import code_map/codec
import code_map/config
import code_map/model
import gleam/dynamic/decode
import gleam/json
import gleam/option.{None, Some}
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
