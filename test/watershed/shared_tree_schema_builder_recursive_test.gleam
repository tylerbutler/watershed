import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import simplifile
import startest/expect
import watershed/json_ot
import watershed/tree/schema
import watershed/tree/schema_builder as builder

type Outline {
  Outline(label: String, children: List(Outline))
}

fn outline() -> builder.Node(Outline) {
  let f = builder.factory("com.example.typed")
  let self = builder.lazy(f, "Outline", outline)
  builder.object2(
    f,
    "Outline",
    Outline,
    builder.required("label", builder.string(), fn(v: Outline) { v.label }),
    builder.required(
      "children",
      builder.array(f, "Children", self),
      fn(v: Outline) { v.children },
    ),
  )
}

fn round_trip(node: builder.Node(a), value: a) -> Nil {
  let assert Ok(compiled) = node |> builder.root |> builder.compile
  let assert Ok(encoded) = builder.encode(compiled, value)
  builder.decode(compiled, encoded) |> expect.to_equal(Ok(value))
}

pub fn typed_recursive_round_trip_test() {
  round_trip(
    outline(),
    Outline("root", [Outline("left", []), Outline("right", [])]),
  )
  let deep =
    list.repeat(Nil, 100)
    |> list.fold(Outline("leaf", []), fn(child, _) {
      Outline("parent", [child])
    })
  round_trip(outline(), deep)
  round_trip(outline(), Outline("wide", list.repeat(Outline("leaf", []), 100)))
}

type MutualA {
  MutualA(next: Option(MutualB))
}

type MutualB {
  MutualB(next: Option(MutualA))
}

fn mutual_a() -> builder.Node(MutualA) {
  let f = builder.factory("com.example.typed")
  builder.object1(
    f,
    "MutualA",
    MutualA,
    builder.optional(
      "next",
      builder.lazy(f, "MutualB", mutual_b),
      fn(v: MutualA) { v.next },
    ),
  )
}

fn mutual_b() -> builder.Node(MutualB) {
  let f = builder.factory("com.example.typed")
  builder.object1(
    f,
    "MutualB",
    MutualB,
    builder.optional(
      "next",
      builder.lazy(f, "MutualA", mutual_a),
      fn(v: MutualB) { v.next },
    ),
  )
}

pub fn typed_recursive_mutual_test() {
  round_trip(mutual_a(), MutualA(Some(MutualB(Some(MutualA(None))))))
}

type Child {
  Null
  Node(OptionalNode)
}

type OptionalNode {
  OptionalNode(child: Option(Child))
}

fn optional_node() -> builder.Node(OptionalNode) {
  let f = builder.factory("com.example.typed")
  let child =
    builder.union([
      builder.variant(builder.null(), fn(_) { Null }, fn(v) {
        case v {
          Null -> Some(Nil)
          Node(_) -> None
        }
      }),
      builder.variant(
        builder.lazy(f, "OptionalNode", optional_node),
        Node,
        fn(v) {
          case v {
            Node(child) -> Some(child)
            Null -> None
          }
        },
      ),
    ])
  builder.object1(
    f,
    "OptionalNode",
    OptionalNode,
    builder.optional("child", child, fn(v: OptionalNode) { v.child }),
  )
}

pub fn typed_recursive_optional_null_test() {
  [
    OptionalNode(None),
    OptionalNode(Some(Null)),
    OptionalNode(Some(Node(OptionalNode(None)))),
  ]
  |> list.each(fn(value) { round_trip(optional_node(), value) })
}

pub fn typed_recursive_invalid_resolution_test() {
  let f = builder.factory("com.example")
  let invalid: List(builder.Node(Nil)) = [
    builder.lazy(f, "Expected", fn() { builder.object0(f, "Other") }),
    builder.lazy(f, "Expected", fn() {
      builder.lazy(f, "Expected", fn() { builder.object0(f, "Expected") })
    }),
    builder.lazy(f, "Expected", fn() { builder.null() }),
    builder.lazy(f, "Expected", fn() {
      builder.union([
        builder.variant(builder.object0(f, "Expected"), fn(v) { v }, Some),
        builder.variant(builder.object0(f, "Other"), fn(v) { v }, Some),
      ])
    }),
    builder.lazy(f, "Expected", fn() {
      builder.object0(builder.factory(""), "Expected")
    }),
    builder.lazy(f, "", fn() { builder.object0(f, "") }),
  ]
  invalid
  |> list.each(fn(node) {
    node |> builder.root |> builder.compile |> expect.to_be_error
    Nil
  })
}

pub fn typed_recursive_conflicting_lazy_definitions_test() {
  let f = builder.factory("com.example")
  let first = builder.lazy(f, "Same", fn() { builder.object0(f, "Same") })
  let second =
    builder.lazy(f, "Same", fn() {
      builder.object1(
        f,
        "Same",
        fn(_) { Nil },
        builder.required("label", builder.string(), fn(_) { "" }),
      )
    })
  let parent =
    builder.object2(
      f,
      "Parent",
      fn(_, _) { Nil },
      builder.required("first", first, fn(_) { Nil }),
      builder.required("second", second, fn(_) { Nil }),
    )
  let assert Error(_) = parent |> builder.root |> builder.compile
  Nil
}

pub fn typed_recursive_repeated_container_conflicts_test() {
  let f = builder.factory("com.example")
  let empty = builder.object0(f, "Target")
  let nonempty =
    builder.object1(
      f,
      "Target",
      fn(_) { Nil },
      builder.required("label", builder.string(), fn(_) { "" }),
    )
  let wrap = fn(child) {
    builder.object1(
      f,
      "Wrapper",
      fn(_) { Nil },
      builder.required("child", child, fn(_) { Nil }),
    )
  }
  let lazy_empty = builder.lazy(f, "Wrapper", fn() { wrap(empty) })
  let lazy_nonempty = builder.lazy(f, "Wrapper", fn() { wrap(nonempty) })
  [
    #(wrap(empty), wrap(nonempty)),
    #(wrap(empty), lazy_nonempty),
    #(lazy_empty, wrap(nonempty)),
    #(lazy_empty, lazy_nonempty),
  ]
  |> list.each(fn(pair) {
    let parent =
      builder.object2(
        f,
        "Parent",
        fn(_, _) { Nil },
        builder.required("first", pair.0, fn(_) { Nil }),
        builder.required("second", pair.1, fn(_) { Nil }),
      )
    let assert Error(_) = parent |> builder.root |> builder.compile
    Nil
  })
}

fn required_cycle() -> builder.Node(Nil) {
  let f = builder.factory("com.example")
  builder.object1(
    f,
    "Cycle",
    fn(_) { Nil },
    builder.required("child", builder.lazy(f, "Cycle", required_cycle), fn(_) {
      Nil
    }),
  )
}

pub fn typed_recursive_required_cycle_follows_parser_test() {
  let native =
    schema.stored_from_string(
      "{\"version\":2,\"nodes\":{\"com.example.Cycle\":{\"kind\":{\"object\":{\"child\":{\"kind\":\"Value\",\"types\":[\"com.example.Cycle\"]}}}}},\"root\":{\"kind\":\"Value\",\"types\":[\"com.example.Cycle\"]}}",
    )
  case native, required_cycle() |> builder.root |> builder.compile {
    Ok(expected), Ok(compiled) ->
      schema.stored_to_json(builder.stored(compiled))
      |> json.to_string
      |> expect.to_equal(schema.stored_to_json(expected) |> json.to_string)
    Error(_), Error(_) -> Nil
    _, _ ->
      "Required cycle differs from native schema validation"
      |> expect.to_equal("Required cycle follows native schema validation")
  }
}

pub fn typed_recursive_pinned_schemas_test() {
  let row = {
    use id <- decode.field("id", decode.string)
    use value <- decode.field("schema", json_ot.decoder())
    decode.success(#(id, value))
  }
  let envelope = {
    use rows <- decode.field("schemas", decode.list(row))
    decode.success(rows)
  }
  let assert Ok(raw) =
    simplifile.read("test/fixtures/shared_tree/typed-api-authoring.json")
  let assert Ok(rows) = json.parse(raw, envelope)
  [
    #("recursive-outline", schema_of(outline())),
    #("mutual-recursion", schema_of(mutual_a())),
    #("optional-recursive-null", schema_of(optional_node())),
  ]
  |> list.each(fn(entry) {
    let assert Ok(persisted) = list.key_find(rows, entry.0)
    let assert Ok(expected) =
      schema.stored_from_json(json_ot.to_json(persisted))
    entry.1
    |> schema.stored_to_json
    |> json.to_string
    |> expect.to_equal(expected |> schema.stored_to_json |> json.to_string)
  })
}

fn schema_of(node: builder.Node(a)) -> schema.StoredSchema {
  let assert Ok(compiled) = node |> builder.root |> builder.compile
  builder.stored(compiled)
}
