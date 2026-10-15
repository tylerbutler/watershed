import gleam/bit_array
import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import spillway/types as spillway_types
import startest/expect
import watershed/canonical_json
import watershed/channel
import watershed/fluid_ids
import watershed/handle
import watershed/json_ot.{VArray, VObject, VString}
import watershed/runtime_core
import watershed/tree/compression_fixture
import watershed/tree/document_summary_fixture
import watershed/tree/fixtures
import watershed/tree/identifier_fixture
import watershed/tree/runtime_fixture
import watershed/tree/schema as tree_schema
import watershed/tree/summary_export
import watershed/tree/types as tree_types
import watershed/tree/undo_acceptance
import watershed/tree_kernel
import watershed/wire
import watershed/wire/fluid_document
import watershed/wire/fluid_inbound
import watershed/wire/fluid_summary
import watershed/wire/socket
import watershed/wire/summary_blob

pub fn identifier_summary_tail_continues_in_fresh_session_test() {
  let assert Ok(fixture) = fixtures.load("identifier-persistence")
  let output = case identifier_fixture.run(fixture.input) {
    Ok(value) -> value
    Error(error) -> panic as { error }
  }
  let assert Ok(VObject(root)) = json_ot.parse_json(json.to_string(output))
  let assert Ok(VArray(observations)) = list.key_find(root, "observations")
  let assert Ok(VObject(tail)) =
    list.find(observations, fn(value) {
      case value {
        VObject(fields) ->
          list.key_find(fields, "id") == Ok(VString("summary-tail"))
        _ -> False
      }
    })
  let assert Ok(VString(identifier)) =
    list.key_find(tail, "continuedIdentifier")
  identifier |> string.length |> expect.to_not_equal(0)
  list.key_find(tail, "continuationReferenceStable")
  |> expect.to_equal(Ok(json_ot.VBool(True)))
}

pub fn shared_tree_document_summary_decodes_captured_hierarchy_test() {
  let assert Ok(fixture) = fixtures.load("summary-tail")
  let assert Ok(session) =
    fluid_ids.session_id("70000000-0000-4000-8000-000000000007")
  let assert Ok(view) =
    fluid_ids.stable_id("60000000-0000-4000-8000-000000000006")
  let assert Ok(snapshot) =
    json.parse(
      json.to_string(fixture.input),
      decode.at(["replayInput", "snapshotAtS"], wire.json_value_decoder()),
    )
  let document = case runtime_fixture.read_snapshot(snapshot) {
    Ok(document) -> document
    Error(detail) -> panic as { detail }
  }

  let summary = case fluid_document.decode(document, None, session, view) {
    Ok(summary) -> summary
    Error(detail) -> panic as { string.inspect(detail) }
  }

  fluid_document.inspect(summary).sequence_number |> expect.to_equal(4)
  let assert Ok(encoded) = fluid_document.encode(summary)
  let assert Ok(again) = fluid_document.decode(encoded, None, session, view)
  fluid_document.inspect(again)
  |> expect.to_equal(fluid_document.inspect(summary))
}

pub fn shared_tree_retained_handle_graph_gc_round_trip_test() {
  let assert Ok(fixture) = fixtures.load("handle-retention")
  let assert Ok(records) =
    json.parse(
      json.to_string(fixture.raw),
      decode.at(["summaries"], decode.list(wire.json_value_decoder())),
    )
  let records =
    list.filter(records, fn(record) {
      json.parse(json.to_string(record), decode.at(["kind"], decode.string))
      == Ok("published-document")
    })
  list.length(records) |> expect.to_equal(8)
  let assert Ok(session) =
    fluid_ids.session_id("70000000-0000-4000-8000-000000000007")
  let assert Ok(view) =
    fluid_ids.stable_id("60000000-0000-4000-8000-000000000006")
  list.each(records, fn(record) {
    let assert Ok(id) =
      json.parse(
        json.to_string(record),
        decode.at(["scenarioId"], decode.string),
      )
    let assert Ok(snapshot) =
      json.parse(
        json.to_string(record),
        decode.at(["value", "snapshot"], wire.json_value_decoder()),
      )
    let assert Ok(hierarchy) = runtime_fixture.read_snapshot(snapshot)
    let summary = case fluid_document.decode(hierarchy, None, session, view) {
      Ok(summary) -> summary
      Error(error) -> panic as { id <> ": " <> string.inspect(error) }
    }
    let stores = fluid_document.datastores(summary)
    let channels =
      list.flat_map(stores, fn(store) {
        list.map(store.channels, fn(item) {
          #(store.id <> "/" <> item.id, item.snapshot)
        })
      })
    let routing =
      fluid_document.CaptureRouting(
        fluid_document.aliases(summary),
        list.map(stores, fn(store) { #(store.id, store.package_path) }),
        list.flat_map(stores, fn(store) {
          list.map(store.channels, fn(item) {
            #(store.id <> "/" <> item.id, item.attributes)
          })
        }),
      )
    let refreshed = case
      fluid_document.capture(
        summary,
        channels,
        fluid_document.compressor(summary),
        routing,
      )
    {
      Ok(summary) -> summary
      Error(error) -> panic as { id <> ": " <> string.inspect(error) }
    }
    case
      fixtures.first_difference(
        fluid_document.gc(refreshed),
        fluid_document.gc(summary),
      )
    {
      Ok(Nil) -> Nil
      Error(path) -> panic as { id <> ": retained graph GC differs at " <> path }
    }
  })
}

pub fn shared_tree_document_summary_read_only_capture_does_not_generate_test() {
  let summary = retained_publication("fresh-load")
  let initial = stored_summary_number(summary)
  captured_summary_number(summary) |> expect.to_equal(initial)
  captured_summary_number(summary) |> expect.to_equal(initial)
}

pub fn shared_tree_document_summary_generation_rejection_retry_advances_test() {
  let summary = retained_publication("fresh-load")
  let assert Ok(runtime_core.Complete(core)) =
    runtime_core.bootstrap_document(
      runtime_fixture.connected(
        "summary-writer",
        [],
        fluid_document.sequence_number(summary),
      ),
      summary,
    )
  let initial = stored_summary_number(summary)
  let assert Ok(#(core, generated)) = runtime_core.generate_summary(core)
  stored_summary_number(generated) |> expect.to_equal(initial + 1)
  let proposal_sequence = fluid_document.sequence_number(generated) + 1
  let proposal =
    json.object([
      #("handle", json.string("rejected")),
      #(
        "summaryProposal",
        json.object([
          #("summarySequenceNumber", json.int(proposal_sequence)),
        ]),
      ),
      #("message", json.string("rejected")),
    ])
  let assert Ok(#(core, _)) =
    runtime_core.handle_sequenced(
      core,
      document_message(
        proposal_sequence,
        1_700_000_000_001,
        "summarize",
        proposal,
      ),
    )
  let assert Ok(#(core, _)) =
    runtime_core.handle_sequenced(
      core,
      document_message(
        proposal_sequence + 1,
        1_700_000_000_002,
        "summaryNack",
        proposal,
      ),
    )
  let assert Ok(#(_, retried)) = runtime_core.generate_summary(core)
  stored_summary_number(retried) |> expect.to_equal(initial + 2)
}

pub fn shared_tree_document_summary_transient_reference_resets_gc_timestamp_test() {
  let summary = retained_publication("fresh-load")
  let assert Ok(runtime_core.Complete(core)) =
    runtime_core.bootstrap_document(
      runtime_fixture.connected(
        "gc-writer",
        [],
        fluid_document.sequence_number(summary),
      ),
      summary,
    )
  let assert Ok(root) = runtime_core.root_channel_address(core)
  let assert Ok(reference) = handle.reference_from_path("/P/root")
  let assert Ok(#(pending, _, [outbound])) =
    runtime_core.set(
      core,
      root,
      "transient",
      handle.reference_to_json(reference),
    )
  let assert Ok(#(referenced, _)) =
    runtime_core.handle_sequenced(
      pending,
      document_message(
        39,
        1_700_000_000_001,
        outbound.operation_type,
        outbound.contents,
      ),
    )
  let assert Ok(captured) = runtime_core.capture_summary(referenced)
  gc_timestamp(captured, "/P") |> expect.to_equal(Error(Nil))
  let assert Ok(#(pending, _, [outbound])) =
    runtime_core.delete(referenced, root, "transient")
  let assert Ok(#(removed, _)) =
    runtime_core.handle_sequenced(
      pending,
      document_message(
        40,
        1_700_000_000_002,
        outbound.operation_type,
        outbound.contents,
      ),
    )
  let assert Ok(captured) = runtime_core.capture_summary(removed)
  gc_timestamp(captured, "/P") |> expect.to_equal(Ok(1_700_000_000_002))
  gc_timestamp(captured, "/P/root") |> expect.to_equal(Ok(1_700_000_000_002))
}

pub fn shared_tree_document_summary_attach_reference_resets_gc_timestamp_test() {
  list.each([False, True], fn(secondary) {
    let summary = retained_publication("fresh-load")
    let assert Ok(runtime_core.Complete(core)) =
      runtime_core.bootstrap_document(
        runtime_fixture.connected("gc-writer", [], 38),
        summary,
      )
    let #(core, address) = case secondary {
      False -> #(core, "A/transient-child")
      True -> {
        let assert Ok(core) = runtime_core.create_detached_data_store(core, "Q")
        #(core, "Q/transient-child")
      }
    }
    let assert Ok(core) =
      runtime_core.create_detached(core, address, channel.InitMap)
    let assert Ok(reference) = handle.reference_from_path("/P/root")
    let assert Ok(#(core, _, [])) =
      runtime_core.set(
        core,
        address,
        "target",
        handle.reference_to_json(reference),
      )
    let assert Ok(child) = handle.reference_from_path("/" <> address)
    let assert Ok(#(pending, _, outbounds)) =
      runtime_core.set(core, "A/root", "child", handle.reference_to_json(child))
    let referenced =
      list.fold(outbounds, pending, fn(core, outbound) {
        let message = summary_outbound_message(core, outbound)
        let assert Ok(#(core, _)) =
          runtime_core.handle_sequenced(
            core,
            spillway_types.SequencedDocumentMessage(
              ..message,
              timestamp: 1_700_000_000_001,
            ),
          )
        core
      })
    let assert Ok(#(pending, _, [outbound])) =
      runtime_core.delete(referenced, address, "target")
    let message = summary_outbound_message(pending, outbound)
    let assert Ok(#(removed, _)) =
      runtime_core.handle_sequenced(
        pending,
        spillway_types.SequencedDocumentMessage(
          ..message,
          timestamp: 1_700_000_000_002,
        ),
      )
    let assert Ok(captured) = runtime_core.capture_summary(removed)
    gc_timestamp(captured, "/P/root") |> expect.to_equal(Ok(1_700_000_000_002))
  })
}

pub fn shared_tree_document_summary_new_channel_intervening_graph_resets_gc_timestamp_test() {
  let summary = retained_publication("fresh-load")
  let assert Ok(runtime_core.Complete(core)) =
    runtime_core.bootstrap_document(
      runtime_fixture.connected("gc-writer", [], 38),
      summary,
    )
  let assert Ok(core) =
    runtime_core.create_detached(core, "P/new", channel.InitMap)
  let assert Ok(child) = handle.reference_from_path("/P/new")
  let assert Ok(#(pending, _, outbounds)) =
    runtime_core.set(
      core,
      "A/root",
      "transient",
      handle.reference_to_json(child),
    )
  let referenced =
    settle_summary_outbounds_at(pending, outbounds, 1_700_000_000_001)
  let assert Ok(#(pending, _, [outbound])) =
    runtime_core.delete(referenced, "A/root", "transient")
  let removed =
    settle_summary_outbounds_at(pending, [outbound], 1_700_000_000_002)
  let assert Ok(captured) = runtime_core.capture_summary(removed)
  list.each(["/P", "/P/root", "/P/new"], fn(path) {
    gc_timestamp(captured, path) |> expect.to_equal(Ok(1_700_000_000_002))
  })
}

pub fn shared_tree_document_summary_transitive_intervening_graph_resets_gc_timestamp_test() {
  let summary = retained_publication("fresh-load")
  let assert Ok(runtime_core.Complete(core)) =
    runtime_core.bootstrap_document(
      runtime_fixture.connected("gc-writer", [], 38),
      summary,
    )
  let assert Ok(core) =
    runtime_core.create_detached(core, "P/middle", channel.InitMap)
  let assert Ok(core) =
    runtime_core.create_detached(core, "P/new", channel.InitMap)
  let assert Ok(middle) = handle.reference_from_path("/P/middle")
  let assert Ok(#(core, _, [])) =
    runtime_core.set(core, "P/new", "target", handle.reference_to_json(middle))
  let assert Ok(child) = handle.reference_from_path("/P/new")
  let assert Ok(#(pending, _, outbounds)) =
    runtime_core.set(
      core,
      "A/root",
      "transient",
      handle.reference_to_json(child),
    )
  let referenced =
    settle_summary_outbounds_at(pending, outbounds, 1_700_000_000_001)
  let assert Ok(#(pending, _, [outbound])) =
    runtime_core.delete(referenced, "A/root", "transient")
  let removed =
    settle_summary_outbounds_at(pending, [outbound], 1_700_000_000_002)
  let assert Ok(captured) = runtime_core.capture_summary(removed)
  list.each(["/P", "/P/middle", "/P/new"], fn(path) {
    gc_timestamp(captured, path) |> expect.to_equal(Ok(1_700_000_000_002))
  })
}

pub fn shared_tree_document_summary_refuses_malformed_last_message_timestamp_test() {
  let summary = retained_publication("fresh-load")
  let assert Ok(fluid_summary.SummaryTree(entries)) =
    fluid_document.encode(summary)
  let encoded = fluid_summary.SummaryTree(entries)
  let assert Ok(fluid_summary.SummaryBlob(bytes)) =
    list.key_find(entries, ".metadata")
  let assert Ok(raw) = bit_array.to_string(bytes)
  let assert Ok(fields) =
    json.parse(raw, decode.dict(decode.string, wire.json_value_decoder()))
  let malformed =
    dict.insert(
      fields,
      "lastMessage",
      json.object([#("timestamp", json.string("bad"))]),
    )
  let encoded =
    replace_entry(
      encoded,
      [".metadata"],
      fluid_summary.SummaryBlob(<<
        json.to_string(json.object(dict.to_list(malformed))):utf8,
      >>),
    )
  let assert Ok(session) =
    fluid_ids.session_id("70000000-0000-4000-8000-000000000007")
  let assert Ok(view) =
    fluid_ids.stable_id("60000000-0000-4000-8000-000000000006")
  fluid_document.decode(encoded, None, session, view) |> expect.to_be_error()
  Nil
}

pub fn shared_tree_document_summary_applies_compression_schema_cas_test() {
  let summary = retained_publication("fresh-load")
  let current = document_schema(summary)
  let assert Ok(reference) =
    json.parse(json.to_string(current), decode.at(["refSeq"], decode.int))
  let proposal = runtime_schema_proposal(reference, [])
  let assert Ok(activated) =
    fluid_document.apply_runtime_schema(summary, proposal, reference + 5)
  let schema = document_schema(activated)
  json.parse(json.to_string(schema), decode.at(["refSeq"], decode.int))
  |> expect.to_equal(Ok(reference + 5))
  list.each(
    ["compressionLz4", "explicitSchemaControl", "opGroupingEnabled"],
    fn(feature) {
      json.parse(
        json.to_string(schema),
        decode.at(["runtime", feature], decode.bool),
      )
      |> expect.to_equal(Ok(True))
    },
  )
}

pub fn shared_tree_document_summary_applies_native_compression_schema_test() {
  let summary = retained_publication("fresh-load")
  let current = document_schema(summary)
  let assert Ok(reference) =
    json.parse(json.to_string(current), decode.at(["refSeq"], decode.int))
  let assert Ok(runtime) =
    json.parse(
      json.to_string(current),
      decode.at(
        ["runtime"],
        decode.dict(decode.string, wire.json_value_decoder()),
      ),
    )
  let proposal =
    json.object([
      #("version", json.int(1)),
      #("refSeq", json.int(reference)),
      #(
        "info",
        json.object([
          #("minVersionForCollab", json.string("2.117.0")),
        ]),
      ),
      #(
        "runtime",
        json.object(
          dict.to_list(dict.insert(runtime, "compressionLz4", json.bool(True))),
        ),
      ),
    ])
  let assert Ok(activated) =
    fluid_document.apply_runtime_schema(summary, proposal, reference + 5)
  let assert Ok(encoded) = fluid_document.encode(activated)
  let assert Ok(session) =
    fluid_ids.session_id("71000000-0000-4000-8000-000000000007")
  let assert Ok(reloaded) =
    fluid_document.decode(
      encoded,
      None,
      session,
      fluid_document.view_id(activated),
    )
  document_schema(reloaded)
  |> json.to_string
  |> expect.to_equal(json.to_string(document_schema(activated)))
  let changed_mode =
    json.object([
      #("version", json.int(1)),
      #("refSeq", json.int(reference)),
      #(
        "info",
        json.object([
          #("minVersionForCollab", json.string("2.117.0")),
        ]),
      ),
      #(
        "runtime",
        json.object(dict.to_list(
          runtime
          |> dict.insert("compressionLz4", json.bool(True))
          |> dict.insert("idCompressorMode", json.string("off")),
        )),
      ),
    ])
  fluid_document.apply_runtime_schema(summary, changed_mode, reference + 5)
  |> expect.to_be_error()
  Nil
}

pub fn shared_tree_document_summary_stops_schema_array_after_failed_cas_test() {
  let summary = retained_publication("fresh-load")
  let current = document_schema(summary)
  let assert Ok(reference) =
    json.parse(json.to_string(current), decode.at(["refSeq"], decode.int))
  let assert Ok(activated) =
    fluid_document.apply_runtime_schema(
      summary,
      runtime_schema_proposal(reference, []),
      10,
    )
  let proposals =
    json.array(
      [
        runtime_schema_proposal(reference, []),
        runtime_schema_proposal(10, []),
      ],
      fn(value) { value },
    )
  fluid_document.apply_runtime_schema(activated, proposals, 20)
  |> expect.to_equal(Ok(activated))
}

pub fn shared_tree_document_summary_plain_leave_clears_sender_prefix_test() {
  let #(core, envelopes) = case
    compression_fixture.core_case("partial-summary-prefix-tail")
  {
    Ok(value) -> value
    Error(error) -> panic as error
  }
  let assert [first, ..] = envelopes
  let assert Some(sender) = first.message.client_id
  let assert Ok(#(partial, _)) = runtime_core.handle_envelope(core, first)
  let assert Ok(summary) = runtime_core.capture_summary(partial)
  fluid_document.inbound_state(summary)
  |> fluid_inbound.partial_chunks
  |> list.length
  |> expect.to_equal(1)
  let join =
    spillway_types.SequencedDocumentMessage(
      ..first.message,
      sequence_number: first.message.sequence_number + 1,
      message_type: "join",
      contents: first.message.contents,
      data: Some(
        json.object([
          #("clientId", json.string(sender)),
          #("detail", json.object([])),
        ])
        |> json.to_string,
      ),
    )
  let assert Ok(summary) = fluid_document.advance(summary, join)
  let leave =
    spillway_types.SequencedDocumentMessage(
      ..join,
      sequence_number: join.sequence_number + 1,
      message_type: "leave",
      data: Some(json.to_string(json.string(sender))),
    )
  let assert Ok(left) = fluid_document.advance(summary, leave)
  fluid_document.inbound_state(left)
  |> fluid_inbound.partial_chunks
  |> expect.to_equal([])
  fluid_document.members(left) |> expect.to_equal([])
  let assert Ok(encoded) = fluid_document.encode(left)
  let assert Ok(session) =
    fluid_ids.session_id("72000000-0000-4000-8000-000000000007")
  let assert Ok(reloaded) =
    fluid_document.decode(encoded, None, session, fluid_document.view_id(left))
  fluid_document.inbound_state(reloaded)
  |> fluid_inbound.partial_chunks
  |> expect.to_equal([])
}

pub fn shared_tree_document_summary_schema_cas_rejects_invalid_proposals_test() {
  let summary = retained_publication("fresh-load")
  let current = document_schema(summary)
  let assert Ok(reference) =
    json.parse(json.to_string(current), decode.at(["refSeq"], decode.int))
  fluid_document.apply_runtime_schema(
    summary,
    runtime_schema_proposal(reference - 1, []),
    reference + 5,
  )
  |> expect.to_equal(Ok(summary))
  fluid_document.apply_runtime_schema(
    summary,
    runtime_schema_proposal(reference + 1, []),
    reference + 5,
  )
  |> expect.to_be_error()
  fluid_document.apply_runtime_schema(
    summary,
    runtime_schema_proposal(reference, [#("futureFeature", json.bool(True))]),
    reference + 5,
  )
  |> expect.to_be_error()
  Nil
}

pub fn shared_tree_document_summary_requires_gc_after_initial_snapshot_test() {
  let assert Ok(session) =
    fluid_ids.session_id("70000000-0000-4000-8000-000000000007")
  let assert Ok(view) =
    fluid_ids.stable_id("60000000-0000-4000-8000-000000000006")
  list.each([0, 3], fn(sequence) {
    let assert Ok(summary) =
      fluid_document.native(sequence, 0, [], [
        #("watershed/root", channel.MapSnapshot([])),
      ])
    let assert Ok(fluid_summary.SummaryTree(entries)) =
      fluid_document.encode(summary)
    let missing =
      fluid_summary.SummaryTree(
        list.filter(entries, fn(entry) { entry.0 != "gc" }),
      )
    case sequence, fluid_document.decode(missing, None, session, view) {
      0, Ok(_) -> Nil
      3, Error(fluid_summary.MissingEntry("/gc/__gc_root")) -> Nil
      _, result ->
        panic as { "missing stored GC accepted: " <> string.inspect(result) }
    }
    let incomplete =
      replace_entry(
        fluid_summary.SummaryTree(entries),
        ["gc"],
        fluid_summary.SummaryTree([]),
      )
    fluid_document.decode(incomplete, None, session, view)
    |> expect.to_be_error()
  })
}

pub fn shared_tree_document_summary_preserves_secondary_root_status_test() {
  let summary = retained_publication("fresh-load")
  let assert Ok(encoded) = fluid_document.encode(summary)
  let rooted =
    replace_entry(
      encoded,
      [".channels", "P", ".component"],
      fluid_summary.SummaryBlob(<<
        "{\"pkg\":\"[\\\"org.watershed.shared-tree.m7.graph\\\"]\",\"summaryFormatVersion\":2,\"isRootDataStore\":true}":utf8,
      >>),
    )
  let assert Ok(session) =
    fluid_ids.session_id("70000000-0000-4000-8000-000000000007")
  let assert Ok(view) =
    fluid_ids.stable_id("60000000-0000-4000-8000-000000000006")
  let assert Ok(rooted) = fluid_document.decode(rooted, None, session, view)
  let assert Ok(runtime_core.Complete(core)) =
    runtime_core.bootstrap_document(
      runtime_fixture.connected("root-reader", [], 38),
      rooted,
    )
  let assert Ok(captured) = runtime_core.capture_summary(core)
  let assert Ok(routes) =
    json.parse(
      json.to_string(fluid_document.gc(captured)),
      decode.at(["gcNodes", "/", "outboundRoutes"], decode.list(decode.string)),
    )
  routes |> expect.to_equal(["/A", "/P"])
  gc_timestamp(captured, "/P") |> expect.to_equal(Error(Nil))
  gc_timestamp(captured, "/P/root") |> expect.to_equal(Error(Nil))
}

pub fn shared_tree_document_summary_two_datastore_tree_cycle_context_and_reload_test() {
  let summary = retained_publication("before-removal")
  let assert Ok(runtime_core.Complete(core)) =
    runtime_core.bootstrap_document(
      runtime_fixture.connected(
        "cycle-writer",
        [],
        fluid_document.sequence_number(summary),
      ),
      summary,
    )
  let assert Ok(channel.TreeState(source)) =
    dict.get(core.channels, "A/9a787e70-ea41-4479-9649-c81c9b74fe58")
  let assert Ok(Some(root)) = tree_kernel.read(source, [])
  let assert tree_types.ObjectValue(_, fields) = root
  let assert Ok(tree_types.MapValue(links_type, _)) =
    list.key_find(fields, "links")
  let assert Ok(core) = runtime_core.create_detached_data_store(core, "B")
  let core = create_summary_test_tree(core, "A/left", source, root)
  let core = create_summary_test_tree(core, "B/right", source, root)
  let assert Ok(core) =
    runtime_core.create_detached(core, "A/child", channel.InitMap)
  let assert Ok(core) =
    runtime_core.create_detached(core, "B/child", channel.InitMap)
  let assert Ok(#(core, _, [])) =
    runtime_core.set(core, "A/child", "context", json.string("A"))
  let assert Ok(#(core, _, [])) =
    runtime_core.set(core, "B/child", "context", json.string("B"))
  let assert Ok(left) = handle.reference_from_path("/A/left")
  let assert Ok(right) = handle.reference_from_path("/B/right")
  let assert Ok(a_child) = handle.reference_from_path("/A/child")
  let assert Ok(b_child) = handle.reference_from_path("/B/child")
  let assert Ok(#(core, _, [])) =
    runtime_core.submit_tree_edits(core, "A/left", [
      tree_types.SetField(["link"], tree_types.HandleValue(right)),
      tree_types.SetField(
        ["links"],
        tree_types.MapValue(links_type, [
          #("local", tree_types.HandleValue(a_child)),
        ]),
      ),
    ])
  let assert Ok(#(core, _, [])) =
    runtime_core.submit_tree_edits(core, "B/right", [
      tree_types.SetField(["link"], tree_types.HandleValue(left)),
      tree_types.SetField(
        ["links"],
        tree_types.MapValue(links_type, [
          #("local", tree_types.HandleValue(b_child)),
        ]),
      ),
    ])
  let assert Ok(#(pending, _, [outbound])) =
    runtime_core.set(core, "A/root", "cycle", handle.reference_to_json(left))
  let core = settle_summary_outbound(pending, outbound)
  let assert Ok(#(pending, _, [outbound])) =
    runtime_core.set(
      core,
      "A/root",
      "local-child",
      handle.reference_to_json(a_child),
    )
  let core = settle_summary_outbound(pending, outbound)
  let assert Ok(#(pending, _, [outbound])) =
    runtime_core.set(
      core,
      "B/root",
      "local-child",
      handle.reference_to_json(b_child),
    )
  let core = settle_summary_outbound(pending, outbound)
  let assert Ok(summary) = runtime_core.capture_summary(core)
  fluid_document.aliases(summary) |> expect.to_equal([#("root", "A")])
  list.map(fluid_document.datastores(summary), fn(store) {
    #(store.id, store.package_path)
  })
  |> expect.to_equal([
    #("A", ["org.watershed.shared-tree.m7.graph"]),
    #("B", ["org.watershed.shared-tree.m7.graph"]),
  ])
  let assert Ok(encoded) = fluid_document.encode(summary)
  let relative = relative_summary_markers(encoded, ["A", "B"])
  let assert Ok(session) =
    fluid_ids.session_id("80000000-0000-4000-8000-000000000008")
  let assert Ok(view) =
    fluid_ids.stable_id("60000000-0000-4000-8000-000000000006")
  let assert Ok(restored) = fluid_document.decode(relative, None, session, view)
  let assert Ok(reencoded) = fluid_document.encode(restored)
  canonical_summary(reencoded) |> expect.to_equal(canonical_summary(encoded))
  let assert Some(before) = fluid_document.compressor(summary)
  let assert Some(after) = fluid_document.compressor(restored)
  fluid_ids.serialize(after, False)
  |> expect.to_equal(fluid_ids.serialize(before, False))
  let assert Ok(runtime_core.Complete(fresh)) =
    runtime_core.bootstrap_document(
      runtime_fixture.connected(
        "cycle-fresh",
        [],
        fluid_document.sequence_number(restored),
      ),
      restored,
    )
  list.each([#("A/left", right), #("B/right", left)], fn(item) {
    runtime_core.tree_read(fresh, item.0, ["link"])
    |> expect.to_equal(Ok(Some(tree_types.HandleValue(item.1))))
  })
  list.each([#("A/left", "A"), #("B/right", "B")], fn(item) {
    let assert Ok(Some(tree_types.HandleValue(reference))) =
      runtime_core.tree_read(fresh, item.0, ["links", "local"])
    let assert Ok(address) =
      runtime_core.resolve_handle_address(
        fresh,
        handle.reference_to_json(reference),
      )
    runtime_core.get(fresh, address, "context")
    |> expect.to_equal(Ok(json.string(item.1)))
    let assert Ok(marker) =
      runtime_core.get(fresh, item.1 <> "/root", "local-child")
    let assert Ok(address) = runtime_core.resolve_handle_address(fresh, marker)
    runtime_core.get(fresh, address, "context")
    |> expect.to_equal(Ok(json.string(item.1)))
  })
  let assert Ok(#(pending, _, [outbound])) =
    runtime_core.submit_tree_edits(fresh, "B/right", [
      tree_types.SetField(["label"], tree_types.StringValue("continued")),
    ])
  let message = summary_outbound_message(pending, outbound)
  let fresh = settle_summary_outbound(pending, outbound)
  let assert Ok(#(observed, _)) = runtime_core.handle_sequenced(core, message)
  runtime_core.tree_read(observed, "B/right", ["label"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("continued"))))
  runtime_core.tree_read(fresh, "A/left", ["link"])
  |> expect.to_equal(Ok(Some(tree_types.HandleValue(right))))
  let malformed = case
    fluid_summary.map_utf8_blobs(relative, fn(raw) {
      Ok(string.replace(raw, "\"url\":\"child\"", "\"url\":\"../child\""))
    })
  {
    Ok(value) -> value
    Error(error) -> panic as { string.inspect(error) }
  }
  fluid_document.decode(malformed, None, session, view) |> expect.to_be_error()
  Nil
}

fn create_summary_test_tree(
  core: runtime_core.Core,
  address: String,
  source: tree_kernel.TreeState,
  root: tree_types.TreeValue,
) -> runtime_core.Core {
  let assert Some(compressor) = core.compressor
  let assert Ok(#(compressor, id)) = fluid_ids.generate(compressor)
  let assert Ok(view) = fluid_ids.decompress(compressor, id)
  let assert Ok(core) =
    runtime_core.create_detached_tree(
      runtime_core.Core(..core, compressor: Some(compressor)),
      address,
      tree_kernel.stored_schema(source),
      Some(root),
      view,
    )
  core
}

fn summary_outbound_message(
  core: runtime_core.Core,
  outbound: wire.OutboundOperation,
) -> spillway_types.SequencedDocumentMessage {
  let assert Ok(contents) =
    json.parse(json.to_string(outbound.contents), decode.dynamic)
  let metadata = case outbound.metadata {
    None -> None
    Some(metadata) -> {
      let assert Ok(value) =
        json.parse(json.to_string(metadata), decode.dynamic)
      Some(value)
    }
  }
  spillway_types.SequencedDocumentMessage(
    client_id: Some(core.client_id),
    sequence_number: core.last_seen_sequence_number + 1,
    minimum_sequence_number: core.minimum_sequence_number,
    client_sequence_number: outbound.client_sequence_number,
    reference_sequence_number: outbound.reference_sequence_number,
    message_type: outbound.operation_type,
    contents:,
    metadata:,
    server_metadata: None,
    origin: None,
    traces: None,
    timestamp: 1_700_000_000_000,
    data: None,
  )
}

fn settle_summary_outbound(
  core: runtime_core.Core,
  outbound: wire.OutboundOperation,
) -> runtime_core.Core {
  let assert Ok(#(settled, _)) =
    runtime_core.handle_sequenced(
      core,
      summary_outbound_message(core, outbound),
    )
  settled
}

fn settle_summary_outbounds_at(
  core: runtime_core.Core,
  outbounds: List(wire.OutboundOperation),
  timestamp: Int,
) -> runtime_core.Core {
  list.fold(outbounds, core, fn(core, outbound) {
    let message = summary_outbound_message(core, outbound)
    let assert Ok(#(settled, _)) =
      runtime_core.handle_sequenced(
        core,
        spillway_types.SequencedDocumentMessage(..message, timestamp:),
      )
    settled
  })
}

fn relative_summary_markers(
  encoded: fluid_summary.SummaryEntry,
  stores: List(String),
) -> fluid_summary.SummaryEntry {
  let assert fluid_summary.SummaryTree(entries) = encoded
  let assert Ok(fluid_summary.SummaryTree(datastores)) =
    list.key_find(entries, ".channels")
  let datastores =
    list.map(datastores, fn(store) {
      case list.contains(stores, store.0) {
        False -> store
        True -> {
          let assert Ok(relative) =
            fluid_summary.map_utf8_blobs(store.1, fn(raw) {
              Ok(string.replace(
                raw,
                "\"url\":\"/" <> store.0 <> "/child\"",
                "\"url\":\"child\"",
              ))
            })
          #(store.0, relative)
        }
      }
    })
  replace_entry(encoded, [".channels"], fluid_summary.SummaryTree(datastores))
}

fn canonical_summary(
  encoded: fluid_summary.SummaryEntry,
) -> fluid_summary.SummaryEntry {
  let assert Ok(canonical) =
    fluid_summary.map_utf8_blobs(encoded, fn(raw) {
      let assert Ok(value) = json_ot.parse_json(raw)
      Ok(canonical_json.to_string(value))
    })
  canonical
}

fn document_message(
  sequence: Int,
  timestamp: Int,
  kind: String,
  contents: json.Json,
) -> spillway_types.SequencedDocumentMessage {
  let assert Ok(contents) = json.parse(json.to_string(contents), decode.dynamic)
  spillway_types.SequencedDocumentMessage(
    client_id: Some("gc-writer"),
    sequence_number: sequence,
    minimum_sequence_number: case sequence >= 38 {
      True -> 36
      False -> 0
    },
    client_sequence_number: case kind {
      "op" -> sequence - 38
      _ -> -1
    },
    reference_sequence_number: sequence - 1,
    message_type: kind,
    contents:,
    metadata: None,
    server_metadata: None,
    origin: None,
    traces: None,
    timestamp:,
    data: None,
  )
}

fn captured_summary_number(summary: fluid_document.DocumentSummary) -> Int {
  let stores = fluid_document.datastores(summary)
  let assert Ok(captured) =
    fluid_document.capture(
      summary,
      list.flat_map(stores, fn(store) {
        list.map(store.channels, fn(item) {
          #(store.id <> "/" <> item.id, item.snapshot)
        })
      }),
      fluid_document.compressor(summary),
      fluid_document.CaptureRouting(
        fluid_document.aliases(summary),
        list.map(stores, fn(store) { #(store.id, store.package_path) }),
        list.flat_map(stores, fn(store) {
          list.map(store.channels, fn(item) {
            #(store.id <> "/" <> item.id, item.attributes)
          })
        }),
      ),
    )
  let assert Ok(fluid_summary.SummaryTree(entries)) =
    fluid_document.encode(captured)
  let assert Ok(fluid_summary.SummaryBlob(bytes)) =
    list.key_find(entries, ".metadata")
  let assert Ok(raw) = bit_array.to_string(bytes)
  let assert Ok(number) =
    json.parse(raw, decode.at(["summaryNumber"], decode.int))
  number
}

fn stored_summary_number(summary: fluid_document.DocumentSummary) -> Int {
  let assert Ok(fluid_summary.SummaryTree(entries)) =
    fluid_document.encode(summary)
  let assert Ok(fluid_summary.SummaryBlob(bytes)) =
    list.key_find(entries, ".metadata")
  let assert Ok(raw) = bit_array.to_string(bytes)
  let assert Ok(number) =
    json.parse(raw, decode.at(["summaryNumber"], decode.int))
  number
}

fn retained_publication(id: String) -> fluid_document.DocumentSummary {
  let assert Ok(fixture) = fixtures.load("handle-retention")
  let assert Ok(records) =
    json.parse(
      json.to_string(fixture.raw),
      decode.at(["summaries"], decode.list(wire.json_value_decoder())),
    )
  let assert Ok(record) =
    list.find(records, fn(record) {
      json.parse(
        json.to_string(record),
        decode.at(["scenarioId"], decode.string),
      )
      == Ok(id)
      && json.parse(json.to_string(record), decode.at(["kind"], decode.string))
      == Ok("published-document")
    })
  let assert Ok(snapshot) =
    json.parse(
      json.to_string(record),
      decode.at(["value", "snapshot"], wire.json_value_decoder()),
    )
  let assert Ok(hierarchy) = runtime_fixture.read_snapshot(snapshot)
  let assert Ok(session) =
    fluid_ids.session_id("70000000-0000-4000-8000-000000000007")
  let assert Ok(view) =
    fluid_ids.stable_id("60000000-0000-4000-8000-000000000006")
  let assert Ok(summary) = fluid_document.decode(hierarchy, None, session, view)
  summary
}

fn document_schema(summary: fluid_document.DocumentSummary) -> json.Json {
  let assert Ok(fluid_summary.SummaryTree(entries)) =
    fluid_document.encode(summary)
  let assert Ok(fluid_summary.SummaryBlob(bytes)) =
    list.key_find(entries, ".metadata")
  let assert Ok(raw) = bit_array.to_string(bytes)
  let assert Ok(schema) =
    json.parse(raw, decode.at(["documentSchema"], wire.json_value_decoder()))
  schema
}

fn runtime_schema_proposal(
  reference: Int,
  extra: List(#(String, json.Json)),
) -> json.Json {
  json.object([
    #("version", json.int(1)),
    #("refSeq", json.int(reference)),
    #("info", json.object([#("minVersionForCollab", json.string("2.117.0"))])),
    #(
      "runtime",
      json.object([
        #("compressionLz4", json.bool(True)),
        #("explicitSchemaControl", json.bool(True)),
        #("opGroupingEnabled", json.bool(True)),
        ..extra
      ]),
    ),
  ])
}

fn gc_timestamp(
  summary: fluid_document.DocumentSummary,
  path: String,
) -> Result(Int, Nil) {
  json.parse(
    json.to_string(fluid_document.gc(summary)),
    decode.at(["gcNodes", path, "unreferencedTimestampMs"], decode.int),
  )
  |> result.replace_error(Nil)
}

pub fn shared_tree_document_summary_restores_each_persistence_state_test() {
  let assert Ok(fixture) = fixtures.load("summary-writer-matrix")
  let assert Ok(states) =
    json.parse(
      json.to_string(fixture.input),
      decode.at(["persistenceStates"], decode.list(wire.json_value_decoder())),
    )
  let assert Ok(session) =
    fluid_ids.session_id("70000000-0000-4000-8000-000000000007")
  let assert Ok(view) =
    fluid_ids.stable_id("60000000-0000-4000-8000-000000000006")
  list.each(states, fn(state) {
    let assert Ok(snapshot) =
      json.parse(
        json.to_string(state),
        decode.at(["snapshot"], wire.json_value_decoder()),
      )
    let assert Ok(expected) =
      json.parse(
        json.to_string(state),
        decode.at(["sequenceNumber"], decode.int),
      )
    let assert Ok(document) = runtime_fixture.read_snapshot(snapshot)
    let decoded = case fluid_document.decode(document, None, session, view) {
      Ok(value) -> value
      Error(error) -> panic as { string.inspect(error) }
    }

    fluid_document.inspect(decoded).sequence_number
    |> expect.to_equal(expected)
    let assert [fluid_document.Datastore(channels: channels, ..), ..] =
      fluid_document.datastores(decoded)
    let assert Ok(fluid_document.Channel(
      snapshot: channel.TreeSnapshot(tree),
      ..,
    )) = list.find(channels, fn(item) { item.id == "_C" })
    let #(_, _, history) = tree_kernel.snapshot_parts(tree)
    history.sequence_number |> expect.to_equal(expected)
    let assert Ok(encoded) = fluid_document.encode(decoded)
    let assert Ok(_) = fluid_document.decode(encoded, None, session, view)
    Nil
  })
}

pub fn shared_tree_document_summary_seeds_routed_core_test() {
  let assert Ok(fixture) = fixtures.load("summary-writer-matrix")
  let assert Ok(states) =
    json.parse(
      json.to_string(fixture.input),
      decode.at(["persistenceStates"], decode.list(wire.json_value_decoder())),
    )
  let assert Ok(first) = list.first(states)
  let assert Ok(snapshot) =
    json.parse(
      json.to_string(first),
      decode.at(["snapshot"], wire.json_value_decoder()),
    )
  let assert Ok(document) = runtime_fixture.read_snapshot(snapshot)
  let assert Ok(session) =
    fluid_ids.session_id("70000000-0000-4000-8000-000000000007")
  let assert Ok(view) =
    fluid_ids.stable_id("60000000-0000-4000-8000-000000000006")
  let assert Ok(summary) = fluid_document.decode(document, None, session, view)
  let connected = runtime_fixture.connected("reader", [], 2)
  let assert Ok(runtime_core.Complete(core)) =
    runtime_core.bootstrap_document(connected, summary)
  runtime_core.root_channel_address(core)
  |> expect.to_equal(Ok("A/root"))
}

pub fn shared_tree_document_summary_loads_upgraded_tree_without_application_view_test() {
  let assert Ok(fixture) = fixtures.load("summary-writer-matrix")
  let assert Ok(states) =
    json.parse(
      json.to_string(fixture.input),
      decode.at(["persistenceStates"], decode.list(wire.json_value_decoder())),
    )
  let assert Ok(first) = list.first(states)
  let assert Ok(snapshot) =
    json.parse(
      json.to_string(first),
      decode.at(["snapshot"], wire.json_value_decoder()),
    )
  let assert Ok(document) = runtime_fixture.read_snapshot(snapshot)
  let assert Ok(session) =
    fluid_ids.session_id("70000000-0000-4000-8000-000000000007")
  let assert Ok(view_id) =
    fluid_ids.stable_id("60000000-0000-4000-8000-000000000006")
  let assert Ok(summary) =
    fluid_document.decode(document, None, session, view_id)
  let assert Ok(runtime_core.Complete(core)) =
    runtime_core.bootstrap_document(
      runtime_fixture.connected(
        "writer",
        [],
        fluid_document.sequence_number(summary),
      ),
      summary,
    )
  let assert Ok(channel.TreeState(state)) = dict.get(core.channels, "A/_C")
  let initial =
    tree_kernel.stored_schema(state)
    |> tree_schema.stored_to_json
    |> tree_schema.view_from_json
    |> expect.to_be_ok()
  let upgraded_view =
    tree_kernel.stored_schema(state)
    |> tree_schema.stored_to_json
    |> json.to_string
    |> string.replace(
      "\"title\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.string\"]}",
      "\"score\":{\"kind\":\"Optional\",\"types\":[\"com.fluidframework.leaf.number\"]},\"title\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.string\"]}",
    )
    |> tree_schema.view_from_string
    |> expect.to_be_ok()
  let assert Ok(#(pending, _, [outbound])) =
    runtime_core.submit_tree_upgrade(core, "A/_C", upgraded_view)
  let contents =
    json.parse(json.to_string(outbound.contents), decode.dynamic)
    |> expect.to_be_ok()
  let metadata = case outbound.metadata {
    None -> None
    Some(value) ->
      json.parse(json.to_string(value), decode.dynamic)
      |> expect.to_be_ok()
      |> Some
  }
  let message =
    spillway_types.SequencedDocumentMessage(
      client_id: Some(pending.client_id),
      sequence_number: pending.last_seen_sequence_number + 1,
      minimum_sequence_number: pending.minimum_sequence_number,
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
  let #(settled, _) =
    runtime_core.handle_sequenced(pending, message)
    |> expect.to_be_ok()
  let summary = runtime_core.capture_summary(settled) |> expect.to_be_ok()
  let assert Ok(runtime_core.Complete(restored)) =
    runtime_core.bootstrap_document(
      runtime_fixture.connected(
        "reader-2",
        [],
        fluid_document.sequence_number(summary),
      ),
      summary,
    )
  runtime_core.tree_compatibility(restored, "A/_C", upgraded_view)
  |> expect.to_equal(Ok(tree_schema.Compatibility(True, True, True)))
  runtime_core.tree_compatibility(restored, "A/_C", initial)
  |> expect.to_equal(Ok(tree_schema.Compatibility(False, False, False)))
  runtime_core.get(restored, "A/root", "tree") |> expect.to_be_ok()
  Nil
}

pub fn shared_tree_document_summary_replays_publication_tail_test() {
  let assert Ok(fixture) = fixtures.load("summary-tail")
  let assert Ok(snapshot) =
    json.parse(
      json.to_string(fixture.input),
      decode.at(["replayInput", "snapshotAtS"], wire.json_value_decoder()),
    )
  let assert Ok(messages) =
    json.parse(
      json.to_string(fixture.input),
      decode.at(
        ["replayInput", "summaryToPublicationMessages"],
        decode.list(socket.sequenced_document_message_decoder()),
      ),
    )
  let assert Ok(document) = runtime_fixture.read_snapshot(snapshot)
  let assert Ok(session) =
    fluid_ids.session_id("70000000-0000-4000-8000-000000000007")
  let assert Ok(view) =
    fluid_ids.stable_id("60000000-0000-4000-8000-000000000006")
  let assert Ok(summary) = fluid_document.decode(document, None, session, view)
  let connected = runtime_fixture.connected("reader", messages, 7)
  let assert Ok(runtime_core.Complete(core)) =
    runtime_core.bootstrap_document(connected, summary)
  core.last_seen_sequence_number |> expect.to_equal(7)
  let assert Ok(captured) = runtime_core.capture_summary(core)
  fluid_document.sequence_number(captured) |> expect.to_equal(7)
  let assert Ok(encoded) = fluid_document.encode(captured)
  let assert Ok(reloaded) = fluid_document.decode(encoded, None, session, view)
  fluid_document.inspect(reloaded).sequence_number |> expect.to_equal(7)
  let assert Ok(later) =
    json.parse(
      json.to_string(fixture.input),
      decode.at(
        ["replayInput", "laterTailMessages"],
        decode.list(socket.sequenced_document_message_decoder()),
      ),
    )
  let final_core =
    list.fold(later, core, fn(core, message) {
      let assert Ok(#(next, _)) = runtime_core.handle_sequenced(core, message)
      next
    })
  final_core.last_seen_sequence_number |> expect.to_equal(12)
  let assert Ok(final_summary) = runtime_core.capture_summary(final_core)
  fluid_document.sequence_number(final_summary) |> expect.to_equal(12)
  let assert Ok(final_encoded) = fluid_document.encode(final_summary)
  let assert Ok(final_loaded) =
    fluid_document.decode(final_encoded, None, session, view)
  fluid_document.sequence_number(final_loaded) |> expect.to_equal(12)
}

pub fn shared_tree_document_summary_tail_corpus_test() {
  fixtures.assert_case("summary-tail", document_summary_fixture.run)
}

pub fn shared_tree_document_summary_preserves_native_channels_test() {
  let connected = runtime_fixture.connected("reader", [], 3)
  let summary =
    runtime_core.Summary(
      3,
      [
        #("watershed/root", channel.MapSnapshot([])),
        #("watershed/score", channel.CounterSnapshot(42)),
      ],
      [],
    )
  let assert Ok(runtime_core.Complete(core)) =
    runtime_core.bootstrap(connected, summary: Some(summary))
  let assert Ok(captured) = runtime_core.capture_summary(core)
  let assert Ok(encoded) = fluid_document.encode(captured)
  let assert Ok(session) =
    fluid_ids.session_id("70000000-0000-4000-8000-000000000007")
  let assert Ok(view) =
    fluid_ids.stable_id("60000000-0000-4000-8000-000000000006")
  let assert Ok(decoded) = fluid_document.decode(encoded, None, session, view)
  fluid_document.inspect(decoded).channels
  |> expect.to_equal([
    summary_blob.ChannelSnapshot("watershed/root", channel.MapSnapshot([])),
    summary_blob.ChannelSnapshot("watershed/score", channel.CounterSnapshot(42)),
  ])
  let assert Ok(runtime_core.Complete(restored)) =
    runtime_core.bootstrap_document(connected, decoded)
  runtime_core.counter_value(restored, "watershed/score")
  |> expect.to_equal(Ok(42))
  runtime_core.root_channel_address(restored)
  |> expect.to_equal(Ok("watershed/root"))
}

pub fn shared_tree_document_summary_rebuilds_gc_after_handle_removal_test() {
  let assert Ok(fixture) = fixtures.load("summary-tail")
  let assert Ok(snapshot) =
    json.parse(
      json.to_string(fixture.input),
      decode.at(["replayInput", "snapshotAtS"], wire.json_value_decoder()),
    )
  let assert Ok(document) = runtime_fixture.read_snapshot(snapshot)
  let assert Ok(session) =
    fluid_ids.session_id("70000000-0000-4000-8000-000000000007")
  let assert Ok(view) =
    fluid_ids.stable_id("60000000-0000-4000-8000-000000000006")
  let assert Ok(summary) = fluid_document.decode(document, None, session, view)
  let channels =
    list.flat_map(fluid_document.datastores(summary), fn(store) {
      list.map(store.channels, fn(item) {
        let address = store.id <> "/" <> item.id
        case address {
          "A/root" -> #(address, channel.MapSnapshot([]))
          _ -> #(address, item.snapshot)
        }
      })
    })
  let assert Ok(updated) =
    fluid_document.capture(
      summary,
      channels,
      fluid_document.compressor(summary),
      fluid_document.CaptureRouting(
        fluid_document.aliases(summary),
        list.map(fluid_document.datastores(summary), fn(store) {
          #(store.id, store.package_path)
        }),
        list.flat_map(fluid_document.datastores(summary), fn(store) {
          list.map(store.channels, fn(item) {
            #(store.id <> "/" <> item.id, item.attributes)
          })
        }),
      ),
    )
  let assert Ok(routes) =
    json.parse(
      json.to_string(fluid_document.gc(updated)),
      decode.at(
        ["gcNodes", "/A/root", "outboundRoutes"],
        decode.list(decode.string),
      ),
    )
  routes |> expect.to_equal(["/A"])
}

pub fn shared_tree_document_summary_refuses_missing_routing_test() {
  let assert Ok(native) =
    fluid_document.native(3, 0, [], [
      #("watershed/root", channel.MapSnapshot([])),
    ])
  let assert Ok(fluid_summary.SummaryTree(entries)) =
    fluid_document.encode(native)
  let without_alias =
    fluid_summary.SummaryTree(
      list.filter(entries, fn(item) { item.0 != ".aliases" }),
    )
  let assert Ok(session) =
    fluid_ids.session_id("70000000-0000-4000-8000-000000000007")
  let assert Ok(view) =
    fluid_ids.stable_id("60000000-0000-4000-8000-000000000006")
  fluid_document.decode(without_alias, None, session, view)
  |> expect.to_equal(Error(fluid_summary.MissingEntry("/.aliases")))
  let no_root =
    fluid_summary.SummaryTree(
      list.map(entries, fn(item) {
        case item.0 {
          ".aliases" -> #(
            item.0,
            fluid_summary.SummaryBlob(<<
              json.to_string(json.array([], fn(value) { value })):utf8,
            >>),
          )
          _ -> item
        }
      }),
    )
  fluid_document.decode(no_root, None, session, view)
  |> expect.to_equal(Error(fluid_summary.MissingEntry("/.aliases/root")))
}

pub fn shared_tree_document_summary_rejects_corrupt_hierarchies_test() {
  let assert Ok(native) =
    fluid_document.native(3, 1, [], [
      #("watershed/root", channel.MapSnapshot([])),
    ])
  let assert Ok(hierarchy) = fluid_document.encode(native)
  let assert Ok(session) =
    fluid_ids.session_id("70000000-0000-4000-8000-000000000007")
  let assert Ok(view) =
    fluid_ids.stable_id("60000000-0000-4000-8000-000000000006")
  let assert fluid_summary.SummaryTree(entries) = hierarchy
  let cases = [
    #(
      replace_entry(
        hierarchy,
        [".metadata"],
        fluid_summary.SummaryBlob(<<
          255,
        >>),
      ),
      "/.metadata",
    ),
    #(
      replace_entry(
        hierarchy,
        [".metadata"],
        fluid_summary.SummaryBlob(<<
          "{\"summaryFormatVersion\":4}":utf8,
        >>),
      ),
      "/.metadata",
    ),
    #(
      replace_entry(
        hierarchy,
        [".protocol", "attributes"],
        fluid_summary.SummaryBlob(<<
          "{\"sequenceNumber\":1,\"minimumSequenceNumber\":2}":utf8,
        >>),
      ),
      "/.protocol/attributes",
    ),
    #(
      replace_entry(
        hierarchy,
        ["gc", "__gc_root"],
        fluid_summary.SummaryBlob(<<
          "{}":utf8,
        >>),
      ),
      "/gc/__gc_root",
    ),
    #(
      replace_entry(
        hierarchy,
        [".aliases"],
        fluid_summary.SummaryBlob(<<
          "invalid JSON":utf8,
        >>),
      ),
      "/.aliases",
    ),
    #(
      fluid_summary.SummaryTree([
        #(
          ".recentBatchInfo",
          fluid_summary.SummaryBlob(<<"{\"not\":\"a batch table\"}":utf8>>),
        ),
        ..entries
      ]),
      "/.recentBatchInfo",
    ),
    #(
      fluid_summary.SummaryTree([
        #(".metadata", fluid_summary.SummaryBlob(<<"{}":utf8>>)),
        ..entries
      ]),
      "/",
    ),
    #(
      replace_entry(
        hierarchy,
        [".aliases"],
        fluid_summary.SummaryHandle("/missing", fluid_summary.BlobHandle),
      ),
      "/missing",
    ),
    #(
      replace_entry(
        hierarchy,
        [".aliases"],
        fluid_summary.SummaryHandle("/.metadata", fluid_summary.TreeHandle),
      ),
      "/.metadata",
    ),
  ]
  list.each(cases, fn(pair) {
    let error = case
      fluid_document.decode(pair.0, Some(hierarchy), session, view)
    {
      Error(error) -> error
      Ok(_) -> panic as { "corrupt hierarchy accepted at " <> pair.1 }
    }
    string.inspect(error)
    |> string.contains(pair.1)
    |> expect.to_be_true()
  })
}

pub fn shared_tree_document_summary_rejects_bad_tree_and_compressor_test() {
  let assert Ok(fixture) = fixtures.load("summary-tail")
  let assert Ok(snapshot) =
    json.parse(
      json.to_string(fixture.input),
      decode.at(["replayInput", "snapshotAtS"], wire.json_value_decoder()),
    )
  let assert Ok(hierarchy) = runtime_fixture.read_snapshot(snapshot)
  let assert Ok(session) =
    fluid_ids.session_id("70000000-0000-4000-8000-000000000007")
  let assert Ok(view) =
    fluid_ids.stable_id("60000000-0000-4000-8000-000000000006")
  let cases = [
    #(
      replace_entry(
        hierarchy,
        [".idCompressor"],
        fluid_summary.SummaryBlob(<<"\"bad-base64\"":utf8>>),
      ),
      "/.idCompressor",
    ),
    #(
      replace_entry(
        hierarchy,
        [".channels", "A", ".channels", "_C", ".attributes"],
        fluid_summary.SummaryBlob(<<"{\"type\":\"unknown\"}":utf8>>),
      ),
      "/.channels/A/.channels/_C/.attributes",
    ),
    #(
      replace_entry(
        hierarchy,
        [".channels", "A", ".channels", "_C", "indexes"],
        fluid_summary.SummaryBlob(<<"{}":utf8>>),
      ),
      "/.channels/A/.channels/_C",
    ),
  ]
  list.each(cases, fn(pair) {
    let assert Error(error) = fluid_document.decode(pair.0, None, session, view)
    string.inspect(error)
    |> string.contains(pair.1)
    |> expect.to_be_true()
  })
}

pub fn shared_map_summary_loads_large_split_blob_test() {
  let large = string.repeat("a", 9 * 1024)
  let assert Ok(initial) =
    fluid_document.native(1, 0, [], [
      #("watershed/root", channel.MapSnapshot([])),
    ])
  let assert Ok(hierarchy) = fluid_document.encode(initial)
  let header =
    json.object([
      #("blobs", json.array(["blob0"], json.string)),
      #("content", json.object([])),
    ])
  let payload =
    json.object([
      #(
        "large",
        json.object([
          #("type", json.string("Plain")),
          #("value", json.string(large)),
        ]),
      ),
    ])
  let map_path = [".channels", "watershed", ".channels", "root"]
  let hierarchy =
    replace_entry(
      hierarchy,
      list.append(map_path, ["header"]),
      fluid_summary.SummaryBlob(<<json.to_string(header):utf8>>),
    )
  let hierarchy =
    insert_entry(
      hierarchy,
      map_path,
      "blob0",
      fluid_summary.SummaryBlob(<<json.to_string(payload):utf8>>),
    )
  let assert Ok(session) =
    fluid_ids.session_id("70000000-0000-4000-8000-000000000007")
  let assert Ok(view) =
    fluid_ids.stable_id("60000000-0000-4000-8000-000000000006")
  let summary = case fluid_document.decode(hierarchy, None, session, view) {
    Ok(summary) -> summary
    Error(error) ->
      panic as { "large map summary rejected: " <> string.inspect(error) }
  }
  let assert Ok(runtime_core.Complete(core)) =
    runtime_core.bootstrap_document(
      runtime_fixture.connected("reader", [], 1),
      summary,
    )
  runtime_core.get(core, "watershed/root", "large")
  |> expect.to_equal(Ok(json.string(large)))
  let missing =
    replace_entry(
      hierarchy,
      list.append(map_path, ["header"]),
      fluid_summary.SummaryBlob(<<
        json.to_string(
          json.object([
            #("blobs", json.array(["blob1"], json.string)),
            #("content", json.object([])),
          ]),
        ):utf8,
      >>),
    )
  case fluid_document.decode(missing, None, session, view) {
    Error(_) -> Nil
    Ok(_) -> panic as "accepted missing map blob"
  }
  let extra =
    replace_entry(
      hierarchy,
      list.append(map_path, ["header"]),
      fluid_summary.SummaryBlob(<<
        json.to_string(
          json.object([
            #("blobs", json.array([], json.string)),
            #("content", json.object([])),
          ]),
        ):utf8,
      >>),
    )
  case fluid_document.decode(extra, None, session, view) {
    Error(_) -> Nil
    Ok(_) -> panic as "accepted unlisted map blob"
  }
}

fn insert_entry(
  tree: fluid_summary.SummaryEntry,
  path: List(String),
  name: String,
  value: fluid_summary.SummaryEntry,
) -> fluid_summary.SummaryEntry {
  case path, tree {
    [], fluid_summary.SummaryTree(entries) ->
      fluid_summary.SummaryTree(list.append(entries, [#(name, value)]))
    [head, ..tail], fluid_summary.SummaryTree(entries) ->
      fluid_summary.SummaryTree(
        list.map(entries, fn(entry) {
          case entry.0 == head {
            True -> #(head, insert_entry(entry.1, tail, name, value))
            False -> entry
          }
        }),
      )
    _, _ -> tree
  }
}

pub fn shared_tree_summary_export_rejects_mismatched_continuation_test() {
  let assert Ok(fixture) = fixtures.load("summary-writer-matrix")
  let assert Ok(states) =
    json.parse(
      json.to_string(fixture.input),
      decode.at(["persistenceStates"], decode.list(wire.json_value_decoder())),
    )
  let assert [first, ..rest] = states
  let assert Ok(attributes) =
    json.parse(
      json.to_string(first),
      decode.dict(decode.string, wire.json_value_decoder()),
    )
  let corrupt =
    json.object([
      #(
        "input",
        json.object([
          #(
            "persistenceStates",
            json.array(
              [
                json.object(
                  dict.insert(
                    attributes,
                    "continuationEdit",
                    json.object([
                      #("path", json.array(["rating"], json.string)),
                      #(
                        "value",
                        json.object([
                          #("kind", json.string("number")),
                          #("value", json.int(999)),
                        ]),
                      ),
                    ]),
                  )
                  |> dict.to_list,
                ),
                ..rest
              ],
              fn(value) { value },
            ),
          ),
        ]),
      ),
    ])
  let assert Error(detail) = summary_export.export(corrupt, "javascript")
  detail |> string.contains("continuation edit differs") |> expect.to_be_true()
}

pub fn shared_tree_undo_redo_summary_reload_continues_without_old_handles_test() {
  undo_acceptance.assert_summary_reload_lifetime()
}

fn replace_entry(
  tree: fluid_summary.SummaryEntry,
  path: List(String),
  value: fluid_summary.SummaryEntry,
) -> fluid_summary.SummaryEntry {
  case path, tree {
    [], _ -> value
    [head, ..tail], fluid_summary.SummaryTree(entries) ->
      fluid_summary.SummaryTree(
        list.map(entries, fn(entry) {
          case entry.0 == head {
            True -> #(head, replace_entry(entry.1, tail, value))
            False -> entry
          }
        }),
      )
    _, _ -> tree
  }
}
