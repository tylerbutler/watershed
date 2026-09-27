//// Generates native SharedTree codec artifacts for the pinned upstream consumer.

import envoy
import gleam/bit_array
import gleam/float
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import simplifile
import watershed/fluid_ids
import watershed/json_ot.{
  type JsonValue, NInt, VArray, VNumber, VObject, VString,
}
import watershed/tree/array_change_fixture
import watershed/tree/change
import watershed/tree/codec
import watershed/tree/codec/field_batch
import watershed/tree/codec/summary
import watershed/tree/forest
import watershed/tree/sequence_field
import watershed/tree/shared_change
import watershed/tree/summary as tree_summary
import watershed/tree/types.{
  ArrayMove, AtomId, ClearField, MapSet, SetField, StringValue,
}
import watershed/wire/fluid_summary

const fixture_path = "test/fixtures/shared_tree/cases/tree-codecs.json"

const map_fixture_path = "test/fixtures/shared_tree/cases/map-history-codecs.json"

const array_fixture_path = "test/fixtures/shared_tree/cases/array-codecs.json"

const array_schema_fixture_path = "test/fixtures/shared_tree/cases/array-schema-content.json"

const reference_commit = "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960"

const reference_version = "3.1.0"

const fresh_summary_session = "30000000-0000-4000-8000-000000000003"

const message_session = "40000000-0000-4000-8000-000000000004"

const summary_peer_session = "50000000-0000-4000-8000-000000000005"

const native_summary_consumer_session = "60000000-0000-4000-8000-000000000006"

pub fn main() {
  let output = case envoy.get("WATERSHED_TREE_CODEC_OUTPUT") {
    Ok(value) -> value
    Error(_) -> panic as "WATERSHED_TREE_CODEC_OUTPUT is required"
  }

  let raw = case simplifile.read(fixture_path) {
    Ok(value) -> value
    Error(error) ->
      panic as { "could not read codec fixture: " <> string.inspect(error) }
  }
  let input = case decode_input(raw) {
    Ok(value) -> value
    Error(error) -> panic as { error }
  }
  let map_raw = case simplifile.read(map_fixture_path) {
    Ok(value) -> value
    Error(error) ->
      panic as { "could not read map codec fixture: " <> string.inspect(error) }
  }
  let map_initial = case decode_map_initial(map_raw) {
    Ok(value) -> value
    Error(error) -> panic as { error }
  }
  let array_raw = case simplifile.read(array_fixture_path) {
    Ok(value) -> value
    Error(error) ->
      panic as {
        "could not read array codec fixture: " <> string.inspect(error)
      }
  }
  let array_schema_raw = case simplifile.read(array_schema_fixture_path) {
    Ok(value) -> value
    Error(error) ->
      panic as {
        "could not read array schema fixture: " <> string.inspect(error)
      }
  }
  let array_input = case decode_array_input(array_raw, array_schema_raw) {
    Ok(value) -> value
    Error(error) -> panic as { error }
  }
  let artifact = case build_artifact(input, map_initial, array_input) {
    Ok(value) -> value
    Error(error) -> panic as { error }
  }
  case simplifile.write(output, json.to_string(artifact) <> "\n") {
    Ok(_) -> Nil
    Error(error) ->
      panic as { "could not write codec artifact: " <> string.inspect(error) }
  }
}

pub fn replay_array_continuation(
  artifact_raw: String,
  consumer_raw: String,
) -> Result(Json, String) {
  use artifact <- result.try(
    json_ot.parse_json(artifact_raw) |> result.map_error(string.inspect),
  )
  use items <- result.try(field(artifact, "items"))
  use items <- result.try(array(items))
  use item <- result.try(find_scenario(items, "message-array-sequence"))
  use initial_summary <- result.try(field(item, "initialSummary"))
  use initial_session_raw <- result.try(field_text(item, "session"))
  use initial_session <- result.try(
    fluid_ids.session_id(initial_session_raw)
    |> result.map_error(string.inspect),
  )
  use consumer <- result.try(
    json_ot.parse_json(consumer_raw) |> result.map_error(string.inspect),
  )
  use observations <- result.try(field(consumer, "observations"))
  use observations <- result.try(array(observations))
  use observation <- result.try(find_scenario(
    observations,
    "message-array-sequence",
  ))
  use continuation <- result.try(field(observation, "continuation"))
  use session_raw <- result.try(field_text(continuation, "session"))
  use session <- result.try(
    fluid_ids.session_id(session_raw) |> result.map_error(string.inspect),
  )
  use compressor_raw <- result.try(field_text(continuation, "compressor"))
  use compressor <- result.try(
    fluid_ids.deserialize(json.string(compressor_raw), session)
    |> result.map_error(string.inspect),
  )
  use decoded_summary <- result.try(
    summary.decode(
      summary_entry(initial_summary),
      None,
      initial_session,
      codec.DecodeContext(codec.Fluid310, compressor),
    )
    |> result.map_error(string.inspect),
  )
  use data <- result.try(summary_forest_data(decoded_summary))
  use view_id <- result.try(
    fluid_ids.stable_id("70000000-0000-4000-8000-000000000007")
    |> result.map_error(string.inspect),
  )
  use state <- result.try(
    forest.import_data(view_id, decoded_summary.schema, data)
    |> result.map_error(string.inspect),
  )
  use original <- result.try(field(item, "encoded"))
  use original <- result.try(array(original))
  use continuation_messages <- result.try(field(continuation, "messages"))
  use continuation_messages <- result.try(array(continuation_messages))
  use continuation_messages <- result.try(
    list.try_map(continuation_messages, fn(value) { field(value, "encoded") }),
  )
  use state <- result.try(
    list.append(original, continuation_messages)
    |> list.try_fold(state, fn(state, message) {
      apply_wire_message(state, message, compressor)
    }),
  )
  use visible <- result.try(
    forest.visible_root(state) |> result.map_error(string.inspect),
  )
  Ok(
    json.object([
      #("visible", case visible {
        Some(value) -> continuation_visible_json(value)
        None -> json.null()
      }),
      #("decodedMessages", json.int(list.length(continuation_messages))),
    ]),
  )
}

fn continuation_visible_json(value: types.TreeValue) -> Json {
  case value {
    types.StringValue(value) -> json.string(value)
    types.NumberValue(value) ->
      case int.to_float(float.truncate(value)) == value {
        True -> json.int(float.truncate(value))
        False -> json.float(value)
      }
    types.BooleanValue(value) -> json.bool(value)
    types.NullValue -> json.null()
    types.ArrayValue(_, elements) ->
      json.array(elements, continuation_visible_json)
    types.MapValue(_, entries) ->
      json.object([
        #(
          "map",
          json.array(entries, fn(entry) {
            json.array(
              [json.string(entry.0), continuation_visible_json(entry.1)],
              fn(value) { value },
            )
          }),
        ),
      ])
    types.ObjectValue(identifier, fields) -> {
      let value =
        json.object(
          list.map(fields, fn(field) {
            #(field.0, continuation_visible_json(field.1))
          }),
        )
      case string.ends_with(identifier, ".Point") {
        True -> json.object([#("point", value)])
        False -> value
      }
    }
  }
}

fn apply_wire_message(
  state: forest.Forest,
  value: JsonValue,
  compressor: fluid_ids.Compressor,
) -> Result(forest.Forest, String) {
  use message <- result.try(
    codec.decode_message(
      json.to_string(json_ot.to_json(value)),
      codec.DecodeContext(codec.Fluid310, compressor),
    )
    |> result.map_error(string.inspect),
  )
  let codec.TreeMessage(codec.WireCommit(revision, _, changes, _), _) = message
  list.try_fold(changes, state, fn(state, item) {
    case item {
      shared_change.SchemaChange(_, _, _) -> Ok(state)
      shared_change.DataChange(value) -> {
        use delta <- result.try(
          change.into_delta(change.TaggedChange(Some(revision), None, value))
          |> result.map_error(string.inspect),
        )
        forest.apply_delta(state, delta) |> result.map_error(string.inspect)
      }
    }
  })
}

type Input {
  Input(
    schemas: List(#(String, String)),
    field_batches: List(#(String, Json)),
    summaries: List(#(String, JsonValue, String, String)),
    message_bases: List(#(String, JsonValue, String, String)),
  )
}

type InitialState {
  InitialState(
    value: summary.TreeSummaryData,
    session: fluid_ids.SessionId,
    compressor: fluid_ids.Compressor,
  )
}

type ArrayInput {
  ArrayInput(
    messages: List(JsonValue),
    sequencing: List(JsonValue),
    advanced_messages: List(JsonValue),
    advanced_expected: List(JsonValue),
    advanced_applications: List(JsonValue),
    nested_expected: JsonValue,
    initial_summary: JsonValue,
    message_session: fluid_ids.SessionId,
    message_compressor: fluid_ids.Compressor,
    advanced_session: fluid_ids.SessionId,
    advanced_compressor: fluid_ids.Compressor,
    summaries: List(
      #(String, JsonValue, fluid_ids.SessionId, fluid_ids.Compressor),
    ),
  )
}

fn decode_input(raw: String) -> Result(Input, String) {
  use root <- result.try(
    json_ot.parse_json(raw)
    |> result.map_error(string.inspect),
  )
  use input <- result.try(field(root, "input"))
  use schemas <- result.try(field(input, "schemas"))
  use schemas <- result.try(array(schemas))
  use schemas <- result.try(
    list.try_map(schemas, fn(value) {
      use id <- result.try(field_text(value, "id"))
      use raw <- result.try(field_text(value, "raw"))
      Ok(#(id, raw))
    }),
  )
  use batches <- result.try(field(input, "fieldBatches"))
  use batches <- result.try(array(batches))
  use batches <- result.try(
    list.try_map(batches, fn(value) {
      use id <- result.try(field_text(value, "id"))
      use encoded <- result.try(field(value, "encoded"))
      Ok(#(id, json_ot.to_json(encoded)))
    }),
  )
  use summaries <- result.try(field(input, "summaries"))
  use summaries <- result.try(array(summaries))
  use summaries <- result.try(
    list.try_map(summaries, fn(value) {
      decode_summary_source(value, "summary")
    }),
  )
  use scenarios <- result.try(field(input, "scenarios"))
  use scenarios <- result.try(array(scenarios))
  use message_bases <- result.try(
    list.try_map(scenarios, fn(value) {
      decode_summary_source(value, "initialSummary")
    }),
  )
  Ok(Input(schemas, batches, summaries, message_bases))
}

fn decode_map_initial(raw: String) -> Result(InitialState, String) {
  use root <- result.try(
    json_ot.parse_json(raw)
    |> result.map_error(string.inspect),
  )
  use evidence <- result.try(field(root, "raw"))
  use summary_source <- result.try(field(evidence, "summary"))
  use encoded <- result.try(field(summary_source, "value"))
  use reload <- result.try(field(evidence, "reload"))
  use compressor_raw <- result.try(field_text(reload, "compressor"))
  use session <- result.try(
    fluid_ids.session_id(fresh_summary_session)
    |> result.map_error(string.inspect),
  )
  use compressor <- result.try(
    fluid_ids.deserialize(json.string(compressor_raw), session)
    |> result.map_error(string.inspect),
  )
  use value <- result.try(
    summary.decode(
      summary_entry(encoded),
      None,
      session,
      codec.DecodeContext(codec.Fluid310, compressor),
    )
    |> result.map_error(string.inspect),
  )
  Ok(InitialState(value, session, compressor))
}

fn decode_array_input(
  raw: String,
  schema_raw: String,
) -> Result(ArrayInput, String) {
  use root <- result.try(
    json_ot.parse_json(raw) |> result.map_error(string.inspect),
  )
  use input <- result.try(field(root, "input"))
  use scenarios <- result.try(field(input, "scenarios"))
  use scenarios <- result.try(array(scenarios))
  use messages <- result.try(find_scenario(scenarios, "sequence-v3"))
  use encoded_messages <- result.try(field(messages, "encodedMessages"))
  use encoded_messages <- result.try(array(encoded_messages))
  use sequencing <- result.try(field(messages, "sequencing"))
  use sequencing <- result.try(array(sequencing))
  use advanced_messages <- result.try(field(messages, "advancedMessages"))
  use advanced_messages <- result.try(array(advanced_messages))
  use advanced_applications <- result.try(field(
    messages,
    "advancedApplications",
  ))
  use advanced_applications <- result.try(array(advanced_applications))
  use expected_root <- result.try(field(root, "expected"))
  use observations <- result.try(field(expected_root, "observations"))
  use observations <- result.try(array(observations))
  use expected <- result.try(find_scenario(observations, "sequence-v3"))
  use expected_result <- result.try(field(expected, "result"))
  use advanced_expected <- result.try(field(expected_result, "advanced"))
  use advanced_expected <- result.try(array(advanced_expected))
  use decoded_expected <- result.try(field(expected_result, "decoded"))
  use decoded_expected <- result.try(array(decoded_expected))
  use first_decoded <- result.try(
    list.first(decoded_expected)
    |> result.map_error(fn(_) { "missing nested source message" }),
  )
  use expected_changes <- result.try(field(first_decoded, "changes"))
  use expected_changes <- result.try(array(expected_changes))
  use expected_data <- result.try(
    list.find(expected_changes, fn(value) {
      field_text(value, "type") == Ok("data")
    })
    |> result.map_error(fn(_) { "missing nested source data change" }),
  )
  use nested_expected <- result.try(field(expected_data, "data"))
  use decode_context <- result.try(field(messages, "decodeContext"))
  use decoder <- result.try(field(decode_context, "decoder"))
  use message_session_raw <- result.try(field_text(decoder, "sessionId"))
  use message_session <- result.try(
    fluid_ids.session_id(message_session_raw)
    |> result.map_error(string.inspect),
  )
  use message_compressor_raw <- result.try(field_text(decoder, "compressor"))
  use message_compressor <- result.try(
    fluid_ids.deserialize(json.string(message_compressor_raw), message_session)
    |> result.map_error(string.inspect),
  )
  use advanced_context <- result.try(field(messages, "advancedDecodeContext"))
  use advanced_session_raw <- result.try(field_text(
    advanced_context,
    "sessionId",
  ))
  use advanced_session <- result.try(
    fluid_ids.session_id(advanced_session_raw)
    |> result.map_error(string.inspect),
  )
  use advanced_compressor_raw <- result.try(field_text(
    advanced_context,
    "compressor",
  ))
  use advanced_compressor <- result.try(
    fluid_ids.deserialize(
      json.string(advanced_compressor_raw),
      advanced_session,
    )
    |> result.map_error(string.inspect),
  )
  use schema_root <- result.try(
    json_ot.parse_json(schema_raw) |> result.map_error(string.inspect),
  )
  use schema_evidence <- result.try(field(schema_root, "raw"))
  use schema_summaries <- result.try(field(schema_evidence, "summaries"))
  use initial_summary <- result.try(field(schema_summaries, "initial"))
  use summaries <- result.try(
    ["retained-history", "full-summary"]
    |> list.try_map(fn(id) {
      use scenario <- result.try(find_scenario(scenarios, id))
      use encoded <- result.try(field(scenario, "encodedSummary"))
      use context <- result.try(field(scenario, "decodeContext"))
      use session_raw <- result.try(field_text(context, "sessionId"))
      use session <- result.try(
        fluid_ids.session_id(session_raw) |> result.map_error(string.inspect),
      )
      use compressor_raw <- result.try(field_text(context, "compressor"))
      use compressor <- result.try(
        fluid_ids.deserialize(json.string(compressor_raw), session)
        |> result.map_error(string.inspect),
      )
      Ok(#(id, encoded, session, compressor))
    }),
  )
  Ok(ArrayInput(
    encoded_messages,
    sequencing,
    advanced_messages,
    advanced_expected,
    advanced_applications,
    nested_expected,
    initial_summary,
    message_session,
    message_compressor,
    advanced_session,
    advanced_compressor,
    summaries,
  ))
}

fn find_scenario(
  scenarios: List(JsonValue),
  id: String,
) -> Result(JsonValue, String) {
  list.find(scenarios, fn(value) { field_text(value, "id") == Ok(id) })
  |> result.map_error(fn(_) { "missing array codec scenario " <> id })
}

fn build_artifact(
  input: Input,
  map_initial: InitialState,
  array_input: ArrayInput,
) -> Result(Json, String) {
  let Input(schemas, batches, summaries, message_bases) = input
  use schema_items <- result.try(
    list.try_map(schemas, fn(source) {
      use decoded <- result.try(codec.decode_schema(source.1) |> native)
      use encoded <- result.try(codec.encode_schema(decoded) |> native)
      Ok(item(source.0, "schema", encoded, []))
    }),
  )
  use batch_items <- result.try(
    list.try_map(batches, fn(source) {
      use decoded <- result.try(field_batch.decode(source.1) |> native)
      use encoded <- result.try(field_batch.encode(decoded) |> native)
      Ok(item(source.0, "fieldBatch", encoded, []))
    }),
  )
  use summary_items <- result.try(list.try_map(summaries, summary_item))
  use initial <- result.try(summary_state(summaries, "initial"))
  use note <- result.try(summary_state(message_bases, "optional"))
  use settled <- result.try(summary_state(summaries, "settled-detached"))
  use message_items <- result.try(native_messages(initial, note))
  use map_message <- result.try(native_message(
    "message-map-set",
    map_initial,
    MapSet(["items"], "native", StringValue("value")),
    False,
    Some("map"),
    Some(#(22, 21, 0)),
  ))
  use authored_summary <- result.try(native_summary(settled))
  use restored_summary <- result.try(restored_summary_item(summaries))
  use map_summary <- result.try(map_summary_item(map_initial))
  use array_items <- result.try(array_codec_items(array_input))
  let items =
    list.flatten([
      schema_items,
      batch_items,
      message_items,
      summary_items,
      [authored_summary, restored_summary, map_message, map_summary],
      array_items,
    ])
  case items {
    [] -> Error("codec artifact has no items")
    _ ->
      Ok(
        json.object([
          #("formatVersion", json.int(1)),
          #(
            "reference",
            json.object([
              #("package", json.string("@fluidframework/tree")),
              #("version", json.string(reference_version)),
              #("commit", json.string(reference_commit)),
            ]),
          ),
          #("target", json.string(target_name())),
          #("items", json.array(items, fn(value) { value })),
        ]),
      )
  }
}

fn array_codec_items(input: ArrayInput) -> Result(List(Json), String) {
  let ArrayInput(
    messages,
    sequencing,
    _advanced_messages,
    _advanced_expected,
    advanced_applications,
    _nested_expected,
    initial_summary,
    message_session,
    message_compressor,
    advanced_session,
    advanced_compressor,
    summaries,
  ) = input
  use initial <- result.try(
    summary.decode(
      summary_entry(initial_summary),
      None,
      message_session,
      codec.DecodeContext(codec.Fluid310, message_compressor),
    )
    |> native,
  )
  use initial_encoded <- result.try(
    summary.encode(
      initial,
      message_session,
      codec.EncodeContext(
        codec.Fluid310,
        message_compressor,
        Some(initial.schema),
      ),
    )
    |> native,
  )
  use decoded <- result.try(
    list.try_map(messages, fn(message) {
      codec.decode_message(
        json.to_string(json_ot.to_json(message)),
        codec.DecodeContext(codec.Fluid310, message_compressor),
      )
      |> native
    }),
  )
  use encoded <- result.try(
    list.try_map(decoded, fn(message) {
      codec.encode_message(
        message,
        codec.EncodeContext(
          codec.Fluid310,
          message_compressor,
          Some(initial.schema),
        ),
      )
      |> native
    }),
  )
  use graphs <- result.try(
    list.try_map(decoded, message_graphs(_, message_compressor)),
  )
  use compressor_raw <- result.try(serialize_compressor(
    message_compressor,
    False,
  ))
  use consumer_session <- result.try(
    fluid_ids.session_id(native_summary_consumer_session)
    |> result.map_error(string.inspect),
  )
  let message_item =
    item(
      "message-array-sequence",
      "message",
      json.array(encoded, fn(value) { value }),
      [
        #("schemaProfile", json.string("array")),
        #("compressor", json.string(compressor_raw)),
        #("compressorMode", json.string("summary")),
        #(
          "session",
          json.string(fluid_ids.session_id_to_string(consumer_session)),
        ),
        #("initialSummary", summary_json(initial_encoded)),
        #("allocationRanges", json.array([], fn(value) { value })),
        #("sequencing", json.array(sequencing, json_ot.to_json)),
        #("expectedGraphs", json.array(graphs, fn(value) { value })),
      ],
    )
  use native_message_item <- result.try(native_array_message_item(
    initial,
    message_session,
    message_compressor,
  ))
  use advanced_message_items <- result.try(advanced_application_items(
    initial,
    advanced_applications,
    advanced_session,
    advanced_compressor,
  ))
  use summary_items <- result.try(list.try_map(summaries, array_summary_item))
  use full_summary <- result.try(
    list.find(summaries, fn(source) { source.0 == "full-summary" })
    |> result.map_error(fn(_) { "missing full array summary" }),
  )
  use peer_summary <- result.try(array_peer_summary_item(full_summary))
  Ok([
    message_item,
    native_message_item,
    ..list.append(advanced_message_items, [peer_summary, ..summary_items])
  ])
}

fn advanced_application_items(
  initial: summary.TreeSummaryData,
  applications: List(JsonValue),
  session: fluid_ids.SessionId,
  compressor: fluid_ids.Compressor,
) -> Result(List(Json), String) {
  use initial_encoded <- result.try(
    summary.encode(
      initial,
      session,
      codec.EncodeContext(codec.Fluid310, compressor, Some(initial.schema)),
    )
    |> native,
  )
  use compressor_raw <- result.try(serialize_compressor(compressor, True))
  list.try_map(applications, fn(application_source) {
    use id <- result.try(field_text(application_source, "id"))
    use features <- result.try(field(application_source, "features"))
    use message <- result.try(field(application_source, "message"))
    use _source_graph <- result.try(field(application_source, "graph"))
    use application <- result.try(field(application_source, "application"))
    use follow_on_messages <- result.try(field(application, "followOnMessages"))
    use follow_on_messages <- result.try(array(follow_on_messages))
    use decoded <- result.try(
      [message, ..follow_on_messages]
      |> list.try_map(fn(source_message) {
        codec.decode_message(
          json.to_string(json_ot.to_json(source_message)),
          codec.DecodeContext(codec.Fluid310, compressor),
        )
        |> native
      }),
    )
    use encoded <- result.try(
      decoded
      |> list.try_map(fn(decoded_message) {
        codec.encode_message(
          decoded_message,
          codec.EncodeContext(codec.Fluid310, compressor, Some(initial.schema)),
        )
        |> native
      }),
    )
    use graphs <- result.try(
      decoded |> list.try_map(message_graphs(_, compressor)),
    )
    Ok(
      item(id, "message", json.array(encoded, fn(value) { value }), [
        #("schemaProfile", json.string("array")),
        #("compressor", json.string(compressor_raw)),
        #("compressorMode", json.string("ongoing")),
        #("session", json.string(fluid_ids.session_id_to_string(session))),
        #("initialSummary", summary_json(initial_encoded)),
        #("allocationRanges", json.array([], fn(value) { value })),
        #(
          "sequencing",
          json.array(
            list.index_map(encoded, fn(_, index) {
              json.object([
                #("clientId", json.string("watershed-native-advanced")),
                #("clientSequenceNumber", json.int(index + 1)),
                #("referenceSequenceNumber", json.int(0)),
                #("sequenceNumber", json.int(index + 1)),
                #("minimumSequenceNumber", json.int(0)),
              ])
            }),
            fn(value) { value },
          ),
        ),
        #("expectedGraphs", json.array(graphs, fn(value) { value })),
        #("nativeGraphs", json.array(graphs, fn(value) { value })),
        #("features", json_ot.to_json(features)),
        #("application", json_ot.to_json(application)),
      ]),
    )
  })
}

fn advanced_nested_message_item(
  initial: summary.TreeSummaryData,
  messages: List(JsonValue),
  expected_graph: JsonValue,
  session: fluid_ids.SessionId,
  compressor: fluid_ids.Compressor,
) -> Result(Json, String) {
  use encoded_source <- result.try(
    list.first(messages)
    |> result.map_error(fn(_) { "missing nested source message" }),
  )
  use decoded <- result.try(
    codec.decode_message(
      json.to_string(json_ot.to_json(encoded_source)),
      codec.DecodeContext(codec.Fluid310, compressor),
    )
    |> native,
  )
  use encoded <- result.try(
    codec.encode_message(
      decoded,
      codec.EncodeContext(codec.Fluid310, compressor, Some(initial.schema)),
    )
    |> native,
  )
  use graphs <- result.try(message_graphs(decoded, compressor))
  use initial_encoded <- result.try(
    summary.encode(
      initial,
      session,
      codec.EncodeContext(codec.Fluid310, compressor, Some(initial.schema)),
    )
    |> native,
  )
  use compressor_raw <- result.try(serialize_compressor(compressor, False))
  use consumer_session <- result.try(
    fluid_ids.session_id(native_summary_consumer_session)
    |> result.map_error(string.inspect),
  )
  Ok(
    item(
      "message-array-advanced-nested",
      "message",
      json.array([encoded], fn(value) { value }),
      [
        #("schemaProfile", json.string("array")),
        #("compressor", json.string(compressor_raw)),
        #("compressorMode", json.string("summary")),
        #(
          "session",
          json.string(fluid_ids.session_id_to_string(consumer_session)),
        ),
        #("initialSummary", summary_json(initial_encoded)),
        #("allocationRanges", json.array([], fn(value) { value })),
        #(
          "sequencing",
          json.array(
            [
              json.object([
                #("clientId", json.string("watershed-native-nested")),
                #("clientSequenceNumber", json.int(1)),
                #("referenceSequenceNumber", json.int(2)),
                #("sequenceNumber", json.int(111)),
                #("minimumSequenceNumber", json.int(0)),
              ]),
            ],
            fn(value) { value },
          ),
        ),
        #(
          "expectedGraphs",
          json.array(
            [json.array([json_ot.to_json(expected_graph)], fn(value) { value })],
            fn(value) { value },
          ),
        ),
        #("nativeGraphs", json.array([graphs], fn(value) { value })),
        #("features", json.array(["nestedChanges"], json.string)),
      ],
    ),
  )
}

fn advanced_array_message_items(
  initial: summary.TreeSummaryData,
  messages: List(JsonValue),
  expected: List(JsonValue),
  session: fluid_ids.SessionId,
  compressor: fluid_ids.Compressor,
) -> Result(List(Json), String) {
  let sources =
    list.zip(
      list.zip(
        [
          #("message-array-advanced-rename", [
            "finalEndpoint",
            "idOverride",
            "rename",
          ]),
          #("message-array-advanced-aad", ["idOverride", "attachAndDetach"]),
          #("message-array-advanced-move-in-remove", [
            "idOverride",
            "rename",
            "moveInRemove",
          ]),
          #("message-array-advanced-insert-move-out", [
            "idOverride",
            "rename",
            "insertMoveOut",
          ]),
        ],
        messages,
      ),
      expected,
    )
  use _ <- result.try(case list.length(sources) == 4 {
    True -> Ok(Nil)
    False -> Error("advanced array codec fixture must contain four messages")
  })
  use initial_encoded <- result.try(
    summary.encode(
      initial,
      session,
      codec.EncodeContext(codec.Fluid310, compressor, Some(initial.schema)),
    )
    |> native,
  )
  use compressor_raw <- result.try(serialize_compressor(compressor, False))
  use consumer_session <- result.try(
    fluid_ids.session_id(native_summary_consumer_session)
    |> result.map_error(string.inspect),
  )
  list.try_map(sources, fn(source) {
    let #(#(#(id, features), encoded_source), expected_graphs) = source
    use decoded <- result.try(
      codec.decode_message(
        json.to_string(json_ot.to_json(encoded_source)),
        codec.DecodeContext(codec.Fluid310, compressor),
      )
      |> native,
    )
    use encoded <- result.try(
      codec.encode_message(
        decoded,
        codec.EncodeContext(codec.Fluid310, compressor, Some(initial.schema)),
      )
      |> native,
    )
    use graphs <- result.try(message_graphs(decoded, compressor))
    Ok(
      item(id, "message", json.array([encoded], fn(value) { value }), [
        #("schemaProfile", json.string("array")),
        #("compressor", json.string(compressor_raw)),
        #("compressorMode", json.string("summary")),
        #(
          "session",
          json.string(fluid_ids.session_id_to_string(consumer_session)),
        ),
        #("initialSummary", summary_json(initial_encoded)),
        #("allocationRanges", json.array([], fn(value) { value })),
        #(
          "sequencing",
          json.array(
            [
              json.object([
                #("clientId", json.string("watershed-native-advanced")),
                #("clientSequenceNumber", json.int(1)),
                #("referenceSequenceNumber", json.int(2)),
                #("sequenceNumber", json.int(110)),
                #("minimumSequenceNumber", json.int(0)),
              ]),
            ],
            fn(value) { value },
          ),
        ),
        #(
          "expectedGraphs",
          json.array([json_ot.to_json(expected_graphs)], fn(value) { value }),
        ),
        #("nativeGraphs", json.array([graphs], fn(value) { value })),
        #("features", json.array(features, json.string)),
      ]),
    )
  })
}

fn native_array_message_item(
  initial: summary.TreeSummaryData,
  session: fluid_ids.SessionId,
  compressor: fluid_ids.Compressor,
) -> Result(Json, String) {
  use data <- result.try(summary_forest_data(initial))
  use view_id <- result.try(
    fluid_ids.stable_id("71000000-0000-4000-8000-000000000007")
    |> result.map_error(string.inspect),
  )
  use state <- result.try(
    forest.import_data(view_id, initial.schema, data) |> native,
  )
  use #(compressor, first_local) <- result.try(
    fluid_ids.generate(compressor) |> result.map_error(string.inspect),
  )
  let #(compressor, first_range) = fluid_ids.take_creation_range(compressor)
  use first_range <- result.try(case first_range {
    Some(value) -> Ok(value)
    None -> Error("native array move generated no allocation range")
  })
  use compressor <- result.try(
    fluid_ids.finalize(compressor, first_range)
    |> result.map_error(string.inspect),
  )
  use first_revision <- result.try(
    fluid_ids.decompress(compressor, first_local)
    |> result.map_error(string.inspect),
  )
  use #(compressor, second_local) <- result.try(
    fluid_ids.generate(compressor) |> result.map_error(string.inspect),
  )
  let #(compressor, second_range) = fluid_ids.take_creation_range(compressor)
  use second_range <- result.try(case second_range {
    Some(value) -> Ok(value)
    None -> Error("native nested edit generated no allocation range")
  })
  use compressor <- result.try(
    fluid_ids.finalize(compressor, second_range)
    |> result.map_error(string.inspect),
  )
  use second_revision <- result.try(
    fluid_ids.decompress(compressor, second_local)
    |> result.map_error(string.inspect),
  )
  use order <- result.try(
    codec.identity_order(
      [first_revision, second_revision],
      compressor,
      "message-array-native-authored",
    )
    |> native,
  )
  use moved <- result.try(
    change.edit(
      initial.schema,
      state,
      first_revision,
      ArrayMove(["left"], 0, 2, ["right"], 1),
      order,
    )
    |> native,
  )
  use move_delta <- result.try(
    change.into_delta(change.TaggedChange(Some(first_revision), None, moved))
    |> native,
  )
  use moved_state <- result.try(forest.apply_delta(state, move_delta) |> native)
  use nested <- result.try(
    change.edit(
      initial.schema,
      moved_state,
      second_revision,
      SetField(["narrow", "0", "label"], StringValue("native-nested")),
      order,
    )
    |> native,
  )
  let messages = [
    codec.TreeMessage(
      codec.WireCommit(
        first_revision,
        session,
        [shared_change.DataChange(moved)],
        None,
      ),
      [],
    ),
    codec.TreeMessage(
      codec.WireCommit(
        second_revision,
        session,
        [shared_change.DataChange(nested)],
        None,
      ),
      [],
    ),
  ]
  use encoded <- result.try(
    list.try_map(messages, fn(message) {
      codec.encode_message(
        message,
        codec.EncodeContext(codec.Fluid310, compressor, Some(initial.schema)),
      )
      |> native
    }),
  )
  use decoded <- result.try(
    list.try_map(encoded, fn(message) {
      codec.decode_message(
        json.to_string(message),
        codec.DecodeContext(codec.Fluid310, compressor),
      )
      |> native
    }),
  )
  use graphs <- result.try(list.try_map(decoded, message_graphs(_, compressor)))
  use initial_encoded <- result.try(
    summary.encode(
      initial,
      session,
      codec.EncodeContext(codec.Fluid310, compressor, Some(initial.schema)),
    )
    |> native,
  )
  use compressor_raw <- result.try(serialize_compressor(compressor, False))
  use consumer_session <- result.try(
    fluid_ids.session_id(native_summary_consumer_session)
    |> result.map_error(string.inspect),
  )
  let sequencing = [
    json.object([
      #("clientId", json.string("watershed-native-array")),
      #("clientSequenceNumber", json.int(1)),
      #("referenceSequenceNumber", json.int(1)),
      #("sequenceNumber", json.int(100)),
      #("minimumSequenceNumber", json.int(0)),
    ]),
    json.object([
      #("clientId", json.string("watershed-native-array")),
      #("clientSequenceNumber", json.int(2)),
      #("referenceSequenceNumber", json.int(100)),
      #("sequenceNumber", json.int(101)),
      #("minimumSequenceNumber", json.int(0)),
    ]),
  ]
  Ok(
    item(
      "message-array-native-authored",
      "message",
      json.array(encoded, fn(value) { value }),
      [
        #("schemaProfile", json.string("array")),
        #("compressor", json.string(compressor_raw)),
        #("compressorMode", json.string("summary")),
        #(
          "session",
          json.string(fluid_ids.session_id_to_string(consumer_session)),
        ),
        #("initialSummary", summary_json(initial_encoded)),
        #("allocationRanges", json.array([], fn(value) { value })),
        #("sequencing", json.array(sequencing, fn(value) { value })),
        #("expectedGraphs", json.array(graphs, fn(value) { value })),
      ],
    ),
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
        shared_change.DataChange(value) -> Ok(value)
        shared_change.SchemaChange(_, _, _) -> Error(Nil)
      }
    })
    |> list.try_map(fn(value) {
      array_change_fixture.graph_json_with_compressor(value, compressor)
    }),
  )
  Ok(json.array(graphs, fn(value) { value }))
}

fn array_summary_item(
  source: #(String, JsonValue, fluid_ids.SessionId, fluid_ids.Compressor),
) -> Result(Json, String) {
  let #(id, encoded, session, compressor) = source
  use decoded <- result.try(
    summary.decode(
      summary_entry(encoded),
      None,
      session,
      codec.DecodeContext(codec.Fluid310, compressor),
    )
    |> native,
  )
  use encoded <- result.try(
    summary.encode(
      decoded,
      session,
      codec.EncodeContext(codec.Fluid310, compressor, Some(decoded.schema)),
    )
    |> native,
  )
  use compressor_raw <- result.try(serialize_compressor(compressor, False))
  use consumer_session <- result.try(
    fluid_ids.session_id(native_summary_consumer_session)
    |> result.map_error(string.inspect),
  )
  Ok(
    item("summary-array-" <> id, "summary", summary_json(encoded), [
      #("schemaProfile", json.string("array")),
      #("compressor", json.string(compressor_raw)),
      #("compressorMode", json.string("summary")),
      #(
        "session",
        json.string(fluid_ids.session_id_to_string(consumer_session)),
      ),
    ]),
  )
}

fn array_peer_summary_item(
  source: #(String, JsonValue, fluid_ids.SessionId, fluid_ids.Compressor),
) -> Result(Json, String) {
  let #(_, encoded, session, compressor) = source
  array_summary_item(#("peer-history", encoded, session, compressor))
}

fn restored_summary_item(
  sources: List(#(String, JsonValue, String, String)),
) -> Result(Json, String) {
  use source <- result.try(
    list.find(sources, fn(source) { source.0 == "settled-detached" })
    |> result.map_error(fn(_) { "missing settled-detached summary" }),
  )
  let #(_, encoded, session_raw, compressor_raw) = source
  use session <- result.try(
    fluid_ids.session_id(session_raw) |> result.map_error(string.inspect),
  )
  use #(_, compressor) <- result.try(restore_summary_compressor(
    compressor_raw,
    session,
  ))
  use decoded <- result.try(
    summary.decode(
      summary_entry(encoded),
      None,
      session,
      codec.DecodeContext(codec.Fluid310, compressor),
    )
    |> native,
  )
  use view <- result.try(
    fluid_ids.stable_id(native_summary_consumer_session)
    |> result.map_error(string.inspect),
  )
  use snapshot <- result.try(
    tree_summary.from_wire(decoded, view, compressor, 6, 0)
    |> result.map_error(string.inspect),
  )
  use restored <- result.try(
    tree_summary.to_wire(snapshot) |> result.map_error(string.inspect),
  )
  use encoded <- result.try(
    summary.encode(
      restored,
      session,
      codec.EncodeContext(codec.Fluid310, compressor, Some(restored.schema)),
    )
    |> native,
  )
  use serialized <- result.try(serialize_compressor(compressor, False))
  Ok(
    item("summary-restored-detached", "summary", summary_json(encoded), [
      #("compressor", json.string(serialized)),
      #("compressorMode", json.string("summary")),
      #("session", json.string(native_summary_consumer_session)),
    ]),
  )
}

fn summary_item(
  source: #(String, JsonValue, String, String),
) -> Result(Json, String) {
  let #(id, encoded, session_raw, compressor_raw) = source
  use source_session <- result.try(
    fluid_ids.session_id(session_raw)
    |> result.map_error(string.inspect),
  )
  use #(session, compressor) <- result.try(restore_summary_compressor(
    compressor_raw,
    source_session,
  ))
  use decoded <- result.try(
    summary.decode(
      summary_entry(encoded),
      None,
      session,
      codec.DecodeContext(codec.Fluid310, compressor),
    )
    |> native,
  )
  use decoded <- result.try(add_peer_base(id, decoded))
  use encoded <- result.try(
    summary.encode(
      decoded,
      session,
      codec.EncodeContext(codec.Fluid310, compressor, Some(decoded.schema)),
    )
    |> native,
  )
  use serialized <- result.try(serialize_compressor(compressor, False))
  use artifact_session <- result.try(
    fluid_ids.session_id(fresh_summary_session)
    |> result.map_error(string.inspect),
  )
  Ok(
    item("summary-" <> id, "summary", summary_json(encoded), [
      #("compressor", json.string(serialized)),
      #("compressorMode", json.string("summary")),
      #(
        "session",
        json.string(fluid_ids.session_id_to_string(artifact_session)),
      ),
    ]),
  )
}

fn add_peer_base(
  id: String,
  value: summary.TreeSummaryData,
) -> Result(summary.TreeSummaryData, String) {
  case id {
    "initial" -> {
      let summary.TreeSummaryData(
        stored,
        forest,
        detached,
        summary.EditManagerSummary(trunk, branches),
      ) = value
      use first <- result.try(
        list.first(trunk)
        |> result.map_error(fn(_) { "initial summary has no trunk commit" }),
      )
      let summary.SummaryCommit(codec.WireCommit(revision, ..), ..) = first
      use peer <- result.try(
        fluid_ids.session_id(summary_peer_session)
        |> result.map_error(string.inspect),
      )
      Ok(summary.TreeSummaryData(
        stored,
        forest,
        detached,
        summary.EditManagerSummary(trunk, [
          summary.PeerBranch(peer, summary.StableRevision(revision), []),
          ..branches
        ]),
      ))
    }
    _ -> Ok(value)
  }
}

fn summary_state(
  summaries: List(#(String, JsonValue, String, String)),
  id: String,
) -> Result(InitialState, String) {
  use source <- result.try(
    list.find(summaries, fn(item) { item.0 == id })
    |> result.map_error(fn(_) { "missing summary " <> id }),
  )
  let #(_, encoded, session_raw, compressor_raw) = source
  use session <- result.try(
    fluid_ids.session_id(session_raw)
    |> result.map_error(string.inspect),
  )
  use #(session, compressor) <- result.try(restore_summary_compressor(
    compressor_raw,
    session,
  ))
  use value <- result.try(
    summary.decode(
      summary_entry(encoded),
      None,
      session,
      codec.DecodeContext(codec.Fluid310, compressor),
    )
    |> native,
  )
  Ok(InitialState(value, session, compressor))
}

fn native_messages(
  initial: InitialState,
  note: InitialState,
) -> Result(List(Json), String) {
  let cases = [
    #(
      "message-point-replacement",
      initial,
      SetField(
        ["point"],
        types.ObjectValue("org.watershed.shared-tree.m1.Point", [
          #("x", types.NumberValue(10.0)),
          #("y", types.NumberValue(20.0)),
        ]),
      ),
      False,
      None,
      None,
    ),
    #(
      "message-nested-scalar",
      initial,
      SetField(["point", "x"], types.NumberValue(7.0)),
      False,
      None,
      None,
    ),
    #(
      "message-optional-set",
      initial,
      SetField(["note"], StringValue("native-note")),
      False,
      None,
      None,
    ),
    #("message-optional-clear", note, ClearField(["note"]), False, None, None),
    #("message-detached-repair", note, ClearField(["note"]), True, None, None),
  ]
  list.try_map(cases, fn(example) {
    native_message(
      example.0,
      example.1,
      example.2,
      example.3,
      example.4,
      example.5,
    )
  })
}

fn native_message(
  id: String,
  initial: InitialState,
  operation: types.Edit,
  add_repair: Bool,
  schema_profile: Option(String),
  sequence: Option(#(Int, Int, Int)),
) -> Result(Json, String) {
  let InitialState(base, session, compressor) = initial
  let summary.TreeSummaryData(stored, _, _, _) = base
  use root <- result.try(summary_root(base))
  use #(compressor, local) <- result.try(
    fluid_ids.generate(compressor)
    |> result.map_error(string.inspect),
  )
  let #(compressor, range) = fluid_ids.take_creation_range(compressor)
  use range <- result.try(case range {
    Some(range) -> Ok(range)
    None -> Error("native message generated no allocation range")
  })
  use compressor <- result.try(
    fluid_ids.finalize(compressor, range)
    |> result.map_error(string.inspect),
  )
  use revision <- result.try(
    fluid_ids.decompress(compressor, local)
    |> result.map_error(string.inspect),
  )
  use order <- result.try(
    codec.identity_order([revision], compressor, id)
    |> native,
  )
  use state <- result.try(
    forest.new(revision, stored, Some(root))
    |> native,
  )
  use authored <- result.try(
    change.edit(stored, state, revision, operation, order)
    |> native,
  )
  use authored <- result.try(case add_repair {
    False -> Ok(authored)
    True -> add_repair_content(authored, order)
  })
  let message =
    codec.TreeMessage(
      codec.WireCommit(
        revision,
        session,
        [shared_change.DataChange(authored)],
        Some(
          codec.CustomMetadata(
            Some(json.object([#("source", json.string("watershed-native"))])),
            [],
          ),
        ),
      ),
      [#("watershedScenario", json.string(id))],
    )
  use encoded <- result.try(
    codec.encode_message(
      message,
      codec.EncodeContext(codec.Fluid310, compressor, Some(stored)),
    )
    |> native,
  )
  use initial_summary <- result.try(
    summary.encode(
      base,
      session,
      codec.EncodeContext(codec.Fluid310, compressor, Some(stored)),
    )
    |> native,
  )
  use serialized <- result.try(serialize_compressor(compressor, False))
  use fresh <- result.try(
    fluid_ids.session_id(message_session)
    |> result.map_error(string.inspect),
  )
  let #(sequence_number, reference_sequence_number, minimum_sequence_number) = case
    sequence
  {
    Some(value) -> value
    None -> #(4, 2, 2)
  }
  let profile_fields = case schema_profile {
    Some(profile) -> [#("schemaProfile", json.string(profile))]
    None -> []
  }
  Ok(
    item(id, "message", encoded, [
      #("compressor", json.string(serialized)),
      #("compressorMode", json.string("summary")),
      #("session", json.string(fluid_ids.session_id_to_string(fresh))),
      #("initialSummary", summary_json(initial_summary)),
      #("allocationRanges", json.array([], fn(value) { value })),
      #("sequenceNumber", json.int(sequence_number)),
      #("referenceSequenceNumber", json.int(reference_sequence_number)),
      #("minimumSequenceNumber", json.int(minimum_sequence_number)),
      #("indexInBatch", json.null()),
      ..profile_fields
    ]),
  )
}

fn map_summary_item(initial: InitialState) -> Result(Json, String) {
  let InitialState(value, _, compressor) = initial
  let summary.TreeSummaryData(stored, _, _, _) = value
  use encoded <- result.try(
    summary.encode(
      value,
      fluid_ids.local_session(compressor),
      codec.EncodeContext(codec.Fluid310, compressor, Some(stored)),
    )
    |> result.map_error(string.inspect),
  )
  use serialized <- result.try(serialize_compressor(compressor, False))
  use fresh <- result.try(
    fluid_ids.session_id(native_summary_consumer_session)
    |> result.map_error(string.inspect),
  )
  Ok(
    item("summary-map-restored", "summary", summary_json(encoded), [
      #("compressor", json.string(serialized)),
      #("compressorMode", json.string("summary")),
      #("session", json.string(fluid_ids.session_id_to_string(fresh))),
      #("schemaProfile", json.string("map")),
    ]),
  )
}

fn native_summary(initial: InitialState) -> Result(Json, String) {
  let InitialState(base, session, compressor) = initial
  let summary.TreeSummaryData(stored, _, _, history) = base
  use #(compressor, local) <- result.try(
    fluid_ids.generate(compressor)
    |> result.map_error(string.inspect),
  )
  let #(compressor, range) = fluid_ids.take_creation_range(compressor)
  use range <- result.try(case range {
    Some(range) -> Ok(range)
    None -> Error("native summary generated no allocation range")
  })
  use compressor <- result.try(
    fluid_ids.finalize(compressor, range)
    |> result.map_error(string.inspect),
  )
  use revision <- result.try(
    fluid_ids.decompress(compressor, local)
    |> result.map_error(string.inspect),
  )
  use order <- result.try(
    codec.identity_order([revision], compressor, "summary-native-authored")
    |> native,
  )
  use data <- result.try(summary_forest_data(base))
  use state <- result.try(forest.import_data(revision, stored, data) |> native)
  use authored <- result.try(
    change.edit(
      stored,
      state,
      revision,
      SetField(["title"], StringValue("watershed-native-summary")),
      order,
    )
    |> native,
  )
  use delta <- result.try(
    change.into_delta(change.TaggedChange(Some(revision), None, authored))
    |> native,
  )
  use updated <- result.try(forest.apply_delta(state, delta) |> native)
  use data <- result.try(forest.export_data(updated) |> native)
  let #(forest_summary, detached) = summary_parts(data)
  let summary.EditManagerSummary(trunk, branches) = history
  let sequenced =
    summary.SummaryCommit(
      codec.WireCommit(
        revision,
        session,
        [shared_change.DataChange(authored)],
        Some(
          codec.CustomMetadata(
            Some(
              json.object([#("source", json.string("watershed-native-summary"))]),
            ),
            [],
          ),
        ),
      ),
      Some(next_sequence_number(trunk)),
      None,
    )
  let value =
    summary.TreeSummaryData(
      stored,
      forest_summary,
      detached,
      summary.EditManagerSummary(list.append(trunk, [sequenced]), branches),
    )
  use encoded <- result.try(
    summary.encode(
      value,
      session,
      codec.EncodeContext(codec.Fluid310, compressor, Some(stored)),
    )
    |> native,
  )
  use serialized <- result.try(serialize_compressor(compressor, False))
  use fresh <- result.try(
    fluid_ids.session_id(native_summary_consumer_session)
    |> result.map_error(string.inspect),
  )
  Ok(
    item("summary-native-authored", "summary", summary_json(encoded), [
      #("compressor", json.string(serialized)),
      #("compressorMode", json.string("summary")),
      #("session", json.string(fluid_ids.session_id_to_string(fresh))),
    ]),
  )
}

fn summary_root(
  value: summary.TreeSummaryData,
) -> Result(types.TreeValue, String) {
  let summary.TreeSummaryData(_, summary.ForestSummary(fields), _, _) = value
  use root <- result.try(
    list.key_find(fields, "rootFieldKey")
    |> result.map_error(fn(_) { "summary has no root field" }),
  )
  case root {
    [root] -> Ok(root)
    _ -> Error("summary root field is not a singleton")
  }
}

fn summary_forest_data(
  value: summary.TreeSummaryData,
) -> Result(forest.ForestData, String) {
  let summary.TreeSummaryData(
    _,
    summary.ForestSummary(fields),
    summary.DetachedFieldIndex(entries, max_id),
    _,
  ) = value
  use root <- result.try(summary_root(value))
  use detached <- result.try(
    list.try_map(entries, fn(entry) {
      let summary.DetachedField(major, minor, root_id) = entry
      use values <- result.try(
        list.key_find(fields, "repair-" <> int.to_string(root_id))
        |> result.map_error(fn(_) { "summary repair field is missing" }),
      )
      use value <- result.try(case values {
        [value] -> Ok(value)
        _ -> Error("summary repair field is not a singleton")
      })
      let major = case major {
        summary.RootRevision -> None
        summary.StableRevision(revision) -> Some(revision)
      }
      Ok(forest.DetachedTreeData(AtomId(major, minor), root_id, None, value))
    }),
  )
  Ok(forest.ForestData(Some(root), detached, max_id + 1))
}

fn summary_parts(
  data: forest.ForestData,
) -> #(summary.ForestSummary, summary.DetachedFieldIndex) {
  let forest.ForestData(root, detached, next_root_id) = data
  let root_fields = case root {
    Some(root) -> [#("rootFieldKey", [root])]
    None -> []
  }
  let repair_fields =
    list.map(detached, fn(entry) {
      let forest.DetachedTreeData(_, root, _, value) = entry
      #("repair-" <> int.to_string(root), [value])
    })
  let entries =
    list.map(detached, fn(entry) {
      let forest.DetachedTreeData(AtomId(major, minor), root, _, _) = entry
      let major = case major {
        None -> summary.RootRevision
        Some(revision) -> summary.StableRevision(revision)
      }
      summary.DetachedField(major, minor, root)
    })
  #(
    summary.ForestSummary(list.append(root_fields, repair_fields)),
    summary.DetachedFieldIndex(entries, next_root_id - 1),
  )
}

fn next_sequence_number(trunk: List(summary.SummaryCommit)) -> Int {
  list.fold(trunk, 0, fn(latest, commit) {
    let summary.SummaryCommit(_, sequence, _) = commit
    case sequence {
      Some(sequence) -> int.max(latest, sequence)
      None -> latest
    }
  })
  + 1
}

fn add_repair_content(
  authored: change.Changeset,
  order: change.IdentityOrder,
) -> Result(change.Changeset, String) {
  let data = change.to_data(authored)
  use detached <- result.try(
    first_detach(data)
    |> result.map_error(fn(_) { "clear change has no detached identity" }),
  )
  change.from_data(
    change.ChangeData(..data, refreshers: [
      forest.Build(detached, [StringValue("seed")]),
      ..data.refreshers
    ]),
    order,
  )
  |> native
}

fn first_detach(data: change.ChangeData) -> Result(types.AtomId, Nil) {
  list.append(
    data.fields,
    data.nodes
      |> list.flat_map(fn(entry) {
        let change.NodeChange(fields) = entry.1
        fields
      }),
  )
  |> list.filter_map(fn(entry) { optional_detach(entry.1) })
  |> list.first
}

fn optional_detach(field: change.FieldChange) -> Result(types.AtomId, Nil) {
  case field {
    change.OptionalField(change) ->
      case change.replacement {
        Some(replacement) -> Ok(replacement.detach_id)
        None -> Error(Nil)
      }
    change.SequenceField(value) ->
      value
      |> sequence_field.to_marks
      |> list.filter_map(fn(mark) {
        case mark.effect {
          sequence_field.Detach(sequence_field.Remove(id, _))
          | sequence_field.Detach(sequence_field.MoveOut(id, _, _)) -> Ok(id)
          _ -> Error(Nil)
        }
      })
      |> list.first
    _ -> Error(Nil)
  }
}

fn restore_summary_compressor(
  raw: String,
  source_session: fluid_ids.SessionId,
) -> Result(#(fluid_ids.SessionId, fluid_ids.Compressor), String) {
  case fluid_ids.deserialize(json.string(raw), source_session) {
    Ok(compressor) -> Ok(#(source_session, compressor))
    Error(fluid_ids.SessionMismatch) -> {
      use fresh <- result.try(
        fluid_ids.session_id(fresh_summary_session)
        |> result.map_error(string.inspect),
      )
      fluid_ids.deserialize(json.string(raw), fresh)
      |> result.map(fn(compressor) { #(fresh, compressor) })
      |> result.map_error(string.inspect)
    }
    Error(error) -> Error(string.inspect(error))
  }
}

fn serialize_compressor(
  compressor: fluid_ids.Compressor,
  include_local: Bool,
) -> Result(String, String) {
  use encoded <- result.try(
    fluid_ids.serialize(compressor, include_local)
    |> result.map_error(string.inspect),
  )
  case json_ot.parse_json(json.to_string(encoded)) {
    Ok(VString(value)) -> Ok(value)
    _ -> Error("compressor serialization is not a JSON string")
  }
}

fn item(
  id: String,
  kind: String,
  encoded: Json,
  extra: List(#(String, Json)),
) -> Json {
  json.object([
    #("id", json.string(id)),
    #("kind", json.string(kind)),
    #("encoded", encoded),
    ..extra
  ])
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
    _ -> panic as "unsupported fixture summary entry"
  }
}

fn summary_json(value: fluid_summary.SummaryEntry) -> Json {
  case value {
    fluid_summary.SummaryTree(entries) ->
      json.object([
        #("type", json.int(1)),
        #(
          "tree",
          json.object(
            list.map(entries, fn(entry) { #(entry.0, summary_json(entry.1)) }),
          ),
        ),
      ])
    fluid_summary.SummaryBlob(bytes) -> {
      let assert Ok(content) = bit_array.to_string(bytes)
      json.object([
        #("type", json.int(2)),
        #("content", json.string(content)),
      ])
    }
    fluid_summary.SummaryHandle(_, _) ->
      panic as "native summary output contains a handle"
  }
}

fn decode_summary_source(
  value: JsonValue,
  summary_field: String,
) -> Result(#(String, JsonValue, String, String), String) {
  use id <- result.try(field_text(value, "id"))
  use encoded <- result.try(field(value, summary_field))
  use session <- result.try(field_text(value, "session"))
  use compressor <- result.try(field_text(value, "compressor"))
  Ok(#(id, encoded, session, compressor))
}

fn field(value: JsonValue, name: String) -> Result(JsonValue, String) {
  case value {
    VObject(fields) ->
      list.key_find(fields, name)
      |> result.map_error(fn(_) { "missing field " <> name })
    _ -> Error("expected object for " <> name)
  }
}

fn field_text(value: JsonValue, name: String) -> Result(String, String) {
  use value <- result.try(field(value, name))
  case value {
    VString(value) -> Ok(value)
    _ -> Error("expected string field " <> name)
  }
}

fn array(value: JsonValue) -> Result(List(JsonValue), String) {
  case value {
    VArray(values) -> Ok(values)
    _ -> Error("expected array")
  }
}

fn native(value: Result(a, error)) -> Result(a, String) {
  value |> result.map_error(string.inspect)
}

@target(erlang)
fn target_name() -> String {
  "erlang"
}

@target(javascript)
fn target_name() -> String {
  "javascript"
}
