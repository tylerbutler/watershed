import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import lattice_core/replica_id
import lattice_sequence/sequence
import signet/types as token
import spillway/message
import spillway/types
import startest/expect
import watershed/channel
import watershed/handle
import watershed/map_kernel
import watershed/runtime_core.{type Core}
import watershed/sequence_kernel
import watershed/wire.{type OutboundOp}
import watershed/wire/ops

const client_id = "default_doc_1"

fn connected_message() -> message.ConnectedMessage {
  message.ConnectedMessage(
    claims: token.TokenClaims(
      document_id: "doc",
      scopes: [token.DocRead, token.DocWrite],
      tenant_id: "default",
      user: token.User(id: "user", properties: dict.new()),
      issued_at: 0,
      expiration: 0,
      version: "1.0",
      jti: None,
    ),
    client_id: client_id,
    existing: True,
    max_message_size: 16_000,
    mode: types.WriteMode,
    service_configuration: types.ServiceConfiguration(
      block_size: 65_536,
      max_message_size: 16_000,
      noop_time_frequency: None,
      noop_count_frequency: None,
    ),
    initial_clients: [],
    initial_messages: [],
    initial_signals: [],
    supported_versions: ["^0.1.0"],
    supported_features: dict.new(),
    version: "^0.1.0",
    timestamp: None,
    checkpoint_sequence_number: Some(1),
    epoch: None,
    relay_service_agent: None,
    summary_context: None,
  )
}

fn bootstrap() -> Core {
  let assert Ok(runtime_core.Complete(core)) =
    runtime_core.bootstrap(connected_message(), summary: None)
  core
}

fn decode_attach(op: OutboundOp) -> #(String, channel.Snapshot) {
  let assert Ok(dynamic_value) =
    json.parse(json.to_string(op.contents), decode.dynamic)
  let assert Ok(ops.AttachOp(address, snapshot)) =
    ops.decode_op_contents(dynamic_value)
  #(address, snapshot)
}

pub fn detached_sequence_attaches_then_emits_ops_test() {
  let address = "sequence-1"
  let core =
    bootstrap()
    |> runtime_core.create_detached(address, channel.InitSequence)

  let assert Ok(#(core, events, outbound)) =
    runtime_core.sequence_insert(core, address, 0, json.string("a"))
  outbound |> expect.to_equal([])
  events
  |> expect.to_equal([
    #(
      address,
      channel.SequenceEvent(sequence_kernel.SequenceChanged([json.string("a")])),
    ),
  ])

  let assert Ok(#(core, _, [child_attach, root_handle_op])) =
    runtime_core.set(core, "root", "items", handle.encode_handle(address))
  let #(child_address, child_snapshot) = decode_attach(child_attach)
  child_address |> expect.to_equal(address)
  let assert channel.SequenceState(child_kernel) =
    channel.from_snapshot(child_snapshot, replica: client_id)
  sequence_kernel.values(child_kernel) |> expect.to_equal([json.string("a")])

  let assert Ok(dynamic_value) =
    json.parse(json.to_string(root_handle_op.contents), decode.dynamic)
  let assert Ok(ops.ChannelOp("root", contents)) =
    ops.decode_op_contents(dynamic_value)
  let assert Ok(channel.MapOp(map_kernel.Set("items", value))) =
    decode.run(contents, ops.channel_op_decoder(channel.MapChannel))
  value |> expect.to_equal(handle.encode_handle(address))

  let assert Ok(#(core, _, [op])) =
    runtime_core.sequence_replace(core, address, 0, json.string("A"))
  json.to_string(op.contents)
  |> string.contains("\"type\":\"sequenceReplace\"")
  |> expect.to_be_true()
  runtime_core.sequence_values(core, address)
  |> expect.to_equal([json.string("A")])
  runtime_core.sequence_length(core, address) |> expect.to_equal(1)
}

pub fn sequence_invalid_index_is_explicit_core_error_test() {
  let core =
    bootstrap()
    |> runtime_core.create_detached("sequence-1", channel.InitSequence)

  runtime_core.sequence_delete(core, "sequence-1", 0)
  |> expect.to_equal(
    Error(runtime_core.SequenceOpFailed(
      "sequence-1",
      "delete index 0 invalid for length 0",
    )),
  )
}

pub fn attached_sequence_move_and_delete_emit_ops_test() {
  let address = "sequence-1"
  let core =
    bootstrap()
    |> runtime_core.create_detached(address, channel.InitSequence)
  let assert Ok(#(core, _, [])) =
    runtime_core.sequence_insert(core, address, 0, json.string("a"))
  let assert Ok(#(core, _, [])) =
    runtime_core.sequence_insert(core, address, 1, json.string("b"))
  let assert Ok(#(core, _, [])) =
    runtime_core.sequence_insert(core, address, 2, json.string("c"))
  let assert Ok(#(core, _, _)) =
    runtime_core.set(core, "root", "items", handle.encode_handle(address))

  let assert Ok(#(core, _, [move_op])) =
    runtime_core.sequence_move(core, address, 2, 0)
  json.to_string(move_op.contents)
  |> string.contains("\"type\":\"sequenceMove\"")
  |> expect.to_be_true()
  runtime_core.sequence_values(core, address)
  |> expect.to_equal([json.string("c"), json.string("a"), json.string("b")])
  runtime_core.sequence_length(core, address) |> expect.to_equal(3)

  let assert Ok(#(core, _, [delete_op])) =
    runtime_core.sequence_delete(core, address, 1)
  json.to_string(delete_op.contents)
  |> string.contains("\"type\":\"sequenceDelete\"")
  |> expect.to_be_true()
  runtime_core.sequence_values(core, address)
  |> expect.to_equal([json.string("c"), json.string("b")])
  runtime_core.sequence_length(core, address) |> expect.to_equal(2)
}

pub fn sequence_same_shape_treats_equivalent_numbers_as_equal_test() {
  let assert Ok(#(_, _, op, _)) =
    sequence_kernel.insert(
      sequence_kernel.new(replica_id.new("client-a")),
      0,
      json.float(1.0),
    )
  let assert sequence_kernel.Insert(index, _, delta) = op
  let echoed = sequence_kernel.Insert(index, json.int(1), delta)

  channel.same_shape(channel.SequenceOp(op), channel.SequenceOp(echoed))
  |> expect.to_be_true()
}

pub fn sequence_same_shape_rejects_altered_delta_test() {
  let assert Ok(#(_, _, op, _)) =
    sequence_kernel.insert(
      sequence_kernel.new(replica_id.new("client-a")),
      0,
      json.string("Ada"),
    )
  let assert sequence_kernel.Insert(index, value, _) = op
  let altered =
    sequence_kernel.Insert(
      index,
      value,
      sequence.new(replica_id.new("attacker")),
    )

  channel.same_shape(channel.SequenceOp(op), channel.SequenceOp(altered))
  |> expect.to_be_false()
}

pub fn attached_sequence_insert_attaches_nested_handle_first_test() {
  let address = "sequence-1"
  let child = "child-1"
  let nested_handle =
    json.object([
      #(
        "items",
        json.array(
          [json.object([#("handle", handle.encode_handle(child))])],
          fn(value) { value },
        ),
      ),
    ])
  let core =
    bootstrap()
    |> runtime_core.create_detached(address, channel.InitSequence)
    |> runtime_core.create_detached(child, channel.InitMap)
  let assert Ok(#(core, _, _)) =
    runtime_core.set(core, "root", "items", handle.encode_handle(address))
  runtime_core.summary_channels(core)
  |> list.map(fn(entry) { entry.0 })
  |> expect.to_equal(["root", address])

  let assert Ok(#(core, _, [child_attach, sequence_op])) =
    runtime_core.sequence_insert(core, address, 0, nested_handle)
  let #(child_address, _) = decode_attach(child_attach)
  child_address |> expect.to_equal(child)
  json.to_string(sequence_op.contents)
  |> string.contains("\"type\":\"sequenceInsert\"")
  |> expect.to_be_true()

  let assert Ok(#(_, _, [_])) =
    runtime_core.set(core, child, "ready", json.bool(True))
  Nil
}

pub fn attached_sequence_replace_attaches_nested_handle_first_test() {
  let address = "sequence-1"
  let child = "child-1"
  let nested_handle =
    json.object([
      #(
        "items",
        json.array(
          [json.object([#("handle", handle.encode_handle(child))])],
          fn(value) { value },
        ),
      ),
    ])
  let core =
    bootstrap()
    |> runtime_core.create_detached(address, channel.InitSequence)
    |> runtime_core.create_detached(child, channel.InitMap)
  let assert Ok(#(core, _, [])) =
    runtime_core.sequence_insert(core, address, 0, json.string("old"))
  let assert Ok(#(core, _, _)) =
    runtime_core.set(core, "root", "items", handle.encode_handle(address))
  runtime_core.summary_channels(core)
  |> list.map(fn(entry) { entry.0 })
  |> expect.to_equal(["root", address])

  let assert Ok(#(core, _, [child_attach, sequence_op])) =
    runtime_core.sequence_replace(core, address, 0, nested_handle)
  let #(child_address, _) = decode_attach(child_attach)
  child_address |> expect.to_equal(child)
  json.to_string(sequence_op.contents)
  |> string.contains("\"type\":\"sequenceReplace\"")
  |> expect.to_be_true()

  let assert Ok(#(_, _, [_])) =
    runtime_core.set(core, child, "ready", json.bool(True))
  Nil
}

pub fn sequence_edit_errors_preserve_optimistic_state_test() {
  let address = "sequence-1"
  let empty =
    bootstrap()
    |> runtime_core.create_detached(address, channel.InitSequence)

  runtime_core.sequence_insert(empty, address, 1, json.string("a"))
  |> expect.to_equal(
    Error(runtime_core.SequenceOpFailed(address, "insert index 1 outside 0..0")),
  )
  runtime_core.sequence_values(empty, address) |> expect.to_equal([])
  runtime_core.sequence_length(empty, address) |> expect.to_equal(0)

  runtime_core.sequence_delete(empty, address, 0)
  |> expect.to_equal(
    Error(runtime_core.SequenceOpFailed(
      address,
      "delete index 0 invalid for length 0",
    )),
  )
  runtime_core.sequence_values(empty, address) |> expect.to_equal([])
  runtime_core.sequence_length(empty, address) |> expect.to_equal(0)

  runtime_core.sequence_move(empty, address, 0, 0)
  |> expect.to_equal(
    Error(runtime_core.SequenceOpFailed(
      address,
      "move source index 0 invalid for length 0",
    )),
  )
  runtime_core.sequence_values(empty, address) |> expect.to_equal([])
  runtime_core.sequence_length(empty, address) |> expect.to_equal(0)

  runtime_core.sequence_replace(empty, address, 0, json.string("A"))
  |> expect.to_equal(
    Error(runtime_core.SequenceOpFailed(
      address,
      "replace index 0 invalid for length 0",
    )),
  )
  runtime_core.sequence_values(empty, address) |> expect.to_equal([])
  runtime_core.sequence_length(empty, address) |> expect.to_equal(0)

  let assert Ok(#(populated, _, [])) =
    runtime_core.sequence_insert(empty, address, 0, json.string("a"))
  runtime_core.sequence_move(populated, address, 0, 1)
  |> expect.to_equal(
    Error(runtime_core.SequenceOpFailed(
      address,
      "move destination index 1 outside 0..0",
    )),
  )
  runtime_core.sequence_values(populated, address)
  |> expect.to_equal([json.string("a")])
  runtime_core.sequence_length(populated, address) |> expect.to_equal(1)
}

pub fn sequence_wrong_type_and_unknown_address_errors_test() {
  let core = bootstrap()

  runtime_core.sequence_insert(core, "root", 0, json.string("a"))
  |> expect.to_equal(
    Error(runtime_core.WrongChannelType(
      address: "root",
      expected: channel.SequenceChannel,
      actual: channel.MapChannel,
    )),
  )
  runtime_core.sequence_insert(core, "missing", 0, json.string("a"))
  |> expect.to_equal(
    Error(runtime_core.UnknownChannel(address: "missing", sequence_number: 1)),
  )
}

pub fn sequence_summary_round_trips_test() {
  let assert Ok(#(state, _, op, _)) =
    sequence_kernel.insert(
      sequence_kernel.new(replica_id.new("a")),
      0,
      json.object([
        #("second", json.int(2)),
        #("first", json.int(1)),
      ]),
    )
  let assert Ok(state) = sequence_kernel.ack_local(state, op)
  let summary = channel.SequenceSummary(state.sequenced)
  let encoded = channel.encode_snapshot(summary)
  let assert Ok(decoded) =
    json.parse(
      json.to_string(encoded),
      channel.snapshot_decoder(channel.SequenceChannel),
    )

  channel.same_snapshot(summary, decoded) |> expect.to_be_true()
}

pub fn sequence_discovers_nested_handles_test() {
  let assert Ok(#(state, _, _, _)) =
    sequence_kernel.insert(
      sequence_kernel.new(replica_id.new("a")),
      0,
      json.object([
        #(
          "items",
          json.array(
            [json.object([#("handle", handle.encode_handle("child"))])],
            fn(value) { value },
          ),
        ),
      ]),
    )
  channel.handle_addresses(channel.SequenceState(state))
  |> expect.to_equal(["child"])
}
