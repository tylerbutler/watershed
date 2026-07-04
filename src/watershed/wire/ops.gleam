//// Codecs for the contents of `"op"` messages: kernel DDS ops in their
//// `{address, contents}` document envelope, attach envelopes carrying a
//// channel snapshot, and the `"summarize"` op announcing a stored snapshot.
////
//// The `{address, contents}` envelope carries no channel type: the channel
//// registry is the authoritative source of a channel's type, so decoding is
//// two-stage. `decode_op_contents` returns attach ops fully decoded (the
//// attach envelope has `channelType`) but channel ops only as
//// `#(address, Dynamic)`; the runtime looks the channel's type up by
//// address and finishes with `channel_op_decoder`.
////
//// The map op format inside the envelope matches TS `@fluidframework/map`
//// ops (`set`/`delete`/`clear`, values wrapped as
//// `{"type": "Plain", "value": ...}`). That is a convenience — it keeps the
//// corpus tests' vocabulary aligned with the TS oracle — not a compatibility
//// contract: nothing external consumes watershed's wire or storage formats
//// yet, so a considered format change needs versioning and fixture updates
//// but no migration shims. Change formats deliberately all the same; that
//// freedom shrinks as soon as real documents or clients exist.

import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}
import gleam/option.{None}

import lattice_core/replica_id
import lattice_maps/crdt
import lattice_maps/or_map
import lattice_sets/or_set
import watershed/channel
import watershed/claims_kernel.{type ClaimOp, Claim}
import watershed/counter_kernel.{type CounterOp, Increment}
import watershed/map_kernel.{type MapOp, Clear, Delete, Set}
import watershed/or_map_kernel.{type OrMapOp}
import watershed/or_set_kernel.{type OrSetOp}
import watershed/register_collection_kernel.{type WriteOp, Write}
import watershed/wire.{type OutboundOp}

/// Contents of a sequenced `"op"`: either a kernel channel op — its payload
/// still undecoded, pending the address → channel-type lookup — or an attach
/// envelope carrying a channel snapshot.
pub type OpContents {
  ChannelOp(address: String, contents: Dynamic)
  AttachOp(address: String, snapshot: channel.Snapshot)
}

/// Wrap a kernel op in the document envelope as an outbound `"op"` message.
pub fn outbound_channel_op(
  address address: String,
  client_sequence_number client_sequence_number: Int,
  reference_sequence_number reference_sequence_number: Int,
  op op: channel.ChannelOp,
) -> OutboundOp {
  wire.OutboundOp(
    client_sequence_number: client_sequence_number,
    reference_sequence_number: reference_sequence_number,
    op_type: "op",
    contents: encode_channel_envelope(address, op),
    metadata: None,
  )
}

/// Attach envelopes carry the full channel snapshot as
/// `{type:"attach", address, channelType, snapshot}`, the `snapshot` payload
/// shaped by the channel type.
pub fn encode_attach(address: String, snapshot: channel.Snapshot) -> Json {
  json.object([
    #("type", json.string("attach")),
    #("address", json.string(address)),
    #(
      "channelType",
      json.string(channel.type_to_string(channel.snapshot_type(snapshot))),
    ),
    #("snapshot", channel.encode_snapshot(snapshot)),
  ])
}

pub fn outbound_attach_op(
  address address: String,
  client_sequence_number client_sequence_number: Int,
  reference_sequence_number reference_sequence_number: Int,
  snapshot snapshot: channel.Snapshot,
) -> OutboundOp {
  wire.OutboundOp(
    client_sequence_number: client_sequence_number,
    reference_sequence_number: reference_sequence_number,
    op_type: "op",
    contents: encode_attach(address, snapshot),
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

/// `{address, contents}` document envelope around a kernel op.
pub fn encode_channel_envelope(address: String, op: channel.ChannelOp) -> Json {
  json.object([
    #("address", json.string(address)),
    #("contents", encode_channel_op(op)),
  ])
}

pub fn encode_channel_op(op: channel.ChannelOp) -> Json {
  case op {
    channel.MapOp(op) -> encode_map_op(op)
    channel.CounterOp(op) -> encode_counter_op(op)
    channel.OrMapOp(op) -> encode_or_map_op(op)
    channel.OrSetOp(op) -> encode_or_set_op(op)
    channel.RegisterCollectionOp(op) -> encode_register_collection_op(op)
    channel.ClaimsOp(op) -> encode_claim_op(op)
  }
}

/// Decoder for a channel op's `contents` payload, selected by the channel's
/// registered type. Stage two of `decode_op_contents`.
pub fn channel_op_decoder(
  channel_type: channel.ChannelType,
) -> Decoder(channel.ChannelOp) {
  case channel_type {
    channel.MapChannel -> map_op_decoder() |> decode.map(channel.MapOp)
    channel.CounterChannel ->
      counter_op_decoder() |> decode.map(channel.CounterOp)
    channel.OrMapChannel -> or_map_op_decoder() |> decode.map(channel.OrMapOp)
    channel.OrSetChannel -> or_set_op_decoder() |> decode.map(channel.OrSetOp)
    channel.RegisterCollectionChannel ->
      register_collection_op_decoder()
      |> decode.map(channel.RegisterCollectionOp)
    channel.ClaimsChannel -> claim_op_decoder() |> decode.map(channel.ClaimsOp)
  }
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

/// `{address, contents}` document envelope around a SharedCounter op.
pub fn encode_counter_envelope(address: String, op: CounterOp) -> Json {
  json.object([
    #("address", json.string(address)),
    #("contents", encode_counter_op(op)),
  ])
}

pub fn encode_counter_op(op: CounterOp) -> Json {
  case op {
    Increment(increment_amount) ->
      json.object([
        #("type", json.string("increment")),
        #("incrementAmount", json.int(increment_amount)),
      ])
  }
}

/// `{address, contents}` document envelope around a SharedOrMap op.
pub fn encode_or_map_envelope(address: String, op: OrMapOp) -> Json {
  json.object([
    #("address", json.string(address)),
    #("contents", encode_or_map_op(op)),
  ])
}

pub fn encode_or_map_op(op: OrMapOp) -> Json {
  case op {
    or_map_kernel.Increment(key, amount, delta) ->
      json.object([
        #("type", json.string("orMapIncrement")),
        #("key", json.string(key)),
        #("amount", json.int(amount)),
        #("delta", delta_json(delta)),
      ])
    or_map_kernel.SetRegister(key, value, timestamp, delta) ->
      json.object([
        #("type", json.string("orMapSet")),
        #("key", json.string(key)),
        #("value", json.string(value)),
        #("timestamp", json.int(timestamp)),
        #("delta", delta_json(delta)),
      ])
    or_map_kernel.Remove(key, delta) ->
      json.object([
        #("type", json.string("orMapRemove")),
        #("key", json.string(key)),
        #("delta", delta_json(delta)),
      ])
  }
}

pub fn encode_or_set_envelope(address: String, op: OrSetOp) -> Json {
  json.object([
    #("address", json.string(address)),
    #("contents", encode_or_set_op(op)),
  ])
}

pub fn encode_or_set_op(op: OrSetOp) -> Json {
  case op {
    or_set_kernel.Add(element, delta) ->
      json.object([
        #("type", json.string("orSetAdd")),
        #("element", json.string(element)),
        #("delta", or_set_delta_json(delta)),
      ])
    or_set_kernel.Remove(element, delta) ->
      json.object([
        #("type", json.string("orSetRemove")),
        #("element", json.string(element)),
        #("delta", or_set_delta_json(delta)),
      ])
  }
}

pub fn encode_register_collection_envelope(
  address: String,
  op: WriteOp,
) -> Json {
  json.object([
    #("address", json.string(address)),
    #("contents", encode_register_collection_op(op)),
  ])
}

pub fn encode_register_collection_op(op: WriteOp) -> Json {
  case op {
    Write(key, value, ref_seq) ->
      json.object([
        #("type", json.string("registerWrite")),
        #("key", json.string(key)),
        #(
          "value",
          json.object([
            #("type", json.string("Plain")),
            #("value", value),
          ]),
        ),
        #("refSeq", json.int(ref_seq)),
      ])
  }
}

pub fn encode_claim_envelope(address: String, op: ClaimOp) -> Json {
  json.object([
    #("address", json.string(address)),
    #("contents", encode_claim_op(op)),
  ])
}

pub fn encode_claim_op(op: ClaimOp) -> Json {
  case op {
    Claim(key, value, ref_seq) ->
      json.object([
        #("type", json.string("claim")),
        #("key", json.string(key)),
        #(
          "value",
          json.object([
            #("type", json.string("Plain")),
            #("value", value),
          ]),
        ),
        #("refSeq", json.int(ref_seq)),
      ])
  }
}

fn delta_json(delta: or_map.ORMapDelta) -> Json {
  json.string(json.to_string(or_map.delta_to_json(delta)))
}

fn or_set_delta_json(delta: or_set.ORSet(String)) -> Json {
  json.string(json.to_string(or_set.to_json(delta)))
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

/// Decode the `contents` of a sequenced `"op"` message into
/// `#(address, CounterOp)`.
pub fn decode_counter_envelope(
  contents: Dynamic,
) -> Result(#(String, CounterOp), List(decode.DecodeError)) {
  decode.run(contents, counter_envelope_decoder())
}

pub fn counter_envelope_decoder() -> Decoder(#(String, CounterOp)) {
  use address <- decode.field("address", decode.string)
  use op <- decode.field("contents", counter_op_decoder())
  decode.success(#(address, op))
}

pub fn counter_op_decoder() -> Decoder(CounterOp) {
  use op_type <- decode.field("type", decode.string)
  case op_type {
    "increment" -> {
      use increment_amount <- decode.field("incrementAmount", decode.int)
      decode.success(Increment(increment_amount))
    }
    _ -> decode.failure(Increment(0), "CounterOp")
  }
}

pub fn or_map_op_decoder() -> Decoder(OrMapOp) {
  use op_type <- decode.field("type", decode.string)
  case op_type {
    "orMapIncrement" -> {
      use key <- decode.field("key", decode.string)
      use amount <- decode.field("amount", decode.int)
      use delta <- decode.field("delta", or_map_delta_decoder())
      decode.success(or_map_kernel.Increment(key, amount, delta))
    }

    "orMapSet" -> {
      use key <- decode.field("key", decode.string)
      use value <- decode.field("value", decode.string)
      use timestamp <- decode.field("timestamp", decode.int)
      use delta <- decode.field("delta", or_map_delta_decoder())
      decode.success(or_map_kernel.SetRegister(key, value, timestamp, delta))
    }
    "orMapRemove" -> {
      use key <- decode.field("key", decode.string)
      use delta <- decode.field("delta", or_map_delta_decoder())
      decode.success(or_map_kernel.Remove(key, delta))
    }
    _ ->
      decode.failure(
        or_map_kernel.Remove("", default_or_map_delta()),
        "OrMapOp",
      )
  }
}

pub fn or_set_op_decoder() -> Decoder(OrSetOp) {
  use op_type <- decode.field("type", decode.string)
  case op_type {
    "orSetAdd" -> {
      use element <- decode.field("element", decode.string)
      use delta <- decode.field("delta", or_set_delta_decoder())
      let op: OrSetOp = or_set_kernel.Add(element, delta)
      decode.success(op)
    }
    "orSetRemove" -> {
      use element <- decode.field("element", decode.string)
      use delta <- decode.field("delta", or_set_delta_decoder())
      let op: OrSetOp = or_set_kernel.Remove(element, delta)
      decode.success(op)
    }
    _ ->
      decode.failure(
        or_set_kernel.Remove("", default_or_set_delta()),
        "OrSetOp",
      )
  }
}

pub fn register_collection_op_decoder() -> Decoder(WriteOp) {
  use op_type <- decode.field("type", decode.string)
  case op_type {
    "registerWrite" -> {
      use key <- decode.field("key", decode.string)
      use value <- decode.field("value", plain_value_decoder())
      use ref_seq <- decode.field("refSeq", decode.int)
      decode.success(Write(key, value, ref_seq))
    }
    _ -> decode.failure(Write("", json.null(), 0), "RegisterCollectionOp")
  }
}

pub fn claim_op_decoder() -> Decoder(ClaimOp) {
  use op_type <- decode.field("type", decode.string)
  case op_type {
    "claim" -> {
      use key <- decode.field("key", decode.string)
      use value <- decode.field("value", plain_value_decoder())
      use ref_seq <- decode.field("refSeq", decode.int)
      decode.success(Claim(key, value, ref_seq))
    }
    _ -> decode.failure(Claim("", json.null(), 0), "ClaimOp")
  }
}

fn or_map_delta_decoder() -> Decoder(or_map.ORMapDelta) {
  use encoded <- decode.then(decode.string)
  case or_map.delta_from_json(encoded) {
    Ok(delta) -> decode.success(delta)
    Error(_) -> decode.failure(default_or_map_delta(), "ORMapDelta")
  }
}

fn default_or_map_delta() -> or_map.ORMapDelta {
  or_map.new(replica_id.new(""), crdt.PnCounterSpec)
  |> or_map.empty_delta
}

fn or_set_delta_decoder() -> Decoder(or_set.ORSet(String)) {
  use encoded <- decode.then(decode.string)
  case or_set.from_json(encoded) {
    Ok(delta) -> decode.success(delta)
    Error(_) -> decode.failure(default_or_set_delta(), "ORSetDelta")
  }
}

fn default_or_set_delta() -> or_set.ORSet(String) {
  or_set.new(replica_id.new(""))
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
      case channel.type_from_string(channel_type) {
        Ok(channel_type) -> {
          use snapshot <- decode.field(
            "snapshot",
            channel.snapshot_decoder(channel_type),
          )
          decode.success(AttachOp(address: address, snapshot: snapshot))
        }
        Error(_) ->
          decode.failure(
            AttachOp(address: "", snapshot: channel.MapSnapshot([])),
            "ChannelType",
          )
      }
    }
    _ ->
      decode.failure(
        AttachOp(address: "", snapshot: channel.MapSnapshot([])),
        "AttachEnvelope",
      )
  }
}

pub fn decode_op_contents(
  contents: Dynamic,
) -> Result(OpContents, List(decode.DecodeError)) {
  // An explicit top-level `type: "attach"` must decode as an attach envelope
  // (no fallback); anything else decodes as the `{address, contents}`
  // envelope, its payload left for stage-two decoding by channel type.
  case decode.run(contents, decode.at(["type"], decode.string)) {
    Ok("attach") -> decode.run(contents, attach_envelope_decoder())
    _ -> decode.run(contents, channel_envelope_decoder())
  }
}

fn channel_envelope_decoder() -> Decoder(OpContents) {
  use address <- decode.field("address", decode.string)
  use contents <- decode.field("contents", decode.dynamic)
  decode.success(ChannelOp(address: address, contents: contents))
}
