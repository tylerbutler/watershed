//// Shared primitives for watershed's Fluid-compatible document-channel
//// payloads.
////
//// The types come from `spillway/types` and `spillway/message`, so the client
//// and the server cannot drift apart. watershed owns the JSON codecs only.
//// Those codecs are in submodules, one for each vocabulary:
////
//// - `wire/socket` — connection-level frames and spillway envelope codecs
//// - `wire/op` — operation contents: channel operations, attach envelopes,
////   summarize operations
//// - `wire/summary_blob` — the versioned summary storage format
////
//// This module holds only what those vocabularies share.

import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

/// An operation that a client wrote, ready for `submitOp`. It has the same
/// fields that the `submitCore` function of the TypeScript driver puts on the
/// wire. `wire/op` constructs it, and `wire/socket` serializes it.
pub type OutboundOperation {
  OutboundOperation(
    client_sequence_number: Int,
    reference_sequence_number: Int,
    operation_type: String,
    contents: Json,
    metadata: Option(Json),
  )
}

/// The wire names of the channel types that watershed uses. These are the
/// `channelType` field of the attach envelope and the `type` field of the
/// summary blob. The map tag is one member of that set.
pub const channel_type_map = "map"

pub const channel_type_counter = "counter"

pub const channel_type_pn_counter = "pnCounter"

pub const channel_type_or_map = "ormap"

pub const channel_type_or_set = "orset"

pub const channel_type_g_set = "g-set"

pub const channel_type_two_p_set = "two-p-set"

pub const channel_type_register_collection = "registerCollection"

pub const channel_type_claims = "claims"

pub const channel_type_task_manager = "taskManager"

pub const channel_type_pact_map = "pactMap"

pub const channel_type_ordered_collection = "orderedCollection"

pub const channel_type_json_ot = "json0"

pub const channel_type_directory = "directory"

pub const channel_type_sequence = "sequence"

pub const channel_type_rich_text = "richText"

pub const channel_type_text = "text"

/// Encode the map entries as the ordered `[{key, value}]` array. An attach
/// snapshot and a summary blob channel both use that array.
pub fn encode_entries(entries: List(#(String, Json))) -> Json {
  json.array(entries, fn(entry) {
    json.object([#("key", json.string(entry.0)), #("value", entry.1)])
  })
}

/// Decode one `{key, value}` map entry.
pub fn entry_decoder() -> Decoder(#(String, Json)) {
  use key <- decode.field("key", decode.string)
  use value <- decode.field("value", json_value_decoder())
  decode.success(#(key, value))
}

/// Decode a parsed-JSON `Dynamic` value back into a `Json` value. The decoded
/// operation contents can then go into the kernel, which stores each value as
/// `Json`.
pub fn json_value_decoder() -> Decoder(Json) {
  let non_null =
    decode.one_of(decode.string |> decode.map(json.string), or: [
      decode.bool |> decode.map(json.bool),
      decode.int |> decode.map(json.int),
      decode.float |> decode.map(json.float),
      decode.list(decode.recursive(json_value_decoder))
        |> decode.map(json.preprocessed_array),
      decode.dict(decode.string, decode.recursive(json_value_decoder))
        |> decode.map(fn(object) { json.object(dict.to_list(object)) }),
    ])
  decode.optional(non_null)
  |> decode.map(fn(value) {
    case value {
      Some(inner) -> inner
      None -> json.null()
    }
  })
}

/// `json_value_decoder` as a plain function. A value that the decoder cannot
/// read becomes null.
pub fn dynamic_to_json(value: Dynamic) -> Json {
  case decode.run(value, json_value_decoder()) {
    Ok(decoded) -> decoded
    Error(_) -> json.null()
  }
}

type ComparableJson {
  ComparableNull
  ComparableBool(Bool)
  ComparableString(String)
  ComparableNumber(Float)
  ComparableInteger(Int)
  ComparableArray(List(ComparableJson))
  ComparableObject(List(#(String, ComparableJson)))
}

const max_safe_json_integer = 9_007_199_254_740_991

const min_safe_json_integer = -9_007_199_254_740_991

/// Compare two JSON values by their data, and not by their encoded text. The
/// comparison ignores the object key order. A safe integral float is equal to
/// the same integer, so the number normalization of JavaScript cannot break an
/// echo.
pub fn json_semantically_equal(ours: Json, echoed: Json) -> Bool {
  case
    json.parse(json.to_string(ours), comparable_json_decoder()),
    json.parse(json.to_string(echoed), comparable_json_decoder())
  {
    Ok(ours), Ok(echoed) -> ours == echoed
    _, _ -> False
  }
}

fn comparable_json_decoder() -> Decoder(ComparableJson) {
  let non_null =
    decode.one_of(decode.string |> decode.map(ComparableString), or: [
      decode.bool |> decode.map(ComparableBool),
      decode.int
        |> decode.map(fn(value) {
          case
            value >= min_safe_json_integer && value <= max_safe_json_integer
          {
            True -> ComparableNumber(int.to_float(value))
            False -> ComparableInteger(value)
          }
        }),
      decode.float |> decode.map(ComparableNumber),
      decode.list(decode.recursive(comparable_json_decoder))
        |> decode.map(ComparableArray),
      decode.dict(decode.string, decode.recursive(comparable_json_decoder))
        |> decode.map(fn(object) {
          ComparableObject(
            object
            |> dict.to_list
            |> list.sort(fn(a, b) { string.compare(a.0, b.0) }),
          )
        }),
    ])
  decode.optional(non_null)
  |> decode.map(fn(value) {
    case value {
      Some(inner) -> inner
      None -> ComparableNull
    }
  })
}
