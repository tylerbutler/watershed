import gleam/dict
@target(erlang)
import gleam/erlang/process
import gleam/list
import gleam/option.{None, Some}
import startest/expect
@target(javascript)
import watershed as facade
import watershed/tree
import watershed/tree/error
import watershed/tree/live_fixture as live
import watershed/tree/object_fixture as fixture
import watershed/tree/schema_builder as builder
@target(erlang)
import watershed_beam as facade

fn compiled(node: builder.Node(a)) -> builder.Compiled(a) {
  node |> builder.root |> builder.compile |> expect.to_be_ok
}

fn object() {
  live.tree(compiled(fixture.node()), fixture.initial())
}

fn create(
  document: facade.Document(root),
  compiled: builder.Compiled(a),
  initial: a,
) -> Result(tree.Tree(a), error.Error) {
  facade.create_tree(document, compiled, initial)
}

@target(javascript)
fn close(document) {
  facade.close(document)
}

@target(erlang)
fn close(document) {
  let runtime = facade.runtime_subject(document)
  let assert Ok(owner) = process.subject_owner(runtime)
  let monitor = process.monitor(owner)
  facade.close(document)
  process.new_selector()
  |> process.select_specific_monitor(monitor, fn(_) { Nil })
  |> process.selector_receive(1000)
  |> expect.to_equal(Ok(Nil))
  process.demonitor_process(monitor)
}

pub fn tree_api_declared_root_array_reads_and_inserts_test() {
  let node =
    builder.array(builder.factory("typed.test"), "Words", builder.string())
  let #(document, handle) = live.tree(compiled(node), ["A", "B"])
  let assert Ok(array) = tree.required_root(handle)
  tree.array_insert(array, 1, ["X"]) |> expect.to_equal(Ok(Nil))
  tree.read(array) |> expect.to_equal(Ok(["A", "X", "B"]))
  facade.close(document)
}

pub fn tree_api_declared_object_preserves_optional_and_null_values_test() {
  let #(document, handle) = object()
  let assert Ok(root) = tree.required_root(handle)
  tree.get(root, fixture.title()) |> expect.to_equal(Ok("Title"))
  tree.get(root, fixture.note()) |> expect.to_equal(Ok(Some("Note")))
  tree.set(root, fixture.note(), None) |> expect.to_equal(Ok(Nil))
  tree.get(root, fixture.note()) |> expect.to_equal(Ok(None))
  tree.get(root, fixture.maybe_null()) |> expect.to_equal(Ok(Some(Nil)))
  tree.set(root, fixture.maybe_null(), None) |> expect.to_equal(Ok(Nil))
  tree.get(root, fixture.maybe_null()) |> expect.to_equal(Ok(None))
  tree.set(root, fixture.maybe_null(), Some(Nil)) |> expect.to_equal(Ok(Nil))
  tree.get(root, fixture.maybe_null()) |> expect.to_equal(Ok(Some(Nil)))
  tree.get(root, fixture.nothing()) |> expect.to_equal(Ok(Nil))
  tree.get(root, fixture.handle_field())
  |> expect.to_equal(Ok(fixture.initial().handle))
  facade.close(document)
}

pub fn tree_api_declared_child_edits_and_removal_preserve_identity_test() {
  let #(document, handle) = object()
  let assert Ok(root) = tree.required_root(handle)
  let assert Ok(child) = tree.child(root, fixture.child())
  tree.read(child)
  |> expect.to_equal(Ok(fixture.Child(builder.Assigned("child"), "Child")))
  tree.get(child, fixture.child_id())
  |> expect.to_equal(Ok(builder.Assigned("child")))
  tree.set(child, fixture.child_text(), "Changed") |> expect.to_equal(Ok(Nil))
  tree.get(root, fixture.child())
  |> expect.to_equal(Ok(fixture.Child(builder.Assigned("child"), "Changed")))
  let assert Ok(Some(optional)) =
    tree.optional_child(root, fixture.optional_child())
  tree.set(root, fixture.optional_child(), None) |> expect.to_equal(Ok(Nil))
  tree.optional_child(root, fixture.optional_child())
  |> expect.to_equal(Ok(None))
  tree.read(optional) |> expect.to_be_error
  facade.close(document)
}

pub fn tree_api_declared_arrays_construct_identifiers_and_edit_by_identity_test() {
  let #(document, handle) = object()
  let assert Ok(root) = tree.required_root(handle)
  let assert Ok(array) = tree.child(root, fixture.items())
  tree.read(array)
  |> expect.to_equal(
    Ok([
      fixture.Child(builder.Assigned("first"), "First"),
      fixture.Child(builder.Assigned("second"), "Second"),
    ]),
  )
  let assert Ok(Nil) =
    tree.array_insert_new(array, 2, [
      fixture.Child(builder.Generate, "Third"),
      fixture.Child(builder.Generate, "Same"),
      fixture.Child(builder.Generate, "Same"),
    ])
  let assert Ok(Some(third)) = tree.array_node(array, 2)
  let assert Ok(builder.Assigned(third_id)) =
    tree.get(third, fixture.child_id())
  third_id |> expect.to_not_equal("")
  let assert Ok(Some(one)) = tree.array_node(array, 3)
  let assert Ok(Some(two)) = tree.array_node(array, 4)
  let assert Ok(one_id) = tree.get(one, fixture.child_id())
  let assert Ok(two_id) = tree.get(two, fixture.child_id())
  one_id |> expect.to_not_equal(two_id)
  tree.array_move_before(array, two, array, Some(one))
  |> expect.to_equal(Ok(Nil))
  tree.set(one, fixture.child_text(), "Moved") |> expect.to_equal(Ok(Nil))
  let assert Ok(values) = tree.read(array)
  list.map(values, fn(value) { value.text })
  |> expect.to_equal(["First", "Second", "Third", "Same", "Moved"])
  let assert Ok(other) = tree.child(root, fixture.other_items())
  tree.array_move_before(array, one, other, None) |> expect.to_equal(Ok(Nil))
  tree.read(other) |> expect.to_equal(Ok([fixture.Child(one_id, "Moved")]))
  tree.array_remove_node(array, two) |> expect.to_equal(Ok(Nil))
  tree.read(two) |> expect.to_be_error
  tree.get(one, fixture.child_text()) |> expect.to_equal(Ok("Moved"))
  facade.close(document)
}

pub fn tree_api_declared_maps_invalidate_replaced_and_removed_nodes_test() {
  let #(document, handle) = object()
  let assert Ok(root) = tree.required_root(handle)
  let assert Ok(entries) = tree.child(root, fixture.entries())
  tree.map_get(entries, "first")
  |> expect.to_equal(
    Ok(Some(fixture.Child(builder.Assigned("mapped"), "Mapped"))),
  )
  tree.map_set_new(entries, "second", fixture.Child(builder.Generate, "Other"))
  |> expect.to_equal(Ok(Nil))
  let assert Ok(Some(mapped)) = tree.map_node(entries, "first")
  tree.map_set_new(
    entries,
    "first",
    fixture.Child(builder.Generate, "Replacement"),
  )
  |> expect.to_equal(Ok(Nil))
  tree.read(mapped) |> expect.to_be_error
  let assert Ok(Some(replacement)) = tree.map_node(entries, "first")
  tree.map_delete(entries, "first") |> expect.to_equal(Ok(Nil))
  tree.read(replacement) |> expect.to_be_error
  tree.map_get(entries, "first") |> expect.to_equal(Ok(None))
  facade.close(document)
}

pub fn tree_api_declared_references_reject_foreign_checkouts_channels_and_documents_test() {
  let #(document, handle) = object()
  let assert Ok(root) = tree.required_root(handle)
  let assert Ok(array) = tree.child(root, fixture.items())
  let assert Ok(branch) = tree.fork(handle)
  let assert Ok(branch_root) = tree.required_root(branch)
  let assert Ok(branch_array) = tree.child(branch_root, fixture.items())
  let assert Ok(Some(branch_item)) = tree.array_node(branch_array, 0)
  tree.array_remove_node(array, branch_item)
  |> expect.to_equal(Error(error.ForeignOrigin))
  tree.dispose(branch) |> expect.to_equal(Ok(Nil))
  let assert Ok(other) =
    create(document, compiled(fixture.node()), fixture.initial())
  let assert Ok(other_root) = tree.required_root(other)
  let assert Ok(other_array) = tree.child(other_root, fixture.items())
  let assert Ok(Some(other_item)) = tree.array_node(other_array, 0)
  tree.array_remove_node(array, other_item)
  |> expect.to_equal(Error(error.ForeignOrigin))
  let #(foreign_document, foreign_tree) = object()
  let assert Ok(foreign_root) = tree.required_root(foreign_tree)
  let assert Ok(foreign_array) = tree.child(foreign_root, fixture.items())
  let assert Ok(Some(foreign_item)) = tree.array_node(foreign_array, 0)
  tree.array_remove_node(array, foreign_item)
  |> expect.to_equal(Error(error.ForeignOrigin))
  close(document)
  tree.read(foreign_root) |> expect.to_equal(Ok(fixture.initial()))
  facade.close(foreign_document)
}

pub fn tree_api_declared_root_replacement_invalidates_descendants_test() {
  let #(document, handle) = object()
  let assert Ok(root) = tree.required_root(handle)
  let assert Ok(child) = tree.child(root, fixture.child())
  let assert Ok(array) = tree.child(root, fixture.items())
  let assert Ok(entries) = tree.child(root, fixture.entries())
  let replacement = fixture.Root(..fixture.initial(), title: "Replacement")
  tree.replace_root(handle, replacement) |> expect.to_equal(Ok(Nil))
  tree.read(root) |> expect.to_be_error
  tree.read(child) |> expect.to_be_error
  tree.read(array) |> expect.to_be_error
  tree.read(entries) |> expect.to_be_error
  tree.read_root(handle) |> expect.to_equal(Ok(replacement))
  let assert Ok(current) = tree.required_root(handle)
  close(document)
  tree.read(current) |> expect.to_equal(Error(error.ClosedRuntime))
}

pub fn tree_api_declared_leaf_and_map_roots_need_no_native_adapters_test() {
  let #(document, leaf) = live.tree(compiled(builder.string()), "leaf")
  tree.read_root(leaf) |> expect.to_equal(Ok("leaf"))
  tree.replace_root(leaf, "changed leaf") |> expect.to_equal(Ok(Nil))
  tree.read_root(leaf) |> expect.to_equal(Ok("changed leaf"))
  let node =
    builder.map(builder.factory("typed.test"), "Entries", builder.string())
  let assert Ok(handle) =
    create(document, compiled(node), dict.from_list([#("first", "value")]))
  let assert Ok(entries) = tree.required_root(handle)
  tree.map_get(entries, "first") |> expect.to_equal(Ok(Some("value")))
  tree.map_set(entries, "second", "other") |> expect.to_equal(Ok(Nil))
  tree.map_delete(entries, "first") |> expect.to_equal(Ok(Nil))
  tree.read(entries)
  |> expect.to_equal(Ok(dict.from_list([#("second", "other")])))
  facade.close(document)
}

pub fn tree_api_declared_closed_optional_root_returns_structured_errors_test() {
  let assert Ok(compiled) =
    builder.string() |> builder.optional_root |> builder.compile
  let #(document, handle) = live.tree(compiled, Some("open"))
  close(document)
  tree.read_root(handle) |> expect.to_equal(Error(error.ClosedRuntime))
  tree.replace_root(handle, Some("closed"))
  |> expect.to_equal(Error(error.ClosedRuntime))
  tree.replace_root(handle, None) |> expect.to_equal(Error(error.ClosedRuntime))
}

type Nested {
  Point(String)
  Items(List(Nested))
  Undeclared
}

fn nested_array() -> builder.Node(List(Nested)) {
  let factory = builder.factory("org.watershed.shared-tree.reload")
  let point =
    builder.object1(
      factory,
      "Point",
      fn(value) { value },
      builder.required("label", builder.string(), fn(value: String) { value }),
    )
  builder.array(
    factory,
    "Items",
    builder.union([
      builder.variant(point, Point, fn(value) {
        case value {
          Point(label) -> Some(label)
          Items(_) | Undeclared -> None
        }
      }),
      builder.variant(
        builder.lazy(factory, "Items", nested_array),
        Items,
        fn(value) {
          case value {
            Items(items) -> Some(items)
            Point(_) | Undeclared -> None
          }
        },
      ),
    ]),
  )
}

pub fn tree_api_declared_heterogeneous_arrays_validate_before_submission_test() {
  let #(submitted, take) = live.capture()
  let #(document, handle, _) =
    live.tree_with_submissions(
      compiled(nested_array()),
      [Point("existing")],
      submitted,
    )
  let assert Ok(array) = tree.required_root(handle)
  let additions = [
    Point("one"),
    Point("two"),
    Point("three"),
    Point("four"),
    Items([Point("nested")]),
  ]
  tree.array_insert(array, 1, additions) |> expect.to_equal(Ok(Nil))
  tree.read(array) |> expect.to_equal(Ok([Point("existing"), ..additions]))
  take(1) |> list.length |> expect.to_equal(1)
  tree.array_insert(array, 0, [Point("valid"), Undeclared])
  |> expect.to_be_error
  tree.array_insert(array, 0, [Items([Undeclared])]) |> expect.to_be_error
  tree.read(array) |> expect.to_equal(Ok([Point("existing"), ..additions]))
  take(0) |> expect.to_equal([])
  facade.close(document)
}
