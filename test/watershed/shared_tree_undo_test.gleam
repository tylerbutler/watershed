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
  type TreeError, DefaultCommit, NumberValue, ObjectValue, RedoCommit, SetField,
  UndoCommit,
}

const tree_schema = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.number\":{\"kind\":{\"leaf\":0}},\"Point\":{\"kind\":{\"object\":{\"x\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.number\"]},\"y\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.number\"]}}}},\"Root\":{\"kind\":{\"object\":{\"point\":{\"kind\":\"Value\",\"types\":[\"Point\"]}}}}},\"root\":{\"kind\":\"Value\",\"types\":[\"Root\"]}}"

fn session() -> fluid_ids.SessionId {
  let assert Ok(id) =
    fluid_ids.session_id("00000000-0000-4000-8000-000000000001")
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

fn root() {
  ObjectValue("Root", [
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
  use authored <- result.try(change.edit(
    schema_from_forest(state),
    state,
    revision,
    edit,
    order,
  ))
  Ok(history.Commit(revision, session(), shared_change.from_data(authored)))
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
  let assert Ok(reverted) = apply(current, inverse)
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

pub fn shared_tree_history_revertible_allows_repeated_reverts_until_disposed_test() {
  let #(state, id, _, order) = setup()
  history.author_revert(state, id, revision_undo(), order)
  |> expect.to_be_ok
  history.author_revert(state, id, revision_redo(), order)
  |> expect.to_be_ok

  let assert Ok(disposed) = history.dispose_revertible(state, id)
  let _ =
    history.author_revert(disposed, id, revision_undo(), order)
    |> expect.to_be_error
  Nil
}
