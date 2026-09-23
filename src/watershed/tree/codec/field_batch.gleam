//// Restricted nonincremental FieldBatch V2 codec.

import gleam/float
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import watershed/json_ot.{
  type JsonValue, NFloat, NInt, VArray, VBool, VNull, VNumber, VObject, VString,
}
import watershed/tree/types.{
  type TreeError, type TreeValue, BooleanValue, CorruptData, NullValue,
  NumberValue, ObjectValue, StringValue, UnsupportedFeature, UnsupportedFormat,
}

const max_safe_integer = 9_007_199_254_740_991

const largest_finite = 1.7976931348623157e308

const string_leaf = "com.fluidframework.leaf.string"

const number_leaf = "com.fluidframework.leaf.number"

const boolean_leaf = "com.fluidframework.leaf.boolean"

const null_leaf = "com.fluidframework.leaf.null"

const handle_leaf = "com.fluidframework.leaf.handle"

const identifier_node = "com.fluidframework.node.identifier"

type Identifier {
  InlineIdentifier(String)
  IndexedIdentifier(Int)
}

type ValueShape {
  OptionalValue
  PresentValue
  AbsentValue
  ConstantValue(JsonValue)
  IdentifierValue
}

type Shape {
  NestedArray(Int)
  InlineArray(length: Int, shape: Int)
  Node(
    type_id: Option(Identifier),
    value: ValueShape,
    fields: List(#(Identifier, Int)),
    extra_fields: Option(Int),
  )
  Any
}

type Batch {
  Batch(
    identifiers: List(String),
    shapes: List(Shape),
    data: List(List(JsonValue)),
  )
}

/// Decode one self-describing FieldBatch V2 value.
pub fn decode(encoded: Json) -> Result(List(List(TreeValue)), TreeError) {
  use value <- result.try(
    json_ot.parse_json(json.to_string(encoded))
    |> result.map_error(fn(_) {
      CorruptData("fieldBatch", "value is not valid JSON")
    }),
  )
  use batch <- result.try(decode_batch(value))
  let Batch(identifiers:, shapes:, data:) = batch
  index_try_map(data, fn(stream, index) {
    let location = "fieldBatch.data[" <> int.to_string(index) <> "]"
    use #(encoded_shape, stream) <- result.try(read(stream, location))
    use shape <- result.try(structural_index(
      encoded_shape,
      location <> ".shape",
    ))
    use #(values, rest) <- result.try(decode_shape(
      shape,
      shapes,
      identifiers,
      stream,
      [],
      location,
    ))
    case rest {
      [] -> Ok(values)
      _ -> Error(CorruptData(location, "stream has trailing values"))
    }
  })
}

/// Encode fields with the upstream uncompressed FieldBatch V2 shapes.
pub fn encode(fields: List(List(TreeValue))) -> Result(Json, TreeError) {
  use data <- result.try(
    index_try_map(fields, fn(field, field_index) {
      use values <- result.try(
        index_try_map(field, fn(value, value_index) {
          encode_node(
            value,
            "fieldBatch.data["
              <> int.to_string(field_index)
              <> "]["
              <> int.to_string(value_index)
              <> "]",
          )
        }),
      )
      Ok(
        VArray([
          VNumber(NInt(1)),
          VArray(list.flatten(values)),
        ]),
      )
    }),
  )
  Ok(
    VObject([
      #("version", VNumber(NInt(2))),
      #("identifiers", VArray([])),
      #(
        "shapes",
        VArray([
          VObject([#("c", VObject([#("extraFields", VNumber(NInt(1)))]))]),
          VObject([#("a", VNumber(NInt(0)))]),
        ]),
      ),
      #("data", VArray(data)),
    ])
    |> json_ot.to_json,
  )
}

fn decode_batch(value: JsonValue) -> Result(Batch, TreeError) {
  use members <- result.try(object(value, "fieldBatch"))
  use _ <- result.try(only_keys(
    members,
    ["version", "identifiers", "shapes", "data"],
    "fieldBatch",
  ))
  use version <- result.try(required(members, "version", "fieldBatch.version"))
  use version <- result.try(structural_int(version, "fieldBatch.version"))
  use _ <- result.try(case version {
    2 -> Ok(Nil)
    other -> Error(UnsupportedFormat("FieldBatch", int.to_string(other)))
  })
  use identifiers_value <- result.try(required(
    members,
    "identifiers",
    "fieldBatch.identifiers",
  ))
  use identifier_values <- result.try(array(
    identifiers_value,
    "fieldBatch.identifiers",
  ))
  use identifiers <- result.try(
    index_try_map(identifier_values, fn(value, index) {
      case value {
        VString(value) -> Ok(value)
        _ ->
          Error(CorruptData(
            "fieldBatch.identifiers[" <> int.to_string(index) <> "]",
            "identifier must be a string",
          ))
      }
    }),
  )
  use shapes_value <- result.try(required(
    members,
    "shapes",
    "fieldBatch.shapes",
  ))
  use shape_values <- result.try(array(shapes_value, "fieldBatch.shapes"))
  use shapes <- result.try(
    index_try_map(shape_values, fn(value, index) {
      decode_shape_record(value, index)
    }),
  )
  use data_value <- result.try(required(members, "data", "fieldBatch.data"))
  use data_values <- result.try(array(data_value, "fieldBatch.data"))
  use data <- result.try(
    index_try_map(data_values, fn(value, index) {
      array(value, "fieldBatch.data[" <> int.to_string(index) <> "]")
    }),
  )
  Ok(Batch(identifiers:, shapes:, data:))
}

fn decode_shape_record(
  value: JsonValue,
  index: Int,
) -> Result(Shape, TreeError) {
  let location = "fieldBatch.shapes[" <> int.to_string(index) <> "]"
  use members <- result.try(object(value, location))
  case members {
    [#("a", encoded)] ->
      structural_index(encoded, location <> ".a") |> result.map(NestedArray)
    [#("b", encoded)] -> decode_inline_shape(encoded, location <> ".b")
    [#("c", encoded)] -> decode_node_shape(encoded, location <> ".c")
    [#("d", VNumber(NInt(0)))] -> Ok(Any)
    [#("d", _)] ->
      Error(CorruptData(location <> ".d", "polymorphic shape must be zero"))
    [#("e", _)] ->
      Error(UnsupportedFeature(location <> ".e", "incremental chunks"))
    [#(name, _)] ->
      Error(CorruptData(location, "unknown shape discriminator " <> name))
    [] -> Error(CorruptData(location, "shape discriminator is missing"))
    _ ->
      Error(CorruptData(location, "shape must have exactly one discriminator"))
  }
}

fn decode_inline_shape(
  value: JsonValue,
  location: String,
) -> Result(Shape, TreeError) {
  use members <- result.try(object(value, location))
  use _ <- result.try(only_keys(members, ["length", "shape"], location))
  use length <- result.try(required(members, "length", location <> ".length"))
  use length <- result.try(structural_int(length, location <> ".length"))
  use shape <- result.try(required(members, "shape", location <> ".shape"))
  use shape <- result.try(structural_index(shape, location <> ".shape"))
  Ok(InlineArray(length:, shape:))
}

fn decode_node_shape(
  value: JsonValue,
  location: String,
) -> Result(Shape, TreeError) {
  use members <- result.try(object(value, location))
  use _ <- result.try(only_keys(
    members,
    ["type", "value", "fields", "extraFields"],
    location,
  ))
  use type_id <- result.try(case optional(members, "type") {
    None -> Ok(None)
    Some(value) ->
      decode_identifier(value, location <> ".type") |> result.map(Some)
  })
  use value_shape <- result.try(case optional(members, "value") {
    None -> Ok(OptionalValue)
    Some(VBool(True)) -> Ok(PresentValue)
    Some(VBool(False)) -> Ok(AbsentValue)
    Some(VArray([constant])) -> Ok(ConstantValue(constant))
    Some(VNumber(NInt(0))) ->
      Error(UnsupportedFeature(location <> ".value", "identifier values"))
    Some(_) -> Error(CorruptData(location <> ".value", "invalid value shape"))
  })
  use fields <- result.try(case optional(members, "fields") {
    None -> Ok([])
    Some(value) -> decode_fixed_fields(value, location <> ".fields")
  })
  use extra_fields <- result.try(case optional(members, "extraFields") {
    None -> Ok(None)
    Some(value) ->
      structural_index(value, location <> ".extraFields") |> result.map(Some)
  })
  Ok(Node(type_id:, value: value_shape, fields:, extra_fields:))
}

fn decode_fixed_fields(
  value: JsonValue,
  location: String,
) -> Result(List(#(Identifier, Int)), TreeError) {
  use values <- result.try(array(value, location))
  index_try_map(values, fn(value, index) {
    let item_location = location <> "[" <> int.to_string(index) <> "]"
    use pair <- result.try(array(value, item_location))
    case pair {
      [key, shape] -> {
        use key <- result.try(decode_identifier(key, item_location <> "[0]"))
        use shape <- result.try(structural_index(shape, item_location <> "[1]"))
        Ok(#(key, shape))
      }
      _ -> Error(CorruptData(item_location, "field shape must have two items"))
    }
  })
}

fn decode_shape(
  index: Int,
  shapes: List(Shape),
  identifiers: List(String),
  stream: List(JsonValue),
  active: List(Int),
  location: String,
) -> Result(#(List(TreeValue), List(JsonValue)), TreeError) {
  use _ <- result.try(case list.contains(active, index) {
    True ->
      Error(CorruptData(location, "shape recursion does not consume input"))
    False -> Ok(Nil)
  })
  use shape <- result.try(
    at(shapes, index, location <> ".shape")
    |> result.map_error(fn(_) {
      CorruptData(location, "shape index is out of bounds")
    }),
  )
  let active = [index, ..active]
  case shape {
    NestedArray(child) ->
      decode_nested(child, shapes, identifiers, stream, location)
    InlineArray(length, child) ->
      decode_inline(
        length,
        child,
        shapes,
        identifiers,
        stream,
        active,
        location,
      )
    Node(type_id, value, fields, extra_fields) ->
      decode_node(
        type_id,
        value,
        fields,
        extra_fields,
        shapes,
        identifiers,
        stream,
        active,
        location,
      )
    Any -> {
      use #(encoded_index, rest) <- result.try(read(stream, location))
      use child <- result.try(structural_index(
        encoded_index,
        location <> ".shape",
      ))
      decode_shape(child, shapes, identifiers, rest, [], location)
    }
  }
}

fn decode_nested(
  child: Int,
  shapes: List(Shape),
  identifiers: List(String),
  stream: List(JsonValue),
  location: String,
) -> Result(#(List(TreeValue), List(JsonValue)), TreeError) {
  use #(encoded, rest) <- result.try(read(stream, location))
  case encoded {
    VArray(inner) -> {
      use values <- result.try(decode_until_empty(
        child,
        shapes,
        identifiers,
        inner,
        [],
        location,
      ))
      Ok(#(values, rest))
    }
    _ -> {
      use count <- result.try(structural_int(encoded, location <> ".length"))
      use values <- result.try(decode_count(
        child,
        count,
        shapes,
        identifiers,
        [],
        location,
      ))
      Ok(#(values, rest))
    }
  }
}

fn decode_until_empty(
  child: Int,
  shapes: List(Shape),
  identifiers: List(String),
  stream: List(JsonValue),
  values: List(TreeValue),
  location: String,
) -> Result(List(TreeValue), TreeError) {
  case stream {
    [] -> Ok(list.reverse(values))
    _ -> {
      let before = list.length(stream)
      use #(decoded, rest) <- result.try(decode_shape(
        child,
        shapes,
        identifiers,
        stream,
        [],
        location,
      ))
      use _ <- result.try(case list.length(rest) < before {
        True -> Ok(Nil)
        False ->
          Error(CorruptData(location, "nested array item consumed no input"))
      })
      decode_until_empty(
        child,
        shapes,
        identifiers,
        rest,
        list.append(list.reverse(decoded), values),
        location,
      )
    }
  }
}

fn decode_count(
  child: Int,
  count: Int,
  shapes: List(Shape),
  identifiers: List(String),
  values: List(TreeValue),
  location: String,
) -> Result(List(TreeValue), TreeError) {
  case count {
    0 -> Ok(list.reverse(values))
    _ -> {
      use #(decoded, rest) <- result.try(decode_shape(
        child,
        shapes,
        identifiers,
        [],
        [],
        location,
      ))
      use _ <- result.try(case rest {
        [] -> Ok(Nil)
        _ -> Error(CorruptData(location, "zero-sized item left input"))
      })
      decode_count(
        child,
        count - 1,
        shapes,
        identifiers,
        list.append(list.reverse(decoded), values),
        location,
      )
    }
  }
}

fn decode_inline(
  count: Int,
  child: Int,
  shapes: List(Shape),
  identifiers: List(String),
  stream: List(JsonValue),
  active: List(Int),
  location: String,
) -> Result(#(List(TreeValue), List(JsonValue)), TreeError) {
  case count {
    0 -> Ok(#([], stream))
    _ -> {
      use #(first, rest) <- result.try(decode_shape(
        child,
        shapes,
        identifiers,
        stream,
        active,
        location,
      ))
      let next_active = case list.length(rest) < list.length(stream) {
        True -> []
        False -> active
      }
      use #(remaining, rest) <- result.try(decode_inline(
        count - 1,
        child,
        shapes,
        identifiers,
        rest,
        next_active,
        location,
      ))
      Ok(#(list.append(first, remaining), rest))
    }
  }
}

fn decode_node(
  type_id: Option(Identifier),
  value_shape: ValueShape,
  fixed_fields: List(#(Identifier, Int)),
  extra_fields: Option(Int),
  shapes: List(Shape),
  identifiers: List(String),
  stream: List(JsonValue),
  active: List(Int),
  location: String,
) -> Result(#(List(TreeValue), List(JsonValue)), TreeError) {
  let initial_length = list.length(stream)
  use #(type_id, stream) <- result.try(case type_id {
    Some(type_id) ->
      resolve_identifier(type_id, identifiers, location <> ".type")
      |> result.map(fn(type_id) { #(type_id, stream) })
    None -> {
      use #(encoded, rest) <- result.try(read(stream, location <> ".type"))
      use identifier <- result.try(decode_identifier(
        encoded,
        location <> ".type",
      ))
      resolve_identifier(identifier, identifiers, location <> ".type")
      |> result.map(fn(type_id) { #(type_id, rest) })
    }
  })
  use #(value, stream) <- result.try(decode_value(
    value_shape,
    stream,
    location <> ".value",
  ))
  let active = case list.length(stream) {
    length if length < initial_length -> []
    _ -> active
  }
  use #(fields, seen, stream) <- result.try(decode_fixed_field_values(
    fixed_fields,
    shapes,
    identifiers,
    stream,
    active,
    [],
    [],
    location,
  ))
  use #(fields, stream) <- result.try(case extra_fields {
    None -> Ok(#(fields, stream))
    Some(shape) -> {
      use #(encoded, rest) <- result.try(read(
        stream,
        location <> ".extraFields",
      ))
      use inner <- result.try(array(encoded, location <> ".extraFields"))
      use #(fields, _) <- result.try(decode_extra_fields(
        shape,
        shapes,
        identifiers,
        inner,
        fields,
        seen,
        location <> ".extraFields",
      ))
      Ok(#(fields, rest))
    }
  })
  use value <- result.try(typed_value(
    type_id,
    value,
    list.reverse(fields),
    location,
  ))
  Ok(#([value], stream))
}

fn decode_fixed_field_values(
  fields: List(#(Identifier, Int)),
  shapes: List(Shape),
  identifiers: List(String),
  stream: List(JsonValue),
  active: List(Int),
  decoded: List(#(String, TreeValue)),
  seen: List(String),
  location: String,
) -> Result(
  #(List(#(String, TreeValue)), List(String), List(JsonValue)),
  TreeError,
) {
  case fields {
    [] -> Ok(#(decoded, seen, stream))
    [field, ..rest] -> {
      use key <- result.try(resolve_identifier(
        field.0,
        identifiers,
        location <> ".fields",
      ))
      use #(values, remaining) <- result.try(decode_shape(
        field.1,
        shapes,
        identifiers,
        stream,
        active,
        location <> ".fields." <> key,
      ))
      use #(decoded, seen) <- result.try(add_field(
        decoded,
        seen,
        key,
        values,
        location,
      ))
      let next_active = case list.length(remaining) < list.length(stream) {
        True -> []
        False -> active
      }
      decode_fixed_field_values(
        rest,
        shapes,
        identifiers,
        remaining,
        next_active,
        decoded,
        seen,
        location,
      )
    }
  }
}

fn decode_extra_fields(
  shape: Int,
  shapes: List(Shape),
  identifiers: List(String),
  stream: List(JsonValue),
  fields: List(#(String, TreeValue)),
  seen: List(String),
  location: String,
) -> Result(#(List(#(String, TreeValue)), List(String)), TreeError) {
  case stream {
    [] -> Ok(#(fields, seen))
    [encoded_key, ..rest] -> {
      use key_identifier <- result.try(decode_identifier(
        encoded_key,
        location <> ".key",
      ))
      use key <- result.try(resolve_identifier(
        key_identifier,
        identifiers,
        location <> ".key",
      ))
      use #(values, rest) <- result.try(decode_shape(
        shape,
        shapes,
        identifiers,
        rest,
        [],
        location <> "." <> key,
      ))
      use #(fields, seen) <- result.try(add_field(
        fields,
        seen,
        key,
        values,
        location,
      ))
      decode_extra_fields(
        shape,
        shapes,
        identifiers,
        rest,
        fields,
        seen,
        location,
      )
    }
  }
}

fn add_field(
  fields: List(#(String, TreeValue)),
  seen: List(String),
  key: String,
  values: List(TreeValue),
  location: String,
) -> Result(#(List(#(String, TreeValue)), List(String)), TreeError) {
  use _ <- result.try(case list.contains(seen, key) {
    True -> Error(CorruptData(location, "node has duplicate field " <> key))
    False -> Ok(Nil)
  })
  case values {
    [] -> Ok(#(fields, [key, ..seen]))
    [value] -> Ok(#([#(key, value), ..fields], [key, ..seen]))
    _ ->
      Error(UnsupportedFeature(
        location <> "." <> key,
        "fields containing multiple trees",
      ))
  }
}

fn decode_value(
  shape: ValueShape,
  stream: List(JsonValue),
  location: String,
) -> Result(#(Option(JsonValue), List(JsonValue)), TreeError) {
  case shape {
    OptionalValue -> {
      use #(present, rest) <- result.try(read(stream, location))
      case present {
        VBool(False) -> Ok(#(None, rest))
        VBool(True) -> {
          use #(value, rest) <- result.try(read(rest, location))
          Ok(#(Some(value), rest))
        }
        _ -> Error(CorruptData(location, "value presence must be a boolean"))
      }
    }
    PresentValue -> {
      use #(value, rest) <- result.try(read(stream, location))
      Ok(#(Some(value), rest))
    }
    AbsentValue -> Ok(#(None, stream))
    ConstantValue(value) -> Ok(#(Some(value), stream))
    IdentifierValue -> Error(UnsupportedFeature(location, "identifier values"))
  }
}

fn typed_value(
  type_id: String,
  value: Option(JsonValue),
  fields: List(#(String, TreeValue)),
  location: String,
) -> Result(TreeValue, TreeError) {
  case type_id {
    type_id if type_id == string_leaf -> {
      use _ <- result.try(no_fields(fields, location))
      case value {
        Some(VString(value)) -> Ok(StringValue(value))
        _ -> Error(CorruptData(location, "string leaf has an invalid value"))
      }
    }
    type_id if type_id == number_leaf -> {
      use _ <- result.try(no_fields(fields, location))
      use number <- result.try(case value {
        Some(VNumber(NFloat(value))) -> Ok(value)
        Some(VNumber(NInt(value))) ->
          float.parse(with_point(int.to_string(value)))
          |> result.map_error(fn(_) {
            CorruptData(location, "number leaf is outside the finite range")
          })
        _ -> Error(CorruptData(location, "number leaf has an invalid value"))
      })
      use _ <- result.try(case finite(number) {
        True -> Ok(Nil)
        False ->
          Error(CorruptData(location, "number leaf is outside the finite range"))
      })
      Ok(
        NumberValue(case number == 0.0 {
          True -> 0.0
          False -> number
        }),
      )
    }
    type_id if type_id == boolean_leaf -> {
      use _ <- result.try(no_fields(fields, location))
      case value {
        Some(VBool(value)) -> Ok(BooleanValue(value))
        _ -> Error(CorruptData(location, "boolean leaf has an invalid value"))
      }
    }
    type_id if type_id == null_leaf -> {
      use _ <- result.try(no_fields(fields, location))
      case value {
        Some(VNull) -> Ok(NullValue)
        _ -> Error(CorruptData(location, "null leaf has an invalid value"))
      }
    }
    type_id if type_id == handle_leaf ->
      Error(UnsupportedFeature(location, "handle leaves"))
    type_id if type_id == identifier_node ->
      Error(UnsupportedFeature(location, "identifier nodes"))
    _ ->
      case string.starts_with(type_id, "com.fluidframework.leaf.") {
        True -> Error(UnsupportedFeature(location, "leaf type " <> type_id))
        False ->
          case value {
            None -> Ok(ObjectValue(type_id, fields))
            Some(_) ->
              Error(UnsupportedFeature(location, "object nodes with values"))
          }
      }
  }
}

fn no_fields(
  fields: List(#(String, TreeValue)),
  location: String,
) -> Result(Nil, TreeError) {
  case fields {
    [] -> Ok(Nil)
    _ -> Error(CorruptData(location, "leaf node has fields"))
  }
}

fn encode_node(
  value: TreeValue,
  location: String,
) -> Result(List(JsonValue), TreeError) {
  case value {
    StringValue(value) ->
      Ok([VString(string_leaf), VBool(True), VString(value), VArray([])])
    NumberValue(value) -> {
      use _ <- result.try(case finite(value) {
        True -> Ok(Nil)
        False ->
          Error(CorruptData(location, "number is outside the finite range"))
      })
      Ok([
        VString(number_leaf),
        VBool(True),
        VNumber(
          NFloat(case value == 0.0 {
            True -> 0.0
            False -> value
          }),
        ),
        VArray([]),
      ])
    }
    BooleanValue(value) ->
      Ok([VString(boolean_leaf), VBool(True), VBool(value), VArray([])])
    NullValue -> Ok([VString(null_leaf), VBool(True), VNull, VArray([])])
    ObjectValue(type_id, fields) -> {
      use encoded_fields <- result.try(
        list.try_fold(fields, [], fn(encoded, field) {
          use _ <- result.try(
            case list.any(encoded, fn(value) { value == VString(field.0) }) {
              True ->
                Error(CorruptData(
                  location,
                  "node has duplicate field " <> field.0,
                ))
              False -> Ok(Nil)
            },
          )
          use child <- result.try(encode_node(
            field.1,
            location <> "." <> field.0,
          ))
          Ok(list.append(encoded, [VString(field.0), VArray(child)]))
        }),
      )
      Ok([VString(type_id), VBool(False), VArray(encoded_fields)])
    }
  }
}

fn decode_identifier(
  value: JsonValue,
  location: String,
) -> Result(Identifier, TreeError) {
  case value {
    VString(value) -> Ok(InlineIdentifier(value))
    _ -> structural_index(value, location) |> result.map(IndexedIdentifier)
  }
}

fn resolve_identifier(
  identifier: Identifier,
  identifiers: List(String),
  location: String,
) -> Result(String, TreeError) {
  case identifier {
    InlineIdentifier(value) -> Ok(value)
    IndexedIdentifier(index) ->
      at(identifiers, index, location)
      |> result.map_error(fn(_) {
        CorruptData(location, "identifier index is out of bounds")
      })
  }
}

fn structural_index(
  value: JsonValue,
  location: String,
) -> Result(Int, TreeError) {
  structural_int(value, location)
}

fn structural_int(
  value: JsonValue,
  location: String,
) -> Result(Int, TreeError) {
  case value {
    VNumber(NInt(value)) if value >= 0 && value <= max_safe_integer -> Ok(value)
    _ -> Error(CorruptData(location, "expected a safe nonnegative integer"))
  }
}

fn finite(value: Float) -> Bool {
  float.absolute_value(value) <=. largest_finite
}

fn with_point(text: String) -> String {
  case string.split_once(text, "e") {
    Ok(#(mantissa, exponent)) -> pointed(mantissa) <> "e" <> exponent
    Error(_) -> pointed(text)
  }
}

fn pointed(mantissa: String) -> String {
  case string.contains(mantissa, ".") {
    True -> mantissa
    False -> mantissa <> ".0"
  }
}

fn object(
  value: JsonValue,
  location: String,
) -> Result(List(#(String, JsonValue)), TreeError) {
  case value {
    VObject(members) -> Ok(members)
    _ -> Error(CorruptData(location, "expected an object"))
  }
}

fn array(
  value: JsonValue,
  location: String,
) -> Result(List(JsonValue), TreeError) {
  case value {
    VArray(values) -> Ok(values)
    _ -> Error(CorruptData(location, "expected an array"))
  }
}

fn optional(
  members: List(#(String, JsonValue)),
  key: String,
) -> Option(JsonValue) {
  case list.key_find(members, key) {
    Ok(value) -> Some(value)
    Error(Nil) -> None
  }
}

fn required(
  members: List(#(String, JsonValue)),
  key: String,
  location: String,
) -> Result(JsonValue, TreeError) {
  case optional(members, key) {
    Some(value) -> Ok(value)
    None -> Error(CorruptData(location, "required property is missing"))
  }
}

fn only_keys(
  members: List(#(String, JsonValue)),
  keys: List(String),
  location: String,
) -> Result(Nil, TreeError) {
  list.try_each(members, fn(member) {
    case list.contains(keys, member.0) {
      True -> Ok(Nil)
      False -> Error(CorruptData(location, "unknown property " <> member.0))
    }
  })
}

fn read(
  stream: List(JsonValue),
  location: String,
) -> Result(#(JsonValue, List(JsonValue)), TreeError) {
  case stream {
    [value, ..rest] -> Ok(#(value, rest))
    [] -> Error(CorruptData(location, "stream is truncated"))
  }
}

fn at(
  values: List(value),
  index: Int,
  location: String,
) -> Result(value, TreeError) {
  case index, values {
    0, [value, ..] -> Ok(value)
    index, [_, ..rest] if index > 0 -> at(rest, index - 1, location)
    _, _ -> Error(CorruptData(location, "index is out of bounds"))
  }
}

fn index_try_map(
  values: List(a),
  function: fn(a, Int) -> Result(b, error),
) -> Result(List(b), error) {
  index_try_map_loop(values, function, 0, [])
}

fn index_try_map_loop(
  values: List(a),
  function: fn(a, Int) -> Result(b, error),
  index: Int,
  mapped: List(b),
) -> Result(List(b), error) {
  case values {
    [] -> Ok(list.reverse(mapped))
    [value, ..rest] -> {
      use value <- result.try(function(value, index))
      index_try_map_loop(rest, function, index + 1, [value, ..mapped])
    }
  }
}
