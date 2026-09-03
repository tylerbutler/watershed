import gleam/dynamic/decode
import gleam/json
import gleam/string
import startest/expect

import watershed/port

// docs:snippet-start foundations-ports-selected
fn selected() -> port.Output(String) {
  port.output("selected", "watershed/task-id@1", json.string)
}

// docs:snippet-end foundations-ports-selected

// docs:snippet-start foundations-ports-focus-subject
fn focus_subject() -> port.Input(String) {
  port.local_input("focus-subject", "watershed/task-id@1", decode.string)
}

// docs:snippet-end foundations-ports-focus-subject

// docs:snippet-start foundations-ports-append-activity
fn append_activity() -> port.Input(String) {
  port.collaborative_input(
    "append-entry",
    "watershed/activity-text@1",
    decode.string,
    ["sequence:insert"],
  )
}

// docs:snippet-end foundations-ports-append-activity

pub fn output_descriptor_has_stable_metadata_test() -> Nil {
  port.output_descriptor(selected())
  |> expect.to_equal(port.Descriptor(
    id: "selected",
    direction: port.OutputPort,
    schema_id: "watershed/task-id@1",
  ))
}

pub fn local_input_descriptor_records_class_test() -> Nil {
  port.input_descriptor(focus_subject())
  |> expect.to_equal(port.Descriptor(
    id: "focus-subject",
    direction: port.InputPort(port.LocalInput),
    schema_id: "watershed/task-id@1",
  ))
}

pub fn collaborative_input_records_capabilities_test() -> Nil {
  port.input_descriptor(append_activity())
  |> expect.to_equal(port.Descriptor(
    id: "append-entry",
    direction: port.InputPort(
      port.CollaborativeInput(capabilities: ["sequence:insert"]),
    ),
    schema_id: "watershed/activity-text@1",
  ))
}

pub fn direction_kind_drops_the_input_class_test() -> Nil {
  port.direction_kind(port.OutputPort)
  |> expect.to_equal(port.OutputDirection)

  port.direction_kind(port.InputPort(port.LocalInput))
  |> expect.to_equal(port.InputDirection)

  port.direction_kind(
    port.InputPort(port.CollaborativeInput(capabilities: ["sequence:insert"])),
  )
  |> expect.to_equal(port.InputDirection)
}

pub fn payload_round_trip_test() -> Nil {
  let encoded = port.encode(selected(), "task-42")
  port.decode(focus_subject(), encoded)
  |> expect.to_equal(Ok("task-42"))
}

pub fn invalid_payload_returns_decode_error_test() -> Nil {
  case port.decode(focus_subject(), json.int(42)) {
    Error(port.InvalidPayload(_)) -> Nil
    other ->
      panic as { "expected InvalidPayload, got " <> string.inspect(other) }
  }
}

pub fn direct_connection_keeps_port_ids_test() -> Nil {
  port.connect(selected(), focus_subject())
  |> expect.to_equal(
    Ok(port.ConnectionTemplate(
      source_port: "selected",
      target_port: "focus-subject",
      schema_id: "watershed/task-id@1",
    )),
  )
}

pub fn matching_payload_type_with_different_schema_is_rejected_test() -> Nil {
  let other = port.local_input("other", "example/other-string@1", decode.string)
  port.connect(selected(), other)
  |> expect.to_equal(
    Error(port.SchemaMismatch(
      source: "watershed/task-id@1",
      target: "example/other-string@1",
    )),
  )
}
