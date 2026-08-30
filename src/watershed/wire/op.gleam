//// Codecs for the contents of an `"op"` message. There are three kinds: a
//// kernel DDS operation in its `{address, contents}` document envelope, an
//// attach envelope that carries a channel snapshot, and the `"summarize"`
//// operation that announces a stored snapshot.
////
//// The `{address, contents}` envelope carries no channel type. The channel
//// registry is the authoritative source of the type of a channel, so the
//// decode has two stages. `decode_operation_contents` returns an attach
//// operation fully decoded, because the attach envelope has a `channelType`
//// field. It returns a channel operation as `#(address, Dynamic)` only. The
//// runtime then finds the type of the channel by its address and completes the
//// decode with `channel_operation_decoder`.
////
//// The map operation format in the envelope is the same as the format of the
//// TypeScript `@fluidframework/map` operations: `set`, `delete`, and `clear`,
//// with each value in a `{"type": "Plain", "value": ...}` wrapper. That
//// agreement is a convenience, because it keeps the vocabulary of the corpus
//// tests the same as the vocabulary of the TypeScript oracle. It is not a
//// compatibility contract. Nothing outside the project reads the wire formats
//// or the storage formats of watershed yet, so a format change needs a new
//// version and new fixtures, but it needs no migration code. Change a format
//// with care all the same. That freedom ends when real documents or real
//// clients exist.

import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}
import gleam/list
import gleam/option.{None, Some}

import lattice_core/replica_id
import lattice_core/version_vector
import lattice_counters/pn_counter
import lattice_maps/crdt
import lattice_maps/or_map
import lattice_sequence/sequence
import lattice_sets/g_set
import lattice_sets/or_set
import lattice_sets/two_p_set
import lattice_text/text
import watershed/channel
import watershed/claims_kernel.{type ClaimOperation, Claim}
import watershed/counter_kernel.{type CounterOperation, Increment}
import watershed/directory_kernel.{type DirectoryOperation}
import watershed/g_set_kernel.{type GSetOperation}
import watershed/json_ot
import watershed/json_ot_kernel.{type JsonOtWireOperation, JsonOtWireOperation}
import watershed/map_kernel.{type MapOperation, Clear, Delete, Set}
import watershed/or_map_kernel.{type OrMapOperation}
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
) -> OutboundOperation {
  wire.OutboundOperation(
    client_sequence_number: client_sequence_number,
    reference_sequence_number: reference_sequence_number,
    operation_type: "op",
    contents: encode_channel_envelope(address, operation),
    metadata: None,
  )
}

/// An attach envelope carries the full channel snapshot as
/// `{type:"attach", address, channelType, snapshot}`. The channel type sets the
/// shape of the `snapshot` payload.
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

pub fn outbound_attach_operation(
  address address: String,
  client_sequence_number client_sequence_number: Int,
  reference_sequence_number reference_sequence_number: Int,
  snapshot snapshot: channel.Snapshot,
) -> OutboundOperation {
  wire.OutboundOperation(
    client_sequence_number: client_sequence_number,
    reference_sequence_number: reference_sequence_number,
    operation_type: "op",
    contents: encode_attach(address, snapshot),
    metadata: None,
  )
}

/// A `"summarize"` operation that announces a stored snapshot. The contents
/// carry the fields that the `validate_summarize_contents` function of the
/// server needs: `handle`, the storage handle of the snapshot; `message`, the
/// commit message; `parents`, the handles of the parent summaries; and `head`,
/// the git tree SHA that the client uploaded. The client sets `handle` equal to
/// `head`, so a client that loads the summary can fetch the tree by its handle.
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

/// The `{address, contents}` document envelope around a kernel operation.
pub fn encode_channel_envelope(
  address: String,
  operation: channel.ChannelOperation,
) -> Json {
  json.object([
    #("address", json.string(address)),
    #("contents", encode_channel_operation(operation)),
  ])
}

pub fn encode_channel_operation(operation: channel.ChannelOperation) -> Json {
  case operation {
    channel.MapOperation(operation) -> encode_map_operation(operation)
    channel.CounterOperation(operation) -> encode_counter_operation(operation)
    channel.PnCounterOperation(operation) ->
      encode_pn_counter_operation(operation)
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

/// The `{address, contents}` document envelope around a map operation.
pub fn encode_map_envelope(address: String, operation: MapOperation) -> Json {
  json.object([
    #("address", json.string(address)),
    #("contents", encode_map_operation(operation)),
  ])
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

/// The `{address, contents}` document envelope around a SharedCounter
/// operation.
pub fn encode_counter_envelope(
  address: String,
  operation: CounterOperation,
) -> Json {
  json.object([
    #("address", json.string(address)),
    #("contents", encode_counter_operation(operation)),
  ])
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

/// The `{address, contents}` document envelope around a PnCounter operation.
pub fn encode_pn_counter_envelope(
  address: String,
  operation: PnCounterOperation,
) -> Json {
  json.object([
    #("address", json.string(address)),
    #("contents", encode_pn_counter_operation(operation)),
  ])
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

/// The `{address, contents}` document envelope around an OrMap operation.
pub fn encode_or_map_envelope(
  address: String,
  operation: OrMapOperation,
) -> Json {
  json.object([
    #("address", json.string(address)),
    #("contents", encode_or_map_operation(operation)),
  ])
}

pub fn encode_or_map_operation(operation: OrMapOperation) -> Json {
  case operation {
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

pub fn encode_or_set_envelope(
  address: String,
  operation: OrSetOperation,
) -> Json {
  json.object([
    #("address", json.string(address)),
    #("contents", encode_or_set_operation(operation)),
  ])
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
) -> Json {
  json.object([
    #("address", json.string(address)),
    #("contents", encode_g_set_operation(operation)),
  ])
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
) -> Json {
  json.object([
    #("address", json.string(address)),
    #("contents", encode_two_p_set_operation(operation)),
  ])
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
) -> Json {
  json.object([
    #("address", json.string(address)),
    #("contents", encode_register_collection_operation(operation)),
  ])
}

pub fn encode_register_collection_operation(operation: WriteOperation) -> Json {
  case operation {
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

pub fn encode_claim_envelope(
  address: String,
  operation: ClaimOperation,
) -> Json {
  json.object([
    #("address", json.string(address)),
    #("contents", encode_claim_operation(operation)),
  ])
}

pub fn encode_claim_operation(operation: ClaimOperation) -> Json {
  case operation {
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

/// Encode a json0 operation envelope. It contains the reference sequence number
/// that the components were written against, and the json0 component array.
pub fn encode_json_ot_operation(operation: JsonOtWireOperation) -> Json {
  json.object([
    #("refSeq", json.int(operation.ref_seq)),
    #("components", json_ot.operation_to_json(operation.components)),
  ])
}

/// Encode a rich-text operation envelope. It contains the reference sequence
/// number that the delta was written against, and the canonical Quill Delta
/// JSON array of that delta.
pub fn encode_rich_text_operation(operation: RichTextWireOperation) -> Json {
  json.object([
    #("refSeq", json.int(operation.ref_seq)),
    #("delta", rich_text.delta_to_json(operation.delta)),
  ])
}

pub fn encode_task_manager_envelope(
  address: String,
  operation: TaskManagerOperation,
) -> Json {
  json.object([
    #("address", json.string(address)),
    #("contents", encode_task_manager_operation(operation)),
  ])
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

/// The `{address, contents}` document envelope around a PactMap operation.
pub fn encode_pact_map_envelope(
  address: String,
  operation: pact_map_kernel.PactMapOperation,
) -> Json {
  json.object([
    #("address", json.string(address)),
    #("contents", encode_pact_map_operation(operation)),
  ])
}

/// Encode a PactMap operation. The value of a `Set` operation is an
/// `Option(Json)`. `None` is a true tombstone, which is not the same as
/// `Some(null)`, and it gets the `Absent` tag.
pub fn encode_pact_map_operation(
  operation: pact_map_kernel.PactMapOperation,
) -> Json {
  case operation {
    pact_map_kernel.Set(key, value, ref_seq) ->
      json.object([
        #("type", json.string("pactMapSet")),
        #("key", json.string(key)),
        #("value", encode_pact_map_value(value)),
        #("refSeq", json.int(ref_seq)),
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
  use address <- decode.field("address", decode.string)
  use operation <- decode.field("contents", pact_map_operation_decoder())
  decode.success(#(address, operation))
}

pub fn pact_map_operation_decoder() -> Decoder(pact_map_kernel.PactMapOperation) {
  use operation_type <- decode.field("type", decode.string)
  case operation_type {
    "pactMapSet" -> {
      use key <- decode.field("key", decode.string)
      use value <- decode.field("value", pact_map_value_decoder())
      use ref_seq <- decode.field("refSeq", decode.int)
      decode.success(pact_map_kernel.Set(key, value, ref_seq))
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

/// The `{address, contents}` document envelope around an ordered-collection
/// operation.
pub fn encode_ordered_envelope(
  address: String,
  operation: OrderedOperation,
) -> Json {
  json.object([
    #("address", json.string(address)),
    #("contents", encode_ordered_operation(operation)),
  ])
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
  use address <- decode.field("address", decode.string)
  use operation <- decode.field("contents", ordered_operation_decoder())
  decode.success(#(address, operation))
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

fn delta_json(delta: or_map.ORMapDelta) -> Json {
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
  use address <- decode.field("address", decode.string)
  use operation <- decode.field("contents", map_operation_decoder())
  decode.success(#(address, operation))
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
  use address <- decode.field("address", decode.string)
  use operation <- decode.field("contents", counter_operation_decoder())
  decode.success(#(address, operation))
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
  use address <- decode.field("address", decode.string)
  use operation <- decode.field("contents", pn_counter_operation_decoder())
  decode.success(#(address, operation))
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

pub fn or_map_operation_decoder() -> Decoder(OrMapOperation) {
  use operation_type <- decode.field("type", decode.string)
  case operation_type {
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
      use ref_seq <- decode.field("refSeq", decode.int)
      decode.success(Write(key, value, ref_seq))
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
      use ref_seq <- decode.field("refSeq", decode.int)
      decode.success(Claim(key, value, ref_seq))
    }
    _ -> decode.failure(Claim("", json.null(), 0), "ClaimOp")
  }
}

pub fn json_ot_operation_decoder() -> Decoder(JsonOtWireOperation) {
  use ref_seq <- decode.field("refSeq", decode.int)
  use components <- decode.field("components", json_ot.operation_decoder())
  decode.success(JsonOtWireOperation(ref_seq, components))
}

/// A strict decoder for a rich-text operation envelope. The `delta` field must
/// decode as a correct Quill Delta, which is an array of insert, delete, and
/// retain operations. A malformed delta fails the whole decode. The decoder
/// does not drop the operation.
pub fn rich_text_operation_decoder() -> Decoder(RichTextWireOperation) {
  use ref_seq <- decode.field("refSeq", decode.int)
  use delta <- decode.field("delta", rich_text_delta_decoder())
  decode.success(RichTextWireOperation(ref_seq, delta))
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
  use t <- decode.field("type", decode.string)
  case t {
    "attach" -> {
      use address <- decode.field("address", decode.string)
      use channel_type <- decode.field("channelType", decode.string)
      case channel.string_to_type(channel_type) {
        Ok(channel_type) -> {
          use snapshot <- decode.field(
            "snapshot",
            channel.snapshot_decoder(channel_type),
          )
          decode.success(AttachOperation(address: address, snapshot: snapshot))
        }
        Error(_) ->
          decode.failure(
            AttachOperation(address: "", snapshot: channel.MapSnapshot([])),
            "ChannelType",
          )
      }
    }
    _ ->
      decode.failure(
        AttachOperation(address: "", snapshot: channel.MapSnapshot([])),
        "AttachEnvelope",
      )
  }
}

pub fn decode_operation_contents(
  contents: Dynamic,
) -> Result(OperationContents, List(decode.DecodeError)) {
  // An explicit top-level `type: "attach"` must decode as an attach envelope
  // (no fallback); anything else decodes as the `{address, contents}`
  // envelope, its payload left for stage-two decoding by channel type.
  case decode.run(contents, decode.at(["type"], decode.string)) {
    Ok("attach") -> decode.run(contents, attach_envelope_decoder())
    _ -> decode.run(contents, channel_envelope_decoder())
  }
}

fn channel_envelope_decoder() -> Decoder(OperationContents) {
  use address <- decode.field("address", decode.string)
  use contents <- decode.field("contents", decode.dynamic)
  decode.success(ChannelOperation(address: address, contents: contents))
}
