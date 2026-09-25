import gleam/json
import gleam/list
import gleam/option.{None, Some}
import startest/expect
import watershed/fluid_ids
import watershed/json_ot.{
  type JsonValue, NInt, VArray, VNumber, VObject, VString,
}
import watershed/tree/change
import watershed/tree/change_fixture_codec as codec
import watershed/tree/fixtures
import watershed/tree/forest
import watershed/tree/history
import watershed/tree/history_fixture
import watershed/tree/schema
import watershed/tree/types.{
  AtomId, MapDelete, MapSet, MapValue, ObjectValue, StringValue,
}

const map_type = "org.watershed.shared-tree.m2.DynamicMap"

const root_type = "org.watershed.shared-tree.m2.Root"

const m2_schema = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}},\"org.watershed.shared-tree.m2.DynamicMap\":{\"kind\":{\"map\":{\"kind\":\"Optional\",\"types\":[\"com.fluidframework.leaf.string\",\"org.watershed.shared-tree.m2.DynamicMap\"]}}},\"org.watershed.shared-tree.m2.Root\":{\"kind\":{\"object\":{\"items\":{\"kind\":\"Value\",\"types\":[\"org.watershed.shared-tree.m2.DynamicMap\"]}}}}},\"root\":{\"kind\":\"Value\",\"types\":[\"org.watershed.shared-tree.m2.DynamicMap\",\"org.watershed.shared-tree.m2.Root\"]}}"

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

pub fn shared_tree_history_runner_rejects_cached_rollback_revision_reuse_test() -> Nil {
  let input = fixture_input()
  let reused =
    get_at(input, [
      Key("schedules"),
      Index(4),
      Key("actions"),
      Index(1),
      Key("allocations"),
      Index(0),
      Key("revision"),
    ])
  let changed =
    replace_at(
      input,
      [
        Key("schedules"),
        Index(4),
        Key("actions"),
        Index(2),
        Key("allocations"),
        Index(0),
        Key("revision"),
      ],
      reused,
    )
  run_value(changed) |> expect.to_be_error
  Nil
}

pub fn shared_tree_history_runner_accepts_exact_rebased_remote_replay_test() -> Nil {
  let input = fixture_input()
  let assert VArray(actions) =
    get_at(input, [
      Key("schedules"),
      Index(4),
      Key("actions"),
    ])
  let assert Ok(replay) = list.drop(actions, 2) |> list.first
  let replay = replace_at(replay, [Key("allocations")], VArray([]))
  let changed =
    replace_at(
      input,
      [
        Key("schedules"),
        Index(4),
        Key("actions"),
      ],
      VArray(list.append(actions, [replay])),
    )
  run_value(changed) |> expect.to_be_ok
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

pub fn shared_tree_history_resubmits_map_repairs_test() {
  assert_map_repairs_are_resubmitted()
}

fn assert_map_repairs_are_resubmitted() {
  [
    #(MapSet(["items"], "key", StringValue("new")), StringValue("old")),
    #(
      MapDelete(["items"], "nested"),
      MapValue(map_type, [#("inside", StringValue("retained"))]),
    ),
  ]
  |> list.each(fn(entry) {
    let revision = map_revision()
    let assert Ok(stored) = schema.stored_from_string(m2_schema)
    let assert Ok(visible) =
      forest.new(map_view_revision(), stored, Some(map_root()))
    let assert Ok(order) = change.identity_order([#(revision, 0)])
    let assert Ok(authored) =
      change.edit(stored, visible, revision, entry.0, order)
    let inverse_revision = map_inverse_revision()
    let assert Ok(inverse_order) =
      change.identity_order([
        #(revision, 0),
        #(inverse_revision, 1),
      ])
    let assert Ok(authored) =
      change.from_data(change.to_data(authored), inverse_order)
    let assert Ok(inverted) =
      change.invert(
        change.TaggedChange(Some(revision), None, authored),
        False,
        inverse_revision,
      )
    let commit = history.Commit(inverse_revision, map_session(), inverted)
    let assert Ok(update) =
      history.append_local(history.new(map_session()), commit)
    let repair = forest.Build(AtomId(Some(revision), 0), [entry.1])
    let assert Ok([resubmitted]) =
      history.resubmit(update.history, [#(inverse_revision, [repair])])
    change.to_data(resubmitted.change).refreshers
    |> expect.to_equal([repair])
  })
}

fn map_revision() -> fluid_ids.StableId {
  let assert Ok(id) =
    fluid_ids.stable_id("00000000-0000-4000-8000-0000000000a0")
  id
}

fn map_view_revision() -> fluid_ids.StableId {
  let assert Ok(id) =
    fluid_ids.stable_id("00000000-0000-4000-8000-000000000001")
  id
}

fn map_inverse_revision() -> fluid_ids.StableId {
  let assert Ok(id) =
    fluid_ids.stable_id("00000000-0000-4000-8000-0000000000c0")
  id
}

fn map_session() -> fluid_ids.SessionId {
  let assert Ok(id) =
    fluid_ids.session_id("00000000-0000-4000-8000-000000000002")
  id
}

fn map_root() -> types.TreeValue {
  ObjectValue(root_type, [
    #(
      "items",
      MapValue(map_type, [
        #("key", StringValue("old")),
        #("nested", MapValue(map_type, [#("inside", StringValue("retained"))])),
      ]),
    ),
  ])
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
