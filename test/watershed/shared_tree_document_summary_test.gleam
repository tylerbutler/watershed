import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import startest/expect
import watershed/channel
import watershed/fluid_ids
import watershed/runtime_core
import watershed/tree/document_summary_fixture
import watershed/tree/fixtures
import watershed/tree/runtime_fixture
import watershed/tree/summary_export
import watershed/tree_kernel
import watershed/wire
import watershed/wire/fluid_document
import watershed/wire/fluid_summary
import watershed/wire/socket
import watershed/wire/summary_blob

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
