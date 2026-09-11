//// Wire metadata for independent OR-map test oracles. No native joins.

import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/string
import watershed/canonical_json

pub type Generation =
  #(Int, Option(String))

pub type Entry {
  Entry(
    key: String,
    generation: Generation,
    membership: String,
    value: Option(String),
  )
}

pub fn generation_decoder() -> decode.Decoder(Generation) {
  use clock <- decode.field("clock", decode.int)
  use creator <- decode.field("creator", decode.optional(decode.string))
  decode.success(#(clock, creator))
}

pub fn entries_decoder() -> decode.Decoder(List(Entry)) {
  decode.at(
    ["state", "entries"],
    decode.list({
      use key <- decode.field("key", decode.string)
      use generation <- decode.field("generation", generation_decoder())
      use membership <- decode.field("membership", decode.string)
      use value <- decode.field("value", decode.optional(decode.string))
      decode.success(Entry(key, generation, membership, value))
    }),
  )
}

pub fn compare(left: Generation, right: Generation) -> order.Order {
  case int.compare(left.0, right.0) {
    order.Eq ->
      case left.1, right.1 {
        None, None -> order.Eq
        None, Some(_) -> order.Lt
        Some(_), None -> order.Gt
        Some(a), Some(b) -> canonical_json.compare(a, b)
      }
    other -> other
  }
}

pub fn generation_json(generation: Generation) -> json.Json {
  json.object([
    #("clock", json.int(generation.0)),
    #("creator", case generation.1 {
      None -> json.null()
      Some(creator) -> json.string(creator)
    }),
  ])
}

fn frame(value: String) -> String {
  int.to_string(string.byte_size(value)) <> ":" <> value
}

pub fn membership_author(
  author: String,
  key: String,
  generation: Generation,
) -> String {
  let suffix = case generation.1 {
    None -> frame("initial")
    Some(creator) ->
      frame("generation")
      <> frame(int.to_string(generation.0))
      <> frame(creator)
  }
  "lattice-map:"
  <> frame(author)
  <> frame("or-membership")
  <> frame(key)
  <> suffix
}

pub fn leaf(encoded: String) -> String {
  let assert Ok(payload) =
    json.parse(encoded, {
      use kind <- decode.then(decode.at(["state", "kind"], decode.string))
      use payload <- decode.then(decode.at(["state", "payload"], decode.string))
      case kind {
        "state" -> decode.success(payload)
        _ -> decode.failure("", "complete leaf state delta")
      }
    })
  payload
}
