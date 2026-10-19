//// Recovery acceptance. The main function checks fresh-process persistence.

import envoy
import gleam/bit_array
import gleam/dict
import gleam/dynamic
import gleam/dynamic/decode
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import signet/types as token
import simplifile
import spillway/message
import spillway/types
import startest/expect
import watershed/channel
import watershed/fluid_ids
import watershed/id
import watershed/recovery
import watershed/runtime_core
import watershed/sluice/frame
import watershed/tree/compression_fixture
import watershed/tree/history
import watershed/tree/identifier_fixture
import watershed/tree/runtime_fixture
import watershed/tree/types as tree_types
import watershed/tree_kernel
import watershed/wire
import watershed/wire/fluid_container
import watershed/wire/fluid_document
import watershed/wire/fluid_inbound
import watershed/wire/socket

@target(erlang)
import gleam/erlang/process
@target(javascript)
import watershed/runtime
@target(erlang)
import watershed/runtime_beam
@target(javascript)
import watershed/transport_js

fn view_id() -> fluid_ids.StableId {
  fluid_ids.stable_id("90000000-0000-4000-8000-000000000009")
  |> expect.to_be_ok()
}

fn core() -> runtime_core.Core {
  let session =
    fluid_ids.session_id("30000000-0000-4000-8000-000000000003")
    |> expect.to_be_ok()
  let root =
    identifier_fixture.full_root(
      identifier_fixture.point("child", "child"),
      [
        identifier_fixture.point("first", "first"),
        identifier_fixture.point("second", "second"),
      ],
      [],
      [],
    )
  let summary =
    fluid_document.initial_tree(
      identifier_fixture.full_stored(),
      Some(root),
      session,
      fluid_ids.stable_id("80000000-0000-4000-8000-000000000008")
        |> expect.to_be_ok(),
    )
    |> expect.to_be_ok()
  let assert runtime_core.Complete(core) =
    runtime_core.bootstrap_document(
      runtime_fixture.connected("original", [], 0),
      summary,
    )
    |> expect.to_be_ok()
  let joining =
    types.SequencedDocumentMessage(
      ..sequenced(
        wire.OutboundOperation(0, 0, "op", json.null(), None),
        "original",
        1,
      ),
      client_id: None,
      message_type: "join",
      data: Some(frame.system_join_data("original")),
    )
  let #(core, _) =
    runtime_core.handle_sequenced(core, joining) |> expect.to_be_ok()
  core
}

fn peer_core(base: runtime_core.Core) -> runtime_core.Core {
  let assert Some(summary) = base.persistence
  let summary =
    fluid_document.decode(
      fluid_document.encode(summary) |> expect.to_be_ok(),
      None,
      fluid_ids.session_id("40000000-0000-4000-8000-000000000004")
        |> expect.to_be_ok(),
      fluid_ids.stable_id("50000000-0000-4000-8000-000000000005")
        |> expect.to_be_ok(),
    )
    |> expect.to_be_ok()
  let assert runtime_core.Complete(peer) =
    runtime_core.bootstrap_document(
      runtime_fixture.connected("peer", [], 1),
      summary,
    )
    |> expect.to_be_ok()
  peer
}

fn sequenced(
  outbound: wire.OutboundOperation,
  client_id: String,
  sequence_number: Int,
) -> types.SequencedDocumentMessage(dynamic.Dynamic) {
  types.SequencedDocumentMessage(
    client_id: Some(client_id),
    sequence_number: sequence_number,
    minimum_sequence_number: 0,
    client_sequence_number: outbound.client_sequence_number,
    reference_sequence_number: outbound.reference_sequence_number,
    message_type: "op",
    contents: json.parse(json.to_string(outbound.contents), decode.dynamic)
      |> expect.to_be_ok(),
    metadata: case outbound.metadata {
      None -> None
      Some(value) ->
        Some(
          json.parse(json.to_string(value), decode.dynamic)
          |> expect.to_be_ok(),
        )
    },
    server_metadata: None,
    origin: None,
    traces: None,
    timestamp: 0,
    data: None,
  )
}

fn roundtrip(core: runtime_core.Core) -> runtime_core.Core {
  let checkpoint =
    recovery.capture(core, tenant: "default", document: "tree")
    |> expect.to_be_ok()
  let text = json.to_string(checkpoint)
  let parsed = json.parse(text, wire.json_value_decoder()) |> expect.to_be_ok()
  recovery.restore(
    parsed,
    tenant: "default",
    document: "tree",
    view_id: fluid_ids.stable_id(id.uuid_v4()) |> expect.to_be_ok(),
  )
  |> expect.to_be_ok()
}

const compressed_tree = "compression-tree-chunked-store/compression-tree-chunked-tree"

fn apply_envelopes(
  core: runtime_core.Core,
  envelopes: List(wire.SequencedEnvelope),
) -> runtime_core.Core {
  list.fold(envelopes, core, fn(core, envelope) {
    runtime_core.handle_envelope(core, envelope)
    |> expect.to_be_ok()
    |> fn(pair) { pair.0 }
  })
}

fn compressed_history(core: runtime_core.Core) {
  let assert Ok(channel.TreeState(tree)) =
    dict.get(core.channels, compressed_tree)
  let view = tree_kernel.history_view(tree)
  #(
    list.map(view.sequenced.trunk, fn(item) {
      let history.SequencedCommit(commit, point) = item
      #(fluid_ids.stable_id_to_string(commit.revision), point)
    }),
    list.map(view.pending, fn(commit) {
      fluid_ids.stable_id_to_string(commit.revision)
    }),
  )
}

fn serialized_compressor(core: runtime_core.Core) {
  let assert Some(compressor) = core.compressor
  fluid_ids.serialize(compressor, True) |> expect.to_be_ok()
}

pub fn document_recovery_retains_partial_peer_prefix_test() {
  let assert Ok(#(base, envelopes)) =
    compression_fixture.core_case("partial-summary-prefix-tail")
  let assert #(expected_prefix, 4, 1) =
    compression_fixture.summary_prefix("partial-summary-prefix-tail")
    |> expect.to_be_ok()
  let prefix = list.take(envelopes, 4)
  let tail = list.drop(envelopes, 4)
  let partial = apply_envelopes(base, prefix)
  let checkpoint =
    recovery.capture(partial, tenant: "default", document: "tree")
    |> expect.to_be_ok()
  let restored =
    recovery.restore(
      checkpoint,
      tenant: "default",
      document: "tree",
      view_id: view_id(),
    )
    |> expect.to_be_ok()
  fluid_inbound.partial_chunks(restored.inbound)
  |> expect.to_equal(expected_prefix)
  let assert Some(runtime_core.RecoveryReplay(sequenced, _)) =
    restored.recovery_replay
  fluid_inbound.partial_chunks(sequenced.inbound)
  |> expect.to_equal(expected_prefix)

  let uninterrupted = apply_envelopes(partial, tail)
  let recovered = apply_envelopes(restored, tail)
  runtime_core.tree_read(recovered, compressed_tree, [])
  |> expect.to_equal(runtime_core.tree_read(uninterrupted, compressed_tree, []))
  compressed_history(recovered)
  |> expect.to_equal(compressed_history(uninterrupted))
  recovered.in_flight |> expect.to_equal(uninterrupted.in_flight)
  serialized_compressor(recovered)
  |> expect.to_equal(serialized_compressor(uninterrupted))
  fluid_inbound.partial_chunks(recovered.inbound) |> expect.to_equal([])
}

pub fn document_recovery_partial_peer_prefix_preserves_pending_native_edits_test() {
  let assert Ok(#(base, envelopes)) =
    compression_fixture.core_case("partial-summary-prefix-tail")
  let assert [first, second, third, fourth, tail] = envelopes
  let assert Ok(#(pending, _, [first_native])) =
    runtime_core.submit_tree_edits(base, compressed_tree, [
      tree_types.SetField(["label"], tree_types.StringValue("native-first")),
    ])
  let compressor_before_prefix = serialized_compressor(pending)
  let pending = apply_envelopes(pending, [first, second])
  serialized_compressor(pending) |> expect.to_equal(compressor_before_prefix)
  let assert Ok(#(pending, _, [second_native])) =
    runtime_core.submit_tree_edits(pending, compressed_tree, [
      tree_types.SetField(["label"], tree_types.StringValue("native-second")),
    ])
  let compressor_before_more_prefix = serialized_compressor(pending)
  let partial = apply_envelopes(pending, [third, fourth])
  partial.in_flight |> list.length |> expect.to_equal(2)
  serialized_compressor(partial)
  |> expect.to_equal(compressor_before_more_prefix)

  let checkpoint =
    recovery.capture(partial, tenant: "default", document: "tree")
    |> expect.to_be_ok()
  let once =
    recovery.restore(
      checkpoint,
      tenant: "default",
      document: "tree",
      view_id: view_id(),
    )
    |> expect.to_be_ok()
  let repeated =
    recovery.capture(once, tenant: "default", document: "tree")
    |> expect.to_be_ok()
    |> recovery.restore(
      tenant: "default",
      document: "tree",
      view_id: fluid_ids.stable_id("70000000-0000-4000-8000-000000000008")
        |> expect.to_be_ok(),
    )
    |> expect.to_be_ok()
  fluid_inbound.partial_chunks(repeated.inbound)
  |> expect.to_equal(fluid_inbound.partial_chunks(partial.inbound))

  let uninterrupted = apply_envelopes(partial, [tail])
  let recovered = apply_envelopes(repeated, [tail])
  recovered.in_flight |> list.length |> expect.to_equal(2)
  runtime_core.tree_read(recovered, compressed_tree, [])
  |> expect.to_equal(runtime_core.tree_read(uninterrupted, compressed_tree, []))
  compressed_history(recovered)
  |> expect.to_equal(compressed_history(uninterrupted))
  serialized_compressor(recovered)
  |> expect.to_equal(serialized_compressor(uninterrupted))

  let accepted_first = sequenced(first_native, "compression-reader", 205)
  let recovered =
    runtime_core.handle_sequenced(recovered, accepted_first)
    |> expect.to_be_ok()
    |> fn(pair) { pair.0 }
  recovered.in_flight |> list.length |> expect.to_equal(1)
  let assert Ok(#(resubmitted, [remaining])) = runtime_core.resubmit(recovered)
  let assert Some(expected_metadata) = second_native.metadata
  let assert Some(actual_metadata) = remaining.metadata
  json_field(actual_metadata, "batchId")
  |> expect.to_equal(json_field(expected_metadata, "batchId"))
  let accepted_second = sequenced(remaining, resubmitted.client_id, 206)
  let settled =
    runtime_core.handle_sequenced(resubmitted, accepted_second)
    |> expect.to_be_ok()
    |> fn(pair) { pair.0 }
  settled.in_flight |> expect.to_equal([])
  let assert Some(compressor) = settled.compressor
  let _ = fluid_ids.generate(compressor) |> expect.to_be_ok()
  Nil
}

pub fn document_recovery_sender_leave_clears_restored_prefix_test() {
  let assert Ok(#(base, envelopes)) =
    compression_fixture.core_case("partial-summary-prefix-tail")
  let joined =
    types.SequencedDocumentMessage(
      ..sequenced(
        wire.OutboundOperation(0, 0, "op", json.null(), None),
        "summary-sender",
        200,
      ),
      client_id: None,
      message_type: "join",
      data: Some(frame.system_join_data("summary-sender")),
    )
  let base =
    runtime_core.handle_sequenced(base, joined)
    |> expect.to_be_ok()
    |> fn(pair) { pair.0 }
  let shifted =
    list.map(envelopes, fn(envelope) {
      wire.SequencedEnvelope(
        ..envelope,
        message: types.SequencedDocumentMessage(
          ..envelope.message,
          sequence_number: envelope.message.sequence_number + 1,
        ),
      )
    })
  let partial = apply_envelopes(base, list.take(shifted, 4))
  let restored = roundtrip(partial)
  let leave =
    types.SequencedDocumentMessage(
      ..sequenced(
        wire.OutboundOperation(0, 0, "op", json.null(), None),
        "summary-sender",
        205,
      ),
      client_id: None,
      message_type: "leave",
      data: Some(frame.system_leave_data("summary-sender")),
    )
  let cleared =
    runtime_core.handle_sequenced(restored, leave)
    |> expect.to_be_ok()
    |> fn(pair) { pair.0 }
  fluid_inbound.partial_chunks(cleared.inbound) |> expect.to_equal([])
  cleared.recovery_replay |> expect.to_equal(None)
}

pub fn document_recovery_rejects_malformed_and_overlimit_peer_prefix_test() {
  let assert Ok(#(base, envelopes)) =
    compression_fixture.core_case("partial-summary-prefix-tail")
  let partial = apply_envelopes(base, list.take(envelopes, 4))
  let checkpoint =
    recovery.capture(partial, tenant: "default", document: "tree")
    |> expect.to_be_ok()
  checkpoint_chunk_blob(checkpoint) |> expect.to_be_some()

  recovery.restore(
    replace_checkpoint_chunk_blob(
      checkpoint,
      bit_array.base64_encode(<<"not json":utf8>>, True),
    ),
    tenant: "default",
    document: "tree",
    view_id: view_id(),
  )
  |> expect.to_be_error()

  let too_many =
    json.array(
      [
        json.array(
          [
            json.string("summary-sender"),
            json.array(list.repeat("x", times: 129), json.string),
          ],
          fn(value) { value },
        ),
      ],
      fn(value) { value },
    )
  recovery.restore(
    replace_checkpoint_chunk_blob(
      checkpoint,
      bit_array.base64_encode(<<json.to_string(too_many):utf8>>, True),
    ),
    tenant: "default",
    document: "tree",
    view_id: view_id(),
  )
  |> expect.to_be_error()
  Nil
}

pub fn document_recovery_pending_move_and_edit_survive_file_restart_test() {
  let assert Ok(#(moved, _, [_])) =
    runtime_core.submit_tree_edits(core(), "A/_C", [
      tree_types.ArrayMove(["left"], 0, 1, ["right"], 0),
    ])
  let assert Ok(#(pending, _, [_])) =
    runtime_core.submit_tree_edits(moved, "A/_C", [
      tree_types.SetField(
        ["right", "0", "label"],
        tree_types.StringValue("edited"),
      ),
    ])
  let checkpoint =
    recovery.capture(pending, tenant: "default", document: "tree")
    |> expect.to_be_ok()
  let path = "/tmp/watershed-document-recovery-" <> id.uuid_v4() <> ".json"
  simplifile.write(path, json.to_string(checkpoint)) |> expect.to_be_ok()
  let encoded = simplifile.read(path) |> expect.to_be_ok()
  simplifile.delete(path) |> expect.to_be_ok()
  let restored =
    recovery.restore(
      json.parse(encoded, wire.json_value_decoder()) |> expect.to_be_ok(),
      tenant: "default",
      document: "tree",
      view_id: view_id(),
    )
    |> expect.to_be_ok()
  runtime_core.tree_read(restored, "A/_C", [])
  |> expect.to_equal(runtime_core.tree_read(pending, "A/_C", []))
  runtime_core.tree_read(restored, "A/_C", ["right", "0", "label"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("edited"))))
  list.map(restored.in_flight, fn(entry) {
    let assert runtime_core.InFlightBatch(
      client_id: client_id,
      client_sequence_number: csn,
      batch_id: batch_id,
      ..,
    ) = entry
    #(client_id, csn, batch_id)
  })
  |> expect.to_equal([
    #("original", 1, Some("original_[1]")),
    #("original", 2, Some("original_[2]")),
  ])
  let assert Some(before) = pending.compressor
  let assert Some(after) = restored.compressor
  fluid_ids.serialize(after, True)
  |> expect.to_equal(fluid_ids.serialize(before, True))
  let assert Ok(#(_, outbounds)) = runtime_core.resubmit(restored)
  list.length(outbounds) |> expect.to_equal(2)
}

pub fn document_recovery_original_ack_does_not_duplicate_move_test() {
  let assert Ok(#(pending, _, [outbound])) =
    runtime_core.submit_tree_edits(core(), "A/_C", [
      tree_types.ArrayMove(["left"], 0, 1, ["right"], 0),
    ])
  let restored = roundtrip(pending)
  let assert Ok(#(acknowledged, _)) =
    runtime_core.handle_sequenced(restored, sequenced(outbound, "original", 2))
  acknowledged.in_flight |> expect.to_equal([])
  runtime_core.tree_read(acknowledged, "A/_C", [])
  |> expect.to_equal(runtime_core.tree_read(pending, "A/_C", []))
  let assert Ok(#(_, outbounds)) = runtime_core.resubmit(acknowledged)
  outbounds |> expect.to_equal([])
}

fn membership_message(
  client: String,
  sequence_number: Int,
  joined: Bool,
) -> types.SequencedDocumentMessage(dynamic.Dynamic) {
  types.SequencedDocumentMessage(
    ..sequenced(
      wire.OutboundOperation(0, 0, "op", json.null(), None),
      client,
      sequence_number,
    ),
    client_id: None,
    message_type: case joined {
      True -> "join"
      False -> "leave"
    },
    data: Some(case joined {
      True -> frame.system_join_data(client)
      False -> frame.system_leave_data(client)
    }),
  )
}

fn recover_after_intervening_reconnect(
  accepted_count: Int,
  remote_before_resubmit: Bool,
  remote_after_resubmit: Bool,
) {
  let base = core()
  let #(pending, _, _) =
    runtime_core.submit_tree_edits(base, "A/_C", [
      tree_types.ArrayMove(["left"], 0, 1, ["right"], 0),
    ])
    |> expect.to_be_ok()
  let #(pending, _, _) =
    runtime_core.submit_tree_edits(pending, "A/_C", [
      tree_types.SetField(
        ["right", "0", "label"],
        tree_types.StringValue("edited"),
      ),
    ])
    |> expect.to_be_ok()
  let restored = roundtrip(pending)
  let reconnected =
    runtime_core.adopt_reconnect(
      pending,
      runtime_fixture.connected("intervening", [], 3),
    )
    |> expect.to_be_ok()
  let prefix = [
    membership_message("original", 2, False),
    membership_message("intervening", 3, True),
  ]
  let #(prefix, later_peer) = case remote_before_resubmit {
    True -> {
      let assert #(peer, _, [remote]) =
        runtime_core.submit_tree_edits(peer_core(base), "A/_C", [
          tree_types.ArrayInsert(["left"], 0, [
            identifier_fixture.point("peer-prefix", "peer-prefix"),
          ]),
        ])
        |> expect.to_be_ok()
      let later = case remote_after_resubmit {
        True -> {
          let assert #(_, _, [later]) =
            runtime_core.submit_tree_edits(peer, "A/_C", [
              tree_types.ArrayInsert(["left"], 0, [
                identifier_fixture.point("peer-later", "peer-later"),
              ]),
            ])
            |> expect.to_be_ok()
          [sequenced(later, "peer", 5)]
        }
        False -> []
      }
      #(list.append(prefix, [sequenced(remote, "peer", 4)]), later)
    }
    False -> #(prefix, [])
  }
  let first_sequence = case remote_before_resubmit, remote_after_resubmit {
    True, True -> 6
    True, False -> 5
    False, _ -> 4
  }
  let reconnected =
    list.fold(prefix, reconnected, fn(state, message) {
      runtime_core.handle_sequenced(state, message)
      |> expect.to_be_ok()
      |> fn(pair) { pair.0 }
    })
  let #(reconnected, submissions) =
    runtime_core.resubmit(runtime_core.go_live(reconnected))
    |> expect.to_be_ok()
  list.length(submissions) |> expect.to_equal(2)
  let submissions = case accepted_count == 3 {
    True -> {
      let #(_, _, later) =
        runtime_core.submit_tree_edits(reconnected, "A/_C", [
          tree_types.ArrayInsert(["right"], 1, [
            identifier_fixture.point("later", "later"),
          ]),
        ])
        |> expect.to_be_ok()
      list.append(submissions, later)
    }
    False -> submissions
  }
  let accepted =
    submissions
    |> list.take(accepted_count)
    |> list.index_map(fn(outbound, index) {
      sequenced(outbound, "intervening", first_sequence + index)
    })
  case remote_after_resubmit {
    True -> {
      let _ =
        list.fold(
          list.append(later_peer, accepted),
          reconnected,
          fn(state, message) {
            runtime_core.handle_sequenced(state, message)
            |> expect.to_be_ok()
            |> fn(pair) { pair.0 }
          },
        )
      Nil
    }
    False -> Nil
  }
  let checkpoint = first_sequence + accepted_count + 1
  let restored =
    runtime_core.adopt_reconnect(
      restored,
      runtime_fixture.connected("recovered", [], checkpoint),
    )
    |> expect.to_be_ok()
  let restored =
    list.fold(
      list.append(
        list.append(prefix, later_peer),
        list.append(accepted, [
          membership_message("intervening", checkpoint - 1, False),
          membership_message("recovered", checkpoint, True),
        ]),
      ),
      restored,
      fn(state, message) {
        runtime_core.handle_sequenced(state, message)
        |> expect.to_be_ok()
        |> fn(pair) { pair.0 }
      },
    )
  runtime_core.reconnect_ready(restored, checkpoint) |> expect.to_equal(True)
  let #(restored, resubmissions) =
    runtime_core.resubmit(runtime_core.go_live(restored))
    |> expect.to_be_ok()
  list.length(resubmissions)
  |> expect.to_equal(case accepted_count {
    3 -> 0
    _ -> 2 - accepted_count
  })
  let restored =
    list.index_fold(resubmissions, restored, fn(state, outbound, index) {
      runtime_core.handle_sequenced(
        state,
        sequenced(outbound, "recovered", checkpoint + index + 1),
      )
      |> expect.to_be_ok()
      |> fn(pair) { pair.0 }
    })
  restored.in_flight |> expect.to_equal([])
  let second_index = case remote_before_resubmit, remote_after_resubmit {
    True, True -> "2"
    True, False -> "1"
    False, _ -> "0"
  }
  runtime_core.tree_read(restored, "A/_C", ["left", second_index, "label"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("second"))))
  runtime_core.tree_read(restored, "A/_C", ["right", "0", "label"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("edited"))))
  case accepted_count == 3 {
    True ->
      runtime_core.tree_read(restored, "A/_C", ["right", "1", "label"])
      |> expect.to_equal(Ok(Some(tree_types.StringValue("later"))))
    False -> Nil
  }
  let assert #(continued, _, [outbound]) =
    runtime_core.submit_tree_edits(restored, "A/_C", [
      tree_types.ArrayInsert(["right"], 1, [
        identifier_fixture.point("continued", "continued"),
      ]),
    ])
    |> expect.to_be_ok()
  let resumed_again = roundtrip(continued)
  runtime_core.tree_read(resumed_again, "A/_C", ["right", "1", "label"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("continued"))))
  let #(settled_again, _) =
    runtime_core.handle_sequenced(
      resumed_again,
      sequenced(outbound, "recovered", continued.last_seen_sequence_number + 1),
    )
    |> expect.to_be_ok()
  settled_again.in_flight |> expect.to_equal([])
  let #(_, _, outbounds) =
    runtime_core.submit_tree_edits(runtime_core.go_live(settled_again), "A/_C", [
      tree_types.ArrayInsert(["right"], 2, [
        identifier_fixture.point("continued-again", "continued-again"),
      ]),
    ])
    |> expect.to_be_ok()
  list.length(outbounds) |> expect.to_equal(1)
}

pub fn document_recovery_accepts_resubmissions_after_intervening_reconnect_test() {
  recover_after_intervening_reconnect(2, False, False)
}

pub fn document_recovery_resubmits_only_suffix_after_intervening_reconnect_test() {
  recover_after_intervening_reconnect(1, False, False)
}

pub fn document_recovery_intervening_reconnect_preserves_newer_allocations_test() {
  recover_after_intervening_reconnect(3, False, False)
}

pub fn document_recovery_accepts_rebased_intervening_resubmissions_test() {
  recover_after_intervening_reconnect(2, True, False)
}

pub fn document_recovery_resubmits_rebased_suffix_after_intervening_reconnect_test() {
  recover_after_intervening_reconnect(1, True, False)
}

pub fn document_recovery_accepts_resubmissions_before_latest_replayed_peer_edit_test() {
  recover_after_intervening_reconnect(2, True, True)
}

pub fn document_recovery_reconstructs_partial_prefix_at_its_authoring_sequence_test() {
  recover_after_intervening_reconnect(1, True, True)
}

pub fn document_recovery_rejects_different_changes_with_matching_batch_identity_test() {
  let base = core()
  let #(pending, _, _) =
    runtime_core.submit_tree_edits(base, "A/_C", [
      tree_types.ArrayMove(["left"], 0, 1, ["right"], 0),
    ])
    |> expect.to_be_ok()
  let assert #(_, _, [foreign]) =
    runtime_core.submit_tree_edits(
      runtime_core.Core(..base, client_id: "foreign"),
      "A/_C",
      [tree_types.ArrayRemove(["left"], 0, 1)],
    )
    |> expect.to_be_ok()
  let assert Some(metadata) = foreign.metadata
  let forged =
    wire.OutboundOperation(
      ..foreign,
      metadata: Some(replace_field(
        metadata,
        "batchId",
        json.string("original_[1]"),
      )),
    )
  let restored = roundtrip(pending)
  runtime_core.handle_sequenced(restored, sequenced(forged, "foreign", 2))
  |> expect.to_be_error()
  Nil
}

pub fn document_recovery_replays_accepted_edits_after_last_checkpoint_test() {
  let assert Ok(#(pending, _, [move])) =
    runtime_core.submit_tree_edits(core(), "A/_C", [
      tree_types.ArrayMove(["left"], 0, 1, ["right"], 0),
    ])
  let restored = roundtrip(pending)
  let assert Ok(#(_, _, [later])) =
    runtime_core.submit_tree_edits(pending, "A/_C", [
      tree_types.ArrayInsert(["right"], 1, [
        identifier_fixture.point("later", "later"),
      ]),
    ])
  let #(restored, _) =
    runtime_core.handle_sequenced(restored, sequenced(move, "original", 2))
    |> expect.to_be_ok()
  let #(restored, _) =
    runtime_core.handle_sequenced(restored, sequenced(later, "original", 3))
    |> expect.to_be_ok()
  runtime_core.tree_read(restored, "A/_C", ["right", "1", "label"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("later"))))
  let #(_, _, outbounds) =
    runtime_core.submit_tree_edits(runtime_core.go_live(restored), "A/_C", [
      tree_types.ArrayInsert(["right"], 2, [
        identifier_fixture.point("continued", "continued"),
      ]),
    ])
    |> expect.to_be_ok()
  list.length(outbounds) |> expect.to_equal(1)
}

pub fn document_recovery_settled_checkpoint_replays_later_allocations_test() {
  let base = core()
  let restored = roundtrip(base)
  let assert Ok(#(_, _, [later])) =
    runtime_core.submit_tree_edits(base, "A/_C", [
      tree_types.ArrayInsert(["right"], 0, [
        identifier_fixture.point("later", "later"),
      ]),
    ])
  let #(restored, _) =
    runtime_core.handle_sequenced(restored, sequenced(later, "original", 2))
    |> expect.to_be_ok()
  runtime_core.tree_read(restored, "A/_C", ["right", "0", "label"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("later"))))
  let #(_, _, outbounds) =
    runtime_core.submit_tree_edits(
      roundtrip(runtime_core.go_live(restored)),
      "A/_C",
      [
        tree_types.ArrayInsert(["right"], 1, [
          identifier_fixture.point("continued", "continued"),
        ]),
      ],
    )
    |> expect.to_be_ok()
  list.length(outbounds) |> expect.to_equal(1)
}

pub fn document_recovery_settled_checkpoint_waits_for_old_session_leave_test() {
  let base = core()
  let assert Ok(#(_, _, [later])) =
    runtime_core.submit_tree_edits(base, "A/_C", [
      tree_types.ArrayInsert(["right"], 0, [
        identifier_fixture.point("later", "later"),
      ]),
    ])
  let restored =
    runtime_core.adopt_reconnect(
      roundtrip(base),
      runtime_fixture.connected("recovered", [], 2),
    )
    |> expect.to_be_ok()
  let joined =
    types.SequencedDocumentMessage(
      ..sequenced(later, "original", 2),
      client_id: None,
      message_type: "join",
      data: Some(frame.system_join_data("recovered")),
    )
  let #(restored, _) =
    runtime_core.handle_sequenced(restored, joined) |> expect.to_be_ok()
  runtime_core.reconnect_ready(restored, 2) |> expect.to_equal(False)
  let #(restored, _) =
    runtime_core.handle_sequenced(restored, sequenced(later, "original", 3))
    |> expect.to_be_ok()
  runtime_core.reconnect_ready(restored, 2) |> expect.to_equal(False)
  let #(restored, _) =
    runtime_core.handle_sequenced(
      restored,
      types.SequencedDocumentMessage(
        ..joined,
        sequence_number: 4,
        message_type: "leave",
        data: Some(frame.system_leave_data("original")),
      ),
    )
    |> expect.to_be_ok()
  runtime_core.reconnect_ready(restored, 2) |> expect.to_equal(True)
  runtime_core.tree_read(restored, "A/_C", ["right", "0", "label"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("later"))))
}

pub fn document_recovery_rejects_wrong_document_and_unsupported_version_test() {
  let checkpoint =
    recovery.capture(core(), tenant: "default", document: "tree")
    |> expect.to_be_ok()
  recovery.restore(
    checkpoint,
    tenant: "other",
    document: "tree",
    view_id: view_id(),
  )
  |> expect.to_be_error()
  recovery.restore(
    checkpoint,
    tenant: "default",
    document: "other",
    view_id: view_id(),
  )
  |> expect.to_be_error()
  recovery.restore(
    json.object([#("version", json.int(2))]),
    tenant: "default",
    document: "tree",
    view_id: view_id(),
  )
  |> expect.to_be_error()
  Nil
}

pub fn document_recovery_rejects_pending_non_tree_operations_test() {
  let assert Ok(#(pending, _, [_])) =
    runtime_core.set(core(), "A/root", "unsaved", json.string("value"))
  recovery.capture(pending, tenant: "default", document: "tree")
  |> expect.to_be_error()
  Nil
}

fn replace_field(data: json.Json, key: String, value: json.Json) -> json.Json {
  json.parse(
    json.to_string(data),
    decode.dict(decode.string, wire.json_value_decoder()),
  )
  |> expect.to_be_ok()
  |> dict.insert(key, value)
  |> dict.to_list
  |> json.object
}

fn json_field(data: json.Json, key: String) -> json.Json {
  json.parse(json.to_string(data), decode.at([key], wire.json_value_decoder()))
  |> expect.to_be_ok()
}

fn checkpoint_chunk_blob(checkpoint: json.Json) {
  checkpoint
  |> json_field("summary")
  |> json_field("tree")
  |> summary_evidence_blob(".chunks")
}

fn summary_evidence_blob(entry: json.Json, name: String) {
  let kind =
    json.parse(json.to_string(entry), decode.at(["type"], decode.string))
    |> expect.to_be_ok()
  case kind {
    "blob" -> None
    "tree" -> {
      let entries =
        json.parse(
          json.to_string(entry),
          decode.at(
            ["entries"],
            decode.list(decode.list(wire.json_value_decoder())),
          ),
        )
        |> expect.to_be_ok()
      entries
      |> list.filter_map(fn(pair) {
        case pair {
          [key, value] -> {
            let key =
              json.parse(json.to_string(key), decode.string)
              |> expect.to_be_ok()
            case key == name {
              True ->
                json.parse(
                  json.to_string(value),
                  decode.at(["base64"], decode.string),
                )
                |> expect.to_be_ok()
                |> Ok
              False ->
                case summary_evidence_blob(value, name) {
                  Some(found) -> Ok(found)
                  None -> Error(Nil)
                }
            }
          }
          _ -> Error(Nil)
        }
      })
      |> list.first
      |> fn(found) {
        case found {
          Ok(value) -> Some(value)
          Error(_) -> None
        }
      }
    }
    _ -> None
  }
}

fn replace_checkpoint_chunk_blob(
  checkpoint: json.Json,
  replacement: String,
) -> json.Json {
  let summary = json_field(checkpoint, "summary")
  replace_field(
    checkpoint,
    "summary",
    replace_field(
      summary,
      "tree",
      replace_summary_evidence_blob(
        json_field(summary, "tree"),
        ".chunks",
        replacement,
      ),
    ),
  )
}

fn replace_summary_evidence_blob(
  entry: json.Json,
  name: String,
  replacement: String,
) -> json.Json {
  let kind =
    json.parse(json.to_string(entry), decode.at(["type"], decode.string))
    |> expect.to_be_ok()
  case kind {
    "tree" -> {
      let entries =
        json.parse(
          json.to_string(entry),
          decode.at(
            ["entries"],
            decode.list(decode.list(wire.json_value_decoder())),
          ),
        )
        |> expect.to_be_ok()
      replace_field(
        entry,
        "entries",
        json.array(entries, fn(pair) {
          case pair {
            [key, value] -> {
              let value = case
                json.to_string(key) == json.to_string(json.string(name))
              {
                True ->
                  json.object([
                    #("type", json.string("blob")),
                    #("base64", json.string(replacement)),
                  ])
                False -> replace_summary_evidence_blob(value, name, replacement)
              }
              json.array([key, value], fn(value) { value })
            }
            _ -> json.array(pair, fn(value) { value })
          }
        }),
      )
    }
    _ -> entry
  }
}

pub fn document_recovery_rejects_unretained_local_ancestry_test() {
  let #(checkpoint, _) = saved_move()
  let trees =
    json.parse(
      json.to_string(checkpoint),
      decode.at(["trees"], decode.list(wire.json_value_decoder())),
    )
    |> expect.to_be_ok()
  let assert [tree] = trees
  let state = json_field(tree, "state")
  let corrupt_history =
    replace_field(
      json_field(state, "history"),
      "localBase",
      json.object([
        #("value", json.string("70000000-0000-4000-8000-000000000007")),
      ]),
    )
  let corrupt_tree =
    replace_field(
      tree,
      "state",
      replace_field(state, "history", corrupt_history),
    )
  recovery.restore(
    replace_field(
      checkpoint,
      "trees",
      json.array([corrupt_tree], fn(value) { value }),
    ),
    tenant: "default",
    document: "tree",
    view_id: view_id(),
  )
  |> expect.to_be_error()
  Nil
}

pub fn document_recovery_rejects_reordered_pending_revisions_test() {
  let assert Ok(#(moved, _, [_])) =
    runtime_core.submit_tree_edits(core(), "A/_C", [
      tree_types.ArrayMove(["left"], 0, 1, ["right"], 0),
    ])
  let assert Ok(#(pending, _, [_])) =
    runtime_core.submit_tree_edits(moved, "A/_C", [
      tree_types.SetField(
        ["right", "0", "label"],
        tree_types.StringValue("edited"),
      ),
    ])
  let checkpoint =
    recovery.capture(pending, tenant: "default", document: "tree")
    |> expect.to_be_ok()
  let assert [first, second] =
    json.parse(
      json.to_string(checkpoint),
      decode.at(["submissions"], decode.list(wire.json_value_decoder())),
    )
    |> expect.to_be_ok()
  let swapped = [
    replace_field(first, "items", json_field(second, "items")),
    replace_field(second, "items", json_field(first, "items")),
  ]
  recovery.restore(
    replace_field(
      checkpoint,
      "submissions",
      json.array(swapped, fn(value) { value }),
    ),
    tenant: "default",
    document: "tree",
    view_id: view_id(),
  )
  |> expect.to_be_error()
  Nil
}

pub fn document_recovery_rejects_malformed_rollback_destroys_test() {
  let #(checkpoint, _) = saved_move()
  let assert [tree] =
    json.parse(
      json.to_string(checkpoint),
      decode.at(["trees"], decode.list(wire.json_value_decoder())),
    )
    |> expect.to_be_ok()
  let state = json_field(tree, "state")
  let history = json_field(state, "history")
  let assert [pending] =
    json.parse(
      json.to_string(history),
      decode.at(["pending"], decode.list(wire.json_value_decoder())),
    )
    |> expect.to_be_ok()
  let assert [node, commit] =
    json.parse(
      json.to_string(json_field(pending, "original")),
      decode.list(wire.json_value_decoder()),
    )
    |> expect.to_be_ok()
  let destroy = fn(local_id, count) {
    json.array(
      [
        json.array([json.null(), json.int(local_id)], fn(value) { value }),
        json.int(count),
      ],
      fn(value) { value },
    )
  }
  [
    json.null(),
    json.array([], fn(value) { value }),
    json.array(
      [json.array([], fn(value) { value }), json.array([], fn(value) { value })],
      fn(value) { value },
    ),
    json.array([json.array([destroy(-1, 1)], fn(value) { value })], fn(value) {
      value
    }),
    json.array([json.array([destroy(0, 0)], fn(value) { value })], fn(value) {
      value
    }),
    json.array(
      [json.array([destroy(0, 2), destroy(1, 1)], fn(value) { value })],
      fn(value) { value },
    ),
  ]
  |> list.each(fn(destroys) {
    let commit =
      replace_field(
        commit,
        "changes",
        replace_field(json_field(commit, "changes"), "destroys", destroys),
      )
    let pending =
      replace_field(
        pending,
        "original",
        json.array([node, commit], fn(value) { value }),
      )
    let history =
      replace_field(
        history,
        "pending",
        json.array([pending], fn(value) { value }),
      )
    let tree =
      replace_field(tree, "state", replace_field(state, "history", history))
    recovery.restore(
      replace_field(
        checkpoint,
        "trees",
        json.array([tree], fn(value) { value }),
      ),
      tenant: "default",
      document: "tree",
      view_id: view_id(),
    )
    |> expect.to_be_error()
    Nil
  })
}

fn replace_submission_field(
  checkpoint: json.Json,
  key: String,
  value: json.Json,
) -> json.Json {
  let assert [submission] =
    json.parse(
      json.to_string(checkpoint),
      decode.at(["submissions"], decode.list(wire.json_value_decoder())),
    )
    |> expect.to_be_ok()
  let items =
    json.parse(
      json.to_string(submission),
      decode.at(["items"], decode.list(wire.json_value_decoder())),
    )
    |> expect.to_be_ok()
    |> list.map(fn(item) {
      let batch = fluid_container.decode(item, None) |> expect.to_be_ok()
      let assert [fluid_container.ContainerMessage(kind, 0, _)] = batch.messages
      case kind {
        fluid_container.ChannelOperation(route, contents) ->
          fluid_container.encode(fluid_container.ChannelOperation(
            route,
            replace_field(contents, key, value),
          ))
          |> expect.to_be_ok()
        _ -> item
      }
    })
  replace_field(
    checkpoint,
    "submissions",
    json.array(
      [
        replace_field(
          submission,
          "items",
          json.array(items, fn(value) { value }),
        ),
      ],
      fn(value) { value },
    ),
  )
}

pub fn document_recovery_rejects_malformed_submission_change_test() {
  let #(checkpoint, _) = saved_move()
  recovery.restore(
    replace_submission_field(checkpoint, "changeset", json.string("invalid")),
    tenant: "default",
    document: "tree",
    view_id: view_id(),
  )
  |> expect.to_be_error()
  Nil
}

pub fn document_recovery_rejects_unsupported_submission_metadata_test() {
  let #(checkpoint, _) = saved_move()
  [
    #("customMetadata", json.object([#("m", json.string("unsupported"))])),
    #("extra", json.bool(True)),
  ]
  |> list.each(fn(field) {
    recovery.restore(
      replace_submission_field(checkpoint, field.0, field.1),
      tenant: "default",
      document: "tree",
      view_id: view_id(),
    )
    |> expect.to_be_error()
    Nil
  })
}

pub fn document_recovery_coalesced_move_and_edit_ack_once_test() {
  let assert Ok(#(moved, _, [move])) =
    runtime_core.submit_tree_edits(core(), "A/_C", [
      tree_types.ArrayMove(["left"], 0, 1, ["right"], 0),
    ])
  let assert Ok(#(pending, _, [edit])) =
    runtime_core.submit_tree_edits(moved, "A/_C", [
      tree_types.SetField(
        ["right", "0", "label"],
        tree_types.StringValue("edited"),
      ),
    ])
  let assert Ok(#(coalesced, [outbound])) =
    runtime_core.coalesce_outbound_operations(pending, [move, edit])
  let restored = roundtrip(coalesced)
  let assert Ok(#(acknowledged, _)) =
    runtime_core.handle_sequenced(restored, sequenced(outbound, "original", 2))
  acknowledged.in_flight |> expect.to_equal([])
  runtime_core.tree_read(acknowledged, "A/_C", ["right", "0", "label"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("edited"))))
}

pub fn document_recovery_rejects_missing_batch_identity_test() {
  let #(checkpoint, _) = saved_move()
  let submissions =
    json.parse(
      json.to_string(checkpoint),
      decode.at(["submissions"], decode.list(wire.json_value_decoder())),
    )
    |> expect.to_be_ok()
  let assert [submission] = submissions
  let corrupt =
    replace_field(
      checkpoint,
      "submissions",
      json.array([replace_field(submission, "batchId", json.null())], fn(value) {
        value
      }),
    )
  recovery.restore(
    corrupt,
    tenant: "default",
    document: "tree",
    view_id: view_id(),
  )
  |> expect.to_be_error()
  Nil
}

pub fn document_recovery_accepts_finalized_capacity_without_batch_id_test() {
  let assert Ok(#(pending, _, [move])) =
    runtime_core.submit_tree_edits(core(), "A/_C", [
      tree_types.ArrayMove(["left"], 0, 1, ["right"], 0),
    ])
  let assert Ok(#(acknowledged, _)) =
    runtime_core.handle_sequenced(pending, sequenced(move, "original", 2))
  let assert Ok(#(edited, _, [edit])) =
    runtime_core.submit_tree_edits(acknowledged, "A/_C", [
      tree_types.SetField(
        ["right", "0", "label"],
        tree_types.StringValue("later"),
      ),
    ])
  let restored = roundtrip(edited)
  let assert Ok(#(accepted, _)) =
    runtime_core.handle_sequenced(restored, sequenced(edit, "original", 3))
  accepted.in_flight |> expect.to_equal([])
  runtime_core.tree_read(accepted, "A/_C", ["right", "0", "label"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("later"))))
}

pub fn document_recovery_pending_insert_restores_and_acknowledges_test() {
  let assert Ok(#(pending, _, [insert])) =
    runtime_core.submit_tree_edits(core(), "A/_C", [
      tree_types.ArrayInsert(["right"], 0, [
        identifier_fixture.point("inserted", "inserted"),
      ]),
    ])
  let restored = roundtrip(pending)
  runtime_core.tree_read(restored, "A/_C", ["right", "0", "label"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("inserted"))))
  let assert Ok(#(accepted, _)) =
    runtime_core.handle_sequenced(restored, sequenced(insert, "original", 2))
  accepted.in_flight |> expect.to_equal([])
}

pub fn document_recovery_rebased_resubmission_remains_checkpointable_test() {
  let base = core()
  let assert Some(summary) = base.persistence
  let summary = fluid_document.encode(summary) |> expect.to_be_ok()
  let peer_summary =
    fluid_document.decode(
      summary,
      None,
      fluid_ids.session_id("40000000-0000-4000-8000-000000000004")
        |> expect.to_be_ok(),
      fluid_ids.stable_id("50000000-0000-4000-8000-000000000005")
        |> expect.to_be_ok(),
    )
    |> expect.to_be_ok()
  let assert runtime_core.Complete(peer) =
    runtime_core.bootstrap_document(
      runtime_fixture.connected("peer", [], 1),
      peer_summary,
    )
    |> expect.to_be_ok()
  let assert Ok(#(pending, _, [_])) =
    runtime_core.submit_tree_edits(base, "A/_C", [
      tree_types.ArrayMove(["left"], 0, 1, ["right"], 0),
    ])
  let assert Ok(#(_, _, [remote])) =
    runtime_core.submit_tree_edits(peer, "A/_C", [
      tree_types.SetField(["child", "label"], tree_types.StringValue("peer")),
    ])
  let assert Ok(#(rebased, _)) =
    runtime_core.handle_sequenced(
      roundtrip(pending),
      sequenced(remote, "peer", 2),
    )
  let assert Ok(#(resubmitted, [outbound])) = runtime_core.resubmit(rebased)
  let restored = roundtrip(resubmitted)
  runtime_core.tree_read(restored, "A/_C", ["right", "0", "label"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("first"))))
  runtime_core.tree_read(restored, "A/_C", ["child", "label"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("peer"))))
  let assert Ok(#(accepted, _)) =
    runtime_core.handle_sequenced(restored, sequenced(outbound, "original", 3))
  accepted.in_flight |> expect.to_equal([])
}

pub fn document_recovery_rejects_missing_tree_or_submission_test() {
  let #(checkpoint, _) = saved_move()
  list.each(["trees", "submissions"], fn(key) {
    recovery.restore(
      replace_field(checkpoint, key, json.array([], fn(value) { value })),
      tenant: "default",
      document: "tree",
      view_id: view_id(),
    )
    |> expect.to_be_error()
    Nil
  })
}

fn connect_message() -> message.ConnectMessage {
  message.ConnectMessage(
    tenant_id: "default",
    document_id: "tree",
    token: Some("fresh-token-not-in-checkpoint"),
    client: types.Client(
      mode: types.WriteMode,
      details: types.ClientDetails(
        types.ClientCapabilities(True),
        None,
        None,
        None,
      ),
      permission: [],
      user: token.User("recovering", dict.new()),
      scopes: ["doc:read", "doc:write"],
      timestamp: None,
    ),
    versions: ["^0.1.0"],
    driver_version: None,
    mode: types.WriteMode,
    nonce: None,
    epoch: None,
    supported_features: None,
    relay_user_agent: None,
  )
}

fn handshake() -> json.Json {
  frame.encode_connected(
    client_id: "recovered",
    tenant_id: "default",
    document_id: "tree",
    scopes: ["doc:read", "doc:write"],
    checkpoint_sequence_number: 4,
    initial_clients: ["recovered"],
    initial_messages: [],
    timestamp: 0,
    presence_v1: False,
  )
}

fn saved_move() {
  let assert Ok(#(pending, _, [outbound])) =
    runtime_core.submit_tree_edits(core(), "A/_C", [
      tree_types.ArrayMove(["left"], 0, 1, ["right"], 0),
    ])
  #(
    recovery.capture(pending, tenant: "default", document: "tree")
      |> expect.to_be_ok(),
    outbound,
  )
}

fn catchup(outbound: wire.OutboundOperation, accepted: Bool) -> json.Json {
  let template =
    runtime_fixture.sequenced_frame(sequenced(outbound, "original", 2))
  let first = case accepted {
    True -> template
    False ->
      frame.Sequenced(
        ..template,
        client_id: None,
        operation_type: "noop",
        contents: json.null(),
        metadata: None,
      )
  }
  frame.encode_operation_event([
    first,
    frame.Sequenced(
      ..template,
      client_id: None,
      sequence_number: 3,
      operation_type: "leave",
      contents: json.null(),
      metadata: None,
      data: Some(frame.system_leave_data("original")),
    ),
    frame.Sequenced(
      ..template,
      client_id: None,
      sequence_number: 4,
      operation_type: "join",
      contents: json.null(),
      metadata: None,
      data: Some(frame.system_join_data("recovered")),
    ),
  ])
}

@target(javascript)
fn check_js_resume(accepted: Bool) {
  let #(checkpoint, outbound) = saved_move()
  let callbacks = transport_js.new_cell(None)
  let ready = transport_js.new_cell(None)
  let owner =
    runtime.start_with_transport_and_checkpoint(
      http_base_url: "https://unused.invalid",
      connect_message: connect_message(),
      checkpoint: checkpoint,
      transport: runtime.Transport(connect: fn(handlers) {
        transport_js.set_cell(callbacks, Some(handlers))
        runtime.TransportHandle(
          push: fn(_, _) { Nil },
          close: fn() { Nil },
          drop: fn() { Nil },
          hold: fn() { Nil },
          resume: fn() { Nil },
        )
      }),
      on_ready: fn(outcome) { transport_js.set_cell(ready, Some(outcome)) },
    )
    |> expect.to_be_ok()
  let assert Some(callbacks) = transport_js.get_cell(callbacks)
  callbacks.on_join()
  callbacks.on_event("connect_document_success", json.to_string(handshake()))
  transport_js.get_cell(ready) |> expect.to_equal(None)
  runtime.connection_observation(owner).phase |> expect.to_equal("catching-up")
  callbacks.on_event("op", json.to_string(catchup(outbound, accepted)))
  transport_js.get_cell(ready) |> expect.to_equal(Some(Ok(Nil)))
  runtime.tree_read(owner, "A/_C", ["right", "0", "label"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("first"))))
  runtime.is_synced(owner) |> expect.to_equal(accepted)
  let next_checkpoint = runtime.pending_checkpoint(owner) |> expect.to_be_ok()
  let restored =
    recovery.restore(
      next_checkpoint,
      tenant: "default",
      document: "tree",
      view_id: view_id(),
    )
    |> expect.to_be_ok()
  list.length(restored.in_flight)
  |> expect.to_equal(case accepted {
    True -> 0
    False -> 1
  })
  runtime.close(owner)
  runtime.pending_checkpoint(owner) |> expect.to_be_error()
  Nil
}

@target(javascript)
pub fn document_recovery_js_waits_for_replay_before_resubmitting_test() {
  check_js_resume(False)
}

@target(javascript)
pub fn document_recovery_js_accepted_before_crash_is_not_duplicated_test() {
  check_js_resume(True)
}

@target(erlang)
fn starting_beam_resume() {
  let #(checkpoint, outbound) = saved_move()
  let callbacks_subject = process.new_subject()
  let owner =
    runtime_beam.start_with_transport_and_checkpoint(
      host: "unused.invalid",
      port: 0,
      connect_message: connect_message(),
      checkpoint: checkpoint,
      transport: runtime_beam.Transport(connect: fn(handlers) {
        process.send(callbacks_subject, handlers)
      }),
    )
    |> expect.to_be_ok()
  let callbacks = process.receive(callbacks_subject, 1000) |> expect.to_be_ok()
  callbacks.on_ready(
    runtime_beam.TransportHandle(
      push: fn(_, _) { Ok(Nil) },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  #(owner, callbacks, outbound)
}

@target(erlang)
fn check_beam_resume(accepted: Bool) {
  let #(owner, callbacks, outbound) = starting_beam_resume()
  callbacks.on_event("connect_document_success", handshake())
  runtime_beam.connection_observation(owner).phase
  |> expect.to_equal("catching-up")
  let readiness = process.new_subject()
  process.send(owner, runtime_beam.AwaitReady(readiness))
  process.receive(readiness, 0) |> expect.to_equal(Error(Nil))
  callbacks.on_event("op", catchup(outbound, accepted))
  process.receive(readiness, 1000) |> expect.to_equal(Ok(Ok(Nil)))
  runtime_beam.tree_read(owner, "A/_C", ["right", "0", "label"])
  |> expect.to_equal(Ok(Some(tree_types.StringValue("first"))))
  runtime_beam.is_synced(owner) |> expect.to_equal(accepted)
  let next_checkpoint =
    runtime_beam.pending_checkpoint(owner) |> expect.to_be_ok()
  let restored =
    recovery.restore(
      next_checkpoint,
      tenant: "default",
      document: "tree",
      view_id: view_id(),
    )
    |> expect.to_be_ok()
  list.length(restored.in_flight)
  |> expect.to_equal(case accepted {
    True -> 0
    False -> 1
  })
  let process_owner = process.subject_owner(owner) |> expect.to_be_ok()
  let monitor = process.monitor(process_owner)
  process.send(owner, runtime_beam.Shutdown)
  process.new_selector()
  |> process.select_specific_monitor(monitor, fn(_) { Nil })
  |> process.selector_receive(1000)
  |> expect.to_equal(Ok(Nil))
  process.demonitor_process(monitor)
  runtime_beam.pending_checkpoint(owner) |> expect.to_be_error()
  runtime_beam.await_ready(owner) |> expect.to_be_error()
  Nil
}

@target(erlang)
pub fn document_recovery_beam_waits_for_replay_before_resubmitting_test() {
  check_beam_resume(False)
}

@target(erlang)
pub fn document_recovery_beam_accepted_before_crash_is_not_duplicated_test() {
  check_beam_resume(True)
}

@target(erlang)
pub fn document_recovery_beam_timeout_completes_startup_waiter_test() {
  let #(owner, callbacks, _) = starting_beam_resume()
  callbacks.on_event("connect_document_success", handshake())
  let readiness = process.new_subject()
  process.send(owner, runtime_beam.AwaitReady(readiness))
  process.send(owner, runtime_beam.ReconnectTimedOut("recovered"))
  let outcome = process.receive(readiness, 1000)
  process.send(owner, runtime_beam.Shutdown)
  let assert Ok(Error(_)) = outcome
  Nil
}

@target(erlang)
pub fn document_recovery_beam_invalid_checkpoint_does_not_connect_test() {
  runtime_beam.start_with_transport_and_checkpoint(
    host: "unused.invalid",
    port: 0,
    connect_message: connect_message(),
    checkpoint: json.null(),
    transport: runtime_beam.Transport(connect: fn(_) {
      panic as "invalid checkpoint opened a transport"
    }),
  )
  |> expect.to_be_error()
  Nil
}

@target(javascript)
pub fn document_recovery_js_invalid_checkpoint_does_not_connect_test() {
  runtime.start_with_transport_and_checkpoint(
    http_base_url: "https://unused.invalid",
    connect_message: connect_message(),
    checkpoint: json.null(),
    transport: runtime.Transport(connect: fn(_) {
      panic as "invalid checkpoint opened a transport"
    }),
    on_ready: fn(_) { panic as "invalid checkpoint reached on_ready" },
  )
  |> expect.to_be_error()
  Nil
}

pub fn main() {
  let assert Ok(path) = envoy.get("WATERSHED_RECOVERY_FILE")
  let assert Ok(stage) = envoy.get("WATERSHED_RECOVERY_STAGE")
  case stage {
    "capture" -> {
      let assert Ok(#(moved, _, [move])) =
        runtime_core.submit_tree_edits(core(), "A/_C", [
          tree_types.ArrayMove(["left"], 0, 1, ["right"], 0),
        ])
      let assert Ok(#(pending, _, [edit])) =
        runtime_core.submit_tree_edits(moved, "A/_C", [
          tree_types.SetField(
            ["right", "0", "label"],
            tree_types.StringValue("edited"),
          ),
        ])
      let checkpoint =
        recovery.capture(pending, tenant: "default", document: "tree")
        |> expect.to_be_ok()
      let encoded =
        json.object([
          #("checkpoint", checkpoint),
          #(
            "firstAck",
            frame.encode_sequenced(
              runtime_fixture.sequenced_frame(sequenced(move, "original", 2)),
            ),
          ),
          #(
            "secondAck",
            frame.encode_sequenced(
              runtime_fixture.sequenced_frame(sequenced(edit, "original", 3)),
            ),
          ),
        ])
      simplifile.write(path, json.to_string(encoded)) |> expect.to_be_ok()
      io.println("Pending move and edit persisted.")
    }
    "resume" -> {
      let encoded = simplifile.read(path) |> expect.to_be_ok()
      let checkpoint =
        json.parse(
          encoded,
          decode.at(["checkpoint"], wire.json_value_decoder()),
        )
        |> expect.to_be_ok()
      let restored =
        recovery.restore(
          checkpoint,
          tenant: "default",
          document: "tree",
          view_id: view_id(),
        )
        |> expect.to_be_ok()
      let first =
        json.parse(
          encoded,
          decode.at(["firstAck"], socket.sequenced_document_message_decoder()),
        )
        |> expect.to_be_ok()
      let second =
        json.parse(
          encoded,
          decode.at(["secondAck"], socket.sequenced_document_message_decoder()),
        )
        |> expect.to_be_ok()
      let assert Ok(#(partially_accepted, _)) =
        runtime_core.handle_sequenced(restored, first)
      let assert Ok(#(_, [remaining])) =
        runtime_core.resubmit(partially_accepted)
      remaining.client_sequence_number |> expect.to_equal(3)
      let assert Ok(#(accepted, _)) =
        runtime_core.handle_sequenced(partially_accepted, second)
      accepted.in_flight |> expect.to_equal([])
      runtime_core.tree_read(accepted, "A/_C", ["right", "0", "label"])
      |> expect.to_equal(Ok(Some(tree_types.StringValue("edited"))))
      runtime_core.submit_tree_edits(accepted, "A/_C", [
        tree_types.ArrayInsert(["right"], 1, [
          identifier_fixture.point("third", "third"),
        ]),
      ])
      |> expect.to_be_ok()
      simplifile.delete(path) |> expect.to_be_ok()
      io.println(
        "Fresh process restored pending identities and continued allocation.",
      )
    }
    _ -> panic as "unknown recovery acceptance stage"
  }
}
