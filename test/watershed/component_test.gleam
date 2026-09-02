import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/result
import gleam/string
import startest/expect
import watershed/component
import watershed/port

type NotesConfig {
  NotesConfig(placeholder: String)
}

type CounterConfig {
  CounterConfig(step: Int)
}

fn notes_decoder() -> decode.Decoder(NotesConfig) {
  use placeholder <- decode.field("placeholder", decode.string)
  decode.success(NotesConfig(placeholder: placeholder))
}

fn counter_decoder() -> decode.Decoder(CounterConfig) {
  use step <- decode.field("step", decode.int)
  decode.success(CounterConfig(step: step))
}

fn notes_descriptor() -> component.Descriptor(String, String) {
  component.descriptor(
    kind: "watershed/notes",
    version: 1,
    config_decoder: notes_decoder(),
    start: fn(context, config) { Ok(context <> ":" <> config.placeholder) },
    ports: [
      port.output_descriptor(port.output("selected", "subject@1", json.string)),
    ],
  )
}

fn counter_descriptor() -> component.Descriptor(String, String) {
  component.descriptor(
    kind: "watershed/counter",
    version: 1,
    config_decoder: counter_decoder(),
    start: fn(context, config) {
      Ok(context <> ":" <> int.to_string(config.step))
    },
    ports: [],
  )
}

fn failing_descriptor() -> component.Descriptor(String, String) {
  component.descriptor(
    kind: "watershed/failing",
    version: 1,
    config_decoder: notes_decoder(),
    start: fn(_context, _config) { Error("cannot subscribe") },
    ports: [],
  )
}

pub fn catalog_holds_different_config_types_test() -> Nil {
  let assert Ok(with_notes) =
    component.register(component.new_catalog(), notes_descriptor())
  let assert Ok(catalog) = component.register(with_notes, counter_descriptor())

  component.find(catalog, "watershed/notes", 1)
  |> result.map(component.kind)
  |> expect.to_equal(Ok("watershed/notes"))
}

pub fn start_decodes_config_inside_descriptor_test() -> Nil {
  component.start(
    notes_descriptor(),
    "room",
    json.object([#("placeholder", json.string("Write"))]),
  )
  |> expect.to_equal(Ok("room:Write"))
}

pub fn invalid_config_has_kind_and_version_test() -> Nil {
  case component.start(notes_descriptor(), "room", json.object([])) {
    Error(component.InvalidConfig(kind, version, _)) -> {
      kind |> expect.to_equal("watershed/notes")
      version |> expect.to_equal(1)
    }
    other -> panic as { "expected InvalidConfig, got " <> string.inspect(other) }
  }
}

pub fn duplicate_kind_and_version_is_rejected_test() -> Nil {
  let assert Ok(catalog) =
    component.register(component.new_catalog(), notes_descriptor())

  component.register(catalog, notes_descriptor())
  |> expect.to_equal(
    Error(component.DuplicateRegistration("watershed/notes", 1)),
  )
}

pub fn versions_can_coexist_test() -> Nil {
  let notes_v2 =
    component.descriptor(
      kind: "watershed/notes",
      version: 2,
      config_decoder: notes_decoder(),
      start: fn(_, config) { Ok(config.placeholder) },
      ports: [],
    )
  let assert Ok(with_v1) =
    component.register(component.new_catalog(), notes_descriptor())
  let assert Ok(catalog) = component.register(with_v1, notes_v2)

  component.find(catalog, "watershed/notes", 2)
  |> result.map(component.version)
  |> expect.to_equal(Ok(2))
}

pub fn unknown_kind_is_reported_test() -> Nil {
  component.find(component.new_catalog(), "watershed/notes", 7)
  |> expect.to_equal(Error(component.NotRegistered("watershed/notes")))
}

pub fn unsupported_version_lists_available_versions_test() -> Nil {
  let notes_v2 =
    component.descriptor(
      kind: "watershed/notes",
      version: 2,
      config_decoder: notes_decoder(),
      start: fn(_, config) { Ok(config.placeholder) },
      ports: [],
    )
  let assert Ok(with_v2) = component.register(component.new_catalog(), notes_v2)
  let assert Ok(catalog) = component.register(with_v2, notes_descriptor())

  component.find(catalog, "watershed/notes", 7)
  |> expect.to_equal(
    Error(component.UnsupportedVersion("watershed/notes", 7, [1, 2])),
  )
}

pub fn unsupported_version_ignores_other_kinds_test() -> Nil {
  let assert Ok(with_notes) =
    component.register(component.new_catalog(), notes_descriptor())
  let assert Ok(catalog) = component.register(with_notes, counter_descriptor())

  component.find(catalog, "watershed/counter", 4)
  |> expect.to_equal(
    Error(component.UnsupportedVersion("watershed/counter", 4, [1])),
  )
}

pub fn validate_config_accepts_a_valid_config_test() -> Nil {
  component.validate_config(
    notes_descriptor(),
    json.object([#("placeholder", json.string("Write"))]),
  )
  |> expect.to_equal(Ok(Nil))
}

pub fn validate_config_rejects_an_invalid_config_test() -> Nil {
  case component.validate_config(notes_descriptor(), json.object([])) {
    Error(component.InvalidConfig(kind, version, _)) -> {
      kind |> expect.to_equal("watershed/notes")
      version |> expect.to_equal(1)
    }
    other -> panic as { "expected InvalidConfig, got " <> string.inspect(other) }
  }
}

pub fn validate_config_does_not_start_the_component_test() -> Nil {
  component.validate_config(
    failing_descriptor(),
    json.object([#("placeholder", json.string("Write"))]),
  )
  |> expect.to_equal(Ok(Nil))
}

pub fn ports_lists_the_declared_port_metadata_test() -> Nil {
  component.ports(notes_descriptor())
  |> expect.to_equal([
    port.Descriptor(
      id: "selected",
      direction: port.OutputPort,
      schema_id: "subject@1",
    ),
  ])

  component.ports(counter_descriptor())
  |> expect.to_equal([])
}

pub fn failed_start_reports_kind_and_reason_test() -> Nil {
  component.start(
    failing_descriptor(),
    "room",
    json.object([
      #("placeholder", json.string("Write")),
    ]),
  )
  |> expect.to_equal(
    Error(component.StartFailed("watershed/failing", 1, "cannot subscribe")),
  )
}
