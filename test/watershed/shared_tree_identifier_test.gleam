import gleam/json
import gleam/list
import gleam/option.{Some}
import gleam/result
import gleam/string
import startest/expect
import watershed/fluid_ids
import watershed/json_ot.{type JsonValue, VArray, VNull, VObject}
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

fn assert_identifier_case(name: String) -> Nil {
  let assert Ok(fixture) = fixtures.load(name)
  let assert Ok(actual) = identifier_fixture.run(fixture.input)
  let assert Ok(actual) = json_ot.parse_json(json.to_string(actual))
  let assert Ok(expected) = json_ot.parse_json(json.to_string(fixture.expected))
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
          && case entry.0, entry.1 {
            "summary", VObject(_) -> False
            _, _ -> True
          }
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
