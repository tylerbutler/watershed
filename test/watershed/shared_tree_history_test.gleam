import gleam/option.{None, Some}
import startest/expect
import watershed/fluid_ids
import watershed/tree/change
import watershed/tree/forest
import watershed/tree/history
import watershed/tree/schema
import watershed/tree/types.{
  type TreeError, InvalidHistory, NumberValue, ObjectValue, SetField,
}

const tree_schema = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.number\":{\"kind\":{\"leaf\":0}},\"Point\":{\"kind\":{\"object\":{\"x\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.number\"]},\"y\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.number\"]}}}},\"Root\":{\"kind\":{\"object\":{\"point\":{\"kind\":\"Value\",\"types\":[\"Point\"]}}}}},\"root\":{\"kind\":\"Value\",\"types\":[\"Root\"]}}"

fn session(value: String) -> fluid_ids.SessionId {
  let assert Ok(id) = fluid_ids.session_id(value)
  id
}

fn revision(value: String) -> fluid_ids.StableId {
  let assert Ok(id) = fluid_ids.stable_id(value)
  id
}

fn local_session() -> fluid_ids.SessionId {
  session("00000000-0000-4000-8000-000000000001")
}

fn peer_session() -> fluid_ids.SessionId {
  session("00000000-0000-4000-8000-000000000002")
}

fn revision_a() -> fluid_ids.StableId {
  revision("00000000-0000-4000-8000-00000000000a")
}

fn revision_b() -> fluid_ids.StableId {
  revision("00000000-0000-4000-8000-00000000000b")
}

fn no_mint(
  state: Nil,
) -> Result(#(fluid_ids.StableId, change.IdentityOrder, Nil), TreeError) {
  let _ = state
  Error(InvalidHistory("unexpected rollback allocation"))
}

fn empty_commit(
  revision: fluid_ids.StableId,
  originator: fluid_ids.SessionId,
) -> history.Commit {
  let assert Ok(order) = change.identity_order([#(revision, -1)])
  let assert Ok(checked) =
    change.from_data(change.to_data(change.empty()), order)
  history.Commit(revision, originator, checked)
}

fn stored_schema() -> schema.StoredSchema {
  let assert Ok(stored) = schema.stored_from_string(tree_schema)
  stored
}

fn point(x: Float, y: Float) {
  ObjectValue("Point", [
    #("x", NumberValue(x)),
    #("y", NumberValue(y)),
  ])
}

fn root() {
  ObjectValue("Root", [#("point", point(1.0, 2.0))])
}

fn real_commit() -> #(history.Commit, forest.Forest) {
  let view = revision("00000000-0000-4000-8000-000000000099")
  let assert Ok(state) = forest.new(view, stored_schema(), Some(root()))
  let assert Ok(order) = change.identity_order([#(revision_a(), -1)])
  let assert Ok(authored) =
    change.edit(
      stored_schema(),
      state,
      revision_a(),
      SetField(["point", "x"], NumberValue(7.0)),
      order,
    )
  #(history.Commit(revision_a(), local_session(), authored), state)
}

pub fn shared_tree_history_starts_empty_test() -> Nil {
  let state = history.new(local_session())
  history.pending(state) |> expect.to_equal([])
  history.inspect(state)
  |> expect.to_equal(history.HistoryView(
    history.HistorySnapshot(
      history.InitialBase,
      [],
      [],
      0,
      -9_007_199_254_740_991,
    ),
    [],
    0,
  ))
}

pub fn shared_tree_history_ack_does_not_apply_twice_test() -> Nil {
  let #(commit, initial_forest) = real_commit()
  let assert Ok(local) =
    history.append_local(history.new(local_session()), commit)
  let assert Some(delta) = local.delta
  let assert Ok(optimistic_forest) = forest.apply_delta(initial_forest, delta)
  history.pending(local.history) |> expect.to_equal([commit])

  let assert Ok(#(ack, Nil)) =
    history.receive(
      local.history,
      commit,
      types.SequencePoint(1, 0),
      0,
      0,
      Nil,
      no_mint,
    )
  history.pending(ack.history) |> expect.to_equal([])
  ack.delta |> expect.to_equal(None)
  forest.export_data(optimistic_forest)
  |> expect.to_equal(forest.export_data(optimistic_forest))
}

pub fn shared_tree_history_local_contract_refusals_test() -> Nil {
  let first = empty_commit(revision_a(), local_session())
  let second = empty_commit(revision_b(), local_session())
  let peer = empty_commit(revision_b(), peer_session())
  let state = history.new(local_session())
  history.append_local(state, peer) |> expect.to_be_error
  let assert Ok(first_update) = history.append_local(state, first)
  history.append_local(first_update.history, first) |> expect.to_be_error
  let assert Ok(second_update) =
    history.append_local(first_update.history, second)
  let assert Error(InvalidHistory(_)) =
    history.receive(
      second_update.history,
      second,
      types.SequencePoint(1, 0),
      0,
      0,
      Nil,
      no_mint,
    )
  history.pending(second_update.history)
  |> expect.to_equal([first, second])
  let assert Error(InvalidHistory(_)) =
    history.receive(
      second_update.history,
      first,
      types.SequencePoint(1, -1),
      0,
      0,
      Nil,
      no_mint,
    )
  let assert Error(InvalidHistory(_)) =
    history.receive(
      second_update.history,
      first,
      types.SequencePoint(9_007_199_254_740_991 + 1, 0),
      0,
      0,
      Nil,
      no_mint,
    )
  Nil
}

pub fn shared_tree_history_retained_duplicate_does_not_ack_next_test() -> Nil {
  let first = empty_commit(revision_a(), local_session())
  let second = empty_commit(revision_b(), local_session())
  let assert Ok(first_update) =
    history.append_local(history.new(local_session()), first)
  let assert Ok(#(acked, Nil)) =
    history.receive(
      first_update.history,
      first,
      types.SequencePoint(1, 0),
      0,
      0,
      Nil,
      no_mint,
    )
  let assert Ok(second_update) = history.append_local(acked.history, second)
  let assert Ok(#(duplicate, Nil)) =
    history.receive(
      second_update.history,
      first,
      types.SequencePoint(2, 0),
      1,
      0,
      Nil,
      no_mint,
    )
  history.pending(duplicate.history) |> expect.to_equal([second])
  duplicate.delta |> expect.to_equal(None)
}
