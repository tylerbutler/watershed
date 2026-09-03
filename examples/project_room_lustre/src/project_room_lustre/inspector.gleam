//// A local task inspector for the project room runtime.
////
//// The workspace persists the component instance and config. The selected
//// task stays in the running value of one client.

import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}
import gleam/option.{type Option, None, Some}

import watershed
import watershed/component

import project_room_lustre/payload

/// The static config for the task inspector.
pub type Config {
  Config(title: String)
}

/// The local state of one running task inspector.
pub opaque type Running {
  Running(
    /// The payload snapshot from the most recent local input.
    selected: Option(payload.TaskPayload),
  )
}

pub fn config_decoder() -> Decoder(Config) {
  use title <- decode.field("title", decode.string)
  decode.success(Config(title: title))
}

pub fn encode_config(config: Config) -> Json {
  json.object([#("title", json.string(config.title))])
}

/// The inspector owns no collaborative channels.
pub fn initialize(
  _document: watershed.Document(root),
  _subtree: watershed.SharedMap,
) -> Result(Nil, String) {
  Ok(Nil)
}

pub fn start(
  _document: watershed.Document(root),
  _subtree: watershed.SharedMap,
  _invalidate: fn() -> Nil,
  _config: Config,
  done: fn(Result(Running, String)) -> Nil,
) -> Nil {
  done(Ok(Running(None)))
}

/// Select one task in this client.
pub fn inspect(
  _running: Running,
  task: payload.TaskPayload,
) -> #(Running, List(component.OutputEvent)) {
  #(Running(Some(task)), [])
}

/// The task that this client selected.
pub fn selected(running: Running) -> Option(payload.TaskPayload) {
  running.selected
}

pub fn stop(_running: Running) -> Result(Nil, String) {
  Ok(Nil)
}
