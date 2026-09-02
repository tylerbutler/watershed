//// Two-client acceptance test for the project room component runtime.

import gleam/list
import gleam/option.{None, Some}
import gleeunit/should

import watershed
import watershed/component
import watershed/component_runtime_js
import watershed/sluice_js
import watershed/transport_js
import watershed/workspace_js

import project_room_lustre/activity
import project_room_lustre/catalog
import project_room_lustre/document_schema
import project_room_lustre/notes
import project_room_lustre/task_collection
import project_room_lustre/workspace_setup

type RoomRuntime =
  component_runtime_js.Runtime(
    document_schema.ProjectRoom,
    catalog.Context(document_schema.ProjectRoom),
    catalog.Running,
  )

pub fn two_clients_keep_selection_local_and_completion_shared_test() -> Nil {
  let sluice =
    sluice_js.start(tenant: "default", document: "project-room-acceptance")
  let document_a = sluice_js.connect(sluice, "user-a")
  let document_b = sluice_js.connect(sluice, "user-b")
  sluice_js.settle(sluice)

  let store_a = ensure_workspace(document_a)
  let assert Ok(Nil) = workspace_setup.seed(store_a)
  sluice_js.settle(sluice)
  let assert Ok(store_b) =
    workspace_js.resolve(
      document_b,
      watershed.root_typed(document_b),
      document_schema.workspace(),
    )

  let reports_a = transport_js.new_cell([])
  let reports_b = transport_js.new_cell([])
  let runtime_a = start_runtime(sluice, document_a, store_a, reports_a)
  let runtime_b = start_runtime(sluice, document_b, store_b, reports_b)
  settle_runtime(sluice)

  run_task(runtime_a, fn(tasks) { task_collection.select(tasks, "task-1") })
  let assert Ok(notes_a) =
    component_runtime_js.running(runtime_a, catalog.notes_instance_id)
    |> result_then(catalog.as_notes)
  let assert Ok(notes_b) =
    component_runtime_js.running(runtime_b, catalog.notes_instance_id)
    |> result_then(catalog.as_notes)
  notes.focused_task_id(notes_a) |> should.equal(Some("task-1"))
  notes.focused_task_id(notes_b) |> should.equal(None)

  run_task(runtime_a, fn(tasks) { task_collection.complete(tasks, "task-1") })
  sluice_js.settle(sluice)
  sluice_js.advance(sluice, 0)

  assert_completed_once(runtime_a)
  assert_completed_once(runtime_b)
  let assert Ok(notes_b_after_completion) =
    component_runtime_js.running(runtime_b, catalog.notes_instance_id)
    |> result_then(catalog.as_notes)
  notes.focused_task_id(notes_b_after_completion) |> should.equal(None)
  reports_with_mutation(transport_js.get_cell(reports_a))
  |> should.equal(1)
  reports_with_mutation(transport_js.get_cell(reports_b))
  |> should.equal(0)

  component_runtime_js.stop(runtime_b) |> should.equal([])
  let reports_reopened = transport_js.new_cell([])
  let reopened = start_runtime(sluice, document_b, store_b, reports_reopened)
  settle_runtime(sluice)
  assert_completed_once(reopened)
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

fn start_runtime(
  sluice: sluice_js.Sluice,
  document: watershed.Document(document_schema.ProjectRoom),
  store: workspace_js.Workspace(document_schema.ProjectRoom),
  reports: transport_js.Cell(List(component_runtime_js.DispatchReport)),
) -> RoomRuntime {
  component_runtime_js.start(
    document: document,
    root: watershed.root_typed(document),
    field: document_schema.workspace(),
    store: store,
    catalog: catalog.catalog(),
    context_for: fn(entry, subtree, invalidate) {
      catalog.context(document, subtree, entry.instance_id, invalidate)
    },
    scheduler: sluice_js.scheduler(sluice),
    on_change: fn() { Nil },
    on_report: fn(report) {
      transport_js.set_cell(reports, [report, ..transport_js.get_cell(reports)])
    },
  )
}

fn settle_runtime(sluice: sluice_js.Sluice) -> Nil {
  settle_rounds(sluice, 8)
}

fn settle_rounds(sluice: sluice_js.Sluice, remaining: Int) -> Nil {
  case remaining {
    0 -> Nil
    _ -> {
      sluice_js.advance(sluice, 0)
      sluice_js.settle(sluice)
      sluice_js.advance(sluice, 200)
      settle_rounds(sluice, remaining - 1)
    }
  }
}

fn run_task(
  runtime: RoomRuntime,
  action: fn(task_collection.Running) ->
    #(task_collection.Running, List(component.OutputEvent)),
) -> Nil {
  component_runtime_js.command(
    runtime,
    catalog.task_collection_instance_id,
    fn(running) {
      case catalog.as_task_collection(running) {
        Error(Nil) -> Error("task action reached the wrong component")
        Ok(tasks) -> {
          let #(tasks, outputs) = action(tasks)
          Ok(#(catalog.TaskCollection(tasks), outputs))
        }
      }
    },
  )
  |> should.equal(Ok(Nil))
}

fn assert_completed_once(runtime: RoomRuntime) -> Nil {
  let assert Ok(tasks) =
    component_runtime_js.running(runtime, catalog.task_collection_instance_id)
    |> result_then(catalog.as_task_collection)
  let assert Some(task) = task_collection.task(tasks, "task-1")
  task.completed |> should.equal(True)

  let assert Ok(stream) =
    component_runtime_js.running(runtime, catalog.activity_instance_id)
    |> result_then(catalog.as_activity)
  activity.entries(stream)
  |> list.filter(fn(entry) { entry.task_id == "task-1" })
  |> list.length
  |> should.equal(1)
}

fn reports_with_mutation(
  reports: List(component_runtime_js.DispatchReport),
) -> Int {
  reports
  |> list.filter(fn(report) {
    case report {
      component_runtime_js.MutationSubmitted(
        _,
        "tasks-completed-to-activity-append",
        _,
      ) -> True
      _ -> False
    }
  })
  |> list.length
}

fn result_then(
  result: Result(a, Nil),
  next: fn(a) -> Result(b, Nil),
) -> Result(b, Nil) {
  case result {
    Ok(value) -> next(value)
    Error(Nil) -> Error(Nil)
  }
}
