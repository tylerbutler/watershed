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

import signet/types as token
import spillway/message
import spillway/types

import lattice_core/replica_id
import watershed/channel
import watershed/claims_kernel
import watershed/counter_kernel
import watershed/handle
import watershed/map_kernel.{Delete, Set, ValueChanged}
import watershed/or_map_kernel
import watershed/register_collection_kernel
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
    claims: token.TokenClaims(
      document_id: "dice",
      scopes: [token.DocRead, token.DocWrite],
      tenant_id: "default",
      user: token.User(id: "user-2", properties: dict.new()),
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
/// payloads are stage-two decoded against the map grammar first, then the
/// counter grammar (the op-type tags are disjoint, so this is unambiguous).
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
            decode.run(contents, ops.channel_op_decoder(channel.MapChannel)),
            decode.run(contents, ops.channel_op_decoder(channel.CounterChannel)),
            decode.run(contents, ops.channel_op_decoder(channel.OrMapChannel)),
            decode.run(
              contents,
              ops.channel_op_decoder(channel.RegisterCollectionChannel),
            ),
            decode.run(contents, ops.channel_op_decoder(channel.ClaimsChannel))
          {
            Ok(op), _, _, _, _ -> DecodedChannelOp(address: address, op: op)
            _, Ok(op), _, _, _ -> DecodedChannelOp(address: address, op: op)
            _, _, Ok(op), _, _ -> DecodedChannelOp(address: address, op: op)
            _, _, _, Ok(op), _ -> DecodedChannelOp(address: address, op: op)
            _, _, _, _, Ok(op) -> DecodedChannelOp(address: address, op: op)
            Error(_), Error(_), Error(_), Error(_), Error(_) ->
              panic as "failed to decode outbound op contents"
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
    ValueChanged(
      key: "die",
      previous_value: None,
      value: Some(json.int(4)),
      local: True,
    ),
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
    ValueChanged(
      key: "x",
      previous_value: None,
      value: Some(json.string("y")),
      local: False,
    ),
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
        value: Some(json.int(2)),
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
  let core = runtime_core.create_detached(core, "child", channel.InitMap)

  case runtime_core.set(core, "child", "a", json.int(1)) {
    Ok(#(core, events, outbound)) -> {
      events
      |> expect.to_equal([
        #(
          "child",
          channel.MapEvent(ValueChanged(
            key: "a",
            previous_value: None,
            value: Some(json.int(1)),
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
  let core = runtime_core.create_detached(core, "child", channel.InitMap)
  let core = runtime_core.create_detached(core, "grand", channel.InitMap)
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
        value: Some(handle.encode_handle("child")),
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
  let core = runtime_core.create_detached(core, "a", channel.InitMap)
  let core = runtime_core.create_detached(core, "b", channel.InitMap)
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
  let core = runtime_core.create_detached(core, "child", channel.InitMap)
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
        value: Some(json.int(2)),
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
  let core = runtime_core.create_detached(core, "child", channel.InitMap)
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
  let core = runtime_core.create_detached(core, "child", channel.InitMap)
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
  let core = runtime_core.create_detached(core, "child", channel.InitMap)
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
  let core = runtime_core.create_detached(core, "child", channel.InitMap)
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

// ─────────────────────────────────────────────────────────────────────────────
// Counter channels (R2)
// ─────────────────────────────────────────────────────────────────────────────

fn counter_op_message(
  address address: String,
  client_id client_id: String,
  sn sn: Int,
  csn csn: Int,
  op op: counter_kernel.CounterOp,
) -> types.SequencedDocumentMessage {
  sequenced_message(
    client_id: Some(client_id),
    sn: sn,
    csn: csn,
    message_type: "op",
    contents: to_dynamic(ops.encode_counter_envelope(address, op)),
  )
}

fn counter_attach_message(
  client_id client_id: String,
  sn sn: Int,
  csn csn: Int,
  address address: String,
  value value: Int,
) -> types.SequencedDocumentMessage {
  sequenced_message(
    client_id: Some(client_id),
    sn: sn,
    csn: csn,
    message_type: "op",
    contents: to_dynamic(ops.encode_attach(
      address,
      channel.CounterSnapshot(value),
    )),
  )
}

pub fn detached_counter_increment_produces_no_outbound_test() {
  let core = bootstrap(initial_messages: [], checkpoint: 1)
  let core = runtime_core.create_detached(core, "tally", channel.InitCounter)

  let assert Ok(#(core, events, outbound)) =
    runtime_core.increment(core, "tally", 3)
  events
  |> expect.to_equal([
    #("tally", channel.CounterEvent(counter_kernel.Incremented(3, 3))),
  ])
  outbound |> expect.to_equal([])
  core.in_flight |> expect.to_equal([])
  runtime_core.counter_value(core, "tally") |> expect.to_equal(Some(3))
}

pub fn counter_attach_via_handle_then_ops_round_trip_test() {
  let core = bootstrap(initial_messages: [], checkpoint: 1)
  let core = runtime_core.create_detached(core, "tally", channel.InitCounter)
  let assert Ok(#(core, _, [])) = runtime_core.increment(core, "tally", 2)

  // Storing the handle attaches the counter with its optimistic value.
  let assert Ok(#(core, _, outbound)) =
    runtime_core.set(core, "root", "tally", handle.encode_handle("tally"))
  list.map(outbound, decode_outbound_contents)
  |> expect.to_equal([
    DecodedAttach(address: "tally", snapshot: channel.CounterSnapshot(2)),
    DecodedChannelOp(
      address: "root",
      op: channel.MapOp(Set("tally", handle.encode_handle("tally"))),
    ),
  ])

  // Server echoes both; the acks retire them silently.
  let #(core, events) =
    apply_tagged(
      core,
      counter_attach_message(
        client_id: our_client_id,
        sn: 2,
        csn: 1,
        address: "tally",
        value: 2,
      ),
    )
  events |> expect.to_equal([])
  let #(core, _) =
    apply_tagged(
      core,
      channel_op_message(
        address: "root",
        client_id: our_client_id,
        sn: 3,
        csn: 2,
        op: Set("tally", handle.encode_handle("tally")),
      ),
    )
  core.in_flight |> expect.to_equal([])

  // An attached increment goes on the wire with the next CSN.
  let assert Ok(#(core, events, [outbound_op])) =
    runtime_core.increment(core, "tally", 5)
  events
  |> expect.to_equal([
    #("tally", channel.CounterEvent(counter_kernel.Incremented(5, 7))),
  ])
  outbound_op.client_sequence_number |> expect.to_equal(3)
  decode_outbound_contents(outbound_op)
  |> expect.to_equal(DecodedChannelOp(
    address: "tally",
    op: channel.CounterOp(counter_kernel.Increment(5)),
  ))

  // A remote increment applies on top of the optimistic value.
  let #(core, events) =
    apply_tagged(
      core,
      counter_op_message(
        address: "tally",
        client_id: other_client_id,
        sn: 4,
        csn: 1,
        op: counter_kernel.Increment(10),
      ),
    )
  events
  |> expect.to_equal([
    #("tally", channel.CounterEvent(counter_kernel.Incremented(10, 17))),
  ])

  // Our own echo retires the pending increment without events.
  let #(core, events) =
    apply_tagged(
      core,
      counter_op_message(
        address: "tally",
        client_id: our_client_id,
        sn: 5,
        csn: 3,
        op: counter_kernel.Increment(5),
      ),
    )
  events |> expect.to_equal([])
  core.in_flight |> expect.to_equal([])
  runtime_core.counter_value(core, "tally") |> expect.to_equal(Some(17))
}

pub fn remote_counter_attach_then_wrong_amount_ack_is_fatal_test() {
  let core = bootstrap(initial_messages: [], checkpoint: 1)
  let #(core, events) =
    apply_tagged(
      core,
      counter_attach_message(
        client_id: other_client_id,
        sn: 2,
        csn: 1,
        address: "tally",
        value: 40,
      ),
    )
  events |> expect.to_equal([])
  runtime_core.counter_value(core, "tally") |> expect.to_equal(Some(40))

  let assert Ok(#(core, _, [_])) = runtime_core.increment(core, "tally", 1)
  expect_error(
    runtime_core.handle_sequenced(
      core,
      counter_op_message(
        address: "tally",
        client_id: our_client_id,
        sn: 3,
        csn: 1,
        op: counter_kernel.Increment(9),
      ),
    ),
    fn(core_error) {
      case core_error {
        runtime_core.AckMismatch(_) -> True
        _ -> False
      }
    },
  )
}

pub fn reconnect_resubmits_counter_ops_restamped_test() {
  let core = bootstrap(initial_messages: [], checkpoint: 1)
  let #(core, _) =
    apply_tagged(
      core,
      counter_attach_message(
        client_id: other_client_id,
        sn: 2,
        csn: 1,
        address: "tally",
        value: 0,
      ),
    )
  let assert Ok(#(core, _, [_])) = runtime_core.increment(core, "tally", 1)
  let assert Ok(#(core, _, [_])) = runtime_core.increment(core, "tally", 2)

  let core =
    runtime_core.adopt_reconnect(
      core,
      reconnect_connected(client_id: reconnect_client_id, checkpoint: 2),
    )
  let #(core, outbound) = runtime_core.resubmit(core)

  list.map(outbound, fn(op) { op.client_sequence_number })
  |> expect.to_equal([3, 4])
  list.map(outbound, decode_outbound_contents)
  |> expect.to_equal([
    DecodedChannelOp(
      address: "tally",
      op: channel.CounterOp(counter_kernel.Increment(1)),
    ),
    DecodedChannelOp(
      address: "tally",
      op: channel.CounterOp(counter_kernel.Increment(2)),
    ),
  ])
  runtime_core.counter_value(core, "tally") |> expect.to_equal(Some(3))

  // The restamped echoes ack cleanly under the new client id.
  let #(core, _) =
    apply_tagged(
      core,
      counter_op_message(
        address: "tally",
        client_id: reconnect_client_id,
        sn: 3,
        csn: 3,
        op: counter_kernel.Increment(1),
      ),
    )
  let #(core, _) =
    apply_tagged(
      core,
      counter_op_message(
        address: "tally",
        client_id: reconnect_client_id,
        sn: 4,
        csn: 4,
        op: counter_kernel.Increment(2),
      ),
    )
  core.in_flight |> expect.to_equal([])
  runtime_core.counter_value(core, "tally") |> expect.to_equal(Some(3))
}

// ─────────────────────────────────────────────────────────────────────────────
// Claims channels (R3)
// ─────────────────────────────────────────────────────────────────────────────

fn claim_op_message(
  address address: String,
  client_id client_id: String,
  sn sn: Int,
  csn csn: Int,
  op op: claims_kernel.ClaimOp,
) -> types.SequencedDocumentMessage {
  sequenced_message(
    client_id: Some(client_id),
    sn: sn,
    csn: csn,
    message_type: "op",
    contents: to_dynamic(ops.encode_claim_envelope(address, op)),
  )
}

fn claim_attach_message(
  client_id client_id: String,
  sn sn: Int,
  csn csn: Int,
  address address: String,
  entries entries: List(#(String, Json, Int)),
) -> types.SequencedDocumentMessage {
  sequenced_message(
    client_id: Some(client_id),
    sn: sn,
    csn: csn,
    message_type: "op",
    contents: to_dynamic(ops.encode_attach(
      address,
      channel.ClaimsSnapshot(entries),
    )),
  )
}

pub fn reconnect_resubmits_pending_claim_and_surfaces_resolution_test() {
  let core = bootstrap(initial_messages: [], checkpoint: 1)
  let #(core, _) =
    apply_tagged(
      core,
      claim_attach_message(
        client_id: other_client_id,
        sn: 2,
        csn: 1,
        address: "locks",
        entries: [],
      ),
    )

  let assert Ok(runtime_core.ClaimPending(
    core: core,
    outbound: [first],
    immediate_outcome: None,
  )) = runtime_core.try_set_claim(core, "locks", "owner", json.string("alice"))
  decode_outbound_contents(first)
  |> expect.to_equal(DecodedChannelOp(
    address: "locks",
    op: channel.ClaimsOp(claims_kernel.Claim(
      key: "owner",
      value: json.string("alice"),
      ref_seq: 2,
    )),
  ))

  let core =
    runtime_core.adopt_reconnect(
      core,
      reconnect_connected(client_id: reconnect_client_id, checkpoint: 3),
    )
  let #(core, _) =
    apply(core, join_message(sn: 3, joining: reconnect_client_id))
  let #(core, outbound) = runtime_core.resubmit(core)
  let assert [resubmitted] = outbound
  resubmitted.client_sequence_number |> expect.to_equal(2)
  resubmitted.reference_sequence_number |> expect.to_equal(3)
  decode_outbound_contents(resubmitted)
  |> expect.to_equal(DecodedChannelOp(
    address: "locks",
    op: channel.ClaimsOp(claims_kernel.Claim(
      key: "owner",
      value: json.string("alice"),
      ref_seq: 2,
    )),
  ))

  let ack =
    claim_op_message(
      address: "locks",
      client_id: reconnect_client_id,
      sn: 4,
      csn: 2,
      op: claims_kernel.Claim("owner", json.string("alice"), 2),
    )
  let assert Ok(#(core, ingested)) = runtime_core.handle_sequenced(core, ack)
  ingested.events
  |> expect.to_equal([
    #("locks", channel.ClaimsEvent(claims_kernel.Claimed("owner", True))),
  ])
  ingested.resolutions
  |> expect.to_equal([
    #(
      "locks",
      channel.ClaimResolved(
        "owner",
        claims_kernel.Accepted(json.string("alice")),
      ),
    ),
  ])
  runtime_core.get_claim(core, "locks", "owner")
  |> expect.to_equal(Some(json.string("alice")))
  core.in_flight |> expect.to_equal([])
}

pub fn claims_summary_round_trip_preserves_sequence_numbers_test() {
  let summary =
    runtime_core.Summary(sequence_number: 5, channels: [
      #("root", channel.MapSnapshot([])),
      #("locks", channel.ClaimsSnapshot([#("owner", json.string("alice"), 5)])),
    ])
  let core = case
    runtime_core.bootstrap(connected_message([], 5), summary: Some(summary))
  {
    Ok(runtime_core.Complete(core)) -> core
    _ -> panic as "expected summary bootstrap to complete"
  }
  runtime_core.summary_channels(core)
  |> expect.to_equal([
    #("root", channel.MapSnapshot([])),
    #("locks", channel.ClaimsSnapshot([#("owner", json.string("alice"), 5)])),
  ])

  let #(core, stale_events) =
    apply_tagged(
      core,
      claim_op_message(
        address: "locks",
        client_id: other_client_id,
        sn: 6,
        csn: 1,
        op: claims_kernel.Claim("owner", json.string("stale"), 0),
      ),
    )
  stale_events |> expect.to_equal([])
  runtime_core.get_claim(core, "locks", "owner")
  |> expect.to_equal(Some(json.string("alice")))

  let #(core, events) =
    apply_tagged(
      core,
      claim_op_message(
        address: "locks",
        client_id: other_client_id,
        sn: 7,
        csn: 2,
        op: claims_kernel.Claim("owner", json.string("carol"), 5),
      ),
    )
  events
  |> expect.to_equal([
    #("locks", channel.ClaimsEvent(claims_kernel.Claimed("owner", False))),
  ])
  runtime_core.get_claim(core, "locks", "owner")
  |> expect.to_equal(Some(json.string("carol")))
  runtime_core.summary_channels(core)
  |> expect.to_equal([
    #("root", channel.MapSnapshot([])),
    #("locks", channel.ClaimsSnapshot([#("owner", json.string("carol"), 7)])),
  ])
}

// ─────────────────────────────────────────────────────────────────────────────
// OR-map channels (OM4)
// ─────────────────────────────────────────────────────────────────────────────

fn or_map_op_message(
  address address: String,
  client_id client_id: String,
  sn sn: Int,
  csn csn: Int,
  op op: or_map_kernel.OrMapOp,
) -> types.SequencedDocumentMessage {
  sequenced_message(
    client_id: Some(client_id),
    sn: sn,
    csn: csn,
    message_type: "op",
    contents: to_dynamic(ops.encode_or_map_envelope(address, op)),
  )
}

fn or_map_attach_message(
  client_id client_id: String,
  sn sn: Int,
  csn csn: Int,
  address address: String,
  snapshot snapshot: channel.Snapshot,
) -> types.SequencedDocumentMessage {
  sequenced_message(
    client_id: Some(client_id),
    sn: sn,
    csn: csn,
    message_type: "op",
    contents: to_dynamic(ops.encode_attach(address, snapshot)),
  )
}

fn remote_tally_op(key: String, amount: Int) -> or_map_kernel.OrMapOp {
  let state =
    or_map_kernel.new(replica_id.new(other_client_id), or_map_kernel.TallyMode)
  let assert Ok(#(_, _, op, _)) = or_map_kernel.increment(state, key, amount)
  op
}

fn or_map_snapshot_entries(
  snapshot: channel.Snapshot,
) -> List(#(String, or_map_kernel.OrMapValue)) {
  let assert channel.OrMapSnapshot(mode, raw_state) = snapshot
  let assert Ok(kernel) =
    or_map_kernel.from_sequenced(raw_state, mode, replica_id.new("test-loader"))
  or_map_kernel.entries(kernel)
}

pub fn detached_or_map_increment_produces_no_outbound_test() {
  let core = bootstrap(initial_messages: [], checkpoint: 1)
  let core =
    runtime_core.create_detached(
      core,
      "scores",
      channel.InitOrMap(or_map_kernel.TallyMode),
    )

  let assert Ok(#(core, events, outbound)) =
    runtime_core.or_map_increment(core, "scores", "score", 3)
  events
  |> expect.to_equal([
    #("scores", channel.OrMapEvent(or_map_kernel.TallyUpdated("score", 3, 3))),
  ])
  outbound |> expect.to_equal([])
  core.in_flight |> expect.to_equal([])
  runtime_core.or_map_value(core, "scores", "score")
  |> expect.to_equal(Some(or_map_kernel.Tally(3)))
}

pub fn or_map_attach_via_handle_then_ops_round_trip_test() {
  let core = bootstrap(initial_messages: [], checkpoint: 1)
  let core =
    runtime_core.create_detached(
      core,
      "scores",
      channel.InitOrMap(or_map_kernel.TallyMode),
    )
  let assert Ok(#(core, _, [])) =
    runtime_core.or_map_increment(core, "scores", "score", 2)

  let assert Ok(#(core, _, outbound)) =
    runtime_core.set(core, "root", "scores", handle.encode_handle("scores"))
  let assert [attach_outbound, root_outbound] =
    list.map(outbound, decode_outbound_contents)
  let assert DecodedAttach(address: "scores", snapshot: attach_snapshot) =
    attach_outbound
  or_map_snapshot_entries(attach_snapshot)
  |> expect.to_equal([#("score", or_map_kernel.Tally(2))])
  root_outbound
  |> expect.to_equal(DecodedChannelOp(
    address: "root",
    op: channel.MapOp(Set("scores", handle.encode_handle("scores"))),
  ))

  let #(core, events) =
    apply_tagged(
      core,
      or_map_attach_message(
        client_id: our_client_id,
        sn: 2,
        csn: 1,
        address: "scores",
        snapshot: attach_snapshot,
      ),
    )
  events |> expect.to_equal([])
  let #(core, _) =
    apply_tagged(
      core,
      channel_op_message(
        address: "root",
        client_id: our_client_id,
        sn: 3,
        csn: 2,
        op: Set("scores", handle.encode_handle("scores")),
      ),
    )
  core.in_flight |> expect.to_equal([])

  let assert Ok(#(core, events, [outbound_op])) =
    runtime_core.or_map_increment(core, "scores", "score", 5)
  events
  |> expect.to_equal([
    #("scores", channel.OrMapEvent(or_map_kernel.TallyUpdated("score", 5, 7))),
  ])
  outbound_op.client_sequence_number |> expect.to_equal(3)
  let assert DecodedChannelOp(address: "scores", op: channel.OrMapOp(own_op)) =
    decode_outbound_contents(outbound_op)

  let #(core, events) =
    apply_tagged(
      core,
      or_map_op_message(
        address: "scores",
        client_id: other_client_id,
        sn: 4,
        csn: 1,
        op: remote_tally_op("score", 10),
      ),
    )
  events
  |> expect.to_equal([
    #("scores", channel.OrMapEvent(or_map_kernel.TallyUpdated("score", 10, 17))),
  ])

  let #(core, events) =
    apply_tagged(
      core,
      or_map_op_message(
        address: "scores",
        client_id: our_client_id,
        sn: 5,
        csn: 3,
        op: own_op,
      ),
    )
  events |> expect.to_equal([])
  core.in_flight |> expect.to_equal([])
  runtime_core.or_map_value(core, "scores", "score")
  |> expect.to_equal(Some(or_map_kernel.Tally(17)))
}

pub fn or_map_mode_mismatch_edits_are_rejected_test() {
  let core = bootstrap(initial_messages: [], checkpoint: 1)
  let core =
    runtime_core.create_detached(
      core,
      "registers",
      channel.InitOrMap(or_map_kernel.RegisterMode),
    )
  case runtime_core.or_map_increment(core, "registers", "k", 1) {
    Error(runtime_core.OrMapModeMismatch(address: "registers", ..)) -> Nil
    _ -> panic as "expected increment on RegisterMode to be rejected"
  }

  let core =
    runtime_core.create_detached(
      core,
      "scores",
      channel.InitOrMap(or_map_kernel.TallyMode),
    )
  case runtime_core.or_map_set(core, "scores", "k", "v", 10) {
    Error(runtime_core.OrMapModeMismatch(address: "scores", ..)) -> Nil
    _ -> panic as "expected set on TallyMode to be rejected"
  }
}

pub fn or_map_register_set_attaches_handle_dependencies_test() {
  let core = bootstrap(initial_messages: [], checkpoint: 1)
  let #(core, _) =
    apply_tagged(
      core,
      or_map_attach_message(
        client_id: other_client_id,
        sn: 2,
        csn: 1,
        address: "registers",
        snapshot: channel.attach_snapshot(channel.new(
          channel.InitOrMap(or_map_kernel.RegisterMode),
          replica: other_client_id,
        )),
      ),
    )
  let core = runtime_core.create_detached(core, "child", channel.InitMap)
  let assert Ok(#(core, _, [])) =
    runtime_core.set(core, "child", "k", json.int(1))

  let encoded_handle = json.to_string(handle.encode_handle("child"))
  let assert Ok(#(_core, _events, outbound)) =
    runtime_core.or_map_set(core, "registers", "child", encoded_handle, 99)
  let assert [attach, op] = list.map(outbound, decode_outbound_contents)
  attach
  |> expect.to_equal(DecodedAttach(
    address: "child",
    snapshot: channel.MapSnapshot([#("k", json.int(1))]),
  ))
  let assert DecodedChannelOp(
    address: "registers",
    op: channel.OrMapOp(or_map_op),
  ) = op
  case or_map_op {
    or_map_kernel.SetRegister("child", value, 99, _) ->
      value |> expect.to_equal(encoded_handle)
    _ -> panic as "expected register set op"
  }
}

pub fn wrong_channel_type_edits_are_rejected_test() {
  let core = bootstrap(initial_messages: [], checkpoint: 1)
  let core = runtime_core.create_detached(core, "tally", channel.InitCounter)

  // Map verbs on a counter channel are rejected, not applied or crashed.
  case runtime_core.set(core, "tally", "k", json.int(1)) {
    Error(runtime_core.WrongChannelType(
      address: "tally",
      expected: channel.MapChannel,
      actual: channel.CounterChannel,
    )) -> Nil
    _ -> panic as "expected set on a counter channel to be rejected"
  }
  case runtime_core.delete(core, "tally", "k") {
    Error(runtime_core.WrongChannelType(..)) -> Nil
    _ -> panic as "expected delete on a counter channel to be rejected"
  }
  case runtime_core.clear(core, "tally") {
    Error(runtime_core.WrongChannelType(..)) -> Nil
    _ -> panic as "expected clear on a counter channel to be rejected"
  }
  // And the counter verb on a map channel likewise.
  case runtime_core.increment(core, "root", 1) {
    Error(runtime_core.WrongChannelType(
      address: "root",
      expected: channel.CounterChannel,
      actual: channel.MapChannel,
    )) -> Nil
    _ -> panic as "expected increment on a map channel to be rejected"
  }
  // Reads on the wrong channel type return empty defaults.
  runtime_core.counter_value(core, "root") |> expect.to_equal(None)
  runtime_core.get(core, "tally", "k") |> expect.to_equal(None)
  runtime_core.entries(core, "tally") |> expect.to_equal([])
  runtime_core.keys(core, "tally") |> expect.to_equal([])
  runtime_core.size(core, "tally") |> expect.to_equal(0)
}

pub fn summary_captures_confirmed_counter_value_test() {
  let core = bootstrap(initial_messages: [], checkpoint: 1)
  let #(core, _) =
    apply_tagged(
      core,
      counter_attach_message(
        client_id: other_client_id,
        sn: 2,
        csn: 1,
        address: "tally",
        value: 0,
      ),
    )
  let #(core, _) =
    apply_tagged(
      core,
      counter_op_message(
        address: "tally",
        client_id: other_client_id,
        sn: 3,
        csn: 2,
        op: counter_kernel.Increment(4),
      ),
    )
  let assert Ok(#(core, _, [_])) = runtime_core.increment(core, "tally", 3)

  // The optimistic read includes the un-acked increment; the summary only
  // captures the confirmed value.
  runtime_core.counter_value(core, "tally") |> expect.to_equal(Some(7))
  runtime_core.summary_channels(core)
  |> expect.to_equal([
    #("root", channel.MapSnapshot([])),
    #("tally", channel.CounterSnapshot(4)),
  ])
}

pub fn bootstrap_from_summary_with_counter_channel_test() {
  let summary =
    runtime_core.Summary(sequence_number: 5, channels: [
      #(
        "root",
        channel.MapSnapshot([#("tally", handle.encode_handle("tally"))]),
      ),
      #("tally", channel.CounterSnapshot(9)),
    ])
  let core = case
    runtime_core.bootstrap(connected_message([], 5), summary: Some(summary))
  {
    Ok(runtime_core.Complete(core)) -> core
    _ -> panic as "expected summary bootstrap to complete"
  }
  runtime_core.counter_value(core, "tally") |> expect.to_equal(Some(9))

  let #(core, events) =
    apply_tagged(
      core,
      counter_op_message(
        address: "tally",
        client_id: other_client_id,
        sn: 6,
        csn: 1,
        op: counter_kernel.Increment(2),
      ),
    )
  events
  |> expect.to_equal([
    #("tally", channel.CounterEvent(counter_kernel.Incremented(2, 11))),
  ])
  runtime_core.counter_value(core, "tally") |> expect.to_equal(Some(11))
}

// ─────────────────────────────────────────────────────────────────────────────
// Register collection channels
// ─────────────────────────────────────────────────────────────────────────────

fn register_op_message(
  address address: String,
  client_id client_id: String,
  sn sn: Int,
  csn csn: Int,
  op op: register_collection_kernel.WriteOp,
) -> types.SequencedDocumentMessage {
  sequenced_message(
    client_id: Some(client_id),
    sn: sn,
    csn: csn,
    message_type: "op",
    contents: to_dynamic(ops.encode_register_collection_envelope(address, op)),
  )
}

fn register_attach_message(
  client_id client_id: String,
  sn sn: Int,
  csn csn: Int,
  address address: String,
  registers registers: List(#(String, register_collection_kernel.Register)),
) -> types.SequencedDocumentMessage {
  sequenced_message(
    client_id: Some(client_id),
    sn: sn,
    csn: csn,
    message_type: "op",
    contents: to_dynamic(ops.encode_attach(
      address,
      channel.RegisterCollectionSnapshot(registers),
    )),
  )
}

fn register_version(
  value: Json,
  seq: Int,
) -> register_collection_kernel.VersionedValue {
  register_collection_kernel.VersionedValue(value, seq)
}

pub fn detached_register_write_produces_no_outbound_test() {
  let core = bootstrap(initial_messages: [], checkpoint: 1)
  let core =
    runtime_core.create_detached(
      core,
      "registers",
      channel.InitRegisterCollection,
    )

  let assert Ok(#(core, events, outbound)) =
    runtime_core.register_write(core, "registers", "station", json.string("A"))
  events
  |> expect.to_equal([
    #(
      "registers",
      channel.RegisterCollectionEvent(register_collection_kernel.AtomicChanged(
        "station",
        json.string("A"),
        True,
      )),
    ),
    #(
      "registers",
      channel.RegisterCollectionEvent(register_collection_kernel.VersionChanged(
        "station",
        json.string("A"),
        True,
      )),
    ),
  ])
  outbound |> expect.to_equal([])
  runtime_core.register_read(
    core,
    "registers",
    "station",
    register_collection_kernel.Atomic,
  )
  |> expect.to_equal(Some(json.string("A")))
}

pub fn register_collection_attached_write_round_trips_test() {
  let core = bootstrap(initial_messages: [], checkpoint: 1)
  let #(core, _) =
    apply_tagged(
      core,
      register_attach_message(
        client_id: other_client_id,
        sn: 2,
        csn: 1,
        address: "registers",
        registers: [],
      ),
    )

  let assert Ok(#(core, events, [outbound])) =
    runtime_core.register_write(core, "registers", "station", json.string("A"))
  events |> expect.to_equal([])
  decode_outbound_contents(outbound)
  |> expect.to_equal(DecodedChannelOp(
    address: "registers",
    op: channel.RegisterCollectionOp(register_collection_kernel.Write(
      "station",
      json.string("A"),
      ref_seq: 2,
    )),
  ))
  runtime_core.register_read(
    core,
    "registers",
    "station",
    register_collection_kernel.Atomic,
  )
  |> expect.to_equal(None)

  let #(core, events) =
    apply_tagged(
      core,
      register_op_message(
        address: "registers",
        client_id: our_client_id,
        sn: 3,
        csn: 1,
        op: register_collection_kernel.Write(
          "station",
          json.string("A"),
          ref_seq: 2,
        ),
      ),
    )
  events
  |> expect.to_equal([
    #(
      "registers",
      channel.RegisterCollectionEvent(register_collection_kernel.AtomicChanged(
        "station",
        json.string("A"),
        True,
      )),
    ),
    #(
      "registers",
      channel.RegisterCollectionEvent(register_collection_kernel.VersionChanged(
        "station",
        json.string("A"),
        True,
      )),
    ),
  ])
  runtime_core.register_read(
    core,
    "registers",
    "station",
    register_collection_kernel.Atomic,
  )
  |> expect.to_equal(Some(json.string("A")))
  core.in_flight |> expect.to_equal([])
}

pub fn register_collection_ack_with_wrong_shape_is_fatal_test() {
  let core = bootstrap(initial_messages: [], checkpoint: 1)
  let #(core, _) =
    apply_tagged(
      core,
      register_attach_message(
        client_id: other_client_id,
        sn: 2,
        csn: 1,
        address: "registers",
        registers: [],
      ),
    )
  let assert Ok(#(core, _, [_])) =
    runtime_core.register_write(core, "registers", "station", json.string("A"))

  runtime_core.handle_sequenced(
    core,
    register_op_message(
      address: "registers",
      client_id: our_client_id,
      sn: 3,
      csn: 1,
      op: register_collection_kernel.Write(
        "station",
        json.string("B"),
        ref_seq: 2,
      ),
    ),
  )
  |> expect_error(fn(core_error) {
    case core_error {
      runtime_core.AckMismatch(_) -> True
      _ -> False
    }
  })
}

pub fn bootstrap_from_summary_with_register_collection_test() {
  let version = register_version(json.string("Survey"), 5)
  let summary =
    runtime_core.Summary(sequence_number: 5, channels: [
      #("root", channel.MapSnapshot([])),
      #(
        "registers",
        channel.RegisterCollectionSnapshot([
          #("station", register_collection_kernel.Register(version, [version])),
        ]),
      ),
    ])
  let core = case
    runtime_core.bootstrap(connected_message([], 5), summary: Some(summary))
  {
    Ok(runtime_core.Complete(core)) -> core
    _ -> panic as "expected summary bootstrap to complete"
  }
  runtime_core.register_read(
    core,
    "registers",
    "station",
    register_collection_kernel.Atomic,
  )
  |> expect.to_equal(Some(json.string("Survey")))

  let #(core, events) =
    apply_tagged(
      core,
      register_op_message(
        address: "registers",
        client_id: other_client_id,
        sn: 6,
        csn: 1,
        op: register_collection_kernel.Write(
          "station",
          json.string("Remote"),
          ref_seq: 5,
        ),
      ),
    )
  events
  |> expect.to_equal([
    #(
      "registers",
      channel.RegisterCollectionEvent(register_collection_kernel.AtomicChanged(
        "station",
        json.string("Remote"),
        False,
      )),
    ),
    #(
      "registers",
      channel.RegisterCollectionEvent(register_collection_kernel.VersionChanged(
        "station",
        json.string("Remote"),
        False,
      )),
    ),
  ])
  runtime_core.register_versions(core, "registers", "station")
  |> expect.to_equal(Some([json.string("Remote")]))
}

// ─────────────────────────────────────────────────────────────────────────────
// Generic owed-ops buffer (reaction auto-submit infra)
// ─────────────────────────────────────────────────────────────────────────────

pub fn owed_op_is_auto_submitted_after_sequenced_batch_test() {
  let core = bootstrap(initial_messages: [], checkpoint: 1)

  // A reacting kernel arm would return this from `channel.apply_remote`; inject
  // it directly to exercise the generic buffer without a producing kernel.
  let owed = channel.MapOp(Set("owed", json.int(9)))
  let core = runtime_core.enqueue_owed(core, "root", [owed])

  // A remote op drives a sequenced batch; `collect_released_ops` then drains the
  // owed buffer, stamping the follow-up with a fresh CSN + in-flight entry.
  let assert Ok(#(core, ingested)) =
    runtime_core.handle_sequenced(
      core,
      map_op_message(
        client_id: other_client_id,
        sn: 2,
        csn: 5,
        op: Set("trigger", json.int(1)),
      ),
    )

  // Exactly one auto-submitted op: the owed MapOp, stamped with csn 1 (the first
  // free CSN) and rsn = the batch's last-seen SN.
  let assert [outbound] = ingested.outbound
  outbound.client_sequence_number |> expect.to_equal(1)
  outbound.reference_sequence_number |> expect.to_equal(2)
  decode_outbound_contents(outbound)
  |> expect.to_equal(DecodedChannelOp(address: "root", op: owed))

  // It is recorded in-flight so the ordinary ack path reclaims it, ...
  core.in_flight
  |> expect.to_equal([
    runtime_core.InFlightOp(
      client_id: our_client_id,
      csn: 1,
      address: "root",
      op: owed,
      meta: channel.NoMeta,
    ),
  ])
  core.next_csn |> expect.to_equal(2)

  // ... and it is auto-submit only — not applied locally (it applies when it
  // comes back sequenced).
  root_has(core, "owed") |> expect.to_equal(False)
}

pub fn multiple_owed_ops_drain_in_order_with_sequential_csns_test() {
  let core = bootstrap(initial_messages: [], checkpoint: 1)

  let first = channel.MapOp(Set("first", json.int(1)))
  let second = channel.MapOp(Set("second", json.int(2)))
  // Two separate enqueues accumulate (append) on the same channel.
  let core = runtime_core.enqueue_owed(core, "root", [first])
  let core = runtime_core.enqueue_owed(core, "root", [second])

  let assert Ok(#(core, ingested)) =
    runtime_core.handle_sequenced(
      core,
      map_op_message(
        client_id: other_client_id,
        sn: 2,
        csn: 5,
        op: Set("trigger", json.int(1)),
      ),
    )

  list.map(ingested.outbound, fn(op) {
    #(op.client_sequence_number, decode_outbound_contents(op))
  })
  |> expect.to_equal([
    #(1, DecodedChannelOp(address: "root", op: first)),
    #(2, DecodedChannelOp(address: "root", op: second)),
  ])
  core.next_csn |> expect.to_equal(3)
}
