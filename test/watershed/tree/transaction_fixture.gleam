import gleam/json.{type Json}
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import watershed/fluid_ids
import watershed/json_ot.{type JsonValue, VObject}
import watershed/tree/change
import watershed/tree/change_fixture_codec as fixture_codec
import watershed/tree/codec
import watershed/tree/fixtures
import watershed/tree/forest
import watershed/tree/shared_change
import watershed/tree/types

type WireInput {
  WireInput(
    id: String,
    nonviolated_bytes: String,
    nonviolated_session: fluid_ids.SessionId,
    nonviolated_compressor: fluid_ids.Compressor,
    violated_bytes: String,
    violated_session: fluid_ids.SessionId,
    violated_compressor: fluid_ids.Compressor,
  )
}

pub fn run_wire(input: Json) -> Result(Json, String) {
  use input <- result.try(fixture_codec.parse(input))
  use parsed <- result.try(decode_input(input))
  use nonviolated <- result.try(decode_message(
    parsed.nonviolated_bytes,
    parsed.nonviolated_compressor,
  ))
  use violated <- result.try(decode_message(
    parsed.violated_bytes,
    parsed.violated_compressor,
  ))
  Ok(
    json.object([
      #(
        "observations",
        fixture_codec.array([
          json.object([
            #("id", json.string(parsed.id)),
            #("nonviolated", nonviolated.0),
            #("violated", violated.0),
            #(
              "message",
              json.object([
                #("nonviolated", nonviolated.1),
                #("violated", violated.1),
              ]),
            ),
            #(
              "messageBytes",
              json.object([
                #("nonviolated", json.string(nonviolated.2)),
                #("violated", json.string(violated.2)),
              ]),
            ),
            #(
              "compressorSessions",
              json.object([
                #(
                  "nonviolated",
                  json.string(fluid_ids.session_id_to_string(
                    parsed.nonviolated_session,
                  )),
                ),
                #(
                  "violated",
                  json.string(fluid_ids.session_id_to_string(
                    parsed.violated_session,
                  )),
                ),
              ]),
            ),
          ]),
        ]),
      ),
    ]),
  )
}

fn decode_input(value: JsonValue) -> Result(WireInput, String) {
  use _ <- result.try(
    fixture_codec.exact(value, [
      "messageBytes",
      "compressor",
      "context",
      "operands",
      "scenarios",
    ]),
  )
  use context <- result.try(fixture_codec.get(value, "context"))
  use _ <- result.try(decode_context(context))
  use operands <- result.try(fixture_codec.get(value, "operands"))
  use _ <- result.try(require_object(operands, "operands"))
  use scenarios <- result.try(fixture_codec.field(
    value,
    "scenarios",
    fixture_codec.items,
  ))
  use id <- result.try(case scenarios {
    [scenario] -> fixture_codec.field(scenario, "id", fixture_codec.text)
    _ -> Error("expected one transaction wire scenario")
  })
  use _ <- result.try(case id {
    "modular-v5-shared-tree-v5" -> Ok(Nil)
    _ -> Error("unsupported transaction wire scenario: " <> id)
  })
  use message_bytes <- result.try(fixture_codec.get(value, "messageBytes"))
  use nonviolated_bytes <- result.try(fixture_codec.field(
    message_bytes,
    "nonviolated",
    fixture_codec.text,
  ))
  use violated_bytes <- result.try(fixture_codec.field(
    message_bytes,
    "violated",
    fixture_codec.text,
  ))
  use _ <- result.try(fixture_codec.field(
    message_bytes,
    "over",
    fixture_codec.text,
  ))
  use compressors <- result.try(fixture_codec.get(value, "compressor"))
  use nonviolated <- result.try(fixture_codec.field(
    compressors,
    "nonviolated",
    decode_compressor,
  ))
  use violated <- result.try(fixture_codec.field(
    compressors,
    "violated",
    decode_compressor,
  ))
  use _ <- result.try(fixture_codec.field(
    compressors,
    "over",
    decode_compressor,
  ))
  Ok(WireInput(
    id:,
    nonviolated_bytes:,
    nonviolated_session: nonviolated.0,
    nonviolated_compressor: nonviolated.1,
    violated_bytes:,
    violated_session: violated.0,
    violated_compressor: violated.1,
  ))
}

fn decode_context(value: JsonValue) -> Result(Nil, String) {
  use _ <- result.try(
    fixture_codec.exact(value, [
      "message",
      "sharedTreeChange",
      "modularChange",
      "minVersionForCollab",
    ]),
  )
  use message <- result.try(fixture_codec.field(
    value,
    "message",
    fixture_codec.integer,
  ))
  use shared_tree <- result.try(fixture_codec.field(
    value,
    "sharedTreeChange",
    fixture_codec.integer,
  ))
  use modular <- result.try(fixture_codec.field(
    value,
    "modularChange",
    fixture_codec.integer,
  ))
  use minimum <- result.try(fixture_codec.field(
    value,
    "minVersionForCollab",
    fixture_codec.text,
  ))
  case message, shared_tree, modular, minimum {
    7, 5, 5, "2.117.0" -> Ok(Nil)
    _, _, _, _ -> Error("unsupported transaction wire context")
  }
}

fn decode_compressor(
  value: JsonValue,
) -> Result(#(fluid_ids.SessionId, fluid_ids.Compressor), String) {
  use _ <- result.try(fixture_codec.exact(value, ["serialized", "sessionId"]))
  use serialized <- result.try(fixture_codec.field(
    value,
    "serialized",
    fixture_codec.text,
  ))
  use session_raw <- result.try(fixture_codec.field(
    value,
    "sessionId",
    fixture_codec.text,
  ))
  use session <- result.try(
    fluid_ids.session_id(session_raw)
    |> result.map_error(string.inspect),
  )
  use compressor <- result.try(
    fluid_ids.deserialize(json.string(serialized), session)
    |> result.map_error(string.inspect),
  )
  Ok(#(session, compressor))
}

fn decode_message(
  bytes: String,
  compressor: fluid_ids.Compressor,
) -> Result(#(Json, Json, String), String) {
  use message <- result.try(
    json_ot.parse_json(bytes) |> result.map_error(string.inspect),
  )
  use compressor_before <- result.try(
    fluid_ids.serialize(compressor, True)
    |> result.map_error(string.inspect),
  )
  use message <- result.try(
    codec.decode_message(
      json.to_string(json_ot.to_json(message)),
      codec.DecodeContext(codec.Fluid310, compressor),
    )
    |> result.map_error(string.inspect),
  )
  use changeset <- result.try(case message {
    codec.TreeMessage(
      codec.WireCommit(changes: [shared_change.DataChange(changeset)], ..),
      _,
    ) -> Ok(changeset)
    _ -> Error("expected one SharedTree data change")
  })
  use encoded <- result.try(
    codec.encode_message(
      message,
      codec.EncodeContext(codec.Fluid310, compressor, option.None),
    )
    |> result.map_error(string.inspect),
  )
  let encoded_bytes = json.to_string(encoded)
  use compressor_after <- result.try(
    fluid_ids.serialize(compressor, True)
    |> result.map_error(string.inspect),
  )
  use _ <- result.try(
    case json.to_string(compressor_after) == json.to_string(compressor_before) {
      True -> Ok(Nil)
      False -> Error("message codec mutated compressor state")
    },
  )
  Ok(#(observe(change.to_data(changeset)), encoded, encoded_bytes))
}

fn observe(data: change.ChangeData) -> Json {
  let constraints =
    data.nodes
    |> list.flat_map(fn(entry) {
      case entry.1.node_exists_constraint {
        None -> []
        Some(constraint) -> [
          json.object([#("violated", json.bool(constraint.violated))]),
        ]
      }
    })
  json.object([
    #("violations", json.int(data.constraint_violation_count)),
    #("constraints", fixture_codec.array(constraints)),
    #("builds", fixture_codec.array(list.map(data.builds, build_json))),
    #("refreshers", fixture_codec.array(list.map(data.refreshers, build_json))),
  ])
}

fn build_json(value: forest.Build) -> Json {
  json.object([
    #("id", atom_json(value.id)),
    #("trees", json.array(value.trees, fixtures.tree_value_to_json)),
  ])
}

fn atom_json(value: types.AtomId) -> Json {
  json.object([
    #("revision", case value.revision {
      None -> json.null()
      Some(value) -> json.string(fluid_ids.stable_id_to_string(value))
    }),
    #("localId", json.int(value.local_id)),
  ])
}

fn require_object(value: JsonValue, name: String) -> Result(Nil, String) {
  case value {
    VObject(_) -> Ok(Nil)
    _ -> Error("expected an object for " <> name)
  }
}
