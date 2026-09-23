import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import watershed/fluid_ids
import watershed/json_ot.{type JsonValue, VObject}
import watershed/tree/change
import watershed/tree/change_fixture_codec as codec
import watershed/tree/fixtures
import watershed/tree/forest
import watershed/tree/history
import watershed/tree/schema
import watershed/tree/types

type ChangeCatalog =
  List(#(String, change.Changeset))

type Allocation {
  Allocation(
    revision: fluid_ids.StableId,
    order: change.IdentityOrder,
    entries: codec.Revisions,
  )
}

type Allocator {
  Allocator(remaining: List(Allocation), consumed: List(Allocation))
}

type Execution {
  Execution(
    history: history.History,
    forest: forest.Forest,
    checkpoints: List(Json),
  )
}

pub fn run(input: Json) -> Result(Json, String) {
  use input <- result.try(codec.parse(input))
  use _ <- result.try(
    codec.exact(input, [
      "schema", "root", "sessions", "revisions", "changes", "schedules",
    ]),
  )
  use revisions <- result.try(
    codec.field(input, "revisions", fn(value) {
      codec.many(value, decode_revision_entry)
    }),
  )
  use _ <- result.try(unique(list.map(revisions, fn(entry) { entry.0 })))
  use _ <- result.try(unique(list.map(revisions, fn(entry) { entry.1 })))
  use identity_order <- result.try(
    change.identity_order(revisions)
    |> codec.native,
  )
  use changes <- result.try(
    codec.field(input, "changes", fn(value) {
      decode_changes(value, identity_order)
    }),
  )
  use schedules <- result.try(codec.field(input, "schedules", codec.items))
  use observations <- result.try(
    list.try_map(schedules, fn(schedule) { run_schedule(schedule, changes) }),
  )
  Ok(json.object([#("observations", codec.array(observations))]))
}

fn run_schedule(
  value: JsonValue,
  changes: ChangeCatalog,
) -> Result(Json, String) {
  use _ <- result.try(codec.exact(value, ["label", "initial", "actions"]))
  use label <- result.try(codec.field(value, "label", codec.text))
  use initial <- result.try(codec.get(value, "initial"))
  use _ <- result.try(
    codec.exact(initial, ["localSession", "schema", "forest"]),
  )
  use local_session <- result.try(codec.field(
    initial,
    "localSession",
    decode_session,
  ))
  use stored <- result.try(
    codec.field(initial, "schema", fn(value) {
      use raw <- result.try(codec.text(value))
      schema.stored_from_string(raw) |> codec.native
    }),
  )
  use initial_forest <- result.try(
    codec.field(initial, "forest", fn(value) {
      decode_initial_forest(value, stored)
    }),
  )
  use actions <- result.try(codec.field(value, "actions", codec.items))
  use execution <- result.try(
    list.try_fold(
      actions,
      Execution(history.new(local_session), initial_forest, []),
      fn(state, action) {
        use id <- result.try(codec.field(action, "id", codec.text))
        run_action(state, action, changes)
        |> result.map_error(fn(error) { label <> "/" <> id <> ": " <> error })
      },
    ),
  )
  Ok(
    json.object([
      #("label", json.string(label)),
      #("checkpoints", codec.array(list.reverse(execution.checkpoints))),
    ]),
  )
}

fn run_action(
  state: Execution,
  value: JsonValue,
  changes: ChangeCatalog,
) -> Result(Execution, String) {
  use operation <- result.try(codec.field(value, "op", codec.text))
  use id <- result.try(codec.field(value, "id", codec.text))
  use allocations <- result.try(
    codec.field(value, "allocations", fn(value) {
      codec.many(value, decode_allocation)
    }),
  )
  case operation {
    "append-local" -> {
      use _ <- result.try(
        codec.exact(value, ["id", "op", "commit", "allocations"]),
      )
      use _ <- result.try(require_no_allocations(allocations))
      use commit <- result.try(
        codec.field(value, "commit", fn(value) { decode_commit(value, changes) }),
      )
      use update <- result.try(
        history.append_local(state.history, commit)
        |> codec.native,
      )
      finish_update(state, id, operation, update, Allocator([], []), [])
    }
    "receive" -> {
      use _ <- result.try(
        codec.exact(value, [
          "id", "op", "commit", "point", "referenceSequenceNumber",
          "minimumSequenceNumber", "allocations",
        ]),
      )
      use commit <- result.try(
        codec.field(value, "commit", fn(value) { decode_commit(value, changes) }),
      )
      use point <- result.try(codec.field(value, "point", decode_point))
      use reference <- result.try(codec.field(
        value,
        "referenceSequenceNumber",
        codec.integer,
      ))
      use minimum <- result.try(codec.field(
        value,
        "minimumSequenceNumber",
        codec.integer,
      ))
      let allocator = Allocator(allocations, [])
      use #(update, allocator) <- result.try(
        history.receive(
          state.history,
          commit,
          point,
          reference,
          minimum,
          allocator,
          mint,
        )
        |> codec.native,
      )
      use _ <- result.try(require_exhausted(allocator))
      finish_update(state, id, operation, update, allocator, [])
    }
    "advance-minimum" -> {
      use _ <- result.try(
        codec.exact(value, [
          "id", "op", "sequenceNumber", "minimumSequenceNumber", "allocations",
        ]),
      )
      use sequence <- result.try(codec.field(
        value,
        "sequenceNumber",
        codec.integer,
      ))
      use minimum <- result.try(codec.field(
        value,
        "minimumSequenceNumber",
        codec.integer,
      ))
      let allocator = Allocator(allocations, [])
      use #(update, allocator) <- result.try(
        history.advance_minimum(
          state.history,
          sequence,
          minimum,
          allocator,
          mint,
        )
        |> codec.native,
      )
      use _ <- result.try(require_exhausted(allocator))
      finish_update(state, id, operation, update, allocator, [])
    }
    "snapshot-restore" -> {
      use _ <- result.try(
        codec.exact(value, ["id", "op", "localSession", "allocations"]),
      )
      use _ <- result.try(require_no_allocations(allocations))
      use local_session <- result.try(codec.field(
        value,
        "localSession",
        decode_session,
      ))
      use snapshot <- result.try(
        history.snapshot(state.history)
        |> codec.native,
      )
      use restored <- result.try(
        history.restore(snapshot, local_session)
        |> codec.native,
      )
      finish_checkpoint(
        Execution(..state, history: restored),
        id,
        operation,
        None,
        [],
        Allocator([], []),
        [#("snapshot", snapshot_json(snapshot))],
      )
    }
    "resubmit" -> {
      use _ <- result.try(
        codec.exact(value, ["id", "op", "repair", "allocations"]),
      )
      use _ <- result.try(require_no_allocations(allocations))
      use repair <- result.try(
        codec.field(value, "repair", fn(value) {
          codec.many(value, decode_repair)
        }),
      )
      use commits <- result.try(
        history.resubmit(state.history, repair)
        |> codec.native,
      )
      finish_checkpoint(state, id, operation, None, [], Allocator([], []), [
        #("resubmitted", json.array(commits, commit_json)),
      ])
    }
    _ -> Error("unknown history operation " <> operation)
  }
}

fn finish_update(
  state: Execution,
  id: String,
  operation: String,
  update: history.HistoryUpdate,
  allocator: Allocator,
  extra: List(#(String, Json)),
) -> Result(Execution, String) {
  use next_forest <- result.try(case update.delta {
    None -> Ok(state.forest)
    Some(delta) -> forest.apply_delta(state.forest, delta) |> codec.native
  })
  finish_checkpoint(
    Execution(..state, history: update.history, forest: next_forest),
    id,
    operation,
    update.delta,
    update.trimmed_revisions,
    allocator,
    extra,
  )
}

fn finish_checkpoint(
  state: Execution,
  id: String,
  operation: String,
  delta: Option(forest.Delta),
  trimmed: List(fluid_ids.StableId),
  allocator: Allocator,
  extra: List(#(String, Json)),
) -> Result(Execution, String) {
  use observed_forest <- result.try(forest_json(state.forest))
  let checkpoint =
    json.object([
      #("id", json.string(id)),
      #("operation", json.string(operation)),
      #("history", history_json(history.inspect(state.history))),
      #("delta", codec.nullable(delta, codec.delta_json)),
      #("forest", observed_forest),
      #("trimmedRevisions", json.array(trimmed, codec.revision_json)),
      #("allocator", allocator_json(allocator)),
      ..extra
    ])
  Ok(Execution(..state, checkpoints: [checkpoint, ..state.checkpoints]))
}

fn decode_changes(
  value: JsonValue,
  identity_order: change.IdentityOrder,
) -> Result(ChangeCatalog, String) {
  case value {
    VObject(entries) ->
      list.try_map(entries, fn(entry) {
        use decoded <- result.try(codec.state(entry.1, identity_order))
        Ok(#(entry.0, decoded))
      })
    _ -> Error("history changes must be an object")
  }
}

fn decode_commit(
  value: JsonValue,
  changes: ChangeCatalog,
) -> Result(history.Commit, String) {
  use _ <- result.try(codec.exact(value, ["revision", "originator", "change"]))
  use revision <- result.try(codec.field(value, "revision", codec.revision))
  use originator <- result.try(codec.field(value, "originator", decode_session))
  use name <- result.try(codec.field(value, "change", codec.text))
  use changeset <- result.try(
    list.key_find(changes, name)
    |> result.map_error(fn(_) { "unknown history change " <> name }),
  )
  Ok(history.Commit(revision, originator, changeset))
}

fn decode_revision_entry(
  value: JsonValue,
) -> Result(#(fluid_ids.StableId, Int), String) {
  use _ <- result.try(codec.exact(value, ["stable", "encoded"]))
  use stable <- result.try(codec.field(value, "stable", codec.revision))
  use encoded <- result.try(codec.field(value, "encoded", codec.integer))
  Ok(#(stable, encoded))
}

fn decode_allocation(value: JsonValue) -> Result(Allocation, String) {
  use _ <- result.try(codec.exact(value, ["revision", "identityOrder"]))
  use revision <- result.try(codec.field(value, "revision", codec.revision))
  use entries <- result.try(
    codec.field(value, "identityOrder", fn(value) {
      codec.many(value, decode_revision_entry)
    }),
  )
  use order <- result.try(change.identity_order(entries) |> codec.native)
  Ok(Allocation(revision, order, entries))
}

fn decode_repair(
  value: JsonValue,
) -> Result(#(fluid_ids.StableId, List(forest.Build)), String) {
  use _ <- result.try(codec.exact(value, ["revision", "builds"]))
  use revision <- result.try(codec.field(value, "revision", codec.revision))
  use builds <- result.try(
    codec.field(value, "builds", fn(value) { codec.many(value, codec.build) }),
  )
  Ok(#(revision, builds))
}

fn decode_point(value: JsonValue) -> Result(types.SequencePoint, String) {
  use _ <- result.try(codec.exact(value, ["sequenceNumber", "indexInBatch"]))
  use sequence_number <- result.try(codec.field(
    value,
    "sequenceNumber",
    codec.integer,
  ))
  use index_in_batch <- result.try(codec.field(
    value,
    "indexInBatch",
    codec.integer,
  ))
  Ok(types.SequencePoint(sequence_number, index_in_batch))
}

fn decode_session(value: JsonValue) -> Result(fluid_ids.SessionId, String) {
  use raw <- result.try(codec.text(value))
  fluid_ids.session_id(raw) |> result.map_error(string.inspect)
}

fn decode_initial_forest(
  value: JsonValue,
  stored: schema.StoredSchema,
) -> Result(forest.Forest, String) {
  use _ <- result.try(codec.exact(value, ["root"]))
  use root <- result.try(
    codec.field(value, "root", fn(value) { codec.optional(value, codec.tree) }),
  )
  use scope <- result.try(
    fluid_ids.stable_id("ffffffff-ffff-4fff-bfff-ffffffffffff")
    |> result.map_error(string.inspect),
  )
  forest.new(scope, stored, root) |> codec.native
}

fn mint(
  allocator: Allocator,
) -> Result(
  #(fluid_ids.StableId, change.IdentityOrder, Allocator),
  types.TreeError,
) {
  case allocator.remaining {
    [] -> Error(types.InvalidHistory("rollback allocation is exhausted"))
    [first, ..rest] ->
      Ok(#(
        first.revision,
        first.order,
        Allocator(rest, list.append(allocator.consumed, [first])),
      ))
  }
}

fn require_no_allocations(values: List(Allocation)) -> Result(Nil, String) {
  case values {
    [] -> Ok(Nil)
    _ -> Error("operation cannot allocate rollback revisions")
  }
}

fn require_exhausted(allocator: Allocator) -> Result(Nil, String) {
  case allocator.remaining {
    [] -> Ok(Nil)
    _ -> Error("operation did not consume every rollback allocation")
  }
}

fn history_json(value: history.HistoryView) -> Json {
  json.object([
    #("sequenced", snapshot_json(value.sequenced)),
    #("pending", json.array(value.pending, commit_json)),
    #("longestBranchLength", json.int(value.longest_branch_length)),
  ])
}

fn snapshot_json(value: history.HistorySnapshot) -> Json {
  json.object([
    #("base", base_json(value.base)),
    #("trunk", json.array(value.trunk, sequenced_commit_json)),
    #("peers", json.array(value.peers, peer_json)),
    #("sequenceNumber", json.int(value.sequence_number)),
    #("minimumSequenceNumber", json.int(value.minimum_sequence_number)),
  ])
}

fn base_json(value: history.HistoryBase) -> Json {
  case value {
    history.InitialBase -> json.object([#("kind", json.string("initial"))])
    history.SequencedBase(point) ->
      json.object([
        #("kind", json.string("sequenced")),
        #("point", point_json(point)),
      ])
  }
}

fn sequenced_commit_json(value: history.SequencedCommit) -> Json {
  json.object([
    #("commit", commit_json(value.commit)),
    #("point", point_json(value.point)),
  ])
}

fn peer_json(value: history.PeerBranch) -> Json {
  json.object([
    #(
      "originator",
      json.string(fluid_ids.session_id_to_string(value.originator)),
    ),
    #("base", codec.nullable(value.base, codec.revision_json)),
    #("commits", json.array(value.commits, commit_json)),
  ])
}

fn commit_json(value: history.Commit) -> Json {
  json.object([
    #("revision", codec.revision_json(value.revision)),
    #(
      "originator",
      json.string(fluid_ids.session_id_to_string(value.originator)),
    ),
    #("change", codec.state_json(value.change)),
  ])
}

fn point_json(value: types.SequencePoint) -> Json {
  json.object([
    #("sequenceNumber", json.int(value.sequence_number)),
    #("indexInBatch", json.int(value.index_in_batch)),
  ])
}

fn allocator_json(value: Allocator) -> Json {
  json.object([
    #(
      "consumed",
      json.array(value.consumed, fn(allocation) {
        json.object([
          #("revision", codec.revision_json(allocation.revision)),
          #(
            "identityOrder",
            json.array(allocation.entries, fn(entry) {
              json.object([
                #("stable", codec.revision_json(entry.0)),
                #("encoded", json.int(entry.1)),
              ])
            }),
          ),
        ])
      }),
    ),
  ])
}

fn forest_json(value: forest.Forest) -> Result(Json, String) {
  use data <- result.try(forest.export_data(value) |> codec.native)
  Ok(
    json.object([
      #("root", codec.nullable(data.root, fixtures.tree_value_to_json)),
      #("references", codec.array([])),
      #(
        "detached",
        json.array(data.detached, fn(entry) {
          json.object([
            #("id", codec.atom_json(entry.id)),
            #("forestRootId", json.int(entry.forest_root_id)),
            #(
              "latestRelevantRevision",
              codec.nullable(
                entry.latest_relevant_revision,
                codec.revision_json,
              ),
            ),
            #("value", fixtures.tree_value_to_json(entry.value)),
          ])
        }),
      ),
      #("nextDetachedRootId", json.int(data.next_detached_root_id)),
    ]),
  )
}

fn unique(values: List(a)) -> Result(Nil, String) {
  case list.length(list.unique(values)) == list.length(values) {
    True -> Ok(Nil)
    False -> Error("duplicate fixture identifier")
  }
}
