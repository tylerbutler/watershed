import gleam/dict
import gleam/json.{type Json}
import gleam/dynamic/decode
import gleam/list
import gleam/option.{type Option, None, Some}
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

pub fn parse_handle(value: Json) -> Result(String, Nil) {
  // Parse as a dict with string values and enforce exact keys.
  case
    json.parse(json.to_string(value), decode.dict(decode.string, decode.string))
  {
    Ok(obj) -> {
      let pairs = dict.to_list(obj)
      case list.length(pairs) == 2 {
        True ->
          case dict.get(obj, "type") {
            Ok(t) ->
              case t == fluid_handle_type {
                True ->
                  case dict.get(obj, "url") {
                    Ok(u) ->
                      case single_segment_url(u) {
                        Some(addr) -> Ok(addr)
                        None -> Error(Nil)
                      }
                    Error(_) -> Error(Nil)
                  }
                False -> Error(Nil)
              }
            Error(_) -> Error(Nil)
          }
        False -> Error(Nil)
      }
    }
    Error(_) -> Error(Nil)
  }
}

fn collect_decoder() -> decode.Decoder(List(String)) {
  // Try to decode a handle marker object first:
  let marker =
    decode.dict(decode.string, decode.string)
    |> decode.map(fn(obj) {
      let pairs = dict.to_list(obj)
      case list.length(pairs) == 2 {
        True ->
          case dict.get(obj, "type") {
            Ok(t) ->
              case t == fluid_handle_type {
                True ->
                  case dict.get(obj, "url") {
                    Ok(u) ->
                      case single_segment_url(u) {
                        Some(addr) -> [addr]
                        None -> []
                      }
                    Error(_) -> []
                  }
                False -> []
              }
            Error(_) -> []
          }
        False -> []
      }
    })

  let non_null =
    decode.one_of(marker, or: [
      decode.string |> decode.map(fn(_) { [] }),
      decode.bool |> decode.map(fn(_) { [] }),
      decode.int |> decode.map(fn(_) { [] }),
      decode.float |> decode.map(fn(_) { [] }),
      decode.list(decode.recursive(collect_decoder))
        |> decode.map(fn(lists) { list.flatten(lists) }),
      decode.dict(decode.string, decode.recursive(collect_decoder))
        |> decode.map(fn(object) {
          // `object` is a dict.Dict(String, List(String)) — flatten its values.
          let pairs = dict.to_list(object)
          let lists = list.map(pairs, fn(pair) { pair.1 })
          list.flatten(lists)
        }),
    ])

  decode.optional(non_null)
  |> decode.map(fn(value) {
    case value {
      Some(inner) -> inner
      None -> []
    }
  })
}

pub fn collect_handle_addresses(value: Json) -> List(String) {
  case json.parse(json.to_string(value), decode.dynamic) {
    Ok(dynamic_value) ->
      case decode.run(dynamic_value, collect_decoder()) {
        Ok(list_all) ->
          list.fold(list_all, [], fn(acc, addr) {
            case list.any(acc, fn(x) { x == addr }) {
              True -> acc
              False -> list.append(acc, [addr])
            }
          })
        Error(_) -> []
      }
    Error(_) -> []
  }
}
