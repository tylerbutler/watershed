//// Fluid container, datastore, and channel envelopes for the pinned profile.
////
//// DDS contents stay opaque until the runtime selects their registered codec.

import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import watershed/fluid_ids
import watershed/handle
import watershed/wire
import watershed/wire/fluid_summary

pub type Route {
  Route(data_store_id: String, channel_id: String)
}

pub fn route_key(route: Route) -> Result(String, ContainerError) {
  let Route(data_store_id, channel_id) = route
  use _ <- result.try(validate_route(data_store_id, channel_id, "route"))
  let key =
    fluid_summary.encode_component(data_store_id)
    <> "/"
    <> fluid_summary.encode_component(channel_id)
  use _ <- result.try(
    handle.encode_path("/" <> key)
    |> result.map_error(fn(_) {
      InvalidRoute("route", "invalid path component")
    }),
  )
  Ok(key)
}

pub fn route_from_path(path: String) -> Result(Route, ContainerError) {
  use _ <- result.try(
    handle.encode_path(path)
    |> result.map_error(fn(_) { InvalidRoute("route", "invalid channel path") }),
  )
  case string.split(path, "/") {
    ["", datastore, channel] -> {
      use datastore <- result.try(
        handle.decode_component(datastore)
        |> result.map_error(fn(_) {
          InvalidRoute("route", "invalid datastore escape")
        }),
      )
      use channel <- result.try(
        handle.decode_component(channel)
        |> result.map_error(fn(_) {
          InvalidRoute("route", "invalid channel escape")
        }),
      )
      Ok(Route(datastore, channel))
    }
    _ -> Error(InvalidRoute("route", "expected a datastore and channel path"))
  }
}

pub type MessageKind {
  ChannelOperation(route: Route, contents: Json)
  IdAllocation(range: fluid_ids.CreationRange)
  DatastoreAttach(data_store_id: String, contents: Json)
  DatastoreAlias(data_store_id: String, alias: String)
  ChannelAttach(route: Route, channel_type: String, snapshot: Json)
}

pub type ContainerError {
  MalformedMessage(location: String, detail: String)
  InvalidRoute(location: String, detail: String)
  UnsupportedMessage(kind: String)
  UnsupportedCompression(format: String)
}

pub type ContainerMessage {
  ContainerMessage(
    kind: MessageKind,
    index_in_batch: Int,
    metadata: Option(Json),
  )
}

pub type DecodedBatch {
  DecodedBatch(
    grouped: Bool,
    metadata: Option(Json),
    messages: List(ContainerMessage),
  )
}

type GroupedItem {
  GroupedItem(
    contents: Json,
    metadata: Option(Json),
    compression: Option(String),
  )
}

pub fn decode(
  contents: Json,
  metadata: Option(Json),
) -> Result(DecodedBatch, ContainerError) {
  use compression <- result.try(
    json.parse(json.to_string(contents), compression_decoder())
    |> result.map_error(fn(_) {
      MalformedMessage("message", "invalid compression field")
    }),
  )
  use _ <- result.try(case compression {
    Some(format) -> Error(UnsupportedCompression(format))
    None -> Ok(Nil)
  })
  use message_type <- result.try(
    json.parse(json.to_string(contents), message_type_decoder())
    |> result.map_error(fn(_) {
      MalformedMessage("message", "missing message type")
    }),
  )
  case message_type {
    "groupedBatch" -> decode_group(contents, metadata)
    _ -> {
      use kind <- result.try(decode_message(contents, "message"))
      Ok(
        DecodedBatch(grouped: False, metadata: metadata, messages: [
          ContainerMessage(kind, 0, metadata),
        ]),
      )
    }
  }
}

fn compression_decoder() -> Decoder(Option(String)) {
  use compression <- decode.optional_field(
    "compression",
    None,
    decode.map(decode.string, Some),
  )
  decode.success(compression)
}

pub fn encode(message: MessageKind) -> Result(Json, ContainerError) {
  case message {
    ChannelOperation(Route(data_store_id, channel_id), contents) -> {
      use _ <- result.try(validate_route(data_store_id, channel_id, "route"))
      Ok(component_message(
        data_store_id,
        json.object([
          #("type", json.string("op")),
          #(
            "content",
            json.object([
              #("address", json.string(channel_id)),
              #("contents", contents),
            ]),
          ),
        ]),
      ))
    }
    IdAllocation(range) -> {
      use contents <- result.try(
        fluid_ids.creation_range_to_json(range)
        |> result.map_error(fn(_) {
          MalformedMessage("idAllocation", "invalid creation range")
        }),
      )
      Ok(
        json.object([
          #("type", json.string("idAllocation")),
          #("contents", contents),
        ]),
      )
    }
    DatastoreAttach(data_store_id, contents) -> {
      use #(id, _, _) <- result.try(decode_attach(contents, "datastore attach"))
      use _ <- result.try(case id == data_store_id {
        True -> Ok(Nil)
        False ->
          Error(InvalidRoute(
            "datastore attach",
            "datastore identity does not match",
          ))
      })
      Ok(
        json.object([
          #("type", json.string("attach")),
          #("contents", contents),
        ]),
      )
    }
    DatastoreAlias(data_store_id, alias) -> {
      use _ <- result.try(nonempty(data_store_id, "alias datastore"))
      use _ <- result.try(nonempty(alias, "alias"))
      Ok(
        json.object([
          #("type", json.string("alias")),
          #(
            "contents",
            json.object([
              #("internalId", json.string(data_store_id)),
              #("alias", json.string(alias)),
            ]),
          ),
        ]),
      )
    }
    ChannelAttach(Route(data_store_id, channel_id), channel_type, snapshot) -> {
      use _ <- result.try(validate_route(
        data_store_id,
        channel_id,
        "channel attach",
      ))
      use _ <- result.try(nonempty(channel_type, "channel type"))
      use _ <- result.try(validate_snapshot(snapshot, "channel attach"))
      Ok(component_message(
        data_store_id,
        json.object([
          #("type", json.string("attach")),
          #(
            "content",
            json.object([
              #("id", json.string(channel_id)),
              #("type", json.string(channel_type)),
              #("snapshot", snapshot),
            ]),
          ),
        ]),
      ))
    }
  }
}

pub fn encode_batch(batch: DecodedBatch) -> Result(Json, ContainerError) {
  case batch {
    DecodedBatch(False, _, [ContainerMessage(kind, 0, _)]) -> encode(kind)
    DecodedBatch(False, _, _) ->
      Error(MalformedMessage(
        "batch",
        "an ungrouped batch must contain one message",
      ))
    DecodedBatch(True, _, messages) -> {
      use encoded <- result.try(
        messages
        |> list.index_map(fn(message, index) { #(message, index) })
        |> list.try_map(fn(entry) {
          let #(ContainerMessage(kind, actual, metadata), expected) = entry
          use _ <- result.try(case actual == expected {
            True -> Ok(Nil)
            False ->
              Error(MalformedMessage(
                "batch",
                "message indices are not contiguous",
              ))
          })
          use contents <- result.try(encode(kind))
          let fields = [#("contents", contents)]
          let fields = case metadata {
            None -> fields
            Some(metadata) -> [#("metadata", metadata), ..fields]
          }
          Ok(json.object(list.reverse(fields)))
        }),
      )
      Ok(
        json.object([
          #("type", json.string("groupedBatch")),
          #("contents", json.array(encoded, fn(value) { value })),
        ]),
      )
    }
  }
}

fn decode_group(
  contents: Json,
  metadata: Option(Json),
) -> Result(DecodedBatch, ContainerError) {
  use items <- result.try(
    json.parse(json.to_string(contents), grouped_items_decoder())
    |> result.map_error(fn(_) {
      MalformedMessage("groupedBatch", "invalid grouped batch")
    }),
  )
  use messages <- result.try(
    items
    |> list.index_map(fn(item, index) { #(item, index) })
    |> list.try_map(fn(entry) {
      let #(GroupedItem(contents, inner_metadata, compression), index) = entry
      use _ <- result.try(case compression {
        Some(format) -> Error(UnsupportedCompression(format))
        None -> Ok(Nil)
      })
      use kind <- result.try(decode_message(
        contents,
        "groupedBatch[" <> index_to_string(index) <> "]",
      ))
      Ok(ContainerMessage(kind, index, inner_metadata))
    }),
  )
  Ok(DecodedBatch(True, metadata, messages))
}

fn grouped_item_decoder() -> Decoder(GroupedItem) {
  use contents <- decode.field("contents", wire.json_value_decoder())
  use metadata <- decode.optional_field(
    "metadata",
    None,
    decode.map(wire.json_value_decoder(), Some),
  )
  use compression <- decode.optional_field(
    "compression",
    None,
    decode.map(decode.string, Some),
  )
  decode.success(GroupedItem(contents, metadata, compression))
}

fn grouped_items_decoder() -> Decoder(List(GroupedItem)) {
  use items <- decode.field("contents", decode.list(grouped_item_decoder()))
  decode.success(items)
}

fn message_type_decoder() -> Decoder(String) {
  use message_type <- decode.field("type", decode.string)
  decode.success(message_type)
}

fn decode_message(
  contents: Json,
  location: String,
) -> Result(MessageKind, ContainerError) {
  use decoded <- result.try(
    json.parse(json.to_string(contents), message_decoder(location))
    |> result.map_error(fn(_) {
      MalformedMessage(location, "invalid message structure")
    }),
  )
  decoded
}

fn message_decoder(
  location: String,
) -> Decoder(Result(MessageKind, ContainerError)) {
  use message_type <- decode.field("type", decode.string)
  case message_type {
    "component" -> component_decoder(location)
    "idAllocation" -> {
      use contents <- decode.field("contents", wire.json_value_decoder())
      decode.success(
        fluid_ids.creation_range_from_json(contents)
        |> result.map(IdAllocation)
        |> result.map_error(fn(_) {
          MalformedMessage(location, "invalid creation range")
        }),
      )
    }
    "attach" -> {
      use contents <- decode.field("contents", wire.json_value_decoder())
      decode.success(
        decode_attach(contents, location)
        |> result.map(fn(attach) { DatastoreAttach(attach.0, contents) }),
      )
    }
    "alias" -> {
      use alias_contents <- decode.field("contents", alias_decoder())
      let #(data_store_id, alias) = alias_contents
      decode.success(
        case nonempty(data_store_id, location), nonempty(alias, location) {
          Ok(_), Ok(_) -> Ok(DatastoreAlias(data_store_id, alias))
          Error(error), _ -> Error(error)
          _, Error(error) -> Error(error)
        },
      )
    }
    _ -> decode.success(Error(UnsupportedMessage(message_type)))
  }
}

fn component_decoder(
  location: String,
) -> Decoder(Result(MessageKind, ContainerError)) {
  use component <- decode.field("contents", component_contents_decoder())
  let #(data_store_id, data_store_message) = component
  decode.success(case nonempty(data_store_id, location) {
    Error(error) -> Error(error)
    Ok(_) ->
      decode_datastore_message(data_store_message, data_store_id, location)
  })
}

fn component_contents_decoder() -> Decoder(#(String, Json)) {
  use data_store_id <- decode.field("address", decode.string)
  use data_store_message <- decode.field("contents", wire.json_value_decoder())
  decode.success(#(data_store_id, data_store_message))
}

fn decode_datastore_message(
  contents: Json,
  data_store_id: String,
  location: String,
) -> Result(MessageKind, ContainerError) {
  use decoded <- result.try(
    json.parse(
      json.to_string(contents),
      datastore_message_decoder(data_store_id, location),
    )
    |> result.map_error(fn(_) {
      MalformedMessage(location, "invalid datastore message")
    }),
  )
  decoded
}

fn datastore_message_decoder(
  data_store_id: String,
  location: String,
) -> Decoder(Result(MessageKind, ContainerError)) {
  use message_type <- decode.field("type", decode.string)
  case message_type {
    "op" -> {
      use operation <- decode.field("content", channel_operation_decoder())
      let #(channel_id, contents) = operation
      decode.success(
        validate_route(data_store_id, channel_id, location)
        |> result.map(fn(_) {
          ChannelOperation(Route(data_store_id, channel_id), contents)
        }),
      )
    }
    "attach" -> {
      use attach <- decode.field("content", wire.json_value_decoder())
      decode.success(channel_attach(attach, data_store_id, location))
    }
    _ -> decode.success(Error(UnsupportedMessage(message_type)))
  }
}

fn channel_operation_decoder() -> Decoder(#(String, Json)) {
  use channel_id <- decode.field("address", decode.string)
  use contents <- decode.field("contents", wire.json_value_decoder())
  decode.success(#(channel_id, contents))
}

fn channel_attach(
  attach: Json,
  data_store_id: String,
  location: String,
) -> Result(MessageKind, ContainerError) {
  use decoded <- result.try(decode_attach(attach, location))
  use _ <- result.try(validate_route(data_store_id, decoded.0, location))
  Ok(ChannelAttach(Route(data_store_id, decoded.0), decoded.1, decoded.2))
}

fn alias_decoder() -> Decoder(#(String, String)) {
  use data_store_id <- decode.field("internalId", decode.string)
  use alias <- decode.field("alias", decode.string)
  decode.success(#(data_store_id, alias))
}

fn decode_attach(
  contents: Json,
  location: String,
) -> Result(#(String, String, Json), ContainerError) {
  use decoded <- result.try(
    json.parse(json.to_string(contents), attach_decoder())
    |> result.map_error(fn(_) {
      MalformedMessage(location, "invalid attach message")
    }),
  )
  use _ <- result.try(nonempty(decoded.0, location))
  use _ <- result.try(nonempty(decoded.1, location))
  use _ <- result.try(validate_snapshot(decoded.2, location))
  Ok(decoded)
}

fn attach_decoder() -> Decoder(#(String, String, Json)) {
  use id <- decode.field("id", decode.string)
  use channel_type <- decode.field("type", decode.string)
  use snapshot <- decode.field("snapshot", wire.json_value_decoder())
  decode.success(#(id, channel_type, snapshot))
}

fn validate_snapshot(
  snapshot: Json,
  location: String,
) -> Result(Nil, ContainerError) {
  json.parse(json.to_string(snapshot), snapshot_decoder())
  |> result.map_error(fn(_) {
    MalformedMessage(location, "invalid attach snapshot")
  })
}

fn snapshot_decoder() -> Decoder(Nil) {
  use _ <- decode.field("entries", decode.list(snapshot_entry_decoder()))
  decode.success(Nil)
}

fn snapshot_entry_decoder() -> Decoder(Nil) {
  use path <- decode.field("path", decode.string)
  use mode <- decode.field("mode", decode.string)
  use entry_type <- decode.field("type", decode.string)
  case path != "", valid_mode(mode), entry_type {
    True, True, "Blob" -> {
      use _ <- decode.field("value", wire.json_value_decoder())
      decode.success(Nil)
    }
    True, True, "Tree" -> {
      use _ <- decode.field("value", decode.recursive(snapshot_decoder))
      decode.success(Nil)
    }
    True, True, "Attachment" -> {
      use _ <- decode.field("value", attachment_value_decoder())
      decode.success(Nil)
    }
    _, _, _ -> decode.failure(Nil, "valid snapshot entry")
  }
}

fn attachment_value_decoder() -> Decoder(Nil) {
  use id <- decode.field("id", decode.string)
  case id == "" {
    True -> decode.failure(Nil, "attachment identity")
    False -> decode.success(Nil)
  }
}

fn valid_mode(mode: String) -> Bool {
  mode == "100644" || mode == "100755" || mode == "040000" || mode == "120000"
}

fn component_message(data_store_id: String, contents: Json) -> Json {
  json.object([
    #("type", json.string("component")),
    #(
      "contents",
      json.object([
        #("address", json.string(data_store_id)),
        #("contents", contents),
      ]),
    ),
  ])
}

fn validate_route(
  data_store_id: String,
  channel_id: String,
  location: String,
) -> Result(Nil, ContainerError) {
  case data_store_id == "", channel_id == "" {
    True, _ -> Error(InvalidRoute(location, "empty datastore identity"))
    _, True -> Error(InvalidRoute(location, "empty channel identity"))
    False, False -> Ok(Nil)
  }
}

fn nonempty(value: String, location: String) -> Result(Nil, ContainerError) {
  case value == "" {
    True -> Error(MalformedMessage(location, "empty required string"))
    False -> Ok(Nil)
  }
}

fn index_to_string(index: Int) -> String {
  case index {
    0 -> "0"
    1 -> "1"
    2 -> "2"
    3 -> "3"
    _ -> "many"
  }
}
