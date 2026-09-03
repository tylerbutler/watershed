//// Headless task collection for the project room runtime.

import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

import watershed
import watershed/component
import watershed/schema
import watershed/transport_js

import project_room_lustre/payload

type TaskCollectionSchema

/// The static config for the task collection.
pub type Config {
  Config(title: String)
}

/// The running task collection state.
pub opaque type Running {
  Running(
    order: transport_js.Cell(watershed.SharedSequence),
    records: transport_js.Cell(watershed.SharedMap),
    order_subscription: transport_js.Cell(watershed.SubscriptionToken),
    records_subscription: transport_js.Cell(watershed.SubscriptionToken),
    subtree_subscription: watershed.SubscriptionToken,
  )
}

fn order_field() -> schema.ChannelField(
  TaskCollectionSchema,
  schema.SequenceChannel,
) {
  schema.channel_field("task_order")
}

fn records_field() -> schema.ChannelField(
  TaskCollectionSchema,
  schema.MapChannel,
) {
  schema.channel_field("task_records")
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
  let typed_subtree: watershed.TypedMap(TaskCollectionSchema) =
    watershed.typed(subtree)
  use order <- result.try(watershed.create_sequence(document))
  use records <- result.try(watershed.create_map(document))
  watershed.set_sequence_field(typed_subtree, order_field(), order)
  watershed.set_map_field(typed_subtree, records_field(), records)
  Ok(Nil)
}

pub fn start(
  document: watershed.Document(root),
  subtree: watershed.SharedMap,
  invalidate: fn() -> Nil,
  _config: Config,
  done: fn(Result(Running, String)) -> Nil,
) -> Nil {
  let typed_subtree: watershed.TypedMap(TaskCollectionSchema) =
    watershed.typed(subtree)
  watershed.ensure_sequence(document, typed_subtree, order_field(), fn(order) {
    case order {
      Error(reason) -> done(Error("task order bootstrap failed: " <> reason))
      Ok(order) ->
        watershed.ensure_map(
          document,
          typed_subtree,
          records_field(),
          fn(records) {
            case records {
              Error(reason) ->
                done(Error("task records bootstrap failed: " <> reason))
              Ok(records) ->
                case seed_if_empty(order, records) {
                  Error(reason) -> done(Error(reason))
                  Ok(Nil) -> {
                    let order_cell = transport_js.new_cell(order)
                    let records_cell = transport_js.new_cell(records)
                    let order_subscription =
                      watershed.subscribe_sequence(order, fn(_) { invalidate() })
                    let records_subscription =
                      watershed.subscribe(records, fn(_) { invalidate() })
                    let order_subscription_cell =
                      transport_js.new_cell(order_subscription)
                    let records_subscription_cell =
                      transport_js.new_cell(records_subscription)
                    let subtree_subscription =
                      watershed.subscribe(subtree, fn(_) {
                        rebind(
                          document,
                          typed_subtree,
                          order_cell,
                          records_cell,
                          order_subscription_cell,
                          records_subscription_cell,
                          invalidate,
                        )
                      })
                    rebind(
                      document,
                      typed_subtree,
                      order_cell,
                      records_cell,
                      order_subscription_cell,
                      records_subscription_cell,
                      invalidate,
                    )
                    done(
                      Ok(Running(
                        order: order_cell,
                        records: records_cell,
                        order_subscription: order_subscription_cell,
                        records_subscription: records_subscription_cell,
                        subtree_subscription: subtree_subscription,
                      )),
                    )
                  }
                }
            }
          },
        )
    }
  })
}

fn rebind(
  document: watershed.Document(root),
  subtree: watershed.TypedMap(TaskCollectionSchema),
  order: transport_js.Cell(watershed.SharedSequence),
  records: transport_js.Cell(watershed.SharedMap),
  order_subscription: transport_js.Cell(watershed.SubscriptionToken),
  records_subscription: transport_js.Cell(watershed.SubscriptionToken),
  invalidate: fn() -> Nil,
) -> Nil {
  case watershed.resolve_sequence_field(document, subtree, order_field()) {
    Ok(Some(current)) -> {
      case
        watershed.sequence_handle_of(current)
        == watershed.sequence_handle_of(transport_js.get_cell(order))
      {
        True -> Nil
        False -> {
          watershed.unsubscribe(transport_js.get_cell(order_subscription))
          transport_js.set_cell(order, current)
          transport_js.set_cell(
            order_subscription,
            watershed.subscribe_sequence(current, fn(_) { invalidate() }),
          )
          invalidate()
        }
      }
    }
    Ok(_) | Error(_) -> Nil
  }
  case watershed.resolve_map_field(document, subtree, records_field()) {
    Ok(Some(current)) -> {
      case
        watershed.handle_of(current)
        == watershed.handle_of(transport_js.get_cell(records))
      {
        True -> Nil
        False -> {
          watershed.unsubscribe(transport_js.get_cell(records_subscription))
          transport_js.set_cell(records, current)
          transport_js.set_cell(
            records_subscription,
            watershed.subscribe(current, fn(_) { invalidate() }),
          )
          invalidate()
        }
      }
    }
    Ok(_) | Error(_) -> Nil
  }
}

fn seed_if_empty(
  order: watershed.SharedSequence,
  records: watershed.SharedMap,
) -> Result(Nil, String) {
  seed(order, records, seed_tasks())
}

fn seed(
  order: watershed.SharedSequence,
  records: watershed.SharedMap,
  tasks: List(payload.TaskPayload),
) -> Result(Nil, String) {
  case tasks {
    [] -> Ok(Nil)
    [task, ..rest] -> {
      ensure_record(records, task)
      use _ <- result.try(ensure_order_entry(order, task.task_id))
      seed(order, records, rest)
    }
  }
}

fn ensure_record(
  records: watershed.SharedMap,
  task: payload.TaskPayload,
) -> Nil {
  case watershed.has(records, task.task_id) {
    True -> Nil
    False -> watershed.set(records, task.task_id, payload.encode(task))
  }
}

fn ensure_order_entry(
  order: watershed.SharedSequence,
  task_id: String,
) -> Result(Nil, String) {
  case list.contains(all_ordered_task_ids(order), task_id) {
    True -> Ok(Nil)
    False ->
      watershed.sequence_insert(
        order,
        watershed.sequence_length(order),
        json.string(task_id),
      )
  }
}

fn seed_tasks() -> List(payload.TaskPayload) {
  [
    payload.TaskPayload(
      task_id: "task-1",
      title: "Draft kickoff plan",
      completed: False,
    ),
    payload.TaskPayload(
      task_id: "task-2",
      title: "Collect team notes",
      completed: False,
    ),
    payload.TaskPayload(
      task_id: "task-3",
      title: "Post status update",
      completed: False,
    ),
  ]
}

pub fn order(running: Running) -> watershed.SharedSequence {
  transport_js.get_cell(running.order)
}

pub fn records(running: Running) -> watershed.SharedMap {
  transport_js.get_cell(running.records)
}

pub fn tasks(running: Running) -> List(payload.TaskPayload) {
  effective_ordered_task_ids(order(running))
  |> list.filter_map(fn(task_id) {
    case task(running, task_id) {
      Some(found) -> Ok(found)
      None -> Error(Nil)
    }
  })
}

pub fn task(running: Running, task_id: String) -> Option(payload.TaskPayload) {
  case watershed.get(records(running), task_id) {
    Error(Nil) -> None
    Ok(value) ->
      case payload.decode(value) {
        Ok(task) -> Some(task)
        Error(_) -> None
      }
  }
}

pub fn select(
  running: Running,
  task_id: String,
) -> #(Running, List(component.OutputEvent)) {
  case task(running, task_id) {
    None -> #(running, [])
    Some(found) -> #(running, [
      component.emit(payload.task_selected(), found),
    ])
  }
}

pub fn complete(
  running: Running,
  task_id: String,
) -> #(Running, List(component.OutputEvent)) {
  case task(running, task_id) {
    None -> #(running, [])
    Some(found) if found.completed -> #(running, [])
    Some(found) -> {
      let completed = payload.TaskPayload(..found, completed: True)
      watershed.set(records(running), task_id, payload.encode(completed))
      #(running, [component.emit(payload.task_completed(), completed)])
    }
  }
}

pub fn stop(running: Running) -> Result(Nil, String) {
  watershed.unsubscribe(transport_js.get_cell(running.order_subscription))
  watershed.unsubscribe(transport_js.get_cell(running.records_subscription))
  watershed.unsubscribe(running.subtree_subscription)
  Ok(Nil)
}

fn effective_ordered_task_ids(order: watershed.SharedSequence) -> List(String) {
  unique_task_ids(all_ordered_task_ids(order), [], [])
}

fn all_ordered_task_ids(order: watershed.SharedSequence) -> List(String) {
  watershed.sequence_values(order)
  |> list.filter_map(fn(value) {
    case json.parse(json.to_string(value), decode.string) {
      Ok(task_id) -> Ok(task_id)
      Error(_) -> Error(Nil)
    }
  })
}

fn unique_task_ids(
  remaining: List(String),
  seen: List(String),
  kept: List(String),
) -> List(String) {
  case remaining {
    [] -> list.reverse(kept)
    [task_id, ..rest] ->
      case list.contains(seen, task_id) {
        True -> unique_task_ids(rest, seen, kept)
        False -> unique_task_ids(rest, [task_id, ..seen], [task_id, ..kept])
      }
  }
}
