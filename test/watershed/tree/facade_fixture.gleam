//// Raw runtime access for protocol, storage, and interoperability tests.

@target(erlang)
import gleam/erlang/process
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
@target(javascript)
import watershed as facade
import watershed/callback
import watershed/channel
import watershed/handle
@target(javascript)
import watershed/runtime
@target(erlang)
import watershed/runtime_beam as runtime
import watershed/tree/forest
import watershed/tree/schema
import watershed/tree/typed
import watershed/tree/types
import watershed/tree_kernel
@target(erlang)
import watershed_beam as facade

pub type Dynamic

pub opaque type RawTree(connection) {
  RawTree(
    runtime: connection,
    address: String,
    selector: types.CheckoutSelector,
    view: schema.ViewSchema,
  )
}

@target(javascript)
pub type Tree =
  RawTree(runtime.Runtime)

@target(erlang)
pub type Tree =
  RawTree(process.Subject(runtime.Msg))

pub opaque type Node {
  Node(tree: Tree, reference: forest.NodeRef)
}

pub type Constraint {
  NodeInDocument(types.FieldPath)
}

pub type TransactionError(e) {
  Aborted(e)
  TransactionFailed(String)
}

pub fn definition(
  view: schema.ViewSchema,
) -> Result(typed.Schema(Dynamic, types.TreeValue), String) {
  let schema.FieldSchema(_, allowed) =
    schema.root_field_schema(schema.view_to_stored(view))
  use identifier <- result.try(case allowed {
    [identifier] -> Ok(identifier)
    _ -> Error("root declaration does not have one node type")
  })
  use codec <- result.try(
    typed.dynamic_node(identifier) |> result.map_error(string.inspect),
  )
  typed.schema(view, codec) |> result.map_error(string.inspect)
}

@target(javascript)
fn connection(document: facade.Document(root)) -> runtime.Runtime {
  facade.runtime_of(document)
}

@target(erlang)
fn connection(document: facade.Document(root)) -> process.Subject(runtime.Msg) {
  facade.runtime_subject(document)
}

pub fn resolve(
  document: facade.Document(root),
  marker: Json,
  view: schema.ViewSchema,
) -> Result(Tree, String) {
  let runtime = connection(document)
  use address <- result.try(runtime.resolve_tree(runtime, marker, view))
  Ok(RawTree(runtime, address, types.DocumentCheckout, view))
}

pub fn open(
  document: facade.Document(root),
  marker: Json,
  view: schema.ViewSchema,
) -> Result(Tree, String) {
  let runtime = connection(document)
  use address <- result.try(runtime.open_tree(runtime, marker))
  Ok(RawTree(runtime, address, types.DocumentCheckout, view))
}

pub fn create(
  document: facade.Document(root),
  initial: types.TreeValue,
  view: schema.ViewSchema,
) -> Result(Tree, String) {
  create_from_parts(document, schema.view_to_stored(view), Some(initial), view)
}

pub fn create_in(
  document: facade.Document(root),
  store: facade.DataStore,
  initial: types.TreeValue,
  view: schema.ViewSchema,
) -> Result(Tree, String) {
  create_in_from_parts(
    document,
    store,
    schema.view_to_stored(view),
    Some(initial),
    view,
  )
}

pub fn create_from_parts(
  document: facade.Document(root),
  stored: schema.StoredSchema,
  initial: Option(types.TreeValue),
  view: schema.ViewSchema,
) -> Result(Tree, String) {
  let runtime = connection(document)
  use address <- result.try(runtime.create_tree(runtime, stored, initial, view))
  Ok(RawTree(runtime, address, types.DocumentCheckout, view))
}

pub fn create_in_from_parts(
  document: facade.Document(root),
  store: facade.DataStore,
  stored: schema.StoredSchema,
  initial: Option(types.TreeValue),
  view: schema.ViewSchema,
) -> Result(Tree, String) {
  use root <- result.try(facade.data_store_root(store))
  use reference <- result.try(
    handle.reference_from_json(facade.handle_of(root), "/")
    |> result.map_error(string.inspect),
  )
  use store_id <- result.try(
    case string.split(handle.reference_path(reference), "/") {
      ["", store_id, "root"] -> Ok(store_id)
      _ -> Error("data store root has an invalid address")
    },
  )
  let runtime = connection(document)
  use address <- result.try(runtime.create_tree_in(
    runtime,
    store_id,
    stored,
    initial,
    view,
  ))
  Ok(RawTree(runtime, address, types.DocumentCheckout, view))
}

pub fn get(
  tree: Tree,
  path: types.FieldPath,
) -> Result(Option(types.TreeValue), String) {
  use _ <- result.try(case split_last(path) {
    None -> Ok(Nil)
    Some(#(parent, key)) -> {
      use value <- result.try(read(tree, parent))
      case value {
        Some(types.ObjectValue(identifier, _)) ->
          schema.field_schema(schema.view_to_stored(tree.view), identifier, key)
          |> result.replace(Nil)
          |> result.map_error(string.inspect)
        Some(types.MapValue(_, _)) -> Ok(Nil)
        Some(_) -> Error("node does not have a readable field: " <> key)
        None -> Error("parent node is absent")
      }
    }
  })
  read(tree, path)
}

pub fn read_root(tree: Tree) -> Result(Option(types.TreeValue), String) {
  read(tree, [])
}

fn read(
  tree: Tree,
  path: types.FieldPath,
) -> Result(Option(types.TreeValue), String) {
  runtime.tree_read_view_on(
    tree.runtime,
    tree.address,
    tree.selector,
    tree.view,
    path,
  )
}

pub fn set(
  tree: Tree,
  path: types.FieldPath,
  value: types.TreeValue,
) -> Result(Nil, String) {
  use change <- result.try(case split_last(path) {
    None -> Ok(types.SetField([], value))
    Some(#(parent, key)) -> {
      use owner <- result.try(read(tree, parent))
      case owner {
        Some(types.MapValue(_, _)) -> Ok(types.MapSet(parent, key, value))
        Some(types.ObjectValue(identifier, _)) -> {
          let stored = schema.view_to_stored(tree.view)
          use _ <- result.try(
            schema.node_schema(stored, schema.value_identifier(value))
            |> result.map_error(string.inspect),
          )
          use field <- result.try(
            schema.field_schema(stored, identifier, key)
            |> result.map_error(string.inspect),
          )
          case field {
            schema.FieldSchema(schema.Identifier, _) ->
              Error("identifier field is read-only: " <> key)
            schema.FieldSchema(schema.Sequence, _) ->
              Error("sequence field cannot be assigned: " <> key)
            _ -> {
              use _ <- result.try(
                schema.validate_field(stored, identifier, key, Some(value))
                |> result.map_error(string.inspect),
              )
              Ok(types.SetField(path, value))
            }
          }
        }
        Some(types.ArrayValue(_, _)) ->
          Error("array elements cannot be assigned by path")
        Some(_) -> Error("leaf node has no field: " <> key)
        None -> Error("parent node is absent")
      }
    }
  })
  edit(tree, change)
}

pub fn clear(tree: Tree, path: types.FieldPath) -> Result(Nil, String) {
  use change <- result.try(case split_last(path) {
    None -> Ok(types.ClearField([]))
    Some(#(parent, key)) -> {
      use owner <- result.try(read(tree, parent))
      case owner {
        Some(types.MapValue(_, _)) -> Ok(types.MapDelete(parent, key))
        Some(types.ObjectValue(identifier, _)) -> {
          use _ <- result.try(
            schema.validate_field(
              schema.view_to_stored(tree.view),
              identifier,
              key,
              None,
            )
            |> result.map_error(string.inspect),
          )
          Ok(types.ClearField(path))
        }
        Some(_) -> Error("node does not have a clearable field: " <> key)
        None -> Error("parent node is absent")
      }
    }
  })
  edit(tree, change)
}

fn edit(tree: Tree, change: types.Edit) -> Result(Nil, String) {
  runtime.tree_edit_view_on(
    tree.runtime,
    tree.address,
    tree.selector,
    tree.view,
    change,
  )
}

pub fn array_get(tree: Tree, path: types.FieldPath, index: Int) {
  runtime.tree_array_get_view_on(
    tree.runtime,
    tree.address,
    tree.selector,
    tree.view,
    path,
    index,
  )
}

pub fn array_values(tree: Tree, path: types.FieldPath) {
  runtime.tree_array_values_view_on(
    tree.runtime,
    tree.address,
    tree.selector,
    tree.view,
    path,
  )
}

pub fn array_insert(tree: Tree, path, index, values) {
  edit(tree, types.ArrayInsert(path, index, values))
}

pub fn array_remove(tree: Tree, path, start, end) {
  edit(tree, types.ArrayRemove(path, start, end))
}

pub fn array_move(
  tree: Tree,
  source_path,
  start,
  end,
  destination_path,
  destination_gap,
) {
  edit(
    tree,
    types.ArrayMove(source_path, start, end, destination_path, destination_gap),
  )
}

pub fn map_get(tree: Tree, path: types.FieldPath, key: String) {
  runtime.tree_map_get_view_on(
    tree.runtime,
    tree.address,
    tree.selector,
    tree.view,
    path,
    key,
  )
}

pub fn map_entries(tree: Tree, path: types.FieldPath) {
  runtime.tree_map_entries_view_on(
    tree.runtime,
    tree.address,
    tree.selector,
    tree.view,
    path,
  )
}

pub fn map_keys(tree: Tree, path: types.FieldPath) {
  map_entries(tree, path)
  |> result.map(fn(entries) { list.map(entries, fn(e) { e.0 }) })
}

pub fn map_set(tree: Tree, path, key, value) {
  edit(tree, types.MapSet(path, key, value))
}

pub fn map_delete(tree: Tree, path, key) {
  edit(tree, types.MapDelete(path, key))
}

pub fn node(tree: Tree, path: types.FieldPath) -> Result(Node, String) {
  use reference <- result.try(runtime.tree_node_reference_view_on(
    tree.runtime,
    tree.address,
    tree.selector,
    tree.view,
    path,
  ))
  case reference {
    Some(reference) -> Ok(Node(tree, reference))
    None -> Error("node is absent")
  }
}

pub fn descend(
  node: Node,
  path: types.FieldPath,
  view: schema.ViewSchema,
) -> Result(Node, String) {
  let Node(tree, reference) = node
  use reference <- result.try(runtime.tree_node_child_view_on(
    tree.runtime,
    tree.address,
    tree.selector,
    view,
    reference,
    path,
  ))
  case reference {
    Some(reference) -> Ok(Node(RawTree(..tree, view: view), reference))
    None -> Error("node is absent")
  }
}

pub fn handle_of(tree: Tree) -> Json {
  handle.encode_handle(tree.address)
}

pub fn compatibility(tree: Tree) {
  runtime.tree_compatibility_on(
    tree.runtime,
    tree.address,
    tree.selector,
    tree.view,
  )
}

pub fn upgrade_schema(tree: Tree) {
  runtime.tree_upgrade_schema_on(
    tree.runtime,
    tree.address,
    tree.selector,
    tree.view,
  )
}

pub fn fork(tree: Tree) -> Result(Tree, String) {
  runtime.tree_fork(tree.runtime, tree.address, tree.selector, tree.view)
  |> result.map(fn(selector) { RawTree(..tree, selector: selector) })
}

pub fn rebase_onto(source: Tree, target: Tree) -> Result(Nil, String) {
  use _ <- result.try(same_origin(source, target))
  runtime.tree_rebase_onto(
    source.runtime,
    source.address,
    source.selector,
    target.selector,
  )
}

pub fn merge(target: Tree, source: Tree, dispose_source: Bool) {
  use _ <- result.try(same_origin(source, target))
  runtime.tree_merge(
    target.runtime,
    target.address,
    target.selector,
    source.selector,
    dispose_source,
  )
}

fn same_origin(first: Tree, second: Tree) -> Result(Nil, String) {
  case first.runtime == second.runtime && first.address == second.address {
    True -> Ok(Nil)
    False -> Error("tree handles do not have the same origin")
  }
}

pub fn branch_status(tree: Tree) {
  runtime.tree_branch_status(tree.runtime, tree.address, tree.selector)
}

pub fn dispose_branch(tree: Tree) {
  runtime.tree_dispose_branch(tree.runtime, tree.address, tree.selector)
}

pub fn history_evidence(tree: Tree) {
  runtime.tree_history_evidence(tree.runtime, tree.address)
}

pub fn retained_snapshot(tree: Tree) {
  runtime.tree_retained_snapshot(tree.runtime, tree.address)
}

pub fn transaction(
  tree: Tree,
  constraints: List(Constraint),
  callback: fn(Tree) -> Result(value, e),
) -> Result(value, TransactionError(e)) {
  let paths =
    list.map(constraints, fn(constraint) {
      let NodeInDocument(path) = constraint
      path
    })
  use _ <- result.try(
    runtime.begin_tree_transaction_on(
      tree.runtime,
      tree.address,
      tree.selector,
      tree.view,
      paths,
    )
    |> result.map_error(TransactionFailed),
  )
  case callback.capture(fn() { callback(tree) }) {
    Ok(Ok(value)) ->
      runtime.commit_tree_transaction_on(
        tree.runtime,
        tree.address,
        tree.selector,
      )
      |> result.replace(value)
      |> result.map_error(TransactionFailed)
    Ok(Error(error)) ->
      case abort(tree) {
        Ok(Nil) -> Error(Aborted(error))
        Error(reason) -> Error(TransactionFailed(reason))
      }
    Error(exception) ->
      case abort(tree) {
        Ok(Nil) ->
          Error(TransactionFailed(
            "tree transaction callback failed: " <> exception,
          ))
        Error(reason) ->
          Error(TransactionFailed(
            "tree transaction callback failed: "
            <> exception
            <> "; transaction abort failed: "
            <> reason,
          ))
      }
  }
}

fn abort(tree: Tree) -> Result(Nil, String) {
  runtime.abort_tree_transaction_on(tree.runtime, tree.address, tree.selector)
}

@target(javascript)
pub fn subscribe(tree: Tree, handler: fn(tree_kernel.TreeEvent) -> Nil) {
  runtime.subscribe_on(tree.runtime, tree.address, tree.selector, fn(event) {
    case event {
      channel.TreeEvent(event) -> handler(event)
      _ -> Nil
    }
  })
}

@target(erlang)
pub fn subscribe(tree: Tree) -> process.Subject(tree_kernel.TreeEvent) {
  let subject = process.new_subject()
  runtime.subscribe_tree_events_on(
    tree.runtime,
    tree.address,
    tree.selector,
    fn(event) {
      case event {
        channel.TreeEvent(event) -> process.send(subject, event)
        _ -> Nil
      }
    },
  )
  subject
}

pub fn subscribe_commits(
  tree: Tree,
  handler: fn(runtime.TreeCommitEvent) -> Nil,
) -> runtime.SubscriptionToken {
  runtime.subscribe_tree_commits_on(
    tree.runtime,
    tree.address,
    tree.selector,
    handler,
  )
}

fn split_last(path: List(String)) -> Option(#(List(String), String)) {
  case list.reverse(path) {
    [] -> None
    [last, ..rest] -> Some(#(list.reverse(rest), last))
  }
}
