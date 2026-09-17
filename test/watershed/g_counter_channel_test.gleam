import gleam/dict
import gleam/json
import gleam/option.{None, Some}
import gleam/string
import startest/expect

import lattice_core/replica_id
import signet/types as token
import spillway/message
import spillway/types
import watershed/channel
import watershed/g_counter_kernel
import watershed/handle
import watershed/runtime_core.{type Core}

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

pub fn g_counter_channel_type_round_trips_test() -> Nil {
  channel.type_to_string(channel.GCounterChannel)
  |> expect.to_equal("gCounter")

  channel.type_to_string(channel.GCounterChannel)
  |> channel.string_to_type
  |> expect.to_equal(Ok(channel.GCounterChannel))
}

pub fn g_counter_snapshot_round_trips_test() -> Nil {
  let assert Ok(#(state, _, operation, _)) =
    g_counter_kernel.increment(g_counter_kernel.new(replica_id.new("r1")), 9)
  let assert Ok(state) = g_counter_kernel.ack_local(state, operation)
  let snapshot = channel.GCounterSnapshot(state.sequenced)
  let encoded = channel.encode_snapshot(snapshot)
  let assert Ok(decoded) =
    json.parse(
      json.to_string(encoded),
      channel.snapshot_decoder(channel.GCounterChannel),
    )

  channel.same_snapshot(snapshot, decoded) |> expect.to_be_true()
}

pub fn detached_g_counter_increments_and_then_emits_operations_test() -> Nil {
  let address = "gc-1"
  let core =
    bootstrap()
    |> runtime_core.create_detached(address, channel.InitGCounter)

  let assert Ok(#(core, events, outbound)) =
    runtime_core.g_counter_increment(core, address, 4)
  events
  |> expect.to_equal([
    #(address, channel.GCounterEvent(g_counter_kernel.Updated(4, 4))),
  ])
  outbound |> expect.to_equal([])
  runtime_core.g_counter_value(core, address) |> expect.to_equal(Ok(4))

  let assert Ok(#(core, _, _)) =
    runtime_core.set(core, "root", "hits", handle.encode_handle(address))

  let assert Ok(#(core, events, [operation])) =
    runtime_core.g_counter_increment(core, address, 2)
  events
  |> expect.to_equal([
    #(address, channel.GCounterEvent(g_counter_kernel.Updated(2, 6))),
  ])
  runtime_core.g_counter_value(core, address) |> expect.to_equal(Ok(6))

  let encoded = json.to_string(operation.contents)
  encoded
  |> string.contains("\"address\":\"" <> address <> "\"")
  |> expect.to_be_true()
  encoded
  |> string.contains("\"type\":\"gCounterIncrement\"")
  |> expect.to_be_true()
  encoded |> string.contains("\"amount\":2") |> expect.to_be_true()
}

pub fn g_counter_refuses_a_negative_increment_test() -> Nil {
  let address = "gc-2"
  let core =
    bootstrap()
    |> runtime_core.create_detached(address, channel.InitGCounter)

  let assert Ok(#(core, _, _)) =
    runtime_core.g_counter_increment(core, address, 7)
  let assert Ok(#(core, _, _)) =
    runtime_core.set(core, "root", "hits", handle.encode_handle(address))

  let before = core
  let assert Error(runtime_core.GCounterOperationFailed(failed_address, _)) =
    runtime_core.g_counter_increment(core, address, -1)
  failed_address |> expect.to_equal(address)

  // The refused edit leaves the core untouched, so no sequence number moves.
  runtime_core.g_counter_value(before, address) |> expect.to_equal(Ok(7))
}

pub fn g_counter_read_rejects_another_channel_type_test() -> Nil {
  let core =
    bootstrap()
    |> runtime_core.create_detached("pnc", channel.InitPnCounter)

  runtime_core.g_counter_value(core, "pnc") |> expect.to_equal(Error(Nil))

  let assert Error(runtime_core.WrongChannelType(
    address: "pnc",
    expected: channel.GCounterChannel,
    ..,
  )) = runtime_core.g_counter_increment(core, "pnc", 1)
  Nil
}
