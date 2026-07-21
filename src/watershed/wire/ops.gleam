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
import gleam/option.{None, Some}

import lattice_core/replica_id
import lattice_counters/pn_counter
import lattice_maps/crdt
import lattice_maps/or_map
import lattice_sequence/sequence
import lattice_sets/g_set
import lattice_sets/or_set
import lattice_sets/two_p_set
import watershed/channel
import watershed/claims_kernel.{type ClaimOp, Claim}
import watershed/counter_kernel.{type CounterOp, Increment}
import watershed/directory_kernel.{type DirectoryOp}
import watershed/g_set_kernel.{type GSetOp}
import watershed/json_ot
import watershed/json_ot_kernel.{type JsonOtWireOp, JsonOtWireOp}
import watershed/map_kernel.{type MapOp, Clear, Delete, Set}
import watershed/or_map_kernel.{type OrMapOp}
import watershed/or_set_kernel.{type OrSetOp}
import watershed/ordered_collection_kernel.{type OrderedOp}
import watershed/pact_map_kernel
import watershed/pn_counter_kernel.{type PnCounterOp}
import watershed/register_collection_kernel.{type WriteOp, Write}
import watershed/sequence_kernel.{type SequenceOp}
import watershed/task_manager_kernel.{type TaskManagerOp}
import watershed/two_p_set_kernel.{type TwoPSetOp}
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
    channel.PnCounterOp(op) -> encode_pn_counter_op(op)
    channel.OrMapOp(op) -> encode_or_map_op(op)
    channel.OrSetOp(op) -> encode_or_set_op(op)
    channel.GSetOp(op) -> encode_g_set_op(op)
    channel.TwoPSetOp(op) -> encode_two_p_set_op(op)
    channel.RegisterCollectionOp(op) -> encode_register_collection_op(op)
    channel.ClaimsOp(op) -> encode_claim_op(op)
    channel.TaskManagerOp(op) -> encode_task_manager_op(op)
    channel.JsonOtOp(op) -> encode_json_ot_op(op)
    channel.DirectoryOp(op, message_id) -> encode_directory_op(op, message_id)
    channel.PactMapOp(op) -> encode_pact_map_op(op)
    channel.OrderedCollectionOp(op) -> encode_ordered_op(op)
    channel.SequenceOp(op) -> encode_sequence_op(op)
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
    channel.PnCounterChannel ->
      pn_counter_op_decoder() |> decode.map(channel.PnCounterOp)
    channel.OrMapChannel -> or_map_op_decoder() |> decode.map(channel.OrMapOp)
    channel.OrSetChannel -> or_set_op_decoder() |> decode.map(channel.OrSetOp)
    channel.GSetChannel -> g_set_op_decoder() |> decode.map(channel.GSetOp)
    channel.TwoPSetChannel ->
      two_p_set_op_decoder() |> decode.map(channel.TwoPSetOp)
    channel.RegisterCollectionChannel ->
      register_collection_op_decoder()
      |> decode.map(channel.RegisterCollectionOp)
    channel.ClaimsChannel -> claim_op_decoder() |> decode.map(channel.ClaimsOp)
    channel.TaskManagerChannel ->
      task_manager_op_decoder() |> decode.map(channel.TaskManagerOp)
    channel.JsonOtChannel ->
      json_ot_op_decoder() |> decode.map(channel.JsonOtOp)
    channel.DirectoryChannel -> directory_op_decoder()
    channel.PactMapChannel ->
      pact_map_op_decoder() |> decode.map(channel.PactMapOp)
    channel.OrderedCollectionChannel ->
      ordered_op_decoder() |> decode.map(channel.OrderedCollectionOp)
    channel.SequenceChannel ->
      sequence_op_decoder() |> decode.map(channel.SequenceOp)
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

/// `{address, contents}` document envelope around a PnCounter op.
pub fn encode_pn_counter_envelope(address: String, op: PnCounterOp) -> Json {
  json.object([
    #("address", json.string(address)),
    #("contents", encode_pn_counter_op(op)),
  ])
}

pub fn encode_pn_counter_op(op: PnCounterOp) -> Json {
  case op {
    pn_counter_kernel.Update(amount, delta) ->
      json.object([
        #("type", json.string("pnCounterUpdate")),
        #("amount", json.int(amount)),
        #("delta", pn_counter_delta_json(delta)),
      ])
  }
}

/// `{address, contents}` document envelope around a OrMap op.
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

pub fn encode_g_set_envelope(address: String, op: GSetOp) -> Json {
  json.object([
    #("address", json.string(address)),
    #("contents", encode_g_set_op(op)),
  ])
}

pub fn encode_g_set_op(op: GSetOp) -> Json {
  case op {
    g_set_kernel.Add(element, delta) ->
      json.object([
        #("type", json.string("gSetAdd")),
        #("element", json.string(element)),
        #("delta", g_set_delta_json(delta)),
      ])
  }
}

pub fn encode_two_p_set_envelope(address: String, op: TwoPSetOp) -> Json {
  json.object([
    #("address", json.string(address)),
    #("contents", encode_two_p_set_op(op)),
  ])
}

pub fn encode_two_p_set_op(op: TwoPSetOp) -> Json {
  case op {
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

/// Encode a json0 op envelope: the reference sequence number the components
/// were authored against plus the json0 component array itself.
pub fn encode_json_ot_op(op: JsonOtWireOp) -> Json {
  json.object([
    #("refSeq", json.int(op.ref_seq)),
    #("components", json_ot.op_to_json(op.components)),
  ])
}

pub fn encode_task_manager_envelope(
  address: String,
  op: TaskManagerOp,
) -> Json {
  json.object([
    #("address", json.string(address)),
    #("contents", encode_task_manager_op(op)),
  ])
}

pub fn encode_task_manager_op(op: TaskManagerOp) -> Json {
  case op {
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

/// Encode a SharedDirectory op. Every variant carries `path` (the absolute
/// directory address) and `mid` — the kernel's `message_id`, which is the op's
/// client-sequence identity; a remote client needs it to run the
/// stale-instance filter and sibling ordering.
pub fn encode_directory_op(op: DirectoryOp, message_id: Int) -> Json {
  case op {
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

fn directory_op_decoder() -> Decoder(channel.ChannelOp) {
  use op_type <- decode.field("type", decode.string)
  use path <- decode.field("path", decode.string)
  use message_id <- decode.field("mid", decode.int)
  case op_type {
    "dirSet" -> {
      use key <- decode.field("key", decode.string)
      use value <- decode.field("value", plain_value_decoder())
      decode.success(channel.DirectoryOp(
        directory_kernel.Set(path, key, value),
        message_id,
      ))
    }
    "dirDelete" -> {
      use key <- decode.field("key", decode.string)
      decode.success(channel.DirectoryOp(
        directory_kernel.Delete(path, key),
        message_id,
      ))
    }
    "dirClear" ->
      decode.success(channel.DirectoryOp(
        directory_kernel.Clear(path),
        message_id,
      ))
    "dirCreateSub" -> {
      use name <- decode.field("name", decode.string)
      decode.success(channel.DirectoryOp(
        directory_kernel.CreateSubDirectory(path, name),
        message_id,
      ))
    }
    "dirDeleteSub" -> {
      use name <- decode.field("name", decode.string)
      decode.success(channel.DirectoryOp(
        directory_kernel.DeleteSubDirectory(path, name),
        message_id,
      ))
    }
    _ ->
      decode.failure(
        channel.DirectoryOp(directory_kernel.Clear(path), message_id),
        "DirectoryOp",
      )
  }
}

/// `{address, contents}` document envelope around a PactMap op.
pub fn encode_pact_map_envelope(
  address: String,
  op: pact_map_kernel.PactMapOp,
) -> Json {
  json.object([
    #("address", json.string(address)),
    #("contents", encode_pact_map_op(op)),
  ])
}

/// Encode a PactMap op. A `Set` value is `Option(Json)`: `None` is a genuine
/// tombstone (distinct from `Some(null)`) and gets an `Absent` tag.
pub fn encode_pact_map_op(op: pact_map_kernel.PactMapOp) -> Json {
  case op {
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
) -> Result(#(String, pact_map_kernel.PactMapOp), List(decode.DecodeError)) {
  decode.run(contents, pact_map_envelope_decoder())
}

pub fn pact_map_envelope_decoder() -> Decoder(
  #(String, pact_map_kernel.PactMapOp),
) {
  use address <- decode.field("address", decode.string)
  use op <- decode.field("contents", pact_map_op_decoder())
  decode.success(#(address, op))
}

pub fn pact_map_op_decoder() -> Decoder(pact_map_kernel.PactMapOp) {
  use op_type <- decode.field("type", decode.string)
  case op_type {
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

/// `{address, contents}` document envelope around an ordered-collection op.
pub fn encode_ordered_envelope(address: String, op: OrderedOp) -> Json {
  json.object([
    #("address", json.string(address)),
    #("contents", encode_ordered_op(op)),
  ])
}

pub fn encode_ordered_op(op: OrderedOp) -> Json {
  case op {
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
) -> Result(#(String, OrderedOp), List(decode.DecodeError)) {
  decode.run(contents, ordered_envelope_decoder())
}

pub fn ordered_envelope_decoder() -> Decoder(#(String, OrderedOp)) {
  use address <- decode.field("address", decode.string)
  use op <- decode.field("contents", ordered_op_decoder())
  decode.success(#(address, op))
}

pub fn ordered_op_decoder() -> Decoder(OrderedOp) {
  use op_type <- decode.field("type", decode.string)
  case op_type {
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

pub fn sequence_op_decoder() -> Decoder(SequenceOp) {
  use op_type <- decode.field("type", decode.string)
  case op_type {
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

pub fn encode_sequence_op(op: SequenceOp) -> Json {
  case op {
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

/// Decode the `contents` of a sequenced `"op"` message into
/// `#(address, PnCounterOp)`.
pub fn decode_pn_counter_envelope(
  contents: Dynamic,
) -> Result(#(String, PnCounterOp), List(decode.DecodeError)) {
  decode.run(contents, pn_counter_envelope_decoder())
}

pub fn pn_counter_envelope_decoder() -> Decoder(#(String, PnCounterOp)) {
  use address <- decode.field("address", decode.string)
  use op <- decode.field("contents", pn_counter_op_decoder())
  decode.success(#(address, op))
}

pub fn pn_counter_op_decoder() -> Decoder(PnCounterOp) {
  use op_type <- decode.field("type", decode.string)
  case op_type {
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

pub fn g_set_op_decoder() -> Decoder(GSetOp) {
  use op_type <- decode.field("type", decode.string)
  case op_type {
    "gSetAdd" -> {
      use element <- decode.field("element", decode.string)
      use delta <- decode.field("delta", g_set_delta_decoder())
      let op: GSetOp = g_set_kernel.Add(element, delta)
      decode.success(op)
    }
    _ -> decode.failure(g_set_kernel.Add("", default_g_set_delta()), "GSetOp")
  }
}

pub fn two_p_set_op_decoder() -> Decoder(TwoPSetOp) {
  use op_type <- decode.field("type", decode.string)
  case op_type {
    "twoPSetAdd" -> {
      use element <- decode.field("element", decode.string)
      use delta <- decode.field("delta", two_p_set_delta_decoder())
      let op: TwoPSetOp = two_p_set_kernel.Add(element, delta)
      decode.success(op)
    }
    "twoPSetRemove" -> {
      use element <- decode.field("element", decode.string)
      use delta <- decode.field("delta", two_p_set_delta_decoder())
      let op: TwoPSetOp = two_p_set_kernel.Remove(element, delta)
      decode.success(op)
    }
    _ ->
      decode.failure(
        two_p_set_kernel.Add("", default_two_p_set_delta()),
        "TwoPSetOp",
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

pub fn json_ot_op_decoder() -> Decoder(JsonOtWireOp) {
  use ref_seq <- decode.field("refSeq", decode.int)
  use components <- decode.field("components", json_ot.op_decoder())
  decode.success(JsonOtWireOp(ref_seq, components))
}

pub fn task_manager_op_decoder() -> Decoder(TaskManagerOp) {
  use op_type <- decode.field("type", decode.string)
  case op_type {
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
  case sequence.from_json(encoded, wire.json_value_decoder()) {
    Ok(delta) -> decode.success(delta)
    Error(_) -> decode.failure(default_sequence_delta(), "SequenceDelta")
  }
}

fn default_pn_counter_delta() -> pn_counter.PNCounter {
  pn_counter.new(replica_id.new(""))
}

fn default_sequence_delta() -> sequence.Sequence(Json) {
  sequence.new(replica_id.new(""))
}

fn default_two_p_set_delta() -> two_p_set.TwoPSet(String) {
  two_p_set.new()
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
