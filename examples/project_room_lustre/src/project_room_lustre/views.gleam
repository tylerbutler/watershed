//// Lustre views for the four fixed project room component types.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}

import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

import watershed_lustre/textarea

import project_room_lustre/activity
import project_room_lustre/inspector
import project_room_lustre/task_collection

/// Draw the task collection.
pub fn tasks(
  running: task_collection.Running,
  selected_task_id: Option(String),
  peer_selections: List(#(String, String, String)),
  select: fn(String) -> msg,
  complete: fn(String) -> msg,
) -> Element(msg) {
  html.section(
    [
      attribute.class("component tasks"),
      attribute.data("component", "tasks"),
    ],
    [
      html.h2([], [html.text("Tasks")]),
      html.p([attribute.class("component-description")], [
        html.text(
          "Owns the shared task order and records. Selection stays local; completion enters the collaborative graph.",
        ),
      ]),
      html.ul(
        [attribute.class("task-list")],
        task_collection.tasks(running)
          |> list.map(fn(task) {
            let selected = selected_task_id == Some(task.task_id)
            html.li(
              [
                attribute.class(
                  "task"
                  <> case selected {
                    True -> " task-selected"
                    False -> ""
                  }
                  <> case task.completed {
                    True -> " task-complete"
                    False -> ""
                  },
                ),
                attribute.data("task-id", task.task_id),
                attribute.data("completed", case task.completed {
                  True -> "true"
                  False -> "false"
                }),
              ],
              [
                html.button(
                  [
                    attribute.class("task-title"),
                    attribute.data("action", "select-task"),
                    attribute.data("task-id", task.task_id),
                    event.on_click(select(task.task_id)),
                  ],
                  [html.text(task.title)],
                ),
                peer_markers(task.task_id, peer_selections),
                html.button(
                  [
                    attribute.data("action", "complete-task"),
                    attribute.data("task-id", task.task_id),
                    attribute.disabled(task.completed),
                    event.on_click(complete(task.task_id)),
                  ],
                  [
                    html.text(case task.completed {
                      True -> "Done"
                      False -> "Complete"
                    }),
                  ],
                ),
              ],
            )
          }),
      ),
    ],
  )
}

fn peer_markers(
  task_id: String,
  peers: List(#(String, String, String)),
) -> Element(msg) {
  html.div(
    [attribute.class("task-presence")],
    peers
      |> list.filter(fn(peer) { peer.2 == task_id })
      |> list.map(fn(peer) {
        html.span(
          [
            attribute.class("task-peer"),
            attribute.data("presence-task", task_id),
            attribute.data("task-peer", peer.0),
            attribute.style("border-color", peer.1),
            attribute.style("color", peer.1),
          ],
          [
            html.span(
              [
                attribute.class("presence-dot"),
                attribute.style("background", peer.1),
              ],
              [],
            ),
            html.text(peer.0 <> " viewing"),
          ],
        )
      }),
  )
}

/// Draw the task that this client selected.
pub fn inspector(running: inspector.Running) -> Element(msg) {
  let selected = inspector.selected(running)
  html.section(
    [
      attribute.class("component inspector"),
      attribute.data("component", "inspector"),
      attribute.data("selected-task", case selected {
        Some(task) -> task.task_id
        None -> ""
      }),
    ],
    [
      html.h2([], [html.text("Task inspector")]),
      html.p([attribute.class("component-description")], [
        html.text(
          "Receives a local input from Tasks. Your selection changes this tab and no other.",
        ),
      ]),
      case selected {
        None ->
          html.p([attribute.class("empty")], [
            html.text("Select a task to inspect it here."),
          ])
        Some(task) ->
          html.div([attribute.class("inspector-card")], [
            html.p([attribute.class("inspector-local")], [
              html.text("Local to this tab"),
            ]),
            html.h3([], [html.text(task.title)]),
            html.p([], [html.text("ID: " <> task.task_id)]),
            html.p([], [html.text("Received as a typed TaskPayload")]),
          ])
      },
    ],
  )
}

/// Draw the notes component and its shared-text editor.
pub fn notes(
  editor: Option(textarea.Model),
  editor_message: fn(textarea.Msg) -> msg,
  user_name: String,
  user_color: String,
  selected_task_id: Option(String),
  peers: List(#(String, String, Option(String))),
) -> Element(msg) {
  html.section(
    [
      attribute.class("component notes"),
      attribute.data("component", "notes"),
    ],
    [
      html.h2([], [html.text("Notes")]),
      html.p([attribute.class("component-description")], [
        html.text(
          "Owns shared text. Ephemeral presence places peer cursors over the editor.",
        ),
      ]),
      presence_roster(user_name, user_color, selected_task_id, peers),
      case editor {
        Some(editor) ->
          textarea.view(editor, [
            attribute.class("notes-editor"),
            attribute.data("notes-editor", "true"),
            attribute.rows(12),
            attribute.placeholder("Write the shared room notes"),
          ])
          |> element.map(editor_message)
        None ->
          html.p([attribute.class("placeholder")], [
            html.text("Opening shared notes…"),
          ])
      },
    ],
  )
}

fn presence_roster(
  user_name: String,
  user_color: String,
  selected_task_id: Option(String),
  peers: List(#(String, String, Option(String))),
) -> Element(msg) {
  html.div(
    [
      attribute.class("presence-roster"),
      attribute.aria_label("People in this document"),
    ],
    [
      presence_chip(
        user_name <> " (you)",
        user_name,
        user_color,
        selected_task_id,
        True,
      ),
      ..list.map(peers, fn(peer) {
        presence_chip(peer.0, peer.0, peer.1, peer.2, False)
      })
    ],
  )
}

fn presence_chip(
  label: String,
  name: String,
  color: String,
  selected_task_id: Option(String),
  local: Bool,
) -> Element(msg) {
  html.span(
    [
      attribute.class("presence-chip"),
      attribute.style("border-color", color),
      attribute.style("color", color),
      case local {
        True -> attribute.data("presence-self", name)
        False -> attribute.data("presence-peer", name)
      },
    ],
    [
      html.span(
        [attribute.class("presence-dot"), attribute.style("background", color)],
        [],
      ),
      html.text(
        label
        <> case selected_task_id {
          Some(task_id) -> " · " <> task_id
          None -> " · no task"
        },
      ),
    ],
  )
}

/// Draw the shared activity stream.
pub fn activity(running: activity.Running) -> Element(msg) {
  let entries = activity.entries(running)
  html.section(
    [
      attribute.class("component activity"),
      attribute.data("component", "activity"),
      attribute.data("entry-count", int.to_string(list.length(entries))),
    ],
    [
      html.h2([], [html.text("Activity")]),
      html.p([attribute.class("component-description")], [
        html.text(
          "Owns a shared sequence. Completed tasks arrive through its collaborative input.",
        ),
      ]),
      case entries {
        [] ->
          html.p([attribute.class("empty")], [
            html.text("Completed tasks land here."),
          ])
        _ ->
          html.ul(
            [attribute.class("activity-list")],
            entries
              |> list.map(fn(entry) {
                html.li([attribute.data("task-id", entry.task_id)], [
                  html.text(entry.title <> " completed"),
                ])
              }),
          )
      },
    ],
  )
}

/// Draw a component that has not reached the ready state.
pub fn placeholder(instance_id: String, state: String) -> Element(msg) {
  html.section(
    [
      attribute.class("component placeholder"),
      attribute.data("component", instance_id),
      attribute.data("runtime-state", state),
    ],
    [
      html.h2([], [html.text(title(instance_id))]),
      html.p([], [html.text(state)]),
    ],
  )
}

fn title(instance_id: String) -> String {
  case instance_id {
    "tasks" -> "Tasks"
    "inspector" -> "Task inspector"
    "notes" -> "Notes"
    "activity" -> "Activity"
    other -> other
  }
}
