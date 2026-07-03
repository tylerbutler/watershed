import gleam/dict
import gleam/dynamic/decode
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub const fluid_handle_type = "__fluid_handle__"

pub fn handle_url(address: String) -> String {
  "/" <> address
}

pub fn encode_handle(address: String) -> Json {
  json.object([
    #("type", json.string(fluid_handle_type)),
    #("url", json.string(handle_url(address))),
  ])
}

fn single_segment_url(url: String) -> Option(String) {
  // Accept only URLs like "/address" with no additional `/` characters.
  let len = string.length(url)
  case
    {
      len > 1
      && string.slice(url, 0, 1) == "/"
      && !string.contains(string.slice(url, 1, len), "/")
    }
  {
    True -> Some(string.slice(url, 1, len))
    False -> None
  }
}

/// Decode a handle marker — exactly `{type: fluid_handle_type, url: "/addr"}`
/// with a single-segment url and no extra keys — to its address.
fn marker_decoder() -> decode.Decoder(String) {
  use obj <- decode.then(decode.dict(decode.string, decode.string))
  let address = case dict.size(obj) == 2 {
    True ->
      case dict.get(obj, "type"), dict.get(obj, "url") {
        Ok(t), Ok(url) if t == fluid_handle_type -> single_segment_url(url)
        _, _ -> None
      }
    False -> None
  }
  case address {
    Some(address) -> decode.success(address)
    None -> decode.failure("", "HandleMarker")
  }
}

pub fn parse_handle(value: Json) -> Result(String, Nil) {
  json.parse(json.to_string(value), marker_decoder())
  |> result.replace_error(Nil)
}

fn collect_decoder() -> decode.Decoder(List(String)) {
  let non_null =
    decode.one_of(marker_decoder() |> decode.map(fn(addr) { [addr] }), or: [
      decode.string |> decode.map(fn(_) { [] }),
      decode.bool |> decode.map(fn(_) { [] }),
      decode.int |> decode.map(fn(_) { [] }),
      decode.float |> decode.map(fn(_) { [] }),
      decode.list(decode.recursive(collect_decoder))
        |> decode.map(list.flatten),
      decode.dict(decode.string, decode.recursive(collect_decoder))
        |> decode.map(fn(object) { dict.values(object) |> list.flatten }),
    ])
  decode.optional(non_null)
  |> decode.map(option.unwrap(_, []))
}

pub fn collect_handle_addresses(value: Json) -> List(String) {
  case json.parse(json.to_string(value), collect_decoder()) {
    Ok(addresses) -> list.unique(addresses)
    Error(_) -> []
  }
}
