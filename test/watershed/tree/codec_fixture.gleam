import gleam/json.{type Json}
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import watershed/fluid_ids
import watershed/json_ot.{type JsonValue, NInt, VNumber, VObject, VString}
import watershed/tree/change_fixture_codec as fixture_codec
import watershed/tree/codec
import watershed/tree/codec/field_batch
import watershed/tree/codec/summary
import watershed/wire/fluid_summary

const fresh_summary_session = "30000000-0000-4000-8000-000000000003"

pub fn run(input: Json) -> Result(Json, String) {
  use value <- result.try(fixture_codec.parse(input))
  use _ <- result.try(
    fixture_codec.exact(value, [
      "profile",
      "scenarios",
      "schemas",
      "fieldBatches",
      "metadataMessage",
      "summaries",
    ]),
  )
  use _ <- result.try(validate_profile(value))
  use _ <- result.try(
    fixture_codec.field(value, "schemas", fn(value) {
      fixture_codec.many(value, validate_schema)
    }),
  )
  use _ <- result.try(
    fixture_codec.field(value, "fieldBatches", fn(value) {
      fixture_codec.many(value, validate_field_batch)
    }),
  )
  use summaries <- result.try(fixture_codec.field(
    value,
    "summaries",
    fixture_codec.items,
  ))
  use summary_observations <- result.try(decode_summaries(summaries))
  use scenarios <- result.try(fixture_codec.field(
    value,
    "scenarios",
    fixture_codec.items,
  ))
  use message_observations <- result.try(list.try_map(
    scenarios,
    decode_scenario,
  ))
  use metadata <- result.try(fixture_codec.field(
    value,
    "metadataMessage",
    decode_metadata_message,
  ))
  Ok(
    json.object([
      #(
        "observations",
        fixture_codec.array(
          list.flatten([
            summary_observations,
            message_observations,
            [
              json.object([
                #("id", json.string("metadata")),
                #("value", metadata),
              ]),
            ],
          ]),
        ),
      ),
    ]),
  )
}

fn validate_profile(input: JsonValue) -> Result(Nil, String) {
  fixture_codec.field(input, "profile", fn(value) {
    use _ <- result.try(
      fixture_codec.exact(value, [
        "message",
        "sharedTreeChange",
        "modularChange",
        "optionalField",
        "genericField",
        "fieldBatch",
        "schema",
        "forest",
        "detachedFieldIndex",
        "editManager",
      ]),
    )
    let expected = [
      #("message", 7),
      #("sharedTreeChange", 5),
      #("modularChange", 5),
      #("optionalField", 2),
      #("genericField", 1),
      #("fieldBatch", 2),
      #("schema", 2),
      #("forest", 2),
      #("detachedFieldIndex", 2),
      #("editManager", 7),
    ]
    list.try_each(expected, fn(item) {
      use actual <- result.try(fixture_codec.field(
        value,
        item.0,
        fixture_codec.integer,
      ))
      case actual == item.1 {
        True -> Ok(Nil)
        False -> Error("unsupported codec profile " <> item.0)
      }
    })
  })
}

fn validate_schema(value: JsonValue) -> Result(Nil, String) {
  use _ <- result.try(fixture_codec.exact(value, ["id", "raw"]))
  use raw <- result.try(fixture_codec.field(value, "raw", fixture_codec.text))
  codec.decode_schema(raw)
  |> result.map(fn(_) { Nil })
  |> native
}

fn validate_field_batch(value: JsonValue) -> Result(Nil, String) {
  use _ <- result.try(fixture_codec.exact(value, ["id", "encoded"]))
  use encoded <- result.try(fixture_codec.get(value, "encoded"))
  field_batch.decode(json_ot.to_json(encoded))
  |> result.map(fn(_) { Nil })
  |> native
}

fn decode_summaries(values: List(JsonValue)) -> Result(List(Json), String) {
  use decoded <- result.try(
    list.try_map(values, fn(value) {
      use _ <- result.try(
        fixture_codec.exact(value, [
          "id",
          "summary",
          "session",
          "compressor",
        ]),
      )
      use id <- result.try(fixture_codec.field(value, "id", fixture_codec.text))
      use session_raw <- result.try(fixture_codec.field(
        value,
        "session",
        fixture_codec.text,
      ))
      use source_session <- result.try(
        fluid_ids.session_id(session_raw)
        |> result.map_error(string.inspect),
      )
      use compressor_raw <- result.try(fixture_codec.field(
        value,
        "compressor",
        fixture_codec.text,
      ))
      use #(session, compressor) <- result.try(restore_summary_compressor(
        compressor_raw,
        source_session,
      ))
      use encoded <- result.try(fixture_codec.get(value, "summary"))
      let entry = summary_entry(encoded)
      use typed <- result.try(
        summary.decode(
          entry,
          None,
          session,
          codec.DecodeContext(codec.Fluid310, compressor),
        )
        |> native,
      )
      Ok(#(id, encoded, typed))
    }),
  )
  let initial = find_summary(decoded, "initial")
  let settled = find_summary(decoded, "settled-detached")
  use initial <- result.try(initial)
  use settled <- result.try(settled)
  use initial_blobs <- result.try(summary_blobs(initial.1))
  use settled_blobs <- result.try(summary_blobs(settled.1))
  Ok([
    observation("bootstrap-history", initial_blobs.0),
    observation("initial-schema", initial_blobs.1),
    observation("initial-forest", initial_blobs.2),
    observation("initial-detached", initial_blobs.3),
    observation("settled-history", settled_blobs.0),
    observation("settled-forest", settled_blobs.2),
    observation("settled-detached", settled_blobs.3),
  ])
}

fn decode_scenario(value: JsonValue) -> Result(Json, String) {
  use _ <- result.try(
    fixture_codec.exact(value, [
      "id",
      "session",
      "compressor",
      "peerSession",
      "peerCompressor",
      "allocationMessages",
      "actions",
      "messages",
      "initialSummary",
      "settledSummary",
      "settledCompressor",
    ]),
  )
  use id <- result.try(fixture_codec.field(value, "id", fixture_codec.text))
  use settled <- result.try(fixture_codec.field(
    value,
    "settledCompressor",
    fixture_codec.text,
  ))
  use fresh <- result.try(
    fluid_ids.session_id(fresh_summary_session)
    |> result.map_error(string.inspect),
  )
  use compressor <- result.try(
    fluid_ids.deserialize(json.string(settled), fresh)
    |> result.map_error(string.inspect),
  )
  use messages <- result.try(
    fixture_codec.field(value, "messages", fn(value) {
      fixture_codec.many(value, fixture_codec.text)
    }),
  )
  use encoded <- result.try(
    list.try_map(messages, fn(raw) {
      use _ <- result.try(
        codec.decode_message(
          raw,
          codec.DecodeContext(codec.Fluid310, compressor),
        )
        |> native,
      )
      json_ot.parse_json(raw)
      |> result.map(json_ot.to_json)
      |> result.map_error(string.inspect)
    }),
  )
  Ok(observation(
    "message-" <> id,
    json.object([#("messages", fixture_codec.array(encoded))]),
  ))
}

fn decode_metadata_message(value: JsonValue) -> Result(Json, String) {
  use _ <- result.try(
    fixture_codec.exact(value, [
      "raw",
      "session",
      "compressor",
      "allocationMessages",
    ]),
  )
  use raw <- result.try(fixture_codec.field(value, "raw", fixture_codec.text))
  use session_raw <- result.try(fixture_codec.field(
    value,
    "session",
    fixture_codec.text,
  ))
  use session <- result.try(
    fluid_ids.session_id(session_raw)
    |> result.map_error(string.inspect),
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
  use allocations <- result.try(fixture_codec.field(
    value,
    "allocationMessages",
    fixture_codec.items,
  ))
  use compressor <- result.try(
    list.try_fold(allocations, compressor, fn(compressor, message) {
      use contents <- result.try(fixture_codec.get(message, "contents"))
      use range <- result.try(fixture_codec.get(contents, "contents"))
      use range <- result.try(
        fluid_ids.creation_range_from_json(json_ot.to_json(range))
        |> result.map_error(string.inspect),
      )
      fluid_ids.finalize(compressor, range)
      |> result.map_error(string.inspect)
    }),
  )
  use message <- result.try(
    codec.decode_message(raw, codec.DecodeContext(codec.Fluid310, compressor))
    |> native,
  )
  let codec.TreeMessage(codec.WireCommit(custom_metadata: metadata, ..), _) =
    message
  case metadata {
    Some(metadata) -> Ok(codec.custom_metadata_to_json(metadata))
    None -> Error("metadata message has no metadata")
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

fn summary_blobs(
  value: JsonValue,
) -> Result(#(Json, Json, Json, Json), String) {
  use history <- result.try(
    blob_json(value, ["indexes", "EditManager", "String"]),
  )
  use schema <- result.try(
    blob_json(value, ["indexes", "Schema", "SchemaString"]),
  )
  use forest <- result.try(blob_json(value, ["indexes", "Forest", "contents"]))
  use detached <- result.try(
    blob_json(value, ["indexes", "DetachedFieldIndex", "DetachedFieldIndexBlob"]),
  )
  Ok(#(history, schema, forest, detached))
}

fn blob_json(value: JsonValue, path: List(String)) -> Result(Json, String) {
  case path {
    [] -> {
      let assert VObject(members) = value
      use content <- result.try(
        list.key_find(members, "content")
        |> result.map_error(fn(_) { "summary blob has no content" }),
      )
      use raw <- result.try(fixture_codec.text(content))
      json_ot.parse_json(raw)
      |> result.map(json_ot.to_json)
      |> result.map_error(string.inspect)
    }
    [name, ..rest] -> {
      let assert VObject(members) = value
      use tree <- result.try(
        list.key_find(members, "tree")
        |> result.map_error(fn(_) { "summary entry is not a tree" }),
      )
      let assert VObject(entries) = tree
      use child <- result.try(
        list.key_find(entries, name)
        |> result.map_error(fn(_) { "missing summary entry " <> name }),
      )
      blob_json(child, rest)
    }
  }
}

fn find_summary(
  summaries: List(#(String, JsonValue, summary.TreeSummaryData)),
  id: String,
) -> Result(#(String, JsonValue, summary.TreeSummaryData), String) {
  list.find(summaries, fn(item) { item.0 == id })
  |> result.map_error(fn(_) { "missing summary " <> id })
}

fn observation(id: String, value: Json) -> Json {
  json.object([#("id", json.string(id)), #("value", value)])
}

fn native(value: Result(a, error)) -> Result(a, String) {
  value |> result.map_error(string.inspect)
}
