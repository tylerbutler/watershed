import gleam/json
import gleam/list
import gleam/string
import startest/expect
import watershed/json_ot.{
  type JsonValue, Index, Key, NInt, VArray, VBool, VNull, VNumber, VObject,
  VString,
}
import watershed/tree/field_fixture
import watershed/tree/fixtures

pub fn shared_tree_field_algebra_matches_upstream_test() -> Nil {
  fixtures.assert_case("field-compose-invert-rebase", field_fixture.run)
}

pub fn shared_tree_field_fixture_uses_every_script_input_test() -> Nil {
  let input = fixture_input()
  let assert Ok(baseline) = field_fixture.run(input)
  [
    replace(
      input,
      [
        Key("scenarios"),
        Index(0),
        Key("actions"),
        Index(0),
        Key("fill"),
        Key("localId"),
      ],
      VNumber(NInt(10)),
      VNumber(NInt(999)),
    ),
    replace(
      input,
      [
        Key("scenarios"),
        Index(0),
        Key("actions"),
        Index(0),
        Key("fill"),
        Key("revision"),
      ],
      VNumber(NInt(0)),
      VNumber(NInt(1)),
    ),
    replace(
      input,
      [
        Key("scenarios"),
        Index(11),
        Key("changes"),
        Key("first"),
        Key("moves"),
        Index(0),
        Index(1),
        Key("localId"),
      ],
      VNumber(NInt(51)),
      VNumber(NInt(999)),
    ),
    replace(
      input,
      [
        Key("scenarios"),
        Index(8),
        Key("actions"),
        Index(0),
        Key("callbacks"),
        Index(0),
        Key("result"),
        Key("localId"),
      ],
      VNumber(NInt(142)),
      VNumber(NInt(999)),
    ),
    replace(
      input,
      [
        Key("scenarios"),
        Index(15),
        Key("actions"),
        Index(0),
        Key("isRollback"),
      ],
      VBool(True),
      VBool(False),
    ),
    replace(
      input,
      [
        Key("scenarios"),
        Index(36),
        Key("forest"),
        Key("initialRoot"),
        Key("value"),
      ],
      VString("old"),
      VString("changed"),
    ),
    remove_first_action(input),
  ]
  |> list.each(fn(changed) {
    case field_fixture.run(changed) {
      Error(_) -> Nil
      Ok(actual) -> {
        let differs = json.to_string(actual) != json.to_string(baseline)
        differs |> expect.to_be_true
      }
    }
  })
}

pub fn shared_tree_field_fixture_executes_original_operation_arguments_test() -> Nil {
  let input = fixture_input()
  let assert Ok(baseline) = field_fixture.run(input)
  let mutations = [
    replace(
      input,
      [Key("operations"), Key("compose"), Key("left")],
      VString("optional"),
      VString("required"),
    ),
    replace(
      input,
      [Key("operations"), Key("compose"), Key("right")],
      VString("required"),
      VString("optional"),
    ),
    replace(
      input,
      [Key("operations"), Key("invert"), Key("change")],
      VString("compose"),
      VString("optional"),
    ),
    replace(
      input,
      [Key("operations"), Key("invert"), Key("isRollback")],
      VBool(False),
      VBool(True),
    ),
    replace(
      input,
      [Key("operations"), Key("rebase"), Key("change")],
      VString("required"),
      VString("optional"),
    ),
    replace(
      input,
      [Key("operations"), Key("rebase"), Key("over")],
      VString("optional"),
      VString("required"),
    ),
    replace(
      input,
      [Key("operations"), Key("replaceRevisions"), Key("change")],
      VString("swap"),
      VString("optional"),
    ),
  ]
  list.zip(
    [
      "compose-left",
      "compose-right",
      "invert-change",
      "invert-rollback",
      "rebase-change",
      "rebase-over",
      "replace-change",
    ],
    mutations,
  )
  |> list.each(fn(item) { assert_differs_or_refuses(item.1, baseline, item.0) })

  replace(
    input,
    [Key("operations"), Key("compose"), Key("left")],
    VString("optional"),
    VString("missing"),
  )
  |> field_fixture.run
  |> error_contains_named("compose selector", "unknown original change")

  replace(
    input,
    [
      Key("operations"),
      Key("compose"),
      Key("revisionMetadata"),
      Key("base"),
    ],
    VNumber(NInt(1)),
    VNumber(NInt(999)),
  )
  |> field_fixture.run
  |> error_contains_named("compose metadata base", "revision")

  replace_list(
    input,
    [
      Key("operations"),
      Key("compose"),
      Key("revisionMetadata"),
      Key("revisions"),
      Index(0),
    ],
    VNumber(NInt(0)),
    VNumber(NInt(999)),
  )
  |> field_fixture.run
  |> error_contains_named("compose metadata revisions", "revision")

  replace_list(
    input,
    [
      Key("operations"),
      Key("compose"),
      Key("revisionMetadata"),
      Key("rollbackRevisions"),
      Index(0),
    ],
    VNumber(NInt(0)),
    VNumber(NInt(999)),
  )
  |> field_fixture.run
  |> error_contains_named("compose metadata rollbacks", "revision")

  replace(
    input,
    [Key("operations"), Key("invert"), Key("inverseRevision")],
    VNumber(NInt(2)),
    VNumber(NInt(999)),
  )
  |> field_fixture.run
  |> error_contains_named("invert revision", "revision")

  replace_list(
    input,
    [
      Key("operations"),
      Key("replaceRevisions"),
      Key("obsolete"),
      Index(0),
    ],
    VNumber(NInt(0)),
    VNumber(NInt(999)),
  )
  |> field_fixture.run
  |> error_contains_named("replace obsolete", "revision")

  replace(
    input,
    [Key("operations"), Key("replaceRevisions"), Key("updated")],
    VNumber(NInt(3)),
    VNumber(NInt(999)),
  )
  |> field_fixture.run
  |> error_contains_named("replace updated", "revision")
}

pub fn shared_tree_field_fixture_rejects_invalid_original_operation_shapes_test() -> Nil {
  let input = fixture_input()
  ["compose", "invert", "rebase", "replaceRevisions"]
  |> list.each(fn(operation) {
    replace_current(input, [Key("operations"), Key(operation)], VNull)
    |> field_fixture.run
    |> error_contains("operation")
  })
  [
    [Key("operations"), Key("compose"), Key("left")],
    [
      Key("operations"),
      Key("compose"),
      Key("revisionMetadata"),
    ],
    [Key("operations"), Key("invert"), Key("isRollback")],
    [Key("operations"), Key("rebase"), Key("over")],
    [Key("operations"), Key("replaceRevisions"), Key("obsolete")],
  ]
  |> list.each(fn(path) {
    replace_current(input, path, VNull)
    |> field_fixture.run
    |> expect_error
  })
}

pub fn shared_tree_field_fixture_only_classifies_occupied_swap_cycles_test() -> Nil {
  let input = fixture_input()
  [
    replace_list(
      input,
      [
        Key("changes"),
        Key("swap"),
        Key("m"),
        Index(0),
        Index(0),
      ],
      VNumber(NInt(4)),
      VNumber(NInt(999)),
    ),
    replace_list(
      input,
      [
        Key("changes"),
        Key("swap"),
        Key("m"),
        Index(1),
        Index(1),
      ],
      VNumber(NInt(4)),
      VNumber(NInt(6)),
    ),
    apply(
      input,
      json_ot.list_insert(
        [
          Key("changes"),
          Key("swap"),
          Key("m"),
          Index(2),
        ],
        VArray([VNumber(NInt(6)), VNumber(NInt(7))]),
      ),
    ),
    replace(
      input,
      [
        Key("swapApplication"),
        Key("registers"),
        Index(0),
        Key("id"),
        Key("localId"),
      ],
      VNumber(NInt(4)),
      VNumber(NInt(999)),
    ),
  ]
  |> list.each(fn(changed) {
    field_fixture.run(changed)
    |> error_contains("occupied two-register swap")
  })
}

pub fn shared_tree_field_fixture_rejects_malformed_scripts_test() -> Nil {
  let input = fixture_input()
  [
    #(
      replace(
        input,
        [Key("codecs"), Key("optional")],
        VNumber(NInt(2)),
        VNumber(NInt(3)),
      ),
      "codec",
    ),
    #(
      replace(
        input,
        [
          Key("scenarios"),
          Index(0),
          Key("actions"),
          Index(0),
          Key("op"),
        ],
        VString("set"),
        VString("unknown"),
      ),
      "unknown field action",
    ),
    #(
      insert(
        input,
        [
          Key("scenarios"),
          Index(0),
          Key("actions"),
          Index(0),
          Key("extra"),
        ],
        VNull,
      ),
      "exact supported fields",
    ),
    #(
      replace(
        input,
        [Key("scenarios"), Index(1), Key("id")],
        VString("edit-occupied"),
        VString("edit-empty"),
      ),
      "duplicate field scenario id",
    ),
    #(
      replace(
        input,
        [
          Key("scenarios"),
          Index(0),
          Key("actions"),
          Index(0),
          Key("fill"),
          Key("localId"),
        ],
        VNumber(NInt(10)),
        VNumber(NInt(4_503_599_627_370_496 * 2)),
      ),
      "safe atom",
    ),
    #(
      replace(
        input,
        [Key("revisionTable"), Index(1), Key("revision")],
        VNumber(NInt(1)),
        VNumber(NInt(0)),
      ),
      "revision mappings",
    ),
  ]
  |> list.each(fn(item) { field_fixture.run(item.0) |> error_contains(item.1) })
}

fn fixture_input() -> json.Json {
  let assert Ok(fixture) = fixtures.load("field-compose-invert-rebase")
  fixture.input
}

fn replace(
  input: json.Json,
  path: List(json_ot.PathKey),
  old: JsonValue,
  new: JsonValue,
) -> json.Json {
  apply(input, json_ot.object_replace(path, old, new))
}

fn replace_current(
  input: json.Json,
  path: List(json_ot.PathKey),
  new: JsonValue,
) -> json.Json {
  let assert Ok(old) = at(value(input), path)
  replace(input, path, old, new)
}

fn insert(
  input: json.Json,
  path: List(json_ot.PathKey),
  value: JsonValue,
) -> json.Json {
  apply(input, json_ot.object_insert(path, value))
}

fn replace_list(
  input: json.Json,
  path: List(json_ot.PathKey),
  old: JsonValue,
  new: JsonValue,
) -> json.Json {
  apply(input, json_ot.list_replace(path, old, new))
}

fn remove_first_action(input: json.Json) -> json.Json {
  let value = value(input)
  let path = [Key("scenarios"), Index(0), Key("actions"), Index(0)]
  let assert Ok(action) = at(value, path)
  apply(input, json_ot.list_delete(path, action))
}

fn apply(input: json.Json, component: json_ot.Component) -> json.Json {
  let assert Ok(value) = json.parse(json.to_string(input), json_ot.decoder())
  case json_ot.apply(value, [component]) {
    Ok(value) -> json_ot.to_json(value)
    Error(error) ->
      panic as {
        "fixture mutation failed: "
        <> string.inspect(component)
        <> ": "
        <> string.inspect(error)
      }
  }
}

fn value(input: json.Json) -> JsonValue {
  let assert Ok(value) = json.parse(json.to_string(input), json_ot.decoder())
  value
}

fn at(value: JsonValue, path: List(json_ot.PathKey)) -> Result(JsonValue, Nil) {
  case path, value {
    [], _ -> Ok(value)
    [Key(key), ..rest], VObject(fields) ->
      case list.key_find(fields, key) {
        Ok(value) -> at(value, rest)
        Error(Nil) -> Error(Nil)
      }
    [Index(index), ..rest], VArray(values) ->
      case values |> list.drop(index) |> list.first {
        Ok(value) -> at(value, rest)
        Error(Nil) -> Error(Nil)
      }
    _, _ -> Error(Nil)
  }
}

fn error_contains(value: Result(a, String), expected: String) -> Nil {
  let assert Error(detail) = value
  string.contains(detail, expected) |> expect.to_be_true
}

fn expect_error(value: Result(a, String)) -> Nil {
  case value {
    Error(_) -> Nil
    Ok(_) -> False |> expect.to_be_true
  }
}

fn error_contains_named(
  value: Result(a, String),
  name: String,
  expected: String,
) -> Nil {
  case value {
    Error(detail) ->
      #(name, string.contains(detail, expected))
      |> expect.to_equal(#(name, True))
    Ok(_) -> #(name, "Ok") |> expect.to_equal(#(name, "Error"))
  }
}

fn assert_differs_or_refuses(
  changed: json.Json,
  baseline: json.Json,
  mutation: String,
) -> Nil {
  case field_fixture.run(changed) {
    Error(_) -> Nil
    Ok(actual) -> {
      let differs = json.to_string(actual) != json.to_string(baseline)
      #(mutation, differs) |> expect.to_equal(#(mutation, True))
    }
  }
}
