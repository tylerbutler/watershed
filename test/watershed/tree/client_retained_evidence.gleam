import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import watershed/fluid_ids
import watershed/runtime_core
import watershed/tree/client_protocol
import watershed/tree/codec
import watershed/tree/codec/summary
import watershed/tree/forest
import watershed/tree_kernel

pub fn encode(
  evidence: runtime_core.TreeRetainedSnapshot,
) -> Result(Json, String) {
  let runtime_core.TreeRetainedSnapshot(snapshot, compressor) = evidence
  use compressor <- result.try(case compressor {
    Some(compressor) -> Ok(compressor)
    None -> Error("tree retained snapshot lacks an ID compressor")
  })
  let #(_, data, _) = tree_kernel.snapshot_parts(snapshot)
  use removed <- result.try(removed_json(data.detached, compressor))
  let summary.EditManagerSummary(trunk, _) = tree_kernel.retained_wire(snapshot)
  use history <- result.try(list.try_map(trunk, commit_json(_, compressor)))
  Ok(
    json.object([
      #("removed", json.array(removed, fn(value) { value })),
      #("history", json.array(history, fn(value) { value })),
    ]),
  )
}

fn removed_json(
  entries: List(forest.DetachedTreeData),
  compressor: fluid_ids.Compressor,
) -> Result(List(Json), String) {
  list.try_map(entries, fn(entry) {
    let forest.DetachedTreeData(id, _, _, value) = entry
    use revision <- result.try(optional_revision(id.revision, compressor))
    Ok(
      json.array(
        [
          json.int(revision),
          json.int(id.local_id),
          client_protocol.encode_value(value),
        ],
        fn(value) { value },
      ),
    )
  })
}

fn commit_json(
  entry: summary.SummaryCommit,
  compressor: fluid_ids.Compressor,
) -> Result(Json, String) {
  let summary.SummaryCommit(
    codec.WireCommit(revision_id, originator, changes, _),
    _,
    _,
  ) = entry
  use revision <- result.try(stable_revision(revision_id, compressor))
  use changes <- result.try(
    codec.encode_changes(
      changes,
      codec.EncodeContext(codec.Fluid310, compressor, None),
      codec.ChangeContext(originator, Some(revision_id), codec.Summary),
    )
    |> result.map_error(string.inspect),
  )
  Ok(
    json.object([
      #("revision", json.int(revision)),
      #("originatorId", json.string(fluid_ids.session_id_to_string(originator))),
      #("changes", changes),
    ]),
  )
}

fn optional_revision(
  revision: Option(fluid_ids.StableId),
  compressor: fluid_ids.Compressor,
) -> Result(Int, String) {
  case revision {
    None -> Ok(0)
    Some(revision) -> stable_revision(revision, compressor)
  }
}

fn stable_revision(
  revision: fluid_ids.StableId,
  compressor: fluid_ids.Compressor,
) -> Result(Int, String) {
  codec.encode_stable_revision(
    revision,
    codec.EncodeContext(codec.Fluid310, compressor, None),
    "retained evidence revision",
  )
  |> result.map_error(string.inspect)
}
