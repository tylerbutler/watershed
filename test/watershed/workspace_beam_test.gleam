@target(erlang)
import gleam/dynamic/decode
@target(erlang)
import gleam/json
@target(erlang)
import gleam/list
@target(erlang)
import gleam/option.{Some}
@target(erlang)
import startest/expect
@target(erlang)
import watershed/component
@target(erlang)
import watershed/port
@target(erlang)
import watershed/port_graph
@target(erlang)
import watershed/schema
@target(erlang)
import watershed/sluice
@target(erlang)
import watershed/workspace
@target(erlang)
import watershed/workspace_beam
@target(erlang)
import watershed_beam

@target(erlang)
type Root

@target(erlang)
fn workspace_field() -> schema.ChildField(Root, workspace.WorkspaceSchema) {
  schema.child_field("workspace")
}

@target(erlang)
fn descriptor(
  kind: String,
  output_id: String,
  input_id: String,
) -> component.Descriptor(Nil, Nil) {
  component.descriptor(
    kind: kind,
    version: 1,
    config_decoder: decode.success(Nil),
    start: fn(_, _) { Ok(Nil) },
    ports: [
      port.output_descriptor(port.output(output_id, "item@1", json.string)),
      port.input_descriptor(port.local_input(input_id, "item@1", decode.string)),
    ],
  )
}

@target(erlang)
fn catalog() -> component.Catalog(Nil, Nil) {
  let assert Ok(with_tasks) =
    component.register(
      component.new_catalog(),
      descriptor("tasks", "selected", "select"),
    )
  let assert Ok(catalog) =
    component.register(with_tasks, descriptor("notes", "focused", "focus"))
  catalog
}

@target(erlang)
fn start(name: String) -> sluice.Sluice {
  let assert Ok(sluice) = sluice.start(tenant: "default", document: name)
  sluice
}

@target(erlang)
fn connect(
  sluice: sluice.Sluice,
  user: String,
) -> watershed_beam.Document(Root) {
  let assert Ok(document) = sluice.connect(sluice, user)
  document
}

@target(erlang)
pub fn cold_bootstrap_race_reopens_one_winning_workspace_test() -> Nil {
  let sluice = start("workspace-beam-cold-race")
  let document_a = connect(sluice, "user-a")
  let document_b = connect(sluice, "user-b")
  sluice.settle(sluice)

  let assert Ok(_) =
    workspace_beam.ensure(
      document_a,
      watershed_beam.root_typed(document_a),
      workspace_field(),
    )
  let assert Ok(_) =
    workspace_beam.ensure(
      document_b,
      watershed_beam.root_typed(document_b),
      workspace_field(),
    )
  sluice.settle(sluice)

  watershed_beam.get(watershed_beam.root(document_a), "workspace")
  |> expect.to_equal(watershed_beam.get(
    watershed_beam.root(document_b),
    "workspace",
  ))
  let assert Ok(winner_a) =
    workspace_beam.resolve(
      document_a,
      watershed_beam.root_typed(document_a),
      workspace_field(),
    )
  let assert Ok(winner_b) =
    workspace_beam.resolve(
      document_b,
      watershed_beam.root_typed(document_b),
      workspace_field(),
    )
  let assert Ok(_) =
    workspace_beam.add_instance(
      winner_a,
      catalog(),
      "tasks-1",
      "tasks",
      1,
      json.null(),
    )
  sluice.settle(sluice)
  workspace.layout(workspace_beam.read(winner_b, catalog()))
  |> expect.to_equal(["tasks-1"])
}

// docs:snippet-start foundations-workspaces-preservation-test
@target(erlang)
pub fn workspace_lifecycle_converges_and_preserves_deleted_data_test() -> Nil {
  let sluice = start("workspace-beam-lifecycle")
  let document_a = connect(sluice, "user-a")
  sluice.settle(sluice)
  let assert Ok(store_a) =
    workspace_beam.ensure(
      document_a,
      watershed_beam.root_typed(document_a),
      workspace_field(),
    )
  sluice.settle(sluice)

  let assert Ok(tasks_child) =
    workspace_beam.add_instance(
      store_a,
      catalog(),
      "tasks-1",
      "tasks",
      1,
      json.null(),
    )
  let assert Ok(_) =
    workspace_beam.add_instance(
      store_a,
      catalog(),
      "notes-1",
      "notes",
      1,
      json.null(),
    )
  watershed_beam.set(tasks_child, "kept", json.string("yes"))
  let edge =
    port_graph.connection(
      "tasks-notes",
      port_graph.PortRef("tasks-1", "selected"),
      port_graph.PortRef("notes-1", "focus"),
    )
  workspace_beam.add_connection(store_a, catalog(), edge)
  |> expect.to_equal(Ok(Nil))
  sluice.settle(sluice)

  let document_b = connect(sluice, "user-b")
  sluice.settle(sluice)
  let assert Ok(store_b) =
    workspace_beam.resolve(
      document_b,
      watershed_beam.root_typed(document_b),
      workspace_field(),
    )
  workspace.layout(workspace_beam.read(store_b, catalog()))
  |> expect.to_equal(["tasks-1", "notes-1"])

  workspace_beam.move_instance(store_a, catalog(), "notes-1", 0)
  |> expect.to_equal(Ok(Nil))
  sluice.settle(sluice)
  workspace.layout(workspace_beam.read(store_b, catalog()))
  |> expect.to_equal(["notes-1", "tasks-1"])

  let child_handle = watershed_beam.handle_of(tasks_child)
  workspace_beam.delete_instance(store_a, catalog(), "tasks-1")
  |> expect.to_equal(Ok(Nil))
  workspace_beam.delete_instance(store_a, catalog(), "tasks-1")
  |> expect.to_equal(Ok(Nil))
  sluice.settle(sluice)

  let snapshot_b = workspace_beam.read(store_b, catalog())
  workspace.layout(snapshot_b) |> expect.to_equal(["notes-1"])
  port_graph.connections(workspace.graph(snapshot_b))
  |> expect.to_equal([])
  let assert Ok(preserved) = watershed_beam.resolve(document_b, child_handle)
  watershed_beam.get(preserved, "kept")
  |> expect.to_equal(Ok(json.string("yes")))
}

// docs:snippet-end foundations-workspaces-preservation-test

@target(erlang)
pub fn concurrent_cycle_keeps_raw_edges_and_one_effective_edge_test() -> Nil {
  let sluice = start("workspace-beam-cycle")
  let document_a = connect(sluice, "user-a")
  sluice.settle(sluice)
  let assert Ok(store_a) =
    workspace_beam.ensure(
      document_a,
      watershed_beam.root_typed(document_a),
      workspace_field(),
    )
  sluice.settle(sluice)
  let document_b = connect(sluice, "user-b")
  sluice.settle(sluice)
  let assert Ok(store_b) =
    workspace_beam.resolve(
      document_b,
      watershed_beam.root_typed(document_b),
      workspace_field(),
    )

  let assert Ok(_) =
    workspace_beam.add_instance(
      store_a,
      catalog(),
      "tasks-1",
      "tasks",
      1,
      json.null(),
    )
  let assert Ok(_) =
    workspace_beam.add_instance(
      store_a,
      catalog(),
      "notes-1",
      "notes",
      1,
      json.null(),
    )
  sluice.settle(sluice)

  let forward =
    port_graph.connection(
      "a-forward",
      port_graph.PortRef("tasks-1", "selected"),
      port_graph.PortRef("notes-1", "focus"),
    )
  let reverse =
    port_graph.connection(
      "b-reverse",
      port_graph.PortRef("notes-1", "focused"),
      port_graph.PortRef("tasks-1", "select"),
    )
  workspace_beam.add_connection(store_a, catalog(), forward)
  |> expect.to_equal(Ok(Nil))
  workspace_beam.add_connection(store_b, catalog(), reverse)
  |> expect.to_equal(Ok(Nil))
  sluice.settle(sluice)

  let snapshot_a = workspace_beam.read(store_a, catalog())
  let snapshot_b = workspace_beam.read(store_b, catalog())
  workspace.raw_connections(snapshot_a) |> list.length |> expect.to_equal(2)
  port_graph.connections(workspace.graph(snapshot_a))
  |> list.map(fn(connection) { connection.id })
  |> expect.to_equal(["a-forward"])
  port_graph.connections(workspace.graph(snapshot_b))
  |> list.map(fn(connection) { connection.id })
  |> expect.to_equal(["a-forward"])
  workspace.diagnostics(snapshot_a)
  |> list.any(fn(diagnostic) {
    diagnostic == workspace.InvalidGraph(port_graph.Cycle("b-reverse"))
  })
  |> expect.to_be_true()
}

@target(erlang)
pub fn delete_cleans_references_when_manifest_is_already_missing_test() -> Nil {
  let sluice = start("workspace-beam-delete-retry")
  let document = connect(sluice, "user-a")
  sluice.settle(sluice)
  let assert Ok(store) =
    workspace_beam.ensure(
      document,
      watershed_beam.root_typed(document),
      workspace_field(),
    )
  let assert Ok(_) =
    workspace_beam.add_instance(
      store,
      catalog(),
      "tasks-1",
      "tasks",
      1,
      json.null(),
    )
  sluice.settle(sluice)

  // A first attempt can remove the manifest before it finishes cleanup.
  let root = watershed_beam.root_typed(document)
  let assert Ok(Some(workspace_map)) =
    watershed_beam.resolve_child(document, root, workspace_field())
  let assert Ok(Some(manifest)) =
    watershed_beam.resolve_map_field(
      document,
      workspace_map,
      workspace.manifest_field(),
    )
  watershed_beam.delete(manifest, "tasks-1")

  workspace_beam.delete_instance(store, catalog(), "tasks-1")
  |> expect.to_equal(Ok(Nil))
  workspace.layout(workspace_beam.read(store, catalog()))
  |> expect.to_equal([])
}

@target(erlang)
pub fn move_collapses_stale_layout_copy_test() -> Nil {
  let sluice = start("workspace-beam-move-duplicate")
  let document = connect(sluice, "user-a")
  sluice.settle(sluice)
  let assert Ok(store) =
    workspace_beam.ensure(
      document,
      watershed_beam.root_typed(document),
      workspace_field(),
    )
  let assert Ok(_) =
    workspace_beam.add_instance(
      store,
      catalog(),
      "tasks-1",
      "tasks",
      1,
      json.null(),
    )
  let assert Ok(_) =
    workspace_beam.add_instance(
      store,
      catalog(),
      "notes-1",
      "notes",
      1,
      json.null(),
    )
  let assert Ok(_) =
    workspace_beam.add_instance(
      store,
      catalog(),
      "tasks-2",
      "tasks",
      1,
      json.null(),
    )
  let assert Ok(Some(map)) =
    watershed_beam.resolve_child(
      document,
      watershed_beam.root_typed(document),
      workspace_field(),
    )
  let assert Ok(Some(layout)) =
    watershed_beam.resolve_sequence_field(
      document,
      map,
      workspace.layout_field(),
    )
  let assert Ok(Nil) =
    watershed_beam.sequence_insert(layout, 2, json.string("tasks-1"))

  workspace_beam.move_instance(store, catalog(), "tasks-1", 2)
  |> expect.to_equal(Ok(Nil))
  workspace.layout(workspace_beam.read(store, catalog()))
  |> expect.to_equal(["notes-1", "tasks-2", "tasks-1"])
}
