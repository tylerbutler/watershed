import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import startest/expect
import watershed/fluid_ids
import watershed/handle
import watershed/json_ot.{type JsonValue, VArray, VNull, VObject, VString}
import watershed/tree/change
import watershed/tree/codec
import watershed/tree/codec/field_batch
import watershed/tree/codec/summary
import watershed/tree/fixtures
import watershed/tree/forest
import watershed/tree/history
import watershed/tree/schema
import watershed/tree/shared_change
import watershed/tree/types
import watershed/tree_kernel

const handle_schema = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.handle\":{\"kind\":{\"leaf\":3}}},\"root\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.handle\"]}}"

const string_schema = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}}},\"root\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.string\"]}}"

pub fn shared_tree_handle_leaf_schema_and_field_batch_test() {
  let assert Ok(stored) = schema.stored_from_string(handle_schema)
  let assert Ok(reference) = handle.reference_from_path("/B/child")
  let value = types.HandleValue(reference)
  schema.validate_root(stored, value) |> expect.to_equal(Ok(Nil))
  schema.validate_root(stored, types.StringValue("/B/child"))
  |> expect.to_be_error()
  let assert Ok(encoded) =
    field_batch.encode_with_schema([[value]], Some(stored))
  field_batch.decode_with_schema(encoded, Some(stored))
  |> expect.to_equal(Ok([[value]]))
}

pub fn shared_tree_reference_normalizes_serialized_paths_test() {
  let absolute =
    json.object([
      #("type", json.string(handle.fluid_handle_type)),
      #("url", json.string("/B/child")),
    ])
  let relative =
    json.object([
      #("type", json.string(handle.fluid_handle_type)),
      #("url", json.string("_C")),
    ])
  let assert Ok(reference) = handle.reference_from_json(absolute, "/A")
  handle.reference_path(reference) |> expect.to_equal("/B/child")
  handle.reference_to_json(reference) |> expect.to_equal(absolute)

  let assert Ok(from_a) = handle.reference_from_json(relative, "/A")
  let assert Ok(from_b) = handle.reference_from_json(relative, "/B")
  handle.reference_path(from_a) |> expect.to_equal("/A/_C")
  handle.reference_path(from_b) |> expect.to_equal("/B/_C")

  let assert Ok(equivalent) = handle.reference_from_path("/B/child")
  equivalent |> expect.to_equal(reference)
  let assert Ok(escaped) = handle.reference_from_path("/A/space%20and%23hash")
  handle.reference_path(escaped)
  |> expect.to_equal("/A/space%20and%23hash")
}

pub fn shared_tree_reference_rejects_invalid_paths_test() {
  [
    "https://example.com/B/child",
    "/B/../child",
    "/B/%GG",
    "//B/child",
    "/B",
    "/",
  ]
  |> list.each(fn(path) {
    let assert Error(handle.InvalidHandle(_)) = handle.reference_from_path(path)
  })

  let pending =
    json.object([
      #("type", json.string(handle.fluid_handle_type)),
      #("url", json.string("/B/child")),
      #("payloadPending", json.bool(True)),
    ])
  handle.reference_from_json(pending, "/A")
  |> expect.to_equal(Error(handle.UnsupportedHandle("pending handle payload")))
}

pub fn shared_tree_bind_serialized_references_normalizes_nested_markers_test() {
  let payload =
    json.object([
      #(
        "nested",
        json.array(
          [
            json.string("before"),
            json.object([
              #("type", json.string(handle.fluid_handle_type)),
              #("url", json.string("_C")),
            ]),
          ],
          fn(value) { value },
        ),
      ),
    ])
  let expected =
    json.object([
      #(
        "nested",
        json.array(
          [
            json.string("before"),
            json.object([
              #("type", json.string(handle.fluid_handle_type)),
              #("url", json.string("/A/_C")),
            ]),
          ],
          fn(value) { value },
        ),
      ),
    ])
  handle.bind_serialized_references(payload, "/A")
  |> expect.to_equal(Ok(expected))
}

pub fn shared_tree_bind_serialized_references_rejects_late_malformed_marker_test() {
  let payload =
    json.array(
      [
        json.string("before"),
        json.object([
          #("type", json.string(handle.fluid_handle_type)),
          #("url", json.int(1)),
        ]),
      ],
      fn(value) { value },
    )
  handle.bind_serialized_references(payload, "/A")
  |> expect.to_equal(Error(handle.InvalidHandle("invalid handle marker")))
}

pub fn shared_tree_bind_serialized_references_preserves_unknown_markers_test() {
  let value =
    json.object([
      #("type", json.string("__fluid_handle_v3__")),
      #("url", json.string("/unsupported")),
    ])
  handle.bind_serialized_references(value, "/A")
  |> expect.to_equal(Ok(value))
  handle.reference_from_json(value, "/A")
  |> expect.to_equal(Error(handle.InvalidHandle("invalid handle marker")))
}

pub fn shared_tree_field_batch_requires_context_for_relative_handles_test() {
  let assert Ok(reference) = handle.reference_from_path("/B/child")
  let assert Ok(encoded) = field_batch.encode([[types.HandleValue(reference)]])
  let relative =
    encoded
    |> json.to_string
    |> string.replace("/B/child", "_C")
  let assert Ok(relative) = json_ot.parse_json(relative)
  field_batch.decode(json_ot.to_json(relative))
  |> expect.to_equal(
    Error(types.CorruptData(
      "fieldBatch.data[0][0]",
      "relative handle requires source-channel context",
    )),
  )
}

pub fn shared_tree_handle_fixture_tagged_value_round_trip_test() {
  let assert Ok(fixtures.Case(input: input, ..)) =
    fixtures.load("handle-leaves")
  let assert Ok(root) = json_ot.parse_json(json.to_string(input))
  let assert Ok(scenario) = scenario(root, "required-root")
  let assert Ok(input) = field(scenario, "input")
  let assert Ok(tagged) = field(input, "taggedValue")
  let tagged = json_ot.to_json(tagged)
  let assert Ok(value) =
    json.parse(json.to_string(tagged), fixtures.tree_value_decoder())
  let assert types.HandleValue(reference) = value
  handle.reference_path(reference) |> expect.to_equal("/B/child")
  fixtures.tree_value_to_json(value) |> expect.to_equal(tagged)
}

pub fn shared_tree_handle_fixture_uncompressed_field_batch_replay_test() {
  let assert Ok(#(stored, payload)) = fixture_codec("uncompressed-v2")
  let assert Ok(reference) = handle.reference_from_path("/B/child")
  let expected = [[types.HandleValue(reference)]]
  field_batch.decode_with_schema(payload, Some(stored))
  |> expect.to_equal(Ok(expected))
  let assert Ok(encoded) =
    field_batch.encode_with_context(expected, Some(stored), summary_ids())
  fixtures.first_difference(encoded, payload) |> expect.to_equal(Ok(Nil))
}

pub fn shared_tree_handle_fixture_schema_aware_field_batch_replay_test() {
  let assert Ok(#(stored, payload)) = fixture_codec("schema-aware-v2")
  let assert Ok(reference) = handle.reference_from_path("/B/child")
  let handle = types.HandleValue(reference)
  let expected = [
    [
      types.ObjectValue("org.watershed.shared-tree.handles.Root", [
        #("label", types.StringValue("leaf-codec")),
        #("link", handle),
        #(
          "links",
          types.MapValue("org.watershed.shared-tree.handles.Links", [
            #("target", handle),
          ]),
        ),
        #(
          "sequence",
          types.ArrayValue("org.watershed.shared-tree.handles.Sequence", [
            handle,
          ]),
        ),
      ]),
    ],
  ]
  field_batch.decode_with_schema(payload, Some(stored))
  |> expect.to_equal(Ok(expected))
  let assert Ok(encoded) =
    field_batch.encode_with_context(expected, Some(stored), summary_ids())
  fixtures.first_difference(encoded, payload) |> expect.to_equal(Ok(Nil))
}

pub fn shared_tree_handle_forest_and_repair_summary_round_trip_test() {
  let assert Ok(stored) = schema.stored_from_string(handle_schema)
  let assert Ok(reference) = handle.reference_from_path("/B/child")
  let value = types.HandleValue(reference)
  let assert Ok(view_id) =
    fluid_ids.stable_id("00000000-0000-4000-8000-000000000001")
  let assert Ok(state) = forest.new(view_id, stored, Some(value))
  forest.visible_root(state) |> expect.to_equal(Ok(Some(value)))
  let assert Ok(data) = forest.export_data(state)
  let assert Ok(imported) = forest.import_data(view_id, stored, data)
  forest.visible_root(imported) |> expect.to_equal(Ok(Some(value)))

  let forest_summary =
    summary.ForestSummary([
      #("rootFieldKey", [value]),
      #("repair-0", [value]),
    ])
  let assert Ok(encoded) = summary.encode_forest(forest_summary)
  summary.decode_forest_with_schema(encoded, stored)
  |> expect.to_equal(Ok(forest_summary))
}

pub fn shared_tree_handle_schema_compatibility_is_distinct_from_string_test() {
  let assert Ok(handle_stored) = schema.stored_from_string(handle_schema)
  let assert Ok(handle_view) = schema.view_from_string(handle_schema)
  let assert Ok(string_stored) = schema.stored_from_string(string_schema)
  let assert Ok(string_view) = schema.view_from_string(string_schema)
  schema.compatibility(handle_stored, handle_view)
  |> expect.to_equal(Ok(schema.Compatibility(True, True, True)))
  schema.compatibility(handle_stored, string_view)
  |> expect.to_equal(Ok(schema.Compatibility(False, False, False)))
  schema.compatibility(string_stored, handle_view)
  |> expect.to_equal(Ok(schema.Compatibility(False, False, False)))
}

pub fn shared_tree_field_batch_refuses_malformed_handle_leaves_test() {
  let assert Ok(stored) = schema.stored_from_string(handle_schema)
  [
    #(
      "{\"type\":\"__fluid_handle__\",\"url\":1}",
      types.CorruptData("fieldBatch.data[0][0]", "invalid handle marker"),
    ),
    #(
      "{\"type\":\"__fluid_handle__\",\"url\":\"/B/child\",\"payloadPending\":true}",
      types.CorruptData("fieldBatch.data[0][0]", "pending handle payload"),
    ),
  ]
  |> list.each(fn(entry) {
    field_batch.decode_with_schema(handle_batch(entry.0), Some(stored))
    |> expect.to_equal(Error(entry.1))
  })
}

pub fn shared_tree_field_batch_refuses_handle_under_wrong_schema_test() {
  let assert Ok(stored) = schema.stored_from_string(string_schema)
  field_batch.decode_with_schema(
    handle_batch("{\"type\":\"__fluid_handle__\",\"url\":\"/B/child\"}"),
    Some(stored),
  )
  |> expect.to_equal(
    Error(types.CorruptData(
      "fieldBatch.data[0][0]",
      "handle leaf is not declared by the stored schema",
    )),
  )
}

pub fn shared_tree_handle_fixture_executes_all_leaf_edits_test() {
  let assert Ok(#(required, handle)) = fixture_state("required-root")
  tree_kernel.read(required, []) |> expect.to_equal(Ok(Some(handle)))

  let assert Ok(#(optional, handle)) = fixture_state("optional-root")
  let assert Ok(#(optional, _, _)) =
    tree_kernel.apply_local(
      optional,
      revision(),
      identity_order(),
      types.SetField([], handle),
    )
  tree_kernel.read(optional, []) |> expect.to_equal(Ok(Some(handle)))
  let assert Ok(#(optional, _, _)) =
    tree_kernel.apply_local(
      optional,
      second_revision(),
      identity_order(),
      types.ClearField([]),
    )
  tree_kernel.read(optional, []) |> expect.to_equal(Ok(None))

  let assert Ok(#(object, handle)) = fixture_state("object-field")
  let assert Ok(#(object, _, _)) =
    tree_kernel.apply_local(
      object,
      revision(),
      identity_order(),
      types.SetField(["link"], handle),
    )
  tree_kernel.read(object, ["link"]) |> expect.to_equal(Ok(Some(handle)))

  let assert Ok(#(map, handle)) = fixture_state("map-entry")
  let assert Ok(#(map, _, _)) =
    tree_kernel.apply_local(
      map,
      revision(),
      identity_order(),
      types.MapSet(["links"], "target", handle),
    )
  tree_kernel.map_get(map, ["links"], "target")
  |> expect.to_equal(Ok(Some(handle)))

  let assert Ok(#(array, handle)) = fixture_state("array-element")
  let assert Ok(#(array, _, _)) =
    tree_kernel.apply_local(
      array,
      revision(),
      identity_order(),
      types.ArrayInsert(["sequence"], 0, [handle]),
    )
  tree_kernel.array_values(array, ["sequence"])
  |> expect.to_equal(Ok([handle]))
}

pub fn shared_tree_handle_build_and_refresher_codec_round_trip_test() {
  let owner = session()
  let assert Ok(#(compressor, local)) =
    fluid_ids.new(owner) |> fluid_ids.generate
  let assert #(compressor, Some(range)) =
    fluid_ids.take_creation_range(compressor)
  let assert Ok(compressor) = fluid_ids.finalize(compressor, range)
  let assert Ok(revision) = fluid_ids.decompress(compressor, local)
  let assert Ok(stored) = schema.stored_from_string(handle_schema)
  let assert Ok(reference) = handle.reference_from_path("/B/child")
  let value = types.HandleValue(reference)
  let build = forest.Build(types.AtomId(Some(revision), 0), [value])
  let refresher = forest.Build(types.AtomId(Some(revision), 1), [value])
  let assert Ok(order) = change.identity_order([#(revision, 0)])
  let assert Ok(changeset) =
    change.from_data(
      change.ChangeData(
        max_local_id: 1,
        revisions: [change.RevisionInfo(revision, None)],
        fields: [],
        nodes: [],
        parents: [],
        aliases: [],
        builds: [build],
        destroys: [],
        refreshers: [refresher],
        cross_field_keys: [],
        constraint_violation_count: 0,
      ),
      order,
    )
  let encode_context =
    codec.EncodeContext(codec.Fluid310, compressor, Some(stored))
  let decode_context = codec.DecodeContext(codec.Fluid310, compressor)
  let change_context = codec.ChangeContext(owner, Some(revision), codec.Message)
  let assert Ok(encoded) =
    codec.encode_modular(changeset, encode_context, change_context)
  let assert Ok(decoded) =
    codec.decode_modular_with_schema(
      encoded,
      decode_context,
      change_context,
      stored,
    )
  let decoded = change.to_data(decoded)
  decoded.builds |> expect.to_equal([build])
  decoded.refreshers |> expect.to_equal([refresher])
}

pub fn shared_tree_handle_edit_manager_history_round_trip_test() {
  let owner = session()
  let assert Ok(#(compressor, local)) =
    fluid_ids.new(owner) |> fluid_ids.generate
  let assert #(compressor, Some(range)) =
    fluid_ids.take_creation_range(compressor)
  let assert Ok(compressor) = fluid_ids.finalize(compressor, range)
  let assert Ok(revision) = fluid_ids.decompress(compressor, local)
  let assert Ok(stored) = schema.stored_from_string(handle_schema)
  let assert Ok(reference) = handle.reference_from_path("/B/child")
  let value = types.HandleValue(reference)
  let build = forest.Build(types.AtomId(Some(revision), 0), [value])
  let assert Ok(order) = change.identity_order([#(revision, 0)])
  let assert Ok(changeset) =
    change.from_data(
      change.ChangeData(
        max_local_id: 0,
        revisions: [change.RevisionInfo(revision, None)],
        fields: [],
        nodes: [],
        parents: [],
        aliases: [],
        builds: [build],
        destroys: [],
        refreshers: [],
        cross_field_keys: [],
        constraint_violation_count: 0,
      ),
      order,
    )
  let commit =
    summary.SummaryCommit(
      codec.WireCommit(
        revision,
        owner,
        [shared_change.DataChange(changeset)],
        None,
      ),
      Some(1),
      None,
    )
  let history = summary.EditManagerSummary([commit], [])
  let assert Ok(encoded) =
    summary.encode_edit_manager(
      history,
      codec.EncodeContext(codec.Fluid310, compressor, Some(stored)),
    )
  let assert Ok(summary.EditManagerSummary(
    [
      summary.SummaryCommit(
        codec.WireCommit(changes: [shared_change.DataChange(decoded)], ..),
        Some(1),
        None,
      ),
    ],
    [],
  )) =
    summary.decode_edit_manager_with_schema(
      encoded,
      codec.DecodeContext(codec.Fluid310, compressor),
      stored,
    )
  change.to_data(decoded).builds |> expect.to_equal([build])
}

fn fixture_codec(id: String) -> Result(#(schema.StoredSchema, json.Json), Nil) {
  let assert Ok(fixtures.Case(input: input, ..)) =
    fixtures.load("handle-leaves")
  use root <- result.try(
    json_ot.parse_json(json.to_string(input))
    |> result.replace_error(Nil),
  )
  use scenario <- result.try(scenario(root, id))
  use codec <- result.try(field(scenario, "codec"))
  use stored <- result.try(field(codec, "storedSchema"))
  use payload <- result.try(field(codec, "payload"))
  use stored <- result.try(
    schema.stored_from_string(json.to_string(json_ot.to_json(stored)))
    |> result.replace_error(Nil),
  )
  Ok(#(stored, json_ot.to_json(payload)))
}

fn scenario(root: JsonValue, id: String) -> Result(JsonValue, Nil) {
  use scenarios <- result.try(field(root, "scenarios"))
  let assert VArray(scenarios) = scenarios
  list.find(scenarios, fn(value) { field(value, "id") == Ok(VString(id)) })
}

fn field(value: JsonValue, name: String) -> Result(JsonValue, Nil) {
  case value {
    VObject(fields) -> list.key_find(fields, name)
    _ -> Error(Nil)
  }
}

fn summary_ids() -> field_batch.IdContext {
  let assert Ok(session) =
    fluid_ids.session_id("00000000-0000-4000-8000-000000000001")
  field_batch.SummaryIds(fluid_ids.new(session))
}

fn fixture_state(
  id: String,
) -> Result(#(tree_kernel.TreeState, types.TreeValue), Nil) {
  let assert Ok(fixtures.Case(input: input, ..)) =
    fixtures.load("handle-leaves")
  use root <- result.try(
    json_ot.parse_json(json.to_string(input))
    |> result.replace_error(Nil),
  )
  use scenario <- result.try(scenario(root, id))
  use input <- result.try(field(scenario, "input"))
  use stored_json <- result.try(field(input, "storedSchema"))
  let raw = json.to_string(json_ot.to_json(stored_json))
  use stored <- result.try(
    schema.stored_from_string(raw) |> result.replace_error(Nil),
  )
  use view <- result.try(
    schema.view_from_string(raw) |> result.replace_error(Nil),
  )
  use tagged <- result.try(field(input, "taggedValue"))
  use handle <- result.try(decode_fixture_value(tagged))
  use initial <- result.try(field(input, "initialRoot"))
  use initial <- result.try(case initial {
    VNull if id == "required-root" -> Ok(Some(handle))
    VNull -> Ok(None)
    value -> decode_fixture_value(value) |> result.map(Some)
  })
  let initial_history = history.inspect(history.new(session())).sequenced
  use snapshot <- result.try(
    tree_kernel.snapshot_from_parts(
      view_id(),
      stored,
      forest.ForestData(initial, [], 0),
      initial_history,
    )
    |> result.replace_error(Nil),
  )
  tree_kernel.restore(snapshot, view_id(), session(), view)
  |> result.map(fn(state) { #(state, handle) })
  |> result.replace_error(Nil)
}

fn decode_fixture_value(value: JsonValue) -> Result(types.TreeValue, Nil) {
  json.parse(
    json.to_string(json_ot.to_json(value)),
    fixtures.tree_value_decoder(),
  )
  |> result.replace_error(Nil)
}

fn session() -> fluid_ids.SessionId {
  let assert Ok(value) =
    fluid_ids.session_id("00000000-0000-4000-8000-000000000001")
  value
}

fn view_id() -> fluid_ids.StableId {
  let assert Ok(value) =
    fluid_ids.stable_id("00000000-0000-4000-8000-000000000002")
  value
}

fn revision() -> fluid_ids.StableId {
  let assert Ok(value) =
    fluid_ids.stable_id("00000000-0000-4000-8000-000000000003")
  value
}

fn second_revision() -> fluid_ids.StableId {
  let assert Ok(value) =
    fluid_ids.stable_id("00000000-0000-4000-8000-000000000004")
  value
}

fn identity_order() -> change.IdentityOrder {
  let assert Ok(value) =
    change.identity_order([
      #(revision(), -2),
      #(second_revision(), -1),
    ])
  value
}

fn handle_batch(marker: String) -> json.Json {
  let raw =
    "{\"version\":2,\"identifiers\":[],\"shapes\":[{\"c\":{\"type\":\"com.fluidframework.leaf.handle\",\"value\":true}}],\"data\":[[0,"
    <> marker
    <> "]]}"
  let assert Ok(value) = json_ot.parse_json(raw)
  json_ot.to_json(value)
}
