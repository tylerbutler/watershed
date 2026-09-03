//// Shared integer-delta ports for project room components.

import gleam/dynamic/decode
import gleam/json

import watershed/port

pub const delta_schema = "project-room/tally-delta@1"

pub fn item_completed() -> port.Output(Int) {
  port.output("item_completed", delta_schema, json.int)
}

pub fn add() -> port.Input(Int) {
  port.collaborative_input("add", delta_schema, decode.int, [
    "pn-counter:update",
  ])
}
