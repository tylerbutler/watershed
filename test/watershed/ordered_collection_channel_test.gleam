//// ConsensusOrderedCollection ↔ runtime wiring tests: the ordered_collection
//// kernel driven through `channel` + `runtime_core` + the wire codecs. Kernel
//// FIFO/job semantics are covered by `ordered_collection_kernel_test`/the fuzz
//// model; these pin the *wiring*: op/snapshot encode-decode, `same_shape`,
//// detached add/acquire carried through attach, and two-client FIFO
//// convergence (add / acquire / complete / release) over sequenced ops.

import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/json.{type Json}
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import startest/expect

import signet/types as token
import spillway/message
import spillway/types

import watershed/channel
import watershed/handle
import watershed/ordered_collection_kernel
import watershed/runtime_core.{type Core}
import watershed/wire
import watershed/wire/ops

const id_a = "default_doc_1"

const id_b = "default_doc_2"

const oc = "oc-1"

// ── fixtures ────────────────────────────────────────────────────────────────

fn to_dynamic(value: Json) -> Dynamic {
  case json.parse(json.to_string(value), decode.dynamic) {
    Ok(dynamic_value) -> dynamic_value
    Error(_) -> panic as "fixture JSON failed to re-parse"
  }
}

fn connected_message(client_id: String) -> message.ConnectedMessage {
  message.ConnectedMessage(
    claims: token.TokenClaims(
      document_id: "doc",
      scopes: [token.DocRead, token.DocWrite],
      tenant_id: "default",
      user: token.User(id: "user", properties: dict.new()),
      issued_at: 0,
      expiration: 0,
      version: "1.0",
      jti: None,
    ),
    client_id: client_id,
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
    initial_messages: [],
    initial_signals: [],
    supported_versions: ["^0.1.0"],
    supported_features: dict.new(),
    version: "^0.1.0",
    timestamp: None,
    checkpoint_sequence_number: Some(1),
    epoch: None,
    relay_service_agent: None,
    summary_context: None,
  )
}

fn bootstrap(client_id: String) -> Core {
  let assert Ok(runtime_core.Complete(core)) =
    runtime_core.bootstrap(connected_message(client_id), summary: None)
  core
}

fn seq_msg(
  author: String,
  sn: Int,
  out: wire.OutboundOp,
) -> types.SequencedDocumentMessage {
  types.SequencedDocumentMessage(
    client_id: Some(author),
    sequence_number: sn,
    minimum_sequence_number: 0,
    client_sequence_number: out.client_sequence_number,
    reference_sequence_number: out.reference_sequence_number,
    message_type: out.op_type,
    contents: to_dynamic(out.contents),
    metadata: None,
    server_metadata: None,
    origin: None,
    traces: None,
    timestamp: 0,
    data: None,
  )
}

fn expect_ok(
  result: Result(
    #(Core, List(#(String, channel.ChannelEvent)), List(wire.OutboundOp)),
    runtime_core.CoreError,
  ),
) -> #(Core, List(wire.OutboundOp)) {
  case result {
    Ok(#(core, _events, outbound)) -> #(core, outbound)
    Error(err) -> panic as { "ordered command failed: " <> string.inspect(err) }
  }
}

fn ingest(
  core: Core,
  msg: types.SequencedDocumentMessage,
) -> #(Core, runtime_core.Ingested) {
  case runtime_core.handle_sequenced(core, msg) {
    Ok(pair) -> pair
    Error(err) ->
      panic as { "handle_sequenced failed: " <> string.inspect(err) }
  }
}

// ── wire codec ────────────────────────────────────────────────────────────────

/// The four ordered ops survive the channel-op wire round-trip.
pub fn ordered_op_wire_round_trips_test() {
  round_trip_op(ordered_collection_kernel.Add(json.string("job")))
  round_trip_op(ordered_collection_kernel.Acquire("acq-7"))
  round_trip_op(ordered_collection_kernel.Complete("acq-7"))
  round_trip_op(ordered_collection_kernel.Release("acq-7"))
}

fn round_trip_op(op: ordered_collection_kernel.OrderedOp) {
  let encoded = ops.encode_channel_op(channel.OrderedCollectionOp(op))
  let assert Ok(decoded) =
    json.parse(
      json.to_string(encoded),
      ops.channel_op_decoder(channel.OrderedCollectionChannel),
    )
  json.to_string(ops.encode_channel_op(decoded))
  |> expect.to_equal(json.to_string(encoded))
}

// ── snapshot codec ────────────────────────────────────────────────────────────

/// A summary with a queued value and a held job survives the snapshot codec.
pub fn ordered_snapshot_round_trips_test() {
  let #(state, _) =
    ordered_collection_kernel.add_detached(
      ordered_collection_kernel.new(),
      json.string("queued"),
    )
  let #(state, _) =
    ordered_collection_kernel.add_detached(state, json.string("held"))
  // Acquire the head into a job so the snapshot carries a jobs entry.
  let #(state, _, _) =
    ordered_collection_kernel.acquire_detached(state, "acq-9")

  let snapshot =
    channel.OrderedCollectionSnapshot(
      ordered_collection_kernel.summary_queue(state),
      ordered_collection_kernel.summary_jobs(state),
    )
  let encoded = channel.encode_snapshot(snapshot)
  let assert Ok(decoded) =
    json.parse(
      json.to_string(encoded),
      channel.snapshot_decoder(channel.OrderedCollectionChannel),
    )
  channel.same_snapshot(snapshot, decoded) |> expect.to_be_true()
}

pub fn ordered_channel_type_round_trips_test() {
  channel.type_to_string(channel.OrderedCollectionChannel)
  |> channel.type_from_string
  |> expect.to_equal(Ok(channel.OrderedCollectionChannel))
}

// ── echo / same_shape ─────────────────────────────────────────────────────────

pub fn ordered_same_shape_echo_test() {
  let add =
    channel.OrderedCollectionOp(ordered_collection_kernel.Add(json.string("j")))
  channel.same_shape(add, add) |> expect.to_be_true()

  // A different value, id, or op kind is not the same shape.
  let other =
    channel.OrderedCollectionOp(ordered_collection_kernel.Add(json.string("k")))
  channel.same_shape(add, other) |> expect.to_be_false()

  let acquire =
    channel.OrderedCollectionOp(ordered_collection_kernel.Acquire("acq-1"))
  channel.same_shape(acquire, acquire) |> expect.to_be_true()
  channel.same_shape(
    acquire,
    channel.OrderedCollectionOp(ordered_collection_kernel.Acquire("acq-2")),
  )
  |> expect.to_be_false()
  channel.same_shape(add, acquire) |> expect.to_be_false()
}

// ── detached add carried through attach ───────────────────────────────────────

pub fn detached_add_attaches_with_optimistic_queue_test() {
  let core =
    bootstrap(id_a)
    |> runtime_core.create_detached(oc, channel.InitOrderedCollection)

  let #(core, _) =
    expect_ok(runtime_core.ordered_add(core, oc, json.string("d1")))
  let #(core, _) =
    expect_ok(runtime_core.ordered_add(core, oc, json.string("d2")))
  runtime_core.ordered_size(core, oc) |> expect.to_equal(Some(2))

  // Attaching the channel preserves the detached items.
  let #(core, _attach_out) =
    expect_ok(runtime_core.set(core, "root", "q", handle.encode_handle(oc)))
  runtime_core.ordered_size(core, oc) |> expect.to_equal(Some(2))
  runtime_core.ordered_queue(core, oc)
  |> list.map(json.to_string)
  |> expect.to_equal([
    json.to_string(json.string("d1")),
    json.to_string(json.string("d2")),
  ])
}

// ── two-client FIFO convergence ───────────────────────────────────────────────

/// Two attached clients converge on add / acquire / release / complete driven
/// entirely through sequenced ops: adds append FIFO, an acquire removes the head
/// into a job on both replicas (delivering the item via the `Acquired` event),
/// a release returns it to the tail, and a complete drops it.
pub fn two_clients_converge_via_sequenced_ops_test() {
  let #(core_a, core_b, sn) = attached_pair()

  // A appends job1 then job2; sequence each op to both replicas.
  let #(core_a, add1) =
    expect_ok(runtime_core.ordered_add(core_a, oc, json.string("job1")))
  let assert [add1_op] = add1
  let #(core_a, core_b, sn, _) = drive(core_a, core_b, id_a, sn, add1_op)

  let #(core_a, add2) =
    expect_ok(runtime_core.ordered_add(core_a, oc, json.string("job2")))
  let assert [add2_op] = add2
  let #(core_a, core_b, sn, _) = drive(core_a, core_b, id_a, sn, add2_op)

  runtime_core.ordered_size(core_a, oc) |> expect.to_equal(Some(2))
  runtime_core.ordered_size(core_b, oc) |> expect.to_equal(Some(2))

  // B acquires the head; the op is non-optimistic, so B's size is unchanged
  // until it sequences.
  let #(core_b, acq) =
    expect_ok(runtime_core.ordered_acquire(core_b, oc, "acq-1"))
  let assert [acq_op] = acq
  runtime_core.ordered_size(core_b, oc) |> expect.to_equal(Some(2))
  // Author = B, so B acks (author-side events) while A applies remotely.
  let #(core_a, core_b, sn, b_events) = drive(core_a, core_b, id_b, sn, acq_op)

  // The head (job1) is delivered to B via the Acquired event.
  acquired_value(b_events)
  |> expect.to_equal(Some(json.to_string(json.string("job1"))))
  runtime_core.ordered_size(core_a, oc) |> expect.to_equal(Some(1))
  runtime_core.ordered_size(core_b, oc) |> expect.to_equal(Some(1))

  // B releases the job; job1 returns to the tail on both replicas.
  let #(core_b, rel) =
    expect_ok(runtime_core.ordered_release(core_b, oc, "acq-1"))
  let assert [rel_op] = rel
  let #(core_a, core_b, sn, _) = drive(core_a, core_b, id_b, sn, rel_op)
  runtime_core.ordered_queue(core_a, oc)
  |> list.map(json.to_string)
  |> expect.to_equal([
    json.to_string(json.string("job2")),
    json.to_string(json.string("job1")),
  ])
  runtime_core.ordered_size(core_a, oc) |> expect.to_equal(Some(2))

  // A acquires the new head (job2, FIFO), then completes it: it is dropped.
  let #(core_a, acq2) =
    expect_ok(runtime_core.ordered_acquire(core_a, oc, "acq-2"))
  let assert [acq2_op] = acq2
  let #(core_a, core_b, sn, a_events) = drive(core_a, core_b, id_a, sn, acq2_op)
  acquired_value(a_events)
  |> expect.to_equal(Some(json.to_string(json.string("job2"))))

  let #(core_a, comp) =
    expect_ok(runtime_core.ordered_complete(core_a, oc, "acq-2"))
  let assert [comp_op] = comp
  let #(core_a, core_b, _sn, _) = drive(core_a, core_b, id_a, sn, comp_op)

  // job2 completed and dropped; job1 remains queued on both.
  runtime_core.ordered_queue(core_a, oc)
  |> list.map(json.to_string)
  |> expect.to_equal([json.to_string(json.string("job1"))])
  runtime_core.ordered_queue(core_a, oc)
  |> expect.to_equal(runtime_core.ordered_queue(core_b, oc))
  runtime_core.ordered_jobs(core_a, oc) |> list.length |> expect.to_equal(0)
}

/// A client that acquired a job then leaves the session has its held job
/// re-released to the queue on the remaining replica via a sequenced `"leave"`
/// system message, so another client can re-acquire it.
pub fn acquired_job_re_releases_on_client_leave_test() {
  let #(core_a, core_b, sn) = attached_pair()

  // A appends job1.
  let #(core_a, add1) =
    expect_ok(runtime_core.ordered_add(core_a, oc, json.string("job1")))
  let assert [add1_op] = add1
  let #(core_a, core_b, sn, _) = drive(core_a, core_b, id_a, sn, add1_op)

  // B acquires job1; it becomes B's held job on both replicas.
  let #(core_b, acq) =
    expect_ok(runtime_core.ordered_acquire(core_b, oc, "acq-1"))
  let assert [acq_op] = acq
  let #(core_a, _core_b, sn, _) = drive(core_a, core_b, id_b, sn, acq_op)
  runtime_core.ordered_size(core_a, oc) |> expect.to_equal(Some(0))
  runtime_core.ordered_jobs(core_a, oc) |> list.length |> expect.to_equal(1)

  // B leaves: the server sequences a "leave" carrying B's id; A re-releases
  // job1 back to the queue, surfacing it as an Added event.
  let #(core_a, ingested) = ingest(core_a, leave_msg(id_b, sn + 1))
  added_value(ingested.events)
  |> expect.to_equal(Some(json.to_string(json.string("job1"))))
  runtime_core.ordered_queue(core_a, oc)
  |> list.map(json.to_string)
  |> expect.to_equal([json.to_string(json.string("job1"))])
  runtime_core.ordered_jobs(core_a, oc) |> list.length |> expect.to_equal(0)

  // A can now re-acquire the freed job.
  let #(core_a, acq2) =
    expect_ok(runtime_core.ordered_acquire(core_a, oc, "acq-2"))
  let assert [acq2_op] = acq2
  let #(core_a, ingested_a) = ingest(core_a, seq_msg(id_a, sn + 2, acq2_op))
  acquired_value(ingested_a.events)
  |> expect.to_equal(Some(json.to_string(json.string("job1"))))
}

/// A membership `"leave"` for a client that holds no jobs (and matches no
/// per-client state) is a harmless no-op: the queue is untouched.
pub fn leave_for_unrelated_client_is_noop_test() {
  let #(core_a, core_b, sn) = attached_pair()

  let #(core_a, add1) =
    expect_ok(runtime_core.ordered_add(core_a, oc, json.string("job1")))
  let assert [add1_op] = add1
  let #(core_a, _core_b, sn, _) = drive(core_a, core_b, id_a, sn, add1_op)

  let #(core_a, ingested) = ingest(core_a, leave_msg("phantom_99", sn + 1))
  ingested.events |> expect.to_equal([])
  runtime_core.ordered_queue(core_a, oc)
  |> list.map(json.to_string)
  |> expect.to_equal([json.to_string(json.string("job1"))])
}

/// A sequenced `"leave"` system message: `clientId` is null and `contents`
/// carries the departing client's id string, stamped with a sequence number.
fn leave_msg(leaving: String, sn: Int) -> types.SequencedDocumentMessage {
  types.SequencedDocumentMessage(
    client_id: None,
    sequence_number: sn,
    minimum_sequence_number: 0,
    client_sequence_number: -1,
    reference_sequence_number: sn - 1,
    message_type: "leave",
    contents: to_dynamic(json.string(leaving)),
    metadata: None,
    server_metadata: None,
    origin: None,
    traces: None,
    timestamp: 0,
    data: None,
  )
}

fn added_value(
  events: List(#(String, channel.ChannelEvent)),
) -> option.Option(String) {
  list.fold(events, None, fn(found, tagged) {
    case found, tagged.1 {
      Some(_), _ -> found
      None,
        channel.OrderedCollectionEvent(ordered_collection_kernel.Added(
          value,
          _,
          _,
        ))
      -> Some(json.to_string(value))
      None, _ -> None
    }
  })
}

/// Bootstrap two clients and attach an ordered collection created by A, driving
/// A's attach ops through both cores so their watermarks match. Returns the two
/// cores and the next sequence number.
fn attached_pair() -> #(Core, Core, Int) {
  let core_a =
    bootstrap(id_a)
    |> runtime_core.create_detached(oc, channel.InitOrderedCollection)
  let #(core_a, attach_out) =
    expect_ok(runtime_core.set(core_a, "root", "q", handle.encode_handle(oc)))

  let core_b = bootstrap(id_b)
  list.fold(attach_out, #(core_a, core_b, 1), fn(acc, out) {
    let #(core_a, core_b, sn) = acc
    let msg = seq_msg(id_a, sn + 1, out)
    let #(core_a, _) = ingest(core_a, msg)
    let #(core_b, _) = ingest(core_b, msg)
    #(core_a, core_b, sn + 1)
  })
}

/// Sequence `out` to both cores in order, keeping the A/B identities stable.
/// `author` names the submitting client; that core acks its own op while the
/// other applies it remotely. Returns both cores (A, B order), the advanced sn,
/// and the events the *author*'s core produced.
fn drive(
  core_a: Core,
  core_b: Core,
  author: String,
  sn: Int,
  out: wire.OutboundOp,
) -> #(Core, Core, Int, List(#(String, channel.ChannelEvent))) {
  let msg = seq_msg(author, sn + 1, out)
  let #(core_a, ingested_a) = ingest(core_a, msg)
  let #(core_b, ingested_b) = ingest(core_b, msg)
  let author_events = case author == id_a {
    True -> ingested_a.events
    False -> ingested_b.events
  }
  #(core_a, core_b, sn + 1, author_events)
}

fn acquired_value(
  events: List(#(String, channel.ChannelEvent)),
) -> option.Option(String) {
  list.fold(events, None, fn(found, tagged) {
    case found, tagged.1 {
      Some(_), _ -> found
      None,
        channel.OrderedCollectionEvent(ordered_collection_kernel.Acquired(
          value,
          _,
          _,
        ))
      -> Some(json.to_string(value))
      None, _ -> None
    }
  })
}
