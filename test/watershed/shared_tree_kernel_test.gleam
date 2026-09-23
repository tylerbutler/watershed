import gleam/list
import gleam/option.{None, Some}
import gleam/string
import startest/expect
import watershed/fluid_ids
import watershed/tree/change
import watershed/tree/forest
import watershed/tree/history
import watershed/tree/schema
import watershed/tree/types.{
  type TreeError, AtomId, ClearField, InvalidEdit, NumberValue, ObjectValue,
  SetField, StringValue,
}
import watershed/tree_kernel

const tree_schema = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.number\":{\"kind\":{\"leaf\":0}},\"Point\":{\"kind\":{\"object\":{\"x\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.number\"]}}}},\"Root\":{\"kind\":{\"object\":{\"point\":{\"kind\":\"Value\",\"types\":[\"Point\"]}}}}},\"root\":{\"kind\":\"Value\",\"types\":[\"Root\"]}}"

const optional_schema = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.number\":{\"kind\":{\"leaf\":0}},\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}},\"Point\":{\"kind\":{\"object\":{\"x\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.number\"]}}}},\"Root\":{\"kind\":{\"object\":{\"point\":{\"kind\":\"Value\",\"types\":[\"Point\"]},\"note\":{\"kind\":\"Optional\",\"types\":[\"com.fluidframework.leaf.string\"]}}}}},\"root\":{\"kind\":\"Value\",\"types\":[\"Root\"]}}"

fn session() -> fluid_ids.SessionId {
  let assert Ok(id) =
    fluid_ids.session_id("00000000-0000-4000-8000-000000000001")
  id
}

fn view_id() -> fluid_ids.StableId {
  let assert Ok(id) =
    fluid_ids.stable_id("00000000-0000-4000-8000-000000000002")
  id
}

fn revision() -> fluid_ids.StableId {
  let assert Ok(id) =
    fluid_ids.stable_id("00000000-0000-4000-8000-000000000003")
  id
}

fn other_session() -> fluid_ids.SessionId {
  let assert Ok(id) =
    fluid_ids.session_id("00000000-0000-4000-8000-000000000004")
  id
}

fn other_revision() -> fluid_ids.StableId {
  let assert Ok(id) =
    fluid_ids.stable_id("00000000-0000-4000-8000-000000000005")
  id
}

fn root() -> types.TreeValue {
  ObjectValue("Root", [
    #("point", ObjectValue("Point", [#("x", NumberValue(1.0))])),
  ])
}

fn initial_state() -> tree_kernel.TreeState {
  initial_state_for(session())
}

fn initial_state_for(local: fluid_ids.SessionId) -> tree_kernel.TreeState {
  let assert Ok(stored) = schema.stored_from_string(tree_schema)
  let assert Ok(view) = schema.view_from_string(tree_schema)
  let initial = history.inspect(history.new(local)).sequenced
  let assert Ok(snapshot) =
    tree_kernel.snapshot_from_parts(
      view_id(),
      stored,
      forest.ForestData(Some(root()), [], 0),
      initial,
    )
  let assert Ok(state) = tree_kernel.restore(snapshot, view_id(), local, view)
  state
}

fn no_mint(
  _state: Nil,
) -> Result(#(fluid_ids.StableId, change.IdentityOrder, Nil), TreeError) {
  Error(types.InvalidHistory("unexpected rollback allocation"))
}

type Allocation {
  Allocation(
    revisions: List(fluid_ids.StableId),
    order: change.IdentityOrder,
    consumed: Int,
  )
}

fn mint(
  allocation: Allocation,
) -> Result(#(fluid_ids.StableId, change.IdentityOrder, Allocation), TreeError) {
  case allocation.revisions {
    [] -> Error(types.InvalidHistory("rollback allocation is exhausted"))
    [revision, ..rest] ->
      Ok(#(
        revision,
        allocation.order,
        Allocation(rest, allocation.order, allocation.consumed + 1),
      ))
  }
}

pub fn shared_tree_kernel_restores_checked_snapshot_test() {
  let assert Ok(stored) = schema.stored_from_string(tree_schema)
  let assert Ok(view) = schema.view_from_string(tree_schema)
  let initial = history.inspect(history.new(session())).sequenced
  let assert Ok(snapshot) =
    tree_kernel.snapshot_from_parts(
      view_id(),
      stored,
      forest.ForestData(Some(root()), [], 0),
      initial,
    )
  let assert Ok(state) =
    tree_kernel.restore(snapshot, view_id(), session(), view)
  tree_kernel.read(state, ["point", "x"])
  |> expect.to_equal(Ok(Some(NumberValue(1.0))))
  tree_kernel.snapshot(state) |> expect.to_equal(Ok(snapshot))
}

pub fn shared_tree_kernel_rejects_incompatible_view_test() {
  let assert Ok(stored) = schema.stored_from_string(tree_schema)
  let assert Ok(view) =
    schema.view_from_string(string.replace(
      tree_schema,
      "\"Value\"",
      "\"Optional\"",
    ))
  let initial = history.inspect(history.new(session())).sequenced
  let assert Ok(snapshot) =
    tree_kernel.snapshot_from_parts(
      view_id(),
      stored,
      forest.ForestData(Some(root()), [], 0),
      initial,
    )
  tree_kernel.restore(snapshot, view_id(), session(), view)
  |> expect.to_be_error
  Nil
}

pub fn shared_tree_kernel_rejects_corrupt_forest_test() {
  let assert Ok(stored) = schema.stored_from_string(tree_schema)
  let initial = history.inspect(history.new(session())).sequenced
  tree_kernel.snapshot_from_parts(
    view_id(),
    stored,
    forest.ForestData(None, [], 0),
    initial,
  )
  |> expect.to_be_error
  Nil
}

pub fn shared_tree_kernel_edits_locally_without_snapshotting_pending_test() {
  let state = initial_state()
  let assert Ok(before) = tree_kernel.snapshot(state)
  let assert Ok(order) = change.identity_order([#(revision(), -1)])
  let assert Ok(#(edited, commit, events)) =
    tree_kernel.apply_local(
      state,
      revision(),
      order,
      SetField(["point", "x"], NumberValue(7.0)),
    )
  commit.revision |> expect.to_equal(revision())
  events |> expect.to_equal([tree_kernel.TreeChanged(True)])
  tree_kernel.read(edited, ["point", "x"])
  |> expect.to_equal(Ok(Some(NumberValue(7.0))))
  let assert Ok(visible_data) = tree_kernel.visible_data(edited)
  visible_data.root |> expect.to_not_equal(Some(root()))
  list.length(visible_data.detached) |> expect.to_equal(1)
  tree_kernel.history_view(edited).pending
  |> expect.to_equal([commit])
  tree_kernel.snapshot(edited) |> expect.to_equal(Ok(before))
  let assert Ok(#(acked, events, Nil)) =
    tree_kernel.receive(
      edited,
      commit,
      types.SequencePoint(1, 0),
      0,
      0,
      Nil,
      no_mint,
    )
  events |> expect.to_equal([])
  let assert Ok(after) = tree_kernel.snapshot(acked)
  after |> expect.to_not_equal(before)
  let #(_, sequenced_data, sequenced_history) =
    tree_kernel.snapshot_parts(after)
  sequenced_data.root
  |> expect.to_equal(
    Some(
      ObjectValue("Root", [
        #("point", ObjectValue("Point", [#("x", NumberValue(7.0))])),
      ]),
    ),
  )
  list.length(sequenced_history.trunk) |> expect.to_equal(1)
  let assert Ok(view) = schema.view_from_string(tree_schema)
  let assert Ok(reloaded) =
    tree_kernel.restore(after, view_id(), session(), view)
  tree_kernel.read(reloaded, ["point", "x"])
  |> expect.to_equal(Ok(Some(NumberValue(7.0))))
}

pub fn shared_tree_kernel_rejects_invalid_edit_before_allocation_test() {
  let state = initial_state()
  let assert Ok(before) = tree_kernel.snapshot(state)
  let assert Error(InvalidEdit(_, _)) =
    tree_kernel.validate_edit(state, ClearField(["point", "x"]))
  tree_kernel.validate_edit(
    state,
    SetField(["point", "x"], StringValue("wrong type")),
  )
  |> expect.to_be_error
  let assert Ok(order) = change.identity_order([#(revision(), -1)])
  tree_kernel.apply_local(state, revision(), order, ClearField(["point", "x"]))
  |> expect.to_be_error
  tree_kernel.snapshot(state) |> expect.to_equal(Ok(before))
  tree_kernel.read(state, ["point", "x"])
  |> expect.to_equal(Ok(Some(NumberValue(1.0))))
}

pub fn shared_tree_kernel_suppresses_same_value_event_test() {
  let state = initial_state()
  let assert Ok(order) = change.identity_order([#(revision(), -1)])
  let assert Ok(#(edited, _, events)) =
    tree_kernel.apply_local(
      state,
      revision(),
      order,
      SetField(["point", "x"], NumberValue(1.0)),
    )
  events |> expect.to_equal([])
  tree_kernel.read(edited, ["point", "x"])
  |> expect.to_equal(Ok(Some(NumberValue(1.0))))
}

pub fn shared_tree_kernel_receive_remote_and_duplicate_test() {
  let sender = initial_state_for(other_session())
  let receiver = initial_state()
  let assert Ok(order) = change.identity_order([#(other_revision(), -1)])
  let assert Ok(#(_, commit, _)) =
    tree_kernel.apply_local(
      sender,
      other_revision(),
      order,
      SetField(["point", "x"], NumberValue(9.0)),
    )
  let assert Ok(#(updated, events, Nil)) =
    tree_kernel.receive(
      receiver,
      commit,
      types.SequencePoint(1, 0),
      0,
      0,
      Nil,
      no_mint,
    )
  events |> expect.to_equal([tree_kernel.TreeChanged(False)])
  tree_kernel.read(updated, ["point", "x"])
  |> expect.to_equal(Ok(Some(NumberValue(9.0))))
  let assert Ok(#(replayed, events, Nil)) =
    tree_kernel.receive(
      updated,
      commit,
      types.SequencePoint(1, 0),
      0,
      0,
      Nil,
      no_mint,
    )
  events |> expect.to_equal([])
  tree_kernel.snapshot(replayed)
  |> expect.to_equal(tree_kernel.snapshot(updated))
}

pub fn shared_tree_kernel_rebases_pending_and_snapshots_trunk_test() {
  let local = initial_state()
  let peer = initial_state_for(other_session())
  let assert Ok(rollback) =
    fluid_ids.stable_id("00000000-0000-4000-8000-000000000006")
  let assert Ok(authored_order) =
    change.identity_order([
      #(revision(), -2),
      #(other_revision(), -1),
    ])
  let assert Ok(rollback_order) =
    change.identity_order([
      #(revision(), -2),
      #(other_revision(), -1),
      #(rollback, 0),
    ])
  let assert Ok(#(local, _, _)) =
    tree_kernel.apply_local(
      local,
      revision(),
      authored_order,
      SetField(["point", "x"], NumberValue(7.0)),
    )
  let assert Ok(#(_, remote, _)) =
    tree_kernel.apply_local(
      peer,
      other_revision(),
      authored_order,
      SetField(["point", "x"], NumberValue(8.0)),
    )
  let assert Ok(#(received, _, allocation)) =
    tree_kernel.receive(
      local,
      remote,
      types.SequencePoint(1, 0),
      0,
      0,
      Allocation([rollback], rollback_order, 0),
      mint,
    )
  allocation.consumed |> expect.to_equal(1)
  let assert Ok(snapshot) = tree_kernel.snapshot(received)
  let assert Ok(view) = schema.view_from_string(tree_schema)
  let assert Ok(reloaded) =
    tree_kernel.restore(snapshot, view_id(), other_session(), view)
  tree_kernel.read(reloaded, ["point", "x"])
  |> expect.to_equal(Ok(Some(NumberValue(8.0))))
}

pub fn shared_tree_kernel_rebinds_authored_orders_before_remote_delivery_test() {
  let local = initial_state()
  let peer = initial_state_for(other_session())
  let assert Ok(rollback) =
    fluid_ids.stable_id("00000000-0000-4000-8000-000000000006")
  let assert Ok(local_order) = change.identity_order([#(revision(), -1)])
  let assert Ok(peer_order) = change.identity_order([#(other_revision(), -1)])
  let assert Ok(delivery_order) =
    change.identity_order([
      #(revision(), 513),
      #(other_revision(), 1),
      #(rollback, 1025),
    ])
  let assert Ok(#(local, _, _)) =
    tree_kernel.apply_local(
      local,
      revision(),
      local_order,
      SetField(["point", "x"], NumberValue(7.0)),
    )
  let assert Ok(#(_, remote, _)) =
    tree_kernel.apply_local(
      peer,
      other_revision(),
      peer_order,
      SetField(["point", "x"], NumberValue(8.0)),
    )
  let assert Ok(before) = tree_kernel.snapshot(local)
  tree_kernel.receive_ordered(
    local,
    remote,
    peer_order,
    types.SequencePoint(1, 0),
    0,
    0,
    Nil,
    no_mint,
  )
  |> expect.to_be_error
  tree_kernel.snapshot(local) |> expect.to_equal(Ok(before))
  let #(received, _, _) = case
    tree_kernel.receive_ordered(
      local,
      remote,
      delivery_order,
      types.SequencePoint(1, 0),
      0,
      0,
      Allocation([rollback], delivery_order, 0),
      mint,
    )
  {
    Ok(value) -> value
    Error(error) -> panic as string.inspect(error)
  }
  tree_kernel.read(received, ["point", "x"])
  |> expect.to_equal(Ok(Some(NumberValue(7.0))))
  tree_kernel.history_view(received).pending
  |> list.length
  |> expect.to_equal(1)
  list.any(tree_kernel.identity_revisions(received), fn(id) { id == rollback })
  |> expect.to_equal(False)
}

pub fn shared_tree_kernel_rebinding_drops_unused_identity_keys_test() {
  let assert Ok(order) =
    change.identity_order([#(revision(), 1), #(other_revision(), 513)])
  let assert Ok(bound) =
    change.rebind_identity_order(change.empty(), order, [revision()])
  change.identity_revisions(bound) |> expect.to_equal([revision()])
}

pub fn shared_tree_kernel_rebinding_trims_obsolete_history_keys_test() {
  let assert Ok(third) =
    fluid_ids.stable_id("00000000-0000-4000-8000-000000000006")
  let revisions = [revision(), other_revision(), third]
  let assert Ok(order) =
    change.identity_order([
      #(revision(), 1),
      #(other_revision(), 513),
      #(third, 1025),
    ])
  let _ =
    list.fold(revisions, #(history.new(session()), 0), fn(state, revision) {
      let sequence = state.1 + 1
      let commit = history.Commit(revision, session(), change.empty())
      let assert Ok(appended) = history.append_local(state.0, commit)
      let assert Ok(bound) =
        history.rebind_identity_order(appended.history, order)
      let assert Ok(#(update, Nil)) =
        history.receive(
          bound,
          commit,
          types.SequencePoint(sequence, 0),
          sequence - 1,
          sequence,
          Nil,
          no_mint,
        )
      history.identity_revisions(update.history) |> expect.to_equal([])
      #(update.history, sequence)
    })
  Nil
}

pub fn shared_tree_kernel_failed_receive_preserves_both_views_test() {
  let state = initial_state()
  let peer = initial_state_for(other_session())
  let assert Ok(order) = change.identity_order([#(other_revision(), -1)])
  let assert Ok(#(_, commit, _)) =
    tree_kernel.apply_local(
      peer,
      other_revision(),
      order,
      SetField(["point", "x"], NumberValue(9.0)),
    )
  let assert Ok(before) = tree_kernel.snapshot(state)
  tree_kernel.receive(
    state,
    commit,
    types.SequencePoint(1, 0),
    2,
    0,
    Nil,
    no_mint,
  )
  |> expect.to_be_error
  tree_kernel.snapshot(state) |> expect.to_equal(Ok(before))
  tree_kernel.read(state, ["point", "x"])
  |> expect.to_equal(Ok(Some(NumberValue(1.0))))
}

pub fn shared_tree_kernel_optional_set_clear_preserves_absence_test() {
  let assert Ok(stored) = schema.stored_from_string(optional_schema)
  let assert Ok(view) = schema.view_from_string(optional_schema)
  let initial = history.inspect(history.new(session())).sequenced
  let assert Ok(snapshot) =
    tree_kernel.snapshot_from_parts(
      view_id(),
      stored,
      forest.ForestData(Some(root()), [], 0),
      initial,
    )
  let assert Ok(state) =
    tree_kernel.restore(snapshot, view_id(), session(), view)
  tree_kernel.read(state, ["note"]) |> expect.to_equal(Ok(None))
  let assert Ok(order) =
    change.identity_order([
      #(revision(), -2),
      #(other_revision(), -1),
    ])
  let assert Ok(#(set, _, _)) =
    tree_kernel.apply_local(
      state,
      revision(),
      order,
      SetField(["note"], StringValue("present")),
    )
  tree_kernel.read(set, ["note"])
  |> expect.to_equal(Ok(Some(StringValue("present"))))
  let assert Ok(#(cleared, _, _)) =
    tree_kernel.apply_local(set, other_revision(), order, ClearField(["note"]))
  tree_kernel.read(cleared, ["note"]) |> expect.to_equal(Ok(None))
}

pub fn shared_tree_kernel_local_ids_continue_after_ack_test() {
  let assert Ok(stored) = schema.stored_from_string(optional_schema)
  let assert Ok(view) = schema.view_from_string(optional_schema)
  let initial = history.inspect(history.new(session())).sequenced
  let assert Ok(snapshot) =
    tree_kernel.snapshot_from_parts(
      view_id(),
      stored,
      forest.ForestData(Some(root()), [], 0),
      initial,
    )
  let assert Ok(state) =
    tree_kernel.restore(snapshot, view_id(), session(), view)
  let assert Ok(order) =
    change.identity_order([#(revision(), -2), #(other_revision(), -1)])
  let assert Ok(#(set, commit, _)) =
    tree_kernel.apply_local(
      state,
      revision(),
      order,
      SetField(["note"], StringValue("present")),
    )
  let assert Ok(#(acked, _, Nil)) =
    tree_kernel.receive(
      set,
      commit,
      types.SequencePoint(1, 0),
      0,
      0,
      Nil,
      no_mint,
    )
  let assert Ok(#(cleared, _, _)) =
    tree_kernel.apply_local(
      acked,
      other_revision(),
      order,
      ClearField(["note"]),
    )
  let assert Ok(data) = tree_kernel.visible_data(cleared)
  let assert [detached] = data.detached
  detached.id |> expect.to_equal(AtomId(Some(other_revision()), 3))
}
