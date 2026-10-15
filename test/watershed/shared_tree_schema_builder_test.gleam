import gleam/dict
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import startest/expect
import watershed/handle
import watershed/tree/schema
import watershed/tree/schema_builder as builder
import watershed/tree/types

type Card {
  Card(title: String, owner: Option(String))
}

fn card_node() -> builder.Node(Card) {
  builder.object2(
    builder.factory("com.example"),
    "Card",
    Card,
    builder.required("title", builder.string(), fn(card: Card) { card.title }),
    builder.optional("owner", builder.string(), fn(card: Card) { card.owner }),
  )
}

pub fn shared_tree_schema_builder_optional_property_test() -> Nil {
  let assert Ok(compiled) = card_node() |> builder.root |> builder.compile
  let expected =
    Some(
      types.ObjectValue("com.example.Card", [
        #("title", types.StringValue("Ship it")),
      ]),
    )
  builder.encode(compiled, Card("Ship it", None))
  |> expect.to_equal(Ok(expected))
  builder.decode(compiled, expected)
  |> expect.to_equal(Ok(Card("Ship it", None)))
  let assert Ok(snapshot) =
    builder.encode(compiled, Card("title", Some("owner")))
  builder.decode(compiled, snapshot)
  |> expect.to_equal(Ok(Card("title", Some("owner"))))
}

fn round_trip(node: builder.Node(a), value: a) -> Nil {
  let assert Ok(compiled) = node |> builder.root |> builder.compile
  let assert Ok(encoded) = builder.encode(compiled, value)
  builder.decode(compiled, encoded) |> expect.to_equal(Ok(value))
}

pub fn shared_tree_schema_builder_object_arities_test() -> Nil {
  let f = builder.factory("com.example")
  round_trip(builder.object0(f, "Empty"), Nil)
  round_trip(
    builder.object1(
      f,
      "One",
      fn(a: String) { #(a) },
      builder.required("z", builder.string(), fn(v: #(String)) { v.0 }),
    ),
    #("a"),
  )
  round_trip(
    builder.object2(
      f,
      "Two",
      fn(a: String, b: Float) { #(a, b) },
      builder.required("z", builder.string(), fn(v: #(String, Float)) { v.0 }),
      builder.required("a", builder.number(), fn(v: #(String, Float)) { v.1 }),
    ),
    #("a", 2.0),
  )
  round_trip(
    builder.object3(
      f,
      "Three",
      fn(a: String, b: Float, c: Bool) { #(a, b, c) },
      builder.required("z", builder.string(), fn(v: #(String, Float, Bool)) {
        v.0
      }),
      builder.required("a", builder.number(), fn(v: #(String, Float, Bool)) {
        v.1
      }),
      builder.required("y", builder.boolean(), fn(v: #(String, Float, Bool)) {
        v.2
      }),
    ),
    #("a", 2.0, True),
  )
  round_trip(
    builder.object4(
      f,
      "Four",
      fn(a: String, b: Float, c: Bool, d: Nil) { #(a, b, c, d) },
      builder.required(
        "z",
        builder.string(),
        fn(v: #(String, Float, Bool, Nil)) { v.0 },
      ),
      builder.required(
        "a",
        builder.number(),
        fn(v: #(String, Float, Bool, Nil)) { v.1 },
      ),
      builder.required(
        "y",
        builder.boolean(),
        fn(v: #(String, Float, Bool, Nil)) { v.2 },
      ),
      builder.required("b", builder.null(), fn(v: #(String, Float, Bool, Nil)) {
        v.3
      }),
    ),
    #("a", 2.0, True, Nil),
  )
  round_trip(
    builder.object5(
      f,
      "Five",
      fn(a: String, b: Float, c: Bool, d: Nil, e: String) { #(a, b, c, d, e) },
      builder.required(
        "z",
        builder.string(),
        fn(v: #(String, Float, Bool, Nil, String)) { v.0 },
      ),
      builder.required(
        "a",
        builder.number(),
        fn(v: #(String, Float, Bool, Nil, String)) { v.1 },
      ),
      builder.required(
        "y",
        builder.boolean(),
        fn(v: #(String, Float, Bool, Nil, String)) { v.2 },
      ),
      builder.required(
        "b",
        builder.null(),
        fn(v: #(String, Float, Bool, Nil, String)) { v.3 },
      ),
      builder.required(
        "x",
        builder.string(),
        fn(v: #(String, Float, Bool, Nil, String)) { v.4 },
      ),
    ),
    #("a", 2.0, True, Nil, "e"),
  )
  round_trip(
    builder.object6(
      f,
      "Six",
      fn(a: String, b: Float, c: Bool, d: Nil, e: String, f: Float) {
        #(a, b, c, d, e, f)
      },
      builder.required(
        "z",
        builder.string(),
        fn(v: #(String, Float, Bool, Nil, String, Float)) { v.0 },
      ),
      builder.required(
        "a",
        builder.number(),
        fn(v: #(String, Float, Bool, Nil, String, Float)) { v.1 },
      ),
      builder.required(
        "y",
        builder.boolean(),
        fn(v: #(String, Float, Bool, Nil, String, Float)) { v.2 },
      ),
      builder.required(
        "b",
        builder.null(),
        fn(v: #(String, Float, Bool, Nil, String, Float)) { v.3 },
      ),
      builder.required(
        "x",
        builder.string(),
        fn(v: #(String, Float, Bool, Nil, String, Float)) { v.4 },
      ),
      builder.required(
        "c",
        builder.number(),
        fn(v: #(String, Float, Bool, Nil, String, Float)) { v.5 },
      ),
    ),
    #("a", 2.0, True, Nil, "e", 6.0),
  )
  round_trip(
    builder.object7(
      f,
      "Seven",
      fn(a: String, b: Float, c: Bool, d: Nil, e: String, f: Float, g: Bool) {
        #(a, b, c, d, e, f, g)
      },
      builder.required(
        "z",
        builder.string(),
        fn(v: #(String, Float, Bool, Nil, String, Float, Bool)) { v.0 },
      ),
      builder.required(
        "a",
        builder.number(),
        fn(v: #(String, Float, Bool, Nil, String, Float, Bool)) { v.1 },
      ),
      builder.required(
        "y",
        builder.boolean(),
        fn(v: #(String, Float, Bool, Nil, String, Float, Bool)) { v.2 },
      ),
      builder.required(
        "b",
        builder.null(),
        fn(v: #(String, Float, Bool, Nil, String, Float, Bool)) { v.3 },
      ),
      builder.required(
        "x",
        builder.string(),
        fn(v: #(String, Float, Bool, Nil, String, Float, Bool)) { v.4 },
      ),
      builder.required(
        "c",
        builder.number(),
        fn(v: #(String, Float, Bool, Nil, String, Float, Bool)) { v.5 },
      ),
      builder.required(
        "w",
        builder.boolean(),
        fn(v: #(String, Float, Bool, Nil, String, Float, Bool)) { v.6 },
      ),
    ),
    #("a", 2.0, True, Nil, "e", 6.0, False),
  )
  round_trip(
    builder.object8(
      f,
      "Eight",
      fn(
        a: String,
        b: Float,
        c: Bool,
        d: Nil,
        e: String,
        f: Float,
        g: Bool,
        h: Option(Nil),
      ) {
        #(a, b, c, d, e, f, g, h)
      },
      builder.required(
        "z",
        builder.string(),
        fn(v: #(String, Float, Bool, Nil, String, Float, Bool, Option(Nil))) {
          v.0
        },
      ),
      builder.required(
        "a",
        builder.number(),
        fn(v: #(String, Float, Bool, Nil, String, Float, Bool, Option(Nil))) {
          v.1
        },
      ),
      builder.required(
        "y",
        builder.boolean(),
        fn(v: #(String, Float, Bool, Nil, String, Float, Bool, Option(Nil))) {
          v.2
        },
      ),
      builder.required(
        "b",
        builder.null(),
        fn(v: #(String, Float, Bool, Nil, String, Float, Bool, Option(Nil))) {
          v.3
        },
      ),
      builder.required(
        "x",
        builder.string(),
        fn(v: #(String, Float, Bool, Nil, String, Float, Bool, Option(Nil))) {
          v.4
        },
      ),
      builder.required(
        "c",
        builder.number(),
        fn(v: #(String, Float, Bool, Nil, String, Float, Bool, Option(Nil))) {
          v.5
        },
      ),
      builder.required(
        "w",
        builder.boolean(),
        fn(v: #(String, Float, Bool, Nil, String, Float, Bool, Option(Nil))) {
          v.6
        },
      ),
      builder.optional(
        "d",
        builder.null(),
        fn(v: #(String, Float, Bool, Nil, String, Float, Bool, Option(Nil))) {
          v.7
        },
      ),
    ),
    #("a", 2.0, True, Nil, "e", 6.0, False, Some(Nil)),
  )
}

pub fn shared_tree_schema_builder_definition_conflicts_test() -> Nil {
  let f = builder.factory("com.example")
  let same_array = builder.array(f, "Child", builder.string())
  let same_map = builder.map(f, "Child", builder.string())
  builder.object2(
    f,
    "Parent",
    fn(a: List(String), b: dict.Dict(String, String)) { #(a, b) },
    builder.required(
      "a",
      same_array,
      fn(v: #(List(String), dict.Dict(String, String))) { v.0 },
    ),
    builder.required(
      "b",
      same_map,
      fn(v: #(List(String), dict.Dict(String, String))) { v.1 },
    ),
  )
  |> builder.root
  |> builder.compile
  |> expect.to_be_error
  builder.object2(
    f,
    "Duplicate",
    fn(a: String, b: String) { #(a, b) },
    builder.required("a", builder.string(), fn(v: #(String, String)) { v.0 }),
    builder.required("a", builder.string(), fn(v: #(String, String)) { v.1 }),
  )
  |> builder.root
  |> builder.compile
  |> expect.to_be_error
  builder.object0(builder.factory(""), "Empty")
  |> builder.root
  |> builder.compile
  |> expect.to_be_error
  Nil
}

pub fn shared_tree_schema_builder_shared_definitions_test() -> Nil {
  let f = builder.factory("com.example")
  let child = builder.array(f, "Child", builder.string())
  let p1 =
    builder.required("z", child, fn(v: #(List(String), List(String))) { v.0 })
  let p2 =
    builder.required(
      "a",
      builder.array(f, "Child", builder.string()),
      fn(v: #(List(String), List(String))) { v.1 },
    )
  let assert Ok(first) =
    builder.object2(f, "Parent", fn(a, b) { #(a, b) }, p1, p2)
    |> builder.root
    |> builder.compile
  let assert Ok(second) =
    builder.object2(f, "Parent", fn(b, a) { #(a, b) }, p2, p1)
    |> builder.root
    |> builder.compile
  json.to_string(schema.stored_to_json(builder.stored(first)))
  |> expect.to_equal(
    json.to_string(schema.stored_to_json(builder.stored(second))),
  )
  round_trip(
    builder.object2(
      f,
      "CrossFactory",
      fn(a: List(String), b: Nil) { #(a, b) },
      builder.required("a", child, fn(v: #(List(String), Nil)) { v.0 }),
      builder.required(
        "b",
        builder.object0(builder.factory("other"), "Empty"),
        fn(v: #(List(String), Nil)) { v.1 },
      ),
    ),
    #(["one"], Nil),
  )
}

pub fn shared_tree_schema_builder_object_failures_test() -> Nil {
  let assert Ok(compiled) = card_node() |> builder.root |> builder.compile
  [
    types.ObjectValue("Other", [#("title", types.StringValue("x"))]),
    types.ObjectValue("com.example.Card", []),
    types.ObjectValue("com.example.Card", [#("title", types.NumberValue(1.0))]),
    types.ObjectValue("com.example.Card", [
      #("title", types.StringValue("x")),
      #("extra", types.NullValue),
    ]),
    types.ObjectValue("com.example.Card", [
      #("title", types.StringValue("x")),
      #("title", types.StringValue("y")),
    ]),
    types.ObjectValue("com.example.Card", [
      #("title", types.StringValue("x")),
      #("owner", types.NullValue),
    ]),
  ]
  |> list.each(fn(value) {
    builder.decode(compiled, Some(value)) |> expect.to_be_error
    Nil
  })
  let assert Ok(empty) =
    builder.object0(builder.factory("com.example"), "Empty")
    |> builder.root
    |> builder.compile
  builder.decode(
    empty,
    Some(types.ObjectValue("com.example.Empty", [#("extra", types.NullValue)])),
  )
  |> expect.to_be_error
  Nil
}

pub fn shared_tree_schema_builder_optional_null_property_test() -> Nil {
  let node =
    builder.object1(
      builder.factory("com.example"),
      "MaybeNull",
      fn(a) { a },
      builder.optional("value", builder.null(), fn(value) { value }),
    )
  let assert Ok(compiled) = node |> builder.root |> builder.compile
  builder.encode(compiled, None)
  |> expect.to_equal(Ok(Some(types.ObjectValue("com.example.MaybeNull", []))))
  builder.encode(compiled, Some(Nil))
  |> expect.to_equal(
    Ok(
      Some(
        types.ObjectValue("com.example.MaybeNull", [#("value", types.NullValue)]),
      ),
    ),
  )
  round_trip(node, None)
  round_trip(node, Some(Nil))
}

pub fn shared_tree_schema_builder_nested_error_paths_test() -> Nil {
  let assert Ok(compiled) =
    builder.array(builder.factory("com.example"), "Cards", card_node())
    |> builder.root
    |> builder.compile
  let assert Error(types.InvalidEdit(path, _)) =
    builder.decode(
      compiled,
      Some(
        types.ArrayValue("com.example.Cards", [
          types.ObjectValue("com.example.Card", [
            #("title", types.NumberValue(1.0)),
          ]),
        ]),
      ),
    )
  path |> expect.to_equal(["0", "title"])
}

pub fn shared_tree_schema_builder_array_round_trip_test() {
  let assert Ok(compiled) =
    builder.array(builder.factory("com.example"), "Words", builder.string())
    |> builder.root
    |> builder.compile
  let expected =
    Some(
      types.ArrayValue("com.example.Words", [
        types.StringValue("first"),
        types.StringValue("second"),
      ]),
    )
  builder.encode(compiled, ["first", "second"])
  |> expect.to_equal(Ok(expected))
  builder.decode(compiled, expected)
  |> expect.to_equal(Ok(["first", "second"]))
  builder.encode(compiled, [])
  |> expect.to_equal(Ok(Some(types.ArrayValue("com.example.Words", []))))
  builder.decode(compiled, Some(types.ArrayValue("Other", [])))
  |> expect.to_be_error
  Nil
}

pub fn shared_tree_schema_builder_maps_round_trip_test() {
  let assert Ok(compiled) =
    builder.map(builder.factory("com.example"), "Numbers", builder.number())
    |> builder.root
    |> builder.compile
  let value =
    dict.from_list([#("2", 2.0), #("__proto__", 3.0), #("", 0.0), #("10", 1.0)])
  let expected =
    Some(
      types.MapValue("com.example.Numbers", [
        #("", types.NumberValue(0.0)),
        #("10", types.NumberValue(1.0)),
        #("2", types.NumberValue(2.0)),
        #("__proto__", types.NumberValue(3.0)),
      ]),
    )
  builder.encode(compiled, value) |> expect.to_equal(Ok(expected))
  builder.decode(compiled, expected) |> expect.to_equal(Ok(value))
  builder.encode(compiled, dict.new())
  |> expect.to_equal(Ok(Some(types.MapValue("com.example.Numbers", []))))
  builder.decode(compiled, Some(types.MapValue("Other", [])))
  |> expect.to_be_error
  builder.decode(
    compiled,
    Some(
      types.MapValue("com.example.Numbers", [
        #("x", types.NumberValue(1.0)),
        #("x", types.NumberValue(2.0)),
      ]),
    ),
  )
  |> expect.to_be_error
  Nil
}

pub fn shared_tree_schema_builder_nested_collections_test() {
  let factory = builder.factory("com.example.nested")
  let assert Ok(arrays) =
    builder.array(
      factory,
      "Rows",
      builder.map(factory, "Row", builder.string()),
    )
    |> builder.root
    |> builder.compile
  let values = [dict.from_list([#("key", "value")]), dict.new()]
  let assert Ok(snapshot) = builder.encode(arrays, values)
  builder.decode(arrays, snapshot) |> expect.to_equal(Ok(values))
  let assert Ok(maps) =
    builder.map(
      factory,
      "Groups",
      builder.array(factory, "Group", builder.string()),
    )
    |> builder.root
    |> builder.compile
  let values = dict.from_list([#("first", ["a", "b"]), #("empty", [])])
  let assert Ok(snapshot) = builder.encode(maps, values)
  builder.decode(maps, snapshot) |> expect.to_equal(Ok(values))
}

pub fn shared_tree_schema_builder_rejects_empty_names_test() {
  [#("", "Words"), #("com.example", ""), #("", "")]
  |> list.each(fn(names) {
    builder.array(builder.factory(names.0), names.1, builder.string())
    |> builder.root
    |> builder.compile
    |> expect.to_be_error
    builder.map(builder.factory(names.0), names.1, builder.string())
    |> builder.root
    |> builder.compile
    |> expect.to_be_error
  })
}

pub fn shared_tree_schema_builder_string_root_test() {
  let assert Ok(compiled) = builder.string() |> builder.root |> builder.compile
  builder.encode(compiled, "hello")
  |> expect.to_equal(Ok(Some(types.StringValue("hello"))))
  builder.decode(compiled, Some(types.StringValue("hello")))
  |> expect.to_equal(Ok("hello"))
  builder.decode(compiled, None) |> expect.to_be_error
  builder.decode(compiled, Some(types.NumberValue(1.0))) |> expect.to_be_error
  schema.can_view(builder.stored(compiled), builder.view(compiled))
  |> expect.to_equal(Ok(Nil))
  json.to_string(schema.stored_to_json(builder.stored(compiled)))
  |> expect.to_equal(
    "{\"nodes\":{\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}}},\"root\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.string\"]},\"version\":2}",
  )
}

pub fn shared_tree_schema_builder_leaf_roots_test() {
  let assert Ok(number) = builder.number() |> builder.root |> builder.compile
  builder.encode(number, 1.5)
  |> expect.to_equal(Ok(Some(types.NumberValue(1.5))))
  builder.decode(number, Some(types.NumberValue(1.5)))
  |> expect.to_equal(Ok(1.5))
  let assert Ok(boolean) = builder.boolean() |> builder.root |> builder.compile
  builder.encode(boolean, True)
  |> expect.to_equal(Ok(Some(types.BooleanValue(True))))
  builder.decode(boolean, Some(types.BooleanValue(True)))
  |> expect.to_equal(Ok(True))
  let assert Ok(null) = builder.null() |> builder.root |> builder.compile
  builder.encode(null, Nil) |> expect.to_equal(Ok(Some(types.NullValue)))
  builder.decode(null, Some(types.NullValue)) |> expect.to_equal(Ok(Nil))
  let assert Ok(reference) = handle.reference_from_path("/B/child")
  let assert Ok(handles) = builder.handle() |> builder.root |> builder.compile
  builder.encode(handles, reference)
  |> expect.to_equal(Ok(Some(types.HandleValue(reference))))
  builder.decode(handles, Some(types.HandleValue(reference)))
  |> expect.to_equal(Ok(reference))
}

pub fn shared_tree_schema_builder_optional_roots_test() {
  let assert Ok(text) =
    builder.string() |> builder.optional_root |> builder.compile
  builder.encode(text, None) |> expect.to_equal(Ok(None))
  builder.encode(text, Some("x"))
  |> expect.to_equal(Ok(Some(types.StringValue("x"))))
  builder.decode(text, None) |> expect.to_equal(Ok(None))
  builder.decode(text, Some(types.StringValue("x")))
  |> expect.to_equal(Ok(Some("x")))
  builder.decode(text, Some(types.NullValue)) |> expect.to_be_error
  let assert Ok(null) =
    builder.null() |> builder.optional_root |> builder.compile
  builder.encode(null, None) |> expect.to_equal(Ok(None))
  builder.encode(null, Some(Nil)) |> expect.to_equal(Ok(Some(types.NullValue)))
  builder.decode(null, None) |> expect.to_equal(Ok(None))
  builder.decode(null, Some(types.NullValue)) |> expect.to_equal(Ok(Some(Nil)))
}
