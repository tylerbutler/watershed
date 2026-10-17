import gleam/option.{None, Some}
import gleeunit
import shared_tree_item_counter_lustre/counter
import shared_tree_item_counter_lustre/schema as document_schema
import watershed
import watershed/fluid_ids
import watershed/runtime
import watershed/runtime_core
import watershed/sluice/frame
import watershed/transport_js
import watershed/tree
import watershed/tree/schema
import watershed/tree/schema_builder as builder
import watershed/tree/types
import watershed/wire/fluid_document

@external(javascript, "./shared_tree_item_counter_lustre_test_ffi.mjs", "stringify")
fn stringify(value: value) -> String

type Fixture(root) {
  Fixture(
    document: watershed.Document(root),
    tree: tree.Tree(List(String)),
    submissions: transport_js.Cell(Int),
  )
}

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn initial_root_is_a_valid_empty_string_array_test() {
  let compiled = document_schema.compiled()
  let assert Ok(Some(encoded)) =
    builder.encode_new(compiled, document_schema.initial())
  let assert Ok(Nil) = schema.validate_root(document_schema.stored(), encoded)
  let assert Ok([]) = builder.decode(compiled, Some(encoded))
}

pub fn compiled_schema_preserves_persisted_identity_test() {
  let assert Ok(compiled) = document_schema.definition()
  let assert Ok(previous) =
    schema.stored_from_string(
      "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}},\"shared_tree_item_counter.StringArray\":{\"kind\":{\"object\":{\"\":{\"kind\":\"Sequence\",\"types\":[\"com.fluidframework.leaf.string\"]}}}}},\"root\":{\"kind\":\"Value\",\"types\":[\"shared_tree_item_counter.StringArray\"]}}",
    )
  let assert Ok(True) =
    schema.allows_superset(previous, builder.stored(compiled))
  let assert Ok(True) =
    schema.allows_superset(builder.stored(compiled), previous)
  let assert Ok(["first"]) =
    builder.decode(
      compiled,
      Some(
        types.ArrayValue("shared_tree_item_counter.StringArray", [
          types.StringValue("first"),
        ]),
      ),
    )
}

pub fn insert_matches_the_fluid_insert_at_start_test() {
  let fixture = fixture(["first"])
  let assert Ok(Nil) = counter.apply(fixture.tree, counter.Insert)
  let assert Ok(["", "first"]) = tree.read_root(fixture.tree)
  let assert 1 = transport_js.get_cell(fixture.submissions)
  watershed.close(fixture.document)
}

pub fn remove_empty_is_a_no_op_test() {
  let fixture = fixture([])
  let assert Ok(Nil) = counter.apply(fixture.tree, counter.Remove)
  let assert Ok([]) = tree.read_root(fixture.tree)
  let assert 0 = transport_js.get_cell(fixture.submissions)
  watershed.close(fixture.document)
}

pub fn remove_targets_the_first_entry_only_test() {
  let fixture = fixture(["first", "second"])
  let assert Ok(Nil) = counter.apply(fixture.tree, counter.Remove)
  let assert Ok(["second"]) = tree.read_root(fixture.tree)
  let assert 1 = transport_js.get_cell(fixture.submissions)
  watershed.close(fixture.document)
}

pub fn malformed_roots_do_not_turn_into_zero_test() {
  let compiled = document_schema.compiled()
  let assert Error(_) =
    builder.decode(compiled, Some(types.StringValue("not an array")))
  let assert Error(_) =
    builder.decode(compiled, Some(types.ArrayValue("wrong.Array", [])))
  let assert Error(_) =
    builder.decode(
      compiled,
      Some(
        types.ArrayValue("shared_tree_item_counter.StringArray", [
          types.NumberValue(1.0),
        ]),
      ),
    )
}

fn fixture(initial: List(String)) -> Fixture(root) {
  let compiled = document_schema.compiled()
  let assert Ok(encoded) = builder.encode_new(compiled, initial)
  let assert Ok(session) =
    fluid_ids.session_id("30000000-0000-4000-8000-000000000003")
  let assert Ok(view_id) =
    fluid_ids.stable_id("40000000-0000-4000-8000-000000000004")
  let assert Ok(summary) =
    fluid_document.initial_tree(
      builder.stored(compiled),
      encoded,
      session,
      view_id,
    )
  let assert Ok(seed) = runtime_core.document_seed(summary)
  let callbacks = transport_js.new_cell(None)
  let submissions = transport_js.new_cell(0)
  let document =
    watershed.connect_via_seed(
      tenant: "default",
      document: "counter",
      user_id: "reader",
      seed: seed,
      transport: runtime.Transport(connect: fn(handlers) {
        transport_js.set_cell(callbacks, Some(handlers))
        runtime.TransportHandle(
          push: fn(event, _) {
            case event {
              "submitOp" ->
                transport_js.set_cell(
                  submissions,
                  transport_js.get_cell(submissions) + 1,
                )
              _ -> Nil
            }
          },
          close: fn() { Nil },
          drop: fn() { Nil },
          hold: fn() { Nil },
          resume: fn() { Nil },
        )
      }),
      on_ready: fn(_) { Nil },
    )
  let assert Some(callbacks) = transport_js.get_cell(callbacks)
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "reader",
      tenant_id: "default",
      document_id: "counter",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 0,
      initial_clients: ["reader"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    )
      |> stringify,
  )
  let assert Ok(tree) = watershed.open_tree(document, compiled)
  Fixture(document:, tree:, submissions:)
}
