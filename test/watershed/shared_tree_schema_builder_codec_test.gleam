import gleam/list
import gleam/option.{Some}
import startest/expect
import watershed/tree/schema_builder as builder
import watershed/tree/types

pub fn shared_tree_schema_builder_codec_wrong_leaf_test() {
  let assert Ok(compiled) = builder.string() |> builder.root |> builder.compile
  [types.BooleanValue(True), types.NullValue, types.NumberValue(1.0)]
  |> list.each(fn(value) {
    let assert Error(types.InvalidEdit(path, _)) =
      builder.decode(compiled, Some(value))
    path |> expect.to_equal([])
  })
}

@target(javascript)
pub fn shared_tree_schema_builder_codec_non_finite_test() {
  let assert Ok(compiled) = builder.number() |> builder.root |> builder.compile
  let infinity = 1.7976931348623157e308 *. 2.0
  [infinity, 0.0 -. infinity, infinity -. infinity]
  |> list.each(fn(value) {
    builder.encode(compiled, value) |> expect.to_be_error
    builder.decode(compiled, Some(types.NumberValue(value)))
    |> expect.to_be_error
  })
}
