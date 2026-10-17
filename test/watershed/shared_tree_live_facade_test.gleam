import gleam/dict.{type Dict}
@target(erlang)
import gleam/erlang/process
import gleam/option.{type Option, None, Some}
import startest/expect
@target(javascript)
import watershed as facade
import watershed/tree as live
import watershed/tree/error as tree_error
import watershed/tree/live_fixture as fixture
import watershed/tree/schema_builder as builder
import watershed/tree/types
@target(erlang)
import watershed_beam as facade

pub fn typed_live_root_and_properties_test() {
  let schema = fixture.card_schema()
  let assert Ok(compiled) = builder.compile(builder.root(schema.node))
  let initial = fixture.Card(builder.Assigned("original"), "First")
  let #(document, tree) = fixture.tree(compiled, initial)
  let view = tree
  live.read_root(view) |> expect.to_equal(Ok(initial))
  let assert Ok(card) = live.required_root(view)
  live.get(card, schema.id) |> expect.to_equal(Ok(builder.Assigned("original")))
  live.set(card, schema.title, "Updated") |> expect.to_equal(Ok(Nil))
  live.get(card, schema.title) |> expect.to_equal(Ok("Updated"))
  live.read(card)
  |> expect.to_equal(Ok(fixture.Card(builder.Assigned("original"), "Updated")))
  live.set(card, schema.id, builder.Assigned("changed")) |> expect.to_be_error
  let wrong =
    builder.required("other", builder.string(), fn(card: fixture.Card) {
      card.title
    })
  live.set(card, wrong, "wrong")
  |> expect.to_equal(Error(tree_error.WrongProperty("other")))
  live.get(card, schema.title) |> expect.to_equal(Ok("Updated"))
  facade.close(document)
}

type Board {
  Board(
    cards: List(fixture.Card),
    by_key: Dict(String, fixture.Card),
    selected: Option(fixture.Card),
  )
}

fn board_schema() {
  let card = fixture.card_schema()
  let factory = builder.factory("typed.test")
  let cards =
    builder.required(
      "cards",
      builder.array(factory, "Cards", card.node),
      fn(board: Board) { board.cards },
    )
  let by_key =
    builder.required(
      "byKey",
      builder.map(factory, "ByKey", card.node),
      fn(board: Board) { board.by_key },
    )
  let selected =
    builder.optional("selected", card.node, fn(board: Board) { board.selected })
  let node = builder.object3(factory, "Board", Board, cards, by_key, selected)
  let assert Ok(compiled) = builder.compile(builder.root(node))
  #(compiled, card, cards, by_key, selected)
}

pub fn typed_live_collection_navigation_follows_other_handle_edits_test() {
  let #(compiled, card, cards_property, map_property, selected_property) =
    board_schema()
  let a = fixture.Card(builder.Assigned("duplicate"), "A")
  let b = fixture.Card(builder.Assigned("duplicate"), "B")
  let #(document, tree) =
    fixture.tree(compiled, Board([a, b], dict.new(), None))
  let view = tree
  let assert Ok(root) = live.required_root(view)
  let assert Ok(cards) = live.child(root, cards_property)
  let assert Ok(Some(saved)) = live.array_node(cards, 1)
  let assert Ok(other) = fixture.open(document, compiled)
  let assert Ok(other_root) = live.required_root(other)
  let assert Ok(other_cards) = live.child(other_root, cards_property)
  live.array_insert(other_cards, 0, [
    fixture.Card(builder.Assigned("inserted"), "Inserted"),
  ])
  |> expect.to_equal(Ok(Nil))
  live.set(saved, card.title, "Edited") |> expect.to_equal(Ok(Nil))
  live.array_get(cards, 1) |> expect.to_equal(Ok(Some(a)))
  live.array_get(cards, 2)
  |> expect.to_equal(
    Ok(Some(fixture.Card(builder.Assigned("duplicate"), "Edited"))),
  )
  let assert Ok(by_key) = live.child(root, map_property)
  live.map_set(by_key, "a/b.0", a) |> expect.to_equal(Ok(Nil))
  let assert Ok(Some(entry)) = live.map_node(by_key, "a/b.0")
  live.set(entry, card.title, "Mapped") |> expect.to_equal(Ok(Nil))
  live.map_get(by_key, "a/b.0")
  |> expect.to_equal(
    Ok(Some(fixture.Card(builder.Assigned("duplicate"), "Mapped"))),
  )
  live.optional_child(root, selected_property) |> expect.to_equal(Ok(None))
  live.set(root, selected_property, Some(b)) |> expect.to_equal(Ok(Nil))
  let assert Ok(Some(selected)) = live.optional_child(root, selected_property)
  live.read(selected) |> expect.to_equal(Ok(b))
  live.set(root, selected_property, None) |> expect.to_equal(Ok(Nil))
  live.status(selected) |> expect.to_equal(Ok(tree_error.Removed))
  live.array_remove(cards, 2, 3) |> expect.to_equal(Ok(Nil))
  live.read(saved)
  |> expect.to_equal(Error(tree_error.InvalidReference(tree_error.Removed)))
  facade.close(document)
}

pub fn typed_live_construction_and_disposal_test() {
  let schema = fixture.card_schema()
  let assert Ok(compiled) = builder.compile(builder.root(schema.node))
  let #(document, tree) =
    fixture.tree(compiled, fixture.Card(builder.Assigned("original"), "First"))
  let view = tree
  let assert Ok(before) = live.required_root(view)
  live.replace_root(view, fixture.Card(builder.Generate, "New"))
  |> expect.to_be_error
  live.replace_root_new(view, fixture.Card(builder.Generate, "New"))
  |> expect.to_equal(Ok(Nil))
  let assert Ok(fixture.Card(builder.Assigned(_), "New")) = live.read_root(view)
  live.status(before) |> expect.to_equal(Ok(tree_error.Removed))
  live.dispose(view) |> expect.to_equal(Ok(Nil))
  live.dispose(view) |> expect.to_equal(Ok(Nil))
  live.read_root(view) |> expect.to_equal(Error(tree_error.ClosedTree))
  let assert Ok(other) = fixture.open(document, compiled)
  let assert Ok(_) = live.read_root(other)
  facade.close(document)
  live.read_root(other) |> expect.to_equal(Error(tree_error.ClosedRuntime))
}

pub fn typed_live_observation_reads_committed_state_and_cancels_test() {
  let schema = fixture.card_schema()
  let assert Ok(compiled) = builder.compile(builder.root(schema.node))
  let initial = fixture.Card(builder.Assigned("original"), "First")
  let #(document, tree) = fixture.tree(compiled, initial)
  let assert Ok(view) = fixture.open(document, compiled)
  let assert Ok(card) = live.required_root(view)
  let #(record, take) = fixture.capture()
  let assert Ok(subscription) = live.observe(view, record)
  take(0) |> expect.to_equal([])
  live.set(card, schema.title, "Updated") |> expect.to_equal(Ok(Nil))
  take(1)
  |> expect.to_equal([Ok(fixture.Card(builder.Assigned("original"), "Updated"))])
  live.unsubscribe(subscription)
  live.unsubscribe(subscription)
  live.set(card, schema.title, "Unobserved") |> expect.to_equal(Ok(Nil))
  let assert Ok(_) = live.read_root(tree)
  take(0) |> expect.to_equal([])
  let assert Ok(_) = live.observe(view, record)
  live.dispose(view) |> expect.to_equal(Ok(Nil))
  let assert Ok(other_card) = live.required_root(tree)
  live.set(other_card, schema.title, "After disposal")
  |> expect.to_equal(Ok(Nil))
  let assert Ok(_) = live.read_root(tree)
  take(0) |> expect.to_equal([])
  facade.close(document)
}

pub fn typed_live_optional_root_and_primitive_root_test() {
  let card = fixture.card_schema()
  let assert Ok(compiled) = builder.compile(builder.optional_root(card.node))
  let initial = fixture.Card(builder.Assigned("original"), "First")
  let #(document, tree) = fixture.tree(compiled, Some(initial))
  let view = tree
  live.required_root(view)
  |> expect.to_equal(Error(tree_error.WrongCardinality))
  let assert Ok(Some(reference)) = live.optional_root(view)
  live.read(reference) |> expect.to_equal(Ok(initial))
  live.replace_root(view, None) |> expect.to_equal(Ok(Nil))
  live.read_root(view) |> expect.to_equal(Ok(None))
  live.optional_root(view) |> expect.to_equal(Ok(None))
  live.status(reference) |> expect.to_equal(Ok(tree_error.Removed))
  facade.close(document)
  let assert Ok(compiled) = builder.compile(builder.root(builder.string()))
  let #(document, tree) = fixture.tree(compiled, "First")
  let view = tree
  live.read_root(view) |> expect.to_equal(Ok("First"))
  live.required_root(view)
  |> expect.to_equal(
    Error(tree_error.WrongKind("composite", "com.fluidframework.leaf.string")),
  )
  live.replace_root(view, "Updated") |> expect.to_equal(Ok(Nil))
  live.read_root(view) |> expect.to_equal(Ok("Updated"))
  facade.close(document)
}

pub fn typed_live_collection_construction_modes_test() {
  let #(compiled, card, cards_property, map_property, selected_property) =
    board_schema()
  let #(document, tree) = fixture.tree(compiled, Board([], dict.new(), None))
  let view = tree
  let assert Ok(root) = live.required_root(view)
  let assert Ok(cards) = live.child(root, cards_property)
  let generated = fixture.Card(builder.Generate, "Generated")
  live.array_insert(cards, 0, [generated]) |> expect.to_be_error
  live.array_get(cards, 0) |> expect.to_equal(Ok(None))
  live.array_insert_new(cards, 0, [generated, generated])
  |> expect.to_equal(Ok(Nil))
  let assert Ok(Some(fixture.Card(builder.Assigned(first), _))) =
    live.array_get(cards, 0)
  let assert Ok(Some(fixture.Card(builder.Assigned(second), _))) =
    live.array_get(cards, 1)
  expect.to_equal(first == second, False)
  let assert Ok(Some(saved)) = live.array_node(cards, 0)
  live.array_move(cards, 0, 1, cards, 2) |> expect.to_equal(Ok(Nil))
  live.get(saved, card.id) |> expect.to_equal(Ok(builder.Assigned(first)))
  let assert Ok(Some(moved)) = live.array_node(cards, 1)
  live.get(moved, card.id) |> expect.to_equal(Ok(builder.Assigned(first)))
  let assert Ok(by_key) = live.child(root, map_property)
  live.map_set(by_key, "", generated) |> expect.to_be_error
  live.map_set_new(by_key, "", generated) |> expect.to_equal(Ok(Nil))
  let assert Ok(Some(fixture.Card(builder.Assigned(_), "Generated"))) =
    live.map_get(by_key, "")
  live.map_delete(by_key, "") |> expect.to_equal(Ok(Nil))
  live.map_get(by_key, "") |> expect.to_equal(Ok(None))
  live.set_new(root, selected_property, Some(generated))
  |> expect.to_equal(Ok(Nil))
  let assert Ok(Some(selected)) = live.optional_child(root, selected_property)
  let assert Ok(fixture.Card(builder.Assigned(_), "Generated")) =
    live.read(selected)
  facade.close(document)
}

pub fn typed_live_leaf_collections_do_not_issue_refs_test() {
  let node =
    builder.array(builder.factory("typed.test"), "Strings", builder.string())
  let assert Ok(compiled) = builder.compile(builder.root(node))
  let #(document, tree) = fixture.tree(compiled, ["a"])
  let view = tree
  let assert Ok(array) = live.required_root(view)
  live.array_get(array, 0) |> expect.to_equal(Ok(Some("a")))
  live.array_node(array, 0) |> expect.to_be_error
  live.array_node(array, 1) |> expect.to_equal(Ok(None))
  live.array_insert(array, 1, ["b", "c"]) |> expect.to_equal(Ok(Nil))
  live.read(array) |> expect.to_equal(Ok(["a", "b", "c"]))
  facade.close(document)
  let node =
    builder.map(builder.factory("typed.test"), "StringsByKey", builder.string())
  let assert Ok(compiled) = builder.compile(builder.root(node))
  let #(document, tree) = fixture.tree(compiled, dict.from_list([#("a", "b")]))
  let view = tree
  let assert Ok(map) = live.required_root(view)
  live.map_get(map, "a") |> expect.to_equal(Ok(Some("b")))
  live.map_node(map, "a") |> expect.to_be_error
  live.map_node(map, "missing") |> expect.to_equal(Ok(None))
  facade.close(document)
}

type Choice {
  CardChoice(fixture.Card)
  TextChoice(String)
}

fn choice_node(card: builder.Node(fixture.Card)) -> builder.Node(Choice) {
  builder.union([
    builder.variant(card, CardChoice, fn(choice) {
      case choice {
        CardChoice(card) -> Some(card)
        TextChoice(_) -> None
      }
    }),
    builder.variant(builder.string(), TextChoice, fn(choice) {
      case choice {
        TextChoice(text) -> Some(text)
        CardChoice(_) -> None
      }
    }),
  ])
}

pub fn typed_live_narrow_keeps_composite_identity_test() {
  let card = fixture.card_schema()
  let node = choice_node(card.node)
  let assert Ok(compiled) = builder.compile(builder.root(node))
  let initial = fixture.Card(builder.Assigned("original"), "First")
  let #(document, tree) = fixture.tree(compiled, CardChoice(initial))
  let view = tree
  let assert Ok(reference) = live.required_root(view)
  let assert Ok(Some(narrowed)) = live.narrow(reference, card.node)
  live.narrow(reference, builder.string()) |> expect.to_equal(Ok(None))
  live.set(narrowed, card.title, "Updated") |> expect.to_equal(Ok(Nil))
  live.read(reference)
  |> expect.to_equal(
    Ok(CardChoice(fixture.Card(builder.Assigned("original"), "Updated"))),
  )
  live.replace_root(view, TextChoice("Leaf")) |> expect.to_equal(Ok(Nil))
  live.status(narrowed) |> expect.to_equal(Ok(tree_error.Removed))
  live.read_root(view) |> expect.to_equal(Ok(TextChoice("Leaf")))
  facade.close(document)
}

pub fn typed_live_node_observer_reports_removal_test() {
  let #(compiled, _, cards_property, _, _) = board_schema()
  let #(document, tree) =
    fixture.tree(
      compiled,
      Board(
        [fixture.Card(builder.Assigned("original"), "First")],
        dict.new(),
        None,
      ),
    )
  let view = tree
  let assert Ok(root) = live.required_root(view)
  let assert Ok(cards) = live.child(root, cards_property)
  let assert Ok(Some(card)) = live.array_node(cards, 0)
  let #(record, take) = fixture.capture()
  let assert Ok(subscription) = live.observe_node(card, record)
  let assert Ok(other) = fixture.open(document, compiled)
  let assert Ok(other_root) = live.required_root(other)
  let assert Ok(other_cards) = live.child(other_root, cards_property)
  live.array_remove(other_cards, 0, 1)
  |> expect.to_equal(Ok(Nil))
  take(1)
  |> expect.to_equal([Error(tree_error.InvalidReference(tree_error.Removed))])
  live.unsubscribe(subscription)
  facade.close(document)
}

pub fn typed_live_move_refuses_another_runtime_with_the_same_client_id_test() {
  let node =
    builder.array(builder.factory("typed.test"), "Strings", builder.string())
  let assert Ok(compiled) = builder.compile(builder.root(node))
  let #(first_document, first_tree) = fixture.tree(compiled, ["first"])
  let #(second_document, second_tree) = fixture.tree(compiled, ["second"])
  let first_view = first_tree
  let second_view = second_tree
  let assert Ok(first) = live.required_root(first_view)
  let assert Ok(second) = live.required_root(second_view)
  live.array_move(first, 0, 1, second, 1)
  |> expect.to_equal(Error(tree_error.ForeignOrigin))
  live.read(first) |> expect.to_equal(Ok(["first"]))
  live.read(second) |> expect.to_equal(Ok(["second"]))
  facade.close(first_document)
  facade.close(second_document)
}

pub fn typed_live_transaction_abort_does_not_poison_new_refs_test() {
  let #(compiled, _, cards_property, _, _) = board_schema()
  let #(document, tree) = fixture.tree(compiled, Board([], dict.new(), None))
  let view = tree
  let assert Ok(root) = live.required_root(view)
  let assert Ok(cards) = live.child(root, cards_property)
  let #(record, take) = fixture.capture()
  let outcome =
    live.transaction(tree, [], fn(_) {
      live.array_insert_new(cards, 0, [
        fixture.Card(builder.Generate, "Aborted"),
      ])
      |> expect.to_equal(Ok(Nil))
      let assert Ok(Some(preview)) = live.array_node(cards, 0)
      record(preview)
      Error(Nil)
    })
  outcome |> expect.to_be_error
  let assert [preview] = take(1)
  live.status(preview) |> expect.to_equal(Ok(tree_error.Invalidated))
  live.array_insert_new(cards, 0, [
    fixture.Card(builder.Generate, "Replacement"),
  ])
  |> expect.to_equal(Ok(Nil))
  let assert Ok(Some(replacement)) = live.array_node(cards, 0)
  live.status(replacement) |> expect.to_equal(Ok(tree_error.Attached))
  let assert Ok(fixture.Card(builder.Assigned(_), "Replacement")) =
    live.read(replacement)
  live.status(preview) |> expect.to_equal(Ok(tree_error.Invalidated))
  facade.close(document)
}

pub fn typed_live_equal_replacements_do_not_retarget_old_refs_test() {
  let #(compiled, _, _, map_property, selected_property) = board_schema()
  let card = fixture.Card(builder.Assigned("duplicate"), "Same")
  let initial = Board([], dict.from_list([#("key", card)]), Some(card))
  let #(document, tree) = fixture.tree(compiled, initial)
  let view = tree
  let assert Ok(root) = live.required_root(view)
  let assert Ok(Some(selected)) = live.optional_child(root, selected_property)
  let assert Ok(by_key) = live.child(root, map_property)
  let assert Ok(Some(entry)) = live.map_node(by_key, "key")
  live.set(root, selected_property, Some(card)) |> expect.to_equal(Ok(Nil))
  live.status(selected) |> expect.to_equal(Ok(tree_error.Removed))
  let assert Ok(Some(replacement)) =
    live.optional_child(root, selected_property)
  live.status(replacement) |> expect.to_equal(Ok(tree_error.Attached))
  live.map_set(by_key, "key", card) |> expect.to_equal(Ok(Nil))
  live.status(entry) |> expect.to_equal(Ok(tree_error.Removed))
  let assert Ok(Some(replacement_entry)) = live.map_node(by_key, "key")
  live.status(replacement_entry) |> expect.to_equal(Ok(tree_error.Attached))
  live.replace_root(view, initial) |> expect.to_equal(Ok(Nil))
  live.status(root) |> expect.to_equal(Ok(tree_error.Removed))
  live.status(replacement) |> expect.to_equal(Ok(tree_error.Removed))
  live.status(replacement_entry) |> expect.to_equal(Ok(tree_error.Removed))
  let assert Ok(current) = live.required_root(view)
  live.status(current) |> expect.to_equal(Ok(tree_error.Attached))
  live.read(current) |> expect.to_equal(Ok(initial))
  facade.close(document)
}

pub fn typed_live_observation_excludes_transaction_previews_test() {
  let card = fixture.card_schema()
  let assert Ok(compiled) = builder.compile(builder.root(card.node))
  let initial = fixture.Card(builder.Assigned("original"), "First")
  let #(document, tree) = fixture.tree(compiled, initial)
  let view = tree
  let assert Ok(reference) = live.required_root(view)
  let #(record, take) = fixture.capture()
  let assert Ok(subscription) = live.observe(view, record)
  live.transaction(tree, [], fn(_) {
    live.set(reference, card.title, "Preview") |> expect.to_equal(Ok(Nil))
    take(0) |> expect.to_equal([])
    live.set(reference, card.title, "Committed") |> expect.to_equal(Ok(Nil))
    take(0) |> expect.to_equal([])
    Ok(Nil)
  })
  |> expect.to_equal(Ok(Nil))
  take(1)
  |> expect.to_equal([
    Ok(fixture.Card(builder.Assigned("original"), "Committed")),
  ])
  live.transaction(tree, [], fn(_) {
    live.set(reference, card.title, "Aborted") |> expect.to_equal(Ok(Nil))
    take(0) |> expect.to_equal([])
    Error(Nil)
  })
  |> expect.to_be_error
  take(0) |> expect.to_equal([])
  live.get(reference, card.title) |> expect.to_equal(Ok("Committed"))
  live.unsubscribe(subscription)
  facade.close(document)
}

pub fn typed_live_disposal_cancels_captured_and_late_observers_test() {
  let card = fixture.card_schema()
  let assert Ok(compiled) = builder.compile(builder.root(card.node))
  let #(document, tree) =
    fixture.tree(compiled, fixture.Card(builder.Assigned("original"), "First"))
  let first = tree
  let assert Ok(second) = fixture.open(document, compiled)
  let assert Ok(reference) = live.required_root(first)
  let #(record, take) = fixture.capture()
  let assert Ok(_) = live.observe(second, fn(_) { record("captured") })
  let assert Ok(subscription) =
    live.observe(first, fn(_) {
      let assert Ok(_) = live.observe(second, fn(_) { record("late") })
      live.dispose(second) |> expect.to_equal(Ok(Nil))
      record("first")
    })
  live.transaction(tree, [], fn(_) {
    live.set(reference, card.title, "Updated")
  })
  |> expect.to_equal(Ok(Nil))
  take(1) |> expect.to_equal(["first"])
  live.unsubscribe(subscription)
  live.set(reference, card.title, "Unobserved") |> expect.to_equal(Ok(Nil))
  let assert Ok(_) = live.read_root(tree)
  take(0) |> expect.to_equal([])
  live.read_root(second) |> expect.to_equal(Error(tree_error.ClosedTree))
  facade.close(document)
}

pub fn typed_live_observers_report_incompatible_schema_upgrade_test() {
  let card = fixture.card_schema()
  let assert Ok(compiled) = builder.compile(builder.root(card.node))
  let initial = fixture.Card(builder.Assigned("original"), "First")
  let #(document, tree) = fixture.tree(compiled, initial)
  let view = tree
  let assert Ok(reference) = live.required_root(view)
  let #(record, take) = fixture.capture()
  let assert Ok(_) = live.observe(view, fn(value) { record(value) })
  let assert Ok(_) = live.observe_node(reference, fn(value) { record(value) })
  let assert Ok(broader) = builder.compile(builder.root(choice_node(card.node)))
  let assert Ok(root) = facade.resolve_root(document)
  let assert Ok(marker) = facade.get(root, "tree")
  let assert Ok(upgraded) = fixture.inspect(document, marker, broader)
  live.upgrade_schema(upgraded) |> expect.to_equal(Ok(Nil))
  take(2)
  |> expect.to_equal([
    Error(tree_error.IncompatibleView),
    Error(tree_error.IncompatibleView),
  ])
  live.read(reference) |> expect.to_equal(Error(tree_error.IncompatibleView))
  live.dispose(view) |> expect.to_equal(Ok(Nil))
  live.read_root(upgraded) |> expect.to_equal(Ok(CardChoice(initial)))
  facade.close(document)
}

pub fn typed_live_branch_disposal_cancels_its_observers_test() {
  let node =
    builder.array(builder.factory("typed.test"), "Strings", builder.string())
  let assert Ok(compiled) = builder.compile(builder.root(node))
  let #(document, tree) = fixture.tree(compiled, ["first"])
  let assert Ok(branch) = live.fork(tree)
  let document_view = tree
  let branch_view = branch
  let assert Ok(document_root) = live.required_root(document_view)
  let assert Ok(branch_root) = live.required_root(branch_view)
  live.array_move(branch_root, 0, 1, document_root, 1)
  |> expect.to_equal(Error(tree_error.ForeignOrigin))
  let #(record, take) = fixture.capture()
  let assert Ok(_) = live.observe(branch_view, record)
  live.array_insert(branch_root, 1, ["branch"]) |> expect.to_equal(Ok(Nil))
  take(1) |> expect.to_equal([Ok(["first", "branch"])])
  live.merge(tree, branch, live.DisposeSource) |> expect.to_equal(Ok(Nil))
  live.read(document_root) |> expect.to_equal(Ok(["first", "branch"]))
  live.read(branch_root) |> expect.to_equal(Error(tree_error.DisposedCheckout))
  take(0) |> expect.to_equal([])
  facade.close(document)
}

pub fn typed_live_observer_failure_keeps_the_runtime_usable_test() {
  let card = fixture.card_schema()
  let assert Ok(compiled) = builder.compile(builder.root(card.node))
  let #(document, tree) =
    fixture.tree(compiled, fixture.Card(builder.Assigned("original"), "First"))
  let view = tree
  let assert Ok(reference) = live.required_root(view)
  let #(record, take) = fixture.capture()
  let assert Ok(subscription) =
    live.observe(view, fn(_) {
      record(Nil)
      panic as "typed observer failure"
    })
  live.set(reference, card.title, "Committed") |> expect.to_equal(Ok(Nil))
  take(1) |> expect.to_equal([Nil])
  live.unsubscribe(subscription)
  live.get(reference, card.title) |> expect.to_equal(Ok("Committed"))
  live.set(reference, card.title, "Still usable") |> expect.to_equal(Ok(Nil))
  live.get(reference, card.title) |> expect.to_equal(Ok("Still usable"))
  facade.close(document)
}

pub fn typed_live_observer_cannot_write_reentrantly_test() {
  let card = fixture.card_schema()
  let assert Ok(compiled) = builder.compile(builder.root(card.node))
  let #(document, tree) =
    fixture.tree(compiled, fixture.Card(builder.Assigned("original"), "First"))
  let view = tree
  let assert Ok(reference) = live.required_root(view)
  let #(record, take) = fixture.capture()
  let assert Ok(subscription) =
    live.observe(view, fn(snapshot) {
      case snapshot {
        Ok(fixture.Card(_, "Committed")) ->
          record(live.set(reference, card.title, "Reentrant"))
        _ -> Nil
      }
    })
  live.set(reference, card.title, "Committed") |> expect.to_equal(Ok(Nil))
  let assert [Error(tree_error.ReentrantEdit)] = take(1)
  live.unsubscribe(subscription)
  live.get(reference, card.title) |> expect.to_equal(Ok("Committed"))
  facade.close(document)
}

@target(erlang)
pub fn typed_live_transaction_preview_is_hidden_from_another_caller_test() {
  let card = fixture.card_schema()
  let assert Ok(compiled) = builder.compile(builder.root(card.node))
  let #(document, tree) =
    fixture.tree(compiled, fixture.Card(builder.Assigned("original"), "First"))
  let view = tree
  let assert Ok(reference) = live.required_root(view)
  let #(record, take) = fixture.capture()
  live.transaction(tree, [], fn(_) {
    live.set(reference, card.title, "Preview") |> expect.to_equal(Ok(Nil))
    let _ = process.spawn_unlinked(fn() { record(live.read_root(view)) })
    take(1)
    |> expect.to_equal([
      Error(tree_error.TransactionConflict(
        "tree transaction uses another caller",
      )),
    ])
    Ok(Nil)
  })
  |> expect.to_equal(Ok(Nil))
  live.get(reference, card.title) |> expect.to_equal(Ok("Preview"))
  facade.close(document)
}

pub fn typed_live_failed_edit_invalidates_only_preview_nodes_test() {
  let #(compiled, _, cards_property, _, _) = board_schema()
  let original = fixture.Card(builder.Assigned("original"), "First")
  let #(document, tree) =
    fixture.tree(compiled, Board([original], dict.new(), None))
  let view = tree
  let assert Ok(root) = live.required_root(view)
  let assert Ok(cards) = live.child(root, cards_property)
  let assert Ok(Some(existing)) = live.array_node(cards, 0)
  let #(record, take) = fixture.capture()
  live.transaction(tree, [], fn(_) {
    live.array_insert_new(cards, 1, [
      fixture.Card(builder.Generate, "Preview"),
    ])
    |> expect.to_equal(Ok(Nil))
    let assert Ok(Some(preview)) = live.array_node(cards, 1)
    record(preview)
    live.array_remove(cards, 2, 3)
  })
  |> expect.to_be_error
  let assert [preview] = take(1)
  live.status(preview) |> expect.to_equal(Ok(tree_error.Invalidated))
  live.status(existing) |> expect.to_equal(Ok(tree_error.Attached))
  live.read(existing) |> expect.to_equal(Ok(original))
  live.read(cards) |> expect.to_equal(Ok([original]))
  facade.close(document)
}

pub fn typed_live_remote_observer_cannot_write_reentrantly_test() {
  let card = fixture.card_schema()
  let assert Ok(compiled) = builder.compile(builder.root(card.node))
  let initial = fixture.Card(builder.Assigned("original"), "First")
  let #(document, tree, deliver) =
    fixture.tree_with_operations(compiled, initial)
  let view = tree
  let assert Ok(reference) = live.required_root(view)
  let #(record, take) = fixture.capture()
  let assert Ok(subscription) =
    live.observe(view, fn(snapshot) {
      case snapshot {
        Ok(fixture.Card(_, "Remote")) ->
          record(live.set(reference, card.title, "Reentrant"))
        _ -> Nil
      }
    })
  deliver([
    fixture.remote_edit(
      compiled,
      initial,
      types.SetField(["title"], types.StringValue("Remote")),
    ),
  ])
  let assert [Error(tree_error.ReentrantEdit)] = take(1)
  live.unsubscribe(subscription)
  live.get(reference, card.title) |> expect.to_equal(Ok("Remote"))
  live.set(reference, card.title, "After delivery") |> expect.to_equal(Ok(Nil))
  facade.close(document)
}
