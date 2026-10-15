//// Local versioned checkpoints for pending SharedTree state.

import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import watershed/fluid_ids
import watershed/json_ot.{
  type JsonValue, NInt, VArray, VNull, VNumber, VObject, VString,
}
import watershed/tree/change
import watershed/tree/codec
import watershed/tree/codec/summary as summary_codec
import watershed/tree/forest
import watershed/tree/history
import watershed/tree/schema
import watershed/tree/shared_change
import watershed/tree/types.{type SequencePoint, type TreeError, CorruptData}
import watershed/tree_kernel

const version = 1

pub fn capture(
  state: tree_kernel.TreeState,
  compressor: fluid_ids.Compressor,
) -> Result(Json, TreeError) {
  use data <- result.try(tree_kernel.capture_recovery(state))
  use _ <- result.try(require(
    history.local_session(tree_kernel.branch_history(state))
      == fluid_ids.local_session(compressor),
    "recovery",
    "compressor local session does not match the tree",
  ))
  use visible <- result.try(encode_forest(data.visible, data.stored, compressor))
  use sequenced <- result.try(encode_forest(
    data.sequenced,
    data.stored,
    compressor,
  ))
  use history <- result.try(encode_history(data.history, compressor))
  use authoring <- result.try(
    list.try_map(data.local_authoring_schemas, fn(entry) {
      use encoded <- result.try(codec.encode_schema(entry.1))
      Ok(json.array([stable(entry.0), encoded], fn(value) { value }))
    }),
  )
  use retained <- result.try(summary_codec.encode_edit_manager(
    data.retained_wire,
    codec.EncodeContext(codec.Fluid310, compressor, Some(data.stored)),
  ))
  Ok(
    json.object([
      #("version", json.int(version)),
      #("schema", schema.stored_to_json(data.stored)),
      #("visible", visible),
      #("sequenced", sequenced),
      #("history", history),
      #("authoringSchemas", json.array(authoring, fn(value) { value })),
      #("nextLocalId", json.int(data.next_local_id)),
      #("retainedWire", retained),
    ]),
  )
}

pub fn restore(
  data: Json,
  view_id: fluid_ids.StableId,
  compressor: fluid_ids.Compressor,
) -> Result(tree_kernel.TreeState, TreeError) {
  use value <- result.try(json_value(data, "recovery"))
  use fields <- result.try(object(value, "recovery"))
  use _ <- result.try(exact(
    fields,
    [
      "version", "schema", "visible", "sequenced", "history", "authoringSchemas",
      "nextLocalId", "retainedWire",
    ],
    "recovery",
  ))
  use checkpoint_version <- result.try(
    required(fields, "version", "recovery.version")
    |> then(fn(value) { integer(value, "recovery.version") }),
  )
  use _ <- result.try(case checkpoint_version {
    1 -> Ok(Nil)
    other ->
      Error(types.UnsupportedFormat("SharedTree recovery", int.to_string(other)))
  })
  use stored <- result.try(
    required(fields, "schema", "recovery.schema")
    |> then(fn(value) { schema.stored_from_json(json_ot.to_json(value)) }),
  )
  use visible <- result.try(
    required(fields, "visible", "recovery.visible")
    |> then(fn(value) {
      decode_forest(
        json_ot.to_json(value),
        stored,
        compressor,
        "recovery.visible",
      )
    }),
  )
  use sequenced <- result.try(
    required(fields, "sequenced", "recovery.sequenced")
    |> then(fn(value) {
      decode_forest(
        json_ot.to_json(value),
        stored,
        compressor,
        "recovery.sequenced",
      )
    }),
  )
  use recovered_history <- result.try(
    required(fields, "history", "recovery.history")
    |> then(fn(value) { decode_history(json_ot.to_json(value), compressor) }),
  )
  use _ <- result.try(require(
    recovered_history.local_session == fluid_ids.local_session(compressor),
    "recovery.history.localSession",
    "compressor local session does not match the checkpoint",
  ))
  use authoring_values <- result.try(
    required(fields, "authoringSchemas", "recovery.authoringSchemas")
    |> then(fn(value) { array(value, "recovery.authoringSchemas") }),
  )
  use authoring <- result.try(
    index_try_map(authoring_values, fn(value, index) {
      let location = "recovery.authoringSchemas[" <> int.to_string(index) <> "]"
      use pair <- result.try(array(value, location))
      use _ <- result.try(length(pair, 2, location))
      use revision <- result.try(
        item(pair, 0, location)
        |> then(fn(value) { decode_stable(value, location <> "[0]") }),
      )
      use stored <- result.try(
        item(pair, 1, location)
        |> then(fn(value) {
          codec.decode_schema(json.to_string(json_ot.to_json(value)))
        }),
      )
      Ok(#(revision, stored))
    }),
  )
  use next_local_id <- result.try(
    required(fields, "nextLocalId", "recovery.nextLocalId")
    |> then(fn(value) { integer(value, "recovery.nextLocalId") }),
  )
  use retained <- result.try(
    required(fields, "retainedWire", "recovery.retainedWire")
    |> then(fn(value) {
      summary_codec.decode_edit_manager_with_schema(
        json_ot.to_json(value),
        codec.DecodeContext(codec.Fluid310, compressor),
        stored,
      )
    }),
  )
  tree_kernel.restore_recovery(
    tree_kernel.RecoveryState(
      stored,
      visible,
      sequenced,
      recovered_history,
      authoring,
      next_local_id,
      retained,
    ),
    view_id,
  )
}

fn encode_forest(
  data: forest.ForestData,
  stored: schema.StoredSchema,
  compressor: fluid_ids.Compressor,
) -> Result(Json, TreeError) {
  let fields = case data.root {
    None -> []
    Some(root) -> [#("root", [root])]
  }
  let fields =
    list.append(
      fields,
      list.index_map(data.detached, fn(entry, index) {
        #("detached:" <> int.to_string(index), [entry.value])
      }),
    )
  use values <- result.try(summary_codec.encode_forest_with_context(
    summary_codec.ForestSummary(fields),
    stored,
    compressor,
  ))
  Ok(
    json.object([
      #("values", values),
      #(
        "detached",
        json.array(data.detached, fn(entry) {
          json.object([
            #("id", atom(entry.id)),
            #("root", json.int(entry.forest_root_id)),
            #("latest", optional_stable(entry.latest_relevant_revision)),
          ])
        }),
      ),
      #("nextRoot", json.int(data.next_detached_root_id)),
    ]),
  )
}

fn decode_forest(
  encoded: Json,
  stored: schema.StoredSchema,
  compressor: fluid_ids.Compressor,
  location: String,
) -> Result(forest.ForestData, TreeError) {
  use value <- result.try(json_value(encoded, location))
  use fields <- result.try(object(value, location))
  use _ <- result.try(exact(
    fields,
    ["values", "detached", "nextRoot"],
    location,
  ))
  use values <- result.try(
    required(fields, "values", location <> ".values")
    |> then(fn(value) {
      summary_codec.decode_forest_with_context(
        json_ot.to_json(value),
        stored,
        compressor,
      )
    }),
  )
  let summary_codec.ForestSummary(values) = values
  use detached_values <- result.try(
    required(fields, "detached", location <> ".detached")
    |> then(fn(value) { array(value, location <> ".detached") }),
  )
  use detached <- result.try(
    index_try_map(detached_values, fn(value, index) {
      let item_location =
        location <> ".detached[" <> int.to_string(index) <> "]"
      use members <- result.try(object(value, item_location))
      use _ <- result.try(exact(
        members,
        ["id", "root", "latest"],
        item_location,
      ))
      use id <- result.try(
        required(members, "id", item_location <> ".id")
        |> then(fn(value) { decode_atom(value, item_location <> ".id") }),
      )
      use root <- result.try(
        required(members, "root", item_location <> ".root")
        |> then(fn(value) { integer(value, item_location <> ".root") }),
      )
      use latest <- result.try(
        required(members, "latest", item_location <> ".latest")
        |> then(fn(value) {
          decode_optional_stable(value, item_location <> ".latest")
        }),
      )
      use tree <- result.try(
        list.key_find(values, "detached:" <> int.to_string(index))
        |> result.map_error(fn(_) {
          CorruptData(item_location, "detached tree value is missing")
        }),
      )
      use tree <- result.try(case tree {
        [tree] -> Ok(tree)
        _ -> Error(CorruptData(item_location, "detached tree must be singular"))
      })
      Ok(forest.DetachedTreeData(id, root, latest, tree))
    }),
  )
  use _ <- result.try(require(
    list.length(values)
      == list.length(detached)
      + case list.key_find(values, "root") {
      Ok(_) -> 1
      Error(_) -> 0
    },
    location <> ".values",
    "forest contains an unexpected field",
  ))
  use root <- result.try(case list.key_find(values, "root") {
    Error(_) -> Ok(None)
    Ok([root]) -> Ok(Some(root))
    Ok(_) ->
      Error(CorruptData(location <> ".values.root", "root must be singular"))
  })
  use next_root <- result.try(
    required(fields, "nextRoot", location <> ".nextRoot")
    |> then(fn(value) { integer(value, location <> ".nextRoot") }),
  )
  Ok(forest.ForestData(root, detached, next_root))
}

fn encode_history(
  data: history.RecoveryHistory,
  compressor: fluid_ids.Compressor,
) -> Result(Json, TreeError) {
  use trunk <- result.try(
    list.try_map(data.trunk, fn(entry) {
      use commit <- result.try(encode_commit(entry.commit, compressor))
      Ok(json.array([commit, point(entry.point)], fn(value) { value }))
    }),
  )
  use peers <- result.try(
    list.try_map(data.peers, fn(peer) {
      use commits <- result.try(
        list.try_map(peer.commits, fn(commit) {
          encode_branch_commit(commit, compressor)
        }),
      )
      Ok(
        json.object([
          #("originator", session(peer.originator)),
          #("base", encode_base(peer.base)),
          #("commits", json.array(commits, fn(value) { value })),
        ]),
      )
    }),
  )
  use pending <- result.try(
    list.try_map(data.pending, fn(entry) {
      use original <- result.try(encode_branch_commit(
        entry.original,
        compressor,
      ))
      use current <- result.try(encode_branch_commit(entry.current, compressor))
      use context <- result.try(
        list.try_map(entry.authoring_context, fn(commit) {
          encode_commit(commit, compressor)
        }),
      )
      Ok(
        json.object([
          #("original", original),
          #("current", current),
          #("context", json.array(context, fn(value) { value })),
        ]),
      )
    }),
  )
  use authored <- result.try(
    list.try_map(data.local_authored_context, fn(commit) {
      encode_commit(commit, compressor)
    }),
  )
  use rollbacks <- result.try(
    list.try_map(data.rollbacks, fn(entry) {
      use changes <- result.try(encode_changes(
        entry.change,
        data.local_session,
        entry.revision,
        compressor,
      ))
      Ok(
        json.object([
          #("source", json.int(entry.source_node)),
          #("revision", stable(entry.revision)),
          #("changes", changes),
        ]),
      )
    }),
  )
  use receipts <- result.try(
    list.try_map(data.receipts, fn(entry) {
      use commit <- result.try(case entry.commit {
        None -> Ok(json.null())
        Some(commit) -> encode_commit(commit, compressor)
      })
      Ok(
        json.object([
          #("revision", stable(entry.revision)),
          #("commit", commit),
          #("point", point(entry.point)),
          #("reference", optional_int(entry.reference_sequence_number)),
          #("minimum", optional_int(entry.minimum_sequence_number)),
        ]),
      )
    }),
  )
  Ok(
    json.object([
      #("localSession", session(data.local_session)),
      #("base", encode_history_base(data.base)),
      #("trunk", json.array(trunk, fn(value) { value })),
      #("peers", json.array(peers, fn(value) { value })),
      #("pending", json.array(pending, fn(value) { value })),
      #("localBase", optional_base(data.local_base)),
      #("localAuthored", json.array(authored, fn(value) { value })),
      #("rollbacks", json.array(rollbacks, fn(value) { value })),
      #("receipts", json.array(receipts, fn(value) { value })),
      #("replayedReceipts", json.array(data.replayed_receipts, point)),
      #("nextNodeId", json.int(data.next_node_id)),
      #("sequenceNumber", json.int(data.sequence_number)),
      #("minimumSequenceNumber", json.int(data.minimum_sequence_number)),
    ]),
  )
}

fn decode_history(
  encoded: Json,
  compressor: fluid_ids.Compressor,
) -> Result(history.RecoveryHistory, TreeError) {
  use value <- result.try(json_value(encoded, "recovery.history"))
  use fields <- result.try(object(value, "recovery.history"))
  use _ <- result.try(exact(
    fields,
    [
      "localSession", "base", "trunk", "peers", "pending", "localBase",
      "localAuthored", "rollbacks", "receipts", "replayedReceipts", "nextNodeId",
      "sequenceNumber", "minimumSequenceNumber",
    ],
    "recovery.history",
  ))
  use local_session <- result.try(
    required(fields, "localSession", "recovery.history.localSession")
    |> then(fn(value) { decode_session(value, "recovery.history.localSession") }),
  )
  use base <- result.try(
    required(fields, "base", "recovery.history.base")
    |> then(decode_history_base),
  )
  use trunk <- result.try(
    decode_many(fields, "trunk", "recovery.history.trunk", fn(value, location) {
      use pair <- result.try(array(value, location))
      use _ <- result.try(length(pair, 2, location))
      use commit <- result.try(
        item(pair, 0, location)
        |> then(fn(value) {
          decode_commit(value, compressor, location <> "[0]")
        }),
      )
      use point <- result.try(
        item(pair, 1, location)
        |> then(fn(value) { decode_point(value, location <> "[1]") }),
      )
      Ok(history.SequencedCommit(commit, point))
    }),
  )
  use peers <- result.try(
    decode_many(fields, "peers", "recovery.history.peers", fn(value, location) {
      use members <- result.try(object(value, location))
      use _ <- result.try(exact(
        members,
        ["originator", "base", "commits"],
        location,
      ))
      use originator <- result.try(
        required(members, "originator", location <> ".originator")
        |> then(fn(value) { decode_session(value, location <> ".originator") }),
      )
      use base <- result.try(
        required(members, "base", location <> ".base")
        |> then(decode_base),
      )
      use commits <- result.try(
        decode_many(
          members,
          "commits",
          location <> ".commits",
          fn(value, location) {
            decode_branch_commit(value, compressor, location)
          },
        ),
      )
      Ok(history.RecoveryPeer(originator, base, commits))
    }),
  )
  use pending <- result.try(
    decode_many(
      fields,
      "pending",
      "recovery.history.pending",
      fn(value, location) {
        use members <- result.try(object(value, location))
        use _ <- result.try(exact(
          members,
          ["original", "current", "context"],
          location,
        ))
        use original <- result.try(
          required(members, "original", location <> ".original")
          |> then(fn(value) {
            decode_branch_commit(value, compressor, location <> ".original")
          }),
        )
        use current <- result.try(
          required(members, "current", location <> ".current")
          |> then(fn(value) {
            decode_branch_commit(value, compressor, location <> ".current")
          }),
        )
        use context <- result.try(
          decode_many(
            members,
            "context",
            location <> ".context",
            fn(value, location) { decode_commit(value, compressor, location) },
          ),
        )
        Ok(history.RecoveryLocalCommit(original, current, context))
      },
    ),
  )
  use local_base <- result.try(
    required(fields, "localBase", "recovery.history.localBase")
    |> then(decode_optional_base),
  )
  use authored <- result.try(
    decode_many(
      fields,
      "localAuthored",
      "recovery.history.localAuthored",
      fn(value, location) { decode_commit(value, compressor, location) },
    ),
  )
  use rollbacks <- result.try(
    decode_many(
      fields,
      "rollbacks",
      "recovery.history.rollbacks",
      fn(value, location) {
        use members <- result.try(object(value, location))
        use _ <- result.try(exact(
          members,
          ["source", "revision", "changes"],
          location,
        ))
        use source <- result.try(
          required(members, "source", location <> ".source")
          |> then(fn(value) { integer(value, location <> ".source") }),
        )
        use revision <- result.try(
          required(members, "revision", location <> ".revision")
          |> then(fn(value) { decode_stable(value, location <> ".revision") }),
        )
        use changes <- result.try(
          required(members, "changes", location <> ".changes")
          |> then(fn(value) {
            decode_changes(
              value,
              local_session,
              revision,
              compressor,
              location <> ".changes",
            )
          }),
        )
        Ok(history.RecoveryRollback(source, revision, changes))
      },
    ),
  )
  use receipts <- result.try(
    decode_many(
      fields,
      "receipts",
      "recovery.history.receipts",
      fn(value, location) {
        use members <- result.try(object(value, location))
        use _ <- result.try(exact(
          members,
          ["revision", "commit", "point", "reference", "minimum"],
          location,
        ))
        use revision <- result.try(
          required(members, "revision", location <> ".revision")
          |> then(fn(value) { decode_stable(value, location <> ".revision") }),
        )
        use commit <- result.try(
          required(members, "commit", location <> ".commit")
          |> then(fn(value) {
            decode_optional(value, location <> ".commit", fn(value) {
              decode_commit(value, compressor, location <> ".commit")
            })
          }),
        )
        use point <- result.try(
          required(members, "point", location <> ".point")
          |> then(fn(value) { decode_point(value, location <> ".point") }),
        )
        use reference <- result.try(
          required(members, "reference", location <> ".reference")
          |> then(fn(value) {
            decode_optional(value, location <> ".reference", fn(value) {
              integer(value, location <> ".reference")
            })
          }),
        )
        use minimum <- result.try(
          required(members, "minimum", location <> ".minimum")
          |> then(fn(value) {
            decode_optional(value, location <> ".minimum", fn(value) {
              integer(value, location <> ".minimum")
            })
          }),
        )
        Ok(history.RecoveryReceipt(revision, commit, point, reference, minimum))
      },
    ),
  )
  use replayed <- result.try(decode_many(
    fields,
    "replayedReceipts",
    "recovery.history.replayedReceipts",
    decode_point,
  ))
  use next_node_id <- result.try(decode_integer_field(
    fields,
    "nextNodeId",
    "recovery.history.nextNodeId",
  ))
  use sequence_number <- result.try(decode_integer_field(
    fields,
    "sequenceNumber",
    "recovery.history.sequenceNumber",
  ))
  use minimum_sequence_number <- result.try(decode_integer_field(
    fields,
    "minimumSequenceNumber",
    "recovery.history.minimumSequenceNumber",
  ))
  Ok(history.RecoveryHistory(
    local_session,
    base,
    trunk,
    peers,
    pending,
    local_base,
    authored,
    rollbacks,
    receipts,
    replayed,
    next_node_id,
    sequence_number,
    minimum_sequence_number,
  ))
}

fn encode_commit(
  commit: history.Commit,
  compressor: fluid_ids.Compressor,
) -> Result(Json, TreeError) {
  use changes <- result.try(encode_changes(
    commit.change,
    commit.originator,
    commit.revision,
    compressor,
  ))
  Ok(
    json.object([
      #("revision", stable(commit.revision)),
      #("originator", session(commit.originator)),
      #("changes", changes),
    ]),
  )
}

fn decode_commit(
  value: JsonValue,
  compressor: fluid_ids.Compressor,
  location: String,
) -> Result(history.Commit, TreeError) {
  use fields <- result.try(object(value, location))
  use _ <- result.try(exact(
    fields,
    ["revision", "originator", "changes"],
    location,
  ))
  use revision <- result.try(
    required(fields, "revision", location <> ".revision")
    |> then(fn(value) { decode_stable(value, location <> ".revision") }),
  )
  use originator <- result.try(
    required(fields, "originator", location <> ".originator")
    |> then(fn(value) { decode_session(value, location <> ".originator") }),
  )
  use changes <- result.try(
    required(fields, "changes", location <> ".changes")
    |> then(fn(value) {
      decode_changes(
        value,
        originator,
        revision,
        compressor,
        location <> ".changes",
      )
    }),
  )
  Ok(history.Commit(revision, originator, changes))
}

fn encode_changes(
  changes: shared_change.Changeset,
  originator: fluid_ids.SessionId,
  revision: fluid_ids.StableId,
  compressor: fluid_ids.Compressor,
) -> Result(Json, TreeError) {
  use parts <- result.try(
    list.try_map(shared_change.to_changes(changes), fn(item) {
      case item {
        shared_change.SchemaChange(..) -> Ok(#(item, []))
        shared_change.DataChange(value) -> {
          let data = change.to_data(value)
          use order <- result.try(codec.identity_order(
            change.identity_revisions(value),
            compressor,
            "recovery.history.change",
          ))
          use encoded <- result.try(change.from_data(
            change.ChangeData(..data, destroys: []),
            order,
          ))
          Ok(#(shared_change.DataChange(encoded), data.destroys))
        }
      }
    }),
  )
  use wire <- result.try(codec.encode_changes(
    list.map(parts, fn(part) { part.0 }),
    codec.EncodeContext(codec.Fluid310, compressor, None),
    codec.ChangeContext(originator, Some(revision), codec.Recovery),
  ))
  Ok(
    json.object([
      #("wire", wire),
      #(
        "destroys",
        json.array(parts, fn(part) {
          json.array(part.1, fn(destroy) {
            json.array([atom(destroy.id), json.int(destroy.count)], fn(value) {
              value
            })
          })
        }),
      ),
    ]),
  )
}

fn decode_changes(
  value: JsonValue,
  originator: fluid_ids.SessionId,
  revision: fluid_ids.StableId,
  compressor: fluid_ids.Compressor,
  location: String,
) -> Result(shared_change.Changeset, TreeError) {
  use fields <- result.try(object(value, location))
  use _ <- result.try(exact(fields, ["wire", "destroys"], location))
  use wire <- result.try(required(fields, "wire", location <> ".wire"))
  use changes <- result.try(codec.decode_changes(
    json_ot.to_json(wire),
    codec.DecodeContext(codec.Fluid310, compressor),
    codec.ChangeContext(originator, Some(revision), codec.Recovery),
  ))
  use destroys <- result.try(
    decode_many(
      fields,
      "destroys",
      location <> ".destroys",
      fn(value, location) {
        use values <- result.try(array(value, location))
        list.try_map(values, fn(value) {
          use pair <- result.try(array(value, location))
          use _ <- result.try(length(pair, 2, location))
          use id <- result.try(
            item(pair, 0, location)
            |> then(fn(value) { decode_atom(value, location <> "[0]") }),
          )
          use count <- result.try(
            item(pair, 1, location)
            |> then(fn(value) { integer(value, location <> "[1]") }),
          )
          Ok(forest.Destroy(id, count))
        })
      },
    ),
  )
  use _ <- result.try(length(
    destroys,
    list.length(changes),
    location <> ".destroys",
  ))
  use changes <- result.try(
    list.try_map(list.zip(changes, destroys), fn(part) {
      case part {
        #(shared_change.SchemaChange(..) as item, []) -> Ok(item)
        #(shared_change.SchemaChange(..), _) ->
          Error(CorruptData(location, "schema change cannot destroy nodes"))
        #(shared_change.DataChange(value), destroys) -> {
          let revisions =
            list.filter_map(destroys, fn(destroy) {
              case destroy.id.revision {
                Some(revision) -> Ok(revision)
                None -> Error(Nil)
              }
            })
          use order <- result.try(codec.identity_order(
            list.append(change.identity_revisions(value), revisions),
            compressor,
            location,
          ))
          change.from_data(
            change.ChangeData(..change.to_data(value), destroys: destroys),
            order,
          )
          |> result.map(shared_change.DataChange)
        }
      }
    }),
  )
  shared_change.from_changes(changes)
  |> result.map_error(fn(error) { CorruptData(location, string.inspect(error)) })
}

fn encode_branch_commit(
  commit: history.RecoveryBranchCommit,
  compressor: fluid_ids.Compressor,
) -> Result(Json, TreeError) {
  use encoded <- result.try(encode_commit(commit.commit, compressor))
  Ok(json.array([json.int(commit.node_id), encoded], fn(value) { value }))
}

fn decode_branch_commit(
  value: JsonValue,
  compressor: fluid_ids.Compressor,
  location: String,
) -> Result(history.RecoveryBranchCommit, TreeError) {
  use pair <- result.try(array(value, location))
  use _ <- result.try(length(pair, 2, location))
  use node_id <- result.try(
    item(pair, 0, location)
    |> then(fn(value) { integer(value, location <> "[0]") }),
  )
  use commit <- result.try(
    item(pair, 1, location)
    |> then(fn(value) { decode_commit(value, compressor, location <> "[1]") }),
  )
  Ok(history.RecoveryBranchCommit(node_id, commit))
}

fn encode_history_base(base: history.HistoryBase) -> Json {
  case base {
    history.InitialBase ->
      json.array([json.string("initial")], fn(value) { value })
    history.SequencedBase(sequence_point) ->
      json.array([json.string("sequenced"), point(sequence_point)], fn(value) {
        value
      })
  }
}

fn decode_history_base(
  value: JsonValue,
) -> Result(history.HistoryBase, TreeError) {
  use values <- result.try(array(value, "recovery.history.base"))
  case values {
    [VString("initial")] -> Ok(history.InitialBase)
    [VString("sequenced"), value] ->
      decode_point(value, "recovery.history.base[1]")
      |> result.map(history.SequencedBase)
    _ -> Error(CorruptData("recovery.history.base", "history base is invalid"))
  }
}

fn encode_base(base: history.RecoveryBranchBase) -> Json {
  case base {
    history.RecoverySentinel -> json.null()
    history.RecoveryRevision(revision) -> stable(revision)
  }
}

fn optional_base(base: Option(history.RecoveryBranchBase)) -> Json {
  case base {
    None -> json.null()
    Some(base) -> json.object([#("value", encode_base(base))])
  }
}

fn decode_optional_base(
  value: JsonValue,
) -> Result(Option(history.RecoveryBranchBase), TreeError) {
  case value {
    VNull -> Ok(None)
    value -> {
      use fields <- result.try(object(value, "recovery.history.localBase"))
      use _ <- result.try(exact(fields, ["value"], "recovery.history.localBase"))
      use base <- result.try(required(
        fields,
        "value",
        "recovery.history.localBase.value",
      ))
      decode_base(base) |> result.map(Some)
    }
  }
}

fn decode_base(
  value: JsonValue,
) -> Result(history.RecoveryBranchBase, TreeError) {
  case value {
    VNull -> Ok(history.RecoverySentinel)
    _ ->
      decode_stable(value, "recovery history branch base")
      |> result.map(history.RecoveryRevision)
  }
}

fn point(value: SequencePoint) -> Json {
  json.array(
    [json.int(value.sequence_number), json.int(value.index_in_batch)],
    fn(value) { value },
  )
}

fn decode_point(
  value: JsonValue,
  location: String,
) -> Result(SequencePoint, TreeError) {
  use values <- result.try(array(value, location))
  use _ <- result.try(length(values, 2, location))
  use sequence <- result.try(
    item(values, 0, location)
    |> then(fn(value) { integer(value, location <> "[0]") }),
  )
  use index <- result.try(
    item(values, 1, location)
    |> then(fn(value) { integer(value, location <> "[1]") }),
  )
  Ok(types.SequencePoint(sequence, index))
}

fn atom(value: types.AtomId) -> Json {
  json.array(
    [optional_stable(value.revision), json.int(value.local_id)],
    fn(value) { value },
  )
}

fn decode_atom(
  value: JsonValue,
  location: String,
) -> Result(types.AtomId, TreeError) {
  use values <- result.try(array(value, location))
  use _ <- result.try(length(values, 2, location))
  use revision <- result.try(
    item(values, 0, location)
    |> then(fn(value) { decode_optional_stable(value, location <> "[0]") }),
  )
  use local_id <- result.try(
    item(values, 1, location)
    |> then(fn(value) { integer(value, location <> "[1]") }),
  )
  Ok(types.AtomId(revision, local_id))
}

fn stable(value: fluid_ids.StableId) -> Json {
  json.string(fluid_ids.stable_id_to_string(value))
}

fn session(value: fluid_ids.SessionId) -> Json {
  json.string(fluid_ids.session_id_to_string(value))
}

fn optional_stable(value: Option(fluid_ids.StableId)) -> Json {
  case value {
    None -> json.null()
    Some(value) -> stable(value)
  }
}

fn decode_optional_stable(
  value: JsonValue,
  location: String,
) -> Result(Option(fluid_ids.StableId), TreeError) {
  decode_optional(value, location, fn(value) { decode_stable(value, location) })
}

fn decode_stable(
  value: JsonValue,
  location: String,
) -> Result(fluid_ids.StableId, TreeError) {
  use value <- result.try(text(value, location))
  fluid_ids.stable_id(value)
  |> result.map_error(fn(error) { CorruptData(location, string.inspect(error)) })
}

fn decode_session(
  value: JsonValue,
  location: String,
) -> Result(fluid_ids.SessionId, TreeError) {
  use value <- result.try(text(value, location))
  fluid_ids.session_id(value)
  |> result.map_error(fn(error) { CorruptData(location, string.inspect(error)) })
}

fn optional_int(value: Option(Int)) -> Json {
  case value {
    None -> json.null()
    Some(value) -> json.int(value)
  }
}

fn decode_optional(
  value: JsonValue,
  _location: String,
  decode: fn(JsonValue) -> Result(a, TreeError),
) -> Result(Option(a), TreeError) {
  case value {
    VNull -> Ok(None)
    value -> decode(value) |> result.map(Some)
  }
}

fn decode_many(
  fields: List(#(String, JsonValue)),
  name: String,
  location: String,
  decode: fn(JsonValue, String) -> Result(a, TreeError),
) -> Result(List(a), TreeError) {
  use values <- result.try(
    required(fields, name, location)
    |> then(fn(value) { array(value, location) }),
  )
  values
  |> list.index_map(fn(value, index) { #(value, index) })
  |> list.try_map(fn(entry) {
    decode(entry.0, location <> "[" <> int.to_string(entry.1) <> "]")
  })
}

fn decode_integer_field(
  fields: List(#(String, JsonValue)),
  name: String,
  location: String,
) -> Result(Int, TreeError) {
  required(fields, name, location)
  |> then(fn(value) { integer(value, location) })
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
    VObject(fields) -> Ok(fields)
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
    VNumber(NInt(value)) -> Ok(value)
    _ -> Error(CorruptData(location, "expected an integer"))
  }
}

fn required(
  fields: List(#(String, JsonValue)),
  name: String,
  location: String,
) -> Result(JsonValue, TreeError) {
  list.key_find(fields, name)
  |> result.map_error(fn(_) {
    CorruptData(location, "required field is missing")
  })
}

fn exact(
  fields: List(#(String, JsonValue)),
  names: List(String),
  location: String,
) -> Result(Nil, TreeError) {
  require(
    list.length(fields) == list.length(names)
      && list.all(fields, fn(field) { list.contains(names, field.0) }),
    location,
    "object fields do not match the checkpoint format",
  )
}

fn item(
  values: List(JsonValue),
  index: Int,
  location: String,
) -> Result(JsonValue, TreeError) {
  case values, index {
    [first, ..], 0 -> Ok(first)
    [_, ..rest], index if index > 0 -> item(rest, index - 1, location)
    _, _ -> Error(CorruptData(location, "array item is missing"))
  }
}

fn length(
  values: List(a),
  expected: Int,
  location: String,
) -> Result(Nil, TreeError) {
  require(list.length(values) == expected, location, "array length is invalid")
}

fn index_try_map(
  values: List(a),
  decode: fn(a, Int) -> Result(b, TreeError),
) -> Result(List(b), TreeError) {
  values
  |> list.index_map(fn(value, index) { #(value, index) })
  |> list.try_map(fn(entry) { decode(entry.0, entry.1) })
}

fn require(
  valid: Bool,
  location: String,
  detail: String,
) -> Result(Nil, TreeError) {
  case valid {
    True -> Ok(Nil)
    False -> Error(CorruptData(location, detail))
  }
}

fn then(value: Result(a, e), next: fn(a) -> Result(b, e)) -> Result(b, e) {
  case value {
    Ok(value) -> next(value)
    Error(error) -> Error(error)
  }
}
