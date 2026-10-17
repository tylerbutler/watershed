import gleam/option.{None, Some}
import startest/expect
@target(javascript)
import watershed as facade
import watershed/tree
import watershed/tree/error
import watershed/tree/live_fixture as fixture
import watershed/tree/schema_builder as builder
@target(erlang)
import watershed_beam as facade

fn card(title: String) -> fixture.Card {
  fixture.Card(builder.Assigned(title), title)
}

pub fn tree_api_node_observation_is_changes_only_and_can_repeat_test() {
  let definition = fixture.card_schema()
  let assert Ok(compiled) =
    builder.array(builder.factory("observation"), "Cards", definition.node)
    |> builder.root
    |> builder.compile
  let #(document, native) = fixture.tree(compiled, [card("A"), card("B")])
  let assert Ok(tree) = facade.tree_typed(native, compiled)
  let assert Ok(array) = tree.required_root(tree)
  let assert Ok(Some(first)) = tree.array_node(array, 0)
  let assert Ok(Some(second)) = tree.array_node(array, 1)
  let #(record, take) = fixture.capture()
  let assert Ok(subscription) = tree.observe_node(first, record)
  take(0) |> expect.to_equal([])
  tree.read(first) |> expect.to_equal(Ok(card("A")))
  tree.set(second, definition.title, "Changed") |> expect.to_equal(Ok(Nil))
  take(1) |> expect.to_equal([Ok(card("A"))])
  tree.set(second, definition.title, "Again") |> expect.to_equal(Ok(Nil))
  take(1) |> expect.to_equal([Ok(card("A"))])
  tree.array_remove_node(array, first) |> expect.to_equal(Ok(Nil))
  take(1) |> expect.to_equal([Error(error.InvalidReference(error.Removed))])
  tree.unsubscribe(subscription)
  tree.unsubscribe(subscription)
  tree.set(second, definition.title, "Ignored") |> expect.to_equal(Ok(Nil))
  take(0) |> expect.to_equal([])
  facade.close(document)
}

pub fn tree_api_disposing_one_document_handle_keeps_other_handles_test() {
  let definition = fixture.card_schema()
  let assert Ok(compiled) = definition.node |> builder.root |> builder.compile
  let #(document, native) = fixture.tree(compiled, card("First"))
  let assert Ok(first) = facade.tree_typed(native, compiled)
  let assert Ok(second) = facade.tree_typed(native, compiled)
  let #(record, take) = fixture.capture()
  let assert Ok(subscription) = tree.observe(first, record)
  tree.dispose(first) |> expect.to_equal(Ok(Nil))
  tree.dispose(first) |> expect.to_equal(Ok(Nil))
  tree.read_root(first) |> expect.to_equal(Error(error.ClosedTree))
  let assert Ok(root) = tree.required_root(second)
  tree.set(root, definition.title, "Still open") |> expect.to_equal(Ok(Nil))
  take(0) |> expect.to_equal([])
  tree.unsubscribe(subscription)
  facade.close(document)
  tree.dispose(first) |> expect.to_equal(Ok(Nil))
  tree.dispose(second) |> expect.to_equal(Ok(Nil))
  tree.unsubscribe(subscription)
}

pub fn tree_api_disposing_fork_releases_checkout_and_retained_history_test() {
  let definition = fixture.card_schema()
  let assert Ok(compiled) = definition.node |> builder.root |> builder.compile
  let #(document, native) = fixture.tree(compiled, card("First"))
  let assert Ok(document_tree) = facade.tree_typed(native, compiled)
  let assert Ok(branch) = tree.fork(document_tree)
  let assert Ok(root) = tree.required_root(branch)
  let #(record, take) = fixture.capture()
  let #(disposed, take_disposed) = fixture.capture()
  let assert Ok(subscription) =
    tree.subscribe_commits(branch, fn(event) {
      let assert Ok(revertible) =
        tree.get_revertible(event, fn(value) {
          disposed(tree.revertible_revision(value))
        })
      record(revertible)
    })
  tree.set(root, definition.title, "Branch") |> expect.to_equal(Ok(Nil))
  let assert [revertible] = take(1)
  tree.dispose(branch) |> expect.to_equal(Ok(Nil))
  tree.revertible_status(revertible)
  |> expect.to_equal(Ok(tree.RevertibleDisposed))
  take_disposed(1) |> expect.to_equal([tree.revertible_revision(revertible)])
  tree.dispose(branch) |> expect.to_equal(Ok(Nil))
  tree.dispose_revertible(revertible) |> expect.to_equal(Ok(Nil))
  tree.unsubscribe(subscription)
  tree.read_root(document_tree) |> expect.to_equal(Ok(card("First")))
  facade.close(document)
}

pub fn tree_api_merge_disposal_releases_source_history_test() {
  let definition = fixture.card_schema()
  let assert Ok(compiled) = definition.node |> builder.root |> builder.compile
  let #(document, native) = fixture.tree(compiled, card("First"))
  let assert Ok(document_tree) = facade.tree_typed(native, compiled)
  let assert Ok(branch) = tree.fork(document_tree)
  let assert Ok(root) = tree.required_root(branch)
  let #(record, take) = fixture.capture()
  let #(disposed, take_disposed) = fixture.capture()
  let assert Ok(subscription) =
    tree.subscribe_commits(branch, fn(event) {
      let assert Ok(revertible) = tree.get_revertible(event, disposed)
      record(revertible)
    })
  tree.set(root, definition.title, "Branch") |> expect.to_equal(Ok(Nil))
  let assert [revertible] = take(1)
  tree.merge(document_tree, branch, tree.DisposeSource)
  |> expect.to_equal(Ok(Nil))
  let assert [removed] = take_disposed(1)
  tree.revertible_revision(removed)
  |> expect.to_equal(tree.revertible_revision(revertible))
  tree.revertible_status(revertible)
  |> expect.to_equal(Ok(tree.RevertibleDisposed))
  tree.dispose(branch) |> expect.to_equal(Ok(Nil))
  tree.unsubscribe(subscription)
  tree.dispose(document_tree) |> expect.to_equal(Ok(Nil))
  facade.close(document)
}

pub fn tree_api_change_callbacks_read_cancel_and_reject_reentrant_edits_test() {
  let definition = fixture.card_schema()
  let assert Ok(compiled) = definition.node |> builder.root |> builder.compile
  let #(document, native) = fixture.tree(compiled, card("First"))
  let assert Ok(tree) = facade.tree_typed(native, compiled)
  let assert Ok(root) = tree.required_root(tree)
  let #(record, take) = fixture.capture()
  let assert Ok(victim) = tree.subscribe_changes(tree, fn(_) { record(None) })
  let assert Ok(subscription) =
    tree.subscribe_changes(tree, fn(event) {
      tree.unsubscribe(victim)
      record(
        Some(#(
          event,
          tree.get(root, definition.title),
          tree.set(root, definition.title, "Reentrant"),
        )),
      )
    })
  take(0) |> expect.to_equal([])
  tree.set(root, definition.title, "Updated") |> expect.to_equal(Ok(Nil))
  take(1)
  |> expect.to_equal([
    Some(#(tree.TreeChanged(True), Ok("Updated"), Error(error.ReentrantEdit))),
  ])
  tree.unsubscribe(subscription)
  tree.unsubscribe(subscription)
  tree.set(root, definition.title, "Ignored") |> expect.to_equal(Ok(Nil))
  take(0) |> expect.to_equal([])
  facade.close(document)
  tree.unsubscribe(subscription)
}

pub fn tree_api_schema_change_notifications_survive_incompatibility_test() {
  let assert Ok(compiled) = builder.string() |> builder.root |> builder.compile
  let assert Ok(expanded) =
    builder.string() |> builder.optional_root |> builder.compile
  let #(document, native) = fixture.tree(compiled, "First")
  let assert Ok(original) = facade.tree_typed(native, compiled)
  let assert Ok(root) = facade.resolve_root(document)
  let assert Ok(marker) = facade.get(root, "tree")
  let assert Ok(upgraded_native) =
    facade.open_tree(document, marker, fixture.definition(expanded))
  let #(record, take) = fixture.capture()
  let assert Ok(subscription) =
    tree.subscribe_changes(original, fn(event) {
      record(#(
        event,
        tree.read_root(original),
        tree.replace_root(original, "Reentrant"),
      ))
    })
  facade.tree_upgrade_schema(upgraded_native) |> expect.to_equal(Ok(Nil))
  take(1)
  |> expect.to_equal([
    #(
      tree.SchemaChanged(True),
      Error(error.IncompatibleView),
      Error(error.ReentrantEdit),
    ),
  ])
  let assert Ok(upgraded) = facade.tree_typed(upgraded_native, expanded)
  tree.read_root(upgraded) |> expect.to_equal(Ok(Some("First")))
  tree.unsubscribe(subscription)
  tree.dispose(original) |> expect.to_equal(Ok(Nil))
  tree.dispose(original) |> expect.to_equal(Ok(Nil))
  tree.read_root(upgraded) |> expect.to_equal(Ok(Some("First")))
  facade.close(document)
}

pub fn tree_api_changes_are_scoped_to_the_document_and_checkout_test() {
  let definition = fixture.card_schema()
  let assert Ok(compiled) = definition.node |> builder.root |> builder.compile
  let #(document, native) = fixture.tree(compiled, card("First"))
  let #(other_document, other_native) = fixture.tree(compiled, card("Other"))
  let assert Ok(document_tree) = facade.tree_typed(native, compiled)
  let assert Ok(other) = facade.tree_typed(other_native, compiled)
  let assert Ok(branch) = tree.fork(document_tree)
  let assert Ok(document_root) = tree.required_root(document_tree)
  let assert Ok(branch_root) = tree.required_root(branch)
  let assert Ok(other_root) = tree.required_root(other)
  let #(record, take) = fixture.capture()
  let assert Ok(_) =
    tree.subscribe_changes(document_tree, fn(event) {
      record(#("document", event))
    })
  let assert Ok(_) =
    tree.subscribe_changes(branch, fn(event) { record(#("branch", event)) })
  let assert Ok(_) =
    tree.subscribe_changes(other, fn(event) { record(#("other", event)) })
  tree.set(branch_root, definition.title, "Branch")
  |> expect.to_equal(Ok(Nil))
  take(1) |> expect.to_equal([#("branch", tree.TreeChanged(True))])
  tree.set(document_root, definition.title, "Document")
  |> expect.to_equal(Ok(Nil))
  take(1) |> expect.to_equal([#("document", tree.TreeChanged(True))])
  tree.dispose(branch) |> expect.to_equal(Ok(Nil))
  tree.set(document_root, definition.title, "Again")
  |> expect.to_equal(Ok(Nil))
  take(1) |> expect.to_equal([#("document", tree.TreeChanged(True))])
  tree.dispose(document_tree) |> expect.to_equal(Ok(Nil))
  tree.set(other_root, definition.title, "Separate")
  |> expect.to_equal(Ok(Nil))
  take(1) |> expect.to_equal([#("other", tree.TreeChanged(True))])
  facade.close(document)
  facade.close(other_document)
}
