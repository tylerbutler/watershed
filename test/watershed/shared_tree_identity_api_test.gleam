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

fn card(title: String) -> fixture.Card {
  fixture.Card(builder.Assigned("duplicate"), title)
}

fn cards() {
  let definition = fixture.card_schema()
  let assert Ok(compiled) =
    builder.array(builder.factory("identity"), "Cards", definition.node)
    |> builder.root
    |> builder.compile
  #(compiled, definition)
}

pub fn tree_api_remove_node_follows_identity_after_remote_insertion_test() {
  let #(compiled, _) = cards()
  let initial = [card("A"), card("B")]
  let #(document, native, deliver) =
    fixture.tree_with_operations(compiled, initial)
  let assert Ok(tree) = facade.tree_typed(native, compiled)
  let assert Ok(items) = tree.required_root(tree)
  let assert Ok(Some(selected)) = tree.array_node(items, 1)
  let assert Ok(Some(types.ArrayValue(_, [inserted]))) =
    builder.encode(compiled, [card("Remote")])
  deliver([
    fixture.remote_edit(compiled, initial, types.ArrayInsert([], 0, [inserted])),
  ])
  let assert Ok(Some(first)) = tree.array_node(items, 1)
  tree.array_move_before(items, selected, items, Some(first))
  |> expect.to_equal(Ok(Nil))
  tree.read_root(tree)
  |> expect.to_equal(Ok([card("Remote"), card("B"), card("A")]))
  tree.array_remove_node(items, selected) |> expect.to_equal(Ok(Nil))
  tree.read_root(tree) |> expect.to_equal(Ok([card("Remote"), card("A")]))
  tree.status(selected) |> expect.to_equal(Ok(error.Removed))
  facade.close(document)
}

pub fn tree_api_move_before_preserves_identity_and_supports_append_test() {
  let #(compiled, definition) = cards()
  let #(document, native) =
    fixture.tree(compiled, [card("A"), card("B"), card("C")])
  let assert Ok(tree) = facade.tree_typed(native, compiled)
  let assert Ok(items) = tree.required_root(tree)
  let assert Ok(Some(a)) = tree.array_node(items, 0)
  let assert Ok(Some(b)) = tree.array_node(items, 1)
  tree.array_move_before(items, b, items, Some(a))
  |> expect.to_equal(Ok(Nil))
  tree.read_root(tree) |> expect.to_equal(Ok([card("B"), card("A"), card("C")]))
  tree.array_move_before(items, b, items, None) |> expect.to_equal(Ok(Nil))
  tree.read_root(tree) |> expect.to_equal(Ok([card("A"), card("C"), card("B")]))
  tree.get(b, definition.title) |> expect.to_equal(Ok("B"))
  tree.array_move_before(items, b, items, Some(b))
  |> expect.to_equal(Ok(Nil))
  tree.read_root(tree) |> expect.to_equal(Ok([card("A"), card("C"), card("B")]))
  facade.close(document)
}

type Board {
  Board(left: List(fixture.Card), right: List(fixture.Card))
}

fn board() {
  let definition = fixture.card_schema()
  let factory = builder.factory("identity")
  let items = builder.array(factory, "Cards", definition.node)
  let left = builder.required("left", items, fn(board: Board) { board.left })
  let right = builder.required("right", items, fn(board: Board) { board.right })
  let assert Ok(compiled) =
    builder.object2(factory, "Board", Board, left, right)
    |> builder.root
    |> builder.compile
  let #(document, native) =
    fixture.tree(compiled, Board([card("A")], [card("B")]))
  let assert Ok(tree) = facade.tree_typed(native, compiled)
  let assert Ok(root) = tree.required_root(tree)
  let assert Ok(left) = tree.child(root, left)
  let assert Ok(right) = tree.child(root, right)
  let assert Ok(Some(a)) = tree.array_node(left, 0)
  let assert Ok(Some(b)) = tree.array_node(right, 0)
  #(document, tree, left, right, a, b)
}

pub fn tree_api_move_between_arrays_rejects_non_child_without_mutation_test() {
  let #(document, tree, left, right, a, b) = board()
  tree.array_move_before(left, a, right, Some(b)) |> expect.to_equal(Ok(Nil))
  tree.read(a) |> expect.to_equal(Ok(card("A")))
  tree.read_root(tree)
  |> expect.to_equal(Ok(Board([], [card("A"), card("B")])))
  tree.array_remove_node(left, a)
  |> expect.to_equal(
    Error(
      error.InvalidValue(types.InvalidEdit(
        ["left"],
        "node is not a direct array child",
      )),
    ),
  )
  tree.array_move_before(right, b, left, Some(a))
  |> expect.to_equal(
    Error(
      error.InvalidValue(types.InvalidEdit(
        ["left"],
        "node is not a direct array child",
      )),
    ),
  )
  tree.read_root(tree)
  |> expect.to_equal(Ok(Board([], [card("A"), card("B")])))
  facade.close(document)
}

pub fn tree_api_identity_edits_reject_foreign_and_removed_refs_test() {
  let #(document, tree, left, right, a, b) = board()
  let #(other_document, other_tree, other_left, _, other_a, _) = board()
  tree.array_remove_node(left, other_a)
  |> expect.to_equal(Error(error.ForeignOrigin))
  tree.array_move_before(left, a, other_left, None)
  |> expect.to_equal(Error(error.ForeignOrigin))
  tree.array_move_before(left, a, right, Some(other_a))
  |> expect.to_equal(Error(error.ForeignOrigin))
  tree.array_remove_node(right, b) |> expect.to_equal(Ok(Nil))
  tree.array_move_before(left, a, right, Some(b))
  |> expect.to_equal(Error(error.InvalidReference(error.Removed)))
  tree.read_root(tree) |> expect.to_equal(Ok(Board([card("A")], [])))
  tree.read_root(other_tree)
  |> expect.to_equal(Ok(Board([card("A")], [card("B")])))
  facade.close(document)
  facade.close(other_document)
}

pub fn tree_api_identity_edits_rollback_with_the_transaction_test() {
  let #(document, tree, left, right, a, _) = board()
  tree.transaction(tree, [tree.node_in_document(a)], fn(_) {
    tree.array_move_before(left, a, right, None) |> expect.to_equal(Ok(Nil))
    tree.array_remove_node(right, a) |> expect.to_equal(Ok(Nil))
    Error("cancel")
  })
  |> expect.to_equal(Error(tree.Aborted("cancel")))
  tree.read_root(tree)
  |> expect.to_equal(Ok(Board([card("A")], [card("B")])))
  tree.status(a) |> expect.to_equal(Ok(error.Attached))
  tree.array_remove_node(left, a) |> expect.to_equal(Ok(Nil))
  tree.read_root(tree) |> expect.to_equal(Ok(Board([], [card("B")])))
  facade.close(document)
}

pub fn tree_api_rejected_identity_edit_sends_no_operation_test() {
  let #(compiled, _) = cards()
  let #(record, take) = fixture.capture()
  let #(document, native, _) =
    fixture.tree_with_submissions(compiled, [card("A")], record)
  let assert Ok(tree) = facade.tree_typed(native, compiled)
  let assert Ok(items) = tree.required_root(tree)
  let assert Ok(Some(item)) = tree.array_node(items, 0)
  let assert Ok(branch) = tree.fork(tree)
  let assert Ok(branch_items) = tree.required_root(branch)
  let assert Ok(Some(branch_item)) = tree.array_node(branch_items, 0)
  tree.array_remove_node(items, branch_item)
  |> expect.to_equal(Error(error.ForeignOrigin))
  tree.array_move_before(items, item, branch_items, None)
  |> expect.to_equal(Error(error.ForeignOrigin))
  tree.read_root(tree) |> expect.to_equal(Ok([card("A")]))
  tree.read_root(branch) |> expect.to_equal(Ok([card("A")]))
  tree.dispose(branch) |> expect.to_equal(Ok(Nil))
  tree.array_remove_node(branch_items, branch_item)
  |> expect.to_equal(Error(error.ClosedTree))
  take(0) |> expect.to_equal([])
  facade.close(document)
}
