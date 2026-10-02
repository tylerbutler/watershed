import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import spillway/types as spillway_types
import startest/expect
import watershed/channel
import watershed/fluid_ids
import watershed/runtime_core
import watershed/tree/change
import watershed/tree/fixtures
import watershed/tree/identifier_fixture
import watershed/tree/runtime_fixture
import watershed/tree/shared_change
import watershed/tree/summary_fixture
import watershed/tree/transaction
import watershed/tree/types
import watershed/tree_kernel
import watershed/wire
import watershed/wire/fluid_document
import watershed/wire/fluid_summary

fn array(values: List(json.Json)) -> json.Json {
  json.array(values, fn(value) { value })
}

fn summary_fixture_input(bytes: String) -> json.Json {
  json.object([
    #(
      "previousSnapshot",
      json.object([
        #(
          "version",
          json.object([
            #("id", json.string("root")),
            #("treeId", json.string("root")),
          ]),
        ),
        #(
          "tree",
          json.object([
            #("id", json.string("root")),
            #("blobs", json.object([])),
            #("trees", json.object([])),
          ]),
        ),
        #("blobs", json.object([])),
        #("blobEncoding", json.string("base64")),
      ]),
    ),
    #(
      "scenarios",
      array([
        json.object([
          #("label", json.string("snapshot-entries")),
        ]),
        json.object([
          #("label", json.string("emitted-entries")),
          #(
            "summary",
            array([
              json.object([
                #("name", json.string("binary")),
                #("kind", json.string("blob")),
                #("bytes", json.string(bytes)),
              ]),
            ]),
          ),
        ]),
      ]),
    ),
  ])
}

fn summary_fixture_scenarios(scenarios: List(json.Json)) -> json.Json {
  json.object([
    #(
      "previousSnapshot",
      json.object([
        #(
          "version",
          json.object([
            #("id", json.string("root")),
            #("treeId", json.string("root")),
          ]),
        ),
        #(
          "tree",
          json.object([
            #("id", json.string("root")),
            #("blobs", json.object([#("blob", json.string("blob-id"))])),
            #("trees", json.object([])),
          ]),
        ),
        #("blobs", json.object([#("blob-id", json.string("AQ=="))])),
        #("blobEncoding", json.string("base64")),
      ]),
    ),
    #("scenarios", array(scenarios)),
  ])
}

fn refusal_scenario(label: String, path: String, kind: String) -> json.Json {
  json.object([
    #("label", json.string(label)),
    #(
      "summary",
      array([
        json.object([
          #("name", json.string("copy")),
          #("kind", json.string("handle")),
          #("handleKind", json.string(kind)),
          #("path", json.string(path)),
        ]),
      ]),
    ),
  ])
}

fn identifier_core(client_id: String, session_id: String) -> runtime_core.Core {
  let assert Ok(session) = fluid_ids.session_id(session_id)
  let assert Ok(view) =
    fluid_ids.stable_id("90000000-0000-4000-8000-000000000009")
  let assert Ok(summary) =
    fluid_document.initial_tree(
      identifier_fixture.full_stored(),
      Some(
        identifier_fixture.full_root(
          identifier_fixture.point("child", "child"),
          [identifier_fixture.point("existing", "existing")],
          [],
          [],
        ),
      ),
      session,
      view,
    )
  let bootstrapped =
    runtime_core.bootstrap_document(
      runtime_fixture.connected(client_id, [], 0),
      summary,
    )
    |> expect.to_be_ok()
  case bootstrapped {
    runtime_core.Complete(core) -> core
    runtime_core.MissingPrefix(..) ->
      panic as "initial identifier summary requested a missing prefix"
  }
}

fn pending_summary(core: runtime_core.Core) -> fluid_document.DocumentSummary {
  let channels = runtime_core.summary_channels(core) |> expect.to_be_ok()
  case core.persistence {
    Some(previous) -> {
      fluid_document.capture(
        previous,
        channels,
        core.compressor,
        fluid_document.CaptureRouting(
          dict.to_list(core.routing.aliases),
          dict.to_list(core.routing.datastores),
          dict.to_list(core.routing.channel_attributes),
        ),
      )
      |> expect.to_be_ok()
    }
    None -> {
      fluid_document.native(
        core.last_seen_sequence_number,
        core.minimum_sequence_number,
        runtime_core.summary_members(core),
        channels,
      )
      |> expect.to_be_ok()
    }
  }
}

fn load_summary(
  summary: fluid_document.DocumentSummary,
  client_id: String,
  session_id: String,
  view_id: String,
) -> runtime_core.Core {
  let encoded = fluid_document.encode(summary) |> expect.to_be_ok()
  let assert Ok(session) = fluid_ids.session_id(session_id)
  let assert Ok(view) = fluid_ids.stable_id(view_id)
  let decoded =
    fluid_document.decode(encoded, None, session, view) |> expect.to_be_ok()
  case
    runtime_core.bootstrap_document(
      runtime_fixture.connected(
        client_id,
        [],
        fluid_document.sequence_number(decoded),
      ),
      decoded,
    )
  {
    Ok(runtime_core.Complete(core)) -> core
    Ok(runtime_core.MissingPrefix(..)) ->
      panic as "summary reload requested a missing prefix"
    Error(error) ->
      panic as { "summary reload failed: " <> string.inspect(error) }
  }
}

fn sequenced(
  outbound: wire.OutboundOperation,
  client_id: String,
  sequence_number: Int,
) -> spillway_types.SequencedDocumentMessage {
  let contents =
    json.parse(json.to_string(outbound.contents), decode.dynamic)
    |> expect.to_be_ok()
  let metadata = case outbound.metadata {
    None -> None
    Some(value) -> {
      let value =
        json.parse(json.to_string(value), decode.dynamic) |> expect.to_be_ok()
      Some(value)
    }
  }
  spillway_types.SequencedDocumentMessage(
    client_id: Some(client_id),
    sequence_number: sequence_number,
    minimum_sequence_number: 0,
    client_sequence_number: outbound.client_sequence_number,
    reference_sequence_number: outbound.reference_sequence_number,
    message_type: outbound.operation_type,
    contents: contents,
    metadata: metadata,
    server_metadata: None,
    origin: None,
    traces: None,
    timestamp: 0,
    data: None,
  )
}

fn tree(core: runtime_core.Core) -> tree_kernel.TreeState {
  case dict.get(core.channels, "A/_C") {
    Ok(channel.TreeState(state)) -> state
    Ok(_) -> panic as "summary fixture channel is not a tree"
    Error(_) -> panic as "summary fixture tree channel is missing"
  }
}

fn latest_violation_count(core: runtime_core.Core) -> Int {
  let assert Ok(entry) =
    tree_kernel.history_view(tree(core)).sequenced.trunk
    |> list.reverse
    |> list.first
  shared_change.to_changes(entry.commit.change)
  |> list.fold(0, fn(count, item) {
    case item {
      shared_change.DataChange(value) ->
        count + change.to_data(value).constraint_violation_count
      shared_change.SchemaChange(_, _, _) -> count
    }
  })
}

fn commit_insert_transaction(
  core: runtime_core.Core,
) -> #(runtime_core.Core, wire.OutboundOperation) {
  let view = identifier_fixture.full_view()
  let active =
    runtime_core.begin_tree_transaction(core, "A/_C", view, [])
    |> expect.to_be_ok()
  let #(active, edit_events, edit_outbound) =
    runtime_core.submit_tree_edits_view(active, "A/_C", view, [
      types.ArrayInsert(["left"], 1, [
        types.ObjectValue(identifier_fixture.point_type, [
          #("label", types.StringValue("tail")),
        ]),
      ]),
      types.SetField(["left", "1", "label"], types.StringValue("tail-final")),
    ])
    |> expect.to_be_ok()
  edit_events |> expect.to_equal([])
  edit_outbound |> expect.to_equal([])
  let #(pending, commit_events, commit_outbound) =
    runtime_core.commit_tree_transaction(active, "A/_C")
    |> expect.to_be_ok()
  list.length(commit_events) |> expect.to_equal(1)
  list.length(commit_outbound) |> expect.to_equal(1)
  let outbound = commit_outbound |> list.first |> expect.to_be_ok()
  #(pending, outbound)
}

fn commit_constrained_transaction(
  core: runtime_core.Core,
) -> #(runtime_core.Core, wire.OutboundOperation) {
  let view = identifier_fixture.full_view()
  let active =
    runtime_core.begin_tree_transaction(core, "A/_C", view, [["left", "0"]])
    |> expect.to_be_ok()
  let #(active, edit_events, edit_outbound) =
    runtime_core.submit_tree_edits_view(active, "A/_C", view, [
      types.SetField(
        ["left", "0", "label"],
        types.StringValue("constrained-tail"),
      ),
    ])
    |> expect.to_be_ok()
  edit_events |> expect.to_equal([])
  edit_outbound |> expect.to_equal([])
  let #(pending, commit_events, commit_outbound) =
    runtime_core.commit_tree_transaction(active, "A/_C")
    |> expect.to_be_ok()
  list.length(commit_events) |> expect.to_equal(1)
  list.length(commit_outbound) |> expect.to_equal(1)
  let outbound = commit_outbound |> list.first |> expect.to_be_ok()
  #(pending, outbound)
}

fn continue_editing(core: runtime_core.Core, sequence_number: Int) {
  let view = identifier_fixture.full_view()
  let before = tree_kernel.reference_at(tree(core), ["child"])
  let active =
    runtime_core.begin_tree_transaction(core, "A/_C", view, [])
    |> expect.to_be_ok()
  let #(active, edit_events, edit_outbound) =
    runtime_core.submit_tree_edits_view(active, "A/_C", view, [
      types.SetField(["child", "label"], types.StringValue("continued")),
    ])
    |> expect.to_be_ok()
  edit_events |> expect.to_equal([])
  edit_outbound |> expect.to_equal([])
  let #(pending, commit_events, commit_outbound) =
    runtime_core.commit_tree_transaction(active, "A/_C")
    |> expect.to_be_ok()
  list.length(commit_events) |> expect.to_equal(1)
  list.length(commit_outbound) |> expect.to_equal(1)
  let outbound = commit_outbound |> list.first |> expect.to_be_ok()
  let #(settled, received) =
    runtime_core.handle_sequenced(
      pending,
      sequenced(outbound, pending.client_id, sequence_number),
    )
    |> expect.to_be_ok()
  received.events |> expect.to_equal([])
  runtime_core.tree_read(settled, "A/_C", ["child", "label"])
  |> expect.to_equal(Ok(Some(types.StringValue("continued"))))
  tree_kernel.reference_at(tree(settled), ["child"])
  |> expect.to_equal(before)
}

pub fn identifier_pending_transaction_keeps_sequenced_summary_test() {
  let base =
    identifier_fixture.state(
      identifier_fixture.full_stored(),
      identifier_fixture.full_view(),
      identifier_fixture.full_root(
        identifier_fixture.point("child", "child"),
        [identifier_fixture.point("existing", "existing")],
        [],
        [],
      ),
    )
  let assert Ok(sequenced) = tree_kernel.snapshot(base)
  let assert Ok(open) =
    transaction.begin(base, fluid_ids.new(identifier_fixture.session()), [])
  let assert Ok(open) =
    transaction.apply_edit(
      open,
      types.ArrayInsert(["left"], 1, [
        types.ObjectValue(identifier_fixture.point_type, [
          #("label", types.StringValue("pending")),
        ]),
      ]),
    )
  let assert Ok(reference) =
    tree_kernel.reference_at(transaction.state(open), ["left", "1"])
  let assert Ok(identifier) =
    tree_kernel.read(transaction.state(open), ["left", "1", "id"])
  let assert Ok(open) =
    transaction.apply_edit(
      open,
      types.SetField(["left", "1", "label"], types.StringValue("pending-final")),
    )
  let assert Ok(#(transaction.Commit(pending, _, _), _)) =
    transaction.finish(open)
  tree_kernel.read(pending, ["left", "1", "id"])
  |> expect.to_equal(Ok(identifier))
  tree_kernel.reference_at(pending, ["left", "1"])
  |> expect.to_equal(Ok(reference))
  tree_kernel.history_view(pending).pending
  |> list.length
  |> expect.to_equal(1)
  tree_kernel.snapshot(pending) |> expect.to_equal(Ok(sequenced))
}

pub fn pending_transaction_summary_replays_tail_and_continues_test() {
  let writer = identifier_core("writer", "30000000-0000-4000-8000-000000000003")
  let #(pending, outbound) = commit_insert_transaction(writer)
  let summary = pending_summary(pending)
  let fresh =
    load_summary(
      summary,
      "reader",
      "50000000-0000-4000-8000-000000000005",
      "60000000-0000-4000-8000-000000000006",
    )
  runtime_core.tree_read(fresh, "A/_C", ["left", "1"])
  |> expect.to_equal(Ok(None))
  tree_kernel.history_view(tree(fresh)).sequenced.trunk
  |> expect.to_equal([])

  let #(after_tail, received) =
    runtime_core.handle_sequenced(
      fresh,
      sequenced(outbound, pending.client_id, 1),
    )
    |> expect.to_be_ok()
  received.events
  |> expect.to_equal([
    #("A/_C", channel.TreeEvent(tree_kernel.TreeChanged(False))),
  ])
  runtime_core.tree_read(after_tail, "A/_C", ["left", "1", "label"])
  |> expect.to_equal(Ok(Some(types.StringValue("tail-final"))))
  tree_kernel.history_view(tree(after_tail)).sequenced.trunk
  |> list.length
  |> expect.to_equal(1)
  continue_editing(after_tail, 2)
}

pub fn explicitly_violated_transaction_tail_continues_test() {
  let writer = identifier_core("writer", "30000000-0000-4000-8000-000000000003")
  let remover =
    identifier_core("remover", "50000000-0000-4000-8000-000000000005")
  let #(pending, _) = commit_constrained_transaction(writer)
  let assert Ok(#(remover, _, [removal])) =
    runtime_core.submit_tree_edits(remover, "A/_C", [
      types.ArrayRemove(["left"], 0, 1),
    ])
  let assert Ok(#(violated, remote)) =
    runtime_core.handle_sequenced(
      pending,
      sequenced(removal, remover.client_id, 1),
    )
  remote.events
  |> expect.to_equal([
    #("A/_C", channel.TreeEvent(tree_kernel.TreeChanged(False))),
  ])
  let assert Ok(#(violated, [tail])) = runtime_core.resubmit(violated)
  let summary = pending_summary(violated)
  let fresh =
    load_summary(
      summary,
      "reader",
      "70000000-0000-4000-8000-000000000007",
      "80000000-0000-4000-8000-000000000008",
    )
  runtime_core.tree_read(fresh, "A/_C", ["left", "0"])
  |> expect.to_equal(Ok(None))
  let assert Ok(#(after_tail, received)) =
    runtime_core.handle_sequenced(fresh, sequenced(tail, violated.client_id, 2))
  received.events |> expect.to_equal([])
  latest_violation_count(after_tail) |> expect.to_equal(1)
  runtime_core.tree_read(after_tail, "A/_C", ["left", "0"])
  |> expect.to_equal(Ok(None))
  continue_editing(after_tail, 3)
}

pub fn pending_transaction_tail_becomes_explicitly_violated_test() {
  let writer = identifier_core("writer", "30000000-0000-4000-8000-000000000003")
  let remover =
    identifier_core("remover", "50000000-0000-4000-8000-000000000005")
  let #(pending, tail) = commit_constrained_transaction(writer)
  let assert Ok(#(remover, _, [removal])) =
    runtime_core.submit_tree_edits(remover, "A/_C", [
      types.ArrayRemove(["left"], 0, 1),
    ])
  let fresh =
    load_summary(
      pending_summary(pending),
      "reader",
      "70000000-0000-4000-8000-000000000007",
      "80000000-0000-4000-8000-000000000008",
    )
  let assert Ok(#(after_removal, removed)) =
    runtime_core.handle_sequenced(
      fresh,
      sequenced(removal, remover.client_id, 1),
    )
  removed.events
  |> expect.to_equal([
    #("A/_C", channel.TreeEvent(tree_kernel.TreeChanged(False))),
  ])
  let assert Ok(#(after_tail, received)) =
    runtime_core.handle_sequenced(
      after_removal,
      sequenced(tail, pending.client_id, 2),
    )
  received.events |> expect.to_equal([])
  latest_violation_count(after_tail) |> expect.to_equal(1)
  runtime_core.tree_read(after_tail, "A/_C", ["left", "0"])
  |> expect.to_equal(Ok(None))
  continue_editing(after_tail, 3)
}

pub fn shared_tree_summary_resolves_binary_blob_from_previous_test() -> Nil {
  let previous =
    fluid_summary.SummaryTree([
      #("binary", fluid_summary.SummaryBlob(<<0, 255, 128>>)),
    ])

  fluid_summary.resolve(
    fluid_summary.SummaryTree([
      #(
        "copy",
        fluid_summary.SummaryHandle("/binary", fluid_summary.BlobHandle),
      ),
    ]),
    Some(previous),
  )
  |> expect.to_equal(
    Ok(
      fluid_summary.SummaryTree([
        #("copy", fluid_summary.SummaryBlob(<<0, 255, 128>>)),
      ]),
    ),
  )
}

pub fn shared_tree_summary_reports_missing_and_wrong_references_test() -> Nil {
  let previous =
    fluid_summary.SummaryTree([
      #("blob", fluid_summary.SummaryBlob(<<1>>)),
      #("tree", fluid_summary.SummaryTree([])),
    ])

  fluid_summary.resolve(
    fluid_summary.SummaryHandle("/blob", fluid_summary.BlobHandle),
    None,
  )
  |> expect.to_equal(Error(fluid_summary.MissingEntry("/blob")))

  fluid_summary.resolve(
    fluid_summary.SummaryHandle("/missing", fluid_summary.BlobHandle),
    Some(previous),
  )
  |> expect.to_equal(Error(fluid_summary.MissingEntry("/missing")))

  fluid_summary.resolve(
    fluid_summary.SummaryHandle("/tree", fluid_summary.BlobHandle),
    Some(previous),
  )
  |> expect.to_equal(
    Error(fluid_summary.WrongKind("/tree", fluid_summary.BlobHandle)),
  )
}

pub fn shared_tree_summary_allows_repeated_references_and_rejects_cycles_test() -> Nil {
  let previous =
    fluid_summary.SummaryTree([
      #("blob", fluid_summary.SummaryBlob(<<7>>)),
      #("self", fluid_summary.SummaryHandle("/self", fluid_summary.BlobHandle)),
      #("left", fluid_summary.SummaryHandle("/right", fluid_summary.BlobHandle)),
      #("right", fluid_summary.SummaryHandle("/left", fluid_summary.BlobHandle)),
    ])

  fluid_summary.resolve(
    fluid_summary.SummaryTree([
      #("first", fluid_summary.SummaryHandle("/blob", fluid_summary.BlobHandle)),
      #(
        "second",
        fluid_summary.SummaryHandle("/blob", fluid_summary.BlobHandle),
      ),
    ]),
    Some(previous),
  )
  |> expect.to_equal(
    Ok(
      fluid_summary.SummaryTree([
        #("first", fluid_summary.SummaryBlob(<<7>>)),
        #("second", fluid_summary.SummaryBlob(<<7>>)),
      ]),
    ),
  )

  fluid_summary.resolve(
    fluid_summary.SummaryHandle("/self", fluid_summary.BlobHandle),
    Some(previous),
  )
  |> expect.to_equal(Error(fluid_summary.CyclicReference("/self")))

  fluid_summary.resolve(
    fluid_summary.SummaryHandle("/left", fluid_summary.BlobHandle),
    Some(previous),
  )
  |> expect.to_equal(Error(fluid_summary.CyclicReference("/left")))
}

pub fn shared_tree_summary_validates_names_paths_and_root_handles_test() -> Nil {
  fluid_summary.encode_component("plus+cash$")
  |> expect.to_equal("plus%2Bcash%24")

  fluid_summary.resolve(
    fluid_summary.SummaryTree([
      #("same", fluid_summary.SummaryBlob(<<>>)),
      #("same", fluid_summary.SummaryTree([])),
    ]),
    None,
  )
  |> expect.to_equal(
    Error(fluid_summary.MalformedEntry("/", "duplicate entry: same")),
  )

  fluid_summary.resolve(
    fluid_summary.SummaryHandle("/bad%ZZ", fluid_summary.BlobHandle),
    Some(fluid_summary.SummaryTree([])),
  )
  |> expect.to_equal(
    Error(fluid_summary.MalformedEntry("/bad%ZZ", "invalid percent encoding")),
  )

  let previous =
    fluid_summary.SummaryTree([
      #("slash/name", fluid_summary.SummaryBlob(<<2>>)),
      #("plus+cash$", fluid_summary.SummaryBlob(<<3>>)),
    ])
  fluid_summary.resolve(
    fluid_summary.SummaryHandle("/slash%2Fname", fluid_summary.BlobHandle),
    Some(previous),
  )
  |> expect.to_equal(Ok(fluid_summary.SummaryBlob(<<2>>)))

  fluid_summary.resolve(
    fluid_summary.SummaryHandle("/plus%2Bcash%24", fluid_summary.BlobHandle),
    Some(previous),
  )
  |> expect.to_equal(Ok(fluid_summary.SummaryBlob(<<3>>)))

  fluid_summary.resolve(
    fluid_summary.SummaryHandle("", fluid_summary.TreeHandle),
    Some(previous),
  )
  |> expect.to_equal(Ok(previous))

  fluid_summary.resolve(
    fluid_summary.SummaryHandle("/", fluid_summary.TreeHandle),
    Some(previous),
  )
  |> expect.to_equal(Error(fluid_summary.MissingEntry("/")))

  fluid_summary.resolve(
    fluid_summary.SummaryHandle(
      "0123456789abcdef0123456789abcdef01234567",
      fluid_summary.TreeHandle,
    ),
    Some(previous),
  )
  |> expect.to_equal(
    Error(fluid_summary.MissingEntry("0123456789abcdef0123456789abcdef01234567")),
  )
}

pub fn shared_tree_summary_materializes_snapshot_bytes_and_paths_test() -> Nil {
  let tree =
    json.object([
      #("id", json.string("root-tree")),
      #(
        "blobs",
        json.object([
          #("binary", json.string("binary-id")),
          #("empty", json.string("empty-id")),
        ]),
      ),
      #(
        "trees",
        json.object([
          #(
            "slash/name",
            json.object([
              #("id", json.string("child-tree")),
              #("blobs", json.object([#("text", json.string("text-id"))])),
              #("trees", json.object([])),
              #("commits", json.object([])),
            ]),
          ),
        ]),
      ),
      #("commits", json.object([])),
    ])
  let blobs =
    dict.from_list([
      #("binary-id", <<0, 255, 128>>),
      #("empty-id", <<>>),
      #("text-id", <<"héllo":utf8>>),
    ])

  fluid_summary.from_snapshot(tree, blobs)
  |> expect.to_equal(
    Ok(
      fluid_summary.SummaryTree([
        #("binary", fluid_summary.SummaryBlob(<<0, 255, 128>>)),
        #("empty", fluid_summary.SummaryBlob(<<>>)),
        #(
          "slash/name",
          fluid_summary.SummaryTree([
            #("text", fluid_summary.SummaryBlob(<<"héllo":utf8>>)),
          ]),
        ),
      ]),
    ),
  )
}

pub fn shared_tree_summary_snapshot_order_is_utf8_deterministic_test() -> Nil {
  let bmp = "\u{E000}"
  let astral = "\u{10000}"
  let tree =
    json.object([
      #("id", json.string("root-tree")),
      #(
        "blobs",
        json.object([
          #(astral, json.string("astral-id")),
          #(bmp, json.string("bmp-id")),
        ]),
      ),
      #("trees", json.object([])),
      #("commits", json.object([])),
    ])

  fluid_summary.from_snapshot(
    tree,
    dict.from_list([#("astral-id", <<1>>), #("bmp-id", <<2>>)]),
  )
  |> expect.to_equal(
    Ok(
      fluid_summary.SummaryTree([
        #(bmp, fluid_summary.SummaryBlob(<<2>>)),
        #(astral, fluid_summary.SummaryBlob(<<1>>)),
      ]),
    ),
  )
}

pub fn shared_tree_summary_refuses_incomplete_or_legacy_snapshots_test() -> Nil {
  let missing_blob =
    json.object([
      #("id", json.string("root-tree")),
      #("blobs", json.object([#("binary", json.string("missing-id"))])),
      #("trees", json.object([])),
      #("commits", json.object([])),
    ])
  fluid_summary.from_snapshot(missing_blob, dict.new())
  |> expect.to_equal(
    Error(fluid_summary.MissingEntry("/binary (snapshot blob missing-id)")),
  )

  let legacy_commit =
    json.object([
      #("id", json.string("root-tree")),
      #("blobs", json.object([])),
      #("trees", json.object([])),
      #("commits", json.object([#("legacy", json.string("commit-id"))])),
    ])
  fluid_summary.from_snapshot(legacy_commit, dict.new())
  |> expect.to_equal(
    Error(fluid_summary.UnsupportedEntry(
      "/legacy",
      "snapshot commits are not supported",
    )),
  )
}

pub fn shared_tree_summary_accepts_omitted_empty_commit_map_test() -> Nil {
  let tree =
    json.object([
      #("id", json.string("root-tree")),
      #("blobs", json.object([])),
      #("trees", json.object([])),
    ])

  fluid_summary.from_snapshot(tree, dict.new())
  |> expect.to_equal(Ok(fluid_summary.SummaryTree([])))
}

pub fn shared_tree_summary_fixture_uses_only_replay_input_test() -> Nil {
  let assert Ok(first) = summary_fixture.run(summary_fixture_input("AP+A"))
  let assert Ok(second) = summary_fixture.run(summary_fixture_input("AQID"))
  fixtures.first_difference(first, second) |> expect.to_be_error

  let _ =
    summary_fixture.run(summary_fixture_input("%%%"))
    |> expect.to_be_error
  Nil
}

pub fn shared_tree_summary_fixture_requires_typed_refusals_test() -> Nil {
  [
    #("missing-parent", "/blob", "blob"),
    #("missing-path", "/missing", "blob"),
    #("wrong-kind", "/blob", "tree"),
    #("malformed-percent-encoding", "/bad%ZZ", "blob"),
  ]
  |> list.each(fn(selector) {
    let #(label, path, kind) = selector
    let assert Ok(actual) =
      summary_fixture.run(
        summary_fixture_scenarios([refusal_scenario(label, path, kind)]),
      )
    actual
    |> expect.to_equal(
      json.object([
        #(
          "observations",
          array([
            json.object([
              #("label", json.string(label)),
              #("refused", json.bool(True)),
            ]),
          ]),
        ),
      ]),
    )
  })

  let _ =
    summary_fixture.run(
      summary_fixture_scenarios([
        refusal_scenario("missing-path", "/bad%ZZ", "blob"),
      ]),
    )
    |> expect.to_be_error
  Nil
}

pub fn shared_tree_summary_fixture_rejects_unknown_or_incomplete_scenarios_test() -> Nil {
  [
    refusal_scenario("unknown", "/missing", "blob"),
    json.object([#("label", json.string("missing-path"))]),
    json.object([
      #("label", json.string("missing-path")),
      #("summary", json.null()),
    ]),
  ]
  |> list.each(fn(scenario) {
    let _ =
      summary_fixture.run(summary_fixture_scenarios([scenario]))
      |> expect.to_be_error
    Nil
  })
}

pub fn shared_tree_summary_fixture_uses_utf16_snapshot_order_test() -> Nil {
  let bmp = "\u{E000}"
  let astral = "\u{10000}"
  let input =
    json.object([
      #(
        "previousSnapshot",
        json.object([
          #(
            "version",
            json.object([
              #("id", json.string("root")),
              #("treeId", json.string("root")),
            ]),
          ),
          #(
            "tree",
            json.object([
              #("id", json.string("root")),
              #(
                "blobs",
                json.object([
                  #(bmp, json.string("bmp-id")),
                  #(astral, json.string("astral-id")),
                ]),
              ),
              #("trees", json.object([])),
            ]),
          ),
          #(
            "blobs",
            json.object([
              #("bmp-id", json.string("Ag==")),
              #("astral-id", json.string("AQ==")),
            ]),
          ),
          #("blobEncoding", json.string("base64")),
        ]),
      ),
      #(
        "scenarios",
        array([
          json.object([#("label", json.string("snapshot-entries"))]),
        ]),
      ),
    ])
  let assert Ok(actual) = summary_fixture.run(input)
  actual
  |> expect.to_equal(
    json.object([
      #(
        "observations",
        array([
          json.object([
            #("label", json.string("snapshot-entries")),
            #(
              "entries",
              array([
                json.object([
                  #("components", array([])),
                  #("kind", json.string("tree")),
                  #("storageId", json.string("root")),
                ]),
                json.object([
                  #("components", array([json.string(astral)])),
                  #("kind", json.string("blob")),
                  #("storageId", json.string("astral-id")),
                  #("bytes", json.string("AQ==")),
                ]),
                json.object([
                  #("components", array([json.string(bmp)])),
                  #("kind", json.string("blob")),
                  #("storageId", json.string("bmp-id")),
                  #("bytes", json.string("Ag==")),
                ]),
              ]),
            ),
          ]),
        ]),
      ),
    ]),
  )
}

pub fn shared_tree_summary_upstream_fixture_test() -> Nil {
  fixtures.assert_case("summary-foundations", summary_fixture.run)
}
