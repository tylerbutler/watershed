import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import lattice_core/replica_id
import lattice_registers/mv_register
import signet/types as token
import spillway/message
import spillway/types
import startest/expect
import watershed/channel
import watershed/handle
import watershed/mv_register_kernel as mv
import watershed/runtime_core
import watershed/wire/op

fn bootstrap() -> runtime_core.Core {
  let connected =
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
  let assert Ok(runtime_core.Complete(core)) =
    runtime_core.bootstrap(connected, summary: None)
  core
}

pub fn detached_attach_and_resubmit_preserve_the_original_write_test() -> Nil {
  let core =
    bootstrap() |> runtime_core.create_detached("cell", channel.InitMvRegister)
  let assert Ok(#(core, events, outbound)) =
    runtime_core.mv_register_set(core, "cell", "baseline")
  events
  |> expect.to_equal([
    #("cell", channel.MvRegisterEvent(mv.ValuesChanged(["baseline"]))),
  ])
  outbound |> expect.to_equal([])
  let assert Ok(#(core, _, attaches)) =
    runtime_core.set(core, "root", "cell", handle.encode_handle("cell"))
  list.length(attaches) |> expect.to_equal(2)
  runtime_core.mv_register_values(core, "cell")
  |> expect.to_equal(Ok(["baseline"]))
  let assert Ok(#(core, _, [write])) =
    runtime_core.mv_register_set(core, "cell", "next")
  let assert Ok(#("cell", original)) =
    json.parse(
      json.to_string(write.contents),
      op.mv_register_envelope_decoder(),
    )
  let #(_, replayed) = runtime_core.resubmit(core)
  let assert Ok(resubmitted) = list.last(replayed)
  json.parse(
    json.to_string(resubmitted.contents),
    op.mv_register_envelope_decoder(),
  )
  |> expect.to_equal(Ok(#("cell", original)))
  runtime_core.mv_register_values(core, "root") |> expect.to_equal(Error(Nil))
  runtime_core.mv_register_set(core, "root", "wrong kind")
  |> result.is_error
  |> expect.to_be_true()
}

pub fn snapshot_and_kind_round_trip_test() -> Nil {
  let #(state, _, _) = mv.p2p_set(mv.new(replica_id.new("a")), "confirmed")
  let #(state, _, _, _) = mv.set(state, "pending")
  let snapshot = channel.snapshot(channel.MvRegisterState(state))
  let assert Ok(decoded) =
    json.parse(
      channel.encode_snapshot(snapshot) |> json.to_string,
      channel.snapshot_decoder(channel.MvRegisterChannel),
    )
  channel.same_snapshot(snapshot, decoded) |> expect.to_be_true()
  let assert Ok(channel.MvRegisterState(loaded)) =
    channel.from_snapshot(decoded, replica: "b")
  mv.values(loaded) |> expect.to_equal(["confirmed"])
  let assert Ok(channel.MvRegisterState(attached)) =
    channel.from_snapshot(
      channel.attach_snapshot(channel.MvRegisterState(state)),
      replica: "b",
    )
  mv.values(attached) |> expect.to_equal(["pending"])
  channel.type_to_string(channel.MvRegisterChannel)
  |> expect.to_equal("mv-register")
  channel.string_to_type("mv-register")
  |> expect.to_equal(Ok(channel.MvRegisterChannel))
}

pub fn operation_requires_one_matching_causal_write_test() -> Nil {
  let #(a, _, write) = mv.p2p_set(mv.new(replica_id.new("a")), "hello")
  let encoded = op.encode_mv_register_envelope("cell", write) |> json.to_string
  json.parse(encoded, op.mv_register_envelope_decoder())
  |> expect.to_equal(Ok(#("cell", write)))
  let assert Ok(tag) =
    json.parse(op.encode_mv_register_operation(write) |> json.to_string, {
      use value <- decode.field("type", decode.string)
      decode.success(value)
    })
  tag |> expect.to_equal("mvRegisterSet")
  let empty = mv_register.new(replica_id.new("b"))
  let #(b, _, _) = mv.p2p_set(mv.new(replica_id.new("b")), "world")
  let conflict = mv_register.merge(a.sequenced, b.sequenced)
  [mv.Set("wrong", a.sequenced), mv.Set("", empty), mv.Set("hello", conflict)]
  |> list.each(fn(operation) {
    json.parse(
      op.encode_mv_register_operation(operation) |> json.to_string,
      op.mv_register_operation_decoder(),
    )
    |> result.is_error
    |> expect.to_be_true()
  })
  json.parse(
    op.encode_mv_register_operation(write) |> json.to_string,
    op.channel_operation_decoder(channel.PnCounterChannel),
  )
  |> result.is_error
  |> expect.to_be_true()
}
