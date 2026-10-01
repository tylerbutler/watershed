import gleam/json

import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import startest/expect
import watershed/fluid_ids
import watershed/json_ot.{type JsonValue, VArray, VObject, VString}
import watershed/tree/array_fixture
import watershed/tree/change
import watershed/tree/codec
import watershed/tree/fixtures
import watershed/tree/forest
import watershed/tree/history
import watershed/tree/identifier_fixture
import watershed/tree/runtime as tree_runtime
import watershed/tree/schema
import watershed/tree/sequence_field/moves
import watershed/tree/shared_change
import watershed/tree/transaction
import watershed/tree/transaction_fixture
import watershed/tree/types
import watershed/tree_kernel

const items_type = "org.watershed.shared-tree.m3.Items"

const point_type = "org.watershed.shared-tree.m3.Point"

pub fn identifier_transaction_abort_preserves_local_advancement_test() {
  let stored = identifier_fixture.stored()
  let base =
    identifier_fixture.state(
      stored,
      identifier_fixture.view("Identifier"),
      identifier_fixture.point("before", "before"),
    )
  let compressor = fluid_ids.new(identifier_fixture.session())
  let assert Ok(open) = transaction.begin(base, compressor, [])
  let assert Ok(open) =
    transaction.apply_edit(
      open,
      types.SetField(
        [],
        types.ObjectValue(identifier_fixture.point_type, [
          #("label", types.StringValue("generated")),
        ]),
      ),
    )
  let advanced = transaction.compressor(open)
  advanced |> expect.to_not_equal(compressor)
  let assert Ok(#(restored, aborted_compressor)) = transaction.abort(open)
  tree_kernel.visible_data(restored)
  |> expect.to_equal(tree_kernel.visible_data(base))
  aborted_compressor |> expect.to_equal(advanced)
}

pub fn identifier_nested_abort_does_not_reuse_reference_test() {
  let stored = identifier_fixture.stored()
  let base =
    identifier_fixture.state(
      stored,
      identifier_fixture.view("Identifier"),
      identifier_fixture.point("before", "before"),
    )
  let compressor = fluid_ids.new(identifier_fixture.session())
  let assert Ok(open) = transaction.begin(base, compressor, [])
  let nested = transaction.begin_nested(open)
  let assert Ok(nested) =
    transaction.apply_edit(
      nested,
      types.SetField(
        [],
        types.ObjectValue(identifier_fixture.point_type, [
          #("label", types.StringValue("first")),
        ]),
      ),
    )
  let assert Ok(first_reference) =
    tree_kernel.reference_at(transaction.state(nested), [])
  let assert Ok(open) = transaction.abort_nested(nested)
  let assert Ok(open) =
    transaction.apply_edit(
      open,
      types.SetField(
        [],
        types.ObjectValue(identifier_fixture.point_type, [
          #("label", types.StringValue("second")),
        ]),
      ),
    )
  let assert Ok(second_reference) =
    tree_kernel.reference_at(transaction.state(open), [])
  second_reference |> expect.to_not_equal(first_reference)
}

pub fn identifier_noop_finish_restores_base_compressor_test() {
  let stored = identifier_fixture.full_stored()
  let base =
    identifier_fixture.state(
      stored,
      identifier_fixture.full_view(),
      identifier_fixture.full_root(
        identifier_fixture.point("child", "child"),
        [],
        [],
        [],
      ),
    )
  let compressor = fluid_ids.new(identifier_fixture.session())
  let assert Ok(open) = transaction.begin(base, compressor, [])
  let open = transaction.begin_nested(open)
  let assert Ok(open) =
    transaction.apply_edit(
      open,
      types.ArrayInsert(["left"], 0, [
        types.ObjectValue(identifier_fixture.point_type, [
          #("label", types.StringValue("temporary")),
        ]),
      ]),
    )
  let assert Ok(open) = transaction.abort_nested(open)
  let assert Ok(#(transaction.NoCommit(restored, finished), _)) =
    transaction.finish(open)
  tree_kernel.visible_data(restored)
  |> expect.to_equal(tree_kernel.visible_data(base))
  finished |> expect.to_equal(compressor)
}

fn transaction_revision() -> fluid_ids.StableId {
  let assert Ok(revision) =
    fluid_ids.stable_id("30000000-0000-4000-8000-000000000001")
  revision
}

fn constraint_forest(view: fluid_ids.StableId) -> forest.Forest {
  let root =
    types.ObjectValue("org.watershed.shared-tree.m3.Root", [
      #(
        "left",
        types.ArrayValue(items_type, [
          types.ObjectValue(point_type, [
            #("label", types.StringValue("point")),
            #("x", types.NumberValue(1.0)),
          ]),
        ]),
      ),
      #("right", types.ArrayValue(items_type, [])),
      #(
        "byKey",
        types.MapValue("org.watershed.shared-tree.m3.ArrayMap", [
          #("item", types.StringValue("value")),
        ]),
      ),
      #("narrow", types.ArrayValue("org.watershed.shared-tree.m3.Points", [])),
    ])
  let assert Ok(state) =
    forest.new(view, array_fixture.stored("objectArrays"), Some(root))
  state
}

fn apply_constraint_edit(
  state: forest.Forest,
  operation: types.Edit,
) -> Result(forest.Forest, types.TreeError) {
  let revision = transaction_revision()
  use order <- result.try(change.identity_order([#(revision, 0)]))
  use authored <- result.try(change.edit(
    array_fixture.stored("objectArrays"),
    state,
    revision,
    operation,
    order,
  ))
  use delta <- result.try(
    change.into_delta(change.TaggedChange(Some(revision), None, authored)),
  )
  forest.apply_delta(state, delta)
}

pub fn shared_tree_constraint_resolves_attached_node_kinds_test() -> Nil {
  let state = constraint_forest(array_fixture.view_id())
  [
    [],
    ["byKey"],
    ["left", "0"],
  ]
  |> list.each(fn(path) {
    let assert Ok(reference) = forest.locate(state, path)
    let assert Ok(change.ConstraintTarget(resolved, resolved_path)) =
      change.resolve_constraint(state, path)
    resolved |> expect.to_equal(reference)
    resolved_path |> expect.to_equal(path)
  })
}

pub fn shared_tree_constraint_resolution_preserves_moved_identity_test() -> Nil {
  let initial = constraint_forest(array_fixture.view_id())
  let assert Ok(reference) = forest.locate(initial, ["left", "0"])
  let assert Ok(moved) =
    apply_constraint_edit(
      initial,
      types.ArrayMove(["left"], 0, 1, ["right"], 0),
    )
  let assert Ok(change.ConstraintTarget(resolved, path)) =
    change.resolve_constraint(moved, ["right", "0"])
  resolved |> expect.to_equal(reference)
  path |> expect.to_equal(["right", "0"])
}

pub fn shared_tree_constraint_rejects_invalid_targets_test() -> Nil {
  let initial = constraint_forest(array_fixture.view_id())
  let assert Error(types.InvalidEdit(_, _)) =
    change.resolve_constraint(initial, ["missing"])
  let assert Ok(target) = change.resolve_constraint(initial, ["left", "0"])
  let assert Ok(removed) =
    apply_constraint_edit(initial, types.ArrayRemove(["left"], 0, 1))
  let assert Error(types.InvalidEdit(_, _)) =
    change.add_node_exists_constraints(change.empty(), removed, [target])

  let other_view =
    fluid_ids.stable_id("30000000-0000-4000-8000-000000000002")
    |> result.unwrap(transaction_revision())
  let other = constraint_forest(other_view)
  let assert Error(types.InvalidEdit(_, _)) =
    change.add_node_exists_constraints(change.empty(), other, [target])
  Nil
}

pub fn shared_tree_constraint_duplicate_targets_collapse_test() -> Nil {
  let state = constraint_forest(array_fixture.view_id())
  let assert Ok(target) = change.resolve_constraint(state, ["left", "0"])
  let assert Ok(constrained) =
    change.add_node_exists_constraints(change.empty(), state, [target, target])
  let data = change.to_data(constrained)
  data.constraint_violation_count |> expect.to_equal(0)
  data.nodes
  |> list.filter(fn(entry) {
    entry.1.node_exists_constraint == Some(change.NodeExistsConstraint(False))
  })
  |> list.length
  |> expect.to_equal(1)
}

const tree_schema = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.number\":{\"kind\":{\"leaf\":0}},\"Point\":{\"kind\":{\"object\":{\"x\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.number\"]}}}},\"Root\":{\"kind\":{\"object\":{\"point\":{\"kind\":\"Value\",\"types\":[\"Point\"]},\"note\":{\"kind\":\"Optional\",\"types\":[\"Point\"]}}}}},\"root\":{\"kind\":\"Value\",\"types\":[\"Root\"]}}"

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

fn other_session() -> fluid_ids.SessionId {
  let assert Ok(id) =
    fluid_ids.session_id("00000000-0000-4000-8000-000000000005")
  id
}

fn remote_revision() -> fluid_ids.StableId {
  let assert Ok(id) =
    fluid_ids.stable_id("00000000-0000-4000-8000-000000000006")
  id
}

fn rollback_revision_one() -> fluid_ids.StableId {
  let assert Ok(id) =
    fluid_ids.stable_id("00000000-0000-4000-8000-000000000007")
  id
}

fn rollback_revision_two() -> fluid_ids.StableId {
  let assert Ok(id) =
    fluid_ids.stable_id("00000000-0000-4000-8000-000000000008")
  id
}

fn rollback_revision_three() -> fluid_ids.StableId {
  let assert Ok(id) =
    fluid_ids.stable_id("00000000-0000-4000-8000-000000000009")
  id
}

fn root() -> types.TreeValue {
  types.ObjectValue("Root", [
    #(
      "point",
      types.ObjectValue("Point", [
        #("x", types.NumberValue(1.0)),
      ]),
    ),
    #(
      "note",
      types.ObjectValue("Point", [
        #("x", types.NumberValue(2.0)),
      ]),
    ),
  ])
}

fn initial_state() -> tree_kernel.TreeState {
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
  state
}

fn array_state(
  local_session: fluid_ids.SessionId,
  values: List(types.TreeValue),
) -> tree_kernel.TreeState {
  let initial = history.inspect(history.new(local_session)).sequenced
  let assert Ok(snapshot) =
    tree_kernel.snapshot_from_parts(
      array_fixture.view_id(),
      array_fixture.stored("rootArray"),
      forest.ForestData(
        Some(types.ArrayValue("org.watershed.shared-tree.m3.Items", values)),
        [],
        0,
      ),
      initial,
    )
  let assert Ok(state) =
    tree_kernel.restore(
      snapshot,
      array_fixture.view_id(),
      local_session,
      array_fixture.view("rootArray"),
    )
  state
}

fn identifier_array_state(
  local_session: fluid_ids.SessionId,
  values: List(types.TreeValue),
) -> tree_kernel.TreeState {
  let root =
    identifier_fixture.full_root(
      identifier_fixture.point("child", "child"),
      values,
      [],
      [],
    )
  let initial = history.inspect(history.new(local_session)).sequenced
  let assert Ok(snapshot) =
    tree_kernel.snapshot_from_parts(
      view_id(),
      identifier_fixture.full_stored(),
      forest.ForestData(Some(root), [], 0),
      initial,
    )
  let assert Ok(state) =
    tree_kernel.restore(
      snapshot,
      view_id(),
      local_session,
      identifier_fixture.full_view(),
    )
  state
}

type Allocation {
  Allocation(revisions: List(fluid_ids.StableId), order: change.IdentityOrder)
}

fn mint(
  allocation: Allocation,
) -> Result(
  #(fluid_ids.StableId, change.IdentityOrder, Allocation),
  types.TreeError,
) {
  case allocation.revisions {
    [] -> Error(types.InvalidHistory("rollback allocation is exhausted"))
    [revision, ..rest] ->
      Ok(#(revision, allocation.order, Allocation(rest, allocation.order)))
  }
}

pub fn shared_tree_transaction_commits_one_outer_change_test() -> Nil {
  let base = initial_state()
  let compressor = fluid_ids.new(session())
  let assert Ok(value) = transaction.begin(base, compressor, [])
  let assert Ok(value) =
    transaction.apply_edit(
      value,
      types.SetField(["point", "x"], types.NumberValue(2.0)),
    )
  tree_kernel.read(transaction.state(value), ["point", "x"])
  |> expect.to_equal(Ok(Some(types.NumberValue(2.0))))
  tree_kernel.history_view(transaction.state(value)).pending
  |> expect.to_equal([])
  let assert Ok(value) =
    transaction.apply_edit(
      value,
      types.SetField(["point", "x"], types.NumberValue(3.0)),
    )
  tree_kernel.read(transaction.state(value), ["point", "x"])
  |> expect.to_equal(Ok(Some(types.NumberValue(3.0))))
  tree_kernel.history_view(transaction.state(value)).pending
  |> expect.to_equal([])

  let assert Ok(#(transaction.Commit(state, _, commit), events)) =
    transaction.finish(value)
  tree_kernel.read(state, ["point", "x"])
  |> expect.to_equal(Ok(Some(types.NumberValue(3.0))))
  tree_kernel.history_view(state).pending |> expect.to_equal([commit])
  shared_change.revision_infos(shared_change.TaggedChange(
    None,
    None,
    commit.change,
  ))
  |> expect.to_equal([change.RevisionInfo(commit.revision, None)])
  events.events |> expect.to_equal([tree_kernel.TreeChanged(True)])
}

pub fn shared_tree_transaction_finish_preserves_preview_node_references_test() -> Nil {
  let base = array_state(session(), [types.StringValue("A")])
  let assert Ok(value) = transaction.begin(base, fluid_ids.new(session()), [])
  let assert Ok(value) =
    transaction.apply_edit(
      value,
      types.ArrayInsert([], 1, [types.StringValue("B")]),
    )
  let assert Ok(b_reference) =
    tree_kernel.reference_at(transaction.state(value), ["1"])
  let assert Ok(value) =
    transaction.apply_edit(
      value,
      types.ArrayInsert([], 2, [types.StringValue("C")]),
    )
  let assert Ok(c_reference) =
    tree_kernel.reference_at(transaction.state(value), ["2"])

  let assert Ok(#(transaction.Commit(state, _, commit), _)) =
    transaction.finish(value)
  tree_kernel.reference_at(state, ["1"])
  |> expect.to_equal(Ok(b_reference))
  tree_kernel.reference_at(state, ["2"])
  |> expect.to_equal(Ok(c_reference))
  tree_kernel.read_reference(state, b_reference)
  |> expect.to_equal(Ok(types.StringValue("B")))
  tree_kernel.read_reference(state, c_reference)
  |> expect.to_equal(Ok(types.StringValue("C")))

  let remote_base = array_state(other_session(), [types.StringValue("A")])
  let assert Ok(remote_order) = change.identity_order([#(remote_revision(), 0)])
  let assert Ok(#(_, remote_commit, _)) =
    tree_kernel.apply_local(
      remote_base,
      remote_revision(),
      remote_order,
      types.ArrayInsert([], 0, [types.StringValue("remote")]),
    )
  let rollback_revisions = [
    rollback_revision_one(),
    rollback_revision_two(),
    rollback_revision_three(),
  ]
  let revisions =
    [
      remote_revision(),
      ..list.append(rollback_revisions, [
        commit.revision,
        ..shared_change.identity_revisions(commit.change)
      ])
    ]
    |> list.unique
  let assert Ok(order) =
    revisions
    |> list.index_map(fn(revision, index) { #(revision, index) })
    |> change.identity_order
  let allocation = Allocation(rollback_revisions, order)
  let assert Ok(#(reconciled, _, allocation)) =
    tree_kernel.receive_ordered(
      state,
      remote_commit,
      order,
      types.SequencePoint(1, 0),
      0,
      0,
      allocation,
      mint,
    )
  tree_kernel.reference_at(reconciled, ["2"])
  |> expect.to_equal(Ok(b_reference))
  tree_kernel.reference_at(reconciled, ["3"])
  |> expect.to_equal(Ok(c_reference))
  tree_kernel.read_reference(reconciled, b_reference)
  |> expect.to_equal(Ok(types.StringValue("B")))
  tree_kernel.read_reference(reconciled, c_reference)
  |> expect.to_equal(Ok(types.StringValue("C")))

  let assert Ok(#(acknowledged, _, _)) =
    tree_kernel.receive_ordered(
      reconciled,
      commit,
      order,
      types.SequencePoint(2, 0),
      0,
      0,
      allocation,
      mint,
    )
  tree_kernel.reference_at(acknowledged, ["2"])
  |> expect.to_equal(Ok(b_reference))
  tree_kernel.reference_at(acknowledged, ["3"])
  |> expect.to_equal(Ok(c_reference))
  tree_kernel.read_reference(acknowledged, b_reference)
  |> expect.to_equal(Ok(types.StringValue("B")))
  tree_kernel.read_reference(acknowledged, c_reference)
  |> expect.to_equal(Ok(types.StringValue("C")))
}

pub fn shared_tree_transaction_insert_move_remove_round_trips_test() -> Nil {
  let values = [
    types.StringValue("A"),
    types.StringValue("B"),
    types.StringValue("C"),
  ]
  let base = array_state(session(), values)
  let compressor = fluid_ids.new(session())
  let assert Ok(a_reference) = tree_kernel.reference_at(base, ["0"])
  let assert Ok(b_reference) = tree_kernel.reference_at(base, ["1"])
  let assert Ok(c_reference) = tree_kernel.reference_at(base, ["2"])
  let assert Ok(value) = transaction.begin(base, compressor, [])
  let assert Ok(value) =
    transaction.apply_edit(
      value,
      types.ArrayInsert([], 1, [types.StringValue("X")]),
    )
  let assert Ok(x_reference) =
    tree_kernel.reference_at(transaction.state(value), ["1"])
  let assert Ok(value) =
    transaction.apply_edit(value, types.ArrayMove([], 1, 2, [], 4))
  let assert Ok(value) =
    transaction.apply_edit(value, types.ArrayRemove([], 1, 2))
  let finished = transaction.finish(value) |> expect.to_be_ok()
  let assert #(transaction.Commit(state, compressor, commit), _) = finished

  tree_kernel.array_values(state, [])
  |> expect.to_equal(
    Ok([
      types.StringValue("A"),
      types.StringValue("C"),
      types.StringValue("X"),
    ]),
  )
  tree_kernel.read_reference(state, a_reference)
  |> expect.to_equal(Ok(types.StringValue("A")))
  tree_kernel.read_reference(state, b_reference)
  |> expect.to_equal(Ok(types.StringValue("B")))
  tree_kernel.read_reference(state, c_reference)
  |> expect.to_equal(Ok(types.StringValue("C")))
  tree_kernel.read_reference(state, x_reference)
  |> expect.to_equal(Ok(types.StringValue("X")))

  let assert [shared_change.DataChange(composed)] =
    shared_change.to_changes(commit.change)
  let data = change.to_data(composed)
  data.cross_field_keys |> expect.to_not_equal([])
  data.cross_field_keys
  |> list.each(fn(entry) {
    let change.CrossFieldKey(key, _, field) = entry
    let moves.Key(_, revision, _) = key
    let moves.FieldId(parent, _) = field
    revision |> expect.to_equal(Some(commit.revision))
    case parent {
      None -> Nil
      Some(parent) -> parent.revision |> expect.to_equal(Some(commit.revision))
    }
  })

  let encoded =
    tree_runtime.encode_commit(commit, state, compressor)
    |> expect.to_be_ok()
  let remote = array_state(other_session(), values)
  let assert Ok(#(decoded, message)) =
    tree_runtime.decode_sequenced_message(
      json.to_string(encoded),
      remote,
      0,
      compressor,
    )
  codec.encode_message(
    message,
    codec.EncodeContext(
      codec.Fluid310,
      compressor,
      Some(tree_kernel.stored_schema(remote)),
    ),
  )
  |> expect.to_equal(Ok(encoded))
  let assert Ok(#(replayed, _, _)) =
    tree_runtime.receive_commit(
      remote,
      decoded,
      types.SequencePoint(1, 0),
      0,
      0,
      compressor,
    )
  tree_kernel.array_values(replayed, [])
  |> expect.to_equal(
    Ok([
      types.StringValue("A"),
      types.StringValue("C"),
      types.StringValue("X"),
    ]),
  )
}

pub fn shared_tree_transaction_finish_preserves_detached_preview_reference_test() -> Nil {
  let base =
    array_state(session(), [
      types.StringValue("A"),
      types.StringValue("B"),
    ])
  let assert Ok(a_reference) = tree_kernel.reference_at(base, ["0"])
  let assert Ok(value) = transaction.begin(base, fluid_ids.new(session()), [])
  let assert Ok(value) =
    transaction.apply_edit(
      value,
      types.ArrayInsert([], 2, [types.StringValue("C")]),
    )
  let assert Ok(value) =
    transaction.apply_edit(value, types.ArrayRemove([], 0, 1))
  tree_kernel.read_reference(transaction.state(value), a_reference)
  |> expect.to_equal(Ok(types.StringValue("A")))

  let assert Ok(#(transaction.Commit(state, _, commit), _)) =
    transaction.finish(value)
  tree_kernel.read_reference(state, a_reference)
  |> expect.to_equal(Ok(types.StringValue("A")))

  let remote_base =
    array_state(other_session(), [
      types.StringValue("A"),
      types.StringValue("B"),
    ])
  let assert Ok(remote_order) = change.identity_order([#(remote_revision(), 0)])
  let assert Ok(#(_, remote_commit, _)) =
    tree_kernel.apply_local(
      remote_base,
      remote_revision(),
      remote_order,
      types.ArrayInsert([], 0, [types.StringValue("remote")]),
    )
  let rollback_revisions = [
    rollback_revision_one(),
    rollback_revision_two(),
    rollback_revision_three(),
  ]
  let revisions =
    [
      remote_revision(),
      ..list.append(rollback_revisions, [
        commit.revision,
        ..shared_change.identity_revisions(commit.change)
      ])
    ]
    |> list.unique
  let assert Ok(order) =
    revisions
    |> list.index_map(fn(revision, index) { #(revision, index) })
    |> change.identity_order
  let allocation = Allocation(rollback_revisions, order)
  let assert Ok(#(reconciled, _, allocation)) =
    tree_kernel.receive_ordered(
      state,
      remote_commit,
      order,
      types.SequencePoint(1, 0),
      0,
      0,
      allocation,
      mint,
    )
  tree_kernel.read_reference(reconciled, a_reference)
  |> expect.to_equal(Ok(types.StringValue("A")))

  let assert Ok(#(acknowledged, _, _)) =
    tree_kernel.receive_ordered(
      reconciled,
      commit,
      order,
      types.SequencePoint(2, 0),
      0,
      0,
      allocation,
      mint,
    )
  tree_kernel.read_reference(acknowledged, a_reference)
  |> expect.to_equal(Ok(types.StringValue("A")))
}

pub fn shared_tree_transaction_abort_restores_document_and_summary_test() -> Nil {
  let base = initial_state()
  let compressor = fluid_ids.new(session())
  let assert Ok(base_snapshot) = tree_kernel.snapshot(base)
  let assert Ok(base_summary) = fluid_ids.serialize(compressor, False)
  let assert Ok(base_ongoing) = fluid_ids.serialize(compressor, True)
  let assert Ok(value) = transaction.begin(base, compressor, [])
  let assert Ok(value) =
    transaction.apply_edit(
      value,
      types.SetField(["point", "x"], types.NumberValue(3.0)),
    )
  let assert Ok(#(state, advanced)) = transaction.abort(value)

  tree_kernel.snapshot(state) |> expect.to_equal(Ok(base_snapshot))
  tree_kernel.visible_data(state)
  |> expect.to_equal(tree_kernel.visible_data(base))
  tree_kernel.history_view(state)
  |> expect.to_equal(tree_kernel.history_view(base))
  fluid_ids.serialize(advanced, False) |> expect.to_equal(Ok(base_summary))
  fluid_ids.serialize(advanced, True)
  |> expect.to_not_equal(Ok(base_ongoing))
}

pub fn shared_tree_transaction_nested_abort_does_not_reuse_node_references_test() -> Nil {
  let base =
    array_state(session(), [
      types.StringValue("A"),
      types.StringValue("B"),
      types.StringValue("C"),
    ])
  let assert Ok(value) = transaction.begin(base, fluid_ids.new(session()), [])
  let value = transaction.begin_nested(value)
  let assert Ok(value) =
    transaction.apply_edit(
      value,
      types.ArrayInsert([], 3, [types.StringValue("discarded")]),
    )
  let assert Ok(discarded_reference) =
    tree_kernel.reference_at(transaction.state(value), ["3"])
  let assert Ok(discarded_target) =
    tree_kernel.resolve_constraint(transaction.state(value), ["3"])
  let assert Ok(value) = transaction.abort_nested(value)
  tree_kernel.read_reference(transaction.state(value), discarded_reference)
  |> expect.to_be_error

  let assert Ok(value) =
    transaction.apply_edit(
      value,
      types.ArrayInsert([], 3, [types.StringValue("replacement")]),
    )
  let assert Ok(replacement_reference) =
    tree_kernel.reference_at(transaction.state(value), ["3"])
  replacement_reference |> expect.to_not_equal(discarded_reference)
  tree_kernel.read_reference(transaction.state(value), discarded_reference)
  |> expect.to_be_error
  tree_kernel.validate_constraints(transaction.state(value), [discarded_target])
  |> expect.to_be_error
  Nil
}

pub fn shared_tree_transaction_outer_abort_does_not_reuse_node_references_test() -> Nil {
  let base =
    array_state(session(), [
      types.StringValue("A"),
      types.StringValue("B"),
      types.StringValue("C"),
    ])
  let compressor = fluid_ids.new(session())
  let assert Ok(value) = transaction.begin(base, compressor, [])
  let assert Ok(value) =
    transaction.apply_edit(
      value,
      types.ArrayInsert([], 3, [types.StringValue("discarded")]),
    )
  let assert Ok(discarded_reference) =
    tree_kernel.reference_at(transaction.state(value), ["3"])
  let assert Ok(discarded_target) =
    tree_kernel.resolve_constraint(transaction.state(value), ["3"])
  let assert Ok(#(aborted, compressor)) = transaction.abort(value)
  tree_kernel.read_reference(aborted, discarded_reference)
  |> expect.to_be_error

  let assert Ok(value) = transaction.begin(aborted, compressor, [])
  let assert Ok(value) =
    transaction.apply_edit(
      value,
      types.ArrayInsert([], 3, [types.StringValue("replacement")]),
    )
  let assert Ok(replacement_reference) =
    tree_kernel.reference_at(transaction.state(value), ["3"])
  replacement_reference |> expect.to_not_equal(discarded_reference)
  tree_kernel.read_reference(transaction.state(value), discarded_reference)
  |> expect.to_be_error
  tree_kernel.validate_constraints(transaction.state(value), [discarded_target])
  |> expect.to_be_error
  Nil
}

pub fn shared_tree_transaction_no_commit_does_not_reuse_nested_node_references_test() -> Nil {
  let base = array_state(session(), [types.StringValue("A")])
  let compressor = fluid_ids.new(session())
  let assert Ok(base_reference) = tree_kernel.reference_at(base, ["0"])
  let assert Ok(base_snapshot) = tree_kernel.snapshot(base)
  let base_history = tree_kernel.history_view(base)
  let assert Ok(value) = transaction.begin(base, compressor, [])
  let value = transaction.begin_nested(value)
  let assert Ok(value) =
    transaction.apply_edit(
      value,
      types.ArrayInsert([], 1, [types.StringValue("discarded")]),
    )
  let assert Ok(discarded_reference) =
    tree_kernel.reference_at(transaction.state(value), ["1"])
  let assert Ok(discarded_target) =
    tree_kernel.resolve_constraint(transaction.state(value), ["1"])
  let assert Ok(value) = transaction.abort_nested(value)

  let assert Ok(#(transaction.NoCommit(restored, restored_compressor), events)) =
    transaction.finish(value)
  events |> expect.to_equal(tree_kernel.ChangeEvents([], False))
  restored_compressor |> expect.to_equal(compressor)
  tree_kernel.visible_data(restored)
  |> expect.to_equal(tree_kernel.visible_data(base))
  tree_kernel.snapshot(restored) |> expect.to_equal(Ok(base_snapshot))
  tree_kernel.history_view(restored) |> expect.to_equal(base_history)
  tree_kernel.history_view(restored).pending |> expect.to_equal([])
  tree_kernel.reference_at(restored, ["0"])
  |> expect.to_equal(Ok(base_reference))
  tree_kernel.read_reference(restored, base_reference)
  |> expect.to_equal(Ok(types.StringValue("A")))
  tree_kernel.read_reference(restored, discarded_reference)
  |> expect.to_be_error
  transaction.begin(restored, restored_compressor, [discarded_target])
  |> expect.to_be_error

  let assert Ok(value) = transaction.begin(restored, restored_compressor, [])
  let assert Ok(value) =
    transaction.apply_edit(
      value,
      types.ArrayInsert([], 1, [types.StringValue("replacement")]),
    )
  let assert Ok(replacement_reference) =
    tree_kernel.reference_at(transaction.state(value), ["1"])
  replacement_reference |> expect.to_not_equal(discarded_reference)
  tree_kernel.read_reference(transaction.state(value), discarded_reference)
  |> expect.to_be_error
  tree_kernel.validate_constraints(transaction.state(value), [discarded_target])
  |> expect.to_be_error
  Nil
}

pub fn shared_tree_transaction_nested_savepoints_restore_inner_state_test() -> Nil {
  let base = initial_state()
  let assert Ok(value) = transaction.begin(base, fluid_ids.new(session()), [])
  let assert Ok(value) =
    transaction.apply_edit(
      value,
      types.SetField(["point", "x"], types.NumberValue(2.0)),
    )
  let value = transaction.begin_nested(value)
  let assert Ok(value) =
    transaction.apply_edit(
      value,
      types.SetField(["point", "x"], types.NumberValue(3.0)),
    )
  let value = transaction.begin_nested(value)
  let assert Ok(value) =
    transaction.apply_edit(
      value,
      types.SetField(["point", "x"], types.NumberValue(4.0)),
    )
  let assert Ok(value) = transaction.abort_nested(value)
  tree_kernel.read(transaction.state(value), ["point", "x"])
  |> expect.to_equal(Ok(Some(types.NumberValue(3.0))))
  let assert Ok(value) = transaction.commit_nested(value)
  tree_kernel.read(transaction.state(value), ["point", "x"])
  |> expect.to_equal(Ok(Some(types.NumberValue(3.0))))
  let assert Ok(#(transaction.Commit(state, _, _), events)) =
    transaction.finish(value)
  tree_kernel.read(state, ["point", "x"])
  |> expect.to_equal(Ok(Some(types.NumberValue(3.0))))
  events.events |> expect.to_equal([tree_kernel.TreeChanged(True)])
}

pub fn shared_tree_transaction_nested_constraints_use_current_author_order_test() -> Nil {
  let base = initial_state()
  let assert Ok(value) = transaction.begin(base, fluid_ids.new(session()), [])
  let assert Ok(value) =
    transaction.apply_edit(
      value,
      types.SetField(
        ["note"],
        types.ObjectValue("Point", [
          #("x", types.NumberValue(2.0)),
        ]),
      ),
    )
  let assert Ok(target) =
    tree_kernel.resolve_constraint(transaction.state(value), ["note"])
  let assert Ok(value) =
    transaction.begin_nested_with_constraints(value, [target])
  transaction.depth(value) |> expect.to_equal(2)
  let assert Ok(value) =
    transaction.apply_edit(
      value,
      types.SetField(["note", "x"], types.NumberValue(3.0)),
    )
  let assert Ok(value) = transaction.commit_nested(value)
  let #(finished, _) = transaction.finish(value) |> expect.to_be_ok
  let assert transaction.Commit(_, _, commit) = finished
  let assert [shared_change.DataChange(data)] =
    shared_change.to_changes(commit.change)
  data
  |> change.to_data
  |> fn(data) {
    data.nodes
    |> list.filter(fn(entry) {
      case entry.1.node_exists_constraint {
        Some(_) -> True
        None -> False
      }
    })
  }
  |> list.length
  |> expect.to_equal(1)
  Nil
}

pub fn shared_tree_transaction_nested_constraint_detects_target_remove_test() -> Nil {
  transaction_constraint_violation_after_remote_remove(1, True)
  |> expect.to_equal(1)
}

pub fn shared_tree_transaction_nested_constraint_ignores_other_remove_test() -> Nil {
  transaction_constraint_violation_after_remote_remove(2, True)
  |> expect.to_equal(0)
}

pub fn shared_tree_transaction_trailing_constraint_detects_target_remove_test() -> Nil {
  transaction_constraint_violation_after_remote_remove(1, False)
  |> expect.to_equal(1)
}

pub fn shared_tree_transaction_trailing_constraint_ignores_other_remove_test() -> Nil {
  transaction_constraint_violation_after_remote_remove(2, False)
  |> expect.to_equal(0)
}

pub fn identifier_constraint_uses_node_identity_and_retains_builds_test() {
  let values = [
    identifier_fixture.point("literal-custom-id", "constrained"),
    identifier_fixture.point("literal-custom-id", "survivor"),
  ]
  let base = identifier_array_state(identifier_fixture.session(), values)
  let assert Ok(constrained_reference) =
    tree_kernel.reference_at(base, ["left", "0"])
  let assert Ok(survivor_reference) =
    tree_kernel.reference_at(base, ["left", "1"])
  constrained_reference |> expect.to_not_equal(survivor_reference)
  tree_kernel.read(base, ["left", "0", "id"])
  |> expect.to_equal(tree_kernel.read(base, ["left", "1", "id"]))

  let assert Ok(open) =
    transaction.begin(base, fluid_ids.new(identifier_fixture.session()), [])
  let assert Ok(open) =
    transaction.apply_edit(
      open,
      types.ArrayInsert(["left"], 2, [
        types.ObjectValue(identifier_fixture.point_type, [
          #("label", types.StringValue("created")),
        ]),
      ]),
    )
  let assert Ok(target) =
    tree_kernel.resolve_constraint(transaction.state(open), ["left", "0"])
  let assert Ok(open) =
    transaction.begin_nested_with_constraints(open, [target])
  let assert Ok(open) =
    transaction.apply_edit(
      open,
      types.SetField(["left", "2", "label"], types.StringValue("created-final")),
    )
  let assert Ok(open) = transaction.commit_nested(open)
  let #(state, commit) = case transaction.finish(open) {
    Ok(#(transaction.Commit(state, _, commit), _)) -> #(state, commit)
    Ok(#(transaction.NoCommit(_, _), _)) ->
      panic as "Identifier transaction produced no commit"
    Error(error) -> panic as { string.inspect(error) }
  }
  let assert Ok(Some(created_identifier)) =
    tree_kernel.read(state, ["left", "2", "id"])

  let remote_base = identifier_array_state(other_session(), values)
  let assert Ok(remote_order) = change.identity_order([#(remote_revision(), 0)])
  let remote_commit = case
    tree_kernel.apply_local(
      remote_base,
      remote_revision(),
      remote_order,
      types.ArrayRemove(["left"], 0, 1),
    )
  {
    Ok(#(_, commit, _)) -> commit
    Error(error) -> panic as { string.inspect(error) }
  }
  let rollback_revisions = [
    rollback_revision_one(),
    rollback_revision_two(),
    rollback_revision_three(),
  ]
  let revisions =
    [
      remote_revision(),
      ..list.append(rollback_revisions, [
        commit.revision,
        ..shared_change.identity_revisions(commit.change)
      ])
    ]
    |> list.unique
  let assert Ok(order) =
    revisions
    |> list.index_map(fn(revision, index) { #(revision, index) })
    |> change.identity_order
  let rebased = case
    tree_kernel.receive_ordered(
      state,
      remote_commit,
      order,
      types.SequencePoint(1, 0),
      0,
      0,
      Allocation(rollback_revisions, order),
      mint,
    )
  {
    Ok(#(state, _, _)) -> state
    Error(error) -> panic as { string.inspect(error) }
  }
  tree_kernel.read(rebased, ["left", "0", "label"])
  |> expect.to_equal(Ok(Some(types.StringValue("survivor"))))
  tree_kernel.read(rebased, ["left", "1"]) |> expect.to_equal(Ok(None))
  tree_kernel.reference_at(rebased, ["left", "0"])
  |> expect.to_equal(Ok(survivor_reference))
  tree_kernel.read_reference(rebased, constrained_reference)
  |> expect.to_equal(
    Ok(identifier_fixture.point("literal-custom-id", "constrained")),
  )

  let pending =
    tree_kernel.history_view(rebased).pending
    |> list.first
    |> expect.to_be_ok
  let data =
    pending.change
    |> shared_change.to_changes
    |> list.filter_map(fn(item) {
      case item {
        shared_change.DataChange(data) -> Ok(data)
        shared_change.SchemaChange(_, _, _) -> Error(Nil)
      }
    })
    |> list.first
    |> expect.to_be_ok
  let data = change.to_data(data)
  data.constraint_violation_count |> expect.to_equal(1)
  let retained = data.builds != [] || data.refreshers != []
  retained |> expect.to_be_true
  list.append(data.builds, data.refreshers)
  |> list.flat_map(fn(build) { build.trees })
  |> list.any(fn(value) {
    case value {
      types.ObjectValue(type_id, fields)
        if type_id == identifier_fixture.point_type
      -> list.key_find(fields, "id") == Ok(created_identifier)
      _ -> False
    }
  })
  |> expect.to_be_true
}

fn transaction_constraint_violation_after_remote_remove(
  index: Int,
  add_nested_edit: Bool,
) -> Int {
  let values = [
    types.StringValue("A"),
    types.StringValue("B"),
    types.StringValue("Z"),
  ]
  let base = array_state(session(), values)
  let assert Ok(value) = transaction.begin(base, fluid_ids.new(session()), [])
  let assert Ok(value) =
    transaction.apply_edit(
      value,
      types.ArrayInsert([], 0, [types.StringValue("C")]),
    )
  tree_kernel.read(transaction.state(value), ["2"])
  |> expect.to_equal(Ok(Some(types.StringValue("B"))))
  let assert Ok(target) =
    tree_kernel.resolve_constraint(transaction.state(value), ["2"])
  let assert Ok(value) =
    transaction.begin_nested_with_constraints(value, [target])
  let value = case add_nested_edit {
    True -> {
      let assert Ok(value) =
        transaction.apply_edit(
          value,
          types.ArrayInsert([], 4, [types.StringValue("D")]),
        )
      value
    }
    False -> value
  }
  let assert Ok(value) = transaction.commit_nested(value)
  let assert Ok(#(transaction.Commit(state, _, commit), _)) =
    transaction.finish(value)

  let remote_base = array_state(other_session(), values)
  let assert Ok(remote_order) = change.identity_order([#(remote_revision(), 0)])
  let assert Ok(#(_, remote_commit, _)) =
    tree_kernel.apply_local(
      remote_base,
      remote_revision(),
      remote_order,
      types.ArrayRemove([], index, index + 1),
    )
  let rollback_revisions = [
    rollback_revision_one(),
    rollback_revision_two(),
    rollback_revision_three(),
  ]
  let revisions =
    [
      remote_revision(),
      ..list.append(rollback_revisions, [
        commit.revision,
        ..shared_change.identity_revisions(commit.change)
      ])
    ]
    |> list.unique
  let assert Ok(order) =
    revisions
    |> list.index_map(fn(revision, index) { #(revision, index) })
    |> change.identity_order
  let #(rebased, _, _) =
    tree_kernel.receive_ordered(
      state,
      remote_commit,
      order,
      types.SequencePoint(1, 0),
      0,
      0,
      Allocation(rollback_revisions, order),
      mint,
    )
    |> expect.to_be_ok
  let pending =
    tree_kernel.history_view(rebased).pending
    |> list.first
    |> expect.to_be_ok
  let item =
    pending.change
    |> shared_change.to_changes
    |> list.filter(fn(item) {
      case item {
        shared_change.DataChange(_) -> True
        shared_change.SchemaChange(_, _, _) -> False
      }
    })
    |> list.first
    |> expect.to_be_ok
  let assert shared_change.DataChange(data) = item
  change.to_data(data).constraint_violation_count
}

pub fn shared_tree_transaction_nested_abort_discards_nested_constraints_test() -> Nil {
  let base = initial_state()
  let assert Ok(value) = transaction.begin(base, fluid_ids.new(session()), [])
  let assert Ok(target) = tree_kernel.resolve_constraint(base, ["point"])
  let assert Ok(value) =
    transaction.begin_nested_with_constraints(value, [target])
  let assert Ok(value) = transaction.abort_nested(value)
  let assert Ok(value) =
    transaction.apply_edit(
      value,
      types.SetField(["point", "x"], types.NumberValue(2.0)),
    )
  let assert Ok(#(transaction.Commit(_, _, commit), _)) =
    transaction.finish(value)
  let assert [shared_change.DataChange(data)] =
    shared_change.to_changes(commit.change)
  data
  |> change.to_data
  |> fn(data) {
    data.nodes
    |> list.filter(fn(entry) {
      case entry.1.node_exists_constraint {
        Some(_) -> True
        None -> False
      }
    })
  }
  |> list.length
  |> expect.to_equal(0)
  Nil
}

pub fn shared_tree_transaction_outer_abort_after_inner_commit_restores_base_test() -> Nil {
  let base = initial_state()
  let compressor = fluid_ids.new(session())
  let assert Ok(base_reference) = tree_kernel.reference_at(base, ["point"])
  let assert Ok(base_snapshot) = tree_kernel.snapshot(base)
  let assert Ok(value) = transaction.begin(base, compressor, [])
  let value = transaction.begin_nested(value)
  let assert Ok(value) =
    transaction.apply_edit(
      value,
      types.SetField(["point", "x"], types.NumberValue(4.0)),
    )
  let assert Ok(value) = transaction.commit_nested(value)
  let advanced = transaction.compressor(value)
  let assert Ok(#(state, aborted_compressor)) = transaction.abort(value)
  tree_kernel.visible_data(state)
  |> expect.to_equal(tree_kernel.visible_data(base))
  tree_kernel.history_view(state)
  |> expect.to_equal(tree_kernel.history_view(base))
  tree_kernel.snapshot(state) |> expect.to_equal(Ok(base_snapshot))
  tree_kernel.reference_at(state, ["point"])
  |> expect.to_equal(Ok(base_reference))
  tree_kernel.read_reference(state, base_reference)
  |> expect.to_equal(
    Ok(
      types.ObjectValue("Point", [
        #("x", types.NumberValue(1.0)),
      ]),
    ),
  )
  aborted_compressor |> expect.to_equal(advanced)
  fluid_ids.serialize(aborted_compressor, False)
  |> expect.to_equal(fluid_ids.serialize(compressor, False))
}

pub fn shared_tree_transaction_outer_lifecycle_rejects_open_nested_scope_test() -> Nil {
  let base = initial_state()
  let assert Ok(value) = transaction.begin(base, fluid_ids.new(session()), [])
  let nested = transaction.begin_nested(value)
  transaction.finish(nested) |> expect.to_be_error
  transaction.abort(nested) |> expect.to_be_error
  let assert Ok(value) = transaction.abort_nested(nested)
  let assert Ok(#(state, _)) = transaction.abort(value)
  state |> expect.to_equal(base)
}

pub fn shared_tree_transaction_nested_lifecycle_rejects_depth_zero_test() -> Nil {
  let assert Ok(value) =
    transaction.begin(initial_state(), fluid_ids.new(session()), [])
  transaction.commit_nested(value) |> expect.to_be_error
  transaction.abort_nested(value) |> expect.to_be_error
  transaction.state(value) |> expect.to_equal(initial_state())
}

pub fn shared_tree_transaction_empty_finish_restores_base_compressor_test() -> Nil {
  let base = initial_state()
  let compressor = fluid_ids.new(session())
  let assert Ok(target) = tree_kernel.resolve_constraint(base, ["point"])
  let assert Ok(value) = transaction.begin(base, compressor, [target])
  let assert Ok(#(transaction.NoCommit(state, restored), events)) =
    transaction.finish(value)
  events |> expect.to_equal(tree_kernel.ChangeEvents([], False))
  state |> expect.to_equal(base)
  restored |> expect.to_equal(compressor)
}

pub fn shared_tree_transaction_same_value_edit_is_not_no_commit_test() -> Nil {
  let base = initial_state()
  let assert Ok(value) = transaction.begin(base, fluid_ids.new(session()), [])
  let assert Ok(value) =
    transaction.apply_edit(
      value,
      types.SetField(["point", "x"], types.NumberValue(1.0)),
    )
  let assert Ok(#(transaction.Commit(_, _, _), events)) =
    transaction.finish(value)
  events.events |> expect.to_equal([])
}

pub fn shared_tree_transaction_rejects_detached_constraint_at_begin_test() -> Nil {
  let base = initial_state()
  let compressor = fluid_ids.new(session())
  let assert Ok(target) = tree_kernel.resolve_constraint(base, ["note"])
  let assert Ok(#(removed, Some(_), _, compressor)) =
    tree_runtime.author_edit(base, types.ClearField(["note"]), compressor)
  let assert Error(types.InvalidEdit(["note"], _)) =
    transaction.begin(removed, compressor, [target])
  Nil
}

pub fn shared_tree_transaction_commits_valid_node_constraint_test() -> Nil {
  let base = initial_state()
  let assert Ok(target) = tree_kernel.resolve_constraint(base, ["point"])
  let assert Ok(value) =
    transaction.begin(base, fluid_ids.new(session()), [target])
  let assert Ok(value) =
    transaction.apply_edit(
      value,
      types.SetField(["point", "x"], types.NumberValue(5.0)),
    )
  let assert Ok(#(transaction.Commit(_, _, commit), _)) =
    transaction.finish(value)
  let assert [shared_change.DataChange(data)] =
    shared_change.to_changes(commit.change)
  let constrained =
    change.to_data(data).nodes
    |> list.filter(fn(entry) {
      case entry.1.node_exists_constraint {
        Some(_) -> True
        None -> False
      }
    })
  list.length(constrained) |> expect.to_equal(1)
}

pub fn shared_tree_transaction_wire_requires_input_sections_test() -> Nil {
  let assert Ok(fixtures.Case(input: input, ..)) =
    fixtures.load("transaction-wire")
  let assert Ok(VObject(root)) = json_ot.parse_json(json.to_string(input))

  ["messageBytes", "compressor", "context", "operands", "scenarios"]
  |> list.each(fn(key) {
    let changed =
      root
      |> list.filter(fn(entry) { entry.0 != key })
      |> VObject
      |> json_ot.to_json
    let _ = transaction_fixture.run_wire(changed) |> expect.to_be_error
    Nil
  })
}

pub fn shared_tree_transaction_wire_rejects_unknown_context_test() -> Nil {
  let assert Ok(fixtures.Case(input: input, ..)) =
    fixtures.load("transaction-wire")
  let assert Ok(VObject(root)) = json_ot.parse_json(json.to_string(input))
  let assert Ok(VObject(context)) = list.key_find(root, "context")
  let changed =
    root
    |> list.key_set(
      "context",
      VObject(list.key_set(context, "minVersionForCollab", VString("unknown"))),
    )
    |> VObject
    |> json_ot.to_json
  let _ = transaction_fixture.run_wire(changed) |> expect.to_be_error
  Nil
}

pub fn shared_tree_transaction_wire_rejects_malformed_compressor_test() -> Nil {
  let assert Ok(fixtures.Case(input: input, ..)) =
    fixtures.load("transaction-wire")
  let assert Ok(VObject(root)) = json_ot.parse_json(json.to_string(input))
  let assert Ok(VObject(compressors)) = list.key_find(root, "compressor")
  let assert Ok(VObject(nonviolated)) =
    list.key_find(compressors, "nonviolated")
  let changed =
    root
    |> list.key_set(
      "compressor",
      VObject(list.key_set(
        compressors,
        "nonviolated",
        VObject(list.key_set(nonviolated, "serialized", VString("invalid"))),
      )),
    )
    |> VObject
    |> json_ot.to_json
  let _ = transaction_fixture.run_wire(changed) |> expect.to_be_error
  Nil
}

pub fn shared_tree_transaction_wire_observes_constraints_and_encoder_output_test() -> Nil {
  let assert Ok(fixtures.Case(input: input, ..)) =
    fixtures.load("transaction-wire")
  let assert Ok(VObject(root)) = json_ot.parse_json(json.to_string(input))
  let assert Ok(VObject(message_bytes)) = list.key_find(root, "messageBytes")
  let original = case transaction_fixture.run_wire(input) {
    Ok(value) -> value
    Error(error) -> panic as { error }
  }
  let assert Ok(VObject(observation)) = wire_observation(original)
  let assert Ok(nonviolated) = list.key_find(observation, "nonviolated")
  let assert Ok(violated) = list.key_find(observation, "violated")
  let assert Ok(VObject(encoded_messages)) =
    list.key_find(observation, "message")
  let assert Ok(VObject(encoded_bytes)) =
    list.key_find(observation, "messageBytes")
  let assert Ok(encoded_nonviolated_message) =
    list.key_find(encoded_messages, "nonviolated")
  let assert Ok(encoded_violated_message) =
    list.key_find(encoded_messages, "violated")
  let assert Ok(VString(encoded_nonviolated)) =
    list.key_find(encoded_bytes, "nonviolated")
  let assert Ok(VString(encoded_violated)) =
    list.key_find(encoded_bytes, "violated")
  expect_wire_constraints(nonviolated, False, 0)
  expect_wire_constraints(violated, True, 1)
  let replay_input =
    root
    |> list.key_set(
      "messageBytes",
      VObject([
        #("nonviolated", VString(encoded_nonviolated)),
        #("violated", VString(encoded_violated)),
        #("over", list.key_find(message_bytes, "over") |> expect.to_be_ok),
      ]),
    )
    |> VObject
    |> json_ot.to_json
  let replayed = case transaction_fixture.run_wire(replay_input) {
    Ok(value) -> value
    Error(error) -> panic as { error }
  }
  let assert Ok(VObject(replayed_observation)) = wire_observation(replayed)
  list.key_find(replayed_observation, "nonviolated")
  |> expect.to_equal(Ok(nonviolated))
  list.key_find(replayed_observation, "violated")
  |> expect.to_equal(Ok(violated))
  let assert Ok(encoded_nonviolated_value) =
    json_ot.parse_json(encoded_nonviolated)
  let assert Ok(encoded_violated_value) = json_ot.parse_json(encoded_violated)
  encoded_nonviolated_value |> expect.to_equal(encoded_nonviolated_message)
  encoded_violated_value |> expect.to_equal(encoded_violated_message)
}

pub fn shared_tree_transaction_wire_rejects_noncanonical_bytes_test() -> Nil {
  let assert Ok(fixtures.Case(input: input, ..)) =
    fixtures.load("transaction-wire")
  let assert Ok(VObject(root)) = json_ot.parse_json(json.to_string(input))
  let assert Ok(VObject(message_bytes)) = list.key_find(root, "messageBytes")
  let assert Ok(VString(nonviolated_bytes)) =
    list.key_find(message_bytes, "nonviolated")
  let original = case transaction_fixture.run_wire(input) {
    Ok(value) -> value
    Error(error) -> panic as { error }
  }
  let assert Ok(VObject(original_observation)) = wire_observation(original)
  let assert Ok(original_nonviolated) =
    list.key_find(original_observation, "nonviolated")
  let changed_bytes =
    nonviolated_bytes
    |> string.replace("{\"revision\":4", "{ \"revision\":4")
  let changed =
    root
    |> list.key_set(
      "messageBytes",
      VObject(list.key_set(message_bytes, "nonviolated", VString(changed_bytes))),
    )
    |> VObject
    |> json_ot.to_json

  let encoded = case transaction_fixture.run_wire(changed) {
    Ok(value) -> value
    Error(error) -> panic as { error }
  }
  let assert Ok(VObject(observation)) = wire_observation(encoded)
  let assert Ok(VObject(encoded_bytes)) =
    list.key_find(observation, "messageBytes")
  let assert Ok(VString(encoded_nonviolated)) =
    list.key_find(encoded_bytes, "nonviolated")
  let is_echo = encoded_nonviolated == changed_bytes
  is_echo |> expect.to_be_false
  let assert Ok(_) = json_ot.parse_json(encoded_nonviolated)
  let replay_input =
    root
    |> list.key_set(
      "messageBytes",
      VObject(list.key_set(
        message_bytes,
        "nonviolated",
        VString(encoded_nonviolated),
      )),
    )
    |> VObject
    |> json_ot.to_json
  let replayed = case transaction_fixture.run_wire(replay_input) {
    Ok(value) -> value
    Error(error) -> panic as { error }
  }
  let assert Ok(VObject(replayed_observation)) = wire_observation(replayed)
  list.key_find(replayed_observation, "nonviolated")
  |> expect.to_equal(Ok(original_nonviolated))
}

pub fn shared_tree_transaction_wire_observes_independent_input_mutations_test() -> Nil {
  let assert Ok(fixtures.Case(input: input, ..)) =
    fixtures.load("transaction-wire")
  let assert Ok(original) = transaction_fixture.run_wire(input)

  [
    #(
      "nonviolated constraint flag",
      replace_nested_string(
        input,
        "messageBytes",
        "nonviolated",
        "\"violated\":false",
        "\"violated\":true",
      ),
    ),
    #(
      "violated count",
      replace_nested_string(
        input,
        "messageBytes",
        "violated",
        "\"violations\":1",
        "\"violations\":0",
      ),
    ),
    #(
      "compressor session",
      replace_input(
        input,
        "989422b1-6ee8-49b7-bb0c-b27c95030135",
        "989422b1-6ee8-49b7-bb0c-b27c95030136",
      ),
    ),
    #(
      "modular version",
      replace_nested_integer(input, "context", "modularChange", 5, 4),
    ),
    #(
      "message byte",
      replace_nested_string(
        input,
        "messageBytes",
        "nonviolated",
        "\"revision\":4",
        "\"revision\":3",
      ),
    ),
    #(
      "Identifier build value",
      replace_nested_string(
        input,
        "messageBytes",
        "nonviolated",
        "\"data\":[[0,\"wire\"],[1,5,\"wire-created\",10]]",
        "\"data\":[[0,\"wire\"],[1,\"changed-identifier\",\"wire-created\",10]]",
      ),
    ),
  ]
  |> list.each(fn(mutation) {
    case transaction_fixture.run_wire(mutation.1) {
      Error(_) -> Nil
      Ok(observation) ->
        case observation == original {
          False -> Nil
          True -> panic as { mutation.0 <> " mutation was not observed" }
        }
    }
  })
}

pub fn shared_tree_transaction_wire_observes_field_edit_mutation_test() -> Nil {
  let assert Ok(fixtures.Case(input: input, ..)) =
    fixtures.load("transaction-wire")
  let original = transaction_fixture.run_wire(input) |> expect.to_be_ok
  let changed =
    replace_nested_string(
      input,
      "messageBytes",
      "nonviolated",
      "\"fieldKey\":\"right\"",
      "\"fieldKey\":\"rightChanged\"",
    )
    |> transaction_fixture.run_wire
    |> expect.to_be_ok
  let assert Ok(VObject(original_observation)) = wire_observation(original)
  let assert Ok(VObject(changed_observation)) = wire_observation(changed)
  list.key_find(changed_observation, "nonviolated")
  |> expect.to_not_equal(list.key_find(original_observation, "nonviolated"))
}

fn wire_observation(value: json.Json) -> Result(json_ot.JsonValue, Nil) {
  let assert Ok(VObject(root)) = json_ot.parse_json(json.to_string(value))
  let assert Ok(VArray([observation])) = list.key_find(root, "observations")
  Ok(observation)
}

fn expect_wire_constraints(
  value: JsonValue,
  violated: Bool,
  violations: Int,
) -> Nil {
  let assert VObject(fields) = value
  list.key_find(fields, "constraints")
  |> expect.to_equal(
    Ok(VArray([VObject([#("violated", json_ot.VBool(violated))])])),
  )
  list.key_find(fields, "violations")
  |> expect.to_equal(Ok(json_ot.VNumber(json_ot.NInt(violations))))
}

fn replace_nested_string(
  input: json.Json,
  parent_key: String,
  child_key: String,
  before: String,
  after: String,
) -> json.Json {
  let assert Ok(VObject(root)) = json_ot.parse_json(json.to_string(input))
  let assert Ok(VObject(parent)) = list.key_find(root, parent_key)
  let assert Ok(VString(value)) = list.key_find(parent, child_key)
  let changed = string.replace(value, before, after)
  expect.to_be_false(changed == value)
  root
  |> list.key_set(
    parent_key,
    VObject(list.key_set(parent, child_key, VString(changed))),
  )
  |> VObject
  |> json_ot.to_json
}

fn replace_nested_integer(
  input: json.Json,
  parent_key: String,
  child_key: String,
  before: Int,
  after: Int,
) -> json.Json {
  let assert Ok(VObject(root)) = json_ot.parse_json(json.to_string(input))
  let assert Ok(VObject(parent)) = list.key_find(root, parent_key)
  let assert Ok(json_ot.VNumber(json_ot.NInt(value))) =
    list.key_find(parent, child_key)
  value |> expect.to_equal(before)
  root
  |> list.key_set(
    parent_key,
    VObject(list.key_set(
      parent,
      child_key,
      json_ot.VNumber(json_ot.NInt(after)),
    )),
  )
  |> VObject
  |> json_ot.to_json
}

fn replace_input(input: json.Json, before: String, after: String) -> json.Json {
  let raw = json.to_string(input)
  let changed = string.replace(raw, before, after)
  expect.to_be_false(changed == raw)
  let assert Ok(value) = json_ot.parse_json(changed)
  json_ot.to_json(value)
}
