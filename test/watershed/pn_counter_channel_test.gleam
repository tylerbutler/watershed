import gleam/dict
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import startest/expect

import lattice_core/replica_id
import signet/types as token
import spillway/message
import spillway/types
import watershed/channel
import watershed/handle
import watershed/pn_counter_kernel
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

pub fn detached_pn_counter_updates_and_then_emits_ops_test() {
  let address = "pnc-1"
  let core =
    bootstrap()
    |> runtime_core.create_detached(address, channel.InitPnCounter)

  let assert Ok(#(core, events, outbound)) =
    runtime_core.pn_counter_update(core, address, 5)
  events
  |> expect.to_equal([
    #(address, channel.PnCounterEvent(pn_counter_kernel.Updated(5, 5))),
  ])
  outbound |> expect.to_equal([])
  runtime_core.pn_counter_value(core, address) |> expect.to_equal(Some(5))

  // A decrement moves the optimistic value the other way.
  let assert Ok(#(core, _, _)) =
    runtime_core.pn_counter_update(core, address, -2)
  runtime_core.pn_counter_value(core, address) |> expect.to_equal(Some(3))

  let assert Ok(#(core, _, _)) =
    runtime_core.set(core, "root", "count", handle.encode_handle(address))

  let assert Ok(#(_core, events, [op])) =
    runtime_core.pn_counter_update(core, address, 4)
  events
  |> expect.to_equal([
    #(address, channel.PnCounterEvent(pn_counter_kernel.Updated(4, 7))),
  ])
  let encoded = json.to_string(op.contents)
  encoded
  |> string.contains("\"address\":\"" <> address <> "\"")
  |> expect.to_be_true()
  encoded
  |> string.contains("\"type\":\"pnCounterUpdate\"")
  |> expect.to_be_true()
  encoded |> string.contains("\"amount\":4") |> expect.to_be_true()
}

pub fn pn_counter_snapshot_round_trips_test() {
  let #(state, _, op, _) =
    pn_counter_kernel.update(pn_counter_kernel.new(replica_id.new("r1")), 9)
  let assert Ok(state) = pn_counter_kernel.ack_local(state, op)
  let snapshot = channel.PnCounterSnapshot(state.sequenced)
  let encoded = channel.encode_snapshot(snapshot)
  let assert Ok(decoded) =
    json.parse(
      json.to_string(encoded),
      channel.snapshot_decoder(channel.PnCounterChannel),
    )

  channel.same_snapshot(snapshot, decoded) |> expect.to_be_true()
}

pub fn pn_counter_channel_type_round_trips_test() {
  channel.type_to_string(channel.PnCounterChannel)
  |> channel.type_from_string
  |> expect.to_equal(Ok(channel.PnCounterChannel))
}

pub fn detached_pn_counter_attaches_with_optimistic_value_test() {
  let address = "pnc-2"
  let core =
    bootstrap()
    |> runtime_core.create_detached(address, channel.InitPnCounter)

  let assert Ok(#(core, _, _)) =
    runtime_core.pn_counter_update(core, address, 3)

  let assert Ok(#(core, _, attach_outbound)) =
    runtime_core.set(core, "root", "count", handle.encode_handle(address))
  attach_outbound |> list.length |> expect.to_equal(2)

  // The attach preserves the detached optimistic value.
  runtime_core.pn_counter_value(core, address) |> expect.to_equal(Some(3))
}
