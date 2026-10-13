import gleam/list
import gleam/option.{None, Some}
import startest/expect
import watershed/fluid_ids
import watershed/tree/array_fixture
import watershed/tree/change
import watershed/tree/forest
import watershed/tree/history
import watershed/tree/node
import watershed/tree/types
import watershed/tree_kernel

const items_type = "org.watershed.shared-tree.m3.Items"

fn session() -> fluid_ids.SessionId {
  let assert Ok(value) =
    fluid_ids.session_id("10000000-0000-4000-8000-000000000001")
  value
}

fn revision(value: String) -> fluid_ids.StableId {
  let assert Ok(value) = fluid_ids.stable_id(value)
  value
}

fn order(revisions: List(fluid_ids.StableId)) -> change.IdentityOrder {
  let assert Ok(value) =
    revisions
    |> list.index_map(fn(revision, index) { #(revision, index) })
    |> change.identity_order
  value
}

fn state_in_view(
  root: types.TreeValue,
  schema: String,
  view_id: fluid_ids.StableId,
) -> tree_kernel.TreeState {
  let initial = history.inspect(history.new(session())).sequenced
  let assert Ok(snapshot) =
    tree_kernel.snapshot_from_parts(
      view_id,
      array_fixture.stored(schema),
      forest.ForestData(Some(root), [], 0),
      initial,
    )
  let assert Ok(state) =
    tree_kernel.restore(
      snapshot,
      view_id,
      session(),
      array_fixture.view(schema),
    )
  state
}

fn state(root: types.TreeValue, schema: String) -> tree_kernel.TreeState {
  state_in_view(root, schema, array_fixture.view_id())
}

fn array_state(values: List(types.TreeValue)) -> tree_kernel.TreeState {
  state(types.ArrayValue(items_type, values), "rootArray")
}

fn object_state(
  left: List(types.TreeValue),
  right: List(types.TreeValue),
) -> tree_kernel.TreeState {
  state(
    types.ObjectValue("org.watershed.shared-tree.m3.Root", [
      #("left", types.ArrayValue(items_type, left)),
      #("right", types.ArrayValue(items_type, right)),
      #("byKey", types.MapValue("org.watershed.shared-tree.m3.ArrayMap", [])),
      #("narrow", types.ArrayValue("org.watershed.shared-tree.m3.Points", [])),
    ]),
    "objectArrays",
  )
}

fn apply(
  state: tree_kernel.TreeState,
  id: String,
  edit: types.Edit,
) -> tree_kernel.TreeState {
  let revision = revision(id)
  let assert Ok(#(state, _, _)) =
    tree_kernel.apply_local(state, revision, order([revision]), edit)
  state
}

pub fn shared_tree_node_resolves_path_edits_from_current_identity_test() {
  let state = object_state([], [])
  let assert Ok(root) = tree_kernel.reference_at(state, [])
  let assert Ok(left) = tree_kernel.reference_at(state, ["left"])
  let assert Ok(map) = tree_kernel.reference_at(state, ["byKey"])
  let value = types.StringValue("value")

  node.resolve(state, root, node.SetField("left", value))
  |> expect.to_equal(Ok(types.SetField(["left"], value)))
  node.resolve(state, root, node.ClearField("left"))
  |> expect.to_equal(Ok(types.ClearField(["left"])))
  node.resolve(state, map, node.MapSet("key", value))
  |> expect.to_equal(Ok(types.MapSet(["byKey"], "key", value)))
  node.resolve(state, map, node.MapDelete("key"))
  |> expect.to_equal(Ok(types.MapDelete(["byKey"], "key")))
  node.resolve(state, left, node.ArrayInsert(0, [value]))
  |> expect.to_equal(Ok(types.ArrayInsert(["left"], 0, [value])))
  node.resolve(state, left, node.ArrayRemove(0, 1))
  |> expect.to_equal(Ok(types.ArrayRemove(["left"], 0, 1)))
}

pub fn shared_tree_node_resolves_array_move_from_current_parents_test() {
  let state =
    object_state([types.StringValue("A"), types.StringValue("B")], [
      types.StringValue("C"),
    ])
  let assert Ok(left) = tree_kernel.reference_at(state, ["left"])
  let assert Ok(right) = tree_kernel.reference_at(state, ["right"])
  let moved =
    apply(
      state,
      "20000000-0000-4000-8000-000000000001",
      types.ArrayMove(["left"], 0, 1, ["right"], 1),
    )

  node.resolve(moved, left, node.ArrayMove(0, 1, right, 0))
  |> expect.to_equal(Ok(types.ArrayMove(["left"], 0, 1, ["right"], 0)))
}

pub fn shared_tree_node_removes_current_direct_child_after_reorder_test() {
  let state =
    array_state([
      types.StringValue("A"),
      types.StringValue("B"),
      types.StringValue("C"),
    ])
  let assert Ok(array) = tree_kernel.reference_at(state, [])
  let assert Ok(child) = tree_kernel.reference_at(state, ["1"])
  let reordered =
    apply(
      state,
      "20000000-0000-4000-8000-000000000002",
      types.ArrayMove([], 0, 1, [], 3),
    )

  node.resolve(reordered, array, node.RemoveNode(child))
  |> expect.to_equal(Ok(types.ArrayRemove([], 0, 1)))
}

pub fn shared_tree_node_moves_before_current_direct_sibling_test() {
  let state =
    object_state([types.StringValue("A"), types.StringValue("B")], [
      types.StringValue("C"),
      types.StringValue("D"),
    ])
  let assert Ok(left) = tree_kernel.reference_at(state, ["left"])
  let assert Ok(right) = tree_kernel.reference_at(state, ["right"])
  let assert Ok(child) = tree_kernel.reference_at(state, ["left", "1"])
  let assert Ok(before) = tree_kernel.reference_at(state, ["right", "1"])

  node.resolve(state, left, node.MoveNode(child, right, Some(before)))
  |> expect.to_equal(Ok(types.ArrayMove(["left"], 1, 2, ["right"], 1)))
  node.resolve(state, left, node.MoveNode(child, right, None))
  |> expect.to_equal(Ok(types.ArrayMove(["left"], 1, 2, ["right"], 2)))
}

pub fn shared_tree_node_preserves_native_self_move_resolution_test() {
  let state = array_state([types.StringValue("A"), types.StringValue("B")])
  let assert Ok(array) = tree_kernel.reference_at(state, [])
  let assert Ok(child) = tree_kernel.reference_at(state, ["0"])

  node.resolve(state, array, node.MoveNode(child, array, Some(child)))
  |> expect.to_equal(Ok(types.ArrayMove([], 0, 1, [], 0)))
}

pub fn shared_tree_node_rejects_nonmember_child_and_sibling_test() {
  let state = object_state([types.StringValue("A")], [types.StringValue("B")])
  let assert Ok(left) = tree_kernel.reference_at(state, ["left"])
  let assert Ok(right) = tree_kernel.reference_at(state, ["right"])
  let assert Ok(left_child) = tree_kernel.reference_at(state, ["left", "0"])
  let assert Ok(right_child) = tree_kernel.reference_at(state, ["right", "0"])

  node.resolve(state, left, node.RemoveNode(right_child))
  |> expect.to_equal(
    Error(types.InvalidEdit(["left"], "node is not a direct array child")),
  )
  node.resolve(state, left, node.MoveNode(left_child, right, Some(left_child)))
  |> expect.to_equal(
    Error(types.InvalidEdit(["right"], "node is not a direct array child")),
  )
}

pub fn shared_tree_node_rejects_detached_replaced_and_foreign_references_test() {
  let state = array_state([types.StringValue("A")])
  let assert Ok(array) = tree_kernel.reference_at(state, [])
  let assert Ok(child) = tree_kernel.reference_at(state, ["0"])
  let detached =
    apply(
      state,
      "20000000-0000-4000-8000-000000000003",
      types.ArrayRemove([], 0, 1),
    )
  node.resolve(detached, array, node.RemoveNode(child))
  |> expect.to_equal(Error(types.InvalidEdit([], "node is not attached")))

  let replaced =
    apply(
      detached,
      "20000000-0000-4000-8000-000000000004",
      types.ArrayInsert([], 0, [types.StringValue("A")]),
    )
  node.resolve(replaced, array, node.RemoveNode(child))
  |> expect.to_equal(Error(types.InvalidEdit([], "node is not attached")))

  let other_view = revision("20000000-0000-4000-8000-000000000099")
  let other =
    state_in_view(
      types.ArrayValue(items_type, [types.StringValue("A")]),
      "rootArray",
      other_view,
    )
  let assert Ok(foreign) = tree_kernel.reference_at(other, ["0"])
  node.resolve(replaced, array, node.RemoveNode(foreign))
  |> expect.to_equal(
    Error(types.InvalidEdit([], "node reference belongs to another view")),
  )
}

pub fn shared_tree_node_reacquires_retained_identity_after_undo_test() {
  let state = array_state([types.StringValue("A")])
  let assert Ok(array) = tree_kernel.reference_at(state, [])
  let assert Ok(child) = tree_kernel.reference_at(state, ["0"])
  let remove_revision = revision("20000000-0000-4000-8000-000000000005")
  let undo_revision = revision("20000000-0000-4000-8000-000000000006")
  let identity_order = order([remove_revision, undo_revision])
  let assert Ok(#(removed, commit, _)) =
    tree_kernel.apply_local(
      state,
      remove_revision,
      identity_order,
      types.ArrayRemove([], 0, 1),
    )
  let assert Ok(#(retained, revertible)) =
    tree_kernel.retain_revertible(removed, commit.revision, types.DefaultCommit)
  let assert Ok(#(restored, _, _, _)) =
    tree_kernel.revert(retained, revertible, undo_revision, identity_order)

  node.resolve(restored, array, node.RemoveNode(child))
  |> expect.to_equal(Ok(types.ArrayRemove([], 0, 1)))
}
