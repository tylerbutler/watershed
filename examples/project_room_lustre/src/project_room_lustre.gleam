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
import watershed/id
import watershed/presence
import watershed/presence_js.{type Handle}
import watershed/workspace_js
import watershed_lustre
import watershed_lustre/component_runtime as runtime_effect
import watershed_lustre/textarea

import project_room_lustre/catalog
import project_room_lustre/checklist
import project_room_lustre/decision_poll
import project_room_lustre/document_schema
import project_room_lustre/governance_payload
import project_room_lustre/inspector
import project_room_lustre/notes
import project_room_lustre/ownership_slots
import project_room_lustre/room_presence.{type RoomPresence}
import project_room_lustre/tally
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
    palette_title: String,
    workspace_operation: Option(String),
    user_id: String,
    color: String,
    presence: Option(Handle(RoomPresence)),
    peers: List(presence.PresenceEntry(RoomPresence)),
    announced: Option(RoomPresence),
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
  PollVote(String)
  PollToggleResults
  PollOpened
  PollClosed
  OwnershipClaim(String)
  OwnershipRelease(String)
  OwnershipHandoff(String, governance_payload.Identity)
  OwnershipToggleDetails
  RuntimeCommandFinished(Result(Nil, component_runtime_js.RuntimeError))
  PaletteTitleChanged(String)
  AddComponent(String)
  WorkspaceOperationFinished(String, Result(Nil, workspace_setup.CreateError))
  MoveComponent(String, Int)
  RemoveComponent(String)
  ChecklistDraftChanged(String, String)
  ChecklistAdd(String)
  ChecklistRename(String, String, String)
  ChecklistRemove(String, String)
  ChecklistComplete(String, String)
  ChecklistReopen(String, String)
  TallyAdd(String, Int)
  NotesEditor(textarea.Msg)
  PresenceStarted(Handle(RoomPresence))
  PresenceEvent(presence.Event(RoomPresence))
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
      palette_title: "",
      workspace_operation: None,
      user_id: user_id,
      color: presence.color_for(user_id),
      presence: None,
      peers: [],
      announced: None,
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
    GotDocument(document) -> {
      let model = Model(..model, document: Some(document))
      let metadata = current_presence(model)
      let model = Model(..model, announced: Some(metadata))
      let #(model, workspace_effect) = open_workspace(model)
      #(
        model,
        effect.batch([
          workspace_effect,
          watershed_lustre.presence(
            document: document,
            config: presence.config(
              room_presence.encode,
              room_presence.decoder(),
            ),
            initial: metadata,
            started: PresenceStarted,
            on_event: PresenceEvent,
          ),
        ]),
      )
    }

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
            context_for: fn(entry, subtree, invalidate, emitter) {
              catalog.context(
                document,
                subtree,
                entry.instance_id,
                invalidate,
                model.user_id,
                presence.short_name(model.user_id),
                emitter,
              )
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
    PollVote(choice_id) ->
      run_poll_action(model, fn(running) {
        decision_poll.vote(running, choice_id)
      })
    PollToggleResults ->
      run_poll_action(model, fn(running) {
        decision_poll.set_results_visibility(
          running,
          case decision_poll.results_visible(running) {
            True -> governance_payload.HideResults
            False -> governance_payload.ShowResults
          },
        )
      })
    PollOpened ->
      run_poll_action(model, fn(running) {
        decision_poll.set_lifecycle(running, governance_payload.OpenPoll)
      })
    PollClosed ->
      run_poll_action(model, fn(running) {
        decision_poll.set_lifecycle(running, governance_payload.ClosePoll)
      })
    OwnershipClaim(slot_id) ->
      run_ownership_action(
        model,
        governance_payload.SlotCommand(slot_id, governance_payload.ClaimSlot),
      )
    OwnershipRelease(slot_id) ->
      run_ownership_action(
        model,
        governance_payload.SlotCommand(slot_id, governance_payload.ReleaseSlot),
      )
    OwnershipHandoff(slot_id, target) ->
      run_ownership_action(
        model,
        governance_payload.SlotCommand(
          slot_id,
          governance_payload.HandoffSlot(target),
        ),
      )
    OwnershipToggleDetails ->
      run_ownership_local_action(model, ownership_slots.toggle_details)
    RuntimeCommandFinished(Ok(Nil)) -> announce_presence(model)
    RuntimeCommandFinished(Error(reason)) -> #(
      Model(..model, error: Some("action failed: " <> string.inspect(reason))),
      effect.none(),
    )
    PaletteTitleChanged(title) -> #(
      Model(..model, palette_title: title, error: None),
      effect.none(),
    )
    AddComponent(kind) ->
      case string.trim(model.palette_title) {
        "" -> #(
          Model(..model, error: Some("component title must not be empty")),
          effect.none(),
        )
        _ ->
          case catalog.find_creation_preset(kind) {
            Error(Nil) -> #(
              Model(
                ..model,
                error: Some("component preset is not available: " <> kind),
              ),
              effect.none(),
            )
            Ok(preset) -> {
              let instance_id =
                kind
                |> string.replace("project-room/", "")
                |> fn(slug) { slug <> "-" <> id.uuid_v4() }
              perform_workspace_operation(model, instance_id, fn(store) {
                workspace_setup.create_from_preset(
                  store,
                  catalog.catalog(),
                  preset,
                  instance_id,
                  model.palette_title,
                )
              })
            }
          }
      }
    WorkspaceOperationFinished(instance_id, outcome) -> {
      let model = case model.workspace_operation == Some(instance_id) {
        True -> Model(..model, workspace_operation: None)
        False -> model
      }
      case outcome {
        Ok(Nil) -> #(
          Model(..model, palette_title: "", error: None),
          effect.none(),
        )
        Error(reason) -> #(
          Model(
            ..model,
            error: Some(
              "workspace operation failed: " <> string.inspect(reason),
            ),
          ),
          effect.none(),
        )
      }
    }
    MoveComponent(instance_id, offset) ->
      case model.runtime {
        None -> #(
          Model(..model, error: Some("component runtime is not ready")),
          effect.none(),
        )
        Some(runtime) ->
          case layout_index(component_runtime_js.layout(runtime), instance_id) {
            Error(Nil) -> #(
              Model(
                ..model,
                error: Some(
                  "component instance does not exist: " <> instance_id,
                ),
              ),
              effect.none(),
            )
            Ok(index) ->
              perform_workspace_operation(model, instance_id, fn(store) {
                workspace_js.move_instance(
                  store,
                  catalog.catalog(),
                  instance_id,
                  index + offset,
                )
                |> result.map_error(workspace_setup.WorkspaceMutation)
              })
          }
      }
    RemoveComponent(instance_id) ->
      perform_workspace_operation(model, instance_id, fn(store) {
        workspace_js.delete_instance(store, catalog.catalog(), instance_id)
        |> result.map_error(workspace_setup.WorkspaceMutation)
      })
    ChecklistDraftChanged(instance_id, draft) ->
      run_checklist_action(model, instance_id, fn(running) {
        Ok(checklist.set_draft(running, draft))
      })
    ChecklistAdd(instance_id) ->
      run_checklist_action(model, instance_id, checklist.add)
    ChecklistRename(instance_id, item_id, label) ->
      run_checklist_action(model, instance_id, fn(running) {
        checklist.rename(running, item_id, label)
      })
    ChecklistRemove(instance_id, item_id) ->
      run_checklist_action(model, instance_id, fn(running) {
        checklist.remove(running, item_id)
      })
    ChecklistComplete(instance_id, item_id) ->
      run_checklist_action(model, instance_id, fn(running) {
        checklist.complete(running, item_id)
      })
    ChecklistReopen(instance_id, item_id) ->
      run_checklist_action(model, instance_id, fn(running) {
        checklist.reopen(running, item_id)
      })
    TallyAdd(instance_id, amount) ->
      run_tally_action(model, instance_id, amount)

    NotesEditor(inner) ->
      case model.editor {
        None -> #(model, effect.none())
        Some(editor) -> {
          let #(editor, editor_effect) = textarea.update(editor, inner)
          let #(model, presence_effect) =
            announce_presence(Model(..model, editor: Some(editor)))
          #(
            model,
            effect.batch([
              effect.map(editor_effect, NotesEditor),
              presence_effect,
            ]),
          )
        }
      }

    PresenceStarted(handle) ->
      announce_presence(Model(..model, presence: Some(handle)))

    PresenceEvent(event) ->
      case event {
        presence.State(entries) | presence.Changed(_, entries) ->
          push_peers(Model(..model, peers: remote_peers(model, entries)))
        presence.Failed(presence.DecodeFailed(_, _)) -> #(model, effect.none())
        presence.Failed(presence.UnsupportedPresence) -> #(
          Model(..model, error: Some("presence unavailable on this server")),
          effect.none(),
        )
        presence.Failed(presence.Rejected(_, message)) -> #(
          Model(..model, error: Some("presence rejected: " <> message)),
          effect.none(),
        )
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
            catalog.inspector_instance_id,
            catalog.decision_poll_instance_id,
            catalog.ownership_slots_instance_id,
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
          let #(editor, peer_effect) =
            textarea.set_peers(editor, peer_cursors(model.peers))
          let #(model, presence_effect) =
            announce_presence(Model(..model, editor: Some(editor)))
          #(
            model,
            effect.batch([
              effect.map(editor_effect, NotesEditor),
              effect.map(peer_effect, NotesEditor),
              presence_effect,
            ]),
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
              let #(editor, peer_effect) =
                textarea.set_peers(editor, peer_cursors(model.peers))
              let #(model, presence_effect) =
                announce_presence(Model(..model, editor: Some(editor)))
              #(
                model,
                effect.batch([
                  effect.map(editor_effect, NotesEditor),
                  effect.map(peer_effect, NotesEditor),
                  presence_effect,
                ]),
              )
            }
          }
        Some(editor), None -> {
          textarea.stop(editor)
          announce_presence(Model(..model, editor: None))
        }
        None, None -> #(model, effect.none())
      }
    }
  }
}

fn current_presence(model: Model) -> RoomPresence {
  room_presence.RoomPresence(
    name: presence.short_name(model.user_id),
    color: model.color,
    selected_task_id: selected_task_id(model),
    cursor: case model.editor {
      Some(editor) -> textarea.cursor(editor)
      None -> None
    },
  )
}

fn announce_presence(model: Model) -> #(Model, Effect(Msg)) {
  let metadata = current_presence(model)
  case model.presence, Some(metadata) == model.announced {
    _, True -> #(model, effect.none())
    None, _ -> #(model, effect.none())
    Some(handle), False -> #(
      Model(..model, announced: Some(metadata)),
      watershed_lustre.update_presence(handle, metadata),
    )
  }
}

fn selected_task_id(model: Model) -> Option(String) {
  case model.runtime {
    None -> None
    Some(runtime) ->
      component_runtime_js.running(runtime, catalog.inspector_instance_id)
      |> result_then(catalog.as_inspector)
      |> result.map(inspector.selected)
      |> result.unwrap(None)
      |> option.map(fn(task) { task.task_id })
  }
}

fn remote_peers(
  model: Model,
  entries: List(presence.PresenceEntry(RoomPresence)),
) -> List(presence.PresenceEntry(RoomPresence)) {
  case model.presence {
    Some(handle) ->
      case presence_js.local_session(handle) {
        Some(session) -> presence.remote_entries(entries, session)
        None -> entries
      }
    None -> entries
  }
}

fn peer_cursors(
  peers: List(presence.PresenceEntry(RoomPresence)),
) -> List(textarea.Peer) {
  list.filter_map(peers, fn(peer) {
    case peer.meta.cursor {
      Some(cursor) ->
        Ok(textarea.peer(
          id: peer.session_id,
          label: peer.meta.name,
          colour: peer.meta.color,
          cursor: cursor,
        ))
      None -> Error(Nil)
    }
  })
}

fn push_peers(model: Model) -> #(Model, Effect(Msg)) {
  case model.editor {
    None -> #(model, effect.none())
    Some(editor) -> {
      let #(editor, editor_effect) =
        textarea.set_peers(editor, peer_cursors(model.peers))
      #(
        Model(..model, editor: Some(editor)),
        effect.map(editor_effect, NotesEditor),
      )
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

fn perform_workspace_operation(
  model: Model,
  instance_id: String,
  operation: fn(workspace_js.Workspace(document_schema.ProjectRoom)) ->
    Result(Nil, workspace_setup.CreateError),
) -> #(Model, Effect(Msg)) {
  case model.store {
    None -> #(
      Model(..model, error: Some("component workspace is not ready")),
      effect.none(),
    )
    Some(store) -> #(
      Model(..model, workspace_operation: Some(instance_id), error: None),
      runtime_effect.perform(
        operation: fn() { operation(store) },
        outcome: fn(outcome) {
          WorkspaceOperationFinished(instance_id, outcome)
        },
      ),
    )
  }
}

fn layout_index(layout: List(String), instance_id: String) -> Result(Int, Nil) {
  list.index_fold(layout, Error(Nil), fn(found, candidate, index) {
    case found, candidate == instance_id {
      Ok(_), _ -> found
      Error(Nil), True -> Ok(index)
      Error(Nil), False -> Error(Nil)
    }
  })
}

fn run_task_action(
  model: Model,
  action: fn(task_collection.Running) ->
    #(task_collection.Running, List(component.OutputEvent)),
) -> #(Model, Effect(Msg)) {
  run_component_action(model, catalog.task_collection_instance_id, fn(running) {
    use tasks <- result.try(
      catalog.as_task_collection(running)
      |> result.map_error(fn(_) { "task action reached the wrong component" }),
    )
    let #(tasks, outputs) = action(tasks)
    Ok(#(catalog.TaskCollection(tasks), outputs))
  })
}

fn run_poll_action(
  model: Model,
  action: fn(decision_poll.Running) ->
    Result(#(decision_poll.Running, List(component.OutputEvent)), String),
) -> #(Model, Effect(Msg)) {
  run_component_action(model, catalog.decision_poll_instance_id, fn(running) {
    use poll <- result.try(
      catalog.as_decision_poll(running)
      |> result.map_error(fn(_) { "poll action reached the wrong component" }),
    )
    use next <- result.try(action(poll))
    Ok(#(catalog.DecisionPoll(next.0), next.1))
  })
}

fn run_ownership_action(
  model: Model,
  command: governance_payload.SlotCommand,
) -> #(Model, Effect(Msg)) {
  run_ownership_local_action(model, fn(running) {
    ownership_slots.submit(running, command)
  })
}

fn run_ownership_local_action(
  model: Model,
  action: fn(ownership_slots.Running) ->
    Result(#(ownership_slots.Running, List(component.OutputEvent)), String),
) -> #(Model, Effect(Msg)) {
  run_component_action(model, catalog.ownership_slots_instance_id, fn(running) {
    use ownership <- result.try(
      catalog.as_ownership_slots(running)
      |> result.map_error(fn(_) {
        "ownership action reached the wrong component"
      }),
    )
    use next <- result.try(action(ownership))
    Ok(#(catalog.OwnershipSlots(next.0), next.1))
  })
}

fn run_checklist_action(
  model: Model,
  instance_id: String,
  action: fn(checklist.Running) ->
    Result(#(checklist.Running, List(component.OutputEvent)), String),
) -> #(Model, Effect(Msg)) {
  run_component_action(model, instance_id, fn(running) {
    use checklist <- result.try(
      catalog.as_checklist(running)
      |> result.map_error(fn(_) {
        "checklist action reached the wrong component"
      }),
    )
    action(checklist)
    |> result.map(fn(next) { #(catalog.Checklist(next.0), next.1) })
  })
}

fn run_tally_action(
  model: Model,
  instance_id: String,
  amount: Int,
) -> #(Model, Effect(Msg)) {
  run_component_action(model, instance_id, fn(running) {
    use tally <- result.try(
      catalog.as_tally(running)
      |> result.map_error(fn(_) { "tally action reached the wrong component" }),
    )
    tally.add(tally, amount)
    |> result.map(fn(next) { #(catalog.Tally(next.0), next.1) })
  })
}

fn run_component_action(
  model: Model,
  instance_id: String,
  action: fn(catalog.Running) ->
    Result(#(catalog.Running, List(component.OutputEvent)), String),
) -> #(Model, Effect(Msg)) {
  case model.runtime {
    None -> #(fail(model, "component runtime is not ready"), effect.none())
    Some(runtime) -> #(
      model,
      runtime_effect.command(
        runtime,
        instance_id,
        action,
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
          html.text(
            "Tasks, poll, ownership, notes, and activity. One workspace.",
          ),
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
    demo_guide(),
    views.palette(
      model.palette_title,
      catalog.creation_presets(),
      palette_disabled(model),
      PaletteTitleChanged,
      AddComponent,
    ),
    workspace_view(model),
  ])
}

fn palette_disabled(model: Model) -> Bool {
  case model.store, model.workspace_operation {
    Some(_), None -> False
    _, _ -> True
  }
}

fn demo_guide() -> Element(msg) {
  html.section([attribute.class("demo-guide")], [
    html.h2([], [html.text("What this demo shows")]),
    html.p([], [
      html.text(
        "One runtime starts six typed components from a catalog. Local inputs control one tab, presence shares awareness, and collaborative inputs change durable data.",
      ),
    ]),
    html.ol([], [
      html.li([], [
        html.strong([], [html.text("Open this URL in two tabs. ")]),
        html.text("Both tabs connect to the same project-room document."),
      ]),
      html.li([], [
        html.strong([], [html.text("Select a task. ")]),
        html.text(
          "Tasks sends a local event to Inspector. Each tab keeps its own selected task.",
        ),
      ]),
      html.li([], [
        html.strong([], [html.text("Compare the other tab. ")]),
        html.text(
          "A presence marker shows what your peer selected without changing your Inspector.",
        ),
      ]),
      html.li([], [
        html.strong([], [html.text("Complete a task. ")]),
        html.text(
          "Tasks sends a collaborative event to Activity. Both tabs show the completed task and one new activity row.",
        ),
      ]),
      html.li([], [
        html.strong([], [html.text("Approve a choice in both tabs. ")]),
        html.text(
          "OR-set ballots converge, and a Claims latch sends one threshold entry to Activity. Results visibility stays local.",
        ),
      ]),
      html.li([], [
        html.strong([], [html.text("Claim and hand off a role. ")]),
        html.text(
          "Claims resolves ownership after sequencing. Compare-and-set protects release and handoff from stale owners.",
        ),
      ]),
      html.li([], [
        html.strong([], [html.text("Edit the notes. ")]),
        html.text("The shared text converges in both tabs."),
      ]),
      html.li([], [
        html.strong([], [html.text("Move your cursor in Notes. ")]),
        html.text(
          "The other tab draws your name and caret at the same anchored position.",
        ),
      ]),
    ]),
    html.div([attribute.class("routes")], [
      html.p([attribute.class("route route-local")], [
        html.span([attribute.class("route-kind")], [html.text("LOCAL")]),
        html.strong([], [html.text("Tasks selected -> Inspector")]),
        html.span([attribute.class("route-detail")], [
          html.text("Independent task detail in each tab"),
        ]),
      ]),
      html.p([attribute.class("route route-shared")], [
        html.span([attribute.class("route-kind")], [html.text("SHARED")]),
        html.strong([], [html.text("Tasks completed -> Activity append")]),
        html.span([attribute.class("route-detail")], [
          html.text("Collaborative state replicated to both tabs"),
        ]),
      ]),
      html.p([attribute.class("route route-shared")], [
        html.span([attribute.class("route-kind")], [html.text("SHARED")]),
        html.strong([], [html.text("Poll threshold -> Activity append")]),
        html.span([attribute.class("route-detail")], [
          html.text("Claims turns concurrent observation into one output"),
        ]),
      ]),
      html.p([attribute.class("route route-shared")], [
        html.span([attribute.class("route-kind")], [html.text("SHARED")]),
        html.strong([], [html.text("Ownership changed -> Activity append")]),
        html.span([attribute.class("route-detail")], [
          html.text("Only accepted ownership changes enter the stream"),
        ]),
      ]),
      html.p([attribute.class("route route-presence")], [
        html.span([attribute.class("route-kind")], [html.text("PRESENCE")]),
        html.strong([], [html.text("Selection and cursor -> peer UI")]),
        html.span([attribute.class("route-detail")], [
          html.text("Transient awareness that cannot control your tab"),
        ]),
      ]),
    ]),
  ])
}

fn workspace_view(model: Model) -> Element(Msg) {
  case model.runtime {
    None ->
      html.div([attribute.class("workspace")], [
        views.placeholder("tasks", "Preparing"),
        views.placeholder("inspector", "Preparing"),
        views.placeholder("poll", "Preparing"),
        views.placeholder("ownership", "Preparing"),
        views.placeholder("notes", "Preparing"),
        views.placeholder("activity", "Preparing"),
      ])
    Some(runtime) -> {
      let layout = component_runtime_js.layout(runtime)
      let count = list.length(layout)
      html.div(
        [attribute.class("workspace")],
        layout
          |> list.index_map(fn(instance_id, index) {
            instance_view(model, runtime, instance_id, index, count)
          }),
      )
    }
  }
}

fn instance_view(
  model: Model,
  runtime: RoomRuntime,
  instance_id: String,
  index: Int,
  count: Int,
) -> Element(Msg) {
  let component_view = case component_runtime_js.running(runtime, instance_id) {
    Error(Nil) ->
      views.placeholder(instance_id, lifecycle_label(runtime, instance_id))
    Ok(running) ->
      case instance_id, running {
        "tasks", catalog.TaskCollection(tasks) ->
          views.tasks(
            tasks,
            selected_task_id(model),
            list.filter_map(model.peers, fn(peer) {
              case peer.meta.selected_task_id {
                Some(task_id) -> Ok(#(peer.meta.name, peer.meta.color, task_id))
                None -> Error(Nil)
              }
            }),
            TaskSelected,
            TaskCompleted,
          )
        "inspector", catalog.Inspector(inspector) -> views.inspector(inspector)
        "poll", catalog.DecisionPoll(poll) ->
          views.decision_poll(
            poll,
            PollVote,
            PollToggleResults,
            PollOpened,
            PollClosed,
          )
        "ownership", catalog.OwnershipSlots(ownership) ->
          views.ownership_slots(
            ownership,
            model.user_id,
            list.map(model.peers, fn(peer) {
              governance_payload.Identity(peer.key, peer.meta.name)
            }),
            OwnershipClaim,
            OwnershipRelease,
            OwnershipHandoff,
            OwnershipToggleDetails,
          )
        "notes", catalog.Notes(_) ->
          views.notes(
            model.editor,
            NotesEditor,
            presence.short_name(model.user_id),
            model.color,
            selected_task_id(model),
            list.map(model.peers, fn(peer) {
              #(peer.meta.name, peer.meta.color, peer.meta.selected_task_id)
            }),
          )
        "activity", catalog.Activity(activity) -> views.activity(activity)
        _, catalog.Checklist(checklist) ->
          views.checklist(
            instance_id,
            checklist,
            fn(draft) { ChecklistDraftChanged(instance_id, draft) },
            ChecklistAdd(instance_id),
            fn(item_id, label) { ChecklistRename(instance_id, item_id, label) },
            fn(item_id) { ChecklistRemove(instance_id, item_id) },
            fn(item_id) { ChecklistComplete(instance_id, item_id) },
            fn(item_id) { ChecklistReopen(instance_id, item_id) },
          )
        _, catalog.Tally(tally) ->
          views.tally(instance_id, tally, fn(amount) {
            TallyAdd(instance_id, amount)
          })
        _, _ -> views.placeholder(instance_id, "Failed")
      }
  }
  case fixed_host_instance(instance_id) {
    True -> component_view
    False ->
      html.div([attribute.class("workspace-instance")], [
        component_view,
        views.instance_controls(
          instance_id,
          index,
          count,
          model.workspace_operation == Some(instance_id),
          fn(offset) { MoveComponent(instance_id, offset) },
          RemoveComponent(instance_id),
        ),
      ])
  }
}

fn fixed_host_instance(instance_id: String) -> Bool {
  list.contains(
    [
      "tasks",
      "inspector",
      "poll",
      "ownership",
      "notes",
      "activity",
      "checklist",
      "tally",
    ],
    instance_id,
  )
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

fn result_then(
  result: Result(a, Nil),
  next: fn(a) -> Result(b, Nil),
) -> Result(b, Nil) {
  case result {
    Ok(value) -> next(value)
    Error(Nil) -> Error(Nil)
  }
}
