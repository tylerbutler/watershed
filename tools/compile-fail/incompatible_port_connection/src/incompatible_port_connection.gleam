//// A fixture that must not compile.

import gleam/dynamic/decode
import gleam/json
import watershed/port

pub fn incompatible_connection() {
  let selected = port.output("selected", "task-id@1", json.string)
  let set_filter = port.local_input("set-filter", "status@1", decode.int)
  port.connect(selected, set_filter)
}
