//// Shared primitives for watershed's Fluid-compatible document-channel
//// payloads.
////
//// Types are reused from `spillway/types` and `spillway/message` so the
//// client and server can't drift; watershed only owns the JSON codecs.
//// Those live in submodules, split by vocabulary:
////
//// - `wire/socket` — connection-level frames and spillway envelope codecs
//// - `wire/ops` — op contents: channel ops, attach envelopes, summarize ops
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

/// A client-authored op ready for `submitOp`. Mirrors the fields the TS
/// driver's `submitCore` puts on the wire. Constructed by `wire/ops`,
/// serialized by `wire/socket`.
pub type OutboundOp {
  OutboundOp(
    client_sequence_number: Int,
    reference_sequence_number: Int,
    op_type: String,
    contents: Json,
    metadata: Option(Json),
  )
}

/// Wire names for the channel types watershed speaks (the attach envelope's
/// and summary blob's `channelType`/`type` fields).
/// The map tag is one variant in that multi-channel set.
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

/// Encode map entries as the ordered `[{key, value}]` array shared by attach
/// snapshots and summary blob channels.
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

/// Decode any parsed-JSON `Dynamic` back into a `Json` value, so decoded op
/// contents can flow into the kernel (which stores values as `Json`).
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

/// `json_value_decoder` as a plain function; undecodable values become null.
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

/// Compare JSON values by their data semantics rather than their encoded
/// spelling. Object key order is ignored, and safe integral floats compare
/// equal to integers so JavaScript number normalization cannot break echoes.
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
