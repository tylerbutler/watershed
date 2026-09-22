import gleam/dict
import gleam/dynamic/decode
import gleam/json.{type Json}
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import gleam/uri

pub const fluid_handle_type = "__fluid_handle__"

pub type HandleError {
  InvalidHandle(detail: String)
  UnsupportedHandle(detail: String)
}

pub fn handle_url(address: String) -> String {
  "/" <> address
}

pub fn encode_handle(address: String) -> Json {
  json.object([
    #("type", json.string(fluid_handle_type)),
    #("url", json.string(handle_url(address))),
  ])
}

/// The one path segment of a handle URL. The result is `Error(Nil)` for a URL
/// that is not exactly `"/address"`.
fn single_segment_url(url: String) -> Result(String, Nil) {
  let length = string.length(url)
  case
    length > 1
    && string.slice(url, 0, 1) == "/"
    && !string.contains(string.slice(url, 1, length), "/")
  {
    True -> Ok(string.slice(url, 1, length))
    False -> Error(Nil)
  }
}

/// Decode a handle marker to its address. A marker is exactly
/// `{type: fluid_handle_type, url: "/address"}`. The url must have one segment,
/// and the object must have no other keys.
fn marker_decoder() -> decode.Decoder(String) {
  use object <- decode.then(decode.dict(decode.string, decode.string))
  let address = case dict.size(object) == 2 {
    True ->
      case dict.get(object, "type"), dict.get(object, "url") {
        Ok(marker_type), Ok(url) if marker_type == fluid_handle_type ->
          single_segment_url(url)
        _, _ -> Error(Nil)
      }
    False -> Error(Nil)
  }
  case address {
    Ok(address) -> decode.success(address)
    Error(Nil) -> decode.failure("", "HandleMarker")
  }
}

pub fn parse_handle(value: Json) -> Result(String, Nil) {
  json.parse(json.to_string(value), marker_decoder())
  |> result.replace_error(Nil)
}

fn contextual_marker_decoder() -> decode.Decoder(#(String, Bool)) {
  use object <- decode.then(decode.dict(decode.string, decode.dynamic))
  use marker_type <- decode.field("type", decode.string)
  use url <- decode.field("url", decode.string)
  let pending = dict.has_key(object, "payloadPending")
  case marker_type == fluid_handle_type {
    True -> decode.success(#(url, pending))
    False -> decode.failure(#("", False), "Fluid handle marker")
  }
}

pub fn resolve_path(
  value: Json,
  context_path: String,
) -> Result(String, HandleError) {
  use #(url, pending) <- result.try(
    json.parse(json.to_string(value), contextual_marker_decoder())
    |> result.map_error(fn(_) { InvalidHandle("invalid handle marker") }),
  )
  use _ <- result.try(case pending {
    True -> Error(UnsupportedHandle("pending handle payload"))
    False -> Ok(Nil)
  })
  case string.starts_with(url, "/") {
    True -> validate_path(url, True)
    False -> {
      use context <- result.try(validate_path(context_path, True))
      use relative <- result.try(validate_path(url, False))
      let absolute = case context {
        "/" -> "/" <> relative
        _ -> context <> "/" <> relative
      }
      validate_path(absolute, True)
    }
  }
}

pub fn encode_path(absolute_path: String) -> Result(Json, HandleError) {
  use path <- result.try(validate_path(absolute_path, True))
  Ok(
    json.object([
      #("type", json.string(fluid_handle_type)),
      #("url", json.string(path)),
    ]),
  )
}

fn validate_path(path: String, absolute: Bool) -> Result(String, HandleError) {
  use _ <- result.try(case path == "" {
    True -> Error(InvalidHandle("empty handle path"))
    False -> Ok(Nil)
  })
  use _ <- result.try(
    case
      string.contains(path, "?")
      || string.contains(path, "#")
      || string.contains(path, "\\")
      || string.contains(path, "://")
      || string.starts_with(path, "//")
    {
      True -> Error(InvalidHandle("external handle path"))
      False -> Ok(Nil)
    },
  )
  use _ <- result.try(case absolute == string.starts_with(path, "/") {
    True -> Ok(Nil)
    False -> Error(InvalidHandle("wrong handle path context"))
  })
  case path == "/" {
    True -> Ok(path)
    False -> {
      let components = case absolute {
        True -> string.drop_start(path, 1) |> string.split("/")
        False -> string.split(path, "/")
      }
      use _ <- result.try(case components {
        [] -> Error(InvalidHandle("empty handle path"))
        _ ->
          list.try_each(components, fn(component) {
            use decoded <- result.try(
              uri.percent_decode(component)
              |> result.map_error(fn(_) { InvalidHandle("invalid path escape") }),
            )
            case
              component == ""
              || decoded == "."
              || decoded == ".."
              || decoded == "/"
              || string.contains(component, ":")
            {
              True -> Error(InvalidHandle("invalid path component"))
              False -> Ok(Nil)
            }
          })
      })
      Ok(path)
    }
  }
}

fn collect_decoder() -> decode.Decoder(List(String)) {
  let non_null =
    decode.one_of(
      marker_decoder() |> decode.map(fn(address) { [address] }),
      or: [
        decode.string |> decode.map(fn(_) { [] }),
        decode.bool |> decode.map(fn(_) { [] }),
        decode.int |> decode.map(fn(_) { [] }),
        decode.float |> decode.map(fn(_) { [] }),
        decode.list(decode.recursive(collect_decoder))
          |> decode.map(list.flatten),
        decode.dict(decode.string, decode.recursive(collect_decoder))
          |> decode.map(fn(object) { dict.values(object) |> list.flatten }),
      ],
    )
  decode.optional(non_null)
  |> decode.map(option.unwrap(_, []))
}

pub fn collect_handle_addresses(value: Json) -> List(String) {
  case json.parse(json.to_string(value), collect_decoder()) {
    Ok(addresses) -> list.unique(addresses)
    Error(_) -> []
  }
}
