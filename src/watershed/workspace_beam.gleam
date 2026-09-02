//// BEAM persistence adapter for a component workspace.
////
//// The adapter stores one workspace child map with a manifest map, a layout
//// sequence, and a connection sequence. It does not start components.

@target(erlang)
import gleam/json.{type Json}
@target(erlang)
import gleam/list
@target(erlang)
import gleam/option.{type Option, None, Some}
@target(erlang)
import gleam/result
@target(erlang)
import gleam/string
@target(erlang)
import watershed/component
@target(erlang)
import watershed/port_graph
@target(erlang)
import watershed/schema.{type ChildField, child_key}
@target(erlang)
import watershed/workspace
@target(erlang)
import watershed_beam

@target(erlang)
/// A workspace persistence error.
pub type WorkspaceError {
  InvalidInstanceId
  DuplicateInstance(instance_id: String)
  InvalidMove(instance_id: String, to_index: Int)
  UnsupportedComponent(reason: component.LookupError)
  InvalidComponentConfig(reason: component.ComponentError)
  ConnectionRejected(reason: workspace.ConnectionError)
  StorageError(reason: String)
}

@target(erlang)
/// The resolved channels of one workspace.
pub opaque type Workspace(root) {
  Workspace(
    document: watershed_beam.Document(root),
    map: watershed_beam.TypedMap(workspace.WorkspaceSchema),
    manifest: watershed_beam.SharedMap,
    layout: watershed_beam.SharedSequence,
    connections: watershed_beam.SharedSequence,
  )
}

@target(erlang)
/// Adopt an existing workspace or create a complete workspace subtree.
pub fn ensure(
  document: watershed_beam.Document(root),
  root: watershed_beam.TypedMap(parent),
  field: ChildField(parent, workspace.WorkspaceSchema),
) -> Result(Workspace(root), WorkspaceError) {
  case watershed_beam.has(watershed_beam.untyped(root), child_key(field)) {
    False -> create(document, root, field)
    True -> {
      use map <- result.try(
        watershed_beam.ensure_child(document, root, field)
        |> result.map_error(StorageError),
      )
      open(document, map)
    }
  }
}

@target(erlang)
/// Resolve an existing workspace without changing it.
pub fn resolve(
  document: watershed_beam.Document(root),
  root: watershed_beam.TypedMap(parent),
  field: ChildField(parent, workspace.WorkspaceSchema),
) -> Result(Workspace(root), WorkspaceError) {
  use map <- result.try(
    watershed_beam.resolve_child(document, root, field)
    |> require("workspace child is missing"),
  )
  open(document, map)
}

@target(erlang)
fn open(
  document: watershed_beam.Document(root),
  map: watershed_beam.TypedMap(workspace.WorkspaceSchema),
) -> Result(Workspace(root), WorkspaceError) {
  use manifest <- result.try(
    watershed_beam.resolve_map_field(document, map, workspace.manifest_field())
    |> require("workspace manifest is missing"),
  )
  use layout <- result.try(
    watershed_beam.resolve_sequence_field(
      document,
      map,
      workspace.layout_field(),
    )
    |> require("workspace layout is missing"),
  )
  use connections <- result.try(
    watershed_beam.resolve_sequence_field(
      document,
      map,
      workspace.connections_field(),
    )
    |> require("workspace connections are missing"),
  )
  Ok(Workspace(document, map, manifest, layout, connections))
}

@target(erlang)
/// Read the effective workspace state.
pub fn read(
  store: Workspace(root),
  catalog: component.Catalog(context, running),
) -> workspace.Snapshot {
  workspace.snapshot(
    manifest: watershed_beam.entries(store.manifest),
    layout: watershed_beam.sequence_values(store.layout),
    connections: watershed_beam.sequence_values(store.connections),
    catalog: catalog,
  )
}

@target(erlang)
/// Prepare stored instances for the later runtime layer.
pub fn prepare(
  store: Workspace(root),
  catalog: component.Catalog(context, running),
) -> List(workspace.PreparationState(watershed_beam.SharedMap)) {
  workspace.prepare(read(store, catalog), catalog, fn(child_handle) {
    watershed_beam.resolve(store.document, child_handle)
  })
}

@target(erlang)
/// Add one instance and append it to the layout.
pub fn add_instance(
  store: Workspace(root),
  catalog: component.Catalog(context, running),
  instance_id: String,
  kind: String,
  version: Int,
  config: Json,
) -> Result(watershed_beam.SharedMap, WorkspaceError) {
  case
    string.is_empty(instance_id),
    watershed_beam.has(store.manifest, instance_id)
  {
    True, _ -> Error(InvalidInstanceId)
    _, True -> Error(DuplicateInstance(instance_id))
    False, False -> {
      use descriptor <- result.try(
        component.find(catalog, kind, version)
        |> result.map_error(UnsupportedComponent),
      )
      use _ <- result.try(
        component.validate_config(descriptor, config)
        |> result.map_error(InvalidComponentConfig),
      )
      use child <- result.try(
        watershed_beam.create_map(store.document)
        |> result.map_error(StorageError),
      )
      let entry =
        workspace.ManifestEntry(
          instance_id: instance_id,
          kind: kind,
          version: version,
          config: config,
          child_handle: watershed_beam.handle_of(child),
        )
      watershed_beam.set(
        store.manifest,
        instance_id,
        workspace.encode_manifest(entry),
      )
      use _ <- result.try(
        watershed_beam.sequence_insert(
          store.layout,
          watershed_beam.sequence_length(store.layout),
          json.string(instance_id),
        )
        |> result.map_error(StorageError),
      )
      Ok(child)
    }
  }
}

@target(erlang)
/// Move one instance to an effective layout index.
pub fn move_instance(
  store: Workspace(root),
  catalog: component.Catalog(context, running),
  instance_id: String,
  to_index: Int,
) -> Result(Nil, WorkspaceError) {
  case workspace.plan_move(read(store, catalog), instance_id, to_index) {
    Error(Nil) -> Error(InvalidMove(instance_id, to_index))
    Ok(workspace.Move(remove_indexes, from_index, target_index)) -> {
      use _ <- result.try(delete_indices(store.layout, remove_indexes))
      case from_index == target_index {
        True -> Ok(Nil)
        False ->
          watershed_beam.sequence_move(store.layout, from_index, target_index)
          |> result.map_error(StorageError)
      }
    }
  }
}

@target(erlang)
/// Validate and append one port connection.
pub fn add_connection(
  store: Workspace(root),
  catalog: component.Catalog(context, running),
  connection: port_graph.Connection,
) -> Result(Nil, WorkspaceError) {
  use _ <- result.try(
    workspace.validate_connection(read(store, catalog), connection, catalog)
    |> result.map_error(ConnectionRejected),
  )
  watershed_beam.sequence_insert(
    store.connections,
    watershed_beam.sequence_length(store.connections),
    workspace.encode_connection(connection),
  )
  |> result.map_error(StorageError)
}

@target(erlang)
/// Remove every stored occurrence of one connection ID.
pub fn remove_connection(
  store: Workspace(root),
  catalog: component.Catalog(context, running),
  connection_id: String,
) -> Result(Nil, WorkspaceError) {
  delete_indices(
    store.connections,
    workspace.connection_id_removal_indices(read(store, catalog), connection_id),
  )
}

@target(erlang)
/// Remove one instance from workspace reachability.
///
/// The attached child map remains readable through a handle retained before
/// this operation.
pub fn delete_instance(
  store: Workspace(root),
  catalog: component.Catalog(context, running),
  instance_id: String,
) -> Result(Nil, WorkspaceError) {
  let snapshot = read(store, catalog)
  use _ <- result.try(delete_indices(
    store.layout,
    workspace.layout_removal_indices(snapshot, instance_id),
  ))
  use _ <- result.try(delete_indices(
    store.connections,
    workspace.instance_connection_indices(snapshot, instance_id),
  ))
  watershed_beam.delete(store.manifest, instance_id)
  Ok(Nil)
}

@target(erlang)
fn create(
  document: watershed_beam.Document(root),
  root: watershed_beam.TypedMap(parent),
  field: ChildField(parent, workspace.WorkspaceSchema),
) -> Result(Workspace(root), WorkspaceError) {
  use raw_map <- result.try(
    watershed_beam.create_map(document)
    |> result.map_error(StorageError),
  )
  use manifest <- result.try(
    watershed_beam.create_map(document)
    |> result.map_error(StorageError),
  )
  use layout <- result.try(
    watershed_beam.create_sequence(document)
    |> result.map_error(StorageError),
  )
  use connections <- result.try(
    watershed_beam.create_sequence(document)
    |> result.map_error(StorageError),
  )
  let map: watershed_beam.TypedMap(workspace.WorkspaceSchema) =
    watershed_beam.typed(raw_map)
  watershed_beam.set_map_field(map, workspace.manifest_field(), manifest)
  watershed_beam.set_sequence_field(map, workspace.layout_field(), layout)
  watershed_beam.set_sequence_field(
    map,
    workspace.connections_field(),
    connections,
  )
  watershed_beam.set_child(root, field, map)
  Ok(Workspace(document, map, manifest, layout, connections))
}

@target(erlang)
fn require(
  value: Result(Option(a), String),
  missing: String,
) -> Result(a, WorkspaceError) {
  case value {
    Ok(Some(inner)) -> Ok(inner)
    Ok(None) -> Error(StorageError(missing))
    Error(reason) -> Error(StorageError(reason))
  }
}

@target(erlang)
fn delete_indices(
  sequence: watershed_beam.SharedSequence,
  indices: List(Int),
) -> Result(Nil, WorkspaceError) {
  list.try_fold(indices, Nil, fn(_, index) {
    watershed_beam.sequence_delete(sequence, index)
    |> result.map_error(StorageError)
  })
}
