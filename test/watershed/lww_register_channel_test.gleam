import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import lattice_core/replica_id
import lattice_registers/lww_register
import signet/types as token
import spillway/message
import spillway/types
import startest/expect
import watershed/channel
import watershed/handle
import watershed/lww_clock
import watershed/lww_register_kernel as register
import watershed/runtime_core
import watershed/wire
import watershed/wire/op
import watershed/wire/summary_blob

const client_id = "default_doc_1"

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

fn bootstrap() -> runtime_core.Core {
  let assert Ok(runtime_core.Complete(core)) =
    runtime_core.bootstrap(connected(), summary: None)
  core
}

fn acknowledge(
  core: runtime_core.Core,
  outbound: wire.OutboundOperation,
) -> #(runtime_core.Core, runtime_core.Ingested) {
  let assert Ok(contents) =
    json.parse(json.to_string(outbound.contents), decode.dynamic)
  let assert Ok(result) =
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
  result
}

fn stamp(operation: register.LwwRegisterOperation) -> #(String, Int, String) {
  let register.Set(value, timestamp, delta) = operation
  let assert Ok(author) =
    json.parse(
      lww_register.to_json(delta) |> json.to_string,
      decode.at(["state", "replica_id"], decode.string),
    )
  #(value, timestamp, author)
}

pub fn lww_register_channel_and_snapshot_contract_test() -> Nil {
  channel.string_to_type("lwwRegister")
  |> expect.to_equal(Ok(channel.LwwRegisterChannel))
  channel.type_to_string(channel.LwwRegisterChannel)
  |> expect.to_equal("lwwRegister")
  channel.supports_p2p(channel.LwwRegisterChannel) |> expect.to_be_true()
  channel.init_type(channel.InitLwwRegister)
  |> expect.to_equal(channel.LwwRegisterChannel)
  let assert Ok(#(state, _, _)) =
    register.p2p_set(register.new(replica_id.new("z")), "confirmed", 100)
  let assert Ok(#(state, _, _, _)) = register.set(state, "pending", 0)
  let wrapped = channel.LwwRegisterState(state)
  let snapshot = channel.snapshot(wrapped)
  let assert Ok(decoded) =
    json.parse(
      channel.encode_snapshot(snapshot) |> json.to_string,
      channel.snapshot_decoder(channel.LwwRegisterChannel),
    )
  channel.same_snapshot(snapshot, decoded) |> expect.to_be_true()
  let assert Ok(channel.LwwRegisterState(loaded)) =
    channel.from_snapshot(decoded, replica: "a")
  register.value(loaded) |> expect.to_equal("confirmed")
  let assert Ok(#(_, _, operation, _)) = register.set(loaded, "next", 0)
  stamp(operation) |> expect.to_equal(#("next", 101, "a"))
  let assert channel.LwwRegisterState(attached) =
    channel.attach_state(wrapped, replica: "z")
  register.value(attached) |> expect.to_equal("pending")
  attached.pending |> expect.to_equal([])
  attached.last_seen |> expect.to_equal(101)
  channel.handle_addresses(wrapped) |> expect.to_equal([])
}

pub fn detached_attach_reconnect_and_ack_preserve_register_metadata_test() -> Nil {
  let core =
    bootstrap()
    |> runtime_core.create_detached("cell", channel.InitLwwRegister)
  let assert Ok(#(core, events, [])) =
    runtime_core.lww_register_set(core, "cell", "baseline", 100)
  events
  |> expect.to_equal([
    #("cell", channel.LwwRegisterEvent(register.Changed("", "baseline"))),
  ])
  let assert Ok(#(core, _, [attach, reference])) =
    runtime_core.set(core, "root", "cell", handle.encode_handle("cell"))
  let #(core, _) = acknowledge(core, attach)
  let #(core, _) = acknowledge(core, reference)
  let assert Ok(#(core, _, [write])) =
    runtime_core.lww_register_set(core, "cell", "next", 0)
  let assert Ok(#("cell", original)) =
    json.parse(
      json.to_string(write.contents),
      op.lww_register_envelope_decoder(),
    )
  stamp(original) |> expect.to_equal(#("next", 101, client_id))
  let reconnect =
    message.ConnectedMessage(
      ..connected(),
      client_id: "default_doc_2",
      checkpoint_sequence_number: Some(core.last_seen_sequence_number),
    )
  let core = runtime_core.adopt_reconnect(core, reconnect)
  let #(core, resubmitted) = runtime_core.resubmit(core)
  let assert [resubmitted] = resubmitted
  json.parse(
    json.to_string(resubmitted.contents),
    op.lww_register_envelope_decoder(),
  )
  |> expect.to_equal(Ok(#("cell", original)))
  let #(core, ingested) = acknowledge(core, resubmitted)
  ingested.events |> expect.to_equal([])
  core.in_flight |> expect.to_equal([])
  runtime_core.lww_register_value(core, "cell") |> expect.to_equal(Ok("next"))
  let assert Ok(channel.LwwRegisterState(kernel)) =
    dict.get(core.channels, "cell")
  kernel.pending |> expect.to_equal([])
  register.sequenced_value(kernel) |> expect.to_equal("next")
  let assert Ok(#(_, [], [same_value])) =
    runtime_core.lww_register_set(core, "cell", "next", 0)
  let assert Ok(#(_, operation)) =
    json.parse(
      json.to_string(same_value.contents),
      op.lww_register_envelope_decoder(),
    )
  stamp(operation) |> expect.to_equal(#("next", 102, client_id))
}

pub fn register_summary_load_retains_winner_but_uses_the_joining_author_test() -> Nil {
  let core =
    bootstrap()
    |> runtime_core.create_detached("cell", channel.InitLwwRegister)
  let assert Ok(#(core, _, [])) =
    runtime_core.lww_register_set(core, "cell", "confirmed", 100)
  let assert Ok(#(core, _, [attach, reference])) =
    runtime_core.set(core, "root", "cell", handle.encode_handle("cell"))
  let #(core, _) = acknowledge(core, attach)
  let #(core, _) = acknowledge(core, reference)
  let assert Ok(#(core, _, [_])) =
    runtime_core.lww_register_set(core, "cell", "pending", 200)
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
      client_id: "default_doc_3",
      checkpoint_sequence_number: Some(core.last_seen_sequence_number),
    )
  let assert Ok(runtime_core.Complete(loaded)) =
    runtime_core.bootstrap(joining, Some(runtime_core.summary_from_blob(blob)))
  runtime_core.lww_register_value(loaded, "cell")
  |> expect.to_equal(Ok("confirmed"))
  let assert Ok(#(_, _, [write])) =
    runtime_core.lww_register_set(loaded, "cell", "new author", 0)
  let assert Ok(#(_, operation)) =
    json.parse(
      json.to_string(write.contents),
      op.lww_register_envelope_decoder(),
    )
  stamp(operation) |> expect.to_equal(#("new author", 101, "default_doc_3"))
}

pub fn register_access_and_clock_errors_are_observable_test() -> Nil {
  let core =
    bootstrap()
    |> runtime_core.create_detached("cell", channel.InitLwwRegister)
  runtime_core.lww_register_value(core, "root") |> expect.to_equal(Error(Nil))
  runtime_core.lww_register_value(core, "missing")
  |> expect.to_equal(Error(Nil))
  let assert Error(runtime_core.WrongChannelType(
    "root",
    channel.LwwRegisterChannel,
    channel.MapChannel,
  )) = runtime_core.lww_register_set(core, "root", "wrong", 1)
  let assert Error(runtime_core.LwwRegisterOperationFailed("cell", detail)) =
    runtime_core.lww_register_set(core, "cell", "invalid", -1)
  detail |> expect.to_equal("invalid LWW timestamp: -1")
  let assert Ok(#(core, _, [])) =
    runtime_core.lww_register_set(
      core,
      "cell",
      "last",
      lww_clock.max_safe_timestamp,
    )
  let assert Ok(#(core, _, _)) =
    runtime_core.set(core, "root", "cell", handle.encode_handle("cell"))
  let assert Error(runtime_core.LwwRegisterOperationFailed("cell", detail)) =
    runtime_core.lww_register_set(core, "cell", "exhausted", 0)
  detail |> expect.to_equal("LWW clock exhausted")
  runtime_core.lww_register_value(core, "cell") |> expect.to_equal(Ok("last"))
  let assert Error(channel.UnsupportedP2p("LWW clock exhausted")) =
    channel.apply_p2p_local(
      channel.LwwRegisterState({
        let assert Ok(state) =
          register.from_sequenced(
            lww_register.new(
              "last",
              lww_clock.max_safe_timestamp,
              replica_id.new("z"),
            ),
            replica_id.new("a"),
          )
        state
      }),
      channel.LwwRegisterSetEdit("exhausted", 0),
    )
  Nil
}

pub fn register_ack_requires_matching_operation_and_local_metadata_test() -> Nil {
  let assert Ok(#(state, _, operation, message_id)) =
    register.set(register.new(replica_id.new("a")), "value", 10)
  let state = channel.LwwRegisterState(state)
  let operation = channel.LwwRegisterOperation(operation)
  let meta = channel.SequencedMeta(1, 0, 0, 1, 1, [], [], 0)
  [
    channel.NoMeta,
    channel.MvRegisterMeta(message_id),
    channel.LwwRegisterMeta(message_id + 1),
  ]
  |> list.each(fn(local) {
    let assert Error(channel.UnexpectedAck(_)) =
      channel.ack_local(state, operation, local, meta)
    Nil
  })
  let assert Ok(#(channel.LwwRegisterState(acked), [], None)) =
    channel.ack_local(
      state,
      operation,
      channel.LwwRegisterMeta(message_id),
      meta,
    )
  register.sequenced_value(acked) |> expect.to_equal("value")
  let different_stamp =
    channel.LwwRegisterOperation(register.Set(
      "value",
      11,
      lww_register.new("value", 11, replica_id.new("a")),
    ))
  let different_author =
    channel.LwwRegisterOperation(register.Set(
      "value",
      10,
      lww_register.new("value", 10, replica_id.new("b")),
    ))
  channel.same_shape(operation, operation) |> expect.to_be_true()
  channel.same_shape(operation, different_stamp) |> expect.to_be_false()
  channel.same_shape(operation, different_author) |> expect.to_be_false()
}
