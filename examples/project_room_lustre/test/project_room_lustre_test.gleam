import gleam/json
import gleam/option.{None, Some}
import gleam/string
import gleeunit
import gleeunit/should
import lustre/element

import watershed
import watershed/component
import watershed/component_runtime_js
import watershed/sluice_js
import watershed/transport_js
import watershed/workspace

import project_room_lustre as app
import project_room_lustre/catalog
import project_room_lustre/checklist
import project_room_lustre/tally
import project_room_lustre/views
import project_room_lustre/workspace_setup

type Root

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn palette_and_dynamic_views_construct_test() -> Nil {
  let _palette =
    views.palette("", catalog.creation_presets(), False, fn(_) { Nil }, fn(_) {
      Nil
    })
  let #(document, checklist_tree, tally_tree) = component_trees()
  let checklist = start_checklist(document, checklist_tree)
  let tally = start_tally(document, tally_tree)
  let _checklist_view =
    views.checklist(
      "checklist-test",
      checklist,
      fn(_) { Nil },
      Nil,
      fn(_, _) { Nil },
      fn(_) { Nil },
      fn(_) { Nil },
      fn(_) { Nil },
    )
  let _tally_view = views.tally("tally-test", tally, fn(_) { Nil })
  Nil
}

pub fn successful_command_clears_only_the_matching_instance_error_test() -> Nil {
  let errors =
    app.new_instance_errors()
    |> app.record_instance_command(
      "checklist-a",
      Error(component_runtime_js.ActionFailed("checklist-a", "empty label")),
    )
    |> app.record_instance_command(
      "tally-b",
      Error(component_runtime_js.ActionFailed("tally-b", "zero delta")),
    )
    |> app.record_instance_command("checklist-a", Ok(Nil))

  app.instance_error(errors, "checklist-a") |> should.equal(None)
  let assert Some(error) = app.instance_error(errors, "tally-b")
  {
    string.contains(error, "action failed:")
    && string.contains(error, "zero delta")
  }
  |> should.be_true
}

pub fn instance_error_view_has_a_stable_instance_selector_test() -> Nil {
  let rendered =
    views.instance_error("checklist-a", "action failed: empty label")
    |> element.to_string

  string.contains(rendered, "data-instance-error=\"checklist-a\"")
  |> should.be_true
  string.contains(rendered, "action failed: empty label")
  |> should.be_true
}

pub fn lifecycle_labels_keep_preparation_unavailable_and_failure_reasons_test() -> Nil {
  let entry =
    workspace.ManifestEntry(
      instance_id: "checklist-a",
      kind: catalog.checklist_kind,
      version: catalog.checklist_version,
      config: json.object([]),
      child_handle: json.null(),
    )

  app.lifecycle_state_label(component_runtime_js.Loading(
    entry,
    "child map is not available",
  ))
  |> should.equal("Preparing: child map is not available")

  app.lifecycle_state_label(component_runtime_js.Unavailable(
    entry,
    component.NotRegistered("project-room/future"),
  ))
  |> fn(label) {
    string.contains(label, "Unavailable:")
    && string.contains(label, "project-room/future")
  }
  |> should.be_true

  app.lifecycle_state_label(component_runtime_js.Failed(
    "checklist-a",
    component_runtime_js.ActionFailed("checklist-a", "empty label"),
  ))
  |> fn(label) {
    string.contains(label, "Failed:") && string.contains(label, "empty label")
  }
  |> should.be_true
}

pub fn move_and_remove_success_preserve_the_palette_title_test() -> Nil {
  app.palette_title_after_workspace_operation("Next component", False, Ok(Nil))
  |> should.equal("Next component")

  app.palette_title_after_workspace_operation(
    "Created component",
    True,
    Ok(Nil),
  )
  |> should.equal("")

  app.palette_title_after_workspace_operation(
    "Retry component",
    True,
    Error(workspace_setup.InvalidTitle),
  )
  |> should.equal("Retry component")
}

fn component_trees() -> #(
  watershed.Document(Root),
  watershed.SharedMap,
  watershed.SharedMap,
) {
  let sluice = sluice_js.start(tenant: "default", document: "dynamic-views")
  let document = sluice_js.connect(sluice, "user-a")
  sluice_js.settle(sluice)
  let assert Ok(checklist_tree) = watershed.create_map(document)
  let assert Ok(tally_tree) = watershed.create_map(document)
  #(document, checklist_tree, tally_tree)
}

fn start_checklist(
  document: watershed.Document(Root),
  subtree: watershed.SharedMap,
) -> checklist.Running {
  let outcome = transport_js.new_cell(None)
  checklist.start(
    document,
    subtree,
    fn() { Nil },
    checklist.Config(title: "Checklist"),
    fn(result) { transport_js.set_cell(outcome, Some(result)) },
  )
  let assert Some(Ok(running)) = transport_js.get_cell(outcome)
  running
}

fn start_tally(
  document: watershed.Document(Root),
  subtree: watershed.SharedMap,
) -> tally.Running {
  let outcome = transport_js.new_cell(None)
  tally.start(
    document,
    subtree,
    fn() { Nil },
    component.output_emitter(fn(_) { Nil }),
    tally.Config(title: "Tally", target: 10),
    fn(result) { transport_js.set_cell(outcome, Some(result)) },
  )
  let assert Some(Ok(running)) = transport_js.get_cell(outcome)
  running
}
