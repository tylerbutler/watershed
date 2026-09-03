//// Headless checklist for the project room runtime.

import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string

import watershed
import watershed/component
import watershed/id
import watershed/schema
import watershed/transport_js

import project_room_lustre/tally_payload

type ChecklistSchema

/// The static checklist configuration.
pub type Config {
  Config(title: String)
}

/// One checklist item.
pub type Item {
  Item(id: String, label: String)
}

/// The running checklist state.
pub opaque type Running {
  Running(
    config: Config,
    items: transport_js.Cell(watershed.SharedSequence),
    completed: transport_js.Cell(watershed.OrSet),
    items_subscription: transport_js.Cell(watershed.SubscriptionToken),
    completed_subscription: transport_js.Cell(watershed.SubscriptionToken),
    subtree_subscription: watershed.SubscriptionToken,
    draft: transport_js.Cell(String),
    invalidate: fn() -> Nil,
  )
}

fn items_field() -> schema.ChannelField(ChecklistSchema, schema.SequenceChannel) {
  schema.channel_field("items")
}

fn completed_field() -> schema.ChannelField(
  ChecklistSchema,
  schema.OrSetChannel,
) {
  schema.channel_field("completed")
}

pub fn config_decoder() -> Decoder(Config) {
  use title <- decode.field("title", decode.string)
  decode.success(Config(title: title))
}

pub fn encode_config(config: Config) -> Json {
  json.object([#("title", json.string(config.title))])
}

/// Attach the owned channels while a new instance subtree is detached.
pub fn initialize(
  document: watershed.Document(root),
  subtree: watershed.SharedMap,
) -> Result(Nil, String) {
  let typed_subtree: watershed.TypedMap(ChecklistSchema) =
    watershed.typed(subtree)
  use items <- result.try(watershed.create_sequence(document))
  use completed <- result.try(watershed.create_or_set(document))
  watershed.set_sequence_field(typed_subtree, items_field(), items)
  watershed.set_or_set_field(typed_subtree, completed_field(), completed)
  Ok(Nil)
}

pub fn start(
  document: watershed.Document(root),
  subtree: watershed.SharedMap,
  invalidate: fn() -> Nil,
  config: Config,
  done: fn(Result(Running, String)) -> Nil,
) -> Nil {
  let typed_subtree: watershed.TypedMap(ChecklistSchema) =
    watershed.typed(subtree)
  watershed.ensure_sequence(document, typed_subtree, items_field(), fn(items) {
    case items {
      Error(reason) ->
        done(Error("checklist items bootstrap failed: " <> reason))
      Ok(items) ->
        watershed.ensure_or_set(
          document,
          typed_subtree,
          completed_field(),
          fn(completed) {
            case completed {
              Error(reason) ->
                done(Error("checklist completion bootstrap failed: " <> reason))
              Ok(completed) -> {
                let items_cell = transport_js.new_cell(items)
                let completed_cell = transport_js.new_cell(completed)
                let items_subscription =
                  transport_js.new_cell(
                    watershed.subscribe_sequence(items, fn(_) { invalidate() }),
                  )
                let completed_subscription =
                  transport_js.new_cell(
                    watershed.subscribe_or_set(completed, fn(_) { invalidate() }),
                  )
                let running_cell = transport_js.new_cell(None)
                let subtree_subscription =
                  watershed.subscribe(subtree, fn(_) {
                    case transport_js.get_cell(running_cell) {
                      Some(running) -> rebind(document, typed_subtree, running)
                      None -> Nil
                    }
                  })
                let running =
                  Running(
                    config:,
                    items: items_cell,
                    completed: completed_cell,
                    items_subscription:,
                    completed_subscription:,
                    subtree_subscription:,
                    draft: transport_js.new_cell(""),
                    invalidate:,
                  )
                transport_js.set_cell(running_cell, Some(running))
                rebind(document, typed_subtree, running)
                done(Ok(running))
              }
            }
          },
        )
    }
  })
}

fn rebind(
  document: watershed.Document(root),
  subtree: watershed.TypedMap(ChecklistSchema),
  running: Running,
) -> Nil {
  case watershed.resolve_sequence_field(document, subtree, items_field()) {
    Ok(Some(current)) -> {
      case
        watershed.sequence_handle_of(current)
        == watershed.sequence_handle_of(items_sequence(running))
      {
        True -> Nil
        False -> {
          watershed.unsubscribe(transport_js.get_cell(
            running.items_subscription,
          ))
          transport_js.set_cell(running.items, current)
          transport_js.set_cell(
            running.items_subscription,
            watershed.subscribe_sequence(current, fn(_) { running.invalidate() }),
          )
          running.invalidate()
        }
      }
    }
    _ -> Nil
  }
  case watershed.resolve_or_set_field(document, subtree, completed_field()) {
    Ok(Some(current)) -> {
      case
        watershed.or_set_handle_of(current)
        == watershed.or_set_handle_of(completed_set(running))
      {
        True -> Nil
        False -> {
          watershed.unsubscribe(transport_js.get_cell(
            running.completed_subscription,
          ))
          transport_js.set_cell(running.completed, current)
          transport_js.set_cell(
            running.completed_subscription,
            watershed.subscribe_or_set(current, fn(_) { running.invalidate() }),
          )
          running.invalidate()
        }
      }
    }
    _ -> Nil
  }
}

pub fn config(running: Running) -> Config {
  running.config
}

pub fn items(running: Running) -> List(Item) {
  watershed.sequence_values(items_sequence(running))
  |> list.filter_map(decode_item)
  |> unique_items([], [])
}

pub fn completed(running: Running, item_id: String) -> Bool {
  watershed.or_set_contains(completed_set(running), item_id)
}

pub fn draft(running: Running) -> String {
  transport_js.get_cell(running.draft)
}

pub fn set_draft(
  running: Running,
  draft: String,
) -> #(Running, List(component.OutputEvent)) {
  transport_js.set_cell(running.draft, draft)
  running.invalidate()
  #(running, [])
}

pub fn add(
  running: Running,
) -> Result(#(Running, List(component.OutputEvent)), String) {
  let label = string.trim(draft(running))
  case label {
    "" -> Error("checklist item label must not be empty")
    _ -> {
      let item = Item(id: id.uuid_v4(), label:)
      use _ <- result.try(watershed.sequence_insert(
        items_sequence(running),
        watershed.sequence_length(items_sequence(running)),
        encode_item(item),
      ))
      transport_js.set_cell(running.draft, "")
      running.invalidate()
      Ok(#(running, []))
    }
  }
}

pub fn rename(
  running: Running,
  item_id: String,
  label: String,
) -> Result(#(Running, List(component.OutputEvent)), String) {
  let label = string.trim(label)
  case label {
    "" -> Error("checklist item label must not be empty")
    _ -> {
      use #(index, item) <- result.try(
        find_item_index(running, item_id)
        |> result.map_error(fn(_) { "checklist item does not exist" }),
      )
      use _ <- result.try(watershed.sequence_delete(
        items_sequence(running),
        index,
      ))
      use _ <- result.try(watershed.sequence_insert(
        items_sequence(running),
        index,
        encode_item(Item(..item, label: label)),
      ))
      Ok(#(running, []))
    }
  }
}

pub fn remove(
  running: Running,
  item_id: String,
) -> Result(#(Running, List(component.OutputEvent)), String) {
  delete_indexes(items_sequence(running), matching_indexes(running, item_id))
  |> result.map(fn(_) { #(running, []) })
}

pub fn complete(
  running: Running,
  item_id: String,
) -> Result(#(Running, List(component.OutputEvent)), String) {
  case find_item(running, item_id), completed(running, item_id) {
    Error(Nil), _ -> Error("checklist item does not exist")
    Ok(_), True -> Ok(#(running, []))
    Ok(_), False -> {
      watershed.or_set_add(completed_set(running), item_id)
      Ok(
        #(running, [
          component.emit(tally_payload.item_completed(), 1),
        ]),
      )
    }
  }
}

pub fn reopen(
  running: Running,
  item_id: String,
) -> Result(#(Running, List(component.OutputEvent)), String) {
  watershed.or_set_remove(completed_set(running), item_id)
  Ok(#(running, []))
}

pub fn stop(running: Running) -> Result(Nil, String) {
  watershed.unsubscribe(transport_js.get_cell(running.items_subscription))
  watershed.unsubscribe(transport_js.get_cell(running.completed_subscription))
  watershed.unsubscribe(running.subtree_subscription)
  Ok(Nil)
}

fn items_sequence(running: Running) -> watershed.SharedSequence {
  transport_js.get_cell(running.items)
}

fn completed_set(running: Running) -> watershed.OrSet {
  transport_js.get_cell(running.completed)
}

fn find_item(running: Running, item_id: String) -> Result(Item, Nil) {
  list.find(items(running), fn(item) { item.id == item_id })
}

fn find_item_index(
  running: Running,
  item_id: String,
) -> Result(#(Int, Item), Nil) {
  watershed.sequence_values(items_sequence(running))
  |> list.index_fold(Error(Nil), fn(found, value, index) {
    case found, decode_item(value) {
      Ok(_), _ -> found
      Error(Nil), Ok(item) if item.id == item_id -> Ok(#(index, item))
      Error(Nil), _ -> found
    }
  })
}

fn matching_indexes(running: Running, item_id: String) -> List(Int) {
  watershed.sequence_values(items_sequence(running))
  |> list.index_fold([], fn(indexes, value, index) {
    case decode_item(value) {
      Ok(item) if item.id == item_id -> [index, ..indexes]
      _ -> indexes
    }
  })
}

fn delete_indexes(
  sequence: watershed.SharedSequence,
  indexes: List(Int),
) -> Result(Nil, String) {
  case indexes {
    [] -> Ok(Nil)
    [index, ..rest] -> {
      use _ <- result.try(watershed.sequence_delete(sequence, index))
      delete_indexes(sequence, rest)
    }
  }
}

fn encode_item(item: Item) -> Json {
  json.object([
    #("version", json.int(1)),
    #("id", json.string(item.id)),
    #("label", json.string(item.label)),
  ])
}

fn item_decoder() -> Decoder(Item) {
  use version <- decode.field("version", decode.int)
  use id <- decode.field("id", decode.string)
  use label <- decode.field("label", decode.string)
  case version {
    1 -> decode.success(Item(id:, label:))
    _ -> decode.failure(Item(id:, label:), "Checklist item")
  }
}

fn decode_item(value: Json) -> Result(Item, Nil) {
  json.parse(json.to_string(value), item_decoder())
  |> result.map_error(fn(_) { Nil })
}

fn unique_items(
  remaining: List(Item),
  seen: List(String),
  kept: List(Item),
) -> List(Item) {
  case remaining {
    [] -> list.reverse(kept)
    [item, ..rest] ->
      case list.contains(seen, item.id) {
        True -> unique_items(rest, seen, kept)
        False -> unique_items(rest, [item.id, ..seen], [item, ..kept])
      }
  }
}
