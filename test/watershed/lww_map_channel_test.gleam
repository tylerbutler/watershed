import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import lattice_core/replica_id
import lattice_maps/crdt
import lattice_maps/lww_map
import lattice_registers/lww_register
import signet/types as token
import spillway/message
import spillway/types
import startest/expect
import watershed/channel
import watershed/fluid_ids
import watershed/handle
import watershed/lww_map_kernel as kernel
import watershed/runtime_core
import watershed/tree/checked_test as checked
import watershed/wire
import watershed/wire/fluid_document
import watershed/wire/op

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
  let snapshot = checked.value(channel.snapshot(state))
  let assert Ok(decoded) =
    json.parse(
      checked.value(channel.encode_snapshot(snapshot)) |> json.to_string,
      checked.value(channel.snapshot_decoder(channel.LwwMapChannel)),
    )
  channel.same_snapshot(snapshot, decoded) |> expect.to_be_true()
  let assert Ok(channel.LwwMapState(loaded)) =
    channel.from_snapshot(decoded, replica: "b")
  let assert Ok(#(loaded, _, _, _)) = kernel.set(loaded, "gone", "restored", 0)
  let wrapped = channel.LwwMapState(loaded)
  let assert Ok(channel.LwwMapState(attached)) =
    channel.attach_state(wrapped, replica: "b")
  attached.pending |> expect.to_equal([])
  kernel.sequenced_entries(attached) |> expect.to_equal([#("gone", "restored")])
  channel.same_snapshot(
    checked.value(channel.attach_snapshot(wrapped)),
    checked.value(channel.snapshot(channel.LwwMapState(attached))),
  )
  |> expect.to_be_true()
  channel.handle_addresses(wrapped) |> expect.to_equal([])
  channel.applies_own_on_sequence(wrapped) |> expect.to_be_false()
  channel.on_leave(wrapped, 1, 1) |> expect.to_equal(#(wrapped, []))
  let assert Error(channel.UnsupportedP2p(_)) =
    channel.apply_p2p_local(state, channel.LwwRegisterSetEdit("wrong", 1))
  Nil
}

pub fn lww_map_ack_metadata_and_operation_matching_test() -> Nil {
  let assert Ok(#(state, _, operation, message_id)) =
    kernel.set(kernel.new(replica_id.new("a")), "k", "v", 10)
  let state = channel.LwwMapState(state)
  let operation = channel.LwwMapOperation(operation)
  let meta = channel.SequencedMeta(1, 0, 0, 1, 1, [], [], 0, 0, None)
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
  let replica = replica_id.new("a")
  let assert Ok(delta) =
    lww_map.set(
      lww_map.new(replica, crdt.LwwRegisterSpec("")),
      "k",
      crdt.CrdtLwwRegister(lww_register.new("v", 11, replica)),
      11,
    )
  let different = channel.LwwMapOperation(kernel.Set("k", "v", 11, delta))
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
  channel.same_snapshot(
    checked.value(channel.snapshot(remote)),
    checked.value(channel.snapshot(duplicate)),
  )
  |> expect.to_be_true()
}

pub fn lww_map_core_attach_reconnect_summary_and_errors_test() -> Nil {
  let core =
    bootstrap()
    |> runtime_core.create_detached("watershed/map", channel.InitLwwMap)
    |> expect.to_be_ok
  let assert Ok(#(core, [], [])) =
    runtime_core.lww_map_remove(core, "watershed/map", "k", 100)
  let assert Ok(#(core, _, [attach, reference])) =
    runtime_core.set(
      core,
      "watershed/root",
      "map",
      handle.encode_handle("watershed/map"),
    )
  let core = acknowledge(core, attach) |> acknowledge(reference)
  let assert Ok(#(core, _, [write])) =
    runtime_core.lww_map_set(core, "watershed/map", "k", "restored", 0)
  let assert Ok(#("watershed/map", original)) =
    json.parse(json.to_string(write.contents), op.lww_map_envelope_decoder())
  let assert kernel.Set("k", "restored", 101, _) = original
  let reconnect =
    message.ConnectedMessage(
      ..connected(),
      client_id: "default_doc_2",
      checkpoint_sequence_number: Some(core.last_seen_sequence_number),
    )
  let assert Ok(#(core, [resubmitted])) =
    core |> runtime_core.adopt_reconnect(reconnect) |> runtime_core.resubmit
  json.parse(
    json.to_string(resubmitted.contents),
    op.lww_map_envelope_decoder(),
  )
  |> expect.to_equal(Ok(#("watershed/map", original)))
  let core = acknowledge(core, resubmitted)
  core.in_flight |> expect.to_equal([])
  runtime_core.lww_map_get(core, "watershed/map", "k")
  |> expect.to_equal(Ok("restored"))
  runtime_core.lww_map_entries(core, "watershed/map")
  |> expect.to_equal([#("k", "restored")])
  runtime_core.lww_map_keys(core, "watershed/map") |> expect.to_equal(["k"])
  let assert Ok(#(core, [], [_])) =
    runtime_core.lww_map_set(core, "watershed/map", "k", "restored", 200)
  let assert Ok(document) =
    fluid_document.native(
      core.last_seen_sequence_number,
      core.minimum_sequence_number,
      runtime_core.summary_members(core),
      checked.value(runtime_core.summary_channels(core)),
    )
  let assert Ok(hierarchy) = fluid_document.encode(document)
  let assert Ok(session) =
    fluid_ids.session_id("70000000-0000-4000-8000-000000000007")
  let assert Ok(view) =
    fluid_ids.stable_id("60000000-0000-4000-8000-000000000006")
  let assert Ok(restored) =
    fluid_document.decode(hierarchy, None, session, view)
  let joining =
    message.ConnectedMessage(
      ..connected(),
      checkpoint_sequence_number: Some(core.last_seen_sequence_number),
    )
  let assert Ok(runtime_core.Complete(loaded)) =
    runtime_core.bootstrap_document(joining, restored)
  let assert Ok(#(_, _, [next])) =
    runtime_core.lww_map_remove(loaded, "watershed/map", "k", 0)
  let assert Ok(#(_, kernel.Remove("k", 102, _))) =
    json.parse(json.to_string(next.contents), op.lww_map_envelope_decoder())
  runtime_core.lww_map_get(core, "watershed/root", "k")
  |> expect.to_equal(Error(Nil))
  runtime_core.lww_map_entries(core, "watershed/missing") |> expect.to_equal([])
  runtime_core.lww_map_keys(core, "watershed/root") |> expect.to_equal([])
  let assert Error(runtime_core.WrongChannelType(
    "watershed/root",
    channel.LwwMapChannel,
    channel.MapChannel,
  )) = runtime_core.lww_map_set(core, "watershed/root", "k", "wrong", 1)
  let assert Error(runtime_core.LwwMapOperationFailed("watershed/map", _)) =
    runtime_core.lww_map_remove(core, "watershed/map", "k", -1)
  Nil
}
