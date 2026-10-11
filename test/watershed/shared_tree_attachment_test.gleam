import gleam/dict
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import startest/expect
import watershed/channel
import watershed/fluid_ids
import watershed/handle
import watershed/runtime_core
import watershed/tree/lifecycle_fixture
import watershed/tree/runtime_fixture
import watershed/wire/fluid_container
import watershed/wire/op as wire_op

pub fn shared_tree_cross_datastore_map_attachment_test() {
  lifecycle_fixture.assert_scenario(
    "cross-datastore-attachment",
    "map-cross-datastore",
  )
}

pub fn shared_tree_cross_datastore_map_cycle_test() {
  lifecycle_fixture.assert_scenario("cross-datastore-attachment", "map-cycle")
}

pub fn shared_tree_attachment_refuses_unknown_final_dependency_atomically_test() {
  let core = attachment_core()
  let assert Ok(core) = runtime_core.create_detached_data_store(core, "D")
  let before = fingerprint(core)
  let assert Ok(valid) = handle.reference_from_path("/D/root")
  let assert Ok(missing) = handle.reference_from_path("/missing/root")

  let assert Error(_) =
    runtime_core.prepare_attachments(core, "A/root", [valid, missing])
  fingerprint(core) |> expect.to_equal(before)
}

pub fn shared_tree_attachment_refuses_malformed_last_marker_atomically_test() {
  let core = attachment_core()
  let assert Ok(core) = runtime_core.create_detached_data_store(core, "D")
  let before = fingerprint(core)
  let value =
    json.object([
      #("valid", handle.encode_handle("D/root")),
      #(
        "late",
        json.object([
          #("type", json.string("__fluid_handle__")),
          #("url", json.int(1)),
        ]),
      ),
    ])

  let assert Error(_) = runtime_core.set(core, "A/root", "bad", value)
  fingerprint(core) |> expect.to_equal(before)
}

pub fn shared_tree_attachment_refuses_duplicate_identities_atomically_test() {
  let core = attachment_core()
  let assert Ok(core) = runtime_core.create_detached_data_store(core, "D")
  let before = fingerprint(core)

  let assert Error(_) = runtime_core.create_detached_data_store(core, "D")
  let assert Error(_) = runtime_core.new_channel_address_in(core, "D", "root")
  let assert Error(_) = runtime_core.new_channel_address_in(core, "A", "root")
  fingerprint(core) |> expect.to_equal(before)
}

pub fn shared_tree_attachment_refuses_unsupported_package_identity_test() {
  wire_op.encode_datastore_attach(
    "D",
    ["unsupported"],
    [#("root", channel.MapSnapshot([]))],
    [],
  )
  |> expect.to_equal(
    Error(fluid_container.UnsupportedMessage(
      "unsupported declared datastore package",
    )),
  )
}

pub fn shared_tree_attachment_scopes_new_channel_addresses_test() {
  let core = attachment_core()
  let assert Ok(core) = runtime_core.create_detached_data_store(core, "D")
  runtime_core.new_channel_address_in(core, "D", "child")
  |> expect.to_equal(Ok("D/child"))
  let assert Error(_) =
    runtime_core.new_channel_address_in(core, "missing", "child")
  Nil
}

pub fn shared_tree_attachment_reconnect_resubmits_prepared_graph_test() {
  let core = attachment_core()
  let assert Ok(core) = runtime_core.create_detached_data_store(core, "D")
  let assert Ok(#(core, _, [_])) =
    runtime_core.set(
      core,
      "A/root",
      "secondary",
      handle.encode_handle("D/root"),
    )
  let assert Ok(core) =
    runtime_core.adopt_reconnect(
      core,
      runtime_fixture.connected(
        "reconnected",
        [],
        core.last_seen_sequence_number,
      ),
    )
  let assert Ok(#(core, [outbound])) = runtime_core.resubmit(core)
  let assert Ok(batch) =
    fluid_container.decode(outbound.contents, outbound.metadata)
  list.length(batch.messages) |> expect.to_equal(3)
  list.length(core.in_flight) |> expect.to_equal(1)
}

pub fn shared_tree_attachment_retains_serialized_removed_binding_test() {
  let core = attachment_core()
  let assert Ok(core) = runtime_core.create_detached_data_store(core, "D")
  let assert Ok(core) = runtime_core.create_detached_data_store(core, "F")
  let assert Ok(#(core, _, [])) =
    runtime_core.set(core, "D/root", "right", handle.encode_handle("F/root"))
  let assert Ok(#(core, _, [_])) =
    runtime_core.set(core, "A/root", "left", handle.encode_handle("D/root"))
  let assert Ok(#(core, _, [_])) = runtime_core.delete(core, "D/root", "right")
  runtime_core.entries(core, "D/root") |> expect.to_equal([])
  runtime_core.has_channel(core, "F/root") |> expect.to_be_true()
  let assert Ok(references) = dict.get(core.bindings, "D/root")
  list.map(references, handle.reference_path)
  |> expect.to_equal(["/F/root"])
}

type Fingerprint {
  Fingerprint(
    next_csn: Int,
    in_flight: Int,
    channels: List(String),
    detached: List(String),
    datastores: List(String),
    local_datastores: List(String),
    compressor: String,
  )
}

fn attachment_core() -> runtime_core.Core {
  runtime_fixture.routed_core() |> expect.to_be_ok()
}

fn fingerprint(core: runtime_core.Core) -> Fingerprint {
  let compressor = case core.compressor {
    Some(compressor) ->
      fluid_ids.serialize(compressor, True)
      |> result.map(json.to_string)
      |> result.unwrap("")
    None -> ""
  }
  Fingerprint(
    core.next_client_sequence_number,
    list.length(core.in_flight),
    dict.keys(core.channels) |> list.sort(string.compare),
    dict.keys(core.detached) |> list.sort(string.compare),
    dict.keys(core.routing.datastores) |> list.sort(string.compare),
    dict.keys(core.local_datastores) |> list.sort(string.compare),
    compressor,
  )
}
