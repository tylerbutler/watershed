import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import startest/expect
import watershed/fluid_ids
import watershed/json_ot.{
  type JsonValue, NInt, VArray, VNumber, VObject, VString,
}
import watershed/tree/codec
import watershed/tree/codec/summary
import watershed/tree/fixtures
import watershed/tree/runtime as tree_runtime
import watershed/tree/schema
import watershed/tree/summary as tree_summary
import watershed/tree/types
import watershed/tree_kernel
import watershed/wire/fluid_summary

fn summary_fixture(
  id: String,
) -> #(fluid_summary.SummaryEntry, fluid_ids.SessionId, fluid_ids.Compressor) {
  let assert Ok(fixtures.Case(input: input, ..)) = fixtures.load("tree-codecs")
  let assert Ok(VObject(input)) = json_ot.parse_json(json.to_string(input))
  let assert Ok(VArray(summaries)) = list.key_find(input, "summaries")
  let assert Ok(VObject(found)) =
    list.find(summaries, fn(value) {
      let assert VObject(members) = value
      list.key_find(members, "id") == Ok(VString(id))
    })
  let assert Ok(VString(session_raw)) = list.key_find(found, "session")
  let assert Ok(source_session) = fluid_ids.session_id(session_raw)
  let assert Ok(fresh_session) =
    fluid_ids.session_id("30000000-0000-4000-8000-000000000003")
  let assert Ok(VString(compressor_raw)) = list.key_find(found, "compressor")
  let #(session, compressor) = case
    fluid_ids.deserialize(json.string(compressor_raw), source_session)
  {
    Ok(value) -> #(source_session, value)
    Error(fluid_ids.SessionMismatch) -> {
      let assert Ok(value) =
        fluid_ids.deserialize(json.string(compressor_raw), fresh_session)
      #(fresh_session, value)
    }
    Error(error) -> panic as { string.inspect(error) }
  }
  let assert Ok(encoded) = list.key_find(found, "summary")
  #(decode_summary_entry(encoded), session, compressor)
}

fn decode_summary_entry(value: JsonValue) -> fluid_summary.SummaryEntry {
  let assert VObject(members) = value
  let assert Ok(VNumber(NInt(kind))) = list.key_find(members, "type")
  case kind {
    1 -> {
      let assert Ok(VObject(tree)) = list.key_find(members, "tree")
      fluid_summary.SummaryTree(
        list.map(tree, fn(entry) { #(entry.0, decode_summary_entry(entry.1)) }),
      )
    }
    2 -> {
      let assert Ok(VString(content)) = list.key_find(members, "content")
      fluid_summary.SummaryBlob(<<content:utf8>>)
    }
    _ -> panic as "unsupported fixture summary entry"
  }
}

pub fn shared_tree_summary_decodes_initial_bootstrap_test() {
  let #(entry, session, compressor) = summary_fixture("initial")
  let assert Ok(summary.TreeSummaryData(
    _,
    summary.ForestSummary(fields),
    summary.DetachedFieldIndex([], 0),
    summary.EditManagerSummary(
      [
        summary.SummaryCommit(
          codec.WireCommit(
            _,
            _,
            [
              codec.SchemaChange(codec.EmptySchema, codec.FixedSchema(_)),
              codec.DataChange(_),
              codec.SchemaChange(codec.FixedSchema(_), codec.FixedSchema(_)),
            ],
            None,
          ),
          Some(2),
          None,
        ),
      ],
      [],
    ),
  )) =
    summary.decode(
      entry,
      None,
      session,
      codec.DecodeContext(codec.Fluid310, compressor),
    )
  list.map(fields, fn(field) { field.0 })
  |> expect.to_equal(["rootFieldKey"])
}

pub fn shared_tree_summary_restores_and_reexports_retained_history_test() {
  let #(entry, session, compressor) = summary_fixture("settled-detached")
  let context = codec.DecodeContext(codec.Fluid310, compressor)
  let assert Ok(decoded) = summary.decode(entry, None, session, context)
  let assert Ok(view_id) =
    fluid_ids.stable_id("00000000-0000-4000-8000-000000000012")
  let assert Ok(snapshot) =
    tree_summary.from_wire(decoded, view_id, compressor, 8, 7)
  let #(_, data, history) = tree_kernel.snapshot_parts(snapshot)
  data.next_detached_root_id |> expect.to_equal(5)
  history.sequence_number |> expect.to_equal(8)
  history.minimum_sequence_number |> expect.to_equal(7)
  list.length(history.peers) |> expect.to_equal(1)
  let assert Ok(output) = tree_summary.to_wire(snapshot)
  output.forest |> expect.to_equal(decoded.forest)
  output.detached |> expect.to_equal(decoded.detached)
  output.history |> expect.to_equal(decoded.history)
}

pub fn shared_tree_summary_restores_initial_schema_commit_test() {
  let #(entry, session, compressor) = summary_fixture("initial")
  let assert Ok(decoded) =
    summary.decode(
      entry,
      None,
      session,
      codec.DecodeContext(codec.Fluid310, compressor),
    )
  let assert Ok(view_id) =
    fluid_ids.stable_id("00000000-0000-4000-8000-000000000012")
  let assert Ok(snapshot) =
    tree_summary.from_wire(decoded, view_id, compressor, 2, 0)
  let assert Ok(view) =
    schema.view_from_json(schema.stored_to_json(decoded.schema))
  let assert Ok(state) =
    tree_runtime.restore(snapshot, view_id, view, compressor)
  let assert Ok(resnapshot) = tree_kernel.snapshot(state)
  let assert Ok(written) = tree_summary.to_wire(resnapshot)
  written |> expect.to_equal(decoded)
}

pub fn shared_tree_summary_decodes_settled_history_and_repairs_test() {
  let #(entry, session, compressor) = summary_fixture("settled-detached")
  let context = codec.DecodeContext(codec.Fluid310, compressor)
  let decoded = case summary.decode(entry, None, session, context) {
    Ok(value) -> value
    Error(error) -> panic as { string.inspect(error) }
  }
  let summary.TreeSummaryData(
    stored,
    summary.ForestSummary(fields),
    summary.DetachedFieldIndex(detached, max_id),
    summary.EditManagerSummary(trunk, branches),
  ) = decoded
  max_id |> expect.to_equal(4)
  list.map(trunk, fn(commit) {
    let summary.SummaryCommit(_, sequence, index) = commit
    #(sequence, index)
  })
  |> expect.to_equal([#(Some(4), None), #(Some(6), None)])
  list.length(branches) |> expect.to_equal(1)
  let #(base, commits) = case list.first(branches) {
    Ok(summary.PeerBranch(_, base, commits)) -> #(base, commits)
    Error(_) -> panic as "missing peer branch"
  }
  base |> expect.to_equal(summary.RootRevision)
  list.map(commits, fn(commit) {
    let summary.SummaryCommit(_, sequence, index) = commit
    #(sequence, index)
  })
  |> expect.to_equal([#(None, None)])
  list.map(fields, fn(field) { field.0 })
  |> expect.to_equal(["rootFieldKey", "repair-2", "repair-4"])
  list.map(detached, fn(item) { #(item.minor, item.root) })
  |> expect.to_equal([#(1, 2), #(1, 4)])

  let encoded = case
    summary.encode(
      decoded,
      session,
      codec.EncodeContext(codec.Fluid310, compressor, Some(stored)),
    )
  {
    Ok(value) -> value
    Error(error) -> panic as { string.inspect(error) }
  }
  summary.decode(encoded, None, session, context)
  |> expect.to_equal(Ok(decoded))
}

pub fn shared_tree_summary_decodes_grouped_detached_ranges_test() {
  let assert Ok(owner) =
    fluid_ids.session_id("10000000-0000-4000-8000-000000000001")
  let assert Ok(#(compressor, _)) = fluid_ids.new(owner) |> fluid_ids.generate
  let assert #(compressor, Some(range)) =
    fluid_ids.take_creation_range(compressor)
  let assert Ok(compressor) = fluid_ids.finalize(compressor, range)
  let context = codec.DecodeContext(codec.Fluid310, compressor)
  let assert Ok(summary.DetachedFieldIndex(entries, 3)) =
    summary.decode_detached(
      raw_json("{\"version\":2,\"data\":[[0,[[1,2],[2,3]]]],\"maxId\":3}"),
      owner,
      context,
    )
  list.map(entries, fn(entry) { #(entry.minor, entry.root) })
  |> expect.to_equal([#(1, 2), #(2, 3)])
}

pub fn shared_tree_summary_rejects_invalid_detached_index_test() {
  let assert Ok(owner) =
    fluid_ids.session_id("10000000-0000-4000-8000-000000000001")
  let assert Ok(#(compressor, _)) = fluid_ids.new(owner) |> fluid_ids.generate
  let context = codec.DecodeContext(codec.Fluid310, compressor)
  let assert Error(_) =
    summary.decode_detached(
      raw_json("{\"version\":2,\"data\":[[-1,0,1]],\"maxId\":1}"),
      owner,
      context,
    )
  let assert Error(_) =
    summary.decode_detached(
      raw_json(
        "{\"version\":2,\"data\":[[\"root\",0,2],[\"root\",1,2]],\"maxId\":2}",
      ),
      owner,
      context,
    )
  Nil
}

pub fn shared_tree_summary_rejects_handles_and_wrong_versions_test() {
  let assert Ok(owner) =
    fluid_ids.session_id("10000000-0000-4000-8000-000000000001")
  let assert Ok(#(compressor, _)) = fluid_ids.new(owner) |> fluid_ids.generate
  let assert Error(_) =
    summary.decode(
      fluid_summary.SummaryHandle("/indexes", fluid_summary.TreeHandle),
      None,
      owner,
      codec.DecodeContext(codec.Fluid310, compressor),
    )
  let #(entry, session, compressor) = summary_fixture("initial")
  let invalid = replace_forest_metadata(entry, "{\"version\":2}")
  let assert Error(_) =
    summary.decode(
      invalid,
      None,
      session,
      codec.DecodeContext(codec.Fluid310, compressor),
    )
  Nil
}

pub fn shared_tree_summary_accepts_absent_optional_root_test() {
  let assert Ok(owner) =
    fluid_ids.session_id("10000000-0000-4000-8000-000000000001")
  let compressor = fluid_ids.new(owner)
  let assert Ok(stored) =
    schema.stored_from_string(
      "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}}},\"root\":{\"kind\":\"Optional\",\"types\":[\"com.fluidframework.leaf.string\"]}}",
    )
  let value =
    summary.TreeSummaryData(
      stored,
      summary.ForestSummary([]),
      summary.DetachedFieldIndex([], 0),
      summary.EditManagerSummary([], []),
    )
  let assert Ok(encoded) =
    summary.encode(
      value,
      owner,
      codec.EncodeContext(codec.Fluid310, compressor, Some(stored)),
    )
  summary.decode(
    encoded,
    None,
    owner,
    codec.DecodeContext(codec.Fluid310, compressor),
  )
  |> expect.to_equal(Ok(value))
}

pub fn shared_tree_summary_rejects_missing_and_extra_repairs_test() {
  let assert Ok(owner) =
    fluid_ids.session_id("10000000-0000-4000-8000-000000000001")
  let compressor = fluid_ids.new(owner)
  let assert Ok(stored) =
    schema.stored_from_string(
      "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}}},\"root\":{\"kind\":\"Optional\",\"types\":[\"com.fluidframework.leaf.string\"]}}",
    )
  let context = codec.EncodeContext(codec.Fluid310, compressor, Some(stored))
  let missing =
    summary.TreeSummaryData(
      stored,
      summary.ForestSummary([]),
      summary.DetachedFieldIndex(
        [
          summary.DetachedField(summary.RootRevision, 0, 1),
        ],
        1,
      ),
      summary.EditManagerSummary([], []),
    )
  let assert Error(_) = summary.encode(missing, owner, context)
  let extra =
    summary.TreeSummaryData(
      stored,
      summary.ForestSummary([
        #("repair-1", [types.StringValue("orphan")]),
      ]),
      summary.DetachedFieldIndex([], 1),
      summary.EditManagerSummary([], []),
    )
  let assert Error(_) = summary.encode(extra, owner, context)
  Nil
}

pub fn shared_tree_summary_preserves_batch_positions_and_metadata_test() {
  let #(entry, session, compressor) = summary_fixture("settled-detached")
  let decode_context = codec.DecodeContext(codec.Fluid310, compressor)
  let assert Ok(summary.TreeSummaryData(
    stored,
    _,
    _,
    summary.EditManagerSummary([first, second], branches),
  )) = summary.decode(entry, None, session, decode_context)
  let summary.SummaryCommit(first_commit, _, _) = first
  let codec.WireCommit(revision, originator, changes, _) = first_commit
  let metadata =
    codec.CustomMetadata(
      Some(json.object([#("source", json.string("native"))])),
      [codec.CustomMetadata(None, [])],
    )
  let history =
    summary.EditManagerSummary(
      [
        summary.SummaryCommit(
          codec.WireCommit(revision, originator, changes, Some(metadata)),
          Some(6),
          Some(0),
        ),
        summary.SummaryCommit(second.commit, Some(6), Some(1)),
      ],
      branches,
    )
  let encode_context =
    codec.EncodeContext(codec.Fluid310, compressor, Some(stored))
  let assert Ok(encoded) = summary.encode_edit_manager(history, encode_context)
  summary.decode_edit_manager(encoded, decode_context)
  |> expect.to_equal(Ok(history))

  let invalid =
    summary.EditManagerSummary(
      [
        summary.SummaryCommit(first_commit, Some(6), None),
        summary.SummaryCommit(second.commit, Some(6), Some(0)),
      ],
      branches,
    )
  let assert Error(_) = summary.encode_edit_manager(invalid, encode_context)
  Nil
}

pub fn shared_tree_summary_peer_base_uses_edit_manager_revision_codec_test() {
  let assert Ok(owner) =
    fluid_ids.session_id("10000000-0000-4000-8000-000000000001")
  let assert Ok(peer) =
    fluid_ids.session_id("20000000-0000-4000-8000-000000000002")
  let assert Ok(#(compressor, local)) =
    fluid_ids.new(owner) |> fluid_ids.generate
  let assert #(compressor, Some(range)) =
    fluid_ids.take_creation_range(compressor)
  let assert Ok(compressor) = fluid_ids.finalize(compressor, range)
  let assert Ok(revision) = fluid_ids.decompress(compressor, local)
  let commit =
    summary.SummaryCommit(
      codec.WireCommit(revision, owner, [], None),
      Some(1),
      None,
    )
  let history =
    summary.EditManagerSummary([commit], [
      summary.PeerBranch(peer, summary.StableRevision(revision), []),
    ])
  let encode_context = codec.EncodeContext(codec.Fluid310, compressor, None)
  let assert Ok(encoded) = summary.encode_edit_manager(history, encode_context)
  json.to_string(encoded)
  |> string.contains("\"base\":0")
  |> expect.to_be_true
  summary.decode_edit_manager(
    encoded,
    codec.DecodeContext(codec.Fluid310, compressor),
  )
  |> expect.to_equal(Ok(history))
}

pub fn shared_tree_summary_finalized_detached_major_uses_op_space_test() {
  let assert Ok(owner) =
    fluid_ids.session_id("10000000-0000-4000-8000-000000000001")
  let assert Ok(#(compressor, local)) =
    fluid_ids.new(owner) |> fluid_ids.generate
  let assert #(compressor, Some(range)) =
    fluid_ids.take_creation_range(compressor)
  let assert Ok(compressor) = fluid_ids.finalize(compressor, range)
  let assert Ok(revision) = fluid_ids.decompress(compressor, local)
  let detached =
    summary.DetachedFieldIndex(
      [summary.DetachedField(summary.StableRevision(revision), 0, 1)],
      1,
    )
  let assert Ok(encoded) =
    summary.encode_detached(
      detached,
      owner,
      codec.EncodeContext(codec.Fluid310, compressor, None),
    )
  json.to_string(encoded)
  |> string.contains("\"data\":[[0,0,1]]")
  |> expect.to_be_true
  summary.decode_detached(
    encoded,
    owner,
    codec.DecodeContext(codec.Fluid310, compressor),
  )
  |> expect.to_equal(Ok(detached))
}

pub fn shared_tree_summary_rejects_peer_base_missing_from_trunk_test() {
  let assert Ok(owner) =
    fluid_ids.session_id("10000000-0000-4000-8000-000000000001")
  let assert Ok(peer) =
    fluid_ids.session_id("20000000-0000-4000-8000-000000000002")
  let assert Ok(#(compressor, local)) =
    fluid_ids.new(owner) |> fluid_ids.generate
  let assert #(compressor, Some(range)) =
    fluid_ids.take_creation_range(compressor)
  let assert Ok(compressor) = fluid_ids.finalize(compressor, range)
  let assert Ok(revision) = fluid_ids.decompress(compressor, local)
  let history =
    summary.EditManagerSummary([], [
      summary.PeerBranch(peer, summary.StableRevision(revision), []),
    ])
  let assert Error(_) =
    summary.encode_edit_manager(
      history,
      codec.EncodeContext(codec.Fluid310, compressor, None),
    )
  let raw =
    "{\"trunk\":[],\"branches\":[[\""
    <> fluid_ids.session_id_to_string(peer)
    <> "\",{\"base\":0,\"commits\":[]}]],\"version\":7}"
  let assert Error(_) =
    summary.decode_edit_manager(
      raw_json(raw),
      codec.DecodeContext(codec.Fluid310, compressor),
    )
  Nil
}

pub fn shared_tree_summary_rejects_singleton_sequence_bounds_test() {
  let assert Ok(owner) =
    fluid_ids.session_id("10000000-0000-4000-8000-000000000001")
  let assert Ok(#(compressor, local)) =
    fluid_ids.new(owner) |> fluid_ids.generate
  let assert #(compressor, Some(range)) =
    fluid_ids.take_creation_range(compressor)
  let assert Ok(compressor) = fluid_ids.finalize(compressor, range)
  let assert Ok(revision) = fluid_ids.decompress(compressor, local)
  let commit = codec.WireCommit(revision, owner, [], None)
  let context = codec.EncodeContext(codec.Fluid310, compressor, None)
  let unsafe_sequence = 9_007_199_254_740_991 + 1
  let assert Error(_) =
    summary.encode_edit_manager(
      summary.EditManagerSummary(
        [
          summary.SummaryCommit(commit, Some(unsafe_sequence), None),
        ],
        [],
      ),
      context,
    )
  let assert Error(_) =
    summary.encode_edit_manager(
      summary.EditManagerSummary(
        [
          summary.SummaryCommit(commit, Some(1), Some(-1)),
        ],
        [],
      ),
      context,
    )
  Nil
}

fn raw_json(raw: String) -> json.Json {
  let assert Ok(value) = json_ot.parse_json(raw)
  json_ot.to_json(value)
}

fn replace_forest_metadata(
  entry: fluid_summary.SummaryEntry,
  metadata: String,
) -> fluid_summary.SummaryEntry {
  let assert fluid_summary.SummaryTree(root) = entry
  let assert Ok(fluid_summary.SummaryTree(indexes)) =
    list.key_find(root, "indexes")
  let assert Ok(fluid_summary.SummaryTree(forest)) =
    list.key_find(indexes, "Forest")
  let forest =
    list.map(forest, fn(entry) {
      case entry.0 {
        ".metadata" -> #(entry.0, fluid_summary.SummaryBlob(<<metadata:utf8>>))
        _ -> entry
      }
    })
  let indexes =
    list.map(indexes, fn(entry) {
      case entry.0 {
        "Forest" -> #(entry.0, fluid_summary.SummaryTree(forest))
        _ -> entry
      }
    })
  fluid_summary.SummaryTree(
    list.map(root, fn(entry) {
      case entry.0 {
        "indexes" -> #(entry.0, fluid_summary.SummaryTree(indexes))
        _ -> entry
      }
    }),
  )
}
