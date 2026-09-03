import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should

import watershed
import watershed/component
import watershed/port_graph
import watershed/sluice_js
import watershed/transport_js
import watershed/workspace
import watershed/workspace_js

import project_room_lustre/catalog
import project_room_lustre/checklist
import project_room_lustre/document_schema
import project_room_lustre/workspace_setup

pub fn creation_presets_build_valid_configs_test() -> Nil {
  let presets = catalog.creation_presets()

  presets
  |> list.map(fn(preset) {
    let catalog.CreationPreset(kind:, ..) = preset
    kind
  })
  |> should.equal([catalog.checklist_kind, catalog.tally_kind])

  presets
  |> list.each(fn(preset) {
    let catalog.CreationPreset(kind:, version:, config:, ..) = preset
    let assert Ok(descriptor) = component.find(catalog.catalog(), kind, version)
    component.validate_config(descriptor, config("Runtime title"))
    |> should.equal(Ok(Nil))
  })
}

pub fn seeded_completion_edge_is_valid_test() -> Nil {
  let #(sluice, document) = document("palette-edge")
  let store = ensure_workspace(document)
  workspace_setup.seed(store) |> should.equal(Ok(Nil))
  sluice_js.settle(sluice)
  let snapshot = workspace_js.read(store, catalog.catalog())
  workspace.graph(snapshot)
  |> port_graph.connections
  |> list.map(fn(edge) { edge.id })
  |> list.contains(catalog.checklist_tally_connection_id)
  |> should.be_true
}

pub fn create_from_preset_trims_title_test() -> Nil {
  let #(_, document) = document("palette-create")
  let store = ensure_workspace(document)
  let assert Ok(preset) = catalog.find_creation_preset(catalog.checklist_kind)
  workspace_setup.create_from_preset(
    store,
    catalog.catalog(),
    preset,
    "runtime-checklist",
    "  Runtime title  ",
  )
  |> should.equal(Ok(Nil))

  let assert [entry] =
    workspace_js.read(store, catalog.catalog())
    |> workspace.manifest_entries
  json.to_string(entry.config)
  |> should.equal(
    json.to_string(
      checklist.encode_config(checklist.Config(title: "Runtime title")),
    ),
  )
}

pub fn create_from_preset_rejects_empty_title_first_test() -> Nil {
  let #(_, document) = document("palette-empty-title")
  let store = ensure_workspace(document)
  let assert Ok(preset) = catalog.find_creation_preset(catalog.checklist_kind)
  workspace_setup.create_from_preset(
    store,
    catalog.catalog(),
    preset,
    "",
    " \n ",
  )
  |> should.equal(Error(workspace_setup.InvalidTitle))
  workspace_js.read(store, catalog.catalog())
  |> workspace.manifest_entries
  |> should.equal([])
}

pub fn create_from_preset_wraps_workspace_errors_test() -> Nil {
  let #(_, document) = document("palette-create-error")
  let store = ensure_workspace(document)
  let assert Ok(preset) = catalog.find_creation_preset(catalog.checklist_kind)
  workspace_setup.create_from_preset(
    store,
    catalog.catalog(),
    preset,
    "runtime-checklist",
    "First",
  )
  |> should.equal(Ok(Nil))
  workspace_setup.create_from_preset(
    store,
    catalog.catalog(),
    preset,
    "runtime-checklist",
    "Second",
  )
  |> should.equal(
    Error(
      workspace_setup.WorkspaceMutation(workspace_js.DuplicateInstance(
        "runtime-checklist",
      )),
    ),
  )
}

fn document(
  name: String,
) -> #(sluice_js.Sluice, watershed.Document(document_schema.ProjectRoom)) {
  let sluice = sluice_js.start(tenant: "default", document: name)
  let document = sluice_js.connect(sluice, "user-a")
  sluice_js.settle(sluice)
  #(sluice, document)
}

fn ensure_workspace(
  document: watershed.Document(document_schema.ProjectRoom),
) -> workspace_js.Workspace(document_schema.ProjectRoom) {
  let opened = transport_js.new_cell(None)
  workspace_js.ensure(
    document,
    watershed.root_typed(document),
    document_schema.workspace(),
    fn(result) { transport_js.set_cell(opened, Some(result)) },
  )
  let assert Some(Ok(store)) = transport_js.get_cell(opened)
  store
}
