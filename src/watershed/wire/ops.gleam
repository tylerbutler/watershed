//// Codecs for the contents of `"op"` messages: kernel map ops in their
//// `{address, contents}` document envelope, attach envelopes carrying a
//// channel snapshot, and the `"summarize"` op announcing a stored snapshot.
////
//// The map op format inside the `{address, contents}` envelope is
//// byte-identical to TS `@fluidframework/map` ops (`set`/`delete`/`clear`,
//// values wrapped as `{"type": "Plain", "value": ...}`).

import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}
import gleam/option.{None}
import gleam/result

import watershed/map_kernel.{type MapOp, Clear, Delete, Set}
import watershed/wire.{type OutboundOp}

/// Contents of a sequenced `"op"`: either a kernel channel op or an attach
/// envelope carrying a channel snapshot.
pub type OpContents {
  ChannelOp(address: String, op: MapOp)
  AttachOp(
    address: String,
    channel_type: String,
    snapshot: List(#(String, Json)),
  )
}

/// Wrap a kernel op in the document envelope as an outbound `"op"` message.
pub fn outbound_map_op(
  address address: String,
  client_sequence_number client_sequence_number: Int,
  reference_sequence_number reference_sequence_number: Int,
  op op: MapOp,
) -> OutboundOp {
  wire.OutboundOp(
    client_sequence_number: client_sequence_number,
    reference_sequence_number: reference_sequence_number,
    op_type: "op",
    contents: encode_map_envelope(address, op),
    metadata: None,
  )
}

/// Attach envelopes carry the full channel snapshot as
/// `{type:"attach", address, channelType, snapshot}`.
pub fn encode_attach(
  address: String,
  channel_type: String,
  snapshot: List(#(String, Json)),
) -> Json {
  json.object([
    #("type", json.string("attach")),
    #("address", json.string(address)),
    #("channelType", json.string(channel_type)),
    #("snapshot", wire.encode_entries(snapshot)),
  ])
}

pub fn outbound_attach_op(
  address address: String,
  client_sequence_number client_sequence_number: Int,
  reference_sequence_number reference_sequence_number: Int,
  snapshot snapshot: List(#(String, Json)),
) -> OutboundOp {
  wire.OutboundOp(
    client_sequence_number: client_sequence_number,
    reference_sequence_number: reference_sequence_number,
    op_type: "op",
    contents: encode_attach(address, wire.channel_type_map, snapshot),
    metadata: None,
  )
}

/// A `"summarize"` op announcing a stored snapshot. Contents carry the fields
/// the server's `validate_summarize_contents` requires: `handle` (storage
/// handle for the snapshot), `message` (commit message), `parents` (parent
/// summary handles), and `head` (the git tree SHA the client uploaded). We set
/// `handle == head` so a loading client can fetch the tree directly by handle.
pub fn outbound_summarize_op(
  client_sequence_number client_sequence_number: Int,
  reference_sequence_number reference_sequence_number: Int,
  handle handle: String,
  message message: String,
  parents parents: List(String),
  head head: String,
) -> OutboundOp {
  wire.OutboundOp(
    client_sequence_number: client_sequence_number,
    reference_sequence_number: reference_sequence_number,
    op_type: "summarize",
    contents: json.object([
      #("handle", json.string(handle)),
      #("message", json.string(message)),
      #("parents", json.array(parents, json.string)),
      #("head", json.string(head)),
    ]),
    metadata: None,
  )
}

/// `{address, contents}` document envelope around a map op.
pub fn encode_map_envelope(address: String, op: MapOp) -> Json {
  json.object([
    #("address", json.string(address)),
    #("contents", encode_map_op(op)),
  ])
}

pub fn encode_map_op(op: MapOp) -> Json {
  case op {
    Set(key, value) ->
      json.object([
        #("type", json.string("set")),
        #("key", json.string(key)),
        #(
          "value",
          json.object([
            #("type", json.string("Plain")),
            #("value", value),
          ]),
        ),
      ])
    Delete(key) ->
      json.object([
        #("type", json.string("delete")),
        #("key", json.string(key)),
      ])
    Clear -> json.object([#("type", json.string("clear"))])
  }
}

/// Decode the `contents` of a sequenced `"op"` message into
/// `#(address, MapOp)`.
pub fn decode_map_envelope(
  contents: Dynamic,
) -> Result(#(String, MapOp), List(decode.DecodeError)) {
  decode.run(contents, map_envelope_decoder())
}

pub fn map_envelope_decoder() -> Decoder(#(String, MapOp)) {
  use address <- decode.field("address", decode.string)
  use op <- decode.field("contents", map_op_decoder())
  decode.success(#(address, op))
}

pub fn map_op_decoder() -> Decoder(MapOp) {
  use op_type <- decode.field("type", decode.string)
  case op_type {
    "set" -> {
      use key <- decode.field("key", decode.string)
      use value <- decode.field("value", plain_value_decoder())
      decode.success(Set(key, value))
    }
    "delete" -> {
      use key <- decode.field("key", decode.string)
      decode.success(Delete(key))
    }
    "clear" -> decode.success(Clear)
    _ -> decode.failure(Clear, "MapOp")
  }
}

/// `Plain` values carry an opaque kernel `Json` payload. Handle-like markers
/// (e.g., `{"type":"Shared", ...}`) are not interpreted here — they must be
/// materialized by the full runtime. We only accept `Plain` markers.
fn plain_value_decoder() -> Decoder(Json) {
  use value_type <- decode.field("type", decode.string)
  case value_type {
    "Plain" -> decode.field("value", wire.json_value_decoder(), decode.success)
    _ -> decode.failure(json.null(), "PlainValue")
  }
}

pub fn attach_envelope_decoder() -> Decoder(OpContents) {
  use t <- decode.field("type", decode.string)
  case t {
    "attach" -> {
      use address <- decode.field("address", decode.string)
      use channel_type <- decode.field("channelType", decode.string)
      case channel_type == wire.channel_type_map {
        True -> {
          use snapshot <- decode.field(
            "snapshot",
            decode.list(wire.entry_decoder()),
          )
          decode.success(AttachOp(
            address: address,
            channel_type: channel_type,
            snapshot: snapshot,
          ))
        }
        False ->
          decode.failure(
            AttachOp(address: "", channel_type: "", snapshot: []),
            "ChannelType",
          )
      }
    }
    _ ->
      decode.failure(
        AttachOp(address: "", channel_type: "", snapshot: []),
        "AttachEnvelope",
      )
  }
}

pub fn decode_op_contents(
  contents: Dynamic,
) -> Result(OpContents, List(decode.DecodeError)) {
  // An explicit top-level `type: "attach"` must decode as an attach envelope
  // (no fallback); anything else decodes as the map envelope.
  case decode.run(contents, decode.at(["type"], decode.string)) {
    Ok("attach") -> decode.run(contents, attach_envelope_decoder())
    _ ->
      decode.run(contents, map_envelope_decoder())
      |> result.map(fn(pair) { ChannelOp(pair.0, pair.1) })
  }
}
