import gleam/dynamic/decode.{type Decoder}
import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set
import gleam/string
import startest/expect
import watershed/tree/fixtures
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

pub fn shared_tree_schema_decodes_supported_schema_test() -> Nil {
  schema.stored_from_string(string_schema) |> expect.to_be_ok
  schema.view_from_string(object_schema) |> expect.to_be_ok
  Nil
}

pub fn shared_tree_schema_refuses_versions_on_both_boundaries_test() -> Nil {
  let raw = string.replace(string_schema, "\"version\":2", "\"version\":99")
  schema.stored_from_string(raw)
  |> expect.to_equal(Error(types.UnsupportedFormat("Schema", "99")))
  schema.view_from_string(raw)
  |> expect.to_equal(Error(types.UnsupportedFormat("Schema", "99")))
}

pub fn shared_tree_schema_rejects_malformed_shapes_test() -> Nil {
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

pub fn shared_tree_schema_rejects_duplicate_declarations_test() -> Nil {
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

pub fn shared_tree_schema_duplicate_scan_respects_strings_and_scopes_test() -> Nil {
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

pub fn shared_tree_schema_refuses_unsupported_semantics_test() -> Nil {
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

pub fn shared_tree_schema_checks_leaf_identity_and_references_test() -> Nil {
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

pub fn shared_tree_schema_recursive_and_empty_definitions_test() -> Nil {
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

pub fn shared_tree_schema_json_entrypoints_test() -> Nil {
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

fn compatible(stored: String, view: String) -> Result(Nil, types.TreeError) {
  let assert Ok(stored) = schema.stored_from_string(stored)
  let assert Ok(view) = schema.view_from_string(view)
  schema.can_view(stored, view)
}

pub fn shared_tree_schema_matching_view_test() -> Nil {
  compatible(object_schema, object_schema) |> expect.to_equal(Ok(Nil))
  let optional = string.replace(string_schema, "\"Value\"", "\"Optional\"")
  let assert Error(types.InvalidSchema(detail)) =
    compatible(string_schema, optional)
  string.contains(detail, "root") |> expect.to_be_true
}

pub fn shared_tree_schema_field_discrepancies_test() -> Nil {
  [
    string.replace(object_schema, "\"Optional\"", "\"Value\""),
    string.replace(
      object_schema,
      "\"types\":[\"Point\"]",
      "\"types\":[\"Root\"]",
    ),
    string.replace(object_schema, "\"note\":", "\"extra\":"),
    string.replace(
      object_schema,
      "\"note\":{",
      "\"extra\":{\"kind\":\"Optional\",\"types\":[]},\"note\":{",
    ),
  ]
  |> list.each(fn(view) {
    let assert Error(types.InvalidSchema(detail)) =
      compatible(object_schema, view)
    string.contains(detail, "Root") |> expect.to_be_true
  })
}

pub fn shared_tree_schema_type_sets_are_order_independent_test() -> Nil {
  let union =
    string.replace(
      object_schema,
      "\"types\":[\"Root\"]",
      "\"types\":[\"Root\",\"Point\"]",
    )
  let reordered =
    string.replace(union, "\"Root\",\"Point\"", "\"Point\",\"Root\",\"Point\"")
  compatible(union, reordered) |> expect.to_equal(Ok(Nil))
  let assert Error(types.InvalidSchema(_)) = compatible(object_schema, union)
  let assert Error(types.InvalidSchema(_)) = compatible(union, object_schema)
  Nil
}

pub fn shared_tree_schema_unused_nodes_and_metadata_test() -> Nil {
  let extra =
    string.replace(
      string_schema,
      "\"nodes\":{",
      "\"nodes\":{\"Unused\":{\"kind\":{\"object\":{}}},",
    )
  compatible(string_schema, extra) |> expect.to_equal(Ok(Nil))
  compatible(extra, string_schema) |> expect.to_equal(Ok(Nil))
  let metadata =
    string.replace(
      extra,
      "\"kind\":{\"leaf\":1}",
      "\"kind\":{\"leaf\":1},\"metadata\":{\"description\":\"text\"}",
    )
  compatible(extra, metadata) |> expect.to_equal(Ok(Nil))
  let mismatch =
    string.replace(
      extra,
      "\"object\":{}",
      "\"object\":{\"child\":{\"kind\":\"Optional\",\"types\":[]}}",
    )
  let assert Error(types.InvalidSchema(detail)) = compatible(extra, mismatch)
  string.contains(detail, "Unused") |> expect.to_be_true
}

pub fn shared_tree_schema_recursive_compatibility_test() -> Nil {
  let recursive =
    string.replace(
      object_schema,
      "\"types\":[\"Point\"]",
      "\"types\":[\"Root\"]",
    )
  compatible(recursive, recursive) |> expect.to_equal(Ok(Nil))
}

pub fn shared_tree_schema_null_is_not_absence_test() -> Nil {
  let assert Ok(stored) = schema.stored_from_string(string_schema)
  schema.validate_root(stored, types.StringValue(""))
  |> expect.to_equal(Ok(Nil))
  let assert Error(types.InvalidEdit([], _)) =
    schema.validate_root(stored, types.NullValue)
  let assert Error(types.InvalidEdit([], _)) =
    schema.validate_root_field(stored, None)
  let optional = string.replace(string_schema, "\"Value\"", "\"Optional\"")
  let assert Ok(stored) = schema.stored_from_string(optional)
  schema.validate_root_field(stored, None) |> expect.to_equal(Ok(Nil))
  let assert Error(types.InvalidEdit([], _)) =
    schema.validate_root_field(stored, Some(types.NullValue))
  Nil
}

fn point(fields: List(#(String, types.TreeValue))) -> types.TreeValue {
  types.ObjectValue("Point", fields)
}

fn root(point: types.TreeValue) -> types.TreeValue {
  types.ObjectValue("Root", [#("point", point)])
}

pub fn shared_tree_schema_nested_values_and_paths_test() -> Nil {
  let assert Ok(stored) = schema.stored_from_string(object_schema)
  let good = root(point([#("x", types.StringValue("value"))]))
  schema.validate_root(stored, good) |> expect.to_equal(Ok(Nil))
  [
    #(root(point([])), ["point", "x"]),
    #(root(point([#("x", types.NullValue)])), ["point", "x"]),
    #(root(types.ObjectValue("Wrong", [])), ["point"]),
    #(
      root(
        point([
          #("x", types.StringValue("")),
          #("x", types.StringValue("second")),
        ]),
      ),
      ["point", "x"],
    ),
    #(
      root(point([#("x", types.StringValue("")), #("extra", types.NullValue)])),
      ["point", "extra"],
    ),
    #(types.ObjectValue("Root", []), ["point"]),
    #(types.StringValue("not a root"), []),
  ]
  |> list.each(fn(test_case) {
    let assert Error(types.InvalidEdit(path, detail)) =
      schema.validate_root(stored, test_case.0)
    path |> expect.to_equal(test_case.1)
    string.is_empty(detail) |> expect.to_be_false
    schema.validate_root(stored, good) |> expect.to_equal(Ok(Nil))
  })
}

pub fn shared_tree_schema_direct_field_validation_test() -> Nil {
  let assert Ok(stored) = schema.stored_from_string(object_schema)
  schema.validate_field(stored, "Root", "note", None)
  |> expect.to_equal(Ok(Nil))
  schema.validate_field(stored, "Root", "note", Some(types.StringValue("")))
  |> expect.to_equal(Ok(Nil))
  [
    #("Root", "point", None),
    #("Root", "note", Some(types.NullValue)),
    #("Root", "missing", None),
    #("Missing", "x", Some(types.StringValue(""))),
    #("com.fluidframework.leaf.string", "x", None),
  ]
  |> list.each(fn(test_case) {
    let assert Error(types.InvalidEdit(path, detail)) =
      schema.validate_field(stored, test_case.0, test_case.1, test_case.2)
    path |> expect.to_equal([test_case.1])
    string.is_empty(detail) |> expect.to_be_false
  })
}

fn leaf_schema(identifier: String, code: Int) -> String {
  json.object([
    #("version", json.int(2)),
    #(
      "nodes",
      json.object([
        #(
          identifier,
          json.object([#("kind", json.object([#("leaf", json.int(code))]))]),
        ),
      ]),
    ),
    #(
      "root",
      json.object([
        #("kind", json.string("Value")),
        #("types", json.array([identifier], json.string)),
      ]),
    ),
  ])
  |> json.to_string
}

pub fn shared_tree_schema_leaf_kinds_test() -> Nil {
  [
    #("com.fluidframework.leaf.string", 1, types.StringValue("")),
    #("com.fluidframework.leaf.boolean", 2, types.BooleanValue(False)),
    #("com.fluidframework.leaf.null", 4, types.NullValue),
    #("com.fluidframework.leaf.number", 0, types.NumberValue(1.5)),
  ]
  |> list.each(fn(test_case) {
    let assert Ok(stored) =
      schema.stored_from_string(leaf_schema(test_case.0, test_case.1))
    schema.validate_root(stored, test_case.2) |> expect.to_equal(Ok(Nil))
    let assert Error(types.InvalidEdit([], _)) =
      schema.validate_root(stored, types.ObjectValue(test_case.0, []))
  })
}

pub fn shared_tree_schema_finite_double_boundaries_test() -> Nil {
  let assert Ok(stored) =
    schema.stored_from_string(leaf_schema("com.fluidframework.leaf.number", 0))
  [
    0.0,
    -0.0,
    5.0e-324,
    1.7976931348623157e308,
    -1.7976931348623157e308,
    9_007_199_254_740_992.0,
    -1.25,
  ]
  |> list.each(fn(value) {
    schema.validate_root(stored, types.NumberValue(value))
    |> expect.to_equal(Ok(Nil))
  })
}

@target(javascript)
pub fn shared_tree_schema_non_finite_numbers_test() -> Nil {
  let assert Ok(stored) =
    schema.stored_from_string(leaf_schema("com.fluidframework.leaf.number", 0))
  let infinity = 1.7976931348623157e308 *. 2.0
  let nan = infinity -. infinity
  [infinity, 0.0 -. infinity, nan]
  |> list.each(fn(value) {
    let assert Error(types.InvalidEdit([], _)) =
      schema.validate_root(stored, types.NumberValue(value))
  })
}

pub fn shared_tree_schema_unicode_field_keys_test() -> Nil {
  ["", "水", "🌊", "e\u{0301}", "\u{0}", "\"\\", "\u{fffd}"]
  |> list.each(fn(key) {
    let raw =
      string.replace(object_schema, "\"x\"", json.to_string(json.string(key)))
    let assert Ok(stored) = schema.stored_from_string(raw)
    schema.validate_root(stored, root(point([#(key, types.StringValue("🌊"))])))
    |> expect.to_equal(Ok(Nil))
  })
}

pub fn shared_tree_schema_empty_type_sets_test() -> Nil {
  let raw =
    string.replace(
      string_schema,
      "\"types\":[\"com.fluidframework.leaf.string\"]",
      "\"types\":[]",
    )
  let assert Ok(stored) = schema.stored_from_string(raw)
  let assert Error(types.InvalidEdit([], _)) =
    schema.validate_root(stored, types.StringValue(""))
  let optional = string.replace(raw, "\"Value\"", "\"Optional\"")
  let assert Ok(stored) = schema.stored_from_string(optional)
  schema.validate_root_field(stored, None) |> expect.to_equal(Ok(Nil))
}

fn runner_input(checks: List(json.Json)) -> json.Json {
  json.object([#("checks", json.array(checks, fn(value) { value }))])
}

pub fn shared_tree_schema_oracle_test() -> Nil {
  fixtures.assert_case("schema-validation", run_schema_case)
}

fn root_check(id: String, stored: String, value: json.Json) -> json.Json {
  json.object([
    #("id", json.string(id)),
    #("operation", json.string("root")),
    #("stored", json.string(stored)),
    #("value", value),
  ])
}

pub fn shared_tree_schema_runner_reports_actual_acceptance_test() -> Nil {
  let input =
    runner_input([
      root_check(
        "accept",
        string_schema,
        json.object([
          #("kind", json.string("string")),
          #("value", json.string("value")),
        ]),
      ),
      root_check("refuse", string_schema, json.null()),
    ])
  let assert Ok(actual) = run_schema_case(input)
  let expected =
    json.object([
      #(
        "observations",
        json.array(
          [
            json.object([
              #("id", json.string("accept")),
              #("accepted", json.bool(True)),
            ]),
            json.object([
              #("id", json.string("refuse")),
              #("accepted", json.bool(False)),
            ]),
          ],
          fn(value) { value },
        ),
      ),
    ])
  fixtures.first_difference(actual, expected) |> expect.to_equal(Ok(Nil))
  fixtures.first_difference(
    actual,
    json.object([
      #(
        "observations",
        json.array(
          [
            json.object([
              #("id", json.string("accept")),
              #("accepted", json.bool(False)),
            ]),
            json.object([
              #("id", json.string("refuse")),
              #("accepted", json.bool(False)),
            ]),
          ],
          fn(value) { value },
        ),
      ),
    ]),
  )
  |> expect.to_equal(Error("$.observations[0].accepted"))
}

pub fn shared_tree_schema_runner_refuses_bad_fixture_inputs_test() -> Nil {
  let valid = root_check("a", string_schema, json.null())
  [
    json.null(),
    json.object([]),
    runner_input([]),
    runner_input([valid, valid]),
    runner_input([root_check("", string_schema, json.null())]),
    runner_input([root_check("a", "{}", json.null())]),
    runner_input([
      root_check(
        "a",
        string_schema,
        json.object([#("kind", json.string("unknown"))]),
      ),
    ]),
    runner_input([
      json.object([
        #("id", json.string("a")),
        #("operation", json.string("future")),
      ]),
    ]),
    runner_input([
      json.object([
        #("id", json.string("a")),
        #("operation", json.string("root")),
        #("stored", json.string(string_schema)),
      ]),
    ]),
    runner_input([
      json.object([
        #("id", json.string("a")),
        #("operation", json.string("canView")),
        #("stored", json.string(string_schema)),
      ]),
    ]),
    runner_input([
      json.object([
        #("id", json.string("a")),
        #("operation", json.string("field")),
        #("stored", json.string(string_schema)),
        #("value", json.null()),
      ]),
    ]),
  ]
  |> list.each(fn(input) { run_schema_case(input) |> expect.to_be_error })
}

type SchemaCheck {
  ViewCheck(id: String, stored: String, view: String)
  RootCheck(id: String, stored: String, value: Option(types.TreeValue))
  FieldCheck(
    id: String,
    stored: String,
    parent_type: String,
    field: String,
    value: Option(types.TreeValue),
  )
}

fn run_schema_case(input: json.Json) -> Result(json.Json, String) {
  use checks <- result.try(
    json.parse(json.to_string(input), {
      use checks <- decode.field("checks", decode.list(schema_check_decoder()))
      decode.success(checks)
    })
    |> result.map_error(fn(error) {
      "invalid schema fixture: " <> string.inspect(error)
    }),
  )
  use _ <- result.try(case checks {
    [] -> Error("schema checks must not be empty")
    [_, ..] -> Ok(Nil)
  })
  use _ <- result.try(
    list.try_fold(checks, set.new(), fn(ids, check) {
      case string.is_empty(check.id) || set.contains(ids, check.id) {
        True -> Error("empty or duplicate schema check id: " <> check.id)
        False -> Ok(set.insert(ids, check.id))
      }
    }),
  )
  use observations <- result.try(list.try_map(checks, run_schema_check))
  Ok(
    json.object([
      #("observations", json.array(observations, fn(value) { value })),
    ]),
  )
}

fn schema_check_decoder() -> Decoder(SchemaCheck) {
  use id <- decode.field("id", decode.string)
  use stored <- decode.field("stored", decode.string)
  use operation <- decode.field("operation", decode.string)
  case operation {
    "canView" -> {
      use view <- decode.field("view", decode.string)
      decode.success(ViewCheck(id, stored, view))
    }
    "root" -> {
      use value <- decode.field("value", decode.optional(tree_value_decoder()))
      decode.success(RootCheck(id, stored, value))
    }
    "field" -> {
      use parent <- decode.field("parentType", decode.string)
      use field <- decode.field("field", decode.string)
      use value <- decode.field("value", decode.optional(tree_value_decoder()))
      decode.success(FieldCheck(id, stored, parent, field, value))
    }
    _ -> decode.failure(RootCheck(id, stored, None), "known schema check")
  }
}

fn tree_value_decoder() -> Decoder(types.TreeValue) {
  use kind <- decode.field("kind", decode.string)
  case kind {
    "string" -> {
      use value <- decode.field("value", decode.string)
      decode.success(types.StringValue(value))
    }
    "boolean" -> {
      use value <- decode.field("value", decode.bool)
      decode.success(types.BooleanValue(value))
    }
    "number" -> {
      use value <- decode.field(
        "value",
        decode.one_of(decode.float, [
          {
            use value <- decode.then(decode.int)
            case float.parse(int.to_string(value) <> ".0") {
              Ok(value) -> decode.success(value)
              Error(Nil) -> decode.failure(0.0, "finite number")
            }
          },
        ]),
      )
      case
        value >=. -1.7976931348623157e308 && value <=. 1.7976931348623157e308
      {
        True -> decode.success(types.NumberValue(value))
        False -> decode.failure(types.NullValue, "finite number")
      }
    }
    "null" -> decode.success(types.NullValue)
    "object" -> {
      use identifier <- decode.field("type", decode.string)
      use fields <- decode.field(
        "fields",
        decode.list({
          use pair <- decode.then(decode.list(decode.dynamic))
          case pair {
            [_, _] -> {
              use key <- decode.field(0, decode.string)
              use value <- decode.field(1, decode.recursive(tree_value_decoder))
              decode.success(#(key, value))
            }
            _ ->
              decode.failure(#("", types.NullValue), "two-element field entry")
          }
        }),
      )
      decode.success(types.ObjectValue(identifier, fields))
    }
    _ -> decode.failure(types.NullValue, "known tree value kind")
  }
}

fn run_schema_check(check: SchemaCheck) -> Result(json.Json, String) {
  use stored <- result.try(
    schema.stored_from_string(check.stored)
    |> result.map_error(fn(error) {
      check.id <> ": invalid stored schema: " <> string.inspect(error)
    }),
  )
  use accepted <- result.try(case check {
    ViewCheck(_, _, view) -> {
      use view <- result.try(
        schema.view_from_string(view)
        |> result.map_error(fn(error) {
          check.id <> ": invalid view schema: " <> string.inspect(error)
        }),
      )
      case schema.can_view(stored, view) {
        Ok(Nil) -> Ok(True)
        Error(types.InvalidSchema(_)) -> Ok(False)
        Error(error) ->
          Error(
            check.id
            <> ": unexpected compatibility error: "
            <> string.inspect(error),
          )
      }
    }
    RootCheck(_, _, value) ->
      schema.validate_root_field(stored, value) |> value_acceptance(check.id)
    FieldCheck(_, _, parent, field, value) ->
      schema.validate_field(stored, parent, field, value)
      |> value_acceptance(check.id)
  })
  Ok(
    json.object([
      #("id", json.string(check.id)),
      #("accepted", json.bool(accepted)),
    ]),
  )
}

fn value_acceptance(
  result: Result(Nil, types.TreeError),
  id: String,
) -> Result(Bool, String) {
  case result {
    Ok(Nil) -> Ok(True)
    Error(types.InvalidEdit(_, _)) -> Ok(False)
    Error(error) ->
      Error(id <> ": unexpected validation error: " <> string.inspect(error))
  }
}
