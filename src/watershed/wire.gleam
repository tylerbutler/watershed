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
import gleam/json.{type Json}
import gleam/option.{type Option, None, Some}

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

pub const channel_type_or_map = "ormap"

pub const channel_type_or_set = "orset"

pub const channel_type_g_set = "g-set"

pub const channel_type_two_p_set = "two-p-set"

pub const channel_type_register_collection = "registerCollection"

pub const channel_type_claims = "claims"

pub const channel_type_task_manager = "taskManager"

pub const channel_type_json_ot = "json0"

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
