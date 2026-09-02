//// A fixed browser project room powered by persisted component definitions.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html

import watershed
import watershed/browser
import watershed/component
import watershed/component_runtime_js
import watershed/workspace_js
import watershed_lustre
import watershed_lustre/component_runtime as runtime_effect
import watershed_lustre/textarea

import project_room_lustre/catalog
import project_room_lustre/document_schema
import project_room_lustre/notes
import project_room_lustre/task_collection
import project_room_lustre/views
import project_room_lustre/workspace_setup

const socket_url = "ws://localhost:4000/socket/websocket?vsn=2.0.0"

const tenant = "dev-tenant"

const tenant_secret = "levee-dev-secret-change-in-production"

type RoomRuntime =
  component_runtime_js.Runtime(
    document_schema.ProjectRoom,
    catalog.Context(document_schema.ProjectRoom),
    catalog.Running,
  )

type Status {
  Connecting
  Preparing
  Running
  Failed(reason: String)
}

type Model {
  Model(
    status: Status,
    connected: Bool,
    document: Option(watershed.Document(document_schema.ProjectRoom)),
    store: Option(workspace_js.Workspace(document_schema.ProjectRoom)),
    runtime: Option(RoomRuntime),
    editor: Option(textarea.Model),
    error: Option(String),
  )
}

type Msg {
  GotDocument(watershed.Document(document_schema.ProjectRoom))
  Connected(Result(Nil, String))
  WorkspaceOpened(
    Result(
      workspace_js.Workspace(document_schema.ProjectRoom),
      workspace_js.WorkspaceError,
    ),
  )
  WorkspaceSeeded(Result(Nil, workspace_js.WorkspaceError))
  RuntimeStarted(RoomRuntime)
  RuntimeChanged
  RuntimeReport(component_runtime_js.DispatchReport)
  TaskSelected(String)
  TaskCompleted(String)
  RuntimeCommandFinished(Result(Nil, component_runtime_js.RuntimeError))
  NotesEditor(textarea.Msg)
}

pub fn main() -> Nil {
  let app = lustre.application(init, update, view)
  let document = browser.document_on_navigate("project-room")
  let assert Ok(_) = lustre.start(app, "#app", document)
  Nil
}

fn init(document: String) -> #(Model, Effect(Msg)) {
  let user_id = "web-" <> int.to_string(1000 + int.random(9000))
  #(
    Model(
      status: Connecting,
      connected: False,
      document: None,
      store: None,
      runtime: None,
      editor: None,
      error: None,
    ),
    watershed_lustre.connect_dev(
      url: socket_url,
      tenant: tenant,
      secret: tenant_secret,
      document: document,
      user_id: user_id,
      got_document: GotDocument,
      connected: Connected,
    ),
  )
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    GotDocument(document) ->
      open_workspace(Model(..model, document: Some(document)))

    Connected(Ok(Nil)) ->
      open_workspace(
        Model(..model, connected: True, status: Preparing, error: None),
      )
    Connected(Error(reason)) -> #(
      Model(..model, status: Failed(reason), error: Some(reason)),
      effect.none(),
    )

    WorkspaceOpened(Ok(store)) -> #(
      Model(..model, store: Some(store), status: Preparing),
      runtime_effect.perform(
        operation: fn() { workspace_setup.seed(store) },
        outcome: WorkspaceSeeded,
      ),
    )
    WorkspaceOpened(Error(reason)) -> #(
      fail(model, "workspace open failed: " <> string.inspect(reason)),
      effect.none(),
    )

    WorkspaceSeeded(Ok(Nil)) ->
      case model.document, model.store {
        Some(document), Some(store) -> #(
          model,
          runtime_effect.start(
            document: document,
            root: watershed.root_typed(document),
            field: document_schema.workspace(),
            store: store,
            catalog: catalog.catalog(),
            context_for: fn(entry, subtree, invalidate) {
              catalog.context(document, subtree, entry.instance_id, invalidate)
            },
            started: RuntimeStarted,
            changed: RuntimeChanged,
            report: RuntimeReport,
          ),
        )
        _, _ -> #(
          fail(model, "workspace handles are not available"),
          effect.none(),
        )
      }
    WorkspaceSeeded(Error(reason)) -> #(
      fail(model, "workspace seed failed: " <> string.inspect(reason)),
      effect.none(),
    )

    RuntimeStarted(runtime) ->
      refresh(Model(..model, runtime: Some(runtime), status: Preparing))
    RuntimeChanged -> refresh(model)
    RuntimeReport(report) ->
      case report {
        component_runtime_js.DispatchFailed(_, _, reason) -> #(
          Model(
            ..model,
            error: Some("dispatch failed: " <> string.inspect(reason)),
          ),
          effect.none(),
        )
        component_runtime_js.RuntimeFailed(reason) -> #(
          Model(
            ..model,
            error: Some("runtime failed: " <> string.inspect(reason)),
          ),
          effect.none(),
        )
        component_runtime_js.Triggered(_, _)
        | component_runtime_js.LocalDelivered(_, _, _)
        | component_runtime_js.MutationSubmitted(_, _, _) -> #(
          model,
          effect.none(),
        )
      }

    TaskSelected(task_id) ->
      run_task_action(model, fn(running) {
        task_collection.select(running, task_id)
      })
    TaskCompleted(task_id) ->
      run_task_action(model, fn(running) {
        task_collection.complete(running, task_id)
      })
    RuntimeCommandFinished(Ok(Nil)) -> #(model, effect.none())
    RuntimeCommandFinished(Error(reason)) -> #(
      Model(..model, error: Some("action failed: " <> string.inspect(reason))),
      effect.none(),
    )

    NotesEditor(inner) ->
      case model.editor {
        None -> #(model, effect.none())
        Some(editor) -> {
          let #(editor, editor_effect) = textarea.update(editor, inner)
          #(
            Model(..model, editor: Some(editor)),
            effect.map(editor_effect, NotesEditor),
          )
        }
      }
  }
}

fn open_workspace(model: Model) -> #(Model, Effect(Msg)) {
  case model.connected, model.document, model.store {
    True, Some(document), None -> #(
      model,
      runtime_effect.ensure_workspace(
        document: document,
        root: watershed.root_typed(document),
        field: document_schema.workspace(),
        opened: WorkspaceOpened,
      ),
    )
    _, _, _ -> #(model, effect.none())
  }
}

fn refresh(model: Model) -> #(Model, Effect(Msg)) {
  case model.runtime {
    None -> #(model, effect.none())
    Some(runtime) -> {
      let ready =
        list.all(
          [
            catalog.task_collection_instance_id,
            catalog.notes_instance_id,
            catalog.activity_instance_id,
          ],
          fn(instance_id) {
            component_runtime_js.running(runtime, instance_id)
            |> result.is_ok
          },
        )
      let model =
        Model(..model, status: case ready {
          True -> Running
          False -> Preparing
        })
      case model.editor, ready_notes(runtime) {
        None, Some(running) -> {
          let #(editor, editor_effect) = textarea.init(notes.text(running))
          #(
            Model(..model, editor: Some(editor)),
            effect.map(editor_effect, NotesEditor),
          )
        }
        Some(editor), Some(running) ->
          case
            watershed.text_handle_of(textarea.channel(editor))
            == watershed.text_handle_of(notes.text(running))
          {
            True -> #(model, effect.none())
            False -> {
              textarea.stop(editor)
              let #(editor, editor_effect) = textarea.init(notes.text(running))
              #(
                Model(..model, editor: Some(editor)),
                effect.map(editor_effect, NotesEditor),
              )
            }
          }
        Some(editor), None -> {
          textarea.stop(editor)
          #(Model(..model, editor: None), effect.none())
        }
        None, None -> #(model, effect.none())
      }
    }
  }
}

fn ready_notes(runtime: RoomRuntime) -> Option(notes.Running) {
  case component_runtime_js.running(runtime, catalog.notes_instance_id) {
    Error(Nil) -> None
    Ok(running) ->
      case catalog.as_notes(running) {
        Ok(notes) -> Some(notes)
        Error(Nil) -> None
      }
  }
}

fn run_task_action(
  model: Model,
  action: fn(task_collection.Running) ->
    #(task_collection.Running, List(component.OutputEvent)),
) -> #(Model, Effect(Msg)) {
  case model.runtime {
    None -> #(fail(model, "component runtime is not ready"), effect.none())
    Some(runtime) -> #(
      model,
      runtime_effect.command(
        runtime,
        catalog.task_collection_instance_id,
        fn(running) {
          use tasks <- result.try(
            catalog.as_task_collection(running)
            |> result.map_error(fn(_) {
              "task action reached the wrong component"
            }),
          )
          let #(tasks, outputs) = action(tasks)
          Ok(#(catalog.TaskCollection(tasks), outputs))
        },
        RuntimeCommandFinished,
      ),
    )
  }
}

fn fail(model: Model, reason: String) -> Model {
  Model(..model, status: Failed(reason), error: Some(reason))
}

fn view(model: Model) -> Element(Msg) {
  html.main([attribute.class("room")], [
    html.header([attribute.class("room-header")], [
      html.div([], [
        html.h1([], [html.text("Project room")]),
        html.p([attribute.class("status")], [
          html.text("Tasks, notes, and activity. One workspace."),
        ]),
      ]),
      html.p(
        [
          attribute.class("status"),
          attribute.data("runtime-status", status_name(model.status)),
        ],
        [html.text(status_label(model.status))],
      ),
    ]),
    case model.error {
      Some(reason) ->
        html.p(
          [
            attribute.class("runtime-error"),
            attribute.data("runtime-error", "true"),
          ],
          [html.text(reason)],
        )
      None -> html.text("")
    },
    workspace_view(model),
  ])
}

fn workspace_view(model: Model) -> Element(Msg) {
  case model.runtime {
    None ->
      html.div([attribute.class("workspace")], [
        views.placeholder("tasks", "Preparing"),
        views.placeholder("notes", "Preparing"),
        views.placeholder("activity", "Preparing"),
      ])
    Some(runtime) ->
      html.div(
        [attribute.class("workspace")],
        component_runtime_js.layout(runtime)
          |> list.map(fn(instance_id) {
            instance_view(model, runtime, instance_id)
          }),
      )
  }
}

fn instance_view(
  model: Model,
  runtime: RoomRuntime,
  instance_id: String,
) -> Element(Msg) {
  case instance_id, component_runtime_js.running(runtime, instance_id) {
    "tasks", Ok(running) ->
      case catalog.as_task_collection(running) {
        Ok(tasks) -> views.tasks(tasks, TaskSelected, TaskCompleted)
        Error(Nil) -> views.placeholder(instance_id, "Failed")
      }
    "notes", Ok(running) ->
      case catalog.as_notes(running) {
        Ok(notes) -> views.notes(notes, model.editor, NotesEditor)
        Error(Nil) -> views.placeholder(instance_id, "Failed")
      }
    "activity", Ok(running) ->
      case catalog.as_activity(running) {
        Ok(activity) -> views.activity(activity)
        Error(Nil) -> views.placeholder(instance_id, "Failed")
      }
    _, _ ->
      views.placeholder(instance_id, lifecycle_label(runtime, instance_id))
  }
}

fn lifecycle_label(runtime: RoomRuntime, instance_id: String) -> String {
  case
    list.find(component_runtime_js.lifecycle(runtime), fn(item) {
      item.0 == instance_id
    })
  {
    Error(Nil) -> "Loading"
    Ok(#(_, state)) ->
      case state {
        component_runtime_js.Loading(_, _) -> "Loading"
        component_runtime_js.Starting(_) -> "Starting"
        component_runtime_js.Ready(_) -> "Ready"
        component_runtime_js.Unavailable(_, _) -> "Unavailable"
        component_runtime_js.Failed(_, _) -> "Failed"
      }
  }
}

fn status_name(status: Status) -> String {
  case status {
    Connecting -> "connecting"
    Preparing -> "preparing"
    Running -> "ready"
    Failed(_) -> "failed"
  }
}

fn status_label(status: Status) -> String {
  case status {
    Connecting -> "Connecting"
    Preparing -> "Preparing components"
    Running -> "Ready"
    Failed(_) -> "Failed"
  }
}
