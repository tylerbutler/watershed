//// Lustre views for the project room components.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}

import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

import watershed_lustre/textarea

import project_room_lustre/activity
import project_room_lustre/catalog
import project_room_lustre/checklist
import project_room_lustre/component_event
import project_room_lustre/decision_poll
import project_room_lustre/governance_payload
import project_room_lustre/inspector
import project_room_lustre/ownership_slots
import project_room_lustre/tally
import project_room_lustre/task_collection

/// Draw the title-only component palette.
pub fn palette(
  title: String,
  presets: List(catalog.CreationPreset(root)),
  disabled: Bool,
  title_changed: fn(String) -> msg,
  add: fn(String) -> msg,
) -> Element(msg) {
  html.section([attribute.class("component-palette")], [
    html.h2([], [html.text("Add a component")]),
    html.input([
      attribute.data("palette-title", ""),
      attribute.aria_label("Component title"),
      attribute.value(title),
      attribute.placeholder("Component title"),
      attribute.disabled(disabled),
      event.on_input(title_changed),
    ]),
    html.div(
      [attribute.class("component-actions")],
      list.map(presets, fn(preset) {
        let catalog.CreationPreset(label:, kind:, ..) = preset
        html.button(
          [
            attribute.data("action", "add-component"),
            attribute.data("component-kind", kind),
            attribute.disabled(disabled),
            event.on_click(add(kind)),
          ],
          [html.text("Add " <> label)],
        )
      }),
    ),
  ])
}

/// Draw controls for one runtime-created instance.
pub fn instance_controls(
  instance_id: String,
  index: Int,
  count: Int,
  disabled: Bool,
  move: fn(Int) -> msg,
  remove: msg,
) -> Element(msg) {
  html.div(
    [
      attribute.class("instance-controls"),
      attribute.data("controls-for", instance_id),
    ],
    [
      html.button(
        [
          attribute.data("action", "move-component-up"),
          attribute.disabled(disabled || index == 0),
          event.on_click(move(-1)),
        ],
        [html.text("Move up")],
      ),
      html.button(
        [
          attribute.data("action", "move-component-down"),
          attribute.disabled(disabled || index == count - 1),
          event.on_click(move(1)),
        ],
        [html.text("Move down")],
      ),
      html.button(
        [
          attribute.data("action", "remove-component"),
          attribute.disabled(disabled),
          event.on_click(remove),
        ],
        [html.text("Remove")],
      ),
    ],
  )
}

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

/// Draw the shared approval poll and this tab's local result controls.
pub fn decision_poll(
  running: decision_poll.Running,
  vote: fn(String) -> msg,
  toggle_results: msg,
  open_poll: msg,
  close_poll: msg,
) -> Element(msg) {
  let config = decision_poll.config(running)
  let open = decision_poll.is_open(running)
  let visible = decision_poll.results_visible(running)
  html.section(
    [
      attribute.class("component poll"),
      attribute.data("component", "poll"),
      attribute.data("poll-open", bool_string(open)),
      attribute.data("results-visible", bool_string(visible)),
    ],
    [
      html.h2([], [html.text(config.title)]),
      html.p([attribute.class("component-description")], [
        html.text(
          "Approvals merge through an OR-set. A Claims latch emits each threshold once.",
        ),
      ]),
      html.h3([], [html.text(config.question)]),
      html.p([attribute.class("poll-state")], [
        html.text(case open {
          True -> "Open"
          False -> "Closed"
        }),
      ]),
      html.ul(
        [attribute.class("poll-choices")],
        list.map(config.choices, fn(choice) {
          let approved = decision_poll.approved_by_local(running, choice.id)
          let count = decision_poll.approval_count(running, choice.id)
          let reached = decision_poll.threshold_reached(running, choice.id)
          let pending = decision_poll.pending_threshold(running, choice.id)
          html.li(
            [
              attribute.data("choice-id", choice.id),
              attribute.data("approved", bool_string(approved)),
              attribute.data("threshold-reached", bool_string(reached)),
              attribute.data("threshold-pending", bool_string(pending)),
              attribute.data("approval-count", case visible {
                True -> int.to_string(count)
                False -> ""
              }),
            ],
            [
              html.button(
                [
                  attribute.data("action", "toggle-approval"),
                  attribute.data("choice-id", choice.id),
                  attribute.disabled(!open),
                  event.on_click(vote(choice.id)),
                ],
                [
                  html.text(case approved {
                    True -> "Retract " <> choice.label
                    False -> "Approve " <> choice.label
                  }),
                ],
              ),
              case visible {
                True ->
                  html.span([attribute.data("poll-result", choice.id)], [
                    html.text(
                      int.to_string(count)
                      <> " approval"
                      <> case count == 1 {
                        True -> ""
                        False -> "s"
                      },
                    ),
                  ])
                False -> html.text("")
              },
              case pending, reached {
                True, _ ->
                  html.span(
                    [attribute.data("poll-threshold-state", "pending")],
                    [
                      html.text("Threshold pending"),
                    ],
                  )
                False, True ->
                  html.span(
                    [attribute.data("poll-threshold-state", "reached")],
                    [
                      html.text("Threshold reached"),
                    ],
                  )
                False, False -> html.text("")
              },
            ],
          )
        }),
      ),
      html.div([attribute.class("component-actions")], [
        html.button(
          [
            attribute.data("action", "toggle-results"),
            event.on_click(toggle_results),
          ],
          [
            html.text(case visible {
              True -> "Hide results"
              False -> "Show results"
            }),
          ],
        ),
        html.button(
          [
            attribute.data("action", "open-poll"),
            attribute.disabled(open),
            event.on_click(open_poll),
          ],
          [html.text("Open poll")],
        ),
        html.button(
          [
            attribute.data("action", "close-poll"),
            attribute.disabled(!open),
            event.on_click(close_poll),
          ],
          [html.text("Close poll")],
        ),
      ]),
      case decision_poll.local_error(running) {
        Some(reason) ->
          html.p([attribute.data("poll-error", "true")], [html.text(reason)])
        None -> html.text("")
      },
    ],
  )
}

/// Draw shared ownership and local owner details.
pub fn ownership_slots(
  running: ownership_slots.Running,
  local_id: String,
  peers: List(governance_payload.Identity),
  claim: fn(String) -> msg,
  release: fn(String) -> msg,
  handoff: fn(String, governance_payload.Identity) -> msg,
  toggle_details: msg,
) -> Element(msg) {
  let config = ownership_slots.config(running)
  let revealed = ownership_slots.details_revealed(running)
  html.section(
    [
      attribute.class("component ownership"),
      attribute.data("component", "ownership"),
      attribute.data("owner-details-visible", bool_string(revealed)),
    ],
    [
      html.h2([], [html.text(config.title)]),
      html.p([attribute.class("component-description")], [
        html.text(
          "Claims resolve first-writer-wins. Release and handoff use compare-and-set.",
        ),
      ]),
      html.ul(
        [attribute.class("ownership-slots")],
        list.map(config.slots, fn(slot) {
          let current = ownership_slots.owner(running, slot.id)
          let pending = ownership_slots.pending(running, slot.id)
          let local_owner = case current {
            Some(owner) -> owner.id == local_id
            None -> False
          }
          html.li(
            [
              attribute.data("slot-id", slot.id),
              attribute.data("slot-state", case current {
                Some(_) -> "occupied"
                None -> "vacant"
              }),
              attribute.data("slot-pending", bool_string(pending)),
              attribute.data("owner-label", case current {
                Some(owner) -> owner.label
                None -> ""
              }),
              attribute.data("owner-id", case current, revealed {
                Some(owner), True -> owner.id
                _, _ -> ""
              }),
            ],
            [
              html.strong([], [html.text(slot.label)]),
              html.span([attribute.data("slot-owner", slot.id)], [
                html.text(case current {
                  Some(owner) -> owner.label
                  None -> "Vacant"
                }),
              ]),
              case pending, current, local_owner {
                True, _, _ ->
                  html.span([attribute.data("ownership-pending", slot.id)], [
                    html.text("Resolving…"),
                  ])
                False, None, _ ->
                  html.button(
                    [
                      attribute.data("action", "claim-slot"),
                      attribute.data("slot-id", slot.id),
                      event.on_click(claim(slot.id)),
                    ],
                    [html.text("Claim")],
                  )
                False, Some(_), True ->
                  html.div([attribute.class("ownership-actions")], [
                    html.button(
                      [
                        attribute.data("action", "release-slot"),
                        attribute.data("slot-id", slot.id),
                        event.on_click(release(slot.id)),
                      ],
                      [html.text("Release")],
                    ),
                    ..list.map(peers, fn(peer) {
                      html.button(
                        [
                          attribute.data("action", "handoff-slot"),
                          attribute.data("slot-id", slot.id),
                          attribute.data("target-id", peer.id),
                          event.on_click(handoff(slot.id, peer)),
                        ],
                        [html.text("Hand to " <> peer.label)],
                      )
                    })
                  ])
                False, Some(_), False -> html.text("")
              },
              case revealed {
                True ->
                  html.div([attribute.data("owner-details", slot.id)], [
                    html.p([], [
                      html.text(case current {
                        Some(owner) -> "Durable ID: " <> owner.id
                        None -> "No current owner ID"
                      }),
                    ]),
                    resolution_view(ownership_slots.last_resolution(
                      running,
                      slot.id,
                    )),
                  ])
                False -> html.text("")
              },
            ],
          )
        }),
      ),
      html.button(
        [
          attribute.data("action", "toggle-owner-details"),
          event.on_click(toggle_details),
        ],
        [
          html.text(case revealed {
            True -> "Hide owner details"
            False -> "Reveal owner details"
          }),
        ],
      ),
    ],
  )
}

fn resolution_view(
  resolved: Option(governance_payload.ClaimResolved),
) -> Element(msg) {
  case resolved {
    None ->
      html.p([attribute.data("last-claim-outcome", "")], [
        html.text("No local attempt"),
      ])
    Some(value) -> {
      let label = case value.resolution {
        governance_payload.Accepted -> "accepted"
        governance_payload.Lost -> "lost"
        governance_payload.Aborted -> "aborted"
      }
      html.p([attribute.data("last-claim-outcome", label)], [
        html.text("Last local attempt: " <> label),
      ])
    }
  }
}

fn bool_string(value: Bool) -> String {
  case value {
    True -> "true"
    False -> "false"
  }
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
            entries |> list.map(activity_entry),
          )
      },
    ],
  )
}

fn activity_entry(entry: activity.Entry) -> Element(msg) {
  case entry {
    activity.TaskCompleted(task) ->
      html.li(
        [
          attribute.data("entry-kind", "task-completed"),
          attribute.data("task-id", task.task_id),
        ],
        [html.text(task.title <> " completed")],
      )
    activity.PollThresholdReached(threshold) ->
      html.li(
        [
          attribute.data("entry-kind", "poll-threshold"),
          attribute.data("choice-id", threshold.choice_id),
        ],
        [
          html.text(
            threshold.choice_label
            <> " reached "
            <> int.to_string(threshold.approvals)
            <> " approvals",
          ),
        ],
      )
    activity.OwnershipAccepted(change) ->
      html.li(
        [
          attribute.data("entry-kind", "ownership-change"),
          attribute.data("slot-id", change.slot_id),
        ],
        [
          html.text(case change.owner {
            Some(owner) -> change.slot_label <> " assigned to " <> owner.label
            None -> change.slot_label <> " released"
          }),
        ],
      )
    activity.ComponentEvent(event) ->
      html.li(
        [
          attribute.data("entry-kind", "component-event"),
          attribute.data("source-instance-id", event.source_instance_id),
          attribute.data("source-kind", event.source_kind),
          attribute.data("source-title", event.source_title),
          attribute.data("action", case event.action {
            component_event.Published -> "published"
            component_event.EntryChanged -> "entry-changed"
            component_event.FolderChanged -> "folder-changed"
            component_event.AgreementAccepted -> "agreement-accepted"
          }),
        ],
        [html.text(event.source_title <> ": " <> event.detail)],
      )
  }
}

/// Draw one checklist instance.
pub fn checklist(
  instance_id: String,
  running: checklist.Running,
  draft_changed: fn(String) -> msg,
  add: msg,
  rename: fn(String, String) -> msg,
  remove: fn(String) -> msg,
  complete: fn(String) -> msg,
  reopen: fn(String) -> msg,
) -> Element(msg) {
  let config = checklist.config(running)
  html.section(
    [
      attribute.class("component checklist"),
      attribute.data("component", instance_id),
      attribute.data("component-kind", "checklist"),
      attribute.data("instance-id", instance_id),
    ],
    [
      html.h2([], [html.text(config.title)]),
      html.p([attribute.class("component-description")], [
        html.text(
          "Items keep their order. Completion merges across every client.",
        ),
      ]),
      html.div([attribute.class("component-actions")], [
        html.input([
          attribute.data("checklist-draft", ""),
          attribute.aria_label("New checklist item"),
          attribute.value(checklist.draft(running)),
          attribute.placeholder("New item"),
          event.on_input(draft_changed),
        ]),
        html.button(
          [attribute.data("action", "add-checklist-item"), event.on_click(add)],
          [html.text("Add item")],
        ),
      ]),
      html.ul(
        [attribute.class("checklist-items")],
        checklist.items(running)
          |> list.map(fn(item) {
            let completed = checklist.completed(running, item.id)
            html.li([attribute.data("item-id", item.id)], [
              html.input([
                attribute.data("item-id", item.id),
                attribute.aria_label("Rename " <> item.label),
                attribute.value(item.label),
                event.on_input(fn(label) { rename(item.id, label) }),
              ]),
              html.button(
                [
                  attribute.data("action", case completed {
                    True -> "reopen-checklist-item"
                    False -> "complete-checklist-item"
                  }),
                  attribute.data("item-id", item.id),
                  event.on_click(case completed {
                    True -> reopen(item.id)
                    False -> complete(item.id)
                  }),
                ],
                [
                  html.text(case completed {
                    True -> "Reopen"
                    False -> "Complete"
                  }),
                ],
              ),
              html.button(
                [
                  attribute.data("action", "remove-checklist-item"),
                  attribute.data("item-id", item.id),
                  event.on_click(remove(item.id)),
                ],
                [html.text("Remove")],
              ),
            ])
          }),
      ),
    ],
  )
}

/// Draw one tally instance.
pub fn tally(
  instance_id: String,
  running: tally.Running,
  add: fn(Int) -> msg,
) -> Element(msg) {
  let config = tally.config(running)
  html.section(
    [
      attribute.class("component tally"),
      attribute.data("component", instance_id),
      attribute.data("component-kind", "tally"),
      attribute.data("instance-id", instance_id),
    ],
    [
      html.h2([], [html.text(config.title)]),
      html.p([attribute.class("component-description")], [
        html.text(
          "The value merges increments and decrements from all clients.",
        ),
      ]),
      html.p(
        [
          attribute.class("tally-value"),
          attribute.data("tally-value", int.to_string(tally.value(running))),
          attribute.data("tally-target", int.to_string(config.target)),
        ],
        [
          html.strong([], [html.text(int.to_string(tally.value(running)))]),
          html.text(" / " <> int.to_string(config.target)),
        ],
      ),
      html.div([attribute.class("component-actions")], [
        html.button(
          [attribute.data("action", "decrement-tally"), event.on_click(add(-1))],
          [html.text("−1")],
        ),
        html.button(
          [attribute.data("action", "increment-tally"), event.on_click(add(1))],
          [html.text("+1")],
        ),
      ]),
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

pub fn instance_error(instance_id: String, reason: String) -> Element(msg) {
  html.p(
    [
      attribute.class("runtime-error"),
      attribute.data("instance-error", instance_id),
    ],
    [html.text(reason)],
  )
}

fn title(instance_id: String) -> String {
  case instance_id {
    "tasks" -> "Tasks"
    "inspector" -> "Task inspector"
    "poll" -> "Decision poll"
    "ownership" -> "Ownership slots"
    "notes" -> "Notes"
    "activity" -> "Activity"
    other -> other
  }
}
