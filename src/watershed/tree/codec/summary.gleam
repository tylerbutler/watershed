//// Fluid 3.1.0 SharedTree summary codecs.

import gleam/bit_array
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{type Order}
import gleam/result
import gleam/string
import watershed/fluid_ids
import watershed/json_ot.{
  type JsonValue, NInt, VArray, VNumber, VObject, VString,
}
import watershed/tree/codec
import watershed/tree/codec/field_batch
import watershed/tree/schema
import watershed/tree/types.{
  type TreeError, type TreeValue, CorruptData, UnsupportedFormat,
}
import watershed/wire/fluid_summary

const max_safe_integer = 9_007_199_254_740_991

const min_safe_integer = -9_007_199_254_740_991

const root_field_key = "rootFieldKey"

const repair_prefix = "repair-"

pub type ForestSummary {
  ForestSummary(fields: List(#(String, List(TreeValue))))
}

pub type SummaryRevision {
  RootRevision
  StableRevision(fluid_ids.StableId)
}

pub type DetachedField {
  DetachedField(major: SummaryRevision, minor: Int, root: Int)
}

pub type DetachedFieldIndex {
  DetachedFieldIndex(entries: List(DetachedField), max_id: Int)
}

pub type SummaryCommit {
  SummaryCommit(
    commit: codec.WireCommit,
    sequence_number: Option(Int),
    index_in_batch: Option(Int),
  )
}

pub type PeerBranch {
  PeerBranch(
    session: fluid_ids.SessionId,
    base: SummaryRevision,
    commits: List(SummaryCommit),
  )
}

pub type EditManagerSummary {
  EditManagerSummary(trunk: List(SummaryCommit), branches: List(PeerBranch))
}

pub type TreeSummaryData {
  TreeSummaryData(
    schema: schema.StoredSchema,
    forest: ForestSummary,
    detached: DetachedFieldIndex,
    history: EditManagerSummary,
  )
}

/// Decode one resolved SharedTree DDS summary subtree.
pub fn decode(
  entry: fluid_summary.SummaryEntry,
  previous: Option(fluid_summary.SummaryEntry),
  session: fluid_ids.SessionId,
  context: codec.DecodeContext,
) -> Result(TreeSummaryData, TreeError) {
  use resolved <- result.try(
    fluid_summary.resolve(entry, previous)
    |> result.map_error(fn(error) {
      CorruptData("summary", string.inspect(error))
    }),
  )
  use root <- result.try(tree_entries(resolved, "summary"))
  use _ <- result.try(exact_entry_names(
    root,
    [".metadata", "indexes"],
    "summary",
  ))
  use _ <- result.try(metadata_version(root, ".metadata", 2, "summary"))
  use indexes <- result.try(required_tree(root, "indexes", "summary.indexes"))
  use _ <- result.try(exact_entry_names(
    indexes,
    ["EditManager", "Schema", "Forest", "DetachedFieldIndex"],
    "summary.indexes",
  ))
  use history_tree <- result.try(required_tree(
    indexes,
    "EditManager",
    "summary.indexes.EditManager",
  ))
  use _ <- result.try(exact_entry_names(
    history_tree,
    [".metadata", "String"],
    "summary.indexes.EditManager",
  ))
  use _ <- result.try(metadata_version(
    history_tree,
    ".metadata",
    2,
    "summary.indexes.EditManager",
  ))
  use history_raw <- result.try(required_blob(
    history_tree,
    "String",
    "summary.indexes.EditManager.String",
  ))
  use schema_tree <- result.try(required_tree(
    indexes,
    "Schema",
    "summary.indexes.Schema",
  ))
  use _ <- result.try(exact_entry_names(
    schema_tree,
    [".metadata", "SchemaString"],
    "summary.indexes.Schema",
  ))
  use _ <- result.try(metadata_version(
    schema_tree,
    ".metadata",
    2,
    "summary.indexes.Schema",
  ))
  use schema_raw <- result.try(required_blob(
    schema_tree,
    "SchemaString",
    "summary.indexes.Schema.SchemaString",
  ))
  use stored <- result.try(schema.stored_from_string(schema_raw))
  use forest_tree <- result.try(required_tree(
    indexes,
    "Forest",
    "summary.indexes.Forest",
  ))
  use _ <- result.try(exact_entry_names(
    forest_tree,
    [".metadata", "contents"],
    "summary.indexes.Forest",
  ))
  use _ <- result.try(metadata_version(
    forest_tree,
    ".metadata",
    3,
    "summary.indexes.Forest",
  ))
  use forest_raw <- result.try(required_blob(
    forest_tree,
    "contents",
    "summary.indexes.Forest.contents",
  ))
  use detached_tree <- result.try(required_tree(
    indexes,
    "DetachedFieldIndex",
    "summary.indexes.DetachedFieldIndex",
  ))
  use _ <- result.try(exact_entry_names(
    detached_tree,
    [".metadata", "DetachedFieldIndexBlob"],
    "summary.indexes.DetachedFieldIndex",
  ))
  use _ <- result.try(metadata_version(
    detached_tree,
    ".metadata",
    2,
    "summary.indexes.DetachedFieldIndex",
  ))
  use detached_raw <- result.try(required_blob(
    detached_tree,
    "DetachedFieldIndexBlob",
    "summary.indexes.DetachedFieldIndex.DetachedFieldIndexBlob",
  ))
  use forest <- result.try(decode_forest_string(forest_raw))
  use detached <- result.try(decode_detached_string(
    detached_raw,
    session,
    context,
  ))
  use history <- result.try(decode_edit_manager_string(history_raw, context))
  use _ <- result.try(validate_tree_summary(stored, forest, detached))
  Ok(TreeSummaryData(stored, forest, detached, history))
}

/// Encode one SharedTree DDS summary subtree without handles.
pub fn encode(
  value: TreeSummaryData,
  session: fluid_ids.SessionId,
  context: codec.EncodeContext,
) -> Result(fluid_summary.SummaryEntry, TreeError) {
  let TreeSummaryData(stored, forest, detached, history) = value
  use _ <- result.try(validate_tree_summary(stored, forest, detached))
  use forest_json <- result.try(encode_forest(forest))
  use detached_json <- result.try(encode_detached(detached, session, context))
  use history_json <- result.try(encode_edit_manager(history, context))
  Ok(
    fluid_summary.SummaryTree([
      #(".metadata", blob("{\"version\":2}")),
      #(
        "indexes",
        fluid_summary.SummaryTree([
          #(
            "EditManager",
            codec_tree(2, "String", json.to_string(history_json)),
          ),
          #(
            "Schema",
            codec_tree(
              2,
              "SchemaString",
              schema.stored_to_json(stored) |> json.to_string,
            ),
          ),
          #("Forest", codec_tree(3, "contents", json.to_string(forest_json))),
          #(
            "DetachedFieldIndex",
            codec_tree(
              2,
              "DetachedFieldIndexBlob",
              json.to_string(detached_json),
            ),
          ),
        ]),
      ),
    ]),
  )
}

/// Decode Forest V2 content from JSON.
pub fn decode_forest(encoded: Json) -> Result(ForestSummary, TreeError) {
  use value <- result.try(json_value(encoded, "forest"))
  use members <- result.try(object(value, "forest"))
  use _ <- result.try(exact_keys(
    members,
    ["keys", "fields", "version"],
    "forest",
  ))
  use version_value <- result.try(required(members, "version", "forest.version"))
  use version <- result.try(integer(version_value, "forest.version"))
  use _ <- result.try(require_version("Forest", version, 2))
  use keys_value <- result.try(required(members, "keys", "forest.keys"))
  use key_values <- result.try(array(keys_value, "forest.keys"))
  use keys <- result.try(
    index_try_map(key_values, fn(value, index) {
      text(value, "forest.keys[" <> int.to_string(index) <> "]")
    }),
  )
  use _ <- result.try(unique_strings(keys, "forest.keys"))
  use fields_value <- result.try(required(members, "fields", "forest.fields"))
  use fields <- result.try(field_batch.decode(json_ot.to_json(fields_value)))
  case list.length(keys) == list.length(fields) {
    True -> Ok(ForestSummary(list.zip(keys, fields)))
    False ->
      Error(CorruptData("forest", "keys and fields must have the same length"))
  }
}

/// Encode Forest V2 content.
pub fn encode_forest(value: ForestSummary) -> Result(Json, TreeError) {
  let ForestSummary(fields) = value
  use _ <- result.try(unique_strings(
    list.map(fields, fn(field) { field.0 }),
    "forest.keys",
  ))
  use encoded <- result.try(
    field_batch.encode(list.map(fields, fn(field) { field.1 })),
  )
  Ok(
    json.object([
      #("keys", json.array(fields, fn(field) { json.string(field.0) })),
      #("fields", encoded),
      #("version", json.int(2)),
    ]),
  )
}

/// Decode DetachedFieldIndex V2 content from JSON.
pub fn decode_detached(
  encoded: Json,
  session: fluid_ids.SessionId,
  context: codec.DecodeContext,
) -> Result(DetachedFieldIndex, TreeError) {
  use value <- result.try(json_value(encoded, "detachedFieldIndex"))
  use members <- result.try(object(value, "detachedFieldIndex"))
  use _ <- result.try(exact_keys(
    members,
    ["version", "data", "maxId"],
    "detachedFieldIndex",
  ))
  use version_value <- result.try(required(
    members,
    "version",
    "detachedFieldIndex.version",
  ))
  use version <- result.try(integer(version_value, "detachedFieldIndex.version"))
  use _ <- result.try(require_version("DetachedFieldIndex", version, 2))
  use max_id_value <- result.try(required(
    members,
    "maxId",
    "detachedFieldIndex.maxId",
  ))
  use max_id <- result.try(nonnegative_integer(
    max_id_value,
    "detachedFieldIndex.maxId",
  ))
  use data_value <- result.try(required(
    members,
    "data",
    "detachedFieldIndex.data",
  ))
  use groups <- result.try(array(data_value, "detachedFieldIndex.data"))
  use entries <- result.try(
    index_try_map(groups, fn(value, index) {
      decode_detached_group(
        value,
        session,
        context,
        "detachedFieldIndex.data[" <> int.to_string(index) <> "]",
      )
    })
    |> result.map(list.flatten),
  )
  use _ <- result.try(validate_detached(entries, max_id))
  Ok(DetachedFieldIndex(entries, max_id))
}

/// Encode DetachedFieldIndex V2 content.
pub fn encode_detached(
  value: DetachedFieldIndex,
  session: fluid_ids.SessionId,
  context: codec.EncodeContext,
) -> Result(Json, TreeError) {
  let DetachedFieldIndex(entries, max_id) = value
  use _ <- result.try(validate_detached(entries, max_id))
  use groups <- result.try(group_detached(entries))
  use encoded <- result.try(
    list.try_map(groups, fn(group) {
      let #(major, entries) = group
      use major <- result.try(encode_major(major, session, context))
      case entries {
        [entry] ->
          Ok(
            json.array(
              [
                major,
                json.int(entry.minor),
                json.int(entry.root),
              ],
              fn(value) { value },
            ),
          )
        _ ->
          Ok(
            json.array(
              [
                major,
                json.array(entries, fn(entry) {
                  json.array(
                    [json.int(entry.minor), json.int(entry.root)],
                    fn(value) { value },
                  )
                }),
              ],
              fn(value) { value },
            ),
          )
      }
    }),
  )
  Ok(
    json.object([
      #("version", json.int(2)),
      #("data", json.array(encoded, fn(value) { value })),
      #("maxId", json.int(max_id)),
    ]),
  )
}

/// Decode EditManager V7 content from JSON.
pub fn decode_edit_manager(
  encoded: Json,
  context: codec.DecodeContext,
) -> Result(EditManagerSummary, TreeError) {
  use value <- result.try(json_value(encoded, "editManager"))
  use members <- result.try(object(value, "editManager"))
  use _ <- result.try(exact_keys(
    members,
    ["trunk", "branches", "version"],
    "editManager",
  ))
  use version_value <- result.try(required(
    members,
    "version",
    "editManager.version",
  ))
  use version <- result.try(integer(version_value, "editManager.version"))
  use _ <- result.try(require_version("EditManager", version, 7))
  use trunk_value <- result.try(required(members, "trunk", "editManager.trunk"))
  use trunk_values <- result.try(array(trunk_value, "editManager.trunk"))
  use trunk <- result.try(
    index_try_map(trunk_values, fn(value, index) {
      decode_commit(
        value,
        True,
        context,
        "editManager.trunk[" <> int.to_string(index) <> "]",
      )
    }),
  )
  use branches_value <- result.try(required(
    members,
    "branches",
    "editManager.branches",
  ))
  use branch_values <- result.try(array(branches_value, "editManager.branches"))
  use branches <- result.try(
    index_try_map(branch_values, fn(value, index) {
      decode_branch(
        value,
        context,
        "editManager.branches[" <> int.to_string(index) <> "]",
      )
    }),
  )
  use _ <- result.try(validate_history(trunk, branches))
  Ok(EditManagerSummary(trunk, branches))
}

/// Encode EditManager V7 content.
pub fn encode_edit_manager(
  value: EditManagerSummary,
  context: codec.EncodeContext,
) -> Result(Json, TreeError) {
  let EditManagerSummary(trunk, branches) = value
  use _ <- result.try(validate_history(trunk, branches))
  use trunk <- result.try(
    list.try_map(trunk, fn(commit) {
      encode_commit(commit, True, context, "editManager.trunk")
    }),
  )
  use branches <- result.try(
    list.try_map(branches, fn(branch) { encode_branch(branch, context) }),
  )
  Ok(
    json.object([
      #("trunk", json.array(trunk, fn(value) { value })),
      #("branches", json.array(branches, fn(value) { value })),
      #("version", json.int(7)),
    ]),
  )
}

fn decode_forest_string(raw: String) -> Result(ForestSummary, TreeError) {
  use value <- result.try(parse(raw, "forest"))
  decode_forest(json_ot.to_json(value))
}

fn decode_detached_string(
  raw: String,
  session: fluid_ids.SessionId,
  context: codec.DecodeContext,
) -> Result(DetachedFieldIndex, TreeError) {
  use value <- result.try(parse(raw, "detachedFieldIndex"))
  decode_detached(json_ot.to_json(value), session, context)
}

fn decode_edit_manager_string(
  raw: String,
  context: codec.DecodeContext,
) -> Result(EditManagerSummary, TreeError) {
  use value <- result.try(parse(raw, "editManager"))
  decode_edit_manager(json_ot.to_json(value), context)
}

fn decode_commit(
  value: JsonValue,
  sequenced: Bool,
  context: codec.DecodeContext,
  location: String,
) -> Result(SummaryCommit, TreeError) {
  use members <- result.try(object(value, location))
  let allowed = case sequenced {
    True -> [
      "change",
      "revision",
      "sessionId",
      "customMetadata",
      "sequenceNumber",
      "indexInBatch",
    ]
    False -> ["change", "revision", "sessionId", "customMetadata"]
  }
  use _ <- result.try(only_keys(members, allowed, location))
  use session_value <- result.try(required(
    members,
    "sessionId",
    location <> ".sessionId",
  ))
  use session_raw <- result.try(text(session_value, location <> ".sessionId"))
  use session <- result.try(
    fluid_ids.session_id(session_raw)
    |> result.map_error(fn(error) {
      CorruptData(location <> ".sessionId", string.inspect(error))
    }),
  )
  use revision_value <- result.try(required(
    members,
    "revision",
    location <> ".revision",
  ))
  use revision <- result.try(decode_authored_revision(
    revision_value,
    session,
    context,
    location <> ".revision",
  ))
  use changes_value <- result.try(required(
    members,
    "change",
    location <> ".change",
  ))
  use changes <- result.try(codec.decode_changes(
    json_ot.to_json(changes_value),
    context,
    codec.ChangeContext(session, Some(revision), codec.Summary),
  ))
  use metadata <- result.try(case optional(members, "customMetadata") {
    None -> Ok(None)
    Some(value) ->
      codec.custom_metadata_from_json(
        json_ot.to_json(value),
        location <> ".customMetadata",
      )
  })
  use sequence_number <- result.try(
    case sequenced, optional(members, "sequenceNumber") {
      True, Some(value) ->
        integer(value, location <> ".sequenceNumber") |> result.map(Some)
      True, None ->
        Error(CorruptData(
          location <> ".sequenceNumber",
          "required property is missing",
        ))
      False, None -> Ok(None)
      False, Some(_) ->
        Error(CorruptData(location, "branch commit has sequence metadata"))
    },
  )
  use index_in_batch <- result.try(case optional(members, "indexInBatch") {
    None -> Ok(None)
    Some(value) ->
      nonnegative_integer(value, location <> ".indexInBatch")
      |> result.map(Some)
  })
  Ok(SummaryCommit(
    codec.WireCommit(revision, session, changes, metadata),
    sequence_number,
    index_in_batch,
  ))
}

fn encode_commit(
  value: SummaryCommit,
  sequenced: Bool,
  context: codec.EncodeContext,
  location: String,
) -> Result(Json, TreeError) {
  let SummaryCommit(
    codec.WireCommit(revision, session, changes, metadata),
    sequence_number,
    index_in_batch,
  ) = value
  use revision <- result.try(codec.encode_stable_revision(
    revision,
    context,
    location <> ".revision",
  ))
  use changes <- result.try(codec.encode_changes(
    changes,
    context,
    codec.ChangeContext(session, Some(revision_id(value)), codec.Summary),
  ))
  use fields <- result.try(case sequenced, sequence_number {
    True, Some(sequence_number) ->
      Ok([
        #("sequenceNumber", json.int(sequence_number)),
        ..case index_in_batch {
          Some(index) -> [#("indexInBatch", json.int(index))]
          None -> []
        }
      ])
    True, None ->
      Error(CorruptData(
        location <> ".sequenceNumber",
        "required property is missing",
      ))
    False, None if index_in_batch == None -> Ok([])
    False, _ ->
      Error(CorruptData(location, "branch commit has sequence metadata"))
  })
  let fields = [
    #("change", changes),
    #("revision", json.int(revision)),
    #("sessionId", json.string(fluid_ids.session_id_to_string(session))),
    ..fields
  ]
  let fields = case metadata {
    Some(metadata) ->
      list.append(fields, [
        #("customMetadata", codec.custom_metadata_to_json(metadata)),
      ])
    None -> fields
  }
  Ok(json.object(fields))
}

fn decode_branch(
  value: JsonValue,
  context: codec.DecodeContext,
  location: String,
) -> Result(PeerBranch, TreeError) {
  use pair <- result.try(array(value, location))
  use #(session_value, branch_value) <- result.try(two(pair, location))
  use session_raw <- result.try(text(session_value, location <> "[0]"))
  use session <- result.try(
    fluid_ids.session_id(session_raw)
    |> result.map_error(fn(error) {
      CorruptData(location <> "[0]", string.inspect(error))
    }),
  )
  use members <- result.try(object(branch_value, location <> "[1]"))
  use _ <- result.try(exact_keys(
    members,
    ["base", "commits"],
    location <> "[1]",
  ))
  use base_value <- result.try(required(members, "base", location <> "[1].base"))
  use base <- result.try(decode_summary_revision(
    base_value,
    session,
    context,
    location <> "[1].base",
    True,
  ))
  use commits_value <- result.try(required(
    members,
    "commits",
    location <> "[1].commits",
  ))
  use commit_values <- result.try(array(
    commits_value,
    location <> "[1].commits",
  ))
  use commits <- result.try(
    index_try_map(commit_values, fn(value, index) {
      decode_commit(
        value,
        False,
        context,
        location <> "[1].commits[" <> int.to_string(index) <> "]",
      )
    }),
  )
  Ok(PeerBranch(session, base, commits))
}

fn encode_branch(
  branch: PeerBranch,
  context: codec.EncodeContext,
) -> Result(Json, TreeError) {
  let PeerBranch(session, base, commits) = branch
  use base <- result.try(encode_summary_revision(
    base,
    session,
    context,
    "editManager.branches.base",
  ))
  use commits <- result.try(
    list.try_map(commits, fn(commit) {
      encode_commit(commit, False, context, "editManager.branches.commits")
    }),
  )
  Ok(
    json.array(
      [
        json.string(fluid_ids.session_id_to_string(session)),
        json.object([
          #("base", base),
          #("commits", json.array(commits, fn(value) { value })),
        ]),
      ],
      fn(value) { value },
    ),
  )
}

fn decode_detached_group(
  value: JsonValue,
  session: fluid_ids.SessionId,
  context: codec.DecodeContext,
  location: String,
) -> Result(List(DetachedField), TreeError) {
  use values <- result.try(array(value, location))
  case values {
    [major, minor, root] -> {
      use major <- result.try(decode_summary_revision(
        major,
        session,
        context,
        location <> "[0]",
        True,
      ))
      use minor <- result.try(nonnegative_integer(minor, location <> "[1]"))
      use root <- result.try(nonnegative_integer(root, location <> "[2]"))
      Ok([DetachedField(major, minor, root)])
    }
    [major, ranges] -> {
      use major <- result.try(decode_summary_revision(
        major,
        session,
        context,
        location <> "[0]",
        True,
      ))
      use ranges <- result.try(array(ranges, location <> "[1]"))
      index_try_map(ranges, fn(value, index) {
        let location = location <> "[1][" <> int.to_string(index) <> "]"
        use pair <- result.try(array(value, location))
        use #(minor, root) <- result.try(two(pair, location))
        use minor <- result.try(nonnegative_integer(minor, location <> "[0]"))
        use root <- result.try(nonnegative_integer(root, location <> "[1]"))
        Ok(DetachedField(major, minor, root))
      })
    }
    _ -> Error(CorruptData(location, "expected a two- or three-item tuple"))
  }
}

fn decode_authored_revision(
  value: JsonValue,
  session: fluid_ids.SessionId,
  context: codec.DecodeContext,
  location: String,
) -> Result(fluid_ids.StableId, TreeError) {
  use revision <- result.try(decode_summary_revision(
    value,
    session,
    context,
    location,
    False,
  ))
  case revision {
    StableRevision(revision) -> Ok(revision)
    RootRevision ->
      Error(CorruptData(location, "root is not an authored revision"))
  }
}

fn decode_summary_revision(
  value: JsonValue,
  session: fluid_ids.SessionId,
  context: codec.DecodeContext,
  location: String,
  allow_stable: Bool,
) -> Result(SummaryRevision, TreeError) {
  case value {
    VString("root") -> Ok(RootRevision)
    VString(value) if allow_stable -> {
      use stable <- result.try(
        fluid_ids.stable_id(value)
        |> result.map_error(fn(error) {
          CorruptData(location, string.inspect(error))
        }),
      )
      let codec.DecodeContext(compressor: compressor, ..) = context
      use compressed <- result.try(
        fluid_ids.recompress(compressor, stable)
        |> result.map_error(fn(error) {
          CorruptData(location, string.inspect(error))
        }),
      )
      case compressed {
        Some(_) -> Ok(StableRevision(stable))
        None ->
          Error(CorruptData(location, "revision is not in the compressor"))
      }
    }
    VNumber(NInt(value)) if value >= 0 -> {
      codec.decode_stable_revision(value, session, context, location)
      |> result.map(StableRevision)
    }
    VNumber(NInt(_)) ->
      Error(CorruptData(location, "expected a finalized revision"))
    _ -> Error(CorruptData(location, "expected a revision"))
  }
}

fn encode_summary_revision(
  value: SummaryRevision,
  _session: fluid_ids.SessionId,
  context: codec.EncodeContext,
  location: String,
) -> Result(Json, TreeError) {
  case value {
    RootRevision -> Ok(json.string("root"))
    StableRevision(revision) -> {
      let codec.EncodeContext(compressor: compressor, ..) = context
      use compressed <- result.try(
        fluid_ids.recompress(compressor, revision)
        |> result.map_error(fn(error) {
          CorruptData(location, string.inspect(error))
        }),
      )
      use compressed <- result.try(case compressed {
        Some(value) -> Ok(value)
        None ->
          Error(CorruptData(location, "revision is not in the compressor"))
      })
      case fluid_ids.session_space_id_to_int(compressed) < 0 {
        True -> Ok(json.string(fluid_ids.stable_id_to_string(revision)))
        False ->
          codec.encode_stable_revision(revision, context, location)
          |> result.map(json.int)
      }
    }
  }
}

fn encode_major(
  value: SummaryRevision,
  session: fluid_ids.SessionId,
  context: codec.EncodeContext,
) -> Result(Json, TreeError) {
  encode_summary_revision(value, session, context, "detachedFieldIndex.data")
}

fn validate_tree_summary(
  stored: schema.StoredSchema,
  forest: ForestSummary,
  detached: DetachedFieldIndex,
) -> Result(Nil, TreeError) {
  let ForestSummary(fields) = forest
  let DetachedFieldIndex(entries, _) = detached
  use _ <- result.try(unique_strings(
    list.map(fields, fn(field) { field.0 }),
    "forest.keys",
  ))
  let root = case list.key_find(fields, root_field_key) {
    Ok(field) -> Some(field)
    Error(Nil) -> None
  }
  use _ <- result.try(case root {
    None -> schema.validate_root_field(stored, None)
    Some([]) -> schema.validate_root_field(stored, None)
    Some([value]) -> schema.validate_root(stored, value)
    Some(_) ->
      Error(CorruptData("forest.rootFieldKey", "root field has multiple trees"))
  })
  use _ <- result.try(
    list.try_each(entries, fn(entry) {
      let key = repair_prefix <> int.to_string(entry.root)
      case list.key_find(fields, key) {
        Ok([value]) -> schema.validate_subtree(stored, value)
        Ok(_) ->
          Error(CorruptData(
            "forest." <> key,
            "repair field must contain one tree",
          ))
        Error(Nil) ->
          Error(CorruptData(
            "forest." <> key,
            "detached repair field is missing",
          ))
      }
    }),
  )
  list.try_each(fields, fn(field) {
    case
      field.0 == root_field_key || string.starts_with(field.0, repair_prefix)
    {
      True ->
        case
          field.0 == root_field_key
          || list.any(entries, fn(entry) {
            field.0 == repair_prefix <> int.to_string(entry.root)
          })
        {
          True -> Ok(Nil)
          False ->
            Error(CorruptData(
              "forest." <> field.0,
              "repair field has no detached index entry",
            ))
        }
      False ->
        Error(CorruptData("forest." <> field.0, "unsupported forest field"))
    }
  })
}

fn validate_detached(
  entries: List(DetachedField),
  max_id: Int,
) -> Result(Nil, TreeError) {
  case max_id >= 0 && max_id <= max_safe_integer {
    False -> Error(CorruptData("detachedFieldIndex.maxId", "invalid watermark"))
    True -> {
      use _ <- result.try(
        list.try_each(entries, fn(entry) {
          case
            entry.minor >= 0
            && entry.minor <= max_safe_integer
            && entry.root >= 0
            && entry.root <= max_id
          {
            True -> Ok(Nil)
            False ->
              Error(CorruptData(
                "detachedFieldIndex.data",
                "invalid detached identifier",
              ))
          }
        }),
      )
      use _ <- result.try(unique_detached(entries))
      unique_roots(entries)
    }
  }
}

fn unique_detached(entries: List(DetachedField)) -> Result(Nil, TreeError) {
  case entries {
    [] -> Ok(Nil)
    [entry, ..rest] ->
      case
        list.any(rest, fn(other) {
          other.major == entry.major && other.minor == entry.minor
        })
      {
        True ->
          Error(CorruptData(
            "detachedFieldIndex.data",
            "duplicate detached identity",
          ))
        False -> unique_detached(rest)
      }
  }
}

fn unique_roots(entries: List(DetachedField)) -> Result(Nil, TreeError) {
  case entries {
    [] -> Ok(Nil)
    [entry, ..rest] ->
      case list.any(rest, fn(other) { other.root == entry.root }) {
        True ->
          Error(CorruptData("detachedFieldIndex.data", "duplicate forest root"))
        False -> unique_roots(rest)
      }
  }
}

fn group_detached(
  entries: List(DetachedField),
) -> Result(List(#(SummaryRevision, List(DetachedField))), TreeError) {
  entries
  |> list.fold([], fn(groups, entry) { put_group(groups, entry) })
  |> Ok
}

fn put_group(
  groups: List(#(SummaryRevision, List(DetachedField))),
  entry: DetachedField,
) -> List(#(SummaryRevision, List(DetachedField))) {
  case groups {
    [] -> [#(entry.major, [entry])]
    [group, ..rest] if group.0 == entry.major -> [
      #(group.0, list.append(group.1, [entry])),
      ..rest
    ]
    [group, ..rest] -> [group, ..put_group(rest, entry)]
  }
}

fn validate_history(
  trunk: List(SummaryCommit),
  branches: List(PeerBranch),
) -> Result(Nil, TreeError) {
  use _ <- result.try(validate_sequence_order(trunk))
  use _ <- result.try(unique_commit_revisions(trunk))
  use _ <- result.try(
    list.try_each(branches, fn(branch) {
      unique_commit_revisions(branch.commits)
    }),
  )
  unique_branch_sessions(branches)
}

fn validate_sequence_order(
  commits: List(SummaryCommit),
) -> Result(Nil, TreeError) {
  case commits {
    [] | [_] -> Ok(Nil)
    [first, second, ..rest] -> {
      use first_id <- result.try(sequence_id(first))
      use second_id <- result.try(sequence_id(second))
      case compare_sequence(first_id, second_id) {
        order.Lt -> validate_sequence_order([second, ..rest])
        _ ->
          Error(CorruptData(
            "editManager.trunk",
            "sequence positions are not strictly increasing",
          ))
      }
    }
  }
}

fn sequence_id(commit: SummaryCommit) -> Result(#(Int, Int), TreeError) {
  let SummaryCommit(_, sequence, index) = commit
  case sequence {
    Some(sequence) -> Ok(#(sequence, option_int(index, 0)))
    None ->
      Error(CorruptData(
        "editManager.trunk.sequenceNumber",
        "required property is missing",
      ))
  }
}

fn compare_sequence(left: #(Int, Int), right: #(Int, Int)) -> Order {
  case int.compare(left.0, right.0) {
    order.Eq -> int.compare(left.1, right.1)
    other -> other
  }
}

fn unique_commit_revisions(
  commits: List(SummaryCommit),
) -> Result(Nil, TreeError) {
  case commits {
    [] -> Ok(Nil)
    [commit, ..rest] -> {
      let revision = revision_id(commit)
      case list.any(rest, fn(other) { revision_id(other) == revision }) {
        True -> Error(CorruptData("editManager", "duplicate commit revision"))
        False -> unique_commit_revisions(rest)
      }
    }
  }
}

fn unique_branch_sessions(
  branches: List(PeerBranch),
) -> Result(Nil, TreeError) {
  case branches {
    [] -> Ok(Nil)
    [branch, ..rest] ->
      case list.any(rest, fn(other) { other.session == branch.session }) {
        True -> Error(CorruptData("editManager.branches", "duplicate peer"))
        False -> unique_branch_sessions(rest)
      }
  }
}

fn revision_id(commit: SummaryCommit) -> fluid_ids.StableId {
  let SummaryCommit(codec.WireCommit(revision, ..), ..) = commit
  revision
}

fn blob(value: String) -> fluid_summary.SummaryEntry {
  fluid_summary.SummaryBlob(<<value:utf8>>)
}

fn codec_tree(
  version: Int,
  key: String,
  value: String,
) -> fluid_summary.SummaryEntry {
  fluid_summary.SummaryTree([
    #(".metadata", blob("{\"version\":" <> int.to_string(version) <> "}")),
    #(key, blob(value)),
  ])
}

fn tree_entries(
  entry: fluid_summary.SummaryEntry,
  location: String,
) -> Result(List(#(String, fluid_summary.SummaryEntry)), TreeError) {
  case entry {
    fluid_summary.SummaryTree(entries) -> Ok(entries)
    _ -> Error(CorruptData(location, "expected a summary tree"))
  }
}

fn required_tree(
  entries: List(#(String, fluid_summary.SummaryEntry)),
  key: String,
  location: String,
) -> Result(List(#(String, fluid_summary.SummaryEntry)), TreeError) {
  use entry <- result.try(required_entry(entries, key, location))
  tree_entries(entry, location)
}

fn required_blob(
  entries: List(#(String, fluid_summary.SummaryEntry)),
  key: String,
  location: String,
) -> Result(String, TreeError) {
  use entry <- result.try(required_entry(entries, key, location))
  case entry {
    fluid_summary.SummaryBlob(bytes) ->
      bit_array.to_string(bytes)
      |> result.replace_error(CorruptData(location, "blob is not UTF-8"))
    _ -> Error(CorruptData(location, "expected a summary blob"))
  }
}

fn required_entry(
  entries: List(#(String, fluid_summary.SummaryEntry)),
  key: String,
  location: String,
) -> Result(fluid_summary.SummaryEntry, TreeError) {
  entries
  |> list.key_find(key)
  |> result.replace_error(CorruptData(location, "required entry is missing"))
}

fn exact_entry_names(
  entries: List(#(String, fluid_summary.SummaryEntry)),
  names: List(String),
  location: String,
) -> Result(Nil, TreeError) {
  use _ <- result.try(unique_strings(
    list.map(entries, fn(entry) { entry.0 }),
    location,
  ))
  case
    list.length(entries) == list.length(names)
    && list.all(entries, fn(entry) { list.contains(names, entry.0) })
  {
    True -> Ok(Nil)
    False -> Error(CorruptData(location, "unexpected summary entries"))
  }
}

fn metadata_version(
  entries: List(#(String, fluid_summary.SummaryEntry)),
  key: String,
  expected: Int,
  location: String,
) -> Result(Nil, TreeError) {
  use raw <- result.try(required_blob(entries, key, location <> "." <> key))
  use value <- result.try(parse(raw, location <> "." <> key))
  use members <- result.try(object(value, location <> "." <> key))
  use _ <- result.try(exact_keys(members, ["version"], location <> "." <> key))
  use version_value <- result.try(required(
    members,
    "version",
    location <> "." <> key <> ".version",
  ))
  use version <- result.try(integer(
    version_value,
    location <> "." <> key <> ".version",
  ))
  require_version(location <> " metadata", version, expected)
}

fn parse(raw: String, location: String) -> Result(JsonValue, TreeError) {
  json_ot.parse_json(raw)
  |> result.map_error(fn(_) { CorruptData(location, "blob is not valid JSON") })
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
  use _ <- result.try(unique_strings(
    list.map(members, fn(member) { member.0 }),
    location,
  ))
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

fn index_try_map(
  values: List(input),
  mapper: fn(input, Int) -> Result(output, error),
) -> Result(List(output), error) {
  index_try_map_loop(values, mapper, 0, [])
}

fn index_try_map_loop(
  values: List(input),
  mapper: fn(input, Int) -> Result(output, error),
  index: Int,
  mapped: List(output),
) -> Result(List(output), error) {
  case values {
    [] -> Ok(list.reverse(mapped))
    [value, ..rest] -> {
      use value <- result.try(mapper(value, index))
      index_try_map_loop(rest, mapper, index + 1, [value, ..mapped])
    }
  }
}

fn unique_strings(
  values: List(String),
  location: String,
) -> Result(Nil, TreeError) {
  case values {
    [] -> Ok(Nil)
    [value, ..rest] ->
      case list.contains(rest, value) {
        True -> Error(CorruptData(location, "duplicate value " <> value))
        False -> unique_strings(rest, location)
      }
  }
}

fn require_version(
  name: String,
  actual: Int,
  expected: Int,
) -> Result(Nil, TreeError) {
  case actual == expected {
    True -> Ok(Nil)
    False ->
      Error(UnsupportedFormat(
        name,
        int.to_string(actual) <> " (expected " <> int.to_string(expected) <> ")",
      ))
  }
}

fn option_int(value: Option(Int), default: Int) -> Int {
  case value {
    Some(value) -> value
    None -> default
  }
}
