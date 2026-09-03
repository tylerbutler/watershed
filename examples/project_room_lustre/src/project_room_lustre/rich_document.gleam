//// Headless rich document component for the project room runtime.

import gleam/option.{None, Some}
import gleam/result

import watershed
import watershed/component
import watershed/rich_text
import watershed/schema
import watershed/transport_js

import project_room_lustre/component_event

type RichDocumentSchema

/// The static rich document configuration.
pub type Config {
  Config(title: String)
}

/// The running rich document state.
pub opaque type Running {
  Running(
    instance_id: String,
    config: Config,
    channel: transport_js.Cell(watershed.SharedRichText),
    channel_subscription: transport_js.Cell(watershed.SubscriptionToken),
    subtree_subscription: watershed.SubscriptionToken,
  )
}

fn document_field() -> schema.ChannelField(
  RichDocumentSchema,
  schema.RichTextChannel,
) {
  schema.channel_field("document")
}

/// Attach the owned channel while a new instance subtree is detached.
pub fn initialize(
  document: watershed.Document(root),
  subtree: watershed.SharedMap,
) -> Result(Nil, String) {
  let typed_subtree: watershed.TypedMap(RichDocumentSchema) =
    watershed.typed(subtree)
  use channel <- result.try(watershed.create_rich_text(document))
  use newline <- result.try(
    rich_text.delta_insert_text(
      rich_text.empty_delta(),
      "\n",
      rich_text.attributes([]),
    )
    |> result.map_error(fn(_) { "rich document newline seed failed" }),
  )
  watershed.submit_rich_text(channel, newline)
  watershed.set_rich_text_field(typed_subtree, document_field(), channel)
  Ok(Nil)
}

pub fn start(
  document: watershed.Document(root),
  subtree: watershed.SharedMap,
  instance_id: String,
  invalidate: fn() -> Nil,
  config: Config,
  done: fn(Result(Running, String)) -> Nil,
) -> Nil {
  let typed_subtree: watershed.TypedMap(RichDocumentSchema) =
    watershed.typed(subtree)
  watershed.ensure_rich_text(
    document,
    typed_subtree,
    document_field(),
    fn(result) {
      case result {
        Error(reason) ->
          done(Error("rich document bootstrap failed: " <> reason))
        Ok(channel) -> {
          let channel_cell = transport_js.new_cell(channel)
          let channel_subscription =
            watershed.subscribe_rich_text(channel, fn(_) { invalidate() })
          let channel_subscription_cell =
            transport_js.new_cell(channel_subscription)
          let subtree_subscription =
            watershed.subscribe(subtree, fn(_) {
              rebind(
                document,
                typed_subtree,
                channel_cell,
                channel_subscription_cell,
                invalidate,
              )
            })
          rebind(
            document,
            typed_subtree,
            channel_cell,
            channel_subscription_cell,
            invalidate,
          )
          done(
            Ok(Running(
              instance_id:,
              config:,
              channel: channel_cell,
              channel_subscription: channel_subscription_cell,
              subtree_subscription:,
            )),
          )
        }
      }
    },
  )
}

fn rebind(
  document: watershed.Document(root),
  subtree: watershed.TypedMap(RichDocumentSchema),
  channel: transport_js.Cell(watershed.SharedRichText),
  channel_subscription: transport_js.Cell(watershed.SubscriptionToken),
  invalidate: fn() -> Nil,
) -> Nil {
  case watershed.resolve_rich_text_field(document, subtree, document_field()) {
    Ok(Some(current)) -> {
      case
        watershed.rich_text_handle_of(current)
        == watershed.rich_text_handle_of(transport_js.get_cell(channel))
      {
        True -> Nil
        False -> {
          watershed.unsubscribe(transport_js.get_cell(channel_subscription))
          transport_js.set_cell(channel, current)
          transport_js.set_cell(
            channel_subscription,
            watershed.subscribe_rich_text(current, fn(_) { invalidate() }),
          )
          invalidate()
        }
      }
    }
    Ok(None) -> Nil
    Error(_) -> Nil
  }
}

pub fn channel(running: Running) -> watershed.SharedRichText {
  transport_js.get_cell(running.channel)
}

pub fn config(running: Running) -> Config {
  running.config
}

pub fn publish(running: Running) -> #(Running, List(component.OutputEvent)) {
  #(running, [
    component.emit(
      component_event.emitted(),
      component_event.Event(
        source_instance_id: running.instance_id,
        source_kind: "project-room/rich-document",
        source_title: running.config.title,
        action: component_event.Published,
        detail: "Published an update",
      ),
    ),
  ])
}

pub fn stop(running: Running) -> Result(Nil, String) {
  watershed.unsubscribe(transport_js.get_cell(running.channel_subscription))
  watershed.unsubscribe(running.subtree_subscription)
  Ok(Nil)
}
