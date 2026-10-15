@target(javascript)
import gleam/dict
@target(javascript)
import gleam/dynamic/decode
@target(javascript)
import gleam/javascript/promise.{type Promise}
@target(javascript)
import gleam/json
@target(javascript)
import gleam/list
@target(javascript)
import gleam/option.{None, Some}
@target(javascript)
import gleam/result
@target(javascript)
import gleam/string
@target(javascript)
import signet/types as token
@target(javascript)
import spillway/message
@target(javascript)
import spillway/types
@target(javascript)
import startest/expect
@target(javascript)
import watershed
@target(javascript)
import watershed/channel
@target(javascript)
import watershed/container
@target(javascript)
import watershed/fluid_ids
@target(javascript)
import watershed/handle
@target(javascript)
import watershed/map_kernel
@target(javascript)
import watershed/runtime
@target(javascript)
import watershed/runtime_core
@target(javascript)
import watershed/schema
@target(javascript)
import watershed/sluice/frame
@target(javascript)
import watershed/summary_policy
@target(javascript)
import watershed/transport_js
@target(javascript)
import watershed/tree/facade_fixture
@target(javascript)
import watershed/tree/fixtures
@target(javascript)
import watershed/tree/identifier_fixture
@target(javascript)
import watershed/tree/runtime_fixture
@target(javascript)
import watershed/tree/schema as tree_schema
@target(javascript)
import watershed/tree/types as tree_types
@target(javascript)
import watershed/tree/undo_acceptance
@target(javascript)
import watershed/tree_kernel
@target(javascript)
import watershed/wire/fluid_container
@target(javascript)
import watershed/wire/op as wire_op

@target(javascript)
type FacadeAbort {
  FacadeAbort
}

@target(javascript)
@external(javascript, "./shared_tree_branch_ffi.mjs", "throwTransaction")
fn throw_transaction(
  tree: facade_fixture.JavascriptTree,
) -> Result(Nil, FacadeAbort)

@target(javascript)
fn connect_message() -> message.ConnectMessage {
  message.ConnectMessage(
    tenant_id: "default",
    document_id: "tree",
    token: Some("test"),
    client: types.Client(
      mode: types.WriteMode,
      details: types.ClientDetails(
        capabilities: types.ClientCapabilities(interactive: True),
        client_type: None,
        environment: None,
        device: None,
      ),
      permission: [],
      user: token.User("reader", dict.new()),
      scopes: ["doc:read", "doc:write"],
      timestamp: None,
    ),
    versions: ["^0.1.0"],
    driver_version: None,
    mode: types.WriteMode,
    nonce: None,
    epoch: None,
    supported_features: None,
    relay_user_agent: None,
  )
}

@target(javascript)
fn membership_frame(
  sequence_number: Int,
  operation_type: String,
  data: String,
) -> frame.Sequenced {
  frame.Sequenced(
    client_id: None,
    sequence_number: sequence_number,
    minimum_sequence_number: 0,
    client_sequence_number: -1,
    reference_sequence_number: 0,
    operation_type: operation_type,
    contents: json.null(),
    metadata: None,
    timestamp: 0,
    data: Some(data),
    compression: None,
  )
}

@target(javascript)
fn identifier_seed() -> runtime_core.BootstrapSeed {
  identifier_fixture.full_seed_input(
    identifier_fixture.full_root(
      identifier_fixture.point("child", "child"),
      [identifier_fixture.point("existing", "existing")],
      [],
      [],
    ),
  )
  |> runtime_core.bootstrap_seed
  |> expect.to_be_ok()
}

@target(javascript)
fn history_count(owner: runtime.Runtime, field: String) -> Int {
  runtime.tree_history_evidence(owner, "A/_C")
  |> expect.to_be_ok()
  |> json.to_string
  |> json.parse(decode.at([field], decode.list(decode.dynamic)))
  |> expect.to_be_ok()
  |> list.length
}

@target(javascript)
fn sequenced_submission(
  submitted: frame.SubmittedOperation,
  client_id: String,
  sequence_number: Int,
) -> frame.Sequenced {
  frame.Sequenced(
    client_id: Some(client_id),
    sequence_number: sequence_number,
    minimum_sequence_number: 0,
    client_sequence_number: submitted.client_sequence_number,
    reference_sequence_number: submitted.reference_sequence_number,
    operation_type: submitted.operation_type,
    contents: submitted.contents,
    metadata: submitted.metadata,
    timestamp: 0,
    data: None,
    compression: None,
  )
}

@target(javascript)
fn evolution_schema(
  id: String,
) -> #(tree_schema.StoredSchema, tree_schema.ViewSchema) {
  let fixture = fixtures.load("schema-evolution-history") |> expect.to_be_ok
  let schemas =
    json.parse(
      json.to_string(fixture.input),
      decode.at(
        ["schemas"],
        decode.list({
          use schema_id <- decode.field("id", decode.string)
          use raw <- decode.field("raw", decode.string)
          decode.success(#(schema_id, raw))
        }),
      ),
    )
    |> expect.to_be_ok
  let raw = list.key_find(schemas, id) |> expect.to_be_ok
  #(
    tree_schema.stored_from_string(raw) |> expect.to_be_ok,
    tree_schema.view_from_string(raw) |> expect.to_be_ok,
  )
}

@target(javascript)
fn schema_evolution_root() -> tree_types.TreeValue {
  tree_types.ObjectValue("org.watershed.shared-tree.m4.Root", [
    #("title", tree_types.StringValue("base")),
    #(
      "point",
      tree_types.ObjectValue("org.watershed.shared-tree.m4.Point", [
        #("x", tree_types.NumberValue(1.0)),
        #("y", tree_types.NumberValue(2.0)),
      ]),
    ),
    #(
      "items",
      tree_types.MapValue("org.watershed.shared-tree.m4.Items", [
        #("label", tree_types.StringValue("value")),
      ]),
    ),
  ])
}

@target(javascript)
fn submitted_tree_identity(
  submitted: frame.SubmittedOperation,
) -> List(#(String, Int)) {
  let batch =
    fluid_container.decode(submitted.contents, submitted.metadata)
    |> expect.to_be_ok
  batch.messages
  |> list.filter_map(fn(message) {
    case message.kind {
      fluid_container.ChannelOperation(
        fluid_container.Route("A", "_C"),
        contents,
      ) -> {
        let raw = json.to_string(contents)
        let originator =
          json.parse(raw, decode.at(["originatorId"], decode.string))
          |> expect.to_be_ok
        let revision =
          json.parse(raw, decode.at(["revision"], decode.int))
          |> expect.to_be_ok
        Ok(#(originator, revision))
      }
      _ -> Error(Nil)
    }
  })
}

@target(javascript)
fn ready_scheduled_runtime(push: fn(String, json.Json) -> Nil) {
  let assert Ok(#(input, _)) = runtime_fixture.routed_seed_input()
  ready_scheduled_runtime_from(input, push)
}

@target(javascript)
fn ready_scheduled_runtime_from(
  input: runtime_core.BootstrapSeedInput,
  push: fn(String, json.Json) -> Nil,
) {
  let assert Ok(seed) = runtime_core.bootstrap_seed(input)
  let assert [view, ..] = input.tree_views
  let callbacks = transport_js.new_cell(None)
  let scheduled = transport_js.new_cell([])
  let owner =
    runtime.start_with_transport_and_seed(
      http_base_url: "https://seed.invalid",
      connect_message: connect_message(),
      seed: seed,
      transport: runtime.Transport(connect: fn(handlers) {
        transport_js.set_cell(callbacks, Some(handlers))
        runtime.TransportHandle(
          push: push,
          close: fn() { Nil },
          drop: fn() { Nil },
          hold: fn() { Nil },
          resume: fn() { Nil },
        )
      }),
      on_ready: fn(_) { Nil },
    )
  runtime.set_scheduler(
    owner,
    transport_js.Scheduler(
      now_milliseconds: fn() { 0 },
      schedule: fn(action, _) {
        transport_js.set_cell(scheduled, [
          action,
          ..transport_js.get_cell(scheduled)
        ])
        fn() { Nil }
      },
    ),
  )
  let assert Some(callbacks) = transport_js.get_cell(callbacks)
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["reader"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    )
      |> json.to_string,
  )
  #(owner, callbacks, view.view, scheduled)
}

@target(javascript)
pub fn aborting_tree_transaction_preserves_other_tree_fork_test() {
  let input = runtime_fixture.routed_two_tree_seed_input() |> expect.to_be_ok()
  let #(owner, _, view, _) =
    ready_scheduled_runtime_from(input, fn(_, _) { Nil })
  runtime.begin_tree_transaction(owner, "A/_C", view, [])
  |> expect.to_equal(Ok(Nil))
  runtime.tree_edit_view(
    owner,
    "A/_C",
    view,
    tree_types.SetField(["title"], tree_types.StringValue("discarded")),
  )
  |> expect.to_equal(Ok(Nil))
  let branch =
    runtime.tree_fork(owner, "B/_C", tree_types.DocumentCheckout, view)
    |> expect.to_be_ok()
  runtime.abort_tree_transaction(owner, "A/_C")
  |> expect.to_equal(Ok(Nil))
  runtime.tree_read(owner, "A/_C", ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue(""))))
  runtime.tree_edit_view_on(
    owner,
    "B/_C",
    branch,
    view,
    tree_types.SetField(["title"], tree_types.StringValue("preserved")),
  )
  |> expect.to_equal(Ok(Nil))
  runtime.tree_read_view_on(owner, "B/_C", branch, view, ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("preserved"))))
  runtime.close(owner)
}

@target(javascript)
fn run_scheduled(scheduled) {
  let actions = transport_js.get_cell(scheduled)
  transport_js.set_cell(scheduled, [])
  actions |> list.reverse |> list.each(fn(action) { action() })
}

@target(javascript)
fn peer_map_set(sequence_number: Int) -> String {
  let assert Ok(contents) =
    fluid_container.encode_batch(
      fluid_container.DecodedBatch(True, None, [
        fluid_container.ContainerMessage(
          fluid_container.ChannelOperation(
            fluid_container.Route("A", "root"),
            wire_op.encode_map_operation(map_kernel.Set(
              "peer",
              json.string("received"),
            )),
          ),
          0,
          None,
        ),
      ]),
    )
  frame.encode_operation_event([
    frame.Sequenced(
      client_id: Some("peer"),
      sequence_number: sequence_number,
      minimum_sequence_number: 0,
      client_sequence_number: 1,
      reference_sequence_number: 0,
      operation_type: "op",
      contents: contents,
      metadata: None,
      timestamp: 0,
      data: None,
      compression: None,
    ),
  ])
  |> json.to_string
}

@target(javascript)
pub fn assert_pending_multi_edit_transaction_resubmit() {
  let sender_callbacks = transport_js.new_cell(None)
  let receiver_callbacks = transport_js.new_cell(None)
  let submissions = transport_js.new_cell([])
  let sender_events = transport_js.new_cell([])
  let receiver_events = transport_js.new_cell([])
  let sender =
    runtime.start_with_transport_and_seed(
      http_base_url: "https://seed.invalid",
      connect_message: connect_message(),
      seed: identifier_seed(),
      transport: runtime.Transport(connect: fn(handlers) {
        transport_js.set_cell(sender_callbacks, Some(handlers))
        runtime.TransportHandle(
          push: fn(event, payload) {
            case event {
              "submitOp" -> {
                let assert Ok(dynamic) =
                  json.parse(json.to_string(payload), decode.dynamic)
                let assert Ok(frame.SubmitOperation(_, [[submitted]])) =
                  frame.decode_submit_operation(dynamic)
                transport_js.set_cell(submissions, [
                  submitted,
                  ..transport_js.get_cell(submissions)
                ])
              }
              _ -> Nil
            }
          },
          close: fn() { Nil },
          drop: fn() { Nil },
          hold: fn() { Nil },
          resume: fn() { Nil },
        )
      }),
      on_ready: fn(_) { Nil },
    )
  let receiver =
    runtime.start_with_transport_and_seed(
      http_base_url: "https://seed.invalid",
      connect_message: connect_message(),
      seed: identifier_seed(),
      transport: runtime.Transport(connect: fn(handlers) {
        transport_js.set_cell(receiver_callbacks, Some(handlers))
        runtime.TransportHandle(
          push: fn(_, _) { Nil },
          close: fn() { Nil },
          drop: fn() { Nil },
          hold: fn() { Nil },
          resume: fn() { Nil },
        )
      }),
      on_ready: fn(_) { Nil },
    )
  let assert Some(sender_transport) = transport_js.get_cell(sender_callbacks)
  let assert Some(receiver_transport) =
    transport_js.get_cell(receiver_callbacks)
  sender_transport.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "writer",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["writer"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    )
      |> json.to_string,
  )
  receiver_transport.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "receiver",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["receiver"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    )
      |> json.to_string,
  )
  let _ =
    runtime.subscribe(sender, "A/_C", fn(event) {
      transport_js.set_cell(sender_events, [
        event,
        ..transport_js.get_cell(sender_events)
      ])
    })
  let _ =
    runtime.subscribe(receiver, "A/_C", fn(event) {
      transport_js.set_cell(receiver_events, [
        event,
        ..transport_js.get_cell(receiver_events)
      ])
    })
  let view = identifier_fixture.full_view()
  runtime.begin_tree_transaction(sender, "A/_C", view, [])
  |> expect.to_equal(Ok(Nil))
  runtime.tree_edit_view(
    sender,
    "A/_C",
    view,
    tree_types.ArrayInsert(["left"], 1, [
      tree_types.ObjectValue(identifier_fixture.point_type, [
        #("label", tree_types.StringValue("pending")),
      ]),
    ]),
  )
  |> expect.to_equal(Ok(Nil))
  runtime.tree_edit_view(
    sender,
    "A/_C",
    view,
    tree_types.SetField(
      ["left", "1", "label"],
      tree_types.StringValue("pending-final"),
    ),
  )
  |> expect.to_equal(Ok(Nil))
  runtime.commit_tree_transaction(sender, "A/_C")
  |> expect.to_equal(Ok(Nil))
  let assert [original] = transport_js.get_cell(submissions)
  let identifier =
    runtime.tree_read(sender, "A/_C", ["left", "1", "id"])
    |> expect.to_be_ok()
  transport_js.get_cell(sender_events)
  |> expect.to_equal([
    channel.TreeEvent(tree_kernel.TreeChanged(True)),
  ])

  sender_transport.on_close()
  runtime.connection_observation(sender).phase
  |> expect.to_equal("reconnecting")
  sender_transport.on_join()
  sender_transport.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "writer-2",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 1,
      initial_clients: ["writer-2"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    )
      |> json.to_string,
  )
  sender_transport.on_event(
    "op",
    frame.encode_operation_event([
      membership_frame(1, "join", "{\"clientId\":\"writer-2\",\"detail\":{}}"),
    ])
      |> json.to_string,
  )
  runtime.connection_observation(sender).phase
  |> expect.to_equal("catching-up")
  transport_js.get_cell(submissions) |> expect.to_equal([original])
  sender_transport.on_event(
    "op",
    frame.encode_operation_event([
      membership_frame(2, "leave", "\"writer\""),
    ])
      |> json.to_string,
  )
  runtime.connection_observation(sender).phase |> expect.to_equal("ready")
  let assert [resent, initial] = transport_js.get_cell(submissions)
  resent.client_sequence_number |> expect.to_equal(1)
  resent.metadata |> expect.to_equal(initial.metadata)
  let assert Ok(batch) =
    fluid_container.decode(resent.contents, resent.metadata)
  batch.messages
  |> list.count(fn(message) {
    case message.kind {
      fluid_container.ChannelOperation(_, _) -> True
      _ -> False
    }
  })
  |> expect.to_equal(1)

  receiver_transport.on_event(
    "op",
    frame.encode_operation_event([
      membership_frame(1, "join", "{\"clientId\":\"writer-2\",\"detail\":{}}"),
      membership_frame(2, "leave", "\"writer\""),
      sequenced_submission(resent, "writer-2", 3),
    ])
      |> json.to_string,
  )
  transport_js.get_cell(receiver_events)
  |> expect.to_equal([
    channel.TreeEvent(tree_kernel.TreeChanged(False)),
  ])
  history_count(receiver, "trunk") |> expect.to_equal(1)
  runtime.tree_array_values(receiver, "A/_C", ["left"])
  |> expect.to_be_ok()
  |> list.length
  |> expect.to_equal(2)
  runtime.tree_read(receiver, "A/_C", ["left", "1", "label"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("pending-final"))))
  runtime.tree_read(receiver, "A/_C", ["left", "1", "id"])
  |> expect.to_equal(Ok(identifier))

  sender_transport.on_event(
    "op",
    frame.encode_operation_event([
      sequenced_submission(resent, "writer-2", 3),
    ])
      |> json.to_string,
  )
  history_count(sender, "pending") |> expect.to_equal(0)
  history_count(sender, "trunk") |> expect.to_equal(1)
  transport_js.get_cell(sender_events)
  |> expect.to_equal([
    channel.TreeEvent(tree_kernel.TreeChanged(True)),
  ])
  runtime.tree_read(sender, "A/_C", ["left", "1", "id"])
  |> expect.to_equal(Ok(identifier))
  runtime.close(sender)
  runtime.close(receiver)
}

@target(javascript)
pub fn assert_accepted_transaction_before_drop() {
  let sender_callbacks = transport_js.new_cell(None)
  let receiver_callbacks = transport_js.new_cell(None)
  let submissions = transport_js.new_cell([])
  let sender_events = transport_js.new_cell([])
  let receiver_events = transport_js.new_cell([])
  let sender =
    runtime.start_with_transport_and_seed(
      http_base_url: "https://seed.invalid",
      connect_message: connect_message(),
      seed: identifier_seed(),
      transport: runtime.Transport(connect: fn(handlers) {
        transport_js.set_cell(sender_callbacks, Some(handlers))
        runtime.TransportHandle(
          push: fn(event, payload) {
            case event {
              "submitOp" -> {
                let assert Ok(dynamic) =
                  json.parse(json.to_string(payload), decode.dynamic)
                let assert Ok(frame.SubmitOperation(_, [[submitted]])) =
                  frame.decode_submit_operation(dynamic)
                transport_js.set_cell(submissions, [
                  submitted,
                  ..transport_js.get_cell(submissions)
                ])
              }

              _ -> Nil
            }
          },
          close: fn() { Nil },
          drop: fn() { Nil },
          hold: fn() { Nil },
          resume: fn() { Nil },
        )
      }),
      on_ready: fn(_) { Nil },
    )
  let receiver =
    runtime.start_with_transport_and_seed(
      http_base_url: "https://seed.invalid",
      connect_message: connect_message(),
      seed: identifier_seed(),
      transport: runtime.Transport(connect: fn(handlers) {
        transport_js.set_cell(receiver_callbacks, Some(handlers))
        runtime.TransportHandle(
          push: fn(_, _) { Nil },
          close: fn() { Nil },
          drop: fn() { Nil },
          hold: fn() { Nil },
          resume: fn() { Nil },
        )
      }),
      on_ready: fn(_) { Nil },
    )
  let assert Some(sender_transport) = transport_js.get_cell(sender_callbacks)
  let assert Some(receiver_transport) =
    transport_js.get_cell(receiver_callbacks)
  sender_transport.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "writer",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["writer"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    )
      |> json.to_string,
  )
  receiver_transport.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "receiver",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["receiver"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    )
      |> json.to_string,
  )
  let _ =
    runtime.subscribe(sender, "A/_C", fn(event) {
      transport_js.set_cell(sender_events, [
        event,
        ..transport_js.get_cell(sender_events)
      ])
    })
  let _ =
    runtime.subscribe(receiver, "A/_C", fn(event) {
      transport_js.set_cell(receiver_events, [
        event,
        ..transport_js.get_cell(receiver_events)
      ])
    })
  let view = identifier_fixture.full_view()
  runtime.begin_tree_transaction(sender, "A/_C", view, [])
  |> expect.to_equal(Ok(Nil))
  runtime.tree_edit_view(
    sender,
    "A/_C",
    view,
    tree_types.ArrayInsert(["left"], 1, [
      tree_types.ObjectValue(identifier_fixture.point_type, [
        #("label", tree_types.StringValue("accepted")),
      ]),
    ]),
  )
  |> expect.to_equal(Ok(Nil))
  runtime.tree_edit_view(
    sender,
    "A/_C",
    view,
    tree_types.SetField(
      ["left", "1", "label"],
      tree_types.StringValue("accepted-final"),
    ),
  )
  |> expect.to_equal(Ok(Nil))
  runtime.commit_tree_transaction(sender, "A/_C")
  |> expect.to_equal(Ok(Nil))
  let assert [submitted] = transport_js.get_cell(submissions)
  let identifier =
    runtime.tree_read(sender, "A/_C", ["left", "1", "id"])
    |> expect.to_be_ok()
  receiver_transport.on_event(
    "op",
    frame.encode_operation_event([
      sequenced_submission(submitted, "writer", 1),
    ])
      |> json.to_string,
  )
  transport_js.get_cell(receiver_events)
  |> expect.to_equal([
    channel.TreeEvent(tree_kernel.TreeChanged(False)),
  ])
  history_count(receiver, "trunk") |> expect.to_equal(1)
  runtime.tree_array_values(receiver, "A/_C", ["left"])
  |> expect.to_be_ok()
  |> list.length
  |> expect.to_equal(2)
  runtime.tree_read(receiver, "A/_C", ["left", "1", "label"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("accepted-final"))))
  runtime.tree_read(receiver, "A/_C", ["left", "1", "id"])
  |> expect.to_equal(Ok(identifier))

  sender_transport.on_close()
  sender_transport.on_join()
  sender_transport.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "writer-2",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 3,
      initial_clients: ["writer-2"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    )
      |> json.to_string,
  )
  sender_transport.on_event(
    "op",
    frame.encode_operation_event([
      sequenced_submission(submitted, "writer", 1),
      membership_frame(2, "join", "{\"clientId\":\"writer-2\",\"detail\":{}}"),
    ])
      |> json.to_string,
  )
  runtime.connection_observation(sender).phase
  |> expect.to_equal("catching-up")
  transport_js.get_cell(submissions) |> expect.to_equal([submitted])
  sender_transport.on_event(
    "op",
    frame.encode_operation_event([
      membership_frame(3, "leave", "\"writer\""),
    ])
      |> json.to_string,
  )
  runtime.connection_observation(sender).phase |> expect.to_equal("ready")
  transport_js.get_cell(submissions) |> expect.to_equal([submitted])
  history_count(sender, "pending") |> expect.to_equal(0)
  history_count(sender, "trunk") |> expect.to_equal(1)
  transport_js.get_cell(sender_events)
  |> expect.to_equal([
    channel.TreeEvent(tree_kernel.TreeChanged(True)),
  ])
  runtime.tree_read(sender, "A/_C", ["left", "1", "id"])
  |> expect.to_equal(Ok(identifier))
  runtime.close(sender)
  runtime.close(receiver)
}

@target(javascript)
pub type BootstrapTreeFixture {
  BootstrapTreeFixture(
    connect: fn() -> Nil,
    receive: fn() -> Nil,
    prefix: String,
    edit_rejected: fn() -> Bool,
    pending_before_close: fn() -> Int,
    phase: fn() -> String,
    ready: fn() -> Int,
    close: fn() -> Nil,
  )
}

@target(javascript)
fn bootstrap_tree_fixture() -> BootstrapTreeFixture {
  let assert Ok(#(input, prefix)) = runtime_fixture.routed_seed_input()
  let assert Ok(seed) = runtime_core.bootstrap_seed(input)
  let assert Ok(fixture) = fixtures.load("batched-commits")
  let assert Some(compressor) = input.compressor
  let assert Ok(captured) =
    runtime_fixture.read(fixture.input, fluid_ids.local_session(compressor))
  let assert [group] = captured.operations
  let callbacks = transport_js.new_cell(None)
  let edit_result = transport_js.new_cell(None)
  let pending_before_close = transport_js.new_cell(-1)
  let ready = transport_js.new_cell(0)
  let owner =
    runtime.start_with_transport_and_seed(
      http_base_url: "https://seed.invalid",
      connect_message: connect_message(),
      seed: seed,
      transport: runtime.Transport(connect: fn(handlers) {
        transport_js.set_cell(callbacks, Some(handlers))
        runtime.TransportHandle(
          push: fn(_, _) { Nil },
          close: fn() { Nil },
          drop: fn() { Nil },
          hold: fn() { Nil },
          resume: fn() { Nil },
        )
      }),
      on_ready: fn(_) {
        transport_js.set_cell(ready, transport_js.get_cell(ready) + 1)
      },
    )
  let assert Some(handlers) = transport_js.get_cell(callbacks)
  let _ =
    runtime.subscribe(owner, "A/_C", fn(_) {
      transport_js.set_cell(
        edit_result,
        Some(runtime.tree_edit(
          owner,
          "A/_C",
          tree_types.SetField(["title"], tree_types.StringValue("local")),
        )),
      )
      transport_js.set_cell(
        pending_before_close,
        runtime.diagnostics(owner).in_flight_count,
      )
      handlers.on_close()
    })
  BootstrapTreeFixture(
    connect: fn() {
      handlers.on_event(
        "connect_document_success",
        frame.encode_connected(
          client_id: "reader",
          tenant_id: "default",
          document_id: "tree",
          scopes: ["doc:read", "doc:write"],
          checkpoint_sequence_number: 2,
          initial_clients: ["reader"],
          initial_messages: [],
          timestamp: 0,
          presence_v1: False,
        )
          |> json.to_string,
      )
    },
    receive: fn() {
      handlers.on_event(
        "op",
        frame.encode_operation_event([runtime_fixture.sequenced_frame(group)])
          |> json.to_string,
      )
    },
    prefix: frame.encode_operation_event(list.map(
      prefix,
      runtime_fixture.sequenced_frame,
    ))
      |> json.to_string,
    edit_rejected: fn() {
      case transport_js.get_cell(edit_result) {
        Some(Error("tree edit requires a ready document connection")) -> True
        _ -> False
      }
    },
    pending_before_close: fn() { transport_js.get_cell(pending_before_close) },
    phase: fn() { runtime.diagnostics(owner).phase },
    ready: fn() { transport_js.get_cell(ready) },
    close: fn() { runtime.close(owner) },
  )
}

@target(javascript)
@external(javascript, "./shared_tree_bootstrap_ffi.mjs", "run")
fn run_bootstrap_tree(
  make_fixture: fn() -> BootstrapTreeFixture,
) -> Promise(Nil)

@target(javascript)
pub fn check_bootstrap_tree_close() -> Promise(Nil) {
  run_bootstrap_tree(bootstrap_tree_fixture)
}

@target(javascript)
pub fn seeded_runtime_resolves_routed_root_before_publication_test() {
  let assert Ok(#(input, prefix)) = runtime_fixture.routed_seed_input()
  let assert Ok(seed) = runtime_core.bootstrap_seed(input)
  let callbacks = transport_js.new_cell(None)
  let ready = transport_js.new_cell(None)
  let runtime =
    runtime.start_with_transport_and_seed(
      http_base_url: "https://seed.invalid",
      connect_message: connect_message(),
      transport: runtime.Transport(connect: fn(handlers) {
        transport_js.set_cell(callbacks, Some(handlers))
        runtime.TransportHandle(
          push: fn(_, _) { Nil },
          close: fn() { Nil },
          drop: fn() { Nil },
          hold: fn() { Nil },
          resume: fn() { Nil },
        )
      }),
      seed: seed,
      on_ready: fn(result) { transport_js.set_cell(ready, Some(result)) },
    )
  runtime.resolve_root(runtime) |> expect.to_be_error()
  let assert Some(callbacks) = transport_js.get_cell(callbacks)
  callbacks.on_join()
  let connected =
    frame.encode_connected(
      client_id: "reader",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 2,
      initial_clients: ["reader"],
      initial_messages: list.map(prefix, runtime_fixture.sequenced_frame),
      timestamp: 0,
      presence_v1: False,
    )
    |> json.to_string
  callbacks.on_event("connect_document_success", connected)
  transport_js.get_cell(ready) |> expect.to_equal(Some(Ok(Nil)))
  runtime.resolve_root(runtime) |> expect.to_equal(Ok("A/root"))
  runtime.tree_read(runtime, "A/_C", []) |> expect.to_be_ok()
  runtime.diagnostics(runtime).last_seen_sequence_number
  |> expect.to_equal(Some(2))
  let events = transport_js.new_cell([])
  let _ =
    runtime.subscribe(runtime, "A/_C", fn(event) {
      transport_js.set_cell(events, [event, ..transport_js.get_cell(events)])
    })
  let assert Ok(fixture) = fixtures.load("batched-commits")
  let assert Some(compressor) = input.compressor
  let assert Ok(captured) =
    runtime_fixture.read(fixture.input, fluid_ids.local_session(compressor))
  let assert [group] = captured.operations
  callbacks.on_event(
    "op",
    frame.encode_operation_event([runtime_fixture.sequenced_frame(group)])
      |> json.to_string,
  )
  runtime.diagnostics(runtime).last_seen_sequence_number
  |> expect.to_equal(Some(3))
  transport_js.get_cell(events) |> list.length |> expect.to_equal(1)
  callbacks.on_close()
  runtime.diagnostics(runtime).phase |> expect.to_equal("reconnecting")
  callbacks.on_join()
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader-2",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 3,
      initial_clients: ["reader-2"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    )
      |> json.to_string,
  )
  runtime.diagnostics(runtime).phase |> expect.to_equal("ready")
  runtime.is_synced(runtime) |> expect.to_equal(True)
  runtime.diagnostics(runtime).last_seen_sequence_number
  |> expect.to_equal(Some(3))
  runtime.resolve_root(runtime) |> expect.to_equal(Ok("A/root"))
  runtime.tree_edit(
    runtime,
    "A/_C",
    tree_types.SetField(["title"], tree_types.StringValue("pending")),
  )
  |> expect.to_equal(Ok(Nil))
  callbacks.on_event(
    "nack",
    "{\"nacks\":[{\"sequenceNumber\":1,\"content\":{\"code\":400,\"type\":\"BadRequestError\",\"message\":\"retry\"}}]}",
  )
  runtime.diagnostics(runtime).phase
  |> expect.to_equal("reconnecting")
  runtime.diagnostics(runtime).in_flight_count |> expect.to_equal(1)
  runtime.close(runtime)
}

@target(javascript)
pub fn shared_tree_facade_fork_edit_isolation_rebase_merge_test() {
  let input =
    identifier_fixture.full_seed_input(
      identifier_fixture.full_root(
        identifier_fixture.point("child", "child"),
        [],
        [],
        [],
      ),
    )
  let seed = runtime_core.bootstrap_seed(input) |> expect.to_be_ok()
  let callbacks = transport_js.new_cell(None)
  let submissions = transport_js.new_cell([])
  let inline_ack = transport_js.new_cell(False)
  let next_sequence = transport_js.new_cell(1)
  let document =
    watershed.connect_via_seed(
      tenant: "default",
      document: "tree",
      user_id: "reader",
      seed: seed,
      transport: runtime.Transport(connect: fn(handlers) {
        transport_js.set_cell(callbacks, Some(handlers))
        runtime.TransportHandle(
          push: fn(event, payload) {
            case event {
              "submitOp" -> {
                let assert Ok(dynamic) =
                  json.parse(json.to_string(payload), decode.dynamic)
                let assert Ok(frame.SubmitOperation(_, [[submitted]])) =
                  frame.decode_submit_operation(dynamic)
                transport_js.set_cell(submissions, [
                  submitted,
                  ..transport_js.get_cell(submissions)
                ])
                case transport_js.get_cell(inline_ack) {
                  True -> {
                    handlers.on_event(
                      "op",
                      frame.encode_operation_event([
                        sequenced_submission(
                          submitted,
                          "reader",
                          transport_js.get_cell(next_sequence),
                        ),
                      ])
                        |> json.to_string,
                    )
                    transport_js.set_cell(
                      next_sequence,
                      transport_js.get_cell(next_sequence) + 1,
                    )
                  }
                  False -> Nil
                }
              }
              _ -> Nil
            }
          },
          close: fn() { Nil },
          drop: fn() { Nil },
          hold: fn() { Nil },
          resume: fn() { Nil },
        )
      }),
      on_ready: fn(_) { Nil },
    )
  let assert Some(callbacks) = transport_js.get_cell(callbacks)
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["reader"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    )
      |> json.to_string,
  )
  let root = watershed.resolve_root(document) |> expect.to_be_ok()
  let marker = watershed.get(root, "tree") |> expect.to_be_ok()
  let assert [view] = input.tree_views
  let main =
    facade_fixture.resolve_javascript(document, marker, view.view)
    |> expect.to_be_ok()
  let parent = watershed.tree_fork(main) |> expect.to_be_ok()
  let fork = watershed.tree_fork(parent) |> expect.to_be_ok()
  watershed.tree_dispose_branch(parent) |> expect.to_equal(Ok(Nil))
  watershed.tree_dispose_branch(parent) |> expect.to_equal(Ok(Nil))
  watershed.tree_branch_status(parent)
  |> expect.to_equal(watershed.BranchDisposed)
  watershed.tree_branch_status(fork)
  |> expect.to_equal(watershed.BranchValid)
  watershed.tree_dispose_branch(main) |> expect.to_be_error()
  watershed.tree_upgrade_schema(fork) |> expect.to_be_error()
  let main_events = transport_js.new_cell([])
  let fork_events = transport_js.new_cell([])
  let _ =
    watershed.subscribe_tree(main, fn(event) {
      transport_js.set_cell(main_events, [
        event,
        ..transport_js.get_cell(main_events)
      ])
    })
  let fork_subscription =
    watershed.subscribe_tree(fork, fn(event) {
      transport_js.set_cell(fork_events, [
        event,
        ..transport_js.get_cell(fork_events)
      ])
    })

  facade_fixture.set_javascript(
    fork,
    ["child", "label"],
    tree_types.StringValue("fork"),
  )
  |> expect.to_equal(Ok(Nil))
  facade_fixture.get_javascript(main, ["child", "label"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("child"))))
  facade_fixture.get_javascript(fork, ["child", "label"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("fork"))))
  facade_fixture.map_set_javascript(
    fork,
    ["byKey"],
    "fork",
    identifier_fixture.point("fork", "fork"),
  )
  |> expect.to_equal(Ok(Nil))
  facade_fixture.array_insert_javascript(fork, ["left"], 0, [
    identifier_fixture.point("array", "array"),
  ])
  |> expect.to_equal(Ok(Nil))
  facade_fixture.map_get_javascript(main, ["byKey"], "fork")
  |> expect.to_equal(Ok(None))
  facade_fixture.array_values_javascript(main, ["left"])
  |> expect.to_equal(Ok([]))
  transport_js.get_cell(main_events) |> expect.to_equal([])
  transport_js.get_cell(fork_events)
  |> expect.to_equal([
    tree_kernel.TreeChanged(True),
    tree_kernel.TreeChanged(True),
    tree_kernel.TreeChanged(True),
  ])
  transport_js.get_cell(submissions) |> expect.to_equal([])
  watershed.unsubscribe(fork_subscription)
  facade_fixture.map_set_javascript(
    fork,
    ["byKey"],
    "unsubscribed",
    identifier_fixture.point("unsubscribed", "unsubscribed"),
  )
  |> expect.to_equal(Ok(Nil))
  transport_js.get_cell(fork_events) |> list.length |> expect.to_equal(3)

  watershed.tree_transaction(fork, [], fn(_) {
    watershed.tree_dispose_branch(fork) |> expect.to_be_error()
    facade_fixture.map_set_javascript(
      main,
      ["byKey"],
      "main",
      identifier_fixture.point("main", "main"),
    )
    |> expect.to_equal(Ok(Nil))
    Error(FacadeAbort)
  })
  |> expect.to_equal(Error(watershed.Aborted(FacadeAbort)))
  facade_fixture.map_get_javascript(main, ["byKey"], "main")
  |> expect.to_be_ok()
  |> expect.to_not_equal(None)
  facade_fixture.map_get_javascript(fork, ["byKey"], "main")
  |> expect.to_equal(Ok(None))
  transport_js.get_cell(fork_events)
  |> expect.to_equal([
    tree_kernel.TreeChanged(True),
    tree_kernel.TreeChanged(True),
    tree_kernel.TreeChanged(True),
  ])

  watershed.tree_transaction(fork, [], fn(tree) {
    facade_fixture.set_javascript(
      tree,
      ["child", "label"],
      tree_types.StringValue("discarded-preview"),
    )
    |> expect.to_equal(Ok(Nil))
    facade_fixture.map_set_javascript(
      main,
      ["byKey"],
      "throw-main",
      identifier_fixture.point("throw-main", "throw-main"),
    )
    |> expect.to_equal(Ok(Nil))
    throw_transaction(tree)
  })
  |> expect.to_be_error()
  facade_fixture.get_javascript(fork, ["child", "label"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("fork"))))
  facade_fixture.map_get_javascript(main, ["byKey"], "throw-main")
  |> expect.to_be_ok()
  |> expect.to_not_equal(None)
  watershed.tree_transaction(fork, [], fn(_) { Ok(Nil) })
  |> expect.to_equal(Ok(Nil))
  watershed.tree_branch_status(fork)
  |> expect.to_equal(watershed.BranchValid)
  watershed.tree_transaction(fork, [], fn(tree) {
    facade_fixture.map_set_javascript(
      tree,
      ["byKey"],
      "committed-owner",
      identifier_fixture.point("committed-owner", "committed-owner"),
    )
    |> expect.to_equal(Ok(Nil))
    facade_fixture.map_set_javascript(
      main,
      ["byKey"],
      "commit-main",
      identifier_fixture.point("commit-main", "commit-main"),
    )
    |> expect.to_equal(Ok(Nil))
    Ok(Nil)
  })
  |> expect.to_equal(Ok(Nil))
  let sibling = watershed.tree_fork(main) |> expect.to_be_ok()
  watershed.tree_transaction(main, [], fn(_) {
    facade_fixture.map_set_javascript(
      fork,
      ["byKey"],
      "reverse",
      identifier_fixture.point("reverse", "reverse"),
    )
    |> expect.to_equal(Ok(Nil))
    facade_fixture.map_set_javascript(
      sibling,
      ["byKey"],
      "sibling",
      identifier_fixture.point("sibling", "sibling"),
    )
    |> expect.to_equal(Ok(Nil))
    Error(FacadeAbort)
  })
  |> expect.to_equal(Error(watershed.Aborted(FacadeAbort)))
  facade_fixture.map_get_javascript(fork, ["byKey"], "reverse")
  |> expect.to_be_ok()
  |> expect.to_not_equal(None)
  facade_fixture.map_get_javascript(sibling, ["byKey"], "sibling")
  |> expect.to_be_ok()
  |> expect.to_not_equal(None)
  let pending_main = transport_js.get_cell(submissions) |> list.reverse
  callbacks.on_event(
    "op",
    frame.encode_operation_event(
      list.index_map(pending_main, fn(submitted, index) {
        sequenced_submission(submitted, "reader", index + 1)
      }),
    )
      |> json.to_string,
  )
  transport_js.set_cell(next_sequence, list.length(pending_main) + 1)
  transport_js.set_cell(submissions, [])

  let handles = transport_js.new_cell([])
  let commit_kinds = transport_js.new_cell([])
  let late_factory = transport_js.new_cell(None)
  let settled = transport_js.new_cell([])
  let delivery_order = transport_js.new_cell([])
  let guarded_results = transport_js.new_cell([])
  let guarded_callback_finished = transport_js.new_cell(0)
  let queued_actions = transport_js.new_cell([])
  let queued_revert = transport_js.new_cell([])
  let queued_once = transport_js.new_cell(False)
  runtime.set_scheduler(
    watershed.runtime_of(document),
    transport_js.Scheduler(
      now_milliseconds: fn() { 0 },
      schedule: fn(action, _) {
        transport_js.set_cell(queued_actions, [
          action,
          ..transport_js.get_cell(queued_actions)
        ])
        fn() { Nil }
      },
    ),
  )
  let _ =
    watershed.subscribe_tree_commits(fork, fn(event) {
      event.local |> expect.to_equal(True)
      transport_js.set_cell(commit_kinds, [
        event.kind,
        ..transport_js.get_cell(commit_kinds)
      ])
      let assert Some(get_revertible) = event.get_revertible
      transport_js.set_cell(late_factory, Some(get_revertible))
      let handle = get_revertible() |> expect.to_be_ok()
      get_revertible() |> expect.to_be_error()
      transport_js.set_cell(handles, [handle, ..transport_js.get_cell(handles)])
      let assert Some(on_settled) = event.on_settled
      on_settled(fn(outcome) {
        transport_js.set_cell(delivery_order, [
          "settled",
          ..transport_js.get_cell(delivery_order)
        ])
        transport_js.set_cell(settled, [
          outcome,
          ..transport_js.get_cell(settled)
        ])
      })
      |> expect.to_equal(Ok(Nil))
    })
  facade_fixture.set_javascript(
    fork,
    ["child", "label"],
    tree_types.StringValue("branch-change"),
  )
  |> expect.to_equal(Ok(Nil))
  let assert [original_handle] = transport_js.get_cell(handles)
  let assert Some(late_factory) = transport_js.get_cell(late_factory)
  late_factory() |> expect.to_be_error()
  watershed.tree_revertible_status(original_handle)
  |> expect.to_equal(watershed.RevertibleValid)
  transport_js.get_cell(settled) |> expect.to_equal([])

  watershed.tree_rebase_onto(fork, main) |> expect.to_equal(Ok(Nil))
  let target_subscription =
    watershed.subscribe_tree_commits(main, fn(_) {
      transport_js.set_cell(delivery_order, [
        "target",
        ..transport_js.get_cell(delivery_order)
      ])
      transport_js.set_cell(guarded_results, [
        #("rebase", watershed.tree_rebase_onto(fork, main)),
        #("merge", watershed.tree_merge(main, fork, False)),
        #(
          "transaction",
          watershed.tree_transaction(fork, [], fn(_) { Ok(Nil) })
            |> result.map_error(string.inspect),
        ),
        #("revert", watershed.tree_revert(original_handle, False)),
        ..transport_js.get_cell(guarded_results)
      ])
      case transport_js.get_cell(queued_once) {
        True -> Nil
        False -> {
          transport_js.set_cell(queued_once, True)
          runtime.schedule(
            watershed.runtime_of(document),
            fn() {
              transport_js.set_cell(queued_revert, [
                watershed.tree_revert(original_handle, True),
                ..transport_js.get_cell(queued_revert)
              ])
            },
            0,
          )
        }
      }
      transport_js.set_cell(
        guarded_callback_finished,
        transport_js.get_cell(guarded_callback_finished) + 1,
      )
    })
  transport_js.set_cell(inline_ack, True)
  watershed.tree_merge(main, fork, False) |> expect.to_equal(Ok(Nil))
  transport_js.set_cell(inline_ack, False)
  transport_js.set_cell(submissions, [])
  transport_js.get_cell(delivery_order)
  |> fn(order) {
    let assert ["settled", ..targets] = order
    targets
    |> list.all(fn(value) { value == "target" })
    |> expect.to_equal(True)
  }
  transport_js.get_cell(guarded_callback_finished)
  |> expect.to_equal(list.length(transport_js.get_cell(guarded_results)) / 4)
  transport_js.get_cell(guarded_callback_finished)
  |> fn(count) { count > 0 }
  |> expect.to_equal(True)
  transport_js.get_cell(guarded_results)
  |> list.each(fn(entry) { entry.1 |> expect.to_be_error() })
  transport_js.get_cell(queued_revert) |> expect.to_equal([])
  watershed.unsubscribe(target_subscription)
  transport_js.get_cell(queued_actions)
  |> list.reverse
  |> list.each(fn(action) { action() })
  transport_js.get_cell(queued_revert) |> expect.to_equal([Ok(Nil)])
  watershed.tree_branch_status(fork)
  |> expect.to_equal(watershed.BranchValid)
  transport_js.get_cell(settled)
  |> expect.to_equal([tree_types.FullyApplied])
  watershed.tree_rebase_onto(fork, main) |> expect.to_equal(Ok(Nil))
  watershed.tree_revertible_status(original_handle)
  |> expect.to_equal(watershed.RevertibleDisposed)
  facade_fixture.get_javascript(fork, ["child", "label"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("fork"))))
  let assert [redo_handle, _] = transport_js.get_cell(handles)
  watershed.tree_revertible_status(original_handle)
  |> expect.to_equal(watershed.RevertibleDisposed)
  watershed.tree_revertible_status(redo_handle)
  |> expect.to_equal(watershed.RevertibleValid)
  watershed.tree_revert(redo_handle, True) |> expect.to_equal(Ok(Nil))
  facade_fixture.get_javascript(fork, ["child", "label"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("branch-change"))))
  transport_js.get_cell(commit_kinds)
  |> expect.to_equal([
    tree_types.RedoCommit,
    tree_types.UndoCommit,
    tree_types.DefaultCommit,
  ])
  watershed.tree_merge(main, fork, True) |> expect.to_equal(Ok(Nil))
  watershed.tree_branch_status(main)
  |> expect.to_equal(watershed.DocumentBranch)
  watershed.tree_branch_status(fork)
  |> expect.to_equal(watershed.BranchDisposed)
  facade_fixture.get_javascript(main, ["child", "label"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("branch-change"))))
  facade_fixture.map_get_javascript(main, ["byKey"], "fork")
  |> expect.to_be_ok()
  |> expect.to_not_equal(None)
  facade_fixture.array_values_javascript(main, ["left"])
  |> expect.to_be_ok()
  |> list.length
  |> expect.to_equal(1)

  let pending = transport_js.get_cell(submissions) |> list.reverse
  let sequence = transport_js.get_cell(next_sequence)
  callbacks.on_event(
    "op",
    frame.encode_operation_event(
      list.index_map(pending, fn(submitted, index) {
        sequenced_submission(submitted, "reader", sequence + index)
      }),
    )
      |> json.to_string,
  )
  transport_js.set_cell(next_sequence, sequence + list.length(pending))
  transport_js.set_cell(submissions, [])
  transport_js.set_cell(inline_ack, True)
  let disposed_settlements = transport_js.new_cell([])
  let disposable = watershed.tree_fork(main) |> expect.to_be_ok()
  let _ =
    watershed.subscribe_tree_commits(disposable, fn(event) {
      let assert Some(on_settled) = event.on_settled
      on_settled(fn(_) {
        watershed.tree_dispose_branch(disposable) |> expect.to_equal(Ok(Nil))
        transport_js.set_cell(disposed_settlements, [
          "dispose-first",
          ..transport_js.get_cell(disposed_settlements)
        ])
      })
      |> expect.to_equal(Ok(Nil))
      on_settled(fn(_) {
        transport_js.set_cell(disposed_settlements, [
          "dispose-second",
          ..transport_js.get_cell(disposed_settlements)
        ])
      })
      |> expect.to_equal(Ok(Nil))
    })
  facade_fixture.map_set_javascript(
    disposable,
    ["byKey"],
    "dispose-during-settlement",
    identifier_fixture.point(
      "dispose-during-settlement",
      "dispose-during-settlement",
    ),
  )
  |> expect.to_equal(Ok(Nil))
  watershed.tree_merge(main, disposable, False) |> expect.to_equal(Ok(Nil))
  transport_js.get_cell(disposed_settlements)
  |> expect.to_equal(["dispose-first"])

  let snapshot_calls = transport_js.new_cell([])
  let snapshot = watershed.tree_fork(main) |> expect.to_be_ok()
  let _ =
    watershed.subscribe_tree(snapshot, fn(_) {
      transport_js.set_cell(snapshot_calls, [
        "snapshot-second",
        ..transport_js.get_cell(snapshot_calls)
      ])
    })
  let _ =
    watershed.subscribe_tree(snapshot, fn(_) {
      watershed.tree_dispose_branch(snapshot) |> expect.to_equal(Ok(Nil))
      transport_js.set_cell(snapshot_calls, [
        "snapshot-first",
        ..transport_js.get_cell(snapshot_calls)
      ])
    })
  facade_fixture.map_set_javascript(
    snapshot,
    ["byKey"],
    "dispose-during-delivery",
    identifier_fixture.point(
      "dispose-during-delivery",
      "dispose-during-delivery",
    ),
  )
  |> expect.to_equal(Ok(Nil))
  transport_js.get_cell(snapshot_calls) |> expect.to_equal(["snapshot-first"])

  let unsubscribe_tree_calls = transport_js.new_cell([])
  let unsubscribe_commit_calls = transport_js.new_cell([])
  let unsubscription = watershed.tree_fork(main) |> expect.to_be_ok()
  let canceled_tree =
    watershed.subscribe_tree(unsubscription, fn(_) {
      transport_js.set_cell(unsubscribe_tree_calls, [
        "canceled",
        ..transport_js.get_cell(unsubscribe_tree_calls)
      ])
    })
  let _ =
    watershed.subscribe_tree(unsubscription, fn(_) {
      watershed.unsubscribe(canceled_tree)
      transport_js.set_cell(unsubscribe_tree_calls, [
        "canceling",
        ..transport_js.get_cell(unsubscribe_tree_calls)
      ])
    })
  let _ =
    watershed.subscribe_tree(unsubscription, fn(_) {
      transport_js.set_cell(unsubscribe_tree_calls, [
        "other",
        ..transport_js.get_cell(unsubscribe_tree_calls)
      ])
    })
  let canceled_commit =
    watershed.subscribe_tree_commits(unsubscription, fn(_) {
      transport_js.set_cell(unsubscribe_commit_calls, [
        "canceled",
        ..transport_js.get_cell(unsubscribe_commit_calls)
      ])
    })
  let _ =
    watershed.subscribe_tree_commits(unsubscription, fn(_) {
      watershed.unsubscribe(canceled_commit)
      transport_js.set_cell(unsubscribe_commit_calls, [
        "canceling",
        ..transport_js.get_cell(unsubscribe_commit_calls)
      ])
    })
  let _ =
    watershed.subscribe_tree_commits(unsubscription, fn(_) {
      transport_js.set_cell(unsubscribe_commit_calls, [
        "other",
        ..transport_js.get_cell(unsubscribe_commit_calls)
      ])
    })
  facade_fixture.map_set_javascript(
    unsubscription,
    ["byKey"],
    "unsubscribe-during-delivery",
    identifier_fixture.point(
      "unsubscribe-during-delivery",
      "unsubscribe-during-delivery",
    ),
  )
  |> expect.to_equal(Ok(Nil))
  transport_js.get_cell(unsubscribe_tree_calls)
  |> expect.to_equal(["canceling", "other"])
  transport_js.get_cell(unsubscribe_commit_calls)
  |> expect.to_equal(["canceling", "other"])

  watershed.tree_dispose_branch(fork) |> expect.to_equal(Ok(Nil))
  let live = watershed.tree_fork(main) |> expect.to_be_ok()
  let live_settlements = transport_js.new_cell([])
  let live_registrations = transport_js.new_cell([])
  let _ =
    watershed.subscribe_tree_commits(live, fn(event) {
      let first = case event.on_settled {
        Some(on_settled) ->
          on_settled(fn(outcome) {
            watershed.close(document)
            transport_js.set_cell(live_settlements, [
              outcome,
              ..transport_js.get_cell(live_settlements)
            ])
          })
        None -> Error("missing live settlement registration")
      }
      let second = case event.on_settled {
        Some(on_settled) ->
          on_settled(fn(outcome) {
            transport_js.set_cell(live_settlements, [
              outcome,
              ..transport_js.get_cell(live_settlements)
            ])
          })
        None -> Error("missing live settlement registration")
      }
      transport_js.set_cell(live_registrations, [
        #(first, second),
        ..transport_js.get_cell(live_registrations)
      ])
    })
  let closed_settlements = transport_js.new_cell([])
  let closing_registrations = transport_js.new_cell([])
  let closing = watershed.tree_fork(main) |> expect.to_be_ok()
  let _ =
    watershed.subscribe_tree_commits(closing, fn(event) {
      let first = case event.on_settled {
        Some(on_settled) ->
          on_settled(fn(_) {
            transport_js.set_cell(closed_settlements, [
              "close-first",
              ..transport_js.get_cell(closed_settlements)
            ])
          })
        None -> Error("missing closing settlement registration")
      }
      let second = case event.on_settled {
        Some(on_settled) ->
          on_settled(fn(_) {
            transport_js.set_cell(closed_settlements, [
              "close-second",
              ..transport_js.get_cell(closed_settlements)
            ])
          })
        None -> Error("missing closing settlement registration")
      }
      transport_js.set_cell(closing_registrations, [
        #(first, second),
        ..transport_js.get_cell(closing_registrations)
      ])
    })
  facade_fixture.map_set_javascript(
    closing,
    ["byKey"],
    "close-during-settlement",
    identifier_fixture.point(
      "close-during-settlement",
      "close-during-settlement",
    ),
  )
  |> expect.to_equal(Ok(Nil))
  transport_js.get_cell(closing_registrations)
  |> expect.to_equal([#(Ok(Nil), Ok(Nil))])
  watershed.tree_merge(live, closing, False) |> expect.to_equal(Ok(Nil))
  transport_js.get_cell(live_registrations)
  |> expect.to_equal([#(Ok(Nil), Ok(Nil))])
  watershed.tree_merge(main, closing, False) |> expect.to_be_error()
  transport_js.get_cell(closed_settlements) |> expect.to_equal([])
  transport_js.get_cell(live_settlements)
  |> expect.to_equal([tree_types.FullyApplied])

  watershed.tree_branch_status(live)
  |> expect.to_equal(watershed.BranchDisposed)
}

@target(javascript)
pub fn facade_merge_ack_disposal_cancels_only_disposed_settlement_scopes_test() {
  let input =
    identifier_fixture.full_seed_input(
      identifier_fixture.full_root(
        identifier_fixture.point("child", "child"),
        [],
        [],
        [],
      ),
    )
  let seed = runtime_core.bootstrap_seed(input) |> expect.to_be_ok()
  let callbacks = transport_js.new_cell(None)
  let submissions = transport_js.new_cell([])
  let document =
    watershed.connect_via_seed(
      tenant: "default",
      document: "tree",
      user_id: "reader",
      seed: seed,
      transport: runtime.Transport(connect: fn(handlers) {
        transport_js.set_cell(callbacks, Some(handlers))
        runtime.TransportHandle(
          push: fn(event, payload) {
            case event {
              "submitOp" -> {
                let assert Ok(dynamic) =
                  json.parse(json.to_string(payload), decode.dynamic)
                let assert Ok(frame.SubmitOperation(_, [[submitted]])) =
                  frame.decode_submit_operation(dynamic)
                transport_js.set_cell(submissions, [
                  submitted,
                  ..transport_js.get_cell(submissions)
                ])
              }
              _ -> Nil
            }
          },
          close: fn() { Nil },
          drop: fn() { Nil },
          hold: fn() { Nil },
          resume: fn() { Nil },
        )
      }),
      on_ready: fn(_) { Nil },
    )
  let assert Some(callbacks) = transport_js.get_cell(callbacks)
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["reader"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    )
      |> json.to_string,
  )
  let root = watershed.resolve_root(document) |> expect.to_be_ok()
  let marker = watershed.get(root, "tree") |> expect.to_be_ok()
  let assert [view] = input.tree_views
  let main =
    facade_fixture.resolve_javascript(document, marker, view.view)
    |> expect.to_be_ok()
  let source = watershed.tree_fork(main) |> expect.to_be_ok()
  let target = watershed.tree_fork(main) |> expect.to_be_ok()
  let descendant = watershed.tree_fork(target) |> expect.to_be_ok()
  let source_outcomes = transport_js.new_cell([])
  let target_outcomes = transport_js.new_cell([])
  let descendant_outcomes = transport_js.new_cell([])
  let main_outcomes = transport_js.new_cell([])
  let source_factory = transport_js.new_cell([])
  let main_factory = transport_js.new_cell([])
  let registrations = transport_js.new_cell([])
  let _ =
    watershed.subscribe_tree_commits(source, fn(event) {
      transport_js.set_cell(source_factory, [
        case event.get_revertible {
          Some(factory) -> factory()
          None -> Error("missing source revertible factory")
        },
        ..transport_js.get_cell(source_factory)
      ])
      let registration = case event.on_settled {
        Some(on_settled) ->
          on_settled(fn(outcome) {
            transport_js.set_cell(source_outcomes, [
              outcome,
              ..transport_js.get_cell(source_outcomes)
            ])
          })
        None -> Error("missing source settlement registration")
      }
      transport_js.set_cell(registrations, [
        #("source", registration),
        ..transport_js.get_cell(registrations)
      ])
    })
  let _ =
    watershed.subscribe_tree_commits(target, fn(event) {
      let first = case event.on_settled {
        Some(on_settled) ->
          on_settled(fn(outcome) {
            let disposal = watershed.tree_dispose_branch(target)
            transport_js.set_cell(target_outcomes, [
              #(outcome, disposal),
              ..transport_js.get_cell(target_outcomes)
            ])
          })
        None -> Error("missing target settlement registration")
      }
      let second = case event.on_settled {
        Some(on_settled) ->
          on_settled(fn(outcome) {
            transport_js.set_cell(target_outcomes, [
              #(outcome, Ok(Nil)),
              ..transport_js.get_cell(target_outcomes)
            ])
          })
        None -> Error("missing target settlement registration")
      }
      transport_js.set_cell(registrations, [
        #("target-later", second),
        #("target-first", first),
        ..transport_js.get_cell(registrations)
      ])
    })
  let _ =
    watershed.subscribe_tree_commits(descendant, fn(event) {
      let registration = case event.on_settled {
        Some(on_settled) ->
          on_settled(fn(outcome) {
            transport_js.set_cell(descendant_outcomes, [
              outcome,
              ..transport_js.get_cell(descendant_outcomes)
            ])
          })
        None -> Error("missing descendant settlement registration")
      }
      transport_js.set_cell(registrations, [
        #("descendant", registration),
        ..transport_js.get_cell(registrations)
      ])
    })
  let _ =
    watershed.subscribe_tree_commits(main, fn(event) {
      transport_js.set_cell(main_factory, [
        case event.get_revertible {
          Some(factory) -> factory()
          None -> Error("missing main revertible factory")
        },
        ..transport_js.get_cell(main_factory)
      ])
      let registration = case event.on_settled {
        Some(on_settled) ->
          on_settled(fn(outcome) {
            transport_js.set_cell(main_outcomes, [
              outcome,
              ..transport_js.get_cell(main_outcomes)
            ])
          })
        None -> Error("missing main settlement registration")
      }
      transport_js.set_cell(registrations, [
        #("main", registration),
        ..transport_js.get_cell(registrations)
      ])
    })
  facade_fixture.set_javascript(
    source,
    ["child", "label"],
    tree_types.StringValue("settled"),
  )
  |> expect.to_equal(Ok(Nil))
  watershed.tree_merge(target, source, False) |> expect.to_equal(Ok(Nil))
  watershed.tree_merge(descendant, target, False) |> expect.to_equal(Ok(Nil))
  watershed.tree_merge(main, source, True) |> expect.to_equal(Ok(Nil))
  let assert [source_factory_result] = transport_js.get_cell(source_factory)
  source_factory_result |> expect.to_be_ok()
  let assert [main_factory_result] = transport_js.get_cell(main_factory)
  main_factory_result |> expect.to_be_ok()
  transport_js.get_cell(registrations)
  |> expect.to_equal([
    #("main", Ok(Nil)),
    #("descendant", Ok(Nil)),
    #("target-later", Ok(Nil)),
    #("target-first", Ok(Nil)),
    #("source", Ok(Nil)),
  ])
  transport_js.get_cell(source_outcomes) |> expect.to_equal([])
  transport_js.get_cell(target_outcomes) |> expect.to_equal([])
  transport_js.get_cell(descendant_outcomes) |> expect.to_equal([])
  transport_js.get_cell(main_outcomes) |> expect.to_equal([])
  let assert [submitted] = transport_js.get_cell(submissions)
  callbacks.on_event(
    "op",
    frame.encode_operation_event([
      sequenced_submission(submitted, "reader", 1),
    ])
      |> json.to_string,
  )
  transport_js.get_cell(source_outcomes) |> expect.to_equal([])
  transport_js.get_cell(target_outcomes)
  |> expect.to_equal([#(tree_types.FullyApplied, Ok(Nil))])
  transport_js.get_cell(descendant_outcomes)
  |> expect.to_equal([tree_types.FullyApplied])
  transport_js.get_cell(main_outcomes)
  |> expect.to_equal([tree_types.FullyApplied])
  watershed.tree_branch_status(source)
  |> expect.to_equal(watershed.BranchDisposed)
  watershed.tree_branch_status(target)
  |> expect.to_equal(watershed.BranchDisposed)
  watershed.tree_branch_status(descendant)
  |> expect.to_equal(watershed.BranchValid)
  callbacks.on_event(
    "op",
    frame.encode_operation_event([
      sequenced_submission(submitted, "reader", 1),
    ])
      |> json.to_string,
  )
  transport_js.get_cell(target_outcomes) |> list.length |> expect.to_equal(1)
  transport_js.get_cell(descendant_outcomes)
  |> list.length
  |> expect.to_equal(1)
  transport_js.get_cell(main_outcomes) |> list.length |> expect.to_equal(1)
  watershed.close(document)
}

@target(javascript)
pub fn facade_branch_settlement_survives_unsubscribe_and_reconnect_test() {
  let input =
    identifier_fixture.full_seed_input(
      identifier_fixture.full_root(
        identifier_fixture.point("child", "child"),
        [],
        [],
        [],
      ),
    )
  let seed = runtime_core.bootstrap_seed(input) |> expect.to_be_ok()
  let callbacks = transport_js.new_cell(None)
  let submissions = transport_js.new_cell([])
  let document =
    watershed.connect_via_seed(
      tenant: "default",
      document: "tree",
      user_id: "reader",
      seed: seed,
      transport: runtime.Transport(connect: fn(handlers) {
        transport_js.set_cell(callbacks, Some(handlers))
        runtime.TransportHandle(
          push: fn(event, payload) {
            case event {
              "submitOp" ->
                transport_js.set_cell(submissions, [
                  payload,
                  ..transport_js.get_cell(submissions)
                ])
              _ -> Nil
            }
          },
          close: fn() { Nil },
          drop: fn() { Nil },
          hold: fn() { Nil },
          resume: fn() { Nil },
        )
      }),
      on_ready: fn(_) { Nil },
    )
  let assert Some(first) = transport_js.get_cell(callbacks)
  first.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["reader"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    )
      |> json.to_string,
  )
  let root = watershed.resolve_root(document) |> expect.to_be_ok()
  let marker = watershed.get(root, "tree") |> expect.to_be_ok()
  let assert [view] = input.tree_views
  let main =
    facade_fixture.resolve_javascript(document, marker, view.view)
    |> expect.to_be_ok()
  let source = watershed.tree_fork(main) |> expect.to_be_ok()
  let outcomes = transport_js.new_cell([])
  let registrations = transport_js.new_cell([])
  let token =
    watershed.subscribe_tree_commits(source, fn(event) {
      let registration = case event.on_settled {
        Some(on_settled) ->
          on_settled(fn(outcome) {
            transport_js.set_cell(outcomes, [
              outcome,
              ..transport_js.get_cell(outcomes)
            ])
          })
        None -> Error("missing reconnect settlement registration")
      }
      transport_js.set_cell(registrations, [
        registration,
        ..transport_js.get_cell(registrations)
      ])
    })
  facade_fixture.set_javascript(
    source,
    ["child", "label"],
    tree_types.StringValue("reconnect"),
  )
  |> expect.to_equal(Ok(Nil))
  transport_js.get_cell(registrations) |> expect.to_equal([Ok(Nil)])
  watershed.unsubscribe(token)
  watershed.tree_merge(main, source, False) |> expect.to_equal(Ok(Nil))
  let assert [original_payload] = transport_js.get_cell(submissions)
  let original_dynamic =
    json.parse(json.to_string(original_payload), decode.dynamic)
    |> expect.to_be_ok()
  let assert frame.SubmitOperation(original_client, [[original]]) =
    frame.decode_submit_operation(original_dynamic)
    |> expect.to_be_ok()
  original_client |> expect.to_equal("reader")
  original.client_sequence_number |> expect.to_equal(1)
  original.reference_sequence_number |> expect.to_equal(0)
  transport_js.get_cell(outcomes) |> expect.to_equal([])
  first.on_close()
  first.on_join()
  first.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader-2",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 1,
      initial_clients: ["reader-2"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    )
      |> json.to_string,
  )
  first.on_event(
    "op",
    frame.encode_operation_event([
      membership_frame(1, "join", "{\"clientId\":\"reader-2\",\"detail\":{}}"),
      membership_frame(2, "leave", "\"reader\""),
    ])
      |> json.to_string,
  )
  let assert [resent_payload, _] = transport_js.get_cell(submissions)
  let resent_dynamic =
    json.parse(json.to_string(resent_payload), decode.dynamic)
    |> expect.to_be_ok()
  let assert frame.SubmitOperation(resent_client, [[resent]]) =
    frame.decode_submit_operation(resent_dynamic)
    |> expect.to_be_ok()
  resent_client |> expect.to_equal("reader-2")
  resent.client_sequence_number |> expect.to_equal(1)
  resent.reference_sequence_number |> expect.to_equal(2)
  resent.contents |> expect.to_equal(original.contents)
  resent.metadata |> expect.to_equal(original.metadata)
  let original_envelope =
    fluid_container.decode(original.contents, original.metadata)
    |> expect.to_be_ok()
  let resent_envelope =
    fluid_container.decode(resent.contents, resent.metadata)
    |> expect.to_be_ok()
  let assert [
    fluid_container.ContainerMessage(
      fluid_container.IdAllocation(original_range),
      0,
      _,
    ),
    fluid_container.ContainerMessage(
      fluid_container.ChannelOperation(fluid_container.Route("A", "_C"), _),
      1,
      _,
    ),
  ] = original_envelope.messages
  let assert [
    fluid_container.ContainerMessage(
      fluid_container.IdAllocation(resent_range),
      0,
      _,
    ),
    fluid_container.ContainerMessage(
      fluid_container.ChannelOperation(fluid_container.Route("A", "_C"), _),
      1,
      _,
    ),
  ] = resent_envelope.messages
  resent_range |> expect.to_equal(original_range)
  let assert Some("reader-2") =
    runtime.connection_observation(watershed.runtime_of(document)).client_id
  first.on_event(
    "op",
    frame.encode_operation_event([
      sequenced_submission(resent, resent_client, 3),
    ])
      |> json.to_string,
  )
  transport_js.get_cell(outcomes)
  |> expect.to_equal([tree_types.FullyApplied])
  transport_js.get_cell(outcomes) |> list.length |> expect.to_equal(1)
  transport_js.get_cell(submissions) |> list.length |> expect.to_equal(2)
  watershed.tree_branch_status(source)
  |> expect.to_equal(watershed.BranchValid)
  watershed.close(document)
}

@target(javascript)
pub fn facade_merge_invalid_inline_echo_rejects_success_delivery_test() {
  let input =
    identifier_fixture.full_seed_input(
      identifier_fixture.full_root(
        identifier_fixture.point("child", "child"),
        [],
        [],
        [],
      ),
    )
  let seed = runtime_core.bootstrap_seed(input) |> expect.to_be_ok()
  let callbacks = transport_js.new_cell(None)
  let document =
    watershed.connect_via_seed(
      tenant: "default",
      document: "tree",
      user_id: "reader",
      seed: seed,
      transport: runtime.Transport(connect: fn(handlers) {
        transport_js.set_cell(callbacks, Some(handlers))
        runtime.TransportHandle(
          push: fn(event, payload) {
            case event {
              "submitOp" -> {
                let assert Ok(dynamic) =
                  json.parse(json.to_string(payload), decode.dynamic)
                let assert Ok(frame.SubmitOperation(sender, [[submitted]])) =
                  frame.decode_submit_operation(dynamic)
                let assert Ok(batch) =
                  fluid_container.decode(submitted.contents, submitted.metadata)
                let assert [first, last] = batch.messages
                let assert Ok(invalid) =
                  fluid_container.encode_batch(
                    fluid_container.DecodedBatch(batch.grouped, batch.metadata, [
                      first,
                      fluid_container.ContainerMessage(
                        ..last,
                        kind: fluid_container.ChannelOperation(
                          fluid_container.Route("missing", "root"),
                          json.null(),
                        ),
                      ),
                    ]),
                  )
                handlers.on_event(
                  "op",
                  frame.encode_operation_event([
                    frame.Sequenced(
                      client_id: Some(sender),
                      sequence_number: 1,
                      minimum_sequence_number: 0,
                      client_sequence_number: submitted.client_sequence_number,
                      reference_sequence_number: submitted.reference_sequence_number,
                      operation_type: submitted.operation_type,
                      contents: invalid,
                      metadata: submitted.metadata,
                      timestamp: 0,
                      data: None,
                      compression: None,
                    ),
                  ])
                    |> json.to_string,
                )
              }
              _ -> Nil
            }
          },
          close: fn() { Nil },
          drop: fn() { Nil },
          hold: fn() { Nil },
          resume: fn() { Nil },
        )
      }),
      on_ready: fn(_) { Nil },
    )
  let assert Some(callbacks) = transport_js.get_cell(callbacks)
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["reader"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    )
      |> json.to_string,
  )
  let root = watershed.resolve_root(document) |> expect.to_be_ok()
  let marker = watershed.get(root, "tree") |> expect.to_be_ok()
  let assert [view] = input.tree_views
  let main =
    facade_fixture.resolve_javascript(document, marker, view.view)
    |> expect.to_be_ok()
  let fork = watershed.tree_fork(main) |> expect.to_be_ok()
  let deliveries = transport_js.new_cell(0)
  let _ =
    watershed.subscribe_tree_commits(main, fn(_) {
      transport_js.set_cell(deliveries, transport_js.get_cell(deliveries) + 1)
    })
  facade_fixture.map_set_javascript(
    fork,
    ["byKey"],
    "merge-candidate",
    identifier_fixture.point("merge-candidate", "merge-candidate"),
  )
  |> expect.to_equal(Ok(Nil))
  watershed.tree_merge(main, fork, False) |> expect.to_be_error()
  transport_js.get_cell(deliveries) |> expect.to_equal(0)
  runtime.diagnostics(watershed.runtime_of(document)).phase
  |> string.starts_with("suspended-pending-tree:")
  |> expect.to_equal(True)
  facade_fixture.map_get_javascript(main, ["byKey"], "merge-candidate")
  |> expect.to_be_ok()
  |> expect.to_not_equal(None)
  watershed.close(document)
}

@target(javascript)
pub fn identifier_refusals_preserve_installed_runtime_test() {
  let assert Ok(seed) =
    identifier_fixture.seed_input()
    |> runtime_core.bootstrap_seed
  let callbacks = transport_js.new_cell(None)
  let ready = transport_js.new_cell(None)
  let pushed = transport_js.new_cell([])
  let owner =
    runtime.start_with_transport_and_seed(
      http_base_url: "https://seed.invalid",
      connect_message: connect_message(),
      transport: runtime.Transport(connect: fn(handlers) {
        transport_js.set_cell(callbacks, Some(handlers))
        runtime.TransportHandle(
          push: fn(event, payload) {
            case event {
              "submitOp" ->
                transport_js.set_cell(pushed, [
                  payload,
                  ..transport_js.get_cell(pushed)
                ])
              _ -> Nil
            }
          },
          close: fn() { Nil },
          drop: fn() { Nil },
          hold: fn() { Nil },
          resume: fn() { Nil },
        )
      }),
      seed: seed,
      on_ready: fn(result) { transport_js.set_cell(ready, Some(result)) },
    )
  let assert Some(callbacks) = transport_js.get_cell(callbacks)
  callbacks.on_join()
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["reader"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    )
      |> json.to_string,
  )
  transport_js.get_cell(ready) |> expect.to_equal(Some(Ok(Nil)))
  let events = transport_js.new_cell([])
  let _ =
    runtime.subscribe(owner, "A/_C", fn(event) {
      transport_js.set_cell(events, [event, ..transport_js.get_cell(events)])
    })
  let before = runtime.diagnostics(owner)

  [
    tree_types.SetField(["id"], tree_types.StringValue("replacement")),
    tree_types.SetField(["id"], tree_types.StringValue("literal-custom-id")),
    tree_types.ClearField(["id"]),
  ]
  |> list.each(fn(edit) {
    runtime.tree_edit(owner, "A/_C", edit) |> expect.to_be_error
    runtime.tree_read(owner, "A/_C", ["id"])
    |> expect.to_equal(Ok(Some(tree_types.StringValue("literal-custom-id"))))
    transport_js.get_cell(events) |> expect.to_equal([])
    transport_js.get_cell(pushed) |> expect.to_equal([])
    runtime.diagnostics(owner).in_flight_count
    |> expect.to_equal(before.in_flight_count)
  })
  runtime.close(owner)
}

@target(javascript)
pub fn routed_facade_root_serializes_its_absolute_handle_test() {
  let assert Ok(#(input, _)) = runtime_fixture.routed_seed_input()
  let assert Ok(seed) =
    runtime_core.bootstrap_seed(
      runtime_core.BootstrapSeedInput(
        ..input,
        datastores: list.append(input.datastores, [
          runtime_core.DatastoreSeed("B", ["test"]),
        ]),
        channels: list.append(input.channels, [
          runtime_core.ChannelSeed(
            fluid_container.Route("B", "root"),
            channel.fluid_attributes(channel.MapChannel),
            channel.MapSnapshot([]),
          ),
        ]),
      ),
    )
  let callbacks = transport_js.new_cell(None)
  let document =
    watershed.connect_via_seed(
      tenant: "default",
      document: "tree",
      user_id: "reader",
      seed: seed,
      transport: runtime.Transport(connect: fn(handlers) {
        transport_js.set_cell(callbacks, Some(handlers))
        runtime.TransportHandle(
          push: fn(_, _) { Nil },
          close: fn() { Nil },
          drop: fn() { Nil },
          hold: fn() { Nil },
          resume: fn() { Nil },
        )
      }),
      on_ready: fn(_) { Nil },
    )
  watershed.resolve_root(document) |> expect.to_be_error()
  let assert Some(callbacks) = transport_js.get_cell(callbacks)
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["reader"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    )
      |> json.to_string,
  )
  let assert Ok(root) = watershed.resolve_root(document)
  let assert [view] = input.tree_views
  let definition = facade_fixture.definition(view.view) |> expect.to_be_ok()
  let assert Ok(marker) = watershed.get(root, "tree")
  let assert Ok(tree) =
    facade_fixture.resolve_javascript(document, marker, view.view)
  watershed.tree_handle_of(tree)
  |> expect.to_equal(handle.encode_handle("A/_C"))
  let typed = watershed.typed(root)
  watershed.resolve_tree_field(
    document,
    typed,
    schema.channel_field("tree"),
    definition,
  )
  |> result.map(fn(value) { option.map(value, watershed.tree_handle_of) })
  |> expect.to_equal(Ok(Some(marker)))
  watershed.resolve_tree_field(
    document,
    typed,
    schema.channel_field("absent-tree"),
    definition,
  )
  |> expect.to_equal(Ok(None))
  watershed.set_tree_field(typed, schema.channel_field("tree"), tree)
  watershed.get(root, "tree") |> expect.to_equal(Ok(marker))
  let changed = transport_js.new_cell([])
  let subscription =
    watershed.subscribe_tree(tree, fn(event) {
      transport_js.set_cell(changed, [event, ..transport_js.get_cell(changed)])
    })
  facade_fixture.set_javascript(
    tree,
    ["unknown"],
    tree_types.StringValue("invalid"),
  )
  |> expect.to_be_error()
  transport_js.get_cell(changed) |> expect.to_equal([])
  facade_fixture.set_javascript(
    tree,
    ["title"],
    tree_types.StringValue("native"),
  )
  |> expect.to_equal(Ok(Nil))
  facade_fixture.get_javascript(tree, ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("native"))))
  transport_js.get_cell(changed)
  |> expect.to_equal([
    tree_kernel.TreeChanged(True),
  ])
  watershed.unsubscribe(subscription)
  facade_fixture.clear_javascript(tree, ["title"]) |> expect.to_be_error()
  facade_fixture.resolve_javascript(
    document,
    watershed.handle_of(root),
    view.view,
  )
  |> expect.to_be_error()
  watershed.handle_of(root)
  |> json.to_string
  |> expect.to_equal("{\"type\":\"__fluid_handle__\",\"url\":\"/A/root\"}")
  let assert Ok(other) =
    watershed.resolve(document, handle.encode_handle("B/root"))
  watershed.handle_of(other)
  |> json.to_string
  |> expect.to_equal("{\"type\":\"__fluid_handle__\",\"url\":\"/B/root\"}")
  watershed.close(document)
}

@target(javascript)
pub fn routed_facade_refusals_preserve_native_diagnostics_and_state_test() {
  let assert Ok(#(input, _)) = runtime_fixture.routed_seed_input()
  let assert Ok(seed) = runtime_core.bootstrap_seed(input)
  let callbacks = transport_js.new_cell(None)
  let submissions = transport_js.new_cell(0)
  let document =
    watershed.connect_via_seed(
      tenant: "default",
      document: "tree",
      user_id: "reader",
      seed: seed,
      transport: runtime.Transport(connect: fn(handlers) {
        transport_js.set_cell(callbacks, Some(handlers))
        runtime.TransportHandle(
          push: fn(event, _) {
            case event {
              "submitOp" ->
                transport_js.set_cell(
                  submissions,
                  transport_js.get_cell(submissions) + 1,
                )
              _ -> Nil
            }
          },
          close: fn() { Nil },
          drop: fn() { Nil },
          hold: fn() { Nil },
          resume: fn() { Nil },
        )
      }),
      on_ready: fn(_) { Nil },
    )
  let assert Some(callbacks) = transport_js.get_cell(callbacks)
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["reader"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    )
      |> json.to_string,
  )
  let assert Ok(root) = watershed.resolve_root(document)
  let assert [view] = input.tree_views
  let assert Ok(marker) = watershed.get(root, "tree")
  let assert Ok(tree) =
    facade_fixture.resolve_javascript(document, marker, view.view)
  let events = transport_js.new_cell([])
  let subscription =
    watershed.subscribe_tree(tree, fn(event) {
      transport_js.set_cell(events, [event, ..transport_js.get_cell(events)])
    })
  let before = watershed.tree_read_root(tree) |> expect.to_be_ok()
  let operations_since_summary = watershed.operations_since_summary(document)

  assert_refusal_terms(facade_fixture.clear_javascript(tree, ["title"]), [
    "title",
    "required field",
  ])
  assert_refusal_terms(
    facade_fixture.set_javascript(tree, ["title"], tree_types.NumberValue(7.0)),
    ["title", "leaf.number"],
  )
  assert_refusal_terms(
    facade_fixture.set_javascript(tree, ["note"], tree_types.NullValue),
    ["note", "leaf.null"],
  )
  assert_refusal_terms(
    facade_fixture.set_javascript(
      tree,
      ["notAField"],
      tree_types.StringValue("invalid"),
    ),
    ["notAField", "unknown field"],
  )
  assert_refusal_terms(
    facade_fixture.set_javascript(
      tree,
      ["point"],
      tree_types.ObjectValue("org.watershed.shared-tree.m1.NotPoint", [
        #("x", tree_types.NumberValue(1.0)),
        #("y", tree_types.NumberValue(2.0)),
      ]),
    ),
    ["NotPoint", "unknown node schema"],
  )

  watershed.tree_read_root(tree) |> expect.to_equal(Ok(before))
  watershed.operations_since_summary(document)
  |> expect.to_equal(operations_since_summary)
  transport_js.get_cell(events) |> expect.to_equal([])
  transport_js.get_cell(submissions) |> expect.to_equal(0)

  facade_fixture.set_javascript(
    tree,
    ["title"],
    tree_types.StringValue("continued"),
  )
  |> expect.to_equal(Ok(Nil))
  transport_js.get_cell(events)
  |> expect.to_equal([tree_kernel.TreeChanged(True)])
  transport_js.get_cell(submissions) |> expect.to_equal(1)
  watershed.unsubscribe(subscription)
  watershed.close(document)
}

@target(javascript)
fn assert_refusal_terms(
  outcome: Result(Nil, String),
  terms: List(String),
) -> Nil {
  let assert Error(error) = outcome
  list.each(terms, fn(term) {
    string.contains(error, term) |> expect.to_be_true()
  })
}

@target(javascript)
pub fn inline_tree_echo_preserves_one_local_invalidation_test() {
  let assert Ok(#(input, _)) = runtime_fixture.routed_seed_input()
  let assert Ok(seed) = runtime_core.bootstrap_seed(input)
  let callbacks = transport_js.new_cell(None)
  let submissions = transport_js.new_cell([])
  let next_sequence_number = transport_js.new_cell(1)
  let owner =
    runtime.start_with_transport_and_seed(
      http_base_url: "https://seed.invalid",
      connect_message: connect_message(),
      seed: seed,
      transport: runtime.Transport(connect: fn(handlers) {
        transport_js.set_cell(callbacks, Some(handlers))
        runtime.TransportHandle(
          push: fn(event, payload) {
            case event {
              "submitOp" -> {
                let assert Ok(dynamic) =
                  json.parse(json.to_string(payload), decode.dynamic)
                let assert Ok(frame.SubmitOperation(sender, [[submitted]])) =
                  frame.decode_submit_operation(dynamic)
                let sequence_number =
                  transport_js.get_cell(next_sequence_number)
                transport_js.set_cell(next_sequence_number, sequence_number + 1)
                transport_js.set_cell(submissions, [
                  submitted,
                  ..transport_js.get_cell(submissions)
                ])
                handlers.on_event(
                  "op",
                  frame.encode_operation_event([
                    frame.Sequenced(
                      client_id: Some(sender),
                      sequence_number: sequence_number,
                      minimum_sequence_number: 0,
                      client_sequence_number: submitted.client_sequence_number,
                      reference_sequence_number: submitted.reference_sequence_number,
                      operation_type: submitted.operation_type,
                      contents: submitted.contents,
                      metadata: submitted.metadata,
                      timestamp: 0,
                      data: None,
                      compression: None,
                    ),
                  ])
                    |> json.to_string,
                )
              }
              _ -> Nil
            }
          },
          close: fn() { Nil },
          drop: fn() { Nil },
          hold: fn() { Nil },
          resume: fn() { Nil },
        )
      }),
      on_ready: fn(_) { Nil },
    )
  let assert Some(callbacks) = transport_js.get_cell(callbacks)
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["reader"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    )
      |> json.to_string,
  )
  let observed = transport_js.new_cell([])
  let _ =
    runtime.subscribe(owner, "A/_C", fn(event) {
      transport_js.set_cell(observed, [
        #(event, runtime.tree_read(owner, "A/_C", ["title"])),
        ..transport_js.get_cell(observed)
      ])
    })
  runtime.auto_summarize(
    owner,
    Some(summary_policy.with_threshold(summary_policy.policy(), 1)),
  )
  runtime.tree_edit(
    owner,
    "A/_C",
    tree_types.SetField(["unknown"], tree_types.StringValue("bad")),
  )
  |> expect.to_be_error()
  transport_js.get_cell(submissions) |> expect.to_equal([])
  transport_js.get_cell(observed) |> expect.to_equal([])
  runtime.diagnostics(owner).in_flight_count |> expect.to_equal(0)
  runtime.tree_edit(
    owner,
    "A/_C",
    tree_types.SetField(["title"], tree_types.StringValue("native")),
  )
  |> expect.to_equal(Ok(Nil))
  let assert [submitted] = transport_js.get_cell(submissions)
  let assert Ok(batch) =
    fluid_container.decode(submitted.contents, submitted.metadata)
  let assert [
    fluid_container.ContainerMessage(fluid_container.IdAllocation(range), 0, _),
    fluid_container.ContainerMessage(
      fluid_container.ChannelOperation(fluid_container.Route("A", "_C"), _),
      1,
      _,
    ),
  ] = batch.messages
  let assert Some(snapshot_compressor) = input.compressor
  range.session_id
  |> expect.to_not_equal(fluid_ids.local_session(snapshot_compressor))
  let assert [#(_, Ok(Some(tree_types.StringValue("native"))))] =
    transport_js.get_cell(observed)
  runtime.diagnostics(owner).in_flight_count |> expect.to_equal(0)
  runtime.diagnostics(owner).last_seen_sequence_number
  |> expect.to_equal(Some(1))
  runtime.is_synced(owner) |> expect.to_equal(True)
  runtime.diagnostics(owner).summary_pending |> expect.to_equal(False)
  callbacks.on_close()
  callbacks.on_join()
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader-2",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 1,
      initial_clients: ["reader-2"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    )
      |> json.to_string,
  )
  runtime.tree_edit(
    owner,
    "A/_C",
    tree_types.SetField(["title"], tree_types.StringValue("after reconnect")),
  )
  |> expect.to_equal(Ok(Nil))
  let assert [again, _] = transport_js.get_cell(submissions)
  let assert Ok(next_batch) =
    fluid_container.decode(again.contents, again.metadata)
  let assert [
    fluid_container.ContainerMessage(
      fluid_container.IdAllocation(next_range),
      0,
      _,
    ),
    _,
  ] = next_batch.messages
  next_range.session_id |> expect.to_equal(range.session_id)
  runtime.is_synced(owner) |> expect.to_equal(True)
  transport_js.get_cell(observed) |> list.length |> expect.to_equal(2)
  runtime.close(owner)
}

@target(javascript)
pub fn pending_tree_disconnect_retains_optimistic_content_and_rejects_edits_test() {
  let assert Ok(#(input, _)) = runtime_fixture.routed_seed_input()
  let assert Ok(seed) = runtime_core.bootstrap_seed(input)
  let callbacks = transport_js.new_cell(None)
  let submissions = transport_js.new_cell([])
  let owner =
    runtime.start_with_transport_and_seed(
      http_base_url: "https://seed.invalid",
      connect_message: connect_message(),
      seed: seed,
      transport: runtime.Transport(connect: fn(handlers) {
        transport_js.set_cell(callbacks, Some(handlers))
        runtime.TransportHandle(
          push: fn(event, payload) {
            case event {
              "submitOp" ->
                transport_js.set_cell(submissions, [
                  payload,
                  ..transport_js.get_cell(submissions)
                ])
              _ -> Nil
            }
          },
          close: fn() { Nil },
          drop: fn() { Nil },
          hold: fn() { Nil },
          resume: fn() { Nil },
        )
      }),
      on_ready: fn(_) { Nil },
    )
  let assert Some(callbacks) = transport_js.get_cell(callbacks)
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["reader"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    )
      |> json.to_string,
  )
  runtime.tree_edit(
    owner,
    "A/_C",
    tree_types.SetField(["title"], tree_types.StringValue("retained")),
  )
  |> expect.to_equal(Ok(Nil))
  runtime.diagnostics(owner).in_flight_count |> expect.to_equal(1)
  callbacks.on_close()
  runtime.connection_observation(owner).phase |> expect.to_equal("reconnecting")
  runtime.connection_observation(owner).pending_tree_count |> expect.to_equal(1)
  runtime.diagnostics(owner).in_flight_count |> expect.to_equal(1)
  runtime.is_synced(owner) |> expect.to_equal(False)
  runtime.tree_read(owner, "A/_C", ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("retained"))))
  runtime.tree_edit(
    owner,
    "A/_C",
    tree_types.SetField(["title"], tree_types.StringValue("lost")),
  )
  |> expect.to_be_error()
  runtime.tree_read(owner, "A/_C", ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("retained"))))
  transport_js.get_cell(submissions) |> list.length |> expect.to_equal(1)
  callbacks.on_join()
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader-2",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 1,
      initial_clients: ["reader-2"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    )
      |> json.to_string,
  )
  callbacks.on_event(
    "op",
    frame.encode_operation_event([
      membership_frame(1, "join", "{\"clientId\":\"reader-2\",\"detail\":{}}"),
    ])
      |> json.to_string,
  )
  runtime.connection_observation(owner).phase
  |> expect.to_equal("catching-up")
  transport_js.get_cell(submissions) |> list.length |> expect.to_equal(1)
  callbacks.on_event(
    "op",
    frame.encode_operation_event([
      membership_frame(2, "leave", "\"reader\""),
    ])
      |> json.to_string,
  )
  runtime.connection_observation(owner).phase |> expect.to_equal("ready")
  transport_js.get_cell(submissions) |> list.length |> expect.to_equal(2)
  let assert [resent, _] = transport_js.get_cell(submissions)
  let assert Ok(dynamic) = json.parse(json.to_string(resent), decode.dynamic)
  let assert Ok(frame.SubmitOperation("reader-2", [[submitted]])) =
    frame.decode_submit_operation(dynamic)
  submitted.reference_sequence_number |> expect.to_equal(2)
  callbacks.on_event(
    "op",
    frame.encode_operation_event([
      frame.Sequenced(
        client_id: Some("reader-2"),
        sequence_number: 3,
        minimum_sequence_number: 0,
        client_sequence_number: submitted.client_sequence_number,
        reference_sequence_number: submitted.reference_sequence_number,
        operation_type: submitted.operation_type,
        contents: submitted.contents,
        metadata: submitted.metadata,
        timestamp: 0,
        data: None,
        compression: None,
      ),
    ])
      |> json.to_string,
  )
  runtime.connection_observation(owner).synced |> expect.to_equal(True)
  runtime.close(owner)
}

@target(javascript)
pub fn bad_replayed_operation_retains_js_pending_tree_test() {
  let assert Ok(#(input, _)) = runtime_fixture.routed_seed_input()
  let assert Ok(seed) = runtime_core.bootstrap_seed(input)
  let callbacks = transport_js.new_cell(None)
  let owner =
    runtime.start_with_transport_and_seed(
      http_base_url: "https://seed.invalid",
      connect_message: connect_message(),
      seed: seed,
      transport: runtime.Transport(connect: fn(handlers) {
        transport_js.set_cell(callbacks, Some(handlers))
        runtime.TransportHandle(
          push: fn(_, _) { Nil },
          close: fn() { Nil },
          drop: fn() { Nil },
          hold: fn() { Nil },
          resume: fn() { Nil },
        )
      }),
      on_ready: fn(_) { Nil },
    )
  let assert Some(callbacks) = transport_js.get_cell(callbacks)
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["reader"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    )
      |> json.to_string,
  )
  runtime.tree_edit(
    owner,
    "A/_C",
    tree_types.SetField(["title"], tree_types.StringValue("retained")),
  )
  |> expect.to_equal(Ok(Nil))
  callbacks.on_close()
  callbacks.on_join()
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader-2",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 1,
      initial_clients: ["reader-2"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    )
      |> json.to_string,
  )
  let assert Ok(contents) =
    fluid_container.encode_batch(
      fluid_container.DecodedBatch(True, None, [
        fluid_container.ContainerMessage(
          fluid_container.ChannelOperation(
            fluid_container.Route("missing", "root"),
            wire_op.encode_map_operation(map_kernel.Clear),
          ),
          0,
          None,
        ),
      ]),
    )
  callbacks.on_event(
    "op",
    frame.encode_operation_event([
      frame.Sequenced(
        client_id: Some("other"),
        sequence_number: 1,
        minimum_sequence_number: 0,
        client_sequence_number: 1,
        reference_sequence_number: 0,
        operation_type: "op",
        contents: contents,
        metadata: None,
        timestamp: 0,
        data: None,
        compression: None,
      ),
    ])
      |> json.to_string,
  )
  let observation = runtime.connection_observation(owner)
  observation.phase |> expect.to_equal("suspended")
  observation.error |> expect.to_not_equal(None)
  observation.pending_tree_count |> expect.to_equal(1)
  observation.client_id |> expect.to_equal(Some("reader-2"))
  runtime.tree_read(owner, "A/_C", ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("retained"))))
  runtime.close(owner)
}

@target(javascript)
pub fn bad_last_group_child_does_not_notify_subscribers_test() {
  let assert Ok(#(input, _)) = runtime_fixture.routed_seed_input()
  let assert Ok(seed) = runtime_core.bootstrap_seed(input)
  let callbacks = transport_js.new_cell(None)
  let ready = transport_js.new_cell(None)
  let owner =
    runtime.start_with_transport_and_seed(
      http_base_url: "https://seed.invalid",
      connect_message: connect_message(),
      seed: seed,
      transport: runtime.Transport(connect: fn(handlers) {
        transport_js.set_cell(callbacks, Some(handlers))
        runtime.TransportHandle(
          push: fn(_, _) { Nil },
          close: fn() { Nil },
          drop: fn() { Nil },
          hold: fn() { Nil },
          resume: fn() { Nil },
        )
      }),
      on_ready: fn(result) { transport_js.set_cell(ready, Some(result)) },
    )
  let assert Some(callbacks) = transport_js.get_cell(callbacks)
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["reader"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    )
      |> json.to_string,
  )
  let events = transport_js.new_cell([])
  let _ =
    runtime.subscribe(owner, "A/root", fn(event) {
      transport_js.set_cell(events, [event, ..transport_js.get_cell(events)])
    })
  let assert Ok(encoded) =
    fluid_container.encode_batch(
      fluid_container.DecodedBatch(True, None, [
        fluid_container.ContainerMessage(
          fluid_container.ChannelOperation(
            fluid_container.Route("A", "root"),
            wire_op.encode_map_operation(map_kernel.Set(
              "name",
              json.string("wrong"),
            )),
          ),
          0,
          None,
        ),
        fluid_container.ContainerMessage(
          fluid_container.ChannelOperation(
            fluid_container.Route("missing", "root"),
            wire_op.encode_map_operation(map_kernel.Clear),
          ),
          1,
          None,
        ),
      ]),
    )
  callbacks.on_event(
    "op",
    frame.encode_operation_event([
      frame.Sequenced(
        client_id: Some("other"),
        sequence_number: 1,
        minimum_sequence_number: 0,
        client_sequence_number: 1,
        reference_sequence_number: 0,
        operation_type: "op",
        contents: encoded,
        metadata: None,
        timestamp: 0,
        data: None,
        compression: None,
      ),
    ])
      |> json.to_string,
  )
  transport_js.get_cell(events) |> expect.to_equal([])
  runtime.diagnostics(owner).phase
  |> string.starts_with("failed:")
  |> expect.to_equal(True)
  transport_js.get_cell(ready) |> expect.to_equal(Some(Ok(Nil)))
  runtime.close(owner)
}

@target(javascript)
pub fn reentrant_tree_subscriber_preserves_submission_order_test() {
  let assert Ok(#(input, _)) = runtime_fixture.routed_seed_input()
  let assert Ok(seed) = runtime_core.bootstrap_seed(input)
  let callbacks = transport_js.new_cell(None)
  let pushed = transport_js.new_cell([])
  let owner =
    runtime.start_with_transport_and_seed(
      http_base_url: "https://seed.invalid",
      connect_message: connect_message(),
      seed: seed,
      transport: runtime.Transport(connect: fn(handlers) {
        transport_js.set_cell(callbacks, Some(handlers))
        runtime.TransportHandle(
          push: fn(event, payload) {
            case event {
              "submitOp" -> {
                let assert Ok(dynamic) =
                  json.parse(json.to_string(payload), decode.dynamic)
                let assert Ok(frame.SubmitOperation(_, [[submitted]])) =
                  frame.decode_submit_operation(dynamic)
                transport_js.set_cell(pushed, [
                  submitted.client_sequence_number,
                  ..transport_js.get_cell(pushed)
                ])
              }
              _ -> Nil
            }
          },
          close: fn() { Nil },
          drop: fn() { Nil },
          hold: fn() { Nil },
          resume: fn() { Nil },
        )
      }),
      on_ready: fn(_) { Nil },
    )
  let assert Some(callbacks) = transport_js.get_cell(callbacks)
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["reader"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    )
      |> json.to_string,
  )
  let _ =
    runtime.subscribe(owner, "A/_C", fn(_) {
      case runtime.tree_read(owner, "A/_C", ["title"]) {
        Ok(Some(tree_types.StringValue("first"))) ->
          runtime.tree_edit(
            owner,
            "A/_C",
            tree_types.SetField(["title"], tree_types.StringValue("second")),
          )
          |> expect.to_equal(Ok(Nil))
        _ -> Nil
      }
    })
  runtime.tree_edit(
    owner,
    "A/_C",
    tree_types.SetField(["title"], tree_types.StringValue("first")),
  )
  |> expect.to_equal(Ok(Nil))
  transport_js.get_cell(pushed) |> list.reverse |> expect.to_equal([1, 2])
  runtime.close(owner)
}

@target(javascript)
pub fn queued_attachment_and_transaction_share_exact_submission_test() {
  let submissions = transport_js.new_cell([])
  let #(owner, callbacks, view, scheduled) =
    ready_scheduled_runtime(fn(event, payload) {
      case event {
        "submitOp" -> {
          let assert Ok(dynamic) =
            json.parse(json.to_string(payload), decode.dynamic)
          let assert Ok(frame.SubmitOperation(_, [[submitted]])) =
            frame.decode_submit_operation(dynamic)
          transport_js.set_cell(submissions, [
            submitted,
            ..transport_js.get_cell(submissions)
          ])
        }
        _ -> Nil
      }
    })
  let child = runtime.create_map(owner) |> expect.to_be_ok()
  runtime.set(owner, child, "local", json.string("kept"))
  runtime.set(owner, "A/root", "child", handle.encode_handle(child))
  runtime.begin_tree_transaction(owner, "A/_C", view, [])
  |> expect.to_equal(Ok(Nil))
  runtime.tree_edit(
    owner,
    "A/_C",
    tree_types.SetField(["title"], tree_types.StringValue("transaction")),
  )
  |> expect.to_equal(Ok(Nil))
  runtime.commit_tree_transaction(owner, "A/_C")
  |> expect.to_equal(Ok(Nil))

  transport_js.get_cell(submissions) |> expect.to_equal([])
  run_scheduled(scheduled)
  runtime.diagnostics(owner).phase |> expect.to_equal("ready")
  let sent = transport_js.get_cell(submissions)
  list.length(sent) |> expect.to_equal(1)
  let submitted = list.first(sent) |> expect.to_be_ok()
  submitted.client_sequence_number |> expect.to_equal(1)
  submitted.reference_sequence_number |> expect.to_equal(0)
  runtime.diagnostics(owner).next_client_sequence_number
  |> expect.to_equal(Some(2))
  runtime.diagnostics(owner).in_flight_count |> expect.to_equal(1)
  callbacks.on_event(
    "op",
    frame.encode_operation_event([
      sequenced_submission(submitted, "reader", 1),
    ])
      |> json.to_string,
  )
  runtime.diagnostics(owner).phase |> expect.to_equal("ready")
  runtime.diagnostics(owner).in_flight_count |> expect.to_equal(0)
  runtime.tree_read(owner, "A/_C", ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("transaction"))))
  runtime.get(owner, "A/root", "child")
  |> expect.to_equal(Ok(handle.encode_handle(child)))
  runtime.close(owner)
}

@target(javascript)
pub fn coalesced_attachment_and_transaction_resubmit_after_reconnect_test() {
  let submissions = transport_js.new_cell([])
  let #(owner, callbacks, view, scheduled) =
    ready_scheduled_runtime(fn(event, payload) {
      case event {
        "submitOp" -> {
          let assert Ok(dynamic) =
            json.parse(json.to_string(payload), decode.dynamic)
          let assert Ok(frame.SubmitOperation(_, [[submitted]])) =
            frame.decode_submit_operation(dynamic)
          transport_js.set_cell(submissions, [
            submitted,
            ..transport_js.get_cell(submissions)
          ])
        }
        _ -> Nil
      }
    })
  let peer_callbacks = transport_js.new_cell(None)
  let assert Ok(#(input, _)) = runtime_fixture.routed_seed_input()
  let peer =
    runtime.start_with_transport_and_seed(
      http_base_url: "https://seed.invalid",
      connect_message: connect_message(),
      seed: runtime_core.bootstrap_seed(input) |> expect.to_be_ok(),
      transport: runtime.Transport(connect: fn(handlers) {
        transport_js.set_cell(peer_callbacks, Some(handlers))
        runtime.TransportHandle(
          push: fn(_, _) { Nil },
          close: fn() { Nil },
          drop: fn() { Nil },
          hold: fn() { Nil },
          resume: fn() { Nil },
        )
      }),
      on_ready: fn(_) { Nil },
    )
  let assert Some(peer_transport) = transport_js.get_cell(peer_callbacks)
  peer_transport.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "peer",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["peer"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    )
      |> json.to_string,
  )
  let child = runtime.create_map(owner) |> expect.to_be_ok()
  runtime.set(owner, child, "local", json.string("kept"))
  runtime.set(owner, "A/root", "child", handle.encode_handle(child))
  runtime.begin_tree_transaction(owner, "A/_C", view, [])
  |> expect.to_equal(Ok(Nil))
  runtime.tree_edit(
    owner,
    "A/_C",
    tree_types.SetField(["title"], tree_types.StringValue("transaction")),
  )
  |> expect.to_equal(Ok(Nil))
  runtime.commit_tree_transaction(owner, "A/_C")
  |> expect.to_equal(Ok(Nil))
  run_scheduled(scheduled)
  let assert [original] = transport_js.get_cell(submissions)

  callbacks.on_close()
  callbacks.on_join()
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader-2",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 1,
      initial_clients: ["reader-2"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    )
      |> json.to_string,
  )
  callbacks.on_event(
    "op",
    frame.encode_operation_event([
      membership_frame(1, "join", "{\"clientId\":\"reader-2\",\"detail\":{}}"),
    ])
      |> json.to_string,
  )
  runtime.connection_observation(owner).phase
  |> expect.to_equal("catching-up")
  callbacks.on_event(
    "op",
    frame.encode_operation_event([
      membership_frame(2, "leave", "\"reader\""),
    ])
      |> json.to_string,
  )
  runtime.connection_observation(owner).phase |> expect.to_equal("ready")
  run_scheduled(scheduled)
  let assert [resent, _] = transport_js.get_cell(submissions)
  resent.client_sequence_number |> expect.to_equal(1)
  resent.reference_sequence_number |> expect.to_equal(2)
  resent.metadata |> expect.to_equal(original.metadata)
  submitted_tree_identity(resent)
  |> expect.to_equal(submitted_tree_identity(original))

  peer_transport.on_event(
    "op",
    frame.encode_operation_event([
      membership_frame(1, "join", "{\"clientId\":\"reader-2\",\"detail\":{}}"),
      membership_frame(2, "leave", "\"reader\""),
      sequenced_submission(resent, "reader-2", 3),
    ])
      |> json.to_string,
  )
  runtime.get(peer, "A/root", "child")
  |> expect.to_equal(Ok(handle.encode_handle(child)))
  runtime.get(peer, child, "local") |> expect.to_equal(Ok(json.string("kept")))
  runtime.tree_read(peer, "A/_C", ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("transaction"))))
  history_count(peer, "trunk") |> expect.to_equal(1)

  callbacks.on_event(
    "op",
    frame.encode_operation_event([
      sequenced_submission(resent, "reader-2", 3),
    ])
      |> json.to_string,
  )
  runtime.diagnostics(owner).in_flight_count |> expect.to_equal(0)
  history_count(owner, "pending") |> expect.to_equal(0)
  history_count(owner, "trunk") |> expect.to_equal(1)
  runtime.get(owner, child, "local") |> expect.to_equal(Ok(json.string("kept")))
  runtime.tree_read(owner, "A/_C", ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("transaction"))))
  transport_js.get_cell(submissions) |> list.length |> expect.to_equal(2)
  runtime.close(owner)
  runtime.close(peer)
}

@target(javascript)
pub fn coalesced_attachment_and_schema_resubmit_after_reconnect_test() {
  let submissions = transport_js.new_cell([])
  let peer_submissions = transport_js.new_cell([])
  let #(stored, base_view) = evolution_schema("v1")
  let #(_, new_node_view) = evolution_schema("new-node")
  let input =
    runtime_fixture.routed_tree_seed_input(
      stored,
      base_view,
      schema_evolution_root(),
    )
    |> expect.to_be_ok
  let #(owner, callbacks, _, scheduled) =
    ready_scheduled_runtime_from(input, fn(event, payload) {
      case event {
        "submitOp" -> {
          let assert Ok(dynamic) =
            json.parse(json.to_string(payload), decode.dynamic)
          let assert Ok(frame.SubmitOperation(_, [[submitted]])) =
            frame.decode_submit_operation(dynamic)
          transport_js.set_cell(submissions, [
            submitted,
            ..transport_js.get_cell(submissions)
          ])
        }
        _ -> Nil
      }
    })
  let peer_callbacks = transport_js.new_cell(None)
  let peer =
    runtime.start_with_transport_and_seed(
      http_base_url: "https://seed.invalid",
      connect_message: connect_message(),
      seed: runtime_core.bootstrap_seed(input) |> expect.to_be_ok(),
      transport: runtime.Transport(connect: fn(handlers) {
        transport_js.set_cell(peer_callbacks, Some(handlers))
        runtime.TransportHandle(
          push: fn(event, payload) {
            case event {
              "submitOp" -> {
                let assert Ok(dynamic) =
                  json.parse(json.to_string(payload), decode.dynamic)
                let assert Ok(frame.SubmitOperation(_, [[submitted]])) =
                  frame.decode_submit_operation(dynamic)
                transport_js.set_cell(peer_submissions, [
                  submitted,
                  ..transport_js.get_cell(peer_submissions)
                ])
              }
              _ -> Nil
            }
          },
          close: fn() { Nil },
          drop: fn() { Nil },
          hold: fn() { Nil },
          resume: fn() { Nil },
        )
      }),
      on_ready: fn(_) { Nil },
    )
  let assert Some(peer_transport) = transport_js.get_cell(peer_callbacks)
  peer_transport.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "peer",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["peer"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    )
      |> json.to_string,
  )
  let view = new_node_view
  let child = runtime.create_map(owner) |> expect.to_be_ok()
  runtime.set(owner, child, "local", json.string("kept"))
  runtime.set(owner, "A/root", "child", handle.encode_handle(child))
  runtime.tree_upgrade_schema(owner, "A/_C", view)
  |> expect.to_equal(Ok(Nil))
  runtime.tree_edit(
    owner,
    "A/_C",
    tree_types.SetField(
      ["extra"],
      tree_types.ObjectValue("org.watershed.shared-tree.m4.Extra", [
        #("value", tree_types.StringValue("pending")),
      ]),
    ),
  )
  |> expect.to_equal(Ok(Nil))
  run_scheduled(scheduled)
  let assert [original] = transport_js.get_cell(submissions)
  runtime.tree_edit(
    peer,
    "A/_C",
    tree_types.SetField(["title"], tree_types.StringValue("wins")),
  )
  |> expect.to_equal(Ok(Nil))
  let assert [winner] = transport_js.get_cell(peer_submissions)

  callbacks.on_close()
  callbacks.on_join()
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader-2",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 2,
      initial_clients: ["reader-2", "peer"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    )
      |> json.to_string,
  )
  callbacks.on_event(
    "op",
    frame.encode_operation_event([
      membership_frame(1, "join", "{\"clientId\":\"reader-2\",\"detail\":{}}"),
      sequenced_submission(winner, "peer", 2),
    ])
      |> json.to_string,
  )
  runtime.connection_observation(owner).phase
  |> expect.to_equal("catching-up")
  callbacks.on_event(
    "op",
    frame.encode_operation_event([
      membership_frame(3, "leave", "\"reader\""),
    ])
      |> json.to_string,
  )
  runtime.connection_observation(owner).phase |> expect.to_equal("ready")
  run_scheduled(scheduled)
  let assert [resent, _] = transport_js.get_cell(submissions)
  resent.client_sequence_number |> expect.to_equal(1)
  resent.reference_sequence_number |> expect.to_equal(3)
  submitted_tree_identity(resent)
  |> expect.to_equal(submitted_tree_identity(original))

  peer_transport.on_event(
    "op",
    frame.encode_operation_event([
      membership_frame(1, "join", "{\"clientId\":\"reader-2\",\"detail\":{}}"),
      sequenced_submission(winner, "peer", 2),
      membership_frame(3, "leave", "\"reader\""),
      sequenced_submission(resent, "reader-2", 4),
    ])
      |> json.to_string,
  )
  runtime.get(peer, "A/root", "child")
  |> expect.to_equal(Ok(handle.encode_handle(child)))
  runtime.get(peer, child, "local") |> expect.to_equal(Ok(json.string("kept")))
  runtime.tree_read(peer, "A/_C", ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("wins"))))
  history_count(peer, "trunk") |> expect.to_equal(3)
  runtime.get(owner, child, "local") |> expect.to_equal(Ok(json.string("kept")))
  runtime.tree_read(owner, "A/_C", ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("wins"))))
  runtime.close(owner)
  runtime.close(peer)
}

@target(javascript)
pub fn queued_attachment_splits_before_peer_reference_change_test() {
  let submissions = transport_js.new_cell([])
  let #(owner, callbacks, _, scheduled) =
    ready_scheduled_runtime(fn(event, payload) {
      case event {
        "submitOp" -> {
          let assert Ok(dynamic) =
            json.parse(json.to_string(payload), decode.dynamic)
          let assert Ok(frame.SubmitOperation(_, [[submitted]])) =
            frame.decode_submit_operation(dynamic)
          transport_js.set_cell(submissions, [
            submitted,
            ..transport_js.get_cell(submissions)
          ])
        }
        _ -> Nil
      }
    })
  let child = runtime.create_map(owner) |> expect.to_be_ok()
  runtime.set(owner, "A/root", "child", handle.encode_handle(child))
  callbacks.on_event("op", peer_map_set(1))
  runtime.tree_edit(
    owner,
    "A/_C",
    tree_types.SetField(["title"], tree_types.StringValue("after peer")),
  )
  |> expect.to_equal(Ok(Nil))
  run_scheduled(scheduled)

  let submissions = transport_js.get_cell(submissions) |> list.reverse
  let assert [attach, edit] = submissions
  [attach.client_sequence_number, edit.client_sequence_number]
  |> expect.to_equal([1, 2])
  [attach.reference_sequence_number, edit.reference_sequence_number]
  |> expect.to_equal([0, 1])
  runtime.diagnostics(owner).phase |> expect.to_equal("ready")
  runtime.diagnostics(owner).next_client_sequence_number
  |> expect.to_equal(Some(3))
  runtime.diagnostics(owner).in_flight_count |> expect.to_equal(2)
  callbacks.on_event(
    "op",
    frame.encode_operation_event([
      sequenced_submission(attach, "reader", 2),
      sequenced_submission(edit, "reader", 3),
    ])
      |> json.to_string,
  )
  runtime.diagnostics(owner).in_flight_count |> expect.to_equal(0)
  runtime.tree_read(owner, "A/_C", ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("after peer"))))
  runtime.close(owner)
}

@target(javascript)
pub fn tree_transaction_commit_reentrancy_preserves_state_and_order_test() {
  let assert Ok(#(input, _)) = runtime_fixture.routed_seed_input()
  let assert Ok(seed) = runtime_core.bootstrap_seed(input)
  let assert [view] = input.tree_views
  let callbacks = transport_js.new_cell(None)
  let pushed = transport_js.new_cell([])
  let observed = transport_js.new_cell([])
  let owner =
    runtime.start_with_transport_and_seed(
      http_base_url: "https://seed.invalid",
      connect_message: connect_message(),
      seed: seed,
      transport: runtime.Transport(connect: fn(handlers) {
        transport_js.set_cell(callbacks, Some(handlers))
        runtime.TransportHandle(
          push: fn(event, payload) {
            case event {
              "submitOp" -> {
                let assert Ok(dynamic) =
                  json.parse(json.to_string(payload), decode.dynamic)
                let assert Ok(frame.SubmitOperation(_, [[submitted]])) =
                  frame.decode_submit_operation(dynamic)
                transport_js.set_cell(pushed, [
                  submitted.client_sequence_number,
                  ..transport_js.get_cell(pushed)
                ])
              }
              _ -> Nil
            }
          },
          close: fn() { Nil },
          drop: fn() { Nil },
          hold: fn() { Nil },
          resume: fn() { Nil },
        )
      }),
      on_ready: fn(_) { Nil },
    )
  let assert Some(callbacks) = transport_js.get_cell(callbacks)
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["reader"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    )
      |> json.to_string,
  )
  let _ =
    runtime.subscribe(owner, "A/_C", fn(_) {
      let current = runtime.tree_read(owner, "A/_C", ["title"])
      transport_js.set_cell(observed, [
        current,
        ..transport_js.get_cell(observed)
      ])
      case current {
        Ok(Some(tree_types.StringValue("outer"))) ->
          runtime.tree_edit(
            owner,
            "A/_C",
            tree_types.SetField(["title"], tree_types.StringValue("reentrant")),
          )
          |> expect.to_equal(Ok(Nil))
        _ -> Nil
      }
    })

  runtime.begin_tree_transaction(owner, "A/_C", view.view, [])
  |> expect.to_equal(Ok(Nil))
  runtime.tree_edit_view(
    owner,
    "A/_C",
    view.view,
    tree_types.SetField(["title"], tree_types.StringValue("intermediate")),
  )
  |> expect.to_equal(Ok(Nil))
  transport_js.get_cell(observed) |> expect.to_equal([])
  runtime.tree_edit_view(
    owner,
    "A/_C",
    view.view,
    tree_types.SetField(["title"], tree_types.StringValue("outer")),
  )
  |> expect.to_equal(Ok(Nil))
  runtime.tree_read(owner, "A/_C", ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("outer"))))
  runtime.begin_tree_transaction(owner, "A/root", view.view, [])
  |> expect.to_be_error()
  runtime.commit_tree_transaction(owner, "A/_C") |> expect.to_equal(Ok(Nil))

  transport_js.get_cell(pushed) |> list.reverse |> expect.to_equal([1, 2])
  transport_js.get_cell(observed)
  |> list.reverse
  |> expect.to_equal([
    Ok(Some(tree_types.StringValue("outer"))),
    Ok(Some(tree_types.StringValue("reentrant"))),
  ])
  runtime.tree_read(owner, "A/_C", ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("reentrant"))))
  runtime.close(owner)
}

@target(javascript)
pub fn tree_commit_runtime_factory_is_shared_across_subscribers_test() {
  let assert Ok(#(input, _)) = runtime_fixture.routed_seed_input()
  let assert Ok(seed) = runtime_core.bootstrap_seed(input)
  let callbacks = transport_js.new_cell(None)
  let owner =
    runtime.start_with_transport_and_seed(
      http_base_url: "https://seed.invalid",
      connect_message: connect_message(),
      seed: seed,
      transport: runtime.Transport(connect: fn(handlers) {
        transport_js.set_cell(callbacks, Some(handlers))
        runtime.TransportHandle(
          push: fn(_, _) { Nil },
          close: fn() { Nil },
          drop: fn() { Nil },
          hold: fn() { Nil },
          resume: fn() { Nil },
        )
      }),
      on_ready: fn(_) { Nil },
    )
  let assert Some(callbacks) = transport_js.get_cell(callbacks)
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["reader"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    )
      |> json.to_string,
  )
  let attempts = transport_js.new_cell([])
  let _ =
    runtime.subscribe_tree_commits(owner, "A/_C", fn(event) {
      let assert runtime.TreeCommitEvent(_, True, Some(get_revertible), _) =
        event
      transport_js.set_cell(attempts, [
        get_revertible(),
        ..transport_js.get_cell(attempts)
      ])
    })
  let _ =
    runtime.subscribe_tree_commits(owner, "A/_C", fn(event) {
      let assert runtime.TreeCommitEvent(_, True, Some(get_revertible), _) =
        event
      transport_js.set_cell(attempts, [
        get_revertible(),
        ..transport_js.get_cell(attempts)
      ])
    })
  runtime.tree_edit(
    owner,
    "A/_C",
    tree_types.SetField(["title"], tree_types.StringValue("final")),
  )
  |> expect.to_equal(Ok(Nil))
  let assert [Error(_), Ok(handle)] = transport_js.get_cell(attempts)
  runtime.tree_revertible_status(handle)
  |> expect.to_equal(runtime.RevertibleValid)
  runtime.close(owner)
  runtime.tree_revertible_status(handle)
  |> expect.to_equal(runtime.RevertibleDisposed)
}

@target(javascript)
pub fn summary_reload_emits_no_historical_commit_factory_and_new_edit_does_test() {
  let callbacks = transport_js.new_cell(None)
  let events = transport_js.new_cell([])
  let factory_results = transport_js.new_cell([])
  let owner =
    runtime.start_with_transport_and_seed(
      http_base_url: "https://seed.invalid",
      connect_message: connect_message(),
      seed: undo_acceptance.summary_reload_seed_after_undo(),
      transport: runtime.Transport(connect: fn(handlers) {
        transport_js.set_cell(callbacks, Some(handlers))
        runtime.TransportHandle(
          push: fn(_, _) { Nil },
          close: fn() { Nil },
          drop: fn() { Nil },
          hold: fn() { Nil },
          resume: fn() { Nil },
        )
      }),
      on_ready: fn(_) { Nil },
    )
  let _ =
    runtime.subscribe_tree_commits(owner, "A/_C", fn(event) {
      let runtime.TreeCommitEvent(kind, local, factory, settlement) = event
      transport_js.set_cell(events, [
        #(
          kind,
          local,
          case factory {
            Some(_) -> True
            None -> False
          },
          case settlement {
            Some(_) -> True
            None -> False
          },
        ),
        ..transport_js.get_cell(events)
      ])
      let factory_result = case factory {
        Some(get_revertible) -> Some(get_revertible())
        None -> None
      }
      transport_js.set_cell(factory_results, [
        factory_result,
        ..transport_js.get_cell(factory_results)
      ])
    })
  let assert Some(callbacks) = transport_js.get_cell(callbacks)
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 2,
      initial_clients: ["reader"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    )
      |> json.to_string,
  )
  transport_js.get_cell(events) |> expect.to_equal([])
  transport_js.get_cell(factory_results) |> expect.to_equal([])
  runtime.tree_edit(
    owner,
    "A/_C",
    tree_types.SetField(["note"], tree_types.StringValue("after reload")),
  )
  |> expect.to_equal(Ok(Nil))
  transport_js.get_cell(events)
  |> expect.to_equal([#(tree_types.DefaultCommit, True, True, True)])
  let assert [Some(Ok(handle))] = transport_js.get_cell(factory_results)
  runtime.tree_revertible_status(handle)
  |> expect.to_equal(runtime.RevertibleValid)
  runtime.close(owner)
}

@target(javascript)
pub fn invalid_inline_own_echo_rejects_edit_without_fanout_test() {
  let assert Ok(#(input, _)) = runtime_fixture.routed_seed_input()
  let assert Ok(seed) = runtime_core.bootstrap_seed(input)
  let callbacks = transport_js.new_cell(None)
  let owner =
    runtime.start_with_transport_and_seed(
      http_base_url: "https://seed.invalid",
      connect_message: connect_message(),
      seed: seed,
      transport: runtime.Transport(connect: fn(handlers) {
        transport_js.set_cell(callbacks, Some(handlers))
        runtime.TransportHandle(
          push: fn(event, payload) {
            case event {
              "submitOp" -> {
                let assert Ok(dynamic) =
                  json.parse(json.to_string(payload), decode.dynamic)
                let assert Ok(frame.SubmitOperation(sender, [[submitted]])) =
                  frame.decode_submit_operation(dynamic)
                let assert Ok(batch) =
                  fluid_container.decode(submitted.contents, submitted.metadata)
                let assert [first, last] = batch.messages
                let assert Ok(invalid) =
                  fluid_container.encode_batch(
                    fluid_container.DecodedBatch(batch.grouped, batch.metadata, [
                      first,
                      fluid_container.ContainerMessage(
                        ..last,
                        kind: fluid_container.ChannelOperation(
                          fluid_container.Route("missing", "root"),
                          json.null(),
                        ),
                      ),
                    ]),
                  )
                handlers.on_event(
                  "op",
                  frame.encode_operation_event([
                    frame.Sequenced(
                      client_id: Some(sender),
                      sequence_number: 1,
                      minimum_sequence_number: 0,
                      client_sequence_number: submitted.client_sequence_number,
                      reference_sequence_number: submitted.reference_sequence_number,
                      operation_type: submitted.operation_type,
                      contents: invalid,
                      metadata: submitted.metadata,
                      timestamp: 0,
                      data: None,
                      compression: None,
                    ),
                  ])
                    |> json.to_string,
                )
              }
              _ -> Nil
            }
          },
          close: fn() { Nil },
          drop: fn() { Nil },
          hold: fn() { Nil },
          resume: fn() { Nil },
        )
      }),
      on_ready: fn(_) { Nil },
    )
  let assert Some(callbacks) = transport_js.get_cell(callbacks)
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["reader"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    )
      |> json.to_string,
  )
  let events = transport_js.new_cell([])
  let _ =
    runtime.subscribe(owner, "A/_C", fn(event) {
      transport_js.set_cell(events, [event, ..transport_js.get_cell(events)])
    })
  runtime.tree_edit(
    owner,
    "A/_C",
    tree_types.SetField(["title"], tree_types.StringValue("reject")),
  )
  |> expect.to_be_error()
  transport_js.get_cell(events) |> expect.to_equal([])
  runtime.connection_observation(owner).phase |> expect.to_equal("suspended")
  runtime.connection_observation(owner).pending_tree_count
  |> expect.to_equal(1)
  runtime.tree_read(owner, "A/_C", ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("reject"))))
  runtime.close(owner)
}

@target(javascript)
pub fn check_tree_summary_guard() -> Promise(Nil) {
  let assert Ok(#(input, _)) = runtime_fixture.routed_seed_input()
  let assert Ok(seed) = runtime_core.bootstrap_seed(input)
  let callbacks = transport_js.new_cell(None)
  let owner =
    runtime.start_with_transport_and_seed(
      http_base_url: "https://seed.invalid",
      connect_message: connect_message(),
      seed: seed,
      transport: runtime.Transport(connect: fn(handlers) {
        transport_js.set_cell(callbacks, Some(handlers))
        runtime.TransportHandle(
          push: fn(_, _) { Nil },
          close: fn() { Nil },
          drop: fn() { Nil },
          hold: fn() { Nil },
          resume: fn() { Nil },
        )
      }),
      on_ready: fn(_) { Nil },
    )
  let assert Some(callbacks) = transport_js.get_cell(callbacks)
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["reader"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    )
      |> json.to_string,
  )
  let before = runtime.diagnostics(owner).next_client_sequence_number
  runtime.summarize(owner)
  |> promise.map(fn(outcome) {
    outcome
    |> expect.to_equal(Error("tree summary publication is not supported"))
    runtime.diagnostics(owner).next_client_sequence_number
    |> expect.to_equal(before)
    runtime.close(owner)
  })
}

@target(javascript)
pub fn check_datastore_alias_claims() -> Promise(Nil) {
  let submissions = transport_js.new_cell([])
  let #(owner, callbacks, _, scheduled) =
    ready_scheduled_runtime(fn(event, payload) {
      case event {
        "submitOp" ->
          transport_js.set_cell(submissions, [
            payload,
            ..transport_js.get_cell(submissions)
          ])
        _ -> Nil
      }
    })
  let store = runtime.create_data_store(owner) |> expect.to_be_ok()
  let settled = transport_js.new_cell(False)
  let first =
    runtime.try_set_alias(owner, store, "public")
    |> promise.map(fn(outcome) {
      transport_js.set_cell(settled, True)
      runtime.resolve_handle_address(owner, handle.encode_handle("public/root"))
      |> expect.to_equal(Ok(store <> "/root"))
      outcome
    })
  let duplicate = runtime.try_set_alias(owner, store, "public")
  run_scheduled(scheduled)
  let assert [payload] = transport_js.get_cell(submissions)
  let dynamic =
    json.parse(json.to_string(payload), decode.dynamic) |> expect.to_be_ok()
  let assert Ok(frame.SubmitOperation(_, [[submitted]])) =
    frame.decode_submit_operation(dynamic)
  promise.resolve(Nil)
  |> promise.await(fn(_) {
    transport_js.get_cell(settled) |> expect.to_be_false()
    callbacks.on_event(
      "op",
      frame.encode_operation_event([
        sequenced_submission(submitted, "reader", 1),
      ])
        |> json.to_string,
    )
    promise.await_list([first, duplicate])
  })
  |> promise.await(fn(outcomes) {
    outcomes
    |> expect.to_equal([
      Ok(container.AliasSuccess),
      Ok(container.AliasSuccess),
    ])
    runtime.try_set_alias(owner, store, "different")
  })
  |> promise.await(fn(outcome) {
    outcome |> expect.to_equal(Ok(container.AlreadyAliased))
    let another = runtime.create_data_store(owner) |> expect.to_be_ok()
    let pending = runtime.try_set_alias(owner, another, "closing")
    runtime.close(owner)
    pending
  })
  |> promise.map(fn(outcome) {
    outcome |> expect.to_be_error()
    Nil
  })
}

@target(javascript)
pub fn check_datastore_alias_reconnect_timeout() -> Promise(Nil) {
  let #(owner, callbacks, _, _) = ready_scheduled_runtime(fn(_, _) { Nil })
  let timers = transport_js.new_cell([])
  runtime.set_scheduler(
    owner,
    transport_js.Scheduler(
      now_milliseconds: fn() { 0 },
      schedule: fn(action, delay) {
        transport_js.set_cell(timers, [
          #(delay, action),
          ..transport_js.get_cell(timers)
        ])
        fn() { Nil }
      },
    ),
  )
  let store = runtime.create_data_store(owner) |> expect.to_be_ok()
  let pending = runtime.try_set_alias(owner, store, "public")
  runtime.force_reconnect(owner)
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "fresh",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 1,
      initial_clients: ["reader", "fresh"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    )
      |> json.to_string,
  )
  let #(_, deadline) =
    transport_js.get_cell(timers)
    |> list.find(fn(timer) { timer.0 == 10_000 })
    |> expect.to_be_ok()
  deadline()
  runtime.connection_observation(owner).phase |> expect.to_equal("suspended")
  promise.race_list([pending, promise.resolve(Ok(container.AliasSuccess))])
  |> promise.map(fn(outcome) {
    runtime.close(owner)
    outcome |> expect.to_be_error()
    Nil
  })
}

@target(javascript)
pub fn detached_graph_lifecycle_facade_test() {
  let assert Ok(#(input, _)) = runtime_fixture.routed_seed_input()
  let seed = runtime_core.bootstrap_seed(input) |> expect.to_be_ok()
  let callbacks = transport_js.new_cell(None)
  let submissions = transport_js.new_cell([])
  let document =
    watershed.connect_via_seed(
      tenant: "default",
      document: "tree",
      user_id: "writer",
      seed: seed,
      transport: runtime.Transport(connect: fn(handlers) {
        transport_js.set_cell(callbacks, Some(handlers))
        runtime.TransportHandle(
          push: fn(event, payload) {
            case event {
              "submitOp" ->
                transport_js.set_cell(submissions, [
                  payload,
                  ..transport_js.get_cell(submissions)
                ])
              _ -> Nil
            }
          },
          close: fn() { Nil },
          drop: fn() { Nil },
          hold: fn() { Nil },
          resume: fn() { Nil },
        )
      }),
      on_ready: fn(_) { Nil },
    )
  watershed.create_data_store(document) |> expect.to_be_error()
  let assert Some(callbacks) = transport_js.get_cell(callbacks)
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "writer",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["writer"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    )
      |> json.to_string,
  )
  let scheduled = transport_js.new_cell([])
  runtime.set_scheduler(
    watershed.runtime_of(document),
    transport_js.Scheduler(
      now_milliseconds: fn() { 0 },
      schedule: fn(action, _) {
        transport_js.set_cell(scheduled, [
          action,
          ..transport_js.get_cell(scheduled)
        ])
        fn() { Nil }
      },
    ),
  )
  let root = watershed.resolve_root(document) |> expect.to_be_ok()
  let malformed_handle =
    json.object([
      #("type", json.string("__fluid_handle__")),
      #("url", json.int(123)),
    ])
  watershed.set_checked(root, "malformed", malformed_handle)
  |> expect.to_be_error()
  watershed.get(root, "malformed") |> expect.to_be_error()
  transport_js.get_cell(submissions) |> expect.to_equal([])
  let store = watershed.create_data_store(document) |> expect.to_be_ok()
  let store_root = watershed.data_store_root(store) |> expect.to_be_ok()
  let foreign =
    watershed.connect_via_seed(
      tenant: "default",
      document: "foreign",
      user_id: "foreign",
      seed: seed,
      transport: runtime.Transport(connect: fn(_) {
        runtime.TransportHandle(
          push: fn(_, _) { Nil },
          close: fn() { Nil },
          drop: fn() { Nil },
          hold: fn() { Nil },
          resume: fn() { Nil },
        )
      }),
      on_ready: fn(_) { Nil },
    )
  watershed.create_map_in(foreign, store) |> expect.to_be_error()
  watershed.close(foreign)
  let _ = watershed.create_map_in(document, store) |> expect.to_be_ok()
  let stored = identifier_fixture.full_stored()
  let view = identifier_fixture.full_view()
  let initial =
    identifier_fixture.full_root(
      tree_types.ObjectValue(identifier_fixture.point_type, [
        #("label", tree_types.StringValue("local")),
      ]),
      [],
      [],
      [],
    )
  let tree =
    facade_fixture.create_in_from_parts_javascript(
      document,
      store,
      stored,
      Some(initial),
      view,
    )
    |> expect.to_be_ok()
  transport_js.get_cell(submissions) |> expect.to_equal([])
  let branch = watershed.tree_fork(tree) |> expect.to_be_ok()
  let branch_revertible = transport_js.new_cell(None)
  let disposed_branch_revertibles = transport_js.new_cell([])
  let _branch_token =
    watershed.subscribe_tree_commits(branch, fn(event) {
      let acquired =
        watershed.tree_get_revertible(event, fn(disposed) {
          transport_js.set_cell(disposed_branch_revertibles, [
            disposed,
            ..transport_js.get_cell(disposed_branch_revertibles)
          ])
        })
        |> expect.to_be_ok()
      transport_js.set_cell(branch_revertible, Some(acquired))
    })
  facade_fixture.set_javascript(
    branch,
    ["child", "label"],
    tree_types.StringValue("branch-only"),
  )
  |> expect.to_equal(Ok(Nil))
  let branch_marker = watershed.tree_handle_of(branch)
  branch_marker |> expect.to_equal(watershed.tree_handle_of(tree))
  let resolved_main =
    facade_fixture.resolve_javascript(document, branch_marker, view)
    |> expect.to_be_ok()
  facade_fixture.get_javascript(resolved_main, ["child", "label"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("local"))))
  transport_js.get_cell(submissions) |> expect.to_equal([])
  watershed.tree_dispose_branch(branch) |> expect.to_equal(Ok(Nil))
  let assert Some(branch_revertible) = transport_js.get_cell(branch_revertible)
  transport_js.get_cell(disposed_branch_revertibles)
  |> expect.to_equal([branch_revertible])
  let generated =
    facade_fixture.get_javascript(tree, ["child", "id"]) |> expect.to_be_ok()
  let commit_handles = transport_js.new_cell([])
  let late_factory = transport_js.new_cell(None)
  let token =
    watershed.subscribe_tree_commits(tree, fn(event) {
      let assert Some(factory) = event.get_revertible
      transport_js.set_cell(late_factory, Some(factory))
      transport_js.set_cell(commit_handles, [
        #(factory(), factory()),
        ..transport_js.get_cell(commit_handles)
      ])
    })
  facade_fixture.set_javascript(
    tree,
    ["child", "label"],
    tree_types.StringValue("changed"),
  )
  |> expect.to_equal(Ok(Nil))
  facade_fixture.get_javascript(tree, ["child", "id"])
  |> expect.to_equal(Ok(generated))
  transport_js.get_cell(submissions) |> expect.to_equal([])
  let assert [#(Ok(revertible), Error(_))] =
    transport_js.get_cell(commit_handles)
  let assert Some(late_factory) = transport_js.get_cell(late_factory)
  late_factory() |> expect.to_be_error()
  watershed.unsubscribe(token)
  watershed.tree_revert(revertible, True) |> expect.to_equal(Ok(Nil))
  facade_fixture.get_javascript(tree, ["child", "label"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("local"))))

  let before = runtime.diagnostics(watershed.runtime_of(document))
  let #(mismatched_stored, _) = evolution_schema("v1")
  facade_fixture.create_in_from_parts_javascript(
    document,
    store,
    mismatched_stored,
    Some(initial),
    view,
  )
  |> expect.to_be_error()
  runtime.diagnostics(watershed.runtime_of(document))
  |> expect.to_equal(before)
  transport_js.get_cell(submissions) |> expect.to_equal([])

  let #(_, incompatible) = evolution_schema("v1")
  facade_fixture.create_in_from_parts_javascript(
    document,
    store,
    stored,
    Some(initial),
    incompatible,
  )
  |> expect.to_be_error()
  runtime.diagnostics(watershed.runtime_of(document))
  |> expect.to_equal(before)
  transport_js.get_cell(submissions) |> expect.to_equal([])

  let target = watershed.create_map_in(document, store) |> expect.to_be_ok()
  let handle_schema =
    "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.handle\":{\"kind\":{\"leaf\":3}}},\"root\":{\"kind\":\"Optional\",\"types\":[\"com.fluidframework.leaf.handle\"]}}"
  let handle_stored =
    tree_schema.stored_from_string(handle_schema) |> expect.to_be_ok()
  let handle_view =
    tree_schema.view_from_string(handle_schema) |> expect.to_be_ok()
  let handle_tree =
    facade_fixture.create_in_from_parts_javascript(
      document,
      store,
      handle_stored,
      None,
      handle_view,
    )
    |> expect.to_be_ok()
  let target_marker = watershed.handle_of(target)
  let target_reference =
    handle.reference_from_json(target_marker, "/") |> expect.to_be_ok()
  let lifetime_revertible = transport_js.new_cell(None)
  let disposed_lifetime_revertibles = transport_js.new_cell([])
  let late_lifetime_factory = transport_js.new_cell(None)
  let lifetime_token =
    watershed.subscribe_tree_commits(handle_tree, fn(event) {
      case transport_js.get_cell(lifetime_revertible), event.get_revertible {
        None, Some(factory) -> {
          transport_js.set_cell(late_lifetime_factory, Some(factory))
          let acquired =
            watershed.tree_get_revertible(event, fn(disposed) {
              transport_js.set_cell(disposed_lifetime_revertibles, [
                #(disposed, watershed.tree_revertible_status(disposed)),
                ..transport_js.get_cell(disposed_lifetime_revertibles)
              ])
              watershed.set(target, "undo-callback", json.string("after-undo"))
            })
            |> expect.to_be_ok()
          factory() |> expect.to_be_error()
          transport_js.set_cell(lifetime_revertible, Some(acquired))
        }
        _, _ -> Nil
      }
    })
  facade_fixture.set_javascript(
    handle_tree,
    [],
    tree_types.HandleValue(target_reference),
  )
  |> expect.to_equal(Ok(Nil))
  let assert Some(lifetime_revertible) =
    transport_js.get_cell(lifetime_revertible)
  let assert Some(late_lifetime_factory) =
    transport_js.get_cell(late_lifetime_factory)
  late_lifetime_factory() |> expect.to_be_error()
  watershed.tree_revertible_status(lifetime_revertible)
  |> expect.to_equal(watershed.RevertibleValid)

  watershed.set(root, "secondary", watershed.handle_of(store_root))
  watershed.set(store_root, "tree", watershed.tree_handle_of(tree))
  watershed.set(
    store_root,
    "handle-tree",
    watershed.tree_handle_of(handle_tree),
  )
  transport_js.get_cell(submissions) |> expect.to_equal([])
  run_scheduled(scheduled)
  let assert [payload] = transport_js.get_cell(submissions)
  let assert Ok(dynamic) = json.parse(json.to_string(payload), decode.dynamic)
  let assert Ok(frame.SubmitOperation(_, [[published]])) =
    frame.decode_submit_operation(dynamic)

  let peer_callbacks = transport_js.new_cell(None)
  let peer_submissions = transport_js.new_cell([])
  let peer =
    watershed.connect_via_seed(
      tenant: "default",
      document: "tree",
      user_id: "peer",
      seed: seed,
      transport: runtime.Transport(connect: fn(handlers) {
        transport_js.set_cell(peer_callbacks, Some(handlers))
        runtime.TransportHandle(
          push: fn(event, payload) {
            case event {
              "submitOp" ->
                transport_js.set_cell(peer_submissions, [
                  payload,
                  ..transport_js.get_cell(peer_submissions)
                ])
              _ -> Nil
            }
          },
          close: fn() { Nil },
          drop: fn() { Nil },
          hold: fn() { Nil },
          resume: fn() { Nil },
        )
      }),
      on_ready: fn(_) { Nil },
    )
  let assert Some(peer_callbacks) = transport_js.get_cell(peer_callbacks)
  peer_callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "peer",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["peer"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    )
      |> json.to_string,
  )
  let publication =
    frame.encode_operation_event([
      sequenced_submission(published, "writer", 1),
    ])
    |> json.to_string
  callbacks.on_event("op", publication)
  peer_callbacks.on_event("op", publication)
  let peer_root = watershed.resolve_root(peer) |> expect.to_be_ok()
  let peer_store_marker =
    watershed.get(peer_root, "secondary") |> expect.to_be_ok()
  let peer_store =
    watershed.resolve(peer, peer_store_marker) |> expect.to_be_ok()
  let peer_tree_marker = watershed.get(peer_store, "tree") |> expect.to_be_ok()
  let peer_tree =
    facade_fixture.resolve_javascript(peer, peer_tree_marker, view)
    |> expect.to_be_ok()
  facade_fixture.get_javascript(peer_tree, ["child", "id"])
  |> expect.to_equal(Ok(generated))
  facade_fixture.get_javascript(peer_tree, ["child", "label"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("local"))))

  facade_fixture.set_javascript(
    peer_tree,
    ["child", "label"],
    tree_types.StringValue("peer"),
  )
  |> expect.to_equal(Ok(Nil))
  let assert [peer_payload] = transport_js.get_cell(peer_submissions)
  let assert Ok(dynamic) =
    json.parse(json.to_string(peer_payload), decode.dynamic)
  let assert Ok(frame.SubmitOperation(_, [[peer_edit]])) =
    frame.decode_submit_operation(dynamic)
  let peer_event =
    frame.encode_operation_event([sequenced_submission(peer_edit, "peer", 2)])
    |> json.to_string
  callbacks.on_event("op", peer_event)
  peer_callbacks.on_event("op", peer_event)
  facade_fixture.get_javascript(tree, ["child", "label"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("peer"))))
  facade_fixture.get_javascript(peer_tree, ["child", "label"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("peer"))))

  let peer_handle_tree_marker =
    watershed.get(peer_store, "handle-tree") |> expect.to_be_ok()
  let peer_handle_tree =
    facade_fixture.resolve_javascript(
      peer,
      peer_handle_tree_marker,
      handle_view,
    )
    |> expect.to_be_ok()
  let assert Ok(Some(tree_types.HandleValue(peer_target_reference))) =
    facade_fixture.get_javascript(peer_handle_tree, [])
  let peer_target_marker = handle.reference_to_json(peer_target_reference)
  let writer_target_before =
    watershed.resolve(document, target_marker) |> expect.to_be_ok()
  writer_target_before |> expect.to_equal(target)
  let peer_target_before =
    watershed.resolve(peer, peer_target_marker) |> expect.to_be_ok()
  watershed.set(peer_target_before, "peer", json.string("survives"))
  let assert [target_payload, _] = transport_js.get_cell(peer_submissions)
  let assert Ok(target_dynamic) =
    json.parse(json.to_string(target_payload), decode.dynamic)
  let assert Ok(frame.SubmitOperation(_, [[target_edit]])) =
    frame.decode_submit_operation(target_dynamic)
  let target_event =
    frame.encode_operation_event([sequenced_submission(target_edit, "peer", 3)])
    |> json.to_string
  callbacks.on_event("op", target_event)
  peer_callbacks.on_event("op", target_event)
  watershed.get(writer_target_before, "peer")
  |> expect.to_equal(Ok(json.string("survives")))

  watershed.tree_revert(lifetime_revertible, True)
  |> expect.to_equal(Ok(Nil))
  watershed.tree_revertible_status(lifetime_revertible)
  |> expect.to_equal(watershed.RevertibleDisposed)
  transport_js.get_cell(disposed_lifetime_revertibles)
  |> expect.to_equal([
    #(lifetime_revertible, watershed.RevertibleDisposed),
  ])
  let assert [undo_callback_payload, undo_payload, _] =
    transport_js.get_cell(submissions)
  let assert Ok(undo_callback_dynamic) =
    json.parse(json.to_string(undo_callback_payload), decode.dynamic)
  let assert Ok(frame.SubmitOperation(_, [[undo_callback]])) =
    frame.decode_submit_operation(undo_callback_dynamic)
  let frame.SubmittedOperation(_, _, undo_callback_csn, _, _) = undo_callback
  let assert Ok(undo_dynamic) =
    json.parse(json.to_string(undo_payload), decode.dynamic)
  let assert Ok(frame.SubmitOperation(_, [[undo]])) =
    frame.decode_submit_operation(undo_dynamic)
  let frame.SubmittedOperation(_, _, undo_csn, _, _) = undo
  undo_callback_csn |> expect.to_equal(undo_csn + 1)
  let undo_event =
    frame.encode_operation_event([
      sequenced_submission(undo, "writer", 4),
      sequenced_submission(undo_callback, "writer", 5),
    ])
    |> json.to_string
  callbacks.on_event("op", undo_event)
  peer_callbacks.on_event("op", undo_event)
  facade_fixture.get_javascript(handle_tree, []) |> expect.to_equal(Ok(None))
  facade_fixture.get_javascript(peer_handle_tree, [])
  |> expect.to_equal(Ok(None))
  let writer_target_after =
    watershed.resolve(document, target_marker) |> expect.to_be_ok()
  writer_target_after |> expect.to_equal(writer_target_before)
  let peer_target_after =
    watershed.resolve(peer, peer_target_marker) |> expect.to_be_ok()
  peer_target_after |> expect.to_equal(peer_target_before)
  watershed.get(writer_target_after, "peer")
  |> expect.to_equal(Ok(json.string("survives")))
  watershed.get(peer_target_after, "peer")
  |> expect.to_equal(Ok(json.string("survives")))
  watershed.get(writer_target_after, "undo-callback")
  |> expect.to_equal(Ok(json.string("after-undo")))
  watershed.get(peer_target_after, "undo-callback")
  |> expect.to_equal(Ok(json.string("after-undo")))

  let merged_branch = watershed.tree_fork(tree) |> expect.to_be_ok()
  let merged_revertible = transport_js.new_cell(None)
  let disposed_merged_revertibles = transport_js.new_cell([])
  let _merged_token =
    watershed.subscribe_tree_commits(merged_branch, fn(event) {
      let acquired =
        watershed.tree_get_revertible(event, fn(disposed) {
          transport_js.set_cell(disposed_merged_revertibles, [
            disposed,
            ..transport_js.get_cell(disposed_merged_revertibles)
          ])
          watershed.set(target, "merge-callback", json.string("after-merge"))
        })
        |> expect.to_be_ok()
      transport_js.set_cell(merged_revertible, Some(acquired))
    })
  facade_fixture.set_javascript(
    merged_branch,
    ["child", "label"],
    tree_types.StringValue("merged"),
  )
  |> expect.to_equal(Ok(Nil))
  let assert Some(merged_revertible) = transport_js.get_cell(merged_revertible)
  watershed.tree_merge(tree, merged_branch, True) |> expect.to_equal(Ok(Nil))
  transport_js.get_cell(disposed_merged_revertibles)
  |> expect.to_equal([merged_revertible])
  let assert [merge_callback_payload, merge_payload, _, _, _] =
    transport_js.get_cell(submissions)
  let assert Ok(merge_callback_dynamic) =
    json.parse(json.to_string(merge_callback_payload), decode.dynamic)
  let assert Ok(frame.SubmitOperation(_, [[merge_callback]])) =
    frame.decode_submit_operation(merge_callback_dynamic)
  let frame.SubmittedOperation(_, _, merge_callback_csn, _, _) = merge_callback
  let assert Ok(merge_dynamic) =
    json.parse(json.to_string(merge_payload), decode.dynamic)
  let assert Ok(frame.SubmitOperation(_, [[merge]])) =
    frame.decode_submit_operation(merge_dynamic)
  let frame.SubmittedOperation(_, _, merge_csn, _, _) = merge
  merge_callback_csn |> expect.to_equal(merge_csn + 1)
  let merge_event =
    frame.encode_operation_event([
      sequenced_submission(merge, "writer", 6),
      sequenced_submission(merge_callback, "writer", 7),
    ])
    |> json.to_string
  callbacks.on_event("op", merge_event)
  peer_callbacks.on_event("op", merge_event)
  facade_fixture.get_javascript(peer_tree, ["child", "label"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("merged"))))
  watershed.get(writer_target_after, "merge-callback")
  |> expect.to_equal(Ok(json.string("after-merge")))
  watershed.get(peer_target_after, "merge-callback")
  |> expect.to_equal(Ok(json.string("after-merge")))

  let explicitly_disposed = transport_js.new_cell(None)
  let explicit_notifications = transport_js.new_cell([])
  let explicit_token =
    watershed.subscribe_tree_commits(tree, fn(event) {
      let acquired =
        watershed.tree_get_revertible(event, fn(disposed) {
          transport_js.set_cell(explicit_notifications, [
            disposed,
            ..transport_js.get_cell(explicit_notifications)
          ])
        })
        |> expect.to_be_ok()
      transport_js.set_cell(explicitly_disposed, Some(acquired))
    })
  facade_fixture.set_javascript(
    tree,
    ["child", "label"],
    tree_types.StringValue("explicit-dispose"),
  )
  |> expect.to_equal(Ok(Nil))
  watershed.unsubscribe(explicit_token)
  let assert Some(explicitly_disposed) =
    transport_js.get_cell(explicitly_disposed)
  watershed.tree_dispose_revertible(explicitly_disposed)
  |> expect.to_equal(Ok(Nil))
  transport_js.get_cell(explicit_notifications)
  |> expect.to_equal([explicitly_disposed])

  let close_revertible = transport_js.new_cell(None)
  let close_notifications = transport_js.new_cell([])
  let close_token =
    watershed.subscribe_tree_commits(tree, fn(event) {
      let acquired =
        watershed.tree_get_revertible(event, fn(disposed) {
          transport_js.set_cell(close_notifications, [
            disposed,
            ..transport_js.get_cell(close_notifications)
          ])
        })
        |> expect.to_be_ok()
      transport_js.set_cell(close_revertible, Some(acquired))
    })
  facade_fixture.set_javascript(
    tree,
    ["child", "label"],
    tree_types.StringValue("close"),
  )
  |> expect.to_equal(Ok(Nil))
  watershed.unsubscribe(close_token)
  let assert Some(close_revertible) = transport_js.get_cell(close_revertible)
  watershed.unsubscribe(lifetime_token)
  watershed.close(peer)
  watershed.close(document)
  watershed.set_checked(root, "closed", json.string("no"))
  |> expect.to_be_error()
  transport_js.get_cell(close_notifications)
  |> expect.to_equal([close_revertible])
  transport_js.get_cell(disposed_lifetime_revertibles)
  |> expect.to_equal([
    #(lifetime_revertible, watershed.RevertibleDisposed),
  ])
  transport_js.get_cell(disposed_branch_revertibles)
  |> expect.to_equal([branch_revertible])
  transport_js.get_cell(disposed_merged_revertibles)
  |> expect.to_equal([merged_revertible])
  transport_js.get_cell(explicit_notifications)
  |> expect.to_equal([explicitly_disposed])
  let _ = watershed.data_store_root(store) |> expect.to_be_error()
  Nil
}
