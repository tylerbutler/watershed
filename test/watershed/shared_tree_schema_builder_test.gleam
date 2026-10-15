import gleam/json
import gleam/option.{None, Some}
import startest/expect
import watershed/handle
import watershed/tree/schema
import watershed/tree/schema_builder as builder
import watershed/tree/types

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
