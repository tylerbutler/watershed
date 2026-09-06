//// Runtime catalog for the headless project room components.

import gleam/json.{type Json}
import gleam/list
import gleam/result

import watershed
import watershed/component
import watershed/port
import watershed/port_graph
import watershed/transport_js

import project_room_lustre/activity
import project_room_lustre/checklist
import project_room_lustre/component_event
import project_room_lustre/decision_poll
import project_room_lustre/governance_payload
import project_room_lustre/inspector
import project_room_lustre/notes
import project_room_lustre/ownership_slots
import project_room_lustre/payload
import project_room_lustre/room_agreement
import project_room_lustre/tally
import project_room_lustre/tally_payload
import project_room_lustre/task_collection

/// The shared runtime context for one component instance.
pub opaque type Context(root) {
  Context(
    document: watershed.Document(root),
    subtree: watershed.SharedMap,
    instance_id: String,
    invalidate: fn() -> Nil,
    participant_id: String,
    participant_label: String,
    emitter: component.OutputEmitter,
  )
}

/// The running state for a project room component.
pub type Running {
  TaskCollection(task_collection.Running)
  Inspector(inspector.Running)
  DecisionPoll(decision_poll.Running)
  OwnershipSlots(ownership_slots.Running)
  Notes(notes.Running)
  Activity(activity.Running)
  Checklist(checklist.Running)
  Tally(tally.Running)
  RoomAgreement(
    running: room_agreement.Running,
    refresh_pending: transport_js.Cell(Bool),
  )
}

/// A component that the room can create at runtime.
pub type CreationPreset(root) {
  CreationPreset(
    label: String,
    kind: String,
    version: Int,
    config: fn(String) -> Json,
    initialize: fn(watershed.Document(root), watershed.SharedMap) ->
      Result(Nil, String),
  )
}

pub const task_collection_kind = "project-room/task-collection"

pub const notes_kind = "project-room/notes"

pub const activity_kind = "project-room/activity"

pub const inspector_kind = "project-room/inspector"

pub const decision_poll_kind = "project-room/decision-poll"

pub const ownership_slots_kind = "project-room/ownership-slots"

pub const checklist_kind = "project-room/checklist"

pub const tally_kind = "project-room/tally"

pub const room_agreement_kind = "project-room/room-agreement"

pub const task_collection_version = 1

pub const notes_version = 1

pub const activity_version = 1

pub const inspector_version = 1

pub const decision_poll_version = 1

pub const ownership_slots_version = 1

pub const checklist_version = 1

pub const tally_version = 1

pub const room_agreement_version = 1

pub const task_collection_instance_id = "tasks"

pub const notes_instance_id = "notes"

pub const activity_instance_id = "activity"

pub const inspector_instance_id = "inspector"

pub const decision_poll_instance_id = "poll"

pub const ownership_slots_instance_id = "ownership"

pub const checklist_instance_id = "checklist"

pub const tally_instance_id = "tally"

pub const room_agreement_instance_id = "agreement"

pub const selected_inspect_connection_id = "tasks-selected-to-inspector"

pub const completed_append_connection_id = "tasks-completed-to-activity-append"

pub const threshold_append_connection_id = "poll-threshold-to-activity-append"

pub const ownership_append_connection_id = "ownership-changed-to-activity-append"

pub const checklist_tally_connection_id = "checklist-completed-to-tally-add"

pub const agreement_activity_connection_id = "agreement-accepted-to-activity"

pub fn context(
  document: watershed.Document(root),
  subtree: watershed.SharedMap,
  instance_id: String,
  invalidate: fn() -> Nil,
  participant_id: String,
  participant_label: String,
  emitter: component.OutputEmitter,
) -> Context(root) {
  Context(
    document:,
    subtree:,
    instance_id:,
    invalidate:,
    participant_id:,
    participant_label:,
    emitter:,
  )
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

pub fn participant_id(context: Context(root)) -> String {
  context.participant_id
}

pub fn participant_label(context: Context(root)) -> String {
  context.participant_label
}

pub fn emitter(context: Context(root)) -> component.OutputEmitter {
  context.emitter
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

pub fn inspector_config() -> inspector.Config {
  inspector.Config(title: "Task inspector")
}

pub fn decision_poll_config() -> decision_poll.Config {
  decision_poll.Config(
    title: "Decision poll",
    question: "What should the room prioritize next?",
    choices: [
      decision_poll.Choice("customer-research", "Customer research"),
      decision_poll.Choice("delivery-plan", "Delivery plan"),
      decision_poll.Choice("technical-risk", "Technical risk"),
    ],
    threshold: 2,
  )
}

pub fn ownership_slots_config() -> ownership_slots.Config {
  ownership_slots.Config(title: "Ownership slots", slots: [
    ownership_slots.Slot("facilitator", "Facilitator"),
    ownership_slots.Slot("note-taker", "Note taker"),
    ownership_slots.Slot("reviewer", "Reviewer"),
  ])
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

pub fn inspector_config_json() -> Json {
  inspector.encode_config(inspector_config())
}

pub fn decision_poll_config_json() -> Json {
  decision_poll.encode_config(decision_poll_config())
}

pub fn ownership_slots_config_json() -> Json {
  ownership_slots.encode_config(ownership_slots_config())
}

pub fn creation_presets() -> List(CreationPreset(root)) {
  [
    CreationPreset(
      label: "Checklist",
      kind: checklist_kind,
      version: checklist_version,
      config: fn(title) {
        checklist.encode_config(checklist.Config(title: title))
      },
      initialize: checklist.initialize,
    ),
    CreationPreset(
      label: "Tally",
      kind: tally_kind,
      version: tally_version,
      config: fn(title) {
        tally.encode_config(tally.Config(title: title, target: 10))
      },
      initialize: tally.initialize,
    ),
    CreationPreset(
      label: "Room Agreement",
      kind: room_agreement_kind,
      version: room_agreement_version,
      config: fn(title) {
        room_agreement.encode_config(room_agreement.Config(title))
      },
      initialize: room_agreement.initialize,
    ),
  ]
}

pub fn find_creation_preset(kind: String) -> Result(CreationPreset(root), Nil) {
  list.find(creation_presets(), fn(preset) { preset.kind == kind })
}

pub fn catalog() -> component.Catalog(Context(root), Running) {
  let assert Ok(full) =
    list.try_fold(
      descriptors(),
      component.new_catalog(),
      fn(catalog, descriptor) { component.register(catalog, descriptor) },
    )
  full
}

pub fn descriptors() -> List(component.Descriptor(Context(root), Running)) {
  [
    task_collection_descriptor(),
    inspector_descriptor(),
    decision_poll_descriptor(),
    ownership_slots_descriptor(),
    notes_descriptor(),
    activity_descriptor(),
    checklist_descriptor(),
    tally_descriptor(),
    room_agreement_descriptor(),
  ]
}

pub fn persisted_connections() -> List(port_graph.Connection) {
  [
    selected_inspect_connection(),
    completed_append_connection(),
    threshold_append_connection(),
    ownership_append_connection(),
    checklist_tally_connection(),
    agreement_activity_connection(),
  ]
}

pub fn checklist_tally_connection() -> port_graph.Connection {
  let assert Ok(template) =
    port.connect(tally_payload.item_completed(), tally_payload.add())
  port_graph.connection(
    checklist_tally_connection_id,
    port_graph.PortRef(checklist_instance_id, template.source_port),
    port_graph.PortRef(tally_instance_id, template.target_port),
  )
}

pub fn agreement_activity_connection() -> port_graph.Connection {
  let assert Ok(template) =
    port.connect(component_event.emitted(), component_event.append())
  port_graph.connection(
    agreement_activity_connection_id,
    port_graph.PortRef(room_agreement_instance_id, template.source_port),
    port_graph.PortRef(activity_instance_id, template.target_port),
  )
}

pub fn threshold_append_connection() -> port_graph.Connection {
  let assert Ok(template) =
    port.connect(
      governance_payload.threshold_reached(),
      governance_payload.append_poll_threshold(),
    )
  port_graph.connection(
    threshold_append_connection_id,
    port_graph.PortRef(decision_poll_instance_id, template.source_port),
    port_graph.PortRef(activity_instance_id, template.target_port),
  )
}

pub fn ownership_append_connection() -> port_graph.Connection {
  let assert Ok(template) =
    port.connect(
      governance_payload.ownership_changed(),
      governance_payload.append_ownership_change(),
    )
  port_graph.connection(
    ownership_append_connection_id,
    port_graph.PortRef(ownership_slots_instance_id, template.source_port),
    port_graph.PortRef(activity_instance_id, template.target_port),
  )
}

pub fn selected_inspect_connection() -> port_graph.Connection {
  let assert Ok(template) =
    port.connect(payload.task_selected(), payload.inspect_task())
  port_graph.connection(
    selected_inspect_connection_id,
    port_graph.PortRef(task_collection_instance_id, template.source_port),
    port_graph.PortRef(inspector_instance_id, template.target_port),
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
    _ -> Error(Nil)
  }
}

pub fn as_inspector(running: Running) -> Result(inspector.Running, Nil) {
  case running {
    Inspector(inner) -> Ok(inner)
    _ -> Error(Nil)
  }
}

pub fn as_decision_poll(
  running: Running,
) -> Result(decision_poll.Running, Nil) {
  case running {
    DecisionPoll(inner) -> Ok(inner)
    _ -> Error(Nil)
  }
}

pub fn as_ownership_slots(
  running: Running,
) -> Result(ownership_slots.Running, Nil) {
  case running {
    OwnershipSlots(inner) -> Ok(inner)
    _ -> Error(Nil)
  }
}

pub fn as_notes(running: Running) -> Result(notes.Running, Nil) {
  case running {
    Notes(inner) -> Ok(inner)
    _ -> Error(Nil)
  }
}

pub fn as_activity(running: Running) -> Result(activity.Running, Nil) {
  case running {
    Activity(inner) -> Ok(inner)
    _ -> Error(Nil)
  }
}

pub fn as_checklist(running: Running) -> Result(checklist.Running, Nil) {
  case running {
    Checklist(inner) -> Ok(inner)
    _ -> Error(Nil)
  }
}

pub fn as_tally(running: Running) -> Result(tally.Running, Nil) {
  case running {
    Tally(inner) -> Ok(inner)
    _ -> Error(Nil)
  }
}

pub fn as_room_agreement(
  running: Running,
) -> Result(room_agreement.Running, Nil) {
  case running {
    RoomAgreement(inner, _) -> Ok(inner)
    _ -> Error(Nil)
  }
}

pub fn room_agreement_needs_refresh(running: Running) -> Bool {
  case running {
    RoomAgreement(_, pending) -> transport_js.get_cell(pending)
    _ -> False
  }
}

pub fn refresh_room_agreement(
  running: Running,
) -> Result(#(Running, List(component.OutputEvent)), String) {
  case running {
    RoomAgreement(inner, pending) -> {
      transport_js.set_cell(pending, False)
      let #(next, outputs) = room_agreement.refresh(inner)
      Ok(#(RoomAgreement(next, pending), outputs))
    }
    _ -> Error("agreement refresh reached the wrong component")
  }
}

fn room_agreement_descriptor() -> component.Descriptor(Context(root), Running) {
  component.executable_descriptor(
    kind: room_agreement_kind,
    version: room_agreement_version,
    config_decoder: room_agreement.config_decoder(),
    start: fn(context, config, done) {
      let pending = transport_js.new_cell(True)
      room_agreement.start(
        document(context),
        subtree(context),
        instance_id(context),
        fn() {
          transport_js.set_cell(pending, True)
          invalidate(context)()
        },
        config,
        fn(started) {
          done(result.map(started, fn(inner) { RoomAgreement(inner, pending) }))
        },
      )
    },
    inputs: [],
    stop: fn(running) {
      use inner <- result.try(
        as_room_agreement(running)
        |> result.map_error(fn(_) {
          "agreement stop reached the wrong component"
        }),
      )
      room_agreement.stop(inner)
    },
    ports: [port.output_descriptor(component_event.emitted())],
  )
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
      case as_task_collection(running) {
        Ok(inner) -> task_collection.stop(inner)
        Error(Nil) -> Error("task collection stop reached the wrong component")
      }
    },
    ports: [
      port.output_descriptor(payload.task_selected()),
      port.output_descriptor(payload.task_completed()),
    ],
  )
}

fn inspector_descriptor() -> component.Descriptor(Context(root), Running) {
  component.executable_descriptor(
    kind: inspector_kind,
    version: inspector_version,
    config_decoder: inspector.config_decoder(),
    start: fn(context, config, done) {
      inspector.start(
        document(context),
        subtree(context),
        invalidate(context),
        config,
        fn(started) {
          case started {
            Ok(running) -> done(Ok(Inspector(running)))
            Error(reason) -> done(Error(reason))
          }
        },
      )
    },
    inputs: [
      component.input_handler(payload.inspect_task(), fn(running, task) {
        case as_inspector(running) {
          Ok(inner) -> {
            let #(next, events) = inspector.inspect(inner, task)
            Ok(#(Inspector(next), events))
          }
          Error(Nil) -> Error("inspector input reached the wrong component")
        }
      }),
    ],
    stop: fn(running) {
      case as_inspector(running) {
        Ok(inner) -> inspector.stop(inner)
        Error(Nil) -> Error("inspector stop reached the wrong component")
      }
    },
    ports: [port.input_descriptor(payload.inspect_task())],
  )
}

fn decision_poll_descriptor() -> component.Descriptor(Context(root), Running) {
  component.executable_descriptor(
    kind: decision_poll_kind,
    version: decision_poll_version,
    config_decoder: decision_poll.config_decoder(),
    start: fn(context, config, done) {
      decision_poll.start(
        document(context),
        subtree(context),
        invalidate(context),
        emitter(context),
        governance_payload.Identity(
          participant_id(context),
          participant_label(context),
        ),
        config,
        fn(started) {
          case started {
            Ok(running) -> done(Ok(DecisionPoll(running)))
            Error(reason) -> done(Error(reason))
          }
        },
      )
    },
    inputs: [
      component.input_handler(
        governance_payload.show_results(),
        fn(running, command) {
          case as_decision_poll(running) {
            Ok(inner) ->
              decision_poll.set_results_visibility(inner, command)
              |> result.map(fn(next) { #(DecisionPoll(next.0), next.1) })
            Error(Nil) -> Error("poll input reached the wrong component")
          }
        },
      ),
      component.input_handler(governance_payload.open_poll(), fn(running, _) {
        case as_decision_poll(running) {
          Ok(inner) ->
            decision_poll.set_lifecycle(inner, governance_payload.OpenPoll)
            |> result.map(fn(next) { #(DecisionPoll(next.0), next.1) })
          Error(Nil) -> Error("poll input reached the wrong component")
        }
      }),
      component.input_handler(governance_payload.close_poll(), fn(running, _) {
        case as_decision_poll(running) {
          Ok(inner) ->
            decision_poll.set_lifecycle(inner, governance_payload.ClosePoll)
            |> result.map(fn(next) { #(DecisionPoll(next.0), next.1) })
          Error(Nil) -> Error("poll input reached the wrong component")
        }
      }),
    ],
    stop: fn(running) {
      case as_decision_poll(running) {
        Ok(inner) -> decision_poll.stop(inner)
        Error(Nil) -> Error("poll stop reached the wrong component")
      }
    },
    ports: [
      port.output_descriptor(governance_payload.vote_changed()),
      port.output_descriptor(governance_payload.threshold_reached()),
      port.input_descriptor(governance_payload.show_results()),
      port.input_descriptor(governance_payload.open_poll()),
      port.input_descriptor(governance_payload.close_poll()),
    ],
  )
}

fn ownership_slots_descriptor() -> component.Descriptor(Context(root), Running) {
  component.executable_descriptor(
    kind: ownership_slots_kind,
    version: ownership_slots_version,
    config_decoder: ownership_slots.config_decoder(),
    start: fn(context, config, done) {
      ownership_slots.start(
        document(context),
        subtree(context),
        invalidate(context),
        emitter(context),
        governance_payload.Identity(
          participant_id(context),
          participant_label(context),
        ),
        config,
        fn(started) {
          case started {
            Ok(running) -> done(Ok(OwnershipSlots(running)))
            Error(reason) -> done(Error(reason))
          }
        },
      )
    },
    inputs: [
      component.input_handler(
        governance_payload.claim_slot(),
        fn(running, command) {
          let command =
            governance_payload.SlotCommand(
              command.slot_id,
              governance_payload.ClaimSlot,
            )
          ownership_input(running, command)
        },
      ),
      component.input_handler(
        governance_payload.release_slot(),
        fn(running, command) {
          let command =
            governance_payload.SlotCommand(
              command.slot_id,
              governance_payload.ReleaseSlot,
            )
          ownership_input(running, command)
        },
      ),
      component.input_handler(
        governance_payload.handoff_slot(),
        fn(running, command) {
          case command.operation {
            governance_payload.HandoffSlot(_) ->
              ownership_input(running, command)
            governance_payload.ClaimSlot | governance_payload.ReleaseSlot ->
              Error("handoff input requires a target")
          }
        },
      ),
      component.input_handler(governance_payload.reveal_owner(), fn(running, _) {
        case as_ownership_slots(running) {
          Ok(inner) ->
            ownership_slots.toggle_details(inner)
            |> result.map(fn(next) { #(OwnershipSlots(next.0), next.1) })
          Error(Nil) -> Error("ownership input reached the wrong component")
        }
      }),
    ],
    stop: fn(running) {
      case as_ownership_slots(running) {
        Ok(inner) -> ownership_slots.stop(inner)
        Error(Nil) -> Error("ownership stop reached the wrong component")
      }
    },
    ports: [
      port.output_descriptor(governance_payload.claim_attempted()),
      port.output_descriptor(governance_payload.claim_resolved()),
      port.output_descriptor(governance_payload.ownership_changed()),
      port.input_descriptor(governance_payload.claim_slot()),
      port.input_descriptor(governance_payload.release_slot()),
      port.input_descriptor(governance_payload.handoff_slot()),
      port.input_descriptor(governance_payload.reveal_owner()),
    ],
  )
}

fn ownership_input(
  running: Running,
  command: governance_payload.SlotCommand,
) -> Result(#(Running, List(component.OutputEvent)), String) {
  case as_ownership_slots(running) {
    Ok(inner) ->
      ownership_slots.submit(inner, command)
      |> result.map(fn(next) { #(OwnershipSlots(next.0), next.1) })
    Error(Nil) -> Error("ownership input reached the wrong component")
  }
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
    inputs: [],
    stop: fn(running) {
      case as_notes(running) {
        Ok(inner) -> notes.stop(inner)
        Error(Nil) -> Error("notes stop reached the wrong component")
      }
    },
    ports: [],
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
        case as_activity(running) {
          Ok(inner) ->
            activity.append_entry(inner, entry)
            |> result.map(fn(next) { #(Activity(next.0), next.1) })
          Error(Nil) -> Error("activity input reached the wrong component")
        }
      }),
      component.input_handler(
        governance_payload.append_poll_threshold(),
        fn(running, entry) {
          case as_activity(running) {
            Ok(inner) ->
              activity.append_poll_threshold(inner, entry)
              |> result.map(fn(next) { #(Activity(next.0), next.1) })
            Error(Nil) -> Error("activity input reached the wrong component")
          }
        },
      ),
      component.input_handler(
        governance_payload.append_ownership_change(),
        fn(running, entry) {
          case as_activity(running) {
            Ok(inner) ->
              activity.append_ownership_change(inner, entry)
              |> result.map(fn(next) { #(Activity(next.0), next.1) })
            Error(Nil) -> Error("activity input reached the wrong component")
          }
        },
      ),
      component.input_handler(component_event.append(), fn(running, entry) {
        case as_activity(running) {
          Ok(inner) ->
            activity.append_component_event(inner, entry)
            |> result.map(fn(next) { #(Activity(next.0), next.1) })
          Error(Nil) -> Error("activity input reached the wrong component")
        }
      }),
    ],
    stop: fn(running) {
      case as_activity(running) {
        Ok(inner) -> activity.stop(inner)
        Error(Nil) -> Error("activity stop reached the wrong component")
      }
    },
    ports: [
      port.input_descriptor(payload.append_entry()),
      port.input_descriptor(governance_payload.append_poll_threshold()),
      port.input_descriptor(governance_payload.append_ownership_change()),
      port.input_descriptor(component_event.append()),
    ],
  )
}

fn checklist_descriptor() -> component.Descriptor(Context(root), Running) {
  component.executable_descriptor(
    kind: checklist_kind,
    version: checklist_version,
    config_decoder: checklist.config_decoder(),
    start: fn(context, config, done) {
      checklist.start(
        document(context),
        subtree(context),
        invalidate(context),
        config,
        fn(started) {
          case started {
            Ok(running) -> done(Ok(Checklist(running)))
            Error(reason) -> done(Error(reason))
          }
        },
      )
    },
    inputs: [
      component.input_handler(checklist.add_item(), fn(running, label) {
        case as_checklist(running) {
          Ok(inner) ->
            checklist.add_label(inner, label)
            |> result.map(fn(next) { #(Checklist(next.0), next.1) })
          Error(Nil) -> Error("checklist input reached the wrong component")
        }
      }),
      component.input_handler(checklist.complete_item(), fn(running, item_id) {
        case as_checklist(running) {
          Ok(inner) ->
            checklist.complete(inner, item_id)
            |> result.map(fn(next) { #(Checklist(next.0), next.1) })
          Error(Nil) -> Error("checklist input reached the wrong component")
        }
      }),
    ],
    stop: fn(running) {
      case as_checklist(running) {
        Ok(inner) -> checklist.stop(inner)
        Error(Nil) -> Error("checklist stop reached the wrong component")
      }
    },
    ports: [
      port.output_descriptor(tally_payload.item_completed()),
      port.input_descriptor(checklist.add_item()),
      port.input_descriptor(checklist.complete_item()),
    ],
  )
}

fn tally_descriptor() -> component.Descriptor(Context(root), Running) {
  component.executable_descriptor(
    kind: tally_kind,
    version: tally_version,
    config_decoder: tally.config_decoder(),
    start: fn(context, config, done) {
      tally.start(
        document(context),
        subtree(context),
        invalidate(context),
        emitter(context),
        config,
        fn(started) {
          case started {
            Ok(running) -> done(Ok(Tally(running)))
            Error(reason) -> done(Error(reason))
          }
        },
      )
    },
    inputs: [
      component.input_handler(tally_payload.add(), fn(running, amount) {
        case as_tally(running) {
          Ok(inner) ->
            tally.add(inner, amount)
            |> result.map(fn(next) { #(Tally(next.0), next.1) })
          Error(Nil) -> Error("tally input reached the wrong component")
        }
      }),
    ],
    stop: fn(running) {
      case as_tally(running) {
        Ok(inner) -> tally.stop(inner)
        Error(Nil) -> Error("tally stop reached the wrong component")
      }
    },
    ports: [
      port.output_descriptor(tally_payload.target_reached()),
      port.input_descriptor(tally_payload.add()),
    ],
  )
}
