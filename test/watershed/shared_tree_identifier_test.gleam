import gleam/int
import gleam/json
import gleam/list
import gleam/option.{Some}
import gleam/result
import gleam/string
import startest/expect
import watershed/fluid_ids
import watershed/json_ot.{
  type JsonValue, NInt, VArray, VNull, VNumber, VObject, VString,
}
import watershed/tree/codec/field_batch
import watershed/tree/fixtures
import watershed/tree/identifier
import watershed/tree/identifier_fixture
import watershed/tree/runtime as tree_runtime
import watershed/tree/schema
import watershed/tree/transaction
import watershed/tree/types
import watershed/tree_kernel

pub fn identifier_schema_upstream_fixture_test() {
  assert_identifier_case("identifier-schema")
}

pub fn identifier_values_upstream_fixture_test() {
  assert_identifier_case("identifier-values")
}

pub fn identifier_field_batches_upstream_fixture_test() {
  assert_identifier_case("identifier-field-batches")
}

pub fn identifier_persistence_upstream_fixture_test() {
  assert_identifier_case("identifier-persistence")
}

pub fn identifier_runner_observes_mutable_inputs_test() {
  let cases = [
    #("identifier-values", "custom-id", "changed-custom-id"),
    #(
      "identifier-field-batches",
      "10000000-0000-4000-8000-000000000001",
      "20000000-0000-4000-8000-000000000002",
    ),
    #("\"firstGenCount\":1", "\"firstGenCount\":2", "identifier-field-batches"),
    #("identifier-values", "\"label\":\"replacement\"", "\"label\":\"changed\""),
  ]
  cases
  |> list.each(fn(mutation) {
    let #(name, before, after) = case mutation {
      #("\"firstGenCount\":1", after, name) -> #(name, mutation.0, after)
      value -> value
    }
    let assert Ok(fixture) = fixtures.load(name)
    let original = identifier_fixture.run(fixture.input)
    let changed =
      fixture.input
      |> json.to_string
      |> string.replace(before, after)
    let assert Ok(changed) = json.parse(changed, json_ot.decoder())
    case identifier_fixture.run(json_ot.to_json(changed)) {
      Error(_) -> Nil
      Ok(changed) -> changed |> expect.to_not_equal(original |> expect.to_be_ok)
    }
  })
}

pub fn identifier_schema_runner_rejects_noncanonical_field_change_test() {
  let input =
    identifier_scenario("identifier-schema", "canonical-field-change")
    |> update_scenario_actions("canonical-field-change", fn(actions) {
      list.map(actions, fn(action) {
        let assert VObject(fields) = action
        VObject(list.key_set(fields, "encoded", VNumber(NInt(1))))
      })
    })
  identifier_fixture.run(input) |> expect.to_be_error
  Nil
}

pub fn identifier_field_batch_runner_uses_op_space_test() {
  let input =
    identifier_scenario("identifier-field-batches", "unknown-uuid-string")
  let changed =
    input
    |> update_scenario_actions("unknown-uuid-string", fn(_) {
      [
        VObject([
          #("op", VString("encode-field-batch")),
          #("path", VArray([VString("identifier")])),
          #("value", VString("30000000-0000-4000-8000-000000000003")),
          #("purpose", VString("summary")),
          #("compressor", VString("summary")),
        ]),
      ]
    })
  let assert Ok(VObject(root)) =
    identifier_fixture.run(changed)
    |> expect.to_be_ok
    |> json.to_string
    |> json_ot.parse_json
  let assert Ok(VArray([VObject(observation)])) =
    list.key_find(root, "observations")
  list.key_find(observation, "encoded")
  |> expect.to_equal(Ok(VNumber(NInt(0))))
}

pub fn identifier_value_runner_executes_appended_action_test() {
  let input =
    identifier_scenario("identifier-persistence", "equal-custom-id-replacement")
  let changed =
    input
    |> update_scenario_actions("equal-custom-id-replacement", fn(actions) {
      list.append(actions, [replacement_action("appended-final")])
    })
  identifier_fixture.run(changed)
  |> expect.to_not_equal(identifier_fixture.run(input))
}

pub fn identifier_transaction_runner_honors_commit_test() {
  let input = identifier_scenario("identifier-persistence", "transaction-abort")
  let changed =
    input
    |> update_scenario_actions("transaction-abort", fn(actions) {
      list.map(actions, fn(action) {
        let assert VObject(fields) = action
        VObject(list.key_set(fields, "result", VString("commit")))
      })
    })
  identifier_fixture.run(changed)
  |> expect.to_not_equal(identifier_fixture.run(input))
}

pub fn identifier_summary_runner_restores_supplied_compressor_test() {
  let input =
    identifier_scenario("identifier-persistence", "initial-summary-defaults")
  let assert Ok(VObject(root)) = json_ot.parse_json(json.to_string(input))
  let assert Ok(VObject(compressors)) = list.key_find(root, "compressors")
  let changed =
    root
    |> list.key_set(
      "compressors",
      VObject(list.key_set(compressors, "initial", VString("invalid"))),
    )
    |> VObject
    |> json_ot.to_json
  identifier_fixture.run(changed) |> expect.to_be_error
  Nil
}

pub fn identifier_retry_runner_requires_reconnect_and_resubmit_test() {
  let input = identifier_scenario("identifier-persistence", "retry-resubmit")
  let changed =
    input
    |> update_scenario_actions("retry-resubmit", fn(actions) {
      list.filter(actions, fn(action) {
        case action {
          VObject(fields) ->
            case list.key_find(fields, "op") {
              Ok(VString("reconnect")) | Ok(VString("resubmit")) -> False
              _ -> True
            }
          _ -> True
        }
      })
    })
  identifier_fixture.run(changed)
  |> expect.to_not_equal(identifier_fixture.run(input))
}

pub fn identifier_retry_runner_delivers_multi_edit_transaction_test() {
  let input = identifier_scenario("identifier-persistence", "retry-resubmit")
  let changed =
    input
    |> update_scenario_actions("retry-resubmit", fn(actions) {
      case actions {
        [disconnect, insert, reconnect, resubmit] -> [
          disconnect,
          insert,
          retry_label_action("retry-final"),
          reconnect,
          resubmit,
        ]
        _ -> actions
      }
    })
  identifier_fixture.run(changed)
  |> expect.to_not_equal(identifier_fixture.run(input))
}

pub fn identifier_remove_runner_observes_full_removed_range_test() {
  let input =
    identifier_scenario("identifier-persistence", "remove-retain-repair")
  let changed =
    input
    |> update_scenario_actions("remove-retain-repair", fn(actions) {
      list.map(actions, fn(action) {
        let assert VObject(fields) = action
        VObject(list.key_set(fields, "count", VNumber(NInt(2))))
      })
    })
  identifier_fixture.run(changed)
  |> expect.to_not_equal(identifier_fixture.run(input))
}

pub fn identifier_summary_projection_observes_semantic_mutation_test() {
  let assert Ok(fixture) = fixtures.load("identifier-persistence")
  let actual = identifier_fixture.run(fixture.input) |> expect.to_be_ok
  let assert Ok(actual) = json_ot.parse_json(json.to_string(actual))
  let assert Ok(expected) = json_ot.parse_json(json.to_string(fixture.expected))
  let changed =
    update_observation_field(
      expected,
      "initial-summary-defaults",
      "summary",
      VObject([#("garbage", VString("not-a-summary"))]),
    )
  let #(actual, changed) = case
    normalize_identifier_case(fixture.input, actual, changed)
  {
    Ok(value) -> value
    Error(error) -> panic as { error }
  }
  let #(actual, expected) = native_projection(actual, changed)
  fixtures.first_difference(json_ot.to_json(actual), json_ot.to_json(expected))
  |> expect.to_be_error
  Nil
}

pub fn identifier_summary_tail_requires_allocation_atomically_test() {
  let assert Ok(fixture) = fixtures.load("identifier-persistence")
  let assert Ok(changed) =
    json_ot.parse_json(json.to_string(fixture.input))
    |> result.map(remove_tail_ranges)
  let _ = identifier_fixture.run(json_ot.to_json(changed)) |> expect.to_be_error
  Nil
}

pub fn identifier_missing_value_uses_document_compressor_test() {
  let assert Ok(session) =
    fluid_ids.session_id("11111111-1111-4111-8111-111111111111")
  let base = fluid_ids.new(session)
  let assert Ok(#(expected_compressor, local)) = fluid_ids.generate(base)
  let assert Ok(stable) = fluid_ids.decompress(expected_compressor, local)
  let input =
    types.ObjectValue(identifier_fixture.point_type, [
      #("label", types.StringValue("new")),
    ])
  let assert Ok(#(value, compressor)) =
    identifier.materialize_value(identifier_fixture.stored(), input, base)
  let assert types.ObjectValue(_, fields) = value
  list.key_find(fields, "id")
  |> expect.to_equal(
    Ok(types.StringValue(fluid_ids.stable_id_to_string(stable))),
  )
  compressor |> expect.to_equal(expected_compressor)
  schema.validate_root(identifier_fixture.stored(), value)
  |> expect.to_equal(Ok(Nil))
}

pub fn identifier_nested_defaults_follow_pinned_order_test() {
  let stored = identifier_fixture.full_stored()
  let base = fluid_ids.new(identifier_fixture.session())
  let #(expected, ids) = generated_ids(base, 4)
  let candidate =
    identifier_fixture.full_root(
      types.ObjectValue(identifier_fixture.point_type, [
        #("label", types.StringValue("child")),
      ]),
      [
        types.ObjectValue(identifier_fixture.point_type, [
          #("label", types.StringValue("array")),
        ]),
      ],
      [],
      [
        #(
          "map",
          types.ObjectValue(identifier_fixture.point_type, [
            #("label", types.StringValue("map")),
          ]),
        ),
      ],
    )
  let initial =
    identifier_fixture.full_root(
      identifier_fixture.point("child-explicit", "before"),
      [],
      [],
      [],
    )
  let state =
    identifier_fixture.state(stored, identifier_fixture.full_view(), initial)
  let assert Ok(#(state, Some(commit), _, compressor)) =
    tree_runtime.author_edit(state, types.SetField([], candidate), base)
  let assert [map_id, array_id, child_id, revision] = ids
  tree_kernel.read(state, ["byKey", "map", "id"])
  |> expect.to_equal(Ok(Some(types.StringValue(map_id))))
  tree_kernel.read(state, ["left", "0", "id"])
  |> expect.to_equal(Ok(Some(types.StringValue(array_id))))
  tree_kernel.read(state, ["child", "id"])
  |> expect.to_equal(Ok(Some(types.StringValue(child_id))))
  commit.revision
  |> fluid_ids.stable_id_to_string
  |> expect.to_equal(revision)
  compressor |> expect.to_equal(expected)
}

pub fn identifier_array_insert_roots_allocate_forward_test() {
  let stored = identifier_fixture.full_stored()
  let base = fluid_ids.new(identifier_fixture.session())
  let #(expected, ids) = generated_ids(base, 3)
  let initial =
    identifier_fixture.full_root(
      identifier_fixture.point("child-explicit", "before"),
      [],
      [],
      [],
    )
  let state =
    identifier_fixture.state(stored, identifier_fixture.full_view(), initial)
  let roots = [
    types.ObjectValue(identifier_fixture.point_type, [
      #("label", types.StringValue("A")),
    ]),
    types.ObjectValue(identifier_fixture.point_type, [
      #("label", types.StringValue("B")),
    ]),
  ]
  let assert Ok(#(state, Some(commit), _, compressor)) =
    tree_runtime.author_edit(state, types.ArrayInsert(["left"], 0, roots), base)
  let assert [a_id, b_id, revision] = ids
  tree_kernel.read(state, ["left", "0", "id"])
  |> expect.to_equal(Ok(Some(types.StringValue(a_id))))
  tree_kernel.read(state, ["left", "1", "id"])
  |> expect.to_equal(Ok(Some(types.StringValue(b_id))))
  commit.revision
  |> fluid_ids.stable_id_to_string
  |> expect.to_equal(revision)
  compressor |> expect.to_equal(expected)
}

pub fn identifier_explicit_strings_do_not_allocate_test() {
  let stored = identifier_fixture.stored()
  let before =
    identifier_fixture.state(
      stored,
      identifier_fixture.view("Identifier"),
      identifier_fixture.point("before", "before"),
    )
  let base = fluid_ids.new(identifier_fixture.session())
  let #(expected, ids) = generated_ids(base, 1)
  let assert Ok(#(after, Some(commit), _, compressor)) =
    tree_runtime.author_edit(
      before,
      types.SetField([], identifier_fixture.point("", "empty")),
      base,
    )
  let assert Ok(data) = tree_kernel.visible_data(after)
  data.root |> expect.to_equal(Some(identifier_fixture.point("", "empty")))
  commit.revision
  |> fluid_ids.stable_id_to_string
  |> expect.to_equal(list.first(ids) |> expect.to_be_ok())
  compressor |> expect.to_equal(expected)
}

pub fn identifier_invalid_insert_preserves_compressor_test() {
  let stored = identifier_fixture.stored()
  let before =
    identifier_fixture.state(
      stored,
      identifier_fixture.view("Identifier"),
      identifier_fixture.point("before", "before"),
    )
  let base = fluid_ids.new(identifier_fixture.session())
  let invalid =
    types.ObjectValue(identifier_fixture.point_type, [
      #("label", types.NumberValue(1.0)),
    ])
  let assert Error(_) =
    tree_runtime.author_edit(before, types.SetField([], invalid), base)
  let #(expected, ids) = generated_ids(base, 2)
  let valid =
    types.ObjectValue(identifier_fixture.point_type, [
      #("label", types.StringValue("valid")),
    ])
  let assert Ok(#(after, Some(commit), _, compressor)) =
    tree_runtime.author_edit(before, types.SetField([], valid), base)
  let assert [identifier, revision] = ids
  tree_kernel.read(after, ["id"])
  |> expect.to_equal(Ok(Some(types.StringValue(identifier))))
  commit.revision
  |> fluid_ids.stable_id_to_string
  |> expect.to_equal(revision)
  compressor |> expect.to_equal(expected)
}

pub fn identifier_move_preserves_value_and_node_reference_test() {
  let stored = identifier_fixture.full_stored()
  let before =
    identifier_fixture.state(
      stored,
      identifier_fixture.full_view(),
      identifier_fixture.full_root(
        identifier_fixture.point("child", "child"),
        [identifier_fixture.point("moved", "moved")],
        [],
        [],
      ),
    )
  let assert Ok(reference) = tree_kernel.reference_at(before, ["left", "0"])
  let compressor = fluid_ids.new(identifier_fixture.session())
  let #(expected, _) = generated_ids(compressor, 1)
  let assert Ok(#(after, Some(_), _, compressor)) =
    tree_runtime.author_edit(
      before,
      types.ArrayMove(["left"], 0, 1, ["right"], 0),
      compressor,
    )
  tree_kernel.read(after, ["right", "0"])
  |> expect.to_equal(Ok(Some(identifier_fixture.point("moved", "moved"))))
  tree_kernel.reference_at(after, ["right", "0"])
  |> expect.to_equal(Ok(reference))
  compressor |> expect.to_equal(expected)
}

pub fn identifier_retry_reuses_authored_value_test() {
  let stored = identifier_fixture.stored()
  let before =
    identifier_fixture.state(
      stored,
      identifier_fixture.view("Identifier"),
      identifier_fixture.point("before", "before"),
    )
  let base = fluid_ids.new(identifier_fixture.session())
  let assert Ok(#(after, Some(commit), _, compressor)) =
    tree_runtime.author_edit(
      before,
      types.SetField(
        [],
        types.ObjectValue(identifier_fixture.point_type, [
          #("label", types.StringValue("generated")),
        ]),
      ),
      base,
    )
  let assert Ok([retry]) = tree_kernel.resubmit_commits(after)
  let assert Ok(authored) =
    tree_runtime.encode_commit(commit, after, compressor)
  let assert Ok(retried) = tree_runtime.encode_commit(retry, after, compressor)
  json.to_string(retried) |> expect.to_equal(json.to_string(authored))
}

pub fn identifier_schema_preserves_field_kind_test() {
  let stored = identifier_fixture.stored()
  schema.field_schema(stored, identifier_fixture.point_type, "id")
  |> expect.to_equal(
    Ok(
      schema.FieldSchema(schema.Identifier, ["com.fluidframework.leaf.string"]),
    ),
  )
  schema.stored_to_json(stored)
  |> schema.stored_from_json
  |> expect.to_equal(Ok(stored))
}

pub fn identifier_field_batch_preserves_unknown_strings_test() {
  let compressor = fluid_ids.new(identifier_fixture.sender_session())
  [
    "customer-17",
    "50000000-0000-4000-8000-000000000005",
    "4b825dc6-5768-5c1e-9a66-9e0f9e2f3f45",
    "客户-🌊",
  ]
  |> list.each(fn(identifier) {
    let value = identifier_fixture.point(identifier, "ordinary")
    let assert Ok(encoded) =
      field_batch.encode_with_context(
        [[value]],
        Some(identifier_fixture.stored()),
        field_batch.SummaryIds(compressor),
      )
    field_batch.decode_with_schema(encoded, Some(identifier_fixture.stored()))
    |> expect.to_equal(Ok([[value]]))
  })
}

pub fn identifier_direct_set_is_atomic_error_test() {
  expect_atomic_error(types.SetField(["id"], types.StringValue("replacement")))
}

pub fn identifier_same_value_set_is_atomic_error_test() {
  expect_atomic_error(types.SetField(
    ["id"],
    types.StringValue("literal-custom-id"),
  ))
}

pub fn identifier_clear_is_atomic_error_test() {
  expect_atomic_error(types.ClearField(["id"]))
}

pub fn identifier_parent_replacement_is_allowed_test() {
  let stored = identifier_fixture.stored()
  let before =
    identifier_fixture.state(
      stored,
      identifier_fixture.view("Identifier"),
      identifier_fixture.point("literal-custom-id", "before"),
    )
  let compressor = fluid_ids.new(identifier_fixture.session())
  let assert Ok(before_reference) = tree_kernel.reference_at(before, [])
  let assert Ok(#(after, Some(_), events, _)) =
    tree_runtime.author_edit(
      before,
      types.SetField([], identifier_fixture.point("replacement-id", "after")),
      compressor,
    )
  tree_kernel.visible_data(after)
  |> expect.to_not_equal(tree_kernel.visible_data(before))
  events.events |> expect.to_equal([tree_kernel.TreeChanged(True)])
  let assert Ok(after_reference) = tree_kernel.reference_at(after, [])
  after_reference |> expect.to_not_equal(before_reference)
  tree_kernel.read_reference(after, after_reference)
  |> expect.to_equal(Ok(identifier_fixture.point("replacement-id", "after")))
}

pub fn identifier_duplicate_custom_strings_remain_distinct_nodes_test() {
  let stored = identifier_fixture.pair_stored()
  let pair =
    types.ObjectValue("Pair", [
      #("left", identifier_fixture.point("duplicate", "left")),
      #("right", identifier_fixture.point("duplicate", "right")),
    ])
  let state =
    identifier_fixture.state(stored, identifier_fixture.pair_view(), pair)
  let assert Ok(left) = tree_kernel.reference_at(state, ["left"])
  let assert Ok(right) = tree_kernel.reference_at(state, ["right"])
  left |> expect.to_not_equal(right)
  tree_kernel.read_reference(state, left)
  |> expect.to_equal(Ok(identifier_fixture.point("duplicate", "left")))
  tree_kernel.read_reference(state, right)
  |> expect.to_equal(Ok(identifier_fixture.point("duplicate", "right")))
}

pub fn identifier_to_value_upgrade_preserves_content_test() {
  let stored = identifier_fixture.stored()
  let before =
    identifier_fixture.state(
      stored,
      identifier_fixture.view("Identifier"),
      identifier_fixture.point("literal-custom-id", "before"),
    )
  let assert Ok(before_reference) = tree_kernel.reference_at(before, ["id"])
  let compressor = fluid_ids.new(identifier_fixture.session())
  let assert Ok(#(after, Some(_), events, _)) =
    tree_runtime.author_upgrade(
      before,
      identifier_fixture.view("Value"),
      compressor,
    )
  tree_kernel.visible_data(after)
  |> expect.to_equal(tree_kernel.visible_data(before))
  tree_kernel.reference_at(after, ["id"])
  |> expect.to_equal(Ok(before_reference))
  events.events |> expect.to_equal([tree_kernel.SchemaChanged(True)])
  tree_kernel.stored_schema(after)
  |> schema.field_schema(identifier_fixture.point_type, "id")
  |> expect.to_equal(
    Ok(schema.FieldSchema(schema.Required, ["com.fluidframework.leaf.string"])),
  )
}

pub fn value_to_identifier_upgrade_is_rejected_test() {
  let value_stored =
    identifier_fixture.view("Value")
    |> schema.view_to_stored
  let assert Error(_) =
    schema.prepare_upgrade(value_stored, identifier_fixture.view("Identifier"))
  Nil
}

pub fn wider_view_cannot_mutate_stored_identifier_test() {
  let stored = identifier_fixture.stored()
  let state =
    identifier_fixture.state(
      stored,
      identifier_fixture.view("Value"),
      identifier_fixture.point("literal-custom-id", "before"),
    )
  let assert Error(_) =
    tree_runtime.author_edit(
      state,
      types.SetField(["id"], types.StringValue("replacement")),
      fluid_ids.new(identifier_fixture.session()),
    )
  tree_kernel.read(state, ["id"])
  |> expect.to_equal(Ok(Some(types.StringValue("literal-custom-id"))))
}

fn expect_atomic_error(edit: types.Edit) {
  let stored = identifier_fixture.stored()
  let state =
    identifier_fixture.state(
      stored,
      identifier_fixture.view("Identifier"),
      identifier_fixture.point("literal-custom-id", "before"),
    )
  let compressor = fluid_ids.new(identifier_fixture.session())
  let assert Ok(before_reference) = tree_kernel.reference_at(state, ["id"])
  let before_data = tree_kernel.visible_data(state)
  let before_history = tree_kernel.history_view(state)

  let assert Error(_) = tree_kernel.validate_edit(state, edit)
  let assert Error(_) = tree_runtime.author_edit(state, edit, compressor)
  let assert Ok(open) = transaction.begin(state, compressor, [])
  let assert Error(_) = transaction.apply_edit(open, edit)
  let assert Ok(#(transaction.NoCommit(restored, restored_compressor), events)) =
    transaction.finish(open)

  tree_kernel.visible_data(restored) |> expect.to_equal(before_data)
  tree_kernel.history_view(restored) |> expect.to_equal(before_history)
  tree_kernel.history_view(restored).pending |> expect.to_equal([])
  tree_kernel.reference_at(restored, ["id"])
  |> expect.to_equal(Ok(before_reference))
  tree_kernel.read_reference(restored, before_reference)
  |> expect.to_equal(Ok(types.StringValue("literal-custom-id")))
  restored_compressor |> expect.to_equal(compressor)
  events |> expect.to_equal(tree_kernel.ChangeEvents([], False))
  Nil
}

fn generated_ids(
  compressor: fluid_ids.Compressor,
  count: Int,
) -> #(fluid_ids.Compressor, List(String)) {
  case count {
    0 -> #(compressor, [])
    _ -> {
      let assert Ok(#(compressor, local)) = fluid_ids.generate(compressor)
      let assert Ok(stable) = fluid_ids.decompress(compressor, local)
      let #(compressor, rest) = generated_ids(compressor, count - 1)
      #(compressor, [fluid_ids.stable_id_to_string(stable), ..rest])
    }
  }
}

fn identifier_scenario(case_name: String, scenario_id: String) -> json.Json {
  let assert Ok(fixture) = fixtures.load(case_name)
  let assert Ok(VObject(root)) =
    json_ot.parse_json(json.to_string(fixture.input))
  let assert Ok(VArray(scenarios)) = list.key_find(root, "scenarios")
  let selected =
    list.filter(scenarios, fn(scenario) {
      case scenario {
        VObject(fields) ->
          list.key_find(fields, "id") == Ok(VString(scenario_id))
        _ -> False
      }
    })
  root
  |> list.key_set("scenarios", VArray(selected))
  |> VObject
  |> json_ot.to_json
}

fn update_scenario_actions(
  input: json.Json,
  scenario_id: String,
  update: fn(List(JsonValue)) -> List(JsonValue),
) -> json.Json {
  let assert Ok(VObject(root)) = json_ot.parse_json(json.to_string(input))
  let assert Ok(VArray(scenarios)) = list.key_find(root, "scenarios")
  let scenarios =
    list.map(scenarios, fn(scenario) {
      case scenario {
        VObject(fields) ->
          case list.key_find(fields, "id"), list.key_find(fields, "actions") {
            Ok(VString(id)), Ok(VArray(actions)) if id == scenario_id ->
              VObject(list.key_set(fields, "actions", VArray(update(actions))))
            _, _ -> scenario
          }
        _ -> scenario
      }
    })
  root
  |> list.key_set("scenarios", VArray(scenarios))
  |> VObject
  |> json_ot.to_json
}

fn replacement_action(label: String) -> JsonValue {
  VObject([
    #("op", VString("set")),
    #("path", VArray([VString("child")])),
    #(
      "value",
      VObject([
        #("schema", VString(identifier_fixture.point_type)),
        #(
          "fields",
          VObject([
            #("id", VString("literal-custom-id")),
            #("label", VString(label)),
          ]),
        ),
      ]),
    ),
  ])
}

fn retry_label_action(label: String) -> JsonValue {
  VObject([
    #("op", VString("set")),
    #(
      "path",
      VArray([
        VString("left"),
        VNumber(NInt(2)),
        VString("label"),
      ]),
    ),
    #("value", VString(label)),
  ])
}

fn update_observation_field(
  value: JsonValue,
  observation_id: String,
  key: String,
  replacement: JsonValue,
) -> JsonValue {
  case value {
    VObject(root) ->
      case list.key_find(root, "observations") {
        Ok(VArray(observations)) ->
          VObject(list.key_set(
            root,
            "observations",
            VArray(
              list.map(observations, fn(observation) {
                case observation {
                  VObject(fields) ->
                    case list.key_find(fields, "id") {
                      Ok(VString(id)) if id == observation_id ->
                        VObject(list.key_set(fields, key, replacement))
                      _ -> observation
                    }
                  _ -> observation
                }
              }),
            ),
          ))
        _ -> value
      }
    _ -> value
  }
}

fn assert_identifier_case(name: String) -> Nil {
  let assert Ok(fixture) = fixtures.load(name)
  let actual = case identifier_fixture.run(fixture.input) {
    Ok(value) -> value
    Error(error) -> panic as { error }
  }
  let assert Ok(actual) = json_ot.parse_json(json.to_string(actual))
  let assert Ok(expected) = json_ot.parse_json(json.to_string(fixture.expected))
  let #(actual, expected) = case
    normalize_identifier_case(fixture.input, actual, expected)
  {
    Ok(value) -> value
    Error(error) -> panic as { error }
  }
  let #(actual, expected) = native_projection(actual, expected)
  fixtures.first_difference(json_ot.to_json(actual), json_ot.to_json(expected))
  |> expect.to_equal(Ok(Nil))
}

fn native_projection(
  actual: JsonValue,
  expected: JsonValue,
) -> #(JsonValue, JsonValue) {
  case actual, expected {
    VObject(actual), VObject(expected) -> {
      let expected =
        list.filter(expected, fn(entry) {
          !list.contains(
            [
              "originalError",
              "upstreamAccepted",
              "decodedByUpstream",
              "beforeNode",
              "afterNode",
            ],
            entry.0,
          )
        })
      let pairs =
        list.map(expected, fn(entry) {
          let actual = list.key_find(actual, entry.0) |> result.unwrap(VNull)
          let #(actual, expected) = native_projection(actual, entry.1)
          #(#(entry.0, actual), #(entry.0, expected))
        })
      #(
        VObject(list.map(pairs, fn(pair) { pair.0 })),
        VObject(list.map(pairs, fn(pair) { pair.1 })),
      )
    }
    VArray(actual), VArray(expected) ->
      case project_array(actual, expected) {
        Ok(value) -> value
        Error(Nil) -> #(VArray(actual), VArray(expected))
      }
    _, _ -> #(actual, expected)
  }
}

fn normalize_identifier_case(
  input: json.Json,
  actual: JsonValue,
  expected: JsonValue,
) -> Result(#(JsonValue, JsonValue), String) {
  use actual <- result.try(normalize_initial_summary(input, actual, False))
  use expected <- result.try(normalize_initial_summary(input, expected, True))
  Ok(#(actual, normalize_initialization_offsets(actual, expected)))
}

fn normalize_initialization_offsets(
  actual: JsonValue,
  expected: JsonValue,
) -> JsonValue {
  case actual, expected {
    VObject(actual_root), VObject(expected_root) ->
      case
        list.key_find(actual_root, "observations"),
        list.key_find(expected_root, "observations")
      {
        Ok(VArray(actual_observations)), Ok(VArray(expected_observations)) ->
          VObject(list.key_set(
            expected_root,
            "observations",
            VArray(
              list.map(expected_observations, fn(expected) {
                case expected {
                  VObject(expected_fields) ->
                    case list.key_find(expected_fields, "id") {
                      Ok(VString(id)) ->
                        case find_observation(actual_observations, id) {
                          Ok(actual_fields) ->
                            VObject(normalize_observation_offset(
                              id,
                              actual_fields,
                              expected_fields,
                            ))
                          Error(_) -> expected
                        }
                      _ -> expected
                    }
                  _ -> expected
                }
              }),
            ),
          ))
        _, _ -> expected
      }
    _, _ -> expected
  }
}

fn find_observation(
  observations: List(JsonValue),
  id: String,
) -> Result(List(#(String, JsonValue)), Nil) {
  use observation <- result.try(
    list.find(observations, fn(observation) {
      case observation {
        VObject(fields) -> list.key_find(fields, "id") == Ok(VString(id))
        _ -> False
      }
    }),
  )
  case observation {
    VObject(fields) -> Ok(fields)
    _ -> Error(Nil)
  }
}

fn normalize_observation_offset(
  id: String,
  actual: List(#(String, JsonValue)),
  expected: List(#(String, JsonValue)),
) -> List(#(String, JsonValue)) {
  case id {
    "allocation-order" ->
      list.key_find(expected, "events")
      |> result.map(shift_operation_array)
      |> result.map(fn(value) { list.key_set(expected, "events", value) })
      |> result.unwrap(expected)
    "transaction-abort" | "nested-abort" ->
      normalize_shifted_string_field(actual, expected, "generated")
    "retry-resubmit" ->
      ["identifier", "acceptedIdentifier"]
      |> list.fold(expected, fn(fields, key) {
        normalize_shifted_string_field(actual, fields, key)
      })
    "remove-retain-repair" ->
      list.key_find(expected, "repair")
      |> result.map(shift_repair_operations)
      |> result.map(fn(value) { list.key_set(expected, "repair", value) })
      |> result.unwrap(expected)
    _ -> expected
  }
}

fn normalize_shifted_string_field(
  actual: List(#(String, JsonValue)),
  expected: List(#(String, JsonValue)),
  key: String,
) -> List(#(String, JsonValue)) {
  case list.key_find(actual, key), list.key_find(expected, key) {
    Ok(VString(actual)), Ok(VString(expected_value)) ->
      case shifted_initialization_id(actual, expected_value) {
        True -> list.key_set(expected, key, VString(actual))
        False -> expected
      }
    _, _ -> expected
  }
}

fn shifted_initialization_id(actual: String, expected: String) -> Bool {
  case string.split(actual, "-"), string.split(expected, "-") {
    [a0, a1, a2, a3, a4], [e0, e1, e2, e3, e4]
      if a0 == e0 && a1 == e1 && a2 == e2 && a3 == e3
    ->
      case int.base_parse(a4, 16), int.base_parse(e4, 16) {
        Ok(actual), Ok(expected) -> expected == actual + 1 && actual >= 5
        _, _ -> False
      }
    _, _ -> False
  }
}

fn shift_operation_array(value: JsonValue) -> JsonValue {
  case value {
    VArray(events) ->
      VArray(
        list.map(events, fn(event) {
          case event {
            VObject(fields) ->
              case list.key_find(fields, "op") {
                Ok(VNumber(NInt(value))) ->
                  VObject(list.key_set(fields, "op", VNumber(NInt(value - 1))))
                _ -> event
              }
            _ -> event
          }
        }),
      )
    _ -> value
  }
}

fn shift_repair_operations(value: JsonValue) -> JsonValue {
  case value {
    VArray(entries) ->
      VArray(
        list.map(entries, fn(entry) {
          case entry {
            VArray([VNumber(NInt(operation)), minor, tree]) ->
              VArray([VNumber(NInt(operation - 1)), minor, tree])
            _ -> entry
          }
        }),
      )
    _ -> value
  }
}

fn normalize_initial_summary(
  input: json.Json,
  value: JsonValue,
  upstream: Bool,
) -> Result(JsonValue, String) {
  case value {
    VObject(root) ->
      case list.key_find(root, "observations") {
        Ok(VArray(observations)) -> {
          use observations <- result.try(
            list.try_map(observations, fn(observation) {
              case observation {
                VObject(fields) ->
                  case
                    list.key_find(fields, "id"),
                    list.key_find(fields, "summary")
                  {
                    Ok(VString("initial-summary-defaults")), Ok(summary) -> {
                      use summary <- result.try(
                        case
                          identifier_fixture.initial_summary_semantics(
                            input,
                            summary,
                            upstream,
                          )
                        {
                          Ok(summary) ->
                            json_ot.parse_json(json.to_string(summary))
                            |> result.map_error(string.inspect)
                          Error(_) if upstream ->
                            Ok(VObject([#("invalidSummary", summary)]))
                          Error(error) -> Error(error)
                        },
                      )
                      let fields = list.key_set(fields, "summary", summary)
                      let fields = case upstream {
                        True ->
                          list.key_set(
                            fields,
                            "allocationEvents",
                            list.key_find(fields, "allocationEvents")
                              |> result.map(drop_initial_revision_event)
                              |> result.unwrap(VNull),
                          )
                        False -> fields
                      }
                      Ok(VObject(fields))
                    }
                    _, _ -> Ok(observation)
                  }
                _ -> Ok(observation)
              }
            }),
          )
          Ok(VObject(list.key_set(root, "observations", VArray(observations))))
        }
        _ -> Ok(value)
      }
    _ -> Ok(value)
  }
}

fn drop_initial_revision_event(value: JsonValue) -> JsonValue {
  case value {
    VArray(events) ->
      VArray(
        list.filter(events, fn(event) {
          case event {
            VObject(fields) ->
              list.key_find(fields, "kind") != Ok(VString("revision"))
            _ -> True
          }
        }),
      )
    _ -> value
  }
}

fn project_array(
  actual: List(JsonValue),
  expected: List(JsonValue),
) -> Result(#(JsonValue, JsonValue), Nil) {
  case actual, expected {
    [], [] -> Ok(#(VArray([]), VArray([])))
    [actual, ..actual_rest], [expected, ..expected_rest] -> {
      let #(actual, expected) = native_projection(actual, expected)
      use #(actual_rest, expected_rest) <- result.try(project_array(
        actual_rest,
        expected_rest,
      ))
      let assert VArray(actual_rest) = actual_rest
      let assert VArray(expected_rest) = expected_rest
      Ok(#(VArray([actual, ..actual_rest]), VArray([expected, ..expected_rest])))
    }
    _, _ -> Error(Nil)
  }
}

fn remove_tail_ranges(value: JsonValue) -> JsonValue {
  case value {
    VObject(root) ->
      case list.key_find(root, "scenarios") {
        Ok(VArray(scenarios)) ->
          VObject(list.key_set(
            root,
            "scenarios",
            VArray(
              list.map(scenarios, fn(scenario) {
                case scenario {
                  VObject(fields) ->
                    case list.key_find(fields, "id") {
                      Ok(json_ot.VString("summary-tail")) ->
                        case list.key_find(fields, "actions") {
                          Ok(VArray(actions)) ->
                            VObject(list.key_set(
                              fields,
                              "actions",
                              VArray(
                                list.map(actions, fn(action) {
                                  case action {
                                    VObject(action_fields) ->
                                      case list.key_find(action_fields, "op") {
                                        Ok(json_ot.VString("apply-tail")) ->
                                          VObject(list.key_set(
                                            action_fields,
                                            "idRanges",
                                            VArray([]),
                                          ))
                                        _ -> action
                                      }
                                    _ -> action
                                  }
                                }),
                              ),
                            ))
                          _ -> scenario
                        }
                      _ -> scenario
                    }
                  _ -> scenario
                }
              }),
            ),
          ))
        _ -> value
      }
    _ -> value
  }
}
