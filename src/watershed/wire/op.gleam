//// DDS codecs inside routed Fluid container envelopes.
////
//// Channel operations carry no type. The runtime selects the payload decoder
//// from its checked registry. Attach messages carry channel attributes and
//// snapshot blobs. The SharedMap codec uses upstream Plain values. Other
//// existing DDSes retain their native payloads and Watershed type identifiers.
////
//// The summarize operation still publishes the native non-tree summary.

import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string

import lattice_core/replica_id
import lattice_core/version_vector
import lattice_counters/g_counter
import lattice_counters/pn_counter
import lattice_maps/crdt
import lattice_maps/lww_map
import lattice_maps/or_map
import lattice_registers/lww_register
import lattice_registers/mv_register
import lattice_sequence/sequence
import lattice_sets/g_set
import lattice_sets/or_set
import lattice_sets/two_p_set
import lattice_text/text
import watershed/channel
import watershed/claims_kernel.{type ClaimOperation, Claim}
import watershed/counter_kernel.{type CounterOperation, Increment}
import watershed/directory_kernel.{type DirectoryOperation}
import watershed/g_counter_kernel.{type GCounterOperation}
import watershed/g_set_kernel.{type GSetOperation}
import watershed/json_ot
import watershed/json_ot_kernel.{type JsonOtWireOperation, JsonOtWireOperation}
import watershed/lww_map_kernel.{type LwwMapOperation}
import watershed/lww_register_kernel.{type LwwRegisterOperation}
import watershed/map_kernel.{type MapOperation, Clear, Delete, Set}
import watershed/mv_register_kernel.{type MvRegisterOperation}
import watershed/or_map_kernel.{type OrMapOperation}
import watershed/or_map_set_leaf
import watershed/or_set_kernel.{type OrSetOperation}
import watershed/ordered_collection_kernel.{type OrderedOperation}
import watershed/pact_map_kernel
import watershed/pn_counter_kernel.{type PnCounterOperation}
import watershed/register_collection_kernel.{type WriteOperation, Write}
import watershed/rich_text
import watershed/rich_text_kernel.{
  type RichTextWireOperation, RichTextWireOperation,
}
import watershed/sequence_kernel.{type SequenceOperation}
import watershed/task_manager_kernel.{type TaskManagerOperation}
import watershed/text_kernel.{type TextOperation}
import watershed/two_p_set_kernel.{type TwoPSetOperation}
import watershed/wire.{type OutboundOperation}
import watershed/wire/fluid_container
import watershed/wire/json_object
import watershed/wire/socket

/// The contents of a sequenced `"op"` message. The contents are a kernel
/// channel operation, whose payload is not decoded yet because the
/// address-to-channel-type lookup must run first. Or the contents are an attach
/// envelope, which carries a channel snapshot.
pub type OperationContents {
  ChannelOperation(address: String, contents: Dynamic)
  AttachOperation(address: String, snapshot: channel.Snapshot)
}

/// Wrap a kernel operation in the document envelope as an outbound `"op"`
/// message.
pub fn outbound_channel_operation(
  address address: String,
  client_sequence_number client_sequence_number: Int,
  reference_sequence_number reference_sequence_number: Int,
  operation operation: channel.ChannelOperation,
) -> Result(OutboundOperation, fluid_container.ContainerError) {
  use contents <- result.try(encode_channel_envelope(address, operation))
  Ok(wire.OutboundOperation(
    client_sequence_number: client_sequence_number,
    reference_sequence_number: reference_sequence_number,
    operation_type: "op",
    contents: contents,
    metadata: None,
  ))
}

/// Encode a routed channel attach with attributes and a header blob.
pub fn encode_attach(
  address: String,
  snapshot: channel.Snapshot,
) -> Result(Json, fluid_container.ContainerError) {
  use route <- result.try(fluid_container.route_from_path("/" <> address))
  let kind = channel.snapshot_type(snapshot)
  let attributes = channel.fluid_attributes(kind)
  let blobs = case snapshot {
    channel.MapSnapshot(entries) -> encode_map_attach_blobs(entries)
    _ -> [attach_blob("header", channel.encode_snapshot(snapshot))]
  }
  let snapshot =
    json.object([
      #(
        "entries",
        json.preprocessed_array([
          attach_blob(".attributes", attributes),
          ..blobs
        ]),
      ),
    ])
  fluid_container.encode(fluid_container.ChannelAttach(
    route,
    channel.fluid_type_to_string(kind),
    snapshot,
  ))
}

fn attach_blob(path: String, contents: Json) -> Json {
  json.object([
    #("path", json.string(path)),
    #("mode", json.string("100644")),
    #("type", json.string("Blob")),
    #(
      "value",
      json.object([
        #("contents", json.string(json.to_string(contents))),
        #("encoding", json.string("utf-8")),
      ]),
    ),
  ])
}

pub fn outbound_attach_operation(
  address address: String,
  client_sequence_number client_sequence_number: Int,
  reference_sequence_number reference_sequence_number: Int,
  snapshot snapshot: channel.Snapshot,
) -> Result(OutboundOperation, fluid_container.ContainerError) {
  use contents <- result.try(encode_attach(address, snapshot))
  Ok(wire.OutboundOperation(
    client_sequence_number: client_sequence_number,
    reference_sequence_number: reference_sequence_number,
    operation_type: "op",
    contents: contents,
    metadata: None,
  ))
}

/// A `"summarize"` operation that announces a stored snapshot. The contents
/// carry the fields that the server needs. `handle` is the staged tree SHA.
/// `head` is the current published commit SHA, or an empty string for the first
/// summary. `parents` is empty for the first summary and otherwise contains
/// only `head`.
pub fn outbound_summarize_operation(
  client_sequence_number client_sequence_number: Int,
  reference_sequence_number reference_sequence_number: Int,
  handle handle: String,
  message message: String,
  parents parents: List(String),
  head head: String,
) -> OutboundOperation {
  wire.OutboundOperation(
    client_sequence_number: client_sequence_number,
    reference_sequence_number: reference_sequence_number,
    operation_type: "summarize",
    contents: json.object([
      #("handle", json.string(handle)),
      #("message", json.string(message)),
      #("parents", json.array(parents, json.string)),
      #("head", json.string(head)),
    ]),
    metadata: None,
  )
}

/// The routed Fluid container envelope around a kernel operation.
pub fn encode_channel_envelope(
  address: String,
  operation: channel.ChannelOperation,
) -> Result(Json, fluid_container.ContainerError) {
  use route <- result.try(fluid_container.route_from_path("/" <> address))
  fluid_container.encode(fluid_container.ChannelOperation(
    route,
    encode_channel_operation(operation),
  ))
}

pub fn encode_channel_operation(operation: channel.ChannelOperation) -> Json {
  case operation {
    channel.MapOperation(operation) -> encode_map_operation(operation)
    channel.CounterOperation(operation) -> encode_counter_operation(operation)
    channel.PnCounterOperation(operation) ->
      encode_pn_counter_operation(operation)
    channel.GCounterOperation(operation) ->
      encode_g_counter_operation(operation)
    channel.MvRegisterOperation(operation) ->
      encode_mv_register_operation(operation)
    channel.LwwRegisterOperation(operation) ->
      encode_lww_register_operation(operation)
    channel.LwwMapOperation(operation) -> encode_lww_map_operation(operation)
    channel.OrMapOperation(operation) -> encode_or_map_operation(operation)
    channel.OrSetOperation(operation) -> encode_or_set_operation(operation)
    channel.GSetOperation(operation) -> encode_g_set_operation(operation)
    channel.TwoPSetOperation(operation) -> encode_two_p_set_operation(operation)
    channel.RegisterCollectionOperation(operation) ->
      encode_register_collection_operation(operation)
    channel.ClaimsOperation(operation) -> encode_claim_operation(operation)
    channel.TaskManagerOperation(operation) ->
      encode_task_manager_operation(operation)
    channel.JsonOtOperation(operation) -> encode_json_ot_operation(operation)
    channel.DirectoryOperation(operation, message_id) ->
      encode_directory_operation(operation, message_id)
    channel.PactMapOperation(operation) -> encode_pact_map_operation(operation)
    channel.OrderedCollectionOperation(operation) ->
      encode_ordered_operation(operation)
    channel.SequenceOperation(operation) -> encode_sequence_operation(operation)
    channel.RichTextOperation(operation) ->
      encode_rich_text_operation(operation)
    channel.TextOperation(operation) -> encode_text_operation(operation)
  }
}

/// The decoder for the `contents` payload of a channel operation. The
/// registered type of the channel selects it. This is stage two of
/// `decode_operation_contents`.
pub fn channel_operation_decoder(
  channel_type: channel.ChannelType,
) -> Decoder(channel.ChannelOperation) {
  case channel_type {
    channel.MapChannel ->
      map_operation_decoder() |> decode.map(channel.MapOperation)
    channel.CounterChannel ->
      counter_operation_decoder() |> decode.map(channel.CounterOperation)
    channel.PnCounterChannel ->
      pn_counter_operation_decoder() |> decode.map(channel.PnCounterOperation)
    channel.GCounterChannel ->
      g_counter_operation_decoder() |> decode.map(channel.GCounterOperation)
    channel.MvRegisterChannel ->
      mv_register_operation_decoder() |> decode.map(channel.MvRegisterOperation)
    channel.LwwRegisterChannel ->
      lww_register_operation_decoder()
      |> decode.map(channel.LwwRegisterOperation)
    channel.LwwMapChannel ->
      lww_map_operation_decoder()
      |> decode.map(channel.LwwMapOperation)
    channel.OrMapChannel ->
      or_map_operation_decoder() |> decode.map(channel.OrMapOperation)
    channel.OrSetChannel ->
      or_set_operation_decoder() |> decode.map(channel.OrSetOperation)
    channel.GSetChannel ->
      g_set_operation_decoder() |> decode.map(channel.GSetOperation)
    channel.TwoPSetChannel ->
      two_p_set_operation_decoder() |> decode.map(channel.TwoPSetOperation)
    channel.RegisterCollectionChannel ->
      register_collection_operation_decoder()
      |> decode.map(channel.RegisterCollectionOperation)
    channel.ClaimsChannel ->
      claim_operation_decoder() |> decode.map(channel.ClaimsOperation)
    channel.TaskManagerChannel ->
      task_manager_operation_decoder()
      |> decode.map(channel.TaskManagerOperation)
    channel.JsonOtChannel ->
      json_ot_operation_decoder() |> decode.map(channel.JsonOtOperation)
    channel.DirectoryChannel -> directory_operation_decoder()
    channel.PactMapChannel ->
      pact_map_operation_decoder() |> decode.map(channel.PactMapOperation)
    channel.OrderedCollectionChannel ->
      ordered_operation_decoder()
      |> decode.map(channel.OrderedCollectionOperation)
    channel.SequenceChannel ->
      sequence_operation_decoder() |> decode.map(channel.SequenceOperation)
    channel.RichTextChannel ->
      rich_text_operation_decoder() |> decode.map(channel.RichTextOperation)
    channel.TextChannel ->
      text_operation_decoder() |> decode.map(channel.TextOperation)
  }
}

/// The routed Fluid container envelope around a map operation.
pub fn encode_map_envelope(
  address: String,
  operation: MapOperation,
) -> Result(Json, fluid_container.ContainerError) {
  encode_channel_envelope(address, channel.MapOperation(operation))
}

pub fn encode_map_operation(operation: MapOperation) -> Json {
  case operation {
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

pub fn decode_map_header(
  header: Json,
) -> Result(List(#(String, Json)), String) {
  decode_map_header_string(json.to_string(header))
}

pub fn decode_map_header_string(
  raw: String,
) -> Result(List(#(String, Json)), String) {
  use #(blobs, entries) <- result.try(decode_map_header_parts(raw))
  case blobs {
    [] -> Ok(entries)
    _ -> Error("SharedMap header requires external blobs")
  }
}

fn decode_map_header_parts(
  raw: String,
) -> Result(#(List(String), List(#(String, Json))), String) {
  use blobs <- result.try(
    json.parse(raw, map_header_decoder())
    |> result.map_error(fn(error) {
      "invalid SharedMap header: " <> string.inspect(error)
    }),
  )
  use fields <- result.try(json_object.members(raw))
  use content <- result.try(
    list.key_find(fields, "content")
    |> result.replace_error("missing SharedMap content"),
  )
  use entries <- result.try(decode_map_content(content))
  Ok(#(blobs, entries))
}

fn decode_map_content(raw: String) -> Result(List(#(String, Json)), String) {
  use entries <- result.try(json_object.members(raw))
  list.try_map(entries, fn(entry) {
    use value <- result.try(
      json.parse(entry.1, plain_value_decoder())
      |> result.map_error(fn(_) { "invalid SharedMap value" }),
    )
    Ok(#(entry.0, value))
  })
}

fn encode_map_attach_blobs(entries: List(#(String, Json))) -> List(Json) {
  let keys = fn(entries: List(#(String, Json))) {
    list.map(entries, fn(entry) { entry.0 })
  }
  case keys(json_object.javascript_order(entries)) == keys(entries) {
    True -> [attach_blob("header", encode_map_header(entries))]
    False -> {
      // Separate blobs preserve map order when object keys would reorder it.
      let blobs =
        list.index_map(entries, fn(entry, index) {
          #("blob" <> int.to_string(index), entry)
        })
      [
        attach_blob(
          "header",
          json.object([
            #("blobs", json.array(blobs, fn(blob) { json.string(blob.0) })),
            #("content", json.object([])),
          ]),
        ),
        ..list.map(blobs, fn(blob) {
          attach_blob(blob.0, encode_map_content([blob.1]))
        })
      ]
    }
  }
}

pub fn encode_map_header(entries: List(#(String, Json))) -> Json {
  json.object([
    #("blobs", json.preprocessed_array([])),
    #("content", encode_map_content(entries)),
  ])
}

fn encode_map_content(entries: List(#(String, Json))) -> Json {
  json.object(
    list.map(entries, fn(entry) {
      #(
        entry.0,
        json.object([
          #("type", json.string("Plain")),
          #("value", entry.1),
        ]),
      )
    }),
  )
}

fn map_header_decoder() -> Decoder(List(String)) {
  use blobs <- decode.field("blobs", decode.list(decode.string))
  use _content <- decode.field(
    "content",
    decode.dict(decode.string, plain_value_decoder()),
  )
  decode.success(blobs)
}

/// The routed Fluid container envelope around a SharedCounter
/// operation.
pub fn encode_counter_envelope(
  address: String,
  operation: CounterOperation,
) -> Result(Json, fluid_container.ContainerError) {
  encode_channel_envelope(address, channel.CounterOperation(operation))
}

pub fn encode_counter_operation(operation: CounterOperation) -> Json {
  case operation {
    Increment(increment_amount) ->
      json.object([
        #("type", json.string("increment")),
        #("incrementAmount", json.int(increment_amount)),
      ])
  }
}

/// The routed Fluid container envelope around a PnCounter operation.
pub fn encode_pn_counter_envelope(
  address: String,
  operation: PnCounterOperation,
) -> Result(Json, fluid_container.ContainerError) {
  encode_channel_envelope(address, channel.PnCounterOperation(operation))
}

pub fn encode_pn_counter_operation(operation: PnCounterOperation) -> Json {
  case operation {
    pn_counter_kernel.Update(amount, delta) ->
      json.object([
        #("type", json.string("pnCounterUpdate")),
        #("amount", json.int(amount)),
        #("delta", pn_counter_delta_json(delta)),
      ])
  }
}

/// The routed Fluid container envelope around a GCounter operation.
pub fn encode_g_counter_envelope(
  address: String,
  operation: GCounterOperation,
) -> Result(Json, fluid_container.ContainerError) {
  encode_channel_envelope(address, channel.GCounterOperation(operation))
}

pub fn encode_g_counter_operation(operation: GCounterOperation) -> Json {
  case operation {
    g_counter_kernel.Increment(amount, delta) ->
      json.object([
        #("type", json.string("gCounterIncrement")),
        #("amount", json.int(amount)),
        #("delta", g_counter_delta_json(delta)),
      ])
  }
}

pub fn encode_lww_register_envelope(
  address: String,
  operation: LwwRegisterOperation,
) -> Result(Json, fluid_container.ContainerError) {
  encode_channel_envelope(address, channel.LwwRegisterOperation(operation))
}

pub fn encode_lww_map_envelope(
  address: String,
  operation: LwwMapOperation,
) -> Result(Json, fluid_container.ContainerError) {
  encode_channel_envelope(address, channel.LwwMapOperation(operation))
}

pub fn encode_lww_map_operation(operation: LwwMapOperation) -> Json {
  let #(tag, key, timestamp, delta, value) = case operation {
    lww_map_kernel.Set(key, value, timestamp, delta) -> #(
      "lwwMapSet",
      key,
      timestamp,
      delta,
      [#("value", json.string(value))],
    )
    lww_map_kernel.Remove(key, timestamp, delta) -> #(
      "lwwMapRemove",
      key,
      timestamp,
      delta,
      [],
    )
  }
  json.object(list.append(
    [
      #("type", json.string(tag)),
      #("key", json.string(key)),
      #("timestamp", json.int(timestamp)),
      #("delta", json.string(lww_map.to_json(delta) |> json.to_string)),
    ],
    value,
  ))
}

pub fn decode_lww_map_envelope(
  contents: Dynamic,
) -> Result(#(String, LwwMapOperation), List(decode.DecodeError)) {
  decode.run(contents, lww_map_envelope_decoder())
}

pub fn lww_map_envelope_decoder() -> Decoder(#(String, LwwMapOperation)) {
  routed_operation_decoder(lww_map_operation_decoder())
}

pub fn lww_map_operation_decoder() -> Decoder(LwwMapOperation) {
  use tag <- decode.field("type", decode.string)
  use key <- decode.field("key", decode.string)
  use timestamp <- decode.field("timestamp", decode.int)
  use encoded <- decode.field("delta", decode.string)
  case json.parse(encoded, lww_map_kernel.decoder()) {
    Error(_) ->
      decode.failure(
        lww_map_kernel.Remove(
          key,
          timestamp,
          lww_map.new(replica_id.new(""), crdt.LwwRegisterSpec("")),
        ),
        "LwwMapDelta",
      )
    Ok(delta) -> {
      use operation <- decode.then(case tag {
        "lwwMapSet" -> {
          use value <- decode.field("value", decode.string)
          decode.success(lww_map_kernel.Set(key, value, timestamp, delta))
        }
        "lwwMapRemove" ->
          decode.success(lww_map_kernel.Remove(key, timestamp, delta))
        _ ->
          decode.failure(
            lww_map_kernel.Remove(key, timestamp, delta),
            "lwwMapSet or lwwMapRemove",
          )
      })
      case lww_map_kernel.validate_operation(operation) {
        Ok(Nil) -> decode.success(operation)
        Error(_) ->
          decode.failure(operation, "matching single-key LWW map fragment")
      }
    }
  }
}

pub fn encode_lww_register_operation(operation: LwwRegisterOperation) -> Json {
  let lww_register_kernel.Set(value, timestamp, delta) = operation
  json.object([
    #("type", json.string("lwwRegisterSet")),
    #("value", json.string(value)),
    #("timestamp", json.int(timestamp)),
    #("delta", json.string(lww_register.to_json(delta) |> json.to_string)),
  ])
}

pub fn decode_lww_register_envelope(
  contents: Dynamic,
) -> Result(#(String, LwwRegisterOperation), List(decode.DecodeError)) {
  decode.run(contents, lww_register_envelope_decoder())
}

pub fn lww_register_envelope_decoder() -> Decoder(
  #(String, LwwRegisterOperation),
) {
  routed_operation_decoder(lww_register_operation_decoder())
}

pub fn lww_register_operation_decoder() -> Decoder(LwwRegisterOperation) {
  use tag <- decode.field("type", decode.string)
  use value <- decode.field("value", decode.string)
  use timestamp <- decode.field("timestamp", decode.int)
  use encoded <- decode.field("delta", decode.string)
  case json.parse(encoded, channel.lww_register_decoder()) {
    Ok(delta) -> {
      let operation = lww_register_kernel.Set(value, timestamp, delta)
      // Structural equality checks both intent fields without exposing the
      // opaque register. A write cannot use the empty bottom author.
      let metadata = {
        use stamp <- decode.then(decode.at(["state", "timestamp"], decode.int))
        use author <- decode.then(decode.at(
          ["state", "replica_id"],
          decode.string,
        ))
        decode.success(#(stamp, author))
      }
      case json.parse(encoded, metadata) {
        Ok(#(stamp, author))
          if tag == "lwwRegisterSet" && author != "" && timestamp == stamp
        ->
          case lww_register.value(delta) == value {
            True -> decode.success(operation)
            False -> decode.failure(operation, "matching LWW register value")
          }
        _ ->
          decode.failure(
            operation,
            "matching LWW register timestamp and author",
          )
      }
    }
    Error(_) ->
      decode.failure(
        lww_register_kernel.Set(
          value,
          timestamp,
          lww_register.new("", 0, replica_id.new("")),
        ),
        "LwwRegisterDelta",
      )
  }
}

pub fn encode_mv_register_envelope(
  address: String,
  operation: MvRegisterOperation,
) -> Result(Json, fluid_container.ContainerError) {
  encode_channel_envelope(address, channel.MvRegisterOperation(operation))
}

pub fn encode_mv_register_operation(operation: MvRegisterOperation) -> Json {
  let mv_register_kernel.Set(value, delta) = operation
  json.object([
    #("type", json.string("mvRegisterSet")),
    #("value", json.string(value)),
    #("delta", json.string(mv_register.to_json(delta) |> json.to_string)),
  ])
}

pub fn decode_mv_register_envelope(
  contents: Dynamic,
) -> Result(#(String, MvRegisterOperation), List(decode.DecodeError)) {
  decode.run(contents, mv_register_envelope_decoder())
}

pub fn mv_register_envelope_decoder() -> Decoder(#(String, MvRegisterOperation)) {
  routed_operation_decoder(mv_register_operation_decoder())
}

pub fn mv_register_operation_decoder() -> Decoder(MvRegisterOperation) {
  use tag <- decode.field("type", decode.string)
  use value <- decode.field("value", decode.string)
  use encoded <- decode.field("delta", decode.string)
  case mv_register_kernel.decode_crdt(encoded) {
    Ok(delta) ->
      case tag == "mvRegisterSet" && mv_register.value(delta) == [value] {
        True -> decode.success(mv_register_kernel.Set(value, delta))
        False ->
          decode.failure(
            mv_register_kernel.Set(value, delta),
            "one matching MV-register write",
          )
      }
    Error(_) ->
      decode.failure(
        mv_register_kernel.Set(value, mv_register.new(replica_id.new(""))),
        "MvRegisterDelta",
      )
  }
}

/// The routed Fluid container envelope around an OrMap operation.
pub fn encode_or_map_envelope(
  address: String,
  operation: OrMapOperation,
) -> Result(Json, fluid_container.ContainerError) {
  encode_channel_envelope(address, channel.OrMapOperation(operation))
}

pub fn encode_or_map_operation(operation: OrMapOperation) -> Json {
  case operation {
    or_map_kernel.AddMember(key, member, delta) ->
      json.object([
        #("type", json.string("orMapAddMember")),
        #("key", json.string(key)),
        #("member", json.string(member)),
        #("delta", delta_json(delta)),
      ])
    or_map_kernel.RemoveMember(key, member, delta) ->
      json.object([
        #("type", json.string("orMapRemoveMember")),
        #("key", json.string(key)),
        #("member", json.string(member)),
        #("delta", delta_json(delta)),
      ])
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
    or_map_kernel.SetMvRegister(key, value, delta) ->
      json.object([
        #("type", json.string("orMapSetMvRegister")),
        #("key", json.string(key)),
        #("value", json.string(value)),
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

pub fn encode_or_set_envelope(
  address: String,
  operation: OrSetOperation,
) -> Result(Json, fluid_container.ContainerError) {
  encode_channel_envelope(address, channel.OrSetOperation(operation))
}

pub fn encode_or_set_operation(operation: OrSetOperation) -> Json {
  case operation {
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

pub fn encode_g_set_envelope(
  address: String,
  operation: GSetOperation,
) -> Result(Json, fluid_container.ContainerError) {
  encode_channel_envelope(address, channel.GSetOperation(operation))
}

pub fn encode_g_set_operation(operation: GSetOperation) -> Json {
  case operation {
    g_set_kernel.Add(element, delta) ->
      json.object([
        #("type", json.string("gSetAdd")),
        #("element", json.string(element)),
        #("delta", g_set_delta_json(delta)),
      ])
  }
}

pub fn encode_two_p_set_envelope(
  address: String,
  operation: TwoPSetOperation,
) -> Result(Json, fluid_container.ContainerError) {
  encode_channel_envelope(address, channel.TwoPSetOperation(operation))
}

pub fn encode_two_p_set_operation(operation: TwoPSetOperation) -> Json {
  case operation {
    two_p_set_kernel.Add(element, delta) ->
      json.object([
        #("type", json.string("twoPSetAdd")),
        #("element", json.string(element)),
        #("delta", two_p_set_delta_json(delta)),
      ])
    two_p_set_kernel.Remove(element, delta) ->
      json.object([
        #("type", json.string("twoPSetRemove")),
        #("element", json.string(element)),
        #("delta", two_p_set_delta_json(delta)),
      ])
  }
}

pub fn encode_register_collection_envelope(
  address: String,
  operation: WriteOperation,
) -> Result(Json, fluid_container.ContainerError) {
  encode_channel_envelope(
    address,
    channel.RegisterCollectionOperation(operation),
  )
}

pub fn encode_register_collection_operation(operation: WriteOperation) -> Json {
  case operation {
    Write(key, value, reference_sequence_number) ->
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
        #("refSeq", json.int(reference_sequence_number)),
      ])
  }
}

pub fn encode_claim_envelope(
  address: String,
  operation: ClaimOperation,
) -> Result(Json, fluid_container.ContainerError) {
  encode_channel_envelope(address, channel.ClaimsOperation(operation))
}

pub fn encode_claim_operation(operation: ClaimOperation) -> Json {
  case operation {
    Claim(key, value, reference_sequence_number) ->
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
        #("refSeq", json.int(reference_sequence_number)),
      ])
  }
}

/// Encode a json0 operation envelope. It contains the reference sequence number
/// that the components were written against, and the json0 component array.
pub fn encode_json_ot_operation(operation: JsonOtWireOperation) -> Json {
  json.object([
    #("refSeq", json.int(operation.reference_sequence_number)),
    #("components", json_ot.operation_to_json(operation.components)),
  ])
}

/// Encode a rich-text operation envelope. It contains the reference sequence
/// number that the delta was written against, and the canonical Quill Delta
/// JSON array of that delta.
pub fn encode_rich_text_operation(operation: RichTextWireOperation) -> Json {
  json.object([
    #("refSeq", json.int(operation.reference_sequence_number)),
    #("delta", rich_text.delta_to_json(operation.delta)),
  ])
}

pub fn encode_task_manager_envelope(
  address: String,
  operation: TaskManagerOperation,
) -> Result(Json, fluid_container.ContainerError) {
  encode_channel_envelope(address, channel.TaskManagerOperation(operation))
}

pub fn encode_task_manager_operation(operation: TaskManagerOperation) -> Json {
  case operation {
    task_manager_kernel.Volunteer(task_id) ->
      json.object([
        #("type", json.string("taskVolunteer")),
        #("taskId", json.string(task_id)),
      ])
    task_manager_kernel.Abandon(task_id) ->
      json.object([
        #("type", json.string("taskAbandon")),
        #("taskId", json.string(task_id)),
      ])
    task_manager_kernel.Complete(task_id) ->
      json.object([
        #("type", json.string("taskComplete")),
        #("taskId", json.string(task_id)),
      ])
  }
}

/// Encode a SharedDirectory operation. Every variant carries `path`, which is
/// the absolute directory address, and `mid`, which is the `message_id` of the
/// kernel. `mid` is the client-sequence identity of the operation. A remote
/// client needs it for the stale-instance filter and for the sibling order.
pub fn encode_directory_operation(
  operation: DirectoryOperation,
  message_id: Int,
) -> Json {
  case operation {
    directory_kernel.Set(path, key, value) ->
      json.object([
        #("type", json.string("dirSet")),
        #("path", json.string(path)),
        #("key", json.string(key)),
        #(
          "value",
          json.object([#("type", json.string("Plain")), #("value", value)]),
        ),
        #("mid", json.int(message_id)),
      ])
    directory_kernel.Delete(path, key) ->
      json.object([
        #("type", json.string("dirDelete")),
        #("path", json.string(path)),
        #("key", json.string(key)),
        #("mid", json.int(message_id)),
      ])
    directory_kernel.Clear(path) ->
      json.object([
        #("type", json.string("dirClear")),
        #("path", json.string(path)),
        #("mid", json.int(message_id)),
      ])
    directory_kernel.CreateSubDirectory(path, name) ->
      json.object([
        #("type", json.string("dirCreateSub")),
        #("path", json.string(path)),
        #("name", json.string(name)),
        #("mid", json.int(message_id)),
      ])
    directory_kernel.DeleteSubDirectory(path, name) ->
      json.object([
        #("type", json.string("dirDeleteSub")),
        #("path", json.string(path)),
        #("name", json.string(name)),
        #("mid", json.int(message_id)),
      ])
  }
}

fn directory_operation_decoder() -> Decoder(channel.ChannelOperation) {
  use operation_type <- decode.field("type", decode.string)
  use path <- decode.field("path", decode.string)
  use message_id <- decode.field("mid", decode.int)
  case operation_type {
    "dirSet" -> {
      use key <- decode.field("key", decode.string)
      use value <- decode.field("value", plain_value_decoder())
      decode.success(channel.DirectoryOperation(
        directory_kernel.Set(path, key, value),
        message_id,
      ))
    }
    "dirDelete" -> {
      use key <- decode.field("key", decode.string)
      decode.success(channel.DirectoryOperation(
        directory_kernel.Delete(path, key),
        message_id,
      ))
    }
    "dirClear" ->
      decode.success(channel.DirectoryOperation(
        directory_kernel.Clear(path),
        message_id,
      ))
    "dirCreateSub" -> {
      use name <- decode.field("name", decode.string)
      decode.success(channel.DirectoryOperation(
        directory_kernel.CreateSubDirectory(path, name),
        message_id,
      ))
    }
    "dirDeleteSub" -> {
      use name <- decode.field("name", decode.string)
      decode.success(channel.DirectoryOperation(
        directory_kernel.DeleteSubDirectory(path, name),
        message_id,
      ))
    }
    _ ->
      decode.failure(
        channel.DirectoryOperation(directory_kernel.Clear(path), message_id),
        "DirectoryOp",
      )
  }
}

/// The routed Fluid container envelope around a PactMap operation.
pub fn encode_pact_map_envelope(
  address: String,
  operation: pact_map_kernel.PactMapOperation,
) -> Result(Json, fluid_container.ContainerError) {
  encode_channel_envelope(address, channel.PactMapOperation(operation))
}

/// Encode a PactMap operation. The value of a `Set` operation is an
/// `Option(Json)`. `None` is a true tombstone, which is not the same as
/// `Some(null)`, and it gets the `Absent` tag.
pub fn encode_pact_map_operation(
  operation: pact_map_kernel.PactMapOperation,
) -> Json {
  case operation {
    pact_map_kernel.Set(key, value, reference_sequence_number) ->
      json.object([
        #("type", json.string("pactMapSet")),
        #("key", json.string(key)),
        #("value", encode_pact_map_value(value)),
        #("refSeq", json.int(reference_sequence_number)),
      ])
    pact_map_kernel.Accept(key) ->
      json.object([
        #("type", json.string("pactMapAccept")),
        #("key", json.string(key)),
      ])
  }
}

fn encode_pact_map_value(value: option.Option(Json)) -> Json {
  case value {
    Some(inner) ->
      json.object([#("type", json.string("Plain")), #("value", inner)])
    None -> json.object([#("type", json.string("Absent"))])
  }
}

pub fn decode_pact_map_envelope(
  contents: Dynamic,
) -> Result(
  #(String, pact_map_kernel.PactMapOperation),
  List(decode.DecodeError),
) {
  decode.run(contents, pact_map_envelope_decoder())
}

pub fn pact_map_envelope_decoder() -> Decoder(
  #(String, pact_map_kernel.PactMapOperation),
) {
  routed_operation_decoder(pact_map_operation_decoder())
}

pub fn pact_map_operation_decoder() -> Decoder(pact_map_kernel.PactMapOperation) {
  use operation_type <- decode.field("type", decode.string)
  case operation_type {
    "pactMapSet" -> {
      use key <- decode.field("key", decode.string)
      use value <- decode.field("value", pact_map_value_decoder())
      use reference_sequence_number <- decode.field("refSeq", decode.int)
      decode.success(pact_map_kernel.Set(key, value, reference_sequence_number))
    }
    "pactMapAccept" -> {
      use key <- decode.field("key", decode.string)
      decode.success(pact_map_kernel.Accept(key))
    }
    _ -> decode.failure(pact_map_kernel.Accept(""), "PactMapOp")
  }
}

fn pact_map_value_decoder() -> Decoder(option.Option(Json)) {
  use value_type <- decode.field("type", decode.string)
  case value_type {
    "Plain" ->
      decode.field("value", wire.json_value_decoder(), fn(inner) {
        decode.success(Some(inner))
      })
    "Absent" -> decode.success(None)
    _ -> decode.failure(None, "PactMapValue")
  }
}

/// The routed Fluid container envelope around an ordered-collection
/// operation.
pub fn encode_ordered_envelope(
  address: String,
  operation: OrderedOperation,
) -> Result(Json, fluid_container.ContainerError) {
  encode_channel_envelope(
    address,
    channel.OrderedCollectionOperation(operation),
  )
}

pub fn encode_ordered_operation(operation: OrderedOperation) -> Json {
  case operation {
    ordered_collection_kernel.Add(value) ->
      json.object([#("type", json.string("orderedAdd")), #("value", value)])
    ordered_collection_kernel.Acquire(acquire_id) ->
      json.object([
        #("type", json.string("orderedAcquire")),
        #("acquireId", json.string(acquire_id)),
      ])
    ordered_collection_kernel.Complete(acquire_id) ->
      json.object([
        #("type", json.string("orderedComplete")),
        #("acquireId", json.string(acquire_id)),
      ])
    ordered_collection_kernel.Release(acquire_id) ->
      json.object([
        #("type", json.string("orderedRelease")),
        #("acquireId", json.string(acquire_id)),
      ])
  }
}

pub fn decode_ordered_envelope(
  contents: Dynamic,
) -> Result(#(String, OrderedOperation), List(decode.DecodeError)) {
  decode.run(contents, ordered_envelope_decoder())
}

pub fn ordered_envelope_decoder() -> Decoder(#(String, OrderedOperation)) {
  routed_operation_decoder(ordered_operation_decoder())
}

pub fn ordered_operation_decoder() -> Decoder(OrderedOperation) {
  use operation_type <- decode.field("type", decode.string)
  case operation_type {
    "orderedAdd" -> {
      use value <- decode.field("value", wire.json_value_decoder())
      decode.success(ordered_collection_kernel.Add(value))
    }
    "orderedAcquire" -> {
      use acquire_id <- decode.field("acquireId", decode.string)
      decode.success(ordered_collection_kernel.Acquire(acquire_id))
    }
    "orderedComplete" -> {
      use acquire_id <- decode.field("acquireId", decode.string)
      decode.success(ordered_collection_kernel.Complete(acquire_id))
    }
    "orderedRelease" -> {
      use acquire_id <- decode.field("acquireId", decode.string)
      decode.success(ordered_collection_kernel.Release(acquire_id))
    }
    _ -> decode.failure(ordered_collection_kernel.Acquire(""), "OrderedOp")
  }
}

pub fn sequence_operation_decoder() -> Decoder(SequenceOperation) {
  use operation_type <- decode.field("type", decode.string)
  case operation_type {
    "sequenceInsert" -> {
      use index <- decode.field("index", decode.int)
      use value <- decode.field("value", wire.json_value_decoder())
      use delta <- decode.field("delta", sequence_delta_decoder())
      decode.success(sequence_kernel.Insert(index, value, delta))
    }
    "sequenceDelete" -> {
      use index <- decode.field("index", decode.int)
      use delta <- decode.field("delta", sequence_delta_decoder())
      decode.success(sequence_kernel.Delete(index, delta))
    }
    "sequenceMove" -> {
      use from_index <- decode.field("fromIndex", decode.int)
      use to_index <- decode.field("toIndex", decode.int)
      use delta <- decode.field("delta", sequence_delta_decoder())
      decode.success(sequence_kernel.Move(from_index, to_index, delta))
    }
    "sequenceReplace" -> {
      use index <- decode.field("index", decode.int)
      use value <- decode.field("value", wire.json_value_decoder())
      use delta <- decode.field("delta", sequence_delta_decoder())
      decode.success(sequence_kernel.Replace(index, value, delta))
    }
    _ ->
      decode.failure(
        sequence_kernel.Delete(0, default_sequence_delta()),
        "SequenceOp",
      )
  }
}

/// Decode the wire tag of a `TextOperation`. The diagnostic intent fields,
/// which are the indexes, the ranges, and the value, travel with the
/// authoritative CRDT `delta`. A `delta` that is malformed or absent fails this
/// decoder, and thus fails stage two of the decode, before the operation
/// reaches the kernel.
pub fn text_operation_decoder() -> Decoder(TextOperation) {
  use operation_type <- decode.field("type", decode.string)
  case operation_type {
    "textInsert" -> {
      use index <- decode.field("index", decode.int)
      use value <- decode.field("value", decode.string)
      use delta <- decode.field("delta", text_delta_decoder())
      decode.success(text_kernel.Insert(index, value, delta))
    }
    "textDeleteRange" -> {
      use start <- decode.field("start", decode.int)
      use end <- decode.field("end", decode.int)
      use delta <- decode.field("delta", text_delta_decoder())
      decode.success(text_kernel.DeleteRange(start, end, delta))
    }
    "textReplaceRange" -> {
      use start <- decode.field("start", decode.int)
      use end <- decode.field("end", decode.int)
      use value <- decode.field("value", decode.string)
      use delta <- decode.field("delta", text_delta_decoder())
      decode.success(text_kernel.ReplaceRange(start, end, value, delta))
    }
    "textAppend" -> {
      use value <- decode.field("value", decode.string)
      use delta <- decode.field("delta", text_delta_decoder())
      decode.success(text_kernel.Append(value, delta))
    }
    _ ->
      decode.failure(
        text_kernel.DeleteRange(0, 0, default_text_delta()),
        "TextOp",
      )
  }
}

pub fn encode_sequence_operation(operation: SequenceOperation) -> Json {
  case operation {
    sequence_kernel.Insert(index, value, delta) ->
      json.object([
        #("type", json.string("sequenceInsert")),
        #("index", json.int(index)),
        #("value", value),
        #("delta", sequence_delta_json(delta)),
      ])
    sequence_kernel.Delete(index, delta) ->
      json.object([
        #("type", json.string("sequenceDelete")),
        #("index", json.int(index)),
        #("delta", sequence_delta_json(delta)),
      ])
    sequence_kernel.Move(from_index, to_index, delta) ->
      json.object([
        #("type", json.string("sequenceMove")),
        #("fromIndex", json.int(from_index)),
        #("toIndex", json.int(to_index)),
        #("delta", sequence_delta_json(delta)),
      ])
    sequence_kernel.Replace(index, value, delta) ->
      json.object([
        #("type", json.string("sequenceReplace")),
        #("index", json.int(index)),
        #("value", value),
        #("delta", sequence_delta_json(delta)),
      ])
  }
}

/// Encode a `TextOperation` for the wire. Every constructor carries the
/// diagnostic intent fields, which are the indexes, the ranges, and the value,
/// with the authoritative CRDT `delta`. A remote replica applies `delta`. It
/// never applies a diagnostic field.
pub fn encode_text_operation(operation: TextOperation) -> Json {
  case operation {
    text_kernel.Insert(index, value, delta) ->
      json.object([
        #("type", json.string("textInsert")),
        #("index", json.int(index)),
        #("value", json.string(value)),
        #("delta", text_delta_json(delta)),
      ])
    text_kernel.DeleteRange(start, end, delta) ->
      json.object([
        #("type", json.string("textDeleteRange")),
        #("start", json.int(start)),
        #("end", json.int(end)),
        #("delta", text_delta_json(delta)),
      ])
    text_kernel.ReplaceRange(start, end, value, delta) ->
      json.object([
        #("type", json.string("textReplaceRange")),
        #("start", json.int(start)),
        #("end", json.int(end)),
        #("value", json.string(value)),
        #("delta", text_delta_json(delta)),
      ])
    text_kernel.Append(value, delta) ->
      json.object([
        #("type", json.string("textAppend")),
        #("value", json.string(value)),
        #("delta", text_delta_json(delta)),
      ])
  }
}

fn delta_json(delta: or_map_kernel.ORMapDelta) -> Json {
  json.string(json.to_string(or_map.delta_to_json(delta)))
}

fn or_set_delta_json(delta: or_set.ORSet(String)) -> Json {
  json.string(json.to_string(or_set.to_json(delta)))
}

fn g_set_delta_json(delta: g_set.GSet(String)) -> Json {
  json.string(json.to_string(g_set.to_json(delta)))
}

fn two_p_set_delta_json(delta: two_p_set.TwoPSet(String)) -> Json {
  json.string(json.to_string(two_p_set.to_json(delta)))
}

fn pn_counter_delta_json(delta: pn_counter.PNCounter) -> Json {
  json.string(json.to_string(pn_counter.to_json(delta)))
}

fn g_counter_delta_json(delta: g_counter.GCounter) -> Json {
  json.string(json.to_string(g_counter.to_json(delta)))
}

fn sequence_delta_json(delta: sequence.Sequence(Json)) -> Json {
  json.string(json.to_string(sequence.to_json(delta, fn(value) { value })))
}

fn text_delta_json(delta: text.Text) -> Json {
  json.string(json.to_string(text.to_json(delta)))
}

/// Decode the `contents` of a sequenced `"op"` message into
/// `#(address, MapOperation)`.
pub fn decode_map_envelope(
  contents: Dynamic,
) -> Result(#(String, MapOperation), List(decode.DecodeError)) {
  decode.run(contents, map_envelope_decoder())
}

pub fn map_envelope_decoder() -> Decoder(#(String, MapOperation)) {
  routed_operation_decoder(map_operation_decoder())
}

pub fn map_operation_decoder() -> Decoder(MapOperation) {
  use operation_type <- decode.field("type", decode.string)
  case operation_type {
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
/// `#(address, CounterOperation)`.
pub fn decode_counter_envelope(
  contents: Dynamic,
) -> Result(#(String, CounterOperation), List(decode.DecodeError)) {
  decode.run(contents, counter_envelope_decoder())
}

pub fn counter_envelope_decoder() -> Decoder(#(String, CounterOperation)) {
  routed_operation_decoder(counter_operation_decoder())
}

pub fn counter_operation_decoder() -> Decoder(CounterOperation) {
  use operation_type <- decode.field("type", decode.string)
  case operation_type {
    "increment" -> {
      use increment_amount <- decode.field("incrementAmount", decode.int)
      decode.success(Increment(increment_amount))
    }
    _ -> decode.failure(Increment(0), "CounterOp")
  }
}

/// Decode the `contents` of a sequenced `"op"` message into
/// `#(address, PnCounterOperation)`.
pub fn decode_pn_counter_envelope(
  contents: Dynamic,
) -> Result(#(String, PnCounterOperation), List(decode.DecodeError)) {
  decode.run(contents, pn_counter_envelope_decoder())
}

pub fn pn_counter_envelope_decoder() -> Decoder(#(String, PnCounterOperation)) {
  routed_operation_decoder(pn_counter_operation_decoder())
}

pub fn pn_counter_operation_decoder() -> Decoder(PnCounterOperation) {
  use operation_type <- decode.field("type", decode.string)
  case operation_type {
    "pnCounterUpdate" -> {
      use amount <- decode.field("amount", decode.int)
      use delta <- decode.field("delta", pn_counter_delta_decoder())
      decode.success(pn_counter_kernel.Update(amount, delta))
    }
    _ ->
      decode.failure(
        pn_counter_kernel.Update(0, default_pn_counter_delta()),
        "PnCounterOp",
      )
  }
}

/// Decode the `contents` of a sequenced `"op"` message into
/// `#(address, GCounterOperation)`.
pub fn decode_g_counter_envelope(
  contents: Dynamic,
) -> Result(#(String, GCounterOperation), List(decode.DecodeError)) {
  decode.run(contents, g_counter_envelope_decoder())
}

pub fn g_counter_envelope_decoder() -> Decoder(#(String, GCounterOperation)) {
  routed_operation_decoder(g_counter_operation_decoder())
}

/// The grow-only counter accepts one operation type. The decoder rejects a
/// negative intent amount, because the public API cannot produce one, and a
/// fragment whose per-replica counts do not decode. It does not require the
/// count of the fragment to equal the intent amount: the fragment is
/// cumulative, and it thus carries the total of that replica.
pub fn g_counter_operation_decoder() -> Decoder(GCounterOperation) {
  use operation_type <- decode.field("type", decode.string)
  case operation_type {
    "gCounterIncrement" -> {
      use amount <- decode.field("amount", non_negative_int_decoder())
      use delta <- decode.field("delta", g_counter_delta_decoder())
      decode.success(g_counter_kernel.Increment(amount, delta))
    }
    _ ->
      decode.failure(
        g_counter_kernel.Increment(0, default_g_counter_delta()),
        "GCounterOp",
      )
  }
}

fn non_negative_int_decoder() -> Decoder(Int) {
  use value <- decode.then(decode.int)
  case value >= 0 {
    True -> decode.success(value)
    False -> decode.failure(0, "a non-negative integer")
  }
}

pub fn or_map_operation_decoder() -> Decoder(OrMapOperation) {
  use operation <- decode.then(or_map_intent_decoder())
  case or_map_kernel.validate_operation_intent(operation) {
    Ok(Nil) -> decode.success(operation)
    Error(_) -> decode.failure(operation, "OR-map intent matching its delta")
  }
}

fn or_map_intent_decoder() -> Decoder(OrMapOperation) {
  use operation_type <- decode.field("type", decode.string)
  case operation_type {
    "orMapIncrement" -> {
      use key <- decode.field("key", decode.string)
      use amount <- decode.field("amount", decode.int)
      use delta <- decode.field("delta", or_map_delta_decoder())
      checked_or_map_operation(
        or_map_kernel.Increment(key, amount, delta),
        delta,
      )
    }

    "orMapSet" -> {
      use key <- decode.field("key", decode.string)
      use value <- decode.field("value", decode.string)
      use timestamp <- decode.field("timestamp", decode.int)
      use delta <- decode.field("delta", or_map_delta_decoder())
      checked_or_map_operation(
        or_map_kernel.SetRegister(key, value, timestamp, delta),
        delta,
      )
    }
    "orMapSetMvRegister" -> {
      use key <- decode.field("key", decode.string)
      use value <- decode.field("value", decode.string)
      use delta <- decode.field("delta", or_map_delta_decoder())
      decode.success(or_map_kernel.SetMvRegister(key, value, delta))
    }
    "orMapRemove" -> {
      use key <- decode.field("key", decode.string)
      use delta <- decode.field("delta", or_map_delta_decoder())
      checked_or_map_operation(or_map_kernel.Remove(key, delta), delta)
    }
    "orMapAddMember" | "orMapRemoveMember" -> {
      use key <- decode.field("key", decode.string)
      use member <- decode.field("member", decode.string)
      use encoded <- decode.field("delta", decode.string)
      case or_map_set_leaf.decode_delta(encoded) {
        Error(_) ->
          decode.failure(
            or_map_kernel.Remove("", default_or_map_delta()),
            "ORMap set delta",
          )
        Ok(delta) -> {
          let operation = case operation_type {
            "orMapAddMember" -> or_map_kernel.AddMember(key, member, delta)
            _ -> or_map_kernel.RemoveMember(key, member, delta)
          }
          validated_set_operation(operation)
        }
      }
    }
    _ ->
      decode.failure(
        or_map_kernel.Remove("", default_or_map_delta()),
        "OrMapOp",
      )
  }
}

pub fn or_set_operation_decoder() -> Decoder(OrSetOperation) {
  use operation_type <- decode.field("type", decode.string)
  case operation_type {
    "orSetAdd" -> {
      use element <- decode.field("element", decode.string)
      use delta <- decode.field("delta", or_set_delta_decoder())
      let operation: OrSetOperation = or_set_kernel.Add(element, delta)
      decode.success(operation)
    }
    "orSetRemove" -> {
      use element <- decode.field("element", decode.string)
      use delta <- decode.field("delta", or_set_delta_decoder())
      let operation: OrSetOperation = or_set_kernel.Remove(element, delta)
      decode.success(operation)
    }
    _ ->
      decode.failure(
        or_set_kernel.Remove("", default_or_set_delta()),
        "OrSetOp",
      )
  }
}

pub fn g_set_operation_decoder() -> Decoder(GSetOperation) {
  use operation_type <- decode.field("type", decode.string)
  case operation_type {
    "gSetAdd" -> {
      use element <- decode.field("element", decode.string)
      use delta <- decode.field("delta", g_set_delta_decoder())
      let operation: GSetOperation = g_set_kernel.Add(element, delta)
      decode.success(operation)
    }
    _ -> decode.failure(g_set_kernel.Add("", default_g_set_delta()), "GSetOp")
  }
}

pub fn two_p_set_operation_decoder() -> Decoder(TwoPSetOperation) {
  use operation_type <- decode.field("type", decode.string)
  case operation_type {
    "twoPSetAdd" -> {
      use element <- decode.field("element", decode.string)
      use delta <- decode.field("delta", two_p_set_delta_decoder())
      let operation: TwoPSetOperation = two_p_set_kernel.Add(element, delta)
      decode.success(operation)
    }
    "twoPSetRemove" -> {
      use element <- decode.field("element", decode.string)
      use delta <- decode.field("delta", two_p_set_delta_decoder())
      let operation: TwoPSetOperation = two_p_set_kernel.Remove(element, delta)
      decode.success(operation)
    }
    _ ->
      decode.failure(
        two_p_set_kernel.Add("", default_two_p_set_delta()),
        "TwoPSetOp",
      )
  }
}

pub fn register_collection_operation_decoder() -> Decoder(WriteOperation) {
  use operation_type <- decode.field("type", decode.string)
  case operation_type {
    "registerWrite" -> {
      use key <- decode.field("key", decode.string)
      use value <- decode.field("value", plain_value_decoder())
      use reference_sequence_number <- decode.field("refSeq", decode.int)
      decode.success(Write(key, value, reference_sequence_number))
    }
    _ -> decode.failure(Write("", json.null(), 0), "RegisterCollectionOp")
  }
}

pub fn claim_operation_decoder() -> Decoder(ClaimOperation) {
  use operation_type <- decode.field("type", decode.string)
  case operation_type {
    "claim" -> {
      use key <- decode.field("key", decode.string)
      use value <- decode.field("value", plain_value_decoder())
      use reference_sequence_number <- decode.field("refSeq", decode.int)
      decode.success(Claim(key, value, reference_sequence_number))
    }
    _ -> decode.failure(Claim("", json.null(), 0), "ClaimOp")
  }
}

pub fn json_ot_operation_decoder() -> Decoder(JsonOtWireOperation) {
  use reference_sequence_number <- decode.field("refSeq", decode.int)
  use components <- decode.field("components", json_ot.operation_decoder())
  decode.success(JsonOtWireOperation(reference_sequence_number, components))
}

/// A strict decoder for a rich-text operation envelope. The `delta` field must
/// decode as a correct Quill Delta, which is an array of insert, delete, and
/// retain operations. A malformed delta fails the whole decode. The decoder
/// does not drop the operation.
pub fn rich_text_operation_decoder() -> Decoder(RichTextWireOperation) {
  use reference_sequence_number <- decode.field("refSeq", decode.int)
  use delta <- decode.field("delta", rich_text_delta_decoder())
  decode.success(RichTextWireOperation(reference_sequence_number, delta))
}

fn rich_text_delta_decoder() -> Decoder(rich_text.Delta) {
  use raw <- decode.then(json_ot.decoder())
  case rich_text.delta_from_json(raw) {
    Ok(delta) -> decode.success(delta)
    Error(_) -> decode.failure(rich_text.empty_delta(), "RichTextDelta")
  }
}

pub fn task_manager_operation_decoder() -> Decoder(TaskManagerOperation) {
  use operation_type <- decode.field("type", decode.string)
  case operation_type {
    "taskVolunteer" -> {
      use task_id <- decode.field("taskId", decode.string)
      decode.success(task_manager_kernel.Volunteer(task_id))
    }
    "taskAbandon" -> {
      use task_id <- decode.field("taskId", decode.string)
      decode.success(task_manager_kernel.Abandon(task_id))
    }
    "taskComplete" -> {
      use task_id <- decode.field("taskId", decode.string)
      decode.success(task_manager_kernel.Complete(task_id))
    }
    _ -> decode.failure(task_manager_kernel.Volunteer(""), "TaskManagerOp")
  }
}

fn or_map_delta_decoder() -> Decoder(or_map_kernel.ORMapDelta) {
  use encoded <- decode.then(decode.string)
  let decoded = case or_map_spec_name(encoded) {
    Ok("or_set") ->
      or_map_set_leaf.decode_delta(encoded) |> result.map_error(fn(_) { Nil })
    Ok(_) -> or_map.delta_from_json(encoded) |> result.map_error(fn(_) { Nil })
    Error(_) -> Error(Nil)
  }
  case decoded {
    Ok(delta) -> decode.success(delta)
    Error(_) -> decode.failure(default_or_map_delta(), "ORMapDelta")
  }
}

fn or_map_spec_name(encoded: String) -> Result(String, Nil) {
  use spec <- result.try(
    json.parse(encoded, decode.at(["state", "spec"], decode.string))
    |> result.map_error(fn(_) { Nil }),
  )
  json.parse(spec, {
    use name <- decode.field("type", decode.string)
    decode.success(name)
  })
  |> result.map_error(fn(_) { Nil })
}

fn checked_or_map_operation(
  operation: OrMapOperation,
  delta: or_map_kernel.ORMapDelta,
) -> Decoder(OrMapOperation) {
  case or_map_spec_name(or_map.delta_to_json(delta) |> json.to_string) {
    Ok("or_set") -> validated_set_operation(operation)
    _ -> decode.success(operation)
  }
}

fn validated_set_operation(
  operation: OrMapOperation,
) -> Decoder(OrMapOperation) {
  case or_map_kernel.validate_operation(or_map_kernel.OrSetMode, operation) {
    Ok(Nil) -> decode.success(operation)
    Error(_) -> decode.failure(operation, "ORMap set operation intent")
  }
}

fn default_or_map_delta() -> or_map_kernel.ORMapDelta {
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

fn g_set_delta_decoder() -> Decoder(g_set.GSet(String)) {
  use encoded <- decode.then(decode.string)
  case g_set.from_json(encoded) {
    Ok(delta) -> decode.success(delta)
    Error(_) -> decode.failure(default_g_set_delta(), "GSetDelta")
  }
}

fn default_g_set_delta() -> g_set.GSet(String) {
  g_set.new()
}

fn two_p_set_delta_decoder() -> Decoder(two_p_set.TwoPSet(String)) {
  use encoded <- decode.then(decode.string)
  case two_p_set.from_json(encoded) {
    Ok(delta) -> decode.success(delta)
    Error(_) -> decode.failure(default_two_p_set_delta(), "TwoPSetDelta")
  }
}

fn pn_counter_delta_decoder() -> Decoder(pn_counter.PNCounter) {
  use encoded <- decode.then(decode.string)
  case pn_counter.from_json(encoded) {
    Ok(delta) -> decode.success(delta)
    Error(_) -> decode.failure(default_pn_counter_delta(), "PNCounterDelta")
  }
}

fn g_counter_delta_decoder() -> Decoder(g_counter.GCounter) {
  use encoded <- decode.then(decode.string)
  case g_counter.from_json(encoded) {
    Ok(delta) -> decode.success(delta)
    Error(_) -> decode.failure(default_g_counter_delta(), "GCounterDelta")
  }
}

fn sequence_delta_decoder() -> Decoder(sequence.Sequence(Json)) {
  use encoded <- decode.then(decode.string)
  case json.parse(encoded, sequence_delta_shape_decoder()) {
    Error(_) -> decode.failure(default_sequence_delta(), "SequenceDelta")
    Ok(Nil) ->
      case sequence.from_json(encoded, wire.json_value_decoder()) {
        Ok(delta) -> decode.success(delta)
        Error(_) -> decode.failure(default_sequence_delta(), "SequenceDelta")
      }
  }
}

fn sequence_delta_shape_decoder() -> Decoder(Nil) {
  use frontier <- decode.then(decode.at(
    ["state", "frontier"],
    version_vector.decoder(),
  ))
  use forwardings <- decode.then(decode.at(
    ["state", "forwardings"],
    decode.list(decode.dynamic),
  ))
  use segment_kinds <- decode.then(decode.at(
    ["state", "segments"],
    decode.list({
      use kind <- decode.field("kind", decode.string)
      decode.success(kind)
    }),
  ))
  case
    version_vector.is_empty(frontier)
    && list.is_empty(forwardings)
    && list.all(segment_kinds, fn(kind) { kind == "item" })
  {
    True -> decode.success(Nil)
    False -> decode.failure(Nil, "SequenceDelta")
  }
}

// `lattice_text` 1.0.0 stores its backing `lattice_sequence.Sequence(String)`
// and serializes it with `sequence.to_json`, so a `Text` delta is wire-shaped
// identically to a `Sequence` delta. Reusing `sequence_delta_shape_decoder`
// here checks the same invariant an authentic operation delta must hold: empty
// frontier, no forwardings, and item-only segments. A delta failing that
// shape check — most notably a compacted state, which has tombstones and a
// non-empty frontier — is rejected before `text.from_json` ever runs, so a
// forged "delta" can't smuggle a full (and potentially stale-relative)
// state into a channel operation.
fn text_delta_decoder() -> Decoder(text.Text) {
  use encoded <- decode.then(decode.string)
  case json.parse(encoded, sequence_delta_shape_decoder()) {
    Error(_) -> decode.failure(default_text_delta(), "TextDelta")
    Ok(Nil) ->
      case text.from_json(encoded) {
        Ok(delta) -> decode.success(delta)
        Error(_) -> decode.failure(default_text_delta(), "TextDelta")
      }
  }
}

fn default_pn_counter_delta() -> pn_counter.PNCounter {
  pn_counter.new(replica_id.new(""))
}

fn default_g_counter_delta() -> g_counter.GCounter {
  g_counter.new(replica_id.new(""))
}

fn default_sequence_delta() -> sequence.Sequence(Json) {
  sequence.new(replica_id.new(""))
}

fn default_text_delta() -> text.Text {
  text.new(replica_id.new(""))
}

fn default_two_p_set_delta() -> two_p_set.TwoPSet(String) {
  two_p_set.new()
}

/// A `Plain` value carries an opaque kernel `Json` payload. This decoder does
/// not interpret a handle marker, for example `{"type":"Shared", ...}`. The
/// full runtime must materialize such a marker. This decoder accepts a `Plain`
/// marker only.
fn plain_value_decoder() -> Decoder(Json) {
  use value_type <- decode.field("type", decode.string)
  case value_type {
    "Plain" -> decode.field("value", wire.json_value_decoder(), decode.success)
    _ -> decode.failure(json.null(), "PlainValue")
  }
}

pub fn attach_envelope_decoder() -> Decoder(OperationContents) {
  use contents <- decode.then(decode.dynamic)
  case decode_operation_contents(contents) {
    Ok(AttachOperation(..) as operation) -> decode.success(operation)
    _ ->
      decode.failure(
        AttachOperation(address: "", snapshot: channel.MapSnapshot([])),
        "AttachEnvelope",
      )
  }
}

pub fn decode_operation_contents(
  contents: Dynamic,
) -> Result(OperationContents, fluid_container.ContainerError) {
  use contents <- result.try(
    socket.container_contents(contents)
    |> result.map_error(fn(detail) {
      fluid_container.MalformedMessage("contents", detail)
    }),
  )
  use batch <- result.try(fluid_container.decode(contents, None))
  case batch {
    fluid_container.DecodedBatch(
      False,
      _,
      [fluid_container.ContainerMessage(kind, _, _)],
    ) -> decode_channel_message(kind)
    _ ->
      Error(fluid_container.UnsupportedMessage(
        "expected a singleton channel message",
      ))
  }
}

pub fn decode_channel_message(
  kind: fluid_container.MessageKind,
) -> Result(OperationContents, fluid_container.ContainerError) {
  case kind {
    fluid_container.ChannelOperation(route, payload) -> {
      use address <- result.try(fluid_container.route_key(route))
      use payload <- result.try(
        json.parse(json.to_string(payload), decode.dynamic)
        |> result.map_error(fn(_) {
          fluid_container.MalformedMessage("contents", "invalid JSON payload")
        }),
      )
      Ok(ChannelOperation(address, payload))
    }
    fluid_container.ChannelAttach(route, channel_type, snapshot) -> {
      use address <- result.try(fluid_container.route_key(route))
      use snapshot <- result.try(decode_attach_snapshot(channel_type, snapshot))
      Ok(AttachOperation(address, snapshot))
    }
    _ -> Error(fluid_container.UnsupportedMessage("expected a channel message"))
  }
}

fn routed_operation_decoder(
  operation_decoder: Decoder(operation),
) -> Decoder(#(String, operation)) {
  use contents <- decode.then(decode.dynamic)
  use operation <- decode.then(decode.at(
    ["contents", "contents", "content", "contents"],
    operation_decoder,
  ))
  case decode_operation_contents(contents) {
    Ok(ChannelOperation(address, _)) -> decode.success(#(address, operation))
    _ -> decode.failure(#("", operation), "routed channel operation")
  }
}

type AttachEntry {
  AttachBlob(contents: String)
  AttachTree(snapshot: Json)
}

fn attach_entries(
  snapshot: Json,
) -> Result(dict.Dict(String, AttachEntry), fluid_container.ContainerError) {
  use entries <- result.try(
    json.parse(
      json.to_string(snapshot),
      decode.field(
        "entries",
        decode.list({
          use path <- decode.field("path", decode.string)
          use mode <- decode.field("mode", decode.string)
          use kind <- decode.field("type", decode.string)
          use value <- decode.field("value", wire.json_value_decoder())
          decode.success(#(path, mode, kind, value))
        }),
        decode.success,
      ),
    )
    |> result.map_error(fn(_) {
      fluid_container.MalformedMessage("attach", "invalid snapshot entries")
    }),
  )
  list.try_fold(entries, dict.new(), fn(found, entry) {
    let #(path, mode, kind, value) = entry
    use _ <- result.try(case path != "" && !dict.has_key(found, path) {
      True -> Ok(Nil)
      False ->
        Error(fluid_container.MalformedMessage(
          "attach",
          "empty or duplicate entry path",
        ))
    })
    use value <- result.try(case kind, mode {
      "Tree", "040000" -> Ok(AttachTree(value))
      "Blob", "100644" ->
        json.parse(json.to_string(value), {
          use contents <- decode.field("contents", decode.string)
          use encoding <- decode.field("encoding", decode.string)
          case encoding {
            "utf-8" -> decode.success(contents)
            _ -> decode.failure("", "UTF-8 attach blob")
          }
        })
        |> result.map(AttachBlob)
        |> result.map_error(fn(_) {
          fluid_container.MalformedMessage("attach", "invalid UTF-8 blob")
        })
      _, _ ->
        Error(fluid_container.UnsupportedMessage("unsupported attach entry"))
    })
    Ok(dict.insert(found, path, value))
  })
}

fn attach_blob_contents(
  entries: dict.Dict(String, AttachEntry),
  path: String,
) -> Result(String, fluid_container.ContainerError) {
  case dict.get(entries, path) {
    Ok(AttachBlob(contents)) -> Ok(contents)
    _ ->
      Error(fluid_container.MalformedMessage("attach", "missing blob " <> path))
  }
}

fn attach_tree(
  entries: dict.Dict(String, AttachEntry),
  path: String,
) -> Result(Json, fluid_container.ContainerError) {
  case dict.get(entries, path) {
    Ok(AttachTree(snapshot)) -> Ok(snapshot)
    _ ->
      Error(fluid_container.MalformedMessage("attach", "missing tree " <> path))
  }
}

fn package_path_decoder() -> Decoder(List(String)) {
  decode.one_of(decode.list(decode.string), [
    {
      use raw <- decode.then(decode.string)
      case json.parse(raw, decode.list(decode.string)) {
        Ok(path) -> decode.success(path)
        Error(_) -> decode.failure([], "JSON package path")
      }
    },
  ])
}

pub fn decode_datastore_attach(
  contents: Json,
) -> Result(
  #(List(String), List(#(String, channel.Snapshot))),
  fluid_container.ContainerError,
) {
  use #(kind, snapshot) <- result.try(
    json.parse(json.to_string(contents), {
      use kind <- decode.field("type", decode.string)
      use snapshot <- decode.field("snapshot", wire.json_value_decoder())
      decode.success(#(kind, snapshot))
    })
    |> result.map_error(fn(_) {
      fluid_container.MalformedMessage(
        "datastore attach",
        "missing datastore metadata",
      )
    }),
  )
  use entries <- result.try(attach_entries(snapshot))
  use _ <- result.try(case list.sort(dict.keys(entries), string.compare) {
    [".channels", ".component"] -> Ok(Nil)
    _ ->
      Error(fluid_container.UnsupportedMessage(
        "unsupported datastore attach snapshot",
      ))
  })
  use component <- result.try(attach_blob_contents(entries, ".component"))
  use package_path <- result.try(
    json.parse(component, {
      use package_path <- decode.field("pkg", package_path_decoder())
      use version <- decode.field("summaryFormatVersion", decode.int)
      use _root <- decode.field("isRootDataStore", decode.bool)
      case
        version == 2
        && list.last(package_path) == Ok(kind)
        && list.all(package_path, fn(part) { part != "" })
      {
        True -> decode.success(package_path)
        False -> decode.failure([], "version 2 datastore package")
      }
    })
    |> result.map_error(fn(_) {
      fluid_container.MalformedMessage(
        "datastore attach",
        "unsupported component metadata",
      )
    }),
  )
  use channels <- result.try(attach_tree(entries, ".channels"))
  use channels <- result.try(attach_entries(channels))
  use channels <- result.try(
    list.try_map(dict.to_list(channels), fn(entry) {
      use snapshot <- result.try(attach_tree(channels, entry.0))
      use channel_entries <- result.try(attach_entries(snapshot))
      use attributes <- result.try(attach_blob_contents(
        channel_entries,
        ".attributes",
      ))
      use kind <- result.try(
        json.parse(attributes, decode.at(["type"], decode.string))
        |> result.map_error(fn(_) {
          fluid_container.MalformedMessage(
            "datastore attach",
            "missing channel type",
          )
        }),
      )
      use snapshot <- result.try(decode_attach_snapshot(kind, snapshot))
      Ok(#(entry.0, snapshot))
    }),
  )
  Ok(#(package_path, channels))
}

pub fn decode_attach_snapshot(
  channel_type: String,
  snapshot: Json,
) -> Result(channel.Snapshot, fluid_container.ContainerError) {
  use kind <- result.try(
    channel.fluid_string_to_type(channel_type)
    |> result.replace_error(fluid_container.UnsupportedMessage(channel_type)),
  )
  use entries <- result.try(attach_entries(snapshot))
  use _ <- result.try(
    case
      kind == channel.MapChannel
      || list.sort(dict.keys(entries), string.compare)
      == [".attributes", "header"]
    {
      True -> Ok(Nil)
      False ->
        Error(fluid_container.UnsupportedMessage(
          "unsupported channel attach snapshot",
        ))
    },
  )
  use attributes <- result.try(attach_blob_contents(entries, ".attributes"))
  use attributes <- result.try(
    json.parse(attributes, {
      use name <- decode.field("type", decode.string)
      use version <- decode.field("snapshotFormatVersion", decode.string)
      use package_version <- decode.field("packageVersion", decode.string)
      decode.success(#(name, version, package_version))
    })
    |> result.map_error(fn(_) {
      fluid_container.MalformedMessage("attach", "invalid channel attributes")
    }),
  )
  let expected = case kind {
    channel.MapChannel -> #(channel_type, "0.2", "3.1.0")
    _ -> #(channel_type, "1", "1")
  }
  use _ <- result.try(case attributes == expected {
    True -> Ok(Nil)
    False ->
      Error(fluid_container.UnsupportedMessage("unsupported channel attributes"))
  })
  use header <- result.try(attach_blob_contents(entries, "header"))
  let decoded = case kind {
    channel.MapChannel ->
      decode_map_attach(entries, header)
      |> result.map(channel.MapSnapshot)
    _ ->
      json.parse(header, channel.snapshot_decoder(kind))
      |> result.map_error(string.inspect)
  }
  decoded
  |> result.map_error(fn(detail) {
    fluid_container.MalformedMessage("attach", detail)
  })
}

fn decode_map_attach(
  blobs: dict.Dict(String, AttachEntry),
  header: String,
) -> Result(List(#(String, Json)), String) {
  use #(names, inline) <- result.try(decode_map_header_parts(header))
  use _ <- result.try(
    case
      list.sort(dict.keys(blobs), string.compare)
      == list.sort([".attributes", "header", ..names], string.compare)
    {
      True -> Ok(Nil)
      False -> Error("SharedMap blob references do not match its snapshot")
    },
  )
  use entries <- result.try(
    list.try_fold(names, inline, fn(entries, name) {
      use raw <- result.try(
        attach_blob_contents(blobs, name) |> result.map_error(string.inspect),
      )
      use more <- result.try(decode_map_content(raw))
      Ok(list.append(entries, more))
    }),
  )
  case list.length(entries) == dict.size(dict.from_list(entries)) {
    True -> Ok(entries)
    False -> Error("duplicate SharedMap key across snapshot blobs")
  }
}
