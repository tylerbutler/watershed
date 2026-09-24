import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import watershed/runtime_core
import watershed/tree/schema
import watershed/tree/types.{
  type FieldPath, type TreeValue, BooleanValue, NullValue, NumberValue,
  ObjectValue, StringValue,
}

const max_safe_integer = 9_007_199_254_740_991

pub type Descriptor {
  Descriptor(
    run_id: String,
    document_id: String,
    tenant: String,
    socket_url: String,
    host: String,
    port: Int,
    view: schema.ViewSchema,
  )
}

pub fn decode_descriptor(raw: String) -> Result(Descriptor, ProtocolError) {
  use data <- result.try(
    json.parse(raw, decode.dynamic)
    |> result.map_error(fn(_) { invalid("descriptor", "malformed JSON") }),
  )
  use version <- result.try(required(data, "protocolVersion", decode.int))
  use _ <- result.try(case version {
    1 -> Ok(Nil)
    _ -> Error(invalid("protocolVersion", "unsupported protocol version"))
  })
  use run_id <- result.try(nonempty(data, "runId"))
  use document_id <- result.try(nonempty(data, "documentId"))
  use tenant <- result.try(nonempty(data, "tenant"))
  use socket_url <- result.try(nonempty(data, "socketUrl"))
  use host <- result.try(nonempty(data, "host"))
  use port <- result.try(required(data, "port", decode.int))
  use _ <- result.try(case port > 0 && port <= 65_535 {
    True -> Ok(Nil)
    False -> Error(invalid("port", "invalid port"))
  })
  use schema_json <- result.try(nonempty(data, "viewSchema"))
  use view <- result.try(
    schema.view_from_string(schema_json)
    |> result.map_error(fn(_) {
      invalid("viewSchema", "unsupported view schema")
    }),
  )
  Ok(Descriptor(run_id, document_id, tenant, socket_url, host, port, view))
}

fn nonempty(data: Dynamic, key: String) -> Result(String, ProtocolError) {
  use value <- result.try(required(data, key, decode.string))
  case string.is_empty(value) {
    True -> Error(invalid(key, "empty " <> key))
    False -> Ok(value)
  }
}

pub type Command {
  Read(FieldPath)
  Set(FieldPath, TreeValue)
  Clear(FieldPath)
  AwaitSynced(Int)
  Checkpoint
  Summarize
  Disconnect
  Reconnect
  Subscribe
  Unsubscribe
  Close
}

pub type Request {
  Request(request_id: Int, command: Command)
}

pub type ProtocolError {
  ProtocolError(code: String, operation: String, message: String)
}

pub type Response {
  Response(
    request_id: Option(Int),
    result: Result(Json, ProtocolError),
    observation: runtime_core.ConnectionObservation,
  )
}

fn invalid(operation: String, detail: String) -> ProtocolError {
  ProtocolError("invalid-command", operation, detail)
}

fn required(
  value: Dynamic,
  name: String,
  decoder: decode.Decoder(a),
) -> Result(a, ProtocolError) {
  decode.run(value, decode.at([name], decoder))
  |> result.map_error(fn(_) { invalid(name, "invalid or missing " <> name) })
}

pub fn request_id(raw: String) -> Option(Int) {
  case json.parse(raw, decode.dynamic) {
    Error(_) -> None
    Ok(value) ->
      case required(value, "requestId", decode.int) {
        Ok(id) if id >= 0 && id <= max_safe_integer -> Some(id)
        _ -> None
      }
  }
}

pub fn decode_request(raw: String) -> Result(Request, ProtocolError) {
  use data <- result.try(
    json.parse(raw, decode.dynamic)
    |> result.map_error(fn(_) { invalid("decode", "malformed JSON") }),
  )
  use id <- result.try(required(data, "requestId", decode.int))
  use _ <- result.try(case id >= 0 && id <= max_safe_integer {
    True -> Ok(Nil)
    False -> Error(invalid("requestId", "request ID is not a safe integer"))
  })
  use command <- result.try(required(data, "command", decode.string))
  use decoded <- result.try(case command {
    "read" -> decode_path(data) |> result.map(Read)
    "set" -> {
      use path <- result.try(decode_path(data))
      use value <- result.try(required(data, "value", decode.dynamic))
      decode_value(value) |> result.map(fn(value) { Set(path, value) })
    }
    "clear" -> decode_path(data) |> result.map(Clear)
    "await-synced" -> {
      use watermark <- result.try(required(
        data,
        "minimumSequenceNumber",
        decode.int,
      ))
      case watermark >= 0 && watermark <= max_safe_integer {
        True -> Ok(AwaitSynced(watermark))
        False -> Error(invalid("await-synced", "invalid sequence watermark"))
      }
    }
    "checkpoint" -> Ok(Checkpoint)
    "summarize" -> Ok(Summarize)
    "disconnect" -> Ok(Disconnect)
    "reconnect" -> Ok(Reconnect)
    "subscribe" -> Ok(Subscribe)
    "unsubscribe" -> Ok(Unsubscribe)
    "close" -> Ok(Close)
    _ -> Error(invalid(command, "unknown command"))
  })
  Ok(Request(id, decoded))
}

fn decode_path(data: Dynamic) -> Result(FieldPath, ProtocolError) {
  use path <- result.try(required(data, "path", decode.list(decode.string)))
  case list.all(path, fn(segment) { !string.is_empty(segment) }) {
    True -> Ok(path)
    False -> Error(invalid("path", "path contains an empty field name"))
  }
}

fn decode_value(value: Dynamic) -> Result(TreeValue, ProtocolError) {
  use kind <- result.try(required(value, "kind", decode.string))
  case kind {
    "string" ->
      required(value, "value", decode.string) |> result.map(StringValue)
    "number" -> {
      use number <- result.try(required(
        value,
        "value",
        decode.one_of(decode.float, or: [
          decode.map(decode.int, int.to_float),
        ]),
      ))
      case
        number >=. -1.7976931348623157e308 && number <=. 1.7976931348623157e308
      {
        True -> Ok(NumberValue(number))
        False -> Error(invalid("value", "number must be finite"))
      }
    }
    "boolean" ->
      required(value, "value", decode.bool) |> result.map(BooleanValue)
    "null" -> Ok(NullValue)
    "object" -> {
      use schema_id <- result.try(required(value, "schemaId", decode.string))
      use _ <- result.try(case string.is_empty(schema_id) {
        True -> Error(invalid("schemaId", "schema ID is empty"))
        False -> Ok(Nil)
      })
      use raw_fields <- result.try(required(
        value,
        "fields",
        decode.list(decode.dynamic),
      ))
      use #(fields, _) <- result.try(
        list.try_fold(raw_fields, #([], []), fn(acc, field) {
          let #(fields, keys) = acc
          use pair <- result.try(
            decode.run(field, decode.list(decode.dynamic))
            |> result.map_error(fn(_) {
              invalid("fields", "object field must be a pair")
            }),
          )
          use #(key, data) <- result.try(case pair {
            [key, data] -> Ok(#(key, data))
            _ -> Error(invalid("fields", "object field must be a pair"))
          })
          use key <- result.try(
            decode.run(key, decode.string)
            |> result.map_error(fn(_) {
              invalid("fields", "object field name must be a string")
            }),
          )
          use _ <- result.try(
            case string.is_empty(key) || list.contains(keys, key) {
              True ->
                Error(invalid("fields", "duplicate or empty object field"))
              False -> Ok(Nil)
            },
          )
          use decoded <- result.try(decode_value(data))
          Ok(#(list.append(fields, [#(key, decoded)]), [key, ..keys]))
        }),
      )
      Ok(ObjectValue(schema_id, fields))
    }
    _ -> Error(invalid("kind", "unknown tree value kind"))
  }
}

pub fn encode_value(value: TreeValue) -> Json {
  case value {
    StringValue(text) ->
      json.object([
        #("kind", json.string("string")),
        #("value", json.string(text)),
      ])
    NumberValue(number) ->
      json.object([
        #("kind", json.string("number")),
        #("value", json.float(number)),
      ])
    BooleanValue(value) ->
      json.object([
        #("kind", json.string("boolean")),
        #("value", json.bool(value)),
      ])
    NullValue -> json.object([#("kind", json.string("null"))])
    ObjectValue(schema_id, fields) ->
      json.object([
        #("kind", json.string("object")),
        #("schemaId", json.string(schema_id)),
        #(
          "fields",
          json.preprocessed_array(
            list.map(fields, fn(entry) {
              json.preprocessed_array([
                json.string(entry.0),
                encode_value(entry.1),
              ])
            }),
          ),
        ),
      ])
  }
}

pub fn encode_read(value: Option(TreeValue)) -> Json {
  case value {
    None -> json.object([#("present", json.bool(False))])
    Some(value) ->
      json.object([
        #("present", json.bool(True)),
        #("value", encode_value(value)),
      ])
  }
}

pub fn encode_response(response: Response) -> Json {
  let observation = response.observation
  let status =
    json.object([
      #("phase", json.string(observation.phase)),
      #("synced", json.bool(observation.synced)),
      #("inFlightCount", json.int(observation.in_flight_count)),
      #("pendingTreeCount", json.int(observation.pending_tree_count)),
      #("clientId", option_json(observation.client_id, json.string)),
      #("error", option_json(observation.error, json.string)),
    ])
  let fields = [
    #("requestId", option_json(response.request_id, json.int)),
    #("sequenceNumber", option_json(observation.sequence_number, json.int)),
    #("observation", status),
  ]
  case response.result {
    Ok(value) ->
      json.object(
        list.append(fields, [
          #("ok", json.bool(True)),
          #("result", value),
        ]),
      )
    Error(error) ->
      json.object(
        list.append(fields, [
          #("ok", json.bool(False)),
          #(
            "error",
            json.object([
              #("code", json.string(error.code)),
              #("operation", json.string(error.operation)),
              #("message", json.string(error.message)),
            ]),
          ),
        ]),
      )
  }
}

fn option_json(value: Option(a), encode: fn(a) -> Json) -> Json {
  case value {
    None -> json.null()
    Some(value) -> encode(value)
  }
}
