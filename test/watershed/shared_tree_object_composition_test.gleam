import gleam/option.{type Option, None, Some}
import gleam/result
import startest/expect
import watershed/tree/schema_builder as builder
import watershed/tree/types

type Nine {
  Nine(
    a: String,
    b: String,
    c: String,
    d: String,
    e: String,
    f: String,
    g: String,
    h: String,
    i: String,
  )
}

pub fn tree_api_object_composition_round_trips_nine_properties_test() {
  let a = builder.required("a", builder.string(), fn(v: Nine) { v.a })
  let b = builder.required("b", builder.string(), fn(v: Nine) { v.b })
  let c = builder.required("c", builder.string(), fn(v: Nine) { v.c })
  let d = builder.required("d", builder.string(), fn(v: Nine) { v.d })
  let e = builder.required("e", builder.string(), fn(v: Nine) { v.e })
  let f = builder.required("f", builder.string(), fn(v: Nine) { v.f })
  let g = builder.required("g", builder.string(), fn(v: Nine) { v.g })
  let h = builder.required("h", builder.string(), fn(v: Nine) { v.h })
  let i = builder.required("i", builder.string(), fn(v: Nine) { v.i })
  let node =
    builder.object(
      builder.factory("composition"),
      "Nine",
      [
        builder.property(a),
        builder.property(b),
        builder.property(c),
        builder.property(d),
        builder.property(e),
        builder.property(f),
        builder.property(g),
        builder.property(h),
        builder.property(i),
      ],
      fn(reader) {
        use a <- result.try(builder.read_property(reader, a))
        use b <- result.try(builder.read_property(reader, b))
        use c <- result.try(builder.read_property(reader, c))
        use d <- result.try(builder.read_property(reader, d))
        use e <- result.try(builder.read_property(reader, e))
        use f <- result.try(builder.read_property(reader, f))
        use g <- result.try(builder.read_property(reader, g))
        use h <- result.try(builder.read_property(reader, h))
        use i <- result.try(builder.read_property(reader, i))
        Ok(Nine(a, b, c, d, e, f, g, h, i))
      },
    )
  let assert Ok(compiled) = node |> builder.root |> builder.compile
  let original = Nine("a", "b", "c", "d", "e", "f", "g", "h", "i")
  let assert Ok(encoded) = builder.encode(compiled, original)
  builder.decode(compiled, encoded) |> expect.to_equal(Ok(original))
}

type Label {
  Label(text: String)
}

pub fn tree_api_object_reader_rejects_undeclared_properties_test() {
  let text = builder.required("text", builder.string(), fn(v: Label) { v.text })
  let other =
    builder.required("other", builder.string(), fn(v: Label) { v.text })
  let node =
    builder.object(
      builder.factory("composition"),
      "Label",
      [builder.property(text)],
      fn(reader) { builder.read_property(reader, other) |> result.map(Label) },
    )
  let assert Ok(compiled) = node |> builder.root |> builder.compile
  case
    builder.decode(
      compiled,
      Some(
        types.ObjectValue("composition.Label", [
          #("text", types.StringValue("present")),
        ]),
      ),
    )
  {
    Error(types.InvalidSchema(_)) -> Nil
    _ -> panic as "Expected an undeclared property error"
  }
}

pub fn tree_api_object_reader_rejects_different_field_cardinality_test() {
  let text = builder.required("text", builder.string(), fn(v: Label) { v.text })
  let optional =
    builder.optional("text", builder.string(), fn(v: Label) { Some(v.text) })
  let node =
    builder.object(
      builder.factory("composition"),
      "Label",
      [builder.property(text)],
      fn(reader) {
        use value <- result.try(builder.read_property(reader, optional))
        case value {
          Some(text) -> Ok(Label(text))
          None -> Error(types.InvalidSchema("Expected text"))
        }
      },
    )
  let assert Ok(compiled) = node |> builder.root |> builder.compile
  case
    builder.decode(
      compiled,
      Some(
        types.ObjectValue("composition.Label", [
          #("text", types.StringValue("present")),
        ]),
      ),
    )
  {
    Error(types.InvalidSchema(_)) -> Nil
    _ -> panic as "Expected a property definition error"
  }
}

pub fn tree_api_object_composition_rejects_duplicate_properties_test() {
  let text = builder.required("text", builder.string(), fn(v: Label) { v.text })
  let node =
    builder.object(
      builder.factory("composition"),
      "Label",
      [builder.property(text), builder.property(text)],
      fn(reader) { builder.read_property(reader, text) |> result.map(Label) },
    )
  let _ = node |> builder.root |> builder.compile |> expect.to_be_error
  Nil
}

type Generated {
  Generated(id: builder.Identifier, deleted: Option(Nil))
}

pub fn tree_api_object_composition_preserves_construction_and_null_test() {
  let id = builder.identifier("id", fn(v: Generated) { v.id })
  let deleted =
    builder.optional("deleted", builder.null(), fn(v: Generated) { v.deleted })
  let node =
    builder.object(
      builder.factory("composition"),
      "Generated",
      [builder.property(id), builder.property(deleted)],
      fn(reader) {
        use id <- result.try(builder.read_property(reader, id))
        use deleted <- result.try(builder.read_property(reader, deleted))
        Ok(Generated(id, deleted))
      },
    )
  let assert Ok(compiled) = node |> builder.root |> builder.compile
  builder.encode(compiled, Generated(builder.Generate, None))
  |> expect.to_be_error
  builder.encode_new(compiled, Generated(builder.Generate, None))
  |> expect.to_equal(Ok(Some(types.ObjectValue("composition.Generated", []))))
  builder.encode_new(compiled, Generated(builder.Generate, Some(Nil)))
  |> expect.to_equal(
    Ok(
      Some(
        types.ObjectValue("composition.Generated", [
          #("deleted", types.NullValue),
        ]),
      ),
    ),
  )
  builder.decode(
    compiled,
    Some(
      types.ObjectValue("composition.Generated", [
        #("id", types.StringValue("assigned")),
        #("deleted", types.NullValue),
      ]),
    ),
  )
  |> expect.to_equal(Ok(Generated(builder.Assigned("assigned"), Some(Nil))))
}
