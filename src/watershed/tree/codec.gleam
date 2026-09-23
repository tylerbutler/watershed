//// Fluid 3.1.0 SharedTree wire codec contexts and common records.

import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import watershed/fluid_ids
import watershed/json_ot.{
  type JsonValue, NInt, VArray, VNumber, VObject, VString,
}
import watershed/tree/change
import watershed/tree/schema
import watershed/tree/types.{type TreeError, CorruptData, InvalidHistory}

pub type Profile {
  Fluid310
}

pub type Purpose {
  Message
  Summary
}

pub type DecodeContext {
  DecodeContext(profile: Profile, compressor: fluid_ids.Compressor)
}

pub type EncodeContext {
  EncodeContext(
    profile: Profile,
    compressor: fluid_ids.Compressor,
    schema: Option(schema.StoredSchema),
  )
}

pub type ChangeContext {
  ChangeContext(
    originator: fluid_ids.SessionId,
    revision: Option(fluid_ids.StableId),
    purpose: Purpose,
  )
}

pub type Revision {
  RootRevision
  StableRevision(fluid_ids.StableId)
}

pub type SchemaState {
  EmptySchema
  FixedSchema(schema.StoredSchema)
}

pub type TreeChange {
  DataChange(change.Changeset)
  SchemaChange(before: SchemaState, after: SchemaState)
}

pub type CustomMetadata {
  CustomMetadata(value: Option(Json), children: List(CustomMetadata))
}

pub type WireCommit {
  WireCommit(
    revision: fluid_ids.StableId,
    originator: fluid_ids.SessionId,
    changes: List(TreeChange),
    custom_metadata: Option(CustomMetadata),
  )
}

pub type TreeMessage {
  TreeMessage(commit: WireCommit, extra_fields: List(#(String, Json)))
}

/// Decode a stored schema or the empty bootstrap schema.
pub fn decode_schema(raw: String) -> Result(SchemaState, TreeError) {
  case schema.stored_from_string(raw) {
    Ok(stored) -> Ok(FixedSchema(stored))
    Error(error) ->
      case json_ot.parse_json(raw) {
        Ok(value) ->
          case is_empty_schema(value) {
            True -> Ok(EmptySchema)
            False -> Error(error)
          }
        _ -> Error(error)
      }
  }
}

/// Encode a schema state without changing validated schema data.
pub fn encode_schema(value: SchemaState) -> Result(Json, TreeError) {
  case value {
    EmptySchema ->
      Ok(
        json_ot.to_json(
          VObject([
            #("version", VNumber(NInt(2))),
            #("nodes", VObject([])),
            #(
              "root",
              VObject([
                #("kind", VString("Forbidden")),
                #("types", VArray([])),
              ]),
            ),
          ]),
        ),
      )
    FixedSchema(stored) -> Ok(schema.stored_to_json(stored))
  }
}

/// Decode one operation-space revision without changing compressor state.
pub fn decode_stable_revision(
  value: Int,
  originator: fluid_ids.SessionId,
  context: DecodeContext,
  location: String,
) -> Result(fluid_ids.StableId, TreeError) {
  let DecodeContext(compressor: compressor, ..) = context
  use operation <- result.try(
    fluid_ids.op_id(value)
    |> result.map_error(fn(error) { id_error(location, error) }),
  )
  use session_space <- result.try(
    fluid_ids.from_op(compressor, operation, originator)
    |> result.map_error(fn(error) { id_error(location, error) }),
  )
  fluid_ids.decompress(compressor, session_space)
  |> result.map_error(fn(error) { id_error(location, error) })
}

/// Encode one known revision without changing compressor state.
pub fn encode_stable_revision(
  revision: fluid_ids.StableId,
  context: EncodeContext,
  location: String,
) -> Result(Int, TreeError) {
  let EncodeContext(compressor: compressor, ..) = context
  use session_space <- result.try(
    fluid_ids.recompress(compressor, revision)
    |> result.map_error(fn(error) { id_error(location, error) }),
  )
  use session_space <- result.try(case session_space {
    Some(value) -> Ok(value)
    None -> Error(CorruptData(location, "revision is not in the compressor"))
  })
  fluid_ids.to_op(compressor, session_space)
  |> result.map(fluid_ids.op_id_to_int)
  |> result.map_error(fn(error) { id_error(location, error) })
}

/// Build change ordering from compressor session-space IDs.
pub fn identity_order(
  revisions: List(fluid_ids.StableId),
  compressor: fluid_ids.Compressor,
  location: String,
) -> Result(change.IdentityOrder, TreeError) {
  use entries <- result.try(
    list.try_fold(
      revisions,
      [],
      fn(entries: List(#(fluid_ids.StableId, Int)), revision) {
        case list.any(entries, fn(entry) { entry.0 == revision }) {
          True -> Ok(entries)
          False -> {
            use compressed <- result.try(
              fluid_ids.recompress(compressor, revision)
              |> result.map_error(fn(error) { id_error(location, error) }),
            )
            use compressed <- result.try(case compressed {
              Some(value) -> Ok(value)
              None ->
                Error(CorruptData(location, "revision is not in the compressor"))
            })
            Ok([
              #(revision, fluid_ids.session_space_id_to_int(compressed)),
              ..entries
            ])
          }
        }
      },
    ),
  )
  change.identity_order(list.reverse(entries))
  |> result.map_error(fn(error) {
    case error {
      InvalidHistory(detail) -> InvalidHistory(detail)
      _ -> CorruptData(location, "invalid revision identity order")
    }
  })
}

fn id_error(location: String, error: fluid_ids.IdError) -> TreeError {
  CorruptData(location, "ID compressor error: " <> string.inspect(error))
}

fn is_empty_schema(value: JsonValue) -> Bool {
  case value {
    VObject([
      #("nodes", VObject([])),
      #(
        "root",
        VObject([#("kind", VString("Forbidden")), #("types", VArray([]))]),
      ),
      #("version", VNumber(NInt(2))),
    ]) -> True
    _ -> False
  }
}
