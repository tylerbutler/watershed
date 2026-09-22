//// Fixed object schemas for the Fluid 3.1.0 schema-v2 profile.
////
//// Stored and view schemas use the persisted schema format. These functions
//// do not accept JavaScript view configuration objects or apply schema upgrades.

import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set.{type Set}
import watershed/canonical_json
import watershed/json_ot.{
  type JsonValue, NFloat, NInt, VArray, VNumber, VObject, VString,
}
import watershed/tree/types.{
  type FieldPath, type TreeError, type TreeValue, BooleanValue, CorruptData,
  InvalidEdit, InvalidSchema, NullValue, NumberValue, ObjectValue, StringValue,
  UnsupportedFormat,
}

pub type Cardinality {
  Required
  Optional
}

pub type FieldSchema {
  FieldSchema(cardinality: Cardinality, allowed_types: List(String))
}

pub type LeafKind {
  StringLeaf
  NumberLeaf
  BooleanLeaf
  NullLeaf
}

pub type NodeSchema {
  Leaf(kind: LeafKind)
  Object(fields: List(#(String, FieldSchema)))
}

type Repository {
  Repository(
    root: FieldSchema,
    nodes: Dict(String, NodeSchema),
    persisted: JsonValue,
  )
}

pub opaque type StoredSchema {
  StoredSchema(repository: Repository)
}

pub opaque type ViewSchema {
  ViewSchema(repository: Repository)
}

/// Decode a schema that is already JSON. Earlier parsers can erase duplicate
/// keys. Use `stored_from_string` for a schema blob from storage or the wire.
pub fn stored_from_json(data: Json) -> Result(StoredSchema, TreeError) {
  stored_from_string(json.to_string(data))
}

/// Decode the persisted form of a fixed view schema. Earlier JSON parsers can
/// erase duplicate keys. Use `view_from_string` to check original bytes.
pub fn view_from_json(data: Json) -> Result(ViewSchema, TreeError) {
  view_from_string(json.to_string(data))
}

/// Decode schema-v2 bytes and reject duplicate declarations.
pub fn stored_from_string(raw: String) -> Result(StoredSchema, TreeError) {
  decode_repository(raw) |> result.map(StoredSchema)
}

/// Decode a fixed view in schema-v2 form, without view options or upgrades.
pub fn view_from_string(raw: String) -> Result(ViewSchema, TreeError) {
  decode_repository(raw) |> result.map(ViewSchema)
}

/// Validate one root value without changing or normalizing it.
pub fn validate_root(
  schema: StoredSchema,
  value: TreeValue,
) -> Result(Nil, TreeError) {
  validate_root_field(schema, Some(value))
}

/// Validate root presence and content. Absence is distinct from a null leaf.
pub fn validate_root_field(
  schema: StoredSchema,
  value: Option(TreeValue),
) -> Result(Nil, TreeError) {
  validate_content(schema.repository, schema.repository.root, value, [])
}

/// Validate a subtree without applying the document root's allowed types.
pub fn validate_subtree(
  schema: StoredSchema,
  value: TreeValue,
) -> Result(Nil, TreeError) {
  let identifier = value_identifier(value)
  case dict.get(schema.repository.nodes, identifier) {
    Ok(node) -> validate_node(schema.repository, node, value, [])
    Error(Nil) -> Error(InvalidEdit([], "unknown schema: " <> identifier))
  }
}

fn value_identifier(value: TreeValue) -> String {
  case value {
    StringValue(_) -> leaf_identifier(StringLeaf)
    NumberValue(_) -> leaf_identifier(NumberLeaf)
    BooleanValue(_) -> leaf_identifier(BooleanLeaf)
    NullValue -> leaf_identifier(NullLeaf)
    ObjectValue(identifier, _) -> identifier
  }
}

/// Validate an assignment or clear against an object's declared field.
/// Error paths start at the field name, not at an attached forest location.
pub fn validate_field(
  schema: StoredSchema,
  parent_type: String,
  field: String,
  value: Option(TreeValue),
) -> Result(Nil, TreeError) {
  use definition <- result.try(field_schema(schema, parent_type, field))
  validate_content(schema.repository, definition, value, [field])
}

/// Read one declared object field, including a field that has no content.
pub fn field_schema(
  schema: StoredSchema,
  parent_type: String,
  field: String,
) -> Result(FieldSchema, TreeError) {
  let path = [field]
  case dict.get(schema.repository.nodes, parent_type) {
    Ok(Object(fields)) ->
      case list.key_find(fields, field) {
        Ok(definition) -> Ok(definition)
        Error(Nil) ->
          Error(InvalidEdit(path, "unknown field in " <> parent_type))
      }
    Ok(Leaf(_)) ->
      Error(InvalidEdit(path, "parent schema is a leaf: " <> parent_type))
    Error(Nil) ->
      Error(InvalidEdit(path, "unknown parent schema: " <> parent_type))
  }
}

fn validate_content(
  repository: Repository,
  field: FieldSchema,
  value: Option(TreeValue),
  path: FieldPath,
) -> Result(Nil, TreeError) {
  case value, field.cardinality {
    None, Optional -> Ok(Nil)
    None, Required -> Error(InvalidEdit(path, "required field is absent"))
    Some(value), _ -> {
      let identifier = value_identifier(value)
      case list.contains(field.allowed_types, identifier) {
        False ->
          Error(InvalidEdit(path, "node type is not allowed: " <> identifier))
        True ->
          case dict.get(repository.nodes, identifier) {
            Error(Nil) ->
              Error(InvalidEdit(path, "unknown schema: " <> identifier))
            Ok(node) -> validate_node(repository, node, value, path)
          }
      }
    }
  }
}

fn validate_node(
  repository: Repository,
  node: NodeSchema,
  value: TreeValue,
  path: FieldPath,
) -> Result(Nil, TreeError) {
  case node, value {
    Leaf(StringLeaf), StringValue(_)
    | Leaf(BooleanLeaf), BooleanValue(_)
    | Leaf(NullLeaf), NullValue
    -> Ok(Nil)
    Leaf(NumberLeaf), NumberValue(number) ->
      case
        number >=. -1.7976931348623157e308 && number <=. 1.7976931348623157e308
      {
        True -> Ok(Nil)
        False -> Error(InvalidEdit(path, "number must be finite"))
      }
    Object(definitions), ObjectValue(_, fields) -> {
      use _ <- result.try(
        list.try_fold(fields, set.new(), fn(keys, entry) {
          case set.contains(keys, entry.0) {
            True ->
              Error(InvalidEdit(
                list.append(path, [entry.0]),
                "duplicate object field",
              ))
            False -> Ok(set.insert(keys, entry.0))
          }
        }),
      )
      use _ <- result.try(
        list.try_each(fields, fn(entry) {
          case list.key_find(definitions, entry.0) {
            Ok(_) -> Ok(Nil)
            Error(Nil) ->
              Error(InvalidEdit(
                list.append(path, [entry.0]),
                "unknown object field",
              ))
          }
        }),
      )
      list.try_each(definitions, fn(entry) {
        let child = list.key_find(fields, entry.0) |> option.from_result
        validate_content(
          repository,
          entry.1,
          child,
          list.append(path, [entry.0]),
        )
      })
    }
    _, _ -> Error(InvalidEdit(path, "value does not match its node schema"))
  }
}

/// Check whether an ordinary fixed view can read and write the stored schema.
/// Extra unused definitions and persisted metadata do not require an upgrade.
pub fn can_view(
  stored: StoredSchema,
  view: ViewSchema,
) -> Result(Nil, TreeError) {
  use _ <- result.try(compare_field(
    stored.repository.root,
    view.repository.root,
    "root",
  ))
  stored.repository.nodes
  |> dict.to_list
  |> list.sort(fn(a, b) { canonical_json.compare(a.0, b.0) })
  |> list.try_each(fn(entry) {
    case dict.get(view.repository.nodes, entry.0) {
      Error(Nil) -> Ok(Nil)
      Ok(node) -> compare_node(entry.1, node, entry.0)
    }
  })
}

fn compare_field(
  stored: FieldSchema,
  view: FieldSchema,
  path: String,
) -> Result(Nil, TreeError) {
  case stored == view {
    True -> Ok(Nil)
    False -> Error(InvalidSchema(path <> ": incompatible field schema"))
  }
}

fn compare_node(
  stored: NodeSchema,
  view: NodeSchema,
  identifier: String,
) -> Result(Nil, TreeError) {
  case stored, view {
    Leaf(a), Leaf(b) if a == b -> Ok(Nil)
    Object(a), Object(b) -> {
      list.append(
        list.map(a, fn(entry) { entry.0 }),
        list.map(b, fn(entry) { entry.0 }),
      )
      |> list.unique
      |> list.sort(canonical_json.compare)
      |> list.try_each(fn(key) {
        case list.key_find(a, key), list.key_find(b, key) {
          Ok(left), Ok(right) ->
            compare_field(left, right, key_path(identifier, key))
          _, _ ->
            Error(InvalidSchema(
              key_path(identifier, key) <> ": incompatible object field",
            ))
        }
      })
    }
    _, _ -> Error(InvalidSchema(identifier <> ": incompatible node kind"))
  }
}

fn decode_repository(raw: String) -> Result(Repository, TreeError) {
  use data <- result.try(
    json.parse(raw, json_ot.decoder())
    |> result.map_error(fn(_) { CorruptData("$", "invalid schema JSON") }),
  )
  use _ <- result.try(scan_value(<<raw:utf8>>, "$"))
  use members <- result.try(object(data, "$"))
  use version <- result.try(member(members, "version", "$"))
  use _ <- result.try(case version {
    VNumber(NInt(2)) | VNumber(NFloat(2.0)) -> Ok(Nil)
    VNumber(number) ->
      Error(UnsupportedFormat(
        "Schema",
        canonical_json.to_string(VNumber(number)),
      ))
    _ -> Error(CorruptData("$.version", "expected a schema version number"))
  })
  use nodes <- result.try(member(members, "nodes", "$"))
  use nodes <- result.try(object(nodes, "$.nodes"))
  use nodes <- result.try(
    list.try_map(nodes, fn(entry) {
      let #(identifier, definition) = entry
      use node <- result.try(decode_node(identifier, definition))
      Ok(#(identifier, node))
    }),
  )
  use root <- result.try(member(members, "root", "$"))
  use root <- result.try(decode_field(root, "$.root"))
  let repository = Repository(root, dict.from_list(nodes), data)
  use _ <- result.try(check_references(repository, root, "$.root"))
  use _ <- result.try(
    list.try_each(nodes, fn(entry) {
      case entry.1 {
        Leaf(_) -> Ok(Nil)
        Object(fields) ->
          list.try_each(fields, fn(field) {
            check_references(repository, field.1, key_path(entry.0, field.0))
          })
      }
    }),
  )
  Ok(repository)
}

fn decode_node(
  identifier: String,
  data: JsonValue,
) -> Result(NodeSchema, TreeError) {
  let path = key_path("$.nodes", identifier)
  use members <- result.try(object(data, path))
  use _ <- result.try(check_metadata(members, path))
  use kind <- result.try(member(members, "kind", path))
  use kind <- result.try(object(kind, path <> ".kind"))
  case kind {
    [#("leaf", value)] -> {
      use leaf <- result.try(case value {
        VNumber(NInt(0)) | VNumber(NFloat(0.0)) -> Ok(NumberLeaf)
        VNumber(NInt(1)) | VNumber(NFloat(1.0)) -> Ok(StringLeaf)
        VNumber(NInt(2)) | VNumber(NFloat(2.0)) -> Ok(BooleanLeaf)
        VNumber(NInt(4)) | VNumber(NFloat(4.0)) -> Ok(NullLeaf)
        VNumber(_) -> Error(InvalidSchema(path <> ": unsupported leaf kind"))
        _ -> Error(CorruptData(path <> ".kind.leaf", "expected a leaf code"))
      })
      case identifier == leaf_identifier(leaf) {
        True -> Ok(Leaf(leaf))
        False ->
          Error(InvalidSchema(
            path <> ": leaf identifier does not match its kind",
          ))
      }
    }
    [#("object", fields)] -> {
      use fields <- result.try(object(fields, path <> ".kind.object"))
      use fields <- result.try(
        list.try_map(fields, fn(field) {
          use definition <- result.try(decode_field(
            field.1,
            key_path(path, field.0),
          ))
          Ok(#(field.0, definition))
        }),
      )
      Ok(Object(fields))
    }
    [#(kind, _)] ->
      Error(InvalidSchema(path <> ": unsupported node kind " <> kind))
    _ -> Error(CorruptData(path <> ".kind", "expected exactly one node kind"))
  }
}

fn decode_field(
  data: JsonValue,
  path: String,
) -> Result(FieldSchema, TreeError) {
  use members <- result.try(object(data, path))
  use _ <- result.try(check_metadata(members, path))
  use kind <- result.try(member(members, "kind", path))
  use cardinality <- result.try(case kind {
    VString("Value") -> Ok(Required)
    VString("Optional") -> Ok(Optional)
    VString(kind) ->
      Error(InvalidSchema(path <> ": unsupported field kind " <> kind))
    _ -> Error(CorruptData(path <> ".kind", "expected a field kind string"))
  })
  use types <- result.try(member(members, "types", path))
  use types <- result.try(case types {
    VArray(types) ->
      list.try_map(types, fn(value) {
        case value {
          VString(identifier) -> Ok(identifier)
          _ ->
            Error(CorruptData(path <> ".types", "expected schema identifiers"))
        }
      })
    _ -> Error(CorruptData(path <> ".types", "expected allowed types"))
  })
  Ok(FieldSchema(
    cardinality,
    types |> list.unique |> list.sort(canonical_json.compare),
  ))
}

fn check_metadata(
  members: List(#(String, JsonValue)),
  path: String,
) -> Result(Nil, TreeError) {
  case list.key_find(members, "metadata") {
    Error(Nil) -> Ok(Nil)
    Ok(VObject(_)) -> Ok(Nil)
    Ok(_) -> Error(CorruptData(path <> ".metadata", "expected metadata object"))
  }
}

fn check_references(
  repository: Repository,
  field: FieldSchema,
  path: String,
) -> Result(Nil, TreeError) {
  list.try_each(field.allowed_types, fn(identifier) {
    case dict.has_key(repository.nodes, identifier) {
      True -> Ok(Nil)
      False -> Error(InvalidSchema(path <> ": missing schema " <> identifier))
    }
  })
}

fn leaf_identifier(kind: LeafKind) -> String {
  case kind {
    StringLeaf -> "com.fluidframework.leaf.string"
    NumberLeaf -> "com.fluidframework.leaf.number"
    BooleanLeaf -> "com.fluidframework.leaf.boolean"
    NullLeaf -> "com.fluidframework.leaf.null"
  }
}

fn object(
  data: JsonValue,
  path: String,
) -> Result(List(#(String, JsonValue)), TreeError) {
  case data {
    VObject(members) ->
      Ok(list.sort(members, fn(a, b) { canonical_json.compare(a.0, b.0) }))
    _ -> Error(CorruptData(path, "expected an object"))
  }
}

fn member(
  members: List(#(String, JsonValue)),
  key: String,
  path: String,
) -> Result(JsonValue, TreeError) {
  list.key_find(members, key)
  |> result.map_error(fn(_) {
    CorruptData(key_path(path, key), "missing property")
  })
}

fn key_path(path: String, key: String) -> String {
  path <> "[" <> json.to_string(json.string(key)) <> "]"
}

// JSON syntax is checked before this scan. Only member identity needs a
// separate pass, because platform JSON parsers discard duplicate keys.
fn scan_value(raw: BitArray, path: String) -> Result(BitArray, TreeError) {
  case whitespace(raw) {
    <<123, rest:bytes>> -> scan_object(rest, path, set.new())
    <<91, rest:bytes>> -> scan_array(rest, path, 0)
    <<34, rest:bytes>> ->
      quoted(rest, [<<34>>], path) |> result.map(fn(pair) { pair.1 })
    <<>> -> Error(CorruptData(path, "missing JSON value"))
    other -> Ok(skip_scalar(other))
  }
}

fn scan_object(
  raw: BitArray,
  path: String,
  keys: Set(String),
) -> Result(BitArray, TreeError) {
  case whitespace(raw) {
    <<125, rest:bytes>> -> Ok(rest)
    <<34, rest:bytes>> -> {
      use #(token, rest) <- result.try(quoted(rest, [<<34>>], path))
      use key <- result.try(
        json.parse_bits(token, decode.string)
        |> result.map_error(fn(_) { CorruptData(path, "invalid object key") }),
      )
      use _ <- result.try(case set.contains(keys, key) {
        True -> Error(CorruptData(key_path(path, key), "duplicate object key"))
        False -> Ok(Nil)
      })
      case whitespace(rest) {
        <<58, rest:bytes>> -> {
          use rest <- result.try(scan_value(rest, key_path(path, key)))
          case whitespace(rest) {
            <<44, rest:bytes>> -> scan_object(rest, path, set.insert(keys, key))
            <<125, rest:bytes>> -> Ok(rest)
            _ -> Error(CorruptData(path, "invalid object delimiter"))
          }
        }
        _ -> Error(CorruptData(path, "missing object colon"))
      }
    }
    _ -> Error(CorruptData(path, "invalid object key"))
  }
}

fn scan_array(
  raw: BitArray,
  path: String,
  index: Int,
) -> Result(BitArray, TreeError) {
  case whitespace(raw) {
    <<93, rest:bytes>> -> Ok(rest)
    other -> {
      use rest <- result.try(scan_value(
        other,
        path <> "[" <> int.to_string(index) <> "]",
      ))
      case whitespace(rest) {
        <<44, rest:bytes>> -> scan_array(rest, path, index + 1)
        <<93, rest:bytes>> -> Ok(rest)
        _ -> Error(CorruptData(path, "invalid array delimiter"))
      }
    }
  }
}

fn quoted(
  raw: BitArray,
  bytes: List(BitArray),
  path: String,
) -> Result(#(BitArray, BitArray), TreeError) {
  case raw {
    <<34, rest:bytes>> ->
      Ok(#(bit_array.concat(list.reverse([<<34>>, ..bytes])), rest))
    <<92, escaped, rest:bytes>> ->
      quoted(rest, [<<92, escaped>>, ..bytes], path)
    <<byte, rest:bytes>> -> quoted(rest, [<<byte>>, ..bytes], path)
    _ -> Error(CorruptData(path, "unterminated JSON string"))
  }
}

fn whitespace(raw: BitArray) -> BitArray {
  case raw {
    <<32, rest:bytes>>
    | <<9, rest:bytes>>
    | <<10, rest:bytes>>
    | <<13, rest:bytes>> -> whitespace(rest)
    _ -> raw
  }
}

fn skip_scalar(raw: BitArray) -> BitArray {
  case raw {
    <<44, _:bytes>> | <<125, _:bytes>> | <<93, _:bytes>> -> raw
    <<_, rest:bytes>> -> skip_scalar(rest)
    _ -> raw
  }
}
