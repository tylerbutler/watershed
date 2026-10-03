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
import watershed/tree/fixtures
@target(javascript)
import watershed/tree/identifier_fixture
@target(javascript)
import watershed/tree/runtime_fixture
@target(javascript)
import watershed/tree/types as tree_types
@target(javascript)
import watershed/tree_kernel
@target(javascript)
import watershed/wire/fluid_container
@target(javascript)
import watershed/wire/op as wire_op

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
  )
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
  resent.client_sequence_number
  |> expect.to_equal(initial.client_sequence_number + 1)
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
  let assert Ok(marker) = watershed.get(root, "tree")
  let assert Ok(tree) = watershed.resolve_tree(document, marker, view.view)
  watershed.tree_handle_of(tree)
  |> expect.to_equal(handle.encode_handle("A/_C"))
  let typed = watershed.typed(root)
  watershed.resolve_tree_field(
    document,
    typed,
    schema.channel_field("tree"),
    view.view,
  )
  |> result.map(fn(value) { option.map(value, watershed.tree_handle_of) })
  |> expect.to_equal(Ok(Some(marker)))
  watershed.resolve_tree_field(
    document,
    typed,
    schema.channel_field("absent-tree"),
    view.view,
  )
  |> expect.to_equal(Ok(None))
  watershed.set_tree_field(typed, schema.channel_field("tree"), tree)
  watershed.get(root, "tree") |> expect.to_equal(Ok(marker))
  let changed = transport_js.new_cell([])
  let subscription =
    watershed.subscribe_tree(tree, fn(event) {
      transport_js.set_cell(changed, [event, ..transport_js.get_cell(changed)])
    })
  watershed.tree_set(tree, ["unknown"], tree_types.StringValue("invalid"))
  |> expect.to_be_error()
  transport_js.get_cell(changed) |> expect.to_equal([])
  watershed.tree_set(tree, ["title"], tree_types.StringValue("native"))
  |> expect.to_equal(Ok(Nil))
  watershed.tree_get(tree, ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("native"))))
  transport_js.get_cell(changed)
  |> expect.to_equal([
    tree_kernel.TreeChanged(True),
  ])
  watershed.unsubscribe(subscription)
  watershed.tree_clear(tree, ["title"]) |> expect.to_be_error()
  watershed.resolve_tree(document, watershed.handle_of(root), view.view)
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
pub fn inline_tree_echo_preserves_one_local_invalidation_test() {
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
              "submitOp" -> {
                let assert Ok(dynamic) =
                  json.parse(json.to_string(payload), decode.dynamic)
                let assert Ok(frame.SubmitOperation(sender, [[submitted]])) =
                  frame.decode_submit_operation(dynamic)
                transport_js.set_cell(submissions, [
                  submitted,
                  ..transport_js.get_cell(submissions)
                ])
                handlers.on_event(
                  "op",
                  frame.encode_operation_event([
                    frame.Sequenced(
                      client_id: Some(sender),
                      sequence_number: submitted.client_sequence_number,
                      minimum_sequence_number: 0,
                      client_sequence_number: submitted.client_sequence_number,
                      reference_sequence_number: submitted.reference_sequence_number,
                      operation_type: submitted.operation_type,
                      contents: submitted.contents,
                      metadata: submitted.metadata,
                      timestamp: 0,
                      data: None,
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
