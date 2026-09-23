import gleam/json
import gleam/list
import startest/expect
import watershed/json_ot.{
  type JsonValue, NInt, VArray, VNumber, VObject, VString,
}
import watershed/tree/change_fixture_codec as codec
import watershed/tree/fixtures
import watershed/tree/history_fixture

type PathKey {
  Key(String)
  Index(Int)
}

pub fn shared_tree_history_matches_upstream_test() -> Nil {
  fixtures.assert_case("history-reconciliation", history_fixture.run)
}

pub fn shared_tree_history_runner_rejects_missing_inputs_test() -> Nil {
  history_fixture.run(json.object([])) |> expect.to_be_error
  Nil
}

pub fn shared_tree_history_runner_uses_edit_values_test() -> Nil {
  let input = fixture_input()
  let assert Ok(original) = run_value(input)
  let changed =
    replace_at(
      input,
      [
        Key("changes"),
        Key("local-title-a"),
        Key("builds"),
        Index(0),
        Key("trees"),
        Index(0),
        Key("value"),
      ],
      VString("changed-local-title"),
    )
  let assert Ok(mutated) = run_value(changed)
  json.to_string(mutated)
  |> expect.to_not_equal(json.to_string(original))
}

pub fn shared_tree_history_runner_rejects_future_reference_test() -> Nil {
  let changed =
    replace_at(
      fixture_input(),
      [
        Key("schedules"),
        Index(1),
        Key("actions"),
        Index(3),
        Key("referenceSequenceNumber"),
      ],
      VNumber(NInt(9)),
    )
  run_value(changed) |> expect.to_be_error
  Nil
}

pub fn shared_tree_history_runner_uses_batch_index_test() -> Nil {
  let input = fixture_input()
  let assert Ok(original) = run_value(input)
  let changed =
    replace_at(
      input,
      [
        Key("schedules"),
        Index(8),
        Key("actions"),
        Index(1),
        Key("point"),
        Key("indexInBatch"),
      ],
      VNumber(NInt(2)),
    )
  let assert Ok(mutated) = run_value(changed)
  json.to_string(mutated)
  |> expect.to_not_equal(json.to_string(original))
  output_at(original, [
    Key("observations"),
    Index(8),
    Key("checkpoints"),
    Index(1),
    Key("forest"),
    Key("root"),
  ])
  |> expect.to_equal(
    output_at(mutated, [
      Key("observations"),
      Index(8),
      Key("checkpoints"),
      Index(1),
      Key("forest"),
      Key("root"),
    ]),
  )
}

pub fn shared_tree_history_runner_rejects_rollback_identity_reuse_test() -> Nil {
  let changed =
    replace_at(
      fixture_input(),
      [
        Key("schedules"),
        Index(1),
        Key("actions"),
        Index(3),
        Key("allocations"),
        Index(0),
        Key("revision"),
      ],
      VString("10000000-0000-4000-8000-000000000001"),
    )
  run_value(changed) |> expect.to_be_error
  Nil
}

pub fn shared_tree_history_runner_uses_per_commit_repair_test() -> Nil {
  let input = fixture_input()
  let assert Ok(original) = run_value(input)
  let changed =
    replace_at(
      input,
      [
        Key("schedules"),
        Index(14),
        Key("actions"),
        Index(3),
        Key("repair"),
        Index(0),
        Key("builds"),
        Index(0),
        Key("trees"),
        Index(0),
        Key("fields"),
        Index(0),
        Index(1),
        Key("value"),
      ],
      VNumber(NInt(99)),
    )
  let assert Ok(mutated) = run_value(changed)
  output_at(original, [
    Key("observations"),
    Index(14),
    Key("checkpoints"),
    Index(3),
    Key("resubmitted"),
  ])
  |> expect.to_not_equal(
    output_at(mutated, [
      Key("observations"),
      Index(14),
      Key("checkpoints"),
      Index(3),
      Key("resubmitted"),
    ]),
  )
}

fn fixture_input() -> JsonValue {
  let assert Ok(fixture) = fixtures.load("history-reconciliation")
  let assert Ok(input) = codec.parse(fixture.input)
  input
}

fn run_value(value: JsonValue) -> Result(json.Json, String) {
  history_fixture.run(json_ot.to_json(value))
}

fn output_at(value: json.Json, path: List(PathKey)) -> JsonValue {
  let assert Ok(value) = codec.parse(value)
  get_at(value, path)
}

fn get_at(value: JsonValue, path: List(PathKey)) -> JsonValue {
  case path, value {
    [], _ -> value
    [Key(key), ..rest], VObject(fields) -> {
      let assert Ok(current) = list.key_find(fields, key)
      get_at(current, rest)
    }
    [Index(index), ..rest], VArray(values) -> {
      let assert Ok(current) = list.drop(values, index) |> list.first
      get_at(current, rest)
    }
    _, _ -> panic as "invalid history fixture path"
  }
}

fn replace_at(
  value: JsonValue,
  path: List(PathKey),
  replacement: JsonValue,
) -> JsonValue {
  case path, value {
    [], _ -> replacement
    [Key(key), ..rest], VObject(fields) -> {
      let assert Ok(current) = list.key_find(fields, key)
      let updated = replace_at(current, rest, replacement)
      VObject(
        list.map(fields, fn(entry) {
          case entry.0 == key {
            True -> #(key, updated)
            False -> entry
          }
        }),
      )
    }
    [Index(index), ..rest], VArray(values) -> {
      let assert Ok(current) = list.drop(values, index) |> list.first
      let updated = replace_at(current, rest, replacement)
      VArray(
        list.index_map(values, fn(value, current_index) {
          case current_index == index {
            True -> updated
            False -> value
          }
        }),
      )
    }
    _, _ -> panic as "invalid history fixture path"
  }
}
