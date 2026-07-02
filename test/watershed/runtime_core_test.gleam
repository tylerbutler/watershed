//// Tests for the pure connection state machine.
////
//// Covers the bootstrap subtleties pinned by the plan: the join-push
//// dedupe (checkpointSequenceNumber == SN of our own join, absent from
//// initialMessages), SN dedupe as a general invariant, fatal sequence
//// gaps, CSN/RSN stamping, and FIFO ack matching.

import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/json.{type Json}
import gleam/option.{None, Some}
import startest/expect

import spillway/message
import spillway/types

import watershed/map_kernel.{Delete, Set, ValueChanged}
import watershed/runtime_core.{type Core}
import watershed/wire

const our_client_id = "default_dice_2"

const other_client_id = "default_dice_1"

// ─────────────────────────────────────────────────────────────────────────────
// Fixture builders
// ─────────────────────────────────────────────────────────────────────────────

fn to_dynamic(value: Json) -> Dynamic {
  case json.parse(json.to_string(value), decode.dynamic) {
    Ok(dynamic_value) -> dynamic_value
    Error(_) -> panic as "fixture JSON failed to re-parse"
  }
}

fn map_op_message(
  client_id client_id: String,
  sn sn: Int,
  csn csn: Int,
  op op: map_kernel.MapOp,
) -> types.SequencedDocumentMessage {
  sequenced_message(
    client_id: Some(client_id),
    sn: sn,
    csn: csn,
    message_type: "op",
    contents: to_dynamic(wire.encode_map_envelope("root", op)),
  )
}

fn join_message(
  sn sn: Int,
  joining joining: String,
) -> types.SequencedDocumentMessage {
  sequenced_message(
    client_id: None,
    sn: sn,
    csn: -1,
    message_type: "join",
    contents: to_dynamic(json.object([#("clientId", json.string(joining))])),
  )
}

fn sequenced_message(
  client_id client_id: option.Option(String),
  sn sn: Int,
  csn csn: Int,
  message_type message_type: String,
  contents contents: Dynamic,
) -> types.SequencedDocumentMessage {
  types.SequencedDocumentMessage(
    client_id: client_id,
    sequence_number: sn,
    minimum_sequence_number: 0,
    client_sequence_number: csn,
    reference_sequence_number: 0,
    message_type: message_type,
    contents: contents,
    metadata: None,
    server_metadata: None,
    origin: None,
    traces: None,
    timestamp: 0,
    data: None,
  )
}

fn connected_message(
  initial_messages initial_messages: List(types.SequencedDocumentMessage),
  checkpoint checkpoint: Int,
) -> message.ConnectedMessage {
  message.ConnectedMessage(
    claims: types.TokenClaims(
      document_id: "dice",
      scopes: ["doc:read", "doc:write"],
      tenant_id: "default",
      user: types.User(id: "user-2", properties: dict.new()),
      issued_at: 0,
      expiration: 0,
      version: "1.0",
      jti: None,
    ),
    client_id: our_client_id,
    existing: True,
    max_message_size: 16_000,
    mode: types.WriteMode,
    service_configuration: types.ServiceConfiguration(
      block_size: 65_536,
      max_message_size: 16_000,
      noop_time_frequency: None,
      noop_count_frequency: None,
    ),
    initial_clients: [],
    initial_messages: initial_messages,
    initial_signals: [],
    supported_versions: ["^0.1.0"],
    supported_features: dict.new(),
    version: "^0.1.0",
    timestamp: None,
    checkpoint_sequence_number: Some(checkpoint),
    epoch: None,
    relay_service_agent: None,
  )
}

fn bootstrap(
  initial_messages initial_messages: List(types.SequencedDocumentMessage),
  checkpoint checkpoint: Int,
) -> Core {
  case
    runtime_core.bootstrap(
      connected_message(initial_messages, checkpoint),
      address: "root",
    )
  {
    Ok(core) -> core
    Error(_) -> panic as "expected bootstrap to succeed"
  }
}

fn apply(
  core: Core,
  msg: types.SequencedDocumentMessage,
) -> #(Core, List(map_kernel.MapEvent)) {
  case runtime_core.handle_sequenced(core, msg) {
    Ok(outcome) -> outcome
    Error(_) -> panic as "expected handle_sequenced to succeed"
  }
}

fn expect_error(
  result: Result(#(Core, List(map_kernel.MapEvent)), runtime_core.CoreError),
  check: fn(runtime_core.CoreError) -> Bool,
) -> Nil {
  case result {
    Error(core_error) ->
      case check(core_error) {
        True -> Nil
        False -> panic as "unexpected CoreError variant"
      }
    Ok(_) -> panic as "expected a CoreError"
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bootstrap
// ─────────────────────────────────────────────────────────────────────────────

pub fn bootstrap_empty_document_test() {
  // Fresh document: no history, checkpoint is the SN of our own join.
  let core = bootstrap(initial_messages: [], checkpoint: 1)

  core.client_id |> expect.to_equal(our_client_id)
  core.last_seen_sn |> expect.to_equal(1)
  core.next_csn |> expect.to_equal(1)
  runtime_core.entries(core) |> expect.to_equal([])
}

pub fn bootstrap_replays_initial_messages_test() {
  let history = [
    join_message(sn: 1, joining: other_client_id),
    map_op_message(
      client_id: other_client_id,
      sn: 2,
      csn: 1,
      op: Set("die", json.int(4)),
    ),
    map_op_message(
      client_id: other_client_id,
      sn: 3,
      csn: 2,
      op: Set("count", json.int(9)),
    ),
    map_op_message(
      client_id: other_client_id,
      sn: 4,
      csn: 3,
      op: Delete("count"),
    ),
  ]
  let core = bootstrap(initial_messages: history, checkpoint: 5)

  runtime_core.get(core, "die") |> expect.to_equal(Some(json.int(4)))
  runtime_core.has(core, "count") |> expect.to_be_false()
  core.last_seen_sn |> expect.to_equal(5)
}

pub fn bootstrap_dedupes_own_join_push_test() {
  // The join for our own client arrives as a separate op push right after
  // connect_document_success, with SN == checkpointSequenceNumber. It must
  // dedupe without disturbing state.
  let core = bootstrap(initial_messages: [], checkpoint: 3)

  let #(core, events) = apply(core, join_message(sn: 3, joining: our_client_id))
  events |> expect.to_equal([])
  core.last_seen_sn |> expect.to_equal(3)

  // The stream continues seamlessly after the deduped push.
  let #(core, _) =
    apply(
      core,
      map_op_message(
        client_id: other_client_id,
        sn: 4,
        csn: 1,
        op: Set("die", json.int(6)),
      ),
    )
  runtime_core.get(core, "die") |> expect.to_equal(Some(json.int(6)))
}

// ─────────────────────────────────────────────────────────────────────────────
// Inbound ordering
// ─────────────────────────────────────────────────────────────────────────────

pub fn already_seen_ops_are_dropped_test() {
  let history = [
    join_message(sn: 1, joining: other_client_id),
    map_op_message(
      client_id: other_client_id,
      sn: 2,
      csn: 1,
      op: Set("die", json.int(4)),
    ),
  ]
  let core = bootstrap(initial_messages: history, checkpoint: 3)

  // Catch-up overlap re-delivers SN 2; the value must not double-apply and
  // no events may leak.
  let #(core, events) =
    apply(
      core,
      map_op_message(
        client_id: other_client_id,
        sn: 2,
        csn: 1,
        op: Set("die", json.int(999)),
      ),
    )
  events |> expect.to_equal([])
  runtime_core.get(core, "die") |> expect.to_equal(Some(json.int(4)))
}

pub fn sequence_gap_is_fatal_test() {
  let core = bootstrap(initial_messages: [], checkpoint: 1)

  runtime_core.handle_sequenced(
    core,
    map_op_message(
      client_id: other_client_id,
      sn: 5,
      csn: 1,
      op: Set("die", json.int(4)),
    ),
  )
  |> expect_error(fn(core_error) {
    core_error == runtime_core.SequenceGap(expected: 2, got: 5)
  })
}

pub fn system_messages_only_advance_sn_test() {
  let core = bootstrap(initial_messages: [], checkpoint: 1)

  // join contents ({clientId: ...}) would fail the map envelope decoder,
  // proving type routing happens before contents decoding.
  let #(core, events) = apply(core, join_message(sn: 2, joining: "someone"))
  events |> expect.to_equal([])
  core.last_seen_sn |> expect.to_equal(2)
}

pub fn foreign_address_ops_are_skipped_test() {
  let core = bootstrap(initial_messages: [], checkpoint: 1)

  let foreign =
    sequenced_message(
      client_id: Some(other_client_id),
      sn: 2,
      csn: 1,
      message_type: "op",
      contents: to_dynamic(wire.encode_map_envelope(
        "other-map",
        Set("die", json.int(4)),
      )),
    )
  let #(core, events) = apply(core, foreign)
  events |> expect.to_equal([])
  runtime_core.has(core, "die") |> expect.to_be_false()
  core.last_seen_sn |> expect.to_equal(2)
}

pub fn undecodable_op_contents_are_fatal_test() {
  let core = bootstrap(initial_messages: [], checkpoint: 1)

  let garbage =
    sequenced_message(
      client_id: Some(other_client_id),
      sn: 2,
      csn: 1,
      message_type: "op",
      contents: to_dynamic(json.object([#("bogus", json.bool(True))])),
    )
  runtime_core.handle_sequenced(core, garbage)
  |> expect_error(fn(core_error) {
    core_error == runtime_core.BadOpContents(sequence_number: 2)
  })
}

// ─────────────────────────────────────────────────────────────────────────────
// Outbound stamping + ack round-trip
// ─────────────────────────────────────────────────────────────────────────────

pub fn local_ops_stamp_csn_and_rsn_test() {
  let core = bootstrap(initial_messages: [], checkpoint: 7)

  let #(core, events, first) = runtime_core.set(core, "die", json.int(4))
  let #(core, _, second) = runtime_core.delete(core, "missing")

  events
  |> expect.to_equal([
    ValueChanged(key: "die", previous_value: None, local: True),
  ])
  first.client_sequence_number |> expect.to_equal(1)
  first.reference_sequence_number |> expect.to_equal(7)
  second.client_sequence_number |> expect.to_equal(2)
  core.next_csn |> expect.to_equal(3)
  runtime_core.get(core, "die") |> expect.to_equal(Some(json.int(4)))
}

pub fn ack_commits_pending_without_events_test() {
  let core = bootstrap(initial_messages: [], checkpoint: 1)
  let #(core, _, _) = runtime_core.set(core, "die", json.int(4))

  // Server sequences our op and echoes it back with our client_id + csn.
  let #(core, events) =
    apply(
      core,
      map_op_message(
        client_id: our_client_id,
        sn: 2,
        csn: 1,
        op: Set("die", json.int(4)),
      ),
    )

  // Ack transparency: no events, view unchanged, queue drained.
  events |> expect.to_equal([])
  runtime_core.get(core, "die") |> expect.to_equal(Some(json.int(4)))
  core.in_flight |> expect.to_equal([])
}

pub fn acks_match_fifo_across_multiple_ops_test() {
  let core = bootstrap(initial_messages: [], checkpoint: 1)
  let #(core, _, _) = runtime_core.set(core, "a", json.int(1))
  let #(core, _, _) = runtime_core.set(core, "b", json.int(2))

  let #(core, _) =
    apply(
      core,
      map_op_message(
        client_id: our_client_id,
        sn: 2,
        csn: 1,
        op: Set("a", json.int(1)),
      ),
    )
  core.in_flight
  |> expect.to_equal([#(2, Set("b", json.int(2)))])

  let #(core, _) =
    apply(
      core,
      map_op_message(
        client_id: our_client_id,
        sn: 3,
        csn: 2,
        op: Set("b", json.int(2)),
      ),
    )
  core.in_flight |> expect.to_equal([])
}

pub fn ack_with_wrong_csn_is_fatal_test() {
  let core = bootstrap(initial_messages: [], checkpoint: 1)
  let #(core, _, _) = runtime_core.set(core, "die", json.int(4))

  runtime_core.handle_sequenced(
    core,
    map_op_message(
      client_id: our_client_id,
      sn: 2,
      csn: 9,
      op: Set("die", json.int(4)),
    ),
  )
  |> expect_error(fn(core_error) {
    case core_error {
      runtime_core.AckMismatch(_) -> True
      _ -> False
    }
  })
}

pub fn ack_with_empty_in_flight_is_fatal_test() {
  let core = bootstrap(initial_messages: [], checkpoint: 1)

  runtime_core.handle_sequenced(
    core,
    map_op_message(
      client_id: our_client_id,
      sn: 2,
      csn: 1,
      op: Set("die", json.int(4)),
    ),
  )
  |> expect_error(fn(core_error) {
    case core_error {
      runtime_core.AckMismatch(_) -> True
      _ -> False
    }
  })
}

pub fn ack_with_wrong_shape_is_fatal_test() {
  let core = bootstrap(initial_messages: [], checkpoint: 1)
  let #(core, _, _) = runtime_core.set(core, "die", json.int(4))

  runtime_core.handle_sequenced(
    core,
    map_op_message(client_id: our_client_id, sn: 2, csn: 1, op: Delete("die")),
  )
  |> expect_error(fn(core_error) {
    case core_error {
      runtime_core.AckMismatch(_) -> True
      _ -> False
    }
  })
}

// ─────────────────────────────────────────────────────────────────────────────
// Optimistic interleaving
// ─────────────────────────────────────────────────────────────────────────────

pub fn pending_local_set_masks_remote_then_converges_test() {
  let core = bootstrap(initial_messages: [], checkpoint: 1)
  let #(core, _, _) = runtime_core.set(core, "die", json.int(6))

  // Remote write raced ahead of ours; it is masked by our pending set.
  let #(core, events) =
    apply(
      core,
      map_op_message(
        client_id: other_client_id,
        sn: 2,
        csn: 1,
        op: Set("die", json.int(2)),
      ),
    )
  events |> expect.to_equal([])
  runtime_core.get(core, "die") |> expect.to_equal(Some(json.int(6)))

  // Our op sequences after it (LWW): converged view keeps our value.
  let #(core, _) =
    apply(
      core,
      map_op_message(
        client_id: our_client_id,
        sn: 3,
        csn: 1,
        op: Set("die", json.int(6)),
      ),
    )
  runtime_core.get(core, "die") |> expect.to_equal(Some(json.int(6)))
  core.in_flight |> expect.to_equal([])
}
