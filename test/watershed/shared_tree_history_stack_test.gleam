import gleam/option.{None, Some}
import startest/expect
@target(javascript)
import watershed as facade
import watershed/tree
import watershed/tree/history_stack as history
import watershed/tree/live_fixture as fixture
import watershed/tree/schema_builder as builder
@target(erlang)
import watershed_beam as facade

pub fn tree_api_history_routes_local_kinds_and_releases_redo_test() {
  let initial = history.new()
  history.route(initial, tree.DefaultCommit, False, Some("remote"))
  |> expect.to_equal(history.Routed(initial, []))
  history.route(initial, tree.DefaultCommit, True, None)
  |> expect.to_equal(history.Routed(initial, []))
  let assert history.Routed(first, []) =
    history.route(initial, tree.DefaultCommit, True, Some("edit"))
  history.next_undo(first) |> expect.to_equal(Some("edit"))
  history.next_redo(first) |> expect.to_equal(None)
  let assert history.Routed(undone, []) =
    history.route(
      history.consume_undo(first),
      tree.UndoCommit,
      True,
      Some("undo"),
    )
  history.next_undo(undone) |> expect.to_equal(None)
  history.next_redo(undone) |> expect.to_equal(Some("undo"))
  let assert history.Routed(redone, []) =
    history.route(
      history.consume_redo(undone),
      tree.RedoCommit,
      True,
      Some("redo"),
    )
  history.next_undo(redone) |> expect.to_equal(Some("redo"))
  history.next_redo(redone) |> expect.to_equal(None)
  history.route(undone, tree.DefaultCommit, True, Some("new edit"))
  |> expect.to_equal(
    history.Routed(history.History(["new edit"], []), ["undo"]),
  )
}

pub fn tree_api_history_prunes_both_stacks_and_clears_each_entry_test() {
  let value = history.History(["latest", "obsolete"], ["redo", "old redo"])
  let pruned =
    history.prune(value, fn(entry) {
      entry != "obsolete" && entry != "old redo"
    })
  pruned |> expect.to_equal(history.History(["latest"], ["redo"]))
  let history.Routed(cleared, dispose) = history.clear(pruned)
  dispose |> expect.to_equal(["latest", "redo"])
  history.next_undo(cleared) |> expect.to_equal(None)
  history.next_redo(cleared) |> expect.to_equal(None)
  history.clear(cleared) |> expect.to_equal(history.Routed(cleared, []))
  history.consume_undo(cleared) |> expect.to_equal(cleared)
  history.consume_redo(cleared) |> expect.to_equal(cleared)
}

pub fn tree_api_history_uses_application_owned_canonical_revertibles_test() {
  let definition = fixture.card_schema()
  let assert Ok(compiled) = definition.node |> builder.root |> builder.compile
  let initial = fixture.Card(builder.Assigned("original"), "First")
  let #(document, tree) = fixture.tree(compiled, initial)
  let assert Ok(root) = tree.required_root(tree)
  let #(record, take) = fixture.capture()
  let #(disposed, take_disposed) = fixture.capture()
  let assert Ok(subscription) =
    tree.subscribe_commits(tree, fn(event) {
      let assert Ok(revertible) = tree.get_revertible(event, disposed)
      record(#(event.kind, event.local, revertible))
    })
  tree.set(root, definition.title, "Updated") |> expect.to_equal(Ok(Nil))
  let assert [#(kind, local, original)] = take(1)
  let assert history.Routed(stack, []) =
    history.route(history.new(), kind, local, Some(original))
  let assert Some(undo) = history.next_undo(stack)
  tree.revert(undo, tree.DisposeRevertible) |> expect.to_equal(Ok(Nil))
  let stack = history.consume_undo(stack)
  let assert [#(kind, local, redo)] = take(1)
  let assert history.Routed(stack, []) =
    history.route(stack, kind, local, Some(redo))
  tree.read_root(tree) |> expect.to_equal(Ok(initial))
  history.next_undo(stack) |> expect.to_equal(None)
  history.next_redo(stack) |> expect.to_equal(Some(redo))
  let assert [removed] = take_disposed(1)
  tree.revertible_revision(removed)
  |> expect.to_equal(tree.revertible_revision(original))
  tree.dispose_revertible(redo) |> expect.to_equal(Ok(Nil))
  let assert Error(_) = tree.revert(redo, tree.DisposeRevertible)
  history.next_redo(stack) |> expect.to_equal(Some(redo))
  let assert [removed] = take_disposed(1)
  let stack =
    history.prune(stack, fn(entry) {
      tree.revertible_revision(entry) != tree.revertible_revision(removed)
    })
  history.next_redo(stack) |> expect.to_equal(None)
  history.clear(stack) |> expect.to_equal(history.Routed(history.new(), []))
  tree.unsubscribe(subscription)
  facade.close(document)
}
