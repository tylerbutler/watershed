//// Shared payload and typed ports for the headless project room components.

import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}

import watershed/port

/// The shared task payload that moves between the headless components.
pub type TaskPayload {
  TaskPayload(task_id: String, title: String, completed: Bool)
}

pub const task_payload_schema_id = "project-room/task-payload@1"

pub const task_selected_port_id = "selected"

pub const focus_subject_port_id = "focus_subject"

pub const task_completed_port_id = "completed"

pub const append_entry_port_id = "append_entry"

pub fn encode(payload: TaskPayload) -> Json {
  json.object([
    #("taskId", json.string(payload.task_id)),
    #("title", json.string(payload.title)),
    #("completed", json.bool(payload.completed)),
  ])
}

pub fn decoder() -> Decoder(TaskPayload) {
  use task_id <- decode.field("taskId", decode.string)
  use title <- decode.field("title", decode.string)
  use completed <- decode.field("completed", decode.bool)
  decode.success(TaskPayload(task_id:, title:, completed:))
}

pub fn decode(value: Json) -> Result(TaskPayload, json.DecodeError) {
  json.parse(json.to_string(value), decoder())
}

pub fn task_selected() -> port.Output(TaskPayload) {
  port.output(task_selected_port_id, task_payload_schema_id, encode)
}

pub fn focus_subject() -> port.Input(TaskPayload) {
  port.local_input(focus_subject_port_id, task_payload_schema_id, decoder())
}

pub fn task_completed() -> port.Output(TaskPayload) {
  port.output(task_completed_port_id, task_payload_schema_id, encode)
}

pub fn append_entry() -> port.Input(TaskPayload) {
  port.collaborative_input(
    append_entry_port_id,
    task_payload_schema_id,
    decoder(),
    ["sequence:insert"],
  )
}
