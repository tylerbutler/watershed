import gleam/float
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import watershed/fluid_ids
import watershed/json_ot.{type JsonValue, NInt, VNumber, VObject, VString}
import watershed/tree/array_change_fixture
import watershed/tree/change_fixture_codec as fixture_codec
import watershed/tree/codec
import watershed/tree/codec/summary
import watershed/tree/schema
import watershed/tree/types
import watershed/wire/fluid_summary

pub fn run(input: Json) -> Result(Json, String) {
  use value <- result.try(fixture_codec.parse(input))
  use _ <- result.try(fixture_codec.exact(value, ["scenarios"]))
  use scenarios <- result.try(fixture_codec.field(
    value,
    "scenarios",
    fixture_codec.items,
  ))
  use observations <- result.try(list.try_map(scenarios, run_scenario))
  Ok(
    json.object([
      #("observations", json.array(observations, fn(value) { value })),
    ]),
  )
}

fn run_scenario(value: JsonValue) -> Result(Json, String) {
  use id <- result.try(fixture_codec.field(value, "id", fixture_codec.text))
  case id {
    "sequence-v3" | "message-v7" | "builds" -> run_message_scenario(id, value)
    "empty-arrays" | "retained-history" | "detached-index" | "full-summary" ->
      run_summary_scenario(id, value)
    _ -> Error(id <> ": unsupported array codec scenario")
  }
}

fn run_message_scenario(id: String, value: JsonValue) -> Result(Json, String) {
  use context <- result.try(decode_context(value))
  use encoded <- result.try(fixture_codec.field(
    value,
    "encodedMessages",
    fixture_codec.items,
  ))
  use decoded <- result.try(
    list.try_map(encoded, fn(message) {
      codec.decode_message(
        json.to_string(json_ot.to_json(message)),
        codec.DecodeContext(codec.Fluid310, context.1),
      )
      |> result.map_error(string.inspect)
    }),
  )
  use reencoded <- result.try(
    list.try_map(decoded, fn(message) {
      codec.encode_message(
        message,
        codec.EncodeContext(codec.Fluid310, context.1, None),
      )
      |> result.map_error(string.inspect)
    }),
  )
  use round_tripped <- result.try(
    list.try_map(reencoded, fn(message) {
      codec.decode_message(
        json.to_string(message),
        codec.DecodeContext(codec.Fluid310, context.1),
      )
      |> result.map_error(string.inspect)
    }),
  )
  use decoded_json <- result.try(
    list.try_map(decoded, message_json(_, context.1)),
  )
  use round_tripped_json <- result.try(
    list.try_map(round_tripped, message_json(_, context.1)),
  )
  use _ <- result.try(case round_tripped_json == decoded_json {
    True -> Ok(Nil)
    False -> Error(id <> ": native message round trip changed semantics")
  })
  let result_members = [
    #("decoded", json.array(decoded_json, fn(value) { value })),
    #("encoded", json.array(encoded, json_ot.to_json)),
  ]
  use result_members <- result.try(
    case fixture_codec.get(value, "advancedMessages") {
      Error(_) -> Ok(result_members)
      Ok(advanced_raw) -> {
        use advanced <- result.try(fixture_codec.items(advanced_raw))
        use advanced_context_raw <- result.try(fixture_codec.get(
          value,
          "advancedDecodeContext",
        ))
        use advanced_context <- result.try(decode_compressor(
          advanced_context_raw,
        ))
        use advanced <- result.try(
          list.try_map(advanced, fn(message) {
            use decoded <- result.try(
              codec.decode_message(
                json.to_string(json_ot.to_json(message)),
                codec.DecodeContext(codec.Fluid310, advanced_context.1),
              )
              |> result.map_error(string.inspect),
            )
            message_graphs(decoded, advanced_context.1)
          }),
        )
        Ok([
          #("advanced", json.array(advanced, fn(value) { value })),
          ..result_members
        ])
      }
    },
  )
  use result_members <- result.try(case id {
    "sequence-v3" -> {
      use fields <- result.try(
        list.try_map(decoded, fn(message) {
          let codec.TreeMessage(codec.WireCommit(changes: changes, ..), _) =
            message
          case changes {
            [codec.DataChange(change), ..] -> {
              use graph <- result.try(
                array_change_fixture.graph_json_with_compressor(
                  change,
                  context.1,
                ),
              )
              use graph <- result.try(fixture_codec.parse(graph))
              use fields <- result.try(fixture_codec.field(
                graph,
                "fields",
                fixture_codec.items,
              ))
              case fields {
                [field] -> Ok(field)
                _ -> Error("sequence-v3 message must change one root field")
              }
            }

            _ -> Error("sequence-v3 message has no data change")
          }
        }),
      )
      Ok([
        #("sequenceChanges", json.array(fields, json_ot.to_json)),
        ..result_members
      ])
    }
    _ -> Ok(result_members)
  })
  Ok(
    json.object([
      #("id", json.string(id)),
      #("result", json.object(result_members)),
    ]),
  )
}

fn message_graphs(
  message: codec.TreeMessage,
  compressor: fluid_ids.Compressor,
) -> Result(Json, String) {
  let codec.TreeMessage(codec.WireCommit(changes: changes, ..), _) = message
  use graphs <- result.try(
    changes
    |> list.filter_map(fn(item) {
      case item {
        codec.DataChange(value) -> Ok(value)
        codec.SchemaChange(_, _) -> Error(Nil)
      }
    })
    |> list.try_map(fn(value) {
      array_change_fixture.graph_json_with_compressor(value, compressor)
    }),
  )
  Ok(json.array(graphs, fn(value) { value }))
}

fn run_summary_scenario(id: String, value: JsonValue) -> Result(Json, String) {
  use context <- result.try(decode_context_value(value))
  use decode_context_raw <- result.try(fixture_codec.get(value, "decodeContext"))
  use input_compressor_raw <- result.try(fixture_codec.field(
    decode_context_raw,
    "compressor",
    fixture_codec.text,
  ))
  use encoded <- result.try(fixture_codec.get(value, "encodedSummary"))
  use decoded <- result.try(
    summary.decode(
      summary_entry(encoded),
      None,
      context.0,
      codec.DecodeContext(codec.Fluid310, context.1),
    )
    |> result.map_error(string.inspect),
  )
  use reencoded <- result.try(
    summary.encode(
      decoded,
      context.0,
      codec.EncodeContext(codec.Fluid310, context.1, Some(decoded.schema)),
    )
    |> result.map_error(string.inspect),
  )
  use round_tripped <- result.try(
    summary.decode(
      reencoded,
      None,
      context.0,
      codec.DecodeContext(codec.Fluid310, context.1),
    )
    |> result.map_error(string.inspect),
  )
  use visible <- result.try(summary_visible(round_tripped))
  use input_schema_raw <- result.try(
    summary_blob(encoded, ["indexes", "Schema", "SchemaString"]),
  )
  use input_forest_raw <- result.try(
    summary_blob(encoded, ["indexes", "Forest", "contents"]),
  )
  let schema_semantics = schema.stored_to_json(round_tripped.schema)
  use detached <- result.try(detached_json(
    round_tripped.detached,
    round_tripped.forest,
    context.1,
  ))
  use history <- result.try(history_json(round_tripped.history, context.1))
  use emitted_compressor <- result.try(serialize_compressor(context.1, False))
  use serialized <- result.try(serialize_compressor(context.1, True))
  Ok(
    json.object([
      #("id", json.string(id)),
      #(
        "result",
        json.object([
          #("visible", visible),
          #(
            "rawInput",
            json.object([
              #("schema", json.string(input_schema_raw)),
              #("forest", json.string(input_forest_raw)),
              #("compressor", json.string(input_compressor_raw)),
            ]),
          ),
          #(
            "emitted",
            json.object([
              #("schemaSemantics", schema_semantics),
              #("compressor", json.string(emitted_compressor)),
            ]),
          ),
          #("schema", json.string(input_schema_raw)),
          #("schemaSemantics", schema_semantics),
          #("forest", json.string(input_forest_raw)),
          #("restoredDetached", detached),
          #("restoredHistory", history),
          #(
            "compressor",
            json.object([
              #(
                "sessionId",
                json.string(fluid_ids.session_id_to_string(context.0)),
              ),
              #("serialized", json.string(serialized)),
            ]),
          ),
        ]),
      ),
    ]),
  )
}

fn decode_context(
  value: JsonValue,
) -> Result(#(fluid_ids.SessionId, fluid_ids.Compressor), String) {
  use context <- result.try(fixture_codec.get(value, "decodeContext"))
  use decoder <- result.try(fixture_codec.get(context, "decoder"))
  decode_compressor(decoder)
}

fn decode_context_value(
  value: JsonValue,
) -> Result(#(fluid_ids.SessionId, fluid_ids.Compressor), String) {
  use context <- result.try(fixture_codec.get(value, "decodeContext"))
  decode_compressor(context)
}

fn decode_compressor(
  value: JsonValue,
) -> Result(#(fluid_ids.SessionId, fluid_ids.Compressor), String) {
  use session_raw <- result.try(fixture_codec.field(
    value,
    "sessionId",
    fixture_codec.text,
  ))
  use session <- result.try(
    fluid_ids.session_id(session_raw) |> result.map_error(string.inspect),
  )
  use compressor_raw <- result.try(fixture_codec.field(
    value,
    "compressor",
    fixture_codec.text,
  ))
  use compressor <- result.try(
    fluid_ids.deserialize(json.string(compressor_raw), session)
    |> result.map_error(string.inspect),
  )
  Ok(#(session, compressor))
}

fn summary_entry(value: JsonValue) -> fluid_summary.SummaryEntry {
  let assert VObject(members) = value
  let assert Ok(VNumber(NInt(kind))) = list.key_find(members, "type")
  case kind {
    1 -> {
      let assert Ok(VObject(tree)) = list.key_find(members, "tree")
      fluid_summary.SummaryTree(
        list.map(tree, fn(entry) { #(entry.0, summary_entry(entry.1)) }),
      )
    }

    2 -> {
      let assert Ok(VString(content)) = list.key_find(members, "content")
      fluid_summary.SummaryBlob(<<content:utf8>>)
    }
    _ -> panic as "unsupported summary entry"
  }
}

fn summary_blob(
  value: JsonValue,
  path: List(String),
) -> Result(String, String) {
  case path {
    [] -> fixture_codec.field(value, "content", fixture_codec.text)
    [name, ..rest] -> {
      use tree <- result.try(fixture_codec.get(value, "tree"))
      use next <- result.try(fixture_codec.get(tree, name))
      summary_blob(next, rest)
    }
  }
}

fn summary_visible(value: summary.TreeSummaryData) -> Result(Json, String) {
  let summary.ForestSummary(fields) = value.forest
  case list.key_find(fields, "rootFieldKey") {
    Ok([root]) -> Ok(visible_value(root))
    Error(_) -> Ok(json.null())
    _ -> Error("summary root field must contain at most one tree")
  }
}

fn visible_value(value: types.TreeValue) -> Json {
  case value {
    types.StringValue(value) -> json.string(value)
    types.NumberValue(value) ->
      case int.to_float(float.truncate(value)) == value {
        True -> json.int(float.truncate(value))
        False -> json.float(value)
      }
    types.BooleanValue(value) -> json.bool(value)
    types.NullValue -> json.null()
    types.ArrayValue(_, elements) -> json.array(elements, visible_value)
    types.MapValue(_, entries) ->
      json.object([
        #(
          "map",
          json.array(entries, fn(entry) {
            json.array(
              [json.string(entry.0), visible_value(entry.1)],
              fn(value) { value },
            )
          }),
        ),
      ])
    types.ObjectValue(identifier, fields) -> {
      let value =
        json.object(
          list.map(fields, fn(field) { #(field.0, visible_value(field.1)) }),
        )
      case string.ends_with(identifier, ".Point") {
        True -> json.object([#("point", value)])
        False -> value
      }
    }
  }
}

fn detached_json(
  value: summary.DetachedFieldIndex,
  forest: summary.ForestSummary,
  compressor: fluid_ids.Compressor,
) -> Result(Json, String) {
  let summary.ForestSummary(fields) = forest
  use entries <- result.try(
    list.try_map(value.entries, fn(entry) {
      use major <- result.try(summary_revision_json(entry.major, compressor))
      use trees <- result.try(
        list.key_find(fields, "repair-" <> int.to_string(entry.root))
        |> result.map_error(fn(_) { "detached summary tree is missing" }),
      )
      use tree <- result.try(case trees {
        [tree] -> Ok(array_change_fixture.source_tree_json(tree))
        _ -> Error("detached summary field must contain one tree")
      })
      Ok(json.array([major, json.int(entry.minor), tree], fn(value) { value }))
    }),
  )
  Ok(json.array(entries, fn(value) { value }))
}

fn history_json(
  value: summary.EditManagerSummary,
  compressor: fluid_ids.Compressor,
) -> Result(Json, String) {
  use trunk <- result.try(
    list.try_map(value.trunk, summary_commit_json(_, compressor)),
  )
  use peers <- result.try(
    list.try_map(value.branches, fn(peer) {
      use base <- result.try(summary_revision_json(peer.base, compressor))
      use commits <- result.try(
        list.try_map(peer.commits, summary_commit_json(_, compressor)),
      )
      Ok(
        json.object([
          #(
            "sessionId",
            json.string(fluid_ids.session_id_to_string(peer.session)),
          ),
          #("base", base),
          #("commits", json.array(commits, fn(value) { value })),
        ]),
      )
    }),
  )
  let longest =
    list.fold(value.branches, 0, fn(length, peer) {
      int.max(length, list.length(peer.commits))
    })
  Ok(
    json.object([
      #("pending", json.array([], fn(value) { value })),
      #("trunk", json.array(trunk, fn(value) { value })),
      #("peers", json.array(peers, fn(value) { value })),
      #("longestBranchLength", json.int(longest)),
    ]),
  )
}

fn summary_commit_json(
  value: summary.SummaryCommit,
  compressor: fluid_ids.Compressor,
) -> Result(Json, String) {
  let summary.SummaryCommit(
    codec.WireCommit(revision, originator, changes, _),
    sequence_number,
    index_in_batch,
  ) = value
  use revision <- result.try(stable_revision_json(revision, compressor))
  use changes <- result.try(list.try_map(changes, change_json(_, compressor)))
  Ok(
    json.object([
      #("revision", revision),
      #("changes", json.array(changes, fn(value) { value })),
      #("sessionId", json.string(fluid_ids.session_id_to_string(originator))),
      #("sequenceNumber", optional_int_json(sequence_number)),
      #("indexInBatch", optional_int_json(index_in_batch)),
    ]),
  )
}

fn change_json(
  value: codec.TreeChange,
  compressor: fluid_ids.Compressor,
) -> Result(Json, String) {
  case value {
    codec.DataChange(value) -> {
      use data <- result.try(array_change_fixture.graph_json_with_compressor(
        value,
        compressor,
      ))
      Ok(
        json.object([
          #("type", json.string("data")),
          #("data", data),
        ]),
      )
    }
    codec.SchemaChange(before, after) ->
      Ok(
        json.object([
          #("type", json.string("schema")),
          #(
            "data",
            json.object([
              #(
                "schema",
                json.object([
                  #("new", schema_state_json(after)),
                  #("old", schema_state_json(before)),
                ]),
              ),
              #("isInverse", json.bool(False)),
            ]),
          ),
        ]),
      )
  }
}

fn schema_state_json(value: codec.SchemaState) -> Json {
  let cardinality = case value {
    codec.EmptySchema -> "Forbidden"
    codec.FixedSchema(stored) -> {
      let schema.FieldSchema(cardinality, _) = schema.root_field_schema(stored)
      case cardinality {
        schema.Required -> "Value"
        schema.Optional -> "Optional"
        schema.Sequence -> "Sequence"
      }
    }
  }
  json.object([
    #(
      "rootFieldSchema",
      json.object([
        #("kind", json.string(cardinality)),
        #("types", json.object([])),
      ]),
    ),
    #("nodeSchema", json.object([])),
  ])
}

fn summary_revision_json(
  value: summary.SummaryRevision,
  compressor: fluid_ids.Compressor,
) -> Result(Json, String) {
  case value {
    summary.RootRevision -> Ok(json.string("root"))
    summary.StableRevision(value) -> stable_revision_json(value, compressor)
  }
}

fn stable_revision_json(
  value: fluid_ids.StableId,
  compressor: fluid_ids.Compressor,
) -> Result(Json, String) {
  codec.encode_stable_revision(
    value,
    codec.EncodeContext(codec.Fluid310, compressor, None),
    "array codec fixture revision",
  )
  |> result.map(json.int)
  |> result.map_error(string.inspect)
}

fn optional_int_json(value: Option(Int)) -> Json {
  case value {
    None -> json.null()
    Some(value) -> json.int(value)
  }
}

fn serialize_compressor(
  compressor: fluid_ids.Compressor,
  ongoing: Bool,
) -> Result(String, String) {
  use encoded <- result.try(
    fluid_ids.serialize(compressor, ongoing)
    |> result.map_error(string.inspect),
  )
  case json_ot.parse_json(json.to_string(encoded)) {
    Ok(VString(value)) -> Ok(value)
    _ -> Error("compressor serialization is not a JSON string")
  }
}

fn message_json(
  message: codec.TreeMessage,
  compressor: fluid_ids.Compressor,
) -> Result(Json, String) {
  let codec.TreeMessage(codec.WireCommit(revision, originator, changes, _), _) =
    message
  use revision <- result.try(
    codec.encode_stable_revision(
      revision,
      codec.EncodeContext(codec.Fluid310, compressor, None),
      "array codec fixture message revision",
    )
    |> result.map_error(string.inspect),
  )
  use changes <- result.try(
    list.try_map(changes, fn(item) {
      case item {
        codec.DataChange(change) -> {
          use data <- result.try(
            array_change_fixture.graph_json_with_compressor(change, compressor),
          )
          Ok(
            json.object([
              #("type", json.string("data")),
              #("data", data),
            ]),
          )
        }
        codec.SchemaChange(_, _) ->
          Error("array message contains an unexpected schema change")
      }
    }),
  )
  Ok(
    json.object([
      #("type", json.string("commit")),
      #("branchId", json.string("main")),
      #("revision", json.int(revision)),
      #("sessionId", json.string(fluid_ids.session_id_to_string(originator))),
      #("changes", json.array(changes, fn(value) { value })),
    ]),
  )
}
