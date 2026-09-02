//// JavaScript persistence adapter for a component workspace.
////
//// The adapter stores one workspace child map with a manifest map, a layout
//// sequence, and a connection sequence. It does not start components.

@target(javascript)
import gleam/json.{type Json}
@target(javascript)
import gleam/list
@target(javascript)
import gleam/option.{type Option, None, Some}
@target(javascript)
import gleam/result
@target(javascript)
import gleam/string
@target(javascript)
import watershed
@target(javascript)
import watershed/component
@target(javascript)
import watershed/port_graph
@target(javascript)
import watershed/schema.{type ChildField, child_key}
@target(javascript)
import watershed/workspace

@target(javascript)
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

@target(javascript)
/// The resolved channels of one workspace.
pub opaque type Workspace(root) {
  Workspace(
    document: watershed.Document(root),
    map: watershed.TypedMap(workspace.WorkspaceSchema),
    manifest: watershed.SharedMap,
    layout: watershed.SharedSequence,
    connections: watershed.SharedSequence,
  )
}

@target(javascript)
/// Adopt an existing workspace or create a complete workspace subtree.
///
/// When the workspace child is absent, the function builds the whole
/// subtree — the workspace map, the manifest map, and the layout and
/// connection sequences — while every channel is still detached, and then
/// attaches all of it with the one write that stores the workspace child on
/// `root`. Recursive handle discovery attaches the nested channels together
/// with the workspace map, so there is no window with a partially attached
/// topology, and this path never waits on a timer.
///
/// When the workspace child is already present, the function adopts it. It
/// resolves the child through the existing, retrying `ensure_child`, because
/// a handle that a remote peer just wrote can still be mid-attach, and then
/// it resolves the three channels directly: a workspace that this function
/// created always carries all three together.
///
/// A cold-start race has the same semantics as before: two callers can
/// converge on one root handle, but a later remote write to the root field
/// can still replace the handle that an earlier caller received.
pub fn ensure(
  document: watershed.Document(root),
  root: watershed.TypedMap(parent),
  field: ChildField(parent, workspace.WorkspaceSchema),
  done: fn(Result(Workspace(root), WorkspaceError)) -> Nil,
) -> Nil {
  case watershed.has(watershed.untyped(root), child_key(field)) {
    False -> done(create(document, root, field))
    True ->
      watershed.ensure_child(document, root, field, fn(result) {
        case result {
          Error(reason) -> done(Error(StorageError(reason)))
          Ok(map) -> done(open(document, map))
        }
      })
  }
}

@target(javascript)
/// Build a complete, detached workspace subtree and attach it in one write.
fn create(
  document: watershed.Document(root),
  root: watershed.TypedMap(parent),
  field: ChildField(parent, workspace.WorkspaceSchema),
) -> Result(Workspace(root), WorkspaceError) {
  use raw_map <- result.try(
    watershed.create_map(document) |> result.map_error(StorageError),
  )
  let map = watershed.typed(raw_map)
  use manifest <- result.try(
    watershed.create_map(document) |> result.map_error(StorageError),
  )
  use layout <- result.try(
    watershed.create_sequence(document) |> result.map_error(StorageError),
  )
  use connections <- result.try(
    watershed.create_sequence(document) |> result.map_error(StorageError),
  )
  watershed.set_map_field(map, workspace.manifest_field(), manifest)
  watershed.set_sequence_field(map, workspace.layout_field(), layout)
  watershed.set_sequence_field(map, workspace.connections_field(), connections)
  watershed.set_child(root, field, map)
  Ok(Workspace(document, map, manifest, layout, connections))
}

@target(javascript)
/// Resolve the manifest map and the layout and connection sequences that an
/// already-resolved workspace child carries.
fn open(
  document: watershed.Document(root),
  map: watershed.TypedMap(workspace.WorkspaceSchema),
) -> Result(Workspace(root), WorkspaceError) {
  use manifest <- result.try(
    watershed.resolve_map_field(document, map, workspace.manifest_field())
    |> require("workspace manifest is missing"),
  )
  use layout <- result.try(
    watershed.resolve_sequence_field(document, map, workspace.layout_field())
    |> require("workspace layout is missing"),
  )
  use connections <- result.try(
    watershed.resolve_sequence_field(
      document,
      map,
      workspace.connections_field(),
    )
    |> require("workspace connections are missing"),
  )
  Ok(Workspace(document, map, manifest, layout, connections))
}

@target(javascript)
/// Resolve an existing workspace without changing it.
pub fn resolve(
  document: watershed.Document(root),
  root: watershed.TypedMap(parent),
  field: ChildField(parent, workspace.WorkspaceSchema),
) -> Result(Workspace(root), WorkspaceError) {
  use map <- result.try(
    watershed.resolve_child(document, root, field)
    |> require("workspace child is missing"),
  )
  open(document, map)
}

@target(javascript)
/// Read the effective workspace state.
pub fn read(
  store: Workspace(root),
  catalog: component.Catalog(context, running),
) -> workspace.Snapshot {
  workspace.snapshot(
    manifest: watershed.entries(store.manifest),
    layout: watershed.sequence_values(store.layout),
    connections: watershed.sequence_values(store.connections),
    catalog: catalog,
  )
}

@target(javascript)
/// Prepare stored instances for the later runtime layer.
pub fn prepare(
  store: Workspace(root),
  catalog: component.Catalog(context, running),
) -> List(workspace.PreparationState(watershed.SharedMap)) {
  workspace.prepare(read(store, catalog), catalog, fn(child_handle) {
    watershed.resolve(store.document, child_handle)
  })
}

@target(javascript)
/// Add one instance and append it to the layout.
pub fn add_instance(
  store: Workspace(root),
  catalog: component.Catalog(context, running),
  instance_id: String,
  kind: String,
  version: Int,
  config: Json,
) -> Result(watershed.SharedMap, WorkspaceError) {
  case
    string.is_empty(instance_id),
    watershed.has(store.manifest, instance_id)
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
        watershed.create_map(store.document)
        |> result.map_error(StorageError),
      )
      let entry =
        workspace.ManifestEntry(
          instance_id: instance_id,
          kind: kind,
          version: version,
          config: config,
          child_handle: watershed.handle_of(child),
        )
      watershed.set(
        store.manifest,
        instance_id,
        workspace.encode_manifest(entry),
      )
      use _ <- result.try(
        watershed.sequence_insert(
          store.layout,
          watershed.sequence_length(store.layout),
          json.string(instance_id),
        )
        |> result.map_error(StorageError),
      )
      Ok(child)
    }
  }
}

@target(javascript)
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
          watershed.sequence_move(store.layout, from_index, target_index)
          |> result.map_error(StorageError)
      }
    }
  }
}

@target(javascript)
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
  watershed.sequence_insert(
    store.connections,
    watershed.sequence_length(store.connections),
    workspace.encode_connection(connection),
  )
  |> result.map_error(StorageError)
}

@target(javascript)
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

@target(javascript)
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
  watershed.delete(store.manifest, instance_id)
  Ok(Nil)
}

@target(javascript)
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

@target(javascript)
fn delete_indices(
  sequence: watershed.SharedSequence,
  indices: List(Int),
) -> Result(Nil, WorkspaceError) {
  list.try_fold(indices, Nil, fn(_, index) {
    watershed.sequence_delete(sequence, index)
    |> result.map_error(StorageError)
  })
}
