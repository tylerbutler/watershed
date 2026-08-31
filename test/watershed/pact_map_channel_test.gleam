//// PactMap ↔ runtime wiring tests: the consensus PactMap kernel driven through
//// `channel` + `runtime_core` + the wire codecs. Kernel-internal quorum
//// semantics are covered by `pact_map_kernel_test`/`pact_map_fuzz_test`; these
//// pin the *wiring*: operation/snapshot encode-decode, `same_shape`, the
//// auto-Accept reaction released after a `Set` sequences, and channel-level
//// convergence under a consistent quorum.
////
//// Convergence is asserted at the *channel* level (`apply_remote` with an
//// explicit, client-independent quorum) to keep these tests about the channel
//// rather than about how a quorum is derived. The runtime draws the real one
//// from the membership roster — see `roster_test` for that, and the sluice
//// driver suite for it end to end.

import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/json.{type Json}
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import startest/expect

import signet/types as token
import spillway/message
import spillway/types

import watershed/channel
import watershed/handle
import watershed/pact_map_kernel
import watershed/runtime_core.{type Core}
import watershed/wire
import watershed/wire/op as wire_op

const id_a = "default_doc_1"

const id_b = "default_doc_2"

const pact_map_address = "pm-1"

// ── fixtures ────────────────────────────────────────────────────────────────

fn json_to_dynamic(value: Json) -> Dynamic {
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

fn sequenced_message(
  author: String,
  sequence_number: Int,
  out: wire.OutboundOperation,
) -> types.SequencedDocumentMessage {
  types.SequencedDocumentMessage(
    client_id: Some(author),
    sequence_number: sequence_number,
    minimum_sequence_number: 0,
    client_sequence_number: out.client_sequence_number,
    reference_sequence_number: out.reference_sequence_number,
    message_type: out.operation_type,
    contents: json_to_dynamic(out.contents),
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
    #(Core, List(#(String, channel.ChannelEvent)), List(wire.OutboundOperation)),
    runtime_core.CoreError,
  ),
) -> #(Core, List(wire.OutboundOperation)) {
  case result {
    Ok(#(core, _events, outbound)) -> #(core, outbound)
    Error(error) ->
      panic as { "pact_map command failed: " <> string.inspect(error) }
  }
}

fn ingest(
  core: Core,
  sequenced: types.SequencedDocumentMessage,
) -> #(Core, runtime_core.Ingested) {
  case runtime_core.handle_sequenced(core, sequenced) {
    Ok(pair) -> pair
    Error(error) ->
      panic as { "handle_sequenced failed: " <> string.inspect(error) }
  }
}

// ── wire codec ────────────────────────────────────────────────────────────────

/// `Set`/`Accept` operations survive the channel-operation wire round-trip, and
/// a `Set`'s `None` (tombstone) value is preserved distinctly from a JSON null.
pub fn pact_map_operation_wire_round_trips_test() -> Nil {
  round_trip_operation(pact_map_kernel.Set(
    "grade",
    Some(json.string("2.1%")),
    4,
  ))
  round_trip_operation(pact_map_kernel.Set("grade", None, 7))
  round_trip_operation(pact_map_kernel.Set("grade", Some(json.null()), 2))
  round_trip_operation(pact_map_kernel.Accept("grade"))
}

fn round_trip_operation(operation: pact_map_kernel.PactMapOperation) -> Nil {
  let encoded =
    wire_op.encode_channel_operation(channel.PactMapOperation(operation))
  let assert Ok(decoded) =
    json.parse(
      json.to_string(encoded),
      wire_op.channel_operation_decoder(channel.PactMapChannel),
    )
  // Compare via re-encoding: `Json` values are opaque and not reliably equal
  // across a decode, but their canonical encodings are.
  json.to_string(wire_op.encode_channel_operation(decoded))
  |> expect.to_equal(json.to_string(encoded))
}

// ── snapshot codec ────────────────────────────────────────────────────────────

/// A PactMap summary (accepted + pending entries) survives the snapshot codec.
pub fn pact_map_snapshot_round_trips_test() -> Nil {
  // Accepted entry: an empty connected quorum settles the set immediately.
  let #(state, _, _) =
    pact_map_kernel.apply_set(
      pact_map_kernel.new(),
      pact_map_kernel.Set("accepted", Some(json.string("v1")), 0),
      5,
      [],
      1,
    )
  // Pending entry: a two-member quorum keeps it pending.
  let #(state, _, _) =
    pact_map_kernel.apply_set(
      state,
      pact_map_kernel.Set("pending", Some(json.string("v2")), 0),
      6,
      [1, 2],
      1,
    )

  let snapshot = channel.PactMapSnapshot(pact_map_kernel.summary_entries(state))
  let encoded = channel.encode_snapshot(snapshot)
  let assert Ok(decoded) =
    json.parse(
      json.to_string(encoded),
      channel.snapshot_decoder(channel.PactMapChannel),
    )
  channel.same_snapshot(snapshot, decoded) |> expect.to_be_true()
}

pub fn pact_map_channel_type_round_trips_test() -> Nil {
  channel.type_to_string(channel.PactMapChannel)
  |> channel.string_to_type
  |> expect.to_equal(Ok(channel.PactMapChannel))
}

// ── echo / same_shape ─────────────────────────────────────────────────────────

pub fn pact_map_same_shape_echo_test() -> Nil {
  let set =
    channel.PactMapOperation(pact_map_kernel.Set("k", Some(json.string("v")), 3))
  channel.same_shape(set, set) |> expect.to_be_true()

  // A different value or operation kind is not the same shape.
  let other =
    channel.PactMapOperation(pact_map_kernel.Set("k", Some(json.string("w")), 3))
  channel.same_shape(set, other) |> expect.to_be_false()
  channel.same_shape(set, channel.PactMapOperation(pact_map_kernel.Accept("k")))
  |> expect.to_be_false()
}

// ── channel-level convergence (consistent quorum) ─────────────────────────────

/// Drive two channel states through the full consensus lifecycle with a
/// client-independent quorum `[1, 2]`: a `Set` goes pending on both, each
/// client's `Accept` drains one signoff, and after both the value is accepted
/// and identical on both replicas.
pub fn two_clients_converge_via_consistent_quorum_test() -> Nil {
  let quorum = [1, 2]
  let value = json.string("recorded")
  let a0 = channel.new(channel.InitPactMap, replica: id_a)
  let b0 = channel.new(channel.InitPactMap, replica: id_b)

  let set_operation =
    channel.PactMapOperation(pact_map_kernel.Set("bm-17", Some(value), 0))

  // Set sequences at 2 (author = client 1); both apply it and go pending.
  let #(a1, _, owed_a) =
    apply(
      a0,
      set_operation,
      sequence_number: 2,
      author: 1,
      self_id: 1,
      quorum: quorum,
    )
  let #(b1, _, owed_b) =
    apply(
      b0,
      set_operation,
      sequence_number: 2,
      author: 1,
      self_id: 2,
      quorum: quorum,
    )
  // Both clients are in the signoff list, so both owe an Accept.
  owed_a
  |> expect.to_equal([channel.PactMapOperation(pact_map_kernel.Accept("bm-17"))])
  owed_b
  |> expect.to_equal([channel.PactMapOperation(pact_map_kernel.Accept("bm-17"))])
  is_pending(a1, "bm-17") |> expect.to_be_true()
  is_pending(b1, "bm-17") |> expect.to_be_true()

  let accept = channel.PactMapOperation(pact_map_kernel.Accept("bm-17"))

  // Client 1's Accept sequences at 3; still pending (client 2 outstanding).
  let #(a2, _, _) =
    apply(a1, accept, sequence_number: 3, author: 1, self_id: 1, quorum: quorum)
  let #(b2, _, _) =
    apply(b1, accept, sequence_number: 3, author: 1, self_id: 2, quorum: quorum)
  is_pending(a2, "bm-17") |> expect.to_be_true()

  // Client 2's Accept sequences at 4; the value settles on both replicas.
  let #(a3, _, _) =
    apply(a2, accept, sequence_number: 4, author: 2, self_id: 1, quorum: quorum)
  let #(b3, _, _) =
    apply(b2, accept, sequence_number: 4, author: 2, self_id: 2, quorum: quorum)

  is_pending(a3, "bm-17") |> expect.to_be_false()
  get(a3, "bm-17")
  |> expect.to_equal(Ok(json.to_string(value)))
  get(a3, "bm-17") |> expect.to_equal(get(b3, "bm-17"))
}

/// When a client whose signoff a pending value is still waiting on leaves the
/// session, `channel.on_leave` drains that outstanding signoff so the value can
/// settle — the same deterministic path FluidFramework drives off quorum
/// `removeMember`.
pub fn pending_value_settles_when_signer_leaves_test() -> Nil {
  let quorum = [1, 2]
  let value = json.string("recorded")
  let state = channel.new(channel.InitPactMap, replica: id_a)

  // Set sequences at 2 (author = client 1); the value goes pending with both
  // clients in the signoff list.
  let set_operation =
    channel.PactMapOperation(pact_map_kernel.Set("bm-17", Some(value), 0))
  let #(state, _, _) =
    apply(
      state,
      set_operation,
      sequence_number: 2,
      author: 1,
      self_id: 1,
      quorum: quorum,
    )

  // Client 1 accepts at 3; still pending on client 2's outstanding signoff.
  let accept = channel.PactMapOperation(pact_map_kernel.Accept("bm-17"))
  let #(state, _, _) =
    apply(
      state,
      accept,
      sequence_number: 3,
      author: 1,
      self_id: 1,
      quorum: quorum,
    )
  is_pending(state, "bm-17") |> expect.to_be_true()

  // Instead of accepting, client 2 leaves at sequence_number 5: its signoff is
  // dropped, the signoff list empties, and the value settles to accepted.
  let #(state, events) = channel.on_leave(state, 2, 5)
  events
  |> expect.to_equal([
    channel.PactMapEvent(pact_map_kernel.WentAccepted("bm-17")),
  ])
  is_pending(state, "bm-17") |> expect.to_be_false()
  get(state, "bm-17") |> expect.to_equal(Ok(json.to_string(value)))
}

fn apply(
  state: channel.ChannelState,
  operation: channel.ChannelOperation,
  sequence_number sequence_number: Int,
  author author: Int,
  self_id self_id: Int,
  quorum quorum: List(Int),
) -> #(
  channel.ChannelState,
  List(channel.ChannelEvent),
  List(channel.ChannelOperation),
) {
  let meta =
    channel.SequencedMeta(
      sequence_number: sequence_number,
      last_seen_sequence_number: sequence_number - 1,
      minimum_sequence_number: 0,
      author: author,
      self: self_id,
      quorum: quorum,
      roster: quorum,
      reference_sequence_number: 0,
    )
  case channel.apply_remote(state, operation, meta) {
    Ok(result) -> result
    Error(error) -> panic as { "apply_remote failed: " <> string.inspect(error) }
  }
}

fn is_pending(state: channel.ChannelState, key: String) -> Bool {
  let assert channel.PactMapState(kernel) = state
  pact_map_kernel.is_pending(kernel, key)
}

fn get(state: channel.ChannelState, key: String) -> Result(String, Nil) {
  let assert channel.PactMapState(kernel) = state
  pact_map_kernel.get(kernel, key) |> result.map(json.to_string)
}

// ── runtime reaction (own-set auto-Accept) ────────────────────────────────────

/// When a remote `Set` naming this client in the (approximated) quorum
/// sequences, the runtime auto-submits an `Accept` follow-up via the
/// released-operations loop — no explicit accept verb is called.
pub fn remote_set_auto_submits_accept_test() -> Nil {
  // A attaches a PactMap channel and shares it; B receives the attach.
  let core_a =
    bootstrap(id_a)
    |> runtime_core.create_detached(pact_map_address, channel.InitPactMap)
  let #(core_a, attach_out) =
    expect_ok(runtime_core.set(
      core_a,
      "root",
      "pm",
      handle.encode_handle(pact_map_address),
    ))

  // Sequence A's attach operations (attach + root set) to BOTH cores in order
  // so each side's `last_seen` advances identically: A acks its own, B attaches
  // the channel remotely.
  let core_b = bootstrap(id_b)
  let #(core_a, core_b, sequence_number) =
    list.fold(attach_out, #(core_a, core_b, 1), fn(acc, out) {
      let #(core_a, core_b, sequence_number) = acc
      let sequenced = sequenced_message(id_a, sequence_number + 1, out)
      let #(core_a, _) = ingest(core_a, sequenced)
      let #(core_b, _) = ingest(core_b, sequenced)
      #(core_a, core_b, sequence_number + 1)
    })

  // B proposes a value; this yields a Set operation on the wire.
  let #(_core_b, set_out) =
    expect_ok(runtime_core.pact_map_set(
      core_b,
      pact_map_address,
      "grade",
      json.string("2.1"),
    ))
  let assert [set_operation] = set_out

  // A ingests B's Set. Because A is in the quorum, it owes an Accept, which the
  // released-operations loop stamps and returns as outbound.
  let #(_core_a, ingested) =
    ingest(core_a, sequenced_message(id_b, sequence_number + 1, set_operation))
  let assert [accept_out] = ingested.outbound
  let encoded = json.to_string(accept_out.contents)
  encoded
  |> string.contains("\"type\":\"pactMapAccept\"")
  |> expect.to_be_true()
  encoded |> string.contains("\"key\":\"grade\"") |> expect.to_be_true()
}
