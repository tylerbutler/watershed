//// Runtime catalog for the headless project room components.

import gleam/json.{type Json}
import gleam/result

import watershed
import watershed/component
import watershed/port
import watershed/port_graph

import project_room_lustre/activity
import project_room_lustre/notes
import project_room_lustre/payload
import project_room_lustre/task_collection

/// The shared runtime context for one component instance.
pub opaque type Context(root) {
  Context(
    document: watershed.Document(root),
    subtree: watershed.SharedMap,
    instance_id: String,
    invalidate: fn() -> Nil,
  )
}

/// The shared running sum for the project room components.
pub type Running {
  TaskCollection(task_collection.Running)
  Notes(notes.Running)
  Activity(activity.Running)
}

pub const task_collection_kind = "project-room/task-collection"

pub const notes_kind = "project-room/notes"

pub const activity_kind = "project-room/activity"

pub const task_collection_version = 1

pub const notes_version = 1

pub const activity_version = 1

pub const task_collection_instance_id = "tasks"

pub const notes_instance_id = "notes"

pub const activity_instance_id = "activity"

pub const selected_focus_connection_id = "tasks-selected-to-notes-focus"

pub const completed_append_connection_id = "tasks-completed-to-activity-append"

pub fn context(
  document: watershed.Document(root),
  subtree: watershed.SharedMap,
  instance_id: String,
  invalidate: fn() -> Nil,
) -> Context(root) {
  Context(document:, subtree:, instance_id:, invalidate:)
}

pub fn document(context: Context(root)) -> watershed.Document(root) {
  context.document
}

pub fn subtree(context: Context(root)) -> watershed.SharedMap {
  context.subtree
}

pub fn instance_id(context: Context(root)) -> String {
  context.instance_id
}

pub fn invalidate(context: Context(root)) -> fn() -> Nil {
  context.invalidate
}

pub fn task_collection_config() -> task_collection.Config {
  task_collection.Config(title: "Tasks")
}

pub fn notes_config() -> notes.Config {
  notes.Config(title: "Notes")
}

pub fn activity_config() -> activity.Config {
  activity.Config(title: "Activity")
}

pub fn task_collection_config_json() -> Json {
  task_collection.encode_config(task_collection_config())
}

pub fn notes_config_json() -> Json {
  notes.encode_config(notes_config())
}

pub fn activity_config_json() -> Json {
  activity.encode_config(activity_config())
}

pub fn catalog() -> component.Catalog(Context(root), Running) {
  let assert Ok(with_tasks) =
    component.register(component.new_catalog(), task_collection_descriptor())
  let assert Ok(with_notes) = component.register(with_tasks, notes_descriptor())
  let assert Ok(full) = component.register(with_notes, activity_descriptor())
  full
}

pub fn descriptors() -> List(component.Descriptor(Context(root), Running)) {
  [
    task_collection_descriptor(),
    notes_descriptor(),
    activity_descriptor(),
  ]
}

pub fn persisted_connections() -> List(port_graph.Connection) {
  [
    selected_focus_connection(),
    completed_append_connection(),
  ]
}

pub fn selected_focus_connection() -> port_graph.Connection {
  let assert Ok(template) =
    port.connect(payload.task_selected(), payload.focus_subject())
  port_graph.connection(
    selected_focus_connection_id,
    port_graph.PortRef(task_collection_instance_id, template.source_port),
    port_graph.PortRef(notes_instance_id, template.target_port),
  )
}

pub fn completed_append_connection() -> port_graph.Connection {
  let assert Ok(template) =
    port.connect(payload.task_completed(), payload.append_entry())
  port_graph.connection(
    completed_append_connection_id,
    port_graph.PortRef(task_collection_instance_id, template.source_port),
    port_graph.PortRef(activity_instance_id, template.target_port),
  )
}

pub fn as_task_collection(
  running: Running,
) -> Result(task_collection.Running, Nil) {
  case running {
    TaskCollection(inner) -> Ok(inner)
    Notes(_) | Activity(_) -> Error(Nil)
  }
}

pub fn as_notes(running: Running) -> Result(notes.Running, Nil) {
  case running {
    Notes(inner) -> Ok(inner)
    TaskCollection(_) | Activity(_) -> Error(Nil)
  }
}

pub fn as_activity(running: Running) -> Result(activity.Running, Nil) {
  case running {
    Activity(inner) -> Ok(inner)
    TaskCollection(_) | Notes(_) -> Error(Nil)
  }
}

fn task_collection_descriptor() -> component.Descriptor(Context(root), Running) {
  component.executable_descriptor(
    kind: task_collection_kind,
    version: task_collection_version,
    config_decoder: task_collection.config_decoder(),
    start: fn(context, config, done) {
      task_collection.start(
        document(context),
        subtree(context),
        invalidate(context),
        config,
        fn(started) {
          case started {
            Ok(running) -> done(Ok(TaskCollection(running)))
            Error(reason) -> done(Error(reason))
          }
        },
      )
    },
    inputs: [],
    stop: fn(running) {
      case running {
        TaskCollection(inner) -> task_collection.stop(inner)
        Notes(_) | Activity(_) ->
          Error("task collection stop reached the wrong component")
      }
    },
    ports: [
      port.output_descriptor(payload.task_selected()),
      port.output_descriptor(payload.task_completed()),
    ],
  )
}

fn notes_descriptor() -> component.Descriptor(Context(root), Running) {
  component.executable_descriptor(
    kind: notes_kind,
    version: notes_version,
    config_decoder: notes.config_decoder(),
    start: fn(context, config, done) {
      notes.start(
        document(context),
        subtree(context),
        invalidate(context),
        config,
        fn(started) {
          case started {
            Ok(running) -> done(Ok(Notes(running)))
            Error(reason) -> done(Error(reason))
          }
        },
      )
    },
    inputs: [
      component.input_handler(payload.focus_subject(), fn(running, subject) {
        case running {
          Notes(inner) -> {
            let #(next, events) = notes.focus_subject(inner, subject)
            Ok(#(Notes(next), events))
          }
          TaskCollection(_) | Activity(_) ->
            Error("notes input reached the wrong component")
        }
      }),
    ],
    stop: fn(running) {
      case running {
        Notes(inner) -> notes.stop(inner)
        TaskCollection(_) | Activity(_) ->
          Error("notes stop reached the wrong component")
      }
    },
    ports: [port.input_descriptor(payload.focus_subject())],
  )
}

fn activity_descriptor() -> component.Descriptor(Context(root), Running) {
  component.executable_descriptor(
    kind: activity_kind,
    version: activity_version,
    config_decoder: activity.config_decoder(),
    start: fn(context, config, done) {
      activity.start(
        document(context),
        subtree(context),
        invalidate(context),
        config,
        fn(started) {
          case started {
            Ok(running) -> done(Ok(Activity(running)))
            Error(reason) -> done(Error(reason))
          }
        },
      )
    },
    inputs: [
      component.input_handler(payload.append_entry(), fn(running, entry) {
        case running {
          Activity(inner) ->
            activity.append_entry(inner, entry)
            |> result.map(fn(next) { #(Activity(next.0), next.1) })
          TaskCollection(_) | Notes(_) ->
            Error("activity input reached the wrong component")
        }
      }),
    ],
    stop: fn(running) {
      case running {
        Activity(inner) -> activity.stop(inner)
        TaskCollection(_) | Notes(_) ->
          Error("activity stop reached the wrong component")
      }
    },
    ports: [port.input_descriptor(payload.append_entry())],
  )
}
