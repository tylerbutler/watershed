//// Shared integer-delta ports for project room components.

import gleam/dynamic/decode
import gleam/json

import watershed/port

pub const delta_schema = "project-room/tally-delta@1"

pub const value_schema = "project-room/tally-value@1"

pub fn item_completed() -> port.Output(Int) {
  port.output("item_completed", delta_schema, json.int)
}

pub fn target_reached() -> port.Output(Int) {
  port.output("target_reached", value_schema, json.int)
}

pub fn add() -> port.Input(Int) {
  port.collaborative_input("add", delta_schema, decode.int, [
    "pn-counter:update",
  ])
}
