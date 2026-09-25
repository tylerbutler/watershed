import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import startest/expect
import watershed/tree/fixtures
import watershed/tree/schema
import watershed/tree/types.{
  BooleanValue, MapValue, NullValue, NumberValue, ObjectValue, StringValue,
}

const map_type = "org.watershed.shared-tree.m2.DynamicMap"

const named_map_type = "org.watershed.shared-tree.m2.NamedMap"

const point_type = "org.watershed.shared-tree.m2.Point"

fn map_schemas() -> #(String, String) {
  let assert Ok(fixture) = fixtures.load("map-schema-content")
  let assert Ok(schemas) =
    json.parse(json.to_string(fixture.input), {
      use schemas <- decode.field("schemas", {
        use named <- decode.field("named", decode.string)
        use recursive <- decode.field("recursive", decode.string)
        decode.success(#(named, recursive))
      })
      decode.success(schemas)
    })
  schemas
}

fn point() -> types.TreeValue {
  ObjectValue(point_type, [
    #("x", NumberValue(1.0)),
    #("y", NumberValue(2.0)),
  ])
}

fn map_root() -> types.TreeValue {
  MapValue(map_type, [
    #("", StringValue("")),
    #("2", NumberValue(2.0)),
    #("10", BooleanValue(True)),
    #("01", NullValue),
    #("__proto__", point()),
    #("é", MapValue(map_type, [#("nested", StringValue("value"))])),
    #("水", StringValue("水")),
  ])
}

fn compatible(stored: String, view: String) -> Result(Nil, types.TreeError) {
  let assert Ok(stored) = schema.stored_from_string(stored)
  let assert Ok(view) = schema.view_from_string(view)
  schema.can_view(stored, view)
}

pub fn shared_tree_map_schema_exposes_explicit_map_edits_test() -> Nil {
  let set = types.MapSet(["items"], "", StringValue("value"))
  let delete = types.MapDelete(["items"], "__proto__")
  let assert types.MapSet(["items"], "", StringValue("value")) = set
  let assert types.MapDelete(["items"], "__proto__") = delete
  Nil
}

pub fn shared_tree_map_schema_validates_map_entries_test() -> Nil {
  let #(_, map_schema) = map_schemas()
  let assert Ok(stored) = schema.stored_from_string(map_schema)
  [
    #("string", StringValue("value")),
    #("number", NumberValue(2.0)),
    #("object", point()),
    #("map", MapValue(map_type, [#("nested", StringValue("value"))])),
  ]
  |> list.each(fn(entry) {
    schema.validate_map_entry(stored, map_type, entry.0, Some(entry.1))
    |> expect.to_equal(Ok(Nil))
  })
  schema.validate_map_entry(stored, map_type, "deleted", None)
  |> expect.to_equal(Ok(Nil))
}

pub fn shared_tree_map_schema_rejects_invalid_map_entries_test() -> Nil {
  let #(_, map_schema) = map_schemas()
  let assert Ok(stored) = schema.stored_from_string(map_schema)
  schema.validate_map_entry(
    stored,
    map_type,
    "blocked",
    Some(ObjectValue(named_map_type, [])),
  )
  |> expect.to_equal(
    Error(types.InvalidEdit(
      ["blocked"],
      "node type is not allowed: " <> named_map_type,
    )),
  )
  schema.validate_map_entry(stored, "missing", "key", None)
  |> expect.to_equal(
    Error(types.InvalidEdit([], "unknown map schema: missing")),
  )
  schema.validate_map_entry(stored, point_type, "key", None)
  |> expect.to_equal(
    Error(types.InvalidEdit([], "node schema is not a map: " <> point_type)),
  )
}

pub fn shared_tree_map_schema_starts_entry_errors_at_map_keys_test() -> Nil {
  let #(_, map_schema) = map_schemas()
  let assert Ok(stored) = schema.stored_from_string(map_schema)
  ["", "__proto__", "é", "水"]
  |> list.each(fn(key) {
    schema.validate_map_entry(
      stored,
      map_type,
      key,
      Some(ObjectValue(named_map_type, [])),
    )
    |> expect.to_equal(
      Error(types.InvalidEdit(
        [key],
        "node type is not allowed: " <> named_map_type,
      )),
    )
  })
}

pub fn shared_tree_map_schema_decodes_named_and_recursive_maps_test() -> Nil {
  let #(named_map_schema, map_schema) = map_schemas()
  let assert Ok(named) = schema.stored_from_string(named_map_schema)
  schema.validate_root(
    named,
    MapValue(named_map_type, [
      #("", BooleanValue(False)),
      #("point", point()),
    ]),
  )
  |> expect.to_equal(Ok(Nil))

  let assert Ok(stored) = schema.stored_from_string(map_schema)
  schema.validate_root(stored, map_root()) |> expect.to_equal(Ok(Nil))
}

pub fn shared_tree_map_schema_rejects_duplicate_entries_test() -> Nil {
  let #(_, map_schema) = map_schemas()
  let assert Ok(stored) = schema.stored_from_string(map_schema)
  let assert Error(types.InvalidEdit(["same"], "duplicate map key")) =
    schema.validate_root(
      stored,
      MapValue(map_type, [
        #("same", ObjectValue("missing", [])),
        #("same", NullValue),
      ]),
    )
  schema.validate_root(
    stored,
    MapValue(map_type, [
      #("same", StringValue("first")),
      #("same", StringValue("second")),
    ]),
  )
  |> expect.to_be_error
  Nil
}

pub fn shared_tree_map_schema_rejects_invalid_entry_schema_test() -> Nil {
  let #(_, map_schema) = map_schemas()
  [
    string.replace(
      map_schema,
      "\"map\":{\"kind\":\"Optional\"",
      "\"map\":{\"kind\":\"Sequence\"",
    ),
    string.replace(
      map_schema,
      "\"org.watershed.shared-tree.m2.DynamicMap\",\"org.watershed.shared-tree.m2.Point\"]}}}",
      "\"org.watershed.shared-tree.m2.DynamicMap\",\"missing\"]}}}",
    ),
  ]
  |> list.each(fn(invalid) {
    schema.stored_from_string(invalid) |> expect.to_be_error
  })
}

pub fn shared_tree_map_schema_compares_entry_views_test() -> Nil {
  let #(_, map_schema) = map_schemas()
  let changed_map_value_types =
    string.replace(
      map_schema,
      "\"com.fluidframework.leaf.string\",\"org.watershed.shared-tree.m2.DynamicMap\"",
      "\"org.watershed.shared-tree.m2.DynamicMap\"",
    )
  compatible(map_schema, changed_map_value_types) |> expect.to_be_error
  Nil
}

pub fn shared_tree_map_schema_reports_entry_lookup_errors_test() -> Nil {
  let #(_, map_schema) = map_schemas()
  let assert Ok(stored) = schema.stored_from_string(map_schema)
  schema.map_entry_schema(stored, map_type)
  |> expect.to_equal(
    Ok(
      schema.FieldSchema(schema.Optional, [
        "com.fluidframework.leaf.boolean",
        "com.fluidframework.leaf.null",
        "com.fluidframework.leaf.number",
        "com.fluidframework.leaf.string",
        map_type,
        point_type,
      ]),
    ),
  )
  schema.map_entry_schema(stored, point_type)
  |> expect.to_equal(
    Error(types.InvalidEdit([], "node schema is not a map: " <> point_type)),
  )
  schema.map_entry_schema(stored, "missing")
  |> expect.to_equal(
    Error(types.InvalidEdit([], "unknown map schema: missing")),
  )
}

pub fn shared_tree_map_schema_rejects_wrong_node_value_kinds_test() -> Nil {
  let #(_, map_schema) = map_schemas()
  let assert Ok(stored) = schema.stored_from_string(map_schema)
  schema.validate_root(stored, ObjectValue(map_type, []))
  |> expect.to_be_error
  schema.validate_subtree(stored, MapValue(point_type, []))
  |> expect.to_be_error
  schema.validate_subtree(
    stored,
    MapValue("com.fluidframework.leaf.string", []),
  )
  |> expect.to_be_error
  Nil
}
