//// Headless activity log for the project room runtime.

import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}
import gleam/list
import gleam/option.{Some}
import gleam/result

import watershed
import watershed/component
import watershed/schema
import watershed/transport_js

import project_room_lustre/payload

type ActivitySchema

/// The static config for the activity component.
pub type Config {
  Config(title: String)
}

/// The running activity state.
pub opaque type Running {
  Running(
    entries: transport_js.Cell(watershed.SharedSequence),
    entries_subscription: transport_js.Cell(watershed.SubscriptionToken),
    subtree_subscription: watershed.SubscriptionToken,
  )
}

fn entries_field() -> schema.ChannelField(
  ActivitySchema,
  schema.SequenceChannel,
) {
  schema.channel_field("activity_entries")
}

pub fn config_decoder() -> Decoder(Config) {
  use title <- decode.field("title", decode.string)
  decode.success(Config(title: title))
}

pub fn encode_config(config: Config) -> Json {
  json.object([#("title", json.string(config.title))])
}

/// Attach the owned sequence while a new instance subtree is detached.
pub fn initialize(
  document: watershed.Document(root),
  subtree: watershed.SharedMap,
) -> Result(Nil, String) {
  let typed_subtree: watershed.TypedMap(ActivitySchema) =
    watershed.typed(subtree)
  use entries <- result.try(watershed.create_sequence(document))
  watershed.set_sequence_field(typed_subtree, entries_field(), entries)
  Ok(Nil)
}

pub fn start(
  document: watershed.Document(root),
  subtree: watershed.SharedMap,
  invalidate: fn() -> Nil,
  _config: Config,
  done: fn(Result(Running, String)) -> Nil,
) -> Nil {
  let typed_subtree: watershed.TypedMap(ActivitySchema) =
    watershed.typed(subtree)
  watershed.ensure_sequence(
    document,
    typed_subtree,
    entries_field(),
    fn(result) {
      case result {
        Error(reason) -> done(Error("activity bootstrap failed: " <> reason))
        Ok(entries) -> {
          let entries_cell = transport_js.new_cell(entries)
          let entries_subscription =
            watershed.subscribe_sequence(entries, fn(_) { invalidate() })
          let entries_subscription_cell =
            transport_js.new_cell(entries_subscription)
          let subtree_subscription =
            watershed.subscribe(subtree, fn(_) {
              rebind(
                document,
                typed_subtree,
                entries_cell,
                entries_subscription_cell,
                invalidate,
              )
            })
          rebind(
            document,
            typed_subtree,
            entries_cell,
            entries_subscription_cell,
            invalidate,
          )
          done(
            Ok(Running(
              entries: entries_cell,
              entries_subscription: entries_subscription_cell,
              subtree_subscription: subtree_subscription,
            )),
          )
        }
      }
    },
  )
}

fn rebind(
  document: watershed.Document(root),
  subtree: watershed.TypedMap(ActivitySchema),
  entries: transport_js.Cell(watershed.SharedSequence),
  entries_subscription: transport_js.Cell(watershed.SubscriptionToken),
  invalidate: fn() -> Nil,
) -> Nil {
  case watershed.resolve_sequence_field(document, subtree, entries_field()) {
    Ok(Some(current)) -> {
      case
        watershed.sequence_handle_of(current)
        == watershed.sequence_handle_of(transport_js.get_cell(entries))
      {
        True -> Nil
        False -> {
          watershed.unsubscribe(transport_js.get_cell(entries_subscription))
          transport_js.set_cell(entries, current)
          transport_js.set_cell(
            entries_subscription,
            watershed.subscribe_sequence(current, fn(_) { invalidate() }),
          )
          invalidate()
        }
      }
    }
    Ok(_) | Error(_) -> Nil
  }
}

pub fn entries_sequence(running: Running) -> watershed.SharedSequence {
  transport_js.get_cell(running.entries)
}

pub fn entries(running: Running) -> List(payload.TaskPayload) {
  watershed.sequence_values(entries_sequence(running))
  |> list.filter_map(fn(value) {
    case payload.decode(value) {
      Ok(entry) -> Ok(entry)
      Error(_) -> Error(Nil)
    }
  })
}

pub fn append_entry(
  running: Running,
  entry: payload.TaskPayload,
) -> Result(#(Running, List(component.OutputEvent)), String) {
  watershed.sequence_insert(
    entries_sequence(running),
    watershed.sequence_length(entries_sequence(running)),
    payload.encode(entry),
  )
  |> result.map(fn(_) { #(running, []) })
}

pub fn stop(running: Running) -> Result(Nil, String) {
  watershed.unsubscribe(transport_js.get_cell(running.entries_subscription))
  watershed.unsubscribe(running.subtree_subscription)
  Ok(Nil)
}
