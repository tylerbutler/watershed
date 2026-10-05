import gleam/list
import gleam/option.{None, Some}
import gleam/result
import startest/expect
import watershed/fluid_ids
import watershed/tree/array_fixture
import watershed/tree/branch
import watershed/tree/change
import watershed/tree/forest
import watershed/tree/history
import watershed/tree/identifier_fixture
import watershed/tree/runtime
import watershed/tree/schema
import watershed/tree/shared_change
import watershed/tree/transaction
import watershed/tree/types.{NumberValue, ObjectValue, SetField}
import watershed/tree_kernel

fn identifier_branch_state() -> tree_kernel.TreeState {
  identifier_fixture.state(
    identifier_fixture.full_stored(),
    identifier_fixture.full_view(),
    identifier_fixture.full_root(
      identifier_fixture.point("child", "child"),
      [],
      [],
      [],
    ),
  )
}

fn generated_point(label: String) -> types.TreeValue {
  ObjectValue(identifier_fixture.point_type, [
    #("label", types.StringValue(label)),
  ])
}

fn reserve_ids(
  compressor: fluid_ids.Compressor,
  count: Int,
) -> fluid_ids.Compressor {
  case count {
    0 -> compressor
    _ -> {
      let assert Ok(#(compressor, _)) = fluid_ids.generate(compressor)
      reserve_ids(compressor, count - 1)
    }
  }
}

pub fn local_branch_shared_allocator_matches_pinned_ranges_test() -> Nil {
  let initial = reserve_ids(fluid_ids.new(identifier_fixture.session()), 3)
  let #(compressor, _) = fluid_ids.take_creation_range(initial)
  let forest =
    branch.new(
      branch.origin("runtime", "document", "tree"),
      identifier_branch_state(),
    )
  let document = branch.document(forest)
  let assert Ok(#(forest, fork)) = branch.fork(forest, document)

  let assert Ok(branch.AuthorResult(forest, Some(branch_commit), _, compressor)) =
    branch.author(
      forest,
      fork,
      types.ArrayInsert(["right"], 0, [generated_point("branch-id")]),
      compressor,
    )
  let assert Ok(Some(types.StringValue(branch_id))) =
    branch.read(forest, fork, ["right", "0", "id"])
  let assert Ok(branch.AuthorResult(forest, Some(main_commit), _, compressor)) =
    branch.author(
      forest,
      document,
      types.ArrayInsert(["left"], 0, [generated_point("main-id")]),
      compressor,
    )
  let assert Ok(Some(types.StringValue(main_id))) =
    branch.read(forest, document, ["left", "0", "id"])
  let assert #(compressor, Some(fluid_ids.CreationRange(_, Some(main_range)))) =
    fluid_ids.take_creation_range(compressor)

  main_range.first_gen_count |> expect.to_equal(4)
  main_range.count |> expect.to_equal(4)
  branch_commit.revision |> expect.to_not_equal(main_commit.revision)
  branch_id |> expect.to_not_equal(main_id)

  let assert Ok(open) =
    transaction.begin(
      branch.checkout_state(forest, fork) |> expect.to_be_ok,
      compressor,
      [],
    )
  let assert Ok(open) =
    transaction.apply_edit(
      open,
      types.ArrayInsert(["right"], 1, [generated_point("aborted-id")]),
    )
  let assert Ok(#(_, compressor)) = transaction.abort(open)
  let assert Ok(branch.AuthorResult(forest, Some(_), _, compressor)) =
    branch.author(
      forest,
      fork,
      types.ArrayMove(["right"], 0, 1, ["right"], 1),
      compressor,
    )
  let assert Ok(#(branch.ReconcileResult(forest, _, [_, _]), compressor)) =
    branch.merge_with_compressor(forest, document, fork, False, compressor)
  let assert #(_, Some(fluid_ids.CreationRange(_, Some(merge_range)))) =
    fluid_ids.take_creation_range(compressor)

  merge_range.first_gen_count |> expect.to_equal(8)
  merge_range.count |> expect.to_equal(5)
  branch.read(forest, document, ["right", "0", "id"])
  |> expect.to_equal(Ok(Some(types.StringValue(branch_id))))
  Nil
}

pub fn local_branch_shared_allocator_interleaves_three_checkouts_test() -> Nil {
  let forest =
    branch.new(
      branch.origin("runtime", "document", "tree"),
      identifier_branch_state(),
    )
  let document = branch.document(forest)
  let compressor = fluid_ids.new(identifier_fixture.session())
  let assert Ok(branch.AuthorResult(forest, Some(main_first), _, compressor)) =
    branch.author(
      forest,
      document,
      types.SetField(["child", "label"], types.StringValue("main-first")),
      compressor,
    )
  let assert Ok(#(forest, fork_a)) = branch.fork(forest, document)
  let assert Ok(#(forest, fork_b)) = branch.fork(forest, document)
  let assert Ok(branch.AuthorResult(forest, Some(commit_a), _, compressor)) =
    branch.author(
      forest,
      fork_a,
      types.ArrayInsert(["right"], 0, [generated_point("fork-a")]),
      compressor,
    )
  let assert Ok(Some(types.StringValue(id_a))) =
    branch.read(forest, fork_a, ["right", "0", "id"])
  let reference_a =
    branch.reference_at(forest, fork_a, ["right", "0"]) |> expect.to_be_ok
  let assert Ok(branch.AuthorResult(forest, Some(commit_b), _, compressor)) =
    branch.author(
      forest,
      fork_b,
      types.ArrayInsert(["right"], 0, [generated_point("fork-b")]),
      compressor,
    )
  let assert Ok(Some(types.StringValue(id_b))) =
    branch.read(forest, fork_b, ["right", "0", "id"])
  id_a |> expect.to_not_equal(id_b)

  let before_abort = fluid_ids.serialize(compressor, True)
  let assert Ok(#(forest, open)) =
    branch.begin_transaction(forest, fork_a, compressor, [])
  let assert Ok(open) =
    branch.transaction_apply(
      open,
      types.ArrayInsert(["left"], 0, [generated_point("aborted")]),
    )
  let compressor = branch.transaction_compressor(open)
  let assert Ok(#(forest, compressor)) =
    branch.abort_transaction(forest, open, compressor)
  fluid_ids.serialize(compressor, True) |> expect.to_not_equal(before_abort)

  let assert Ok(branch.AuthorResult(forest, Some(move_a), _, compressor)) =
    branch.author(
      forest,
      fork_a,
      types.ArrayMove(["right"], 0, 1, ["right"], 1),
      compressor,
    )
  branch.reference_at(forest, fork_a, ["right", "0"])
  |> expect.to_equal(Ok(reference_a))
  let assert Ok(branch.AuthorResult(forest, Some(main_second), _, compressor)) =
    branch.author(
      forest,
      document,
      types.ArrayInsert(["left"], 0, [generated_point("main-second")]),
      compressor,
    )
  let assert #(compressor, Some(fluid_ids.CreationRange(_, Some(main_range)))) =
    fluid_ids.take_creation_range(compressor)
  main_range.first_gen_count |> expect.to_equal(1)
  main_range.count |> expect.to_equal(10)

  let assert Ok(#(branch.ReconcileResult(forest, _, merged_a), compressor)) =
    branch.merge_with_compressor(forest, document, fork_a, False, compressor)
  list.map(merged_a, fn(commit) { commit.revision })
  |> expect.to_equal([commit_a.revision, move_a.revision])
  branch.read(forest, document, ["right", "0", "id"])
  |> expect.to_equal(Ok(Some(types.StringValue(id_a))))
  let assert #(compressor, Some(fluid_ids.CreationRange(_, Some(a_range)))) =
    fluid_ids.take_creation_range(compressor)
  let assert Ok(#(branch.ReconcileResult(forest, _, merged_b), compressor)) =
    branch.merge_with_compressor(forest, document, fork_b, False, compressor)
  list.map(merged_b, fn(commit) { commit.revision })
  |> expect.to_equal([commit_b.revision])
  let assert #(_, Some(fluid_ids.CreationRange(_, Some(b_range)))) =
    fluid_ids.take_creation_range(compressor)

  a_range.first_gen_count |> expect.to_equal(11)
  a_range.count |> expect.to_equal(2)
  b_range.first_gen_count |> expect.to_equal(13)
  b_range.count |> expect.to_equal(1)
  main_first.revision |> expect.to_not_equal(main_second.revision)
  let assert Ok(Some(types.StringValue(main_right_zero))) =
    branch.read(forest, document, ["right", "0", "id"])
  let assert Ok(Some(types.StringValue(main_right_one))) =
    branch.read(forest, document, ["right", "1", "id"])
  list.contains([main_right_zero, main_right_one], id_a) |> expect.to_be_true
  list.contains([main_right_zero, main_right_one], id_b) |> expect.to_be_true
}

pub fn local_branch_transaction_is_one_outer_commit_test() -> Nil {
  let forest =
    branch.new(branch.origin("runtime", "document", "tree"), branch_state())
  let document = branch.document(forest)
  let assert Ok(#(forest, fork)) = branch.fork(forest, document)
  let compressor = fluid_ids.new(session())
  let assert Ok(#(forest, open)) =
    branch.begin_transaction(forest, fork, compressor, [])
  let assert Ok(open) =
    branch.transaction_apply(open, SetField(["point", "x"], NumberValue(7.0)))
  let assert Ok(open) =
    branch.transaction_apply(open, SetField(["point", "y"], NumberValue(9.0)))
  let compressor = branch.transaction_compressor(open)
  let assert Ok(branch.TransactionCommit(forest, commit, events, compressor)) =
    branch.finish_transaction(forest, open, compressor)

  branch.local_history(forest, fork)
  |> expect.to_be_ok
  |> fn(local) { local.commits }
  |> expect.to_equal([commit])
  branch.read(forest, fork, ["point", "x"])
  |> expect.to_equal(Ok(Some(NumberValue(7.0))))
  branch.read(forest, fork, ["point", "y"])
  |> expect.to_equal(Ok(Some(NumberValue(9.0))))
  list.length(events) |> expect.to_equal(1)
  let assert #(_, Some(fluid_ids.CreationRange(_, Some(range)))) =
    fluid_ids.take_creation_range(compressor)
  range.count |> expect.to_equal(1)
}

pub fn local_branch_nested_abort_preserves_identifier_allocation_test() -> Nil {
  let forest =
    branch.new(
      branch.origin("runtime", "document", "tree"),
      identifier_branch_state(),
    )
  let document = branch.document(forest)
  let assert Ok(#(forest, fork)) = branch.fork(forest, document)
  let assert Ok(#(forest, open)) =
    branch.begin_transaction(
      forest,
      fork,
      fluid_ids.new(identifier_fixture.session()),
      [],
    )
  let open = branch.transaction_begin_nested(open)
  let assert Ok(open) =
    branch.transaction_apply(
      open,
      types.ArrayInsert(["left"], 0, [generated_point("aborted")]),
    )
  let assert Ok(Some(types.StringValue(aborted_id))) =
    branch.transaction_read(open, ["left", "0", "id"])
  let assert Ok(open) = branch.transaction_abort_nested(open)
  let assert Ok(open) =
    branch.transaction_apply(
      open,
      types.ArrayInsert(["left"], 0, [generated_point("committed")]),
    )
  let assert Ok(Some(types.StringValue(committed_id))) =
    branch.transaction_read(open, ["left", "0", "id"])
  aborted_id |> expect.to_not_equal(committed_id)
  let compressor = branch.transaction_compressor(open)
  let assert Ok(branch.TransactionCommit(forest, _, _, compressor)) =
    branch.finish_transaction(forest, open, compressor)
  branch.read(forest, fork, ["left", "0", "id"])
  |> expect.to_equal(Ok(Some(types.StringValue(committed_id))))
  let assert #(_, Some(fluid_ids.CreationRange(_, Some(range)))) =
    fluid_ids.take_creation_range(compressor)
  range.first_gen_count |> expect.to_equal(1)
  range.count |> expect.to_equal(4)
}

pub fn local_branch_transaction_abort_preserves_main_callback_edit_test() -> Nil {
  let forest =
    branch.new(branch.origin("runtime", "document", "tree"), branch_state())
  let document = branch.document(forest)
  let assert Ok(#(forest, fork)) = branch.fork(forest, document)
  let assert Ok(#(forest, open)) =
    branch.begin_transaction(forest, fork, fluid_ids.new(session()), [])
  let assert Ok(open) =
    branch.transaction_apply(open, SetField(["point", "x"], NumberValue(7.0)))
  let assert Ok(branch.AuthorResult(
    forest,
    Some(main_commit),
    [main_event],
    compressor,
  )) =
    branch.author(
      forest,
      document,
      SetField(["point", "y"], NumberValue(9.0)),
      branch.transaction_compressor(open),
    )
  let assert Ok(#(forest, compressor)) =
    branch.abort_transaction(forest, open, compressor)

  branch.read(forest, fork, ["point", "x"])
  |> expect.to_equal(Ok(Some(NumberValue(1.0))))
  branch.read(forest, document, ["point", "y"])
  |> expect.to_equal(Ok(Some(NumberValue(9.0))))
  branch.history_view(forest, document)
  |> expect.to_be_ok
  |> fn(view) { view.pending }
  |> expect.to_equal([main_commit])
  main_event
  |> expect.to_equal(branch.BranchEvent(
    types.DocumentCheckout,
    Some(main_commit),
    tree_kernel.ChangeEvents([tree_kernel.TreeChanged(True)], False),
  ))
  let assert #(_, Some(fluid_ids.CreationRange(_, Some(range)))) =
    fluid_ids.take_creation_range(compressor)
  range.count |> expect.to_equal(2)
}

pub fn local_branch_transaction_commit_preserves_main_callback_edit_test() -> Nil {
  let forest =
    branch.new(branch.origin("runtime", "document", "tree"), branch_state())
  let document = branch.document(forest)
  let assert Ok(#(forest, fork)) = branch.fork(forest, document)
  let assert Ok(#(forest, open)) =
    branch.begin_transaction(forest, fork, fluid_ids.new(session()), [])
  let assert Ok(open) =
    branch.transaction_apply(open, SetField(["point", "x"], NumberValue(7.0)))
  let assert Ok(branch.AuthorResult(
    forest,
    Some(main_commit),
    [main_event],
    compressor,
  )) =
    branch.author(
      forest,
      document,
      SetField(["point", "y"], NumberValue(9.0)),
      branch.transaction_compressor(open),
    )
  let assert Ok(open) =
    branch.transaction_apply_with_compressor(
      open,
      SetField(["point", "y"], NumberValue(8.0)),
      compressor,
    )
  let compressor = branch.transaction_compressor(open)
  let assert Ok(branch.TransactionCommit(
    forest,
    fork_commit,
    [fork_event],
    compressor,
  )) = branch.finish_transaction(forest, open, compressor)

  branch.read(forest, fork, ["point", "x"])
  |> expect.to_equal(Ok(Some(NumberValue(7.0))))
  branch.read(forest, fork, ["point", "y"])
  |> expect.to_equal(Ok(Some(NumberValue(8.0))))
  branch.read(forest, document, ["point", "y"])
  |> expect.to_equal(Ok(Some(NumberValue(9.0))))
  branch.history_view(forest, document)
  |> expect.to_be_ok
  |> fn(view) { view.pending }
  |> expect.to_equal([main_commit])
  branch.local_history(forest, fork)
  |> expect.to_be_ok
  |> fn(local) { local.commits }
  |> expect.to_equal([fork_commit])
  main_event.checkout |> expect.to_equal(types.DocumentCheckout)
  fork_event.commit |> expect.to_equal(Some(fork_commit))
  let assert #(_, Some(fluid_ids.CreationRange(_, Some(range)))) =
    fluid_ids.take_creation_range(compressor)
  range.count |> expect.to_equal(3)
}

pub fn local_branch_main_transaction_preserves_fork_callback_edit_test() -> Nil {
  let forest =
    branch.new(branch.origin("runtime", "document", "tree"), branch_state())
  let document = branch.document(forest)
  let assert Ok(#(forest, fork)) = branch.fork(forest, document)
  let assert Ok(#(forest, open)) =
    branch.begin_transaction(forest, document, fluid_ids.new(session()), [])
  let assert Ok(open) =
    branch.transaction_apply(open, SetField(["point", "x"], NumberValue(7.0)))
  let assert Ok(branch.AuthorResult(
    forest,
    Some(fork_commit),
    [fork_event],
    compressor,
  )) =
    branch.author(
      forest,
      fork,
      SetField(["point", "y"], NumberValue(9.0)),
      branch.transaction_compressor(open),
    )
  let assert Ok(branch.TransactionCommit(forest, main_commit, [main_event], _)) =
    branch.finish_transaction(forest, open, compressor)

  branch.read(forest, document, ["point", "x"])
  |> expect.to_equal(Ok(Some(NumberValue(7.0))))
  branch.read(forest, fork, ["point", "y"])
  |> expect.to_equal(Ok(Some(NumberValue(9.0))))
  branch.history_view(forest, document)
  |> expect.to_be_ok
  |> fn(view) { view.pending }
  |> expect.to_equal([main_commit])
  branch.local_history(forest, fork)
  |> expect.to_be_ok
  |> fn(local) { local.commits }
  |> expect.to_equal([fork_commit])
  main_event.checkout |> expect.to_equal(types.DocumentCheckout)
  fork_event.commit |> expect.to_equal(Some(fork_commit))
}

pub fn local_branch_transaction_preserves_sibling_callback_edit_test() -> Nil {
  let forest =
    branch.new(branch.origin("runtime", "document", "tree"), branch_state())
  let document = branch.document(forest)
  let assert Ok(#(forest, source)) = branch.fork(forest, document)
  let assert Ok(#(forest, sibling)) = branch.fork(forest, document)
  let assert Ok(#(forest, open)) =
    branch.begin_transaction(forest, source, fluid_ids.new(session()), [])
  let assert Ok(open) =
    branch.transaction_apply(open, SetField(["point", "x"], NumberValue(7.0)))
  let assert Ok(branch.AuthorResult(
    forest,
    Some(sibling_commit),
    [_],
    compressor,
  )) =
    branch.author(
      forest,
      sibling,
      SetField(["point", "y"], NumberValue(9.0)),
      branch.transaction_compressor(open),
    )
  let assert Ok(#(forest, _)) =
    branch.abort_transaction(forest, open, compressor)

  branch.read(forest, source, ["point", "x"])
  |> expect.to_equal(Ok(Some(NumberValue(1.0))))
  branch.read(forest, sibling, ["point", "y"])
  |> expect.to_equal(Ok(Some(NumberValue(9.0))))
  branch.history_view(forest, document)
  |> expect.to_be_ok
  |> fn(view) { view.pending }
  |> expect.to_equal([])
  branch.local_history(forest, sibling)
  |> expect.to_be_ok
  |> fn(local) { local.commits }
  |> expect.to_equal([sibling_commit])
}

pub fn local_branch_constrained_source_commit_is_retained_after_rebase_test() -> Nil {
  let forest =
    branch.new(branch.origin("runtime", "document", "tree"), branch_state())
  let document = branch.document(forest)
  let compressor = fluid_ids.new(session())
  let assert Ok(branch.AuthorResult(forest, Some(initial_commit), _, compressor)) =
    branch.author(
      forest,
      document,
      SetField(["point", "y"], NumberValue(2.0)),
      compressor,
    )
  let assert Ok(#(forest, fork)) = branch.fork(forest, document)
  let constraint =
    branch.checkout_state(forest, fork)
    |> expect.to_be_ok
    |> tree_kernel.resolve_constraint(["point"])
    |> expect.to_be_ok
  let assert Ok(#(forest, open)) =
    branch.begin_transaction(forest, fork, compressor, [constraint])
  let assert Ok(open) =
    branch.transaction_apply(open, SetField(["point", "x"], NumberValue(7.0)))
  let compressor = branch.transaction_compressor(open)
  let assert Ok(branch.TransactionCommit(
    forest,
    transaction_commit,
    _,
    compressor,
  )) = branch.finish_transaction(forest, open, compressor)
  let assert Ok(#(forest, guarded_handle)) =
    branch.retain_revertible(
      forest,
      fork,
      transaction_commit.revision,
      types.DefaultCommit,
    )
  let assert Ok(branch.AuthorResult(forest, Some(main_commit), _, compressor)) =
    branch.author(
      forest,
      document,
      SetField(
        ["point"],
        ObjectValue("Point", [
          #("x", NumberValue(30.0)),
          #("y", NumberValue(40.0)),
        ]),
      ),
      compressor,
    )
  let assert Ok(#(
    branch.ReconcileResult(
      forest,
      [
        branch.BranchEvent(
          types.LocalCheckout(_),
          None,
          tree_kernel.ChangeEvents([tree_kernel.TreeChanged(True)], False),
        ),
      ],
      [],
    ),
    compressor,
  )) = branch.rebase_with_compressor(forest, fork, document, compressor)

  branch.local_history(forest, fork)
  |> expect.to_be_ok
  |> fn(local) { local.commits }
  |> list.map(fn(commit) { commit.revision })
  |> expect.to_equal([
    initial_commit.revision,
    main_commit.revision,
    transaction_commit.revision,
  ])
  let replacement =
    ObjectValue("Point", [
      #("x", NumberValue(30.0)),
      #("y", NumberValue(40.0)),
    ])
  branch.read(forest, fork, ["point"])
  |> expect.to_equal(Ok(Some(replacement)))
  branch.read(forest, document, ["point"])
  |> expect.to_equal(Ok(Some(replacement)))
  branch.revertible_is_valid(forest, guarded_handle) |> expect.to_be_true
  let assert Ok(#(
    branch.ReconcileResult(
      forest,
      [branch.BranchEvent(types.DocumentCheckout, Some(merged), _)],
      [published],
    ),
    compressor,
  )) = branch.merge_with_compressor(forest, document, fork, False, compressor)
  published.revision |> expect.to_equal(transaction_commit.revision)
  merged |> expect.to_equal(published)
  runtime.commit_outcome(published.change)
  |> expect.to_equal(types.NewContentOnly)
  branch.history_view(forest, document)
  |> expect.to_be_ok
  |> fn(view) { list.map(view.pending, fn(commit) { commit.revision }) }
  |> expect.to_equal([
    initial_commit.revision,
    main_commit.revision,
    transaction_commit.revision,
  ])
  transaction_commit.revision |> expect.to_not_equal(main_commit.revision)
  let assert #(_, Some(fluid_ids.CreationRange(_, Some(range)))) =
    fluid_ids.take_creation_range(compressor)
  range.first_gen_count |> expect.to_equal(1)
  range.count |> expect.to_equal(4)
}

pub fn local_branch_constraint_violation_preserves_unrelated_source_commit_test() -> Nil {
  let forest =
    branch.new(
      branch.origin("runtime", "document", "tree"),
      rich_branch_state(),
    )
  let document = branch.document(forest)
  let assert Ok(#(forest, fork)) = branch.fork(forest, document)
  let compressor = fluid_ids.new(session())
  let assert Ok(branch.AuthorResult(
    forest,
    Some(unrelated_commit),
    _,
    compressor,
  )) =
    branch.author(
      forest,
      fork,
      types.MapSet(["byKey"], "source", point("source", 8.0)),
      compressor,
    )
  let constraint =
    branch.checkout_state(forest, fork)
    |> expect.to_be_ok
    |> tree_kernel.resolve_constraint(["left", "0"])
    |> expect.to_be_ok
  let assert Ok(#(forest, open)) =
    branch.begin_transaction(forest, fork, compressor, [constraint])
  let assert Ok(open) =
    branch.transaction_apply(
      open,
      SetField(["left", "0", "x"], NumberValue(7.0)),
    )
  let compressor = branch.transaction_compressor(open)
  let assert Ok(branch.TransactionCommit(forest, guarded_commit, _, compressor)) =
    branch.finish_transaction(forest, open, compressor)
  let assert Ok(#(forest, guarded_handle)) =
    branch.retain_revertible(
      forest,
      fork,
      guarded_commit.revision,
      types.DefaultCommit,
    )
  let assert Ok(branch.AuthorResult(forest, Some(remove_commit), _, compressor)) =
    branch.author(
      forest,
      document,
      types.ArrayRemove(["left"], 0, 1),
      compressor,
    )
  let assert Ok(#(branch.ReconcileResult(forest, [_], []), compressor)) =
    branch.rebase_with_compressor(forest, fork, document, compressor)

  branch.local_history(forest, fork)
  |> expect.to_be_ok
  |> fn(local) { list.map(local.commits, fn(commit) { commit.revision }) }
  |> expect.to_equal([
    remove_commit.revision,
    unrelated_commit.revision,
    guarded_commit.revision,
  ])
  branch.read(forest, fork, ["byKey", "source"])
  |> expect.to_equal(Ok(Some(point("source", 8.0))))
  branch.read(forest, fork, ["left"])
  |> expect.to_equal(
    Ok(
      Some(
        types.ArrayValue(array_items_type, [
          point("left-b", 2.0),
        ]),
      ),
    ),
  )
  branch.revertible_is_valid(forest, guarded_handle) |> expect.to_be_true

  let assert Ok(#(
    branch.ReconcileResult(
      forest,
      [
        branch.BranchEvent(
          types.DocumentCheckout,
          Some(merged_unrelated),
          tree_kernel.ChangeEvents([tree_kernel.TreeChanged(True)], False),
        ),
        branch.BranchEvent(
          types.DocumentCheckout,
          Some(merged_guarded),
          tree_kernel.ChangeEvents([], False),
        ),
      ],
      [published_unrelated, published_guarded],
    ),
    compressor,
  )) = branch.merge_with_compressor(forest, document, fork, False, compressor)
  published_unrelated.revision |> expect.to_equal(unrelated_commit.revision)
  published_guarded.revision |> expect.to_equal(guarded_commit.revision)
  merged_unrelated |> expect.to_equal(published_unrelated)
  merged_guarded |> expect.to_equal(published_guarded)
  runtime.commit_outcome(published_guarded.change)
  |> expect.to_equal(types.NewContentOnly)
  branch.history_view(forest, document)
  |> expect.to_be_ok
  |> fn(view) { list.map(view.pending, fn(commit) { commit.revision }) }
  |> expect.to_equal([
    remove_commit.revision,
    unrelated_commit.revision,
    guarded_commit.revision,
  ])
  let assert #(_, Some(fluid_ids.CreationRange(_, Some(range)))) =
    fluid_ids.take_creation_range(compressor)
  range.first_gen_count |> expect.to_equal(1)
  range.count |> expect.to_equal(5)
}

pub fn local_branch_violated_commit_preserves_created_node_dependencies_test() -> Nil {
  let forest =
    branch.new(
      branch.origin("runtime", "document", "tree"),
      rich_branch_state(),
    )
  let document = branch.document(forest)
  let assert Ok(#(forest, fork)) = branch.fork(forest, document)
  let compressor = fluid_ids.new(session())
  let constraint =
    branch.checkout_state(forest, fork)
    |> expect.to_be_ok
    |> tree_kernel.resolve_constraint(["left", "0"])
    |> expect.to_be_ok
  let assert Ok(#(forest, open)) =
    branch.begin_transaction(forest, fork, compressor, [constraint])
  let assert Ok(open) =
    branch.transaction_apply(
      open,
      types.ArrayInsert(["right"], 1, [point("guarded", 8.0)]),
    )
  let compressor = branch.transaction_compressor(open)
  let assert Ok(branch.TransactionCommit(forest, guarded_commit, _, compressor)) =
    branch.finish_transaction(forest, open, compressor)
  let assert Ok(branch.AuthorResult(forest, Some(later_commit), _, compressor)) =
    branch.author(
      forest,
      fork,
      SetField(["right", "1", "x"], NumberValue(9.0)),
      compressor,
    )
  let assert Ok(branch.AuthorResult(forest, Some(remove_commit), _, compressor)) =
    branch.author(
      forest,
      document,
      types.ArrayRemove(["left"], 0, 1),
      compressor,
    )
  let assert Ok(#(branch.ReconcileResult(forest, [_], []), compressor)) =
    branch.rebase_with_compressor(forest, fork, document, compressor)

  let assert Ok(history.LocalBranch(_, _, commits)) =
    branch.local_history(forest, fork)
  list.map(commits, fn(commit) { commit.revision })
  |> expect.to_equal([
    remove_commit.revision,
    guarded_commit.revision,
    later_commit.revision,
  ])
  let assert Ok(rebased_guarded) =
    list.find(commits, fn(commit) { commit.revision == guarded_commit.revision })
  let assert [shared_change.DataChange(guarded_data)] =
    shared_change.to_changes(rebased_guarded.change)
  change.to_data(guarded_data).constraint_violation_count
  |> expect.to_equal(1)
  change.to_data(guarded_data).builds |> expect.to_not_equal([])
  runtime.commit_outcome(rebased_guarded.change)
  |> expect.to_equal(types.NewContentOnly)
  let assert Ok(rebased_later) =
    list.find(commits, fn(commit) { commit.revision == later_commit.revision })
  runtime.commit_outcome(rebased_later.change)
  |> expect.to_equal(types.FullyApplied)
  branch.read(forest, fork, ["right"])
  |> expect.to_equal(
    Ok(Some(types.ArrayValue(array_items_type, [point("right-a", 3.0)]))),
  )

  let assert Ok(#(branch.ReconcileResult(forest, events, published), _)) =
    branch.merge_with_compressor(forest, document, fork, False, compressor)
  list.map(published, fn(commit) { commit.revision })
  |> expect.to_equal([guarded_commit.revision, later_commit.revision])
  list.map(events, fn(event) {
    let assert Some(commit) = event.commit
    commit.revision
  })
  |> expect.to_equal([guarded_commit.revision, later_commit.revision])
  branch.history_view(forest, document)
  |> expect.to_be_ok
  |> fn(view) { list.map(view.pending, fn(commit) { commit.revision }) }
  |> expect.to_equal([
    remove_commit.revision,
    guarded_commit.revision,
    later_commit.revision,
  ])
  branch.read(forest, document, ["right"])
  |> expect.to_equal(
    Ok(Some(types.ArrayValue(array_items_type, [point("right-a", 3.0)]))),
  )
}

pub fn local_branch_undo_is_checkout_scoped_test() -> Nil {
  let forest =
    branch.new(branch.origin("runtime", "document", "tree"), branch_state())
  let document = branch.document(forest)
  let assert Ok(#(forest, fork)) = branch.fork(forest, document)
  let compressor = fluid_ids.new(session())
  let assert Ok(branch.AuthorResult(forest, Some(fork_commit), _, compressor)) =
    branch.author(
      forest,
      fork,
      SetField(["point", "x"], NumberValue(7.0)),
      compressor,
    )
  let assert Ok(#(forest, original)) =
    branch.retain_revertible(
      forest,
      fork,
      fork_commit.revision,
      types.DefaultCommit,
    )
  let assert Ok(branch.RevertResult(
    forest,
    _,
    types.UndoCommit,
    [_],
    undo,
    compressor,
  )) = branch.revert(forest, original, compressor)
  branch.read(forest, fork, ["point", "x"])
  |> expect.to_equal(Ok(Some(NumberValue(1.0))))
  branch.read(forest, document, ["point", "x"])
  |> expect.to_equal(Ok(Some(NumberValue(1.0))))

  let assert Ok(branch.RevertResult(
    forest,
    _,
    types.RedoCommit,
    [_],
    _,
    compressor,
  )) = branch.revert(forest, undo, compressor)
  branch.read(forest, fork, ["point", "x"])
  |> expect.to_equal(Ok(Some(NumberValue(7.0))))

  let assert Ok(branch.RevertResult(forest, _, types.UndoCommit, [_], _, _)) =
    branch.revert(forest, original, compressor)
  branch.read(forest, fork, ["point", "x"])
  |> expect.to_equal(Ok(Some(NumberValue(1.0))))
}

pub fn local_branch_source_revertible_survives_merged_ack_and_rebase_test() -> Nil {
  let forest =
    branch.new(branch.origin("runtime", "document", "tree"), branch_state())
  let document = branch.document(forest)
  let assert Ok(#(forest, source)) = branch.fork(forest, document)
  let compressor = fluid_ids.new(session())
  let assert Ok(branch.AuthorResult(forest, Some(source_commit), _, compressor)) =
    branch.author(
      forest,
      source,
      SetField(["point", "x"], NumberValue(7.0)),
      compressor,
    )
  let assert Ok(#(forest, source_handle)) =
    branch.retain_revertible(
      forest,
      source,
      source_commit.revision,
      types.DefaultCommit,
    )
  let assert Ok(#(branch.ReconcileResult(forest, _, [merged]), compressor)) =
    branch.merge_with_compressor(forest, document, source, False, compressor)
  let assert Ok(#(forest, Nil)) =
    branch.update_document(forest, fn(authoritative) {
      use #(acked, _, Nil) <- result.try(tree_kernel.receive(
        authoritative,
        merged,
        types.SequencePoint(1, 0),
        0,
        0,
        Nil,
        no_mint,
      ))
      Ok(#(acked, Nil))
    })
  let assert Ok(#(branch.ReconcileResult(forest, _, []), compressor)) =
    branch.rebase_with_compressor(forest, source, document, compressor)
  let assert Ok(history.LocalBranch(_, Some(base), [])) =
    branch.local_history(forest, source)
  base |> expect.to_equal(source_commit.revision)
  branch.revertible_is_valid(forest, source_handle) |> expect.to_be_true

  let assert Ok(branch.RevertResult(
    forest,
    _,
    types.UndoCommit,
    [_],
    undo,
    compressor,
  )) = branch.revert(forest, source_handle, compressor)
  branch.read(forest, source, ["point", "x"])
  |> expect.to_equal(Ok(Some(NumberValue(1.0))))
  branch.read(forest, document, ["point", "x"])
  |> expect.to_equal(Ok(Some(NumberValue(7.0))))
  branch.history_view(forest, document)
  |> expect.to_be_ok
  |> fn(view) { view.pending }
  |> expect.to_equal([])

  let assert Ok(branch.RevertResult(forest, _, types.RedoCommit, [_], _, _)) =
    branch.revert(forest, undo, compressor)
  branch.read(forest, source, ["point", "x"])
  |> expect.to_equal(Ok(Some(NumberValue(7.0))))
  branch.read(forest, document, ["point", "x"])
  |> expect.to_equal(Ok(Some(NumberValue(7.0))))
  branch.history_view(forest, document)
  |> expect.to_be_ok
  |> fn(view) { view.pending }
  |> expect.to_equal([])
}

pub fn local_branch_disposal_invalidates_only_its_revertibles_test() -> Nil {
  let forest =
    branch.new(branch.origin("runtime", "document", "tree"), branch_state())
  let document = branch.document(forest)
  let assert Ok(#(forest, fork)) = branch.fork(forest, document)
  let compressor = fluid_ids.new(session())
  let assert Ok(branch.AuthorResult(forest, Some(fork_commit), _, compressor)) =
    branch.author(
      forest,
      fork,
      SetField(["point", "x"], NumberValue(7.0)),
      compressor,
    )
  let assert Ok(#(forest, fork_handle)) =
    branch.retain_revertible(
      forest,
      fork,
      fork_commit.revision,
      types.DefaultCommit,
    )
  let assert Ok(#(branch.ReconcileResult(forest, _, [merged]), compressor)) =
    branch.merge_with_compressor(forest, document, fork, False, compressor)
  merged.revision |> expect.to_equal(fork_commit.revision)
  let assert Ok(#(forest, target_handle)) =
    branch.retain_revertible(
      forest,
      document,
      merged.revision,
      types.DefaultCommit,
    )
  let _ =
    branch.retain_revertible(
      forest,
      fork,
      fork_commit.revision,
      types.DefaultCommit,
    )
    |> expect.to_be_error
  let forest = branch.dispose(forest, fork) |> expect.to_be_ok

  branch.revertible_is_valid(forest, target_handle) |> expect.to_be_true
  branch.revertible_is_valid(forest, fork_handle) |> expect.to_be_false
  let _ = branch.revert(forest, fork_handle, compressor) |> expect.to_be_error
  Nil
}

const tree_schema = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.number\":{\"kind\":{\"leaf\":0}},\"Point\":{\"kind\":{\"object\":{\"x\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.number\"]},\"y\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.number\"]}}}},\"Root\":{\"kind\":{\"object\":{\"point\":{\"kind\":\"Value\",\"types\":[\"Point\"]}}}}},\"root\":{\"kind\":\"Value\",\"types\":[\"Root\"]}}"

fn branch_state() -> tree_kernel.TreeState {
  let assert Ok(stored) = schema.stored_from_string(tree_schema)
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
  let view_id = revision("98")
  let assert Ok(initial) = forest.new(view_id, stored, Some(root))
  let assert Ok(data) = forest.export_data(initial)
  let assert Ok(snapshot) =
    tree_kernel.snapshot_from_parts(
      view_id,
      stored,
      data,
      history.HistorySnapshot(history.InitialBase, [], [], 0, 0, []),
    )
  let assert Ok(view) = schema.view_from_json(schema.stored_to_json(stored))
  let assert Ok(state) = tree_kernel.restore(snapshot, view_id, session(), view)
  state
}

const array_items_type = "org.watershed.shared-tree.m3.Items"

const array_point_type = "org.watershed.shared-tree.m3.Point"

fn point(label: String, x: Float) -> types.TreeValue {
  ObjectValue(array_point_type, [
    #("label", types.StringValue(label)),
    #("x", NumberValue(x)),
  ])
}

fn rich_root(
  left: List(types.TreeValue),
  right: List(types.TreeValue),
  by_key: List(#(String, types.TreeValue)),
) -> types.TreeValue {
  ObjectValue("org.watershed.shared-tree.m3.Root", [
    #("left", types.ArrayValue(array_items_type, left)),
    #("right", types.ArrayValue(array_items_type, right)),
    #("byKey", types.MapValue("org.watershed.shared-tree.m3.ArrayMap", by_key)),
    #("narrow", types.ArrayValue("org.watershed.shared-tree.m3.Points", [])),
  ])
}

fn initial_left() -> List(types.TreeValue) {
  [point("left-a", 1.0), point("left-b", 2.0)]
}

fn initial_right() -> List(types.TreeValue) {
  [point("right-a", 3.0)]
}

fn initial_map() -> List(#(String, types.TreeValue)) {
  [
    #("0", types.ArrayValue(array_items_type, [types.StringValue("existing")])),
  ]
}

fn rich_branch_state() -> tree_kernel.TreeState {
  let root = rich_root(initial_left(), initial_right(), initial_map())
  let stored = array_fixture.stored("objectArrays")
  let view_id = array_fixture.view_id()
  let assert Ok(snapshot) =
    tree_kernel.snapshot_from_parts(
      view_id,
      stored,
      forest.ForestData(Some(root), [], 0),
      history.HistorySnapshot(history.InitialBase, [], [], 0, 0, []),
    )
  let assert Ok(state) =
    tree_kernel.restore(
      snapshot,
      view_id,
      session(),
      array_fixture.view("objectArrays"),
    )
  state
}

pub fn local_branch_fork_isolates_kernel_state_test() -> Nil {
  let main = branch_state()
  let origin = branch.origin("runtime", "document", "tree")
  let forest = branch.new(origin, main)
  let document = branch.document(forest)
  let main_reference =
    branch.reference_at(forest, document, ["point"]) |> expect.to_be_ok
  let main_data = branch.visible_data(forest, document) |> expect.to_be_ok
  let main_history = branch.history_view(forest, document) |> expect.to_be_ok
  let assert Ok(#(forest, fork)) = branch.fork(forest, document)
  let fork_reference =
    branch.reference_at(forest, fork, ["point"]) |> expect.to_be_ok
  let fork_before = branch.visible_data(forest, fork) |> expect.to_be_ok

  let assert Ok(#(edited, _, events)) =
    branch.apply(
      forest,
      fork,
      revision("0f"),
      change.identity_order([#(revision("0f"), -1)]) |> expect.to_be_ok,
      SetField(["point", "x"], NumberValue(7.0)),
    )

  branch.read(edited, document, ["point", "x"])
  |> expect.to_equal(Ok(Some(NumberValue(1.0))))
  branch.read(edited, fork, ["point", "x"])
  |> expect.to_equal(Ok(Some(NumberValue(7.0))))
  branch.visible_data(edited, document) |> expect.to_equal(Ok(main_data))
  branch.history_view(edited, document)
  |> expect.to_equal(Ok(main_history))
  main_reference |> expect.to_equal(fork_reference)
  main_data.detached |> expect.to_equal(fork_before.detached)
  events
  |> expect.to_equal(tree_kernel.ChangeEvents(
    [tree_kernel.TreeChanged(True)],
    False,
  ))
}

fn branch_order() -> change.IdentityOrder {
  change.identity_order([
    #(revision("1a"), -4),
    #(revision("1b"), -3),
    #(revision("1c"), -2),
    #(revision("1d"), -1),
  ])
  |> expect.to_be_ok
}

pub fn local_branch_rebase_changes_source_and_preserves_target_test() -> Nil {
  let forest =
    branch.new(branch.origin("runtime", "document", "tree"), branch_state())
  let document = branch.document(forest)
  let assert Ok(#(forest, source)) = branch.fork(forest, document)
  let assert Ok(#(forest, target)) = branch.fork(forest, document)
  let assert Ok(#(forest, _, _)) =
    branch.apply(
      forest,
      source,
      revision("1a"),
      branch_order(),
      SetField(["point", "x"], NumberValue(7.0)),
    )
  let assert Ok(#(forest, _, _)) =
    branch.apply(
      forest,
      target,
      revision("1b"),
      branch_order(),
      SetField(["point", "y"], NumberValue(9.0)),
    )
  let assert Ok(#(branch.ReconcileResult(forest, events, commits), _)) =
    branch.rebase(
      forest,
      source,
      target,
      Allocation([revision("1c")], branch_order()),
      mint,
    )

  branch.read(forest, source, ["point", "x"])
  |> expect.to_equal(Ok(Some(NumberValue(7.0))))
  branch.read(forest, source, ["point", "y"])
  |> expect.to_equal(Ok(Some(NumberValue(9.0))))
  branch.read(forest, target, ["point", "x"])
  |> expect.to_equal(Ok(Some(NumberValue(1.0))))
  branch.read(forest, target, ["point", "y"])
  |> expect.to_equal(Ok(Some(NumberValue(9.0))))
  commits |> expect.to_equal([])
  list.length(events) |> expect.to_equal(1)
}

pub fn local_branch_document_update_preserves_authoritative_history_test() -> Nil {
  let main = branch_state()
  let forest = branch.new(branch.origin("runtime", "document", "tree"), main)
  let document = branch.document(forest)
  let assert Ok(#(forest, fork)) = branch.fork(forest, document)
  let assert Ok(#(forest, main_commit)) =
    branch.update_document(forest, fn(authoritative) {
      use #(updated, commit, _) <- result.try(tree_kernel.apply_local(
        authoritative,
        revision("1b"),
        branch_order(),
        SetField(["point", "y"], NumberValue(9.0)),
      ))
      Ok(#(updated, commit))
    })

  branch.history_view(forest, document)
  |> expect.to_be_ok
  |> fn(view) { view.pending }
  |> expect.to_equal([main_commit])
  let assert Ok(#(branch.ReconcileResult(forest, _, _), _)) =
    branch.rebase(
      forest,
      fork,
      document,
      Allocation([revision("1c")], branch_order()),
      mint,
    )
  branch.read(forest, fork, ["point", "y"])
  |> expect.to_equal(Ok(Some(NumberValue(9.0))))
}

pub fn local_branch_document_update_preserves_remote_progress_test() -> Nil {
  let forest =
    branch.new(branch.origin("runtime", "document", "tree"), branch_state())
  let document = branch.document(forest)
  let assert Ok(#(forest, fork)) = branch.fork(forest, document)
  let remote =
    edit_field_commit_with_order(
      revision("1b"),
      peer_session(),
      "y",
      9.0,
      branch_order(),
    )
  let assert Ok(#(forest, Nil)) =
    branch.update_document(forest, fn(authoritative) {
      use #(received, _, Nil) <- result.try(tree_kernel.receive(
        authoritative,
        remote,
        types.SequencePoint(1, 0),
        0,
        0,
        Nil,
        no_mint,
      ))
      Ok(#(received, Nil))
    })
  let assert Ok(#(branch.ReconcileResult(forest, _, _), _)) =
    branch.rebase(
      forest,
      fork,
      document,
      Allocation([revision("1c")], branch_order()),
      mint,
    )
  branch.read(forest, fork, ["point", "y"])
  |> expect.to_equal(Ok(Some(NumberValue(9.0))))
  branch.history_view(forest, document)
  |> expect.to_be_ok
  |> fn(view) { view.sequenced.sequence_number }
  |> expect.to_equal(1)
}

pub fn local_branch_document_update_preserves_ack_progress_test() -> Nil {
  let forest =
    branch.new(branch.origin("runtime", "document", "tree"), branch_state())
  let document = branch.document(forest)
  let assert Ok(#(forest, fork)) = branch.fork(forest, document)
  let assert Ok(#(forest, commit)) =
    branch.update_document(forest, fn(authoritative) {
      use #(edited, commit, _) <- result.try(tree_kernel.apply_local(
        authoritative,
        revision("1b"),
        branch_order(),
        SetField(["point", "y"], NumberValue(9.0)),
      ))
      Ok(#(edited, commit))
    })
  let assert Ok(#(forest, Nil)) =
    branch.update_document(forest, fn(authoritative) {
      use #(acked, _, Nil) <- result.try(tree_kernel.receive(
        authoritative,
        commit,
        types.SequencePoint(1, 0),
        0,
        0,
        Nil,
        no_mint,
      ))
      Ok(#(acked, Nil))
    })
  let assert Ok(#(branch.ReconcileResult(forest, _, _), _)) =
    branch.rebase(
      forest,
      fork,
      document,
      Allocation([revision("1c")], branch_order()),
      mint,
    )
  branch.read(forest, fork, ["point", "y"])
  |> expect.to_equal(Ok(Some(NumberValue(9.0))))
  branch.history_view(forest, document)
  |> expect.to_be_ok
  |> fn(view) { view.pending }
  |> expect.to_equal([])
}

pub fn local_branch_merge_into_document_preserves_boundaries_test() -> Nil {
  let forest =
    branch.new(branch.origin("runtime", "document", "tree"), branch_state())
  let document = branch.document(forest)
  let assert Ok(#(forest, source)) = branch.fork(forest, document)
  let assert Ok(#(forest, first, _)) =
    branch.apply(
      forest,
      source,
      revision("1a"),
      branch_order(),
      SetField(["point", "x"], NumberValue(7.0)),
    )
  let assert Ok(#(forest, second, _)) =
    branch.apply(
      forest,
      source,
      revision("1b"),
      branch_order(),
      SetField(["point", "y"], NumberValue(9.0)),
    )
  let assert Ok(#(branch.ReconcileResult(forest, events, commits), _)) =
    branch.merge(
      forest,
      document,
      source,
      False,
      Allocation([revision("1c"), revision("1d")], branch_order()),
      mint,
    )

  branch.read(forest, document, ["point", "x"])
  |> expect.to_equal(Ok(Some(NumberValue(7.0))))
  branch.read(forest, document, ["point", "y"])
  |> expect.to_equal(Ok(Some(NumberValue(9.0))))
  commits |> expect.to_equal([first, second])
  let assert [
    branch.BranchEvent(
      types.DocumentCheckout,
      Some(first_event),
      tree_kernel.ChangeEvents([tree_kernel.TreeChanged(True)], False),
    ),
    branch.BranchEvent(
      types.DocumentCheckout,
      Some(second_event),
      tree_kernel.ChangeEvents([tree_kernel.TreeChanged(True)], False),
    ),
  ] = events
  first_event |> expect.to_equal(first)
  second_event |> expect.to_equal(second)
  branch.history_view(forest, document)
  |> expect.to_be_ok
  |> fn(view) { view.pending }
  |> expect.to_equal([first, second])
}

pub fn local_branch_document_merge_preserves_authoring_schema_through_ack_test() -> Nil {
  let forest =
    branch.new(branch.origin("runtime", "document", "tree"), branch_state())
  let document = branch.document(forest)
  let assert Ok(#(forest, source)) = branch.fork(forest, document)
  let assert Ok(#(forest, commit, _)) =
    branch.apply(
      forest,
      source,
      revision("1a"),
      branch_order(),
      SetField(["point", "x"], NumberValue(7.0)),
    )
  let assert Ok(#(branch.ReconcileResult(forest, _, [merged]), _)) =
    branch.merge(
      forest,
      document,
      source,
      False,
      Allocation([], branch_order()),
      mint,
    )
  merged.revision |> expect.to_equal(commit.revision)
  let assert Ok(#(forest, authored_schema)) =
    branch.update_document(forest, fn(authoritative) {
      use authored <- result.try(tree_kernel.authoring_schema(
        authoritative,
        session(),
        0,
        merged.revision,
      ))
      Ok(#(authoritative, authored))
    })
  authored_schema
  |> expect.to_equal(
    schema.FixedSchema(tree_kernel.stored_schema(branch_state())),
  )

  let assert Ok(#(forest, Nil)) =
    branch.update_document(forest, fn(authoritative) {
      use #(acked, _, Nil) <- result.try(tree_kernel.receive(
        authoritative,
        merged,
        types.SequencePoint(1, 0),
        0,
        0,
        Nil,
        no_mint,
      ))
      Ok(#(acked, Nil))
    })
  branch.history_view(forest, document)
  |> expect.to_be_ok
  |> fn(view) { view.pending }
  |> expect.to_equal([])
  branch.read(forest, document, ["point", "x"])
  |> expect.to_equal(Ok(Some(NumberValue(7.0))))
}

pub fn local_branch_document_revert_records_authoring_schema_through_ack_test() -> Nil {
  let forest =
    branch.new(branch.origin("runtime", "document", "tree"), branch_state())
  let document = branch.document(forest)
  let assert Ok(#(forest, source)) = branch.fork(forest, document)
  let compressor = fluid_ids.new(session())
  let assert Ok(branch.AuthorResult(forest, Some(source_commit), _, compressor)) =
    branch.author(
      forest,
      source,
      SetField(["point", "x"], NumberValue(7.0)),
      compressor,
    )
  let assert Ok(#(branch.ReconcileResult(forest, _, [merged]), compressor)) =
    branch.merge_with_compressor(forest, document, source, False, compressor)
  merged.revision |> expect.to_equal(source_commit.revision)
  let assert Ok(#(forest, target_handle)) =
    branch.retain_revertible(
      forest,
      document,
      merged.revision,
      types.DefaultCommit,
    )
  let assert Ok(#(forest, Nil)) =
    branch.update_document(forest, fn(authoritative) {
      use #(acked, _, Nil) <- result.try(tree_kernel.receive(
        authoritative,
        merged,
        types.SequencePoint(1, 0),
        0,
        0,
        Nil,
        no_mint,
      ))
      Ok(#(acked, Nil))
    })

  let assert Ok(branch.RevertResult(
    forest,
    inverse,
    types.UndoCommit,
    [_],
    _,
    _,
  )) = branch.revert(forest, target_handle, compressor)
  branch.read(forest, document, ["point", "x"])
  |> expect.to_equal(Ok(Some(NumberValue(1.0))))
  let assert Ok(#(forest, authored_schema)) =
    branch.update_document(forest, fn(authoritative) {
      use authored <- result.try(tree_kernel.authoring_schema(
        authoritative,
        session(),
        1,
        inverse.revision,
      ))
      Ok(#(authoritative, authored))
    })
  authored_schema
  |> expect.to_equal(
    schema.FixedSchema(tree_kernel.stored_schema(branch_state())),
  )
  let assert Ok(#(forest, Nil)) =
    branch.update_document(forest, fn(authoritative) {
      use #(acked, _, Nil) <- result.try(tree_kernel.receive(
        authoritative,
        inverse,
        types.SequencePoint(2, 0),
        1,
        0,
        Nil,
        no_mint,
      ))
      Ok(#(acked, Nil))
    })
  branch.history_view(forest, document)
  |> expect.to_be_ok
  |> fn(view) { view.pending }
  |> expect.to_equal([])
  branch.read(forest, document, ["point", "x"])
  |> expect.to_equal(Ok(Some(NumberValue(1.0))))
}

pub fn local_branch_object_replacement_rebases_exact_state_test() -> Nil {
  list.each([False, True], fn(target_first) {
    let forest =
      branch.new(branch.origin("runtime", "document", "tree"), branch_state())
    let document = branch.document(forest)
    let assert Ok(#(forest, source)) = branch.fork(forest, document)
    let assert Ok(#(forest, target)) = branch.fork(forest, document)
    let original_reference =
      branch.reference_at(forest, source, ["point"]) |> expect.to_be_ok
    let replacement =
      ObjectValue("Point", [
        #("x", NumberValue(7.0)),
        #("y", NumberValue(8.0)),
      ])
    let apply_source = fn(forest) {
      let assert Ok(#(forest, _, _)) =
        branch.apply(
          forest,
          source,
          revision("1a"),
          branch_order(),
          SetField(["point"], replacement),
        )
      forest
    }
    let apply_target = fn(forest) {
      let assert Ok(#(forest, _, _)) =
        branch.apply(
          forest,
          target,
          revision("1b"),
          branch_order(),
          SetField(["point", "x"], NumberValue(9.0)),
        )
      forest
    }
    let forest = case target_first {
      True -> apply_source(apply_target(forest))
      False -> apply_target(apply_source(forest))
    }
    let assert Ok(#(branch.ReconcileResult(forest, _, _), _)) =
      branch.rebase(
        forest,
        source,
        target,
        Allocation([revision("1c")], branch_order()),
        mint,
      )

    branch.read(forest, source, ["point"])
    |> expect.to_equal(
      Ok(
        Some(
          ObjectValue("Point", [
            #("x", NumberValue(7.0)),
            #("y", NumberValue(8.0)),
          ]),
        ),
      ),
    )
    branch.reference_at(forest, source, ["point"])
    |> expect.to_not_equal(Ok(original_reference))
    let assert Ok(history.LocalBranch(_, _, commits)) =
      branch.local_history(forest, source)
    list.map(commits, fn(commit) { commit.revision })
    |> expect.to_equal([revision("1b"), revision("1a")])
  })
}

pub fn local_branch_forest_lifecycle_matches_pinned_contract_test() -> Nil {
  let forest =
    branch.new(branch.origin("runtime", "document", "tree"), branch_state())
  let document = branch.document(forest)
  let assert Ok(#(forest, parent)) = branch.fork(forest, document)
  let assert Ok(#(forest, child)) = branch.fork(forest, parent)
  let assert Ok(forest) = branch.dispose(forest, parent)
  branch.read(forest, child, ["point", "x"])
  |> expect.to_equal(Ok(Some(NumberValue(1.0))))
  branch.dispose(forest, parent) |> expect.to_equal(Ok(forest))
  branch.dispose(forest, document) |> expect.to_be_error

  let assert Ok(#(forest, empty)) = branch.fork(forest, document)
  let assert Ok(#(branch.ReconcileResult(forest, events, commits), _)) =
    branch.merge(
      forest,
      document,
      empty,
      True,
      Allocation([], branch_order()),
      mint,
    )
  events |> expect.to_equal([])
  commits |> expect.to_equal([])
  let _ = branch.read(forest, empty, ["point", "x"]) |> expect.to_be_error
  Nil
}

pub fn local_branch_reconciliation_guards_are_atomic_test() -> Nil {
  let forest =
    branch.new(branch.origin("runtime", "document", "tree"), branch_state())
  let document = branch.document(forest)
  let assert Ok(#(forest, source)) = branch.fork(forest, document)
  let before = branch.visible_data(forest, source)
  let unrelated =
    branch.document(branch.new(
      branch.origin("other", "document", "tree"),
      branch_state(),
    ))

  branch.rebase(forest, source, unrelated, Allocation([], branch_order()), mint)
  |> expect.to_be_error
  branch.visible_data(forest, source) |> expect.to_equal(before)

  let active =
    branch.set_transaction_active(forest, source, True) |> expect.to_be_ok
  branch.rebase(active, source, document, Allocation([], branch_order()), mint)
  |> expect.to_be_error
  branch.visible_data(active, source) |> expect.to_equal(before)

  let disposed = branch.dispose(forest, source) |> expect.to_be_ok
  branch.merge(
    disposed,
    document,
    source,
    False,
    Allocation([], branch_order()),
    mint,
  )
  |> expect.to_be_error
  let changed_schema =
    branch.update_document(forest, fn(authoritative) {
      Ok(#(
        tree_kernel.with_branch_history(
          rich_branch_state(),
          tree_kernel.branch_history(authoritative),
        ),
        Nil,
      ))
    })
    |> expect.to_be_ok
    |> fn(value) { value.0 }
  branch.rebase(
    changed_schema,
    source,
    document,
    Allocation([], branch_order()),
    mint,
  )
  |> expect.to_be_error
  branch.visible_data(changed_schema, source) |> expect.to_equal(before)
  let _ =
    branch.rebase(
      forest,
      document,
      source,
      Allocation([], branch_order()),
      mint,
    )
    |> expect.to_be_error
  Nil
}

type FieldCase {
  FieldCase(
    name: String,
    source: types.Edit,
    target: types.Edit,
    expected: types.TreeValue,
    identity_before: types.FieldPath,
    identity_after: types.FieldPath,
    array_changed: Bool,
  )
}

fn event_matches_field_case(
  event: branch.BranchEvent,
  target: types.LocalCheckoutId,
  array_changed: Bool,
) -> Bool {
  case event {
    branch.BranchEvent(
      types.LocalCheckout(event_target),
      Some(history.Commit(event_revision, event_originator, event_change)),
      tree_kernel.ChangeEvents([tree_kernel.TreeChanged(True)], event_array),
    ) -> {
      let projection = case shared_change.to_changes(event_change) {
        [shared_change.DataChange(changeset)] -> {
          let data = change.to_data(changeset)
          data.revisions == [change.RevisionInfo(revision("1a"), None)]
          && data.constraint_violation_count == 0
          && data.fields != []
        }
        _ -> False
      }
      event_target == target
      && event_revision == revision("1a")
      && event_originator == session()
      && event_array == array_changed
      && shared_change.identity_revisions(event_change)
      == [
        revision("1a"),
        revision("1b"),
        revision("1c"),
        revision("1d"),
      ]
      && projection
    }
    _ -> False
  }
}

fn reconcile_field_case(scenario: FieldCase, target_first: Bool) -> Nil {
  let forest =
    branch.new(
      branch.origin("runtime", "document", "tree"),
      rich_branch_state(),
    )
  let document = branch.document(forest)
  let assert Ok(#(forest, source)) = branch.fork(forest, document)
  let assert Ok(#(forest, target)) = branch.fork(forest, document)
  let source_identity =
    branch.reference_at(forest, source, scenario.identity_before)
    |> expect.to_be_ok
  let apply_source = fn(forest) {
    let #(forest, _, _) =
      branch.apply(
        forest,
        source,
        revision("1a"),
        branch_order(),
        scenario.source,
      )
      |> expect.to_be_ok
    forest
  }
  let apply_target = fn(forest) {
    let #(forest, _, _) =
      branch.apply(
        forest,
        target,
        revision("1b"),
        branch_order(),
        scenario.target,
      )
      |> expect.to_be_ok
    forest
  }
  let forest = case target_first {
    True -> apply_source(apply_target(forest))
    False -> apply_target(apply_source(forest))
  }
  let target_before = branch.visible_data(forest, target) |> expect.to_be_ok
  let target_root = branch.reference_at(forest, target, []) |> expect.to_be_ok
  let assert Ok(history.LocalBranch(target_id, _, _)) =
    branch.local_history(forest, target)
  let #(branch.ReconcileResult(rebased, _, _), _) =
    branch.rebase(
      forest,
      source,
      target,
      Allocation([revision("1c")], branch_order()),
      mint,
    )
    |> expect.to_be_ok
  branch.visible_data(rebased, target)
  |> expect.to_equal(Ok(target_before))
  branch.reference_at(rebased, target, [])
  |> expect.to_equal(Ok(target_root))

  let #(branch.ReconcileResult(merged, events, commits), _) =
    branch.merge(
      forest,
      target,
      source,
      False,
      Allocation([revision("1c")], branch_order()),
      mint,
    )
    |> expect.to_be_ok
  let assert Ok(rebased_data) = branch.visible_data(rebased, source)
  let assert Ok(merged_data) = branch.visible_data(merged, target)
  rebased_data.root |> expect.to_equal(Some(scenario.expected))
  merged_data.root |> expect.to_equal(Some(scenario.expected))
  rebased_data.root |> expect.to_equal(merged_data.root)
  branch.reference_at(rebased, source, scenario.identity_after)
  |> expect.to_equal(Ok(source_identity))
  branch.reference_at(merged, target, scenario.identity_after)
  |> expect.to_equal(Ok(source_identity))
  let assert Ok(history.LocalBranch(_, _, rebased_commits)) =
    branch.local_history(rebased, source)
  let assert Ok(rebased_source) = list.last(rebased_commits)
  let assert [merged_source] = commits
  rebased_source |> expect.to_equal(merged_source)
  list.map(commits, fn(commit) { commit.revision })
  |> expect.to_equal([revision("1a")])
  let assert [event] = events
  event_matches_field_case(event, target_id, scenario.array_changed)
  |> expect.to_equal(True)
  let assert branch.BranchEvent(_, Some(event_commit), _) = event
  event_commit |> expect.to_equal(merged_source)
}

pub fn local_branch_field_reconciliation_matrix_test() -> Nil {
  let left_a = point("left-a", 1.0)
  let left_b = point("left-b", 2.0)
  let right_a = point("right-a", 3.0)
  let existing = initial_map()
  let source_map =
    types.ArrayValue(array_items_type, [types.StringValue("source")])
  let target_map =
    types.ArrayValue(array_items_type, [types.StringValue("target")])
  let cases = [
    FieldCase(
      "object-unrelated",
      SetField(["left", "0", "x"], NumberValue(7.0)),
      SetField(["left", "0", "label"], types.StringValue("target")),
      rich_root([point("target", 7.0), left_b], [right_a], existing),
      ["left", "0"],
      ["left", "0"],
      False,
    ),
    FieldCase(
      "object-overlap",
      SetField(["left", "0", "x"], NumberValue(7.0)),
      SetField(["left", "0", "x"], NumberValue(9.0)),
      rich_root([point("left-a", 7.0), left_b], [right_a], existing),
      ["left", "0"],
      ["left", "0"],
      False,
    ),
    FieldCase(
      "map-unrelated",
      types.MapSet(["byKey"], "source", source_map),
      types.MapSet(["byKey"], "target", target_map),
      rich_root(
        [left_a, left_b],
        [right_a],
        list.append(existing, [
          #("source", source_map),
          #("target", target_map),
        ]),
      ),
      ["left", "0"],
      ["left", "0"],
      False,
    ),
    FieldCase(
      "map-overlap",
      types.MapDelete(["byKey"], "0"),
      types.MapSet(["byKey"], "0", target_map),
      rich_root([left_a, left_b], [right_a], []),
      ["left", "0"],
      ["left", "0"],
      False,
    ),
    FieldCase(
      "array-insert-unrelated",
      types.ArrayInsert(["left"], 1, [types.StringValue("source")]),
      types.ArrayInsert(["right"], 1, [types.StringValue("target")]),
      rich_root(
        [left_a, types.StringValue("source"), left_b],
        [right_a, types.StringValue("target")],
        existing,
      ),
      ["left", "1"],
      ["left", "2"],
      True,
    ),
    FieldCase(
      "array-insert-overlap",
      types.ArrayInsert(["left"], 1, [types.StringValue("source")]),
      types.ArrayInsert(["left"], 1, [types.StringValue("target")]),
      rich_root(
        [
          left_a,
          types.StringValue("source"),
          types.StringValue("target"),
          left_b,
        ],
        [right_a],
        existing,
      ),
      ["left", "1"],
      ["left", "3"],
      True,
    ),
    FieldCase(
      "array-remove-overlap",
      types.ArrayRemove(["left"], 0, 1),
      SetField(["left", "0", "x"], NumberValue(9.0)),
      rich_root([left_b], [right_a], existing),
      ["left", "1"],
      ["left", "0"],
      True,
    ),
    FieldCase(
      "same-array-move-overlap",
      types.ArrayMove(["left"], 0, 1, ["left"], 2),
      types.ArrayMove(["left"], 1, 2, ["left"], 0),
      rich_root([left_b, left_a], [right_a], existing),
      ["left", "0"],
      ["left", "1"],
      True,
    ),
    FieldCase(
      "same-array-move-unrelated",
      types.ArrayMove(["left"], 0, 1, ["left"], 2),
      types.MapSet(["byKey"], "target", target_map),
      rich_root(
        [left_b, left_a],
        [right_a],
        list.append(existing, [#("target", target_map)]),
      ),
      ["left", "0"],
      ["left", "1"],
      True,
    ),
    FieldCase(
      "cross-array-move-overlap",
      types.ArrayMove(["left"], 0, 1, ["right"], 1),
      SetField(["left", "0", "x"], NumberValue(9.0)),
      rich_root([left_b], [right_a, point("left-a", 9.0)], existing),
      ["left", "0"],
      ["right", "1"],
      True,
    ),
    FieldCase(
      "cross-array-move-unrelated",
      types.ArrayMove(["left"], 0, 1, ["right"], 1),
      types.MapSet(["byKey"], "target", target_map),
      rich_root(
        [left_b],
        [right_a, left_a],
        list.append(existing, [#("target", target_map)]),
      ),
      ["left", "0"],
      ["right", "1"],
      True,
    ),
  ]
  list.each(cases, fn(scenario) {
    reconcile_field_case(scenario, False)
    reconcile_field_case(scenario, True)
  })
}

pub fn local_branch_event_projection_rejects_mutations_test() -> Nil {
  let forest =
    branch.new(
      branch.origin("runtime", "document", "tree"),
      rich_branch_state(),
    )
  let document = branch.document(forest)
  let assert Ok(#(forest, source)) = branch.fork(forest, document)
  let assert Ok(#(forest, target)) = branch.fork(forest, document)
  let assert Ok(#(forest, _, _)) =
    branch.apply(
      forest,
      source,
      revision("1a"),
      branch_order(),
      types.ArrayInsert(["left"], 1, [types.StringValue("source")]),
    )
  let assert Ok(#(forest, _, _)) =
    branch.apply(
      forest,
      target,
      revision("1b"),
      branch_order(),
      types.MapSet(
        ["byKey"],
        "target",
        types.ArrayValue(array_items_type, [types.StringValue("target")]),
      ),
    )
  let assert Ok(history.LocalBranch(target_id, _, _)) =
    branch.local_history(forest, target)
  let assert Ok(#(branch.ReconcileResult(_, [event], [_]), _)) =
    branch.merge(
      forest,
      target,
      source,
      False,
      Allocation([revision("1c")], branch_order()),
      mint,
    )
  event_matches_field_case(event, target_id, True) |> expect.to_equal(True)
  let assert branch.BranchEvent(_, Some(commit), changes) = event
  branch.BranchEvent(types.DocumentCheckout, Some(commit), changes)
  |> event_matches_field_case(target_id, True)
  |> expect.to_equal(False)
  branch.BranchEvent(
    types.LocalCheckout(target_id),
    Some(commit),
    tree_kernel.ChangeEvents([tree_kernel.TreeChanged(True)], False),
  )
  |> event_matches_field_case(target_id, True)
  |> expect.to_equal(False)

  let assert [shared_change.DataChange(changeset)] =
    shared_change.to_changes(commit.change)
  let data = change.to_data(changeset)
  let mutated_data =
    change.ChangeData(..data, revisions: [
      change.RevisionInfo(revision("1a"), Some(revision("1b"))),
    ])
  let mutated_change =
    change.from_data(mutated_data, branch_order())
    |> expect.to_be_ok
    |> shared_change.from_data
  branch.BranchEvent(
    types.LocalCheckout(target_id),
    Some(history.Commit(..commit, change: mutated_change)),
    changes,
  )
  |> event_matches_field_case(target_id, True)
  |> expect.to_equal(False)
}

type Allocation {
  Allocation(revisions: List(fluid_ids.StableId), order: change.IdentityOrder)
}

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

fn revision(suffix: String) -> fluid_ids.StableId {
  let assert Ok(id) =
    fluid_ids.stable_id("00000000-0000-4000-8000-0000000000" <> suffix)
  id
}

fn empty_commit(suffix: String) -> history.Commit {
  let revision = revision(suffix)
  let assert Ok(order) = change.identity_order([#(revision, -1)])
  empty_commit_with_order(revision, order)
}

fn empty_commit_with_order(
  revision: fluid_ids.StableId,
  order: change.IdentityOrder,
) -> history.Commit {
  let assert Ok(change) =
    change.from_data(change.to_data(change.empty()), order)
  history.Commit(revision, session(), shared_change.from_data(change))
}

fn repair_commit(suffix: String) -> history.Commit {
  edit_commit(suffix, session(), 7.0)
}

fn edit_commit(
  suffix: String,
  originator: fluid_ids.SessionId,
  value: Float,
) -> history.Commit {
  let commit_revision = revision(suffix)
  let assert Ok(order) = change.identity_order([#(commit_revision, -1)])
  edit_commit_with_order(commit_revision, originator, value, order)
}

fn edit_commit_with_order(
  commit_revision: fluid_ids.StableId,
  originator: fluid_ids.SessionId,
  value: Float,
  order: change.IdentityOrder,
) -> history.Commit {
  edit_field_commit_with_order(commit_revision, originator, "x", value, order)
}

fn edit_field_commit_with_order(
  commit_revision: fluid_ids.StableId,
  originator: fluid_ids.SessionId,
  field: String,
  value: Float,
  order: change.IdentityOrder,
) -> history.Commit {
  let assert Ok(stored) = schema.stored_from_string(tree_schema)
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
  let assert Ok(state) = forest.new(revision("99"), stored, Some(root))
  let assert Ok(authored) =
    change.edit(
      stored,
      state,
      commit_revision,
      SetField(["point", field], NumberValue(value)),
      order,
    )
  history.Commit(commit_revision, originator, shared_change.from_data(authored))
}

fn repair_roots(commit: history.Commit) {
  commit.change
  |> shared_change.to_changes
  |> list.flat_map(fn(item) {
    case item {
      shared_change.SchemaChange(_, _, _) -> []
      shared_change.DataChange(data) ->
        data
        |> change.to_data
        |> fn(data) { data.builds }
        |> list.map(fn(build) { build.id })
    }
  })
}

fn no_mint(state: Nil) {
  let _ = state
  panic as "unexpected rollback allocation"
}

fn mint(state: Allocation) {
  let assert [revision, ..rest] = state.revisions
  Ok(#(revision, state.order, Allocation(rest, state.order)))
}

fn commit_effects(commit: history.Commit) {
  let tagged =
    shared_change.TaggedChange(Some(commit.revision), None, commit.change)
  let composed = shared_change.compose([tagged]) |> expect.to_be_ok
  shared_change.effects(shared_change.TaggedChange(None, None, composed))
  |> expect.to_be_ok
}

fn replayed_revision_branches() {
  let replayed_revision = revision("0a")
  let target_revision = revision("0b")
  let assert Ok(order) =
    change.identity_order([
      #(replayed_revision, -2),
      #(target_revision, -1),
    ])
  let replayed =
    edit_field_commit_with_order(replayed_revision, session(), "x", 7.0, order)
  let target =
    edit_field_commit_with_order(
      target_revision,
      peer_session(),
      "y",
      9.0,
      order,
    )
  let appended =
    history.append_local(history.new(session()), replayed) |> expect.to_be_ok
  let #(sequenced, Nil) =
    history.receive(
      appended.history,
      replayed,
      types.SequencePoint(1, 0),
      0,
      0,
      Nil,
      no_mint,
    )
    |> expect.to_be_ok
  let #(with_old, old) =
    history.fork_local(sequenced.history, types.DocumentCheckout)
    |> expect.to_be_ok
  let #(with_target, Nil) =
    history.receive(
      with_old,
      target,
      types.SequencePoint(2, 0),
      1,
      0,
      Nil,
      no_mint,
    )
    |> expect.to_be_ok
  let #(with_replay, Nil) =
    history.receive(
      with_target.history,
      replayed,
      types.SequencePoint(3, 0),
      2,
      0,
      Nil,
      no_mint,
    )
    |> expect.to_be_ok
  let #(state, current) =
    history.fork_local(with_replay.history, types.DocumentCheckout)
    |> expect.to_be_ok
  #(state, old, current, replayed, target)
}

fn replayed_revision_branches_after_original_trim() {
  let replayed_revision = revision("0a")
  let target_revision = revision("0b")
  let assert Ok(order) =
    change.identity_order([
      #(replayed_revision, -2),
      #(target_revision, -1),
    ])
  let replayed =
    edit_field_commit_with_order(replayed_revision, session(), "x", 7.0, order)
  let target =
    edit_field_commit_with_order(
      target_revision,
      peer_session(),
      "y",
      9.0,
      order,
    )
  let appended =
    history.append_local(history.new(session()), replayed) |> expect.to_be_ok
  let #(sequenced, Nil) =
    history.receive(
      appended.history,
      replayed,
      types.SequencePoint(1, 0),
      0,
      0,
      Nil,
      no_mint,
    )
    |> expect.to_be_ok
  let #(with_target, Nil) =
    history.receive(
      sequenced.history,
      target,
      types.SequencePoint(2, 0),
      1,
      0,
      Nil,
      no_mint,
    )
    |> expect.to_be_ok
  let #(with_old, old) =
    history.fork_local(with_target.history, types.DocumentCheckout)
    |> expect.to_be_ok
  let #(with_replay, Nil) =
    history.receive(
      with_old,
      replayed,
      types.SequencePoint(3, 0),
      2,
      0,
      Nil,
      no_mint,
    )
    |> expect.to_be_ok
  let #(with_current, current) =
    history.fork_local(with_replay.history, types.DocumentCheckout)
    |> expect.to_be_ok
  let #(trimmed, Nil) =
    history.advance_minimum(with_current, 3, 3, Nil, no_mint)
    |> expect.to_be_ok
  trimmed.trimmed_revisions |> expect.to_equal([replayed.revision])
  #(trimmed.history, old, current, replayed, target)
}

pub fn local_branch_snapshot_restore_preserves_replay_classification_test() -> Nil {
  let #(state, _, _, replayed, _) = replayed_revision_branches()
  let snapshot = history.inspect(state).sequenced
  snapshot.replayed_receipts
  |> expect.to_equal([types.SequencePoint(3, 0)])

  let restored = history.restore(snapshot, session()) |> expect.to_be_ok
  history.inspect(restored).sequenced.replayed_receipts
  |> expect.to_equal([types.SequencePoint(3, 0)])
  history.inspect(restored).sequenced.trunk
  |> list.map(fn(entry) { entry.commit.revision })
  |> expect.to_equal([replayed.revision, revision("0b"), replayed.revision])
}

pub fn local_branch_snapshot_restore_releases_trimmed_replay_marker_test() -> Nil {
  let #(state, _, _, _, _) = replayed_revision_branches()
  let restored =
    history.restore(history.inspect(state).sequenced, session())
    |> expect.to_be_ok
  let #(trimmed, Nil) =
    history.advance_minimum(restored, 3, 3, Nil, no_mint)
    |> expect.to_be_ok

  history.inspect(trimmed.history).sequenced.replayed_receipts
  |> expect.to_equal([])
}

pub fn local_branch_fork_pins_optimistic_head_test() -> Nil {
  let trunk = empty_commit("0a")
  let pending = repair_commit("0b")
  let assert Ok(appended) = history.append_local(history.new(session()), trunk)
  let assert Ok(#(acked, Nil)) =
    history.receive(
      appended.history,
      trunk,
      types.SequencePoint(1, 0),
      0,
      0,
      Nil,
      no_mint,
    )
  let assert Ok(optimistic) = history.append_local(acked.history, pending)
  let assert Ok(#(forked, id)) =
    history.fork_local(optimistic.history, types.DocumentCheckout)
  let assert types.LocalCheckoutId(0) = id
  let assert Ok(#(advanced, Nil)) =
    history.advance_minimum(forked, 1, 1, Nil, no_mint)

  advanced.trimmed_revisions |> expect.to_equal([])
  history.inspect(advanced.history).sequenced.trunk
  |> expect.to_equal([history.SequencedCommit(trunk, types.SequencePoint(1, 0))])
  history.inspect_local(advanced.history, id)
  |> expect.to_equal(
    Ok(history.LocalBranch(id, Some(trunk.revision), [pending])),
  )
  repair_roots(pending)
  |> list.length
  |> fn(length) { length > 0 }
  |> expect.to_equal(True)
  let assert Ok(history.LocalBranch(_, _, [retained])) =
    history.inspect_local(advanced.history, id)
  repair_roots(retained) |> expect.to_equal(repair_roots(pending))
}

pub fn local_branch_descendant_survives_parent_disposal_test() -> Nil {
  let trunk = empty_commit("0a")
  let assert Ok(appended) = history.append_local(history.new(session()), trunk)
  let assert Ok(#(acked, Nil)) =
    history.receive(
      appended.history,
      trunk,
      types.SequencePoint(1, 0),
      0,
      0,
      Nil,
      no_mint,
    )
  let assert Ok(#(with_parent, parent)) =
    history.fork_local(acked.history, types.DocumentCheckout)
  let assert Ok(#(with_child, child)) =
    history.fork_local(with_parent, types.LocalCheckout(parent))
  let assert Ok(without_parent) = history.dispose_local(with_child, parent)
  let assert Ok(#(advanced, Nil)) =
    history.advance_minimum(without_parent, 1, 1, Nil, no_mint)

  history.inspect_local(advanced.history, parent) |> expect.to_be_error()
  history.inspect_local(advanced.history, child)
  |> expect.to_equal(Ok(history.LocalBranch(child, Some(trunk.revision), [])))
  advanced.trimmed_revisions |> expect.to_equal([])

  let assert Ok(disposed_again) =
    history.dispose_local(advanced.history, parent)
  disposed_again |> expect.to_equal(advanced.history)
  let assert Ok(without_child) = history.dispose_local(disposed_again, child)
  let assert Ok(#(released, Nil)) =
    history.advance_minimum(without_child, 1, 1, Nil, no_mint)
  released.trimmed_revisions |> expect.to_equal([trunk.revision])
}

pub fn local_branch_dispose_preserves_revertible_pin_test() -> Nil {
  let first = empty_commit("0a")
  let second = empty_commit("0b")
  let assert Ok(appended_first) =
    history.append_local(history.new(session()), first)
  let assert Ok(appended_second) =
    history.append_local(appended_first.history, second)
  let assert Ok(#(acked_first, Nil)) =
    history.receive(
      appended_second.history,
      first,
      types.SequencePoint(1, 0),
      0,
      0,
      Nil,
      no_mint,
    )
  let assert Ok(#(acked_second, Nil)) =
    history.receive(
      acked_first.history,
      second,
      types.SequencePoint(2, 0),
      1,
      0,
      Nil,
      no_mint,
    )
  let assert Ok(#(forked, branch)) =
    history.fork_local(acked_second.history, types.DocumentCheckout)
  let assert Ok(#(retained, revertible)) =
    history.retain_revertible(forked, second.revision, types.DefaultCommit)
  let assert Ok(disposed_branch) = history.dispose_local(retained, branch)
  let assert Ok(#(pinned, Nil)) =
    history.advance_minimum(disposed_branch, 2, 2, Nil, no_mint)

  pinned.trimmed_revisions |> expect.to_equal([first.revision])
  history.inspect(pinned.history).sequenced.trunk
  |> expect.to_equal([
    history.SequencedCommit(second, types.SequencePoint(2, 0)),
  ])
  history.revertible_is_valid(pinned.history, revertible)
  |> expect.to_equal(True)

  let assert Ok(released) =
    history.dispose_revertible(pinned.history, revertible)
  let assert Ok(#(trimmed, Nil)) =
    history.advance_minimum(released, 2, 2, Nil, no_mint)
  trimmed.trimmed_revisions |> expect.to_equal([second.revision])
}

pub fn local_branch_rebase_advances_only_its_pin_test() -> Nil {
  let trunk_revision = revision("0a")
  let target_revision = revision("0b")
  let source_revision = revision("0c")
  let rollback_revision = revision("0d")
  let assert Ok(order) =
    change.identity_order([
      #(trunk_revision, -4),
      #(target_revision, -3),
      #(source_revision, -2),
      #(rollback_revision, -1),
    ])
  let trunk = empty_commit_with_order(trunk_revision, order)
  let target = empty_commit_with_order(target_revision, order)
  let source = empty_commit_with_order(source_revision, order)
  let assert Ok(appended) = history.append_local(history.new(session()), trunk)
  let assert Ok(#(acked_trunk, Nil)) =
    history.receive(
      appended.history,
      trunk,
      types.SequencePoint(1, 0),
      0,
      0,
      Nil,
      no_mint,
    )
  let assert Ok(#(with_source, source_id)) =
    history.fork_local(acked_trunk.history, types.DocumentCheckout)
  let assert Ok(source_authored) =
    history.append_local_checkout(with_source, source_id, source)
  let assert Ok(#(with_sibling, sibling_id)) =
    history.fork_local(source_authored.history, types.DocumentCheckout)
  let assert Ok(target_pending) = history.append_local(with_sibling, target)
  let assert Ok(#(target_acked, Nil)) =
    history.receive(
      target_pending.history,
      target,
      types.SequencePoint(2, 0),
      1,
      0,
      Nil,
      no_mint,
    )
  let assert Ok(#(with_rebase_target, rebase_target)) =
    history.fork_local(target_acked.history, types.DocumentCheckout)
  let target_before = history.inspect_local(with_rebase_target, rebase_target)
  let allocation = Allocation([rollback_revision], order)
  let source_before = history.inspect_local(with_rebase_target, source_id)
  let assert Ok(#(self_rebased, Allocation([_], _))) =
    history.rebase_local(
      with_rebase_target,
      source_id,
      types.LocalCheckout(source_id),
      allocation,
      mint,
    )
  history.inspect_local(self_rebased.history, source_id)
  |> expect.to_equal(source_before)
  let assert Ok(#(rebased, Allocation([], _))) =
    history.rebase_local(
      self_rebased.history,
      source_id,
      types.LocalCheckout(rebase_target),
      allocation,
      mint,
    )

  history.inspect_local(rebased.history, rebase_target)
  |> expect.to_equal(target_before)
  let assert Ok(history.LocalBranch(_, source_base, source_commits)) =
    history.inspect_local(rebased.history, source_id)
  source_base |> expect.to_equal(Some(target_revision))
  source_commits
  |> fn(commits) { commits |> list.map(fn(commit) { commit.revision }) }
  |> expect.to_equal([source_revision])
  history.inspect_local(rebased.history, sibling_id)
  |> expect.to_equal(
    Ok(history.LocalBranch(sibling_id, Some(trunk_revision), [])),
  )
  history.inspect_rollback_revisions(rebased.history)
  |> expect.to_equal([rollback_revision])

  let assert Ok(#(sibling_pinned, Allocation([], _))) =
    history.advance_minimum(rebased.history, 2, 2, Allocation([], order), mint)
  sibling_pinned.trimmed_revisions |> expect.to_equal([])
  let assert Ok(without_sibling) =
    history.dispose_local(sibling_pinned.history, sibling_id)
  let assert Ok(#(source_pinned, Allocation([], _))) =
    history.advance_minimum(without_sibling, 2, 2, Allocation([], order), mint)
  source_pinned.trimmed_revisions |> expect.to_equal([trunk_revision])
  history.inspect_rollback_revisions(source_pinned.history)
  |> expect.to_equal([])
}

pub fn local_branch_merge_removes_common_revisions_test() -> Nil {
  let trunk = empty_commit("0a")
  let common = empty_commit("0b")
  let source_only = empty_commit("0c")
  let assert Ok(appended) = history.append_local(history.new(session()), trunk)
  let assert Ok(#(acked, Nil)) =
    history.receive(
      appended.history,
      trunk,
      types.SequencePoint(1, 0),
      0,
      0,
      Nil,
      no_mint,
    )
  let assert Ok(#(forked, source)) =
    history.fork_local(acked.history, types.DocumentCheckout)
  let assert Ok(common_update) =
    history.append_local_checkout(forked, source, common)
  let assert Ok(#(with_target, target)) =
    history.fork_local(common_update.history, types.LocalCheckout(source))
  let assert Ok(source_update) =
    history.append_local_checkout(with_target, source, source_only)
  let assert Ok(#(self_merged, [], Nil)) =
    history.merge_local(
      source_update.history,
      types.LocalCheckout(source),
      source,
      Nil,
      no_mint,
    )
  history.inspect_local(self_merged.history, source)
  |> expect.to_equal(history.inspect_local(source_update.history, source))
  let assert Ok(#(merged, surviving, Nil)) =
    history.merge_local(
      self_merged.history,
      types.LocalCheckout(target),
      source,
      Nil,
      no_mint,
    )

  surviving
  |> list.map(fn(commit) { commit.revision })
  |> expect.to_equal([source_only.revision])
  let assert Ok(history.LocalBranch(_, base, commits)) =
    history.inspect_local(merged.history, target)
  base |> expect.to_equal(Some(trunk.revision))
  commits
  |> list.map(fn(commit) { commit.revision })
  |> expect.to_equal([common.revision, source_only.revision])
  history.inspect_local(merged.history, source)
  |> expect.to_equal(
    Ok(history.LocalBranch(source, Some(trunk.revision), [common, source_only])),
  )

  let assert Ok(#(repeated, repeated_surviving, Nil)) =
    history.merge_local(
      merged.history,
      types.LocalCheckout(target),
      source,
      Nil,
      no_mint,
    )
  repeated_surviving |> expect.to_equal([])
  history.inspect_local(repeated.history, target)
  |> expect.to_equal(history.inspect_local(merged.history, target))
}

pub fn local_branch_repeated_divergent_merge_excludes_target_revisions_test() -> Nil {
  let trunk_revision = revision("0a")
  let source_revision = revision("0b")
  let target_revision = revision("0c")
  let rollback_revision = revision("0d")
  let assert Ok(order) =
    change.identity_order([
      #(trunk_revision, -4),
      #(source_revision, -3),
      #(target_revision, -2),
      #(rollback_revision, -1),
    ])
  let trunk = empty_commit_with_order(trunk_revision, order)
  let source_commit = empty_commit_with_order(source_revision, order)
  let target_commit = empty_commit_with_order(target_revision, order)
  let assert Ok(appended) = history.append_local(history.new(session()), trunk)
  let assert Ok(#(acked, Nil)) =
    history.receive(
      appended.history,
      trunk,
      types.SequencePoint(1, 0),
      0,
      0,
      Nil,
      no_mint,
    )
  let assert Ok(#(with_source, source)) =
    history.fork_local(acked.history, types.DocumentCheckout)
  let assert Ok(#(with_target, target)) =
    history.fork_local(with_source, types.DocumentCheckout)
  let assert Ok(source_authored) =
    history.append_local_checkout(with_target, source, source_commit)
  let assert Ok(target_authored) =
    history.append_local_checkout(
      source_authored.history,
      target,
      target_commit,
    )
  let allocation = Allocation([rollback_revision], order)
  let assert Ok(#(merged, surviving, Allocation([], _))) =
    history.merge_local(
      target_authored.history,
      types.LocalCheckout(target),
      source,
      allocation,
      mint,
    )

  surviving
  |> list.map(fn(commit) { commit.revision })
  |> expect.to_equal([source_revision])
  let target_after_first = history.inspect_local(merged.history, target)
  let assert Ok(#(repeated, repeated_surviving, Allocation([], _))) =
    history.merge_local(
      merged.history,
      types.LocalCheckout(target),
      source,
      Allocation([], order),
      mint,
    )
  repeated_surviving |> expect.to_equal([])
  history.inspect_local(repeated.history, target)
  |> expect.to_equal(target_after_first)
}

pub fn local_branch_pending_revision_is_not_replayed_after_sequencing_test() -> Nil {
  let pending_revision = revision("0a")
  let remote_revision = revision("0b")
  let rollback_revision = revision("0c")
  let assert Ok(order) =
    change.identity_order([
      #(pending_revision, -3),
      #(remote_revision, -2),
      #(rollback_revision, -1),
    ])
  let pending = empty_commit_with_order(pending_revision, order)
  let remote =
    history.Commit(
      ..empty_commit_with_order(remote_revision, order),
      originator: peer_session(),
    )
  let assert Ok(appended) =
    history.append_local(history.new(session()), pending)
  let assert Ok(#(forked, source)) =
    history.fork_local(appended.history, types.DocumentCheckout)
  let assert Ok(#(remote_received, Allocation([], _))) =
    history.receive(
      forked,
      remote,
      types.SequencePoint(1, 0),
      0,
      0,
      Allocation([rollback_revision], order),
      mint,
    )
  let assert Ok(#(sequenced, Allocation([], _))) =
    history.receive(
      remote_received.history,
      pending,
      types.SequencePoint(2, 0),
      1,
      0,
      Allocation([], order),
      mint,
    )
  let assert Ok(#(rebased, Allocation([], _))) =
    history.rebase_local(
      sequenced.history,
      source,
      types.DocumentCheckout,
      Allocation([], order),
      mint,
    )

  history.inspect_local(rebased.history, source)
  |> expect.to_equal(
    Ok(history.LocalBranch(source, Some(pending_revision), [])),
  )
}

pub fn local_branch_replay_keeps_original_sequence_pin_test() -> Nil {
  let first_revision = revision("0a")
  let remote_revision = revision("0b")
  let assert Ok(order) =
    change.identity_order([
      #(first_revision, -2),
      #(remote_revision, -1),
    ])
  let first = empty_commit_with_order(first_revision, order)
  let remote =
    edit_commit_with_order(remote_revision, peer_session(), 9.0, order)
  let appended =
    history.append_local(history.new(session()), first) |> expect.to_be_ok
  let #(sequenced, Nil) =
    history.receive(
      appended.history,
      first,
      types.SequencePoint(1, 0),
      0,
      0,
      Nil,
      no_mint,
    )
    |> expect.to_be_ok
  let #(forked, fork) =
    history.fork_local(sequenced.history, types.DocumentCheckout)
    |> expect.to_be_ok
  let #(with_remote, Nil) =
    history.receive(
      forked,
      remote,
      types.SequencePoint(2, 0),
      1,
      0,
      Nil,
      no_mint,
    )
    |> expect.to_be_ok
  let #(with_replay, Nil) =
    history.receive(
      with_remote.history,
      first,
      types.SequencePoint(3, 0),
      2,
      0,
      Nil,
      no_mint,
    )
    |> expect.to_be_ok
  let #(pinned, Nil) =
    history.advance_minimum(with_replay.history, 3, 3, Nil, no_mint)
    |> expect.to_be_ok

  pinned.trimmed_revisions |> expect.to_equal([])
  let #(rebased, Nil) =
    history.rebase_local(
      pinned.history,
      fork,
      types.DocumentCheckout,
      Nil,
      no_mint,
    )
    |> expect.to_be_ok
  rebased.effects
  |> list.length
  |> fn(length) { length > 0 }
  |> expect.to_equal(True)

  let disposed = history.dispose_local(rebased.history, fork) |> expect.to_be_ok
  let #(released, Nil) =
    history.advance_minimum(disposed, 3, 3, Nil, no_mint)
    |> expect.to_be_ok
  released.trimmed_revisions
  |> expect.to_equal([first.revision, remote.revision, first.revision])
}

pub fn local_branch_merge_ignores_replayed_source_receipt_test() -> Nil {
  let #(state, old, current, replayed, target) = replayed_revision_branches()
  let #(merged, surviving, Nil) =
    history.merge_local(state, types.LocalCheckout(old), current, Nil, no_mint)
    |> expect.to_be_ok

  surviving
  |> list.map(fn(commit) { commit.revision })
  |> expect.to_equal([target.revision])
  merged.effects |> expect.to_equal(commit_effects(target))
  history.inspect_local(merged.history, old)
  |> expect.to_equal(
    Ok(history.LocalBranch(old, Some(replayed.revision), [target])),
  )
  history.inspect_local(merged.history, current)
  |> expect.to_equal(
    Ok(history.LocalBranch(current, Some(replayed.revision), [])),
  )
}

pub fn local_branch_reverse_merge_ignores_replayed_target_receipt_test() -> Nil {
  let #(state, old, current, replayed, _) = replayed_revision_branches()
  let #(merged, surviving, Nil) =
    history.merge_local(state, types.LocalCheckout(current), old, Nil, no_mint)
    |> expect.to_be_ok

  surviving |> expect.to_equal([])
  merged.effects |> expect.to_equal([])
  history.inspect_local(merged.history, current)
  |> expect.to_equal(
    Ok(history.LocalBranch(current, Some(replayed.revision), [])),
  )
  history.inspect_local(merged.history, old)
  |> expect.to_equal(Ok(history.LocalBranch(old, Some(replayed.revision), [])))
}

pub fn local_branch_rebase_ignores_replayed_target_receipt_test() -> Nil {
  let #(state, old, current, replayed, target) = replayed_revision_branches()
  let #(rebased, Nil) =
    history.rebase_local(state, old, types.LocalCheckout(current), Nil, no_mint)
    |> expect.to_be_ok

  rebased.effects |> expect.to_equal(commit_effects(target))
  history.inspect_local(rebased.history, old)
  |> expect.to_equal(Ok(history.LocalBranch(old, Some(replayed.revision), [])))
  history.inspect_local(rebased.history, current)
  |> expect.to_equal(
    Ok(history.LocalBranch(current, Some(replayed.revision), [])),
  )
}

pub fn local_branch_trimmed_original_still_ignores_replay_receipt_test() -> Nil {
  let #(state, old, current, _replayed, target) =
    replayed_revision_branches_after_original_trim()
  let #(merged, surviving, Nil) =
    history.merge_local(state, types.LocalCheckout(old), current, Nil, no_mint)
    |> expect.to_be_ok

  surviving |> expect.to_equal([])
  merged.effects |> expect.to_equal([])
  history.inspect_local(merged.history, old)
  |> expect.to_equal(Ok(history.LocalBranch(old, Some(target.revision), [])))

  let #(rebased, Nil) =
    history.rebase_local(state, old, types.LocalCheckout(current), Nil, no_mint)
    |> expect.to_be_ok
  rebased.effects |> expect.to_equal([])
  history.inspect_local(rebased.history, old)
  |> expect.to_equal(Ok(history.LocalBranch(old, None, [])))
}
