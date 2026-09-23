//// Generates native SharedTree codec artifacts for the pinned upstream consumer.

import envoy
import gleam/bit_array
import gleam/json.{type Json}
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import simplifile
import watershed/fluid_ids
import watershed/json_ot.{
  type JsonValue, NInt, VArray, VNumber, VObject, VString,
}
import watershed/tree/change
import watershed/tree/codec
import watershed/tree/codec/field_batch
import watershed/tree/codec/summary
import watershed/tree/forest
import watershed/tree/schema
import watershed/tree/types.{
  BooleanValue, ClearField, NullValue, NumberValue, ObjectValue, SetField,
  StringValue,
}
import watershed/wire/fluid_summary

const fixture_path = "test/fixtures/shared_tree/cases/tree-codecs.json"

const reference_commit = "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960"

const reference_version = "3.1.0"

const fresh_summary_session = "30000000-0000-4000-8000-000000000003"

const message_session = "40000000-0000-4000-8000-000000000004"

const summary_peer_session = "50000000-0000-4000-8000-000000000005"

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
  let artifact = case build_artifact(input) {
    Ok(value) -> value
    Error(error) -> panic as { error }
  }
  case simplifile.write(output, json.to_string(artifact) <> "\n") {
    Ok(_) -> Nil
    Error(error) ->
      panic as { "could not write codec artifact: " <> string.inspect(error) }
  }
}

type Input {
  Input(
    schemas: List(#(String, String)),
    field_batches: List(#(String, Json)),
    summaries: List(#(String, JsonValue, String, String)),
  )
}

type InitialState {
  InitialState(
    value: summary.TreeSummaryData,
    session: fluid_ids.SessionId,
    compressor: fluid_ids.Compressor,
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
      use id <- result.try(field_text(value, "id"))
      use encoded <- result.try(field(value, "summary"))
      use session <- result.try(field_text(value, "session"))
      use compressor <- result.try(field_text(value, "compressor"))
      Ok(#(id, encoded, session, compressor))
    }),
  )
  Ok(Input(schemas, batches, summaries))
}

fn build_artifact(input: Input) -> Result(Json, String) {
  let Input(schemas, batches, summaries) = input
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
  use initial <- result.try(initial_state(summaries))
  use message_items <- result.try(native_messages(initial))
  let items =
    list.flatten([schema_items, batch_items, message_items, summary_items])
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

fn initial_state(
  summaries: List(#(String, JsonValue, String, String)),
) -> Result(InitialState, String) {
  use source <- result.try(
    list.find(summaries, fn(item) { item.0 == "initial" })
    |> result.map_error(fn(_) { "missing initial summary" }),
  )
  let #(_, encoded, session_raw, compressor_raw) = source
  use session <- result.try(
    fluid_ids.session_id(session_raw)
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
    |> native,
  )
  Ok(InitialState(value, session, compressor))
}

fn native_messages(initial: InitialState) -> Result(List(Json), String) {
  let InitialState(value, session, compressor) = initial
  let summary.TreeSummaryData(stored, summary.ForestSummary(fields), _, history) =
    value
  use root <- result.try(
    list.key_find(fields, "rootFieldKey")
    |> result.map_error(fn(_) { "initial summary has no root field" }),
  )
  use root <- result.try(case root {
    [root] -> Ok(root)
    _ -> Error("initial summary root field is not a singleton")
  })
  let with_note =
    ObjectValue("org.watershed.shared-tree.m1.Root", [
      #("title", StringValue("")),
      #("enabled", BooleanValue(False)),
      #("rating", NumberValue(0.0)),
      #("marker", NullValue),
      #("note", StringValue("to-clear")),
      #(
        "point",
        ObjectValue("org.watershed.shared-tree.m1.Point", [
          #("x", NumberValue(0.0)),
          #("y", NumberValue(0.0)),
        ]),
      ),
    ])
  let cases = [
    #(
      "message-point-replacement",
      root,
      SetField(
        ["point"],
        ObjectValue("org.watershed.shared-tree.m1.Point", [
          #("x", NumberValue(10.0)),
          #("y", NumberValue(20.0)),
        ]),
      ),
      False,
    ),
    #(
      "message-nested-scalar",
      root,
      SetField(["point", "x"], NumberValue(7.0)),
      False,
    ),
    #(
      "message-optional-set",
      root,
      SetField(["note"], StringValue("native-note")),
      False,
    ),
    #("message-optional-clear", with_note, ClearField(["note"]), False),
    #("message-detached-repair", with_note, ClearField(["note"]), True),
  ]
  list.try_map(cases, fn(example) {
    native_message(
      example.0,
      example.1,
      example.2,
      example.3,
      value,
      history,
      stored,
      session,
      compressor,
    )
  })
}

fn native_message(
  id: String,
  root: types.TreeValue,
  operation: types.Edit,
  add_repair: Bool,
  base: summary.TreeSummaryData,
  history: summary.EditManagerSummary,
  stored: schema.StoredSchema,
  session: fluid_ids.SessionId,
  compressor: fluid_ids.Compressor,
) -> Result(Json, String) {
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
        [codec.DataChange(authored)],
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
  let summary.TreeSummaryData(_, _, detached, _) = base
  let initial =
    summary.TreeSummaryData(
      stored,
      summary.ForestSummary([#("rootFieldKey", [root])]),
      detached,
      history,
    )
  use initial_summary <- result.try(
    summary.encode(
      initial,
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
  Ok(
    item(id, "message", encoded, [
      #("compressor", json.string(serialized)),
      #("compressorMode", json.string("summary")),
      #("session", json.string(fluid_ids.session_id_to_string(fresh))),
      #("initialSummary", summary_json(initial_summary)),
      #("allocationRanges", json.array([], fn(value) { value })),
      #("sequenceNumber", json.int(4)),
      #("referenceSequenceNumber", json.int(2)),
      #("minimumSequenceNumber", json.int(2)),
      #("indexInBatch", json.null()),
    ]),
  )
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
      forest.Build(detached, [StringValue("to-clear")]),
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
