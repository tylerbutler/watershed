import gleam/option.{Some}
import startest/expect
@target(javascript)
import watershed as facade
import watershed/runtime_core as core
import watershed/tree/error
import watershed/tree/live
import watershed/tree/live_fixture as fixture
import watershed/tree/runtime_fixture
import watershed/tree/schema_builder as builder
import watershed/tree/types
@target(erlang)
import watershed_beam as facade

pub fn tree_api_errors_distinguish_closed_runtime_and_closed_tree_test() {
  let definition = fixture.card_schema()
  let assert Ok(compiled) = definition.node |> builder.root |> builder.compile
  let #(document, native) =
    fixture.tree(compiled, fixture.Card(builder.Assigned("original"), "First"))
  let assert Ok(tree) = facade.tree_typed(native, compiled)
  let assert Ok(other) = facade.tree_typed(native, compiled)
  live.dispose(tree) |> expect.to_equal(Ok(Nil))
  live.read_root(tree) |> expect.to_equal(Error(error.ClosedTree))
  facade.close(document)
  live.read_root(other) |> expect.to_equal(Error(error.ClosedRuntime))
}

pub fn tree_api_errors_preserve_wrong_property_and_incompatible_schema_test() {
  let definition = fixture.card_schema()
  let assert Ok(compiled) = definition.node |> builder.root |> builder.compile
  let #(document, native) =
    fixture.tree(compiled, fixture.Card(builder.Assigned("original"), "First"))
  let assert Ok(tree) = facade.tree_typed(native, compiled)
  let assert Ok(root) = live.required_root(tree)
  let wrong =
    builder.required("absent", builder.string(), fn(v: fixture.Card) { v.title })
  live.set(root, wrong, "Rejected")
  |> expect.to_equal(Error(error.WrongProperty("absent")))
  live.read_root(tree)
  |> expect.to_equal(Ok(fixture.Card(builder.Assigned("original"), "First")))
  let assert Ok(incompatible) =
    builder.string() |> builder.root |> builder.compile
  case facade.tree_typed(native, incompatible) {
    Error(error.IncompatibleView) -> Nil
    _ -> panic as "Expected an incompatible schema"
  }
  facade.close(document)
}

pub fn tree_api_errors_preserve_native_invalid_edit_payload_test() {
  let assert Ok(compiled) =
    builder.array(builder.factory("errors"), "Items", builder.string())
    |> builder.root
    |> builder.compile
  let assert Ok(Some(value)) = builder.encode(compiled, [])
  let assert Ok(input) =
    runtime_fixture.routed_tree_seed_input(
      builder.stored(compiled),
      builder.view(compiled),
      value,
    )
  let assert Ok(seed) = core.bootstrap_seed(input)
  let assert Ok(core.Complete(state)) =
    core.bootstrap_seeded(runtime_fixture.connected("errors", [], 0), seed)
  let assert Error(core.TreeOperationFailed(_, original)) =
    core.submit_tree_edits(state, "A/_C", [
      types.ArrayInsert([], 3, [types.StringValue("Rejected")]),
    ])
  let #(document, native) = fixture.tree(compiled, [])
  let assert Ok(tree) = facade.tree_typed(native, compiled)
  let assert Ok(array) = live.required_root(tree)
  live.array_insert(array, 3, ["Rejected"])
  |> expect.to_equal(Error(error.InvalidValue(original)))
  live.read_root(tree) |> expect.to_equal(Ok([]))
  facade.close(document)
}
