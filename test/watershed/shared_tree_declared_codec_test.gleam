import gleam/dict
import gleam/list
import gleam/option.{type Option, None, Some}
import startest/expect
@target(javascript)
import watershed as facade
import watershed/handle
import watershed/tree
import watershed/tree/declaration_fixture as fixture
import watershed/tree/live_fixture
import watershed/tree/schema
import watershed/tree/schema_builder as builder
import watershed/tree/types
@target(erlang)
import watershed_beam as facade

fn compiled(node: builder.Node(a)) -> builder.Compiled(a) {
  node |> builder.root |> builder.compile |> expect.to_be_ok
}

fn round_trip(node: builder.Node(a), value: a) -> Nil {
  let compiled = compiled(node)
  let assert Ok(encoded) = builder.encode(compiled, value)
  builder.decode(compiled, encoded) |> expect.to_equal(Ok(value))
}

pub fn tree_api_compiled_leaf_round_trips_test() {
  let assert Ok(reference) = handle.reference_from_path("/data/tree")
  round_trip(builder.string(), "water")
  round_trip(builder.number(), -1.25)
  round_trip(builder.boolean(), True)
  round_trip(builder.null(), Nil)
  round_trip(builder.handle(), reference)
}

pub fn tree_api_compiled_leaf_roots_reject_wrong_values_test() {
  builder.decode(compiled(builder.string()), Some(types.NumberValue(1.0)))
  |> expect.to_be_error
  builder.decode(compiled(builder.number()), Some(types.StringValue("1")))
  |> expect.to_be_error
  builder.decode(compiled(builder.boolean()), Some(types.NullValue))
  |> expect.to_be_error
  builder.decode(compiled(builder.null()), Some(types.BooleanValue(False)))
  |> expect.to_be_error
  builder.decode(compiled(builder.handle()), Some(types.StringValue("/tree")))
  |> expect.to_be_error
  Nil
}

pub fn tree_api_compiled_number_preserves_finite_boundaries_test() {
  list.each(
    [
      -1.7976931348623157e308,
      -5.0e-324,
      -0.0,
      0.0,
      5.0e-324,
      1.7976931348623157e308,
    ],
    fn(value) { round_trip(builder.number(), value) },
  )
}

@target(javascript)
pub fn tree_api_compiled_number_rejects_non_finite_values_test() {
  let compiled = compiled(builder.number())
  let infinity = 1.7976931348623157e308 *. 2.0
  let nan = infinity -. infinity
  list.each([infinity, 0.0 -. infinity, nan], fn(value) {
    builder.encode(compiled, value) |> expect.to_be_error
    builder.decode(compiled, Some(types.NumberValue(value)))
    |> expect.to_be_error
    Nil
  })
}

pub fn tree_api_compiled_records_decode_field_order_and_check_schema_test() {
  let compiled =
    fixture.item()
    |> builder.root
    |> builder.compile
    |> expect.to_be_ok
  let value =
    types.ObjectValue(fixture.item_type, [
      #("completed", types.BooleanValue(False)),
      #("text", types.StringValue("Check the gate")),
      #("id", types.StringValue("item-1")),
    ])
  builder.decode(compiled, Some(value))
  |> expect.to_equal(Ok(fixture.Item("item-1", "Check the gate", False)))
  builder.decode(compiled, Some(types.ObjectValue("wrong.Item", [])))
  |> expect.to_be_error
  Nil
}

pub fn tree_api_compiled_required_roots_reject_absence_test() {
  builder.decode(compiled(builder.string()), None) |> expect.to_be_error
  builder.decode(compiled(fixture.item()), None) |> expect.to_be_error
  Nil
}

pub fn tree_api_compiled_optional_roots_preserve_absence_test() {
  let assert Ok(compiled) =
    builder.string() |> builder.optional_root |> builder.compile
  builder.encode(compiled, None) |> expect.to_equal(Ok(None))
  builder.decode(compiled, None) |> expect.to_equal(Ok(None))
  builder.encode(compiled, Some("present"))
  |> expect.to_equal(Ok(Some(types.StringValue("present"))))
  builder.decode(compiled, Some(types.NumberValue(1.0)))
  |> expect.to_be_error
  Nil
}

pub fn tree_api_compiled_optional_null_root_is_not_absence_test() {
  let assert Ok(compiled) =
    builder.null() |> builder.optional_root |> builder.compile
  builder.decode(compiled, None) |> expect.to_equal(Ok(None))
  builder.decode(compiled, Some(types.NullValue))
  |> expect.to_equal(Ok(Some(Nil)))
  builder.encode(compiled, Some(Nil))
  |> expect.to_equal(Ok(Some(types.NullValue)))
}

type MaybeNull {
  MaybeNull(value: Option(Nil))
}

pub fn tree_api_compiled_optional_null_property_is_not_absence_test() {
  let node =
    builder.object1(
      builder.factory("typed.test"),
      "MaybeNull",
      MaybeNull,
      builder.optional("value", builder.null(), fn(value: MaybeNull) {
        value.value
      }),
    )
  let compiled = compiled(node)
  builder.decode(compiled, Some(types.ObjectValue("typed.test.MaybeNull", [])))
  |> expect.to_equal(Ok(MaybeNull(None)))
  builder.decode(
    compiled,
    Some(
      types.ObjectValue("typed.test.MaybeNull", [
        #("value", types.NullValue),
      ]),
    ),
  )
  |> expect.to_equal(Ok(MaybeNull(Some(Nil))))
  round_trip(node, MaybeNull(None))
  round_trip(node, MaybeNull(Some(Nil)))
}

type Choice {
  Text(String)
  Number(Float)
}

fn choice() -> builder.Node(Choice) {
  builder.union([
    builder.variant(builder.string(), Text, fn(value) {
      case value {
        Text(value) -> Some(value)
        Number(_) -> None
      }
    }),
    builder.variant(builder.number(), Number, fn(value) {
      case value {
        Number(value) -> Some(value)
        Text(_) -> None
      }
    }),
  ])
}

pub fn tree_api_compiled_union_roots_check_every_alternative_test() {
  let compiled = compiled(choice())
  builder.decode(compiled, Some(types.StringValue("water")))
  |> expect.to_equal(Ok(Text("water")))
  builder.decode(compiled, Some(types.NumberValue(1.0)))
  |> expect.to_equal(Ok(Number(1.0)))
  builder.decode(compiled, Some(types.BooleanValue(True)))
  |> expect.to_be_error
  let assert Ok(optional) = choice() |> builder.optional_root |> builder.compile
  builder.decode(optional, None) |> expect.to_equal(Ok(None))
  builder.decode(optional, Some(types.StringValue("water")))
  |> expect.to_equal(Ok(Some(Text("water"))))
  builder.decode(optional, Some(types.NumberValue(1.0)))
  |> expect.to_equal(Ok(Some(Number(1.0))))
}

pub fn tree_api_compiled_collections_check_complete_union_members_test() {
  let factory = builder.factory("typed.test")
  let array = builder.array(factory, "Choices", choice())
  let entries = builder.map(factory, "Entries", choice())
  round_trip(array, [Text("water"), Number(1.0)])
  round_trip(
    entries,
    dict.from_list([#("text", Text("water")), #("number", Number(1.0))]),
  )
  builder.decode(
    compiled(array),
    Some(
      types.ArrayValue("typed.test.Choices", [
        types.StringValue("water"),
        types.BooleanValue(True),
      ]),
    ),
  )
  |> expect.to_be_error
  builder.decode(
    compiled(entries),
    Some(
      types.MapValue("typed.test.Entries", [
        #("wrong", types.BooleanValue(True)),
      ]),
    ),
  )
  |> expect.to_be_error
  Nil
}

pub fn tree_api_compiled_declarations_reject_empty_names_test() {
  list.each([#("", "Item"), #("typed.test", ""), #("", "")], fn(names) {
    builder.object0(builder.factory(names.0), names.1)
    |> builder.root
    |> builder.compile
    |> expect.to_be_error
    Nil
  })
}

pub fn tree_api_compiled_property_access_checks_member_definition_test() {
  let #(document, handle) =
    live_fixture.tree(
      compiled(fixture.item()),
      fixture.Item("item-1", "First", False),
    )
  let assert Ok(root) = tree.required_root(handle)
  let id =
    builder.required("id", builder.string(), fn(value: fixture.Item) {
      value.id
    })
  tree.get(root, id) |> expect.to_equal(Ok("item-1"))
  let missing =
    builder.required("missing", builder.string(), fn(value: fixture.Item) {
      value.id
    })
  let wrong_kind =
    builder.required("id", builder.boolean(), fn(value: fixture.Item) {
      value.completed
    })
  let wrong_cardinality =
    builder.optional("id", builder.string(), fn(value: fixture.Item) {
      Some(value.id)
    })
  tree.get(root, missing) |> expect.to_be_error
  tree.get(root, wrong_kind) |> expect.to_be_error
  tree.get(root, wrong_cardinality) |> expect.to_be_error
  tree.set(root, wrong_kind, True) |> expect.to_be_error
  tree.set(root, wrong_cardinality, None) |> expect.to_be_error
  tree.read_root(handle)
  |> expect.to_equal(Ok(fixture.Item("item-1", "First", False)))
  facade.close(document)
}

pub fn tree_api_compiled_generated_identifier_has_distinct_write_modes_test() {
  let compiled = compiled(fixture.generated_item())
  let value = fixture.GeneratedItem(builder.Generate, "Allocated later")
  builder.encode(compiled, value) |> expect.to_be_error
  builder.encode_new(compiled, value)
  |> expect.to_equal(
    Ok(
      Some(
        types.ObjectValue(fixture.generated_item_type, [
          #("text", types.StringValue("Allocated later")),
        ]),
      ),
    ),
  )
  builder.decode(
    compiled,
    Some(
      types.ObjectValue(fixture.generated_item_type, [
        #("text", types.StringValue("Allocated later")),
      ]),
    ),
  )
  |> expect.to_be_error
  let assigned =
    fixture.GeneratedItem(builder.Assigned("generated-id"), "Allocated later")
  let assert Ok(encoded) = builder.encode(compiled, assigned)
  builder.decode(compiled, encoded) |> expect.to_equal(Ok(assigned))
}

pub fn tree_api_compiled_schema_rejects_sequence_roots_test() {
  schema.view_from_string(
    "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}}},\"root\":{\"kind\":\"Sequence\",\"types\":[\"com.fluidframework.leaf.string\"]}}",
  )
  |> expect.to_equal(
    Error(types.InvalidSchema(
      "$.root: sequence field is only valid as an array primary field",
    )),
  )
}
