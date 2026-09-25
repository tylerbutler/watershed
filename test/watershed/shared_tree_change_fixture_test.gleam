import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import startest/expect
import watershed/fluid_ids
import watershed/json_ot.{
  type JsonValue, type PathKey, Index, Key, NInt, VArray, VBool, VNumber,
  VObject, VString,
}
import watershed/tree/change
import watershed/tree/change_fixture
import watershed/tree/change_fixture_codec as codec
import watershed/tree/fixtures
import watershed/tree/map_change_fixture

pub fn shared_tree_nested_change_algebra_matches_upstream_test() -> Nil {
  fixtures.assert_case("modular-nested-algebra", change_fixture.run)
}

pub fn shared_tree_map_change_algebra_matches_upstream_test() -> Nil {
  fixtures.assert_case("map-field-algebra", map_change_fixture.run)
}

pub fn shared_tree_nested_change_runner_rejects_missing_inputs_test() -> Nil {
  change_fixture.run(json.object([])) |> expect.to_be_error
  Nil
}

fn input() -> JsonValue {
  let assert Ok(fixture) = fixtures.load("modular-nested-algebra")
  let assert Ok(input) = codec.parse(fixture.input)
  input
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
        list.index_map(values, fn(value, position) {
          case position == index {
            True -> updated
            False -> value
          }
        }),
      )
    }
    _, _ -> panic as "invalid mutation path"
  }
}

fn operation_path(index: Int, field: String) -> List(PathKey) {
  [Key("expanded"), Key("operations"), Index(index), Key(field)]
}

fn replay(value: JsonValue) -> json.Json {
  let assert Ok(output) = change_fixture.run(json_ot.to_json(value))
  output
}

fn map_input() -> JsonValue {
  let assert Ok(fixture) = fixtures.load("map-field-algebra")
  let assert Ok(input) = codec.parse(fixture.input)
  input
}

fn map_replay(value: JsonValue) -> json.Json {
  let assert Ok(output) = map_change_fixture.run(json_ot.to_json(value))
  output
}

fn map_scenario_path(scenario: Int, rest: List(PathKey)) -> List(PathKey) {
  [Key("scenarios"), Index(scenario), ..rest]
}

fn assert_map_mutation_changes(
  original: JsonValue,
  path: List(PathKey),
  replacement: JsonValue,
) -> Nil {
  let baseline = map_replay(original)
  let changed_input = replace_at(original, path, replacement)
  let changed = case map_change_fixture.run(json_ot.to_json(changed_input)) {
    Ok(changed) -> changed
    Error(error) -> panic as { string.inspect(path) <> ": " <> error }
  }
  case fixtures.first_difference(baseline, changed) {
    Error(_) -> Nil
    Ok(Nil) -> panic as { string.inspect(path) <> ": output did not change" }
  }
}

fn strip_echoed_operations(value: JsonValue) -> JsonValue {
  case value {
    VArray(values) -> VArray(list.map(values, strip_echoed_operations))
    VObject(fields) ->
      VObject(
        fields
        |> list.filter(fn(entry) { entry.0 != "operation" })
        |> list.map(fn(entry) { #(entry.0, strip_echoed_operations(entry.1)) }),
      )
    other -> other
  }
}

fn map_replay_without_echoed_operations(value: JsonValue) -> json.Json {
  let assert Ok(output) = map_change_fixture.run(json_ot.to_json(value))
  let assert Ok(output) = codec.parse(output)
  output |> strip_echoed_operations |> json_ot.to_json
}

fn stable_revision(value: String) -> fluid_ids.StableId {
  let assert Ok(revision) = fluid_ids.stable_id(value)
  revision
}

pub fn shared_tree_map_change_runner_executes_fixture_arguments_test() -> Nil {
  let original = map_input()
  let mutations = [
    #(
      map_scenario_path(0, [
        Key("changes"),
        Index(0),
        Key("encoded"),
        Key("builds"),
        Key("trees"),
        Key("data"),
        Index(0),
        Index(1),
        Index(2),
      ]),
      VString("changed"),
    ),
    #(
      map_scenario_path(4, [Key("algebra"), Index(2)]),
      VObject([
        #("operation", VString("rebase-left-over-right")),
        #("change", VString("right")),
        #("over", VString("left")),
        #(
          "revisionMetadata",
          VArray([
            VObject([
              #("revision", VString("00000000-0000-4000-b000-000000000008")),
            ]),
            VObject([
              #("revision", VString("00000000-0000-4000-b000-000000000009")),
            ]),
          ]),
        ),
        #("output", VString("right-over-left")),
      ]),
    ),
  ]
  list.each(mutations, fn(mutation) {
    assert_map_mutation_changes(original, mutation.0, mutation.1)
  })
}

pub fn shared_tree_map_change_runner_observes_supported_operation_test() -> Nil {
  let original = map_input()
  let changed =
    replace_at(
      original,
      map_scenario_path(4, [Key("algebra"), Index(2)]),
      VObject([
        #("operation", VString("invert")),
        #("change", VString("left")),
        #("inverseRevision", VString("00000000-0000-4000-b000-000000000008")),
        #("output", VString("left-over-right")),
      ]),
    )
  fixtures.first_difference(
    map_replay_without_echoed_operations(original),
    map_replay_without_echoed_operations(changed),
  )
  |> expect.to_be_error
  Nil
}

pub fn shared_tree_map_change_runner_accepts_irrelevant_revision_metadata_test() -> Nil {
  let original = map_input()
  let path =
    map_scenario_path(4, [
      Key("algebra"),
      Index(2),
      Key("revisionMetadata"),
    ])
  let assert Ok(scenarios_value) = codec.get(original, "scenarios")
  let assert Ok(scenarios) = codec.items(scenarios_value)
  let assert Ok(scenario) = list.drop(scenarios, 4) |> list.first
  let assert Ok(algebra_value) = codec.get(scenario, "algebra")
  let assert Ok(algebra) = codec.items(algebra_value)
  let assert Ok(operation) = list.drop(algebra, 2) |> list.first
  let assert Ok(metadata_value) = codec.get(operation, "revisionMetadata")
  let assert Ok(metadata) = codec.items(metadata_value)
  let changed =
    replace_at(
      original,
      path,
      VArray(
        list.append(metadata, [
          VObject([
            #("revision", VString("00000000-0000-4000-b000-00000000000a")),
          ]),
        ]),
      ),
    )
  map_replay(changed) |> expect.to_equal(map_replay(original))
}

pub fn shared_tree_fixture_codec_rejects_invalid_tagged_revisions_test() -> Nil {
  let first = stable_revision("00000000-0000-4000-b000-000000000001")
  let second = stable_revision("00000000-0000-4000-b000-000000000002")
  let assert Ok(order) = change.identity_order([#(first, 0), #(second, 1)])
  let assert Ok(changeset) =
    change.from_data(
      change.ChangeData(
        max_local_id: -1,
        revisions: [
          change.RevisionInfo(first, None),
          change.RevisionInfo(second, None),
        ],
        fields: [],
        nodes: [],
        parents: [],
        aliases: [],
        builds: [],
        destroys: [],
        refreshers: [],
      ),
      order,
    )
  codec.wire_tagged(changeset, [#(first, 0), #(second, 1)], Some(first))
  |> expect.to_be_error
  Nil
}

pub fn shared_tree_map_change_runner_rejects_invalid_input_test() -> Nil {
  let original = map_input()
  let mutations = [
    #(
      map_scenario_path(0, [Key("algebra"), Index(0), Key("operation")]),
      VString("unknown"),
    ),
    #(
      map_scenario_path(0, [
        Key("algebra"),
        Index(0),
        Key("changes"),
        Index(0),
      ]),
      VString("missing"),
    ),
    #([Key("profile"), Key("modularChange")], VNumber(NInt(6))),
    #(map_scenario_path(0, [Key("algebra")]), VObject([])),
  ]
  list.each(mutations, fn(mutation) {
    let changed = replace_at(original, mutation.0, mutation.1)
    map_change_fixture.run(json_ot.to_json(changed)) |> expect.to_be_error
    Nil
  })
}

pub fn shared_tree_nested_change_runner_executes_operation_arguments_test() -> Nil {
  let original = input()
  let baseline = replay(original)
  let mutations = [
    #(
      list.append(operation_path(0, "value"), [Key("value")]),
      VNumber(NInt(43)),
    ),
    #(
      operation_path(6, "changes"),
      VArray([VString("child-y"), VString("child-x")]),
    ),
    #(operation_path(10, "isRollback"), VBool(False)),
    #(
      operation_path(10, "inverseRevision"),
      VString("00000000-0000-4000-b000-000000000007"),
    ),
    #(
      list.append(operation_path(21, "repair"), [
        Index(0),
        Key("trees"),
        Index(0),
        Key("value"),
      ]),
      VString("different repair content"),
    ),
  ]
  list.each(mutations, fn(mutation) {
    let changed = replay(replace_at(original, mutation.0, mutation.1))
    fixtures.first_difference(baseline, changed) |> expect.to_be_error
    Nil
  })
}

fn forest_state(output: json.Json, id: String) -> JsonValue {
  let assert Ok(output) = codec.parse(output)
  let assert Ok(observations) = codec.field(output, "observations", codec.items)
  let assert Ok(observation) =
    list.find(observations, fn(observation) {
      codec.field(observation, "operation", codec.text) == Ok("modular-forest")
      && codec.field(observation, "id", codec.text) == Ok(id)
    })
  let assert Ok(checkpoints) =
    codec.field(observation, "checkpoints", codec.items)
  let assert Ok(last) = list.last(checkpoints)
  let assert Ok(state) = codec.get(last, "state")
  state
}

pub fn shared_tree_nested_change_mutation_changes_detached_not_replacement_test() -> Nil {
  let original = input()
  let mutated =
    replace_at(
      original,
      list.append(operation_path(0, "value"), [Key("value")]),
      VNumber(NInt(43)),
    )
  let before = forest_state(replay(original), "parent-then-child")
  let after = forest_state(replay(mutated), "parent-then-child")
  let assert Ok(before_root) = codec.get(before, "root")
  let assert Ok(after_root) = codec.get(after, "root")
  fixtures.first_difference(
    json_ot.to_json(before_root),
    json_ot.to_json(after_root),
  )
  |> expect.to_equal(Ok(Nil))
  let assert Ok(before_references) = codec.get(before, "references")
  let assert Ok(after_references) = codec.get(after, "references")
  fixtures.first_difference(
    json_ot.to_json(before_references),
    json_ot.to_json(after_references),
  )
  |> expect.to_be_error
  Nil
}

pub fn shared_tree_nested_change_runner_observes_alias_chains_test() -> Nil {
  let original = input()
  let assert Ok(expanded) = codec.get(original, "expanded")
  let assert Ok(changes) = codec.get(expanded, "changes")
  let assert Ok(first) = codec.get(changes, "first")
  let assert Ok([alias]) = codec.field(first, "aliases", codec.items)
  let assert Ok(#(source, target)) = codec.pair(alias)
  let assert Ok(revision) = codec.get(source, "revision")
  let intermediate =
    VObject([
      #("revision", revision),
      #("localId", VNumber(NInt(6))),
    ])
  let mutated =
    replace_at(
      original,
      [Key("expanded"), Key("changes"), Key("first"), Key("aliases")],
      VArray([
        VArray([source, intermediate]),
        VArray([intermediate, target]),
      ]),
    )
  let baseline = replay(original)
  let changed = replay(mutated)
  fixtures.first_difference(baseline, changed) |> expect.to_be_error
  forest_state(baseline, "parent-then-child")
  |> expect.to_equal(forest_state(changed, "parent-then-child"))
}

pub fn shared_tree_nested_change_runner_rejects_malformed_arguments_test() -> Nil {
  let original = input()
  let mutations = [
    #([Key("codecs"), Key("modular")], VNumber(NInt(6))),
    #([Key("compression")], VNumber(NInt(1))),
    #(
      [Key("expanded"), Key("revisions"), Index(1), Key("encoded")],
      VNumber(NInt(4)),
    ),
    #(
      [
        Key("expanded"),
        Key("changes"),
        Key("first"),
        Key("fields"),
        Index(0),
        Index(1),
        Key("kind"),
      ],
      VString("Sequence"),
    ),
    #([Key("expanded"), Key("changes"), Key("first"), Key("nodes")], VArray([])),
    #(operation_path(0, "op"), VString("unknown")),
    #(operation_path(0, "id"), VString("first")),
    #(
      operation_path(0, "path"),
      VArray([VString("missing-parent"), VString("x")]),
    ),
    #(operation_path(10, "isRollback"), VString("false")),
    #(operation_path(14, "over"), VString("missing")),
    #(operation_path(14, "revisionMetadata"), VArray([])),
    #(
      list.append(operation_path(14, "revisionMetadata"), [
        Index(0),
        Key("rollbackOf"),
      ]),
      VString("00000000-0000-4000-b000-000000000004"),
    ),
    #(
      [
        Key("expanded"),
        Key("scenarios"),
        Index(0),
        Key("actions"),
        Index(1),
        Key("change"),
      ],
      VString("missing"),
    ),
  ]
  list.each(mutations, fn(mutation) {
    let mutated = replace_at(original, mutation.0, mutation.1)
    change_fixture.run(json_ot.to_json(mutated)) |> expect.to_be_error
    Nil
  })
}

pub fn shared_tree_nested_change_runner_rejects_unknown_structure_members_test() -> Nil {
  let original = input()
  let assert Ok(expanded) = codec.get(original, "expanded")
  let assert Ok(changes) = codec.get(expanded, "changes")
  let assert Ok(VObject(fields)) = codec.get(changes, "first")
  list.each(
    ["crossFieldKeys", "nodeExistsConstraint", "noChangeConstraint"],
    fn(key) {
      let mutated =
        replace_at(
          original,
          [Key("expanded"), Key("changes"), Key("first")],
          VObject([#(key, VArray([])), ..fields]),
        )
      change_fixture.run(json_ot.to_json(mutated)) |> expect.to_be_error
      Nil
    },
  )
}

pub fn shared_tree_nested_change_runner_rejects_sequence_generic_index_test() -> Nil {
  let original = input()
  let assert Ok(expanded) = codec.get(original, "expanded")
  let assert Ok(changes) = codec.get(expanded, "changes")
  let assert Ok(first) = codec.get(changes, "first")
  let assert Ok(nodes) = codec.field(first, "nodes", codec.items)
  let assert Ok(node) = list.first(nodes)
  let assert Ok(#(id, _)) = codec.pair(node)
  let mutated =
    replace_at(
      original,
      [
        Key("expanded"),
        Key("changes"),
        Key("first"),
        Key("fields"),
        Index(0),
        Index(1),
      ],
      VObject([
        #("kind", VString("Generic")),
        #("children", VArray([VArray([VNumber(NInt(1)), id])])),
      ]),
    )
  change_fixture.run(json_ot.to_json(mutated)) |> expect.to_be_error
  Nil
}

pub fn shared_tree_nested_change_runner_rejects_unmapped_revision_test() -> Nil {
  let original = input()
  let assert Ok(expanded) = codec.get(original, "expanded")
  let assert Ok([edit, ..]) = codec.field(expanded, "operations", codec.items)
  let assert Ok([scenario, ..]) =
    codec.field(expanded, "scenarios", codec.items)
  let assert Ok([retain, ..]) = codec.field(scenario, "actions", codec.items)
  let scenario = replace_at(scenario, [Key("actions")], VArray([retain]))
  let restricted =
    replace_at(original, [Key("expanded"), Key("operations")], VArray([edit]))
  let restricted =
    replace_at(
      restricted,
      [Key("expanded"), Key("scenarios")],
      VArray([scenario]),
    )
  let _ = replay(restricted)
  let invalid =
    replace_at(
      restricted,
      operation_path(0, "revision"),
      VString("00000000-0000-4000-b000-000000000008"),
    )
  change_fixture.run(json_ot.to_json(invalid)) |> expect.to_be_error
  Nil
}

pub fn shared_tree_nested_change_runner_uses_explicit_revision_order_test() -> Nil {
  let original = input()
  let mutated =
    replace_at(
      original,
      [Key("expanded"), Key("revisions"), Index(4), Key("encoded")],
      VNumber(NInt(1033)),
    )
  let mutated =
    replace_at(
      mutated,
      [Key("expanded"), Key("revisions"), Index(5), Key("encoded")],
      VNumber(NInt(520)),
    )
  let baseline = replay(original)
  let changed = replay(mutated)
  fixtures.first_difference(baseline, changed) |> expect.to_be_error
  let before = forest_state(baseline, "nonlexical-undo")
  let after = forest_state(changed, "nonlexical-undo")
  codec.get(before, "root") |> expect.to_equal(codec.get(after, "root"))
}
