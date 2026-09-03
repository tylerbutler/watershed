import gleam/option.{None, Some}
import gleeunit

import watershed
import watershed/component
import watershed/sluice_js
import watershed/transport_js

import project_room_lustre/catalog
import project_room_lustre/checklist
import project_room_lustre/tally
import project_room_lustre/views

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
