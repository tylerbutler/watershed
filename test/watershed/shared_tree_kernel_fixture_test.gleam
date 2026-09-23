import gleam/json
import gleam/list
import startest/expect
import watershed/json_ot.{
  type JsonValue, NInt, VArray, VNumber, VObject, VString,
}
import watershed/tree/change_fixture_codec as input
import watershed/tree/fixtures
import watershed/tree/kernel_fixture

pub fn shared_tree_kernel_object_schedules_test() {
  let names = [
    "independent-fields",
    "same-field-both-orders",
    "optional-set-clear",
    "null-and-absence",
    "nested-independent",
    "parent-child-both-orders",
    "detached-child-edit",
  ]
  list.each(names, fn(name) {
    let assert Ok(fixture) = fixtures.load(name)
    let assert Ok(expected) = kernel_fixture.project_expected(fixture.expected)
    let actual = case kernel_fixture.run(fixture.input) {
      Ok(actual) -> actual
      Error(detail) -> panic as { name <> ": " <> detail }
    }
    case fixtures.first_difference(actual, expected) {
      Ok(Nil) -> Nil
      Error(path) -> panic as { name <> " differs at " <> path }
    }
  })
}

pub fn shared_tree_kernel_runner_uses_action_values_and_paths_test() {
  let input = fixture_input("nested-independent")
  let assert Ok(original) = run(input)
  let changed_value =
    replace_at(
      input,
      [
        Key("schedules"),
        Index(0),
        Key("actions"),
        Index(0),
        Key("value"),
      ],
      VNumber(NInt(29)),
    )
  let assert Ok(changed) = run(changed_value)
  json.to_string(changed) |> expect.to_not_equal(json.to_string(original))
  let changed_path =
    replace_at(
      input,
      [
        Key("schedules"),
        Index(0),
        Key("actions"),
        Index(0),
        Key("path"),
      ],
      VString("point.y"),
    )
  let assert Ok(changed) = run(changed_path)
  json.to_string(changed) |> expect.to_not_equal(json.to_string(original))
}

pub fn shared_tree_kernel_runner_rejects_wrong_session_and_client_test() {
  let input = fixture_input("independent-fields")
  replace_at(
    input,
    [
      Key("schedules"),
      Index(0),
      Key("initial"),
      Key("sessions"),
      Index(1),
    ],
    VString("00000000-0000-4000-8000-000000000098"),
  )
  |> run
  |> expect.to_be_error
  replace_at(
    input,
    [
      Key("schedules"),
      Index(0),
      Key("actions"),
      Index(0),
      Key("client"),
    ],
    VNumber(NInt(4)),
  )
  |> run
  |> expect.to_be_error
  Nil
}

pub fn shared_tree_kernel_runner_uses_delivery_position_test() {
  let input = fixture_input("independent-fields")
  let assert Ok(original) = run(input)
  let assert VArray(actions) =
    get_at(input, [Key("schedules"), Index(0), Key("actions")])
  let assert [first, second, deliver] = actions
  let changed =
    replace_at(
      input,
      [Key("schedules"), Index(0), Key("actions")],
      VArray([
        first,
        deliver,
        second,
      ]),
    )
  let assert Ok(changed) = run(changed)
  json.to_string(changed) |> expect.to_not_equal(json.to_string(original))
}

pub fn shared_tree_kernel_projection_rejects_missing_visible_batch_test() {
  let assert Ok(fixture) = fixtures.load("independent-fields")
  let assert Ok(expected) = input.parse(fixture.expected)
  let path = [
    Key("observations"),
    Index(0),
    Key("checkpoints"),
    Index(1),
    Key("clients"),
    Index(0),
    Key("events"),
  ]
  let assert VArray(events) = get_at(expected, path)
  replace_at(expected, path, VArray(list.take(events, 3)))
  |> json_ot.to_json
  |> kernel_fixture.project_expected
  |> expect.to_be_error
  Nil
}

pub fn shared_tree_kernel_runner_checks_retained_edit_inputs_test() {
  let input = fixture_input("detached-child-edit")
  let path = [
    Key("schedules"),
    Index(0),
    Key("actions"),
    Index(2),
  ]
  replace_at(input, list.append(path, [Key("client")]), VNumber(NInt(99)))
  |> run
  |> expect.to_be_error
  replace_at(input, list.append(path, [Key("path")]), VString("missing"))
  |> run
  |> expect.to_be_error
  replace_at(input, list.append(path, [Key("value")]), VString("not a number"))
  |> run
  |> expect.to_be_error
  Nil
}

type PathKey {
  Key(String)
  Index(Int)
}

fn fixture_input(name: String) -> JsonValue {
  let assert Ok(fixture) = fixtures.load(name)
  let assert Ok(value) = input.parse(fixture.input)
  value
}

fn run(value: JsonValue) -> Result(json.Json, String) {
  kernel_fixture.run(json_ot.to_json(value))
}

fn get_at(value: JsonValue, path: List(PathKey)) -> JsonValue {
  case path, value {
    [], _ -> value
    [Key(key), ..rest], VObject(fields) -> {
      let assert Ok(child) = list.key_find(fields, key)
      get_at(child, rest)
    }
    [Index(index), ..rest], VArray(items) -> {
      let assert Ok(child) = list.drop(items, index) |> list.first
      get_at(child, rest)
    }
    _, _ -> panic as "invalid kernel fixture path"
  }
}

fn replace_at(
  value: JsonValue,
  path: List(PathKey),
  replacement: JsonValue,
) -> JsonValue {
  case path, value {
    [], _ -> replacement
    [Key(key), ..rest], VObject(fields) ->
      VObject(
        list.map(fields, fn(entry) {
          case entry.0 == key {
            True -> #(key, replace_at(entry.1, rest, replacement))
            False -> entry
          }
        }),
      )
    [Index(index), ..rest], VArray(items) ->
      VArray(
        list.index_map(items, fn(item, position) {
          case position == index {
            True -> replace_at(item, rest, replacement)
            False -> item
          }
        }),
      )
    _, _ -> panic as "invalid kernel fixture path"
  }
}
