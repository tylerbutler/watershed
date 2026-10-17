@target(erlang)
import gleam/erlang/process
import gleam/json
import gleam/option.{None, Some}
import startest/expect
@target(javascript)
import watershed as facade
import watershed/tree
import watershed/tree/error
import watershed/tree/live_fixture as fixture
import watershed/tree/schema_builder as builder
import watershed/tree/types
@target(erlang)
import watershed_beam as facade

fn card() {
  let definition = fixture.card_schema()
  let assert Ok(compiled) = definition.node |> builder.root |> builder.compile
  let #(document, native) =
    fixture.tree(compiled, fixture.Card(builder.Assigned("original"), "First"))
  let assert Ok(tree) = facade.tree_typed(native, compiled)
  #(document, tree, definition)
}

pub fn tree_api_reads_and_edits_with_one_handle_test() {
  let #(document, tree, definition) = card()
  let assert Ok(root) = tree.required_root(tree)
  tree.set(root, definition.title, "Updated") |> expect.to_equal(Ok(Nil))
  tree.get(root, definition.title) |> expect.to_equal(Ok("Updated"))
  tree.read_root(tree)
  |> expect.to_equal(Ok(fixture.Card(builder.Assigned("original"), "Updated")))
  facade.close(document)
}

pub fn tree_api_transaction_keeps_application_abort_values_test() {
  let #(document, tree, definition) = card()
  let assert Ok(root) = tree.required_root(tree)
  tree.transaction(tree, [tree.node_in_document(root)], fn(same_tree) {
    let assert Ok(same_root) = tree.required_root(same_tree)
    let assert Ok(Nil) = tree.set(same_root, definition.title, "Preview")
    Error(#("cancelled", 42))
  })
  |> expect.to_equal(Error(tree.Aborted(#("cancelled", 42))))
  tree.get(root, definition.title) |> expect.to_equal(Ok("First"))
  facade.close(document)
}

pub fn tree_api_fork_keeps_reads_and_history_on_one_handle_test() {
  let #(document, document_tree, definition) = card()
  let assert Ok(branch) = tree.fork(document_tree)
  let assert Ok(root) = tree.required_root(branch)
  tree.set(root, definition.title, "Branch") |> expect.to_equal(Ok(Nil))
  tree.read_root(document_tree)
  |> expect.to_equal(Ok(fixture.Card(builder.Assigned("original"), "First")))
  tree.merge(document_tree, branch, tree.DisposeSource)
  |> expect.to_equal(Ok(Nil))
  tree.read_root(document_tree)
  |> expect.to_equal(Ok(fixture.Card(builder.Assigned("original"), "Branch")))
  facade.close(document)
}

pub fn tree_api_transaction_aborts_when_the_callback_raises_test() {
  let #(document, tree, definition) = card()
  let assert Ok(root) = tree.required_root(tree)
  let outcome =
    tree.transaction(tree, [], fn(_) {
      let assert Ok(Nil) = tree.set(root, definition.title, "Preview")
      panic as "Application callback failed"
    })
  let assert Error(tree.TransactionFailed(error.RuntimeFailure(_))) = outcome
  tree.get(root, definition.title) |> expect.to_equal(Ok("First"))
  tree.transaction(tree, [], fn(_) { Ok(42) }) |> expect.to_equal(Ok(42))
  facade.close(document)
}

@target(erlang)
pub fn tree_api_transaction_hides_previews_from_other_callers_test() {
  let #(document, tree, definition) = card()
  let assert Ok(root) = tree.required_root(tree)
  let #(record, take) = fixture.capture()
  tree.transaction(tree, [], fn(_) {
    let assert Ok(Nil) = tree.set(root, definition.title, "Preview")
    let _ = process.spawn_unlinked(fn() { record(tree.read_root(tree)) })
    take(1)
    |> expect.to_equal([
      Error(error.TransactionConflict("tree transaction uses another caller")),
    ])
    Ok(Nil)
  })
  |> expect.to_equal(Ok(Nil))
  facade.close(document)
}

pub fn tree_api_commit_events_and_revertibles_use_the_same_tree_test() {
  let #(document, tree, definition) = card()
  let assert Ok(root) = tree.required_root(tree)
  let #(record, take) = fixture.capture()
  let #(disposed, take_disposed) = fixture.capture()
  let assert Ok(subscription) =
    tree.subscribe_commits(tree, fn(event) {
      let assert Ok(revertible) =
        tree.get_revertible(event, fn(value) {
          disposed(tree.revertible_revision(value))
        })
      record(#(event.kind, revertible))
    })
  take(0) |> expect.to_equal([])
  tree.set(root, definition.title, "Updated") |> expect.to_equal(Ok(Nil))
  let assert [#(tree.DefaultCommit, original)] = take(1)
  let revision = tree.revertible_revision(original)
  tree.revertible_status(original) |> expect.to_equal(Ok(tree.RevertibleValid))
  tree.revert(original, tree.DisposeRevertible) |> expect.to_equal(Ok(Nil))
  let assert [#(tree.UndoCommit, undo)] = take(1)
  tree.get(root, definition.title) |> expect.to_equal(Ok("First"))
  take_disposed(1) |> expect.to_equal([revision])
  tree.revertible_status(original)
  |> expect.to_equal(Ok(tree.RevertibleDisposed))
  tree.revert(undo, tree.KeepRevertible) |> expect.to_equal(Ok(Nil))
  let assert [#(tree.RedoCommit, redo)] = take(1)
  tree.get(root, definition.title) |> expect.to_equal(Ok("Updated"))
  tree.dispose_revertible(undo) |> expect.to_equal(Ok(Nil))
  take_disposed(1) |> expect.to_equal([tree.revertible_revision(undo)])
  tree.dispose_revertible(redo) |> expect.to_equal(Ok(Nil))
  take_disposed(1) |> expect.to_equal([tree.revertible_revision(redo)])
  tree.unsubscribe(subscription)
  facade.close(document)
  tree.revertible_revision(original) |> expect.to_equal(revision)
}

pub fn tree_api_document_handle_disposal_does_not_own_revertibles_test() {
  let #(document, tree, definition) = card()
  let assert Ok(root) = tree.required_root(tree)
  let #(record, take) = fixture.capture()
  let assert Ok(_) =
    tree.subscribe_commits(tree, fn(event) {
      let assert Ok(revertible) = tree.get_revertible(event, fn(_) { Nil })
      record(revertible)
    })
  tree.set(root, definition.title, "Updated") |> expect.to_equal(Ok(Nil))
  let assert [revertible] = take(1)
  tree.dispose(tree) |> expect.to_equal(Ok(Nil))
  tree.revert(revertible, tree.DisposeRevertible) |> expect.to_equal(Ok(Nil))
  tree.revertible_status(revertible)
  |> expect.to_equal(Ok(tree.RevertibleDisposed))
  take(0) |> expect.to_equal([])
  facade.close(document)
}

pub fn tree_api_branch_commit_factories_are_scoped_and_expire_test() {
  let definition = fixture.card_schema()
  let assert Ok(compiled) = definition.node |> builder.root |> builder.compile
  let #(submitted, take_submitted) = fixture.capture()
  let #(document, native, deliver) =
    fixture.tree_with_submissions(
      compiled,
      fixture.Card(builder.Assigned("original"), "First"),
      submitted,
    )
  let assert Ok(document_tree) = facade.tree_typed(native, compiled)
  let assert Ok(branch) = tree.fork(document_tree)
  let assert Ok(root) = tree.required_root(branch)
  let #(record, take) = fixture.capture()
  let #(settled, take_settled) = fixture.capture()
  let #(document_commit, take_document) = fixture.capture()
  let assert Ok(_) =
    tree.subscribe_commits(document_tree, fn(event) {
      document_commit(event.local)
    })
  let assert Ok(_) =
    tree.subscribe_commits(branch, fn(event) {
      let assert Some(register) = event.on_settled
      let registration = register(settled)
      let acquired = tree.get_revertible(event, fn(_) { Nil })
      let duplicate = tree.get_revertible(event, fn(_) { Nil })
      let snapshot = tree.get(root, definition.title)
      let reentrant = tree.set(root, definition.title, "Reentrant")
      record(#(event, acquired, duplicate, registration, snapshot, reentrant))
    })
  tree.set(root, definition.title, "Branch") |> expect.to_equal(Ok(Nil))
  let assert [
    #(
      event,
      Ok(revertible),
      Error(error.RuntimeFailure(_)),
      Ok(Nil),
      Ok("Branch"),
      Error(error.ReentrantEdit),
    ),
  ] = take(1)
  event.local |> expect.to_equal(True)
  take_document(0) |> expect.to_equal([])
  take_settled(0) |> expect.to_equal([])
  let assert Error(error.RuntimeFailure(_)) =
    tree.get_revertible(event, fn(_) { Nil })
  let assert Some(register) = event.on_settled
  let assert Error(error.RuntimeFailure(_)) = register(fn(_) { Nil })
  tree.merge(document_tree, branch, tree.KeepSource)
  |> expect.to_equal(Ok(Nil))
  take_document(1) |> expect.to_equal([True])
  take_settled(0) |> expect.to_equal([])
  let assert [payload] = take_submitted(1)
  deliver([fixture.acknowledgement(payload)])
  take_settled(1) |> expect.to_equal([tree.FullyApplied])
  tree.revert(revertible, tree.DisposeRevertible) |> expect.to_equal(Ok(Nil))
  let assert [#(undo, _, _, _, _, _)] = take(1)
  undo.kind |> expect.to_equal(tree.UndoCommit)
  tree.get(root, definition.title) |> expect.to_equal(Ok("First"))
  tree.read_root(document_tree)
  |> expect.to_equal(Ok(fixture.Card(builder.Assigned("original"), "Branch")))
  take_document(0) |> expect.to_equal([])
  facade.close(document)
}

pub fn tree_api_remote_commits_do_not_offer_local_history_test() {
  let definition = fixture.card_schema()
  let assert Ok(compiled) = definition.node |> builder.root |> builder.compile
  let initial = fixture.Card(builder.Assigned("original"), "First")
  let #(document, native, deliver) =
    fixture.tree_with_operations(compiled, initial)
  let assert Ok(tree) = facade.tree_typed(native, compiled)
  let #(record, take) = fixture.capture()
  let assert Ok(_) = tree.subscribe_commits(tree, record)
  let #(changed, take_changes) = fixture.capture()
  let assert Ok(_) = tree.subscribe_changes(tree, changed)
  deliver([
    fixture.remote_edit(
      compiled,
      initial,
      types.SetField(["title"], types.StringValue("Remote")),
    ),
  ])
  let assert [event] = take(1)
  event.kind |> expect.to_equal(tree.DefaultCommit)
  event.local |> expect.to_equal(False)
  event.get_revertible |> expect.to_equal(None)
  event.on_settled |> expect.to_equal(None)
  take_changes(1) |> expect.to_equal([tree.TreeChanged(False)])
  tree.read_root(tree)
  |> expect.to_equal(Ok(fixture.Card(builder.Assigned("original"), "Remote")))
  facade.close(document)
}

pub fn tree_api_checkout_status_and_routing_use_the_same_handle_test() {
  let definition = fixture.card_schema()
  let assert Ok(compiled) = definition.node |> builder.root |> builder.compile
  let #(document, native) =
    fixture.tree(compiled, fixture.Card(builder.Assigned("original"), "First"))
  let assert Ok(tree) = facade.tree_typed(native, compiled)
  let assert Ok(root) = facade.resolve_root(document)
  let assert Ok(marker) = facade.get(root, "tree")
  let route = json.to_string(marker)
  tree.handle_of(tree) |> json.to_string |> expect.to_equal(route)
  tree.branch_status(tree) |> expect.to_equal(Ok(tree.DocumentBranch))
  let assert Ok(branch) = tree.fork(tree)
  tree.branch_status(branch) |> expect.to_equal(Ok(tree.BranchValid))
  tree.handle_of(branch) |> json.to_string |> expect.to_equal(route)
  tree.dispose(branch) |> expect.to_equal(Ok(Nil))
  tree.branch_status(branch) |> expect.to_equal(Ok(tree.BranchDisposed))
  tree.dispose(branch) |> expect.to_equal(Ok(Nil))
  facade.close(document)
  tree.handle_of(tree) |> json.to_string |> expect.to_equal(route)
  tree.branch_status(tree) |> expect.to_equal(Error(error.ClosedRuntime))
}
