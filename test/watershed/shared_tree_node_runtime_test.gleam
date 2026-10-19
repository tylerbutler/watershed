import gleam/dynamic
import gleam/dynamic/decode
import gleam/json
import gleam/option.{None, Some}
import spillway/types
import startest/expect
import watershed/fluid_ids
import watershed/runtime_core
import watershed/tree/identifier_fixture
import watershed/tree/node
import watershed/tree/runtime_fixture
import watershed/tree/types as tree_types
import watershed/wire

@target(javascript)
import gleam/dict
@target(javascript)
import gleam/list
@target(javascript)
import signet/types as token
@target(javascript)
import spillway/message
@target(javascript)
import watershed/runtime
@target(javascript)
import watershed/sluice/frame
@target(javascript)
import watershed/transport_js

@target(erlang)
import gleam/dict as beam_dict
@target(erlang)
import gleam/erlang/process
@target(erlang)
import signet/types as beam_token
@target(erlang)
import spillway/message as beam_message
@target(erlang)
import watershed/runtime_beam
@target(erlang)
import watershed/sluice/frame as beam_frame

fn root() -> tree_types.TreeValue {
  identifier_fixture.full_root(
    identifier_fixture.point("child", "child"),
    [
      identifier_fixture.point("first", "first"),
      identifier_fixture.point("second", "second"),
    ],
    [],
    [],
  )
}

fn core(client_id: String, session_id: String) -> runtime_core.Core {
  let input = identifier_fixture.full_seed_input(root())
  let assert Some(compressor) = input.compressor
  let serialized = fluid_ids.serialize(compressor, False) |> expect.to_be_ok()
  let session = fluid_ids.session_id(session_id) |> expect.to_be_ok()
  let compressor =
    fluid_ids.deserialize(serialized, session) |> expect.to_be_ok()
  let seed =
    runtime_core.BootstrapSeedInput(..input, compressor: Some(compressor))
    |> runtime_core.bootstrap_seed
    |> expect.to_be_ok()
  let assert runtime_core.Complete(core) =
    runtime_core.bootstrap_seeded(
      runtime_fixture.connected(client_id, [], 0),
      seed,
    )
    |> expect.to_be_ok()
  core
}

fn sequenced(
  outbound: wire.OutboundOperation,
  client_id: String,
  sequence_number: Int,
) -> types.SequencedDocumentMessage(dynamic.Dynamic) {
  let contents =
    json.parse(json.to_string(outbound.contents), decode.dynamic)
    |> expect.to_be_ok()
  let metadata = case outbound.metadata {
    None -> None
    Some(value) ->
      json.parse(json.to_string(value), decode.dynamic)
      |> expect.to_be_ok()
      |> Some
  }
  types.SequencedDocumentMessage(
    client_id: Some(client_id),
    sequence_number: sequence_number,
    minimum_sequence_number: 0,
    client_sequence_number: outbound.client_sequence_number,
    reference_sequence_number: outbound.reference_sequence_number,
    message_type: "op",
    contents: contents,
    metadata: metadata,
    server_metadata: None,
    origin: None,
    traces: None,
    timestamp: 0,
    data: None,
  )
}

pub fn shared_tree_node_peer_reorder_preserves_identity_and_sequenced_output_test() {
  let view = identifier_fixture.full_view()
  let reader = core("reader", "50000000-0000-4000-8000-000000000005")
  let peer = core("peer", "60000000-0000-4000-8000-000000000006")
  let reference =
    runtime_core.tree_node_reference_view_on(
      reader,
      "A/_C",
      tree_types.DocumentCheckout,
      view,
      ["left", "0"],
    )
    |> expect.to_be_ok()
    |> expect.to_be_some()
  let assert #(peer, _, [peer_outbound]) =
    runtime_core.submit_tree_edits_view_on(
      peer,
      "A/_C",
      tree_types.DocumentCheckout,
      view,
      [tree_types.ArrayMove(["left"], 0, 1, ["left"], 2)],
    )
    |> expect.to_be_ok()
  let #(reader, _) =
    runtime_core.handle_sequenced(reader, sequenced(peer_outbound, "peer", 1))
    |> expect.to_be_ok()

  runtime_core.tree_node_reference_view_on(
    reader,
    "A/_C",
    tree_types.DocumentCheckout,
    view,
    ["left", "1"],
  )
  |> expect.to_equal(Ok(Some(reference)))
  runtime_core.tree_node_read_view_on(
    reader,
    "A/_C",
    tree_types.DocumentCheckout,
    view,
    reference,
    ["label"],
  )
  |> expect.to_equal(Ok(Some(tree_types.StringValue("first"))))

  let assert #(_reader, _, [reader_outbound]) =
    runtime_core.submit_tree_node_edit_view_on(
      reader,
      "A/_C",
      tree_types.DocumentCheckout,
      view,
      reference,
      node.SetField("label", tree_types.StringValue("edited")),
    )
    |> expect.to_be_ok()
  let #(peer, _) =
    runtime_core.handle_sequenced(peer, sequenced(peer_outbound, "peer", 1))
    |> expect.to_be_ok()
  let #(peer, _) =
    runtime_core.handle_sequenced(peer, sequenced(reader_outbound, "reader", 2))
    |> expect.to_be_ok()
  runtime_core.tree_read_view_on(
    peer,
    "A/_C",
    tree_types.DocumentCheckout,
    view,
    ["left", "1", "label"],
  )
  |> expect.to_equal(Ok(Some(tree_types.StringValue("edited"))))
}

@target(javascript)
fn js_connect_message() -> message.ConnectMessage {
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
fn starting_js_runtime() {
  let seed =
    identifier_fixture.full_seed_input(root())
    |> runtime_core.bootstrap_seed
    |> expect.to_be_ok()
  let callbacks = transport_js.new_cell(None)
  let submissions = transport_js.new_cell([])
  let ready = transport_js.new_cell(None)
  let owner =
    runtime.start_with_transport_and_seed(
      http_base_url: "https://seed.invalid",
      connect_message: js_connect_message(),
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
      on_ready: fn(outcome) { transport_js.set_cell(ready, Some(outcome)) },
    )
  let assert Some(callbacks) = transport_js.get_cell(callbacks)
  #(owner, callbacks, identifier_fixture.full_view(), submissions, ready)
}

@target(javascript)
fn ready_js_runtime() {
  let #(owner, callbacks, view, submissions, ready) = starting_js_runtime()
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
  #(owner, callbacks, view, submissions)
}

@target(javascript)
pub fn shared_tree_node_js_initialization_reconnect_and_close_test() {
  let #(owner, callbacks, view, _, _) = starting_js_runtime()
  runtime.tree_node_reference_view_on(
    owner,
    "A/_C",
    tree_types.DocumentCheckout,
    view,
    ["left", "0"],
  )
  |> expect.to_equal(Error(
    "tree node reference requires a ready document connection",
  ))
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
  let reference =
    runtime.tree_node_reference_view_on(
      owner,
      "A/_C",
      tree_types.DocumentCheckout,
      view,
      ["left", "0"],
    )
    |> expect.to_be_ok()
    |> expect.to_be_some()
  let root_reference =
    runtime.tree_node_reference_view_on(
      owner,
      "A/_C",
      tree_types.DocumentCheckout,
      view,
      [],
    )
    |> expect.to_be_ok()
    |> expect.to_be_some()
  let child_reference =
    runtime.tree_node_reference_view_on(
      owner,
      "A/_C",
      tree_types.DocumentCheckout,
      view,
      ["child"],
    )
    |> expect.to_be_ok()
    |> expect.to_be_some()
  runtime.tree_node_child_view_on(
    owner,
    "A/_C",
    tree_types.DocumentCheckout,
    view,
    root_reference,
    ["child"],
  )
  |> expect.to_equal(Ok(Some(child_reference)))
  let left_reference =
    runtime.tree_node_reference_view_on(
      owner,
      "A/_C",
      tree_types.DocumentCheckout,
      view,
      ["left"],
    )
    |> expect.to_be_ok()
    |> expect.to_be_some()
  runtime.tree_node_array_references_view_on(
    owner,
    "A/_C",
    tree_types.DocumentCheckout,
    view,
    left_reference,
  )
  |> expect.to_be_ok()
  |> expect.to_equal([
    reference,
    runtime.tree_node_reference_view_on(
      owner,
      "A/_C",
      tree_types.DocumentCheckout,
      view,
      ["left", "1"],
    )
      |> expect.to_be_ok()
      |> expect.to_be_some(),
  ])
  let map_reference =
    runtime.tree_node_reference_view_on(
      owner,
      "A/_C",
      tree_types.DocumentCheckout,
      view,
      ["byKey"],
    )
    |> expect.to_be_ok()
    |> expect.to_be_some()
  runtime.tree_node_map_entries_view_on(
    owner,
    "A/_C",
    tree_types.DocumentCheckout,
    view,
    map_reference,
  )
  |> expect.to_equal(Ok([]))

  callbacks.on_close()
  runtime.diagnostics(owner).phase |> expect.to_equal("reconnecting")
  runtime.tree_node_read_view_on(
    owner,
    "A/_C",
    tree_types.DocumentCheckout,
    view,
    reference,
    ["label"],
  )
  |> expect.to_equal(Ok(Some(tree_types.StringValue("first"))))
  runtime.tree_node_edit_view_on(
    owner,
    "A/_C",
    tree_types.DocumentCheckout,
    view,
    reference,
    node.SetField("label", tree_types.StringValue("rejected")),
  )
  |> expect.to_equal(Error(
    "tree node edit requires a ready document connection",
  ))

  runtime.close(owner)
  runtime.tree_node_reference_view_on(
    owner,
    "A/_C",
    tree_types.DocumentCheckout,
    view,
    ["left", "0"],
  )
  |> expect.to_equal(Error(
    "tree node reference requires a ready document connection",
  ))
}

@target(javascript)
pub fn shared_tree_node_js_transaction_candidate_is_current_test() {
  let #(owner, _, view, _) = ready_js_runtime()
  let reference =
    runtime.tree_node_reference_view_on(
      owner,
      "A/_C",
      tree_types.DocumentCheckout,
      view,
      ["left", "0"],
    )
    |> expect.to_be_ok()
    |> expect.to_be_some()
  runtime.begin_tree_transaction(owner, "A/_C", view, [])
  |> expect.to_equal(Ok(Nil))
  runtime.tree_edit_view(
    owner,
    "A/_C",
    view,
    tree_types.SetField(
      ["left", "0", "label"],
      tree_types.StringValue("candidate"),
    ),
  )
  |> expect.to_equal(Ok(Nil))
  runtime.tree_node_reference_view_on(
    owner,
    "A/_C",
    tree_types.DocumentCheckout,
    view,
    ["left", "0"],
  )
  |> expect.to_equal(Ok(Some(reference)))
  runtime.tree_node_read_view_on(
    owner,
    "A/_C",
    tree_types.DocumentCheckout,
    view,
    reference,
    ["label"],
  )
  |> expect.to_equal(Ok(Some(tree_types.StringValue("candidate"))))
  runtime.tree_node_edit_view_on(
    owner,
    "A/_C",
    tree_types.DocumentCheckout,
    view,
    reference,
    node.SetField("label", tree_types.StringValue("node-candidate")),
  )
  |> expect.to_equal(Ok(Nil))
  runtime.tree_node_read_view_on(
    owner,
    "A/_C",
    tree_types.DocumentCheckout,
    view,
    reference,
    ["label"],
  )
  |> expect.to_equal(Ok(Some(tree_types.StringValue("node-candidate"))))
  runtime.abort_tree_transaction(owner, "A/_C") |> expect.to_equal(Ok(Nil))
  runtime.tree_node_read_view_on(
    owner,
    "A/_C",
    tree_types.DocumentCheckout,
    view,
    reference,
    ["label"],
  )
  |> expect.to_equal(Ok(Some(tree_types.StringValue("first"))))
  runtime.close(owner)
}

@target(javascript)
pub fn shared_tree_node_js_stale_edit_preserves_runtime_effects_test() {
  let #(owner, _, view, submissions) = ready_js_runtime()
  let notifications = transport_js.new_cell(0)
  let _ =
    runtime.subscribe(owner, "A/_C", fn(_) {
      transport_js.set_cell(
        notifications,
        transport_js.get_cell(notifications) + 1,
      )
    })
  let reference =
    runtime.tree_node_reference_view_on(
      owner,
      "A/_C",
      tree_types.DocumentCheckout,
      view,
      ["left", "0"],
    )
    |> expect.to_be_ok()
    |> expect.to_be_some()
  runtime.tree_edit_view(
    owner,
    "A/_C",
    view,
    tree_types.ArrayRemove(["left"], 0, 1),
  )
  |> expect.to_equal(Ok(Nil))
  transport_js.get_cell(notifications) |> expect.to_equal(1)
  transport_js.get_cell(submissions) |> list.length |> expect.to_equal(1)

  let snapshot =
    runtime.tree_retained_snapshot(owner, "A/_C") |> expect.to_be_ok()
  let assert runtime_core.TreeRetainedSnapshot(_, Some(snapshot_compressor)) =
    snapshot
  let compressor =
    fluid_ids.serialize(snapshot_compressor, True) |> expect.to_be_ok()
  let history =
    runtime.tree_history_evidence(owner, "A/_C") |> expect.to_be_ok()
  let pending = runtime.diagnostics(owner).in_flight_count
  let notification_count = transport_js.get_cell(notifications)
  let submission_count = transport_js.get_cell(submissions) |> list.length

  runtime.tree_node_edit_view_on(
    owner,
    "A/_C",
    tree_types.DocumentCheckout,
    view,
    reference,
    node.SetField("label", tree_types.StringValue("rejected")),
  )
  |> expect.to_be_error()
  let after_snapshot =
    runtime.tree_retained_snapshot(owner, "A/_C") |> expect.to_be_ok()
  after_snapshot |> expect.to_equal(snapshot)
  let assert runtime_core.TreeRetainedSnapshot(_, Some(after_compressor)) =
    after_snapshot
  fluid_ids.serialize(after_compressor, True)
  |> expect.to_equal(Ok(compressor))
  runtime.tree_history_evidence(owner, "A/_C")
  |> expect.to_equal(Ok(history))
  runtime.diagnostics(owner).in_flight_count |> expect.to_equal(pending)
  transport_js.get_cell(notifications)
  |> expect.to_equal(notification_count)
  transport_js.get_cell(submissions)
  |> list.length
  |> expect.to_equal(submission_count)
  runtime.tree_read_view_on(owner, "A/_C", tree_types.DocumentCheckout, view, [
    "left",
    "0",
    "label",
  ])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("second"))))
  runtime.close(owner)
}

@target(erlang)
fn beam_connect_message() -> beam_message.ConnectMessage {
  beam_message.ConnectMessage(
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
      user: beam_token.User("reader", beam_dict.new()),
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
fn starting_beam_actor(submissions: process.Subject(json.Json)) {
  let seed =
    identifier_fixture.full_seed_input(root())
    |> runtime_core.bootstrap_seed
    |> expect.to_be_ok()
  let callbacks_subject = process.new_subject()
  let actor =
    runtime_beam.start_with_transport_and_seed(
      host: "seed.invalid",
      port: 0,
      connect_message: beam_connect_message(),
      transport: runtime_beam.Transport(connect: fn(callbacks) {
        process.send(callbacks_subject, callbacks)
      }),
      seed: seed,
    )
    |> expect.to_be_ok()
  let callbacks = process.receive(callbacks_subject, 1000) |> expect.to_be_ok()
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
  #(actor, callbacks, identifier_fixture.full_view())
}

@target(erlang)
fn ready_beam_actor(submissions: process.Subject(json.Json)) {
  let #(actor, callbacks, view) = starting_beam_actor(submissions)
  callbacks.on_event(
    "connect_document_success",
    beam_frame.encode_connected(
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
  #(actor, callbacks, view)
}

@target(erlang)
fn stop_beam_actor(actor: process.Subject(runtime_beam.Msg)) {
  let owner = process.subject_owner(actor) |> expect.to_be_ok()
  let monitor = process.monitor(owner)
  process.send(actor, runtime_beam.Shutdown)
  process.new_selector()
  |> process.select_specific_monitor(monitor, fn(_) { Nil })
  |> process.selector_receive(1000)
  |> expect.to_equal(Ok(Nil))
  process.demonitor_process(monitor)
}

@target(erlang)
pub fn shared_tree_node_beam_initialization_reconnect_and_close_test() {
  let submissions = process.new_subject()
  let #(actor, callbacks, view) = starting_beam_actor(submissions)
  runtime_beam.tree_node_reference_view_on(
    actor,
    "A/_C",
    tree_types.DocumentCheckout,
    view,
    ["left", "0"],
  )
  |> expect.to_equal(Error(
    "tree node reference requires a ready document connection",
  ))
  callbacks.on_event(
    "connect_document_success",
    beam_frame.encode_connected(
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
  let reference =
    runtime_beam.tree_node_reference_view_on(
      actor,
      "A/_C",
      tree_types.DocumentCheckout,
      view,
      ["left", "0"],
    )
    |> expect.to_be_ok()
    |> expect.to_be_some()
  let root_reference =
    runtime_beam.tree_node_reference_view_on(
      actor,
      "A/_C",
      tree_types.DocumentCheckout,
      view,
      [],
    )
    |> expect.to_be_ok()
    |> expect.to_be_some()
  let child_reference =
    runtime_beam.tree_node_reference_view_on(
      actor,
      "A/_C",
      tree_types.DocumentCheckout,
      view,
      ["child"],
    )
    |> expect.to_be_ok()
    |> expect.to_be_some()
  runtime_beam.tree_node_child_view_on(
    actor,
    "A/_C",
    tree_types.DocumentCheckout,
    view,
    root_reference,
    ["child"],
  )
  |> expect.to_equal(Ok(Some(child_reference)))
  let left_reference =
    runtime_beam.tree_node_reference_view_on(
      actor,
      "A/_C",
      tree_types.DocumentCheckout,
      view,
      ["left"],
    )
    |> expect.to_be_ok()
    |> expect.to_be_some()
  runtime_beam.tree_node_array_references_view_on(
    actor,
    "A/_C",
    tree_types.DocumentCheckout,
    view,
    left_reference,
  )
  |> expect.to_be_ok()
  |> expect.to_equal([
    reference,
    runtime_beam.tree_node_reference_view_on(
      actor,
      "A/_C",
      tree_types.DocumentCheckout,
      view,
      ["left", "1"],
    )
      |> expect.to_be_ok()
      |> expect.to_be_some(),
  ])
  let map_reference =
    runtime_beam.tree_node_reference_view_on(
      actor,
      "A/_C",
      tree_types.DocumentCheckout,
      view,
      ["byKey"],
    )
    |> expect.to_be_ok()
    |> expect.to_be_some()
  runtime_beam.tree_node_map_entries_view_on(
    actor,
    "A/_C",
    tree_types.DocumentCheckout,
    view,
    map_reference,
  )
  |> expect.to_equal(Ok([]))

  callbacks.on_close("transport lost")
  runtime_beam.tree_node_read_view_on(
    actor,
    "A/_C",
    tree_types.DocumentCheckout,
    view,
    reference,
    ["label"],
  )
  |> expect.to_equal(Ok(Some(tree_types.StringValue("first"))))
  runtime_beam.tree_node_edit_view_on(
    actor,
    "A/_C",
    tree_types.DocumentCheckout,
    view,
    reference,
    node.SetField("label", tree_types.StringValue("rejected")),
  )
  |> expect.to_equal(Error(
    "tree node edit requires a ready document connection",
  ))

  stop_beam_actor(actor)
  runtime_beam.tree_node_reference_view_on(
    actor,
    "A/_C",
    tree_types.DocumentCheckout,
    view,
    ["left", "0"],
  )
  |> expect.to_equal(Error("document runtime is closed"))
  runtime_beam.tree_node_edit_view_on(
    actor,
    "A/_C",
    tree_types.DocumentCheckout,
    view,
    reference,
    node.SetField("label", tree_types.StringValue("closed")),
  )
  |> expect.to_equal(Error("document runtime is closed"))
}

@target(erlang)
pub fn shared_tree_node_beam_transaction_candidate_and_owner_access_test() {
  let submissions = process.new_subject()
  let #(actor, _, view) = ready_beam_actor(submissions)
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
        tree_types.SetField(
          ["left", "0", "label"],
          tree_types.StringValue("candidate"),
        ),
      )
      |> expect.to_equal(Ok(Nil))
      let reference =
        runtime_beam.tree_node_reference_view_on(
          actor,
          "A/_C",
          tree_types.DocumentCheckout,
          view,
          ["left", "0"],
        )
        |> expect.to_be_ok()
        |> expect.to_be_some()
      runtime_beam.tree_node_read_view_on(
        actor,
        "A/_C",
        tree_types.DocumentCheckout,
        view,
        reference,
        ["label"],
      )
      |> expect.to_equal(Ok(Some(tree_types.StringValue("candidate"))))
      runtime_beam.tree_node_edit_view_on(
        actor,
        "A/_C",
        tree_types.DocumentCheckout,
        view,
        reference,
        node.SetField("label", tree_types.StringValue("node-candidate")),
      )
      |> expect.to_equal(Ok(Nil))
      process.send(begun, #(continue, reference))
      process.receive(continue, 1000) |> expect.to_equal(Ok(Nil))
      let read =
        runtime_beam.tree_node_read_view_on(
          actor,
          "A/_C",
          tree_types.DocumentCheckout,
          view,
          reference,
          ["label"],
        )
      let abort = runtime_beam.abort_tree_transaction(actor, "A/_C")
      process.send(owner_results, #(read, abort))
    })
  let #(continue, reference) = process.receive(begun, 1000) |> expect.to_be_ok()

  runtime_beam.tree_node_read_view_on(
    actor,
    "A/_C",
    tree_types.DocumentCheckout,
    view,
    reference,
    ["label"],
  )
  |> expect.to_equal(Error("tree transaction uses another caller"))
  runtime_beam.tree_node_edit_view_on(
    actor,
    "A/_C",
    tree_types.DocumentCheckout,
    view,
    reference,
    node.SetField("label", tree_types.StringValue("nonowner")),
  )
  |> expect.to_equal(Error("tree transaction uses another caller"))

  process.send(continue, Nil)
  process.receive(owner_results, 1000)
  |> expect.to_equal(
    Ok(#(Ok(Some(tree_types.StringValue("node-candidate"))), Ok(Nil))),
  )
  runtime_beam.tree_node_read_view_on(
    actor,
    "A/_C",
    tree_types.DocumentCheckout,
    view,
    reference,
    ["label"],
  )
  |> expect.to_equal(Ok(Some(tree_types.StringValue("first"))))
  stop_beam_actor(actor)
}

@target(erlang)
pub fn shared_tree_node_beam_stale_edit_preserves_runtime_effects_test() {
  let submissions = process.new_subject()
  let #(actor, _, view) = ready_beam_actor(submissions)
  let notifications = process.new_subject()
  process.send(
    actor,
    runtime_beam.Subscribe("A/_C", fn(event) {
      process.send(notifications, event)
    }),
  )
  let reference =
    runtime_beam.tree_node_reference_view_on(
      actor,
      "A/_C",
      tree_types.DocumentCheckout,
      view,
      ["left", "0"],
    )
    |> expect.to_be_ok()
    |> expect.to_be_some()
  runtime_beam.tree_edit_view(
    actor,
    "A/_C",
    view,
    tree_types.ArrayRemove(["left"], 0, 1),
  )
  |> expect.to_equal(Ok(Nil))
  process.receive(notifications, 1000) |> expect.to_be_ok()
  process.receive(submissions, 1000) |> expect.to_be_ok()

  let snapshot =
    runtime_beam.tree_retained_snapshot(actor, "A/_C")
    |> expect.to_be_ok()
  let assert runtime_core.TreeRetainedSnapshot(_, Some(snapshot_compressor)) =
    snapshot
  let compressor =
    fluid_ids.serialize(snapshot_compressor, True) |> expect.to_be_ok()
  let history =
    runtime_beam.tree_history_evidence(actor, "A/_C")
    |> expect.to_be_ok()

  runtime_beam.tree_node_edit_view_on(
    actor,
    "A/_C",
    tree_types.DocumentCheckout,
    view,
    reference,
    node.SetField("label", tree_types.StringValue("rejected")),
  )
  |> expect.to_be_error()
  let after_snapshot =
    runtime_beam.tree_retained_snapshot(actor, "A/_C")
    |> expect.to_be_ok()
  after_snapshot |> expect.to_equal(snapshot)
  let assert runtime_core.TreeRetainedSnapshot(_, Some(after_compressor)) =
    after_snapshot
  fluid_ids.serialize(after_compressor, True)
  |> expect.to_equal(Ok(compressor))
  runtime_beam.tree_history_evidence(actor, "A/_C")
  |> expect.to_equal(Ok(history))
  process.receive(notifications, 0) |> expect.to_equal(Error(Nil))
  process.receive(submissions, 0) |> expect.to_equal(Error(Nil))
  runtime_beam.tree_read_view_on(
    actor,
    "A/_C",
    tree_types.DocumentCheckout,
    view,
    ["left", "0", "label"],
  )
  |> expect.to_equal(Ok(Some(tree_types.StringValue("second"))))
  stop_beam_actor(actor)
}
