//// Presence metadata for one project room session.

import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}
import gleam/option.{type Option, None, Some}

import watershed_lustre/textarea

/// The transient activity that one client publishes.
pub type RoomPresence {
  RoomPresence(
    name: String,
    color: String,
    selected_task_id: Option(String),
    cursor: Option(textarea.Cursor),
  )
}

pub fn encode(metadata: RoomPresence) -> Json {
  json.object([
    #("name", json.string(metadata.name)),
    #("color", json.string(metadata.color)),
    #("selectedTaskId", case metadata.selected_task_id {
      Some(task_id) -> json.string(task_id)
      None -> json.null()
    }),
    #("cursor", case metadata.cursor {
      Some(cursor) -> textarea.cursor_to_json(cursor)
      None -> json.null()
    }),
  ])
}

pub fn decoder() -> Decoder(RoomPresence) {
  use name <- decode.field("name", decode.string)
  use color <- decode.field("color", decode.string)
  use selected_task_id <- decode.field(
    "selectedTaskId",
    decode.optional(decode.string),
  )
  use cursor <- decode.field(
    "cursor",
    decode.optional(textarea.cursor_decoder()),
  )
  decode.success(RoomPresence(name:, color:, selected_task_id:, cursor:))
}
