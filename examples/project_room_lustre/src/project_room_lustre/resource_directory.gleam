//// Headless directory-backed resource directory for the project room runtime.

import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string

import watershed
import watershed/component
import watershed/directory_kernel
import watershed/schema
import watershed/transport_js

import project_room_lustre/component_event

type ResourceDirectorySchema

pub type Config {
  Config(title: String)
}

pub type Entry {
  Entry(key: String, value: String)
}

pub opaque type Running {
  Running(
    instance_id: String,
    config: Config,
    directory: transport_js.Cell(watershed.SharedDirectory),
    directory_subscription: transport_js.Cell(watershed.SubscriptionToken),
    subtree_subscription: watershed.SubscriptionToken,
    path: transport_js.Cell(String),
    folder_draft: transport_js.Cell(String),
    entry_key_draft: transport_js.Cell(String),
    entry_value_draft: transport_js.Cell(String),
    stopped: transport_js.Cell(Bool),
    invalidate: fn() -> Nil,
  )
}

fn tree_field() -> schema.ChannelField(
  ResourceDirectorySchema,
  schema.DirectoryChannel,
) {
  schema.channel_field("tree")
}

pub fn encode_config(config: Config) -> Json {
  json.object([#("title", json.string(config.title))])
}

pub fn config_decoder() -> Decoder(Config) {
  use title <- decode.field("title", decode.string)
  decode.success(Config(title: title))
}

pub fn initialize(
  document: watershed.Document(root),
  subtree: watershed.SharedMap,
) -> Result(Nil, String) {
  let typed_subtree: watershed.TypedMap(ResourceDirectorySchema) =
    watershed.typed(subtree)
  use directory <- result.try(watershed.create_directory(document))
  watershed.set_directory_field(typed_subtree, tree_field(), directory)
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
  let typed_subtree: watershed.TypedMap(ResourceDirectorySchema) =
    watershed.typed(subtree)
  watershed.ensure_directory(document, typed_subtree, tree_field(), fn(result) {
    case result {
      Error(reason) ->
        done(Error("resource directory bootstrap failed: " <> reason))
      Ok(directory) -> {
        let directory_cell = transport_js.new_cell(directory)
        let path = transport_js.new_cell("/")
        let stopped = transport_js.new_cell(False)
        let directory_subscription =
          transport_js.new_cell(subscribe_directory(
            directory,
            path,
            stopped,
            invalidate,
          ))
        let directory_subscription_cell = directory_subscription
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
            instance_id:,
            config:,
            directory: directory_cell,
            directory_subscription: directory_subscription_cell,
            subtree_subscription:,
            path:,
            folder_draft: transport_js.new_cell(""),
            entry_key_draft: transport_js.new_cell(""),
            entry_value_draft: transport_js.new_cell(""),
            stopped:,
            invalidate:,
          )
        transport_js.set_cell(running_cell, Some(running))
        rebind(document, typed_subtree, running)
        done(Ok(running))
      }
    }
  })
}

fn subscribe_directory(
  directory: watershed.SharedDirectory,
  path: transport_js.Cell(String),
  stopped: transport_js.Cell(Bool),
  invalidate: fn() -> Nil,
) -> watershed.SubscriptionToken {
  watershed.subscribe_directory(directory, fn(event) {
    case transport_js.get_cell(stopped) {
      True -> Nil
      False -> {
        case event {
          directory_kernel.SubDirectoryDeleted(deleted, _) ->
            case path_covers(deleted, transport_js.get_cell(path)) {
              True -> transport_js.set_cell(path, "/")
              False -> Nil
            }
          _ -> Nil
        }
        invalidate()
      }
    }
  })
}

fn rebind(
  document: watershed.Document(root),
  subtree: watershed.TypedMap(ResourceDirectorySchema),
  running: Running,
) -> Nil {
  case transport_js.get_cell(running.stopped) {
    True -> Nil
    False ->
      case watershed.resolve_directory_field(document, subtree, tree_field()) {
        Ok(Some(current)) -> {
          case
            watershed.directory_handle_of(current)
            == watershed.directory_handle_of(current_directory(running))
          {
            True -> Nil
            False -> {
              watershed.unsubscribe(transport_js.get_cell(
                running.directory_subscription,
              ))
              transport_js.set_cell(running.directory, current)
              transport_js.set_cell(
                running.directory_subscription,
                subscribe_directory(
                  current,
                  running.path,
                  running.stopped,
                  running.invalidate,
                ),
              )
              running.invalidate()
            }
          }
        }
        _ -> Nil
      }
  }
}

fn current_directory(running: Running) -> watershed.SharedDirectory {
  transport_js.get_cell(running.directory)
}

pub fn path(running: Running) -> String {
  normalize_path(transport_js.get_cell(running.path))
}

pub fn entries(running: Running) -> List(Entry) {
  watershed.directory_entries(current_directory(running), path(running))
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
  |> list.filter_map(fn(pair) {
    let #(key, value) = pair
    case json_string(value) {
      Ok(value) -> Ok(Entry(key:, value:))
      Error(_) -> Error(Nil)
    }
  })
}

pub fn folders(running: Running) -> List(String) {
  watershed.directory_subdirectories(current_directory(running), path(running))
  |> list.sort(string.compare)
}

pub fn open_folder(running: Running, name: String) -> Result(Running, String) {
  use name <- result.try(valid_name(name))
  case
    watershed.directory_has_subdirectory(
      current_directory(running),
      path(running),
      name,
    )
  {
    True -> {
      transport_js.set_cell(running.path, join_path(path(running), name))
      Ok(running)
    }
    False -> Error("folder not found: " <> name)
  }
}

pub fn open_parent(running: Running) -> Running {
  transport_js.set_cell(running.path, parent_path(path(running)))
  running
}

pub fn create_folder(
  running: Running,
  name: String,
) -> Result(#(Running, List(component.OutputEvent)), String) {
  use name <- result.try(valid_name(name))
  let current_path = path(running)
  watershed.directory_create_subdirectory(
    current_directory(running),
    current_path,
    name,
  )
  Ok(
    #(running, [
      folder_event(
        running,
        component_event.FolderChanged,
        "Created folder " <> join_path(current_path, name),
      ),
    ]),
  )
}

pub fn delete_folder(
  running: Running,
  name: String,
) -> Result(#(Running, List(component.OutputEvent)), String) {
  use name <- result.try(valid_name(name))
  let current_path = path(running)
  watershed.directory_delete_subdirectory(
    current_directory(running),
    current_path,
    name,
  )
  Ok(
    #(running, [
      folder_event(
        running,
        component_event.FolderChanged,
        "Deleted folder " <> join_path(current_path, name),
      ),
    ]),
  )
}

pub fn set_entry(
  running: Running,
  key: String,
  value: String,
) -> Result(#(Running, List(component.OutputEvent)), String) {
  use key <- result.try(valid_name(key))
  let current_path = path(running)
  watershed.directory_set(
    current_directory(running),
    current_path,
    key,
    json.string(value),
  )
  Ok(
    #(running, [
      folder_event(
        running,
        component_event.EntryChanged,
        "Updated " <> join_path(current_path, key),
      ),
    ]),
  )
}

pub fn delete_entry(
  running: Running,
  key: String,
) -> Result(#(Running, List(component.OutputEvent)), String) {
  use key <- result.try(valid_name(key))
  let current_path = path(running)
  watershed.directory_delete(current_directory(running), current_path, key)
  Ok(
    #(running, [
      folder_event(
        running,
        component_event.EntryChanged,
        "Deleted " <> join_path(current_path, key),
      ),
    ]),
  )
}

fn folder_event(
  running: Running,
  action: component_event.Action,
  detail: String,
) -> component.OutputEvent {
  component.emit(
    component_event.emitted(),
    component_event.Event(
      source_instance_id: running.instance_id,
      source_kind: "project-room/resource-directory",
      source_title: running.config.title,
      action:,
      detail:,
    ),
  )
}

fn json_string(value: Json) -> Result(String, Nil) {
  json.to_string(value)
  |> json.parse(decode.string)
  |> result.map_error(fn(_) { Nil })
}

fn valid_name(name: String) -> Result(String, String) {
  let name = string.trim(name)
  case name == "" || string.contains(name, "/") {
    True -> Error("names cannot be empty or contain /")
    False -> Ok(name)
  }
}

fn normalize_path(path: String) -> String {
  let segments =
    string.split(path, "/")
    |> list.filter(fn(segment) { segment != "" })
  case segments {
    [] -> "/"
    _ -> "/" <> string.join(segments, "/")
  }
}

fn join_path(path: String, name: String) -> String {
  case normalize_path(path) {
    "/" -> "/" <> name
    path -> path <> "/" <> name
  }
}

fn parent_path(path: String) -> String {
  case string.split(normalize_path(path), "/") {
    ["", ..segments] ->
      case list.reverse(segments) {
        [] -> "/"
        [_, ..rest] ->
          case list.reverse(rest) {
            [] -> "/"
            names -> "/" <> string.join(names, "/")
          }
      }
    _ -> "/"
  }
}

fn path_covers(deleted: String, target: String) -> Bool {
  case normalize_path(deleted) {
    "/" -> True
    normalized_deleted -> {
      let target = normalize_path(target)
      target == normalized_deleted
      || string.starts_with(target, normalized_deleted <> "/")
    }
  }
}

pub fn stop(running: Running) -> Result(Nil, String) {
  case transport_js.get_cell(running.stopped) {
    True -> Ok(Nil)
    False -> {
      transport_js.set_cell(running.stopped, True)
      watershed.unsubscribe(transport_js.get_cell(
        running.directory_subscription,
      ))
      watershed.unsubscribe(running.subtree_subscription)
      Ok(Nil)
    }
  }
}
