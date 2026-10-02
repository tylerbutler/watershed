//// Restricted nonincremental FieldBatch V2 codec.

import gleam/float
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import watershed/fluid_ids
import watershed/json_ot.{
  type JsonValue, NFloat, NInt, VArray, VBool, VNull, VNumber, VObject, VString,
}
import watershed/tree/schema
import watershed/tree/types.{
  type TreeError, type TreeValue, ArrayValue, BooleanValue, CorruptData,
  MapValue, NullValue, NumberValue, ObjectValue, StringValue, UnsupportedFeature,
  UnsupportedFormat,
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

type RawNode {
  RawNode(
    schema_id: String,
    value: Option(JsonValue),
    fields: List(#(String, List(RawNode))),
  )
}

type EncodeValueShape {
  EncodePresentValue
  EncodeAbsentValue
  EncodeNullValue
  EncodeIdentifierValue
}

type EncodeShape {
  EncodeNode(
    type_id: String,
    value: EncodeValueShape,
    fields: List(#(String, EncodeShape)),
  )
}

type EncodedTree {
  EncodedTree(shape: EncodeShape, data: List(JsonValue))
}

pub type IdContext {
  MessageIds(compressor: fluid_ids.Compressor, originator: fluid_ids.SessionId)
  SummaryIds(compressor: fluid_ids.Compressor)
}

/// Decode one self-describing FieldBatch V2 value.
pub fn decode(encoded: Json) -> Result(List(List(TreeValue)), TreeError) {
  decode_fields(encoded, None, None)
}

fn decode_fields(
  encoded: Json,
  stored: Option(schema.StoredSchema),
  ids: Option(IdContext),
) -> Result(List(List(TreeValue)), TreeError) {
  use fields <- result.try(decode_raw(encoded, ids))
  index_try_map(fields, fn(field, field_index) {
    index_try_map(field, fn(value, value_index) {
      raw_value(
        value,
        stored,
        "fieldBatch.data["
          <> int.to_string(field_index)
          <> "]["
          <> int.to_string(value_index)
          <> "]",
      )
    })
  })
}

fn decode_raw(
  encoded: Json,
  ids: Option(IdContext),
) -> Result(List(List(RawNode)), TreeError) {
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
      ids,
    ))
    case rest {
      [] -> Ok(values)
      _ -> Error(CorruptData(location, "stream has trailing values"))
    }
  })
}

/// Decode FieldBatch V2 content and classify structural nodes with stored schema.
pub fn decode_with_schema(
  encoded: Json,
  stored: Option(schema.StoredSchema),
) -> Result(List(List(TreeValue)), TreeError) {
  decode_fields(encoded, stored, None)
}

pub fn decode_with_context(
  encoded: Json,
  stored: Option(schema.StoredSchema),
  ids: IdContext,
) -> Result(List(List(TreeValue)), TreeError) {
  decode_fields(encoded, stored, Some(ids))
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
          VObject([#("a", VNumber(NInt(2)))]),
          VObject([#("d", VNumber(NInt(0)))]),
          VObject([
            #(
              "c",
              VObject([
                #("type", VString(null_leaf)),
                #("value", VArray([VNull])),
              ]),
            ),
          ]),
        ]),
      ),
      #("data", VArray(data)),
    ])
    |> json_ot.to_json,
  )
}

/// Encode fields and verify structural node kinds against stored schema.
pub fn encode_with_schema(
  fields: List(List(TreeValue)),
  stored: Option(schema.StoredSchema),
) -> Result(Json, TreeError) {
  use _ <- result.try(case stored {
    None -> Ok([])
    Some(stored) ->
      index_try_map(fields, fn(field, field_index) {
        index_try_map(field, fn(value, value_index) {
          validate_value_kind(
            value,
            stored,
            "fieldBatch.data["
              <> int.to_string(field_index)
              <> "]["
              <> int.to_string(value_index)
              <> "]",
          )
        })
      })
  })
  encode(fields)
}

pub fn encode_with_context(
  fields: List(List(TreeValue)),
  stored: Option(schema.StoredSchema),
  ids: IdContext,
) -> Result(Json, TreeError) {
  case stored {
    None -> encode(fields)
    Some(stored) -> {
      case encode_compressed_fields(fields, stored, ids) {
        Ok(encoded) -> Ok(encoded)
        Error(Nil) -> encode_with_context_generic(fields, stored, ids)
      }
    }
  }
}

fn encode_with_context_generic(
  fields: List(List(TreeValue)),
  stored: schema.StoredSchema,
  ids: IdContext,
) -> Result(Json, TreeError) {
  use data <- result.try(
    index_try_map(fields, fn(field, field_index) {
      use values <- result.try(
        index_try_map(field, fn(value, value_index) {
          let location =
            "fieldBatch.data["
            <> int.to_string(field_index)
            <> "]["
            <> int.to_string(value_index)
            <> "]"
          use _ <- result.try(validate_value_kind(value, stored, location))
          encode_node_with_context(
            value,
            stored,
            schema.root_field_schema(stored),
            ids,
            location,
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
          VObject([
            #("c", VObject([#("extraFields", VNumber(NInt(1)))])),
          ]),
          VObject([#("a", VNumber(NInt(2)))]),
          VObject([#("d", VNumber(NInt(0)))]),
          VObject([
            #(
              "c",
              VObject([
                #("type", VString(null_leaf)),
                #("value", VArray([VNull])),
              ]),
            ),
          ]),
          VObject([
            #(
              "c",
              VObject([
                #("type", VString(string_leaf)),
                #("value", VNumber(NInt(0))),
              ]),
            ),
          ]),
        ]),
      ),
      #("data", VArray(data)),
    ])
    |> json_ot.to_json,
  )
}

fn encode_compressed_fields(
  fields: List(List(TreeValue)),
  stored: schema.StoredSchema,
  ids: IdContext,
) -> Result(Json, Nil) {
  use encoded_fields <- result.try(
    list.try_map(fields, fn(field) {
      case field {
        [value] ->
          encode_compressed_tree(
            value,
            stored,
            inferred_field_schema(value),
            ids,
          )
          |> result.map(fn(tree) { [tree] })
        _ -> Error(Nil)
      }
    }),
  )
  let trees = list.flatten(encoded_fields)
  let shapes =
    trees
    |> list.map(fn(tree) { tree.shape })
    |> discover_shapes
  let identifiers =
    shapes
    |> list.flat_map(shape_identifiers)
    |> counted_identifiers
  let data =
    list.map(encoded_fields, fn(field) {
      VArray(
        list.flat_map(field, fn(tree) {
          [VNumber(NInt(shape_index(shapes, tree.shape))), ..tree.data]
        }),
      )
    })
  Ok(
    VObject([
      #("version", VNumber(NInt(2))),
      #("identifiers", VArray(list.map(identifiers, VString))),
      #(
        "shapes",
        VArray(
          list.map(shapes, fn(shape) {
            encode_compressed_shape(shape, shapes, identifiers)
          }),
        ),
      ),
      #("data", VArray(data)),
    ])
    |> json_ot.to_json,
  )
}

fn inferred_field_schema(value: TreeValue) -> schema.FieldSchema {
  let type_id = case value {
    StringValue(_) -> string_leaf
    NumberValue(_) -> number_leaf
    BooleanValue(_) -> boolean_leaf
    NullValue -> null_leaf
    ObjectValue(type_id, _) | MapValue(type_id, _) | ArrayValue(type_id, _) ->
      type_id
  }
  schema.FieldSchema(schema.Required, [type_id])
}

fn encode_compressed_tree(
  value: TreeValue,
  stored: schema.StoredSchema,
  definition: schema.FieldSchema,
  ids: IdContext,
) -> Result(EncodedTree, Nil) {
  let schema.FieldSchema(cardinality, allowed_types) = definition
  use type_id <- result.try(single(allowed_types))
  use node <- result.try(
    schema.node_schema(stored, type_id) |> result.map_error(fn(_) { Nil }),
  )
  case node, value {
    schema.Leaf(schema.StringLeaf), StringValue(value) -> {
      case cardinality {
        schema.Identifier -> {
          use encoded <- result.try(
            encode_identifier(value, ids, "fieldBatch")
            |> result.map_error(fn(_) { Nil }),
          )
          Ok(
            EncodedTree(EncodeNode(type_id, EncodeIdentifierValue, []), [
              encoded,
            ]),
          )
        }
        _ ->
          Ok(
            EncodedTree(EncodeNode(type_id, EncodePresentValue, []), [
              VString(value),
            ]),
          )
      }
    }
    schema.Leaf(schema.NumberLeaf), NumberValue(value) ->
      Ok(
        EncodedTree(EncodeNode(type_id, EncodePresentValue, []), [
          VNumber(NFloat(value)),
        ]),
      )
    schema.Leaf(schema.BooleanLeaf), BooleanValue(value) ->
      Ok(
        EncodedTree(EncodeNode(type_id, EncodePresentValue, []), [VBool(value)]),
      )
    schema.Leaf(schema.NullLeaf), NullValue ->
      Ok(EncodedTree(EncodeNode(type_id, EncodeNullValue, []), []))
    schema.Object(definitions), ObjectValue(value_type, fields)
      if value_type == type_id
    -> {
      use encoded <- result.try(
        list.try_map(definitions, fn(definition) {
          use field_value <- result.try(
            list.key_find(fields, definition.0)
            |> result.map_error(fn(_) { Nil }),
          )
          use tree <- result.try(encode_compressed_tree(
            field_value,
            stored,
            definition.1,
            ids,
          ))
          Ok(#(definition.0, tree))
        }),
      )
      Ok(EncodedTree(
        EncodeNode(
          type_id,
          EncodeAbsentValue,
          list.map(encoded, fn(entry) { #(entry.0, entry.1.shape) }),
        ),
        list.flat_map(encoded, fn(entry) { entry.1.data }),
      ))
    }
    _, _ -> Error(Nil)
  }
}

fn discover_shapes(roots: List(EncodeShape)) -> List(EncodeShape) {
  discover_shape_children(list.unique(roots), list.unique(roots))
}

fn discover_shape_children(
  remaining: List(EncodeShape),
  found: List(EncodeShape),
) -> List(EncodeShape) {
  case remaining {
    [] -> found
    [shape, ..rest] -> {
      let children = shape_children(shape)
      let new_children =
        list.filter(children, fn(child) { !list.contains(found, child) })
      discover_shape_children(
        list.append(rest, new_children),
        list.append(found, new_children),
      )
    }
  }
}

fn shape_children(shape: EncodeShape) -> List(EncodeShape) {
  let EncodeNode(_, _, fields) = shape
  list.map(fields, fn(field) { field.1 })
}

fn shape_identifiers(shape: EncodeShape) -> List(String) {
  let EncodeNode(type_id, _, fields) = shape
  [type_id, ..list.map(fields, fn(field) { field.0 })]
}

fn counted_identifiers(values: List(String)) -> List(String) {
  values
  |> list.unique
  |> list.filter(fn(value) {
    values
    |> list.filter(fn(candidate) { candidate == value })
    |> list.length
    |> fn(count) { count > 1 }
  })
}

fn encode_compressed_shape(
  shape: EncodeShape,
  shapes: List(EncodeShape),
  identifiers: List(String),
) -> JsonValue {
  let EncodeNode(type_id, value, fields) = shape
  let value_members = case value {
    EncodePresentValue -> [#("value", VBool(True))]
    EncodeAbsentValue -> [#("value", VBool(False))]
    EncodeNullValue -> [#("value", VArray([VNull]))]
    EncodeIdentifierValue -> [#("value", VNumber(NInt(0)))]
  }
  let field_members = case fields {
    [] -> []
    _ -> [
      #(
        "fields",
        VArray(
          list.map(fields, fn(field) {
            VArray([
              encode_identifier_token(field.0, identifiers),
              VNumber(NInt(shape_index(shapes, field.1))),
            ])
          }),
        ),
      ),
    ]
  }
  VObject([
    #(
      "c",
      VObject([
        #("type", encode_identifier_token(type_id, identifiers)),
        ..list.append(value_members, field_members)
      ]),
    ),
  ])
}

fn encode_identifier_token(
  value: String,
  identifiers: List(String),
) -> JsonValue {
  case index_of(identifiers, value, 0) {
    Some(index) -> VNumber(NInt(index))
    None -> VString(value)
  }
}

fn shape_index(shapes: List(EncodeShape), shape: EncodeShape) -> Int {
  case index_of(shapes, shape, 0) {
    Some(index) -> index
    None -> 0
  }
}

fn index_of(values: List(a), target: a, index: Int) -> Option(Int) {
  case values {
    [] -> None
    [value, ..rest] ->
      case value == target {
        True -> Some(index)
        False -> index_of(rest, target, index + 1)
      }
  }
}

fn single(values: List(a)) -> Result(a, Nil) {
  case values {
    [value] -> Ok(value)
    _ -> Error(Nil)
  }
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
    Some(VNumber(NInt(0))) -> Ok(IdentifierValue)
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
  ids: Option(IdContext),
) -> Result(#(List(RawNode), List(JsonValue)), TreeError) {
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
      decode_nested(child, shapes, identifiers, stream, location, ids)
    InlineArray(length, child) ->
      decode_inline(
        length,
        child,
        shapes,
        identifiers,
        stream,
        active,
        location,
        ids,
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
        ids,
      )
    Any -> {
      use #(encoded_index, rest) <- result.try(read(stream, location))
      use child <- result.try(structural_index(
        encoded_index,
        location <> ".shape",
      ))
      decode_shape(child, shapes, identifiers, rest, [], location, ids)
    }
  }
}

fn decode_nested(
  child: Int,
  shapes: List(Shape),
  identifiers: List(String),
  stream: List(JsonValue),
  location: String,
  ids: Option(IdContext),
) -> Result(#(List(RawNode), List(JsonValue)), TreeError) {
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
        ids,
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
        ids,
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
  values: List(RawNode),
  location: String,
  ids: Option(IdContext),
) -> Result(List(RawNode), TreeError) {
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
        ids,
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
        ids,
      )
    }
  }
}

fn decode_count(
  child: Int,
  count: Int,
  shapes: List(Shape),
  identifiers: List(String),
  values: List(RawNode),
  location: String,
  ids: Option(IdContext),
) -> Result(List(RawNode), TreeError) {
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
        ids,
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
        ids,
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
  ids: Option(IdContext),
) -> Result(#(List(RawNode), List(JsonValue)), TreeError) {
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
        ids,
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
        ids,
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
  ids: Option(IdContext),
) -> Result(#(List(RawNode), List(JsonValue)), TreeError) {
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
    ids,
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
    ids,
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
        ids,
      ))
      Ok(#(fields, rest))
    }
  })
  use value <- result.try(raw_node(
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
  decoded: List(#(String, List(RawNode))),
  seen: List(String),
  location: String,
  ids: Option(IdContext),
) -> Result(
  #(List(#(String, List(RawNode))), List(String), List(JsonValue)),
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
        ids,
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
        ids,
      )
    }
  }
}

fn decode_extra_fields(
  shape: Int,
  shapes: List(Shape),
  identifiers: List(String),
  stream: List(JsonValue),
  fields: List(#(String, List(RawNode))),
  seen: List(String),
  location: String,
  ids: Option(IdContext),
) -> Result(#(List(#(String, List(RawNode))), List(String)), TreeError) {
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
        ids,
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
        ids,
      )
    }
  }
}

fn add_field(
  fields: List(#(String, List(RawNode))),
  seen: List(String),
  key: String,
  values: List(RawNode),
  location: String,
) -> Result(#(List(#(String, List(RawNode))), List(String)), TreeError) {
  use _ <- result.try(case list.contains(seen, key) {
    True -> Error(CorruptData(location, "node has duplicate field " <> key))
    False -> Ok(Nil)
  })
  Ok(#([#(key, values), ..fields], [key, ..seen]))
}

fn decode_value(
  shape: ValueShape,
  stream: List(JsonValue),
  location: String,
  ids: Option(IdContext),
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
    IdentifierValue -> {
      use #(value, rest) <- result.try(read(stream, location))
      case value {
        VString(_) -> Ok(#(Some(value), rest))
        VNumber(NInt(value)) ->
          decode_compressed_identifier(value, ids, location)
          |> result.map(fn(value) { #(Some(VString(value)), rest) })
        _ -> Error(CorruptData(location, "identifier value is invalid"))
      }
    }
  }
}

fn decode_compressed_identifier(
  value: Int,
  ids: Option(IdContext),
  location: String,
) -> Result(String, TreeError) {
  case ids {
    None ->
      Error(UnsupportedFeature(
        location,
        "numeric identifier decoding requires an ID context",
      ))
    Some(MessageIds(compressor, originator)) -> {
      use operation <- result.try(
        fluid_ids.op_id(value)
        |> result.map_error(fn(error) { id_error(location, error) }),
      )
      use session_space <- result.try(
        fluid_ids.from_op(compressor, operation, originator)
        |> result.map_error(fn(error) { id_error(location, error) }),
      )
      fluid_ids.decompress(compressor, session_space)
      |> result.map(fluid_ids.stable_id_to_string)
      |> result.map_error(fn(error) { id_error(location, error) })
    }
    Some(SummaryIds(compressor)) ->
      case value < 0 {
        True ->
          Error(CorruptData(location, "summary identifier must be finalized"))
        False -> {
          use session_space <- result.try(
            fluid_ids.session_space_id(value)
            |> result.map_error(fn(error) { id_error(location, error) }),
          )
          fluid_ids.decompress(compressor, session_space)
          |> result.map(fluid_ids.stable_id_to_string)
          |> result.map_error(fn(error) { id_error(location, error) })
        }
      }
  }
}

fn raw_node(
  type_id: String,
  value: Option(JsonValue),
  fields: List(#(String, List(RawNode))),
  location: String,
) -> Result(RawNode, TreeError) {
  case type_id == handle_leaf || type_id == identifier_node {
    True ->
      Error(
        UnsupportedFeature(location, case type_id == handle_leaf {
          True -> "handle leaves"
          False -> "identifier nodes"
        }),
      )
    False -> Ok(RawNode(type_id, value, fields))
  }
}

// ponytail: Conventional conversion function naming. Use an x_to_y name, for
// example raw_node_to_tree_value.
fn raw_value(
  node: RawNode,
  stored: Option(schema.StoredSchema),
  location: String,
) -> Result(TreeValue, TreeError) {
  let RawNode(type_id, value, fields) = node
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
        False -> structural_value(type_id, value, fields, stored, location)
      }
  }
}

fn no_fields(
  fields: List(#(String, List(RawNode))),
  location: String,
) -> Result(Nil, TreeError) {
  case list.all(fields, fn(field) { list.is_empty(field.1) }) {
    True -> Ok(Nil)
    False -> Error(CorruptData(location, "leaf node has fields"))
  }
}

fn structural_value(
  type_id: String,
  value: Option(JsonValue),
  fields: List(#(String, List(RawNode))),
  stored: Option(schema.StoredSchema),
  location: String,
) -> Result(TreeValue, TreeError) {
  use _ <- result.try(case value {
    None -> Ok(Nil)
    Some(_) -> Error(UnsupportedFeature(location, "object nodes with values"))
  })
  case stored {
    None ->
      singleton_fields(fields, None, location)
      |> result.map(ObjectValue(type_id, _))
    Some(stored) -> {
      use node <- result.try(schema.node_schema(stored, type_id))
      case node {
        schema.Object(_) ->
          singleton_fields(fields, Some(stored), location)
          |> result.map(ObjectValue(type_id, _))
        schema.Map(_) ->
          singleton_fields(fields, Some(stored), location)
          |> result.map(MapValue(type_id, _))
        schema.Array(_) -> {
          use elements <- result.try(array_field(fields, location))
          use elements <- result.try(
            list.try_map(elements, fn(element) {
              raw_value(element, Some(stored), location <> ".")
            }),
          )
          Ok(ArrayValue(type_id, elements))
        }
        schema.Leaf(_) ->
          Error(CorruptData(location, "leaf node uses a structural shape"))
      }
    }
  }
}

fn singleton_fields(
  fields: List(#(String, List(RawNode))),
  stored: Option(schema.StoredSchema),
  location: String,
) -> Result(List(#(String, TreeValue)), TreeError) {
  list.try_fold(fields, [], fn(decoded, field) {
    case field.1 {
      [] -> Ok(decoded)
      [value] -> {
        use value <- result.try(raw_value(
          value,
          stored,
          location <> "." <> field.0,
        ))
        Ok([#(field.0, value), ..decoded])
      }
      _ ->
        Error(UnsupportedFeature(
          location <> "." <> field.0,
          "fields containing multiple trees",
        ))
    }
  })
  |> result.map(list.reverse)
}

fn array_field(
  fields: List(#(String, List(RawNode))),
  location: String,
) -> Result(List(RawNode), TreeError) {
  case fields {
    [] -> Ok([])
    [#("", elements)] -> Ok(elements)
    _ -> Error(CorruptData(location, "array node has an invalid primary field"))
  }
}

fn encode_node(
  value: TreeValue,
  location: String,
) -> Result(List(JsonValue), TreeError) {
  case value {
    StringValue(value) ->
      Ok([
        VNumber(NInt(0)),
        VString(string_leaf),
        VBool(True),
        VString(value),
        VArray([]),
      ])
    NumberValue(value) -> {
      use _ <- result.try(case finite(value) {
        True -> Ok(Nil)
        False ->
          Error(CorruptData(location, "number is outside the finite range"))
      })
      Ok([
        VNumber(NInt(0)),
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
      Ok([
        VNumber(NInt(0)),
        VString(boolean_leaf),
        VBool(True),
        VBool(value),
        VArray([]),
      ])
    NullValue -> Ok([VNumber(NInt(3))])
    ObjectValue(type_id, fields) ->
      encode_structural_node(type_id, fields, location)
    MapValue(type_id, entries) ->
      encode_structural_node(type_id, entries, location)
    ArrayValue(type_id, elements) ->
      encode_array_node(type_id, elements, location)
  }
}

fn encode_node_with_context(
  value: TreeValue,
  stored: schema.StoredSchema,
  definition: schema.FieldSchema,
  ids: IdContext,
  location: String,
) -> Result(List(JsonValue), TreeError) {
  let schema.FieldSchema(cardinality, _) = definition
  case cardinality, value {
    schema.Identifier, StringValue(value) -> {
      use encoded <- result.try(encode_identifier(value, ids, location))
      Ok([VNumber(NInt(4)), encoded])
    }
    _, ObjectValue(type_id, fields) ->
      encode_structural_node_with_context(
        type_id,
        fields,
        stored,
        ids,
        location,
      )
    _, MapValue(type_id, entries) ->
      encode_structural_node_with_context(
        type_id,
        entries,
        stored,
        ids,
        location,
      )
    _, ArrayValue(type_id, elements) ->
      encode_array_node_with_context(type_id, elements, stored, ids, location)
    _, _ -> encode_node(value, location)
  }
}

fn encode_identifier(
  value: String,
  ids: IdContext,
  location: String,
) -> Result(JsonValue, TreeError) {
  case fluid_ids.stable_id(value) {
    Error(_) -> Ok(VString(value))
    Ok(stable) -> {
      let compressor = case ids {
        MessageIds(compressor, _) | SummaryIds(compressor) -> compressor
      }
      case fluid_ids.recompress(compressor, stable) {
        Error(fluid_ids.UnknownId(_)) | Ok(None) -> Ok(VString(value))
        Error(error) -> Error(id_error(location, error))
        Ok(Some(compressed)) ->
          case fluid_ids.to_op(compressor, compressed) {
            Error(fluid_ids.UnknownId(_)) -> Ok(VString(value))
            Error(error) -> Error(id_error(location, error))
            Ok(operation) -> {
              let operation_value = fluid_ids.op_id_to_int(operation)
              case ids {
                SummaryIds(_) if operation_value < 0 -> Ok(VString(value))
                MessageIds(_, _) | SummaryIds(_) ->
                  Ok(VNumber(NInt(operation_value)))
              }
            }
          }
      }
    }
  }
}

fn encode_array_node(
  type_id: String,
  elements: List(TreeValue),
  location: String,
) -> Result(List(JsonValue), TreeError) {
  use encoded <- result.try(
    list.try_map(elements, fn(element) { encode_node(element, location <> ".") }),
  )
  Ok([
    VNumber(NInt(0)),
    VString(type_id),
    VBool(False),
    VArray([
      VString(""),
      VArray(list.flatten(encoded)),
    ]),
  ])
}

fn encode_array_node_with_context(
  type_id: String,
  elements: List(TreeValue),
  stored: schema.StoredSchema,
  ids: IdContext,
  location: String,
) -> Result(List(JsonValue), TreeError) {
  use definition <- result.try(schema.array_element_schema(stored, type_id))
  use encoded <- result.try(
    list.try_map(elements, fn(element) {
      encode_node_with_context(
        element,
        stored,
        definition,
        ids,
        location <> ".",
      )
    }),
  )
  Ok([
    VNumber(NInt(0)),
    VString(type_id),
    VBool(False),
    VArray([
      VString(""),
      VArray(list.flatten(encoded)),
    ]),
  ])
}

fn classify_value(
  value: TreeValue,
  stored: schema.StoredSchema,
  location: String,
) -> Result(TreeValue, TreeError) {
  case value {
    ObjectValue(type_id, fields) -> {
      use fields <- result.try(
        list.try_map(fields, fn(field) {
          classify_value(field.1, stored, location <> "." <> field.0)
          |> result.map(fn(value) { #(field.0, value) })
        }),
      )
      use node <- result.try(schema.node_schema(stored, type_id))
      case node {
        schema.Object(_) -> Ok(ObjectValue(type_id, fields))
        schema.Map(_) -> Ok(MapValue(type_id, fields))
        schema.Array(_) ->
          Error(CorruptData(location, "array node uses an object shape"))
        schema.Leaf(_) ->
          Error(CorruptData(location, "leaf node uses a structural shape"))
      }
    }
    MapValue(type_id, fields) -> {
      use fields <- result.try(
        list.try_map(fields, fn(field) {
          classify_value(field.1, stored, location <> "." <> field.0)
          |> result.map(fn(value) { #(field.0, value) })
        }),
      )
      use node <- result.try(schema.node_schema(stored, type_id))
      case node {
        schema.Map(_) -> Ok(MapValue(type_id, fields))
        schema.Object(_) -> Ok(ObjectValue(type_id, fields))
        schema.Array(_) ->
          Error(CorruptData(location, "array node uses an object shape"))
        schema.Leaf(_) ->
          Error(CorruptData(location, "leaf node uses a structural shape"))
      }
    }
    ArrayValue(type_id, elements) -> {
      use elements <- result.try(
        list.try_map(elements, fn(element) {
          classify_value(element, stored, location <> ".")
        }),
      )
      use node <- result.try(schema.node_schema(stored, type_id))
      case node {
        schema.Array(_) -> Ok(ArrayValue(type_id, elements))
        schema.Object(_) | schema.Map(_) ->
          Error(CorruptData(location, "non-array node uses an array shape"))
        schema.Leaf(_) ->
          Error(CorruptData(location, "leaf node uses an array shape"))
      }
    }
    // ponytail: Match all variants. This catch-all also takes any new TreeValue
    // variant without a compiler error. Name the remaining variants.
    other -> Ok(other)
  }
}

fn validate_value_kind(
  value: TreeValue,
  stored: schema.StoredSchema,
  location: String,
) -> Result(Nil, TreeError) {
  use classified <- result.try(classify_value(value, stored, location))
  case value, classified {
    ObjectValue(_, fields), ObjectValue(_, _) ->
      list.try_each(fields, fn(field) {
        validate_value_kind(field.1, stored, location <> "." <> field.0)
      })
    MapValue(_, entries), MapValue(_, _) ->
      list.try_each(entries, fn(entry) {
        validate_value_kind(entry.1, stored, location <> "." <> entry.0)
      })
    ArrayValue(_, elements), ArrayValue(_, _) ->
      list.try_each(elements, fn(element) {
        validate_value_kind(element, stored, location <> ".")
      })
    ObjectValue(_, _), MapValue(_, _) ->
      Error(CorruptData(location, "object node uses a map schema"))
    MapValue(_, _), ObjectValue(_, _) ->
      Error(CorruptData(location, "map node uses an object schema"))
    _, _ -> Ok(Nil)
  }
}

fn encode_structural_node(
  type_id: String,
  fields: List(#(String, TreeValue)),
  location: String,
) -> Result(List(JsonValue), TreeError) {
  use encoded_fields <- result.try(
    list.try_fold(fields, [], fn(encoded, field) {
      use _ <- result.try(
        case list.any(encoded, fn(value) { value == VString(field.0) }) {
          True ->
            Error(CorruptData(location, "node has duplicate field " <> field.0))
          False -> Ok(Nil)
        },
      )
      use child <- result.try(encode_node(field.1, location <> "." <> field.0))
      Ok(list.append(encoded, [VString(field.0), VArray(child)]))
    }),
  )
  Ok([
    VNumber(NInt(0)),
    VString(type_id),
    VBool(False),
    VArray(encoded_fields),
  ])
}

fn encode_structural_node_with_context(
  type_id: String,
  fields: List(#(String, TreeValue)),
  stored: schema.StoredSchema,
  ids: IdContext,
  location: String,
) -> Result(List(JsonValue), TreeError) {
  use node <- result.try(schema.node_schema(stored, type_id))
  use encoded_fields <- result.try(
    list.try_fold(fields, [], fn(encoded, field) {
      use _ <- result.try(
        case list.any(encoded, fn(value) { value == VString(field.0) }) {
          True ->
            Error(CorruptData(location, "node has duplicate field " <> field.0))
          False -> Ok(Nil)
        },
      )
      use definition <- result.try(case node {
        schema.Object(_) -> schema.field_schema(stored, type_id, field.0)
        schema.Map(definition) -> Ok(definition)
        schema.Array(_) | schema.Leaf(_) ->
          Error(CorruptData(location, "node uses an invalid structural shape"))
      })
      use child <- result.try(encode_node_with_context(
        field.1,
        stored,
        definition,
        ids,
        location <> "." <> field.0,
      ))
      Ok(list.append(encoded, [VString(field.0), VArray(child)]))
    }),
  )
  Ok([
    VNumber(NInt(0)),
    VString(type_id),
    VBool(False),
    VArray(encoded_fields),
  ])
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

fn id_error(location: String, error: fluid_ids.IdError) -> TreeError {
  CorruptData(location, "ID compressor error: " <> string.inspect(error))
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

// ponytail: Use result for fallible functions. This lookup returns Option when
// it finds nothing. Return Result(_, Nil). Each of the four codec modules has a
// copy of this helper and the JSON object, array, and string helpers. Keep one
// copy.
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
