//// Two-client acceptance test for the project room component runtime.

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleeunit/should

import watershed
import watershed/component
import watershed/component_runtime_js
import watershed/sluice_js
import watershed/transport_js
import watershed/workspace_js

import project_room_lustre/activity
import project_room_lustre/catalog
import project_room_lustre/checklist
import project_room_lustre/decision_poll
import project_room_lustre/document_schema
import project_room_lustre/governance_payload
import project_room_lustre/inspector
import project_room_lustre/notes
import project_room_lustre/ownership_slots
import project_room_lustre/tally
import project_room_lustre/task_collection
import project_room_lustre/workspace_setup

type RoomRuntime =
  component_runtime_js.Runtime(
    document_schema.ProjectRoom,
    catalog.Context(document_schema.ProjectRoom),
    catalog.Running,
  )

pub fn two_clients_inspect_independently_and_complete_collaboratively_test() -> Nil {
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
  let runtime_a =
    start_runtime(sluice, document_a, store_a, "user-a", "User A", reports_a)
  let runtime_b =
    start_runtime(sluice, document_b, store_b, "user-b", "User B", reports_b)
  settle_runtime(sluice)
  component_runtime_js.layout(runtime_a)
  |> should.equal([
    catalog.task_collection_instance_id,
    catalog.inspector_instance_id,
    catalog.decision_poll_instance_id,
    catalog.ownership_slots_instance_id,
    catalog.notes_instance_id,
    catalog.activity_instance_id,
    catalog.checklist_instance_id,
    catalog.tally_instance_id,
  ])
  component_runtime_js.layout(runtime_b)
  |> should.equal(component_runtime_js.layout(runtime_a))

  run_checklist(runtime_a, fn(items) {
    let #(items, _) = checklist.set_draft(items, "Ship the palette")
    checklist.add(items)
  })
  let assert Ok(checklist_a) =
    component_runtime_js.running(runtime_a, catalog.checklist_instance_id)
    |> result_then(catalog.as_checklist)
  let assert [item] = checklist.items(checklist_a)
  run_checklist(runtime_a, fn(items) { checklist.complete(items, item.id) })
  settle_runtime(sluice)
  assert_tally_value(runtime_a, 1)
  assert_tally_value(runtime_b, 1)

  run_task(runtime_a, fn(tasks) { task_collection.select(tasks, "task-1") })
  assert_inspected(runtime_a, Some("task-1"))
  assert_inspected(runtime_b, None)

  run_task(runtime_b, fn(tasks) { task_collection.select(tasks, "task-2") })
  assert_inspected(runtime_a, Some("task-1"))
  assert_inspected(runtime_b, Some("task-2"))

  run_task(runtime_a, fn(tasks) { task_collection.complete(tasks, "task-1") })
  sluice_js.settle(sluice)
  sluice_js.advance(sluice, 0)

  assert_completed_once(runtime_a)
  assert_completed_once(runtime_b)
  assert_inspected(runtime_a, Some("task-1"))
  assert_inspected(runtime_b, Some("task-2"))
  reports_with_mutation(transport_js.get_cell(reports_a))
  |> should.equal(1)
  reports_with_mutation(transport_js.get_cell(reports_b))
  |> should.equal(0)

  run_poll(runtime_a, fn(poll) {
    decision_poll.set_results_visibility(poll, governance_payload.ShowResults)
  })
  assert_results_visible(runtime_a, True)
  assert_results_visible(runtime_b, False)

  sluice_js.pause(sluice, document_a)
  sluice_js.pause(sluice, document_b)
  run_poll(runtime_a, fn(poll) { decision_poll.vote(poll, "customer-research") })
  run_poll(runtime_b, fn(poll) { decision_poll.vote(poll, "customer-research") })
  sluice_js.resume(sluice, document_a)
  sluice_js.resume(sluice, document_b)
  settle_runtime(sluice)

  assert_poll_threshold(runtime_a)
  assert_poll_threshold(runtime_b)

  sluice_js.pause(sluice, document_a)
  sluice_js.pause(sluice, document_b)
  run_ownership(
    runtime_a,
    governance_payload.SlotCommand("facilitator", governance_payload.ClaimSlot),
  )
  run_ownership(
    runtime_b,
    governance_payload.SlotCommand("facilitator", governance_payload.ClaimSlot),
  )
  sluice_js.resume(sluice, document_a)
  sluice_js.resume(sluice, document_b)
  settle_runtime(sluice)

  let owner = assert_same_owner(runtime_a, runtime_b)
  run_ownership_local(runtime_a, ownership_slots.toggle_details)
  assert_owner_details(runtime_a, True)
  assert_owner_details(runtime_b, False)

  let assert Ok(notes_a) =
    component_runtime_js.running(runtime_a, catalog.notes_instance_id)
    |> result_then(catalog.as_notes)
  let assert Ok(Nil) = watershed.text_append(notes.text(notes_a), "Decision")
  settle_runtime(sluice)

  component_runtime_js.stop(runtime_b) |> should.equal([])
  let reports_reopened = transport_js.new_cell([])
  let reopened =
    start_runtime(
      sluice,
      document_b,
      store_b,
      "user-b",
      "User B",
      reports_reopened,
    )
  settle_runtime(sluice)
  assert_completed_once(reopened)
  assert_inspected(reopened, None)
  assert_results_visible(reopened, False)
  assert_poll_threshold(reopened)
  assert_owner(reopened, owner)
  let assert Ok(reopened_notes) =
    component_runtime_js.running(reopened, catalog.notes_instance_id)
    |> result_then(catalog.as_notes)
  watershed.text_value(notes.text(reopened_notes))
  |> should.equal("Decision")
}

pub fn runtime_created_checklist_converges_and_stops_test() -> Nil {
  let #(sluice, document_a, document_b, store_a, store_b) =
    two_client_workspace("project-room-runtime-create")
  let runtime_a = start_test_runtime(sluice, document_a, store_a, "user-a")
  let runtime_b = start_test_runtime(sluice, document_b, store_b, "user-b")
  settle_runtime(sluice)

  let assert Ok(preset) = catalog.find_creation_preset(catalog.checklist_kind)
  let instance_id = "checklist-runtime-test"
  workspace_setup.create_from_preset(
    store_a,
    catalog.catalog(),
    preset,
    instance_id,
    "Sprint checklist",
  )
  |> should.equal(Ok(Nil))
  settle_runtime(sluice)

  component_runtime_js.running(runtime_a, instance_id)
  |> result_then(catalog.as_checklist)
  |> result.is_ok
  |> should.be_true
  component_runtime_js.running(runtime_b, instance_id)
  |> result_then(catalog.as_checklist)
  |> result.is_ok
  |> should.be_true

  run_checklist_instance(runtime_a, instance_id, fn(items) {
    let #(items, _) = checklist.set_draft(items, "Verify both clients")
    checklist.add(items)
  })
  settle_runtime(sluice)

  let assert Ok(checklist_a) =
    component_runtime_js.running(runtime_a, instance_id)
    |> result_then(catalog.as_checklist)
  let assert [item] = checklist.items(checklist_a)
  let assert Ok(checklist_b) =
    component_runtime_js.running(runtime_b, instance_id)
    |> result_then(catalog.as_checklist)
  checklist.items(checklist_b) |> should.equal([item])

  run_checklist_instance(runtime_b, instance_id, fn(items) {
    checklist.complete(items, item.id)
  })
  settle_runtime(sluice)

  let assert Ok(checklist_a) =
    component_runtime_js.running(runtime_a, instance_id)
    |> result_then(catalog.as_checklist)
  checklist.completed(checklist_a, item.id) |> should.be_true
  let assert Ok(checklist_b) =
    component_runtime_js.running(runtime_b, instance_id)
    |> result_then(catalog.as_checklist)
  checklist.completed(checklist_b, item.id) |> should.be_true
  assert_tally_value(runtime_a, 0)
  assert_tally_value(runtime_b, 0)

  workspace_js.move_instance(store_a, catalog.catalog(), instance_id, 0)
  |> should.equal(Ok(Nil))
  settle_runtime(sluice)
  let assert [first_a, ..] = component_runtime_js.layout(runtime_a)
  first_a |> should.equal(instance_id)
  let assert [first_b, ..] = component_runtime_js.layout(runtime_b)
  first_b |> should.equal(instance_id)

  workspace_js.delete_instance(store_a, catalog.catalog(), instance_id)
  |> should.equal(Ok(Nil))
  settle_runtime(sluice)
  component_runtime_js.running(runtime_a, instance_id)
  |> should.equal(Error(Nil))
  component_runtime_js.running(runtime_b, instance_id)
  |> should.equal(Error(Nil))
}

fn two_client_workspace(
  name: String,
) -> #(
  sluice_js.Sluice,
  watershed.Document(document_schema.ProjectRoom),
  watershed.Document(document_schema.ProjectRoom),
  workspace_js.Workspace(document_schema.ProjectRoom),
  workspace_js.Workspace(document_schema.ProjectRoom),
) {
  let sluice = sluice_js.start(tenant: "default", document: name)
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
  #(sluice, document_a, document_b, store_a, store_b)
}

fn start_test_runtime(
  sluice: sluice_js.Sluice,
  document: watershed.Document(document_schema.ProjectRoom),
  store: workspace_js.Workspace(document_schema.ProjectRoom),
  participant_id: String,
) -> RoomRuntime {
  start_runtime(
    sluice,
    document,
    store,
    participant_id,
    participant_id,
    transport_js.new_cell([]),
  )
}

fn assert_inspected(runtime: RoomRuntime, task_id: Option(String)) -> Nil {
  let assert Ok(running) =
    component_runtime_js.running(runtime, catalog.inspector_instance_id)
    |> result_then(catalog.as_inspector)
  inspector.selected(running)
  |> option.map(fn(task) { task.task_id })
  |> should.equal(task_id)
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
  participant_id: String,
  participant_label: String,
  reports: transport_js.Cell(List(component_runtime_js.DispatchReport)),
) -> RoomRuntime {
  component_runtime_js.start(
    document: document,
    root: watershed.root_typed(document),
    field: document_schema.workspace(),
    store: store,
    catalog: catalog.catalog(),
    context_for: fn(entry, subtree, invalidate, emitter) {
      catalog.context(
        document,
        subtree,
        entry.instance_id,
        invalidate,
        participant_id,
        participant_label,
        emitter,
      )
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

fn run_checklist(
  runtime: RoomRuntime,
  action: fn(checklist.Running) ->
    Result(#(checklist.Running, List(component.OutputEvent)), String),
) -> Nil {
  run_checklist_instance(runtime, catalog.checklist_instance_id, action)
}

fn run_checklist_instance(
  runtime: RoomRuntime,
  instance_id: String,
  action: fn(checklist.Running) ->
    Result(#(checklist.Running, List(component.OutputEvent)), String),
) -> Nil {
  component_runtime_js.command(runtime, instance_id, fn(running) {
    case catalog.as_checklist(running) {
      Error(Nil) -> Error("checklist action reached the wrong component")
      Ok(items) ->
        action(items)
        |> result.map(fn(next) { #(catalog.Checklist(next.0), next.1) })
    }
  })
  |> should.equal(Ok(Nil))
}

fn run_poll(
  runtime: RoomRuntime,
  action: fn(decision_poll.Running) ->
    Result(#(decision_poll.Running, List(component.OutputEvent)), String),
) -> Nil {
  component_runtime_js.command(
    runtime,
    catalog.decision_poll_instance_id,
    fn(running) {
      case catalog.as_decision_poll(running) {
        Error(Nil) -> Error("poll action reached the wrong component")
        Ok(poll) ->
          case action(poll) {
            Error(reason) -> Error(reason)
            Ok(next) -> Ok(#(catalog.DecisionPoll(next.0), next.1))
          }
      }
    },
  )
  |> should.equal(Ok(Nil))
}

fn run_ownership(
  runtime: RoomRuntime,
  command: governance_payload.SlotCommand,
) -> Nil {
  run_ownership_local(runtime, fn(running) {
    ownership_slots.submit(running, command)
  })
}

fn run_ownership_local(
  runtime: RoomRuntime,
  action: fn(ownership_slots.Running) ->
    Result(#(ownership_slots.Running, List(component.OutputEvent)), String),
) -> Nil {
  component_runtime_js.command(
    runtime,
    catalog.ownership_slots_instance_id,
    fn(running) {
      case catalog.as_ownership_slots(running) {
        Error(Nil) -> Error("ownership action reached the wrong component")
        Ok(ownership) ->
          case action(ownership) {
            Error(reason) -> Error(reason)
            Ok(next) -> Ok(#(catalog.OwnershipSlots(next.0), next.1))
          }
      }
    },
  )
  |> should.equal(Ok(Nil))
}

fn assert_results_visible(runtime: RoomRuntime, expected: Bool) -> Nil {
  let assert Ok(poll) =
    component_runtime_js.running(runtime, catalog.decision_poll_instance_id)
    |> result_then(catalog.as_decision_poll)
  decision_poll.results_visible(poll) |> should.equal(expected)
}

fn assert_tally_value(runtime: RoomRuntime, expected: Int) -> Nil {
  let assert Ok(counter) =
    component_runtime_js.running(runtime, catalog.tally_instance_id)
    |> result_then(catalog.as_tally)
  tally.value(counter) |> should.equal(expected)
}

fn assert_poll_threshold(runtime: RoomRuntime) -> Nil {
  let assert Ok(poll) =
    component_runtime_js.running(runtime, catalog.decision_poll_instance_id)
    |> result_then(catalog.as_decision_poll)
  decision_poll.approval_count(poll, "customer-research")
  |> should.equal(2)
  decision_poll.threshold_reached(poll, "customer-research")
  |> should.be_true
}

fn assert_same_owner(
  first: RoomRuntime,
  second: RoomRuntime,
) -> governance_payload.Identity {
  let assert Ok(first_running) =
    component_runtime_js.running(first, catalog.ownership_slots_instance_id)
    |> result_then(catalog.as_ownership_slots)
  let assert Some(owner) = ownership_slots.owner(first_running, "facilitator")
  assert_owner(second, owner)
  owner
}

fn assert_owner(
  runtime: RoomRuntime,
  expected: governance_payload.Identity,
) -> Nil {
  let assert Ok(running) =
    component_runtime_js.running(runtime, catalog.ownership_slots_instance_id)
    |> result_then(catalog.as_ownership_slots)
  ownership_slots.owner(running, "facilitator")
  |> should.equal(Some(expected))
}

fn assert_owner_details(runtime: RoomRuntime, expected: Bool) -> Nil {
  let assert Ok(running) =
    component_runtime_js.running(runtime, catalog.ownership_slots_instance_id)
    |> result_then(catalog.as_ownership_slots)
  ownership_slots.details_revealed(running) |> should.equal(expected)
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
  |> list.filter(fn(entry) {
    case entry {
      activity.TaskCompleted(task) -> task.task_id == "task-1"
      activity.PollThresholdReached(_) | activity.OwnershipAccepted(_) -> False
    }
  })
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
