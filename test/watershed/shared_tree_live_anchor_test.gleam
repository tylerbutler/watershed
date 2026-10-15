import gleam/list
import gleam/option.{Some}
import startest/expect
import watershed/fluid_ids
import watershed/tree/branch
import watershed/tree/change
import watershed/tree/forest
import watershed/tree/identifier_fixture
import watershed/tree/runtime
import watershed/tree/transaction
import watershed/tree/types
import watershed/tree_kernel

fn initial() -> tree_kernel.TreeState {
  identifier_fixture.state(
    identifier_fixture.full_stored(),
    identifier_fixture.full_view(),
    identifier_fixture.full_root(
      identifier_fixture.point("featured", "featured"),
      [
        identifier_fixture.point("duplicate", "same"),
        identifier_fixture.point("duplicate", "same"),
      ],
      [],
      [],
    ),
  )
}

fn author(
  state: tree_kernel.TreeState,
  compressor: fluid_ids.Compressor,
  edit: types.Edit,
) -> #(tree_kernel.TreeState, fluid_ids.Compressor) {
  let assert Ok(#(state, Some(_), _, compressor)) =
    runtime.author_edit(state, edit, compressor)
  #(state, compressor)
}

fn saved(state: tree_kernel.TreeState) -> forest.NodeRef {
  tree_kernel.reference_at(state, ["left", "1"]) |> expect.to_be_ok
}

fn same_node(
  state: tree_kernel.TreeState,
  reference: forest.NodeRef,
  path: List(String),
) -> Nil {
  tree_kernel.path_of_reference(state, reference) |> expect.to_equal(Ok(path))
  tree_kernel.reference_at(state, path) |> expect.to_equal(Ok(reference))
  tree_kernel.ensure_attached(state, reference) |> expect.to_equal(Ok(Nil))
  tree_kernel.read_reference(state, reference)
  |> expect.to_equal(
    tree_kernel.read(state, path) |> expect.to_be_ok |> expect.to_be_some |> Ok,
  )
}

pub fn live_anchor_insert_move_characterization_test() {
  let state = initial()
  let reference = saved(state)
  let first = tree_kernel.reference_at(state, ["left", "0"]) |> expect.to_be_ok
  first |> expect.to_not_equal(reference)
  let compressor = fluid_ids.new(identifier_fixture.session())
  let #(state, compressor) =
    author(
      state,
      compressor,
      types.ArrayInsert(["left"], 0, [
        identifier_fixture.point("new", "new"),
      ]),
    )
  same_node(state, reference, ["left", "2"])
  let #(state, compressor) =
    author(state, compressor, types.ArrayMove(["left"], 2, 3, ["left"], 0))
  same_node(state, reference, ["left", "0"])
  let #(state, _) =
    author(state, compressor, types.ArrayMove(["left"], 0, 1, ["right"], 0))
  same_node(state, reference, ["right", "0"])
}

pub fn live_anchor_transaction_preview_characterization_test() {
  [False, True]
  |> list.each(fn(abort) {
    let base = initial()
    let reference = saved(base)
    let compressor = fluid_ids.new(identifier_fixture.session())
    let assert Ok(open) = transaction.begin(base, compressor, [])
    let assert Ok(open) =
      transaction.apply_edit(
        open,
        types.ArrayInsert(["left"], 0, [
          identifier_fixture.point("preview", "preview"),
        ]),
      )
    let preview = transaction.state(open)
    let inserted =
      tree_kernel.reference_at(preview, ["left", "0"]) |> expect.to_be_ok
    same_node(preview, reference, ["left", "2"])
    case abort {
      True -> {
        let assert Ok(#(state, compressor)) = transaction.abort(open)
        same_node(state, reference, ["left", "1"])
        tree_kernel.read_reference(state, inserted) |> expect.to_be_error
        let #(state, _) =
          author(
            state,
            compressor,
            types.ArrayInsert(["left"], 0, [
              identifier_fixture.point("replacement", "preview"),
            ]),
          )
        tree_kernel.reference_at(state, ["left", "0"])
        |> expect.to_not_equal(Ok(inserted))
      }
      False -> {
        let assert Ok(#(transaction.Commit(state, _, _), _)) =
          transaction.finish(open)
        same_node(state, reference, ["left", "2"])
        same_node(state, inserted, ["left", "0"])
      }
    }
  })
}

pub fn live_anchor_remove_and_equal_replacement_characterization_test() {
  let base = initial()
  let reference = saved(base)
  let compressor = fluid_ids.new(identifier_fixture.session())
  let #(state, compressor) =
    author(base, compressor, types.ArrayRemove(["left"], 1, 2))
  tree_kernel.ensure_attached(state, reference) |> expect.to_be_error
  tree_kernel.path_of_reference(state, reference) |> expect.to_be_error
  tree_kernel.read_reference(state, reference)
  |> expect.to_equal(Ok(identifier_fixture.point("duplicate", "same")))
  let #(state, _) =
    author(
      state,
      compressor,
      types.ArrayInsert(["left"], 1, [
        identifier_fixture.point("duplicate", "same"),
      ]),
    )
  tree_kernel.reference_at(state, ["left", "1"])
  |> expect.to_not_equal(Ok(reference))
}

pub fn live_anchor_branch_rebase_characterization_test() {
  let origin = branch.origin("runtime", "document", "tree")
  let branches = branch.new(origin, initial())
  let main = branch.document(branches)
  let reference =
    branch.reference_at(branches, main, ["left", "1"]) |> expect.to_be_ok
  let assert Ok(#(branches, fork)) = branch.fork(branches, main)
  let fork_reference =
    branch.reference_at(branches, fork, ["left", "1"]) |> expect.to_be_ok
  let compressor = fluid_ids.new(identifier_fixture.session())
  let assert Ok(branch.AuthorResult(branches, Some(_), _, compressor)) =
    branch.author(
      branches,
      fork,
      types.SetField(["left", "1", "label"], types.StringValue("branch")),
      compressor,
    )
  let assert Ok(branch.AuthorResult(branches, Some(_), _, compressor)) =
    branch.author(
      branches,
      main,
      types.ArrayInsert(["left"], 0, [
        identifier_fixture.point("new", "new"),
      ]),
      compressor,
    )
  let assert Ok(#(branch.ReconcileResult(branches, _, _), compressor)) =
    branch.rebase_with_compressor(branches, fork, main, compressor)
  branch.reference_at(branches, fork, ["left", "2"])
  |> expect.to_equal(Ok(fork_reference))
  branch.path_of_reference(branches, fork, fork_reference)
  |> expect.to_equal(Ok(["left", "2"]))
  let assert Ok(#(branch.ReconcileResult(branches, _, _), _)) =
    branch.merge_with_compressor(branches, main, fork, False, compressor)
  branch.reference_at(branches, main, ["left", "2"])
  |> expect.to_equal(Ok(reference))
}

pub fn live_anchor_new_branch_content_characterization_test() {
  let branches =
    branch.new(branch.origin("runtime", "document", "tree"), initial())
  let main = branch.document(branches)
  let assert Ok(#(branches, fork)) = branch.fork(branches, main)
  let compressor = fluid_ids.new(identifier_fixture.session())
  let assert Ok(branch.AuthorResult(branches, Some(_), _, compressor)) =
    branch.author(
      branches,
      fork,
      types.ArrayInsert(["right"], 0, [
        identifier_fixture.point("duplicate", "fork"),
      ]),
      compressor,
    )
  let fork_reference =
    branch.reference_at(branches, fork, ["right", "0"]) |> expect.to_be_ok
  let assert Ok(branch.AuthorResult(branches, Some(_), _, compressor)) =
    branch.author(
      branches,
      main,
      types.ArrayInsert(["left"], 0, [
        identifier_fixture.point("duplicate", "main"),
      ]),
      compressor,
    )
  let main_reference =
    branch.reference_at(branches, main, ["left", "0"]) |> expect.to_be_ok
  let assert Ok(#(branch.ReconcileResult(branches, _, _), compressor)) =
    branch.rebase_with_compressor(branches, fork, main, compressor)
  branch.reference_at(branches, fork, ["right", "0"])
  |> expect.to_equal(Ok(fork_reference))
  let fork_state = branch.checkout_state(branches, fork) |> expect.to_be_ok
  tree_kernel.read_reference(fork_state, fork_reference)
  |> expect.to_equal(Ok(identifier_fixture.point("duplicate", "fork")))
  let assert Ok(#(branch.ReconcileResult(branches, _, _), _)) =
    branch.merge_with_compressor(branches, main, fork, False, compressor)
  branch.reference_at(branches, main, ["left", "0"])
  |> expect.to_equal(Ok(main_reference))
}

fn revisions() -> #(
  fluid_ids.StableId,
  fluid_ids.StableId,
  fluid_ids.StableId,
  change.IdentityOrder,
) {
  let assert Ok(local) =
    fluid_ids.stable_id("40000000-0000-4000-8000-000000000001")
  let assert Ok(remote) =
    fluid_ids.stable_id("40000000-0000-4000-8000-000000000002")
  let assert Ok(rollback) =
    fluid_ids.stable_id("40000000-0000-4000-8000-000000000003")
  let assert Ok(order) =
    change.identity_order([#(local, -3), #(remote, -2), #(rollback, -1)])
  #(local, remote, rollback, order)
}

fn mint_rollback(
  used: Bool,
) -> Result(#(fluid_ids.StableId, change.IdentityOrder, Bool), types.TreeError) {
  let #(_, _, rollback, order) = revisions()
  case used {
    False -> Ok(#(rollback, order, True))
    True ->
      Error(types.InvalidHistory("Unexpected additional rollback allocation"))
  }
}

pub fn live_anchor_remote_replay_characterization_test() {
  let base = initial()
  let original = saved(base)
  let #(local_id, remote_id, _, order) = revisions()
  let assert Ok(snapshot) = tree_kernel.snapshot(base)
  let assert Ok(peer_view) =
    fluid_ids.stable_id("50000000-0000-4000-8000-000000000001")
  let assert Ok(peer_session) =
    fluid_ids.session_id("60000000-0000-4000-8000-000000000001")
  let assert Ok(peer) =
    tree_kernel.restore(
      snapshot,
      peer_view,
      peer_session,
      identifier_fixture.full_view(),
    )
  let assert Ok(#(local, local_commit, _)) =
    tree_kernel.apply_local(
      base,
      local_id,
      order,
      types.ArrayInsert(["right"], 0, [
        identifier_fixture.point("duplicate", "local"),
      ]),
    )
  let inserted =
    tree_kernel.reference_at(local, ["right", "0"]) |> expect.to_be_ok
  let assert Ok(#(_, remote, _)) =
    tree_kernel.apply_local(
      peer,
      remote_id,
      order,
      types.ArrayInsert(["left"], 0, [
        identifier_fixture.point("duplicate", "remote"),
      ]),
    )
  let assert Ok(#(received, _, used)) =
    tree_kernel.receive(
      local,
      remote,
      types.SequencePoint(1, 0),
      0,
      0,
      False,
      mint_rollback,
    )
  same_node(received, original, ["left", "2"])
  same_node(received, inserted, ["right", "0"])
  let assert Ok(#(acked, _, _)) =
    tree_kernel.receive(
      received,
      local_commit,
      types.SequencePoint(2, 0),
      0,
      0,
      used,
      mint_rollback,
    )
  same_node(acked, original, ["left", "2"])
  same_node(acked, inserted, ["right", "0"])
}

pub fn live_anchor_remove_undo_characterization_test() {
  let branches =
    branch.new(branch.origin("runtime", "document", "tree"), initial())
  let main = branch.document(branches)
  let reference =
    branch.reference_at(branches, main, ["left", "1"]) |> expect.to_be_ok
  let compressor = fluid_ids.new(identifier_fixture.session())
  let assert Ok(branch.AuthorResult(branches, Some(commit), _, compressor)) =
    branch.author(branches, main, types.ArrayRemove(["left"], 1, 2), compressor)
  let assert Ok(#(branches, undo)) =
    branch.retain_revertible(
      branches,
      main,
      commit.revision,
      types.DefaultCommit,
    )
  let assert Ok(branch.RevertResult(branches, _, _, _, _, _)) =
    branch.revert(branches, undo, compressor)
  branch.reference_at(branches, main, ["left", "1"])
  |> expect.to_equal(Ok(reference))
}

pub fn live_anchor_replacement_characterization_test() {
  [[], ["child"]]
  |> list.each(fn(path) {
    let base = initial()
    let assert Ok(Some(value)) = tree_kernel.read(base, path)
    let assert Ok(old) = tree_kernel.reference_at(base, path)
    let #(state, _) =
      author(
        base,
        fluid_ids.new(identifier_fixture.session()),
        types.SetField(path, value),
      )
    tree_kernel.reference_at(state, path) |> expect.to_not_equal(Ok(old))
    forest.reference_status(tree_kernel.visible_forest(state), old)
    |> expect.to_equal(Ok(forest.RemovedNode))
  })
  let base = initial()
  let compressor = fluid_ids.new(identifier_fixture.session())
  let point = identifier_fixture.point("duplicate", "same")
  let #(state, compressor) =
    author(base, compressor, types.MapSet(["byKey"], "key", point))
  let assert Ok(old) = tree_kernel.reference_at(state, ["byKey", "key"])
  let #(state, _) =
    author(state, compressor, types.MapSet(["byKey"], "key", point))
  tree_kernel.reference_at(state, ["byKey", "key"])
  |> expect.to_not_equal(Ok(old))
  forest.reference_status(tree_kernel.visible_forest(state), old)
  |> expect.to_equal(Ok(forest.RemovedNode))
}

pub fn live_anchor_replayed_subtree_descendants_test() {
  let base = initial()
  let #(local_id, remote_id, _, order) = revisions()
  let assert Ok(snapshot) = tree_kernel.snapshot(base)
  let assert Ok(peer_view) =
    fluid_ids.stable_id("50000000-0000-4000-8000-000000000001")
  let assert Ok(peer_session) =
    fluid_ids.session_id("60000000-0000-4000-8000-000000000001")
  let assert Ok(peer) =
    tree_kernel.restore(
      snapshot,
      peer_view,
      peer_session,
      identifier_fixture.full_view(),
    )
  let assert Ok(#(local, _, _)) =
    tree_kernel.apply_local(
      base,
      local_id,
      order,
      types.SetField(
        [],
        identifier_fixture.full_root(
          identifier_fixture.point("duplicate", "replacement"),
          [],
          [identifier_fixture.point("duplicate", "descendant")],
          [],
        ),
      ),
    )
  let paths = [[], ["right"], ["right", "0"]]
  let references =
    list.map(paths, fn(path) {
      #(path, tree_kernel.reference_at(local, path) |> expect.to_be_ok)
    })
  let assert Ok(#(_, remote, _)) =
    tree_kernel.apply_local(
      peer,
      remote_id,
      order,
      types.SetField(["left", "0", "label"], types.StringValue("peer")),
    )
  let assert Ok(#(received, _, _)) =
    tree_kernel.receive(
      local,
      remote,
      types.SequencePoint(1, 0),
      0,
      0,
      False,
      mint_rollback,
    )
  references |> list.each(fn(pair) { same_node(received, pair.1, pair.0) })
}
