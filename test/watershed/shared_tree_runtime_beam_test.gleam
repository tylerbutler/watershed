@target(erlang)
import gleam/dict
@target(erlang)
import gleam/dynamic/decode
@target(erlang)
import gleam/erlang/process
@target(erlang)
import gleam/json
@target(erlang)
import gleam/list
@target(erlang)
import gleam/option.{None, Some}
@target(erlang)
import gleam/result
@target(erlang)
import signet/types as token
@target(erlang)
import spillway/message
@target(erlang)
import spillway/types
@target(erlang)
import startest/expect
@target(erlang)
import watershed/channel
@target(erlang)
import watershed/fluid_ids
@target(erlang)
import watershed/handle
@target(erlang)
import watershed/map_kernel
@target(erlang)
import watershed/runtime_beam
@target(erlang)
import watershed/runtime_core
@target(erlang)
import watershed/schema
@target(erlang)
import watershed/sluice/frame
@target(erlang)
import watershed/summary_policy
@target(erlang)
import watershed/tree/fixtures
@target(erlang)
import watershed/tree/identifier_fixture
@target(erlang)
import watershed/tree/runtime_fixture
@target(erlang)
import watershed/tree/types as tree_types
@target(erlang)
import watershed/tree/undo_acceptance
@target(erlang)
import watershed/tree_kernel
@target(erlang)
import watershed/wire/fluid_container
@target(erlang)
import watershed/wire/op as wire_op
@target(erlang)
import watershed/wire/socket
@target(erlang)
import watershed_beam

@target(erlang)
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

@target(erlang)
fn ready_tree_actor(push: fn(String, json.Json) -> Result(Nil, String)) {
  let assert Ok(#(input, _)) = runtime_fixture.routed_seed_input()
  let assert Ok(seed) = runtime_core.bootstrap_seed(input)
  let assert [view] = input.tree_views
  let callbacks_subject = process.new_subject()
  let assert Ok(actor) =
    runtime_beam.start_with_transport_and_seed(
      host: "seed.invalid",
      port: 0,
      connect_message: connect_message(),
      transport: runtime_beam.Transport(connect: fn(callbacks) {
        process.send(callbacks_subject, callbacks)
      }),
      seed: seed,
    )
  let assert Ok(callbacks) = process.receive(callbacks_subject, 1000)
  callbacks.on_ready(
    runtime_beam.TransportHandle(push: push, close: fn() { Nil }, drop: fn() {
      Nil
    }),
  )
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
    ),
  )
  runtime_beam.await_ready(actor) |> expect.to_equal(Ok(Nil))
  #(actor, callbacks, view.view)
}

@target(erlang)
fn ready_identifier_actor(push: fn(String, json.Json) -> Result(Nil, String)) {
  let assert Ok(seed) =
    identifier_fixture.seed_input()
    |> runtime_core.bootstrap_seed
  let callbacks_subject = process.new_subject()
  let assert Ok(actor) =
    runtime_beam.start_with_transport_and_seed(
      host: "seed.invalid",
      port: 0,
      connect_message: connect_message(),
      transport: runtime_beam.Transport(connect: fn(callbacks) {
        process.send(callbacks_subject, callbacks)
      }),
      seed: seed,
    )
  let assert Ok(callbacks) = process.receive(callbacks_subject, 1000)
  callbacks.on_ready(
    runtime_beam.TransportHandle(push: push, close: fn() { Nil }, drop: fn() {
      Nil
    }),
  )
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
    ),
  )
  runtime_beam.await_ready(actor) |> expect.to_equal(Ok(Nil))
  actor
}

@target(erlang)
pub fn identifier_refusals_preserve_installed_runtime_test() {
  let submissions = process.new_subject()
  let actor =
    ready_identifier_actor(fn(event, payload) {
      case event {
        "submitOp" -> process.send(submissions, payload)
        _ -> Nil
      }
      Ok(Nil)
    })
  let events = process.new_subject()
  process.send(
    actor,
    runtime_beam.Subscribe("A/_C", fn(event) { process.send(events, event) }),
  )

  [
    tree_types.SetField(["id"], tree_types.StringValue("replacement")),
    tree_types.SetField(["id"], tree_types.StringValue("literal-custom-id")),
    tree_types.ClearField(["id"]),
  ]
  |> list.each(fn(edit) {
    runtime_beam.tree_edit(actor, "A/_C", edit) |> expect.to_be_error
    runtime_beam.tree_read(actor, "A/_C", ["id"])
    |> expect.to_equal(Ok(Some(tree_types.StringValue("literal-custom-id"))))
    process.receive(events, 0) |> expect.to_equal(Error(Nil))
    process.receive(submissions, 0) |> expect.to_equal(Error(Nil))
  })
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
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

@target(erlang)
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

@target(erlang)
fn history_count(
  actor: process.Subject(runtime_beam.Msg),
  field: String,
) -> Int {
  runtime_beam.tree_history_evidence(actor, "A/_C")
  |> expect.to_be_ok()
  |> json.to_string
  |> json.parse(decode.at([field], decode.list(decode.dynamic)))
  |> expect.to_be_ok()
  |> list.length
}

@target(erlang)
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

@target(erlang)
pub fn assert_pending_multi_edit_transaction_resubmit() {
  let sender_connections = process.new_subject()
  let receiver_connections = process.new_subject()
  let submissions = process.new_subject()
  let sender_events = process.new_subject()
  let receiver_events = process.new_subject()
  let assert Ok(sender) =
    runtime_beam.start_with_transport_and_seed(
      host: "seed.invalid",
      port: 0,
      connect_message: connect_message(),
      seed: identifier_seed(),
      transport: runtime_beam.Transport(connect: fn(callbacks) {
        process.send(sender_connections, callbacks)
      }),
    )
  let assert Ok(receiver) =
    runtime_beam.start_with_transport_and_seed(
      host: "seed.invalid",
      port: 0,
      connect_message: connect_message(),
      seed: identifier_seed(),
      transport: runtime_beam.Transport(connect: fn(callbacks) {
        process.send(receiver_connections, callbacks)
      }),
    )
  let assert Ok(sender_transport) = process.receive(sender_connections, 1000)
  let assert Ok(receiver_transport) =
    process.receive(receiver_connections, 1000)
  sender_transport.on_ready(
    runtime_beam.TransportHandle(
      push: fn(event, payload) {
        case event {
          "submitOp" -> {
            let assert Ok(dynamic) =
              json.parse(json.to_string(payload), decode.dynamic)
            let assert Ok(frame.SubmitOperation(_, [[submitted]])) =
              frame.decode_submit_operation(dynamic)
            process.send(submissions, submitted)
          }
          _ -> Nil
        }
        Ok(Nil)
      },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  receiver_transport.on_ready(
    runtime_beam.TransportHandle(
      push: fn(_, _) { Ok(Nil) },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
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
    ),
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
    ),
  )
  runtime_beam.await_ready(sender) |> expect.to_equal(Ok(Nil))
  runtime_beam.await_ready(receiver) |> expect.to_equal(Ok(Nil))
  process.send(
    sender,
    runtime_beam.Subscribe("A/_C", fn(event) {
      process.send(sender_events, event)
    }),
  )
  process.send(
    receiver,
    runtime_beam.Subscribe("A/_C", fn(event) {
      process.send(receiver_events, event)
    }),
  )
  let view = identifier_fixture.full_view()
  runtime_beam.begin_tree_transaction(sender, "A/_C", view, [])
  |> expect.to_equal(Ok(Nil))
  runtime_beam.tree_edit_view(
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
  runtime_beam.tree_edit_view(
    sender,
    "A/_C",
    view,
    tree_types.SetField(
      ["left", "1", "label"],
      tree_types.StringValue("pending-final"),
    ),
  )
  |> expect.to_equal(Ok(Nil))
  runtime_beam.commit_tree_transaction(sender, "A/_C")
  |> expect.to_equal(Ok(Nil))
  let assert Ok(original) = process.receive(submissions, 1000)
  let identifier =
    runtime_beam.tree_read(sender, "A/_C", ["left", "1", "id"])
    |> expect.to_be_ok()
  process.receive(sender_events, 1000)
  |> expect.to_equal(Ok(channel.TreeEvent(tree_kernel.TreeChanged(True))))

  sender_transport.on_close("transport lost")
  runtime_beam.connection_observation(sender).phase
  |> expect.to_equal("reconnecting")
  let assert Ok(rejoined) = process.receive(sender_connections, 1000)
  rejoined.on_ready(
    runtime_beam.TransportHandle(
      push: fn(event, payload) {
        case event {
          "submitOp" -> {
            let assert Ok(dynamic) =
              json.parse(json.to_string(payload), decode.dynamic)
            let assert Ok(frame.SubmitOperation(_, [[submitted]])) =
              frame.decode_submit_operation(dynamic)
            process.send(submissions, submitted)
          }
          _ -> Nil
        }
        Ok(Nil)
      },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  rejoined.on_event(
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
    ),
  )
  rejoined.on_event(
    "op",
    frame.encode_operation_event([
      membership_frame(1, "join", "{\"clientId\":\"writer-2\",\"detail\":{}}"),
    ]),
  )
  runtime_beam.connection_observation(sender).phase
  |> expect.to_equal("catching-up")
  process.receive(submissions, 0) |> expect.to_equal(Error(Nil))
  rejoined.on_event(
    "op",
    frame.encode_operation_event([
      membership_frame(2, "leave", "\"writer\""),
    ]),
  )
  let assert Ok(resent) = process.receive(submissions, 1000)
  runtime_beam.connection_observation(sender).phase |> expect.to_equal("ready")
  resent.client_sequence_number
  |> expect.to_equal(original.client_sequence_number + 1)
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
    ]),
  )
  process.receive(receiver_events, 1000)
  |> expect.to_equal(Ok(channel.TreeEvent(tree_kernel.TreeChanged(False))))
  history_count(receiver, "trunk") |> expect.to_equal(1)
  runtime_beam.tree_array_values(receiver, "A/_C", ["left"])
  |> expect.to_be_ok()
  |> list.length
  |> expect.to_equal(2)
  runtime_beam.tree_read(receiver, "A/_C", ["left", "1", "label"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("pending-final"))))
  runtime_beam.tree_read(receiver, "A/_C", ["left", "1", "id"])
  |> expect.to_equal(Ok(identifier))

  rejoined.on_event(
    "op",
    frame.encode_operation_event([
      sequenced_submission(resent, "writer-2", 3),
    ]),
  )
  history_count(sender, "pending") |> expect.to_equal(0)
  history_count(sender, "trunk") |> expect.to_equal(1)
  process.receive(sender_events, 0) |> expect.to_equal(Error(Nil))
  runtime_beam.tree_read(sender, "A/_C", ["left", "1", "id"])
  |> expect.to_equal(Ok(identifier))
  process.send(sender, runtime_beam.Shutdown)
  process.send(receiver, runtime_beam.Shutdown)
}

@target(erlang)
pub fn assert_accepted_transaction_before_drop() {
  let sender_connections = process.new_subject()
  let receiver_connections = process.new_subject()
  let submissions = process.new_subject()
  let sender_events = process.new_subject()
  let receiver_events = process.new_subject()
  let assert Ok(sender) =
    runtime_beam.start_with_transport_and_seed(
      host: "seed.invalid",
      port: 0,
      connect_message: connect_message(),
      seed: identifier_seed(),
      transport: runtime_beam.Transport(connect: fn(callbacks) {
        process.send(sender_connections, callbacks)
      }),
    )
  let assert Ok(receiver) =
    runtime_beam.start_with_transport_and_seed(
      host: "seed.invalid",
      port: 0,
      connect_message: connect_message(),
      seed: identifier_seed(),
      transport: runtime_beam.Transport(connect: fn(callbacks) {
        process.send(receiver_connections, callbacks)
      }),
    )
  let assert Ok(sender_transport) = process.receive(sender_connections, 1000)
  let assert Ok(receiver_transport) =
    process.receive(receiver_connections, 1000)
  sender_transport.on_ready(
    runtime_beam.TransportHandle(
      push: fn(event, payload) {
        case event {
          "submitOp" -> {
            let assert Ok(dynamic) =
              json.parse(json.to_string(payload), decode.dynamic)
            let assert Ok(frame.SubmitOperation(_, [[submitted]])) =
              frame.decode_submit_operation(dynamic)
            process.send(submissions, submitted)
          }
          _ -> Nil
        }
        Ok(Nil)
      },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  receiver_transport.on_ready(
    runtime_beam.TransportHandle(
      push: fn(_, _) { Ok(Nil) },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
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
    ),
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
    ),
  )
  runtime_beam.await_ready(sender) |> expect.to_equal(Ok(Nil))
  runtime_beam.await_ready(receiver) |> expect.to_equal(Ok(Nil))
  process.send(
    sender,
    runtime_beam.Subscribe("A/_C", fn(event) {
      process.send(sender_events, event)
    }),
  )
  process.send(
    receiver,
    runtime_beam.Subscribe("A/_C", fn(event) {
      process.send(receiver_events, event)
    }),
  )
  let view = identifier_fixture.full_view()
  runtime_beam.begin_tree_transaction(sender, "A/_C", view, [])
  |> expect.to_equal(Ok(Nil))
  runtime_beam.tree_edit_view(
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
  runtime_beam.tree_edit_view(
    sender,
    "A/_C",
    view,
    tree_types.SetField(
      ["left", "1", "label"],
      tree_types.StringValue("accepted-final"),
    ),
  )
  |> expect.to_equal(Ok(Nil))
  runtime_beam.commit_tree_transaction(sender, "A/_C")
  |> expect.to_equal(Ok(Nil))
  let assert Ok(submitted) = process.receive(submissions, 1000)
  let identifier =
    runtime_beam.tree_read(sender, "A/_C", ["left", "1", "id"])
    |> expect.to_be_ok()
  process.receive(sender_events, 1000)
  |> expect.to_equal(Ok(channel.TreeEvent(tree_kernel.TreeChanged(True))))
  receiver_transport.on_event(
    "op",
    frame.encode_operation_event([
      sequenced_submission(submitted, "writer", 1),
    ]),
  )
  process.receive(receiver_events, 1000)
  |> expect.to_equal(Ok(channel.TreeEvent(tree_kernel.TreeChanged(False))))
  history_count(receiver, "trunk") |> expect.to_equal(1)
  runtime_beam.tree_array_values(receiver, "A/_C", ["left"])
  |> expect.to_be_ok()
  |> list.length
  |> expect.to_equal(2)
  runtime_beam.tree_read(receiver, "A/_C", ["left", "1", "label"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("accepted-final"))))
  runtime_beam.tree_read(receiver, "A/_C", ["left", "1", "id"])
  |> expect.to_equal(Ok(identifier))

  sender_transport.on_close("transport lost")
  let assert Ok(rejoined) = process.receive(sender_connections, 1000)
  rejoined.on_ready(
    runtime_beam.TransportHandle(
      push: fn(event, payload) {
        case event {
          "submitOp" -> {
            let assert Ok(dynamic) =
              json.parse(json.to_string(payload), decode.dynamic)
            let assert Ok(frame.SubmitOperation(_, [[resent]])) =
              frame.decode_submit_operation(dynamic)
            process.send(submissions, resent)
          }
          _ -> Nil
        }
        Ok(Nil)
      },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  rejoined.on_event(
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
    ),
  )
  rejoined.on_event(
    "op",
    frame.encode_operation_event([
      sequenced_submission(submitted, "writer", 1),
      membership_frame(2, "join", "{\"clientId\":\"writer-2\",\"detail\":{}}"),
    ]),
  )
  runtime_beam.connection_observation(sender).phase
  |> expect.to_equal("catching-up")
  process.receive(submissions, 0) |> expect.to_equal(Error(Nil))
  rejoined.on_event(
    "op",
    frame.encode_operation_event([
      membership_frame(3, "leave", "\"writer\""),
    ]),
  )
  runtime_beam.connection_observation(sender).phase |> expect.to_equal("ready")
  process.receive(submissions, 0) |> expect.to_equal(Error(Nil))
  history_count(sender, "pending") |> expect.to_equal(0)
  history_count(sender, "trunk") |> expect.to_equal(1)
  process.receive(sender_events, 0) |> expect.to_equal(Error(Nil))
  runtime_beam.tree_read(sender, "A/_C", ["left", "1", "id"])
  |> expect.to_equal(Ok(identifier))
  process.send(sender, runtime_beam.Shutdown)
  process.send(receiver, runtime_beam.Shutdown)
}

@target(erlang)
fn pending_reconnect_actor() {
  let assert Ok(#(input, _)) = runtime_fixture.routed_seed_input()
  let assert Ok(seed) = runtime_core.bootstrap_seed(input)
  let connections = process.new_subject()
  let assert Ok(actor) =
    runtime_beam.start_with_transport_and_seed(
      host: "seed.invalid",
      port: 0,
      connect_message: connect_message(),
      seed: seed,
      transport: runtime_beam.Transport(connect: fn(callbacks) {
        process.send(connections, callbacks)
      }),
    )
  let assert Ok(first) = process.receive(connections, 1000)
  first.on_ready(
    runtime_beam.TransportHandle(
      push: fn(_, _) { Ok(Nil) },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
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
    ),
  )
  runtime_beam.await_ready(actor) |> expect.to_equal(Ok(Nil))
  runtime_beam.tree_edit(
    actor,
    "A/_C",
    tree_types.SetField(["title"], tree_types.StringValue("retained")),
  )
  |> expect.to_equal(Ok(Nil))
  first.on_close("transport lost")
  #(actor, connections)
}

@target(erlang)
pub fn failed_reconnect_request_does_not_restore_stale_phase_test() {
  let #(actor, connections) = pending_reconnect_actor()
  let assert Ok(second) = process.receive(connections, 1000)
  second.on_ready(
    runtime_beam.TransportHandle(
      push: fn(event, _) {
        case event {
          "requestOps" -> Error("history request refused")
          _ -> Ok(Nil)
        }
      },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  second.on_event(
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
    ),
  )
  let assert Ok(third) = process.receive(connections, 1000)
  let observation = runtime_beam.connection_observation(actor)
  observation.phase |> expect.to_equal("reconnecting")
  observation.pending_tree_count |> expect.to_equal(1)
  third.on_ready(
    runtime_beam.TransportHandle(
      push: fn(_, _) { Ok(Nil) },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  third.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader-3",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 1,
      initial_clients: ["reader-3"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    ),
  )
  runtime_beam.connection_observation(actor).client_id
  |> expect.to_equal(Some("reader-3"))
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
pub fn failed_gap_request_does_not_restore_old_catching_up_core_test() {
  let #(actor, connections) = pending_reconnect_actor()
  let assert Ok(second) = process.receive(connections, 1000)
  second.on_ready(
    runtime_beam.TransportHandle(
      push: fn(event, payload) {
        case
          event == "requestOps"
          && json.to_string(payload)
          == json.to_string(socket.encode_request_operations(from: 1))
        {
          True -> Error("gap request refused")
          False -> Ok(Nil)
        }
      },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  second.on_event(
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
    ),
  )
  second.on_event(
    "op",
    frame.encode_operation_event([
      membership_frame(1, "join", "{\"clientId\":\"reader-2\",\"detail\":{}}"),
    ]),
  )
  second.on_event(
    "op",
    frame.encode_operation_event([membership_frame(3, "leave", "\"other\"")]),
  )
  let observation = runtime_beam.connection_observation(actor)
  observation.phase |> expect.to_equal("reconnecting")
  observation.error |> expect.to_equal(Some("gap request refused"))
  observation.pending_tree_count |> expect.to_equal(1)
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
pub fn permanent_reconnect_rejection_retains_pending_without_retry_test() {
  let #(actor, connections) = pending_reconnect_actor()
  let assert Ok(second) = process.receive(connections, 1000)
  second.on_ready(
    runtime_beam.TransportHandle(
      push: fn(_, _) { Ok(Nil) },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  second.on_event(
    "connect_document_error",
    json.object([
      #("code", json.int(401)),
      #("message", json.string("authorization revoked")),
    ]),
  )
  let observation = runtime_beam.connection_observation(actor)
  observation.phase |> expect.to_equal("suspended")
  observation.error |> expect.to_equal(Some("authorization revoked"))
  observation.pending_tree_count |> expect.to_equal(1)
  runtime_beam.tree_read(actor, "A/_C", ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("retained"))))
  second.on_event(
    "connect_document_error",
    json.object([
      #("code", json.int(401)),
      #("message", json.string("authorization revoked")),
    ]),
  )
  process.receive(connections, 0) |> expect.to_equal(Error(Nil))
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
pub fn repeated_reconnect_server_failures_stop_with_observable_reason_test() {
  let #(actor, connections) = pending_reconnect_actor()
  let error =
    json.object([
      #("code", json.int(503)),
      #("message", json.string("service unavailable")),
    ])
  list.each([Nil, Nil, Nil], fn(_) {
    let assert Ok(callbacks) = process.receive(connections, 1000)
    callbacks.on_ready(
      runtime_beam.TransportHandle(
        push: fn(_, _) { Ok(Nil) },
        close: fn() { Nil },
        drop: fn() { Nil },
      ),
    )
    callbacks.on_event("connect_document_error", error)
    let observation = runtime_beam.connection_observation(actor)
    observation.phase |> expect.to_equal("reconnecting")
    observation.error |> expect.to_equal(Some("service unavailable"))
    observation.pending_tree_count |> expect.to_equal(1)
    process.receive(connections, 0) |> expect.to_equal(Error(Nil))
  })
  let assert Ok(last) = process.receive(connections, 1000)
  last.on_ready(
    runtime_beam.TransportHandle(
      push: fn(_, _) { Ok(Nil) },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  last.on_event("connect_document_error", error)
  let observation = runtime_beam.connection_observation(actor)
  observation.phase |> expect.to_equal("suspended")
  observation.error |> expect.to_equal(Some("service unavailable"))
  process.receive(connections, 500) |> expect.to_equal(Error(Nil))
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
pub fn bad_replayed_operation_suspends_without_killing_actor_test() {
  let #(actor, connections) = pending_reconnect_actor()
  let assert Ok(second) = process.receive(connections, 1000)
  second.on_ready(
    runtime_beam.TransportHandle(
      push: fn(_, _) { Ok(Nil) },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  second.on_event(
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
    ),
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
  second.on_event(
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
    ]),
  )
  let observation = runtime_beam.connection_observation(actor)
  observation.phase |> expect.to_equal("suspended")
  observation.pending_tree_count |> expect.to_equal(1)
  observation.error |> expect.to_not_equal(None)
  runtime_beam.tree_read(actor, "A/_C", ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("retained"))))
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
pub fn bad_live_operation_fails_without_crashing_actor_test() {
  let assert Ok(#(input, _)) = runtime_fixture.routed_seed_input()
  let assert Ok(seed) = runtime_core.bootstrap_seed(input)
  let callbacks_subject = process.new_subject()
  let assert Ok(actor) =
    runtime_beam.start_with_transport_and_seed(
      host: "seed.invalid",
      port: 0,
      connect_message: connect_message(),
      transport: runtime_beam.Transport(connect: fn(callbacks) {
        process.send(callbacks_subject, callbacks)
      }),
      seed: seed,
    )
  let assert Ok(callbacks) = process.receive(callbacks_subject, 1000)
  callbacks.on_ready(
    runtime_beam.TransportHandle(
      push: fn(_, _) { Ok(Nil) },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
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
    ),
  )
  runtime_beam.await_ready(actor) |> expect.to_equal(Ok(Nil))
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
    ]),
  )
  runtime_beam.await_ready(actor) |> expect.to_be_error()
  let observation = runtime_beam.connection_observation(actor)
  observation.phase |> expect.to_equal("failed")
  observation.error |> expect.to_not_equal(None)
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
pub fn deferred_bad_operation_fails_transaction_abort_explicitly_test() {
  let assert Ok(#(input, _)) = runtime_fixture.routed_seed_input()
  let assert Ok(seed) = runtime_core.bootstrap_seed(input)
  let assert [view] = input.tree_views
  let callbacks_subject = process.new_subject()
  let assert Ok(actor) =
    runtime_beam.start_with_transport_and_seed(
      host: "seed.invalid",
      port: 0,
      connect_message: connect_message(),
      transport: runtime_beam.Transport(connect: fn(callbacks) {
        process.send(callbacks_subject, callbacks)
      }),
      seed: seed,
    )
  let assert Ok(callbacks) = process.receive(callbacks_subject, 1000)
  callbacks.on_ready(
    runtime_beam.TransportHandle(
      push: fn(_, _) { Ok(Nil) },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
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
    ),
  )
  runtime_beam.await_ready(actor) |> expect.to_equal(Ok(Nil))
  runtime_beam.begin_tree_transaction(actor, "A/_C", view.view, [])
  |> expect.to_equal(Ok(Nil))
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
    ]),
  )
  runtime_beam.tree_read(actor, "A/_C", ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue(""))))
  runtime_beam.abort_tree_transaction(actor, "A/_C") |> expect.to_be_error()
  let observation = runtime_beam.connection_observation(actor)
  observation.phase |> expect.to_equal("failed")
  observation.error |> expect.to_not_equal(None)
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
fn deferred_gap_request_failure(
  finish: fn(process.Subject(runtime_beam.Msg), String) -> Result(Nil, String),
) {
  let #(actor, callbacks, view) =
    ready_tree_actor(fn(event, _) {
      case event {
        "requestOps" -> Error("gap request refused")
        _ -> Ok(Nil)
      }
    })
  runtime_beam.begin_tree_transaction(actor, "A/_C", view, [])
  |> expect.to_equal(Ok(Nil))
  callbacks.on_event(
    "op",
    frame.encode_operation_event([
      membership_frame(2, "leave", "\"other\""),
    ]),
  )
  finish(actor, "A/_C")
  |> expect.to_equal(Error("gap request refused"))
  let observation = runtime_beam.connection_observation(actor)
  observation.phase |> expect.to_equal("failed")
  observation.error |> expect.to_equal(Some("gap request refused"))
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
pub fn deferred_gap_request_failure_returns_from_abort_test() {
  deferred_gap_request_failure(runtime_beam.abort_tree_transaction)
}

@target(erlang)
pub fn deferred_gap_request_failure_returns_from_noop_commit_test() {
  deferred_gap_request_failure(runtime_beam.commit_tree_transaction)
}

@target(erlang)
pub fn transaction_transport_failure_is_not_reported_as_commit_test() {
  let assert Ok(#(input, _)) = runtime_fixture.routed_seed_input()
  let assert Ok(seed) = runtime_core.bootstrap_seed(input)
  let assert [view] = input.tree_views
  let callbacks_subject = process.new_subject()
  let assert Ok(actor) =
    runtime_beam.start_with_transport_and_seed(
      host: "seed.invalid",
      port: 0,
      connect_message: connect_message(),
      transport: runtime_beam.Transport(connect: fn(callbacks) {
        process.send(callbacks_subject, callbacks)
      }),
      seed: seed,
    )
  let assert Ok(callbacks) = process.receive(callbacks_subject, 1000)
  callbacks.on_ready(
    runtime_beam.TransportHandle(
      push: fn(event, _) {
        case event {
          "submitOp" -> Error("submission refused")
          _ -> Ok(Nil)
        }
      },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
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
    ),
  )
  runtime_beam.await_ready(actor) |> expect.to_equal(Ok(Nil))
  runtime_beam.begin_tree_transaction(actor, "A/_C", view.view, [])
  |> expect.to_equal(Ok(Nil))
  runtime_beam.tree_edit_view(
    actor,
    "A/_C",
    view.view,
    tree_types.SetField(["title"], tree_types.StringValue("pending")),
  )
  |> expect.to_equal(Ok(Nil))
  runtime_beam.commit_tree_transaction(actor, "A/_C") |> expect.to_be_error()
  runtime_beam.connection_observation(actor).phase
  |> expect.to_equal("reconnecting")
  runtime_beam.tree_read(actor, "A/_C", ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("pending"))))
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
pub fn dead_transaction_caller_does_not_strand_actor_test() {
  let assert Ok(#(input, _)) = runtime_fixture.routed_seed_input()
  let assert Ok(seed) = runtime_core.bootstrap_seed(input)
  let assert [view] = input.tree_views
  let callbacks_subject = process.new_subject()
  let assert Ok(actor) =
    runtime_beam.start_with_transport_and_seed(
      host: "seed.invalid",
      port: 0,
      connect_message: connect_message(),
      transport: runtime_beam.Transport(connect: fn(callbacks) {
        process.send(callbacks_subject, callbacks)
      }),
      seed: seed,
    )
  let assert Ok(callbacks) = process.receive(callbacks_subject, 1000)
  callbacks.on_ready(
    runtime_beam.TransportHandle(
      push: fn(_, _) { Ok(Nil) },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
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
    ),
  )
  runtime_beam.await_ready(actor) |> expect.to_equal(Ok(Nil))
  let begun = process.new_subject()
  let caller =
    process.spawn_unlinked(fn() {
      runtime_beam.begin_tree_transaction(actor, "A/_C", view.view, [])
      |> expect.to_equal(Ok(Nil))
      runtime_beam.tree_edit_view(
        actor,
        "A/_C",
        view.view,
        tree_types.SetField(["title"], tree_types.StringValue("discarded")),
      )
      |> expect.to_equal(Ok(Nil))
      process.send(begun, Nil)
    })
  let monitor = process.monitor(caller)
  process.receive(begun, 1000) |> expect.to_equal(Ok(Nil))
  process.new_selector()
  |> process.select_specific_monitor(monitor, fn(_) { Nil })
  |> process.selector_receive(1000)
  |> expect.to_equal(Ok(Nil))
  process.demonitor_process(monitor)

  runtime_beam.begin_tree_transaction(actor, "A/_C", view.view, [])
  |> expect.to_equal(Ok(Nil))
  runtime_beam.tree_read(actor, "A/_C", ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue(""))))
  runtime_beam.abort_tree_transaction(actor, "A/_C")
  |> expect.to_equal(Ok(Nil))
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
pub fn active_transaction_rejects_nonowner_tree_access_test() {
  let #(actor, _, view) = ready_tree_actor(fn(_, _) { Ok(Nil) })
  let begun = process.new_subject()
  let owner_results = process.new_subject()
  let _ =
    process.spawn_unlinked(fn() {
      let continue = process.new_subject()
      runtime_beam.begin_tree_transaction(actor, "A/_C", view, [])
      |> expect.to_equal(Ok(Nil))
      runtime_beam.tree_edit_view(
        actor,
        "A/_C",
        view,
        tree_types.SetField(["title"], tree_types.StringValue("owner")),
      )
      |> expect.to_equal(Ok(Nil))
      process.send(begun, continue)
      process.receive(continue, 1000) |> expect.to_equal(Ok(Nil))
      let read = runtime_beam.tree_read(actor, "A/_C", ["title"])
      let edit =
        runtime_beam.tree_edit(
          actor,
          "A/_C",
          tree_types.SetField(["title"], tree_types.StringValue("owner-two")),
        )
      let abort = runtime_beam.abort_tree_transaction(actor, "A/_C")
      process.send(owner_results, #(read, edit, abort))
    })
  let continue = process.receive(begun, 1000) |> expect.to_be_ok()

  runtime_beam.tree_read_view(actor, "A/_C", view, ["title"])
  |> expect.to_equal(Error("tree transaction uses another caller"))
  runtime_beam.tree_edit(
    actor,
    "A/_C",
    tree_types.SetField(["title"], tree_types.StringValue("nonowner")),
  )
  |> expect.to_equal(Error("tree transaction uses another caller"))

  process.send(continue, Nil)
  process.receive(owner_results, 1000)
  |> expect.to_equal(
    Ok(#(Ok(Some(tree_types.StringValue("owner"))), Ok(Nil), Ok(Nil))),
  )
  runtime_beam.tree_read(actor, "A/_C", ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue(""))))
  runtime_beam.tree_edit(
    actor,
    "A/_C",
    tree_types.SetField(["title"], tree_types.StringValue("after")),
  )
  |> expect.to_equal(Ok(Nil))
  runtime_beam.tree_read(actor, "A/_C", ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("after"))))
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
pub fn seeded_actor_resolves_routed_root_before_publication_test() {
  let assert Ok(#(input, prefix)) = runtime_fixture.routed_seed_input()
  let assert Ok(seed) = runtime_core.bootstrap_seed(input)
  let callbacks_subject = process.new_subject()
  let assert Ok(actor) =
    runtime_beam.start_with_transport_and_seed(
      host: "seed.invalid",
      port: 0,
      connect_message: connect_message(),
      transport: runtime_beam.Transport(connect: fn(callbacks) {
        process.send(callbacks_subject, callbacks)
      }),
      seed: seed,
    )
  let before =
    process.call(actor, waiting: 1000, sending: runtime_beam.ResolveRoot)
  before |> expect.to_be_error()
  let assert Ok(callbacks) = process.receive(callbacks_subject, 1000)
  callbacks.on_ready(
    runtime_beam.TransportHandle(
      push: fn(_, _) { Ok(Nil) },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  callbacks.on_event(
    "connect_document_success",
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
    ),
  )
  runtime_beam.await_ready(actor) |> expect.to_equal(Ok(Nil))
  runtime_beam.resolve_root(actor) |> expect.to_equal(Ok("A/root"))
  runtime_beam.operations_since_summary(actor) |> expect.to_equal(2)
  runtime_beam.tree_read(actor, "A/_C", []) |> expect.to_be_ok()
  let events = process.new_subject()
  process.send(
    actor,
    runtime_beam.Subscribe("A/_C", fn(event) { process.send(events, event) }),
  )
  runtime_beam.resolve_root(actor) |> expect.to_equal(Ok("A/root"))
  let assert Ok(fixture) = fixtures.load("batched-commits")
  let assert Some(compressor) = input.compressor
  let assert Ok(captured) =
    runtime_fixture.read(fixture.input, fluid_ids.local_session(compressor))
  let assert [group] = captured.operations
  callbacks.on_event(
    "op",
    frame.encode_operation_event([runtime_fixture.sequenced_frame(group)]),
  )
  runtime_beam.operations_since_summary(actor) |> expect.to_equal(3)
  process.receive(events, 1000) |> expect.to_be_ok()
  process.receive(events, 0) |> expect.to_equal(Error(Nil))
  runtime_beam.summarize(actor)
  |> expect.to_equal(Error("tree summary publication is not supported"))
  callbacks.on_close("transport lost")
  let assert Ok(rejoined) = process.receive(callbacks_subject, 1000)
  rejoined.on_ready(
    runtime_beam.TransportHandle(
      push: fn(_, _) { Ok(Nil) },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  rejoined.on_event(
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
    ),
  )
  runtime_beam.client_id(actor) |> expect.to_equal(Some("reader-2"))
  runtime_beam.resolve_root(actor) |> expect.to_equal(Ok("A/root"))
  runtime_beam.is_synced(actor) |> expect.to_equal(True)
  runtime_beam.tree_edit(
    actor,
    "A/_C",
    tree_types.SetField(["title"], tree_types.StringValue("pending")),
  )
  |> expect.to_equal(Ok(Nil))
  rejoined.on_event(
    "nack",
    json.object([
      #(
        "nacks",
        json.preprocessed_array([
          json.object([
            #("sequenceNumber", json.int(1)),
            #(
              "content",
              json.object([
                #("code", json.int(400)),
                #("type", json.string("BadRequestError")),
                #("message", json.string("retry")),
              ]),
            ),
          ]),
        ]),
      ),
    ]),
  )
  runtime_beam.await_ready(actor)
  |> expect.to_equal(Ok(Nil))
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
pub fn failed_bootstrap_history_read_reports_error_without_crashing_actor_test() {
  let assert Ok(#(input, _)) = runtime_fixture.routed_seed_input()
  let assert Ok(seed) = runtime_core.bootstrap_seed(input)
  let callbacks_subject = process.new_subject()
  let assert Ok(actor) =
    runtime_beam.start_with_transport_and_seed(
      host: "seed.invalid",
      port: 0,
      connect_message: message.ConnectMessage(..connect_message(), token: None),
      transport: runtime_beam.Transport(connect: fn(callbacks) {
        process.send(callbacks_subject, callbacks)
      }),
      seed: seed,
    )
  let assert Ok(pid) = process.subject_owner(actor)
  process.unlink(pid)
  let assert Ok(callbacks) = process.receive(callbacks_subject, 1000)
  callbacks.on_ready(
    runtime_beam.TransportHandle(
      push: fn(_, _) { Ok(Nil) },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 3,
      initial_clients: ["reader"],
      initial_messages: [membership_frame(3, "leave", "\"departed\"")],
      timestamp: 0,
      presence_v1: False,
    ),
  )
  runtime_beam.await_ready(actor)
  |> expect.to_equal(Error(
    "history catch-up failed: history catch-up requires an auth token",
  ))
  runtime_beam.connection_observation(actor).phase
  |> expect.to_equal("failed")
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
pub fn invalid_bootstrap_message_fails_ready_without_crashing_actor_test() {
  let assert Ok(#(input, _)) = runtime_fixture.routed_seed_input()
  let assert Ok(seed) = runtime_core.bootstrap_seed(input)
  let callbacks_subject = process.new_subject()
  let assert Ok(actor) =
    runtime_beam.start_with_transport_and_seed(
      host: "seed.invalid",
      port: 0,
      connect_message: connect_message(),
      transport: runtime_beam.Transport(connect: fn(callbacks) {
        process.send(callbacks_subject, callbacks)
      }),
      seed: seed,
    )
  let assert Ok(callbacks) = process.receive(callbacks_subject, 1000)
  callbacks.on_ready(
    runtime_beam.TransportHandle(
      push: fn(_, _) { Ok(Nil) },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader",
      tenant_id: "default",
      document_id: "tree",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 1,
      initial_clients: ["reader"],
      initial_messages: [
        membership_frame(1, "unsupported-required-message", ""),
      ],
      timestamp: 0,
      presence_v1: False,
    ),
  )
  runtime_beam.await_ready(actor) |> expect.to_be_error()
  runtime_beam.connection_observation(actor).phase
  |> expect.to_equal("failed")
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
pub fn routed_beam_facade_root_serializes_absolute_handle_test() {
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
  let callbacks_subject = process.new_subject()
  let assert Ok(document) =
    watershed_beam.connect_via_seed(
      tenant: "default",
      document: "tree",
      user_id: "reader",
      seed: seed,
      transport: runtime_beam.Transport(connect: fn(callbacks) {
        process.send(callbacks_subject, callbacks)
      }),
    )
  watershed_beam.resolve_root(document) |> expect.to_be_error()
  let assert Ok(callbacks) = process.receive(callbacks_subject, 1000)
  callbacks.on_ready(
    runtime_beam.TransportHandle(
      push: fn(_, _) { Ok(Nil) },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
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
    ),
  )
  let actor = watershed_beam.runtime_subject(document)
  runtime_beam.await_ready(actor) |> expect.to_equal(Ok(Nil))
  let assert Ok(root) = watershed_beam.resolve_root(document)
  let assert [view] = input.tree_views
  let assert Ok(marker) = watershed_beam.get(root, "tree")
  let assert Ok(tree) = watershed_beam.resolve_tree(document, marker, view.view)
  watershed_beam.tree_handle_of(tree)
  |> expect.to_equal(handle.encode_handle("A/_C"))
  let typed = watershed_beam.typed(root)
  watershed_beam.resolve_tree_field(
    document,
    typed,
    schema.channel_field("tree"),
    view.view,
  )
  |> result.map(fn(value) { option.map(value, watershed_beam.tree_handle_of) })
  |> expect.to_equal(Ok(Some(marker)))
  watershed_beam.resolve_tree_field(
    document,
    typed,
    schema.channel_field("absent-tree"),
    view.view,
  )
  |> expect.to_equal(Ok(None))
  watershed_beam.set_tree_field(typed, schema.channel_field("tree"), tree)
  watershed_beam.get(root, "tree") |> expect.to_equal(Ok(marker))
  let events = watershed_beam.subscribe_tree(tree)
  runtime_beam.resolve_root(actor) |> expect.to_be_ok()
  watershed_beam.tree_set(tree, ["unknown"], tree_types.StringValue("invalid"))
  |> expect.to_be_error()
  process.receive(events, 0) |> expect.to_equal(Error(Nil))
  watershed_beam.tree_set(tree, ["title"], tree_types.StringValue("native"))
  |> expect.to_equal(Ok(Nil))
  watershed_beam.tree_get(tree, ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("native"))))
  process.receive(events, 1000)
  |> expect.to_equal(Ok(tree_kernel.TreeChanged(True)))
  watershed_beam.tree_clear(tree, ["title"]) |> expect.to_be_error()
  watershed_beam.resolve_tree(
    document,
    watershed_beam.handle_of(root),
    view.view,
  )
  |> expect.to_be_error()
  watershed_beam.handle_of(root)
  |> json.to_string
  |> expect.to_equal("{\"type\":\"__fluid_handle__\",\"url\":\"/A/root\"}")
  let assert Ok(other) =
    watershed_beam.resolve(document, handle.encode_handle("B/root"))
  watershed_beam.handle_of(other)
  |> json.to_string
  |> expect.to_equal("{\"type\":\"__fluid_handle__\",\"url\":\"/B/root\"}")
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
pub fn actor_tree_echo_installs_state_before_next_command_test() {
  let assert Ok(#(input, _)) = runtime_fixture.routed_seed_input()
  let assert Ok(seed) = runtime_core.bootstrap_seed(input)
  let callbacks_subject = process.new_subject()
  let events = process.new_subject()
  let submissions = process.new_subject()
  let assert Ok(actor) =
    runtime_beam.start_with_transport_and_seed(
      host: "seed.invalid",
      port: 0,
      connect_message: connect_message(),
      seed: seed,
      transport: runtime_beam.Transport(connect: fn(handlers) {
        process.send(callbacks_subject, handlers)
      }),
    )
  let assert Ok(callbacks) = process.receive(callbacks_subject, 1000)
  callbacks.on_ready(
    runtime_beam.TransportHandle(
      push: fn(event, payload) {
        case event {
          "submitOp" -> {
            let assert Ok(dynamic) =
              json.parse(json.to_string(payload), decode.dynamic)
            let assert Ok(frame.SubmitOperation(_, [[submitted]])) =
              frame.decode_submit_operation(dynamic)
            process.send(submissions, submitted)
            callbacks.on_event(
              "op",
              frame.encode_operation_event([
                frame.Sequenced(
                  client_id: Some("reader"),
                  sequence_number: 1,
                  minimum_sequence_number: 0,
                  client_sequence_number: submitted.client_sequence_number,
                  reference_sequence_number: submitted.reference_sequence_number,
                  operation_type: submitted.operation_type,
                  contents: submitted.contents,
                  metadata: submitted.metadata,
                  timestamp: 0,
                  data: None,
                ),
              ]),
            )
          }

          _ -> Nil
        }
        Ok(Nil)
      },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
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
    ),
  )
  runtime_beam.await_ready(actor) |> expect.to_equal(Ok(Nil))
  process.send(
    actor,
    runtime_beam.Subscribe("A/_C", fn(event) { process.send(events, event) }),
  )
  runtime_beam.resolve_root(actor) |> expect.to_equal(Ok("A/root"))
  runtime_beam.auto_summarize(
    actor,
    Some(summary_policy.with_threshold(summary_policy.policy(), 1)),
  )
  runtime_beam.tree_edit(
    actor,
    "A/_C",
    tree_types.SetField(["unknown"], tree_types.StringValue("bad")),
  )
  |> expect.to_be_error()
  process.receive(events, 0) |> expect.to_equal(Error(Nil))
  process.receive(submissions, 0) |> expect.to_equal(Error(Nil))
  runtime_beam.tree_edit(
    actor,
    "A/_C",
    tree_types.SetField(["title"], tree_types.StringValue("native")),
  )
  |> expect.to_equal(Ok(Nil))
  let assert Ok(submitted) = process.receive(submissions, 1000)
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
  process.receive(events, 1000)
  |> expect.to_equal(Ok(channel.TreeEvent(tree_kernel.TreeChanged(True))))
  runtime_beam.tree_read(actor, "A/_C", ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("native"))))
  runtime_beam.is_synced(actor) |> expect.to_equal(True)
  process.send(actor, runtime_beam.MaybeSummarize)
  runtime_beam.resolve_root(actor) |> expect.to_equal(Ok("A/root"))
  process.receive(events, 0) |> expect.to_equal(Error(Nil))
  callbacks.on_close("transport lost")
  let assert Ok(rejoined) = process.receive(callbacks_subject, 1000)
  rejoined.on_ready(
    runtime_beam.TransportHandle(
      push: fn(event, payload) {
        case event {
          "submitOp" -> {
            let assert Ok(dynamic) =
              json.parse(json.to_string(payload), decode.dynamic)
            let assert Ok(frame.SubmitOperation(_, [[submitted]])) =
              frame.decode_submit_operation(dynamic)
            process.send(submissions, submitted)
          }
          _ -> Nil
        }
        Ok(Nil)
      },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  rejoined.on_event(
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
    ),
  )
  runtime_beam.client_id(actor) |> expect.to_equal(Some("reader-2"))
  runtime_beam.tree_edit(
    actor,
    "A/_C",
    tree_types.SetField(["title"], tree_types.StringValue("after reconnect")),
  )
  |> expect.to_equal(Ok(Nil))
  let assert Ok(next) = process.receive(submissions, 1000)
  let assert Ok(next_batch) =
    fluid_container.decode(next.contents, next.metadata)
  let assert [
    fluid_container.ContainerMessage(
      fluid_container.IdAllocation(next_range),
      0,
      _,
    ),
    _,
  ] = next_batch.messages
  next_range.session_id |> expect.to_equal(range.session_id)
  runtime_beam.is_synced(actor) |> expect.to_equal(False)
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
pub fn commit_delivery_exit_invalidates_factory_and_replays_messages_test() {
  let #(actor, _, _) = ready_tree_actor(fn(_, _) { Ok(Nil) })
  let factories = process.new_subject()
  let started = process.new_subject()
  let releases = process.new_subject()
  let token =
    runtime_beam.subscribe_tree_commits(actor, "A/_C", fn(event) {
      let assert runtime_beam.TreeCommitEvent(_, True, Some(factory), Some(_)) =
        event
      let release = process.new_subject()
      process.send(factories, factory)
      process.send(releases, release)
      process.send(started, Nil)
      process.receive(release, 1000) |> expect.to_equal(Ok(Nil))
      process.kill(process.self())
    })

  runtime_beam.tree_edit(
    actor,
    "A/_C",
    tree_types.SetField(["title"], tree_types.StringValue("native")),
  )
  |> expect.to_equal(Ok(Nil))
  let factory = process.receive(factories, 1000) |> expect.to_be_ok()
  let release = process.receive(releases, 1000) |> expect.to_be_ok()
  process.receive(started, 1000) |> expect.to_equal(Ok(Nil))
  let before = process.new_subject()
  let edit = process.new_subject()
  let after = process.new_subject()
  process.send(actor, runtime_beam.UnsubscribeTreeCommits(token))
  process.send(actor, runtime_beam.TreeRead("A/_C", ["title"], before))
  process.send(
    actor,
    runtime_beam.TreeEdit(
      "A/_C",
      tree_types.SetField(["title"], tree_types.StringValue("queued")),
      edit,
    ),
  )
  process.send(actor, runtime_beam.TreeRead("A/_C", ["title"], after))
  process.send(release, Nil)
  process.receive(before, 1000)
  |> expect.to_equal(Ok(Ok(Some(tree_types.StringValue("native")))))
  process.receive(edit, 1000) |> expect.to_equal(Ok(Ok(Nil)))
  process.receive(after, 1000)
  |> expect.to_equal(Ok(Ok(Some(tree_types.StringValue("queued")))))
  factory() |> expect.to_be_error()
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
pub fn summary_reload_emits_no_historical_commit_factory_and_new_edit_does_test() {
  let callbacks_subject = process.new_subject()
  let events = process.new_subject()
  let assert Ok(actor) =
    runtime_beam.start_with_transport_and_seed(
      host: "seed.invalid",
      port: 0,
      connect_message: connect_message(),
      transport: runtime_beam.Transport(connect: fn(callbacks) {
        process.send(callbacks_subject, callbacks)
      }),
      seed: undo_acceptance.summary_reload_seed_after_undo(),
    )
  let assert Ok(callbacks) = process.receive(callbacks_subject, 1000)
  callbacks.on_ready(
    runtime_beam.TransportHandle(
      push: fn(_, _) { Ok(Nil) },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  let _ =
    runtime_beam.subscribe_tree_commits(actor, "A/_C", fn(event) {
      let assert runtime_beam.TreeCommitEvent(
        tree_types.DefaultCommit,
        True,
        Some(factory),
        Some(_),
      ) = event
      process.send(events, factory())
    })
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
    ),
  )
  runtime_beam.await_ready(actor) |> expect.to_equal(Ok(Nil))
  process.receive(events, 0) |> expect.to_equal(Error(Nil))
  runtime_beam.tree_edit(
    actor,
    "A/_C",
    tree_types.SetField(["note"], tree_types.StringValue("after reload")),
  )
  |> expect.to_equal(Ok(Nil))
  let assert Ok(Ok(handle)) = process.receive(events, 1000)
  runtime_beam.tree_revertible_status(handle)
  |> expect.to_equal(runtime_beam.RevertibleValid)
  process.receive(events, 0) |> expect.to_equal(Error(Nil))
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
pub fn pending_tree_actor_retains_content_after_transport_loss_test() {
  let assert Ok(#(input, _)) = runtime_fixture.routed_seed_input()
  let assert Ok(seed) = runtime_core.bootstrap_seed(input)
  let callbacks_subject = process.new_subject()
  let submissions = process.new_subject()
  let assert Ok(actor) =
    runtime_beam.start_with_transport_and_seed(
      host: "seed.invalid",
      port: 0,
      connect_message: connect_message(),
      seed: seed,
      transport: runtime_beam.Transport(connect: fn(callbacks) {
        process.send(callbacks_subject, callbacks)
      }),
    )
  let assert Ok(callbacks) = process.receive(callbacks_subject, 1000)
  callbacks.on_ready(
    runtime_beam.TransportHandle(
      push: fn(event, payload) {
        case event {
          "submitOp" -> process.send(submissions, payload)
          _ -> Nil
        }
        Ok(Nil)
      },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
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
    ),
  )
  runtime_beam.await_ready(actor) |> expect.to_equal(Ok(Nil))
  runtime_beam.tree_edit(
    actor,
    "A/_C",
    tree_types.SetField(["title"], tree_types.StringValue("retained")),
  )
  |> expect.to_equal(Ok(Nil))
  process.receive(submissions, 1000) |> expect.to_be_ok()
  callbacks.on_close("transport lost")
  runtime_beam.connection_observation(actor).phase
  |> expect.to_equal("reconnecting")
  runtime_beam.connection_observation(actor).pending_tree_count
  |> expect.to_equal(1)
  runtime_beam.tree_read(actor, "A/_C", ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("retained"))))
  runtime_beam.tree_edit(
    actor,
    "A/_C",
    tree_types.SetField(["title"], tree_types.StringValue("lost")),
  )
  |> expect.to_be_error()
  runtime_beam.is_synced(actor) |> expect.to_equal(False)
  runtime_beam.client_id(actor) |> expect.to_equal(Some("reader"))
  let assert Ok(rejoined) = process.receive(callbacks_subject, 1000)
  rejoined.on_ready(
    runtime_beam.TransportHandle(
      push: fn(event, payload) {
        case event {
          "submitOp" -> process.send(submissions, payload)
          _ -> Nil
        }
        Ok(Nil)
      },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  rejoined.on_event(
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
    ),
  )
  rejoined.on_event(
    "op",
    frame.encode_operation_event([
      membership_frame(1, "join", "{\"clientId\":\"reader-2\",\"detail\":{}}"),
    ]),
  )
  runtime_beam.connection_observation(actor).phase
  |> expect.to_equal("catching-up")
  process.receive(submissions, 0) |> expect.to_equal(Error(Nil))
  rejoined.on_event(
    "op",
    frame.encode_operation_event([
      membership_frame(2, "leave", "\"reader\""),
    ]),
  )
  let assert Ok(payload) = process.receive(submissions, 1000)
  let assert Ok(dynamic) = json.parse(json.to_string(payload), decode.dynamic)
  let assert Ok(frame.SubmitOperation("reader-2", [[submitted]])) =
    frame.decode_submit_operation(dynamic)
  submitted.reference_sequence_number |> expect.to_equal(2)
  rejoined.on_event(
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
    ]),
  )
  runtime_beam.connection_observation(actor).synced |> expect.to_equal(True)
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
pub fn suspended_pending_tree_can_restart_reconnect_test() {
  let assert Ok(#(input, _)) = runtime_fixture.routed_seed_input()
  let assert Ok(seed) = runtime_core.bootstrap_seed(input)
  let callbacks_subject = process.new_subject()
  let assert Ok(actor) =
    runtime_beam.start_with_transport_and_seed(
      host: "seed.invalid",
      port: 0,
      connect_message: connect_message(),
      seed: seed,
      transport: runtime_beam.Transport(connect: fn(callbacks) {
        process.send(callbacks_subject, callbacks)
      }),
    )
  let assert Ok(callbacks) = process.receive(callbacks_subject, 1000)
  callbacks.on_ready(
    runtime_beam.TransportHandle(
      push: fn(_, _) { Ok(Nil) },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
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
    ),
  )
  runtime_beam.await_ready(actor) |> expect.to_equal(Ok(Nil))
  runtime_beam.tree_edit(
    actor,
    "A/_C",
    tree_types.SetField(["title"], tree_types.StringValue("retained")),
  )
  |> expect.to_equal(Ok(Nil))

  callbacks.on_fail("first failure")
  let assert Ok(first_retry) = process.receive(callbacks_subject, 1000)
  first_retry.on_fail("second failure")
  let assert Ok(second_retry) = process.receive(callbacks_subject, 1000)
  second_retry.on_fail("third failure")
  let assert Ok(third_retry) = process.receive(callbacks_subject, 1000)
  third_retry.on_fail("fourth failure")
  runtime_beam.connection_observation(actor).phase
  |> expect.to_equal("suspended")

  process.send(actor, runtime_beam.DropChannel)
  process.receive(callbacks_subject, 1000) |> expect.to_be_ok()
  runtime_beam.connection_observation(actor).phase
  |> expect.to_equal("reconnecting")
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
pub fn suspended_reconnect_closes_live_transport_before_restart_test() {
  let #(actor, connections) = pending_reconnect_actor()
  let closed = process.new_subject()
  let assert Ok(rejoined) = process.receive(connections, 1000)
  rejoined.on_ready(
    runtime_beam.TransportHandle(
      push: fn(_, _) { Ok(Nil) },
      close: fn() { process.send(closed, Nil) },
      drop: fn() { Nil },
    ),
  )
  rejoined.on_event(
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
    ),
  )
  rejoined.on_event(
    "op",
    frame.encode_operation_event([
      membership_frame(1, "join", "{\"clientId\":\"reader-2\",\"detail\":{}}"),
    ]),
  )
  runtime_beam.connection_observation(actor).phase
  |> expect.to_equal("catching-up")

  process.send(actor, runtime_beam.ReconnectTimedOut("reader-2"))
  runtime_beam.connection_observation(actor).phase
  |> expect.to_equal("suspended")
  process.send(actor, runtime_beam.DropChannel)

  process.receive(closed, 1000) |> expect.to_be_ok()
  process.receive(connections, 1000) |> expect.to_be_ok()
  runtime_beam.connection_observation(actor).phase
  |> expect.to_equal("reconnecting")
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
pub fn failed_tree_send_retains_candidate_and_refuses_more_edits_test() {
  let assert Ok(#(input, _)) = runtime_fixture.routed_seed_input()
  let assert Ok(seed) = runtime_core.bootstrap_seed(input)
  let callbacks_subject = process.new_subject()
  let events = process.new_subject()
  let submissions = process.new_subject()
  let assert Ok(actor) =
    runtime_beam.start_with_transport_and_seed(
      host: "seed.invalid",
      port: 0,
      connect_message: connect_message(),
      seed: seed,
      transport: runtime_beam.Transport(connect: fn(callbacks) {
        process.send(callbacks_subject, callbacks)
      }),
    )
  let assert Ok(callbacks) = process.receive(callbacks_subject, 1000)
  callbacks.on_ready(
    runtime_beam.TransportHandle(
      push: fn(event, payload) {
        case event {
          "submitOp" -> {
            process.send(submissions, payload)
            Error("send refused")
          }
          _ -> Ok(Nil)
        }
      },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
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
    ),
  )
  runtime_beam.await_ready(actor) |> expect.to_equal(Ok(Nil))
  process.send(
    actor,
    runtime_beam.Subscribe("A/_C", fn(event) { process.send(events, event) }),
  )
  runtime_beam.resolve_root(actor) |> expect.to_equal(Ok("A/root"))
  runtime_beam.tree_edit(
    actor,
    "A/_C",
    tree_types.SetField(["title"], tree_types.StringValue("retained")),
  )
  |> expect.to_equal(Ok(Nil))
  let assert Ok(payload) = process.receive(submissions, 1000)
  let assert Ok(dynamic) = json.parse(json.to_string(payload), decode.dynamic)
  let assert Ok(frame.SubmitOperation(_, [[submitted]])) =
    frame.decode_submit_operation(dynamic)
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
  runtime_beam.await_ready(actor)
  |> expect.to_equal(Ok(Nil))
  runtime_beam.tree_read(actor, "A/_C", ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("retained"))))
  runtime_beam.tree_edit(
    actor,
    "A/_C",
    tree_types.SetField(["title"], tree_types.StringValue("lost")),
  )
  |> expect.to_be_error()
  runtime_beam.is_synced(actor) |> expect.to_equal(False)
  runtime_beam.client_id(actor) |> expect.to_equal(Some("reader"))
  process.receive(events, 1000)
  |> expect.to_equal(Ok(channel.TreeEvent(tree_kernel.TreeChanged(True))))
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
pub fn failed_heartbeat_with_pending_tree_keeps_actor_and_core_test() {
  let assert Ok(#(input, _)) = runtime_fixture.routed_seed_input()
  let assert Ok(seed) = runtime_core.bootstrap_seed(input)
  let callbacks_subject = process.new_subject()
  let sends = process.new_subject()
  let assert Ok(actor) =
    runtime_beam.start_with_transport_and_seed(
      host: "seed.invalid",
      port: 0,
      connect_message: connect_message(),
      seed: seed,
      transport: runtime_beam.Transport(connect: fn(callbacks) {
        process.send(callbacks_subject, callbacks)
      }),
    )
  let assert Ok(callbacks) = process.receive(callbacks_subject, 1000)
  callbacks.on_ready(
    runtime_beam.TransportHandle(
      push: fn(event, _) {
        case event {
          "noop" -> {
            process.send(sends, event)
            Error("heartbeat send refused")
          }
          "submitOp" -> Ok(Nil)
          _ -> {
            process.send(sends, event)
            Ok(Nil)
          }
        }
      },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
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
    ),
  )
  runtime_beam.await_ready(actor) |> expect.to_equal(Ok(Nil))
  process.receive(sends, 1000)
  |> expect.to_equal(Ok("connect_document"))
  runtime_beam.tree_edit(
    actor,
    "A/_C",
    tree_types.SetField(["title"], tree_types.StringValue("retained")),
  )
  |> expect.to_equal(Ok(Nil))
  process.send(actor, runtime_beam.Heartbeat)
  runtime_beam.await_ready(actor)
  |> expect.to_equal(Ok(Nil))
  process.receive(sends, 1000) |> expect.to_equal(Ok("noop"))
  runtime_beam.tree_read(actor, "A/_C", ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("retained"))))
  runtime_beam.tree_edit(
    actor,
    "A/_C",
    tree_types.SetField(["title"], tree_types.StringValue("discarded")),
  )
  |> expect.to_be_error()
  runtime_beam.is_synced(actor) |> expect.to_equal(False)
  runtime_beam.client_id(actor) |> expect.to_equal(Some("reader"))
  process.send(actor, runtime_beam.Put("A/root", "ignored", json.int(1)))
  process.send(actor, runtime_beam.SubmitRipple("test", json.null()))
  process.send(actor, runtime_beam.SubmitPresence("presence", json.null()))
  process.send(actor, runtime_beam.Heartbeat)
  callbacks.on_ready(
    runtime_beam.TransportHandle(
      push: fn(event, _) {
        process.send(sends, event)
        Ok(Nil)
      },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  callbacks.on_fail("late failure")
  runtime_beam.connection_observation(actor).phase
  |> expect.to_equal("reconnecting")
  runtime_beam.tree_read(actor, "A/_C", ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("retained"))))
  process.receive(sends, 0) |> expect.to_equal(Error(Nil))
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
fn failed_sibling_send_with_pending_tree(event: String) -> Nil {
  let assert Ok(#(input, _)) = runtime_fixture.routed_seed_input()
  let assert Ok(seed) = runtime_core.bootstrap_seed(input)
  let callbacks_subject = process.new_subject()
  let sends = process.new_subject()
  let assert Ok(actor) =
    runtime_beam.start_with_transport_and_seed(
      host: "seed.invalid",
      port: 0,
      connect_message: connect_message(),
      seed: seed,
      transport: runtime_beam.Transport(connect: fn(callbacks) {
        process.send(callbacks_subject, callbacks)
      }),
    )
  let assert Ok(callbacks) = process.receive(callbacks_subject, 1000)
  callbacks.on_ready(
    runtime_beam.TransportHandle(
      push: fn(pushed, payload) {
        let failed = case pushed, event {
          "submitSignal", "submitSignal" -> True
          "submitOp", "submitOp" -> {
            let assert Ok(dynamic) =
              json.parse(json.to_string(payload), decode.dynamic)
            let assert Ok(frame.SubmitOperation(_, [[submitted]])) =
              frame.decode_submit_operation(dynamic)
            let assert Ok(batch) =
              fluid_container.decode(submitted.contents, submitted.metadata)
            case batch.messages {
              [
                fluid_container.ContainerMessage(
                  fluid_container.ChannelOperation(
                    fluid_container.Route("A", "root"),
                    _,
                  ),
                  _,
                  _,
                ),
                ..
              ] -> True
              _ -> False
            }
          }
          _, _ -> False
        }
        case failed {
          True -> {
            process.send(sends, pushed)
            Error("sibling send refused")
          }
          False -> Ok(Nil)
        }
      },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
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
    ),
  )
  runtime_beam.await_ready(actor) |> expect.to_equal(Ok(Nil))
  runtime_beam.tree_edit(
    actor,
    "A/_C",
    tree_types.SetField(["title"], tree_types.StringValue("retained")),
  )
  |> expect.to_equal(Ok(Nil))
  case event {
    "submitSignal" ->
      process.send(actor, runtime_beam.SubmitRipple("test", json.null()))
    "submitOp" ->
      process.send(
        actor,
        runtime_beam.Put("A/root", "after", json.string("kept")),
      )
    _ -> panic as "invalid sibling send test event"
  }
  runtime_beam.await_ready(actor)
  |> expect.to_equal(Ok(Nil))
  process.receive(sends, 1000) |> expect.to_equal(Ok(event))
  runtime_beam.tree_read(actor, "A/_C", ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("retained"))))
  case event {
    "submitOp" ->
      process.call(actor, waiting: 1000, sending: fn(reply) {
        runtime_beam.GetValue("A/root", "after", reply)
      })
      |> expect.to_equal(Ok(json.string("kept")))
    _ -> Nil
  }
  runtime_beam.is_synced(actor) |> expect.to_equal(False)
  process.send(actor, runtime_beam.Put("A/root", "ignored", json.int(1)))
  process.send(actor, runtime_beam.SubmitRipple("test", json.null()))
  process.send(actor, runtime_beam.Heartbeat)
  runtime_beam.connection_observation(actor).phase
  |> expect.to_equal("reconnecting")
  process.receive(sends, 0) |> expect.to_equal(Error(Nil))
  process.send(actor, runtime_beam.Shutdown)
}

@target(erlang)
pub fn failed_map_send_with_pending_tree_retains_both_edits_test() {
  failed_sibling_send_with_pending_tree("submitOp")
}

@target(erlang)
pub fn failed_signal_with_pending_tree_retains_core_test() {
  failed_sibling_send_with_pending_tree("submitSignal")
}

@target(erlang)
pub fn bad_last_group_child_fails_without_notifying_beam_subscribers_test() {
  let assert Ok(#(input, _)) = runtime_fixture.routed_seed_input()
  let assert Ok(seed) = runtime_core.bootstrap_seed(input)
  let callbacks_subject = process.new_subject()
  let events = process.new_subject()
  let assert Ok(actor) =
    runtime_beam.start_with_transport_and_seed(
      host: "seed.invalid",
      port: 0,
      connect_message: connect_message(),
      seed: seed,
      transport: runtime_beam.Transport(connect: fn(callbacks) {
        process.send(callbacks_subject, callbacks)
      }),
    )
  let assert Ok(callbacks) = process.receive(callbacks_subject, 1000)
  callbacks.on_ready(
    runtime_beam.TransportHandle(
      push: fn(_, _) { Ok(Nil) },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
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
    ),
  )
  runtime_beam.await_ready(actor) |> expect.to_equal(Ok(Nil))
  process.send(
    actor,
    runtime_beam.Subscribe("A/root", fn(event) { process.send(events, event) }),
  )
  runtime_beam.resolve_root(actor) |> expect.to_equal(Ok("A/root"))
  let assert Ok(contents) =
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
        contents: contents,
        metadata: None,
        timestamp: 0,
        data: None,
      ),
    ]),
  )
  runtime_beam.await_ready(actor) |> expect.to_be_error()
  runtime_beam.connection_observation(actor).phase
  |> expect.to_equal("failed")
  process.receive(events, 0) |> expect.to_equal(Error(Nil))
  process.send(actor, runtime_beam.Shutdown)
}
