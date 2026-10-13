//// Typed declarations and value adapters for SharedTree schemas.

import gleam/float
import gleam/result
import gleam/string
import watershed/handle
import watershed/tree/schema as tree_schema
import watershed/tree/types

const string_identifier = "com.fluidframework.leaf.string"

const number_identifier = "com.fluidframework.leaf.number"

const boolean_identifier = "com.fluidframework.leaf.boolean"

const handle_identifier = "com.fluidframework.leaf.handle"

const null_identifier = "com.fluidframework.leaf.null"

const largest_finite = 1.7976931348623157e308

pub type Error {
  AccessFailed(reason: String)
  DecodeFailed(reason: String)
  InvalidDeclaration(reason: String)
  MissingRequired(field: String)
}

pub opaque type Required {
  Required
}

pub opaque type Optional {
  Optional
}

pub opaque type Codec(a) {
  Codec(
    identifier: String,
    encode: fn(a) -> Result(types.TreeValue, Error),
    decode: fn(types.TreeValue) -> Result(a, Error),
  )
}

pub opaque type NodeCodec(schema, record) {
  NodeCodec(
    identifier: String,
    decode: fn(types.TreeValue) -> Result(record, Error),
  )
}

pub opaque type Builder(schema, input) {
  Builder(
    identifier: String,
    encode: fn(input) -> Result(types.TreeValue, Error),
  )
}

pub opaque type Schema(schema, record) {
  Schema(view: tree_schema.ViewSchema, root: NodeCodec(schema, record))
}

pub opaque type Field(schema, value, cardinality) {
  Field(
    key: String,
    codec: Codec(value),
    optional: Bool,
    cardinality: cardinality,
  )
}

pub opaque type IdentifierField(schema) {
  IdentifierField(key: String)
}

pub opaque type ChildField(parent, child, record, cardinality) {
  ChildField(
    key: String,
    codec: NodeCodec(child, record),
    optional: Bool,
    cardinality: cardinality,
  )
}

pub opaque type ArrayField(parent, item, record) {
  ArrayField(key: String, identifier: String, codec: NodeCodec(item, record))
}

pub opaque type MapField(parent, item, record) {
  MapField(key: String, identifier: String, codec: NodeCodec(item, record))
}

pub fn string() -> Codec(String) {
  Codec(
    string_identifier,
    fn(value) { Ok(types.StringValue(value)) },
    fn(value) {
      case value {
        types.StringValue(text) -> Ok(text)
        _ -> Error(DecodeFailed("expected a string leaf"))
      }
    },
  )
}

pub fn number() -> Codec(Float) {
  Codec(
    number_identifier,
    fn(value) {
      case finite(value) {
        True -> Ok(types.NumberValue(value))
        False -> Error(DecodeFailed("expected a finite number leaf"))
      }
    },
    fn(value) {
      case value {
        types.NumberValue(number) ->
          case finite(number) {
            True -> Ok(number)
            False -> Error(DecodeFailed("expected a finite number leaf"))
          }
        _ -> Error(DecodeFailed("expected a number leaf"))
      }
    },
  )
}

pub fn boolean() -> Codec(Bool) {
  Codec(
    boolean_identifier,
    fn(value) { Ok(types.BooleanValue(value)) },
    fn(value) {
      case value {
        types.BooleanValue(boolean) -> Ok(boolean)
        _ -> Error(DecodeFailed("expected a boolean leaf"))
      }
    },
  )
}

pub fn null() -> Codec(Nil) {
  Codec(null_identifier, fn(_) { Ok(types.NullValue) }, fn(value) {
    case value {
      types.NullValue -> Ok(Nil)
      _ -> Error(DecodeFailed("expected a null leaf"))
    }
  })
}

pub fn handle() -> Codec(handle.Reference) {
  Codec(
    handle_identifier,
    fn(value) { Ok(types.HandleValue(value)) },
    fn(value) {
      case value {
        types.HandleValue(reference) -> Ok(reference)
        _ -> Error(DecodeFailed("expected a handle leaf"))
      }
    },
  )
}

pub fn encode(codec: Codec(a), value: a) -> Result(types.TreeValue, Error) {
  codec.encode(value)
}

pub fn decode(codec: Codec(a), value: types.TreeValue) -> Result(a, Error) {
  codec.decode(value)
}

pub fn node(
  identifier: String,
  decode: fn(types.TreeValue) -> Result(record, Error),
) -> Result(NodeCodec(schema, record), Error) {
  case valid_identifier(identifier) {
    True -> Ok(NodeCodec(identifier, decode))
    False -> Error(InvalidDeclaration("node identifier is empty or padded"))
  }
}

pub fn builder(
  identifier: String,
  encode: fn(input) -> Result(types.TreeValue, Error),
) -> Result(Builder(schema, input), Error) {
  case valid_identifier(identifier) {
    True -> Ok(Builder(identifier, encode))
    False -> Error(InvalidDeclaration("builder identifier is empty or padded"))
  }
}

pub fn build(
  builder: Builder(schema, input),
  value: input,
) -> Result(types.TreeValue, Error) {
  use encoded <- result.try(builder.encode(value))
  case node_value_identifier(encoded) == builder.identifier {
    True -> Ok(encoded)
    False -> Error(DecodeFailed("expected node " <> builder.identifier))
  }
}

pub fn schema(
  view: tree_schema.ViewSchema,
  root: NodeCodec(schema, record),
) -> Result(Schema(schema, record), Error) {
  let stored = tree_schema.view_to_stored(view)
  use _ <- result.try(case tree_schema.node_schema(stored, root.identifier) {
    Ok(_) -> Ok(Nil)
    Error(_) ->
      Error(InvalidDeclaration("root node is absent: " <> root.identifier))
  })
  let definition = tree_schema.root_field_schema(stored)
  case root_field_matches(definition, root.identifier) {
    True -> Ok(Schema(view, root))
    False ->
      Error(InvalidDeclaration("root does not allow " <> root.identifier))
  }
}

pub fn required(key: String, codec: Codec(a)) -> Field(schema, a, Required) {
  Field(key, codec, False, Required)
}

pub fn optional(key: String, codec: Codec(a)) -> Field(schema, a, Optional) {
  Field(key, codec, True, Optional)
}

pub fn identifier(key: String) -> IdentifierField(schema) {
  IdentifierField(key)
}

pub fn required_child(
  key: String,
  codec: NodeCodec(child, record),
) -> ChildField(parent, child, record, Required) {
  ChildField(key, codec, False, Required)
}

pub fn optional_child(
  key: String,
  codec: NodeCodec(child, record),
) -> ChildField(parent, child, record, Optional) {
  ChildField(key, codec, True, Optional)
}

pub fn array_field(
  key: String,
  array_type: String,
  item: NodeCodec(item, record),
) -> ArrayField(parent, item, record) {
  ArrayField(key, array_type, item)
}

pub fn map_field(
  key: String,
  map_type: String,
  item: NodeCodec(item, record),
) -> MapField(parent, item, record) {
  MapField(key, map_type, item)
}

pub fn schema_view(definition: Schema(s, r)) -> tree_schema.ViewSchema {
  definition.view
}

pub fn schema_root(definition: Schema(s, r)) -> NodeCodec(s, r) {
  definition.root
}

pub fn node_identifier(codec: NodeCodec(s, r)) -> String {
  codec.identifier
}

pub fn decode_node(
  codec: NodeCodec(s, r),
  value: types.TreeValue,
) -> Result(r, Error) {
  case node_value_identifier(value) == codec.identifier {
    True -> codec.decode(value)
    False -> Error(DecodeFailed("expected node " <> codec.identifier))
  }
}

pub fn builder_identifier(builder: Builder(s, input)) -> String {
  builder.identifier
}

pub fn field_key(field: Field(s, a, c)) -> String {
  field.key
}

pub fn field_is_optional(field: Field(s, a, c)) -> Bool {
  field.optional
}

pub fn encode_field(
  field: Field(s, a, c),
  value: a,
) -> Result(types.TreeValue, Error) {
  encode(field.codec, value)
}

pub fn decode_field(
  field: Field(s, a, c),
  value: types.TreeValue,
) -> Result(a, Error) {
  decode(field.codec, value)
}

pub fn identifier_key(field: IdentifierField(s)) -> String {
  field.key
}

pub fn child_key(field: ChildField(s, child, r, c)) -> String {
  field.key
}

pub fn child_codec(field: ChildField(s, child, r, c)) -> NodeCodec(child, r) {
  field.codec
}

pub fn child_is_optional(field: ChildField(s, child, r, c)) -> Bool {
  field.optional
}

pub fn array_key(field: ArrayField(s, item, r)) -> String {
  field.key
}

pub fn array_identifier(field: ArrayField(s, item, r)) -> String {
  field.identifier
}

pub fn array_codec(field: ArrayField(s, item, r)) -> NodeCodec(item, r) {
  field.codec
}

pub fn map_key(field: MapField(s, item, r)) -> String {
  field.key
}

pub fn map_identifier(field: MapField(s, item, r)) -> String {
  field.identifier
}

pub fn map_codec(field: MapField(s, item, r)) -> NodeCodec(item, r) {
  field.codec
}

pub fn validate_field(
  view: tree_schema.ViewSchema,
  owner: String,
  field: Field(s, a, c),
) -> Result(Nil, Error) {
  check_object_field(view, owner, field.key, field_cardinality(field.optional), [
    field.codec.identifier,
  ])
}

pub fn validate_identifier(
  view: tree_schema.ViewSchema,
  owner: String,
  field: IdentifierField(s),
) -> Result(Nil, Error) {
  check_object_field(view, owner, field.key, tree_schema.Identifier, [
    string_identifier,
  ])
}

pub fn validate_child(
  view: tree_schema.ViewSchema,
  owner: String,
  field: ChildField(s, child, r, c),
) -> Result(Nil, Error) {
  check_object_field(view, owner, field.key, field_cardinality(field.optional), [
    field.codec.identifier,
  ])
}

pub fn validate_array(
  view: tree_schema.ViewSchema,
  owner: String,
  field: ArrayField(s, item, r),
) -> Result(Nil, Error) {
  let stored = tree_schema.view_to_stored(view)
  use _ <- result.try(result_from_bool(
    tree_schema.field_schema(stored, owner, field.key)
      == Ok(tree_schema.FieldSchema(tree_schema.Required, [field.identifier])),
    "array field does not match " <> owner <> "." <> field.key,
  ))
  use elements <- result.try(
    case tree_schema.array_element_schema(stored, field.identifier) {
      Ok(value) -> Ok(value)
      Error(_) ->
        Error(InvalidDeclaration(
          "array declaration is absent: " <> field.identifier,
        ))
    },
  )
  result_from_bool(
    field_matches(elements, tree_schema.Sequence, [field.codec.identifier]),
    "array element does not allow " <> field.codec.identifier,
  )
}

pub fn validate_map(
  view: tree_schema.ViewSchema,
  owner: String,
  field: MapField(s, item, r),
) -> Result(Nil, Error) {
  let stored = tree_schema.view_to_stored(view)
  use _ <- result.try(result_from_bool(
    tree_schema.field_schema(stored, owner, field.key)
      == Ok(tree_schema.FieldSchema(tree_schema.Required, [field.identifier])),
    "map field does not match " <> owner <> "." <> field.key,
  ))
  use entries <- result.try(
    case tree_schema.map_entry_schema(stored, field.identifier) {
      Ok(value) -> Ok(value)
      Error(_) ->
        Error(InvalidDeclaration(
          "map declaration is absent: " <> field.identifier,
        ))
    },
  )
  result_from_bool(
    field_matches(entries, tree_schema.Optional, [field.codec.identifier]),
    "map entry does not allow " <> field.codec.identifier,
  )
}

fn check_object_field(
  view: tree_schema.ViewSchema,
  owner: String,
  key: String,
  cardinality: tree_schema.Cardinality,
  allowed_types: List(String),
) -> Result(Nil, Error) {
  let stored = tree_schema.view_to_stored(view)
  case tree_schema.field_schema(stored, owner, key) {
    Ok(definition) ->
      result_from_bool(
        field_matches(definition, cardinality, allowed_types),
        "field declaration does not match " <> owner <> "." <> key,
      )
    Error(_) ->
      Error(InvalidDeclaration(
        "field declaration is absent: " <> owner <> "." <> key,
      ))
  }
}

fn root_field_matches(
  definition: tree_schema.FieldSchema,
  identifier: String,
) -> Bool {
  case definition.cardinality {
    tree_schema.Required | tree_schema.Optional ->
      definition.allowed_types == [identifier]
    tree_schema.Sequence | tree_schema.Identifier -> False
  }
}

fn field_matches(
  definition: tree_schema.FieldSchema,
  cardinality: tree_schema.Cardinality,
  allowed_types: List(String),
) -> Bool {
  definition.cardinality == cardinality
  && definition.allowed_types == allowed_types
}

fn field_cardinality(optional: Bool) -> tree_schema.Cardinality {
  case optional {
    True -> tree_schema.Optional
    False -> tree_schema.Required
  }
}

fn node_value_identifier(value: types.TreeValue) -> String {
  case value {
    types.StringValue(_) -> string_identifier
    types.NumberValue(_) -> number_identifier
    types.BooleanValue(_) -> boolean_identifier
    types.NullValue -> null_identifier
    types.HandleValue(_) -> handle_identifier
    types.ObjectValue(identifier, _)
    | types.MapValue(identifier, _)
    | types.ArrayValue(identifier, _) -> identifier
  }
}

fn valid_identifier(identifier: String) -> Bool {
  identifier != "" && string.trim(identifier) == identifier
}

fn finite(value: Float) -> Bool {
  float.absolute_value(value) <=. largest_finite
}

fn result_from_bool(valid: Bool, detail: String) -> Result(Nil, Error) {
  case valid {
    True -> Ok(Nil)
    False -> Error(InvalidDeclaration(detail))
  }
}
