import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import watershed/canonical_json
import watershed/runtime_core
import watershed/tree/schema
import watershed/tree/types.{
  type FieldPath, type TreeValue, ArrayValue, BooleanValue, MapValue, NullValue,
  NumberValue, ObjectValue, StringValue,
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
    views: List(#(String, schema.ViewSchema)),
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
  use raw_views <- result.try(
    decode.run(data, {
      use views <- decode.optional_field(
        "viewSchemas",
        dict.from_list([#("default", schema_json)]),
        decode.dict(decode.string, decode.string),
      )
      decode.success(views)
    })
    |> result.map_error(fn(_) {
      invalid("viewSchemas", "invalid view schema catalogue")
    }),
  )
  use views <- result.try(
    raw_views
    |> dict.to_list
    |> list.try_map(fn(entry) {
      use _ <- result.try(case string.is_empty(entry.0) {
        True -> Error(invalid("viewSchemas", "empty view label"))
        False -> Ok(Nil)
      })
      schema.view_from_string(entry.1)
      |> result.map(fn(view) { #(entry.0, view) })
      |> result.map_error(fn(_) {
        invalid("viewSchemas", "unsupported view schema")
      })
    }),
  )
  Ok(Descriptor(
    run_id,
    document_id,
    tenant,
    socket_url,
    host,
    port,
    view,
    views,
  ))
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
  MapGet(FieldPath, String)
  MapSet(FieldPath, String, TreeValue)
  MapDelete(FieldPath, String)
  MapKeys(FieldPath)
  MapEntries(FieldPath)
  SchemaCompatibility(String)
  SchemaUpgrade(String)
  OpenView(String)
  ArrayGet(FieldPath, Int)
  ArrayValues(FieldPath)
  ArrayInsert(FieldPath, Int, List(TreeValue))
  ArrayRemove(FieldPath, Int, Int)
  ArrayMove(FieldPath, Int, Int, FieldPath, Int)
  ConstrainedArrayRemove(FieldPath, FieldPath, Int, Int)
  Transaction(TransactionScope)
  RetainLastLocalCommit(String)
  RevertibleStatus(String)
  DisposeRevertible(String)
  Revert(String, Bool)
  AwaitSynced(Int)
  Checkpoint
  PendingSummaryEvidence
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

/// The requested end of one transaction scope.
pub type ScopeResult {
  CommitScope
  AbortScope
}

/// One edit inside a transaction scope. A nested scope is also an edit.
pub type TransactionEdit {
  TransactionSet(FieldPath, TreeValue)
  TransactionClear(FieldPath)
  TransactionMapSet(FieldPath, String, TreeValue)
  TransactionMapDelete(FieldPath, String)
  TransactionArrayInsert(FieldPath, Int, List(TreeValue))
  TransactionArrayRemove(FieldPath, Int, Int)
  TransactionArrayMove(FieldPath, Int, Int, FieldPath, Int)
  TransactionNested(TransactionScope)
}

/// One transaction scope. Each path is a node existence constraint.
pub type TransactionScope {
  TransactionScope(
    constraints: List(FieldPath),
    edits: List(TransactionEdit),
    result: ScopeResult,
  )
}

/// What one client saw inside one transaction scope.
pub type TransactionObservation {
  TransactionObservation(
    outcome: String,
    constraints: List(FieldPath),
    edits_applied: Int,
    observed_tree: Json,
    nested: List(TransactionObservation),
  )
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
  use command <- result.try(
    decode.run(
      data,
      decode.one_of(decode.at(["command"], decode.string), or: [
        decode.at(["op"], decode.string),
      ]),
    )
    |> result.map_error(fn(_) {
      invalid("command", "invalid or missing command or op")
    }),
  )
  use decoded <- result.try(case command {
    "read" -> decode_path(data) |> result.map(Read)
    "set" -> {
      use path <- result.try(decode_path(data))
      use value <- result.try(required(data, "value", decode.dynamic))
      decode_value(value) |> result.map(fn(value) { Set(path, value) })
    }
    "clear" -> decode_path(data) |> result.map(Clear)
    "map-get" -> {
      use path <- result.try(decode_path(data))
      use key <- result.try(decode_key(data))
      Ok(MapGet(path, key))
    }
    "map-set" -> {
      use path <- result.try(decode_path(data))
      use key <- result.try(decode_key(data))
      use value <- result.try(required(data, "value", decode.dynamic))
      decode_value(value) |> result.map(fn(value) { MapSet(path, key, value) })
    }
    "map-delete" -> {
      use path <- result.try(decode_path(data))
      use key <- result.try(decode_key(data))
      Ok(MapDelete(path, key))
    }
    "map-keys" -> decode_path(data) |> result.map(MapKeys)
    "map-entries" -> decode_path(data) |> result.map(MapEntries)
    "schema-compatibility" ->
      decode_view_label(data) |> result.map(SchemaCompatibility)
    "schema-upgrade" -> decode_view_label(data) |> result.map(SchemaUpgrade)
    "open-view" -> decode_view_label(data) |> result.map(OpenView)
    "array-get" -> {
      use path <- result.try(decode_path(data))
      use index <- result.try(decode_safe_index(data, "index"))
      Ok(ArrayGet(path, index))
    }
    "array-values" -> decode_path(data) |> result.map(ArrayValues)
    "array-insert" -> {
      use path <- result.try(decode_path(data))
      use index <- result.try(decode_safe_index(data, "index"))
      use values <- result.try(required(
        data,
        "values",
        decode.list(decode.dynamic),
      ))
      use values <- result.try(list.try_map(values, decode_value))
      Ok(ArrayInsert(path, index, values))
    }
    "array-remove" -> {
      use path <- result.try(decode_path(data))
      use start <- result.try(decode_safe_index(data, "start"))
      use end <- result.try(decode_safe_index(data, "end"))
      Ok(ArrayRemove(path, start, end))
    }
    "array-move" -> {
      use source_path <- result.try(decode_named_path(data, "sourcePath"))
      use source_start <- result.try(decode_safe_index(data, "sourceStart"))
      use source_end <- result.try(decode_safe_index(data, "sourceEnd"))
      use destination_path <- result.try(decode_named_path(
        data,
        "destinationPath",
      ))
      use destination_gap <- result.try(decode_safe_index(
        data,
        "destinationGap",
      ))
      Ok(ArrayMove(
        source_path,
        source_start,
        source_end,
        destination_path,
        destination_gap,
      ))
    }
    "constrained-array-remove" -> {
      use target_path <- result.try(decode_named_path(data, "targetPath"))
      use path <- result.try(decode_path(data))
      use start <- result.try(decode_safe_index(data, "start"))
      use end <- result.try(decode_safe_index(data, "end"))
      Ok(ConstrainedArrayRemove(target_path, path, start, end))
    }
    "transaction" -> decode_transaction_scope(data) |> result.map(Transaction)
    "retainLastLocalCommit" ->
      nonempty(data, "name") |> result.map(RetainLastLocalCommit)
    "revertibleStatus" -> nonempty(data, "name") |> result.map(RevertibleStatus)
    "disposeRevertible" ->
      nonempty(data, "name") |> result.map(DisposeRevertible)
    "revert" -> {
      use name <- result.try(nonempty(data, "name"))
      use dispose <- result.try(required(data, "dispose", decode.bool))
      Ok(Revert(name, dispose))
    }
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
    "pending-summary-evidence" -> Ok(PendingSummaryEvidence)
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
  decode_named_path(data, "path")
}

fn decode_transaction_scope(
  data: Dynamic,
) -> Result(TransactionScope, ProtocolError) {
  use raw_constraints <- result.try(required(
    data,
    "constraints",
    decode.list(decode.dynamic),
  ))
  use constraints <- result.try(list.try_map(
    raw_constraints,
    decode_transaction_constraint,
  ))
  use raw_edits <- result.try(required(
    data,
    "edits",
    decode.list(decode.dynamic),
  ))
  use edits <- result.try(list.try_map(raw_edits, decode_transaction_edit))
  use outcome <- result.try(required(data, "result", decode.string))
  use result <- result.try(case outcome {
    "commit" -> Ok(CommitScope)
    "abort" -> Ok(AbortScope)
    _ -> Error(invalid("result", "unknown transaction result"))
  })
  Ok(TransactionScope(constraints, edits, result))
}

fn decode_transaction_constraint(
  data: Dynamic,
) -> Result(FieldPath, ProtocolError) {
  use kind <- result.try(required(data, "type", decode.string))
  case kind {
    "nodeInDocument" -> decode_path(data)
    _ ->
      Error(invalid("constraints", "unsupported transaction constraint type"))
  }
}

fn decode_transaction_edit(
  data: Dynamic,
) -> Result(TransactionEdit, ProtocolError) {
  use op <- result.try(required(data, "op", decode.string))
  case op {
    "set" -> {
      use path <- result.try(decode_path(data))
      use value <- result.try(required(data, "value", decode.dynamic))
      decode_value(value)
      |> result.map(fn(value) { TransactionSet(path, value) })
    }
    "clear" -> decode_path(data) |> result.map(TransactionClear)
    "map-set" -> {
      use path <- result.try(decode_path(data))
      use key <- result.try(decode_key(data))
      use value <- result.try(required(data, "value", decode.dynamic))
      decode_value(value)
      |> result.map(fn(value) { TransactionMapSet(path, key, value) })
    }
    "map-delete" -> {
      use path <- result.try(decode_path(data))
      use key <- result.try(decode_key(data))
      Ok(TransactionMapDelete(path, key))
    }
    "array-insert" -> {
      use path <- result.try(decode_path(data))
      use index <- result.try(decode_safe_index(data, "index"))
      use values <- result.try(required(
        data,
        "values",
        decode.list(decode.dynamic),
      ))
      use values <- result.try(list.try_map(values, decode_value))
      Ok(TransactionArrayInsert(path, index, values))
    }
    "array-remove" -> {
      use path <- result.try(decode_path(data))
      use start <- result.try(decode_safe_index(data, "start"))
      use end <- result.try(decode_safe_index(data, "end"))
      Ok(TransactionArrayRemove(path, start, end))
    }
    "array-move" -> {
      use source_path <- result.try(decode_named_path(data, "sourcePath"))
      use source_start <- result.try(decode_safe_index(data, "sourceStart"))
      use source_end <- result.try(decode_safe_index(data, "sourceEnd"))
      use destination_path <- result.try(decode_named_path(
        data,
        "destinationPath",
      ))
      use destination_gap <- result.try(decode_safe_index(
        data,
        "destinationGap",
      ))
      Ok(TransactionArrayMove(
        source_path,
        source_start,
        source_end,
        destination_path,
        destination_gap,
      ))
    }
    "transaction" ->
      decode_transaction_scope(data) |> result.map(TransactionNested)
    _ -> Error(invalid("edits", "unknown transaction edit"))
  }
}

fn decode_named_path(
  data: Dynamic,
  name: String,
) -> Result(FieldPath, ProtocolError) {
  required(data, name, decode.list(decode.string))
}

fn decode_safe_index(
  data: Dynamic,
  name: String,
) -> Result(Int, ProtocolError) {
  use value <- result.try(required(data, name, decode.int))
  case value >= 0 && value <= max_safe_integer {
    True -> Ok(value)
    False -> Error(invalid(name, name <> " is not a safe nonnegative integer"))
  }
}

fn decode_key(data: Dynamic) -> Result(String, ProtocolError) {
  required(data, "key", decode.string)
}

fn decode_view_label(data: Dynamic) -> Result(String, ProtocolError) {
  nonempty(data, "view")
}

pub fn descriptor_view(
  descriptor: Descriptor,
  label: String,
) -> Result(schema.ViewSchema, ProtocolError) {
  descriptor.views
  |> list.find(fn(entry) { entry.0 == label })
  |> result.map(fn(entry) { entry.1 })
  |> result.map_error(fn(_) {
    invalid("view", "view label is not in the input profile")
  })
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
    "map" -> {
      use schema_id <- result.try(required(value, "schemaId", decode.string))
      use _ <- result.try(case string.is_empty(schema_id) {
        True -> Error(invalid("schemaId", "schema ID is empty"))
        False -> Ok(Nil)
      })
      use raw_entries <- result.try(required(
        value,
        "entries",
        decode.list(decode.dynamic),
      ))
      use #(entries, _) <- result.try(
        list.try_fold(raw_entries, #([], []), fn(acc, entry) {
          let #(entries, keys) = acc
          use pair <- result.try(
            decode.run(entry, decode.list(decode.dynamic))
            |> result.map_error(fn(_) {
              invalid("entries", "map entry must be a pair")
            }),
          )
          use #(key, data) <- result.try(case pair {
            [key, data] -> Ok(#(key, data))
            _ -> Error(invalid("entries", "map entry must be a pair"))
          })
          use key <- result.try(
            decode.run(key, decode.string)
            |> result.map_error(fn(_) {
              invalid("entries", "map entry key must be a string")
            }),
          )
          use _ <- result.try(case list.contains(keys, key) {
            True -> Error(invalid("entries", "duplicate map entry"))
            False -> Ok(Nil)
          })
          use decoded <- result.try(decode_value(data))
          Ok(#(list.append(entries, [#(key, decoded)]), [key, ..keys]))
        }),
      )
      Ok(MapValue(schema_id, entries))
    }
    "array" -> {
      use schema_id <- result.try(required(value, "schemaId", decode.string))
      use _ <- result.try(case string.is_empty(schema_id) {
        True -> Error(invalid("schemaId", "schema ID is empty"))
        False -> Ok(Nil)
      })
      use elements <- result.try(required(
        value,
        "elements",
        decode.list(decode.dynamic),
      ))
      use elements <- result.try(list.try_map(elements, decode_value))
      Ok(ArrayValue(schema_id, elements))
    }
    _ -> Error(invalid("kind", "unknown tree value kind"))
  }
}

pub fn decode_tree_value(raw: String) -> Result(TreeValue, ProtocolError) {
  use value <- result.try(
    json.parse(raw, decode.dynamic)
    |> result.map_error(fn(_) { invalid("value", "malformed JSON") }),
  )
  decode_value(value)
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
    MapValue(schema_id, entries) ->
      json.object([
        #("kind", json.string("map")),
        #("schemaId", json.string(schema_id)),
        #(
          "entries",
          entries
            |> list.map(fn(entry) {
              json.preprocessed_array([
                json.string(entry.0),
                encode_value(entry.1),
              ])
            })
            |> json.preprocessed_array,
        ),
      ])
    ArrayValue(schema_id, elements) ->
      json.object([
        #("kind", json.string("array")),
        #("schemaId", json.string(schema_id)),
        #(
          "elements",
          elements |> list.map(encode_value) |> json.preprocessed_array,
        ),
      ])
  }
}

pub fn encode_map_keys(keys: List(String)) -> Json {
  keys
  |> list.sort(canonical_json.compare)
  |> json.array(json.string)
}

pub fn encode_map_entries(entries: List(#(String, TreeValue))) -> Json {
  entries
  |> list.sort(fn(left, right) { canonical_json.compare(left.0, right.0) })
  |> list.map(fn(entry) {
    json.preprocessed_array([
      json.string(entry.0),
      encode_value(entry.1),
    ])
  })
  |> json.preprocessed_array
}

pub fn encode_compatibility(status: schema.Compatibility) -> Json {
  json.object([
    #("canView", json.bool(status.can_view)),
    #("canUpgrade", json.bool(status.can_upgrade)),
    #("isEquivalent", json.bool(status.is_equivalent)),
  ])
}

pub fn encode_array_values(values: List(TreeValue)) -> Json {
  values |> list.map(encode_value) |> json.preprocessed_array
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

pub fn encode_checkpoint(
  root: Json,
  values: List(#(String, Json)),
  events: List(Json),
  commits: List(Json),
  history: Json,
  read_error: Option(String),
  retained: Option(Json),
  summary_sequence_number: Option(Int),
) -> Json {
  let fields = [
    #("root", root),
    #("values", json.object(values)),
    #("events", json.array(events, fn(event) { event })),
    #("commits", json.array(commits, fn(commit) { commit })),
    #("history", history),
  ]
  let fields = case read_error {
    Some(reason) -> list.append(fields, [#("readError", json.string(reason))])
    None -> fields
  }
  let fields = case summary_sequence_number {
    Some(sequence_number) ->
      list.append(fields, [
        #("summarySequenceNumber", json.int(sequence_number)),
      ])
    None -> fields
  }
  json.object(case retained {
    None -> fields
    Some(retained) -> list.append(fields, [#("retained", retained)])
  })
}

fn encode_path(path: List(String)) -> Json {
  json.array(path, json.string)
}

/// Encode what one client saw inside one transaction scope.
pub fn encode_transaction_observation(
  observation: TransactionObservation,
) -> Json {
  json.object([
    #("outcome", json.string(observation.outcome)),
    #("constraints", json.array(observation.constraints, encode_path)),
    #("editsApplied", json.int(observation.edits_applied)),
    #("observedTree", observation.observed_tree),
    #("nested", json.array(observation.nested, encode_transaction_observation)),
  ])
}

/// Encode the measured result of one client-authored transaction.
pub fn encode_transaction_result(
  callback: TransactionObservation,
  events: List(Json),
  commit_revision: Option(String),
  outbound_count: Int,
  tree: Json,
) -> Json {
  json.object([
    #("outcome", json.string(callback.outcome)),
    #("callback", encode_transaction_observation(callback)),
    #("events", json.array(events, fn(event) { event })),
    #("commitRevision", option_json(commit_revision, json.string)),
    #("outboundCount", json.int(outbound_count)),
    #("tree", tree),
  ])
}

/// The revision of the newest pending commit in history evidence.
pub fn last_pending_revision(history: Json) -> Option(String) {
  let decoder =
    decode.at(["pending"], decode.list(decode.at(["revision"], decode.string)))
  case json.parse(json.to_string(history), decoder) {
    Error(_) -> None
    Ok(revisions) -> list.last(revisions) |> option.from_result
  }
}

/// Return accepted and pending revision IDs from history evidence.
pub fn history_revisions(history: Json) -> List(String) {
  history_commit_ids(history) |> list.map(fn(entry) { entry.0 })
}

/// Return revision and originator IDs from accepted and pending history.
pub fn history_commit_ids(history: Json) -> List(#(String, String)) {
  let raw = json.to_string(history)
  let commit = {
    use revision <- decode.field("revision", decode.string)
    use originator <- decode.field("originatorId", decode.string)
    decode.success(#(revision, originator))
  }
  let pending = decode.at(["pending"], decode.list(commit))
  let trunk = decode.at(["trunk"], decode.list(decode.at(["commit"], commit)))
  list.append(
    json.parse(raw, trunk) |> result.unwrap([]),
    json.parse(raw, pending) |> result.unwrap([]),
  )
}

pub fn encode_startup_error(
  code: String,
  operation: String,
  message: String,
) -> String {
  json.object([
    #("kind", json.string("startup-error")),
    #("code", json.string(code)),
    #("operation", json.string(operation)),
    #("message", json.string(message)),
  ])
  |> json.to_string
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
