//// Shared activity events emitted by project room components.

import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}

import watershed/port

pub type Action {
  Published
  EntryChanged
  FolderChanged
  AgreementAccepted
}

pub type Event {
  Event(
    source_instance_id: String,
    source_kind: String,
    source_title: String,
    action: Action,
    detail: String,
  )
}

pub const schema_id = "project-room/component-event@1"

pub const emitted_port_id = "component_event"

pub const append_port_id = "append_component_event"

pub fn encode(event: Event) -> Json {
  json.object([
    #("sourceInstanceId", json.string(event.source_instance_id)),
    #("sourceKind", json.string(event.source_kind)),
    #("sourceTitle", json.string(event.source_title)),
    #("action", json.string(encode_action(event.action))),
    #("detail", json.string(event.detail)),
  ])
}

pub fn decoder() -> Decoder(Event) {
  use source_instance_id <- decode.field("sourceInstanceId", decode.string)
  use source_kind <- decode.field("sourceKind", decode.string)
  use source_title <- decode.field("sourceTitle", decode.string)
  use action <- decode.field("action", action_decoder())
  use detail <- decode.field("detail", decode.string)
  decode.success(Event(
    source_instance_id:,
    source_kind:,
    source_title:,
    action:,
    detail:,
  ))
}

pub fn emitted() -> port.Output(Event) {
  port.output(emitted_port_id, schema_id, encode)
}

pub fn append() -> port.Input(Event) {
  port.collaborative_input(append_port_id, schema_id, decoder(), [
    "sequence:insert",
  ])
}

fn encode_action(action: Action) -> String {
  case action {
    Published -> "published"
    EntryChanged -> "entry_changed"
    FolderChanged -> "folder_changed"
    AgreementAccepted -> "agreement_accepted"
  }
}

fn action_decoder() -> Decoder(Action) {
  decode.string
  |> decode.then(fn(action) {
    case action {
      "published" -> decode.success(Published)
      "entry_changed" -> decode.success(EntryChanged)
      "folder_changed" -> decode.success(FolderChanged)
      "agreement_accepted" -> decode.success(AgreementAccepted)
      _ -> decode.failure(Published, "Action")
    }
  })
}
