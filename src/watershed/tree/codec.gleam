//// Fluid 3.1.0 SharedTree wire codec contexts and common records.

import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import watershed/fluid_ids
import watershed/json_ot.{
  type JsonValue, NInt, VArray, VBool, VNull, VNumber, VObject, VString,
}
import watershed/tree/change
import watershed/tree/codec/field_batch
import watershed/tree/forest
import watershed/tree/optional_field
import watershed/tree/schema
import watershed/tree/types.{type TreeError, CorruptData, InvalidHistory}

const max_safe_integer = 9_007_199_254_740_991

const min_safe_integer = -9_007_199_254_740_991

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

type DecodeChangeState {
  DecodeChangeState(
    next_id: Int,
    nodes: List(#(types.AtomId, change.NodeChange)),
    parents: List(#(types.AtomId, change.ParentField)),
  )
}

/// Decode one Message V7 commit envelope.
pub fn decode_message(
  raw: String,
  context: DecodeContext,
) -> Result(TreeMessage, TreeError) {
  decode_message_value(raw, context, None)
}

/// Decode one Message V7 commit envelope with its active stored schema.
pub fn decode_message_with_schema(
  raw: String,
  context: DecodeContext,
  stored: schema.StoredSchema,
) -> Result(TreeMessage, TreeError) {
  decode_message_value(raw, context, Some(stored))
}

fn decode_message_value(
  raw: String,
  context: DecodeContext,
  stored: Option(schema.StoredSchema),
) -> Result(TreeMessage, TreeError) {
  use value <- result.try(
    json_ot.parse_json(raw)
    |> result.map_error(fn(_) {
      CorruptData("message", "message is not valid JSON")
    }),
  )
  use members <- result.try(object(value, "message"))
  use version <- result.try(required(members, "version", "message.version"))
  use version <- result.try(integer(version, "message.version"))
  use _ <- result.try(case version {
    7 -> Ok(Nil)
    other -> Error(types.UnsupportedFormat("Message", int.to_string(other)))
  })
  use originator_value <- result.try(required(
    members,
    "originatorId",
    "message.originatorId",
  ))
  use originator_raw <- result.try(text(
    originator_value,
    "message.originatorId",
  ))
  use originator <- result.try(
    fluid_ids.session_id(originator_raw)
    |> result.map_error(fn(error) {
      CorruptData("message.originatorId", string.inspect(error))
    }),
  )
  use revision_value <- result.try(required(
    members,
    "revision",
    "message.revision",
  ))
  use revision_number <- result.try(integer(revision_value, "message.revision"))
  use revision <- result.try(decode_stable_revision(
    revision_number,
    originator,
    context,
    "message.revision",
  ))
  use changeset <- result.try(required(
    members,
    "changeset",
    "message.changeset",
  ))
  use changes <- result.try(decode_changes_value(
    changeset,
    context,
    ChangeContext(originator, Some(revision), Message),
    stored,
    "message.changeset",
  ))
  use custom_metadata <- result.try(case optional(members, "customMetadata") {
    None -> Ok(None)
    Some(value) -> decode_custom_metadata(value, "message.customMetadata")
  })
  let extra_fields =
    members
    |> list.filter(fn(member) {
      !list.contains(
        ["revision", "originatorId", "changeset", "version", "customMetadata"],
        member.0,
      )
    })
    |> list.map(fn(member) { #(member.0, json_ot.to_json(member.1)) })
  Ok(TreeMessage(
    WireCommit(revision, originator, changes, custom_metadata),
    extra_fields,
  ))
}

/// Encode one Message V7 commit envelope.
pub fn encode_message(
  message: TreeMessage,
  context: EncodeContext,
) -> Result(Json, TreeError) {
  let TreeMessage(
    WireCommit(revision, originator, changes, custom_metadata),
    extra_fields,
  ) = message
  use _ <- result.try(validate_extra_fields(extra_fields))
  use encoded_revision <- result.try(encode_stable_revision(
    revision,
    context,
    "message.revision",
  ))
  use changeset <- result.try(encode_changes(
    changes,
    context,
    ChangeContext(originator, Some(revision), Message),
  ))
  let fields = [
    #("revision", json.int(encoded_revision)),
    #("originatorId", json.string(fluid_ids.session_id_to_string(originator))),
    #("changeset", changeset),
    #("version", json.int(7)),
  ]
  let fields = case custom_metadata {
    Some(metadata) ->
      case metadata_has_value(metadata) {
        True ->
          list.append(fields, [
            #("customMetadata", custom_metadata_to_json(metadata)),
          ])
        False -> fields
      }
    _ -> fields
  }
  Ok(json.object(list.append(fields, extra_fields)))
}

/// Decode one ModularChange V5 payload.
pub fn decode_modular(
  encoded: Json,
  context: DecodeContext,
  change_context: ChangeContext,
) -> Result(change.Changeset, TreeError) {
  use value <- result.try(json_value(encoded, "modular"))
  decode_modular_value(value, context, change_context, None, "modular")
}

/// Decode one ModularChange V5 payload with its active stored schema.
pub fn decode_modular_with_schema(
  encoded: Json,
  context: DecodeContext,
  change_context: ChangeContext,
  stored: schema.StoredSchema,
) -> Result(change.Changeset, TreeError) {
  use value <- result.try(json_value(encoded, "modular"))
  decode_modular_value(value, context, change_context, Some(stored), "modular")
}

/// Encode one ModularChange V5 payload.
pub fn encode_modular(
  value: change.Changeset,
  context: EncodeContext,
  change_context: ChangeContext,
) -> Result(Json, TreeError) {
  encode_modular_value(value, context, change_context, "modular")
  |> result.map(json_ot.to_json)
}

/// Decode an ordered SharedTreeChange V5 list.
pub fn decode_changes(
  encoded: Json,
  context: DecodeContext,
  change_context: ChangeContext,
) -> Result(List(TreeChange), TreeError) {
  use value <- result.try(json_value(encoded, "changes"))
  decode_changes_value(value, context, change_context, None, "changes")
}

/// Decode SharedTreeChange V5 content with its active stored schema.
pub fn decode_changes_with_schema(
  encoded: Json,
  context: DecodeContext,
  change_context: ChangeContext,
  stored: schema.StoredSchema,
) -> Result(List(TreeChange), TreeError) {
  use value <- result.try(json_value(encoded, "changes"))
  decode_changes_value(value, context, change_context, Some(stored), "changes")
}

/// Encode an ordered SharedTreeChange V5 list.
pub fn encode_changes(
  changes: List(TreeChange),
  context: EncodeContext,
  change_context: ChangeContext,
) -> Result(Json, TreeError) {
  encode_changes_value(changes, context, change_context, "changes")
  |> result.map(json_ot.to_json)
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

fn decode_changes_value(
  value: JsonValue,
  context: DecodeContext,
  change_context: ChangeContext,
  stored: Option(schema.StoredSchema),
  location: String,
) -> Result(List(TreeChange), TreeError) {
  use values <- result.try(array(value, location))
  index_try_map(values, fn(value, index) {
    let location = location <> "[" <> int.to_string(index) <> "]"
    use members <- result.try(object(value, location))
    case members {
      [#("data", data)] ->
        decode_modular_value(
          data,
          context,
          change_context,
          stored,
          location <> ".data",
        )
        |> result.map(DataChange)
      [#("schema", schema_change)] ->
        decode_schema_change(schema_change, location <> ".schema")
      _ ->
        Error(CorruptData(
          location,
          "change must contain exactly one data or schema member",
        ))
    }
  })
}

fn encode_changes_value(
  changes: List(TreeChange),
  context: EncodeContext,
  change_context: ChangeContext,
  location: String,
) -> Result(JsonValue, TreeError) {
  use values <- result.try(
    index_try_map(changes, fn(value, index) {
      let location = location <> "[" <> int.to_string(index) <> "]"
      case value {
        DataChange(change) ->
          encode_modular_value(change, context, change_context, location)
          |> result.map(fn(value) { VObject([#("data", value)]) })
        SchemaChange(before, after) -> {
          use before <- result.try(encode_schema(before))
          use before <- result.try(json_value(before, location <> ".schema.old"))
          use after <- result.try(encode_schema(after))
          use after <- result.try(json_value(after, location <> ".schema.new"))
          Ok(
            VObject([#("schema", VObject([#("old", before), #("new", after)]))]),
          )
        }
      }
    }),
  )
  Ok(VArray(values))
}

fn decode_schema_change(
  value: JsonValue,
  location: String,
) -> Result(TreeChange, TreeError) {
  use members <- result.try(object(value, location))
  use _ <- result.try(exact_keys(members, ["old", "new"], location))
  use old <- result.try(required(members, "old", location <> ".old"))
  use new <- result.try(required(members, "new", location <> ".new"))
  use old <- result.try(
    decode_schema(json.to_string(json_ot.to_json(old)))
    |> result.map_error(fn(error) { at_location(error, location <> ".old") }),
  )
  use new <- result.try(
    decode_schema(json.to_string(json_ot.to_json(new)))
    |> result.map_error(fn(error) { at_location(error, location <> ".new") }),
  )
  Ok(SchemaChange(old, new))
}

fn decode_modular_value(
  value: JsonValue,
  context: DecodeContext,
  change_context: ChangeContext,
  stored: Option(schema.StoredSchema),
  location: String,
) -> Result(change.Changeset, TreeError) {
  use members <- result.try(object(value, location))
  use _ <- result.try(only_keys(
    members,
    [
      "maxId", "changes", "revisions", "builds", "refreshers", "violations",
      "noChangeConstraint",
    ],
    location,
  ))
  use _ <- result.try(case optional(members, "noChangeConstraint") {
    None -> Ok(Nil)
    Some(_) ->
      Error(types.UnsupportedFeature(
        location <> ".noChangeConstraint",
        "no-change constraints",
      ))
  })
  use _ <- result.try(case optional(members, "violations") {
    None -> Ok(Nil)
    Some(value) -> {
      use count <- result.try(nonnegative_integer(
        value,
        location <> ".violations",
      ))
      case count {
        0 -> Ok(Nil)
        _ ->
          Error(types.UnsupportedFeature(
            location <> ".violations",
            "constraint violations",
          ))
      }
    }
  })
  use max_id <- result.try(case optional(members, "maxId") {
    None -> Ok(-1)
    Some(value) -> nonnegative_integer(value, location <> ".maxId")
  })
  use revisions <- result.try(decode_revision_infos(
    optional(members, "revisions"),
    context,
    change_context,
    location <> ".revisions",
  ))
  use changes <- result.try(required(members, "changes", location <> ".changes"))
  let state = DecodeChangeState(max_id + 1, [], [])
  use #(fields, state) <- result.try(decode_field_map(
    changes,
    None,
    state,
    context,
    change_context,
    location <> ".changes",
  ))
  use builds <- result.try(case optional(members, "builds") {
    None -> Ok([])
    Some(value) ->
      decode_builds(
        value,
        context,
        change_context,
        stored,
        location <> ".builds",
      )
  })
  use refreshers <- result.try(case optional(members, "refreshers") {
    None -> Ok([])
    Some(value) ->
      decode_builds(
        value,
        context,
        change_context,
        stored,
        location <> ".refreshers",
      )
  })
  let DecodeChangeState(_, nodes, parents) = state
  let data =
    change.ChangeData(
      max_local_id: max_id,
      revisions: revisions,
      fields: fields,
      nodes: list.reverse(nodes),
      parents: list.reverse(parents),
      aliases: [],
      builds: builds,
      destroys: [],
      refreshers: refreshers,
    )
  let DecodeContext(compressor: compressor, ..) = context
  use order <- result.try(identity_order(
    data_revisions(data),
    compressor,
    location <> ".revisions",
  ))
  change.from_data(data, order)
}

fn decode_revision_infos(
  encoded: Option(JsonValue),
  context: DecodeContext,
  change_context: ChangeContext,
  location: String,
) -> Result(List(change.RevisionInfo), TreeError) {
  let ChangeContext(originator:, revision: tagged, ..) = change_context
  case encoded {
    None ->
      Ok(case tagged {
        Some(revision) -> [change.RevisionInfo(revision, None)]
        None -> []
      })
    Some(value) -> {
      use values <- result.try(array(value, location))
      use revisions <- result.try(
        index_try_map(values, fn(value, index) {
          let location = location <> "[" <> int.to_string(index) <> "]"
          use members <- result.try(object(value, location))
          use _ <- result.try(only_keys(
            members,
            ["revision", "rollbackOf"],
            location,
          ))
          use revision <- result.try(required(
            members,
            "revision",
            location <> ".revision",
          ))
          use revision <- result.try(decode_revision_value(
            revision,
            originator,
            context,
            False,
            location <> ".revision",
          ))
          use revision <- result.try(authored_revision(
            revision,
            location <> ".revision",
          ))
          use rollback <- result.try(case optional(members, "rollbackOf") {
            None -> Ok(None)
            Some(value) -> {
              use revision <- result.try(decode_revision_value(
                value,
                originator,
                context,
                False,
                location <> ".rollbackOf",
              ))
              use revision <- result.try(authored_revision(
                revision,
                location <> ".rollbackOf",
              ))
              Ok(Some(revision))
            }
          })
          Ok(change.RevisionInfo(revision, rollback))
        }),
      )
      case tagged {
        None -> Ok(revisions)
        Some(tagged) ->
          case revisions {
            [change.RevisionInfo(revision, None)] if revision == tagged ->
              Ok(revisions)
            _ ->
              Error(CorruptData(
                location,
                "tagged change revision metadata does not match its commit",
              ))
          }
      }
    }
  }
}

fn decode_field_map(
  value: JsonValue,
  parent: Option(types.AtomId),
  state: DecodeChangeState,
  context: DecodeContext,
  change_context: ChangeContext,
  location: String,
) -> Result(
  #(List(#(String, change.FieldChange)), DecodeChangeState),
  TreeError,
) {
  use values <- result.try(array(value, location))
  decode_field_entries(
    values,
    parent,
    state,
    context,
    change_context,
    [],
    [],
    location,
  )
}

fn decode_field_entries(
  values: List(JsonValue),
  parent: Option(types.AtomId),
  state: DecodeChangeState,
  context: DecodeContext,
  change_context: ChangeContext,
  fields: List(#(String, change.FieldChange)),
  seen: List(String),
  location: String,
) -> Result(
  #(List(#(String, change.FieldChange)), DecodeChangeState),
  TreeError,
) {
  case values {
    [] -> Ok(#(list.reverse(fields), state))
    [value, ..rest] -> {
      let entry_location =
        location <> "[" <> int.to_string(list.length(fields)) <> "]"
      use members <- result.try(object(value, entry_location))
      use _ <- result.try(exact_keys(
        members,
        ["fieldKey", "fieldKind", "change"],
        entry_location,
      ))
      use key <- result.try(required(
        members,
        "fieldKey",
        entry_location <> ".fieldKey",
      ))
      use key <- result.try(text(key, entry_location <> ".fieldKey"))
      use _ <- result.try(case list.contains(seen, key) {
        True -> Error(CorruptData(entry_location, "duplicate field change"))
        False -> Ok(Nil)
      })
      use kind <- result.try(required(
        members,
        "fieldKind",
        entry_location <> ".fieldKind",
      ))
      use kind <- result.try(text(kind, entry_location <> ".fieldKind"))
      use encoded <- result.try(required(
        members,
        "change",
        entry_location <> ".change",
      ))
      use #(field, state) <- result.try(case kind {
        "Value" ->
          decode_optional_field(
            encoded,
            parent,
            key,
            state,
            context,
            change_context,
            entry_location <> ".change",
          )
          |> result.map(fn(value) { #(change.ValueField(value.0), value.1) })
        "Optional" ->
          decode_optional_field(
            encoded,
            parent,
            key,
            state,
            context,
            change_context,
            entry_location <> ".change",
          )
          |> result.map(fn(value) { #(change.OptionalField(value.0), value.1) })
        "ModularEditBuilder.Generic" ->
          decode_generic_field(
            encoded,
            parent,
            key,
            state,
            context,
            change_context,
            entry_location <> ".change",
          )
          |> result.map(fn(value) { #(change.GenericField(value.0), value.1) })
        other ->
          Error(types.UnsupportedFeature(
            entry_location <> ".fieldKind",
            "field kind " <> other,
          ))
      })
      decode_field_entries(
        rest,
        parent,
        state,
        context,
        change_context,
        [#(key, field), ..fields],
        [key, ..seen],
        location,
      )
    }
  }
}

fn decode_generic_field(
  value: JsonValue,
  parent: Option(types.AtomId),
  field: String,
  state: DecodeChangeState,
  context: DecodeContext,
  change_context: ChangeContext,
  location: String,
) -> Result(#(List(#(Int, types.AtomId)), DecodeChangeState), TreeError) {
  use values <- result.try(array(value, location))
  decode_generic_entries(
    values,
    parent,
    field,
    state,
    context,
    change_context,
    [],
    location,
  )
}

fn decode_generic_entries(
  values: List(JsonValue),
  parent: Option(types.AtomId),
  field: String,
  state: DecodeChangeState,
  context: DecodeContext,
  change_context: ChangeContext,
  children: List(#(Int, types.AtomId)),
  location: String,
) -> Result(#(List(#(Int, types.AtomId)), DecodeChangeState), TreeError) {
  case values {
    [] -> Ok(#(list.reverse(children), state))
    [value, ..rest] -> {
      use pair <- result.try(array(value, location))
      use #(index_value, node_value) <- result.try(two(pair, location))
      use index <- result.try(nonnegative_integer(index_value, location))
      use #(node_id, state) <- result.try(decode_node_change(
        node_value,
        parent,
        field,
        state,
        context,
        change_context,
        location,
      ))
      decode_generic_entries(
        rest,
        parent,
        field,
        state,
        context,
        change_context,
        [#(index, node_id), ..children],
        location,
      )
    }
  }
}

fn decode_optional_field(
  value: JsonValue,
  parent: Option(types.AtomId),
  field: String,
  state: DecodeChangeState,
  context: DecodeContext,
  change_context: ChangeContext,
  location: String,
) -> Result(#(optional_field.FieldChange, DecodeChangeState), TreeError) {
  use members <- result.try(object(value, location))
  use _ <- result.try(only_keys(members, ["m", "r", "c"], location))
  use moves <- result.try(case optional(members, "m") {
    None -> Ok([])
    Some(value) ->
      decode_pairs(value, location <> ".m", fn(value, location) {
        decode_atom(value, context, change_context, location)
      })
  })
  use replacement <- result.try(case optional(members, "r") {
    None -> Ok(None)
    Some(value) ->
      decode_replacement(value, context, change_context, location <> ".r")
      |> result.map(Some)
  })
  use #(children, state) <- result.try(case optional(members, "c") {
    None -> Ok(#([], state))
    Some(value) ->
      decode_optional_children(
        value,
        parent,
        field,
        state,
        context,
        change_context,
        location <> ".c",
      )
  })
  Ok(#(optional_field.FieldChange(moves, children, replacement), state))
}

fn decode_optional_children(
  value: JsonValue,
  parent: Option(types.AtomId),
  field: String,
  state: DecodeChangeState,
  context: DecodeContext,
  change_context: ChangeContext,
  location: String,
) -> Result(
  #(List(#(optional_field.RegisterId, types.AtomId)), DecodeChangeState),
  TreeError,
) {
  use values <- result.try(array(value, location))
  decode_optional_child_entries(
    values,
    parent,
    field,
    state,
    context,
    change_context,
    [],
    location,
  )
}

fn decode_optional_child_entries(
  values: List(JsonValue),
  parent: Option(types.AtomId),
  field: String,
  state: DecodeChangeState,
  context: DecodeContext,
  change_context: ChangeContext,
  children: List(#(optional_field.RegisterId, types.AtomId)),
  location: String,
) -> Result(
  #(List(#(optional_field.RegisterId, types.AtomId)), DecodeChangeState),
  TreeError,
) {
  case values {
    [] -> Ok(#(list.reverse(children), state))
    [value, ..rest] -> {
      use pair <- result.try(array(value, location))
      use #(register, node) <- result.try(two(pair, location))
      use register <- result.try(decode_register(
        register,
        context,
        change_context,
        location,
      ))
      use #(node, state) <- result.try(decode_node_change(
        node,
        parent,
        field,
        state,
        context,
        change_context,
        location,
      ))
      decode_optional_child_entries(
        rest,
        parent,
        field,
        state,
        context,
        change_context,
        [#(register, node), ..children],
        location,
      )
    }
  }
}

fn decode_node_change(
  value: JsonValue,
  parent: Option(types.AtomId),
  field: String,
  state: DecodeChangeState,
  context: DecodeContext,
  change_context: ChangeContext,
  location: String,
) -> Result(#(types.AtomId, DecodeChangeState), TreeError) {
  let DecodeChangeState(next_id, nodes, parents) = state
  use _ <- result.try(case next_id <= max_safe_integer {
    True -> Ok(Nil)
    False -> Error(CorruptData(location, "node change ID is out of range"))
  })
  let ChangeContext(revision:, ..) = change_context
  let id = types.AtomId(revision, next_id)
  use members <- result.try(object(value, location))
  use _ <- result.try(only_keys(
    members,
    ["fieldChanges", "nodeExistsConstraint"],
    location,
  ))
  use _ <- result.try(case optional(members, "nodeExistsConstraint") {
    None -> Ok(Nil)
    Some(_) ->
      Error(types.UnsupportedFeature(
        location <> ".nodeExistsConstraint",
        "node existence constraints",
      ))
  })
  let state = DecodeChangeState(next_id + 1, nodes, parents)
  use #(fields, state) <- result.try(case optional(members, "fieldChanges") {
    None -> Ok(#([], state))
    Some(value) ->
      decode_field_map(
        value,
        Some(id),
        state,
        context,
        change_context,
        location <> ".fieldChanges",
      )
  })
  let DecodeChangeState(next_id, nodes, parents) = state
  Ok(#(
    id,
    DecodeChangeState(next_id, [#(id, change.NodeChange(fields)), ..nodes], [
      #(id, change.ParentField(parent, field)),
      ..parents
    ]),
  ))
}

fn decode_replacement(
  value: JsonValue,
  context: DecodeContext,
  change_context: ChangeContext,
  location: String,
) -> Result(optional_field.Replacement, TreeError) {
  use members <- result.try(object(value, location))
  use _ <- result.try(only_keys(members, ["e", "d", "s"], location))
  use empty <- result.try(required(members, "e", location <> ".e"))
  use empty <- result.try(boolean(empty, location <> ".e"))
  use detach <- result.try(required(members, "d", location <> ".d"))
  use detach <- result.try(decode_atom(
    detach,
    context,
    change_context,
    location <> ".d",
  ))
  use source <- result.try(case optional(members, "s") {
    None -> Ok(None)
    Some(value) ->
      decode_register(value, context, change_context, location <> ".s")
      |> result.map(Some)
  })
  Ok(optional_field.Replacement(empty, source, detach))
}

fn decode_register(
  value: JsonValue,
  context: DecodeContext,
  change_context: ChangeContext,
  location: String,
) -> Result(optional_field.RegisterId, TreeError) {
  case value {
    VNull -> Ok(optional_field.Active)
    _ ->
      decode_atom(value, context, change_context, location)
      |> result.map(optional_field.Detached)
  }
}

fn decode_atom(
  value: JsonValue,
  context: DecodeContext,
  change_context: ChangeContext,
  location: String,
) -> Result(types.AtomId, TreeError) {
  let ChangeContext(originator:, revision: inherited, ..) = change_context
  case value {
    VNumber(NInt(local_id)) -> {
      use local_id <- result.try(safe_local_id(local_id, location))
      Ok(types.AtomId(inherited, local_id))
    }
    VArray([local_id, encoded_revision]) -> {
      use local_id <- result.try(nonnegative_integer(
        local_id,
        location <> "[0]",
      ))
      use revision <- result.try(decode_revision_value(
        encoded_revision,
        originator,
        context,
        False,
        location <> "[1]",
      ))
      use revision <- result.try(authored_revision(revision, location <> "[1]"))
      Ok(types.AtomId(Some(revision), local_id))
    }
    _ ->
      Error(CorruptData(location, "atom must be an integer or a revision pair"))
  }
}

fn decode_builds(
  value: JsonValue,
  context: DecodeContext,
  change_context: ChangeContext,
  stored: Option(schema.StoredSchema),
  location: String,
) -> Result(List(forest.Build), TreeError) {
  use members <- result.try(object(value, location))
  use _ <- result.try(exact_keys(members, ["builds", "trees"], location))
  use trees <- result.try(required(members, "trees", location <> ".trees"))
  use trees <- result.try(
    field_batch.decode_with_schema(json_ot.to_json(trees), stored)
    |> result.map_error(fn(error) { at_location(error, location <> ".trees") }),
  )
  use groups <- result.try(required(members, "builds", location <> ".builds"))
  use groups <- result.try(array(groups, location <> ".builds"))
  use builds <- result.try(
    index_try_map(groups, fn(group, group_index) {
      let group_location =
        location <> ".builds[" <> int.to_string(group_index) <> "]"
      use group <- result.try(array(group, group_location))
      use #(entries, revision) <- result.try(case group {
        [entries] -> Ok(#(entries, change_context.revision))
        [entries, revision] -> {
          use revision <- result.try(decode_revision_value(
            revision,
            change_context.originator,
            context,
            False,
            group_location <> "[1]",
          ))
          use revision <- result.try(authored_revision(
            revision,
            group_location <> "[1]",
          ))
          Ok(#(entries, Some(revision)))
        }
        _ ->
          Error(CorruptData(
            group_location,
            "build group must have one or two items",
          ))
      })
      use entries <- result.try(array(entries, group_location <> "[0]"))
      index_try_map(entries, fn(entry, entry_index) {
        let entry_location =
          group_location <> "[0][" <> int.to_string(entry_index) <> "]"
        use entry <- result.try(array(entry, entry_location))
        use #(local_id, tree_index) <- result.try(two(entry, entry_location))
        use local_id <- result.try(nonnegative_integer(
          local_id,
          entry_location <> "[0]",
        ))
        use tree_index <- result.try(nonnegative_integer(
          tree_index,
          entry_location <> "[1]",
        ))
        use chunk <- result.try(
          at(trees, tree_index, entry_location <> "[1]")
          |> result.map_error(fn(_) {
            CorruptData(entry_location <> "[1]", "tree index is out of bounds")
          }),
        )
        Ok(forest.Build(types.AtomId(revision, local_id), chunk))
      })
    }),
  )
  Ok(list.flatten(builds))
}

fn encode_modular_value(
  value: change.Changeset,
  context: EncodeContext,
  change_context: ChangeContext,
  location: String,
) -> Result(JsonValue, TreeError) {
  let data = change.to_data(value)
  use _ <- result.try(case data.destroys {
    [] -> Ok(Nil)
    _ ->
      Error(types.UnsupportedFeature(
        location <> ".destroys",
        "rollback-only destroys",
      ))
  })
  use changes <- result.try(encode_field_map(
    data.fields,
    data,
    context,
    change_context,
    location <> ".changes",
  ))
  use revisions <- result.try(encode_revision_infos(
    data.revisions,
    context,
    change_context,
    location,
  ))
  use builds <- result.try(encode_builds(
    data.builds,
    context,
    change_context,
    location <> ".builds",
  ))
  use refreshers <- result.try(encode_builds(
    data.refreshers,
    context,
    change_context,
    location <> ".refreshers",
  ))
  let members = [#("changes", changes)]
  let members = case data.max_local_id {
    -1 -> members
    max_id -> [#("maxId", VNumber(NInt(max_id))), ..members]
  }
  let members = case revisions {
    None -> members
    Some(value) -> [#("revisions", value), ..members]
  }
  let members = case builds {
    None -> members
    Some(value) -> [#("builds", value), ..members]
  }
  let members = case refreshers {
    None -> members
    Some(value) -> [#("refreshers", value), ..members]
  }
  Ok(VObject(members))
}

fn encode_revision_infos(
  revisions: List(change.RevisionInfo),
  context: EncodeContext,
  change_context: ChangeContext,
  location: String,
) -> Result(Option(JsonValue), TreeError) {
  case change_context.revision {
    Some(tagged) ->
      case revisions {
        [change.RevisionInfo(revision, None)] if revision == tagged -> Ok(None)
        _ ->
          Error(CorruptData(
            location <> ".revisions",
            "tagged change must contain only its commit revision",
          ))
      }
    None -> {
      use values <- result.try(
        index_try_map(revisions, fn(info, index) {
          let location =
            location <> ".revisions[" <> int.to_string(index) <> "]"
          use revision <- result.try(encode_revision_value(
            StableRevision(info.revision),
            context,
            False,
            location <> ".revision",
          ))
          use rollback <- result.try(case info.rollback_of {
            None -> Ok([])
            Some(rollback) -> {
              use rollback <- result.try(encode_revision_value(
                StableRevision(rollback),
                context,
                False,
                location <> ".rollbackOf",
              ))
              Ok([#("rollbackOf", rollback)])
            }
          })
          Ok(VObject([#("revision", revision), ..rollback]))
        }),
      )
      Ok(Some(VArray(values)))
    }
  }
}

fn encode_field_map(
  fields: List(#(String, change.FieldChange)),
  data: change.ChangeData,
  context: EncodeContext,
  change_context: ChangeContext,
  location: String,
) -> Result(JsonValue, TreeError) {
  use values <- result.try(
    index_try_map(fields, fn(entry, index) {
      let location = location <> "[" <> int.to_string(index) <> "]"
      use #(kind, encoded) <- result.try(case entry.1 {
        change.ValueField(value) ->
          encode_optional_field(
            value,
            data,
            context,
            change_context,
            location <> ".change",
          )
          |> result.map(fn(value) { #("Value", value) })
        change.OptionalField(value) ->
          encode_optional_field(
            value,
            data,
            context,
            change_context,
            location <> ".change",
          )
          |> result.map(fn(value) { #("Optional", value) })
        change.GenericField(children) ->
          encode_generic_field(
            children,
            data,
            context,
            change_context,
            location <> ".change",
          )
          |> result.map(fn(value) { #("ModularEditBuilder.Generic", value) })
      })
      Ok(
        VObject([
          #("fieldKey", VString(entry.0)),
          #("fieldKind", VString(kind)),
          #("change", encoded),
        ]),
      )
    }),
  )
  Ok(VArray(values))
}

fn encode_generic_field(
  children: List(#(Int, types.AtomId)),
  data: change.ChangeData,
  context: EncodeContext,
  change_context: ChangeContext,
  location: String,
) -> Result(JsonValue, TreeError) {
  use values <- result.try(
    index_try_map(children, fn(child, index) {
      let location = location <> "[" <> int.to_string(index) <> "]"
      use node <- result.try(encode_node_change(
        child.1,
        data,
        context,
        change_context,
        [],
        location <> "[1]",
      ))
      Ok(VArray([VNumber(NInt(child.0)), node]))
    }),
  )
  Ok(VArray(values))
}

fn encode_optional_field(
  value: optional_field.FieldChange,
  data: change.ChangeData,
  context: EncodeContext,
  change_context: ChangeContext,
  location: String,
) -> Result(JsonValue, TreeError) {
  use moves <- result.try(
    index_try_map(value.moves, fn(move, index) {
      let location = location <> ".m[" <> int.to_string(index) <> "]"
      use source <- result.try(encode_atom(
        move.0,
        context,
        change_context,
        location <> "[0]",
      ))
      use destination <- result.try(encode_atom(
        move.1,
        context,
        change_context,
        location <> "[1]",
      ))
      Ok(VArray([source, destination]))
    }),
  )
  use children <- result.try(
    index_try_map(value.child_changes, fn(child, index) {
      let location = location <> ".c[" <> int.to_string(index) <> "]"
      use register <- result.try(encode_register(
        child.0,
        context,
        change_context,
        location <> "[0]",
      ))
      use node <- result.try(encode_node_change(
        child.1,
        data,
        context,
        change_context,
        [],
        location <> "[1]",
      ))
      Ok(VArray([register, node]))
    }),
  )
  use replacement <- result.try(case value.replacement {
    None -> Ok(None)
    Some(replacement) -> {
      use detach <- result.try(encode_atom(
        replacement.detach_id,
        context,
        change_context,
        location <> ".r.d",
      ))
      use source <- result.try(case replacement.source {
        None -> Ok([])
        Some(source) -> {
          use source <- result.try(encode_register(
            source,
            context,
            change_context,
            location <> ".r.s",
          ))
          Ok([#("s", source)])
        }
      })
      Ok(
        Some(
          VObject([
            #("e", VBool(replacement.was_empty)),
            #("d", detach),
            ..source
          ]),
        ),
      )
    }
  })
  let members = case moves {
    [] -> []
    _ -> [#("m", VArray(moves))]
  }
  let members = case replacement {
    None -> members
    Some(value) -> list.append(members, [#("r", value)])
  }
  let members = case children {
    [] -> members
    _ -> list.append(members, [#("c", VArray(children))])
  }
  Ok(VObject(members))
}

fn encode_node_change(
  id: types.AtomId,
  data: change.ChangeData,
  context: EncodeContext,
  change_context: ChangeContext,
  visited: List(types.AtomId),
  location: String,
) -> Result(JsonValue, TreeError) {
  use _ <- result.try(case list.contains(visited, id) {
    True -> Error(CorruptData(location, "node alias cycle"))
    False -> Ok(Nil)
  })
  case list.key_find(data.aliases, id) {
    Ok(next) ->
      encode_node_change(
        next,
        data,
        context,
        change_context,
        [id, ..visited],
        location,
      )
    Error(Nil) -> {
      use node <- result.try(
        list.key_find(data.nodes, id)
        |> result.map_error(fn(_) {
          CorruptData(location, "child node change is missing")
        }),
      )
      case node.fields {
        [] -> Ok(VObject([]))
        fields -> {
          use fields <- result.try(encode_field_map(
            fields,
            data,
            context,
            change_context,
            location <> ".fieldChanges",
          ))
          Ok(VObject([#("fieldChanges", fields)]))
        }
      }
    }
  }
}

fn encode_register(
  value: optional_field.RegisterId,
  context: EncodeContext,
  change_context: ChangeContext,
  location: String,
) -> Result(JsonValue, TreeError) {
  case value {
    optional_field.Active -> Ok(VNull)
    optional_field.Detached(id) ->
      encode_atom(id, context, change_context, location)
  }
}

fn encode_atom(
  id: types.AtomId,
  context: EncodeContext,
  change_context: ChangeContext,
  location: String,
) -> Result(JsonValue, TreeError) {
  use local_id <- result.try(safe_local_id(id.local_id, location))
  case id.revision {
    None -> Ok(VNumber(NInt(local_id)))
    Some(revision) if Some(revision) == change_context.revision ->
      Ok(VNumber(NInt(local_id)))
    Some(revision) -> {
      use revision <- result.try(encode_revision_value(
        StableRevision(revision),
        context,
        False,
        location <> "[1]",
      ))
      Ok(VArray([VNumber(NInt(local_id)), revision]))
    }
  }
}

fn encode_builds(
  builds: List(forest.Build),
  context: EncodeContext,
  change_context: ChangeContext,
  location: String,
) -> Result(Option(JsonValue), TreeError) {
  case builds {
    [] -> Ok(None)
    _ -> {
      use trees <- result.try(
        field_batch.encode(list.map(builds, fn(build) { build.trees })),
      )
      use trees <- result.try(json_value(trees, location <> ".trees"))
      use entries <- result.try(
        index_try_map(builds, fn(build, index) {
          use local_id <- result.try(safe_local_id(build.id.local_id, location))
          use revision <- result.try(case build.id.revision {
            None -> Ok(None)
            Some(revision) if Some(revision) == change_context.revision ->
              Ok(None)
            Some(revision) ->
              encode_revision_value(
                StableRevision(revision),
                context,
                False,
                location,
              )
              |> result.map(Some)
          })
          Ok(#(
            revision,
            VArray([VNumber(NInt(local_id)), VNumber(NInt(index))]),
          ))
        }),
      )
      let groups =
        list.fold(entries, [], fn(groups, entry) {
          case groups {
            [#(revision, values), ..rest] if revision == entry.0 -> [
              #(revision, [entry.1, ..values]),
              ..rest
            ]
            _ -> [#(entry.0, [entry.1]), ..groups]
          }
        })
        |> list.reverse
      let groups =
        list.map(groups, fn(group) {
          let values = VArray(list.reverse(group.1))
          case group.0 {
            None -> VArray([values])
            Some(revision) -> VArray([values, revision])
          }
        })
      Ok(
        Some(
          VObject([
            #("builds", VArray(groups)),
            #("trees", trees),
          ]),
        ),
      )
    }
  }
}

fn encode_revision_value(
  revision: Revision,
  context: EncodeContext,
  allow_root: Bool,
  location: String,
) -> Result(JsonValue, TreeError) {
  case revision {
    RootRevision ->
      case allow_root {
        True -> Ok(VString("root"))
        False ->
          Error(CorruptData(location, "root is not an authored revision"))
      }
    StableRevision(revision) ->
      encode_stable_revision(revision, context, location)
      |> result.map(fn(value) { VNumber(NInt(value)) })
  }
}

fn decode_revision_value(
  value: JsonValue,
  originator: fluid_ids.SessionId,
  context: DecodeContext,
  allow_root: Bool,
  location: String,
) -> Result(Revision, TreeError) {
  case value {
    VString("root") ->
      case allow_root {
        True -> Ok(RootRevision)
        False ->
          Error(CorruptData(location, "root is not an authored revision"))
      }
    VNumber(NInt(value)) ->
      decode_stable_revision(value, originator, context, location)
      |> result.map(StableRevision)
    _ -> Error(CorruptData(location, "invalid encoded revision"))
  }
}

fn authored_revision(
  revision: Revision,
  location: String,
) -> Result(fluid_ids.StableId, TreeError) {
  case revision {
    StableRevision(revision) -> Ok(revision)
    RootRevision ->
      Error(CorruptData(location, "root is not an authored revision"))
  }
}

fn decode_pairs(
  value: JsonValue,
  location: String,
  decoder: fn(JsonValue, String) -> Result(value, TreeError),
) -> Result(List(#(value, value)), TreeError) {
  use values <- result.try(array(value, location))
  index_try_map(values, fn(value, index) {
    let location = location <> "[" <> int.to_string(index) <> "]"
    use pair <- result.try(array(value, location))
    use #(first, second) <- result.try(two(pair, location))
    use first <- result.try(decoder(first, location <> "[0]"))
    use second <- result.try(decoder(second, location <> "[1]"))
    Ok(#(first, second))
  })
}

fn decode_custom_metadata(
  value: JsonValue,
  location: String,
) -> Result(Option(CustomMetadata), TreeError) {
  use metadata <- result.try(decode_custom_metadata_node(value, location))
  Ok(case metadata_has_value(metadata) {
    True -> Some(metadata)
    False -> None
  })
}

fn decode_custom_metadata_node(
  value: JsonValue,
  location: String,
) -> Result(CustomMetadata, TreeError) {
  use members <- result.try(object(value, location))
  use _ <- result.try(only_keys(members, ["m", "c"], location))
  let metadata =
    optional(members, "m")
    |> option.map(json_ot.to_json)
  use children <- result.try(case optional(members, "c") {
    None -> Ok([])
    Some(value) -> {
      use values <- result.try(array(value, location <> ".c"))
      index_try_map(values, fn(value, index) {
        decode_custom_metadata_node(
          value,
          location <> ".c[" <> int.to_string(index) <> "]",
        )
      })
    }
  })
  Ok(CustomMetadata(metadata, children))
}

/// Decode recursive commit metadata without changing compressor state.
pub fn custom_metadata_from_json(
  value: Json,
  location: String,
) -> Result(Option(CustomMetadata), TreeError) {
  use value <- result.try(json_value(value, location))
  decode_custom_metadata(value, location)
}

/// Encode recursive commit metadata.
pub fn custom_metadata_to_json(value: CustomMetadata) -> Json {
  let CustomMetadata(metadata, children) = value
  let fields = case metadata {
    None -> []
    Some(value) -> [#("m", value)]
  }
  let fields = case children {
    [] -> fields
    _ ->
      list.append(fields, [
        #("c", json.array(children, custom_metadata_to_json)),
      ])
  }
  json.object(fields)
}

fn metadata_has_value(value: CustomMetadata) -> Bool {
  let CustomMetadata(metadata, children) = value
  option.is_some(metadata) || list.any(children, metadata_has_value)
}

fn validate_extra_fields(
  fields: List(#(String, Json)),
) -> Result(Nil, TreeError) {
  use _ <- result.try(
    list.try_each(fields, fn(field) {
      case
        list.contains(
          ["revision", "originatorId", "changeset", "version", "customMetadata"],
          field.0,
        )
      {
        True ->
          Error(CorruptData(
            "message." <> field.0,
            "extra field collides with a reserved property",
          ))
        False -> Ok(Nil)
      }
    }),
  )
  case has_duplicate_keys(list.map(fields, fn(field) { field.0 })) {
    True -> Error(CorruptData("message", "duplicate extra field"))
    False -> Ok(Nil)
  }
}

fn data_revisions(data: change.ChangeData) -> List(fluid_ids.StableId) {
  let revisions =
    list.fold(data.revisions, [], fn(revisions, info) {
      let revisions = [info.revision, ..revisions]
      case info.rollback_of {
        None -> revisions
        Some(revision) -> [revision, ..revisions]
      }
    })
  let revisions = collect_field_revisions(data.fields, revisions)
  let revisions =
    list.fold(data.nodes, revisions, fn(revisions, entry) {
      collect_field_revisions(
        entry.1.fields,
        collect_atom_revision(entry.0, revisions),
      )
    })
  let revisions =
    list.fold(data.parents, revisions, fn(revisions, entry) {
      let revisions = collect_atom_revision(entry.0, revisions)
      case entry.1.parent {
        None -> revisions
        Some(parent) -> collect_atom_revision(parent, revisions)
      }
    })
  let revisions =
    list.fold(data.aliases, revisions, fn(revisions, entry) {
      collect_atom_revision(entry.1, collect_atom_revision(entry.0, revisions))
    })
  let revisions =
    list.fold(data.builds, revisions, fn(revisions, build) {
      collect_atom_revision(build.id, revisions)
    })
  let revisions =
    list.fold(data.refreshers, revisions, fn(revisions, build) {
      collect_atom_revision(build.id, revisions)
    })
  list.reverse(revisions)
}

fn collect_field_revisions(
  fields: List(#(String, change.FieldChange)),
  revisions: List(fluid_ids.StableId),
) -> List(fluid_ids.StableId) {
  list.fold(fields, revisions, fn(revisions, entry) {
    case entry.1 {
      change.GenericField(children) ->
        list.fold(children, revisions, fn(revisions, child) {
          collect_atom_revision(child.1, revisions)
        })
      change.ValueField(field) | change.OptionalField(field) -> {
        let revisions =
          list.fold(field.moves, revisions, fn(revisions, move) {
            collect_atom_revision(
              move.1,
              collect_atom_revision(move.0, revisions),
            )
          })
        let revisions =
          list.fold(field.child_changes, revisions, fn(revisions, child) {
            let revisions = case child.0 {
              optional_field.Active -> revisions
              optional_field.Detached(id) ->
                collect_atom_revision(id, revisions)
            }
            collect_atom_revision(child.1, revisions)
          })
        case field.replacement {
          None -> revisions
          Some(replacement) -> {
            let revisions =
              collect_atom_revision(replacement.detach_id, revisions)
            case replacement.source {
              None | Some(optional_field.Active) -> revisions
              Some(optional_field.Detached(id)) ->
                collect_atom_revision(id, revisions)
            }
          }
        }
      }
    }
  })
}

fn collect_atom_revision(
  atom: types.AtomId,
  revisions: List(fluid_ids.StableId),
) -> List(fluid_ids.StableId) {
  case atom.revision {
    None -> revisions
    Some(revision) -> [revision, ..revisions]
  }
}

fn json_value(value: Json, location: String) -> Result(JsonValue, TreeError) {
  json_ot.parse_json(json.to_string(value))
  |> result.map_error(fn(_) { CorruptData(location, "value is not valid JSON") })
}

fn object(
  value: JsonValue,
  location: String,
) -> Result(List(#(String, JsonValue)), TreeError) {
  case value {
    VObject(members) -> Ok(members)
    _ -> Error(CorruptData(location, "expected an object"))
  }
}

fn array(
  value: JsonValue,
  location: String,
) -> Result(List(JsonValue), TreeError) {
  case value {
    VArray(values) -> Ok(values)
    _ -> Error(CorruptData(location, "expected an array"))
  }
}

fn text(value: JsonValue, location: String) -> Result(String, TreeError) {
  case value {
    VString(value) -> Ok(value)
    _ -> Error(CorruptData(location, "expected a string"))
  }
}

fn boolean(value: JsonValue, location: String) -> Result(Bool, TreeError) {
  case value {
    VBool(value) -> Ok(value)
    _ -> Error(CorruptData(location, "expected a boolean"))
  }
}

fn integer(value: JsonValue, location: String) -> Result(Int, TreeError) {
  case value {
    VNumber(NInt(value))
      if value >= min_safe_integer && value <= max_safe_integer
    -> Ok(value)
    _ -> Error(CorruptData(location, "expected a safe integer"))
  }
}

fn nonnegative_integer(
  value: JsonValue,
  location: String,
) -> Result(Int, TreeError) {
  use value <- result.try(integer(value, location))
  case value >= 0 {
    True -> Ok(value)
    False -> Error(CorruptData(location, "expected a nonnegative integer"))
  }
}

fn safe_local_id(value: Int, location: String) -> Result(Int, TreeError) {
  case value >= 0 && value <= max_safe_integer {
    True -> Ok(value)
    False -> Error(CorruptData(location, "invalid local identifier"))
  }
}

fn optional(
  members: List(#(String, JsonValue)),
  key: String,
) -> Option(JsonValue) {
  case list.key_find(members, key) {
    Ok(value) -> Some(value)
    Error(Nil) -> None
  }
}

fn required(
  members: List(#(String, JsonValue)),
  key: String,
  location: String,
) -> Result(JsonValue, TreeError) {
  case optional(members, key) {
    Some(value) -> Ok(value)
    None -> Error(CorruptData(location, "required property is missing"))
  }
}

fn only_keys(
  members: List(#(String, JsonValue)),
  keys: List(String),
  location: String,
) -> Result(Nil, TreeError) {
  list.try_each(members, fn(member) {
    case list.contains(keys, member.0) {
      True -> Ok(Nil)
      False -> Error(CorruptData(location, "unknown property " <> member.0))
    }
  })
}

fn exact_keys(
  members: List(#(String, JsonValue)),
  keys: List(String),
  location: String,
) -> Result(Nil, TreeError) {
  use _ <- result.try(only_keys(members, keys, location))
  case list.length(members) == list.length(keys) {
    True -> Ok(Nil)
    False -> Error(CorruptData(location, "required property is missing"))
  }
}

fn two(
  values: List(value),
  location: String,
) -> Result(#(value, value), TreeError) {
  case values {
    [first, second] -> Ok(#(first, second))
    _ -> Error(CorruptData(location, "expected a two-item tuple"))
  }
}

fn at(
  values: List(value),
  index: Int,
  location: String,
) -> Result(value, TreeError) {
  case index, values {
    0, [value, ..] -> Ok(value)
    index, [_, ..rest] if index > 0 -> at(rest, index - 1, location)
    _, _ -> Error(CorruptData(location, "index is out of bounds"))
  }
}

fn index_try_map(
  values: List(a),
  function: fn(a, Int) -> Result(b, error),
) -> Result(List(b), error) {
  index_try_map_loop(values, function, 0, [])
}

fn index_try_map_loop(
  values: List(a),
  function: fn(a, Int) -> Result(b, error),
  index: Int,
  mapped: List(b),
) -> Result(List(b), error) {
  case values {
    [] -> Ok(list.reverse(mapped))
    [value, ..rest] -> {
      use value <- result.try(function(value, index))
      index_try_map_loop(rest, function, index + 1, [value, ..mapped])
    }
  }
}

fn has_duplicate_keys(values: List(String)) -> Bool {
  case values {
    [] -> False
    [value, ..rest] -> list.contains(rest, value) || has_duplicate_keys(rest)
  }
}

fn at_location(error: TreeError, location: String) -> TreeError {
  case error {
    types.InvalidSchema(detail) -> CorruptData(location, detail)
    types.InvalidEdit(_, detail) -> CorruptData(location, detail)
    types.UnsupportedFormat(family, version) ->
      types.UnsupportedFormat(family, version)
    types.UnsupportedFeature(_, feature) ->
      types.UnsupportedFeature(location, feature)
    CorruptData(_, detail) -> CorruptData(location, detail)
    InvalidHistory(detail) -> CorruptData(location, detail)
  }
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
