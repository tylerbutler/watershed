import gleam/list
import gleam/option.{None, Some}
import gleam/result
import startest/expect
import watershed/fluid_ids
import watershed/tree/change
import watershed/tree/forest
import watershed/tree/history
import watershed/tree/schema
import watershed/tree/shared_change
import watershed/tree/types.{
  type TreeError, ArrayInsert, ArrayValue, DefaultCommit, InvalidHistory,
  NumberValue, ObjectValue, RedoCommit, SetField, UndoCommit,
}
import watershed/tree/undo_acceptance

const tree_schema = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.number\":{\"kind\":{\"leaf\":0}},\"Items\":{\"kind\":{\"object\":{\"\":{\"kind\":\"Sequence\",\"types\":[\"com.fluidframework.leaf.number\"]}}}},\"Point\":{\"kind\":{\"object\":{\"x\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.number\"]},\"y\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.number\"]}}}},\"Root\":{\"kind\":{\"object\":{\"items\":{\"kind\":\"Value\",\"types\":[\"Items\"]},\"point\":{\"kind\":\"Value\",\"types\":[\"Point\"]}}}}},\"root\":{\"kind\":\"Value\",\"types\":[\"Root\"]}}"

fn session() -> fluid_ids.SessionId {
  let assert Ok(id) =
    fluid_ids.session_id("00000000-0000-4000-8000-000000000001")
  id
}

fn peer_session() -> fluid_ids.SessionId {
  let assert Ok(id) =
    fluid_ids.session_id("00000000-0000-4000-8000-000000000002")
  id
}

fn other_peer_session() -> fluid_ids.SessionId {
  let assert Ok(id) =
    fluid_ids.session_id("00000000-0000-4000-8000-000000000003")
  id
}

fn revision(value: String) -> fluid_ids.StableId {
  let assert Ok(id) = fluid_ids.stable_id(value)
  id
}

fn revision_a() -> fluid_ids.StableId {
  revision("00000000-0000-4000-8000-00000000000a")
}

fn revision_b() -> fluid_ids.StableId {
  revision("00000000-0000-4000-8000-00000000000b")
}

fn revision_c() -> fluid_ids.StableId {
  revision("00000000-0000-4000-8000-00000000000c")
}

fn revision_undo() -> fluid_ids.StableId {
  revision("00000000-0000-4000-8000-00000000000d")
}

fn revision_redo() -> fluid_ids.StableId {
  revision("00000000-0000-4000-8000-00000000000e")
}

fn revision_later_trunk() -> fluid_ids.StableId {
  revision("00000000-0000-4000-8000-00000000000f")
}

fn revision_later_local() -> fluid_ids.StableId {
  revision("00000000-0000-4000-8000-000000000010")
}

fn revision_rollback() -> fluid_ids.StableId {
  revision("00000000-0000-4000-8000-000000000011")
}

type Allocation {
  Allocation(revisions: List(fluid_ids.StableId), order: change.IdentityOrder)
}

fn mint(
  allocation: Allocation,
) -> Result(#(fluid_ids.StableId, change.IdentityOrder, Allocation), TreeError) {
  case allocation.revisions {
    [] -> Error(InvalidHistory("rollback allocation is exhausted"))
    [revision, ..rest] ->
      Ok(#(revision, allocation.order, Allocation(rest, allocation.order)))
  }
}

fn root() {
  ObjectValue("Root", [
    #("items", ArrayValue("Items", [NumberValue(1.0), NumberValue(2.0)])),
    #(
      "point",
      ObjectValue("Point", [
        #("x", NumberValue(1.0)),
        #("y", NumberValue(2.0)),
      ]),
    ),
  ])
}

fn setup() -> #(
  history.History,
  types.RevertibleId,
  forest.Forest,
  change.IdentityOrder,
) {
  let assert Ok(stored) = schema.stored_from_string(tree_schema)
  let assert Ok(initial) =
    forest.new(
      revision("00000000-0000-4000-8000-000000000099"),
      stored,
      Some(root()),
    )
  let assert Ok(order) =
    change.identity_order([
      #(revision_a(), -5),
      #(revision_b(), -4),
      #(revision_c(), -3),
      #(revision_undo(), -2),
      #(revision_redo(), -1),
    ])
  let assert Ok(commit_a) =
    author(
      initial,
      revision_a(),
      SetField(["point", "x"], NumberValue(3.0)),
      order,
    )
  let assert Ok(after_a) = apply(initial, commit_a)
  let assert Ok(commit_b) =
    author(
      after_a,
      revision_b(),
      SetField(["point", "x"], NumberValue(7.0)),
      order,
    )
  let assert Ok(after_b) = apply(after_a, commit_b)
  let assert Ok(commit_c) =
    author(
      after_b,
      revision_c(),
      SetField(["point", "y"], NumberValue(9.0)),
      order,
    )
  let assert Ok(current) = apply(after_b, commit_c)
  let assert Ok(appended_a) =
    history.append_local(history.new(session()), commit_a)
  let assert Ok(appended_b) = history.append_local(appended_a.history, commit_b)
  let assert Ok(#(retained, id)) =
    history.retain_revertible(appended_b.history, revision_b(), DefaultCommit)
  let assert Ok(appended_c) = history.append_local(retained, commit_c)
  #(appended_c.history, id, current, order)
}

fn author(
  state: forest.Forest,
  revision: fluid_ids.StableId,
  edit: types.Edit,
  order: change.IdentityOrder,
) -> Result(history.Commit, TreeError) {
  author_as(state, revision, session(), edit, order)
}

fn author_as(
  state: forest.Forest,
  revision: fluid_ids.StableId,
  originator: fluid_ids.SessionId,
  edit: types.Edit,
  order: change.IdentityOrder,
) -> Result(history.Commit, TreeError) {
  use authored <- result.try(change.edit(
    schema_from_forest(state),
    state,
    revision,
    edit,
    order,
  ))
  Ok(history.Commit(revision, originator, shared_change.from_data(authored)))
}

fn schema_from_forest(state: forest.Forest) -> schema.StoredSchema {
  forest.stored_schema(state)
}

fn apply(
  state: forest.Forest,
  commit: history.Commit,
) -> Result(forest.Forest, TreeError) {
  use effects <- result.try(
    shared_change.effects(shared_change.TaggedChange(
      Some(commit.revision),
      None,
      commit.change,
    )),
  )
  list.try_fold(effects, state, fn(state, effect) {
    case effect {
      shared_change.DataDelta(delta) -> forest.apply_delta(state, delta)
      shared_change.SchemaDelta(_, _, _) -> Ok(state)
    }
  })
}

pub fn shared_tree_history_author_revert_defaults_to_undo_and_preserves_later_commit_test() {
  let #(state, id, current, order) = setup()
  let assert Ok(history.RevertAuthoring(target, inverse, UndoCommit)) =
    history.author_revert(state, id, revision_undo(), order)

  target.revision |> expect.to_equal(revision_b())
  inverse.revision |> expect.to_equal(revision_undo())
  let reverted = apply(current, inverse) |> expect.to_be_ok
  forest.read(reverted, ["point", "x"])
  |> expect.to_equal(Ok(Some(NumberValue(3.0))))
  forest.read(reverted, ["point", "y"])
  |> expect.to_equal(Ok(Some(NumberValue(9.0))))
}

pub fn shared_tree_history_author_revert_of_undo_returns_redo_test() {
  let #(state, _, _, order) = setup()
  let assert Ok(#(retained, id)) =
    history.retain_revertible(state, revision_c(), UndoCommit)
  let assert Ok(history.RevertAuthoring(target, inverse, RedoCommit)) =
    history.author_revert(retained, id, revision_redo(), order)

  target.revision |> expect.to_equal(revision_c())
  inverse.revision |> expect.to_equal(revision_redo())
}

pub fn shared_tree_history_author_revert_peer_target_preserves_later_trunk_and_pending_test() {
  let assert Ok(stored) = schema.stored_from_string(tree_schema)
  let assert Ok(initial) =
    forest.new(
      revision("00000000-0000-4000-8000-000000000099"),
      stored,
      Some(root()),
    )
  let assert Ok(order) =
    change.identity_order([
      #(revision_a(), -6),
      #(revision_b(), -5),
      #(revision_later_trunk(), -4),
      #(revision_later_local(), -3),
      #(revision_rollback(), -2),
      #(revision_undo(), -1),
    ])
  let assert Ok(commit_a) =
    author(
      initial,
      revision_a(),
      SetField(["point", "y"], NumberValue(3.0)),
      order,
    )
  let assert Ok(after_a) = apply(initial, commit_a)
  let assert Ok(peer_target) =
    author_as(
      initial,
      revision_b(),
      peer_session(),
      ArrayInsert(["items"], 1, [NumberValue(7.0)]),
      order,
    )
  let assert Ok(after_target) = apply(after_a, peer_target)
  let assert Ok(later_trunk) =
    author_as(
      after_target,
      revision_later_trunk(),
      other_peer_session(),
      ArrayInsert(["items"], 0, [NumberValue(9.0)]),
      order,
    )
  let assert Ok(after_trunk) = apply(after_target, later_trunk)
  let assert Ok(later_local) =
    author(
      after_trunk,
      revision_later_local(),
      ArrayInsert(["items"], 4, [NumberValue(10.0)]),
      order,
    )
  let assert Ok(current) = apply(after_trunk, later_local)

  let assert Ok(appended) =
    history.append_local(history.new(session()), commit_a)
  let assert Ok(#(acked, allocation)) =
    history.receive(
      appended.history,
      commit_a,
      types.SequencePoint(1, 0),
      0,
      0,
      Allocation([revision_rollback()], order),
      mint,
    )
  let assert Ok(#(received_target, allocation)) =
    history.receive(
      acked.history,
      peer_target,
      types.SequencePoint(2, 0),
      0,
      0,
      allocation,
      mint,
    )
  let assert Ok(#(retained, id)) =
    history.retain_revertible(
      received_target.history,
      revision_b(),
      DefaultCommit,
    )
  let assert Ok(#(received_trunk, _)) =
    history.receive(
      retained,
      later_trunk,
      types.SequencePoint(3, 0),
      2,
      0,
      allocation,
      mint,
    )
  let assert Ok(appended_local) =
    history.append_local(received_trunk.history, later_local)
  let authored =
    history.author_revert(appended_local.history, id, revision_undo(), order)
    |> expect.to_be_ok
  authored.kind |> expect.to_equal(UndoCommit)
  let reverted = apply(current, authored.inverse) |> expect.to_be_ok

  forest.read(reverted, ["items"])
  |> expect.to_equal(
    Ok(
      Some(
        ArrayValue("Items", [
          NumberValue(9.0),
          NumberValue(1.0),
          NumberValue(2.0),
          NumberValue(10.0),
        ]),
      ),
    ),
  )
}

pub fn shared_tree_history_revertible_allows_repeated_reverts_until_disposed_test() {
  let #(state, id, _, order) = setup()
  history.author_revert(state, id, revision_undo(), order)
  |> expect.to_be_ok
  history.author_revert(state, id, revision_redo(), order)
  |> expect.to_be_ok

  let assert Ok(disposed) = history.dispose_revertible(state, id)
  history.author_revert(disposed, id, revision_undo(), order)
  |> expect.to_equal(Error(InvalidHistory("revertible is already disposed")))
}

pub fn shared_tree_undo_object_set_preserves_later_field_test() {
  undo_acceptance.assert_object_set()
}

pub fn shared_tree_undo_object_replacement_pins_child_edit_conflict_test() {
  undo_acceptance.assert_object_replacement()
}

pub fn equal_value_reinsert_changes_live_reference_test() {
  undo_acceptance.assert_equal_value_reinsert_changes_live_reference()
}
