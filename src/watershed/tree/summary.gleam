//// Convert retained SharedTree summaries to sequenced native state.

import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import watershed/fluid_ids
import watershed/tree/change
import watershed/tree/codec
import watershed/tree/codec/summary as summary_codec
import watershed/tree/forest
import watershed/tree/history
import watershed/tree/types.{type TreeError, AtomId, CorruptData, SequencePoint}
import watershed/tree_kernel

const root_field_key = "rootFieldKey"

const repair_prefix = "repair-"

pub fn from_wire(
  data: summary_codec.TreeSummaryData,
  view_id: fluid_ids.StableId,
  compressor: fluid_ids.Compressor,
  sequence_number: Int,
  minimum_sequence_number: Int,
) -> Result(tree_kernel.TreeSnapshot, TreeError) {
  let summary_codec.TreeSummaryData(
    stored,
    summary_codec.ForestSummary(fields),
    summary_codec.DetachedFieldIndex(entries, max_id),
    summary_codec.EditManagerSummary(trunk, peers),
  ) = data
  let revisions =
    list.append(
      list.map(trunk, revision),
      list.flat_map(peers, fn(peer) { list.map(peer.commits, revision) }),
    )
  let revisions =
    list.append(
      revisions,
      list.flat_map(
        list.append(trunk, list.flat_map(peers, fn(peer) { peer.commits })),
        fn(entry) {
          let summary_codec.SummaryCommit(
            codec.WireCommit(_, _, changes, _),
            _,
            _,
          ) = entry
          list.flat_map(changes, fn(item) {
            case item {
              codec.DataChange(value) -> change.identity_revisions(value)
              codec.SchemaChange(_, _) -> []
            }
          })
        },
      ),
    )
  use order <- result.try(codec.identity_order(
    revisions,
    compressor,
    "summary.indexes.EditManager",
  ))
  use trunk <- result.try(
    list.try_map(trunk, fn(entry) {
      let summary_codec.SummaryCommit(_, number, index) = entry
      use number <- result.try(case number {
        Some(number) -> Ok(number)
        None ->
          Error(CorruptData(
            "summary.indexes.EditManager.trunk",
            "sequence number is missing",
          ))
      })
      use commit <- result.try(decode_commit(entry, order))
      Ok(history.SequencedCommit(
        commit,
        SequencePoint(number, case index {
          Some(index) -> index
          None -> 0
        }),
      ))
    }),
  )
  use peers <- result.try(
    list.try_map(peers, fn(peer) {
      let summary_codec.PeerBranch(session, base, commits) = peer
      use commits <- result.try(
        list.try_map(commits, fn(entry) { decode_commit(entry, order) }),
      )
      Ok(history.PeerBranch(
        session,
        case base {
          summary_codec.RootRevision -> None
          summary_codec.StableRevision(revision) -> Some(revision)
        },
        commits,
      ))
    }),
  )
  let history_snapshot =
    history.HistorySnapshot(
      history.InitialBase,
      trunk,
      peers,
      sequence_number,
      minimum_sequence_number,
    )
  use _ <- result.try(history.restore(
    history_snapshot,
    fluid_ids.local_session(compressor),
  ))
  use root <- result.try(case list.key_find(fields, root_field_key) {
    Ok([root]) -> Ok(Some(root))
    Error(Nil) -> Ok(None)
    _ -> Error(CorruptData("summary.indexes.Forest", "invalid root field"))
  })
  let tip = case list.last(trunk) {
    Ok(entry) -> Some(entry.commit.revision)
    Error(Nil) -> None
  }
  use detached <- result.try(
    list.try_map(entries, fn(entry) {
      let summary_codec.DetachedField(major, minor, root_id) = entry
      use value <- result.try(
        case list.key_find(fields, repair_prefix <> int.to_string(root_id)) {
          Ok([value]) -> Ok(value)
          _ ->
            Error(CorruptData(
              "summary.indexes.Forest."
                <> repair_prefix
                <> int.to_string(root_id),
              "detached root is missing",
            ))
        },
      )
      Ok(forest.DetachedTreeData(
        AtomId(
          case major {
            summary_codec.RootRevision -> None
            summary_codec.StableRevision(revision) -> Some(revision)
          },
          minor,
        ),
        root_id,
        tip,
        value,
      ))
    }),
  )
  tree_kernel.snapshot_from_summary(
    view_id,
    stored,
    forest.ForestData(root, detached, max_id + 1),
    history_snapshot,
    data.history,
  )
}

fn revision(entry: summary_codec.SummaryCommit) -> fluid_ids.StableId {
  let summary_codec.SummaryCommit(codec.WireCommit(revision, _, _, _), _, _) =
    entry
  revision
}

fn decode_commit(
  entry: summary_codec.SummaryCommit,
  order: change.IdentityOrder,
) -> Result(history.Commit, TreeError) {
  let summary_codec.SummaryCommit(
    codec.WireCommit(revision, originator, changes, _),
    _,
    _,
  ) = entry
  use data <- result.try(
    list.try_map(changes, fn(item) {
      case item {
        codec.DataChange(value) ->
          change.rebind_identity_order(value, order, [revision])
          |> result.map(Some)
        codec.SchemaChange(_, _) -> Ok(None)
      }
    }),
  )
  let data =
    list.flat_map(data, fn(item) {
      case item {
        Some(value) -> [value]
        None -> []
      }
    })
  use composed <- result.try(case data {
    [] -> Ok(change.empty())
    [first] -> Ok(first)
    [first, ..rest] ->
      change.compose([
        change.TaggedChange(Some(revision), None, first),
        ..list.map(rest, fn(next) { change.TaggedChange(None, None, next) })
      ])
  })
  Ok(history.Commit(revision, originator, composed))
}

pub fn to_wire(
  snapshot: tree_kernel.TreeSnapshot,
) -> Result(summary_codec.TreeSummaryData, TreeError) {
  let #(stored, data, history_snapshot) = tree_kernel.snapshot_parts(snapshot)
  let summary_codec.EditManagerSummary(original_trunk, original_peers) =
    tree_kernel.retained_wire(snapshot)
  let fields = case data.root {
    Some(root) -> [#(root_field_key, [root])]
    None -> []
  }
  let fields =
    list.append(
      fields,
      list.map(data.detached, fn(entry) {
        #(repair_prefix <> int.to_string(entry.forest_root_id), [entry.value])
      }),
    )
  let detached =
    list.map(data.detached, fn(entry) {
      summary_codec.DetachedField(
        case entry.id.revision {
          None -> summary_codec.RootRevision
          Some(revision) -> summary_codec.StableRevision(revision)
        },
        entry.id.local_id,
        entry.forest_root_id,
      )
    })
  use trunk <- result.try(
    list.try_map(history_snapshot.trunk, fn(entry) {
      let original =
        list.find(original_trunk, fn(value) {
          revision(value) == entry.commit.revision
        })
      use wire <- result.try(encode_commit(entry.commit, original))
      Ok(
        summary_codec.SummaryCommit(
          wire,
          Some(entry.point.sequence_number),
          case original {
            Ok(summary_codec.SummaryCommit(_, _, Some(_))) ->
              Some(entry.point.index_in_batch)
            _ ->
              case entry.point.index_in_batch {
                0 -> None
                index -> Some(index)
              }
          },
        ),
      )
    }),
  )
  use peers <- result.try(
    list.try_map(history_snapshot.peers, fn(peer) {
      let previous =
        list.find(original_peers, fn(value) { value.session == peer.originator })
      use commits <- result.try(
        list.try_map(peer.commits, fn(commit) {
          let original = case previous {
            Ok(branch) ->
              list.find(branch.commits, fn(value) {
                revision(value) == commit.revision
              })
            Error(Nil) -> Error(Nil)
          }
          use wire <- result.try(encode_commit(commit, original))
          Ok(summary_codec.SummaryCommit(wire, None, None))
        }),
      )
      Ok(summary_codec.PeerBranch(
        peer.originator,
        case peer.base {
          None -> summary_codec.RootRevision
          Some(revision) -> summary_codec.StableRevision(revision)
        },
        commits,
      ))
    }),
  )
  Ok(summary_codec.TreeSummaryData(
    stored,
    summary_codec.ForestSummary(fields),
    summary_codec.DetachedFieldIndex(detached, data.next_detached_root_id - 1),
    summary_codec.EditManagerSummary(trunk, peers),
  ))
}

fn encode_commit(
  commit: history.Commit,
  original: Result(summary_codec.SummaryCommit, Nil),
) -> Result(codec.WireCommit, TreeError) {
  case original {
    Error(Nil) ->
      Ok(codec.WireCommit(
        commit.revision,
        commit.originator,
        [codec.DataChange(commit.change)],
        None,
      ))
    Ok(summary_codec.SummaryCommit(
      codec.WireCommit(_, _, changes, metadata),
      _,
      _,
    )) -> {
      let original =
        list.flat_map(changes, fn(item) {
          case item {
            codec.DataChange(value) -> [value]
            codec.SchemaChange(_, _) -> []
          }
        })
      use changes <- result.try(case original {
        [only] ->
          case change.to_data(only) == change.to_data(commit.change) {
            True -> Ok(changes)
            False ->
              list.map(changes, fn(item) {
                case item {
                  codec.DataChange(_) -> codec.DataChange(commit.change)
                  other -> other
                }
              })
              |> Ok
          }
        [] -> Ok(changes)
        [first, ..rest] -> {
          use combined <- result.try(
            change.compose([
              change.TaggedChange(Some(commit.revision), None, first),
              ..list.map(rest, fn(item) {
                change.TaggedChange(None, None, item)
              })
            ]),
          )
          case change.to_data(combined) == change.to_data(commit.change) {
            True -> Ok(changes)
            False ->
              Error(CorruptData(
                "summary.indexes.EditManager",
                "cannot rewrite a rebased commit with multiple data changes",
              ))
          }
        }
      })
      Ok(codec.WireCommit(commit.revision, commit.originator, changes, metadata))
    }
  }
}
