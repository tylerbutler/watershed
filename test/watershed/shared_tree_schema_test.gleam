import gleam/json
import gleam/list
import gleam/string
import startest/expect
import watershed/tree/schema
import watershed/tree/types

const string_schema = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}}},\"root\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.string\"]}}"

const object_schema = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}},\"Point\":{\"kind\":{\"object\":{\"x\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.string\"]}}}},\"Root\":{\"kind\":{\"object\":{\"point\":{\"kind\":\"Value\",\"types\":[\"Point\"]},\"note\":{\"kind\":\"Optional\",\"types\":[\"com.fluidframework.leaf.string\"]}}}}},\"root\":{\"kind\":\"Value\",\"types\":[\"Root\"]}}"

fn corrupt(raw: String) {
  let assert Error(types.CorruptData(location, detail)) =
    schema.stored_from_string(raw)
  string.is_empty(location) |> expect.to_be_false
  string.is_empty(detail) |> expect.to_be_false
}

pub fn shared_tree_schema_decodes_supported_schema_test() {
  schema.stored_from_string(string_schema) |> expect.to_be_ok
  schema.view_from_string(object_schema) |> expect.to_be_ok
  Nil
}

pub fn shared_tree_schema_refuses_versions_on_both_boundaries_test() {
  let raw = string.replace(string_schema, "\"version\":2", "\"version\":99")
  schema.stored_from_string(raw)
  |> expect.to_equal(Error(types.UnsupportedFormat("Schema", "99")))
  schema.view_from_string(raw)
  |> expect.to_equal(Error(types.UnsupportedFormat("Schema", "99")))
}

pub fn shared_tree_schema_rejects_malformed_shapes_test() {
  [
    "{",
    "null",
    "[]",
    "{}",
    string.replace(string_schema, "\"version\":2", "\"version\":\"2\""),
    string.replace(string_schema, "\"leaf\":1", "\"leaf\":\"string\""),
    string.replace(string_schema, "\"kind\":{\"leaf\":1}", "\"kind\":{}"),
    string.replace(
      string_schema,
      "\"kind\":{\"leaf\":1}",
      "\"kind\":{\"leaf\":1,\"object\":{}}",
    ),
    string.replace(string_schema, "\"types\":[", "\"types\":null,\"other\":["),
    string.replace(
      string_schema,
      "\"kind\":{\"leaf\":1}",
      "\"kind\":{\"leaf\":1},\"metadata\":null",
    ),
  ]
  |> list.each(corrupt)
}

pub fn shared_tree_schema_rejects_duplicate_declarations_test() {
  [
    string.replace(
      string_schema,
      "\"version\":2",
      "\"version\":2,\"version\":2",
    ),
    string.replace(
      string_schema,
      "\"nodes\":{",
      "\"nodes\":{\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}},",
    ),
    string.replace(
      object_schema,
      "\"x\":{",
      "\"x\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.string\"]},\"\\u0078\":{",
    ),
    string.replace(string_schema, "\"leaf\":1", "\"leaf\":1,\"le\\u0061f\":1"),
  ]
  |> list.each(fn(raw) {
    let assert Error(types.CorruptData(_, detail)) =
      schema.stored_from_string(raw)
    string.contains(detail, "duplicate") |> expect.to_be_true
  })
}

pub fn shared_tree_schema_duplicate_scan_respects_strings_and_scopes_test() {
  let raw =
    string.replace(
      object_schema,
      "\"version\":2",
      "\"version\":2,\"metadata\":{\"items\":[{\"key\":\"\\\"},:{\\\\\"},{\"key\":\"ok\"}],\"\\u6c34\":\"water\"}",
    )
  schema.stored_from_string(raw) |> expect.to_be_ok
  corrupt(string.replace(
    raw,
    "\"\\u6c34\":\"water\"",
    "\"\\u6c34\":\"water\",\"水\":\"duplicate\"",
  ))
}

pub fn shared_tree_schema_refuses_unsupported_semantics_test() {
  [
    string.replace(string_schema, "\"Value\"", "\"Sequence\""),
    string.replace(string_schema, "\"Value\"", "\"Identifier\""),
    string.replace(string_schema, "\"Value\"", "\"Forbidden\""),
    string.replace(string_schema, "\"Value\"", "\"FutureField\""),
    string.replace(string_schema, "\"leaf\":1", "\"leaf\":3"),
    string.replace(string_schema, "\"leaf\":1", "\"leaf\":8"),
    string.replace(string_schema, "\"leaf\":1", "\"future\":{}"),
    string.replace(object_schema, "\"object\":", "\"map\":"),
    string.replace(
      object_schema,
      "\"x\":{\"kind\":\"Value\"",
      "\"\":{\"kind\":\"Sequence\"",
    ),
  ]
  |> list.each(fn(raw) {
    let assert Error(types.InvalidSchema(detail)) =
      schema.stored_from_string(raw)
    string.is_empty(detail) |> expect.to_be_false
  })
}

pub fn shared_tree_schema_checks_leaf_identity_and_references_test() {
  [
    string.replace(string_schema, "\"leaf\":1", "\"leaf\":0"),
    string.replace(
      string_schema,
      "com.fluidframework.leaf.string",
      "invented.string",
    ),
    string.replace(
      object_schema,
      "\"types\":[\"Point\"]",
      "\"types\":[\"Missing\"]",
    ),
  ]
  |> list.each(fn(raw) {
    let assert Error(types.InvalidSchema(_)) = schema.stored_from_string(raw)
  })
}

pub fn shared_tree_schema_recursive_and_empty_definitions_test() {
  let raw =
    "{\"version\":2,\"nodes\":{\"A\":{\"kind\":{\"object\":{\"next\":{\"kind\":\"Optional\",\"types\":[\"B\"]}}}},\"B\":{\"kind\":{\"object\":{\"next\":{\"kind\":\"Optional\",\"types\":[\"A\"]}}}},\"Empty\":{\"kind\":{\"object\":{}}}},\"root\":{\"kind\":\"Optional\",\"types\":[\"A\"]}}"
  schema.stored_from_string(raw) |> expect.to_be_ok
  schema.view_from_string(raw) |> expect.to_be_ok
  schema.stored_from_string(string.replace(
    raw,
    "\"types\":[\"A\"]",
    "\"types\":[]",
  ))
  |> expect.to_be_ok
  Nil
}

pub fn shared_tree_schema_json_entrypoints_test() {
  let encoded =
    json.object([
      #("version", json.int(2)),
      #("nodes", json.object([])),
      #(
        "root",
        json.object([
          #("kind", json.string("Optional")),
          #("types", json.array([], json.string)),
        ]),
      ),
    ])
  schema.stored_from_json(encoded) |> expect.to_be_ok
  schema.view_from_json(encoded) |> expect.to_be_ok
  Nil
}
