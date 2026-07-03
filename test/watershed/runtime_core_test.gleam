//// Tests for the pure connection state machine.
////
//// Covers the bootstrap subtleties pinned by the plan: the join-push
//// dedupe (checkpointSequenceNumber == SN of our own join, absent from
//// initialMessages), SN dedupe as a general invariant, fatal sequence
//// gaps, CSN/RSN stamping, and FIFO ack matching.

import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{None, Some}
import startest/expect

import spillway/message
import spillway/types

import watershed/channel
import watershed/handle
import watershed/map_kernel.{Delete, Set, ValueChanged}
import watershed/runtime_core.{type Core}
import watershed/wire
import watershed/wire/ops

const our_client_id = "default_dice_2"

const other_client_id = "default_dice_1"

const reconnect_client_id = "default_dice_9"

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
  channel_op_message(
    address: "root",
    client_id: client_id,
    sn: sn,
    csn: csn,
    op: op,
  )
}

fn channel_op_message(
  address address: String,
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
    contents: to_dynamic(ops.encode_map_envelope(address, op)),
  )
}

fn attach_message(
  client_id client_id: String,
  sn sn: Int,
  csn csn: Int,
  address address: String,
  snapshot snapshot: List(#(String, Json)),
) -> types.SequencedDocumentMessage {
  sequenced_message(
    client_id: Some(client_id),
    sn: sn,
    csn: csn,
    message_type: "op",
    contents: to_dynamic(ops.encode_attach(
      address,
      channel.MapSnapshot(snapshot),
    )),
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
    summary_context: None,
  )
}

fn bootstrap(
  initial_messages initial_messages: List(types.SequencedDocumentMessage),
  checkpoint checkpoint: Int,
) -> Core {
  case
    runtime_core.bootstrap(
      connected_message(initial_messages, checkpoint),
      summary: None,
    )
  {
    Ok(runtime_core.Complete(core)) -> core
    Ok(runtime_core.MissingPrefix(..)) ->
      panic as "expected bootstrap to complete without catch-up"
    Error(_) -> panic as "expected bootstrap to succeed"
  }
}

/// A `connect_document_success` for a reconnect, i.e. with a fresh
/// server-assigned client_id and the checkpoint of the new join.
fn reconnect_connected(
  client_id client_id: String,
  checkpoint checkpoint: Int,
) -> message.ConnectedMessage {
  let base = connected_message([], checkpoint)
  message.ConnectedMessage(..base, client_id: client_id)
}

fn apply(
  core: Core,
  msg: types.SequencedDocumentMessage,
) -> #(Core, List(map_kernel.MapEvent)) {
  case runtime_core.handle_sequenced(core, msg) {
    Ok(#(core, ingested)) -> #(core, root_events(ingested.events))
    Error(_) -> panic as "expected handle_sequenced to succeed"
  }
}

fn apply_tagged(
  core: Core,
  msg: types.SequencedDocumentMessage,
) -> #(Core, List(#(String, channel.ChannelEvent))) {
  case runtime_core.handle_sequenced(core, msg) {
    Ok(#(core, ingested)) -> #(core, ingested.events)
    Error(_) -> panic as "expected handle_sequenced to succeed"
  }
}

fn ingest(
  core: Core,
  msg: types.SequencedDocumentMessage,
) -> #(Core, List(map_kernel.MapEvent), option.Option(Int)) {
  case runtime_core.handle_sequenced(core, msg) {
    Ok(#(core, ingested)) -> #(
      core,
      root_events(ingested.events),
      ingested.request_ops_from,
    )
    Error(_) -> panic as "expected handle_sequenced to succeed"
  }
}

fn root_events(
  events: List(#(String, channel.ChannelEvent)),
) -> List(map_kernel.MapEvent) {
  list.filter_map(events, fn(entry) {
    case entry {
      #("root", channel.MapEvent(event)) -> Ok(event)
      _ -> Error(Nil)
    }
  })
}

fn root_summary(
  sequence_number: Int,
  entries: List(#(String, Json)),
) -> runtime_core.Summary {
  runtime_core.Summary(sequence_number: sequence_number, channels: [
    #("root", channel.MapSnapshot(entries)),
  ])
}

fn root_get(core: Core, key: String) -> option.Option(Json) {
  runtime_core.get(core, "root", key)
}

fn root_has(core: Core, key: String) -> Bool {
  runtime_core.has(core, "root", key)
}

fn root_size(core: Core) -> Int {
  runtime_core.size(core, "root")
}

fn root_entries(core: Core) -> List(#(String, Json)) {
  runtime_core.entries(core, "root")
}

fn root_set(
  core: Core,
  key: String,
  value: Json,
) -> #(Core, List(map_kernel.MapEvent), wire.OutboundOp) {
  case runtime_core.set(core, "root", key, value) {
    Ok(#(core, events, [outbound])) -> #(core, root_events(events), outbound)
    Ok(_) -> panic as "expected exactly one outbound op"
    Error(_) -> panic as "expected root set to succeed"
  }
}

fn root_delete(
  core: Core,
  key: String,
) -> #(Core, List(map_kernel.MapEvent), wire.OutboundOp) {
  case runtime_core.delete(core, "root", key) {
    Ok(#(core, events, [outbound])) -> #(core, root_events(events), outbound)
    Ok(_) -> panic as "expected exactly one outbound op"
    Error(_) -> panic as "expected root delete to succeed"
  }
}

/// An outbound op's contents, fully decoded for comparison: channel op
/// payloads are stage-two decoded against the map grammar (every channel in
/// these tests is a map).
type DecodedOp {
  DecodedAttach(address: String, snapshot: channel.Snapshot)
  DecodedChannelOp(address: String, op: channel.ChannelOp)
}

fn decode_outbound_contents(op: wire.OutboundOp) -> DecodedOp {
  case json.parse(json.to_string(op.contents), decode.dynamic) {
    Error(_) -> panic as "failed to re-parse outbound contents"
    Ok(dynamic_value) ->
      case ops.decode_op_contents(dynamic_value) {
        Ok(ops.AttachOp(address, snapshot)) ->
          DecodedAttach(address: address, snapshot: snapshot)
        Ok(ops.ChannelOp(address, contents)) ->
          case
            decode.run(contents, ops.channel_op_decoder(channel.MapChannel))
          {
            Ok(op) -> DecodedChannelOp(address: address, op: op)
            Error(_) -> panic as "failed to decode outbound op contents"
          }
        Error(_) -> panic as "failed to decode outbound contents"
      }
  }
}

fn expect_error(
  result: Result(#(Core, runtime_core.Ingested), runtime_core.CoreError),
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
  root_entries(core) |> expect.to_equal([])
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

  root_get(core, "die") |> expect.to_equal(Some(json.int(4)))
  root_has(core, "count") |> expect.to_be_false()
  core.last_seen_sn |> expect.to_equal(5)
}

pub fn bootstrap_truncated_history_requests_prefix_test() {
  // A document with more ops than the server's in-band history window:
  // `initialMessages` starts above SN 1, so the prefix (SN 1..2) must be
  // fetched from the deltas REST endpoint before bootstrap can complete.
  let truncated = [
    map_op_message(
      client_id: other_client_id,
      sn: 3,
      csn: 1,
      op: Set("die", json.int(4)),
    ),
    map_op_message(
      client_id: other_client_id,
      sn: 4,
      csn: 2,
      op: Set("count", json.int(9)),
    ),
  ]

  let #(core, checkpoint) = case
    runtime_core.bootstrap(connected_message(truncated, 5), summary: None)
  {
    Ok(runtime_core.MissingPrefix(core, checkpoint, from, to)) -> {
      // Nothing replayed yet, so the fetch range is the full missing prefix
      // (from exclusive, to inclusive) and the checkpoint is deferred.
      from |> expect.to_equal(0)
      to |> expect.to_equal(2)
      checkpoint |> expect.to_equal(5)
      core.last_seen_sn |> expect.to_equal(0)
      #(core, checkpoint)
    }
    _ -> panic as "expected bootstrap to request the missing prefix"
  }

  // Resuming with the fetched prefix drains the buffered suffix, applies the
  // checkpoint, and completes with the full history's state.
  let prefix = [
    map_op_message(
      client_id: other_client_id,
      sn: 1,
      csn: 1,
      op: Set("count", json.int(1)),
    ),
    join_message(sn: 2, joining: other_client_id),
  ]
  case
    runtime_core.resume_bootstrap(core, checkpoint: checkpoint, deltas: prefix)
  {
    Ok(runtime_core.Complete(core)) -> {
      core.last_seen_sn |> expect.to_equal(5)
      root_get(core, "die") |> expect.to_equal(Some(json.int(4)))
      root_get(core, "count") |> expect.to_equal(Some(json.int(9)))
    }
    _ -> panic as "expected resume_bootstrap to complete"
  }
}

pub fn resume_bootstrap_pages_large_gaps_test() {
  // The deltas endpoint caps each response, so a wide gap closes over several
  // rounds: each partial page must advance `from` and re-request the rest.
  let tail = [
    map_op_message(
      client_id: other_client_id,
      sn: 6,
      csn: 3,
      op: Set("last", json.int(6)),
    ),
  ]
  let #(core, checkpoint) = case
    runtime_core.bootstrap(connected_message(tail, 7), summary: None)
  {
    Ok(runtime_core.MissingPrefix(core, checkpoint, from, to)) -> {
      from |> expect.to_equal(0)
      to |> expect.to_equal(5)
      #(core, checkpoint)
    }
    _ -> panic as "expected bootstrap to request the missing prefix"
  }

  // First page covers only SN 1..3 of the requested 1..5.
  let first_page =
    list.map([1, 2, 3], fn(sn) {
      map_op_message(
        client_id: other_client_id,
        sn: sn,
        csn: sn,
        op: Set("k" <> int.to_string(sn), json.int(sn)),
      )
    })
  let #(core, checkpoint) = case
    runtime_core.resume_bootstrap(
      core,
      checkpoint: checkpoint,
      deltas: first_page,
    )
  {
    Ok(runtime_core.MissingPrefix(core, checkpoint, from, to)) -> {
      // Progress recorded: the next round asks for just the remainder.
      from |> expect.to_equal(3)
      to |> expect.to_equal(5)
      #(core, checkpoint)
    }
    _ -> panic as "expected a second catch-up round"
  }

  let second_page =
    list.map([4, 5], fn(sn) {
      map_op_message(
        client_id: other_client_id,
        sn: sn,
        csn: sn,
        op: Set("k" <> int.to_string(sn), json.int(sn)),
      )
    })
  case
    runtime_core.resume_bootstrap(
      core,
      checkpoint: checkpoint,
      deltas: second_page,
    )
  {
    Ok(runtime_core.Complete(core)) -> {
      core.last_seen_sn |> expect.to_equal(7)
      root_get(core, "last") |> expect.to_equal(Some(json.int(6)))
      root_get(core, "k4") |> expect.to_equal(Some(json.int(4)))
      root_size(core) |> expect.to_equal(6)
    }
    _ -> panic as "expected resume_bootstrap to complete after paging"
  }
}

pub fn resume_bootstrap_without_progress_is_fatal_test() {
  // A catch-up round that advances nothing means the server's storage is
  // genuinely missing the range: fail loudly rather than diverge or spin.
  let tail = [
    map_op_message(
      client_id: other_client_id,
      sn: 4,
      csn: 1,
      op: Set("die", json.int(4)),
    ),
  ]
  let #(core, checkpoint) = case
    runtime_core.bootstrap(connected_message(tail, 5), summary: None)
  {
    Ok(runtime_core.MissingPrefix(core, checkpoint, _, _)) -> #(
      core,
      checkpoint,
    )
    _ -> panic as "expected bootstrap to request the missing prefix"
  }

  case runtime_core.resume_bootstrap(core, checkpoint: checkpoint, deltas: []) {
    Error(runtime_core.HistoryGap(_)) -> Nil
    Error(_) -> panic as "expected HistoryGap, got another CoreError"
    Ok(_) -> panic as "expected an empty catch-up round to be fatal"
  }
}

pub fn bootstrap_from_summary_truncated_deltas_requests_prefix_test() {
  // A summarized document whose post-summary history outgrew the in-band
  // window: the summary seeds SN 100, but the served deltas start at 105, so
  // the fetch range must start at the summary's sequence number.
  let summary = root_summary(100, [#("die", json.int(4))])
  let tail = [
    map_op_message(
      client_id: other_client_id,
      sn: 105,
      csn: 9,
      op: Set("post", json.int(1)),
    ),
  ]
  case
    runtime_core.bootstrap(connected_message(tail, 106), summary: Some(summary))
  {
    Ok(runtime_core.MissingPrefix(_, checkpoint, from, to)) -> {
      from |> expect.to_equal(100)
      to |> expect.to_equal(104)
      checkpoint |> expect.to_equal(106)
    }
    _ -> panic as "expected summary bootstrap to request the missing prefix"
  }
}

pub fn bootstrap_from_summary_seeds_and_applies_deltas_test() {
  // A summarized document: the summary captures {die: 4} as of SN 5, and the
  // post-summary deltas (initialMessages) start at SN 6. Bootstrap must seed
  // the kernel from the summary and replay only the deltas on top — no gap.
  let summary = root_summary(5, [#("die", json.int(4))])
  let deltas = [
    map_op_message(
      client_id: other_client_id,
      sn: 6,
      csn: 1,
      op: Set("count", json.int(9)),
    ),
    map_op_message(client_id: other_client_id, sn: 7, csn: 2, op: Delete("die")),
  ]
  let core = case
    runtime_core.bootstrap(connected_message(deltas, 8), summary: Some(summary))
  {
    Ok(runtime_core.Complete(core)) -> core
    _ -> panic as "expected summary bootstrap to succeed"
  }

  // Seeded from the summary, then the deltas applied: die deleted, count added.
  root_has(core, "die") |> expect.to_be_false()
  root_get(core, "count") |> expect.to_equal(Some(json.int(9)))
  core.last_seen_sn |> expect.to_equal(8)
}

pub fn bootstrap_from_summary_no_deltas_test() {
  // A freshly summarized document with no post-summary ops: the state is
  // exactly the summary, seen as of the summary's sequence number.
  let summary =
    root_summary(5, [
      #("a", json.int(1)),
      #("b", json.int(2)),
    ])
  let core = case
    runtime_core.bootstrap(connected_message([], 5), summary: Some(summary))
  {
    Ok(runtime_core.Complete(core)) -> core
    _ -> panic as "expected summary bootstrap to succeed"
  }

  root_entries(core)
  |> expect.to_equal([#("a", json.int(1)), #("b", json.int(2))])
  core.last_seen_sn |> expect.to_equal(5)
  // The confirmed entries a fresh summarize would capture round-trip exactly.
  runtime_core.summary_channels(core)
  |> expect.to_equal([
    #("root", channel.MapSnapshot([#("a", json.int(1)), #("b", json.int(2))])),
  ])
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
  root_get(core, "die") |> expect.to_equal(Some(json.int(6)))
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
  root_get(core, "die") |> expect.to_equal(Some(json.int(4)))
}

pub fn sequence_gap_buffers_and_requests_catch_up_test() {
  let core = bootstrap(initial_messages: [], checkpoint: 1)

  // An op past the next expected SN is buffered, not applied, and the first
  // such op asks the runtime to requestOps from the last contiguous SN.
  let #(core, events, request_ops_from) =
    ingest(
      core,
      map_op_message(
        client_id: other_client_id,
        sn: 5,
        csn: 1,
        op: Set("die", json.int(4)),
      ),
    )
  events |> expect.to_equal([])
  request_ops_from |> expect.to_equal(Some(1))
  root_has(core, "die") |> expect.to_be_false()
  core.last_seen_sn |> expect.to_equal(1)

  // A further out-of-order op extends the buffer without re-requesting.
  let #(core, _, request_ops_from) =
    ingest(
      core,
      map_op_message(
        client_id: other_client_id,
        sn: 4,
        csn: 2,
        op: Set("count", json.int(9)),
      ),
    )
  request_ops_from |> expect.to_equal(None)
  core.last_seen_sn |> expect.to_equal(1)

  // The missing ops (SN 2, 3) arrive; the buffer drains contiguously and the
  // catch-up completes with events for every applied op.
  let #(core, _, request_ops_from) =
    ingest(
      core,
      map_op_message(
        client_id: other_client_id,
        sn: 2,
        csn: 3,
        op: Set("a", json.int(1)),
      ),
    )
  request_ops_from |> expect.to_equal(None)
  core.last_seen_sn |> expect.to_equal(2)

  let #(core, _, request_ops_from) =
    ingest(
      core,
      map_op_message(
        client_id: other_client_id,
        sn: 3,
        csn: 4,
        op: Set("b", json.int(2)),
      ),
    )
  // SN 3 applies, then buffered SN 4 and SN 5 drain in one go.
  core.last_seen_sn |> expect.to_equal(5)
  request_ops_from |> expect.to_equal(None)
  root_get(core, "die") |> expect.to_equal(Some(json.int(4)))
  root_get(core, "count") |> expect.to_equal(Some(json.int(9)))
  root_get(core, "a") |> expect.to_equal(Some(json.int(1)))
  root_get(core, "b") |> expect.to_equal(Some(json.int(2)))
}

pub fn system_messages_only_advance_sn_test() {
  let core = bootstrap(initial_messages: [], checkpoint: 1)

  // join contents ({clientId: ...}) would fail the map envelope decoder,
  // proving type routing happens before contents decoding.
  let #(core, events) = apply(core, join_message(sn: 2, joining: "someone"))
  events |> expect.to_equal([])
  core.last_seen_sn |> expect.to_equal(2)
}

pub fn unknown_address_ops_are_fatal_test() {
  let core = bootstrap(initial_messages: [], checkpoint: 1)

  let foreign =
    sequenced_message(
      client_id: Some(other_client_id),
      sn: 2,
      csn: 1,
      message_type: "op",
      contents: to_dynamic(ops.encode_map_envelope(
        "other-map",
        Set("die", json.int(4)),
      )),
    )
  runtime_core.handle_sequenced(core, foreign)
  |> expect_error(fn(core_error) {
    core_error
    == runtime_core.UnknownChannel(address: "other-map", sequence_number: 2)
  })
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

  let #(core, events, first) = root_set(core, "die", json.int(4))
  let #(core, _, second) = root_delete(core, "missing")

  events
  |> expect.to_equal([
    ValueChanged(key: "die", previous_value: None, local: True),
  ])
  first.client_sequence_number |> expect.to_equal(1)
  first.reference_sequence_number |> expect.to_equal(7)
  second.client_sequence_number |> expect.to_equal(2)
  core.next_csn |> expect.to_equal(3)
  root_get(core, "die") |> expect.to_equal(Some(json.int(4)))
}

pub fn ack_commits_pending_without_events_test() {
  let core = bootstrap(initial_messages: [], checkpoint: 1)
  let #(core, _, _) = root_set(core, "die", json.int(4))

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
  root_get(core, "die") |> expect.to_equal(Some(json.int(4)))
  core.in_flight |> expect.to_equal([])
}

pub fn acks_match_fifo_across_multiple_ops_test() {
  let core = bootstrap(initial_messages: [], checkpoint: 1)
  let #(core, _, _) = root_set(core, "a", json.int(1))
  let #(core, _, _) = root_set(core, "b", json.int(2))

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
  |> expect.to_equal([
    runtime_core.InFlightOp(
      client_id: our_client_id,
      csn: 2,
      address: "root",
      op: channel.MapOp(Set("b", json.int(2))),
      meta: channel.NoMeta,
    ),
  ])

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
  let #(core, _, _) = root_set(core, "die", json.int(4))

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
  let #(core, _, _) = root_set(core, "die", json.int(4))

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
  let #(core, _, _) = root_set(core, "die", json.int(6))

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
  root_get(core, "die") |> expect.to_equal(Some(json.int(6)))

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
  root_get(core, "die") |> expect.to_equal(Some(json.int(6)))
  core.in_flight |> expect.to_equal([])
}

// ─────────────────────────────────────────────────────────────────────────────
// Reconnect: reconcile + resubmit
// ─────────────────────────────────────────────────────────────────────────────

pub fn reconnect_reconciles_then_resubmits_test() {
  // Two local ops are in flight when the connection drops.
  let core = bootstrap(initial_messages: [], checkpoint: 1)
  let #(core, _, _) = root_set(core, "a", json.int(1))
  let #(core, _, _) = root_set(core, "b", json.int(2))

  // Reconnect: fresh client_id, and the server assigned SN 2 to op "a" under
  // the OLD id while we were disconnected, so the new join lands at SN 3.
  let core =
    runtime_core.adopt_reconnect(
      core,
      reconnect_connected(client_id: reconnect_client_id, checkpoint: 3),
    )
  core.client_id |> expect.to_equal(reconnect_client_id)
  // Kernel + in-flight survive the reconnect; only the id changed.
  core.last_seen_sn |> expect.to_equal(1)

  // Catch-up replays op "a" under the OLD client id: it reconciles (acks the
  // head) rather than double-applying, and emits no events.
  let #(core, events, request_ops_from) =
    ingest(
      core,
      map_op_message(
        client_id: our_client_id,
        sn: 2,
        csn: 1,
        op: Set("a", json.int(1)),
      ),
    )
  events |> expect.to_equal([])
  request_ops_from |> expect.to_equal(None)
  core.in_flight
  |> expect.to_equal([
    runtime_core.InFlightOp(
      client_id: our_client_id,
      csn: 2,
      address: "root",
      op: channel.MapOp(Set("b", json.int(2))),
      meta: channel.NoMeta,
    ),
  ])

  // Our own new join advances last_seen to the checkpoint.
  let #(core, _) =
    apply(core, join_message(sn: 3, joining: reconnect_client_id))
  core.last_seen_sn |> expect.to_equal(3)

  // Resubmit the survivor with a fresh CSN under the new client id.
  let #(core, outbound) = runtime_core.resubmit(core)
  core.in_flight
  |> expect.to_equal([
    runtime_core.InFlightOp(
      client_id: reconnect_client_id,
      csn: 3,
      address: "root",
      op: channel.MapOp(Set("b", json.int(2))),
      meta: channel.NoMeta,
    ),
  ])
  core.next_csn |> expect.to_equal(4)
  case outbound {
    [op] -> {
      op.client_sequence_number |> expect.to_equal(3)
      op.reference_sequence_number |> expect.to_equal(3)
    }
    _ -> panic as "expected exactly one resubmitted op"
  }

  // The resubmitted op finally acks under the new client id; nothing is lost
  // or duplicated.
  let #(core, _) =
    apply(
      core,
      map_op_message(
        client_id: reconnect_client_id,
        sn: 4,
        csn: 3,
        op: Set("b", json.int(2)),
      ),
    )
  core.in_flight |> expect.to_equal([])
  root_get(core, "a") |> expect.to_equal(Some(json.int(1)))
  root_get(core, "b") |> expect.to_equal(Some(json.int(2)))
}

pub fn reconnect_with_all_ops_reconciled_resubmits_nothing_test() {
  // The whole in-flight batch was sequenced-but-not-broadcast before the drop
  // (the nack-prefix hazard); catch-up must ack all of it, resubmit none.
  let core = bootstrap(initial_messages: [], checkpoint: 1)
  let #(core, _, _) = root_set(core, "a", json.int(1))
  let #(core, _, _) = root_set(core, "b", json.int(2))

  let core =
    runtime_core.adopt_reconnect(
      core,
      reconnect_connected(client_id: reconnect_client_id, checkpoint: 4),
    )

  let #(core, _, _) =
    ingest(
      core,
      map_op_message(
        client_id: our_client_id,
        sn: 2,
        csn: 1,
        op: Set("a", json.int(1)),
      ),
    )
  let #(core, _, _) =
    ingest(
      core,
      map_op_message(
        client_id: our_client_id,
        sn: 3,
        csn: 2,
        op: Set("b", json.int(2)),
      ),
    )
  let #(core, _) =
    apply(core, join_message(sn: 4, joining: reconnect_client_id))

  core.in_flight |> expect.to_equal([])
  let #(core, outbound) = runtime_core.resubmit(core)
  outbound |> expect.to_equal([])
  core.in_flight |> expect.to_equal([])
  root_get(core, "a") |> expect.to_equal(Some(json.int(1)))
  root_get(core, "b") |> expect.to_equal(Some(json.int(2)))
}

pub fn reconnect_applies_missed_delta_from_others_test() {
  // Changes other clients made while we were offline must surface as events.
  let core = bootstrap(initial_messages: [], checkpoint: 1)
  let core =
    runtime_core.adopt_reconnect(
      core,
      reconnect_connected(client_id: reconnect_client_id, checkpoint: 3),
    )

  let #(core, events, _) =
    ingest(
      core,
      map_op_message(
        client_id: other_client_id,
        sn: 2,
        csn: 1,
        op: Set("x", json.string("y")),
      ),
    )
  events
  |> expect.to_equal([
    ValueChanged(key: "x", previous_value: None, local: False),
  ])
  root_get(core, "x") |> expect.to_equal(Some(json.string("y")))

  let #(core, _) =
    apply(core, join_message(sn: 3, joining: reconnect_client_id))
  let #(_, outbound) = runtime_core.resubmit(core)
  outbound |> expect.to_equal([])
}

pub fn resubmit_restamps_in_flight_in_order_test() {
  let core = bootstrap(initial_messages: [], checkpoint: 5)
  let #(core, _, _) = root_set(core, "a", json.int(1))
  let #(core, _, _) = root_set(core, "b", json.int(2))
  let #(core, _, _) = root_delete(core, "a")

  let core =
    runtime_core.adopt_reconnect(
      core,
      reconnect_connected(client_id: reconnect_client_id, checkpoint: 9),
    )
  let #(core, outbound) = runtime_core.resubmit(core)

  // Fresh sequential CSNs, new client id, order preserved, RSN = last_seen.
  core.next_csn |> expect.to_equal(7)
  core.in_flight
  |> expect.to_equal([
    runtime_core.InFlightOp(
      client_id: reconnect_client_id,
      csn: 4,
      address: "root",
      op: channel.MapOp(Set("a", json.int(1))),
      meta: channel.NoMeta,
    ),
    runtime_core.InFlightOp(
      client_id: reconnect_client_id,
      csn: 5,
      address: "root",
      op: channel.MapOp(Set("b", json.int(2))),
      meta: channel.NoMeta,
    ),
    runtime_core.InFlightOp(
      client_id: reconnect_client_id,
      csn: 6,
      address: "root",
      op: channel.MapOp(Delete("a")),
      meta: channel.NoMeta,
    ),
  ])
  list.length(outbound) |> expect.to_equal(3)
  case outbound {
    [first, ..] -> {
      first.client_sequence_number |> expect.to_equal(4)
      first.reference_sequence_number |> expect.to_equal(5)
    }
    [] -> panic as "expected resubmitted ops"
  }
}

pub fn remote_attach_creates_channel_and_subsequent_ops_apply_with_tagged_events_test() {
  let core = bootstrap(initial_messages: [], checkpoint: 1)

  let child_snapshot = [#("a", json.int(1))]
  let #(core, attach_events) =
    apply_tagged(
      core,
      attach_message(
        client_id: other_client_id,
        sn: 2,
        csn: 1,
        address: "child",
        snapshot: child_snapshot,
      ),
    )
  attach_events |> expect.to_equal([])
  runtime_core.entries(core, "child") |> expect.to_equal(child_snapshot)

  let #(core, events) =
    apply_tagged(
      core,
      channel_op_message(
        address: "child",
        client_id: other_client_id,
        sn: 3,
        csn: 2,
        op: Set("b", json.int(2)),
      ),
    )
  events
  |> expect.to_equal([
    #(
      "child",
      channel.MapEvent(ValueChanged(
        key: "b",
        previous_value: None,
        local: False,
      )),
    ),
  ])
  runtime_core.get(core, "child", "b") |> expect.to_equal(Some(json.int(2)))
}

pub fn duplicate_attach_is_fatal_test() {
  let core = bootstrap(initial_messages: [], checkpoint: 1)
  let #(core, _) =
    apply_tagged(
      core,
      attach_message(
        client_id: other_client_id,
        sn: 2,
        csn: 1,
        address: "child",
        snapshot: [],
      ),
    )

  runtime_core.handle_sequenced(
    core,
    attach_message(
      client_id: other_client_id,
      sn: 3,
      csn: 2,
      address: "child",
      snapshot: [],
    ),
  )
  |> expect_error(fn(core_error) {
    core_error
    == runtime_core.DuplicateAttach(address: "child", sequence_number: 3)
  })
}

pub fn detached_edits_produce_no_outbound_test() {
  let core = bootstrap(initial_messages: [], checkpoint: 1)
  let core = runtime_core.create_detached(core, "child", channel.MapChannel)

  case runtime_core.set(core, "child", "a", json.int(1)) {
    Ok(#(core, events, outbound)) -> {
      events
      |> expect.to_equal([
        #(
          "child",
          channel.MapEvent(ValueChanged(
            key: "a",
            previous_value: None,
            local: True,
          )),
        ),
      ])
      outbound |> expect.to_equal([])
      core.in_flight |> expect.to_equal([])
      runtime_core.get(core, "child", "a")
      |> expect.to_equal(Some(json.int(1)))
    }
    Error(_) -> panic as "expected detached edit to succeed"
  }
}

pub fn handle_set_emits_recursive_attach_post_order_test() {
  let core = bootstrap(initial_messages: [], checkpoint: 1)
  let core = runtime_core.create_detached(core, "child", channel.MapChannel)
  let core = runtime_core.create_detached(core, "grand", channel.MapChannel)
  let assert Ok(#(core, _, [])) =
    runtime_core.set(core, "grand", "g", json.int(1))
  let assert Ok(#(core, _, [])) =
    runtime_core.set(core, "child", "ref", handle.encode_handle("grand"))

  let assert Ok(#(core, events, outbound)) =
    runtime_core.set(core, "root", "child", handle.encode_handle("child"))

  events
  |> expect.to_equal([
    #(
      "root",
      channel.MapEvent(ValueChanged(
        key: "child",
        previous_value: None,
        local: True,
      )),
    ),
  ])
  list.map(outbound, decode_outbound_contents)
  |> expect.to_equal([
    DecodedAttach(
      address: "grand",
      snapshot: channel.MapSnapshot([#("g", json.int(1))]),
    ),
    DecodedAttach(
      address: "child",
      snapshot: channel.MapSnapshot([#("ref", handle.encode_handle("grand"))]),
    ),
    DecodedChannelOp(
      address: "root",
      op: channel.MapOp(Set("child", handle.encode_handle("child"))),
    ),
  ])
  runtime_core.has_channel(core, "child") |> expect.to_be_true()
  runtime_core.has_channel(core, "grand") |> expect.to_be_true()
}

pub fn handle_set_emits_cycle_safe_attach_post_order_test() {
  let core = bootstrap(initial_messages: [], checkpoint: 1)
  let core = runtime_core.create_detached(core, "a", channel.MapChannel)
  let core = runtime_core.create_detached(core, "b", channel.MapChannel)
  let assert Ok(#(core, _, [])) =
    runtime_core.set(core, "a", "peer", handle.encode_handle("b"))
  let assert Ok(#(core, _, [])) =
    runtime_core.set(core, "b", "peer", handle.encode_handle("a"))

  let assert Ok(#(_, _, outbound)) =
    runtime_core.set(core, "root", "ref", handle.encode_handle("a"))

  list.map(outbound, decode_outbound_contents)
  |> expect.to_equal([
    DecodedAttach(
      address: "b",
      snapshot: channel.MapSnapshot([#("peer", handle.encode_handle("a"))]),
    ),
    DecodedAttach(
      address: "a",
      snapshot: channel.MapSnapshot([#("peer", handle.encode_handle("b"))]),
    ),
    DecodedChannelOp(
      address: "root",
      op: channel.MapOp(Set("ref", handle.encode_handle("a"))),
    ),
  ])
}

pub fn edits_between_attach_submit_and_ack_queue_fifo_test() {
  let core = bootstrap(initial_messages: [], checkpoint: 1)
  let core = runtime_core.create_detached(core, "child", channel.MapChannel)
  let assert Ok(#(core, _, [])) =
    runtime_core.set(core, "child", "a", json.int(1))
  let assert Ok(#(core, _, initial_outbound)) =
    runtime_core.set(core, "root", "ref", handle.encode_handle("child"))
  list.length(initial_outbound) |> expect.to_equal(2)

  let assert Ok(#(core, events, [child_outbound])) =
    runtime_core.set(core, "child", "a", json.int(2))
  events
  |> expect.to_equal([
    #(
      "child",
      channel.MapEvent(ValueChanged(
        key: "a",
        previous_value: Some(json.int(1)),
        local: True,
      )),
    ),
  ])
  decode_outbound_contents(child_outbound)
  |> expect.to_equal(DecodedChannelOp(
    address: "child",
    op: channel.MapOp(Set("a", json.int(2))),
  ))
  core.in_flight
  |> expect.to_equal([
    runtime_core.InFlightAttach(
      client_id: our_client_id,
      csn: 1,
      address: "child",
      snapshot: channel.MapSnapshot([#("a", json.int(1))]),
    ),
    runtime_core.InFlightOp(
      client_id: our_client_id,
      csn: 2,
      address: "root",
      op: channel.MapOp(Set("ref", handle.encode_handle("child"))),
      meta: channel.NoMeta,
    ),
    runtime_core.InFlightOp(
      client_id: our_client_id,
      csn: 3,
      address: "child",
      op: channel.MapOp(Set("a", json.int(2))),
      meta: channel.NoMeta,
    ),
  ])

  let #(core, attach_events) =
    apply_tagged(
      core,
      attach_message(
        client_id: our_client_id,
        sn: 2,
        csn: 1,
        address: "child",
        snapshot: [#("a", json.int(1))],
      ),
    )
  attach_events |> expect.to_equal([])

  let #(core, root_events_) =
    apply(
      core,
      map_op_message(
        client_id: our_client_id,
        sn: 3,
        csn: 2,
        op: Set("ref", handle.encode_handle("child")),
      ),
    )
  root_events_ |> expect.to_equal([])

  let #(core, child_events) =
    apply_tagged(
      core,
      channel_op_message(
        address: "child",
        client_id: our_client_id,
        sn: 4,
        csn: 3,
        op: Set("a", json.int(2)),
      ),
    )
  child_events |> expect.to_equal([])
  runtime_core.get(core, "child", "a") |> expect.to_equal(Some(json.int(2)))
  core.in_flight |> expect.to_equal([])
}

pub fn attach_ack_pops_with_no_events_test() {
  let core = bootstrap(initial_messages: [], checkpoint: 1)
  let core = runtime_core.create_detached(core, "child", channel.MapChannel)
  let assert Ok(#(core, _, [])) =
    runtime_core.set(core, "child", "a", json.int(1))
  let assert Ok(#(core, _, outbound)) =
    runtime_core.set(core, "root", "ref", handle.encode_handle("child"))
  outbound
  |> expect.to_equal([
    ops.outbound_attach_op(
      address: "child",
      client_sequence_number: 1,
      reference_sequence_number: 1,
      snapshot: channel.MapSnapshot([#("a", json.int(1))]),
    ),
    ops.outbound_channel_op(
      address: "root",
      client_sequence_number: 2,
      reference_sequence_number: 1,
      op: channel.MapOp(Set("ref", handle.encode_handle("child"))),
    ),
  ])

  let #(core, events) =
    apply_tagged(
      core,
      attach_message(
        client_id: our_client_id,
        sn: 2,
        csn: 1,
        address: "child",
        snapshot: [#("a", json.int(1))],
      ),
    )
  events |> expect.to_equal([])
  runtime_core.entries(core, "child") |> expect.to_equal([#("a", json.int(1))])
  core.in_flight
  |> expect.to_equal([
    runtime_core.InFlightOp(
      client_id: our_client_id,
      csn: 2,
      address: "root",
      op: channel.MapOp(Set("ref", handle.encode_handle("child"))),
      meta: channel.NoMeta,
    ),
  ])
}

pub fn attach_ack_mismatch_is_fatal_test() {
  let core = bootstrap(initial_messages: [], checkpoint: 1)
  let core = runtime_core.create_detached(core, "child", channel.MapChannel)
  let assert Ok(#(core, _, [])) =
    runtime_core.set(core, "child", "a", json.int(1))
  let assert Ok(#(core, _, _)) =
    runtime_core.set(core, "root", "ref", handle.encode_handle("child"))

  runtime_core.handle_sequenced(
    core,
    attach_message(
      client_id: our_client_id,
      sn: 2,
      csn: 1,
      address: "child",
      snapshot: [#("wrong", json.int(1))],
    ),
  )
  |> expect_error(fn(core_error) {
    case core_error {
      runtime_core.AckMismatch(_) -> True
      _ -> False
    }
  })
}

pub fn attach_ack_value_mismatch_is_fatal_test() {
  let core = bootstrap(initial_messages: [], checkpoint: 1)
  let core = runtime_core.create_detached(core, "child", channel.MapChannel)
  let assert Ok(#(core, _, [])) =
    runtime_core.set(core, "child", "a", json.int(1))
  let assert Ok(#(core, _, _)) =
    runtime_core.set(core, "root", "ref", handle.encode_handle("child"))

  runtime_core.handle_sequenced(
    core,
    attach_message(
      client_id: our_client_id,
      sn: 2,
      csn: 1,
      address: "child",
      snapshot: [#("a", json.int(2))],
    ),
  )
  |> expect_error(fn(core_error) {
    case core_error {
      runtime_core.AckMismatch(_) -> True
      _ -> False
    }
  })
}

pub fn reconnect_resubmit_preserves_interleaved_attach_and_op_queue_test() {
  let core = bootstrap(initial_messages: [], checkpoint: 1)
  let core = runtime_core.create_detached(core, "child", channel.MapChannel)
  let assert Ok(#(core, _, [])) =
    runtime_core.set(core, "child", "a", json.int(1))
  let assert Ok(#(core, _, _)) =
    runtime_core.set(core, "root", "ref", handle.encode_handle("child"))
  let assert Ok(#(core, _, _)) =
    runtime_core.set(core, "child", "a", json.int(2))

  let core =
    runtime_core.adopt_reconnect(
      core,
      reconnect_connected(client_id: reconnect_client_id, checkpoint: 5),
    )
  let #(core, outbound) = runtime_core.resubmit(core)

  core.in_flight
  |> expect.to_equal([
    runtime_core.InFlightAttach(
      client_id: reconnect_client_id,
      csn: 4,
      address: "child",
      snapshot: channel.MapSnapshot([#("a", json.int(1))]),
    ),
    runtime_core.InFlightOp(
      client_id: reconnect_client_id,
      csn: 5,
      address: "root",
      op: channel.MapOp(Set("ref", handle.encode_handle("child"))),
      meta: channel.NoMeta,
    ),
    runtime_core.InFlightOp(
      client_id: reconnect_client_id,
      csn: 6,
      address: "child",
      op: channel.MapOp(Set("a", json.int(2))),
      meta: channel.NoMeta,
    ),
  ])
  list.map(outbound, decode_outbound_contents)
  |> expect.to_equal([
    DecodedAttach(
      address: "child",
      snapshot: channel.MapSnapshot([#("a", json.int(1))]),
    ),
    DecodedChannelOp(
      address: "root",
      op: channel.MapOp(Set("ref", handle.encode_handle("child"))),
    ),
    DecodedChannelOp(address: "child", op: channel.MapOp(Set("a", json.int(2)))),
  ])
}

pub fn bootstrap_from_multi_channel_summary_and_attach_replay_test() {
  let summary =
    runtime_core.Summary(sequence_number: 5, channels: [
      #("root", channel.MapSnapshot([#("die", json.int(4))])),
      #("child", channel.MapSnapshot([#("a", json.int(1))])),
    ])
  let deltas = [
    attach_message(
      client_id: other_client_id,
      sn: 6,
      csn: 1,
      address: "grand",
      snapshot: [#("g", json.int(9))],
    ),
    channel_op_message(
      address: "child",
      client_id: other_client_id,
      sn: 7,
      csn: 2,
      op: Set("b", json.int(2)),
    ),
  ]

  case
    runtime_core.bootstrap(connected_message(deltas, 8), summary: Some(summary))
  {
    Ok(runtime_core.Complete(core)) -> {
      root_get(core, "die") |> expect.to_equal(Some(json.int(4)))
      runtime_core.get(core, "child", "a") |> expect.to_equal(Some(json.int(1)))
      runtime_core.get(core, "child", "b") |> expect.to_equal(Some(json.int(2)))
      runtime_core.get(core, "grand", "g") |> expect.to_equal(Some(json.int(9)))
      runtime_core.summary_channels(core)
      |> expect.to_equal([
        #("root", channel.MapSnapshot([#("die", json.int(4))])),
        #(
          "child",
          channel.MapSnapshot([#("a", json.int(1)), #("b", json.int(2))]),
        ),
        #("grand", channel.MapSnapshot([#("g", json.int(9))])),
      ])
    }
    _ -> panic as "expected multi-channel summary bootstrap to succeed"
  }
}

pub fn bootstrap_from_bare_attach_history_test() {
  let history = [
    attach_message(
      client_id: other_client_id,
      sn: 1,
      csn: 1,
      address: "child",
      snapshot: [#("a", json.int(1))],
    ),
    channel_op_message(
      address: "child",
      client_id: other_client_id,
      sn: 2,
      csn: 2,
      op: Set("b", json.int(2)),
    ),
    map_op_message(
      client_id: other_client_id,
      sn: 3,
      csn: 3,
      op: Set("ref", handle.encode_handle("child")),
    ),
  ]

  case runtime_core.bootstrap(connected_message(history, 4), summary: None) {
    Ok(runtime_core.Complete(core)) -> {
      runtime_core.get(core, "child", "a") |> expect.to_equal(Some(json.int(1)))
      runtime_core.get(core, "child", "b") |> expect.to_equal(Some(json.int(2)))
      root_get(core, "ref")
      |> expect.to_equal(Some(handle.encode_handle("child")))
      runtime_core.summary_channels(core)
      |> expect.to_equal([
        #(
          "root",
          channel.MapSnapshot([#("ref", handle.encode_handle("child"))]),
        ),
        #(
          "child",
          channel.MapSnapshot([#("a", json.int(1)), #("b", json.int(2))]),
        ),
      ])
    }
    _ -> panic as "expected attach history bootstrap to succeed"
  }
}
