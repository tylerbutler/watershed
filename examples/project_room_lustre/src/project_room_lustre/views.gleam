//// Lustre views for the three fixed project room component types.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}

import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

import watershed_lustre/textarea

import project_room_lustre/activity
import project_room_lustre/notes
import project_room_lustre/task_collection

/// Draw the task collection.
pub fn tasks(
  running: task_collection.Running,
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
      html.ul(
        [attribute.class("task-list")],
        task_collection.tasks(running)
          |> list.map(fn(task) {
            let selected =
              task_collection.selected_task_id(running) == Some(task.task_id)
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

/// Draw the notes component and its shared-text editor.
pub fn notes(
  running: notes.Running,
  editor: Option(textarea.Model),
  editor_message: fn(textarea.Msg) -> msg,
) -> Element(msg) {
  let focus = case notes.focused_task_id(running) {
    Some(task_id) -> "Focused on " <> task_id
    None -> "Select a task in this tab"
  }
  html.section(
    [
      attribute.class("component notes"),
      attribute.data("component", "notes"),
      attribute.data("focused-task", case notes.focused_task_id(running) {
        Some(task_id) -> task_id
        None -> ""
      }),
    ],
    [
      html.h2([], [html.text("Notes")]),
      html.p(
        [
          attribute.class("notes-context"),
          attribute.data("notes-context", "true"),
        ],
        [html.text(focus)],
      ),
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
    "notes" -> "Notes"
    "activity" -> "Activity"
    other -> other
  }
}
