@target(erlang)
import gleam/erlang/process
import startest/expect
@target(javascript)
import watershed as facade
import watershed/tree
import watershed/tree/error
import watershed/tree/live_fixture as fixture
import watershed/tree/schema_builder as builder
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
