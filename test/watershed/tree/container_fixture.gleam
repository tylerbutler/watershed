import gleam/bit_array
import gleam/dict
import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/uri
import watershed/fluid_ids
import watershed/handle
import watershed/wire
import watershed/wire/fluid_container.{
  type ContainerMessage, type DecodedBatch, type MessageKind, type Route,
  ChannelAttach, ChannelOperation, ContainerMessage, DatastoreAlias,
  DatastoreAttach, DecodedBatch, IdAllocation, Route,
}

type DecodeCase {
  DecodeCase(id: String, contents: Json, metadata: Option(Json))
}

type HandleCase {
  HandleCase(id: String, value: Json, context_path: String)
}

type EncodeCase {
  EncodeMessage(id: String, message: MessageKind)
  EncodeBatch(id: String, batch: DecodedBatch)
}

type OuterMessage {
  OuterMessage(
    client_id: String,
    client_sequence_number: Int,
    minimum_sequence_number: Int,
    reference_sequence_number: Int,
    sequence_number: Int,
    contents: String,
    metadata: Option(Json),
  )
}

pub fn run(input: Json) -> Result(Json, String) {
  use decode_cases <- result.try(read(
    input,
    ["decodeCases"],
    decode.list(decode_case_decoder()),
  ))
  use grouped <- result.try(read(
    input,
    ["groupedWireMessages"],
    decode.list(outer_message_decoder()),
  ))
  use bootstrap <- result.try(read(
    input,
    ["bootstrapMessages"],
    decode.list(outer_message_decoder()),
  ))
  use handles <- result.try(read(
    input,
    ["handleCases"],
    decode.list(handle_case_decoder()),
  ))
  use encode_cases <- result.try(read(
    input,
    ["encodeCases"],
    decode.list(encode_case_decoder()),
  ))
  use snapshot <- result.try(field(input, ["initialSnapshot"]))
  use decoded <- result.try(list.try_map(decode_cases, decode_case))
  use grouped <- result.try(case grouped {
    [first, ..] -> grouped_observation(first)
    [] -> Error("container input has no grouped wire message")
  })
  use bootstrap_messages <- result.try(bootstrap_messages_observation(
    bootstrap,
    snapshot,
  ))
  use handles <- result.try(list.try_map(handles, handle_observation))
  use encoded <- result.try(list.try_map(encode_cases, encode_observation))
  use bootstrap <- result.try(bootstrap_observation(snapshot))
  let observations =
    list.flatten([
      decoded,
      [grouped, bootstrap_messages],
      handles,
      encoded,
      [bootstrap],
    ])
  Ok(
    json.object([
      #("observations", array(observations)),
    ]),
  )
}

fn decode_case(value: DecodeCase) -> Result(Json, String) {
  let DecodeCase(id, contents, metadata) = value
  use batch <- result.try(native(fluid_container.decode(contents, metadata)))
  Ok(decoded_case_json(id, batch))
}

fn decoded_case_json(id: String, batch: DecodedBatch) -> Json {
  let DecodedBatch(grouped, metadata, messages) = batch
  let fields = [
    #("kind", json.string("decodedCase")),
    #("id", json.string(id)),
    #("grouped", json.bool(grouped)),
    #("messages", array(list.map(messages, message_json))),
  ]
  json.object(with_optional(fields, "metadata", metadata))
}

fn grouped_observation(message: OuterMessage) -> Result(Json, String) {
  let OuterMessage(
    client_id,
    client_sequence_number,
    minimum_sequence_number,
    reference_sequence_number,
    sequence_number,
    contents,
    metadata,
  ) = message
  use contents <- result.try(parse(contents, "grouped message"))
  use batch <- result.try(native(fluid_container.decode(contents, metadata)))
  let DecodedBatch(grouped, decoded_metadata, messages) = batch
  let fields = [
    #("kind", json.string("decodedBatch")),
    #("grouped", json.bool(grouped)),
    #(
      "outer",
      outer_json(
        client_id,
        client_sequence_number,
        minimum_sequence_number,
        reference_sequence_number,
        sequence_number,
      ),
    ),
    #("messages", array(list.map(messages, message_json))),
  ]
  Ok(json.object(with_optional(fields, "metadata", decoded_metadata)))
}

fn bootstrap_messages_observation(
  messages: List(OuterMessage),
  snapshot: Json,
) -> Result(Json, String) {
  use observations <- result.try(
    list.try_map(messages, fn(message) {
      let OuterMessage(
        client_id,
        client_sequence_number,
        minimum_sequence_number,
        reference_sequence_number,
        sequence_number,
        contents,
        metadata,
      ) = message
      use contents <- result.try(parse(contents, "bootstrap message"))
      use batch <- result.try(
        native(fluid_container.decode(contents, metadata)),
      )
      use container_message <- result.try(case batch {
        DecodedBatch(False, _, [message]) -> Ok(message)
        _ -> Error("bootstrap message is not a singleton")
      })
      let ContainerMessage(kind, _, _) = container_message
      let fields = [
        #(
          "outer",
          outer_json(
            client_id,
            client_sequence_number,
            minimum_sequence_number,
            reference_sequence_number,
            sequence_number,
          ),
        ),
        #("message", kind_json(kind)),
      ]
      let fields = with_optional(fields, "metadata", metadata)
      case kind {
        ChannelOperation(route, payload) -> {
          use resolved <- result.try(resolve_plain_handle(
            payload,
            route,
            snapshot,
          ))
          Ok(
            json.object(case resolved {
              None -> fields
              Some(resolved) -> [#("resolvedHandle", resolved), ..fields]
            }),
          )
        }
        _ -> Ok(json.object(fields))
      }
    }),
  )
  Ok(
    json.object([
      #("kind", json.string("bootstrapMessages")),
      #("messages", array(observations)),
    ]),
  )
}

fn resolve_plain_handle(
  payload: Json,
  context: Route,
  snapshot: Json,
) -> Result(Option(Json), String) {
  let decoded =
    json.parse(json.to_string(payload), {
      use value_type <- decode.optional_field("type", "", decode.string)
      use marker <- decode.optional_field(
        "value",
        None,
        decode.map(wire.json_value_decoder(), Some),
      )
      decode.success(#(value_type, marker))
    })
  case decoded {
    Ok(#("set", Some(value))) -> {
      use value <- result.try(
        json.parse(json.to_string(value), {
          use plain_type <- decode.field("type", decode.string)
          use marker <- decode.field("value", wire.json_value_decoder())
          decode.success(#(plain_type, marker))
        })
        |> result.map_error(fn(_) { "invalid bootstrap map value" }),
      )
      case value.0 {
        "Plain" -> {
          let Route(data_store_id, channel_id) = context
          use path <- result.try(
            handle.resolve_path(
              value.1,
              "/" <> data_store_id <> "/" <> channel_id,
            )
            |> result.map_error(fn(_) { "invalid bootstrap handle" }),
          )
          use route <- result.try(route_from_path(path))
          use target_type <- result.try(route_type(snapshot, route))
          let Route(data_store_id, channel_id) = route
          Ok(
            Some(
              json.object([
                #("path", json.string(path)),
                #("route", route_json(data_store_id, channel_id)),
                #("targetType", json.string(target_type)),
              ]),
            ),
          )
        }
        _ -> Error("bootstrap map value is not Plain")
      }
    }
    Ok(_) -> Ok(None)
    Error(_) -> Error("invalid bootstrap map operation")
  }
}

fn handle_observation(value: HandleCase) -> Result(Json, String) {
  let HandleCase(id, marker, context_path) = value
  use path <- result.try(
    handle.resolve_path(marker, context_path)
    |> result.map_error(fn(_) { "invalid handle case " <> id }),
  )
  use encoded <- result.try(
    handle.encode_path(path)
    |> result.map_error(fn(_) { "could not encode handle case " <> id }),
  )
  use parts <- result.try(path_parts(path))
  Ok(
    json.object([
      #("kind", json.string("handle")),
      #("id", json.string(id)),
      #("path", json.string(path)),
      #("parts", json.array(parts, json.string)),
      #("encoded", encoded),
    ]),
  )
}

fn encode_observation(value: EncodeCase) -> Result(Json, String) {
  let #(id, encoded) = case value {
    EncodeMessage(id, message) -> #(id, fluid_container.encode(message))
    EncodeBatch(id, batch) -> #(id, fluid_container.encode_batch(batch))
  }
  use encoded <- result.try(native(encoded))
  Ok(
    json.object([
      #("kind", json.string("encodedCase")),
      #("id", json.string(id)),
      #("contents", encoded),
      #("upstreamAccepted", json.bool(True)),
    ]),
  )
}

fn bootstrap_observation(snapshot: Json) -> Result(Json, String) {
  use map_header <- result.try(
    snapshot_blob(snapshot, [
      "tree",
      "trees",
      ".channels",
      "trees",
      "A",
      "trees",
      ".channels",
      "trees",
      "root",
      "blobs",
      "header",
    ]),
  )
  use map_attributes <- result.try(
    snapshot_blob(snapshot, [
      "tree",
      "trees",
      ".channels",
      "trees",
      "A",
      "trees",
      ".channels",
      "trees",
      "root",
      "blobs",
      ".attributes",
    ]),
  )
  use tree_attributes <- result.try(
    snapshot_blob(snapshot, [
      "tree",
      "trees",
      ".channels",
      "trees",
      "A",
      "trees",
      ".channels",
      "trees",
      "_C",
      "blobs",
      ".attributes",
    ]),
  )
  use map_type <- result.try(read(map_attributes, ["type"], decode.string))
  use map_snapshot <- result.try(read(
    map_attributes,
    ["snapshotFormatVersion"],
    decode.string,
  ))
  use map_package <- result.try(read(
    map_attributes,
    ["packageVersion"],
    decode.string,
  ))
  use value_type <- result.try(read(
    map_header,
    ["content", "tree", "type"],
    decode.string,
  ))
  use marker <- result.try(field(map_header, ["content", "tree", "value"]))
  use handle_type <- result.try(read(marker, ["type"], decode.string))
  use handle_path <- result.try(
    handle.resolve_path(marker, "/A/root")
    |> result.map_error(fn(_) { "invalid bootstrap header handle" }),
  )
  use route <- result.try(route_from_path(handle_path))
  use target_type <- result.try(route_type(snapshot, route))
  use tree_type <- result.try(read(tree_attributes, ["type"], decode.string))
  use tree_snapshot <- result.try(read(
    tree_attributes,
    ["snapshotFormatVersion"],
    decode.string,
  ))
  use tree_package <- result.try(read(
    tree_attributes,
    ["packageVersion"],
    decode.string,
  ))
  use _ <- result.try(case target_type == tree_type {
    True -> Ok(Nil)
    False -> Error("bootstrap handle target type does not match")
  })
  let Route(data_store_id, channel_id) = route
  Ok(
    json.object([
      #("kind", json.string("bootstrap")),
      #("mapType", json.string(map_type)),
      #("mapSnapshotFormatVersion", json.string(map_snapshot)),
      #("mapPackageVersion", json.string(map_package)),
      #("valueType", json.string(value_type)),
      #("handleType", json.string(handle_type)),
      #("handlePath", json.string(handle_path)),
      #("route", route_json(data_store_id, channel_id)),
      #("treeType", json.string(tree_type)),
      #("treeSnapshotFormatVersion", json.string(tree_snapshot)),
      #("treePackageVersion", json.string(tree_package)),
    ]),
  )
}

fn snapshot_blob(
  snapshot: Json,
  id_path: List(String),
) -> Result(Json, String) {
  use id <- result.try(read(snapshot, id_path, decode.string))
  use blobs <- result.try(read(
    snapshot,
    ["blobs"],
    decode.dict(decode.string, decode.string),
  ))
  use encoded <- result.try(
    dict.get(blobs, id)
    |> result.map_error(fn(_) { "snapshot blob is missing: " <> id }),
  )
  use bytes <- result.try(
    bit_array.base64_decode(encoded)
    |> result.map_error(fn(_) { "snapshot blob has invalid base64: " <> id }),
  )
  use raw <- result.try(
    bit_array.to_string(bytes)
    |> result.map_error(fn(_) { "snapshot blob is not UTF-8: " <> id }),
  )
  parse(raw, "snapshot blob " <> id)
}

fn route_type(snapshot: Json, route: Route) -> Result(String, String) {
  let Route(data_store_id, channel_id) = route
  use attributes <- result.try(
    snapshot_blob(snapshot, [
      "tree",
      "trees",
      ".channels",
      "trees",
      data_store_id,
      "trees",
      ".channels",
      "trees",
      channel_id,
      "blobs",
      ".attributes",
    ]),
  )
  read(attributes, ["type"], decode.string)
}

fn route_from_path(path: String) -> Result(Route, String) {
  use parts <- result.try(path_parts(path))
  case parts {
    [data_store_id, channel_id] -> Ok(Route(data_store_id, channel_id))
    _ -> Error("handle path is not a datastore and channel route")
  }
}

fn path_parts(path: String) -> Result(List(String), String) {
  path
  |> string.drop_start(1)
  |> string.split("/")
  |> list.try_map(fn(part) {
    uri.percent_decode(part)
    |> result.map_error(fn(_) { "handle path has an invalid escape" })
  })
}

fn message_json(message: ContainerMessage) -> Json {
  let ContainerMessage(kind, index, metadata) = message
  let fields = [
    #("index", json.int(index)),
    #("message", kind_json(kind)),
  ]
  json.object(with_optional(fields, "metadata", metadata))
}

fn kind_json(kind: MessageKind) -> Json {
  case kind {
    ChannelOperation(Route(data_store_id, channel_id), contents) ->
      json.object([
        #("kind", json.string("channelOperation")),
        #("route", route_json(data_store_id, channel_id)),
        #("contents", contents),
      ])
    IdAllocation(range) -> {
      let assert Ok(range) = fluid_ids.creation_range_to_json(range)
      json.object([
        #("kind", json.string("idAllocation")),
        #("range", range),
      ])
    }
    DatastoreAttach(data_store_id, contents) ->
      json.object([
        #("kind", json.string("datastoreAttach")),
        #("dataStoreId", json.string(data_store_id)),
        #("contents", contents),
      ])
    DatastoreAlias(data_store_id, alias) ->
      json.object([
        #("kind", json.string("datastoreAlias")),
        #("dataStoreId", json.string(data_store_id)),
        #("alias", json.string(alias)),
      ])
    ChannelAttach(Route(data_store_id, channel_id), channel_type, snapshot) ->
      json.object([
        #("kind", json.string("channelAttach")),
        #("route", route_json(data_store_id, channel_id)),
        #("channelType", json.string(channel_type)),
        #("snapshot", snapshot),
      ])
  }
}

fn route_json(data_store_id: String, channel_id: String) -> Json {
  json.object([
    #("dataStoreId", json.string(data_store_id)),
    #("channelId", json.string(channel_id)),
  ])
}

fn outer_json(
  client_id: String,
  client_sequence_number: Int,
  minimum_sequence_number: Int,
  reference_sequence_number: Int,
  sequence_number: Int,
) -> Json {
  json.object([
    #("clientId", json.string(client_id)),
    #("clientSequenceNumber", json.int(client_sequence_number)),
    #("minimumSequenceNumber", json.int(minimum_sequence_number)),
    #("referenceSequenceNumber", json.int(reference_sequence_number)),
    #("sequenceNumber", json.int(sequence_number)),
  ])
}

fn decode_case_decoder() -> Decoder(DecodeCase) {
  use id <- decode.field("id", decode.string)
  use contents <- decode.field("contents", wire.json_value_decoder())
  use metadata <- decode.optional_field(
    "metadata",
    None,
    decode.map(wire.json_value_decoder(), Some),
  )
  decode.success(DecodeCase(id, contents, metadata))
}

fn handle_case_decoder() -> Decoder(HandleCase) {
  use id <- decode.field("id", decode.string)
  use value <- decode.field("value", wire.json_value_decoder())
  use context_path <- decode.field("contextPath", decode.string)
  decode.success(HandleCase(id, value, context_path))
}

fn outer_message_decoder() -> Decoder(OuterMessage) {
  use client_id <- decode.field("clientId", decode.string)
  use client_sequence_number <- decode.field("clientSequenceNumber", decode.int)
  use minimum_sequence_number <- decode.field(
    "minimumSequenceNumber",
    decode.int,
  )
  use reference_sequence_number <- decode.field(
    "referenceSequenceNumber",
    decode.int,
  )
  use sequence_number <- decode.field("sequenceNumber", decode.int)
  use contents <- decode.field("contents", decode.string)
  use metadata <- decode.optional_field(
    "metadata",
    None,
    decode.map(wire.json_value_decoder(), Some),
  )
  decode.success(OuterMessage(
    client_id,
    client_sequence_number,
    minimum_sequence_number,
    reference_sequence_number,
    sequence_number,
    contents,
    metadata,
  ))
}

fn encode_case_decoder() -> Decoder(EncodeCase) {
  use id <- decode.field("id", decode.string)
  use message <- decode.optional_field(
    "message",
    None,
    decode.map(message_kind_decoder(), Some),
  )
  use batch <- decode.optional_field(
    "batch",
    None,
    decode.map(batch_decoder(), Some),
  )
  case message, batch {
    Some(message), None -> decode.success(EncodeMessage(id, message))
    None, Some(batch) -> decode.success(EncodeBatch(id, batch))
    _, _ ->
      decode.failure(EncodeMessage(id, DatastoreAlias("", "")), "encode case")
  }
}

fn batch_decoder() -> Decoder(DecodedBatch) {
  use grouped <- decode.field("grouped", decode.bool)
  use metadata <- decode.optional_field(
    "metadata",
    None,
    decode.map(wire.json_value_decoder(), Some),
  )
  use messages <- decode.field(
    "messages",
    decode.list(container_message_decoder()),
  )
  decode.success(DecodedBatch(grouped, metadata, messages))
}

fn container_message_decoder() -> Decoder(ContainerMessage) {
  use index <- decode.field("index", decode.int)
  use metadata <- decode.optional_field(
    "metadata",
    None,
    decode.map(wire.json_value_decoder(), Some),
  )
  use message <- decode.field("message", message_kind_decoder())
  decode.success(ContainerMessage(message, index, metadata))
}

fn message_kind_decoder() -> Decoder(MessageKind) {
  use kind <- decode.field("kind", decode.string)
  case kind {
    "channelOperation" -> {
      use route <- decode.field("route", route_decoder())
      use contents <- decode.field("contents", wire.json_value_decoder())
      decode.success(ChannelOperation(route, contents))
    }
    "idAllocation" -> {
      use range <- decode.field("range", wire.json_value_decoder())
      case fluid_ids.creation_range_from_json(range) {
        Ok(range) -> decode.success(IdAllocation(range))
        Error(_) ->
          decode.failure(DatastoreAlias("", ""), "valid creation range")
      }
    }
    "datastoreAttach" -> {
      use data_store_id <- decode.field("dataStoreId", decode.string)
      use contents <- decode.field("contents", wire.json_value_decoder())
      decode.success(DatastoreAttach(data_store_id, contents))
    }
    "datastoreAlias" -> {
      use data_store_id <- decode.field("dataStoreId", decode.string)
      use alias <- decode.field("alias", decode.string)
      decode.success(DatastoreAlias(data_store_id, alias))
    }
    "channelAttach" -> {
      use route <- decode.field("route", route_decoder())
      use channel_type <- decode.field("channelType", decode.string)
      use snapshot <- decode.field("snapshot", wire.json_value_decoder())
      decode.success(ChannelAttach(route, channel_type, snapshot))
    }
    _ -> decode.failure(DatastoreAlias("", ""), "known container message kind")
  }
}

fn route_decoder() -> Decoder(Route) {
  use data_store_id <- decode.field("dataStoreId", decode.string)
  use channel_id <- decode.field("channelId", decode.string)
  decode.success(Route(data_store_id, channel_id))
}

fn with_optional(
  fields: List(#(String, Json)),
  key: String,
  value: Option(Json),
) -> List(#(String, Json)) {
  case value {
    None -> fields
    Some(value) -> [#(key, value), ..fields]
  }
}

fn read(
  input: Json,
  path: List(String),
  decoder: Decoder(a),
) -> Result(a, String) {
  json.parse(json.to_string(input), decode.at(path, decoder))
  |> result.map_error(fn(error) {
    "invalid container input at "
    <> string.join(path, ".")
    <> ": "
    <> string.inspect(error)
  })
}

fn field(input: Json, path: List(String)) -> Result(Json, String) {
  read(input, path, wire.json_value_decoder())
}

fn parse(raw: String, location: String) -> Result(Json, String) {
  json.parse(raw, wire.json_value_decoder())
  |> result.map_error(fn(_) { "invalid JSON at " <> location })
}

fn native(value: Result(a, b)) -> Result(a, String) {
  value |> result.map_error(fn(error) { string.inspect(error) })
}

fn array(values: List(Json)) -> Json {
  json.array(values, fn(value) { value })
}
