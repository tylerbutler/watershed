import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import lattice_core/replica_id
import lattice_maps/lww_map
import signet/types as token
import spillway/message
import spillway/types
import startest/expect
import watershed/channel
import watershed/handle
import watershed/lww_map_kernel as kernel
import watershed/runtime_core
import watershed/wire
import watershed/wire/op
import watershed/wire/summary_blob

fn connected() -> message.ConnectedMessage {
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
    client_id: "default_doc_1",
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

fn bootstrap() -> runtime_core.Core {
  let assert Ok(runtime_core.Complete(core)) =
    runtime_core.bootstrap(connected(), summary: None)
  core
}

fn acknowledge(
  core: runtime_core.Core,
  outbound: wire.OutboundOperation,
) -> runtime_core.Core {
  let assert Ok(contents) =
    json.parse(json.to_string(outbound.contents), decode.dynamic)
  let assert Ok(#(core, ingested)) =
    runtime_core.handle_sequenced(
      core,
      types.SequencedDocumentMessage(
        client_id: Some(core.client_id),
        sequence_number: core.last_seen_sequence_number + 1,
        minimum_sequence_number: 0,
        client_sequence_number: outbound.client_sequence_number,
        reference_sequence_number: outbound.reference_sequence_number,
        message_type: outbound.operation_type,
        contents: contents,
        metadata: None,
        server_metadata: None,
        origin: None,
        traces: None,
        timestamp: 0,
        data: None,
      ),
    )
  ingested.events |> expect.to_equal([])
  core
}

pub fn lww_map_channel_snapshot_and_attach_contract_test() -> Nil {
  channel.string_to_type("lwwMap") |> expect.to_equal(Ok(channel.LwwMapChannel))
  channel.type_to_string(channel.LwwMapChannel) |> expect.to_equal("lwwMap")
  channel.supports_p2p(channel.LwwMapChannel) |> expect.to_be_true()
  channel.init_type(channel.InitLwwMap)
  |> expect.to_equal(channel.LwwMapChannel)
  let assert Ok(#(state, [], _)) =
    channel.apply_p2p_local(
      channel.new(channel.InitLwwMap, replica: "a"),
      channel.LwwMapRemoveEdit("gone", 100),
    )
  let snapshot = channel.snapshot(state)
  let assert Ok(decoded) =
    json.parse(
      channel.encode_snapshot(snapshot) |> json.to_string,
      channel.snapshot_decoder(channel.LwwMapChannel),
    )
  channel.same_snapshot(snapshot, decoded) |> expect.to_be_true()
  let assert Ok(channel.LwwMapState(loaded)) =
    channel.from_snapshot(decoded, replica: "b")
  let assert Ok(#(loaded, _, _, _)) = kernel.set(loaded, "gone", "restored", 0)
  let wrapped = channel.LwwMapState(loaded)
  let assert channel.LwwMapState(attached) =
    channel.attach_state(wrapped, replica: "b")
  attached.pending |> expect.to_equal([])
  kernel.sequenced_entries(attached) |> expect.to_equal([#("gone", "restored")])
  channel.same_snapshot(
    channel.attach_snapshot(wrapped),
    channel.snapshot(channel.LwwMapState(attached)),
  )
  |> expect.to_be_true()
  channel.handle_addresses(wrapped) |> expect.to_equal([])
  channel.applies_own_on_sequence(wrapped) |> expect.to_be_false()
  channel.on_leave(wrapped, 1, 1) |> expect.to_equal(#(wrapped, []))
  let unsafe = channel.LwwMapSnapshot(lww_map.set(lww_map.new(), "bad", "v", 0))
  let assert Error(_) = channel.from_snapshot(unsafe, replica: "a")
  let assert Error(_) = channel.merge_p2p_snapshot(state, unsafe)
  let assert Error(channel.UnsupportedP2p(_)) =
    channel.apply_p2p_local(state, channel.LwwRegisterSetEdit("wrong", 1))
  Nil
}

pub fn lww_map_ack_metadata_and_operation_matching_test() -> Nil {
  let assert Ok(#(state, _, operation, message_id)) =
    kernel.set(kernel.new(replica_id.new("a")), "k", "v", 10)
  let state = channel.LwwMapState(state)
  let operation = channel.LwwMapOperation(operation)
  let meta = channel.SequencedMeta(1, 0, 0, 1, 1, [], [], 0)
  [
    channel.NoMeta,
    channel.LwwRegisterMeta(message_id),
    channel.LwwMapMeta(message_id + 1),
  ]
  |> list.each(fn(local) {
    let assert Error(channel.UnexpectedAck(_)) =
      channel.ack_local(state, operation, local, meta)
    Nil
  })
  let assert Ok(#(channel.LwwMapState(acked), [], None)) =
    channel.ack_local(state, operation, channel.LwwMapMeta(message_id), meta)
  kernel.sequenced_entries(acked) |> expect.to_equal([#("k", "v")])
  let different =
    channel.LwwMapOperation(kernel.Set(
      "k",
      "v",
      11,
      lww_map.set(lww_map.new(), "k", "v", 11),
    ))
  channel.same_shape(operation, operation) |> expect.to_be_true()
  channel.same_shape(operation, different) |> expect.to_be_false()
  let assert Ok(#(remote, _, [])) =
    channel.apply_remote(
      channel.new(channel.InitLwwMap, replica: "b"),
      operation,
      meta,
    )
  let assert Ok(#(duplicate, [], [])) =
    channel.apply_remote(remote, operation, meta)
  channel.same_snapshot(channel.snapshot(remote), channel.snapshot(duplicate))
  |> expect.to_be_true()
}

pub fn lww_map_core_attach_reconnect_summary_and_errors_test() -> Nil {
  let core =
    bootstrap() |> runtime_core.create_detached("map", channel.InitLwwMap)
  let assert Ok(#(core, [], [])) =
    runtime_core.lww_map_remove(core, "map", "k", 100)
  let assert Ok(#(core, _, [attach, reference])) =
    runtime_core.set(core, "root", "map", handle.encode_handle("map"))
  let core = acknowledge(core, attach) |> acknowledge(reference)
  let assert Ok(#(core, _, [write])) =
    runtime_core.lww_map_set(core, "map", "k", "restored", 0)
  let assert Ok(#("map", original)) =
    json.parse(json.to_string(write.contents), op.lww_map_envelope_decoder())
  let assert kernel.Set("k", "restored", 101, _) = original
  let reconnect =
    message.ConnectedMessage(
      ..connected(),
      client_id: "default_doc_2",
      checkpoint_sequence_number: Some(core.last_seen_sequence_number),
    )
  let assert #(core, [resubmitted]) =
    core |> runtime_core.adopt_reconnect(reconnect) |> runtime_core.resubmit
  json.parse(
    json.to_string(resubmitted.contents),
    op.lww_map_envelope_decoder(),
  )
  |> expect.to_equal(Ok(#("map", original)))
  let core = acknowledge(core, resubmitted)
  core.in_flight |> expect.to_equal([])
  runtime_core.lww_map_get(core, "map", "k") |> expect.to_equal(Ok("restored"))
  runtime_core.lww_map_entries(core, "map")
  |> expect.to_equal([#("k", "restored")])
  runtime_core.lww_map_keys(core, "map") |> expect.to_equal(["k"])
  let assert Ok(#(core, [], [_])) =
    runtime_core.lww_map_set(core, "map", "k", "restored", 200)
  let assert Ok(blob) =
    summary_blob.encode_channels(
      core.last_seen_sequence_number,
      runtime_core.summary_members(core),
      runtime_core.summary_channels(core),
    )
    |> json.to_string
    |> summary_blob.decode
  let joining =
    message.ConnectedMessage(
      ..connected(),
      checkpoint_sequence_number: Some(core.last_seen_sequence_number),
    )
  let assert Ok(runtime_core.Complete(loaded)) =
    runtime_core.bootstrap(joining, Some(runtime_core.summary_from_blob(blob)))
  let assert Ok(#(_, _, [next])) =
    runtime_core.lww_map_remove(loaded, "map", "k", 0)
  let assert Ok(#(_, kernel.Remove("k", 102, _))) =
    json.parse(json.to_string(next.contents), op.lww_map_envelope_decoder())
  runtime_core.lww_map_get(core, "root", "k") |> expect.to_equal(Error(Nil))
  runtime_core.lww_map_entries(core, "missing") |> expect.to_equal([])
  runtime_core.lww_map_keys(core, "root") |> expect.to_equal([])
  let assert Error(runtime_core.WrongChannelType(
    "root",
    channel.LwwMapChannel,
    channel.MapChannel,
  )) = runtime_core.lww_map_set(core, "root", "k", "wrong", 1)
  let assert Error(runtime_core.LwwMapOperationFailed("map", _)) =
    runtime_core.lww_map_remove(core, "map", "k", -1)
  Nil
}
