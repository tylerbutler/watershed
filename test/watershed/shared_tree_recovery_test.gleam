import gleam/json
import gleam/list
import gleam/option.{Some}
import startest/expect
import watershed/fluid_ids
import watershed/json_ot
import watershed/tree/change
import watershed/tree/forest
import watershed/tree/history
import watershed/tree/recovery
import watershed/tree/schema
import watershed/tree/shared_change
import watershed/tree/types.{
  type TreeError, ArrayMove, DefaultCommit, NumberValue, ObjectValue,
  SequencePoint, SetField, StringValue,
}
import watershed/tree_kernel

const tree_schema = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.number\":{\"kind\":{\"leaf\":0}},\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}},\"Item\":{\"kind\":{\"object\":{\"label\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.string\"]},\"score\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.number\"]}}}},\"Items\":{\"kind\":{\"object\":{\"\":{\"kind\":\"Sequence\",\"types\":[\"Item\"]}}}},\"Root\":{\"kind\":{\"object\":{\"left\":{\"kind\":\"Value\",\"types\":[\"Items\"]},\"right\":{\"kind\":\"Value\",\"types\":[\"Items\"]},\"title\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.string\"]}}}}},\"root\":{\"kind\":\"Value\",\"types\":[\"Root\"]}}"

type Allocation {
  Allocation(revisions: List(fluid_ids.StableId), order: change.IdentityOrder)
}

fn session(raw: String) -> fluid_ids.SessionId {
  fluid_ids.session_id(raw) |> expect.to_be_ok
}

fn local_session() -> fluid_ids.SessionId {
  session("10000000-0000-4000-8000-000000000001")
}

fn peer_session() -> fluid_ids.SessionId {
  session("20000000-0000-4000-8000-000000000002")
}

fn view(raw: String) -> fluid_ids.StableId {
  fluid_ids.stable_id(raw) |> expect.to_be_ok
}

fn root() -> types.TreeValue {
  ObjectValue("Root", [
    #(
      "left",
      types.ArrayValue("Items", [
        ObjectValue("Item", [
          #("label", StringValue("a")),
          #("score", NumberValue(1.0)),
        ]),
        ObjectValue("Item", [
          #("label", StringValue("b")),
          #("score", NumberValue(2.0)),
        ]),
      ]),
    ),
    #("right", types.ArrayValue("Items", [])),
    #("title", StringValue("base")),
  ])
}

fn initial_state(
  local: fluid_ids.SessionId,
  view_id: fluid_ids.StableId,
) -> tree_kernel.TreeState {
  let stored = schema.stored_from_string(tree_schema) |> expect.to_be_ok
  let initial = history.inspect(history.new(local)).sequenced
  let snapshot =
    tree_kernel.snapshot_from_parts(
      view_id,
      stored,
      forest.ForestData(Some(root()), [], 0),
      initial,
    )
    |> expect.to_be_ok
  tree_kernel.restore_unviewed(snapshot, view_id, local) |> expect.to_be_ok
}

fn revisions(count: Int) -> #(fluid_ids.Compressor, List(fluid_ids.StableId)) {
  let #(compressor, ids) =
    generate_revisions(fluid_ids.new(local_session()), count, [])
  let assert #(compressor, Some(range)) =
    fluid_ids.take_creation_range(compressor)
  #(fluid_ids.finalize(compressor, range) |> expect.to_be_ok, ids)
}

fn generate_revisions(
  compressor: fluid_ids.Compressor,
  count: Int,
  ids: List(fluid_ids.StableId),
) -> #(fluid_ids.Compressor, List(fluid_ids.StableId)) {
  case count {
    0 -> #(compressor, list.reverse(ids))
    _ -> {
      let #(compressor, id) = fluid_ids.generate(compressor) |> expect.to_be_ok
      let stable = fluid_ids.decompress(compressor, id) |> expect.to_be_ok
      generate_revisions(compressor, count - 1, [stable, ..ids])
    }
  }
}

fn mint(
  allocation: Allocation,
) -> Result(#(fluid_ids.StableId, change.IdentityOrder, Allocation), TreeError) {
  case allocation.revisions {
    [] -> Error(types.InvalidHistory("rollback allocation is exhausted"))
    [revision, ..rest] ->
      Ok(#(revision, allocation.order, Allocation(rest, allocation.order)))
  }
}

fn roundtrip(value: json.Json) -> json.Json {
  json_ot.parse_json(json.to_string(value))
  |> expect.to_be_ok
  |> json_ot.to_json
}

pub fn pending_move_recovery_preserves_native_history_test() {
  let #(compressor, ids) = revisions(12)
  let assert [
    move_revision,
    edit_revision,
    peer_before_revision,
    rollback_1,
    rollback_2,
    rollback_3,
    rollback_4,
    peer_after_revision,
    rollback_5,
    rollback_6,
    next_revision,
    _,
  ] = ids
  let order =
    ids
    |> list.index_map(fn(revision, index) { #(revision, index) })
    |> change.identity_order
    |> expect.to_be_ok
  let local =
    initial_state(local_session(), view("30000000-0000-4000-8000-000000000003"))
  let peer =
    initial_state(peer_session(), view("40000000-0000-4000-8000-000000000004"))
  let #(peer, peer_before, _) =
    tree_kernel.apply_local(
      peer,
      peer_before_revision,
      order,
      SetField(["title"], StringValue("peer-before")),
    )
    |> expect.to_be_ok
  let #(local, _, _) =
    tree_kernel.receive_ordered(
      local,
      peer_before,
      order,
      SequencePoint(1, 0),
      0,
      0,
      Allocation([], order),
      mint,
    )
    |> expect.to_be_ok
  let #(local, original_move, _) =
    tree_kernel.apply_local(
      local,
      move_revision,
      order,
      ArrayMove(["left"], 0, 1, ["right"], 0),
    )
    |> expect.to_be_ok
  let move_max_id = shared_change.max_local_id(original_move.change)
  let #(local, _, _) =
    tree_kernel.apply_local(
      local,
      edit_revision,
      order,
      SetField(["right", "0", "label"], StringValue("local")),
    )
    |> expect.to_be_ok
  tree_kernel.resubmit_commits(local) |> expect.to_be_ok
  let #(local, revertible) =
    tree_kernel.retain_revertible(local, move_revision, DefaultCommit)
    |> expect.to_be_ok

  let checkpoint =
    recovery.capture(local, compressor) |> expect.to_be_ok |> roundtrip
  let restored =
    recovery.restore(
      checkpoint,
      view("50000000-0000-4000-8000-000000000005"),
      compressor,
    )
    |> expect.to_be_ok

  let recovered_history = tree_kernel.history_view(restored).sequenced
  recovered_history.sequence_number |> expect.to_equal(1)
  recovered_history.minimum_sequence_number |> expect.to_equal(0)
  tree_kernel.resubmit_commits(restored)
  |> expect.to_be_ok
  |> list.each(fn(commit) {
    shared_change.to_changes(commit.change)
    |> list.each(fn(item) {
      case item {
        shared_change.SchemaChange(..) -> Nil
        shared_change.DataChange(data) ->
          change.to_data(data).nodes
          |> list.all(fn(node) { node.0.revision == Some(commit.revision) })
          |> expect.to_be_true
      }
    })
  })
  tree_kernel.array_values(restored, ["left"])
  |> expect.to_equal(
    Ok([
      ObjectValue("Item", [
        #("label", StringValue("b")),
        #("score", NumberValue(2.0)),
      ]),
    ]),
  )
  tree_kernel.read(restored, ["right", "0", "label"])
  |> expect.to_equal(Ok(Some(StringValue("local"))))
  tree_kernel.read(restored, ["title"])
  |> expect.to_equal(Ok(Some(StringValue("peer-before"))))
  tree_kernel.resubmit_commits(restored)
  |> expect.to_be_ok
  |> list.map(fn(commit) { commit.revision })
  |> expect.to_equal([move_revision, edit_revision])
  tree_kernel.revertible_is_valid(restored, revertible)
  |> expect.to_be_false

  let #(restored, _, _) =
    tree_kernel.receive_ordered(
      restored,
      original_move,
      order,
      SequencePoint(2, 0),
      1,
      0,
      Allocation([], order),
      mint,
    )
    |> expect.to_be_ok
  let #(_, peer_after, _) =
    tree_kernel.apply_local(
      peer,
      peer_after_revision,
      order,
      SetField(["title"], StringValue("peer-after")),
    )
    |> expect.to_be_ok
  let #(restored, _, _) =
    tree_kernel.receive_ordered(
      restored,
      peer_after,
      order,
      SequencePoint(3, 0),
      2,
      0,
      Allocation(
        [rollback_1, rollback_2, rollback_3, rollback_4, rollback_5, rollback_6],
        order,
      ),
      mint,
    )
    |> expect.to_be_ok
  tree_kernel.read(restored, ["right", "0", "label"])
  |> expect.to_equal(Ok(Some(StringValue("local"))))
  tree_kernel.resubmit_commits(restored)
  |> expect.to_be_ok
  |> list.map(fn(commit) { commit.revision })
  |> expect.to_equal([edit_revision])

  let #(_, next, _) =
    expect.to_be_ok(tree_kernel.apply_local(
      restored,
      next_revision,
      order,
      types.ArrayInsert(["right"], 1, [
        ObjectValue("Item", [
          #("label", StringValue("next")),
          #("score", NumberValue(3.0)),
        ]),
      ]),
    ))
  expect.to_be_true(shared_change.max_local_id(next.change) > move_max_id)
}

pub fn recovery_refuses_malformed_and_live_branch_state_test() {
  let #(compressor, _) = revisions(1)
  let state =
    initial_state(local_session(), view("60000000-0000-4000-8000-000000000006"))
  recovery.restore(
    json.object([#("version", json.int(1))]),
    view("70000000-0000-4000-8000-000000000007"),
    compressor,
  )
  |> expect.to_be_error

  let #(branch_history, _) =
    history.fork_local(
      tree_kernel.branch_history(state),
      types.DocumentCheckout,
    )
    |> expect.to_be_ok
  recovery.capture(
    tree_kernel.with_branch_history(state, branch_history),
    compressor,
  )
  |> expect.to_be_error

  Nil
}
