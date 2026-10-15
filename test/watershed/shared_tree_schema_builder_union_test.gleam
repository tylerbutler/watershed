import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import simplifile
import startest/expect
import watershed/json_ot
import watershed/tree/schema
import watershed/tree/schema_builder as builder
import watershed/tree/types

type Choice {
  Text(String)
  Count(Float)
  Flag(Bool)
  Unmatched
}

fn text() -> builder.Variant(Choice) {
  builder.variant(builder.string(), Text, fn(value) {
    case value {
      Text(value) -> Some(value)
      _ -> None
    }
  })
}

fn count() -> builder.Variant(Choice) {
  builder.variant(builder.number(), Count, fn(value) {
    case value {
      Count(value) -> Some(value)
      _ -> None
    }
  })
}

fn choice() -> builder.Node(Choice) {
  builder.union([text(), count()])
}

pub fn typed_union_round_trip_test() {
  let assert Ok(compiled) = choice() |> builder.root |> builder.compile
  builder.encode(compiled, Text("hello"))
  |> expect.to_equal(Ok(Some(types.StringValue("hello"))))
  builder.decode(compiled, Some(types.NumberValue(2.0)))
  |> expect.to_equal(Ok(Count(2.0)))
  builder.decode(compiled, Some(types.BooleanValue(True)))
  |> expect.to_be_error
  Nil
}

pub fn typed_union_invalid_declarations_test() {
  builder.union([]) |> builder.root |> builder.compile |> expect.to_be_error
  builder.union([text(), text()])
  |> builder.root
  |> builder.compile
  |> expect.to_be_error
  builder.union([
    text(),
    builder.variant(choice(), fn(value) { value }, Some),
  ])
  |> builder.root
  |> builder.compile
  |> expect.to_be_error
  Nil
}

pub fn typed_union_exactly_one_projector_test() {
  let assert Ok(compiled) = choice() |> builder.root |> builder.compile
  builder.encode(compiled, Unmatched) |> expect.to_be_error
  let ambiguous =
    builder.union([
      builder.variant(builder.string(), fn(_) { Nil }, fn(_) { Some("") }),
      builder.variant(builder.number(), fn(_) { Nil }, fn(_) { Some(0.0) }),
    ])
  let assert Ok(compiled) = ambiguous |> builder.root |> builder.compile
  builder.encode(compiled, Nil) |> expect.to_be_error
  Nil
}

type Record {
  Record(selected: Choice, other: Option(Choice))
}

fn record() -> builder.Node(Record) {
  builder.object2(
    builder.factory("com.example"),
    "Record",
    Record,
    builder.required("selected", choice(), fn(v: Record) { v.selected }),
    builder.optional("other", choice(), fn(v: Record) { v.other }),
  )
}

fn round_trip(node: builder.Node(a), value: a) -> Nil {
  let assert Ok(compiled) = node |> builder.root |> builder.compile
  let assert Ok(encoded) = builder.encode(compiled, value)
  builder.decode(compiled, encoded) |> expect.to_equal(Ok(value))
}

pub fn typed_union_composition_test() {
  let f = builder.factory("com.example")
  round_trip(record(), Record(Text("selected"), Some(Count(3.0))))
  round_trip(record(), Record(Count(1.0), None))
  round_trip(builder.array(f, "Choices", choice()), [Text("a"), Count(2.0)])
  round_trip(
    builder.map(f, "ByKey", choice()),
    dict.from_list([#("text", Text("a")), #("count", Count(2.0))]),
  )
  let assert Ok(compiled) = record() |> builder.root |> builder.compile
  builder.encode(compiled, Record(Text("a"), Some(Unmatched)))
  |> expect.to_be_error
  let assert Ok(compiled) =
    builder.array(f, "Choices", choice()) |> builder.root |> builder.compile
  builder.encode(compiled, [Unmatched]) |> expect.to_be_error
  let assert Ok(compiled) =
    builder.map(f, "ByKey", choice()) |> builder.root |> builder.compile
  builder.encode(compiled, dict.from_list([#("bad", Unmatched)]))
  |> expect.to_be_error
  Nil
}

pub fn typed_union_nested_and_order_test() {
  let nested =
    builder.union([
      builder.variant(choice(), fn(v) { v }, fn(v) {
        case v {
          Text(_) | Count(_) -> Some(v)
          _ -> None
        }
      }),
      builder.variant(builder.boolean(), Flag, fn(v) {
        case v {
          Flag(value) -> Some(value)
          _ -> None
        }
      }),
    ])
  [Text("a"), Count(2.0), Flag(True)]
  |> list.each(fn(value) { round_trip(nested, value) })
  let assert Ok(first) = choice() |> builder.root |> builder.compile
  let assert Ok(second) =
    builder.union([count(), text()]) |> builder.root |> builder.compile
  builder.stored(first)
  |> schema.stored_to_json
  |> json.to_string
  |> expect.to_equal(
    builder.stored(second) |> schema.stored_to_json |> json.to_string,
  )
}

pub fn typed_union_cross_factory_test() {
  let alternatives =
    builder.union([
      builder.variant(
        builder.object0(builder.factory("com.first"), "Empty"),
        fn(_) { Text("first") },
        fn(_) { None },
      ),
      builder.variant(
        builder.object0(builder.factory("com.second"), "Empty"),
        fn(_) { Text("second") },
        fn(_) { None },
      ),
    ])
  let assert Ok(compiled) = alternatives |> builder.root |> builder.compile
  builder.decode(compiled, Some(types.ObjectValue("com.second.Empty", [])))
  |> expect.to_equal(Ok(Text("second")))
}

pub fn typed_union_pinned_allowed_types_test() {
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
  let assert Ok(persisted) = list.key_find(rows, "union-root")
  let assert Ok(expected) = schema.stored_from_json(json_ot.to_json(persisted))
  let point =
    builder.object1(
      builder.factory("com.example.typed"),
      "Point",
      fn(v) { v },
      builder.required("label", builder.string(), fn(v: String) { v }),
    )
  let node =
    builder.union([
      text(),
      builder.variant(point, Text, fn(_) { None }),
    ])
  let assert Ok(compiled) = node |> builder.root |> builder.compile
  schema.root_field_schema(builder.stored(compiled))
  |> expect.to_equal(schema.root_field_schema(expected))
}
