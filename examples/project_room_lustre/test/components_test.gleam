import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should

import watershed
import watershed/component
import watershed/port_graph
import watershed/sluice_js
import watershed/transport_js

import project_room_lustre/activity
import project_room_lustre/catalog
import project_room_lustre/inspector
import project_room_lustre/notes
import project_room_lustre/payload
import project_room_lustre/task_collection

type Root

fn document(name: String) -> #(sluice_js.Sluice, watershed.Document(Root)) {
  let sluice = sluice_js.start(tenant: "default", document: name)
  let document = sluice_js.connect(sluice, "user-a")
  sluice_js.settle(sluice)
  #(sluice, document)
}

fn new_subtree(document: watershed.Document(Root)) -> watershed.SharedMap {
  let assert Ok(subtree) = watershed.create_map(document)
  subtree
}

fn invalidations() -> transport_js.Cell(Int) {
  transport_js.new_cell(0)
}

fn count_invalidation(counter: transport_js.Cell(Int)) -> fn() -> Nil {
  fn() { transport_js.set_cell(counter, transport_js.get_cell(counter) + 1) }
}

fn task_ids(tasks: List(payload.TaskPayload)) -> List(String) {
  list.map(tasks, fn(task) { task.task_id })
}

fn attach_shared_task_collection_subtree(
  document: watershed.Document(Root),
) -> watershed.SharedMap {
  let assert Ok(subtree) = watershed.create_map(document)
  let assert Ok(order) = watershed.create_sequence(document)
  let assert Ok(records) = watershed.create_map(document)
  watershed.set(
    watershed.root(document),
    "shared",
    watershed.handle_of(subtree),
  )
  watershed.set(subtree, "task_order", watershed.sequence_handle_of(order))
  watershed.set(subtree, "task_records", watershed.handle_of(records))
  subtree
}

fn resolve_shared_task_collection_subtree(
  document: watershed.Document(Root),
) -> watershed.SharedMap {
  let assert Ok(handle) = watershed.get(watershed.root(document), "shared")
  let assert Ok(subtree) = watershed.resolve(document, handle)
  subtree
}

fn start_task_collection(
  document: watershed.Document(Root),
  subtree: watershed.SharedMap,
  counter: transport_js.Cell(Int),
) -> task_collection.Running {
  let outcome = transport_js.new_cell(None)
  task_collection.start(
    document,
    subtree,
    count_invalidation(counter),
    catalog.task_collection_config(),
    fn(result) { transport_js.set_cell(outcome, Some(result)) },
  )
  let assert Some(Ok(running)) = transport_js.get_cell(outcome)
  running
}

fn start_notes(
  document: watershed.Document(Root),
  subtree: watershed.SharedMap,
  counter: transport_js.Cell(Int),
) -> notes.Running {
  let outcome = transport_js.new_cell(None)
  notes.start(
    document,
    subtree,
    count_invalidation(counter),
    catalog.notes_config(),
    fn(result) { transport_js.set_cell(outcome, Some(result)) },
  )
  let assert Some(Ok(running)) = transport_js.get_cell(outcome)
  running
}

fn start_inspector(
  document: watershed.Document(Root),
  subtree: watershed.SharedMap,
  counter: transport_js.Cell(Int),
) -> inspector.Running {
  let outcome = transport_js.new_cell(None)
  inspector.start(
    document,
    subtree,
    count_invalidation(counter),
    catalog.inspector_config(),
    fn(result) { transport_js.set_cell(outcome, Some(result)) },
  )
  let assert Some(Ok(running)) = transport_js.get_cell(outcome)
  running
}

fn start_activity(
  document: watershed.Document(Root),
  subtree: watershed.SharedMap,
  counter: transport_js.Cell(Int),
) -> activity.Running {
  let outcome = transport_js.new_cell(None)
  activity.start(
    document,
    subtree,
    count_invalidation(counter),
    catalog.activity_config(),
    fn(result) { transport_js.set_cell(outcome, Some(result)) },
  )
  let assert Some(Ok(running)) = transport_js.get_cell(outcome)
  running
}

pub fn bootstrap_twice_adopts_same_handles_and_data_test() -> Nil {
  let #(_sluice, room) = document("project-room-bootstrap")

  let tasks_tree = new_subtree(room)
  let inspector_tree = new_subtree(room)
  let notes_tree = new_subtree(room)
  let activity_tree = new_subtree(room)

  let tasks_a = start_task_collection(room, tasks_tree, invalidations())
  let tasks_b = start_task_collection(room, tasks_tree, invalidations())
  watershed.sequence_handle_of(task_collection.order(tasks_a))
  |> should.equal(watershed.sequence_handle_of(task_collection.order(tasks_b)))
  watershed.handle_of(task_collection.records(tasks_a))
  |> should.equal(watershed.handle_of(task_collection.records(tasks_b)))
  task_collection.tasks(tasks_a) |> should.equal(task_collection.tasks(tasks_b))

  let inspector_a = start_inspector(room, inspector_tree, invalidations())
  let inspector_b = start_inspector(room, inspector_tree, invalidations())
  inspector.selected(inspector_a) |> should.equal(None)
  inspector.selected(inspector_b) |> should.equal(None)

  let notes_a = start_notes(room, notes_tree, invalidations())
  let notes_b = start_notes(room, notes_tree, invalidations())
  watershed.text_handle_of(notes.text(notes_a))
  |> should.equal(watershed.text_handle_of(notes.text(notes_b)))
  watershed.text_value(notes.text(notes_a))
  |> should.equal(watershed.text_value(notes.text(notes_b)))

  let activity_a = start_activity(room, activity_tree, invalidations())
  let activity_b = start_activity(room, activity_tree, invalidations())
  watershed.sequence_handle_of(activity.entries_sequence(activity_a))
  |> should.equal(
    watershed.sequence_handle_of(activity.entries_sequence(activity_b)),
  )
  activity.entries(activity_a) |> should.equal(activity.entries(activity_b))

  let assert Ok(Nil) = task_collection.stop(tasks_a)
  let assert Ok(Nil) = task_collection.stop(tasks_b)
  let assert Ok(Nil) = inspector.stop(inspector_a)
  let assert Ok(Nil) = inspector.stop(inspector_b)
  let assert Ok(Nil) = notes.stop(notes_a)
  let assert Ok(Nil) = notes.stop(notes_b)
  let assert Ok(Nil) = activity.stop(activity_a)
  let assert Ok(Nil) = activity.stop(activity_b)
  Nil
}

pub fn stop_and_restart_preserves_data_test() -> Nil {
  let #(_sluice, room) = document("project-room-restart")

  let tasks_tree = new_subtree(room)
  let notes_tree = new_subtree(room)
  let activity_tree = new_subtree(room)

  let task_counter = invalidations()
  let notes_counter = invalidations()
  let activity_counter = invalidations()

  let tasks_running = start_task_collection(room, tasks_tree, task_counter)
  let notes_running = start_notes(room, notes_tree, notes_counter)
  let activity_running = start_activity(room, activity_tree, activity_counter)

  let assert [first_task, ..] = task_collection.tasks(tasks_running)
  let #(_next_tasks, first_events) =
    task_collection.complete(tasks_running, first_task.task_id)
  let assert [first_event] = first_events
  component.output_payload(first_event)
  |> payload.decode
  |> should.equal(Ok(payload.TaskPayload(..first_task, completed: True)))

  let assert Ok(Nil) = watershed.text_append(notes.text(notes_running), "Alpha")
  let assert Ok(#(next_activity, [])) =
    activity.append_entry(
      activity_running,
      payload.TaskPayload(
        task_id: "task-9",
        title: "Archived decision",
        completed: True,
      ),
    )
  activity.entries(next_activity)
  |> should.equal([
    payload.TaskPayload(
      task_id: "task-9",
      title: "Archived decision",
      completed: True,
    ),
  ])

  let assert Ok(Nil) = task_collection.stop(tasks_running)
  let assert Ok(Nil) = notes.stop(notes_running)
  let assert Ok(Nil) = activity.stop(activity_running)

  let task_total = transport_js.get_cell(task_counter)
  let notes_total = transport_js.get_cell(notes_counter)
  let activity_total = transport_js.get_cell(activity_counter)

  watershed.set(
    task_collection.records(tasks_running),
    "task-1",
    payload.encode(payload.TaskPayload(
      task_id: "task-1",
      title: "Draft kickoff plan",
      completed: True,
    )),
  )
  let assert Ok(Nil) = watershed.text_append(notes.text(notes_running), " Beta")
  let assert Ok(Nil) =
    watershed.sequence_insert(
      activity.entries_sequence(activity_running),
      watershed.sequence_length(activity.entries_sequence(activity_running)),
      payload.encode(payload.TaskPayload(
        task_id: "task-10",
        title: "Shared summary",
        completed: True,
      )),
    )

  transport_js.get_cell(task_counter) |> should.equal(task_total)
  transport_js.get_cell(notes_counter) |> should.equal(notes_total)
  transport_js.get_cell(activity_counter) |> should.equal(activity_total)

  let restarted_tasks = start_task_collection(room, tasks_tree, invalidations())
  let restarted_notes = start_notes(room, notes_tree, invalidations())
  let restarted_activity = start_activity(room, activity_tree, invalidations())

  task_collection.task(restarted_tasks, "task-1")
  |> should.equal(
    Some(payload.TaskPayload(
      task_id: "task-1",
      title: "Draft kickoff plan",
      completed: True,
    )),
  )
  watershed.text_value(notes.text(restarted_notes))
  |> should.equal("Alpha Beta")
  activity.entries(restarted_activity)
  |> should.equal([
    payload.TaskPayload(
      task_id: "task-9",
      title: "Archived decision",
      completed: True,
    ),
    payload.TaskPayload(
      task_id: "task-10",
      title: "Shared summary",
      completed: True,
    ),
  ])
}

pub fn completion_emits_once_per_transition_test() -> Nil {
  let #(_sluice, room) = document("project-room-complete-once")
  let running = start_task_collection(room, new_subtree(room), invalidations())
  let assert [first_task, ..] = task_collection.tasks(running)

  let #(completed_once, first_events) =
    task_collection.complete(running, first_task.task_id)
  let #(completed_twice, second_events) =
    task_collection.complete(completed_once, first_task.task_id)

  list.length(first_events) |> should.equal(1)
  first_events
  |> list.map(component.output_id)
  |> should.equal([payload.task_completed_port_id])
  second_events |> should.equal([])
  task_collection.task(completed_twice, first_task.task_id)
  |> should.equal(Some(payload.TaskPayload(..first_task, completed: True)))
}

pub fn inspector_selection_is_local_test() -> Nil {
  let #(_sluice, room) = document("project-room-inspector")
  let subtree = new_subtree(room)
  let counter = invalidations()
  let context =
    catalog.context(room, subtree, catalog.inspector_instance_id, fn() {
      transport_js.set_cell(counter, transport_js.get_cell(counter) + 1)
    })
  let room_catalog: component.Catalog(catalog.Context(Root), catalog.Running) =
    catalog.catalog()
  let assert Ok(descriptor) =
    component.find(
      room_catalog,
      catalog.inspector_kind,
      catalog.inspector_version,
    )
  let outcome = transport_js.new_cell(None)
  component.start(
    descriptor,
    context,
    catalog.inspector_config_json(),
    fn(result) { transport_js.set_cell(outcome, Some(result)) },
  )
  let assert Some(Ok(running)) = transport_js.get_cell(outcome)
  let before_focus = transport_js.get_cell(counter)
  let subject =
    payload.TaskPayload(
      task_id: "task-2",
      title: "Collect team notes",
      completed: False,
    )
  let assert Ok(#(next_running, [])) =
    component.deliver(
      descriptor,
      running,
      payload.inspect_task_port_id,
      payload.encode(subject),
    )
  let assert Ok(next_inspector) = catalog.as_inspector(next_running)

  inspector.selected(next_inspector) |> should.equal(Some(subject))
  transport_js.get_cell(counter) |> should.equal(before_focus)
}

pub fn activity_append_writes_one_record_test() -> Nil {
  let #(_sluice, room) = document("project-room-activity-append")
  let subtree = new_subtree(room)
  let counter = invalidations()
  let running = start_activity(room, subtree, counter)
  let entry =
    payload.TaskPayload(
      task_id: "task-7",
      title: "Close sprint",
      completed: True,
    )

  let assert Ok(#(next_running, events)) = activity.append_entry(running, entry)

  events |> should.equal([])
  watershed.sequence_values(activity.entries_sequence(next_running))
  |> list.length
  |> should.equal(1)
  activity.entries(next_running) |> should.equal([entry])
}

pub fn concurrent_bootstrap_keeps_three_unique_task_ids_test() -> Nil {
  let sluice = sluice_js.start(tenant: "default", document: "project-room-race")
  let document_a = sluice_js.connect(sluice, "user-a")
  let document_b = sluice_js.connect(sluice, "user-b")
  sluice_js.settle(sluice)

  let subtree_a = attach_shared_task_collection_subtree(document_a)
  sluice_js.settle(sluice)
  let subtree_b = resolve_shared_task_collection_subtree(document_b)

  sluice_js.pause(sluice, document_a)
  sluice_js.pause(sluice, document_b)
  let running_a = start_task_collection(document_a, subtree_a, invalidations())
  let running_b = start_task_collection(document_b, subtree_b, invalidations())
  sluice_js.resume(sluice, document_a)
  sluice_js.resume(sluice, document_b)
  sluice_js.settle(sluice)

  watershed.sequence_values(task_collection.order(running_a))
  |> list.length
  |> should.equal(6)
  task_ids(task_collection.tasks(running_a))
  |> should.equal(["task-1", "task-2", "task-3"])
  task_ids(task_collection.tasks(running_b))
  |> should.equal(task_ids(task_collection.tasks(running_a)))
}

pub fn configs_payloads_and_catalog_connections_round_trip_test() -> Nil {
  let room_catalog: component.Catalog(catalog.Context(Root), catalog.Running) =
    catalog.catalog()
  let payload_value =
    payload.TaskPayload(
      task_id: "task-4",
      title: "Review notes",
      completed: False,
    )
  payload.encode(payload_value)
  |> payload.decode
  |> should.equal(Ok(payload_value))

  json.parse(
    json.to_string(
      task_collection.encode_config(catalog.task_collection_config()),
    ),
    task_collection.config_decoder(),
  )
  |> should.equal(Ok(catalog.task_collection_config()))

  json.parse(
    json.to_string(inspector.encode_config(catalog.inspector_config())),
    inspector.config_decoder(),
  )
  |> should.equal(Ok(catalog.inspector_config()))

  json.parse(
    json.to_string(notes.encode_config(catalog.notes_config())),
    notes.config_decoder(),
  )
  |> should.equal(Ok(catalog.notes_config()))

  json.parse(
    json.to_string(activity.encode_config(catalog.activity_config())),
    activity.config_decoder(),
  )
  |> should.equal(Ok(catalog.activity_config()))

  let assert Ok(tasks_descriptor) =
    component.find(
      room_catalog,
      catalog.task_collection_kind,
      catalog.task_collection_version,
    )
  let assert Ok(notes_descriptor) =
    component.find(room_catalog, catalog.notes_kind, catalog.notes_version)
  let assert Ok(inspector_descriptor) =
    component.find(
      room_catalog,
      catalog.inspector_kind,
      catalog.inspector_version,
    )
  let assert Ok(activity_descriptor) =
    component.find(
      room_catalog,
      catalog.activity_kind,
      catalog.activity_version,
    )
  component.validate_config(
    tasks_descriptor,
    catalog.task_collection_config_json(),
  )
  |> should.equal(Ok(Nil))
  component.validate_config(notes_descriptor, catalog.notes_config_json())
  |> should.equal(Ok(Nil))
  component.validate_config(
    inspector_descriptor,
    catalog.inspector_config_json(),
  )
  |> should.equal(Ok(Nil))
  component.validate_config(activity_descriptor, catalog.activity_config_json())
  |> should.equal(Ok(Nil))

  let connections = catalog.persisted_connections()
  connections |> list.length |> should.equal(2)
  connections
  |> should.equal([
    port_graph.connection(
      catalog.selected_inspect_connection_id,
      port_graph.PortRef(
        catalog.task_collection_instance_id,
        payload.task_selected_port_id,
      ),
      port_graph.PortRef(
        catalog.inspector_instance_id,
        payload.inspect_task_port_id,
      ),
    ),
    port_graph.connection(
      catalog.completed_append_connection_id,
      port_graph.PortRef(
        catalog.task_collection_instance_id,
        payload.task_completed_port_id,
      ),
      port_graph.PortRef(
        catalog.activity_instance_id,
        payload.append_entry_port_id,
      ),
    ),
  ])
}
