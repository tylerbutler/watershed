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
import watershed/or_set_kernel
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

pub fn detached_or_set_attaches_and_then_emits_delta_ops_test() {
  let address = "set-1"
  let core =
    bootstrap()
    |> runtime_core.create_detached(address, channel.InitOrSet)

  let assert Ok(#(core, events, outbound)) =
    runtime_core.or_set_add(core, address, "alice")
  events
  |> expect.to_equal([
    #(address, channel.OrSetEvent(or_set_kernel.ElementAdded("alice"))),
  ])
  outbound |> expect.to_equal([])
  runtime_core.or_set_values(core, address) |> expect.to_equal(["alice"])

  let assert Ok(#(core, _, attach_outbound)) =
    runtime_core.set(core, "root", "members", handle.encode_handle(address))
  attach_outbound |> list_length |> expect.to_equal(2)

  let assert Ok(#(_core, events, [op])) =
    runtime_core.or_set_add(core, address, "bob")
  events
  |> expect.to_equal([
    #(address, channel.OrSetEvent(or_set_kernel.ElementAdded("bob"))),
  ])
  let encoded = json.to_string(op.contents)
  encoded
  |> string.contains("\"address\":\"" <> address <> "\"")
  |> expect.to_be_true()
  encoded |> string.contains("\"type\":\"orSetAdd\"") |> expect.to_be_true()
  encoded |> string.contains("\"element\":\"bob\"") |> expect.to_be_true()
}

pub fn or_set_snapshot_round_trips_test() {
  let #(state, _, op, _) =
    or_set_kernel.add(or_set_kernel.new(replica_id.new("a")), "a")
  let assert Ok(state) = or_set_kernel.ack_local(state, op)
  let snapshot = channel.OrSetSnapshot(state.sequenced)
  let encoded = channel.encode_snapshot(snapshot)
  let assert Ok(decoded) =
    json.parse(
      json.to_string(encoded),
      channel.snapshot_decoder(channel.OrSetChannel),
    )

  channel.same_snapshot(snapshot, decoded) |> expect.to_be_true()
}

fn list_length(items: List(a)) -> Int {
  list.length(items)
}
