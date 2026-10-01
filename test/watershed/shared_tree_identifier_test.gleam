import gleam/option.{Some}
import startest/expect
import watershed/fluid_ids
import watershed/tree/identifier_fixture
import watershed/tree/runtime as tree_runtime
import watershed/tree/schema
import watershed/tree/transaction
import watershed/tree/types
import watershed/tree_kernel

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
