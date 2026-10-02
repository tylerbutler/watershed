//// Fixed schemas for the Fluid 3.1.0 schema-v2 profile.
////
//// Stored and view schemas use the persisted schema format. These functions
//// do not accept JavaScript view configuration objects or mutate stored data.

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
  type FieldPath, type TreeError, type TreeValue, ArrayValue, BooleanValue,
  CorruptData, InvalidEdit, InvalidSchema, MapValue, NullValue, NumberValue,
  ObjectValue, StringValue, UnsupportedFormat,
}

pub type Cardinality {
  Required
  Optional
  Sequence
  Identifier
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
  Map(entries: FieldSchema)
  Array(elements: FieldSchema)
}

type FieldKind {
  ForbiddenKind
  OptionalKind
  RequiredKind
  SequenceKind
  IdentifierKind
}

type ComparisonField {
  ComparisonField(kind: FieldKind, allowed_types: List(String))
}

type ComparisonLeafKind {
  ComparisonStringLeaf
  ComparisonNumberLeaf
  ComparisonBooleanLeaf
  ComparisonHandleLeaf
  ComparisonNullLeaf
}

type ComparisonNode {
  ComparisonLeaf(kind: ComparisonLeafKind)
  ComparisonObject(fields: List(#(String, ComparisonField)))
  ComparisonMap(entries: ComparisonField)
  ComparisonArray(elements: ComparisonField)
}

type Repository {
  Repository(
    root: FieldSchema,
    nodes: Dict(String, NodeSchema),
    comparison_root: ComparisonField,
    comparison_nodes: Dict(String, ComparisonNode),
    persisted: JsonValue,
    profile_supported: Bool,
  )
}

pub opaque type StoredSchema {
  StoredSchema(repository: Repository)
}

pub opaque type ViewSchema {
  ViewSchema(repository: Repository)
}

pub type SchemaState {
  EmptySchema
  FixedSchema(StoredSchema)
}

// ponytail: Make invalid states impossible (suggestion). Three Bool fields
// allow invalid mixes, for example equivalent but not viewable. Use one variant
// for each compatibility class.
pub type Compatibility {
  Compatibility(can_view: Bool, can_upgrade: Bool, is_equivalent: Bool)
}

/// Read the stored root field definition.
pub fn root_field_schema(schema: StoredSchema) -> FieldSchema {
  schema.repository.root
}

/// Read one node definition by its stored identifier.
pub fn node_schema(
  schema: StoredSchema,
  identifier: String,
) -> Result(NodeSchema, TreeError) {
  case dict.get(schema.repository.nodes, identifier) {
    Ok(node) -> Ok(node)
    Error(Nil) -> Error(InvalidSchema("unknown node schema: " <> identifier))
  }
}

/// Return true when the stored schema declares an Identifier field.
pub fn has_identifier_fields(schema: StoredSchema) -> Bool {
  field_has_identifier(schema.repository.root)
  || schema.repository.nodes
  |> dict.values
  |> list.any(fn(node) {
    case node {
      Leaf(_) -> False
      Object(fields) ->
        list.any(fields, fn(field) { field_has_identifier(field.1) })
      Map(entries) | Array(entries) -> field_has_identifier(entries)
    }
  })
}

fn field_has_identifier(field: FieldSchema) -> Bool {
  let FieldSchema(cardinality, _) = field
  cardinality == Identifier
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
  decode_repository(raw, False) |> result.map(StoredSchema)
}

/// Return the validated persisted representation without normalization.
pub fn stored_to_json(schema: StoredSchema) -> Json {
  json_ot.to_json(schema.repository.persisted)
}

/// Decode a fixed view in schema-v2 form, without view options or upgrades.
pub fn view_from_string(raw: String) -> Result(ViewSchema, TreeError) {
  decode_repository(raw, True) |> result.map(ViewSchema)
}

/// Convert a fixed view to the same persisted schema representation.
pub fn view_to_stored(view: ViewSchema) -> StoredSchema {
  StoredSchema(view.repository)
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
  validate_content(schema.repository, schema.repository.root, value, [], False)
}

/// Validate new root content before Identifier defaults are materialized.
pub fn validate_root_construction(
  schema: StoredSchema,
  value: Option(TreeValue),
) -> Result(Nil, TreeError) {
  validate_content(schema.repository, schema.repository.root, value, [], True)
}

/// Validate a subtree without applying the document root's allowed types.
pub fn validate_subtree(
  schema: StoredSchema,
  value: TreeValue,
) -> Result(Nil, TreeError) {
  let identifier = value_identifier(value)
  case dict.get(schema.repository.nodes, identifier) {
    Ok(node) -> validate_node(schema.repository, node, value, [], False)
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
    MapValue(identifier, _) -> identifier
    ArrayValue(identifier, _) -> identifier
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
  validate_content(schema.repository, definition, value, [field], False)
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
    Ok(Map(_)) ->
      Error(InvalidEdit(path, "parent schema is a map: " <> parent_type))
    Ok(Array(_)) ->
      Error(InvalidEdit(path, "parent schema is an array: " <> parent_type))
    Error(Nil) ->
      Error(InvalidEdit(path, "unknown parent schema: " <> parent_type))
  }
}

/// Read the common entry field for a map schema.
pub fn map_entry_schema(
  schema: StoredSchema,
  map_type: String,
) -> Result(FieldSchema, TreeError) {
  case dict.get(schema.repository.nodes, map_type) {
    Ok(Map(entries)) -> Ok(entries)
    Ok(_) -> Error(InvalidEdit([], "node schema is not a map: " <> map_type))
    Error(Nil) -> Error(InvalidEdit([], "unknown map schema: " <> map_type))
  }
}

/// Read the element field for an array schema.
pub fn array_element_schema(
  schema: StoredSchema,
  array_type: String,
) -> Result(FieldSchema, TreeError) {
  case dict.get(schema.repository.nodes, array_type) {
    Ok(Array(elements)) -> Ok(elements)
    Ok(_) ->
      Error(InvalidEdit([], "node schema is not an array: " <> array_type))
    Error(Nil) -> Error(InvalidEdit([], "unknown array schema: " <> array_type))
  }
}

/// Validate all values in one array.
pub fn validate_array_elements(
  schema: StoredSchema,
  array_type: String,
  elements: List(TreeValue),
) -> Result(Nil, TreeError) {
  use definition <- result.try(array_element_schema(schema, array_type))
  elements
  |> list.index_map(fn(value, index) { #(index, value) })
  |> list.try_each(fn(entry) {
    validate_content(
      schema.repository,
      definition,
      Some(entry.1),
      [int.to_string(entry.0)],
      False,
    )
  })
}

/// Validate one map entry assignment or deletion.
pub fn validate_map_entry(
  schema: StoredSchema,
  map_type: String,
  key: String,
  value: Option(TreeValue),
) -> Result(Nil, TreeError) {
  use definition <- result.try(map_entry_schema(schema, map_type))
  validate_content(schema.repository, definition, value, [key], False)
}

fn validate_content(
  repository: Repository,
  field: FieldSchema,
  value: Option(TreeValue),
  path: FieldPath,
  allow_missing_identifier: Bool,
) -> Result(Nil, TreeError) {
  case value, field.cardinality {
    None, Optional -> Ok(Nil)
    None, Required -> Error(InvalidEdit(path, "required field is absent"))
    None, Sequence -> Ok(Nil)
    None, Identifier if allow_missing_identifier -> Ok(Nil)
    None, Identifier -> Error(InvalidEdit(path, "identifier field is absent"))
    Some(StringValue(_) as value), Identifier ->
      validate_allowed_node(
        repository,
        field,
        value,
        path,
        allow_missing_identifier,
      )
    Some(_), Identifier ->
      Error(InvalidEdit(path, "identifier field must contain a string"))
    Some(value), _ ->
      validate_allowed_node(
        repository,
        field,
        value,
        path,
        allow_missing_identifier,
      )
  }
}

fn validate_allowed_node(
  repository: Repository,
  field: FieldSchema,
  value: TreeValue,
  path: FieldPath,
  allow_missing_identifier: Bool,
) -> Result(Nil, TreeError) {
  let identifier = value_identifier(value)
  case list.contains(field.allowed_types, identifier) {
    False ->
      Error(InvalidEdit(path, "node type is not allowed: " <> identifier))
    True ->
      case dict.get(repository.nodes, identifier) {
        Error(Nil) -> Error(InvalidEdit(path, "unknown schema: " <> identifier))
        Ok(node) ->
          validate_node(repository, node, value, path, allow_missing_identifier)
      }
  }
}

fn validate_node(
  repository: Repository,
  node: NodeSchema,
  value: TreeValue,
  path: FieldPath,
  allow_missing_identifier: Bool,
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
          allow_missing_identifier,
        )
      })
    }
    Map(definition), MapValue(_, entries) -> {
      use _ <- result.try(
        list.try_fold(entries, set.new(), fn(keys, entry) {
          case set.contains(keys, entry.0) {
            True ->
              Error(InvalidEdit(
                list.append(path, [entry.0]),
                "duplicate map key",
              ))
            False -> Ok(set.insert(keys, entry.0))
          }
        }),
      )
      list.try_each(entries, fn(entry) {
        validate_content(
          repository,
          definition,
          Some(entry.1),
          list.append(path, [entry.0]),
          allow_missing_identifier,
        )
      })
    }
    Array(definition), ArrayValue(_, elements) ->
      elements
      |> list.index_map(fn(value, index) { #(index, value) })
      |> list.try_each(fn(entry) {
        validate_content(
          repository,
          definition,
          Some(entry.1),
          list.append(path, [int.to_string(entry.0)]),
          allow_missing_identifier,
        )
      })
    _, _ -> Error(InvalidEdit(path, "value does not match its node schema"))
  }
}

/// Check whether an ordinary fixed view can read and write the stored schema.
/// Extra unused definitions and persisted metadata do not require an upgrade.
pub fn can_view(
  stored: StoredSchema,
  view: ViewSchema,
) -> Result(Nil, TreeError) {
  use _ <- result.try(case repository_view_supported(view.repository) {
    True -> Ok(Nil)
    False -> Error(InvalidSchema("view is outside the supported profile"))
  })
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

/// Classify a fixed view against the stored schema.
pub fn compatibility(
  stored: StoredSchema,
  view: ViewSchema,
) -> Result(Compatibility, TreeError) {
  let target = view_to_stored(view)
  use can_upgrade <- result.try(allows_superset(stored, target))
  use reverse <- result.try(allows_superset(target, stored))
  use can_view <- result.try(case can_view(stored, view) {
    Ok(Nil) -> Ok(True)
    Error(InvalidSchema(_)) -> Ok(False)
    Error(error) -> Error(error)
  })
  Ok(Compatibility(can_view, can_upgrade, can_view && can_upgrade && reverse))
}

/// Check whether a candidate schema accepts every value in the original.
pub fn allows_superset(
  original: StoredSchema,
  candidate: StoredSchema,
) -> Result(Bool, TreeError) {
  Ok(
    field_allows_superset(
      original.repository.comparison_root,
      candidate.repository.comparison_root,
    )
    && original.repository.nodes
    |> dict.keys
    |> list.all(fn(entry) {
      // ponytail: Panicking in libraries. This let assert can panic if the
      // dictionaries do not share keys. Iterate comparison_nodes directly or
      // propagate the lookup result.
      let assert Ok(original_node) =
        dict.get(original.repository.comparison_nodes, entry)
      tree_allows_superset(
        original.repository,
        entry,
        original_node,
        dict.get(candidate.repository.comparison_nodes, entry)
          |> option.from_result,
      )
    }),
  )
}

/// Prepare one supported schema upgrade without changing stored data.
pub fn prepare_upgrade(
  stored: StoredSchema,
  view: ViewSchema,
) -> Result(Option(StoredSchema), TreeError) {
  let target = view_to_stored(view)
  use status <- result.try(compatibility(stored, view))
  case status.can_upgrade {
    False -> Error(InvalidSchema("stored schema cannot upgrade to this view"))
    True -> {
      use reverse <- result.try(allows_superset(target, stored))
      case reverse {
        True -> Ok(None)
        False ->
          validate_upgrade(stored, target)
          |> result.map(fn(_) { Some(target) })
      }
    }
  }
}

/// Check that a forward schema change is monotonic and in the M4 profile.
pub fn validate_upgrade(
  before: StoredSchema,
  after: StoredSchema,
) -> Result(Nil, TreeError) {
  use allowed <- result.try(allows_superset(before, after))
  case allowed {
    False -> Error(InvalidSchema("stored schema cannot upgrade to candidate"))
    True -> check_supported_upgrade(before.repository, after.repository)
  }
}

fn check_supported_upgrade(
  before: Repository,
  after: Repository,
) -> Result(Nil, TreeError) {
  case after.profile_supported {
    False -> Error(InvalidSchema("upgrade is outside the supported profile"))
    True ->
      before.nodes
      |> dict.to_list
      |> list.try_each(fn(entry) {
        case dict.get(after.nodes, entry.0) {
          Error(Nil) -> Ok(Nil)
          Ok(node) ->
            case same_node_kind(entry.1, node) {
              True -> Ok(Nil)
              False ->
                Error(InvalidSchema(
                  "upgrade changes existing node kind: " <> entry.0,
                ))
            }
        }
      })
  }
}

fn same_node_kind(left: NodeSchema, right: NodeSchema) -> Bool {
  case left, right {
    Leaf(_), Leaf(_)
    | Object(_), Object(_)
    | Map(_), Map(_)
    | Array(_), Array(_)
    -> True
    _, _ -> False
  }
}

fn tree_allows_superset(
  repository: Repository,
  identifier: String,
  original: ComparisonNode,
  candidate: Option(ComparisonNode),
) -> Bool {
  case node_is_never(repository, identifier, original, []) {
    True -> True
    False ->
      case candidate {
        None -> False
        Some(candidate) ->
          case node_is_never(repository, identifier, candidate, []) {
            True -> False
            False -> node_allows_superset(original, candidate)
          }
      }
  }
}

fn node_allows_superset(
  original: ComparisonNode,
  candidate: ComparisonNode,
) -> Bool {
  case original, candidate {
    ComparisonLeaf(left), ComparisonLeaf(right) -> left == right
    ComparisonMap(left), ComparisonMap(right) ->
      field_allows_superset(left, right)
    ComparisonArray(left), ComparisonArray(right) ->
      field_allows_superset(left, right)
    ComparisonObject(left), ComparisonObject(right) ->
      object_fields_allow_superset(left, right)
    ComparisonObject(fields), ComparisonMap(entries) ->
      list.all(fields, fn(field) { field_allows_superset(field.1, entries) })
    _, _ -> False
  }
}

fn node_is_never(
  repository: Repository,
  identifier: String,
  node: ComparisonNode,
  stack: List(String),
) -> Bool {
  case list.contains(stack, identifier) {
    True -> True
    False ->
      case node {
        ComparisonLeaf(_) -> False
        ComparisonMap(entries) -> field_requires_one(entries.kind)
        ComparisonArray(_) -> False
        ComparisonObject(fields) ->
          list.any(fields, fn(field) {
            field_is_never(repository, field.1, [identifier, ..stack])
          })
      }
  }
}

fn field_is_never(
  repository: Repository,
  field: ComparisonField,
  stack: List(String),
) -> Bool {
  field_requires_one(field.kind)
  && list.all(field.allowed_types, fn(identifier) {
    case dict.get(repository.comparison_nodes, identifier) {
      Error(Nil) -> True
      Ok(node) -> node_is_never(repository, identifier, node, stack)
    }
  })
}

fn field_requires_one(kind: FieldKind) -> Bool {
  case kind {
    RequiredKind | IdentifierKind -> True
    ForbiddenKind | OptionalKind | SequenceKind -> False
  }
}

fn field_allows_superset(
  original: ComparisonField,
  candidate: ComparisonField,
) -> Bool {
  list.all(original.allowed_types, fn(identifier) {
    list.contains(candidate.allowed_types, identifier)
  })
  && case original.kind == candidate.kind {
    True -> True
    False ->
      case candidate.kind {
        ForbiddenKind | IdentifierKind -> False
        OptionalKind ->
          list.contains(
            [IdentifierKind, RequiredKind, ForbiddenKind],
            original.kind,
          )
        RequiredKind -> original.kind == IdentifierKind
        SequenceKind ->
          list.contains(
            [IdentifierKind, RequiredKind, OptionalKind, ForbiddenKind],
            original.kind,
          )
      }
  }
}

fn public_leaf_kind(kind: ComparisonLeafKind) -> LeafKind {
  case kind {
    ComparisonStringLeaf | ComparisonHandleLeaf -> StringLeaf
    ComparisonNumberLeaf -> NumberLeaf
    ComparisonBooleanLeaf -> BooleanLeaf
    ComparisonNullLeaf -> NullLeaf
  }
}

fn public_field(field: ComparisonField) -> FieldSchema {
  FieldSchema(
    case field.kind {
      RequiredKind -> Required
      ForbiddenKind | OptionalKind -> Optional
      SequenceKind -> Sequence
      IdentifierKind -> Identifier
    },
    field.allowed_types,
  )
}

fn profile_field_kind(kind: FieldKind) -> Bool {
  case kind {
    RequiredKind | OptionalKind -> True
    ForbiddenKind | SequenceKind | IdentifierKind -> False
  }
}

fn repository_view_supported(repository: Repository) -> Bool {
  case repository.comparison_root.kind {
    RequiredKind | OptionalKind ->
      repository.comparison_nodes
      |> dict.values
      |> list.all(comparison_node_view_supported)
    ForbiddenKind | SequenceKind | IdentifierKind -> False
  }
}

fn comparison_node_view_supported(node: ComparisonNode) -> Bool {
  case node {
    ComparisonLeaf(ComparisonHandleLeaf) -> False
    ComparisonLeaf(_) -> True
    ComparisonObject(fields) ->
      list.all(fields, fn(field) {
        case field.1.kind {
          RequiredKind | OptionalKind -> True
          IdentifierKind -> field.0 != "" && identifier_field_supported(field.1)
          ForbiddenKind | SequenceKind -> False
        }
      })
    ComparisonMap(entries) ->
      case entries.kind {
        RequiredKind | OptionalKind -> True
        ForbiddenKind | SequenceKind | IdentifierKind -> False
      }
    ComparisonArray(elements) -> elements.kind == SequenceKind
  }
}

fn comparison_leaf_kind(code: JsonValue) -> Result(ComparisonLeafKind, Nil) {
  case code {
    VNumber(NInt(0)) | VNumber(NFloat(0.0)) -> Ok(ComparisonNumberLeaf)
    VNumber(NInt(1)) | VNumber(NFloat(1.0)) -> Ok(ComparisonStringLeaf)
    VNumber(NInt(2)) | VNumber(NFloat(2.0)) -> Ok(ComparisonBooleanLeaf)
    VNumber(NInt(3)) | VNumber(NFloat(3.0)) -> Ok(ComparisonHandleLeaf)
    VNumber(NInt(4)) | VNumber(NFloat(4.0)) -> Ok(ComparisonNullLeaf)
    _ -> Error(Nil)
  }
}

fn comparison_field_kind(kind: String) -> Result(FieldKind, Nil) {
  case kind {
    "Forbidden" -> Ok(ForbiddenKind)
    "Optional" -> Ok(OptionalKind)
    "Value" -> Ok(RequiredKind)
    "Sequence" -> Ok(SequenceKind)
    "Identifier" -> Ok(IdentifierKind)
    _ -> Error(Nil)
  }
}

fn field_kind_name(kind: FieldKind) -> String {
  case kind {
    ForbiddenKind -> "Forbidden"
    OptionalKind -> "Optional"
    RequiredKind -> "Value"
    SequenceKind -> "Sequence"
    IdentifierKind -> "Identifier"
  }
}

fn field_types(field: ComparisonField) -> List(String) {
  field.allowed_types
}

fn comparison_node_types(node: ComparisonNode) -> List(ComparisonField) {
  case node {
    ComparisonLeaf(_) -> []
    ComparisonObject(fields) -> list.map(fields, fn(field) { field.1 })
    ComparisonMap(entries) -> [entries]
    ComparisonArray(elements) -> [elements]
  }
}

fn comparison_node_supported(node: ComparisonNode) -> Bool {
  case node {
    ComparisonLeaf(ComparisonHandleLeaf) -> False
    ComparisonLeaf(_) -> True
    ComparisonObject(fields) ->
      list.all(fields, fn(field) {
        profile_field_kind(field.1.kind)
        || case field.1.kind {
          IdentifierKind -> field.0 != "" && identifier_field_supported(field.1)
          ForbiddenKind | OptionalKind | RequiredKind | SequenceKind -> False
        }
      })
    ComparisonMap(entries) -> profile_field_kind(entries.kind)
    ComparisonArray(_) -> False
  }
}

fn identifier_field_supported(field: ComparisonField) -> Bool {
  field.allowed_types == ["com.fluidframework.leaf.string"]
}

fn comparison_node_to_public(node: ComparisonNode) -> NodeSchema {
  case node {
    ComparisonLeaf(kind) -> Leaf(public_leaf_kind(kind))
    ComparisonObject(fields) ->
      Object(list.map(fields, fn(field) { #(field.0, public_field(field.1)) }))
    ComparisonMap(entries) -> Map(public_field(entries))
    ComparisonArray(elements) -> Array(public_field(elements))
  }
}

fn comparison_nodes_to_public(
  nodes: List(#(String, ComparisonNode)),
) -> Dict(String, NodeSchema) {
  nodes
  |> list.map(fn(entry) { #(entry.0, comparison_node_to_public(entry.1)) })
  |> dict.from_list
}

fn comparison_nodes_supported(nodes: List(#(String, ComparisonNode))) -> Bool {
  list.all(nodes, fn(entry) { comparison_node_supported(entry.1) })
}

fn check_comparison_references(
  repository: Repository,
  field: ComparisonField,
  path: String,
) -> Result(Nil, TreeError) {
  field_types(field)
  |> list.try_each(fn(identifier) {
    case dict.has_key(repository.comparison_nodes, identifier) {
      True -> Ok(Nil)
      False -> Error(InvalidSchema(path <> ": missing schema " <> identifier))
    }
  })
}

fn check_comparison_node_references(
  repository: Repository,
  identifier: String,
  node: ComparisonNode,
) -> Result(Nil, TreeError) {
  comparison_node_types(node)
  |> list.try_each(fn(field) {
    check_comparison_references(repository, field, identifier)
  })
}

fn decode_comparison_field_kind(
  value: JsonValue,
  path: String,
  allow_excluded: Bool,
) -> Result(FieldKind, TreeError) {
  case value {
    VString(kind) ->
      case comparison_field_kind(kind) {
        Ok(kind) ->
          case
            kind == SequenceKind
            || kind == IdentifierKind
            || profile_field_kind(kind)
            || allow_excluded
          {
            True -> Ok(kind)
            False ->
              Error(InvalidSchema(
                path <> ": unsupported field kind " <> field_kind_name(kind),
              ))
          }
        Error(Nil) ->
          Error(InvalidSchema(path <> ": unsupported field kind " <> kind))
      }
    _ -> Error(CorruptData(path <> ".kind", "expected a field kind string"))
  }
}

fn decode_comparison_leaf_kind(
  value: JsonValue,
  path: String,
  allow_excluded: Bool,
) -> Result(ComparisonLeafKind, TreeError) {
  case comparison_leaf_kind(value) {
    Ok(ComparisonHandleLeaf) if !allow_excluded ->
      Error(InvalidSchema(path <> ": unsupported leaf kind"))
    Ok(kind) -> Ok(kind)
    Error(Nil) ->
      case value {
        VNumber(_) -> Error(InvalidSchema(path <> ": unsupported leaf kind"))
        _ -> Error(CorruptData(path <> ".kind.leaf", "expected a leaf code"))
      }
  }
}

fn leaf_identifier_matches(
  identifier: String,
  kind: ComparisonLeafKind,
) -> Bool {
  case kind {
    ComparisonHandleLeaf -> True
    // ponytail: Match all variants. This catch-all also takes any new leaf kind
    // variant without a compiler error. Name the remaining variants.
    _ -> identifier == leaf_identifier(public_leaf_kind(kind))
  }
}

fn field_allows_missing(field: ComparisonField) -> Bool {
  field_allows_superset(ComparisonField(ForbiddenKind, []), field)
}

fn field_allows_removal(field: ComparisonField) -> Bool {
  field_allows_superset(field, ComparisonField(ForbiddenKind, []))
}

fn object_fields_allow_superset(
  original: List(#(String, ComparisonField)),
  candidate: List(#(String, ComparisonField)),
) -> Bool {
  list.append(
    list.map(original, fn(field) { field.0 }),
    list.map(candidate, fn(field) { field.0 }),
  )
  |> list.unique
  |> list.all(fn(key) {
    case list.key_find(original, key), list.key_find(candidate, key) {
      Error(Nil), Ok(field) -> field_allows_missing(field)
      Ok(field), Error(Nil) -> field_allows_removal(field)
      Ok(left), Ok(right) -> field_allows_superset(left, right)
      Error(Nil), Error(Nil) -> True
    }
  })
}

fn compare_field(
  stored: FieldSchema,
  view: FieldSchema,
  path: String,
) -> Result(Nil, TreeError) {
  case
    stored == view
    || {
      let FieldSchema(stored_cardinality, stored_types) = stored
      let FieldSchema(view_cardinality, view_types) = view
      stored_cardinality == Identifier
      && view_cardinality == Required
      && stored_types == view_types
    }
  {
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
    Map(a), Map(b) -> compare_field(a, b, identifier)
    Array(a), Array(b) -> compare_field(a, b, identifier)
    _, _ -> Error(InvalidSchema(identifier <> ": incompatible node kind"))
  }
}

fn decode_repository(
  raw: String,
  allow_excluded: Bool,
) -> Result(Repository, TreeError) {
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
      use node <- result.try(decode_node(identifier, definition, allow_excluded))
      Ok(#(identifier, node))
    }),
  )
  use root <- result.try(member(members, "root", "$"))
  use root <- result.try(decode_field(root, "$.root", allow_excluded))
  use _ <- result.try(case root.kind {
    SequenceKind ->
      Error(InvalidSchema(
        "$.root: sequence field is only valid as an array primary field",
      ))
    IdentifierKind if !allow_excluded ->
      Error(InvalidSchema("$.root: identifier field is only valid on an object"))
    ForbiddenKind | OptionalKind | RequiredKind | IdentifierKind -> Ok(Nil)
  })
  let comparison_nodes = dict.from_list(nodes)
  let repository =
    Repository(
      public_field(root),
      comparison_nodes_to_public(nodes),
      root,
      comparison_nodes,
      data,
      profile_field_kind(root.kind) && comparison_nodes_supported(nodes),
    )
  use _ <- result.try(check_comparison_references(repository, root, "$.root"))
  use _ <- result.try(
    list.try_each(nodes, fn(entry) {
      check_comparison_node_references(repository, entry.0, entry.1)
    }),
  )
  Ok(repository)
}

fn decode_node(
  identifier: String,
  data: JsonValue,
  allow_excluded: Bool,
) -> Result(ComparisonNode, TreeError) {
  let path = key_path("$.nodes", identifier)
  use members <- result.try(object(data, path))
  use _ <- result.try(check_metadata(members, path))
  use kind <- result.try(member(members, "kind", path))
  use kind <- result.try(object(kind, path <> ".kind"))
  case kind {
    [#("leaf", value)] -> {
      use leaf <- result.try(decode_comparison_leaf_kind(
        value,
        path,
        allow_excluded,
      ))
      case leaf_identifier_matches(identifier, leaf) {
        True -> Ok(ComparisonLeaf(leaf))
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
            allow_excluded,
          ))
          Ok(#(field.0, definition))
        }),
      )
      case fields {
        [#("", ComparisonField(SequenceKind, _) as elements)] ->
          Ok(ComparisonArray(elements))
        _ -> {
          use _ <- result.try(case allow_excluded {
            True -> Ok(Nil)
            False ->
              list.try_each(fields, fn(field) {
                case field.1.kind {
                  SequenceKind ->
                    Error(InvalidSchema(
                      key_path(path, field.0)
                      <> ": sequence field is only valid as an array primary field",
                    ))
                  IdentifierKind ->
                    case field.0 != "" && identifier_field_supported(field.1) {
                      True -> Ok(Nil)
                      False ->
                        Error(InvalidSchema(
                          key_path(path, field.0)
                          <> ": identifier field must be a named string field",
                        ))
                    }
                  ForbiddenKind | OptionalKind | RequiredKind -> Ok(Nil)
                }
              })
          })
          Ok(ComparisonObject(fields))
        }
      }
    }
    [#("map", entries)] -> {
      use entries <- result.try(decode_field(
        entries,
        path <> ".kind.map",
        allow_excluded,
      ))
      use _ <- result.try(case entries.kind, allow_excluded {
        SequenceKind, False ->
          Error(InvalidSchema(
            path
            <> ".kind.map: sequence field is only valid as an array primary field",
          ))
        IdentifierKind, False ->
          Error(InvalidSchema(
            path <> ".kind.map: identifier field is only valid on an object",
          ))
        ForbiddenKind, _
        | OptionalKind, _
        | RequiredKind, _
        | SequenceKind, True
        | IdentifierKind, True
        -> Ok(Nil)
      })
      Ok(ComparisonMap(entries))
    }
    [#(kind, _)] ->
      Error(InvalidSchema(path <> ": unsupported node kind " <> kind))
    _ -> Error(CorruptData(path <> ".kind", "expected exactly one node kind"))
  }
}

fn decode_field(
  data: JsonValue,
  path: String,
  allow_excluded: Bool,
) -> Result(ComparisonField, TreeError) {
  use members <- result.try(object(data, path))
  use _ <- result.try(check_metadata(members, path))
  use kind <- result.try(member(members, "kind", path))
  use kind <- result.try(decode_comparison_field_kind(
    kind,
    path,
    allow_excluded,
  ))
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
  Ok(ComparisonField(
    kind,
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
