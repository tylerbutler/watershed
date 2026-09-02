//// JavaScript workspace persistence adapter tests.
////
//// `ensure`'s creation path builds the whole workspace subtree while every
//// channel is detached and attaches it with one write, so it settles
//// synchronously and every test can call it directly to seed a workspace.
//// Adopting a workspace that a remote peer created can still retry on a real
//// timer while that peer's write is mid-attach, so these tests only exercise
//// that path once, against a workspace that has already settled, where the
//// resolve succeeds on the first attempt and the callback fires before the
//// test function returns. `startest` runs each test function synchronously,
//// so a path that can genuinely wait on a timer would not be observable
//// here.

@target(javascript)
import gleam/dynamic/decode
@target(javascript)
import gleam/json
@target(javascript)
import gleam/list
@target(javascript)
import gleam/option.{None, Some}
@target(javascript)
import startest/expect

@target(javascript)
import watershed
@target(javascript)
import watershed/component
@target(javascript)
import watershed/port
@target(javascript)
import watershed/port_graph
@target(javascript)
import watershed/schema
@target(javascript)
import watershed/sluice_js
@target(javascript)
import watershed/transport_js
@target(javascript)
import watershed/workspace
@target(javascript)
import watershed/workspace_js

@target(javascript)
type Root

@target(javascript)
fn workspace_field() -> schema.ChildField(Root, workspace.WorkspaceSchema) {
  schema.child_field("workspace")
}

@target(javascript)
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

@target(javascript)
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

@target(javascript)
fn start(name: String) -> sluice_js.Sluice {
  sluice_js.start(tenant: "default", document: name)
}

@target(javascript)
fn connect(sluice: sluice_js.Sluice, user: String) -> watershed.Document(Root) {
  sluice_js.connect(sluice, user_id: user)
}

@target(javascript)
/// Bootstrap a fresh workspace on `document`'s root through `ensure`.
///
/// `ensure`'s creation path builds the whole subtree while every channel is
/// detached and attaches it with one write, so it never waits on a timer and
/// its callback fires before this function returns.
fn seed(document: watershed.Document(Root)) -> workspace_js.Workspace(Root) {
  let outcome = transport_js.new_cell(None)
  workspace_js.ensure(
    document,
    watershed.root_typed(document),
    workspace_field(),
    fn(result) { transport_js.set_cell(outcome, Some(result)) },
  )
  let assert Some(Ok(store)) = transport_js.get_cell(outcome)
  store
}

@target(javascript)
fn workspace_map(
  document: watershed.Document(Root),
) -> watershed.TypedMap(workspace.WorkspaceSchema) {
  let assert Ok(Some(map)) =
    watershed.resolve_child(
      document,
      watershed.root_typed(document),
      workspace_field(),
    )
  map
}

@target(javascript)
fn raw_manifest(document: watershed.Document(Root)) -> watershed.SharedMap {
  let assert Ok(Some(manifest)) =
    watershed.resolve_map_field(
      document,
      workspace_map(document),
      workspace.manifest_field(),
    )
  manifest
}

@target(javascript)
fn raw_layout(document: watershed.Document(Root)) -> watershed.SharedSequence {
  let assert Ok(Some(layout)) =
    watershed.resolve_sequence_field(
      document,
      workspace_map(document),
      workspace.layout_field(),
    )
  layout
}

@target(javascript)
pub fn cold_bootstrap_race_reopens_one_winning_workspace_test() -> Nil {
  let sluice = start("workspace-js-cold-race")
  let document_a = connect(sluice, "user-a")
  let document_b = connect(sluice, "user-b")
  sluice_js.settle(sluice)

  let _store_a = seed(document_a)
  let _store_b = seed(document_b)
  sluice_js.settle(sluice)

  watershed.get(watershed.root(document_a), "workspace")
  |> expect.to_equal(watershed.get(watershed.root(document_b), "workspace"))
  let assert Ok(winner_a) =
    workspace_js.resolve(
      document_a,
      watershed.root_typed(document_a),
      workspace_field(),
    )
  let assert Ok(winner_b) =
    workspace_js.resolve(
      document_b,
      watershed.root_typed(document_b),
      workspace_field(),
    )
  let assert Ok(_) =
    workspace_js.add_instance(
      winner_a,
      catalog(),
      "tasks-1",
      "tasks",
      1,
      json.null(),
    )
  sluice_js.settle(sluice)
  workspace.layout(workspace_js.read(winner_b, catalog()))
  |> expect.to_equal(["tasks-1"])
}

@target(javascript)
pub fn ensure_creates_a_complete_workspace_topology_synchronously_test() -> Nil {
  let sluice = start("workspace-js-ensure-create")
  let document = connect(sluice, "user-a")
  sluice_js.settle(sluice)

  let outcome = transport_js.new_cell(None)
  workspace_js.ensure(
    document,
    watershed.root_typed(document),
    workspace_field(),
    fn(result) { transport_js.set_cell(outcome, Some(result)) },
  )

  // The whole subtree is built while detached and attached with one write,
  // so `done` runs before this line does, with no timer in between.
  let assert Some(Ok(store)) = transport_js.get_cell(outcome)
  workspace.layout(workspace_js.read(store, catalog())) |> expect.to_equal([])

  // Exactly one child exists at the root, and it resolves the workspace map
  // together with all three of its channels.
  watershed.keys(watershed.root(document)) |> expect.to_equal(["workspace"])
  let assert Ok(_) =
    workspace_js.resolve(
      document,
      watershed.root_typed(document),
      workspace_field(),
    )
  Nil
}

@target(javascript)
pub fn ensure_adopts_an_existing_workspace_synchronously_test() -> Nil {
  let sluice = start("workspace-js-ensure-adopt")
  let document_a = connect(sluice, "user-a")
  sluice_js.settle(sluice)
  let store_a = seed(document_a)
  let assert Ok(_) =
    workspace_js.add_instance(
      store_a,
      catalog(),
      "tasks-1",
      "tasks",
      1,
      json.null(),
    )
  sluice_js.settle(sluice)

  let document_b = connect(sluice, "user-b")
  sluice_js.settle(sluice)

  let outcome = transport_js.new_cell(None)
  workspace_js.ensure(
    document_b,
    watershed.root_typed(document_b),
    workspace_field(),
    fn(result) { transport_js.set_cell(outcome, Some(result)) },
  )

  // The workspace child and its three channels already exist and are
  // attached, so every step above resolves through the fast, timer-free path
  // and `done` runs before this line does.
  let assert Some(Ok(store_b)) = transport_js.get_cell(outcome)
  workspace.layout(workspace_js.read(store_b, catalog()))
  |> expect.to_equal(["tasks-1"])
}

@target(javascript)
pub fn workspace_lifecycle_converges_and_preserves_deleted_data_test() -> Nil {
  let sluice = start("workspace-js-lifecycle")
  let document_a = connect(sluice, "user-a")
  sluice_js.settle(sluice)
  let store_a = seed(document_a)
  sluice_js.settle(sluice)

  let assert Ok(tasks_child) =
    workspace_js.add_instance(
      store_a,
      catalog(),
      "tasks-1",
      "tasks",
      1,
      json.null(),
    )
  let assert Ok(_) =
    workspace_js.add_instance(
      store_a,
      catalog(),
      "notes-1",
      "notes",
      1,
      json.null(),
    )
  watershed.set(tasks_child, "kept", json.string("yes"))
  let edge =
    port_graph.connection(
      "tasks-notes",
      port_graph.PortRef("tasks-1", "selected"),
      port_graph.PortRef("notes-1", "focus"),
    )
  workspace_js.add_connection(store_a, catalog(), edge)
  |> expect.to_equal(Ok(Nil))
  sluice_js.settle(sluice)

  let document_b = connect(sluice, "user-b")
  sluice_js.settle(sluice)
  let assert Ok(store_b) =
    workspace_js.resolve(
      document_b,
      watershed.root_typed(document_b),
      workspace_field(),
    )
  workspace.layout(workspace_js.read(store_b, catalog()))
  |> expect.to_equal(["tasks-1", "notes-1"])

  workspace_js.move_instance(store_a, catalog(), "notes-1", 0)
  |> expect.to_equal(Ok(Nil))
  sluice_js.settle(sluice)
  workspace.layout(workspace_js.read(store_b, catalog()))
  |> expect.to_equal(["notes-1", "tasks-1"])

  let child_handle = watershed.handle_of(tasks_child)
  workspace_js.delete_instance(store_a, catalog(), "tasks-1")
  |> expect.to_equal(Ok(Nil))
  // Deletion is idempotent: repeating it must not fail or double-delete.
  workspace_js.delete_instance(store_a, catalog(), "tasks-1")
  |> expect.to_equal(Ok(Nil))
  sluice_js.settle(sluice)

  let snapshot_b = workspace_js.read(store_b, catalog())
  workspace.layout(snapshot_b) |> expect.to_equal(["notes-1"])
  port_graph.connections(workspace.graph(snapshot_b))
  |> expect.to_equal([])
  let assert Ok(preserved) = watershed.resolve(document_b, child_handle)
  watershed.get(preserved, "kept")
  |> expect.to_equal(Ok(json.string("yes")))
}

@target(javascript)
pub fn concurrent_cycle_keeps_raw_edges_and_one_effective_edge_test() -> Nil {
  let sluice = start("workspace-js-cycle")
  let document_a = connect(sluice, "user-a")
  sluice_js.settle(sluice)
  let store_a = seed(document_a)
  sluice_js.settle(sluice)
  let document_b = connect(sluice, "user-b")
  sluice_js.settle(sluice)
  let assert Ok(store_b) =
    workspace_js.resolve(
      document_b,
      watershed.root_typed(document_b),
      workspace_field(),
    )

  let assert Ok(_) =
    workspace_js.add_instance(
      store_a,
      catalog(),
      "tasks-1",
      "tasks",
      1,
      json.null(),
    )
  let assert Ok(_) =
    workspace_js.add_instance(
      store_a,
      catalog(),
      "notes-1",
      "notes",
      1,
      json.null(),
    )
  sluice_js.settle(sluice)

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
  workspace_js.add_connection(store_a, catalog(), forward)
  |> expect.to_equal(Ok(Nil))
  workspace_js.add_connection(store_b, catalog(), reverse)
  |> expect.to_equal(Ok(Nil))
  sluice_js.settle(sluice)

  let snapshot_a = workspace_js.read(store_a, catalog())
  let snapshot_b = workspace_js.read(store_b, catalog())
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

@target(javascript)
pub fn delete_removes_duplicate_layout_entries_and_incident_edges_test() -> Nil {
  let sluice = start("workspace-js-duplicate-cleanup")
  let document = connect(sluice, "user-a")
  sluice_js.settle(sluice)
  let store = seed(document)

  let assert Ok(_) =
    workspace_js.add_instance(
      store,
      catalog(),
      "tasks-1",
      "tasks",
      1,
      json.null(),
    )
  let assert Ok(_) =
    workspace_js.add_instance(
      store,
      catalog(),
      "notes-1",
      "notes",
      1,
      json.null(),
    )

  // A stray write duplicates the layout reference to "tasks-1"; deletion must
  // remove every occurrence, not just the effective one.
  let layout = raw_layout(document)
  watershed.sequence_insert(
    layout,
    watershed.sequence_length(layout),
    json.string("tasks-1"),
  )
  |> expect.to_equal(Ok(Nil))

  let edge =
    port_graph.connection(
      "tasks-notes",
      port_graph.PortRef("tasks-1", "selected"),
      port_graph.PortRef("notes-1", "focus"),
    )
  workspace_js.add_connection(store, catalog(), edge)
  |> expect.to_equal(Ok(Nil))

  workspace_js.delete_instance(store, catalog(), "tasks-1")
  |> expect.to_equal(Ok(Nil))

  let snapshot = workspace_js.read(store, catalog())
  workspace.layout(snapshot) |> expect.to_equal(["notes-1"])
  watershed.sequence_values(layout)
  |> expect.to_equal([json.string("notes-1")])
  port_graph.connections(workspace.graph(snapshot))
  |> expect.to_equal([])
}

@target(javascript)
pub fn delete_cleans_references_when_manifest_is_already_missing_test() -> Nil {
  let sluice = start("workspace-js-delete-retry")
  let document = connect(sluice, "user-a")
  sluice_js.settle(sluice)
  let store = seed(document)
  let assert Ok(_) =
    workspace_js.add_instance(
      store,
      catalog(),
      "tasks-1",
      "tasks",
      1,
      json.null(),
    )
  sluice_js.settle(sluice)

  // A first attempt can remove the manifest before it finishes cleanup.
  watershed.delete(raw_manifest(document), "tasks-1")

  workspace_js.delete_instance(store, catalog(), "tasks-1")
  |> expect.to_equal(Ok(Nil))
  workspace.layout(workspace_js.read(store, catalog()))
  |> expect.to_equal([])
}

@target(javascript)
pub fn move_collapses_stale_layout_copy_test() -> Nil {
  let sluice = start("workspace-js-move-duplicate")
  let document = connect(sluice, "user-a")
  sluice_js.settle(sluice)
  let store = seed(document)
  let assert Ok(_) =
    workspace_js.add_instance(
      store,
      catalog(),
      "tasks-1",
      "tasks",
      1,
      json.null(),
    )
  let assert Ok(_) =
    workspace_js.add_instance(
      store,
      catalog(),
      "notes-1",
      "notes",
      1,
      json.null(),
    )
  let assert Ok(_) =
    workspace_js.add_instance(
      store,
      catalog(),
      "tasks-2",
      "tasks",
      1,
      json.null(),
    )
  let layout = raw_layout(document)
  let assert Ok(Nil) =
    watershed.sequence_insert(layout, 2, json.string("tasks-1"))

  workspace_js.move_instance(store, catalog(), "tasks-1", 2)
  |> expect.to_equal(Ok(Nil))
  workspace.layout(workspace_js.read(store, catalog()))
  |> expect.to_equal(["notes-1", "tasks-2", "tasks-1"])
}
