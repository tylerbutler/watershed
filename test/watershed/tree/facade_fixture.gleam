import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
@target(javascript)
import watershed
import watershed/handle
@target(javascript)
import watershed/runtime
@target(erlang)
import watershed/runtime_beam
import watershed/tree/schema
import watershed/tree/typed
import watershed/tree/types
@target(erlang)
import watershed_beam

pub type Dynamic

@target(javascript)
pub type JavascriptTree =
  watershed.SharedTree(Dynamic, types.TreeValue)

@target(erlang)
pub type ErlangTree =
  watershed_beam.SharedTree(Dynamic, types.TreeValue)

fn typed_error(error: typed.Error) -> String {
  case error {
    typed.AccessFailed(reason) -> reason
    _ -> string.inspect(error)
  }
}

pub fn definition(
  view: schema.ViewSchema,
) -> Result(typed.Schema(Dynamic, types.TreeValue), String) {
  let stored = schema.view_to_stored(view)
  let schema.FieldSchema(_, allowed) = schema.root_field_schema(stored)
  use identifier <- result.try(single(allowed, "root"))
  use codec <- result.try(
    typed.dynamic_node(identifier) |> result.map_error(typed_error),
  )
  typed.schema(view, codec) |> result.map_error(typed_error)
}

pub fn builder(
  value: types.TreeValue,
) -> Result(typed.Builder(Dynamic, types.TreeValue), String) {
  typed.dynamic_builder(identifier(value)) |> result.map_error(typed_error)
}

@target(javascript)
pub fn resolve_javascript(
  document: watershed.Document(root),
  value: Json,
  view: schema.ViewSchema,
) -> Result(watershed.SharedTree(Dynamic, types.TreeValue), String) {
  use definition <- result.try(definition(view))
  watershed.resolve_tree(document, value, definition)
  |> result.map_error(typed_error)
}

@target(erlang)
pub fn resolve_erlang(
  document: watershed_beam.Document(root),
  value: Json,
  view: schema.ViewSchema,
) -> Result(watershed_beam.SharedTree(Dynamic, types.TreeValue), String) {
  use definition <- result.try(definition(view))
  watershed_beam.resolve_tree(document, value, definition)
  |> result.map_error(typed_error)
}

@target(javascript)
pub fn open_javascript(
  document: watershed.Document(root),
  value: Json,
  view: schema.ViewSchema,
) -> Result(watershed.SharedTree(Dynamic, types.TreeValue), String) {
  use definition <- result.try(definition(view))
  watershed.open_tree(document, value, definition)
  |> result.map_error(typed_error)
}

@target(erlang)
pub fn open_erlang(
  document: watershed_beam.Document(root),
  value: Json,
  view: schema.ViewSchema,
) -> Result(watershed_beam.SharedTree(Dynamic, types.TreeValue), String) {
  use definition <- result.try(definition(view))
  watershed_beam.open_tree(document, value, definition)
  |> result.map_error(typed_error)
}

@target(javascript)
pub fn create_javascript(
  document: watershed.Document(root),
  initial: types.TreeValue,
  view: schema.ViewSchema,
) -> Result(watershed.SharedTree(Dynamic, types.TreeValue), String) {
  use definition <- result.try(definition(view))
  use builder <- result.try(builder(initial))
  watershed.create_tree(document, definition, builder, Some(initial))
  |> result.map_error(typed_error)
}

@target(javascript)
pub fn create_in_javascript(
  document: watershed.Document(root),
  store: watershed.DataStore,
  initial: types.TreeValue,
  view: schema.ViewSchema,
) -> Result(watershed.SharedTree(Dynamic, types.TreeValue), String) {
  use definition <- result.try(definition(view))
  use builder <- result.try(builder(initial))
  watershed.create_tree_in(document, store, definition, builder, Some(initial))
  |> result.map_error(typed_error)
}

@target(erlang)
pub fn create_erlang(
  document: watershed_beam.Document(root),
  initial: types.TreeValue,
  view: schema.ViewSchema,
) -> Result(watershed_beam.SharedTree(Dynamic, types.TreeValue), String) {
  use definition <- result.try(definition(view))
  use builder <- result.try(builder(initial))
  watershed_beam.create_tree(document, definition, builder, Some(initial))
  |> result.map_error(typed_error)
}

@target(erlang)
pub fn create_in_erlang(
  document: watershed_beam.Document(root),
  store: watershed_beam.DataStore,
  initial: types.TreeValue,
  view: schema.ViewSchema,
) -> Result(watershed_beam.SharedTree(Dynamic, types.TreeValue), String) {
  use definition <- result.try(definition(view))
  use builder <- result.try(builder(initial))
  watershed_beam.create_tree_in(
    document,
    store,
    definition,
    builder,
    Some(initial),
  )
  |> result.map_error(typed_error)
}

@target(javascript)
pub fn create_from_parts_javascript(
  document: watershed.Document(root),
  stored: schema.StoredSchema,
  initial: Option(types.TreeValue),
  view: schema.ViewSchema,
) -> Result(JavascriptTree, String) {
  use _ <- result.try(
    schema.can_view(stored, view) |> result.map_error(string.inspect),
  )
  use definition <- result.try(definition(view))
  use builder <- result.try(root_builder(view, initial))
  case stored == schema.view_to_stored(view) {
    True ->
      watershed.create_tree(document, definition, builder, initial)
      |> result.map_error(typed_error)
    False -> {
      use address <- result.try(runtime.create_tree(
        watershed.runtime_of(document),
        stored,
        initial,
        view,
      ))
      watershed.resolve_tree(
        document,
        handle.encode_handle(address),
        definition,
      )
      |> result.map_error(typed_error)
    }
  }
}

@target(javascript)
pub fn create_in_from_parts_javascript(
  document: watershed.Document(root),
  store: watershed.DataStore,
  stored: schema.StoredSchema,
  initial: Option(types.TreeValue),
  view: schema.ViewSchema,
) -> Result(JavascriptTree, String) {
  use _ <- result.try(
    schema.can_view(stored, view) |> result.map_error(string.inspect),
  )
  use definition <- result.try(definition(view))
  use builder <- result.try(root_builder(view, initial))
  case stored == schema.view_to_stored(view) {
    True ->
      watershed.create_tree_in(document, store, definition, builder, initial)
      |> result.map_error(typed_error)
    False -> {
      use store_id <- result.try(store_id_javascript(store))
      use address <- result.try(runtime.create_tree_in(
        watershed.runtime_of(document),
        store_id,
        stored,
        initial,
        view,
      ))
      watershed.resolve_tree(
        document,
        handle.encode_handle(address),
        definition,
      )
      |> result.map_error(typed_error)
    }
  }
}

@target(erlang)
pub fn create_from_parts_erlang(
  document: watershed_beam.Document(root),
  stored: schema.StoredSchema,
  initial: Option(types.TreeValue),
  view: schema.ViewSchema,
) -> Result(ErlangTree, String) {
  use _ <- result.try(
    schema.can_view(stored, view) |> result.map_error(string.inspect),
  )
  use definition <- result.try(definition(view))
  use builder <- result.try(root_builder(view, initial))
  case stored == schema.view_to_stored(view) {
    True ->
      watershed_beam.create_tree(document, definition, builder, initial)
      |> result.map_error(typed_error)
    False -> {
      use address <- result.try(runtime_beam.create_tree(
        watershed_beam.runtime_subject(document),
        stored,
        initial,
        view,
      ))
      watershed_beam.resolve_tree(
        document,
        handle.encode_handle(address),
        definition,
      )
      |> result.map_error(typed_error)
    }
  }
}

@target(erlang)
pub fn create_in_from_parts_erlang(
  document: watershed_beam.Document(root),
  store: watershed_beam.DataStore,
  stored: schema.StoredSchema,
  initial: Option(types.TreeValue),
  view: schema.ViewSchema,
) -> Result(ErlangTree, String) {
  use _ <- result.try(
    schema.can_view(stored, view) |> result.map_error(string.inspect),
  )
  use definition <- result.try(definition(view))
  use builder <- result.try(root_builder(view, initial))
  case stored == schema.view_to_stored(view) {
    True ->
      watershed_beam.create_tree_in(
        document,
        store,
        definition,
        builder,
        initial,
      )
      |> result.map_error(typed_error)
    False -> {
      use store_id <- result.try(store_id_erlang(store))
      use address <- result.try(runtime_beam.create_tree_in(
        watershed_beam.runtime_subject(document),
        store_id,
        stored,
        initial,
        view,
      ))
      watershed_beam.resolve_tree(
        document,
        handle.encode_handle(address),
        definition,
      )
      |> result.map_error(typed_error)
    }
  }
}

@target(javascript)
pub fn get_javascript(
  tree: watershed.SharedTree(Dynamic, types.TreeValue),
  path: types.FieldPath,
) -> Result(Option(types.TreeValue), String) {
  case path {
    [] -> watershed.tree_read_root(tree) |> result.map_error(typed_error)
    _ -> {
      let assert Ok(#(parent_path, key)) = split_last(path)
      use parent <- result.try(node_javascript(tree, parent_path))
      get_on_javascript(parent, key)
    }
  }
}

@target(erlang)
pub fn get_erlang(
  tree: watershed_beam.SharedTree(Dynamic, types.TreeValue),
  path: types.FieldPath,
) -> Result(Option(types.TreeValue), String) {
  case path {
    [] -> watershed_beam.tree_read_root(tree) |> result.map_error(typed_error)
    _ -> {
      let assert Ok(#(parent_path, key)) = split_last(path)
      use parent <- result.try(node_erlang(tree, parent_path))
      get_on_erlang(parent, key)
    }
  }
}

@target(javascript)
pub fn set_javascript(
  tree: watershed.SharedTree(Dynamic, types.TreeValue),
  path: types.FieldPath,
  value: types.TreeValue,
) -> Result(Nil, String) {
  case split_last(path) {
    Error(Nil) -> {
      use builder <- result.try(builder(value))
      watershed.tree_set_root(tree, builder, value)
      |> result.map_error(typed_error)
    }
    Ok(#(parent_path, key)) -> {
      use parent <- result.try(node_javascript(tree, parent_path))
      set_on_javascript(parent, key, value)
    }
  }
}

@target(erlang)
pub fn set_erlang(
  tree: watershed_beam.SharedTree(Dynamic, types.TreeValue),
  path: types.FieldPath,
  value: types.TreeValue,
) -> Result(Nil, String) {
  case split_last(path) {
    Error(Nil) -> {
      use builder <- result.try(builder(value))
      watershed_beam.tree_set_root(tree, builder, value)
      |> result.map_error(typed_error)
    }
    Ok(#(parent_path, key)) -> {
      use parent <- result.try(node_erlang(tree, parent_path))
      set_on_erlang(parent, key, value)
    }
  }
}

@target(javascript)
pub fn clear_javascript(
  tree: watershed.SharedTree(Dynamic, types.TreeValue),
  path: types.FieldPath,
) -> Result(Nil, String) {
  case split_last(path) {
    Error(Nil) ->
      watershed.tree_clear_root(tree) |> result.map_error(typed_error)
    Ok(#(parent_path, key)) -> {
      use parent <- result.try(node_javascript(tree, parent_path))
      clear_on_javascript(parent, key)
    }
  }
}

@target(erlang)
pub fn clear_erlang(
  tree: watershed_beam.SharedTree(Dynamic, types.TreeValue),
  path: types.FieldPath,
) -> Result(Nil, String) {
  case split_last(path) {
    Error(Nil) ->
      watershed_beam.tree_clear_root(tree) |> result.map_error(typed_error)
    Ok(#(parent_path, key)) -> {
      use parent <- result.try(node_erlang(tree, parent_path))
      clear_on_erlang(parent, key)
    }
  }
}

@target(javascript)
pub fn array_javascript(
  tree: watershed.SharedTree(Dynamic, types.TreeValue),
  path: types.FieldPath,
) -> Result(watershed.TreeArray(Dynamic, types.TreeValue), String) {
  use node <- result.try(node_javascript(tree, path))
  use items <- result.try(array_items(
    node_identifier_javascript(node),
    tree_view_javascript(tree),
  ))
  use codec <- result.try(collection_codec(items))
  watershed.tree_as_array(node, codec) |> result.map_error(typed_error)
}

@target(erlang)
pub fn array_erlang(
  tree: watershed_beam.SharedTree(Dynamic, types.TreeValue),
  path: types.FieldPath,
) -> Result(watershed_beam.TreeArray(Dynamic, types.TreeValue), String) {
  use node <- result.try(node_erlang(tree, path))
  use items <- result.try(array_items(
    node_identifier_erlang(node),
    tree_view_erlang(tree),
  ))
  use codec <- result.try(collection_codec(items))
  watershed_beam.tree_as_array(node, codec) |> result.map_error(typed_error)
}

@target(javascript)
pub fn array_get_javascript(tree, path, index) {
  use array <- result.try(array_javascript(tree, path))
  watershed.tree_array_get(array, index) |> result.map_error(typed_error)
}

@target(erlang)
pub fn array_get_erlang(tree, path, index) {
  use array <- result.try(array_erlang(tree, path))
  watershed_beam.tree_array_get(array, index) |> result.map_error(typed_error)
}

@target(javascript)
pub fn array_values_javascript(tree, path) {
  use array <- result.try(array_javascript(tree, path))
  watershed.tree_array_values(array) |> result.map_error(typed_error)
}

@target(erlang)
pub fn array_values_erlang(tree, path) {
  use array <- result.try(array_erlang(tree, path))
  watershed_beam.tree_array_values(array) |> result.map_error(typed_error)
}

@target(javascript)
pub fn array_insert_javascript(tree, path, index, values) {
  use array <- result.try(array_javascript(tree, path))
  use node <- result.try(node_javascript(tree, path))
  use items <- result.try(array_items(
    node_identifier_javascript(node),
    tree_view_javascript(tree),
  ))
  use builder <- result.try(collection_builder(values, items))
  watershed.tree_array_insert(array, index, builder, values)
  |> result.map_error(typed_error)
}

@target(erlang)
pub fn array_insert_erlang(tree, path, index, values) {
  use array <- result.try(array_erlang(tree, path))
  use node <- result.try(node_erlang(tree, path))
  use items <- result.try(array_items(
    node_identifier_erlang(node),
    tree_view_erlang(tree),
  ))
  use builder <- result.try(collection_builder(values, items))
  watershed_beam.tree_array_insert(array, index, builder, values)
  |> result.map_error(typed_error)
}

@target(javascript)
pub fn array_remove_javascript(tree, path, start, end) {
  use array <- result.try(array_javascript(tree, path))
  watershed.tree_array_remove(array, start, end)
  |> result.map_error(typed_error)
}

@target(erlang)
pub fn array_remove_erlang(tree, path, start, end) {
  use array <- result.try(array_erlang(tree, path))
  watershed_beam.tree_array_remove(array, start, end)
  |> result.map_error(typed_error)
}

@target(javascript)
pub fn array_move_javascript(
  tree,
  source_path,
  start,
  end,
  destination_path,
  destination_gap,
) {
  use source <- result.try(array_javascript(tree, source_path))
  use destination <- result.try(array_javascript(tree, destination_path))
  watershed.tree_array_move(source, start, end, destination, destination_gap)
  |> result.map_error(typed_error)
}

@target(erlang)
pub fn array_move_erlang(
  tree,
  source_path,
  start,
  end,
  destination_path,
  destination_gap,
) {
  use source <- result.try(array_erlang(tree, source_path))
  use destination <- result.try(array_erlang(tree, destination_path))
  watershed_beam.tree_array_move(
    source,
    start,
    end,
    destination,
    destination_gap,
  )
  |> result.map_error(typed_error)
}

@target(javascript)
pub fn map_javascript(
  tree: watershed.SharedTree(Dynamic, types.TreeValue),
  path: types.FieldPath,
) -> Result(watershed.TreeMap(Dynamic, types.TreeValue), String) {
  use node <- result.try(node_javascript(tree, path))
  use items <- result.try(map_items(
    node_identifier_javascript(node),
    tree_view_javascript(tree),
  ))
  use codec <- result.try(collection_codec(items))
  watershed.tree_as_map(node, codec) |> result.map_error(typed_error)
}

@target(erlang)
pub fn map_erlang(
  tree: watershed_beam.SharedTree(Dynamic, types.TreeValue),
  path: types.FieldPath,
) -> Result(watershed_beam.TreeMap(Dynamic, types.TreeValue), String) {
  use node <- result.try(node_erlang(tree, path))
  use items <- result.try(map_items(
    node_identifier_erlang(node),
    tree_view_erlang(tree),
  ))
  use codec <- result.try(collection_codec(items))
  watershed_beam.tree_as_map(node, codec) |> result.map_error(typed_error)
}

@target(javascript)
pub fn map_get_javascript(tree, path, key) {
  use map <- result.try(map_javascript(tree, path))
  watershed.tree_map_get(map, key) |> result.map_error(typed_error)
}

@target(erlang)
pub fn map_get_erlang(tree, path, key) {
  use map <- result.try(map_erlang(tree, path))
  watershed_beam.tree_map_get(map, key) |> result.map_error(typed_error)
}

@target(javascript)
pub fn map_set_javascript(tree, path, key, value) {
  use map <- result.try(map_javascript(tree, path))
  use builder <- result.try(builder(value))
  watershed.tree_map_set(map, key, builder, value)
  |> result.map_error(typed_error)
}

@target(erlang)
pub fn map_set_erlang(tree, path, key, value) {
  use map <- result.try(map_erlang(tree, path))
  use builder <- result.try(builder(value))
  watershed_beam.tree_map_set(map, key, builder, value)
  |> result.map_error(typed_error)
}

@target(javascript)
pub fn map_delete_javascript(tree, path, key) {
  use map <- result.try(map_javascript(tree, path))
  watershed.tree_map_delete(map, key) |> result.map_error(typed_error)
}

@target(erlang)
pub fn map_delete_erlang(tree, path, key) {
  use map <- result.try(map_erlang(tree, path))
  watershed_beam.tree_map_delete(map, key) |> result.map_error(typed_error)
}

@target(javascript)
pub fn map_keys_javascript(tree, path) {
  use map <- result.try(map_javascript(tree, path))
  watershed.tree_map_keys(map) |> result.map_error(typed_error)
}

@target(erlang)
pub fn map_keys_erlang(tree, path) {
  use map <- result.try(map_erlang(tree, path))
  watershed_beam.tree_map_keys(map) |> result.map_error(typed_error)
}

@target(javascript)
pub fn map_entries_javascript(tree, path) {
  use map <- result.try(map_javascript(tree, path))
  watershed.tree_map_entries(map) |> result.map_error(typed_error)
}

@target(erlang)
pub fn map_entries_erlang(tree, path) {
  use map <- result.try(map_erlang(tree, path))
  watershed_beam.tree_map_entries(map) |> result.map_error(typed_error)
}

fn collection_builder(
  values: List(types.TreeValue),
  declared: List(String),
) -> Result(typed.Builder(Dynamic, types.TreeValue), String) {
  case values {
    [first, ..rest] ->
      case
        list.all(rest, fn(value) { identifier(value) == identifier(first) })
      {
        True -> builder(first)
        False -> Error("collection values have different node types")
      }
    [] -> {
      case declared {
        [identifier, ..] ->
          typed.dynamic_builder(identifier) |> result.map_error(typed_error)
        [] -> Error("collection item declaration is empty")
      }
    }
  }
}

@target(javascript)
fn store_id_javascript(store: watershed.DataStore) -> Result(String, String) {
  use root <- result.try(watershed.data_store_root(store))
  store_id(watershed.handle_of(root))
}

@target(erlang)
fn store_id_erlang(store: watershed_beam.DataStore) -> Result(String, String) {
  use root <- result.try(watershed_beam.data_store_root(store))
  store_id(watershed_beam.handle_of(root))
}

fn store_id(marker: Json) -> Result(String, String) {
  use reference <- result.try(
    handle.reference_from_json(marker, "/")
    |> result.map_error(string.inspect),
  )
  case string.split(handle.reference_path(reference), "/") {
    ["", id, "root"] -> Ok(id)
    _ -> Error("data store root has an invalid address")
  }
}

fn root_builder(
  view: schema.ViewSchema,
  initial: Option(types.TreeValue),
) -> Result(typed.Builder(Dynamic, types.TreeValue), String) {
  case initial {
    Some(value) -> builder(value)
    None -> {
      let schema.FieldSchema(_, allowed) =
        schema.root_field_schema(schema.view_to_stored(view))
      use identifier <- result.try(single(allowed, "root"))
      typed.dynamic_builder(identifier) |> result.map_error(typed_error)
    }
  }
}

fn array_items(
  identifier: String,
  view: schema.ViewSchema,
) -> Result(List(String), String) {
  schema.array_element_schema(schema.view_to_stored(view), identifier)
  |> result.map_error(string.inspect)
  |> result.map(fn(field) {
    let schema.FieldSchema(_, allowed) = field
    allowed
  })
}

fn map_items(
  identifier: String,
  view: schema.ViewSchema,
) -> Result(List(String), String) {
  schema.map_entry_schema(schema.view_to_stored(view), identifier)
  |> result.map_error(string.inspect)
  |> result.map(fn(field) {
    let schema.FieldSchema(_, allowed) = field
    allowed
  })
}

fn collection_codec(
  identifiers: List(String),
) -> Result(typed.NodeCodec(Dynamic, types.TreeValue), String) {
  typed.dynamic_union_node(identifiers) |> result.map_error(typed_error)
}

fn single(values: List(String), owner: String) -> Result(String, String) {
  case values {
    [value] -> Ok(value)
    _ -> Error(owner <> " declaration does not have one node type")
  }
}

fn identifier(value: types.TreeValue) -> String {
  case value {
    types.StringValue(_) -> "com.fluidframework.leaf.string"
    types.NumberValue(_) -> "com.fluidframework.leaf.number"
    types.BooleanValue(_) -> "com.fluidframework.leaf.boolean"
    types.HandleValue(_) -> "com.fluidframework.leaf.handle"
    types.NullValue -> "com.fluidframework.leaf.null"
    types.ObjectValue(identifier, _)
    | types.MapValue(identifier, _)
    | types.ArrayValue(identifier, _) -> identifier
  }
}

fn split_last(
  path: types.FieldPath,
) -> Result(#(types.FieldPath, String), Nil) {
  case list.reverse(path) {
    [] -> Error(Nil)
    [last, ..rest] -> Ok(#(list.reverse(rest), last))
  }
}

@target(javascript)
fn tree_view_javascript(
  tree: watershed.SharedTree(Dynamic, types.TreeValue),
) -> schema.ViewSchema {
  watershed.tree_definition_view(tree)
}

@target(erlang)
fn tree_view_erlang(
  tree: watershed_beam.SharedTree(Dynamic, types.TreeValue),
) -> schema.ViewSchema {
  watershed_beam.tree_definition_view(tree)
}

@target(javascript)
fn node_identifier_javascript(
  node: watershed.TreeNode(Dynamic, types.TreeValue),
) -> String {
  watershed.tree_node_type(node)
}

@target(erlang)
fn node_identifier_erlang(
  node: watershed_beam.TreeNode(Dynamic, types.TreeValue),
) -> String {
  watershed_beam.tree_node_type(node)
}

@target(javascript)
pub fn node_javascript(
  tree: watershed.SharedTree(Dynamic, types.TreeValue),
  path: types.FieldPath,
) -> Result(watershed.TreeNode(Dynamic, types.TreeValue), String) {
  use root <- result.try(
    watershed.tree_root(tree) |> result.map_error(typed_error),
  )
  use root <- result.try(case root {
    Some(root) -> Ok(root)
    None -> Error("tree root is absent")
  })
  descend_javascript(root, path, tree_view_javascript(tree))
}

@target(erlang)
pub fn node_erlang(
  tree: watershed_beam.SharedTree(Dynamic, types.TreeValue),
  path: types.FieldPath,
) -> Result(watershed_beam.TreeNode(Dynamic, types.TreeValue), String) {
  use root <- result.try(
    watershed_beam.tree_root(tree) |> result.map_error(typed_error),
  )
  use root <- result.try(case root {
    Some(root) -> Ok(root)
    None -> Error("tree root is absent")
  })
  descend_erlang(root, path, tree_view_erlang(tree))
}

@target(javascript)
pub fn descend_javascript(
  node: watershed.TreeNode(Dynamic, types.TreeValue),
  path: types.FieldPath,
  view: schema.ViewSchema,
) -> Result(watershed.TreeNode(Dynamic, types.TreeValue), String) {
  case path {
    [] -> Ok(node)
    [key, ..rest] -> {
      let stored = schema.view_to_stored(view)
      let owner = node_identifier_javascript(node)
      use child <- result.try(case schema.node_schema(stored, owner) {
        Ok(schema.Object(_)) -> {
          use field <- result.try(
            schema.field_schema(stored, owner, key)
            |> result.map_error(string.inspect),
          )
          let schema.FieldSchema(cardinality, allowed) = field
          use identifier <- result.try(single(allowed, owner <> "." <> key))
          use codec <- result.try(
            typed.dynamic_node(identifier) |> result.map_error(typed_error),
          )
          case cardinality {
            schema.Required -> {
              let descriptor = typed.required_child(key, codec)
              watershed.tree_child(node, descriptor)
              |> result.map_error(typed_error)
              |> and_then(required_node(key))
            }
            schema.Optional -> {
              let descriptor = typed.optional_child(key, codec)
              watershed.tree_child(node, descriptor)
              |> result.map_error(typed_error)
              |> and_then(required_node(key))
            }
            schema.Identifier | schema.Sequence ->
              Error("field is not a structural child: " <> key)
          }
        }
        Ok(schema.Map(_)) -> {
          use items <- result.try(map_items(owner, view))
          use codec <- result.try(collection_codec(items))
          use map <- result.try(
            watershed.tree_as_map(node, codec)
            |> result.map_error(typed_error),
          )
          watershed.tree_map_node(map, key)
          |> result.map_error(typed_error)
          |> and_then(required_node(key))
        }
        Ok(schema.Array(_)) -> {
          use index <- result.try(
            int.parse(key)
            |> result.map_error(fn(_) { "array path is not an index: " <> key }),
          )
          use items <- result.try(array_items(owner, view))
          use codec <- result.try(collection_codec(items))
          use array <- result.try(
            watershed.tree_as_array(node, codec)
            |> result.map_error(typed_error),
          )
          use nodes <- result.try(
            watershed.tree_array_nodes(array)
            |> result.map_error(typed_error),
          )
          node_at(nodes, index)
        }
        Ok(schema.Leaf(_)) -> Error("leaf node has no child: " <> key)
        Error(error) -> Error(string.inspect(error))
      })
      descend_javascript(child, rest, view)
    }
  }
}

@target(erlang)
pub fn descend_erlang(
  node: watershed_beam.TreeNode(Dynamic, types.TreeValue),
  path: types.FieldPath,
  view: schema.ViewSchema,
) -> Result(watershed_beam.TreeNode(Dynamic, types.TreeValue), String) {
  case path {
    [] -> Ok(node)
    [key, ..rest] -> {
      let stored = schema.view_to_stored(view)
      let owner = node_identifier_erlang(node)
      use child <- result.try(case schema.node_schema(stored, owner) {
        Ok(schema.Object(_)) -> {
          use field <- result.try(
            schema.field_schema(stored, owner, key)
            |> result.map_error(string.inspect),
          )
          let schema.FieldSchema(cardinality, allowed) = field
          use identifier <- result.try(single(allowed, owner <> "." <> key))
          use codec <- result.try(
            typed.dynamic_node(identifier) |> result.map_error(typed_error),
          )
          case cardinality {
            schema.Required -> {
              let descriptor = typed.required_child(key, codec)
              watershed_beam.tree_child(node, descriptor)
              |> result.map_error(typed_error)
              |> and_then(required_node(key))
            }
            schema.Optional -> {
              let descriptor = typed.optional_child(key, codec)
              watershed_beam.tree_child(node, descriptor)
              |> result.map_error(typed_error)
              |> and_then(required_node(key))
            }
            schema.Identifier | schema.Sequence ->
              Error("field is not a structural child: " <> key)
          }
        }
        Ok(schema.Map(_)) -> {
          use items <- result.try(map_items(owner, view))
          use codec <- result.try(collection_codec(items))
          use map <- result.try(
            watershed_beam.tree_as_map(node, codec)
            |> result.map_error(typed_error),
          )
          watershed_beam.tree_map_node(map, key)
          |> result.map_error(typed_error)
          |> and_then(required_node(key))
        }
        Ok(schema.Array(_)) -> {
          use index <- result.try(
            int.parse(key)
            |> result.map_error(fn(_) { "array path is not an index: " <> key }),
          )
          use items <- result.try(array_items(owner, view))
          use codec <- result.try(collection_codec(items))
          use array <- result.try(
            watershed_beam.tree_as_array(node, codec)
            |> result.map_error(typed_error),
          )
          use nodes <- result.try(
            watershed_beam.tree_array_nodes(array)
            |> result.map_error(typed_error),
          )
          node_at(nodes, index)
        }
        Ok(schema.Leaf(_)) -> Error("leaf node has no child: " <> key)
        Error(error) -> Error(string.inspect(error))
      })
      descend_erlang(child, rest, view)
    }
  }
}

fn required_node(key: String) -> fn(Option(a)) -> Result(a, String) {
  fn(value) {
    case value {
      Some(value) -> Ok(value)
      None -> Error("tree child is absent: " <> key)
    }
  }
}

fn and_then(
  outcome: Result(a, error),
  next: fn(a) -> Result(b, error),
) -> Result(b, error) {
  case outcome {
    Ok(value) -> next(value)
    Error(error) -> Error(error)
  }
}

fn node_at(nodes: List(a), index: Int) -> Result(a, String) {
  case index < 0 {
    True -> Error("array index is negative")
    False ->
      case list.first(list.drop(nodes, index)) {
        Ok(node) -> Ok(node)
        Error(Nil) -> Error("array index is out of bounds")
      }
  }
}

@target(javascript)
fn set_on_javascript(
  node: watershed.TreeNode(Dynamic, types.TreeValue),
  key: String,
  value: types.TreeValue,
) -> Result(Nil, String) {
  let view = watershed.tree_definition_view_from_node(node)
  set_object_or_map_javascript(node, key, value, view)
}

@target(javascript)
fn get_on_javascript(
  node: watershed.TreeNode(Dynamic, types.TreeValue),
  key: String,
) -> Result(Option(types.TreeValue), String) {
  let view = watershed.tree_definition_view_from_node(node)
  let stored = schema.view_to_stored(view)
  let owner = node_identifier_javascript(node)
  case schema.node_schema(stored, owner) {
    Ok(schema.Object(_)) -> {
      use field <- result.try(
        schema.field_schema(stored, owner, key)
        |> result.map_error(string.inspect),
      )
      let schema.FieldSchema(cardinality, allowed) = field
      use target <- result.try(single(allowed, owner <> "." <> key))
      use leaf <- result.try(is_leaf(stored, target))
      case cardinality, leaf {
        schema.Identifier, _ ->
          watershed.tree_identifier(node, typed.identifier(key))
          |> result.map(types.StringValue)
          |> result.map(Some)
          |> result.map_error(typed_error)
        schema.Required, True ->
          watershed.tree_get(
            node,
            typed.required(key, typed.dynamic_codec(target)),
          )
          |> result.map(Some)
          |> result.map_error(typed_error)
        schema.Optional, True ->
          watershed.tree_get_optional(
            node,
            typed.optional(key, typed.dynamic_codec(target)),
          )
          |> result.map_error(typed_error)
        schema.Required, False | schema.Optional, False -> {
          use codec <- result.try(
            typed.dynamic_node(target) |> result.map_error(typed_error),
          )
          let child = case cardinality {
            schema.Required ->
              watershed.tree_child(node, typed.required_child(key, codec))
            schema.Optional ->
              watershed.tree_child(node, typed.optional_child(key, codec))
            _ -> panic as "unreachable child cardinality"
          }
          use child <- result.try(child |> result.map_error(typed_error))
          case child {
            None -> Ok(None)
            Some(child) ->
              watershed.tree_read(child)
              |> result.map(Some)
              |> result.map_error(typed_error)
          }
        }
        schema.Sequence, _ ->
          Error("field is not a readable singleton: " <> key)
      }
    }
    Ok(schema.Map(_)) -> {
      use items <- result.try(map_items(owner, view))
      use codec <- result.try(collection_codec(items))
      use map <- result.try(
        watershed.tree_as_map(node, codec)
        |> result.map_error(typed_error),
      )
      watershed.tree_map_get(map, key) |> result.map_error(typed_error)
    }
    Ok(_) -> Error("node does not have a readable field: " <> key)
    Error(error) -> Error(string.inspect(error))
  }
}

@target(erlang)
fn set_on_erlang(
  node: watershed_beam.TreeNode(Dynamic, types.TreeValue),
  key: String,
  value: types.TreeValue,
) -> Result(Nil, String) {
  let view = watershed_beam.tree_definition_view_from_node(node)
  set_object_or_map_erlang(node, key, value, view)
}

@target(erlang)
fn get_on_erlang(
  node: watershed_beam.TreeNode(Dynamic, types.TreeValue),
  key: String,
) -> Result(Option(types.TreeValue), String) {
  let view = watershed_beam.tree_definition_view_from_node(node)
  let stored = schema.view_to_stored(view)
  let owner = node_identifier_erlang(node)
  case schema.node_schema(stored, owner) {
    Ok(schema.Object(_)) -> {
      use field <- result.try(
        schema.field_schema(stored, owner, key)
        |> result.map_error(string.inspect),
      )
      let schema.FieldSchema(cardinality, allowed) = field
      use target <- result.try(single(allowed, owner <> "." <> key))
      use leaf <- result.try(is_leaf(stored, target))
      case cardinality, leaf {
        schema.Identifier, _ ->
          watershed_beam.tree_identifier(node, typed.identifier(key))
          |> result.map(types.StringValue)
          |> result.map(Some)
          |> result.map_error(typed_error)
        schema.Required, True ->
          watershed_beam.tree_get(
            node,
            typed.required(key, typed.dynamic_codec(target)),
          )
          |> result.map(Some)
          |> result.map_error(typed_error)
        schema.Optional, True ->
          watershed_beam.tree_get_optional(
            node,
            typed.optional(key, typed.dynamic_codec(target)),
          )
          |> result.map_error(typed_error)
        schema.Required, False | schema.Optional, False -> {
          use codec <- result.try(
            typed.dynamic_node(target) |> result.map_error(typed_error),
          )
          let child = case cardinality {
            schema.Required ->
              watershed_beam.tree_child(node, typed.required_child(key, codec))
            schema.Optional ->
              watershed_beam.tree_child(node, typed.optional_child(key, codec))
            _ -> panic as "unreachable child cardinality"
          }
          use child <- result.try(child |> result.map_error(typed_error))
          case child {
            None -> Ok(None)
            Some(child) ->
              watershed_beam.tree_read(child)
              |> result.map(Some)
              |> result.map_error(typed_error)
          }
        }
        schema.Sequence, _ ->
          Error("field is not a readable singleton: " <> key)
      }
    }
    Ok(schema.Map(_)) -> {
      use items <- result.try(map_items(owner, view))
      use codec <- result.try(collection_codec(items))
      use map <- result.try(
        watershed_beam.tree_as_map(node, codec)
        |> result.map_error(typed_error),
      )
      watershed_beam.tree_map_get(map, key) |> result.map_error(typed_error)
    }
    Ok(_) -> Error("node does not have a readable field: " <> key)
    Error(error) -> Error(string.inspect(error))
  }
}

@target(javascript)
fn set_object_or_map_javascript(
  node: watershed.TreeNode(Dynamic, types.TreeValue),
  key: String,
  value: types.TreeValue,
  view: schema.ViewSchema,
) -> Result(Nil, String) {
  let stored = schema.view_to_stored(view)
  let owner = node_identifier_javascript(node)
  case schema.node_schema(stored, owner) {
    Ok(schema.Object(_)) -> {
      use field <- result.try(
        schema.field_schema(stored, owner, key)
        |> result.map_error(string.inspect),
      )
      let schema.FieldSchema(cardinality, allowed) = field
      use target <- result.try(single(allowed, owner <> "." <> key))
      use leaf <- result.try(is_leaf(stored, target))
      case leaf, cardinality {
        True, schema.Required ->
          watershed.tree_set(
            node,
            typed.required(key, typed.dynamic_codec(target)),
            value,
          )
          |> result.map_error(typed_error)
        True, schema.Optional ->
          watershed.tree_set(
            node,
            typed.optional(key, typed.dynamic_codec(target)),
            value,
          )
          |> result.map_error(typed_error)
        False, schema.Required -> {
          use codec <- result.try(
            typed.dynamic_node(target) |> result.map_error(typed_error),
          )
          use builder <- result.try(builder(value))
          watershed.tree_set_child(
            node,
            typed.required_child(key, codec),
            builder,
            value,
          )
          |> result.map_error(typed_error)
        }
        False, schema.Optional -> {
          use codec <- result.try(
            typed.dynamic_node(target) |> result.map_error(typed_error),
          )
          use builder <- result.try(builder(value))
          watershed.tree_set_child(
            node,
            typed.optional_child(key, codec),
            builder,
            value,
          )
          |> result.map_error(typed_error)
        }
        _, schema.Identifier -> Error("identifier field is read-only: " <> key)
        _, schema.Sequence ->
          Error("sequence field cannot be assigned: " <> key)
      }
    }
    Ok(schema.Map(_)) -> {
      use items <- result.try(map_items(owner, view))
      use codec <- result.try(collection_codec(items))
      use map <- result.try(
        watershed.tree_as_map(node, codec)
        |> result.map_error(typed_error),
      )
      use builder <- result.try(builder(value))
      watershed.tree_map_set(map, key, builder, value)
      |> result.map_error(typed_error)
    }
    Ok(schema.Array(_)) -> Error("array elements cannot be assigned by path")
    Ok(schema.Leaf(_)) -> Error("leaf node has no field: " <> key)
    Error(error) -> Error(string.inspect(error))
  }
}

@target(erlang)
fn set_object_or_map_erlang(
  node: watershed_beam.TreeNode(Dynamic, types.TreeValue),
  key: String,
  value: types.TreeValue,
  view: schema.ViewSchema,
) -> Result(Nil, String) {
  let stored = schema.view_to_stored(view)
  let owner = node_identifier_erlang(node)
  case schema.node_schema(stored, owner) {
    Ok(schema.Object(_)) -> {
      use field <- result.try(
        schema.field_schema(stored, owner, key)
        |> result.map_error(string.inspect),
      )
      let schema.FieldSchema(cardinality, allowed) = field
      use target <- result.try(single(allowed, owner <> "." <> key))
      use leaf <- result.try(is_leaf(stored, target))
      case leaf, cardinality {
        True, schema.Required ->
          watershed_beam.tree_set(
            node,
            typed.required(key, typed.dynamic_codec(target)),
            value,
          )
          |> result.map_error(typed_error)
        True, schema.Optional ->
          watershed_beam.tree_set(
            node,
            typed.optional(key, typed.dynamic_codec(target)),
            value,
          )
          |> result.map_error(typed_error)
        False, schema.Required -> {
          use codec <- result.try(
            typed.dynamic_node(target) |> result.map_error(typed_error),
          )
          use builder <- result.try(builder(value))
          watershed_beam.tree_set_child(
            node,
            typed.required_child(key, codec),
            builder,
            value,
          )
          |> result.map_error(typed_error)
        }
        False, schema.Optional -> {
          use codec <- result.try(
            typed.dynamic_node(target) |> result.map_error(typed_error),
          )
          use builder <- result.try(builder(value))
          watershed_beam.tree_set_child(
            node,
            typed.optional_child(key, codec),
            builder,
            value,
          )
          |> result.map_error(typed_error)
        }
        _, schema.Identifier -> Error("identifier field is read-only: " <> key)
        _, schema.Sequence ->
          Error("sequence field cannot be assigned: " <> key)
      }
    }
    Ok(schema.Map(_)) -> {
      use items <- result.try(map_items(owner, view))
      use codec <- result.try(collection_codec(items))
      use map <- result.try(
        watershed_beam.tree_as_map(node, codec)
        |> result.map_error(typed_error),
      )
      use builder <- result.try(builder(value))
      watershed_beam.tree_map_set(map, key, builder, value)
      |> result.map_error(typed_error)
    }
    Ok(schema.Array(_)) -> Error("array elements cannot be assigned by path")
    Ok(schema.Leaf(_)) -> Error("leaf node has no field: " <> key)
    Error(error) -> Error(string.inspect(error))
  }
}

@target(javascript)
fn clear_on_javascript(
  node: watershed.TreeNode(Dynamic, types.TreeValue),
  key: String,
) -> Result(Nil, String) {
  let view = watershed.tree_definition_view_from_node(node)
  let stored = schema.view_to_stored(view)
  let owner = node_identifier_javascript(node)
  case schema.node_schema(stored, owner) {
    Ok(schema.Object(_)) -> {
      use field <- result.try(
        schema.field_schema(stored, owner, key)
        |> result.map_error(string.inspect),
      )
      let schema.FieldSchema(cardinality, allowed) = field
      use target <- result.try(single(allowed, owner <> "." <> key))
      use leaf <- result.try(is_leaf(stored, target))
      case cardinality, leaf {
        schema.Optional, True ->
          watershed.tree_clear(
            node,
            typed.optional(key, typed.dynamic_codec(target)),
          )
          |> result.map_error(typed_error)
        schema.Optional, False -> {
          use codec <- result.try(
            typed.dynamic_node(target) |> result.map_error(typed_error),
          )
          watershed.tree_clear_child(node, typed.optional_child(key, codec))
          |> result.map_error(typed_error)
        }
        _, _ -> Error("field is not optional: " <> key)
      }
    }
    Ok(schema.Map(_)) -> {
      use items <- result.try(map_items(owner, view))
      use codec <- result.try(collection_codec(items))
      use map <- result.try(
        watershed.tree_as_map(node, codec)
        |> result.map_error(typed_error),
      )
      watershed.tree_map_delete(map, key) |> result.map_error(typed_error)
    }
    Ok(_) -> Error("node does not have a clearable field: " <> key)
    Error(error) -> Error(string.inspect(error))
  }
}

@target(erlang)
fn clear_on_erlang(
  node: watershed_beam.TreeNode(Dynamic, types.TreeValue),
  key: String,
) -> Result(Nil, String) {
  let view = watershed_beam.tree_definition_view_from_node(node)
  let stored = schema.view_to_stored(view)
  let owner = node_identifier_erlang(node)
  case schema.node_schema(stored, owner) {
    Ok(schema.Object(_)) -> {
      use field <- result.try(
        schema.field_schema(stored, owner, key)
        |> result.map_error(string.inspect),
      )
      let schema.FieldSchema(cardinality, allowed) = field
      use target <- result.try(single(allowed, owner <> "." <> key))
      use leaf <- result.try(is_leaf(stored, target))
      case cardinality, leaf {
        schema.Optional, True ->
          watershed_beam.tree_clear(
            node,
            typed.optional(key, typed.dynamic_codec(target)),
          )
          |> result.map_error(typed_error)
        schema.Optional, False -> {
          use codec <- result.try(
            typed.dynamic_node(target) |> result.map_error(typed_error),
          )
          watershed_beam.tree_clear_child(
            node,
            typed.optional_child(key, codec),
          )
          |> result.map_error(string.inspect)
        }
        _, _ -> Error("field is not optional: " <> key)
      }
    }
    Ok(schema.Map(_)) -> {
      use items <- result.try(map_items(owner, view))
      use codec <- result.try(collection_codec(items))
      use map <- result.try(
        watershed_beam.tree_as_map(node, codec)
        |> result.map_error(typed_error),
      )
      watershed_beam.tree_map_delete(map, key)
      |> result.map_error(typed_error)
    }
    Ok(_) -> Error("node does not have a clearable field: " <> key)
    Error(error) -> Error(string.inspect(error))
  }
}

fn is_leaf(
  stored: schema.StoredSchema,
  identifier: String,
) -> Result(Bool, String) {
  schema.node_schema(stored, identifier)
  |> result.map(fn(node) {
    case node {
      schema.Leaf(_) -> True
      _ -> False
    }
  })
  |> result.map_error(string.inspect)
}
