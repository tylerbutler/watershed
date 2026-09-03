import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should

import watershed
import watershed_lustre/textarea

import project_room_lustre/room_presence

pub fn metadata_round_trips_with_and_without_activity_test() -> Nil {
  let cursor = start_cursor()
  let values = [
    room_presence.RoomPresence(
      name: "1234",
      color: "#4363d8",
      selected_task_id: None,
      cursor: None,
    ),
    room_presence.RoomPresence(
      name: "5678",
      color: "#3cb44b",
      selected_task_id: Some("task-2"),
      cursor: Some(cursor),
    ),
  ]

  values
  |> list.each(fn(value) {
    json.parse(
      json.to_string(room_presence.encode(value)),
      room_presence.decoder(),
    )
    |> should.equal(Ok(value))
  })
}

fn start_cursor() -> textarea.Cursor {
  let anchor =
    watershed.text_start_anchor()
    |> watershed.text_anchor_to_json
    |> json.to_string
    |> json.string
  let encoded = json.object([#("start", anchor), #("end", anchor)])
  let assert Ok(cursor) =
    json.parse(json.to_string(encoded), textarea.cursor_decoder())
  cursor
}
