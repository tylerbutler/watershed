import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import startest/expect
import watershed/handle
import watershed/tree/schema as tree_schema
import watershed/tree/typed
import watershed/tree/typed_fixture as fixture
import watershed/tree/types

pub fn shared_tree_typed_leaf_round_trips_test() {
  let assert Ok(reference) = handle.reference_from_path("/data/tree")
  [
    #(typed.encode(typed.string(), "water"), Ok(types.StringValue("water"))),
    #(typed.encode(typed.number(), -1.25), Ok(types.NumberValue(-1.25))),
    #(typed.encode(typed.boolean(), True), Ok(types.BooleanValue(True))),
    #(typed.encode(typed.null(), Nil), Ok(types.NullValue)),
    #(typed.encode(typed.handle(), reference), Ok(types.HandleValue(reference))),
  ]
  |> list.all(fn(pair) { pair.0 == pair.1 })
  |> expect.to_be_true
  typed.decode(typed.string(), types.StringValue("water"))
  |> expect.to_equal(Ok("water"))
  typed.decode(typed.number(), types.NumberValue(-1.25))
  |> expect.to_equal(Ok(-1.25))
  typed.decode(typed.boolean(), types.BooleanValue(True))
  |> expect.to_equal(Ok(True))
  typed.decode(typed.null(), types.NullValue) |> expect.to_equal(Ok(Nil))
  typed.decode(typed.handle(), types.HandleValue(reference))
  |> expect.to_equal(Ok(reference))
}

pub fn shared_tree_typed_string_decode_rejects_number_test() {
  typed.decode(typed.string(), types.NumberValue(1.0))
  |> expect.to_equal(Error(typed.DecodeFailed("expected a string leaf")))
}

pub fn shared_tree_typed_number_accepts_finite_boundaries_test() {
  [
    -1.7976931348623157e308,
    -5.0e-324,
    -0.0,
    0.0,
    5.0e-324,
    1.7976931348623157e308,
  ]
  |> list.all(fn(value) {
    typed.encode(typed.number(), value) == Ok(types.NumberValue(value))
    && typed.decode(typed.number(), types.NumberValue(value)) == Ok(value)
  })
  |> expect.to_be_true
}

@target(javascript)
pub fn shared_tree_typed_number_rejects_non_finite_values_test() {
  let infinity = 1.7976931348623157e308 *. 2.0
  let nan = infinity -. infinity
  [infinity, 0.0 -. infinity, nan]
  |> list.all(fn(value) {
    typed.encode(typed.number(), value)
    == Error(typed.DecodeFailed("expected a finite number leaf"))
    && typed.decode(typed.number(), types.NumberValue(value))
    == Error(typed.DecodeFailed("expected a finite number leaf"))
  })
  |> expect.to_be_true
}

pub fn shared_tree_typed_node_decode_checks_identifier_and_field_order_test() {
  let value =
    types.ObjectValue(fixture.item_type, [
      #("completed", types.BooleanValue(False)),
      #("text", types.StringValue("Check the gate")),
      #("id", types.StringValue("item-1")),
    ])
  typed.decode_node(fixture.item_codec(), value)
  |> expect.to_equal(
    Ok(fixture.Item(id: "item-1", text: "Check the gate", completed: False)),
  )
  typed.decode_node(fixture.item_codec(), types.ObjectValue("wrong.Item", []))
  |> expect.to_equal(
    Error(typed.DecodeFailed("expected node " <> fixture.item_type)),
  )
}

pub fn shared_tree_typed_leaf_nodes_decode_and_build_test() {
  let assert Ok(reference) = handle.reference_from_path("/data/tree")
  [
    #("com.fluidframework.leaf.string", types.StringValue("water")),
    #("com.fluidframework.leaf.number", types.NumberValue(1.25)),
    #("com.fluidframework.leaf.boolean", types.BooleanValue(True)),
    #("com.fluidframework.leaf.null", types.NullValue),
    #("com.fluidframework.leaf.handle", types.HandleValue(reference)),
  ]
  |> list.each(fn(leaf) {
    let codec = typed.node(leaf.0, fn(value) { Ok(value) }) |> expect.to_be_ok
    typed.decode_node(codec, leaf.1) |> expect.to_equal(Ok(leaf.1))

    let builder = typed.builder(leaf.0, fn(_) { Ok(leaf.1) }) |> expect.to_be_ok
    typed.build(builder, Nil) |> expect.to_equal(Ok(leaf.1))
  })
}

pub fn shared_tree_typed_leaf_nodes_reject_mismatched_identifiers_test() {
  let string_node =
    typed.node("com.fluidframework.leaf.string", fn(value) {
      typed.decode(typed.string(), value)
    })
    |> expect.to_be_ok
  typed.decode_node(string_node, types.NumberValue(1.0))
  |> expect.to_equal(
    Error(typed.DecodeFailed("expected node com.fluidframework.leaf.string")),
  )

  let string_builder =
    typed.builder("com.fluidframework.leaf.string", fn(_) {
      Ok(types.NumberValue(1.0))
    })
    |> expect.to_be_ok
  typed.build(string_builder, Nil)
  |> expect.to_equal(
    Error(typed.DecodeFailed("expected node com.fluidframework.leaf.string")),
  )
}

pub fn shared_tree_typed_schema_accepts_leaf_roots_test() {
  [
    #("com.fluidframework.leaf.number", 0),
    #("com.fluidframework.leaf.string", 1),
    #("com.fluidframework.leaf.boolean", 2),
    #("com.fluidframework.leaf.handle", 3),
    #("com.fluidframework.leaf.null", 4),
  ]
  |> list.each(fn(leaf) {
    let raw =
      "{\"version\":2,\"nodes\":{\""
      <> leaf.0
      <> "\":{\"kind\":{\"leaf\":"
      <> int.to_string(leaf.1)
      <> "}}},\"root\":{\"kind\":\"Value\",\"types\":[\""
      <> leaf.0
      <> "\"]}}"
    let view = tree_schema.view_from_string(raw) |> expect.to_be_ok
    let codec = typed.node(leaf.0, fn(value) { Ok(value) }) |> expect.to_be_ok
    typed.schema(view, codec) |> expect.to_be_ok
  })
}

pub fn shared_tree_typed_optional_absence_differs_from_present_null_test() {
  let assert Ok(codec) =
    typed.node("MaybeNull", fn(value) {
      let assert types.ObjectValue(_, fields) = value
      case fields {
        [] -> Ok(None)
        [#("value", value)] ->
          typed.decode(typed.null(), value) |> result.map(Some)
        _ -> Error(typed.DecodeFailed("expected optional null field"))
      }
    })
  typed.decode_node(codec, types.ObjectValue("MaybeNull", []))
  |> expect.to_equal(Ok(None))
  typed.decode_node(
    codec,
    types.ObjectValue("MaybeNull", [#("value", types.NullValue)]),
  )
  |> expect.to_equal(Ok(Some(Nil)))
}

pub fn shared_tree_typed_declaration_identifiers_must_be_visible_test() {
  let _ = typed.node("", fn(_) { Ok(Nil) }) |> expect.to_be_error
  let _ = typed.node(" ", fn(_) { Ok(Nil) }) |> expect.to_be_error
  let _ =
    typed.builder("\n", fn(_) { Ok(types.NullValue) }) |> expect.to_be_error
  Nil
}

pub fn shared_tree_typed_schema_checks_root_identifier_test() {
  typed.schema(fixture.view(), fixture.checklist_codec()) |> expect.to_be_ok
  typed.schema(fixture.view(), fixture.item_codec())
  |> expect.to_equal(
    Error(typed.SchemaMismatch("root does not allow " <> fixture.item_type)),
  )
}

pub fn shared_tree_typed_field_validators_check_owner_member_and_cardinality_test() {
  let view = fixture.view()
  typed.validate_field(view, fixture.item_type, fixture.item_id())
  |> expect.to_equal(Ok(Nil))
  typed.validate_field(
    view,
    fixture.item_type,
    typed.optional("id", typed.string()),
  )
  |> expect.to_be_error
  typed.validate_field(view, fixture.checklist_type, fixture.item_id())
  |> expect.to_be_error
  typed.validate_field(
    view,
    fixture.item_type,
    typed.required("id", typed.boolean()),
  )
  |> expect.to_be_error
  Nil
}

pub fn shared_tree_typed_collection_validators_check_member_definitions_test() {
  let view = fixture.view()
  typed.validate_array(view, fixture.checklist_type, fixture.checklist_items())
  |> expect.to_equal(Ok(Nil))
  typed.validate_array(view, fixture.item_type, fixture.checklist_items())
  |> expect.to_be_error
  typed.validate_array(
    view,
    fixture.checklist_type,
    typed.array_field("items", fixture.items_type, fixture.checklist_codec()),
  )
  |> expect.to_be_error
  Nil
}

pub fn shared_tree_typed_identifier_builder_omits_generated_identifier_test() {
  let input = fixture.GeneratedItemInput(text: "Allocated later")
  typed.build(fixture.generated_item_builder(), input)
  |> expect.to_equal(
    Ok(
      types.ObjectValue(fixture.generated_item_type, [
        #("text", types.StringValue("Allocated later")),
      ]),
    ),
  )
  typed.decode_node(
    fixture.generated_item_codec(),
    types.ObjectValue(fixture.generated_item_type, [
      #("text", types.StringValue("Allocated later")),
    ]),
  )
  |> expect.to_be_error
  typed.decode_node(
    fixture.generated_item_codec(),
    types.ObjectValue(fixture.generated_item_type, [
      #("text", types.StringValue("Allocated later")),
      #("id", types.StringValue("generated-id")),
    ]),
  )
  |> expect.to_equal(
    Ok(fixture.GeneratedItem(id: "generated-id", text: "Allocated later")),
  )
  typed.validate_identifier(
    fixture.identifier_view(),
    fixture.generated_item_type,
    fixture.generated_item_identifier(),
  )
  |> expect.to_equal(Ok(Nil))
}

pub fn shared_tree_typed_builder_rejects_wrong_node_identifier_test() {
  let builder =
    typed.builder(fixture.item_type, fn(_) {
      Ok(types.ObjectValue("wrong.Item", []))
    })
    |> expect.to_be_ok
  typed.build(builder, Nil)
  |> expect.to_equal(
    Error(typed.DecodeFailed("expected node " <> fixture.item_type)),
  )
}

pub fn shared_tree_typed_map_and_child_validators_check_schema_test() {
  let raw =
    "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}},\"Child\":{\"kind\":{\"object\":{\"name\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.string\"]}}}},\"Children\":{\"kind\":{\"map\":{\"kind\":\"Optional\",\"types\":[\"Child\"]}}},\"Root\":{\"kind\":{\"object\":{\"child\":{\"kind\":\"Optional\",\"types\":[\"Child\"]},\"children\":{\"kind\":\"Value\",\"types\":[\"Children\"]}}}}},\"root\":{\"kind\":\"Value\",\"types\":[\"Root\"]}}"
  let view = tree_schema.view_from_string(raw) |> expect.to_be_ok
  let child = typed.node("Child", fn(_) { Ok(Nil) }) |> expect.to_be_ok
  typed.validate_child(view, "Root", typed.optional_child("child", child))
  |> expect.to_equal(Ok(Nil))
  typed.validate_child(view, "Root", typed.required_child("child", child))
  |> expect.to_be_error
  typed.validate_map(
    view,
    "Root",
    typed.map_field("children", "Children", child),
  )
  |> expect.to_equal(Ok(Nil))
  let other = typed.node("Root", fn(_) { Ok(Nil) }) |> expect.to_be_ok
  typed.validate_map(
    view,
    "Root",
    typed.map_field("children", "Children", other),
  )
  |> expect.to_be_error
  Nil
}
