//// Headless notes component for the project room runtime.

import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}
import gleam/option.{Some}
import gleam/result

import watershed
import watershed/schema
import watershed/transport_js

type NotesSchema

/// The static config for the notes component.
pub type Config {
  Config(title: String)
}

/// The running notes state.
pub opaque type Running {
  Running(
    text: transport_js.Cell(watershed.SharedText),
    text_subscription: transport_js.Cell(watershed.SubscriptionToken),
    subtree_subscription: watershed.SubscriptionToken,
  )
}

fn text_field() -> schema.ChannelField(NotesSchema, schema.TextChannel) {
  schema.channel_field("notes_text")
}

pub fn config_decoder() -> Decoder(Config) {
  use title <- decode.field("title", decode.string)
  decode.success(Config(title: title))
}

pub fn encode_config(config: Config) -> Json {
  json.object([#("title", json.string(config.title))])
}

/// Attach the owned text while a new instance subtree is detached.
pub fn initialize(
  document: watershed.Document(root),
  subtree: watershed.SharedMap,
) -> Result(Nil, String) {
  let typed_subtree: watershed.TypedMap(NotesSchema) = watershed.typed(subtree)
  use text <- result.try(watershed.create_text(document))
  watershed.set_text_field(typed_subtree, text_field(), text)
  Ok(Nil)
}

pub fn start(
  document: watershed.Document(root),
  subtree: watershed.SharedMap,
  invalidate: fn() -> Nil,
  _config: Config,
  done: fn(Result(Running, String)) -> Nil,
) -> Nil {
  let typed_subtree: watershed.TypedMap(NotesSchema) = watershed.typed(subtree)
  watershed.ensure_text(document, typed_subtree, text_field(), fn(result) {
    case result {
      Error(reason) -> done(Error("notes bootstrap failed: " <> reason))
      Ok(text) -> {
        let text_cell = transport_js.new_cell(text)
        let text_subscription =
          watershed.subscribe_text(text, fn(_) { invalidate() })
        let text_subscription_cell = transport_js.new_cell(text_subscription)
        let subtree_subscription =
          watershed.subscribe(subtree, fn(_) {
            rebind(
              document,
              typed_subtree,
              text_cell,
              text_subscription_cell,
              invalidate,
            )
          })
        rebind(
          document,
          typed_subtree,
          text_cell,
          text_subscription_cell,
          invalidate,
        )
        done(
          Ok(Running(
            text: text_cell,
            text_subscription: text_subscription_cell,
            subtree_subscription: subtree_subscription,
          )),
        )
      }
    }
  })
}

fn rebind(
  document: watershed.Document(root),
  subtree: watershed.TypedMap(NotesSchema),
  text: transport_js.Cell(watershed.SharedText),
  text_subscription: transport_js.Cell(watershed.SubscriptionToken),
  invalidate: fn() -> Nil,
) -> Nil {
  case watershed.resolve_text_field(document, subtree, text_field()) {
    Ok(Some(current)) -> {
      case
        watershed.text_handle_of(current)
        == watershed.text_handle_of(transport_js.get_cell(text))
      {
        True -> Nil
        False -> {
          watershed.unsubscribe(transport_js.get_cell(text_subscription))
          transport_js.set_cell(text, current)
          transport_js.set_cell(
            text_subscription,
            watershed.subscribe_text(current, fn(_) { invalidate() }),
          )
          invalidate()
        }
      }
    }
    Ok(_) | Error(_) -> Nil
  }
}

pub fn text(running: Running) -> watershed.SharedText {
  transport_js.get_cell(running.text)
}

pub fn stop(running: Running) -> Result(Nil, String) {
  watershed.unsubscribe(transport_js.get_cell(running.text_subscription))
  watershed.unsubscribe(running.subtree_subscription)
  Ok(Nil)
}
