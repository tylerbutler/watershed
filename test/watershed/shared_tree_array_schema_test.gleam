import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{Some}
import gleam/string
import startest/expect
import watershed/json_ot
import watershed/tree/array_fixture
import watershed/tree/array_schema_fixture
import watershed/tree/change_fixture_codec as codec
import watershed/tree/codec/field_batch
import watershed/tree/fixtures
import watershed/tree/forest
import watershed/tree/schema
import watershed/tree/types
import watershed/wire

const items_type = "org.watershed.shared-tree.m3.Items"

const point_type = "org.watershed.shared-tree.m3.Point"

pub fn shared_tree_array_schema_decodes_sequence_node_test() -> Nil {
  let stored = array_fixture.stored("rootArray")
  schema.node_schema(stored, items_type)
  |> expect.to_equal(
    Ok(
      schema.Array(
        schema.FieldSchema(schema.Sequence, [
          "com.fluidframework.leaf.boolean",
          "com.fluidframework.leaf.null",
          "com.fluidframework.leaf.number",
          "com.fluidframework.leaf.string",
          "org.watershed.shared-tree.m3.ArrayMap",
          items_type,
          "org.watershed.shared-tree.m3.Point",
        ]),
      ),
    ),
  )
}

pub fn shared_tree_array_schema_validates_empty_and_ordered_elements_test() -> Nil {
  let stored = array_fixture.stored("rootArray")
  schema.validate_array_elements(stored, items_type, [])
  |> expect.to_equal(Ok(Nil))
  schema.validate_array_elements(stored, items_type, [
    types.StringValue("B"),
    types.StringValue("A"),
    types.StringValue("B"),
  ])
  |> expect.to_equal(Ok(Nil))
  schema.validate_array_elements(stored, items_type, [
    types.StringValue("string"),
    types.NumberValue(1.0),
    types.BooleanValue(True),
    types.NullValue,
    types.ObjectValue(point_type, [
      #("label", types.StringValue("point")),
      #("x", types.NumberValue(2.0)),
    ]),
    types.MapValue("org.watershed.shared-tree.m3.ArrayMap", []),
    types.ArrayValue(items_type, []),
  ])
  |> expect.to_equal(Ok(Nil))
  let _ =
    schema.validate_array_elements(stored, items_type, [
      types.ObjectValue("missing", []),
    ])
    |> expect.to_be_error
  Nil
}

pub fn shared_tree_array_schema_rejects_malformed_sequence_fields_test() -> Nil {
  let valid =
    array_fixture.stored("rootArray")
    |> schema.stored_to_json
    |> json.to_string
  [
    string.replace(
      valid,
      "\"root\":{\"kind\":\"Value\"",
      "\"root\":{\"kind\":\"Sequence\"",
    ),
    string.replace(
      valid,
      "\"\":{\"kind\":\"Sequence\"",
      "\"items\":{\"kind\":\"Sequence\"",
    ),
    "{\"version\":2,\"nodes\":{\"A\":{\"kind\":{\"object\":{\"\":{\"kind\":\"Sequence\",\"types\":[]},\"other\":{\"kind\":\"Optional\",\"types\":[]}}}}},\"root\":{\"kind\":\"Value\",\"types\":[\"A\"]}}",
  ]
  |> list.each(fn(raw) { schema.stored_from_string(raw) |> expect.to_be_error })
}

pub fn shared_tree_array_schema_matches_upstream_test() -> Nil {
  fixtures.assert_case("array-schema-content", array_schema_fixture.run)
}

pub fn shared_tree_array_schema_summary_uses_production_content_path_test() {
  let assert Ok(fixture) = fixtures.load("array-schema-content")
  let assert Ok(input) = codec.parse(fixture.input)
  let assert Ok(scenarios) = codec.field(input, "scenarios", codec.items)
  let assert Ok(summary) = scenarios |> list.drop(9) |> list.first
  let assert Ok(forest_bytes) = codec.field(summary, "forestBytes", codec.text)
  let assert Ok(encoded) =
    json.parse(forest_bytes, {
      use fields <- decode.field("fields", decode.dynamic)
      decode.success(fields)
    })
  let stored = array_fixture.stored("objectArrays")
  let assert Ok([[root]]) =
    field_batch.decode_with_schema(wire.dynamic_to_json(encoded), Some(stored))
  let assert Ok(state) = forest.new(array_fixture.view_id(), stored, Some(root))
  let assert Ok(Some(visible)) = forest.visible_root(state)
  let assert Ok(native_encoded) = field_batch.encode([[visible]])
  field_batch.decode_with_schema(native_encoded, Some(stored))
  |> expect.to_equal(Ok([[visible]]))
}

pub fn shared_tree_array_schema_compatible_move_is_explicitly_unsupported_test() {
  let assert Ok(fixture) = fixtures.load("array-schema-content")
  let raw = fixture.input |> json.to_string
  let mutated =
    raw
    |> string.replace("\"start\":0", "\"start\":1")
    |> string.replace("\"end\":1", "\"end\":2")
  let changed = mutated != raw
  changed |> expect.to_be_true
  let assert Ok(input) = json.parse(mutated, json_ot.decoder())
  let assert Error(detail) = array_schema_fixture.run(json_ot.to_json(input))
  string.contains(detail, "compatible array moves are unsupported")
  |> expect.to_be_true
}

pub fn shared_tree_array_schema_runner_rejects_bad_profile_test() -> Nil {
  let assert Ok(fixture) = fixtures.load("array-schema-content")
  let raw =
    fixture.input
    |> json.to_string
    |> string.replace("\"schema\":2", "\"schema\":99")
  let assert Ok(input) = json.parse(raw, json_ot.decoder())
  let _ = array_schema_fixture.run(json_ot.to_json(input)) |> expect.to_be_error
  Nil
}
