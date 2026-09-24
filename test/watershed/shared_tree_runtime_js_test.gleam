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
import watershed/sluice/frame
@target(javascript)
import watershed/summary_policy
@target(javascript)
import watershed/transport_js
@target(javascript)
import watershed/tree/fixtures
@target(javascript)
import watershed/tree/runtime_fixture
@target(javascript)
import watershed/tree/types as tree_types
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
  |> expect.to_equal(
    "suspended-pending-tree: pending tree reconnect and resubmission are not supported",
  )
  runtime.diagnostics(runtime).in_flight_count |> expect.to_equal(1)
  runtime.close(runtime)
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
  runtime.diagnostics(owner).in_flight_count |> expect.to_equal(1)
  callbacks.on_close()
  runtime.diagnostics(owner).phase
  |> expect.to_equal(
    "suspended-pending-tree: pending tree reconnect and resubmission are not supported",
  )
  runtime.diagnostics(owner).in_flight_count |> expect.to_equal(1)
  runtime.is_synced(owner) |> expect.to_equal(False)
  runtime.tree_read(owner, "A/_C", ["title"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("retained"))))
  runtime.tree_edit(
    owner,
    "A/_C",
    tree_types.SetField(["title"], tree_types.StringValue("lost")),
  )
  |> expect.to_equal(Error(
    "pending tree reconnect and resubmission are not supported",
  ))
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
  runtime.diagnostics(owner).phase
  |> string.starts_with("failed:")
  |> expect.to_equal(True)
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
