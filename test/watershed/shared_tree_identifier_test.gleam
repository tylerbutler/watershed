import gleam/json
import gleam/list
import gleam/option.{Some}
import startest/expect
import watershed/fluid_ids
import watershed/tree/codec/field_batch
import watershed/tree/identifier
import watershed/tree/identifier_fixture
import watershed/tree/runtime as tree_runtime
import watershed/tree/schema
import watershed/tree/transaction
import watershed/tree/types
import watershed/tree_kernel

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
