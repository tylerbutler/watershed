//// Fixed persisted composition for the project room example.

import gleam/json.{type Json}
import gleam/list
import gleam/result

import watershed
import watershed/component
import watershed/port_graph
import watershed/workspace
import watershed/workspace_js

import project_room_lustre/activity
import project_room_lustre/catalog
import project_room_lustre/document_schema
import project_room_lustre/notes
import project_room_lustre/task_collection

/// Add the three fixed instances and two connections that are not present.
///
/// The function reads before each write, so it is safe to call after a partial
/// attempt. Concurrent cold clients can still create competing child maps;
/// workspace and component runtime reconciliation select and reopen the
/// winning handles.
pub fn seed(
  store: workspace_js.Workspace(document_schema.ProjectRoom),
) -> Result(Nil, workspace_js.WorkspaceError) {
  let room_catalog = catalog.catalog()
  use _ <- result.try(ensure_instance(
    store,
    room_catalog,
    catalog.task_collection_instance_id,
    catalog.task_collection_kind,
    catalog.task_collection_version,
    catalog.task_collection_config_json(),
    task_collection.initialize,
  ))
  use _ <- result.try(ensure_instance(
    store,
    room_catalog,
    catalog.notes_instance_id,
    catalog.notes_kind,
    catalog.notes_version,
    catalog.notes_config_json(),
    notes.initialize,
  ))
  use _ <- result.try(ensure_instance(
    store,
    room_catalog,
    catalog.activity_instance_id,
    catalog.activity_kind,
    catalog.activity_version,
    catalog.activity_config_json(),
    activity.initialize,
  ))
  list.try_fold(catalog.persisted_connections(), Nil, fn(_, connection) {
    ensure_connection(store, room_catalog, connection)
  })
}

fn ensure_instance(
  store: workspace_js.Workspace(document_schema.ProjectRoom),
  room_catalog: component.Catalog(
    catalog.Context(document_schema.ProjectRoom),
    catalog.Running,
  ),
  instance_id: String,
  kind: String,
  version: Int,
  config: Json,
  initialize: fn(
    watershed.Document(document_schema.ProjectRoom),
    watershed.SharedMap,
  ) -> Result(Nil, String),
) -> Result(Nil, workspace_js.WorkspaceError) {
  let exists =
    workspace_js.read(store, room_catalog)
    |> workspace.manifest_entries
    |> list.any(fn(entry) { entry.instance_id == instance_id })
  case exists {
    True -> Ok(Nil)
    False ->
      workspace_js.add_instance_with(
        store,
        room_catalog,
        instance_id,
        kind,
        version,
        config,
        initialize,
      )
      |> result.map(fn(_) { Nil })
  }
}

fn ensure_connection(
  store: workspace_js.Workspace(document_schema.ProjectRoom),
  room_catalog: component.Catalog(
    catalog.Context(document_schema.ProjectRoom),
    catalog.Running,
  ),
  connection: port_graph.Connection,
) -> Result(Nil, workspace_js.WorkspaceError) {
  let exists =
    workspace_js.read(store, room_catalog)
    |> workspace.raw_connections
    |> list.any(fn(raw) {
      case workspace.decode_connection(raw) {
        Ok(found) -> found.id == connection.id
        Error(_) -> False
      }
    })
  case exists {
    True -> Ok(Nil)
    False -> workspace_js.add_connection(store, room_catalog, connection)
  }
}
