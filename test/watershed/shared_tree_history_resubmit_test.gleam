import gleam/option.{Some}
import startest/expect
import watershed/fluid_ids
import watershed/tree/change
import watershed/tree/forest
import watershed/tree/history
import watershed/tree/schema
import watershed/tree/types.{NumberValue, ObjectValue, SetField}

const tree_schema = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.number\":{\"kind\":{\"leaf\":0}},\"Point\":{\"kind\":{\"object\":{\"x\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.number\"]},\"y\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.number\"]}}}},\"Root\":{\"kind\":{\"object\":{\"point\":{\"kind\":\"Value\",\"types\":[\"Point\"]}}}}},\"root\":{\"kind\":\"Value\",\"types\":[\"Root\"]}}"

fn session() -> fluid_ids.SessionId {
  let assert Ok(value) =
    fluid_ids.session_id("00000000-0000-4000-8000-000000000001")
  value
}

fn revision(suffix: String) -> fluid_ids.StableId {
  let assert Ok(value) =
    fluid_ids.stable_id("00000000-0000-4000-8000-0000000000" <> suffix)
  value
}

fn commit(revision: fluid_ids.StableId) -> history.Commit {
  let assert Ok(order) = change.identity_order([#(revision, -1)])
  let assert Ok(checked) =
    change.from_data(change.to_data(change.empty()), order)
  history.Commit(revision, session(), checked)
}

fn scalar_commit(commit_revision: fluid_ids.StableId) -> history.Commit {
  let assert Ok(stored) = schema.stored_from_string(tree_schema)
  let view = revision("99")
  let root =
    ObjectValue("Root", [
      #(
        "point",
        ObjectValue("Point", [
          #("x", NumberValue(1.0)),
          #("y", NumberValue(2.0)),
        ]),
      ),
    ])
  let assert Ok(state) = forest.new(view, stored, Some(root))
  let assert Ok(order) = change.identity_order([#(commit_revision, -1)])
  let assert Ok(authored) =
    change.edit(
      stored,
      state,
      commit_revision,
      SetField(["point", "x"], NumberValue(11.0)),
      order,
    )
  history.Commit(commit_revision, session(), authored)
}

pub fn shared_tree_history_resubmit_rejects_duplicate_repairs_test() -> Nil {
  let pending = commit(revision("01"))
  let assert Ok(local) = history.append_local(history.new(session()), pending)
  history.resubmit(local.history, [
    #(pending.revision, []),
    #(pending.revision, []),
  ])
  |> expect.to_be_error
  history.pending(local.history) |> expect.to_equal([pending])
}

pub fn shared_tree_history_resubmit_rejects_extraneous_commit_test() -> Nil {
  let pending = commit(revision("01"))
  let assert Ok(local) = history.append_local(history.new(session()), pending)
  history.resubmit(local.history, [#(revision("02"), [])])
  |> expect.to_be_error
  history.pending(local.history) |> expect.to_equal([pending])
}

pub fn shared_tree_history_resubmits_own_scalar_build_without_repair_test() -> Nil {
  let pending = scalar_commit(revision("01"))
  let assert Ok(local) = history.append_local(history.new(session()), pending)
  history.resubmit(local.history, []) |> expect.to_equal(Ok([pending]))
}
